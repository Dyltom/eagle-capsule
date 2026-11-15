"""Sync protocol messages, serial framing, a serial-port transport and an in-memory loopback transport.

A frame is: 1 type byte + fixed little-endian fields + optional payload (DATA only).
BLE GATT: one frame per write (host->device) or notification (device->host).
Serial:   SLIP-delimited, frame + CRC-32 (see uart_encode / UartDecoder). Used over USB CDC-ACM
          (the capsule's USB-C port) or a hardware UART on the bench; the bytes are the same.
"""
from __future__ import annotations

import struct
import time
import zlib
from collections import deque
from enum import IntEnum

PROTO_VERSION = 1
MIN_FRAME = 96            # INFO is 88 bytes; BLE needs ATT_MTU >= 99 (use 247 with DLE)
DATA_OVERHEAD = 9         # type + seq + offset
MAX_UART_BODY = 0xFFFF + 4   # largest frame (u16 max_frame) + CRC-32


class T(IntEnum):
    HELLO = 0x01
    AUTH = 0x02
    SET_TIME = 0x03
    LIST = 0x04
    FETCH = 0x05
    ACK = 0x06
    INFO = 0x81
    AUTH_OK = 0x82
    TIME_OK = 0x83
    LIST_ITEM = 0x84
    LIST_END = 0x85
    DATA = 0x86
    DATA_END = 0x87
    ACK_OK = 0x88
    ERR = 0xFF


class E(IntEnum):
    BAD_REQUEST = 1
    VERSION = 2
    NOT_AUTHENTICATED = 3
    AUTH_FAILED = 4
    UNKNOWN_CHUNK = 5
    HASH_MISMATCH = 6


FIELDS = {
    T.HELLO: struct.Struct("<BH"),             # proto_version, max_frame
    T.INFO: struct.Struct("<B8sIQQ8sIIIHI32s"),  # version, device_id, boot_id, mono_ms, utc_ms (0=unknown),
                                               # key_fp, oldest_seq, next_seq, dropped, max_frame, free_kb, challenge
    T.AUTH: struct.Struct("<32s"),             # mac
    T.AUTH_OK: struct.Struct("<"),
    T.SET_TIME: struct.Struct("<Q"),           # utc_ms
    T.TIME_OK: struct.Struct("<IQQ"),          # boot_id, mono_ms, utc_ms
    T.LIST: struct.Struct("<IH"),              # from_seq (inclusive), max_items
    T.LIST_ITEM: struct.Struct("<II32s"),      # seq, size, sha256(file)
    T.LIST_END: struct.Struct("<B"),           # more
    T.FETCH: struct.Struct("<III"),            # seq, offset, length
    T.DATA: struct.Struct("<II"),              # seq, offset, + payload
    T.DATA_END: struct.Struct("<II"),          # seq, next_offset
    T.ACK: struct.Struct("<I32s"),             # seq, sha256
    T.ACK_OK: struct.Struct("<I"),             # seq
    T.ERR: struct.Struct("<BI"),               # code, seq (0 if n/a)
}


class ProtocolError(Exception):
    pass


class Disconnected(Exception):
    pass


def pack(t: T, *fields, payload: bytes = b"") -> bytes:
    return bytes([t]) + FIELDS[t].pack(*fields) + payload


def unpack(frame: bytes) -> tuple[T, tuple, bytes]:
    try:
        t = T(frame[0])
        s = FIELDS[t]
        return t, s.unpack_from(frame, 1), frame[1 + s.size:]
    except (IndexError, ValueError, struct.error) as e:
        raise ProtocolError(f"bad frame: {e}") from None


# ---------------------------------------------------------------- UART framing (SLIP + CRC-32)

END, ESC, ESC_END, ESC_ESC = 0xC0, 0xDB, 0xDC, 0xDD


def uart_encode(frame: bytes) -> bytes:
    body = frame + struct.pack("<I", zlib.crc32(frame))
    out = bytearray([END])
    for b in body:
        out += bytes([ESC, ESC_END]) if b == END else bytes([ESC, ESC_ESC]) if b == ESC else bytes([b])
    out.append(END)
    return bytes(out)


class UartDecoder:
    """Byte-stream -> frames. Frames with a bad CRC, or longer than any legal frame, are counted and dropped."""

    def __init__(self) -> None:
        self.buf, self.esc, self.overflow, self.bad = bytearray(), False, False, 0

    def feed(self, data: bytes) -> list[bytes]:
        out = []
        for b in data:
            if b == END:
                if self.overflow:
                    self.bad += 1
                elif len(self.buf) > 4:
                    frame, crc = bytes(self.buf[:-4]), struct.unpack("<I", self.buf[-4:])[0]
                    if zlib.crc32(frame) == crc:
                        out.append(frame)
                    else:
                        self.bad += 1
                self.buf, self.esc, self.overflow = bytearray(), False, False
            elif self.overflow:
                continue
            elif self.esc:
                self.buf.append(END if b == ESC_END else ESC if b == ESC_ESC else b)
                self.esc = False
            elif b == ESC:
                self.esc = True
            else:
                self.buf.append(b)
            if len(self.buf) > MAX_UART_BODY:
                self.buf, self.overflow = bytearray(), True
        return out


