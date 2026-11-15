# Eagle Capsule - Firmware Architecture

Target: Seeed XIAO nRF52840 Sense (nRF52840: 64 MHz Cortex-M4F, 1 MB flash,
256 KB RAM, 2 MB external QSPI NOR on the board) on Zephyr / nRF Connect SDK.
The Zephyr board target is `xiao_ble/nrf52840/sense`.

Related docs:

- [`WIRING.md`](WIRING.md): pins, power, the switch, the LED and the pogo connector.
  Pin names below refer to it.
- [`SYNC-PROTOCOL.md`](SYNC-PROTOCOL.md): the chunk format, list/fetch/ack, time-set,
  and the on-device X25519 + AES-GCM encryption. **This document treats a chunk's
  ciphertext as opaque.** It only says where the encryption runs and what it costs.
- `tools/feasibility.py`: the power, storage and sync-time model. Numbers here are
  consistent with it unless noted.

> **Reconciled with [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md) (the source of truth for the chunk format and crypto, backed by the tested host code):**
> - **Encryption** is a fresh X25519 key per chunk → HKDF → AES-256-GCM. The CC310 accelerates X25519, SHA-256, the random number generator and ChaCha20-Poly1305, but has **no GCM**. AES-256-GCM in software costs <1% CPU at these rates. ChaCha20-Poly1305 is reserved as a hardware-accelerated alternative algorithm.
> - **Chunk layout:** the header is written first and the end-of-chunk fields go in a trailer, so the device streams encrypt-and-hash and never holds a chunk in RAM.
> - **Power-cut loss:** to lose ≤4 KB instead of a whole chunk, seal each chunk in ~4 KB authenticated segments. This is an open item in SYNC-PROTOCOL.md, to be done before the firmware is frozen.
> - **The on-SD layout (raw ring, section 8) is internal to the device.** The protocol only sees chunk sequence numbers, so the raw ring and the protocol are compatible.
> - **The time-quality, end-time and privacy-marker fields** live in the chunk header's flags/reserved bytes. SYNC-PROTOCOL.md is to be extended when the firmware milestone M8 lands.


Anything marked **ESTIMATE** must be replaced with a bench measurement
(section 11) before we rely on it.

---

## 1. Design rules

1. **Recording never stops for anything but the privacy switch or a flat battery.**
   Sync, BLE, IMU, LEDs and charging are all lower priority than the audio path.
2. **Everything on the card is ciphertext.** The device encrypts to the owner's
   PC public key. It cannot decrypt its own history, so a lost or stolen capsule
   leaks nothing.
3. **Power-loss safe by construction.** At most the chunk currently being written is
   lost on a brownout or crash. Committed chunks are never corrupted.
4. **Sealed case:** every update, recovery and diagnostic path works over BLE or the
   dock UART. SWD is used once, before sealing.
5. **Small modules with host tests.** Each module (ring storage, chunker, time base,
   VAD stats) builds and runs under `native_sim` with a RAM disk, so an AI agent can
   write and verify it without hardware.

---

## 2. Toolchain and versions

- Start on **NCS v2.7.0**, the version Omi's DevKit firmware builds on, so the
  Omi code we reuse (section 10) compiles unchanged. Pin the version in a
  `west.yml` manifest. Move to a newer NCS only as a dedicated milestone.
- Bluetooth: the SoftDevice Controller (NCS default) plus the Zephyr host,
  peripheral role only, one connection, one bond.
- Out of the box the XIAO runs the **Adafruit UF2 bootloader** with Zephyr's
  `nrf52840_partition_uf2_sdv7` layout: 156 KB is reserved for a SoftDevice that Zephyr
  doesn't use, the app gets 788 KB, the UF2 bootloader takes 48 KB, and there is no OTA. We replace it
  with MCUboot over SWD once (section 9).

---

## 3. Audio pipeline and threads

