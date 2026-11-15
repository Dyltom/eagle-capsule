"""A fake Eagle Capsule: records synthetic chunks into an encrypted ring buffer and
answers the sync protocol exactly as the firmware should.

Time is virtual: `advance(ms)` moves both the device's monotonic clock and the
simulated "true" wall clock, so tests can check timestamp reconstruction exactly.
"""
from __future__ import annotations

import hashlib
import hmac
import random
import time
from collections import OrderedDict

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey

from . import audio
from .chunkfile import ChunkMeta, auth_mac, key_fingerprint, raw_public, seal
from .protocol import DATA_OVERHEAD, MIN_FRAME, PROTO_VERSION, E, T, pack, unpack

DEVICE_MAX_FRAME = 1024        # firmware TX buffer; BLE further limits it to ATT_MTU - 3


class FakeDevice:
    def __init__(self, host_pub: bytes, *, device_id: bytes = b"EAGLE001", true_utc_ms: int | None = None,
                 clock_known: bool = True, chunk_seconds: int = 60, sample_rate: int = 16000,
                 codec: str = "auto", capacity_bytes: int = 64 << 20, seed: int = 1) -> None:
        self.host_pub, self.device_id = host_pub, device_id
        # Simulation truth (defaults to the real clock). The device itself cannot see this.
        self.true_utc_ms = int(time.time() * 1000) if true_utc_ms is None else true_utc_ms
        self.chunk_seconds, self.sample_rate = chunk_seconds, sample_rate
        self.codec = audio.make_codec(codec, sample_rate)
        self.capacity = capacity_bytes
        self.rng = random.Random(seed)
        self.store: OrderedDict[int, tuple[bytes, bytes]] = OrderedDict()   # seq -> (file, sha256)
        self.next_seq, self.dropped = 1, 0
        self.fetch_log: list[tuple[int, int, int]] = []
        self.boot_id = 0
        self.reboot(lose_clock=not clock_known)

    # ------------------------------------------------------------ device life
    def reboot(self, lose_clock: bool = True) -> None:
        self.boot_id = self.rng.getrandbits(32)          # firmware: TRNG at boot
        self.mono_ms = 0
        self.utc_offset = None if lose_clock else self.true_utc_ms   # offset = UTC at mono 0
        self.connect()

    def advance(self, ms: int) -> None:
        self.mono_ms += ms
        self.true_utc_ms += ms

    def utc_now(self) -> int:
        return 0 if self.utc_offset is None else self.utc_offset + self.mono_ms

    def record(self, n_chunks: int = 1) -> list[int]:
        seqs = []
        for _ in range(n_chunks):
            pcm = audio.synth_pcm(self.chunk_seconds, self.sample_rate, self.rng)
            meta = ChunkMeta(self.device_id, self.boot_id, self.next_seq, self.mono_ms, self.utc_now(),
                             self.sample_rate, self.codec.bitrate, self.codec.codec_id, self.codec.frame_ms,
                             duration_ms=self.chunk_seconds * 1000,
                             vad=audio.energy_vad(pcm, self.sample_rate))
            blob = seal(meta, self.codec.encode(pcm), self.host_pub)
            self._put(self.next_seq, blob)
            seqs.append(self.next_seq)
            self.next_seq += 1
            self.advance(self.chunk_seconds * 1000)
        return seqs

    def _put(self, seq: int, blob: bytes) -> None:
        while self.store and self.used() + len(blob) > self.capacity:
            self.store.popitem(last=False)                 # ring buffer: overwrite oldest
            self.dropped += 1
        self.store[seq] = (blob, hashlib.sha256(blob).digest())   # firmware: hash while writing

    def used(self) -> int:
        return sum(len(b) for b, _ in self.store.values())

    # ------------------------------------------------------------ protocol
    def connect(self) -> None:
        """New link: fresh challenge, not authenticated."""
        self.authed, self.max_frame = False, MIN_FRAME
        self._challenge_key = X25519PrivateKey.generate()

    def handle(self, frame: bytes) -> list[bytes]:
        try:
            t, f, _ = unpack(frame)
        except Exception:
            return [pack(T.ERR, E.BAD_REQUEST, 0)]
        if t == T.HELLO:
            return self._hello(*f)
        if t == T.AUTH:
            return self._auth(*f)
        if not self.authed:
            return [pack(T.ERR, E.NOT_AUTHENTICATED, 0)]
        if t == T.SET_TIME:
            self.utc_offset = f[0] - self.mono_ms
            return [pack(T.TIME_OK, self.boot_id, self.mono_ms, self.utc_now())]
        if t == T.LIST:
            return self._list(*f)
        if t == T.FETCH:
            return self._fetch(*f)
        if t == T.ACK:
            return self._ack(*f)
        return [pack(T.ERR, E.BAD_REQUEST, 0)]

    def _hello(self, version: int, max_frame: int) -> list[bytes]:
        if version != PROTO_VERSION:
            return [pack(T.ERR, E.VERSION, 0)]
        self.connect()
        self.max_frame = max(MIN_FRAME, min(max_frame, DEVICE_MAX_FRAME))
        oldest = next(iter(self.store), self.next_seq)
        free_kb = (self.capacity - self.used()) // 1024
        return [pack(T.INFO, PROTO_VERSION, self.device_id, self.boot_id, self.mono_ms, self.utc_now(),
                     key_fingerprint(self.host_pub), oldest, self.next_seq, self.dropped, self.max_frame,
                     free_kb, raw_public(self._challenge_key))]

    def _auth(self, mac: bytes) -> list[bytes]:
        shared = self._challenge_key.exchange(X25519PublicKey.from_public_bytes(self.host_pub))
        expected = auth_mac(shared, raw_public(self._challenge_key), self.device_id, self.boot_id)
        self.authed = hmac.compare_digest(mac, expected)
        return [pack(T.AUTH_OK)] if self.authed else [pack(T.ERR, E.AUTH_FAILED, 0)]

    def _list(self, from_seq: int, max_items: int) -> list[bytes]:
        seqs = [s for s in self.store if s >= from_seq]
        out = [pack(T.LIST_ITEM, s, len(self.store[s][0]), self.store[s][1]) for s in seqs[:max_items]]
        return out + [pack(T.LIST_END, int(len(seqs) > max_items))]

    def _fetch(self, seq: int, offset: int, length: int) -> list[bytes]:
        if seq not in self.store:
            return [pack(T.ERR, E.UNKNOWN_CHUNK, seq)]
        self.fetch_log.append((seq, offset, length))
        blob = self.store[seq][0]
        end = min(len(blob), offset + length) if length else len(blob)
        step, out = self.max_frame - DATA_OVERHEAD, []
        for off in range(offset, end, step):
            out.append(pack(T.DATA, seq, off, payload=blob[off:min(off + step, end)]))
        return out + [pack(T.DATA_END, seq, max(end, offset))]

    def _ack(self, seq: int, sha: bytes) -> list[bytes]:
        if seq not in self.store:          # already deleted (lost ACK_OK) or overwritten: idempotent
            return [pack(T.ACK_OK, seq)]
        if not hmac.compare_digest(sha, self.store[seq][1]):
            return [pack(T.ERR, E.HASH_MISMATCH, seq)]
        del self.store[seq]                # firmware: unlink file, then update index
        return [pack(T.ACK_OK, seq)]


def new_host_key() -> X25519PrivateKey:
    return X25519PrivateKey.generate()

