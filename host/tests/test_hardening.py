"""Regression tests for the host-side review findings (durability, filing, link security, bad chunks, limits)."""
from __future__ import annotations

import hashlib
import os
import stat
import sys
import threading
import unittest
import wave
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey  # noqa: E402

from eagle_host.chunkfile import ChunkMeta, raw_public, seal  # noqa: E402
from eagle_host.client import InsecureLink  # noqa: E402
from eagle_host.files import DataDirLocked, DirLock, write_file  # noqa: E402
from eagle_host.keys import PASSPHRASE_ENV, load_or_create_key  # noqa: E402
from eagle_host.protocol import (MAX_UART_BODY, Disconnected, LoopbackTransport, T, UartDecoder,  # noqa: E402
                                 pack, uart_encode, unpack)
from eagle_host.store import Index  # noqa: E402
from tests.test_sync import CHUNK_S, RATE, Base  # noqa: E402

POSIX = os.name == "posix"


def meta(dev, seq: int, **kw) -> ChunkMeta:
    fields = dict(device_id=dev.device_id, boot_id=dev.boot_id, seq=seq, start_mono_ms=dev.mono_ms,
                  start_utc_ms=dev.utc_now(), sample_rate=RATE, bitrate=0, codec=0, frame_ms=20,
                  duration_ms=1000)
    fields.update(kw)
    return ChunkMeta(**fields)


