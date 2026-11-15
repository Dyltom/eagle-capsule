"""Host sync client: HELLO -> AUTH -> SET_TIME -> LIST -> (FETCH, verify, decrypt, store, ACK)*."""
from __future__ import annotations

import hashlib
import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey

from . import audio
from .chunkfile import CODEC_NAMES, ChunkError, ChunkMeta, auth_mac, key_fingerprint, open_chunk, raw_public
from .files import DirLock, make_private_dirs, open_private, write_file
from .protocol import PROTO_VERSION, Disconnected, ProtocolError, T, pack, unpack
from .store import Index, write_rollup
from .transcribe import StubTranscriber

MAX_CHUNK_BYTES = 8 << 20          # device chunks fit a 256 KiB slot (~186 KB at 24 kbps); the simulator's PCM fallback is ~1.9 MB
LIST_PAGE = 64
MAX_LIST_ITEMS = 1 << 20
SAMPLE_RATES = {8000, 12000, 16000, 24000, 32000, 44100, 48000}
FRAME_MS = {10, 20, 40, 60}

log = logging.getLogger(__name__)


class DeviceError(Exception):
    pass


class KeyMismatch(DeviceError):
    """The device encrypts to a different host key than ours."""


class InsecureLink(Exception):
    """The transport does not declare `secure_link`, so AUTH and ACK must not be sent over it."""


class ChunkRejected(Exception):
    """The chunk decrypted but must not be archived (wrong device, bad metadata, too large)."""


class FetchFailed(Exception):
    """FETCH stopped making progress."""


@dataclass
class SyncReport:
    device_id: str = ""
    boot_id: int = 0
    imported: list[int] = field(default_factory=list)
    reacked: list[int] = field(default_factory=list)       # already stored here, previous ACK was lost
    refetched: list[int] = field(default_factory=list)     # indexed, but the archive file was missing/damaged
    hash_failed: list[int] = field(default_factory=list)
    decrypt_failed: list[int] = field(default_factory=list)
    failed: dict[int, str] = field(default_factory=dict)   # seq -> reason; not ACKed, retried next sync
    eph_reused: list[int] = field(default_factory=list)    # stored, but the device repeated an ephemeral key
    errors: list[str] = field(default_factory=list)        # session-level problems that did not stop the sync
    resumed_bytes: int = 0
    dropped_on_device: int = 0
    interrupted: bool = False
    days: list[str] = field(default_factory=list)