```
 PDM mic (P1.00 clk / P0.16 data, power P1.10)
   |  EasyDMA, 2 x 100 ms buffers (1600 samples x int16), 16 kHz mono
   v
 [PDM IRQ, prio 5]  -- memcpy -->  PCM ring (0.5 s, 16 KB)
                                        |
                                        v
 [codec thread, prio 2, preemptive]  Opus encode, 1 frame per 10 or 20 ms
   |  + per-frame energy stats (VAD metadata, section 6)
   v
 encoded-frame queue (16 KB, about 5 s at 24 kbps)
   |
   v
 [storage thread, prio 4]  pack frames -> 4 KB pages -> AES-256-GCM (software; CC310 has no GCM)
   |                       -> double-buffered 4 KB writes -> raw ring on SD (section 8)
   |                       -> chunk commit (header written last)
   v
 microSD over SPI2 @ 8 MHz
                                  [sync thread, prio 6]  list/fetch/ack over
                                     BLE GATT or the dock UART (SYNC-PROTOCOL.md);
                                     reads committed chunks only
 [supervisor thread, prio 8]  watchdog feeding, battery/charger, dock state,
                              privacy switch, LED, IMU state, time base persistence
 BT controller (MPSL/SDC) runs at ISR/zero-latency priority; BT host RX/TX threads at defaults.
```

Why it is shaped this way:

- **PDM:** 1.28 MHz clock, ratio 80 → 16 kHz, gain from Omi's tuned config (`MIC_GAIN 64`).
  The IRQ only copies into the ring. The 100 ms DMA blocks match Omi's `mic.c`.
- **Codec thread** has the highest app priority. If it starves, audio is lost.
  The PCM ring of 0.5 s covers BLE connection events and flash erase stalls.
- **Opus settings (start):** Omi's proven setup: `OPUS_APPLICATION_RESTRICTED_LOWDELAY`
  (CELT only), complexity 3, VBR, 16 kHz mono, `SIGNAL_VOICE`. Two deliberate
  changes to evaluate on the bench:
  - **Bitrate 24 kbps** instead of Omi's 32 kbps. At 32 kbps, a full day is
    346 MB and syncs in 2.4 h at 40 KB/s, or **6.4 h at 15 KB/s** (the
    Windows-BLE worst case in `feasibility.py`), which nearly fills the dock
    window. 24 kbps cuts that by 25%. Choose the final value by Whisper word
    error rate on our own recordings at 16/24/32 kbps. Note that `feasibility.py`
    currently assumes 16 kbps.
  - **20 ms frames** instead of 10 ms. Latency doesn't matter for storage, and 20 ms CELT
    frames give better quality per bit and halve per-frame overhead (TOC byte,
    length prefix).
- **The storage thread is not real-time.** SD cards stall for 100-500 ms (rarely more)
  during internal garbage collection. That stall is absorbed by the 16 KB encoded
  queue (about 5 s at 24 kbps), not by the PCM ring.
- **Encryption runs in the storage thread** on 4 KB pages using the nRF52840
  CryptoCell-310 AES engine through PSA Crypto. At about 3 KB/s of audio, the cost is
  negligible. X25519 runs once per chunk (a fresh ephemeral key per chunk, as SYNC-PROTOCOL.md
  defines) and takes a few ms in software. **ESTIMATE**: measure in M8.

### CPU load (ESTIMATE until M5)

| Work | Load on a 64 MHz M4F |
|---|---|
| Opus CELT encode, 16 kHz mono, complexity 3, fixed point with Omi's ARM EDSP flags | **~15-30%**: about 10-20 MCPS. Omi already runs it in real time *plus* live BLE streaming, so it fits. |
| PDM IRQ copy, ring management | < 1% |
| AES-256-GCM in software, 3 KB/s | < 1% |
| SPI SD writes (EasyDMA, 4 KB every ~1.4 s) | < 1% CPU; the DMA does the transfer |
| BLE sync (host stack) while docked | 5-15% during transfers |
| Total while worn | ~20-35%, which is where the 1.2-2.5 mA CPU line in `feasibility.py` comes from |

How to measure it: wrap `opus_encode()` with `k_cycle_get_32()` and log the
mean and max cycles per frame. Toggle a spare GPIO (D2) around it and watch
it on the PPK2's digital channel together with current.

---

## 4. Memory budgets

### RAM: 256 KB