def put(dev, m: ChunkMeta, eph=None) -> None:
    blob = seal(m, [b"\x01\x00" * (RATE // 50)] * 50, dev.host_pub, eph)
    dev.store[m.seq] = (blob, hashlib.sha256(blob).digest())
    dev.next_seq = max(dev.next_seq, m.seq + 1)


def drop_frames(dev, frame_type: T, which: set[int]) -> None:
    """Make the device's Nth response of `frame_type` vanish (a frame lost to a CRC error)."""
    orig, n = dev.handle, [0]

    def handle(frame):
        out = []
        for r in orig(frame):
            if r[0] == frame_type:
                n[0] += 1
                if n[0] in which:
                    continue
            out.append(r)
        return out
    dev.handle = handle


def limit_calls(dev, name: str, limit: int) -> None:
    """Turn a would-be infinite loop in the client into an error instead of a hung test run."""
    orig, n = getattr(dev, name), [0]

    def wrapped(*a):
        n[0] += 1
        if n[0] > limit:
            raise RuntimeError(f"client sent more than {limit} {name} requests")
        return orig(*a)
    setattr(dev, name, wrapped)


class Durability(Base):
    """Finding 1: nothing is ACKed unless the archive file is on disk and verified."""

    def _lose_first_ack(self) -> None:
        orig = self.dev._ack
        self.dev._ack = lambda s, h: []           # ACK lost in transit: no ACK_OK, device keeps the chunk
        first = self.client(LoopbackTransport(self.dev)).sync()
        self.assertTrue(first.interrupted)
        self.dev._ack = orig

    def test_reack_refetches_when_archive_file_is_damaged(self) -> None:
        self.dev.record(1)
        self._lose_first_ack()
        wav = next(self.data.rglob("*.wav"))
        wav.write_bytes(b"")                       # what delayed allocation can leave after a power cut
        self.dev.fetch_log.clear()
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual((report.reacked, report.refetched, report.imported), ([], [1], [1]))
        self.assertTrue(self.dev.fetch_log, "re-downloaded instead of trusting the index")
        with wave.open(str(wav)) as w:
            self.assertEqual(w.getnframes(), CHUNK_S * RATE)
        self.assertEqual(len(list(wav.parent.glob("*.damaged-*"))), 1, "damaged file set aside, not deleted")
        self.assertEqual(len(self.dev.store), 0)

    def test_reack_without_download_when_archive_file_is_intact(self) -> None:
        self.dev.record(1)
        self._lose_first_ack()
        self.dev.fetch_log.clear()
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual((report.reacked, report.imported, self.dev.fetch_log), ([1], [], []))
        self.assertEqual(len(self.dev.store), 0)

    def test_file_is_fsynced_before_ack(self) -> None:
        self.dev.record(1)
        events, real_fsync = [], os.fsync

        class Recording(LoopbackTransport):
            def send(self, frame):
                if frame[0] == T.ACK:
                    events.append("ack")
                super().send(frame)

        with mock.patch("os.fsync", side_effect=lambda fd: (events.append("fsync"), real_fsync(fd))[1]):
            self.assertEqual(self.client(Recording(self.dev)).sync().imported, [1])
        self.assertGreaterEqual(events[:events.index("ack")].count("fsync"), 2, "file and directory fsynced")
        self.assertEqual([p for p in self.data.rglob(".tmp-*")], [], "no temp files left behind")

    def test_write_file_never_overwrites(self) -> None:
        path = self.data / "a" / "x.wav"
        write_file(path, b"one")
        with self.assertRaises(FileExistsError):
            write_file(path, b"two")
        write_file(path, b"one")                   # identical content (earlier run stopped before indexing)
        self.assertEqual(path.read_bytes(), b"one")


class Filing(Base):
    """Finding 2: archive paths include device and boot, and a file is never overwritten."""

    def test_two_devices_same_second_same_seq(self) -> None:
        a = self.make_device(device_id=b"PENDANTA", seed=1)
        b = self.make_device(device_id=b"PENDANTB", seed=2)
        a.true_utc_ms = b.true_utc_ms = self.dev.true_utc_ms
        a.reboot(lose_clock=False)
        b.reboot(lose_clock=False)
        a.record(1)
        b.record(1)
        self.client(LoopbackTransport(a)).sync()
        first = next(self.data.rglob("*.wav"))
        before = first.read_bytes()
        self.client(LoopbackTransport(b)).sync()
        paths = [r["path"] for r in self.db().execute("SELECT path FROM chunks ORDER BY device_id")]
        self.assertEqual(len(set(paths)), 2)
        self.assertIn(b"PENDANTA".hex(), paths[0])
        self.assertIn(b"PENDANTB".hex(), paths[1])
        self.assertEqual(len(list(self.data.rglob("*.wav"))), 2)
        self.assertEqual(first.read_bytes(), before)

    def test_forged_chunk_cannot_overwrite_real_audio(self) -> None:
        utc = self.dev.true_utc_ms
        self.dev.record(1)
        self.client(LoopbackTransport(self.dev)).sync()
        victim = next(self.data.rglob("*.wav"))
        before = victim.read_bytes()
        rogue = self.make_device(device_id=b"ROGUE!!!")    # needs only the host PUBLIC key
        put(rogue, meta(rogue, 1, boot_id=7, start_mono_ms=0, start_utc_ms=utc))
        self.client(LoopbackTransport(rogue)).sync()
        self.assertEqual(victim.read_bytes(), before)


class LinkSecurity(Base):
    """Finding 3: no AUTH/ACK over a link that is not declared secure."""

    def test_refuses_insecure_link_unless_overridden(self) -> None:
        self.dev.record(1)
        with self.assertRaises(InsecureLink):
            self.client(LoopbackTransport(self.dev, secure_link=False)).sync()
        self.assertIn(1, self.dev.store)
        report = self.client(LoopbackTransport(self.dev, secure_link=False), allow_insecure=True).sync()
        self.assertEqual(report.imported, [1])

    def test_auth_relay_is_refused(self) -> None:
        real = self.dev
        real.record(5)

        class Relay:                      # host thinks this is the pendant; it forwards to the real one
            max_frame = 244

            def __init__(self):
                real.connect()
                self.q = []

            def send(self, f):
                out = real.handle(f)
                if f[0] == T.AUTH and out[0][0] == T.AUTH_OK:
                    items = [unpack(x)[1] for x in real.handle(pack(T.LIST, 0, 64)) if x[0] == T.LIST_ITEM]
                    for seq, _, sha in items:
                        real.handle(pack(T.ACK, seq, sha))
                    raise Disconnected("relay hangs up")
                self.q += out

            def recv(self):
                return self.q.pop(0)

        with self.assertRaises(InsecureLink):
            self.client(Relay()).sync()
        self.assertEqual(list(real.store), [1, 2, 3, 4, 5])


class BadChunks(Base):
    """Findings 4, 5, 7: one bad chunk is skipped (no ACK) and the rest still sync."""

    def test_reused_seq_is_stored_as_a_distinct_chunk(self) -> None:
        self.dev.record(2)
        self.assertEqual(self.client(LoopbackTransport(self.dev)).sync().imported, [1, 2])
        self.dev.next_seq = 1                      # card replaced / seq counter reset
        self.dev.advance(3_600_000)
        self.dev.record(3)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual((report.imported, report.failed), ([1, 2, 3], {}))
        self.assertEqual(self.db().execute("SELECT COUNT(*) FROM chunks").fetchone()[0], 5)
        self.assertEqual(len(self.dev.store), 0)

    def test_absurd_device_time_does_not_block_sync(self) -> None:
        put(self.dev, meta(self.dev, 1, start_mono_ms=0, start_utc_ms=2**62))
        self.dev.record(2)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [1, 2, 3])
        src = self.db().execute("SELECT time_source FROM chunks WHERE seq=1").fetchone()[0]
        self.assertEqual(src, "reconciled", "implausible device clock ignored, anchor used instead")

    def test_bad_sample_rate_is_skipped_not_acked(self) -> None:
        put(self.dev, meta(self.dev, 1, sample_rate=0))
        self.dev.record(2)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [2, 3])
        self.assertIn("sample rate", report.failed[1])
        self.assertEqual(list(self.dev.store), [1])
        self.assertEqual(self.db().execute("SELECT COUNT(*) FROM chunks WHERE seq=1").fetchone()[0], 0)

    def test_chunk_from_another_device_is_rejected(self) -> None:
        other = self.make_device(device_id=b"DEVICE_A")
        other.record(1)
        self.dev.store[1] = other.store[1]
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [])
        self.assertIn("device", report.failed[1])
        self.assertIn(1, self.dev.store)
        self.assertEqual(self.db().execute("SELECT COUNT(*) FROM chunks").fetchone()[0], 0)

    def test_device_err_on_fetch_skips_only_that_chunk(self) -> None:
        self.dev.record(2)
        orig = self.dev._fetch
        self.dev._fetch = lambda s, o, n: [pack(T.ERR, 5, s)] if s == 1 else orig(s, o, n)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [2])
        self.assertIn("DeviceError", report.failed[1])
        self.assertFalse(report.interrupted)

    def test_device_err_on_ack_skips_only_that_chunk(self) -> None:
        self.dev.record(2)
        orig = self.dev._ack
        self.dev._ack = lambda s, h: [pack(T.ERR, 6, s)] if s == 1 else orig(s, h)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [2])
        self.assertIn("DeviceError", report.failed[1])

    def test_short_file_fails_fast_instead_of_looping(self) -> None:
        self.dev.record(2)
        orig = self.dev._list

        def bad_list(f, m):
            out = orig(f, m)
            _, (s, size, sha), _ = unpack(out[0])
            out[0] = pack(T.LIST_ITEM, s, size + 10, sha)       # INDEX and file disagree
            return out
        self.dev._list = bad_list
        limit_calls(self.dev, "_fetch", 200)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertIn("FetchFailed", report.failed[1])
        self.assertEqual(report.imported, [2])
        self.assertLess(len(self.dev.fetch_log), 20)