# ---------------------------------------------------------------- serial-port transport

class SerialTransport:
    """Sync over a byte-stream serial port: USB CDC-ACM to the capsule, or a UART on the bench.

    `port` is anything with pyserial's `write(bytes)`, `read(n) -> bytes` (b"" on timeout) and,
    optionally, `in_waiting` and `close()`, e.g. `serial.Serial("/dev/ttyACM0", timeout=0.05)`.
    Use `SerialTransport.open(path)` to let it import pyserial for you.
    secure_link defaults to True: a USB cable needs physical access (SYNC-PROTOCOL.md section 8).
    An OSError from the port (pyserial's SerialException is one, e.g. the cable was pulled)
    becomes Disconnected; no complete frame within `timeout` seconds is a TimeoutError.
    """

    def __init__(self, port, *, max_frame: int = 1024, timeout: float = 2.0, secure_link: bool = True) -> None:
        if not MIN_FRAME <= max_frame <= 0xFFFF:
            raise ValueError(f"max_frame must be {MIN_FRAME}..65535")
        self.port, self.max_frame, self.timeout, self.secure_link = port, max_frame, timeout, secure_link
        self._dec = UartDecoder()
        self._rx: deque[bytes] = deque()

    @classmethod
    def open(cls, path: str, **kw) -> "SerialTransport":
        import serial  # pyserial: optional, only needed for a real port

        # CDC-ACM ignores the baud rate; 1 Mbaud is right for a hardware UART on the bench.
        return cls(serial.Serial(path, baudrate=1_000_000, timeout=0.05), **kw)

    @property
    def bad_frames(self) -> int:
        return self._dec.bad

    def send(self, frame: bytes) -> None:
        if len(frame) > 0xFFFF:
            raise ProtocolError("frame too long")
        try:
            self.port.write(uart_encode(frame))
        except OSError as e:
            raise Disconnected(f"serial write failed: {e}") from e

    def recv(self) -> bytes:
        deadline = time.monotonic() + self.timeout
        while not self._rx:
            if time.monotonic() > deadline:
                raise TimeoutError("no response from device")
            try:
                data = self.port.read(getattr(self.port, "in_waiting", 0) or 1)
            except OSError as e:
                raise Disconnected(f"serial read failed: {e}") from e
            self._rx.extend(self._dec.feed(data))
        return self._rx.popleft()

    def close(self) -> None:
        close = getattr(self.port, "close", None)
        if close:
            close()


# ---------------------------------------------------------------- loopback transport

class LoopbackTransport:
    """In-memory link to a simulated device, with fault injection for tests.

    mode="ble":  frames are passed whole and must fit in ATT_MTU - 3.
    mode="uart": frames go through SLIP+CRC encoding and are re-assembled from 61-byte slices.
    drop_after_data: the link dies after this many DATA frames have been delivered.
    corrupt_data:    flip a byte in the Nth DATA frame (models corruption the link CRC cannot see,
                     e.g. a bad SD read on the device).
    secure_link:     whether the client may AUTH and ACK over this link. A real transport sets it
                     only for a bonded LE Secure Connections link or the USB cable. The
                     loopback is in-process, so nothing can relay or inject; tests set False.
    """

    def __init__(self, device, mode: str = "ble", mtu: int = 247,
                 drop_after_data: int | None = None, corrupt_data: int | None = None,
                 secure_link: bool = True) -> None:
        assert mode in ("ble", "uart")
        self.device, self.mode, self.secure_link = device, mode, secure_link
        self.max_frame = mtu - 3 if mode == "ble" else 1024
        self.drop_after_data, self.corrupt_data = drop_after_data, corrupt_data
        self.data_frames, self.connected = 0, True
        self._rx: deque[bytes] = deque()
        self._rx_bytes = bytearray()
        self._host_dec, self._dev_dec = UartDecoder(), UartDecoder()
        device.connect()

    def send(self, frame: bytes) -> None:
        if not self.connected:
            raise Disconnected("link is down")
        if self.mode == "uart":
            inbound = self._dev_dec.feed(uart_encode(frame))
        else:
            if len(frame) > self.max_frame:
                raise ProtocolError("frame exceeds ATT MTU")
            inbound = [frame]
        for f in inbound:
            for resp in self.device.handle(f):
                if resp[0] == T.DATA:
                    self.data_frames += 1
                    if self.drop_after_data is not None and self.data_frames > self.drop_after_data:
                        self.connected = False
                        return
                    if self.data_frames == self.corrupt_data:
                        resp = resp[:-1] + bytes([resp[-1] ^ 0xFF])
                if self.mode == "uart":
                    self._rx_bytes += uart_encode(resp)
                else:
                    assert len(resp) <= self.max_frame, "device sent an oversize notification"
                    self._rx.append(resp)

    def recv(self) -> bytes:
        while not self._rx and self._rx_bytes:
            chunk, self._rx_bytes = self._rx_bytes[:61], self._rx_bytes[61:]
            self._rx.extend(self._host_dec.feed(bytes(chunk)))
        if self._rx:
            return self._rx.popleft()
        if not self.connected:
            raise Disconnected("link dropped")
        raise TimeoutError("no response from device")