| Item | KB | Notes |
|---|---|---|
| BLE controller + host (1 conn, DLE 251, MTU ~247-498) | 30-40 | Omi's `BT_BUF_ACL_TX_SIZE=2048` with many buffers is oversized for us; tune it in M12. |
| PDM DMA buffers 2 × 1600 × int16 | 6.4 | Same as Omi. |
| PCM ring (0.5 s) | 16 | Omi uses 1 s (32 KB). We halve it. |
| Opus encoder state (CELT) | 7.2 | `OPUS_ENCODER_SIZE 7180` in Omi's `codec.c` (hybrid mode would need 10.9). |
| Codec thread stack | 16-24 | Omi allocates **32 KB**. Opus uses the stack for scratch. Measure the high-water mark with `CONFIG_THREAD_ANALYZER` and trim. |
| Encoded-frame queue | 16 | Absorbs SD stalls. |
| Storage page buffers (2 × 4 KB) + GCM context | 9 | |
| Sync read/transmit buffers | 4-8 | |
| PSA crypto / mbedTLS heap | 8-16 | |
| Other stacks (main, storage, sync, supervisor, sysworkq, BT RX, ISR, idle) | ~24 | |
| mcumgr / SMP buffers | 4-6 | |
| Kernel, drivers, settings/NVS cache, misc | ~8 | |
| USB CDC console (bench builds only) | 0 / 8 | Off in production. |
| **Total** | **~150-185** | **~70-100 KB headroom.** RAM is not a risk. |

### Flash: 1 MB internal + 2 MB QSPI

Measure with `west build -t rom_report`. These figures are **ESTIMATES** for a
`-Os` build with logging off:

| Component | KB |
|---|---|
| Zephyr kernel, drivers (GPIO, SPI, UART, ADC, I2C, WDT, PDM, QSPI) | 30-40 |
| BLE host + SoftDevice Controller (peripheral only) | 120-160 |
| **Opus 1.2.1 fixed-point encoder** (Omi compiles the CELT and SILK sources; dropping SILK files we never call saves some) | **80-160** |
| PSA crypto: AES-256-GCM (software; CC310 has no GCM), X25519, SHA-256/HKDF | 30-60 |
| mcumgr / SMP (image + OS groups, BT + UART transports) | 25-40 |
| disk_access + SD over SPI + raw ring (FATFS would add ~25) | 15-25 |
| Sensors, settings/NVS, app logic | 35-65 |
| **App total** | **~335-550** |

Layout decision:

- **Both MCUboot slots in internal flash** gives (1024 − 48 MCUboot − 32 NVS) / 2 ≈ **472 KB
  per slot**, which is *below* the high estimate. That is a real risk.
- **Recommended:** put the **secondary slot on the onboard 2 MB QSPI NOR (P25Q16H)**
  (`CONFIG_PM_EXTERNAL_FLASH_MCUBOOT_SECONDARY` in NCS). The primary slot becomes about
  **940 KB**, and the rest of the QSPI chip (about 1 MB) is free for a crash log.
  MCUboot then needs the QSPI driver (+~8-16 KB to its size). Keep the QSPI chip in
  deep power-down (`has-dpd`) when idle, or it adds standby current.

---

## 5. Power, charging and dock state

### States

| State | Entered when | Audio | Radio | Notes |
|---|---|---|---|---|
| WORN | VBUS absent, IMU shows motion within the last N min | recording | BLE off, or very slow advertising | the normal day |
| STILL | VBUS absent, no motion for > 10 min | recording, tagged `still` | as WORN | probably left on a table; optionally drop to a lower bitrate |
| DOCKED | `USBDETECTED` (VBUS present) | recording (sleep audio), tagged `docked` | advertising + sync, UART enabled | charging at 100 mA |
| PRIVACY | switch D5 HIGH | **mic unpowered (P1.10 LOW), PDM stopped** | unchanged | chunk closed with a `privacy_start` marker |
| LOW_BATT | VBAT < 3.50 V off dock | recording | radio off | LED warning |
| OFF | VBAT < 3.40 V, or a "storage mode" command | none | none | close the chunk, persist state, **System OFF**; wakes on VBUS (USB detect) or the D5 GPIO |

### Dock detection via VBUS

The XIAO's 5V pin is the nRF52840's VBUS (WIRING.md section 3), so the POWER peripheral
raises `USBDETECTED` / `USBREMOVED` with nothing extra wired. Use
`nrfx_power` USB events, or poll `nrf_power_usbregstatus_vbusdet_get()` from the
supervisor. Debounce for 500 ms, because pogo contacts bounce as the magnet seats.
On dock: drive P0.13 LOW, enable `uart0` on D6/D7, start advertising.
On undock: disable `uart0` and set D6/D7 to disconnected inputs (no driven voltage on
exposed contacts), stop advertising.
A dock and a PC USB cable look the same on VBUS. If that matters, tell them apart by
whether USB enumeration happens or the dock bridge answers on UART.

### Charging with no power path (BQ25101)

The BQ25101 charges the battery node, and the whole system runs from that same
node. Consequences and rules:

