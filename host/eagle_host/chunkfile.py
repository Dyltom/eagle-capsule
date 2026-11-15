"""Chunk file format and encryption (docs/SYNC-PROTOCOL.md sections 3 and 6).

On-card file = OUTER header (clear, used as AES-GCM AAD) + AES-256-GCM(plaintext) + 16-byte tag.
Plaintext   = INNER header + frames (u16 len + bytes, terminated by len 0) + TRAILER + VAD bitmap.

The device only ever holds the host's X25519 *public* key, so it can write chunks
but cannot read them back.
"""
from __future__ import annotations

import hashlib
import hmac
import struct
from dataclasses import dataclass, field

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

MAGIC = b"ECAP"
FORMAT_VERSION = 1
ALG_X25519_HKDF_SHA256_AES256GCM = 1

OUTER = struct.Struct("<4sBBHI8s32s")      # magic, ver, alg, reserved, seq, key_fp, eph_pub   (52 B)
INNER = struct.Struct("<8sIIQQIIBBBB")     # device_id, boot_id, seq, start_mono_ms, start_utc_ms,
                                           # sample_rate, bitrate, codec, frame_ms, channels, flags (44 B)
TRAILER = struct.Struct("<IIH")            # frame_count, duration_ms, vad_seconds (+ ceil(n/8) bitmap bytes)
FRAME_LEN = struct.Struct("<H")
TAG_LEN = 16

CODEC_PCM_S16LE = 0
CODEC_OPUS = 1
CODEC_NAMES = {CODEC_PCM_S16LE: "pcm_s16le", CODEC_OPUS: "opus"}
FLAG_UTC_VALID = 0x01

CHUNK_INFO = b"eagle-capsule/v1/chunk"
AUTH_INFO = b"eagle-capsule/v1/auth"


class ChunkError(Exception):
    """File is malformed, was encrypted to a different key, or failed authentication."""


@dataclass
class ChunkMeta:
    device_id: bytes
    boot_id: int
    seq: int
    start_mono_ms: int
    start_utc_ms: int            # 0 = device did not know UTC when the chunk started
    sample_rate: int
    bitrate: int                 # 0 for raw PCM
    codec: int
    frame_ms: int
    channels: int = 1
    duration_ms: int = 0
    vad: list[bool] = field(default_factory=list)   # one flag per second, informational only


@dataclass
class Chunk:
    meta: ChunkMeta
    frames: list[bytes]
    eph_pub: bytes = b""


# ---------------------------------------------------------------- keys

def raw_public(key: X25519PrivateKey | X25519PublicKey) -> bytes:
    pub = key.public_key() if isinstance(key, X25519PrivateKey) else key
    return pub.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def key_fingerprint(host_pub: bytes) -> bytes:
    return hashlib.sha256(host_pub).digest()[:8]


def _hkdf(shared: bytes, salt: bytes, info: bytes, length: int) -> bytes:
    if shared == bytes(32):
        raise ChunkError("low-order X25519 point")
    return HKDF(algorithm=hashes.SHA256(), length=length, salt=salt, info=info).derive(shared)


def auth_mac(shared: bytes, challenge: bytes, device_id: bytes, boot_id: int) -> bytes:
    """Proof that the host holds the private key the device encrypts to (protocol AUTH)."""
    key = _hkdf(shared, challenge, AUTH_INFO, 32)
    return hmac.new(key, challenge + device_id + struct.pack("<I", boot_id), hashlib.sha256).digest()


# ---------------------------------------------------------------- plaintext

