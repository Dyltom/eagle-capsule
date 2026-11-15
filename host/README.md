# Eagle Capsule host: sync client and device simulator

> **Credits.** The BLE + Opus streaming approach comes from
> [BasedHardware/omi](https://github.com/BasedHardware/omi) (MIT). Local transcription uses
> [SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper) (MIT) when it is installed.
> The real BLE link will use [bleak](https://github.com/hbldh/bleak) (MIT). Thank you to all three.
> See also [`../CREDITS.md`](../CREDITS.md).

This is a reference implementation of [`docs/SYNC-PROTOCOL.md`](../docs/SYNC-PROTOCOL.md) for a
dry run before buying hardware. A **simulated pendant** records synthetic audio into an
encrypted ring buffer. A **sync client** pulls it over an in-memory link that behaves like BLE
GATT or a byte-stream UART, then verifies, decrypts, files, indexes and summarises it.

## Setup

Python 3.11+. The only required dependency is `cryptography`.

```powershell
# Windows PowerShell, from the repo root
cd host
py -3.11 -m venv .venv            # .venv is gitignored
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt   # cryptography (+ pytest, optional)
```

```bash
# Linux / WSL / macOS
cd host && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
```

Optional extras, each detected at runtime. Without them the code falls back gracefully:

| Package | Effect if installed | Fallback |
|---|---|---|
| `opuslib` (+ libopus DLL/.so) | Simulator encodes real 16 kbps Opus; host decodes to WAV | Raw 16-bit PCM payload (`codec = 0`) |
| `faster-whisper` | `--whisper` transcribes each chunk | Transcript row with status `untranscribed` |

## Run the tests

```bash
cd host
python -m unittest -v          # standard library only
python -m pytest -q            # same tests, if pytest is installed
```

| Test | What it proves |
|---|---|
| `NormalSync` (BLE and UART) | List, fetch, SHA-256 check, decrypt, WAV under `data/YYYY/MM/DD/`, SQLite rows, FTS5 search, daily rollup, device empties only after ACK. Also covers the stub transcriber and ring-buffer overwrite reporting. |
| `DisconnectResume` (BLE and UART) | Link dies about 24 KB into a chunk. Nothing is deleted, the `.partial` file is kept, and the next session FETCHes from the saved offset. |
| `HashMismatch` | A corrupted DATA frame means no ACK, the chunk stays on the device and is imported on retry. The device refuses an ACK with the wrong hash or one sent before AUTH. A UART CRC error drops the frame. |
| `LostClock` | Chunks recorded without UTC are reconstructed to the millisecond from `(boot_id, mono_ms)` and the SET_TIME anchor. A boot that never saw a sync is filed under `data/undated/`. |
| `Encryption` | Only the host key opens a chunk. A forged fingerprint or a flipped bit fails the GCM check. A host with the wrong key cannot sync or delete. |

## Run a simulated night

```bash
cd host
python -m eagle_host.demo --out demo-out --chunks 5 --chunk-seconds 60
python -m eagle_host.demo --out demo-out --uart --lost-clock --flaky   # dock UART, no clock, dropped link
```

Output (the `data/` folder is gitignored):

```
demo-out/host_key.pem                 X25519 private key (demo: unencrypted, so protect a real one)
demo-out/host_key.pub                 the 32 bytes you would flash into the pendant
demo-out/data/index.sqlite            chunks, anchors, transcripts, transcripts_fts
demo-out/data/2026/11/15/HHMMSS_<seq>.wav
demo-out/data/2026/11/15/2026-11-15.md   daily rollup
demo-out/data/undated/boot-<id>/...   chunks whose wall-clock time can't be recovered
```

Search transcripts with: `SELECT * FROM transcripts_fts WHERE transcripts_fts MATCH 'dentist'`.

## Code map

| File | Role | Real-world counterpart |
|---|---|---|
| `eagle_host/chunkfile.py` | File format, ECIES seal/open, AUTH MAC | Firmware writer (C, streaming GCM) and host reader |
| `eagle_host/protocol.py` | Frame structs, SLIP+CRC-32, `LoopbackTransport` with fault injection | GATT CTRL/STREAM characteristics, or the dock UART |
| `eagle_host/simulator.py` | `FakeDevice`: ring buffer, boot/clock model, protocol handler | nRF52840 firmware |
| `eagle_host/audio.py` | Synthetic speech-ish audio, energy VAD, PCM/Opus codec choice | PDM mic + Opus encoder |
| `eagle_host/client.py` | `SyncClient`: handshake, resume, verify, import, ACK | Same code, once the transport is real |
| `eagle_host/store.py` | SQLite schema, time reconciliation, Markdown rollup | Same |
| `eagle_host/transcribe.py` | faster-whisper, or a stub | Same |

## Moving to real hardware

Only the transport changes. `SyncClient` needs an object with `max_frame`, `send(frame)` and
`recv() -> frame` that raises `Disconnected` or `TimeoutError`:

* **BLE**: wrap `bleak.BleakClient`. Request MTU 247, then set `max_frame = mtu - 3`.
  `send` writes to CTRL (write-without-response). A notify handler on STREAM pushes frames
  into an `asyncio.Queue` (or a thread-safe queue), and `recv` pops with a timeout. A
  `disconnected_callback` maps to `Disconnected`.
* **UART dock**: `pyserial` at 1 Mbaud. `send` writes `uart_encode(frame)`. `recv` reads
  bytes into `UartDecoder.feed()` until a frame comes out.

The simulator's `handle(frame) -> [frames]` is the state machine the firmware implements.
The tests double as its acceptance tests: point a real transport at a dev board and the same
client logic has to pass.

What the simulator does **not** model: the encryption is one-shot here, while the firmware
must stream it (AES-GCM is incremental, so the output is byte-identical); there is no SD
latency or wear, no concurrent recording during sync, no BLE timing, and Opus is only used if
`opuslib` is present.
