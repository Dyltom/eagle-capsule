"""Run a simulated night: the fake pendant records, then syncs to a local data dir.

    python -m eagle_host.demo --out demo-out --chunks 5 --chunk-seconds 10 [--uart] [--lost-clock] [--flaky]
"""
from __future__ import annotations

import argparse
import logging
import os
import time
from pathlib import Path

from .chunkfile import raw_public
from .client import SyncClient
from .keys import PASSPHRASE_ENV, load_or_create_key
from .protocol import LoopbackTransport
from .simulator import FakeDevice
from .transcribe import StubTranscriber, default_transcriber

__all__ = ["load_or_create_key", "main"]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=Path("demo-out"))
    ap.add_argument("--chunks", type=int, default=5)
    ap.add_argument("--chunk-seconds", type=int, default=10)
    ap.add_argument("--rate", type=int, default=16000)
    ap.add_argument("--codec", choices=["auto", "pcm", "opus"], default="auto")
    ap.add_argument("--uart", action="store_true", help="byte-stream serial framing (USB CDC, or a UART) instead of BLE GATT frames")
    ap.add_argument("--lost-clock", action="store_true", help="device boots without knowing UTC")
    ap.add_argument("--flaky", action="store_true", help="drop the link mid-transfer, then reconnect")
    ap.add_argument("--whisper", action="store_true", help="use faster-whisper if installed")
    a = ap.parse_args()

    os.umask(0o077)
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    if not os.environ.get(PASSPHRASE_ENV) and not (a.out / "host_key.pem").exists():
        print(f"note: ${PASSPHRASE_ENV} is not set, so host_key.pem is stored unencrypted (still owner-only)")
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
              f"hash_failed {r.hash_failed}, decrypt_failed {r.decrypt_failed}, failed {r.failed}, "
              f"interrupted {r.interrupted}")
        if not r.interrupted:
            break
    for day in r.days:
        folder = a.out / "data" / ("undated" if day == "undated" else day.replace("-", "/"))
        print(f"rollup: {folder / (day + '.md')}")
    print(f"index:  {a.out / 'data' / 'index.sqlite'}   chunks left on device: {len(dev.store)}")


if __name__ == "__main__":
    main()
