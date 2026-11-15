# Eagle Capsule host: sync client and device simulator

> **Credits.** The BLE + Opus streaming approach comes from
> [BasedHardware/omi](https://github.com/BasedHardware/omi) (MIT). Local transcription uses
> [SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper) (MIT) when it is installed.
> The real BLE link will use [bleak](https://github.com/hbldh/bleak) (MIT), and the USB serial link
> uses [pyserial](https://github.com/pyserial/pyserial) (BSD-3-Clause). Thank you to all four.
> See also [`../CREDITS.md`](../CREDITS.md).

This is a reference implementation of [`docs/SYNC-PROTOCOL.md`](../docs/SYNC-PROTOCOL.md) for a
dry run before buying hardware. A **simulated pendant** records synthetic audio into an
encrypted ring buffer. A **sync client** pulls it over an in-memory link that behaves like BLE
GATT or a byte-stream serial port (USB CDC-ACM, the capsule's main sync path), then verifies,
decrypts, files, indexes and summarises it. `SerialTransport` is the real USB serial transport,
tested against a fake port.

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
| `opuslib` (+ libopus DLL/.so) | Simulator encodes real Opus at 16 kbps (`OPUS_BITRATE` in `eagle_host/audio.py`, `APPLICATION_VOIP`), not the firmware's planned 24 kbps CELT-only setup; host decodes to WAV | Raw 16-bit PCM payload (`codec = 0`, 256 kbps, ~1.9 MB per 60 s chunk; the simulator has no 256 KiB slot limit) |
| `faster-whisper` | `--whisper` transcribes each chunk | Transcript row with status `untranscribed` |
| `pyserial` | `SerialTransport.open("/dev/ttyACM0")` talks to a real capsule over USB | Not needed for the tests or the demo |

## Run the tests

```bash
cd host
python -m unittest -v          # standard library only
python -m pytest -q            # same tests, if pytest is installed
```

| Test | What it proves |
|---|---|
| `NormalSync` (BLE and serial) | List, fetch, SHA-256 check, decrypt, WAV under `data/YYYY/MM/DD/`, SQLite rows, FTS5 search, daily rollup, device empties only after ACK. Also covers the stub transcriber and ring-buffer overwrite reporting. |
| `DisconnectResume` (BLE and serial) | Link dies about 24 KB into a chunk. Nothing is deleted, the `.partial` file is kept, and the next session FETCHes from the saved offset. |
| `HashMismatch` | A corrupted DATA frame means no ACK, the chunk stays on the device and is imported on retry. The device refuses an ACK with the wrong hash or one sent before AUTH. A serial CRC error drops the frame. |
| `LostClock` | Chunks recorded without UTC are reconstructed to the millisecond from `(boot_id, mono_ms)` and the SET_TIME anchor. A boot that never saw a sync is filed under `data/undated/`. |
| `Encryption` | Only the host key opens a chunk. A forged fingerprint or a flipped bit fails the GCM check. A host with the wrong key cannot sync or delete. |

`tests/test_hardening.py` holds one regression test per finding from the host review:

| Test class | What it proves |
|---|---|
| `Durability` | The WAV and its directory are fsynced before the ACK. A lost ACK is re-sent only if the archive file still matches its recorded hash; otherwise it is set aside and the chunk is fetched again. `write_file` never overwrites. |
| `Filing` | Two pendants recording the same `seq` in the same second get separate files. A forged chunk cannot overwrite real audio. |
| `LinkSecurity` | No AUTH/ACK over a transport without `secure_link` (including an AUTH relay) unless `allow_insecure=True`. |
| `BadChunks` | A reused `seq`, an absurd device clock, a bad sample rate, a chunk from another device, a device `ERR` on FETCH or ACK, or a file shorter than LIST says: each affects only that chunk. |
| `LostFrames` | A serial DATA frame or DATA_END lost to a CRC error is re-FETCHed from the last good offset. |
| `TimeAnchors` | An anchor only places chunks of its own boot, within the mono range that boot has reported. |
| `Limits` | Chunks over 8 MiB are not fetched. A repeated LIST page or `seq = 0xFFFFFFFF` ends the listing. The serial decoder buffer is bounded. |
| `Concurrency` | A second sync on the same data dir is refused. |
| `EphemeralReuse` | A repeated `eph_pub` (GCM key/nonce reuse) is reported, and the audio is still stored. |
| `Rollup` | A failing rollup is reported, never raised over the sync result. |
| `Permissions` | The key is 0600 and passphrase-encrypted. The data dir and everything in it are owner-only (0700/0600). |

`tests/test_serial.py` drives `SerialTransport` through a fake pyserial-like port wired to the
simulated device (`SerialSync`): a full sync with line noise already in the buffer, a cable
pulled mid-transfer and resumed, a silent port timing out, a write error becoming `Disconnected`,
and `secure_link` defaulting to True for the cable.

## Run a simulated night

```bash
cd host
python -m eagle_host.demo --out demo-out --chunks 5 --chunk-seconds 60
python -m eagle_host.demo --out demo-out --uart --lost-clock --flaky   # serial framing (as over USB CDC), no clock, dropped link
```

Output (the `data/` folder is gitignored):

```
demo-out/host_key.pem                 X25519 private key, 0600 (encrypted if $EAGLE_KEY_PASSPHRASE is set)
demo-out/host_key.pub                 the 32 bytes you would flash into the pendant
demo-out/data/index.sqlite            chunks, anchors, transcripts, transcripts_fts
demo-out/data/2026/11/15/<device_id>/<HHMMSS>_<boot_id>_<seq>_<sha8>.wav
demo-out/data/2026/11/15/2026-11-15.md   daily rollup
demo-out/data/undated/<device_id>/boot-<boot_id>/mono<ms>_<boot_id>_<seq>_<sha8>.wav
                                      chunks whose wall-clock time can't be recovered
demo-out/data/.partial/               resumable downloads;  data/.lock  one sync at a time
```

`device_id` and `boot_id` are hex and `seq` is decimal. `sha8` is the first 8 hex digits of the
chunk's SHA-256 as stored on the device, so a reused `seq` never collides. An archive file is
never overwritten. If Opus can't be decoded on this host, the file is `<...>.opus.frames`
(length-prefixed packets) instead of `.wav`.

### Key and file handling

* `eagle_host.keys.load_or_create_key(path, passphrase=None)` creates the key as a 0600 PKCS#8
  PEM, plus the `.pub`. The passphrase defaults to `$EAGLE_KEY_PASSPHRASE`. With one, the PEM
  is encrypted. Without one, it is stored in clear (still owner-only) and the demo says so.
  `eagle_host.demo.load_or_create_key` is the same function.
* The client creates the data dir and its subfolders 0700, and every file in them 0600
  (WAVs, rollups, the index and its journal, partials, the lock). The demo also sets `umask 077`.
* Each archive file goes to a temp file, then fsync, rename and directory fsync. Only after
  that is the SQLite row committed, and only after that is the ACK sent.

### What happens when something goes wrong

`SyncClient.sync()` returns a `SyncReport`. Nothing in the lists below is ACKed, so the device
keeps it and the next sync retries it:

| Field | Meaning |
|---|---|
| `hash_failed` | The downloaded bytes don't match the LIST hash. |
| `decrypt_failed` | GCM failed (corrupt, or sealed to another key). |
| `failed` | `{seq: reason}` for everything else: a device `ERR`, no FETCH progress, inner `device_id` not equal to INFO's, unknown codec, unsupported sample rate/frame size/channels, over 8 MiB. |

Informational fields: `refetched` (index row existed but the archive file was missing or
damaged; the old file is renamed `*.damaged-<ns>`), `reacked`, `eph_reused`, `errors`
(session-level problems such as a non-ascending LIST or a failed rollup), and `interrupted`
(the link dropped; partial downloads are kept). `sync()` raises `KeyMismatch`, `InsecureLink`
or `files.DataDirLocked` before doing anything destructive. A device clock outside 2020–2100
is ignored, and the chunk is dated from an anchor or filed as undated.

Search transcripts with: `SELECT * FROM transcripts_fts WHERE transcripts_fts MATCH 'dentist'`.

## Running it at home

A suggested split (not yet tested on real hardware):

| Box | Job | Why |
|---|---|---|
| NAS (Unraid or similar) | Durable storage for `data/` and `index.sqlite`, with snapshots and an off-site backup, **encrypted at rest** (restic or borg repository, or an encrypted share) | Always on, redundant disks. Keep the X25519 private key off it. |
| Apple Silicon Mac (e.g. M3 Max) | Sync client on the capsule's USB serial port (plug the capsule's cable into the Mac at night), then decrypt, VAD and transcribe overnight | Fast, quiet and low-power for an overnight batch |

Transcription on the Mac:

* **whisper.cpp** is the mature path on Apple Silicon. It runs fully on the GPU via Metal, and
  can optionally run the encoder on the Neural Engine via Core ML
  ([README](https://github.com/ggml-org/whisper.cpp)).
* **faster-whisper**, which `eagle_host/transcribe.py` uses, runs on CTranslate2. CTranslate2
  v4.9.0 (10 Nov 2026) added an **experimental** Metal backend (`device="mps"`, in the Apple
  Silicon wheels), but `device="auto"`, which our code passes, still picks the CPU
  ([release notes](https://github.com/OpenNMT/CTranslate2/releases/tag/v4.9.0)). We haven't
  tested faster-whisper on MPS. Until we have, expect CPU speed on a Mac, or swap in whisper.cpp.

**The archive is plaintext.** The host decrypts on import: `data/` holds WAVs (or
`.opus.frames`) and daily Markdown rollups, and `index.sqlite` holds plaintext transcripts.
Only the device's card and the in-flight `.partial` downloads are ciphertext. On the host the
client makes all of it owner-only (0700 dirs, 0600 files), but that does nothing for a copy.
So any NAS, backup or off-site copy must be encrypted with its own key (restic/borg, or an
encrypted share), and the X25519 private key stays on the decrypting box, not on the NAS.

Network: keep any web or search interface on the **home network or a Tailscale tailnet only**.
Never port-forward it to the internet. The archive is everyone's conversations, so treat it like
a password vault. The X25519 private key lives on the box that decrypts (the Mac), with its own
backup kept offline.

## Code map

| File | Role | Real-world counterpart |
|---|---|---|
| `eagle_host/chunkfile.py` | File format, ECIES seal/open, AUTH MAC | Firmware writer (C, streaming GCM) and host reader |
| `eagle_host/protocol.py` | Frame structs, SLIP+CRC-32, `SerialTransport` (USB CDC), `LoopbackTransport` with fault injection | GATT CTRL/STREAM characteristics, or the capsule's USB CDC sync port |
| `eagle_host/simulator.py` | `FakeDevice`: ring buffer, boot/clock model, protocol handler | nRF52840 firmware |
| `eagle_host/audio.py` | Synthetic speech-ish audio, energy VAD, PCM/Opus codec choice | PDM mic + Opus encoder |
| `eagle_host/client.py` | `SyncClient`: handshake, resume, verify, import, ACK | Same code, once the transport is real |
| `eagle_host/store.py` | SQLite schema, time reconciliation, Markdown rollup | Same |
| `eagle_host/files.py` | Owner-only, fsynced, no-overwrite writes; data-dir lock | Same |
| `eagle_host/keys.py` | Host key file (0600, optional passphrase) | Same, or swap in the OS keyring/DPAPI |
| `eagle_host/transcribe.py` | faster-whisper, or a stub | Same |

## Moving to real hardware

Only the transport changes, and the USB one is already here. `SyncClient` needs an object with `max_frame`, `secure_link`,
`send(frame)` and `recv() -> frame` that raises `Disconnected` or `TimeoutError`. The client
refuses to AUTH or ACK unless `secure_link` is true (see SYNC-PROTOCOL.md §8 for the relay
attack this blocks):

* **BLE**: wrap `bleak.BleakClient`. Request MTU 247, then set `max_frame = mtu - 3`.
  `send` writes to CTRL (write-without-response). A notify handler on STREAM pushes frames
  into an `asyncio.Queue` (or a thread-safe queue), and `recv` pops with a timeout. A
  `disconnected_callback` maps to `Disconnected`. Set `secure_link = True` only when the
  link is encrypted with an LE Secure Connections bond to the paired pendant.
* **USB cable (main path)**: plug the capsule into the PC; it enumerates as two CDC-ACM ports,
  one for sync and one for SMP firmware updates (`docs/FIRMWARE.md` §9). Already written and
  tested: `SerialTransport.open("/dev/ttyACM0")` (macOS `/dev/cu.usbmodem…`, Windows `COMx`)
  opens it with pyserial; `send` writes `uart_encode(frame)` and `recv` feeds bytes into
  `UartDecoder` until a frame comes out. A pulled cable is `Disconnected`, so the next sync
  resumes. Use it like the loopback:

  ```python
  from eagle_host.protocol import SerialTransport
  link = SerialTransport.open("/dev/ttyACM0")
  report = SyncClient(link, key, Path("data")).sync()
  link.close()
  ```

  The baud rate is ignored by CDC (it matters only on a bench UART). `secure_link = True` (physical
  access is required).

The simulator's `handle(frame) -> [frames]` is the state machine the firmware implements.
The tests double as its acceptance tests: point a real transport at a dev board and the same
client logic has to pass.

What the simulator does **not** model: the encryption is one-shot here, while the firmware
must stream it (AES-GCM is incremental, so the output is byte-identical); there is no SD
latency or wear, no concurrent recording during sync, no BLE timing, and Opus is only used if
`opuslib` is present. Its store is a byte-capacity dict, not the firmware's raw ring of 256 KiB
slots with a commit table (FIRMWARE.md §8): an ACK removes the chunk at once, and the ring
drops the oldest stored (so un-ACKed) chunk, counting it in `dropped`.