class LostFrames(Base):
    """Finding 8: a UART frame lost to a CRC error means re-FETCH from the last good offset."""

    def test_lost_data_frame(self) -> None:
        self.dev.record(1)
        drop_frames(self.dev, T.DATA, {3})
        report = self.client(LoopbackTransport(self.dev, "uart")).sync()
        self.assertEqual((report.imported, report.failed, report.hash_failed), ([1], {}, []))

    def test_lost_data_end(self) -> None:
        self.dev.record(1)
        drop_frames(self.dev, T.DATA_END, {1})
        report = self.client(LoopbackTransport(self.dev, "uart")).sync()
        self.assertEqual((report.imported, report.interrupted), ([1], False))


class TimeAnchors(Base):
    """Finding 9: an anchor only places chunks inside the mono range its boot has shown."""

    def test_anchor_is_used_only_within_its_boot_range(self) -> None:
        self.data.mkdir(parents=True)
        idx = Index(self.data / "index.sqlite")
        self.addCleanup(idx.close)
        t = 1_760_000_000_000
        idx.add_anchor("d", 7, 5000, t)
        self.assertEqual(idx.resolve_utc("d", 7, 4000, 0), (t - 1000, "reconciled"))
        self.assertEqual(idx.resolve_utc("d", 7, 10**12, 0), (None, "unknown"))
        self.assertEqual(idx.resolve_utc("d", 8, 4000, 0), (None, "unknown"))
        self.assertEqual(idx.resolve_utc("d", 7, 4000, 2**62), (t - 1000, "reconciled"))


class Limits(Base):
    """Finding 10: bounded chunk size, LIST paging and UART buffer."""

    def test_oversize_chunk_is_not_fetched(self) -> None:
        self.dev.record(2)
        orig = self.dev._list

        def big(f, m):
            out = orig(f, m)
            _, (s, _size, sha), _ = unpack(out[0])
            out[0] = pack(T.LIST_ITEM, s, 9 << 20, sha)
            return out
        self.dev._list = big
        limit_calls(self.dev, "_fetch", 200)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertIn("exceeds", report.failed[1])
        self.assertNotIn(1, [s for s, _, _ in self.dev.fetch_log])
        self.assertEqual(report.imported, [2])

    def test_repeated_list_pages_terminate(self) -> None:
        self.dev.record(2)
        orig = self.dev._list
        self.dev._list = lambda f, m: orig(0, m)[:-1] + [pack(T.LIST_END, 1)]   # ignores from_seq, always "more"
        limit_calls(self.dev, "_list", 50)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [1, 2])
        self.assertTrue(any("ascending" in e for e in report.errors))

    def test_last_possible_seq(self) -> None:
        put(self.dev, meta(self.dev, 0xFFFFFFFF))
        self.dev.next_seq = 0xFFFFFFFF             # the simulator's INFO field is u32 too
        orig = self.dev._list
        self.dev._list = lambda f, m: orig(f, m)[:-1] + [pack(T.LIST_END, 1)]
        limit_calls(self.dev, "_list", 50)
        report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [0xFFFFFFFF])

    def test_uart_decoder_buffer_is_bounded(self) -> None:
        dec = UartDecoder()
        self.assertEqual(dec.feed(b"\x41" * 200_000), [])
        self.assertLessEqual(len(dec.buf), MAX_UART_BODY)
        frame = pack(T.ACK_OK, 7)
        self.assertEqual(dec.feed(uart_encode(frame)), [frame])
        self.assertEqual(dec.bad, 1)


