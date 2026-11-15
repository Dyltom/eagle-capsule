"""Host sync client: HELLO -> AUTH -> SET_TIME -> LIST -> (FETCH, verify, decrypt, store, ACK)*."""
from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey

from . import audio
from .chunkfile import CODEC_NAMES, ChunkError, auth_mac, key_fingerprint, open_chunk, raw_public
from .protocol import PROTO_VERSION, Disconnected, ProtocolError, T, pack, unpack
from .store import Index, write_rollup
from .transcribe import StubTranscriber


class DeviceError(Exception):
    pass


class KeyMismatch(DeviceError):
    """The device encrypts to a different host key than ours."""


@dataclass
class SyncReport:
    device_id: str = ""
    boot_id: int = 0
    imported: list[int] = field(default_factory=list)
    reacked: list[int] = field(default_factory=list)       # already stored here, previous ACK was lost
    hash_failed: list[int] = field(default_factory=list)
    decrypt_failed: list[int] = field(default_factory=list)
    resumed_bytes: int = 0
    dropped_on_device: int = 0
    interrupted: bool = False
    days: list[str] = field(default_factory=list)


class SyncClient:
    def __init__(self, transport, host_key: X25519PrivateKey, data_dir: Path, *, transcriber=None,
                 now_ms=lambda: int(time.time() * 1000), tz=None, window: int = 16 * 1024) -> None:
        self.t, self.key, self.now_ms, self.tz, self.window = transport, host_key, now_ms, tz, window
        self.data_dir = Path(data_dir)
        self.partial_dir = self.data_dir / ".partial"
        self.partial_dir.mkdir(parents=True, exist_ok=True)
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

    def _list(self) -> list[tuple[int, int, bytes]]:
        items, start = [], 0
        while True:
            self.t.send(pack(T.LIST, start, 64))
            while True:
                t, f, _ = unpack(self.t.recv())
                if t == T.LIST_ITEM:
                    items.append(f)
                elif t == T.LIST_END:
                    break
                else:
                    raise ProtocolError(f"unexpected {t.name} in LIST")
            if not f[0] or not items:
                return items
            start = items[-1][0] + 1

    def _fetch(self, seq: int, size: int, report: SyncReport) -> bytes:
        part = self.partial_dir / f"{self.device_id}-{seq:08d}.part"
        have = part.stat().st_size if part.exists() else 0
        if have > size:
            part.unlink()
            have = 0
        report.resumed_bytes += have
        with open(part, "ab") as out:
            while have < size:
                self.t.send(pack(T.FETCH, seq, have, min(self.window, size - have)))
                while True:
                    t, f, payload = unpack(self.t.recv())
                    if t == T.DATA:
                        if f != (seq, have):
                            raise ProtocolError(f"gap in chunk {seq}: got offset {f[1]}, expected {have}")
                        out.write(payload)
                        out.flush()
                        have += len(payload)
                    elif t == T.DATA_END:
                        break
                    elif t == T.ERR:
                        raise DeviceError(f"device error {f[0]} fetching {seq}")
                    else:
                        raise ProtocolError(f"unexpected {t.name} in FETCH")
        blob = part.read_bytes()
        part.unlink()
        return blob

    def _ack(self, seq: int, sha: bytes) -> None:
        self._call(pack(T.ACK, seq, sha), T.ACK_OK)

    # ------------------------------------------------------------ import
    def _import(self, blob: bytes, sha_hex: str) -> str:
        chunk = open_chunk(blob, self.key)
        m = chunk.meta
        utc, source = self.index.resolve_utc(self.device_id, m.boot_id, m.start_mono_ms, m.start_utc_ms)
        if utc is None:
            day, folder = "undated", self.data_dir / "undated" / f"boot-{m.boot_id:08x}"
            stem = f"mono{m.start_mono_ms:012d}_{m.seq:08d}"
        else:
            dt = datetime.fromtimestamp(utc / 1000, self.tz)
            day, folder = dt.strftime("%Y-%m-%d"), self.data_dir / dt.strftime("%Y/%m/%d")
            stem = f"{dt:%H%M%S}_{m.seq:08d}"
        folder.mkdir(parents=True, exist_ok=True)
        pcm = audio.frames_to_pcm(m.codec, chunk.frames, m.sample_rate, m.frame_ms)
        if pcm is not None:
            path = folder / f"{stem}.wav"
            audio.write_wav(path, pcm, m.sample_rate)
        else:
            path = folder / f"{stem}.{CODEC_NAMES.get(m.codec, 'bin')}.frames"
            audio.write_frames(path, chunk.frames)
        try:
            status, text, lang = self.transcriber.transcribe(path)
        except Exception as e:  # transcription must never block the archive
            status, text, lang = "error", str(e), None
        row = dict(device_id=self.device_id, seq=m.seq, boot_id=m.boot_id, start_mono_ms=m.start_mono_ms,
                   start_utc_ms=utc, time_source=source, day=day, duration_ms=m.duration_ms,
                   codec=CODEC_NAMES.get(m.codec, str(m.codec)), sample_rate=m.sample_rate, bitrate=m.bitrate,
                   speech_ratio=sum(m.vad) / len(m.vad) if m.vad else 0.0,
                   vad_bits="".join("1" if v else "0" for v in m.vad), sha256=sha_hex,
                   path=path.relative_to(self.data_dir).as_posix())
        self.index.add_chunk(row, (self.transcriber.name, status, text, lang))
        return day

    # ------------------------------------------------------------ main entry
    def sync(self) -> SyncReport:
        report, days = SyncReport(), set()
        try:
            self._handshake(report)
            for seq, size, sha in self._list():
                known = self.index.chunk_sha(self.device_id, seq)
                if known == sha.hex():          # stored on a previous run but the ACK never landed
                    self._ack(seq, sha)
                    report.reacked.append(seq)
                    continue
                blob = self._fetch(seq, size, report)
                if hashlib.sha256(blob).digest() != sha:
                    report.hash_failed.append(seq)   # no ACK: the device keeps it, we retry next time
                    continue
                try:
                    days.add(self._import(blob, sha.hex()))
                except ChunkError:
                    report.decrypt_failed.append(seq)   # no ACK: never delete what we cannot read
                    continue
                self._ack(seq, sha)                     # only after the file and index row are durable
                report.imported.append(seq)
        except (Disconnected, TimeoutError):
            report.interrupted = True
        finally:
            for day in sorted(days):
                write_rollup(self.index, self.data_dir, day, self.tz)
            report.days = sorted(days)
        return report

    def close(self) -> None:
        self.index.close()
