"""Run a simulated night: the fake pendant records, then syncs to a local data dir.

    python -m eagle_host.demo --out demo-out --chunks 5 --chunk-seconds 10 [--uart] [--lost-clock] [--flaky]
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from .chunkfile import raw_public
from .client import SyncClient
from .protocol import LoopbackTransport
from .simulator import FakeDevice
from .transcribe import StubTranscriber, default_transcriber


def load_or_create_key(path: Path) -> X25519PrivateKey:
    """Demo only: an unencrypted PEM. On a real host protect it (passphrase, DPAPI, keyring)."""
    if path.exists():
        return serialization.load_pem_private_key(path.read_bytes(), password=None)
    key = X25519PrivateKey.generate()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                       serialization.NoEncryption()))
    path.with_suffix(".pub").write_bytes(raw_public(key))   # this 32-byte file is what gets flashed
    return key


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=Path("demo-out"))
    ap.add_argument("--chunks", type=int, default=5)
    ap.add_argument("--chunk-seconds", type=int, default=10)
    ap.add_argument("--rate", type=int, default=16000)
    ap.add_argument("--codec", choices=["auto", "pcm", "opus"], default="auto")
    ap.add_argument("--uart", action="store_true", help="byte-stream UART framing instead of BLE GATT frames")
    ap.add_argument("--lost-clock", action="store_true", help="device boots without knowing UTC")
    ap.add_argument("--flaky", action="store_true", help="drop the link mid-transfer, then reconnect")
    ap.add_argument("--whisper", action="store_true", help="use faster-whisper if installed")
    a = ap.parse_args()

    key = load_or_create_key(a.out / "host_key.pem")
    started = int(time.time() * 1000) - (a.chunks * a.chunk_seconds + 30) * 1000   # so the sync ends "now"
    dev = FakeDevice(raw_public(key), chunk_seconds=a.chunk_seconds, sample_rate=a.rate, codec=a.codec,
                     clock_known=not a.lost_clock, true_utc_ms=started)
    print(f"device {dev.device_id.hex()} boot {dev.boot_id:08x}: recording {a.chunks} x {a.chunk_seconds}s "
          f"({type(dev.codec).__name__})")
    dev.record(a.chunks)
    dev.advance(30_000)

    mode = "uart" if a.uart else "ble"
    transcriber = default_transcriber() if a.whisper else StubTranscriber()
    for attempt in range(1, 4):
        link = LoopbackTransport(dev, mode, drop_after_data=150 if a.flaky and attempt == 1 else None)
        client = SyncClient(link, key, a.out / "data", transcriber=transcriber, now_ms=lambda: dev.true_utc_ms)
        r = client.sync()
        client.close()
        print(f"sync #{attempt} over {mode}: imported {r.imported}, resumed {r.resumed_bytes} B, "
              f"hash_failed {r.hash_failed}, decrypt_failed {r.decrypt_failed}, interrupted {r.interrupted}")
        if not r.interrupted:
            break
    for day in r.days:
        folder = a.out / "data" / ("undated" if day == "undated" else day.replace("-", "/"))
        print(f"rollup: {folder / (day + '.md')}")
    print(f"index:  {a.out / 'data' / 'index.sqlite'}   chunks left on device: {len(dev.store)}")


if __name__ == "__main__":
    main()
