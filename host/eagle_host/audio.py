"""Synthetic audio and the "opus-or-raw" codec abstraction.

Opus is used when `opuslib` (and the libopus shared library) is available; otherwise
chunks carry raw 16-bit PCM. Everything downstream only sees `codec` + `frames`.
"""
from __future__ import annotations

import math
import random
import struct
import wave
from array import array
from pathlib import Path

from .chunkfile import CODEC_OPUS, CODEC_PCM_S16LE

try:  # optional
    import opuslib  # type: ignore
except Exception:  # ImportError, or OSError when libopus itself is missing
    opuslib = None

OPUS_BITRATE = 16000


def synth_pcm(seconds: int, rate: int, rng: random.Random) -> bytes:
    """Alternating "speech-like" (amplitude-modulated tones) and near-silent seconds."""
    out = array("h")
    for _ in range(seconds):
        speech = rng.random() < 0.5
        f1, f2 = rng.uniform(120, 250), rng.uniform(500, 1500)
        for n in range(rate):
            t = n / rate
            if speech:
                env = 0.5 + 0.5 * math.sin(2 * math.pi * 4 * t)
                v = env * (6000 * math.sin(2 * math.pi * f1 * t) + 3000 * math.sin(2 * math.pi * f2 * t))
            else:
                v = rng.uniform(-40, 40)
            out.append(int(v))
    return out.tobytes()


def energy_vad(pcm: bytes, rate: int, threshold: float = 500.0) -> list[bool]:
    """Per-second RMS gate, standing in for the firmware's cheap VAD (flags only, never gates)."""
    samples, flags = array("h", pcm), []
    for i in range(0, len(samples), rate):
        sec = samples[i:i + rate]
        flags.append(math.sqrt(sum(s * s for s in sec) / max(len(sec), 1)) > threshold)
    return flags


class PcmCodec:
    codec_id = CODEC_PCM_S16LE

    def __init__(self, rate: int, frame_ms: int) -> None:
        self.rate, self.frame_ms = rate, frame_ms
        self.bitrate = rate * 16
        self.frame_bytes = rate * frame_ms // 1000 * 2

    def encode(self, pcm: bytes) -> list[bytes]:
        return [pcm[i:i + self.frame_bytes] for i in range(0, len(pcm), self.frame_bytes)]


class OpusCodec:
    codec_id = CODEC_OPUS

    def __init__(self, rate: int, frame_ms: int) -> None:
        self.rate, self.frame_ms, self.bitrate = rate, frame_ms, OPUS_BITRATE
        self.samples = rate * frame_ms // 1000
        self.enc = opuslib.Encoder(rate, 1, opuslib.APPLICATION_VOIP)
        self.enc.bitrate = OPUS_BITRATE

    def encode(self, pcm: bytes) -> list[bytes]:
        step = self.samples * 2
        pcm += bytes(-len(pcm) % step)
        return [self.enc.encode(pcm[i:i + step], self.samples) for i in range(0, len(pcm), step)]


def make_codec(name: str, rate: int, frame_ms: int = 20):
    if name == "opus" or (name == "auto" and opuslib is not None):
        if opuslib is None:
            raise RuntimeError("opuslib not available")
        return OpusCodec(rate, frame_ms)
    return PcmCodec(rate, frame_ms)


def frames_to_pcm(codec: int, frames: list[bytes], rate: int, frame_ms: int) -> bytes | None:
    """Host side: return PCM for a chunk, or None if this codec cannot be decoded here."""
    if codec == CODEC_PCM_S16LE:
        return b"".join(frames)
    if codec == CODEC_OPUS and opuslib is not None:
        dec, n = opuslib.Decoder(rate, 1), rate * frame_ms // 1000
        return b"".join(dec.decode(f, n) for f in frames)
    return None


def write_wav(path: Path, pcm: bytes, rate: int) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)


def write_frames(path: Path, frames: list[bytes]) -> None:
    """Fallback when Opus can't be decoded on this host: length-prefixed packets."""
    path.write_bytes(b"".join(struct.pack("<H", len(f)) + f for f in frames))