def encode_plaintext(meta: ChunkMeta, frames: list[bytes]) -> bytes:
    flags = FLAG_UTC_VALID if meta.start_utc_ms else 0
    out = [INNER.pack(meta.device_id, meta.boot_id, meta.seq, meta.start_mono_ms, meta.start_utc_ms,
                      meta.sample_rate, meta.bitrate, meta.codec, meta.frame_ms, meta.channels, flags)]
    for f in frames:
        if not 0 < len(f) < 0xFFFF:
            raise ValueError("frame length out of range")
        out += [FRAME_LEN.pack(len(f)), f]
    out.append(FRAME_LEN.pack(0))
    bitmap = bytearray((len(meta.vad) + 7) // 8)
    for i, v in enumerate(meta.vad):
        if v:
            bitmap[i // 8] |= 1 << (i % 8)
    out += [TRAILER.pack(len(frames), meta.duration_ms, len(meta.vad)), bytes(bitmap)]
    return b"".join(out)


def decode_plaintext(buf: bytes) -> Chunk:
    try:
        (dev, boot, seq, mono, utc, rate, br, codec, fms, ch, flags) = INNER.unpack_from(buf, 0)
        pos, frames = INNER.size, []
        while True:
            (n,) = FRAME_LEN.unpack_from(buf, pos)
            pos += FRAME_LEN.size
            if n == 0:
                break
            frames.append(buf[pos:pos + n])
            pos += n
        count, duration, nvad = TRAILER.unpack_from(buf, pos)
        bitmap = buf[pos + TRAILER.size:]
    except struct.error as e:
        raise ChunkError(f"truncated plaintext: {e}") from None
    if count != len(frames) or len(bitmap) != (nvad + 7) // 8:
        raise ChunkError("trailer does not match body")
    vad = [bool(bitmap[i // 8] >> (i % 8) & 1) for i in range(nvad)]
    meta = ChunkMeta(dev, boot, seq, mono, utc if flags & FLAG_UTC_VALID else 0,
                     rate, br, codec, fms, ch, duration, vad)
    return Chunk(meta, frames)


# ---------------------------------------------------------------- seal / open

def seal(meta: ChunkMeta, frames: list[bytes], host_pub: bytes, eph: X25519PrivateKey | None = None) -> bytes:
    """Device side. One-shot here; firmware does the same thing streaming (GCM is incremental).

    `eph` exists only so tests can simulate a broken TRNG (ephemeral key reuse)."""
    eph = eph or X25519PrivateKey.generate()
    eph_pub = raw_public(eph)
    key_nonce = _hkdf(eph.exchange(X25519PublicKey.from_public_bytes(host_pub)),
                      eph_pub + host_pub, CHUNK_INFO, 44)
    header = OUTER.pack(MAGIC, FORMAT_VERSION, ALG_X25519_HKDF_SHA256_AES256GCM, 0,
                        meta.seq, key_fingerprint(host_pub), eph_pub)
    return header + AESGCM(key_nonce[:32]).encrypt(key_nonce[32:], encode_plaintext(meta, frames), header)


def outer_seq(blob: bytes) -> int:
    return OUTER.unpack_from(blob, 0)[4]


def open_chunk(blob: bytes, host_key: X25519PrivateKey) -> Chunk:
    """Host side. Raises ChunkError unless `host_key` is the key the chunk was sealed to."""
    if len(blob) < OUTER.size + TAG_LEN:
        raise ChunkError("file too short")
    magic, ver, alg, _, seq, fp, eph_pub = OUTER.unpack_from(blob, 0)
    if magic != MAGIC or ver != FORMAT_VERSION or alg != ALG_X25519_HKDF_SHA256_AES256GCM:
        raise ChunkError("unknown chunk format")
    host_pub = raw_public(host_key)
    if fp != key_fingerprint(host_pub):
        raise ChunkError("chunk was encrypted to a different host key")
    key_nonce = _hkdf(host_key.exchange(X25519PublicKey.from_public_bytes(eph_pub)),
                      eph_pub + host_pub, CHUNK_INFO, 44)
    header = blob[:OUTER.size]
    try:
        plain = AESGCM(key_nonce[:32]).decrypt(key_nonce[32:], blob[OUTER.size:], header)
    except InvalidTag:
        raise ChunkError("authentication failed (corrupt or wrong key)") from None
    chunk = decode_plaintext(plain)
    if chunk.meta.seq != seq:
        raise ChunkError("inner/outer sequence mismatch")
    chunk.eph_pub = eph_pub
    return chunk