1. **Charge at 100 mA (P0.13 LOW) whenever docked.** At 50 mA, the 10% termination
   threshold is 5 mA, which is close to the 3-4 mA recording load. Termination might
   then not happen until the radio goes quiet.
2. **Termination vs. sync load.** The charger sees battery current *plus* system
   current. If the system draws more than 10 mA (10% of 100 mA) once the cell is
   full, as it can during a BLE bulk sync at +8 dBm, the charger never sees
   termination and sits in CV until the **10 h safety timer** expires.
   Mitigation: **sync first, then let it top off.** Sync starts right after docking,
   while the charger is still in CC. Use **0 dBm TX on the dock** (the PC is close;
   6.4 mA vs 16.4 mA peak at +8 dBm). Use long connection intervals
   once the bulk transfer is done.
3. **Timer budget.** About 55 mAh used per 16 h day (`feasibility.py`) refills in well
   under 2 h at 100 mA, far inside the 10 h fast-charge timer (which is extended
   during DPM/thermal regulation). The precharge timer (30 min) only matters for
   a deeply flat cell.
4. **Recharge cycling.** After termination, the recording load drains the cell until the
   BQ25101 recharge threshold restarts charging. That is normal and gentle.
5. **The VBAT reading is wrong while charging.** Read the ADC when `/CHG` (P0.17) is
   high, or apply a measured offset. **Never set P0.14 HIGH** (WIRING.md).

### Battery measurement

SAADC on AIN7 (P0.31), internal reference, gain 1/6, 12-bit, oversampling 8,
acquisition time ≥ 40 µs. Read every 60 s. Map to a percentage with a LiPo discharge
curve table measured on our cell (M16).

### Time base

- **Monotonic clock:** RTC1 (Zephyr kernel ticks) from the 32.768 kHz LFXO.
  **VERIFY** that the XIAO fits the crystal (Zephyr's `xiao_ble` defconfig uses
  the crystal source), ±20 ppm ≈ ±1.7 s/day.
- **Wall clock:** `unix_ms = anchor_unix_ms + (uptime_ms − anchor_uptime_ms)`.
  The PC sets the anchor on every sync (the time-set message is in SYNC-PROTOCOL.md).
  The PC can also correct drift after the fact by interpolating between two
  consecutive anchors.
- **Survive resets:** keep the anchor, `boot_id`, and a last-seen uptime in a
  **`__noinit` RAM block with a CRC**. nRF52 RAM is retained through watchdog and
  soft resets, but not through a power-on reset or brownout. Also persist the
  anchor to NVS on every time-set. On boot:
  valid retained block → time continues, quality `derived`;
  NVS only → time unknown until the next sync, quality `unknown`, and the PC fixes it
  afterwards using `boot_id` + uptime.
- Every chunk header carries `boot_id`, `uptime_ms` at start and end, the wall-clock
  estimate and its quality flag (field layout in SYNC-PROTOCOL.md).

---

## 6. VAD: store everything, VAD on the server

| Option | Pros | Cons |
|---|---|---|
| **A. No device VAD; store everything** (recommended) | No lost speech onsets, whispers, or quiet sleep-talk and snoring, which an energy gate will clip. Silero VAD on the PC is far better than anything that fits here, and it can be re-run when the models improve. No tuning in the field. | More storage and sync time. That is cheap: 32 GB holds about **120 days at 24 kbps**. |
| B. Energy VAD gates recording on the device | Less data and less sync time | Irreversible: dropped audio is gone. Thresholds depend on noise floor, clothing rub and the dock environment. |
| C. Opus DTX | Built into Opus | Mostly effective in SILK/VOIP mode. With CELT-only restricted-low-delay in Opus 1.2.1, its benefit is doubtful. **VERIFY** before relying on it. |

**Decision: A, plus cheap device-side metadata.** The codec thread computes,
per frame, RMS energy and a running noise-floor estimate (minimum tracker with
slow rise). It writes per-chunk summaries into the chunk header: speech-likely
fraction, peak level and noise floor. The PC can then
**prioritise fetching speech-heavy chunks first** and run Silero on everything later.
An optional later step: drop to 8-12 kbps after more than 30 s of deep silence
(reversible, audio kept), never a gate.

---

## 7. IMU (LSM6DS3TR-C)

- **Power hygiene first:** Zephyr powers the IMU at boot (`regulator-boot-on` on
  P1.08). If it is left in its default/active configuration, it costs about 1 mA.
  Either cut P1.08, or configure it right away.