def _sha256_file(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


class SyncClient:
    def __init__(self, transport, host_key: X25519PrivateKey, data_dir: Path, *, transcriber=None,
                 now_ms=lambda: int(time.time() * 1000), tz=None, window: int = 16 * 1024,
                 allow_insecure: bool = False, max_chunk_bytes: int = MAX_CHUNK_BYTES, retries: int = 5) -> None:
        self.t, self.key, self.now_ms, self.tz, self.window = transport, host_key, now_ms, tz, window
        self.allow_insecure, self.max_chunk_bytes, self.retries = allow_insecure, max_chunk_bytes, retries
        self.data_dir = Path(data_dir)
        self.partial_dir = self.data_dir / ".partial"
        make_private_dirs(self.partial_dir)
        self.index = Index(self.data_dir / "index.sqlite")
        self.transcriber = transcriber or StubTranscriber()

    # ------------------------------------------------------------ request helpers
    def _call(self, frame: bytes, *expect: T) -> tuple[T, tuple, bytes]:
        self.t.send(frame)
        t, f, payload = unpack(self.t.recv())
        if t == T.ERR:
            raise DeviceError(f"device error {f[0]} (seq {f[1]})")
        if t not in expect:
            raise ProtocolError(f"unexpected {t.name}")
        return t, f, payload

    def _handshake(self, report: SyncReport) -> None:
        if not getattr(self.t, "secure_link", False) and not self.allow_insecure:
            raise InsecureLink("refusing to AUTH/ACK over a link that is not a bonded LESC BLE link or the "
                               "wired dock (see SYNC-PROTOCOL.md section 8)")
        _, info, _ = self._call(pack(T.HELLO, PROTO_VERSION, self.t.max_frame), T.INFO)
        (_, dev_id, boot_id, _mono, _utc, key_fp, _oldest, _next, dropped, _mf, _free, challenge) = info
        self.device_id, report.device_id, report.boot_id = dev_id.hex(), dev_id.hex(), boot_id
        report.dropped_on_device = dropped
        if key_fp != key_fingerprint(raw_public(self.key)):
            raise KeyMismatch("device is provisioned with a different host public key")
        shared = self.key.exchange(X25519PublicKey.from_public_bytes(challenge))
        self._call(pack(T.AUTH, auth_mac(shared, challenge, dev_id, boot_id)), T.AUTH_OK)
        # Push UTC and record the (boot, mono) <-> UTC anchor. Midpoint of the round trip.
        sent = self.now_ms()
        _, (boot, mono, _), _ = self._call(pack(T.SET_TIME, sent), T.TIME_OK)
        self.index.add_anchor(self.device_id, boot, mono, (sent + self.now_ms()) // 2)

    def _list(self, report: SyncReport) -> list[tuple[int, int, bytes]]:
        items, start = [], 0
        while True:
            self.t.send(pack(T.LIST, start, LIST_PAGE))
            page = []
            while True:
                t, f, _ = unpack(self.t.recv())
                if t == T.LIST_END:
                    more = f[0]
                    break
                if t != T.LIST_ITEM:
                    raise ProtocolError(f"unexpected {t.name} in LIST")
                page.append(f)
                if len(page) > LIST_PAGE:
                    raise ProtocolError("LIST page longer than requested")
            for item in page:
                if item[0] < start or (items and item[0] <= items[-1][0]):
                    report.errors.append(f"LIST not strictly ascending at seq {item[0]}; listing stopped")
                    return items
                items.append(item)
            if not more or not page or items[-1][0] == 0xFFFFFFFF or len(items) >= MAX_LIST_ITEMS:
                return items
            start = items[-1][0] + 1

    def _drain(self) -> None:
        """Discard what is left of a broken FETCH window (up to its DATA_END, or a timeout)."""
        while True:
            try:
                if unpack(self.t.recv())[0] == T.DATA_END:
                    return
            except ProtocolError:
                continue
            except TimeoutError:
                return

    def _read_window(self, seq: int, have: int, end: int, out: int) -> int:
        """Append in-order DATA to `out` until DATA_END; return DATA_END's next_offset."""
        while True:
            t, f, payload = unpack(self.t.recv())
            if t == T.DATA:
                if f != (seq, have) or have + len(payload) > end:
                    raise ProtocolError(f"gap in chunk {seq}: got offset {f[1]}, expected {have}")
                os.write(out, payload)
                have += len(payload)
            elif t == T.DATA_END and f[0] == seq:
                return f[1]
            elif t == T.ERR:
                raise DeviceError(f"device error {f[0]} fetching {seq}")
            else:
                raise ProtocolError(f"unexpected {t.name} in FETCH")

    def _fetch(self, seq: int, size: int, report: SyncReport) -> bytes:
        part = self.partial_dir / f"{self.device_id}-{seq:08d}.part"
        if part.exists() and part.stat().st_size > size:
            part.unlink()
        out = open_private(part, os.O_WRONLY | os.O_CREAT | os.O_APPEND)
        try:
            have = os.fstat(out).st_size
            report.resumed_bytes += have
            stalls = 0
            while have < size:
                start, length = have, min(self.window, size - have)
                self.t.send(pack(T.FETCH, seq, have, length))
                err = None
                try:
                    next_offset = self._read_window(seq, have, start + length, out)
                except (ProtocolError, TimeoutError) as e:   # lost frame or lost DATA_END: re-FETCH from `have`
                    err = e
                    self._drain()
                have = os.fstat(out).st_size
                if err is None and next_offset == have < start + length:
                    raise FetchFailed(f"device ended chunk {seq} at {have} bytes; LIST said {size}")
                stalls = 0 if have > start else stalls + 1
                if stalls > self.retries:
                    if isinstance(err, TimeoutError):
                        raise err
                    raise FetchFailed(f"no progress at offset {have} of {size} after {stalls} attempts"
                                      + (f" ({err})" if err else ""))
        finally:
            os.close(out)
        blob = part.read_bytes()
        part.unlink()
        return blob

    def _ack(self, seq: int, sha: bytes) -> None:
        self._call(pack(T.ACK, seq, sha), T.ACK_OK)

    # ------------------------------------------------------------ import
    def _check_meta(self, m: ChunkMeta) -> str | None:
        if m.device_id.hex() != self.device_id:
            return f"chunk is from device {m.device_id.hex()}, session is {self.device_id}"
        if m.codec not in CODEC_NAMES:
            return f"unknown codec {m.codec}"
        if m.sample_rate not in SAMPLE_RATES:
            return f"unsupported sample rate {m.sample_rate}"
        if m.frame_ms not in FRAME_MS:
            return f"unsupported frame_ms {m.frame_ms}"
        if m.channels != 1:
            return f"unsupported channel count {m.channels}"
        return None

    def _import(self, blob: bytes, sha_hex: str, report: SyncReport) -> str:
        chunk = open_chunk(blob, self.key)
        m = chunk.meta
        problem = self._check_meta(m)
        if problem:
            raise ChunkRejected(problem)
        if self.index.eph_pub_seen(chunk.eph_pub.hex()):
            report.eph_reused.append(m.seq)
            log.warning("chunk %d repeats an ephemeral key: the device's TRNG or key handling is broken", m.seq)
        utc, source = self.index.resolve_utc(self.device_id, m.boot_id, m.start_mono_ms, m.start_utc_ms)
        if m.start_utc_ms and source != "device":
            log.warning("chunk %d: ignoring implausible device time %d", m.seq, m.start_utc_ms)
        tag = f"{m.boot_id:08x}_{m.seq:08d}_{sha_hex[:8]}"
        if utc is None:
            day, folder = "undated", Path("undated", self.device_id, f"boot-{m.boot_id:08x}")
            stem = f"mono{m.start_mono_ms:012d}_{tag}"
        else:
            dt = datetime.fromtimestamp(utc / 1000, self.tz)
            day, folder = dt.strftime("%Y-%m-%d"), Path(dt.strftime("%Y/%m/%d"), self.device_id)
            stem = f"{dt:%H%M%S}_{tag}"
        pcm = audio.frames_to_pcm(m.codec, chunk.frames, m.sample_rate, m.frame_ms)
        if pcm is not None:
            rel, data = folder / f"{stem}.wav", audio.wav_bytes(pcm, m.sample_rate)
        else:
            rel, data = folder / f"{stem}.{CODEC_NAMES[m.codec]}.frames", audio.frames_blob(chunk.frames)
        path = self.data_dir / rel
        write_file(path, data)                  # durable before it is indexed, and before the ACK
        try:
            status, text, lang = self.transcriber.transcribe(path)
        except Exception as e:  # transcription must never block the archive
            status, text, lang = "error", str(e), None
        row = dict(device_id=self.device_id, seq=m.seq, boot_id=m.boot_id, start_mono_ms=m.start_mono_ms,
                   start_utc_ms=utc, time_source=source, day=day, duration_ms=m.duration_ms,
                   codec=CODEC_NAMES[m.codec], sample_rate=m.sample_rate, bitrate=m.bitrate,
                   speech_ratio=sum(m.vad) / len(m.vad) if m.vad else 0.0,
                   vad_bits="".join("1" if v else "0" for v in m.vad), sha256=sha_hex,
                   file_sha256=hashlib.sha256(data).hexdigest(), eph_pub=chunk.eph_pub.hex(), path=rel.as_posix())
        self.index.add_chunk(row, (self.transcriber.name, status, text, lang))
        return day

    def _archived(self, seq: int, sha: bytes, report: SyncReport) -> bool:
        """True if this exact chunk is indexed and its archive file is intact (so a re-ACK is safe).
        A row whose file is missing or damaged is dropped and the file set aside, so it is fetched again."""
        row = self.index.find_chunk(self.device_id, sha.hex())
        if row is None:
            return False
        path = self.data_dir / row["path"]
        if _sha256_file(path) == row["file_sha256"]:
            return True
        log.warning("chunk %d: archive file %s is missing or damaged; fetching it again", seq, path)
        if path.exists():
            os.replace(path, path.with_name(f"{path.name}.damaged-{time.time_ns()}"))
        self.index.remove_chunk(row["id"])
        report.refetched.append(seq)
        return False

    def _sync_chunk(self, seq: int, size: int, sha: bytes, report: SyncReport, days: set[str]) -> None:
        if size > self.max_chunk_bytes:
            raise ChunkRejected(f"size {size} exceeds the {self.max_chunk_bytes} byte limit")
        if self._archived(seq, sha, report):    # stored on a previous run but the ACK never landed
            self._ack(seq, sha)
            report.reacked.append(seq)
            return
        blob = self._fetch(seq, size, report)
        if hashlib.sha256(blob).digest() != sha:
            report.hash_failed.append(seq)      # no ACK: the device keeps it, we retry next time
            return
        try:
            days.add(self._import(blob, sha.hex(), report))
        except ChunkError:
            report.decrypt_failed.append(seq)   # no ACK: never delete what we cannot read
            return
        self._ack(seq, sha)                     # only after the file and index row are durable
        report.imported.append(seq)

    # ------------------------------------------------------------ main entry
    def sync(self) -> SyncReport:
        report, days = SyncReport(), set()
        with DirLock(self.data_dir / ".lock"):
            try:
                self._handshake(report)
                for seq, size, sha in self._list(report):
                    try:
                        self._sync_chunk(seq, size, sha, report, days)
                    except (Disconnected, TimeoutError):
                        raise
                    except Exception as e:      # one bad chunk must not block the rest: no ACK, move on
                        report.failed[seq] = f"{type(e).__name__}: {e}"
                        log.warning("chunk %d not imported: %s", seq, report.failed[seq])
            except (Disconnected, TimeoutError):
                report.interrupted = True
            finally:
                for day in sorted(days):
                    try:
                        write_rollup(self.index, self.data_dir, day, self.tz)
                    except Exception as e:      # never mask the sync's own outcome
                        report.errors.append(f"rollup {day}: {type(e).__name__}: {e}")
                        log.exception("rollup for %s failed", day)
                report.days = sorted(days)
        return report

    def close(self) -> None:
        self.index.close()
