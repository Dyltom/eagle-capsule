"""End-to-end tests: simulated device <-> loopback transport <-> sync client.

Run from host/:  python -m unittest -v      (or: python -m pytest -q)
"""
from __future__ import annotations

import hashlib
import sqlite3
import sys
import tempfile
import unittest
import wave
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from eagle_host.chunkfile import ChunkError, open_chunk, raw_public  # noqa: E402
from eagle_host.client import KeyMismatch, SyncClient, SyncReport  # noqa: E402
from eagle_host.protocol import E, T, LoopbackTransport, UartDecoder, pack, uart_encode, unpack  # noqa: E402
from eagle_host.simulator import FakeDevice, new_host_key  # noqa: E402

CHUNK_S, RATE = 2, 8000          # small chunks keep the tests fast (~32 KB each as raw PCM)


class WordsTranscriber:
    name = "test-words"

    def transcribe(self, path):
        return "done", f"the eagle has landed {path.stem}", "en"


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.data = Path(self.tmp.name) / "data"
        self.key = new_host_key()
        self.dev = self.make_device()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def make_device(self, **kw) -> FakeDevice:
        kw.setdefault("clock_known", True)
        return FakeDevice(raw_public(self.key), chunk_seconds=CHUNK_S, sample_rate=RATE, codec="pcm", **kw)

    def client(self, transport, key=None, **kw) -> SyncClient:
        c = SyncClient(transport, key or self.key, self.data, now_ms=lambda: self.dev.true_utc_ms,
                       tz=timezone.utc, **kw)
        self.addCleanup(c.close)
        return c

    def db(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.data / "index.sqlite")
        conn.row_factory = sqlite3.Row
        self.addCleanup(conn.close)
        return conn


class NormalSync(Base):
    def _sync_and_check(self, mode: str) -> None:
        t0 = self.dev.true_utc_ms
        self.dev.record(3)
        self.dev.advance(5000)
        report = self.client(LoopbackTransport(self.dev, mode), transcriber=WordsTranscriber()).sync()

        self.assertEqual(report.imported, [1, 2, 3])
        self.assertFalse(report.interrupted or report.hash_failed or report.decrypt_failed)
        self.assertEqual(len(self.dev.store), 0, "device deletes only after ACK, and all were ACKed")

        rows = self.db().execute("SELECT * FROM chunks ORDER BY seq").fetchall()
        self.assertEqual([r["seq"] for r in rows], [1, 2, 3])
        for i, r in enumerate(rows):
            self.assertEqual(r["time_source"], "device")
            self.assertEqual(r["start_utc_ms"], t0 + i * CHUNK_S * 1000)
            day = datetime.fromtimestamp(r["start_utc_ms"] / 1000, timezone.utc)
            self.assertTrue(r["path"].startswith(day.strftime("%Y/%m/%d/") + self.dev.device_id.hex() + "/"),
                            r["path"])
            with wave.open(str(self.data / r["path"])) as w:
                self.assertEqual(w.getnframes(), CHUNK_S * RATE)
            self.assertEqual(len(r["vad_bits"]), CHUNK_S)

        hits = self.db().execute("SELECT rowid FROM transcripts_fts WHERE transcripts_fts MATCH 'eagle'").fetchall()
        self.assertEqual(len(hits), 3)
        rollup = self.data / rows[0]["day"].replace("-", "/") / f"{rows[0]['day']}.md"
        self.assertIn("3 chunks", rollup.read_text())

    def test_ble(self) -> None:
        self._sync_and_check("ble")

    def test_uart(self) -> None:
        self._sync_and_check("uart")

    def test_stub_transcriber_marks_untranscribed(self) -> None:
        self.dev.record(1)
        self.client(LoopbackTransport(self.dev)).sync()
        status = self.db().execute("SELECT status FROM transcripts").fetchone()[0]
        self.assertEqual(status, "untranscribed")

    def test_ring_buffer_reports_overwrites(self) -> None:
        self.dev = self.make_device(capacity_bytes=100_000)     # room for ~3 chunks
        self.dev.record(5)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.dropped_on_device, 2)
        self.assertEqual(report.imported, [3, 4, 5])


class DisconnectResume(Base):
    def _run(self, mode: str) -> None:
        self.dev.record(2)
        drop_after = 24_000 // (235 if mode == "ble" else 1015)    # die ~24 KB into chunk 1
        first = self.client(LoopbackTransport(self.dev, mode, drop_after_data=drop_after)).sync()
        self.assertTrue(first.interrupted)
        self.assertEqual(first.imported, [])
        self.assertEqual(len(self.dev.store), 2, "nothing deleted while the transfer was incomplete")
        self.assertTrue(any((self.data / ".partial").iterdir()), "partial file kept for resume")

        self.dev.fetch_log.clear()
        second = self.client(LoopbackTransport(self.dev, mode)).sync()
        self.assertEqual(second.imported, [1, 2])
        self.assertGreater(second.resumed_bytes, 0)
        self.assertGreater(self.dev.fetch_log[0][1], 0, "first FETCH after reconnect starts mid-file")
        self.assertEqual(len(self.dev.store), 0)
        self.assertFalse(any((self.data / ".partial").iterdir()))

    def test_ble(self) -> None:
        self._run("ble")

    def test_uart(self) -> None:
        self._run("uart")


