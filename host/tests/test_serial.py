"""SerialTransport (USB CDC-ACM to the capsule) against a fake serial port wired to the simulated device."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from eagle_host.protocol import (Disconnected, SerialTransport, T, UartDecoder, pack,  # noqa: E402
                                 uart_encode)
from tests.test_sync import Base  # noqa: E402


class FakePort:
    """Behaves like an open pyserial port on the capsule's CDC-ACM interface.

    noise:        bytes already in the host's receive buffer when the port opens.
    unplug_after: reads after this many bytes have been delivered raise OSError (the cable was pulled).
    """

    def __init__(self, device, noise: bytes = b"", unplug_after: int | None = None) -> None:
        self.device, self.unplug_after, self.delivered, self.closed = device, unplug_after, 0, False
        self.dec, self.out = UartDecoder(), bytearray(noise)
        device.connect()

    def write(self, data: bytes) -> int:
        if self.closed:
            raise OSError("port is closed")
        for frame in self.dec.feed(data):
            for resp in self.device.handle(frame):
                self.out += uart_encode(resp)
        return len(data)

    @property
    def in_waiting(self) -> int:
        return len(self.out)

    def read(self, n: int) -> bytes:
        if self.closed or (self.unplug_after is not None and self.delivered >= self.unplug_after):
            self.closed = True
            raise OSError("device reports readiness to read but returned no data")
        n = min(n, 61)                     # deliver in USB-packet-sized pieces
        chunk = bytes(self.out[:n])
        del self.out[:n]
        self.delivered += len(chunk)
        return chunk

    def close(self) -> None:
        self.closed = True


class SerialSync(Base):
    def test_full_sync_over_usb_cdc(self) -> None:
        self.dev.record(3)
        self.dev.advance(5000)
        link = SerialTransport(FakePort(self.dev, noise=b"\x00garbage\xc0\x13"))
        self.assertTrue(link.secure_link, "a USB cable needs physical access, so AUTH/ACK are allowed")
        report = self.client(link).sync()
        self.assertEqual(report.imported, [1, 2, 3])
        self.assertFalse(report.interrupted or report.failed or report.hash_failed)
        self.assertEqual(len(self.dev.store), 0)

    def test_cable_pulled_mid_transfer_then_resumes(self) -> None:
        self.dev.record(2)
        report = self.client(SerialTransport(FakePort(self.dev, unplug_after=20_000))).sync()
        self.assertTrue(report.interrupted)
        self.assertEqual(len(self.dev.store), 2, "nothing is released without an ACK")
        report = self.client(SerialTransport(FakePort(self.dev))).sync()
        self.assertEqual(report.imported, [1, 2])
        self.assertGreater(report.resumed_bytes, 0)

    def test_silent_port_times_out(self) -> None:
        class Silent:
            def write(self, data: bytes) -> int:
                return len(data)

            def read(self, n: int) -> bytes:
                return b""

        link = SerialTransport(Silent(), timeout=0.05)
        link.send(pack(T.HELLO, 1, 1024))
        with self.assertRaises(TimeoutError):
            link.recv()

    def test_write_error_is_a_disconnect(self) -> None:
        port = FakePort(self.dev)
        port.close()
        with self.assertRaises(Disconnected):
            SerialTransport(port).send(pack(T.HELLO, 1, 1024))

    def test_rejects_bad_max_frame(self) -> None:
        with self.assertRaises(ValueError):
            SerialTransport(FakePort(self.dev), max_frame=10)


if __name__ == "__main__":
    unittest.main()