class Concurrency(Base):
    """Finding 11: one sync per data dir."""

    def test_second_sync_on_same_data_dir_is_refused(self) -> None:
        self.dev.record(1)
        client = self.client(LoopbackTransport(self.dev))
        with DirLock(self.data / ".lock"):
            with self.assertRaises(DataDirLocked):
                client.sync()
        self.assertIn(1, self.dev.store)
        self.assertEqual(self.client(LoopbackTransport(self.dev)).sync().imported, [1])

    def test_lock_is_exclusive_across_threads(self) -> None:
        self.data.mkdir(parents=True)
        results = []
        with DirLock(self.data / ".lock"):
            def other():
                try:
                    with DirLock(self.data / ".lock"):
                        results.append("acquired")
                except DataDirLocked:
                    results.append("locked")
            th = threading.Thread(target=other)
            th.start()
            th.join()
        self.assertEqual(results, ["locked"])


class EphemeralReuse(Base):
    """Finding 12: a repeated ephemeral key (= key and nonce reuse) is flagged, the audio still kept."""

    def test_reused_ephemeral_key_is_flagged(self) -> None:
        eph = X25519PrivateKey.generate()
        put(self.dev, meta(self.dev, 1), eph)
        self.dev.advance(1000)
        put(self.dev, meta(self.dev, 2), eph)
        with self.assertLogs("eagle_host.client", "WARNING"):
            report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual((report.imported, report.eph_reused), ([1, 2], [2]))


class Rollup(Base):
    """Finding 13: a failing rollup does not mask the sync result."""

    def test_rollup_failure_is_reported_not_raised(self) -> None:
        self.dev.record(1)
        with mock.patch("eagle_host.client.write_rollup", side_effect=OSError("disk full")):
            report = self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(report.imported, [1])
        self.assertTrue(any("disk full" in e for e in report.errors))


@unittest.skipUnless(POSIX, "POSIX permission bits")
class Permissions(Base):
    """Finding 6: owner-only key and archive, passphrase-protected key."""

    def setUp(self) -> None:
        super().setUp()
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)

    def mode(self, p: Path) -> int:
        return stat.S_IMODE(p.stat().st_mode)

    def test_key_file_is_private_and_encrypted(self) -> None:
        path = Path(self.tmp.name) / "keys" / "host_key.pem"
        key = load_or_create_key(path, passphrase="correct horse")
        self.assertEqual(self.mode(path), 0o600)
        self.assertEqual(self.mode(path.parent), 0o700)
        self.assertTrue(path.read_text().startswith("-----BEGIN ENCRYPTED PRIVATE KEY-----"))
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop(PASSPHRASE_ENV, None)
            with self.assertRaises(TypeError):
                load_or_create_key(path)
        with mock.patch.dict(os.environ, {PASSPHRASE_ENV: "correct horse"}):
            self.assertEqual(raw_public(load_or_create_key(path)), raw_public(key))
        self.assertEqual(path.with_suffix(".pub").read_bytes(), raw_public(key))

    def test_archive_is_owner_only(self) -> None:
        self.dev.record(2)
        self.client(LoopbackTransport(self.dev, drop_after_data=200)).sync()
        for p in (self.data / ".partial").iterdir():
            self.assertEqual(self.mode(p), 0o600, p)
        self.client(LoopbackTransport(self.dev)).sync()
        self.assertEqual(self.mode(self.data), 0o700)
        files = [p for p in self.data.rglob("*") if p.is_file()]
        self.assertTrue(any(p.suffix == ".wav" for p in files) and any(p.suffix == ".md" for p in files))
        for p in files:
            self.assertEqual(self.mode(p), 0o600, p)
        for p in self.data.rglob("*"):
            if p.is_dir():
                self.assertEqual(self.mode(p), 0o700, p)


if __name__ == "__main__":
    unittest.main()