class HashMismatch(Base):
    def test_corrupt_transfer_is_not_acked(self) -> None:
        self.dev.record(2)
        report = self.client(LoopbackTransport(self.dev, corrupt_data=5)).sync()
        self.assertEqual(report.hash_failed, [1])
        self.assertEqual(report.imported, [2])
        self.assertIn(1, self.dev.store, "chunk 1 must survive on the device")
        self.assertNotIn(2, self.dev.store)
        self.assertEqual(self.db().execute("SELECT COUNT(*) FROM chunks WHERE seq=1").fetchone()[0], 0)

        retry = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(retry.imported, [1])
        self.assertEqual(len(self.dev.store), 0)

    def test_device_rejects_ack_with_wrong_hash_or_without_auth(self) -> None:
        self.dev.record(1)
        bogus = pack(T.ACK, 1, bytes(32))
        self.assertEqual(unpack(self.dev.handle(bogus)[0])[1][0], E.NOT_AUTHENTICATED)
        client = self.client(LoopbackTransport(self.dev))
        client._handshake(SyncReport())
        self.assertEqual(unpack(self.dev.handle(bogus)[0])[1][0], E.HASH_MISMATCH)
        self.assertIn(1, self.dev.store)

    def test_uart_crc_drops_line_noise(self) -> None:
        wire = bytearray(uart_encode(pack(T.ACK_OK, 7)))
        wire[3] ^= 0x01
        dec = UartDecoder()
        self.assertEqual(dec.feed(bytes(wire)), [])
        self.assertEqual(dec.bad, 1)


class LostClock(Base):
    def test_reconciles_from_monotonic_time(self) -> None:
        self.dev = self.make_device(clock_known=False)
        boot1_truth = [self.dev.true_utc_ms + i * CHUNK_S * 1000 for i in range(3)]
        self.dev.record(3)
        self.dev.advance(60_000)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [1, 2, 3])
        rows = self.db().execute("SELECT * FROM chunks ORDER BY seq").fetchall()
        self.assertEqual([r["time_source"] for r in rows], ["reconciled"] * 3)
        for r, truth in zip(rows, boot1_truth):
            self.assertLessEqual(abs(r["start_utc_ms"] - truth), 1)

        # After the push the device stamps UTC itself.
        self.dev.record(1)
        self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(self.db().execute("SELECT time_source FROM chunks WHERE seq=4").fetchone()[0], "device")

        # A boot that never saw a sync cannot be placed in time; the next one can.
        self.dev.reboot(lose_clock=True)
        orphan_boot = self.dev.boot_id
        self.dev.record(2)
        self.dev.reboot(lose_clock=True)
        self.dev.advance(10_000)
        truth = self.dev.true_utc_ms
        self.dev.record(1)
        self.client(LoopbackTransport(self.dev)).sync()
        orphan = self.db().execute("SELECT * FROM chunks WHERE seq IN (5,6)").fetchall()
        self.assertTrue(all(r["time_source"] == "unknown" and r["start_utc_ms"] is None for r in orphan))
        self.assertTrue(all(r["path"].startswith(f"undated/{self.dev.device_id.hex()}/boot-{orphan_boot:08x}/") for r in orphan))
        last = self.db().execute("SELECT * FROM chunks WHERE seq=7").fetchone()
        self.assertEqual((last["time_source"], last["start_utc_ms"]), ("reconciled", truth))
        self.assertTrue((self.data / "undated" / "undated.md").exists())


class Encryption(Base):
    def test_only_host_key_decrypts(self) -> None:
        self.dev.record(1)
        blob = self.dev.store[1][0]
        self.assertNotIn(self.dev.device_id, blob, "inner header is encrypted")
        self.assertEqual(open_chunk(blob, self.key).meta.seq, 1)

        other = new_host_key()
        with self.assertRaises(ChunkError):
            open_chunk(blob, other)
        # Even if an attacker rewrites the key fingerprint, the AEAD still fails.
        forged = blob[:12] + hashlib.sha256(raw_public(other)).digest()[:8] + blob[20:]
        with self.assertRaises(ChunkError):
            open_chunk(forged, other)
        tampered = blob[:-1] + bytes([blob[-1] ^ 1])
        with self.assertRaises(ChunkError):
            open_chunk(tampered, self.key)

    def test_wrong_host_cannot_sync_or_delete(self) -> None:
        self.dev.record(1)
        with self.assertRaises(KeyMismatch):
            self.client(LoopbackTransport(self.dev), key=new_host_key()).sync()
        self.assertIn(1, self.dev.store)


if __name__ == "__main__":
    unittest.main()