- **Use it in accel-only low-power mode** at 12.5-26 Hz with the gyro powered down. The
  embedded **wake-up** (motion threshold) function goes to INT1 (P0.11), and
  optionally the 6D orientation event. Expected current: tens of µA. **VERIFY** with
  the ST datasheet and the PPK2.
- Zephyr's `st,lsm6dsl` driver (which the board DTS uses, register-compatible enough
  for basic reads) doesn't expose low-power mode or wake-up configuration. Write a small
  register-level helper over `i2c_write_read_dt()` for those. Omi's DK2 config
  ships with the accelerometer disabled.
- **What it's used for:** WORN vs STILL detection (section 5), chunk tags so the PC
  can tell "worn conversation" from "on the desk", and an optional bitrate drop when
  STILL. **Dock detection uses VBUS, not the IMU.** VBUS is authoritative.
- Fallback: if the IMU ever proves too costly, cut P1.08 and use the audio
  noise-floor stats alone to separate worn from still.

---

## 8. SD storage: raw ring, not FAT

### Why not FAT/exFAT (what Omi does)

Omi opens, appends and closes a file per write (`sdcard.c`). Every append updates
the FAT and the directory entry, which means:

- Power loss mid-update can corrupt the filesystem, not just the last data.
- Write amplification: several small metadata writes for each data write.
- More code (about 25 KB) and RAM.

The only benefit, reading the card in a PC, doesn't apply to a sealed device with
encrypted content.
Keep FAT only for the Omi bench test (M1).

### Layout (raw LBAs via Zephyr `disk_access_*` on the `SD` disk)

```
 LBA 0      Superblock A  (magic, layout version, device id, slot size, slot count, format UUID, CRC)
 LBA 8      Superblock B  (identical copy)
 LBA 16..   Metadata log  (e.g. 256 x 4 KB records; each: seq, ack watermark,
                           head hint, counters, CRC; newest valid record wins)
 LBA M..    Data slots    (N fixed-size slots, e.g. 64 KiB = 128 sectors each)
            slot = [header sector][page 1]...[page k]   (k <= 127)
```

- **One chunk per slot.** Slot size is matched to the chunk size in
  SYNC-PROTOCOL.md. 64 KiB is about 22 s at 24 kbps, so a brownout loses at most about 22 s.
- **Commit protocol:** write the payload pages first, as 4 KB aligned multi-block writes,
  then the **header sector last** (sequence number, length, timestamps, VAD stats,
  CRC). A slot whose header has a valid CRC and a higher sequence number than the
  previous one is committed. Otherwise it is free or torn.
- **Early close:** the chunk is closed short (with the header recording the actual length)
  on privacy, dock/undock, low battery and a time-set, so state changes are chunk
  boundaries.
- **Boot recovery:** read the newest metadata record → scan forward from the
  head hint until the sequence breaks → that is the head. A torn slot just after
  the head is logged as a gap event. This is O(few slots), not a full-card scan.
- **Acks** advance a watermark in the metadata log. Headers are never rewritten to
  mark them acked.
- **When full:** overwrite the oldest slot even if it isn't acked (recording wins),
  increment `overwritten_unacked`, and report it in the next sync.
- **Wear:** at 24 kbps, about 260 MB/day on 32 GB means each LBA is written about 3 times a year.
  Wear is not a concern, but use a **high-endurance/industrial microSD**: those
  handle sudden power loss better.
- **Testing:** the ring module runs under `native_sim` against Zephyr's RAM disk,
  with a fault injector that "cuts power" after random sector writes (M6).

### SPI

`spi2` at **8 MHz**. That is the SPIM0-2 maximum; Omi's 24 MHz request is silently
clamped (WIRING.md section 1). That gives about 1 MB/s raw, while recording needs
about 3 KB/s and sync reads need at most about 90 KB/s. The card stays in SPI idle between
writes. The optional D4 load switch can power-cycle it if bench measurement shows
high idle current (0.1-1 mA, varying by card brand).

---

## 9. Reliability: watchdog, OTA DFU, recovery

### Watchdog

- nRF52840 WDT with an **8 s** timeout, running during sleep, paused while halted by the
  debugger.
- **Only the supervisor feeds it**, and only when every critical thread has checked
  in within its own deadline: codec 1 s, storage 3 s (SD stalls), sync 10 s
  (only while a session is active).
- A **reset counter in `__noinit` RAM**: 3 resets within 10 min → **safe mode**,
  in which recording continues with the minimal pipeline (IMU off, no VAD stats),
  SMP/DFU stays available, and the event is reported at the next sync.
- Log `RESETREAS` and the last thread that missed its deadline into an event chunk.

### OTA DFU (the case is sealed)

1. **One time, before sealing:** connect SWD (pads under the XIAO) with a J-Link,
   an nRF52 DK's debug-out, or a CMSIS-DAP probe. Erase the chip, which removes the
   UF2 bootloader. Flash **MCUboot**, plus the app, with the secondary slot on QSPI (section 4).
2. **Signed images:** an ECDSA-P256 or Ed25519 key that lives on the owner's PC,
   **never in the repo**. MCUboot rejects anything unsigned.
3. **Swap with revert:** a new image boots as "test". The app confirms it
   (`boot_write_img_confirmed()`) only after a self-test: PDM produces non-silent
   samples, an SD write/read round-trip succeeds, and BLE is up. If it never confirms, the
   next reset (watchdog) reverts to the old image.
4. **Transports:** mcumgr SMP over **BLE**, requiring a bonded and encrypted link
   (`CONFIG_MCUMGR_TRANSPORT_BT_AUTHEN`), and over the **dock UART**. On the PC, use
   `smpmgr` / `smpclient` (Python, built on bleak) or the `mcumgr` CLI.
5. **Last-resort rescue:** MCUboot **serial recovery on the dock UART**
   (`CONFIG_BOOT_SERIAL_UART` + `CONFIG_BOOT_SERIAL_WAIT_FOR_DFU`, ~500 ms
   window at every boot). A bricked app that still watchdog-resets can be
   re-flashed from the dock without opening the case.
6. Enable `CONFIG_BT_PRIVACY` (resolvable private addresses) so the capsule can't
   be tracked by its BLE address. Advertise only when docked, or on demand.

---

## 10. What to reuse from Omi (MIT) vs. write fresh

Omi devkit sources: `omi/firmware/devkit/` (repo root is MIT; per-folder terms
checked). Keep their copyright notices in reused files and credit them in
`CREDITS.md`, which another commit will update.

| Omi file | Verdict | Why |
|---|---|---|
| `src/mic.c` (nrfx PDM, a port of Seeed's Arduino mic code) | **Reuse**, lightly adapted | Proven PDM config, gain, IRQ wiring, mic power on P1.10. Add start/stop for privacy. |
| `src/codec.c` + `src/lib/opus-1.2.1/` + the CMake flags (`OPUS_ARM_*` EDSP) | **Reuse** | The Opus build is the hardest part to get right on Zephyr. Change: 20 ms frames, bitrate, a smaller stack after measuring, and the VAD stats hook. |
| `src/config.h` | Reuse as a reference | Pin and codec constants. |
| `overlay/xiao_ble_sense_devkitv2-adafruit.overlay`, `prj_*.conf` | **Reuse for M1 only** | Our wiring matches its SPI and CS pins. Our own overlay drops I2S, sets 8 MHz SPI, and adds `uart0`. |
| `src/button.c` | Borrow the debounce pattern only | Our D5 is a 2-state switch, not a tap button. |
| `src/transport.c` (battery ADC) | Borrow the ADC setup | We add the P0.14 rule and charge awareness. |
| `src/sdcard.c`, `src/storage.c` | **Replace** | FAT file-per-session and an unencrypted, Omi-specific BLE storage protocol. Ours is the raw ring + SYNC-PROTOCOL.md. |
| `src/transport.c` (BLE audio streaming) | **Replace** | We don't stream live. |
| `src/speaker.c`, haptic, NFC, `usb.c` | Drop | Not in our hardware. |
| `src/wdog_facade.c` | Read it, then write our own | Our watchdog policy is check-in based. |
| `scripts/devkit/sdcard_test_files/decode_audio.py` | **Reuse on the PC** for bench decoding of raw Opus frames (M5) | |

**Write fresh:** raw ring storage, the chunker + encryption (to SYNC-PROTOCOL.md),
the sync service, the time base, the supervisor/watchdog, power/charge/dock
management, the IMU low-power helper, the MCUboot/partition setup, and host tests.

---

## 11. Bench bring-up test plan

Do these in order. Each step is a small separate test app (or a shell command in a
bench build with the USB CDC console). Don't move on until a step passes.

| # | Test | Pass criteria |
|---|---|---|
| T0 | Bare XIAO, blinky over UF2, USB CDC log | Builds and runs on `xiao_ble/nrf52840/sense`. |
| T1 | **Power hygiene + baseline:** IMU off (P1.08 LOW), mic off, LEDs off, P0.14 LOW, System ON idle | Record the µA on the **PPK2 in source-meter mode at 3.8 V into the BAT pads**, USB unplugged. This is the floor every later number is compared to. |
| T2 | Back-feed check: battery only, measure the 5V pin to GND | About 0 V (WIRING.md section 3). |
| T3 | Charger: dock with P0.13 LOW, then HIGH-Z; ammeter in series with the battery | About 100 mA / 50 mA in CC; `/CHG` (P0.17) LOW while charging. |
| T4 | VBAT ADC (P0.14 LOW, AIN7) vs a multimeter at the BAT pads | Within ±30 mV when not charging. |
| T5 | VBUS events: dock and undock 20 times | Every transition is seen, debounced, with no spurious events. |
| T6 | PDM alone: 10 s of PCM to RAM, dumped over CDC | Clean audio at a sensible level. Note the current delta. |
| T7 | Opus alone: encode the recorded PCM; cycles per frame; stack high-water | Real time with ≥ 2× margin. Decodes on the PC with `decode_audio.py` / `opusdec`. |
| T8 | SD alone at 8 MHz: init, CD pin, 4 KB raw write/read patterns, **1 h write-latency histogram** | No errors. The worst-case latency sets the encoded-queue size. Note idle current with the card in. |
| T9 | IMU alone: WHO_AM_I, accel low-power, wake interrupt on P0.11 | The interrupt fires on a tap. Current matches the datasheet (tens of µA). |
| T10 | Switch (D5) and LED (D3) | Both positions read correctly, with zero static current in either. |
| T11 | UART over the pogo pins with the dock bridge at 1 Mbaud | Loopback with no errors. Pins high-Z when undocked. |
| T12 | BLE: bond with the PC, bulk-throughput test with bleak | Measured KB/s. Put it into `feasibility.py` (`BLE_KBYTES_S`). |
| T13 | Crypto: AES-256-GCM in software and ChaCha20-Poly1305 on CC310 (KB/s) and X25519 timing | Within budget (section 3). |
| T14 | Omi DK2 firmware unmodified on our wiring (switch on "record") | SD files appear, so the SPI/CS wiring is proven. |
| T15 | Full pipeline, 24 h soak | No gaps, no resets, chunks decrypt and decode on the PC. |
| T16 | **Current profile with the PPK2** over 10 min each: WORN-recording, PRIVACY, DOCKED+sync | Compare against `feasibility.py`. Replace the ESTIMATE lines with measured values. |
| T17 | Fault injection: 100 random power cuts during writes; a forced thread hang; a bad DFU image | The ring always recovers with at most one torn slot; the watchdog resets with time carried over; the DFU reverts. |

**Multimeter vs PPK2:** a multimeter in series works for steady currents (charger
CC current, a mA-level average), but its µA-range burden voltage can brown out the
board on SD/radio peaks, and its averaging misses ms-scale bursts. Use the **PPK2**
for anything averaged or sleep-level. Run it in source-meter mode at 3.7-3.8 V on the BAT
pads with the cell removed, and use ampere-meter mode for docked charging tests.

---

## 12. Milestones (each is one small, AI-codeable PR)

Each milestone has a host test (`native_sim`/`ztest`) where possible, and a bench
check from section 11.

| M | Deliverable | Done when |
|---|---|---|
| M0 | West workspace pinned to NCS v2.7.0, CI build for `xiao_ble/nrf52840/sense` | T0 |
| M1 | Omi DK2 firmware built and run on our wiring (no code changes) | T14 |
| M2 | `boards/` overlay for Eagle Capsule pins + a power-hygiene init module | T1, T2 |
| M3 | Power module: VBAT ADC, P0.13 control, `/CHG`, VBUS events | T3, T4, T5 |
| M4 | **MCUboot via SWD + QSPI secondary slot + signed images + SMP over USB CDC** (all later work uses the final layout) | Upload/confirm/revert works on the bench. |
| M5 | Mic + codec modules (ported from Omi), CPU/stack measured | T6, T7 |
| M6 | Raw ring storage module + `native_sim` RAM-disk tests + power-cut fault injector | Host tests pass, then T8 |
| M7 | Pipeline PDM → Opus → plaintext chunks → ring | 1 h of audio decodes on the PC. |
| M8 | Encryption per SYNC-PROTOCOL.md (PSA; X25519/SHA-256 on CC310) + shared test vectors with the PC tool | The PC decrypts device chunks. T13 |
| M9 | Time base (anchor, `__noinit` retention, NVS, chunk timestamps) | Time survives a watchdog reset. |
| M10 | Supervisor + watchdog check-ins + crash-loop safe mode | T17 (hang part) |
| M11 | Privacy switch + mic power gating + LED | T10. The mic draws 0 mA in privacy. |
| M12 | BLE sync service (list/fetch/ack) per SYNC-PROTOCOL.md + PC bleak client | T12. A full day syncs within the dock window. |
| M13 | Dock: VBUS state machine, UART transport (sync + SMP), charge-rate rules | T11. Charging terminates after a sync. |
| M14 | IMU low-power helper + WORN/STILL state + chunk tags | T9 |
| M15 | VAD stats in chunk headers + PC-side fetch prioritisation | Speech-heavy chunks are fetched first. |
| M16 | LOW_BATT / System OFF / storage mode, battery curve, power optimisation pass | T16 meets the `feasibility.py` budget. |
| M17 | MCUboot serial recovery on the dock UART + BLE SMP with bonded auth | Rescue a deliberately bricked app from the dock. |
| M18 | **Seal**: 72 h soak, T17 fault-injection, an over-the-air DFU on the sealed unit | All pass. |

---

## 13. Feasibility risks found

1. **Flash:** with both MCUboot slots internal, about 472 KB per slot is below the
   high-end app estimate (BLE + Opus + crypto + SMP). **Mitigation:** put the secondary
   slot on the onboard QSPI flash.
2. **The stock UF2 bootloader means no OTA.** MCUboot needs a **one-time SWD flash**
   before sealing.
3. **Charge termination vs. sync load** (no power-path): a sync drawing more than 10 mA
   while full can stop termination until the 10 h timer runs out. **Mitigation:** sync early,
   0 dBm, 100 mA charge.
4. **Sync time at 32 kbps** over Windows BLE (about 6.4 h worst case). **Mitigation:**
   24 kbps, the dock UART, and VAD-prioritised fetch.
5. **Omi's 24 MHz SPI request is really 8 MHz** (SPIM2). That is harmless, but don't plan on more.
6. **The IMU is powered at boot** by the Zephyr board DTS, which costs about 1 mA unless it is handled.
7. **Pin overlap with Omi DK2 firmware** (I2S on D1-D3, D5 long-press = power off).
   Bench only; mitigated with a series resistor on CD and the switch semantics.

---

## Sources

- BasedHardware/omi, `omi/firmware/devkit/` (commit 2e2a0b3, Oct 2025):
  `src/config.h`, `src/codec.c` (Opus CELT, complexity 3, VBR, 32 kbps, 10 ms,
  `OPUS_ENCODER_SIZE 7180`, 32 KB codec stack), `src/mic.c`, `src/sdcard.c`,
  `src/storage.c`, `src/button.c`, `src/transport.c`,
  `overlay/xiao_ble_sense_devkitv2-adafruit.overlay`,
  `prj_xiao_ble_sense_devkitv2-adafruit.conf`, and the Omi docs on DevKit charging.
  <https://github.com/BasedHardware/omi>
- Seeed Studio XIAO nRF52840 (Sense) wiki and schematic: <https://wiki.seeedstudio.com/XIAO_BLE/>
- Zephyr: board `boards/seeed/xiao_ble/`, `dts/vendor/nordic/nrf52840_partition_uf2_sdv7.dtsi`,
  disk access / SDMMC-over-SPI, the RAM disk, `native_sim`, the thread analyzer, mcumgr/SMP.
  <https://docs.zephyrproject.org/latest/services/device_mgmt/mcumgr.html>
- Nordic: nRF52840 Product Specification (SPIM, POWER/USBREG, WDT, CC310, SAADC),
  nRF52840 errata (anomaly 198), and nRF Connect SDK docs (partition manager, external
  flash MCUboot secondary slot, SoftDevice Controller, PSA crypto).
  <https://docs.nordicsemi.com/bundle/ps_nrf52840/page/keyfeatures_html5.html>,
  <https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/index.html>
- MCUboot: <https://docs.mcuboot.com/>
- Texas Instruments BQ25101 datasheet: <https://www.ti.com/lit/ds/symlink/bq25101.pdf>
- Opus codec (Xiph.Org): <https://opus-codec.org/docs/>
