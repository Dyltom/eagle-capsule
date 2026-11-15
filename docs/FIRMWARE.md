# Eagle Capsule - Firmware Architecture

Target: Seeed XIAO nRF52840 Sense (nRF52840: 64 MHz Cortex-M4F, 1 MB flash,
256 KB RAM, 2 MB external QSPI NOR on the board) on Zephyr / nRF Connect SDK.
The Zephyr board target is `xiao_ble/nrf52840/sense`.

Related docs:

- [`WIRING.md`](WIRING.md): pins, power, the mic board, the switch, the LED and the
  USB-C port. Pin names below refer to it.
- [`SYNC-PROTOCOL.md`](SYNC-PROTOCOL.md): the chunk format, list/fetch/ack, time-set,
  and the on-device X25519 + AES-GCM encryption. **This document treats a chunk's
  ciphertext as opaque.** It only says where the encryption runs and what it costs.
- `tools/feasibility.py`: the power, storage and sync-time model. Numbers here are
  consistent with it unless noted.

> **Reconciled with [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md) (the source of truth for the chunk format and crypto, backed by the tested host code):**
> - **Encryption** is a fresh X25519 key per chunk → HKDF → AES-256-GCM. The CC310 accelerates X25519, SHA-256/HMAC and the random number generator. It has **no AES-256 and no GCM** (128-bit AES keys only), so AES-256-GCM runs in software, at <1% CPU at these rates. ChaCha20-Poly1305 (`alg = 2`) is reserved as an alternative; see SYNC-PROTOCOL.md §6.4 for why it is not a drop-in hardware path.
> - **Chunk layout:** one chunk = one 60 s raw-ring slot (section 8). The header is written first, audio is encrypted and hashed as it streams, the trailer and GCM tag go last, then a slot-commit record. The device never holds a chunk in RAM.
> - **Power-cut loss (decided for v1):** a chunk is sealed as a whole, so an unclean power-off loses the open chunk, **≤ 60 s**. Firmware closes the chunk early on a low-VBAT warning to make that rare. Sealing in ~4 KB segments (lose ≤ ~1.4 s) is a **v2 format** change in SYNC-PROTOCOL.md §8, not a blocker for freezing v1 firmware; the reference host does not parse segments.
> - **The on-SD layout (raw ring, section 8) is internal to the device.** The protocol only sees `seq`, size and SHA-256, so the raw ring and the protocol are compatible.
> - **Extra chunk metadata** (state tags, after-privacy marker, close reason, level stats) is **inside the ciphertext only**, never in the cleartext outer header. What v1 can carry today and what waits for v2 is defined in SYNC-PROTOCOL.md §3.


Anything marked **ESTIMATE** must be replaced with a bench measurement
(section 11) before we rely on it.

> **What changed (Nov 2026, owner decisions):** USB-C is the only charge and sync
> path. The dock UART on D6/D7 and the pogo dock are gone; **USB CDC-ACM** on the
> XIAO's own port carries the sync protocol, SMP and MCUboot serial recovery, and BLE
> stays as the wireless fallback. The mic is an external **Infineon IM73D122** (PDM
> CLK D4, DATA D6, power D2) with the onboard mic held off. The default cell is 600 mAh.

---

## 1. Design rules

1. **Recording never stops for anything but the privacy switch or a flat battery.**
   Sync, BLE, IMU, LEDs and charging are all lower priority than the audio path.
2. **Everything on the card is ciphertext.** The device encrypts to the owner's
   PC public key. It cannot decrypt its own history, so a lost or stolen capsule
   leaks nothing.
3. **Power-loss safe by construction.** At most the chunk currently being written is
   lost on a brownout or crash. Committed chunks are never corrupted.
4. **Sealed case:** every update, recovery and diagnostic path works over BLE or
   USB CDC on the capsule's USB-C port. SWD is used once, before sealing.
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
 IM73D122 PDM mic (CLK D4/P0.04 @ 1.28 MHz, DATA D6/P1.11, power D2/P0.28; onboard mic P1.10 LOW)
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
 [storage thread, prio 4]  OUTER header first, then frames -> AES-256-GCM (software) + SHA-256 (CC310)
   |                       -> double-buffered 4 KB writes into the chunk's 256 KiB slot (section 8)
   |                       -> trailer + GCM tag last -> slot-commit record (seq, size, sha256)
   v
 microSD over SPI2 @ 8 MHz
                                  [sync thread, prio 6]  list/fetch/ack over
                                     USB CDC or BLE GATT (SYNC-PROTOCOL.md);
                                     reads committed chunks only
 [supervisor thread, prio 8]  watchdog feeding, battery/charger, plug state,
                              privacy switch, LED, IMU state, time base persistence
 BT controller (MPSL/SDC) runs at ISR/zero-latency priority; BT host RX/TX threads at defaults.
```

Why it is shaped this way:

- **PDM (IM73D122):** **1.28 MHz clock, ratio 80 → 16 kHz.** Never the nRF52840 default
  of 1.032 MHz (ratio 64): the IM73D122 is not specified between 0.85 and 1.2 MHz, so its
  SNR there is unknown. 1.231, 1.28 and 1.333 MHz are inside its normal-mode range
  (1.2-1.65 MHz; 71 dB(A) is specified at 1.536 MHz, so ~70-71 dB(A) at 1.28 MHz is
  **unverified**). Use **nrfx PDM directly with the documented enums**
  (`NRF_PDM_FREQ_1280K`, `NRF_PDM_RATIO_80X`), as Omi's `mic.c` does, rather than
  Zephyr's `dmic` driver, whose prescaler search on the nRF52840 may pick another clock.
  Assert the clock in a test (T6b).
- **Gain:** the IM73D122's sensitivity is −26 dBFS, the same as the stock mic, so Omi's
  tuned `MIC_GAIN 64` carries over.
- **Power-up:** D2 HIGH, wait, start PDM, then **discard the first ~50-100 ms** of samples
  (the datasheet allows up to 50 ms for VDD ramp and start-up). This happens at boot and
  after every privacy period, so the chunk after privacy starts with a short gap.
- **Channel and edge:** the board's L/R jumper picks the channel; firmware reads that
  one (`NRF_PDM_MODE_MONO`, matching edge). Silence or noise on first power-up usually
  means the jumper and the PDM edge setting disagree: flip one before suspecting the board.
- **Current:** the IM73D122 draws ~0.7-0.9 mA at our clock and supply (690 µA typ is
  specified at 1.536 MHz/1.8 V; 3.3 V from a GPIO is higher, unverified). The stock mic's
  draw is unknown, so the net change is **+0.1-0.5 mA (unverified)**. `feasibility.py`
  carries 0.8 / 1.1 mA for the mic line (stock was 0.6 / 0.8). Measured in T6b and T16.
- **Stock-mic fallback:** a build flag switches back to the onboard mic (P1.00/P0.16,
  power P1.10) at the same 1.28 MHz/ratio 80. Keep it building so a bad mic board never
  blocks the rest of the project.
- The IRQ only copies into the ring. The 100 ms DMA blocks match Omi's `mic.c`.
- **Codec thread** has the highest app priority. If it starves, audio is lost.
  The PCM ring of 0.5 s covers BLE connection events and flash erase stalls.
- **Opus settings (start):** Omi's proven setup: `OPUS_APPLICATION_RESTRICTED_LOWDELAY`
  (CELT only), complexity 3, VBR, 16 kHz mono, `SIGNAL_VOICE`. Two deliberate
  changes to evaluate on the bench:
  - **Bitrate 24 kbps** instead of Omi's 32 kbps. A full day is 259 MB at 24 kbps
    and 346 MB at 32 kbps (`feasibility.py`). Over USB CDC (300 KB/s **ESTIMATE**, 100
    worst) that is ~14 min at 24 kbps, ~58 min at 32 kbps and the worst rate. Over BLE it
    is ~1.8 h at the unmeasured 40 KB/s estimate, but **~14 h / ~19 h at the 5 KB/s
    Boswell measured** on this board, longer than the night. That is why USB CDC is the
    primary path. 24 kbps cuts every figure by 25%. Choose the final value by Whisper word error rate on our own recordings at
    16/24/32 kbps. `feasibility.py` models 24 (typical) and 32 kbps (`--worst`).
  - **20 ms frames** instead of 10 ms. Latency doesn't matter for storage, and 20 ms CELT
    frames give better quality per bit and halve per-frame overhead (TOC byte,
    length prefix).
- **The storage thread is not real-time.** SD cards stall for 100-500 ms (rarely more)
  during internal garbage collection. That stall is absorbed by the 16 KB encoded
  queue (about 5 s at 24 kbps), not by the PCM ring.
- **Encryption runs in the storage thread**, streaming, through PSA Crypto. AES-256-GCM
  is **software** (nrf_oberon / Mbed TLS): the CC310 handles only 128-bit AES keys and has
  no GCM. At about 3 KB/s of audio that is <1% CPU. The CC310 does the SHA-256 of the
  stored bytes (for LIST) and the X25519 work: two operations per chunk (ephemeral keygen +
  ECDH, once a minute) plus one or two per sync session, a few ms each on the CC310 vs
  tens of ms in software. **ESTIMATE**: measure in M8 (T13).

### CPU load (ESTIMATE until M5)

| Work | Load on a 64 MHz M4F |
|---|---|
| Opus CELT encode, 16 kHz mono, complexity 3, fixed point with Omi's ARM EDSP flags | **~15-30%**: about 10-20 MCPS. Omi already runs it in real time *plus* live BLE streaming, so it fits. |
| PDM IRQ copy, ring management | < 1% |
| AES-256-GCM in software, 3 KB/s | < 1% |
| SPI SD writes (EasyDMA, 4 KB every ~1.4 s) | < 1% CPU; the DMA does the transfer |
| Sync while plugged in (USB CDC, or the BLE host stack) | 5-15% during transfers |
| Total while worn | ~20-35%, which is where the 1.2-2.5 mA CPU line in `feasibility.py` comes from |

How to measure it: wrap `opus_encode()` with `k_cycle_get_32()` and log the
mean and max cycles per frame. Toggle a spare GPIO (D7, if no SD load switch is
fitted) around it and watch it on the PPK2's digital channel together with current.

---

## 4. Memory budgets

### RAM: 256 KB

| Item | KB | Notes |
|---|---|---|
| BLE controller + host (1 conn, DLE 251, MTU ~247-498) | 30-40 | Omi's `BT_BUF_ACL_TX_SIZE=2048` with many buffers is oversized for us; tune it in M12. |
| PDM DMA buffers 2 × 1600 × int16 | 6.4 | Same as Omi. |
| PCM ring (0.5 s) | 16 | Omi uses 1 s (32 KB). We halve it. |
| Opus encoder state (CELT) | 7.2 | `OPUS_ENCODER_SIZE 7180` in Omi's `codec.c` (hybrid mode would need 10.9). |
| Codec thread stack | 24 | Omi allocates **32 KB**. Boswell overflowed a smaller stack and measured a **17,944 B high-water mark** for Opus on this board, so start at 24 KB. Confirm with `CONFIG_THREAD_ANALYZER` before trimming. |
| Encoded-frame queue | 16 | Absorbs SD stalls. |
| Storage page buffers (2 × 4 KB) + GCM and SHA-256 contexts | 9 | |
| Sync read/transmit buffers | 4-8 | |
| PSA crypto / mbedTLS heap | 8-16 | |
| Other stacks (main, storage, sync, supervisor, sysworkq, BT RX, ISR, idle) | ~24 | |
| mcumgr / SMP buffers | 4-6 | |
| Kernel, drivers, settings/NVS cache, misc | ~8 | |
| USB device stack + CDC-ACM (sync port + SMP port), in production | 6-10 | It is the sync path now, not a bench console. A log console, if wanted, is a third CDC interface in bench builds. |
| **Total** | **~163-191** | Sum of the lines above: low 162.6, high 190.6. **~65-93 KB headroom.** RAM is not a risk, and an optional ~14 KB per-slot ACK cache (section 8) still fits. |

### Flash: 1 MB internal + 2 MB QSPI

Measure with `west build -t rom_report`. These figures are **ESTIMATES** for a
`-Os` build with logging off:

| Component | KB |
|---|---|
| Zephyr kernel, drivers (GPIO, SPI, ADC, I2C, WDT, PDM, QSPI) | 30-40 |
| USB device stack + CDC-ACM | 15-25 |
| BLE host + SoftDevice Controller (peripheral only) | 120-160 |
| **Opus 1.2.1 fixed-point encoder** (Omi compiles the CELT and SILK sources; dropping SILK files we never call saves some) | **80-160** |
| PSA crypto: AES-256-GCM (software; CC310 has no GCM), X25519, SHA-256/HKDF | 30-60 |
| mcumgr / SMP (image + OS groups, BT + serial-over-CDC transports) | 25-40 |
| disk_access + SD over SPI + raw ring (FATFS would add ~25) | 15-25 |
| Sensors, settings/NVS, app logic | 35-65 |
| **App total** | **~350-575** |

Layout decision:

- **MCUboot size:** with the QSPI driver and **USB CDC serial recovery** (section 9) it
  probably outgrows a 48 KB partition. Budget **64 KB** (**ESTIMATE**; measure in M4).
- **Both MCUboot slots in internal flash** gives (1024 − 64 MCUboot − 32 NVS) / 2 ≈ **464 KB
  per slot**, which is *below* the high estimate. That is a real risk.
- **Recommended:** put the **secondary slot on the onboard 2 MB QSPI NOR (P25Q16H)**
  (`CONFIG_PM_EXTERNAL_FLASH_MCUBOOT_SECONDARY` in NCS). The primary slot becomes about
  **928 KB**, and the rest of the QSPI chip (about 1 MB) is free for a crash log.
  Keep the QSPI chip in deep power-down (`has-dpd`) when idle, or it adds standby current.

---

## 5. Power, charging and plug state

### States

| State | Entered when | Audio | Radio | Indicator LED (D3) | Notes |
|---|---|---|---|---|---|
| WORN | VBUS absent, IMU shows motion within the last N min | recording | BLE off; an on-demand window only after the pull gesture (below) | **on (slow blink), required** | the normal day; USB-C dust cap on |
| STILL | VBUS absent, no motion for > 10 min | recording, tagged `still` | as WORN | **on (slow blink), required** | probably left on a table; optionally drop to a lower bitrate |
| PLUGGED | `USBDETECTED` (VBUS present): the stand, a charger or the PC | recording (sleep audio on the stand), tagged `plugged` | **PC** (USB configured): sync over USB CDC (primary). **Plain charger** (no enumeration within ~5 s), or a PC that sends no HELLO within ~60 s: BLE advertises as the fallback | may be dimmed or off (configurable) | charging at 100 mA |
| PRIVACY | switch D5 HIGH | **firmware drives external mic power D2 LOW, PDM stopped; onboard mic stays off (P1.10 LOW)** | unchanged | off | open chunk closed; the next chunk is flagged `after_privacy` (SYNC-PROTOCOL.md §3) |
| LOW_BATT | VBAT < 3.50 V unplugged | recording | radio off | warning pattern (still visibly on) | |
| OFF | VBAT < 3.40 V, or a "storage mode" command | none | none | off | close the chunk, persist state, **System OFF**; wakes on VBUS (USB detect) or the D5 GPIO |

**Indicator rule:** the LED is on whenever the capsule records unplugged (WORN, STILL,
LOW_BATT). It may be dimmed or turned off only in PLUGGED (WIRING.md §5, LEGAL.md). The
supervisor drives it from the state. If the supervisor stalls, it stops feeding the
watchdog and the device resets (section 9).

**Privacy switch:** it is **firmware-enforced**. D5 is read by firmware, which stops
PDM and drives the external mic's power line (D2) LOW; the onboard mic's power (P1.10)
is LOW at all times. It is not a hardware kill (WIRING.md §4 has the DPDT upgrade path).

**On-demand BLE pull gesture.** There is no button. Flick the switch
**privacy → record → privacy → record within 3 s** (each position held ≥ 100 ms after
debounce). The supervisor then advertises for 2 min, connectable only by the bonded host,
and acknowledges with a double LED blink. Each pass through privacy really cuts the mic
and closes a chunk, so the gesture costs ~1-3 s of audio and two short chunks. An IMU
double-tap (the LSM6DS3TR-C's embedded tap detection on INT1) is the alternative if the
switch pattern proves awkward; it costs no audio but needs the accelerometer awake.

### Plug detection via VBUS, and PC vs charger

The XIAO's 5V pin is the nRF52840's VBUS (WIRING.md section 3), so the POWER peripheral
raises `USBDETECTED` / `USBREMOVED` with nothing extra wired. Use
`nrfx_power` USB events (the USB stack consumes them), or poll
`nrf_power_usbregstatus_vbusdet_get()` from the supervisor. Debounce for 500 ms
(a plug going in at an angle can make and break VBUS).

- **On plug-in:** drive P0.13 LOW (100 mA), enable the USB device stack. A charger and a
  PC look the same on VBUS; **enumeration tells them apart**. If the host configures the
  device (`USB_DC_CONFIGURED` in the NCS v2.7 legacy stack), it's a PC: the sync service
  listens on the CDC sync port for HELLO. If nothing enumerates within ~5 s, it's a plain
  charger (a BC1.2 charger shorts D+/D− and never enumerates): start the BLE fallback
  advertising. A PC that enumerates but sends no HELLO within ~60 s also gets the BLE
  fallback.
- **On unplug:** disable the USB stack, stop advertising, and turn the indicator back on.
- **VBUS current:** the charger takes up to 100 mA from VBUS, plus the USB regulator.
  That is at a USB 2.0 unit load, which a host allows before configuration. Declare
  ~150 mA in the descriptor (`CONFIG_USB_MAX_POWER=75`, 2 mA units) for margin
  (**VERIFY** that no host refuses it).

### Charging with no power path (BQ25101)

The BQ25101 charges the battery node, and the whole system runs from that same
node. Consequences and rules:

1. **Charge at 100 mA (P0.13 LOW) whenever plugged in.** At 50 mA, the 10% termination
   threshold is 5 mA, which is close to the 3-4 mA recording load. Termination might
   then not happen until the radio goes quiet.
2. **Termination vs. sync load.** The charger sees battery current *plus* system
   current. If the system draws more than 10 mA (10% of 100 mA) once the cell is
   full, as it can during a BLE bulk sync at +8 dBm, the charger never sees
   termination and sits in CV until the **10 h safety timer** expires.
   Mitigation: **sync first, then let it top off.** A USB CDC sync starts right after
   plug-in and takes ~15 min to ~1 h (**ESTIMATE**), while the charger is still in CC.
   For the BLE fallback, use **0 dBm TX** (the PC is close; 6.4 mA vs 16.4 mA peak at
   +8 dBm) and long connection intervals once the bulk transfer is done.
3. **Timer budget.** A 16 h day unplugged uses about 54 mAh typical, 126 mAh worst
   (`feasibility.py`; the mAh don't depend on the cell size), which refills in
   ~0.8-2.2 h at 100 mA, far inside the 10 h fast-charge timer (which is extended
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
- **New `boot_id` on every reset.** Every boot, including a watchdog or soft reset,
  draws a fresh `boot_id` from the TRNG, and uptime restarts at 0 with it, so
  `(boot_id, uptime_ms)` never repeats (SYNC-PROTOCOL.md §1). `boot_id` is never
  retained across a reset.
- **Time does not survive a reset in v1.** After any reset the device's UTC is unknown
  (`start_utc_ms = 0`) until the next `SET_TIME`. The host then places the new boot's
  chunks from that sync's anchor (SYNC-PROTOCOL.md §7 rule 2). Chunks are undated only
  if the device resets again before syncing. The firmware sets `start_utc_ms` only from
  a `SET_TIME` received in the **current** boot, because the v1 host trusts any non-zero
  value as device time.
- **Retained hint (optional, separate from `boot_id`):** a **`__noinit` RAM block with a
  CRC** holds `prev_boot_id`, the last anchor and a last-seen uptime. nRF52 RAM is
  retained through watchdog and soft resets, but not through a power-on reset or
  brownout. It lets a later format record "this boot followed `prev_boot_id` at roughly
  this offset" (a v2 trailer field, SYNC-PROTOCOL.md §3) so the host can bound otherwise
  undated chunks. It never re-uses the old `boot_id` and never sets `start_utc_ms`.
- Every chunk carries, inside the ciphertext, `boot_id`, `start_mono_ms`, `start_utc_ms`
  (0 = unknown) and `duration_ms`, so the end uptime is `start_mono_ms + duration_ms`
  (field layout in SYNC-PROTOCOL.md §3).

---

## 6. VAD: store everything, VAD on the server

| Option | Pros | Cons |
|---|---|---|
| **A. No device VAD; store everything** (recommended) | No lost speech onsets, whispers, or quiet sleep-talk and snoring, which an energy gate will clip. Silero VAD on the PC is far better than anything that fits here, and it can be re-run when the models improve. No tuning in the field. | More storage and sync time. That is cheap: 32 GB holds about **80 days** in fixed 256 KiB slots (section 8), whatever the bitrate. |
| B. Energy VAD gates recording on the device | Less data and less sync time | Irreversible: dropped audio is gone. Thresholds depend on noise floor, clothing rub and the bedside environment. |
| C. Opus DTX | Built into Opus | Mostly effective in SILK/VOIP mode. With CELT-only restricted-low-delay in Opus 1.2.1, its benefit is doubtful. **VERIFY** before relying on it. |

**Decision: A, plus cheap device-side metadata.** The codec thread computes,
per frame, RMS energy and a running noise-floor estimate (minimum tracker with
slow rise). v1 writes a per-second speech-likely bitmap into the encrypted trailer
(SYNC-PROTOCOL.md §3; the host turns it into `speech_ratio`). Peak level and noise
floor wait for the v2 trailer extension. All of it is inside the ciphertext, so the
device and the host see it only after decryption.
**No speech-first fetch in v1** (former M15 dropped): the VAD data is encrypted and
LIST_ITEM carries only `seq`, size and SHA-256, so the host cannot rank chunks before
fetching them, and USB CDC moves a whole day in ~15 min to ~1 h (**ESTIMATE**) anyway. The host runs
Silero on everything. An optional later step: drop to 8-12 kbps after more than 30 s of deep silence
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
  STILL. **Plug detection uses VBUS, not the IMU.** VBUS is authoritative.
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
 LBA 0      Superblock A  (magic, layout version, device_id, slot size = 256 KiB, slot count, format UUID, CRC)
 LBA 8      Superblock B  (identical copy)
 LBA 16..   Metadata log  (e.g. 256 x 4 KB records; each: head hint, lowest-unACKed hint,
                           `dropped`, next seq, CRC; newest valid record wins)
 LBA C..    Commit table  (one 512 B sector per slot, at C + slot index:
                           seq, size, sha256, boot_id, acked flag, CRC)
 LBA S..    Data slots    (N x 256 KiB = 512 sectors each; one chunk per slot)
            slot = [OUTER header | ciphertext, streamed in 4 KB writes ... | trailer | GCM tag | unused tail]
```

- **One chunk = one slot = 60 s.** A slot is 256 KiB (262,144 B). A 60 s chunk at
  32 kbps is 240,000 B of Opus + 3,000 frames × 2 B length prefix (20 ms frames) + 2 B terminator + 44 B
  inner header + 18 B trailer + 52 B outer header + 16 B tag ≈ **246,132 B**, leaving
  ~16 KB (6%) for VBR overshoot. At 24 kbps it is ≈ 186,132 B. A 32 GB card
  (~30.4 GB usable) holds ~116,000 slots, so **~80 days of ring at any bitrate**;
  early-closed short chunks still use a whole slot, so many state changes shorten that.
- **Write and commit order:** write the **OUTER header first**, then the ciphertext as
  the encoder produces it (4 KB aligned multi-block writes, SHA-256 updated over the
  bytes as stored), then the **trailer and GCM tag last**. Only then write the slot's
  **commit record** (seq, size, SHA-256, CRC) to the commit table. A slot whose commit
  record has a valid CRC and the expected seq is committed; anything else is free or
  torn. LIST reads the commit table, never the audio.
- **Early close:** the chunk is closed short (the trailer records the actual duration)
  on privacy, plug-in/unplug, low battery, a time-set, and when the next frame would not
  fit in the slot, so state changes are chunk boundaries.
- **Boot recovery:** read the newest metadata record → scan the commit table forward
  from the head hint until the seq breaks → that is the head. A torn slot just after
  the head is logged as a gap event. This is O(few slots), not a full-card scan.
- **ACKs are per slot, not a watermark.** Out-of-order ACKs are normal: the host
  deliberately leaves chunks it cannot verify or decrypt un-ACKed and ACKs later ones
  (SYNC-PROTOCOL.md §4). An ACK rewrites that slot's commit record with `acked = 1`,
  then ACK_OK is sent. A tear during that rewrite can only lose a chunk the host
  already holds durably. LIST skips ACKed slots, starting from the lowest-unACKed hint.
  Firmware may cache a 1-bit-per-slot bitmap in RAM (~14 KB for 32 GB) so LIST does not
  rescan old commit records.
- **When full:** the ring always takes the **oldest** slot next (ACKed slots are not
  reused out of order, which keeps recovery simple). If that slot is committed and
  not ACKed, it is overwritten anyway (recording wins), the persistent **`dropped`**
  counter is incremented, and it is reported in INFO (SYNC-PROTOCOL.md §2).
- **Brownout:** the open chunk has no tag and no commit record, so it is lost:
  **≤ 60 s** per unclean power-off (decision at the top of this document; SYNC-PROTOCOL.md §8).
- **Wear:** at 24 kbps about 270 MB is written per day, and the ring wraps every ~80
  days, so each LBA is written about 4-5 times a year (commit records twice per wrap).
  Wear is not a concern, but use a **high-endurance/industrial microSD**: those
  handle sudden power loss better.
- **Testing:** the ring module runs under `native_sim` against Zephyr's RAM disk,
  with a fault injector that "cuts power" after random sector writes (M6).

### SPI

`spi2` at **8 MHz**. That is the SPIM0-2 maximum; Omi's 24 MHz request is silently
clamped (WIRING.md section 1). That gives about 1 MB/s raw, while recording needs
about 3 KB/s and a USB CDC sync reads 100-300 KB/s (**ESTIMATE**). During a sync the SD
card (read latency, sharing the bus with recording writes) is the likely limit, not USB:
read in multi-block runs of 16-64 KB, and let a recording write pre-empt a read. The card
stays in SPI idle between writes. The optional D7 load switch can power-cycle it if bench
measurement shows high idle current (0.1-1 mA, varying by card brand).

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
   samples from the IM73D122, an SD write/read round-trip succeeds, BLE is up, and (if
   plugged into a PC) USB enumerates. If it never confirms, the
   next reset (watchdog) reverts to the old image.
4. **Transports:** mcumgr SMP over **BLE**, requiring a bonded and encrypted link
   (`CONFIG_MCUMGR_TRANSPORT_BT_AUTHEN`), and over **USB CDC**: the device is a
   composite with **two CDC-ACM interfaces**, one for the sync protocol and one for SMP
   (`CONFIG_MCUMGR_TRANSPORT_UART` on that CDC-ACM UART), so SMP's framing and the sync
   protocol's SLIP never share a port. On the PC, use `smpmgr` / `smpclient` (Python) or
   the `mcumgr` CLI on the SMP port.
5. **Last-resort rescue:** MCUboot **serial recovery over USB CDC**
   (`CONFIG_BOOT_SERIAL_CDC_ACM` + `CONFIG_BOOT_SERIAL_WAIT_FOR_DFU`). USB has to
   enumerate first, so the wait window is ~2-3 s, not 500 ms (**ESTIMATE**), and costs
   that much audio on every reboot. MCUboot's boot hooks can skip the wait when VBUS is
   absent, so a watchdog reset while worn doesn't lose it (**VERIFY** on the pinned NCS).
   A bricked app that still watchdog-resets can be re-flashed over a USB-C cable without
   opening the case.
6. Enable `CONFIG_BT_PRIVACY` (resolvable private addresses) so the capsule can't
   be tracked by its BLE address. Advertise only as the plugged-in fallback (plain
   charger, or no HELLO from a PC) or after the on-demand pull gesture (section 5).

---

## 10. What to reuse from Omi (MIT) vs. write fresh

Omi devkit sources: `omi/firmware/devkit/` (repo root is MIT; per-folder terms
checked). Keep their copyright notices in reused files and credit them in
`CREDITS.md`.

| Omi file | Verdict | Why |
|---|---|---|
| `src/mic.c` (nrfx PDM, a port of Seeed's Arduino mic code) | **Reuse**, adapted | Proven nrfx PDM config, gain and IRQ wiring. Change: pins to CLK P0.04 / DIN P1.11, power to D2 (P1.10 held LOW), clock to 1.28 MHz ratio 80, the post-power-up discard, start/stop for privacy. |
| `src/codec.c` + `src/lib/opus-1.2.1/` + the CMake flags (`OPUS_ARM_*` EDSP) | **Reuse** | The Opus build is the hardest part to get right on Zephyr. Change: 20 ms frames, bitrate, a smaller stack after measuring, and the VAD stats hook. |
| `src/config.h` | Reuse as a reference | Pin and codec constants. |
| `overlay/xiao_ble_sense_devkitv2-adafruit.overlay`, `prj_*.conf` | **Reuse for M1 only** | Our wiring matches its SPI and CS pins. Our own overlay drops I2S, keeps `uart0` off, moves `pdm0` to D4/D6, sets 8 MHz SPI, and adds the two CDC-ACM nodes. |
| `src/button.c` | Borrow the debounce pattern only | Our D5 is a 2-state switch, not a tap button. |
| `src/transport.c` (battery ADC) | Borrow the ADC setup | We add the P0.14 rule and charge awareness. |
| `src/sdcard.c`, `src/storage.c` | **Replace** | FAT file-per-session and an unencrypted, Omi-specific BLE storage protocol. Ours is the raw ring + SYNC-PROTOCOL.md. |
| `src/transport.c` (BLE audio streaming) | **Replace** | We don't stream live. |
| `src/speaker.c`, haptic, NFC | Drop | Not in our hardware. |
| `usb.c` | Read, don't reuse | Our USB use (plug state, CDC sync, SMP) is written fresh. |
| `src/wdog_facade.c` | Read it, then write our own | Our watchdog policy is check-in based. |
| `scripts/devkit/sdcard_test_files/decode_audio.py` | **Reuse on the PC** for bench decoding of raw Opus frames (M5) | |

**Write fresh:** raw ring storage, the chunker + encryption (to SYNC-PROTOCOL.md),
the sync service (USB CDC + BLE), the time base, the supervisor/watchdog,
power/charge/plug management, the IMU low-power helper, the MCUboot/partition setup, and host tests.

---

## 11. Bench bring-up test plan

Do these in order. Each step is a small separate test app (or a shell command in a
bench build with the USB CDC console). Don't move on until a step passes.

| # | Test | Pass criteria |
|---|---|---|
| T0 | Bare XIAO, blinky over UF2, USB CDC log | Builds and runs on `xiao_ble/nrf52840/sense`. |
| T1 | **Power hygiene + baseline:** IMU off (P1.08 LOW), mic off, LEDs off, P0.14 LOW, System ON idle | Record the µA on the **PPK2 in source-meter mode at 3.8 V into the BAT pads**, USB unplugged. This is the floor every later number is compared to. |
| T2 | VBUS dead on battery: battery only, measure the 5V pin to GND | About 0 V (WIRING.md section 3), so the exposed USB-C contacts carry no voltage while worn. |
| T3 | Charger: plug a USB charger, P0.13 LOW, then HIGH-Z; ammeter in series with the battery | About 100 mA / 50 mA in CC; `/CHG` (P0.17) LOW while charging. |
| T4 | VBAT ADC (P0.14 LOW, AIN7) vs a multimeter at the BAT pads | Within ±30 mV when not charging. |
| T5 | VBUS events: plug and unplug 20 times each into a PC and into a plain charger | Every transition is seen, debounced, with no spurious events. PC vs charger is told apart by enumeration every time. |
| T6 | PDM with the **stock** mic (fallback build): 10 s of PCM to RAM, dumped over CDC | Clean audio at a sensible level. Note the current delta. This is the reference for T6b. |
| T6b | PDM with the **IM73D122** board on D4/D6, power D2, P1.10 LOW: same capture | PDM clock measured at 1.28 MHz on a scope or logic analyser (never 1.032). No click or DC step after the power-up discard. Same script as T6 at 0.3/1/2 m: noise floor lower than the stock mic, speech level within a few dB (same −26 dBFS sensitivity). Current delta vs T6 within +0.1-0.5 mA. D2 LOW → mic draws 0. |
| T7 | Opus alone: encode the recorded PCM; cycles per frame; stack high-water | Real time with ≥ 2× margin. Decodes on the PC with `decode_audio.py` / `opusdec`. |
| T8 | SD alone at 8 MHz: init, CD pin, 4 KB raw write/read patterns, **1 h write-latency histogram** | No errors. The worst-case latency sets the encoded-queue size. Note idle current with the card in. |
| T9 | IMU alone: WHO_AM_I, accel low-power, wake interrupt on P0.11 | The interrupt fires on a tap. Current matches the datasheet (tens of µA). |
| T10 | Switch (D5) and LED (D3) | Both positions read correctly, with zero static current in either. |
| T11 | USB CDC sync: plug into the PC, run the host `SerialTransport` against a full ring while recording continues | Enumerates as two CDC-ACM ports. Measured KB/s into `feasibility.py` (`USB_KBYTES_S`); ≥ 100 KB/s, i.e. a 32 kbps day in < 1 h. No audio gaps during the sync. Cable pulled mid-transfer → the next sync resumes. |
| T12 | BLE: bond with the PC, bulk-throughput test with bleak | Measured KB/s. Put it into `feasibility.py` (`BLE_KBYTES_S`). |
| T13 | Crypto: AES-256-GCM in software and ChaCha20-Poly1305 on CC310 (KB/s) and X25519 timing | Within budget (section 3). |
| T14 | Omi DK2 firmware unmodified on our wiring (switch on "record") | SD files appear, so the SPI/CS wiring is proven. |
| T15 | Full pipeline, 24 h soak | No gaps, no resets, chunks decrypt and decode on the PC. |
| T16 | **Current profile with the PPK2** over 10 min each: WORN-recording (IM73D122), WORN-recording (stock-mic build), PRIVACY, PLUGGED+sync | Compare against `feasibility.py`. Replace the ESTIMATE lines, including the mic line, with measured values. |
| T17 | Fault injection: 100 random power cuts during writes; a forced thread hang; a bad DFU image | The ring always recovers with at most one torn slot; the watchdog reset starts a new `boot_id` and the next sync reconciles its chunks; the DFU reverts. |

**Multimeter vs PPK2:** a multimeter in series works for steady currents (charger
CC current, a mA-level average), but its µA-range burden voltage can brown out the
board on SD/radio peaks, and its averaging misses ms-scale bursts. Use the **PPK2**
for anything averaged or sleep-level. Run it in source-meter mode at 3.7-3.8 V on the BAT
pads with the cell removed, and use ampere-meter mode for plugged-in charging tests.

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
| M5 | Mic + codec modules (ported from Omi; IM73D122 at 1.28 MHz, stock-mic build flag), CPU/stack measured | T6, T6b, T7 |
| M6 | Raw ring storage module (256 KiB slots, commit table, per-slot ACK, `dropped`) + `native_sim` RAM-disk tests incl. out-of-order ACKs + power-cut fault injector | Host tests pass, then T8 |
| M7 | Pipeline PDM → Opus → plaintext chunks → ring | 1 h of audio decodes on the PC. |
| M8 | Encryption per SYNC-PROTOCOL.md (PSA; X25519/SHA-256 on CC310, AES-256-GCM in software) + shared test vectors with the PC tool | The PC decrypts device chunks. T13 |
| M9 | Time base (anchor from SET_TIME, chunk timestamps, optional `__noinit` prev-boot hint) | After a watchdog reset: new `boot_id`, `start_utc_ms = 0` until the next sync, and the host dates those chunks from that sync's anchor. |
| M10 | Supervisor + watchdog check-ins + crash-loop safe mode | T17 (hang part) |
| M11 | Firmware-enforced privacy switch (D2 LOW, P1.10 LOW) + indicator LED rule + switch-flick pull gesture | T10. The mic draws 0 mA in privacy; the LED is on in every unplugged recording state. |
| M12 | BLE sync service (list/fetch/ack) per SYNC-PROTOCOL.md + PC bleak client | T12. On-demand pull (gesture) and the plain-charger fallback work. A full day over BLE is not expected to fit the night at the measured 5 KB/s; that is M13's job. |
| M13 | Plug state machine (PC vs charger), USB CDC transport (sync + SMP ports), charge-rate rules | T5, T11. A full day syncs over USB CDC in < 1 h. Charging terminates after a sync. |
| M14 | IMU low-power helper + WORN/STILL state + chunk tags | T9 |
| M15 | **Dropped for v1.** (Was: VAD-prioritised fetch.) The VAD data is inside the ciphertext and LIST_ITEM has only seq/size/sha256, and USB CDC makes it unnecessary. The per-second VAD bitmap is part of M7/M8. | n/a |
| M16 | LOW_BATT / System OFF / storage mode, battery curve, power optimisation pass | T16 meets the `feasibility.py` budget. |
| M17 | MCUboot serial recovery over USB CDC + BLE SMP with bonded auth | Rescue a deliberately bricked app over a USB-C cable. |
| M18 | **Seal**: 72 h soak, T17 fault-injection, an over-the-air DFU on the sealed unit | All pass. |

---

## 13. Feasibility risks found

1. **Flash:** with both MCUboot slots internal, about 464 KB per slot is below the
   high-end app estimate (BLE + Opus + crypto + SMP). **Mitigation:** put the secondary
   slot on the onboard QSPI flash.
2. **The stock UF2 bootloader means no OTA.** MCUboot needs a **one-time SWD flash**
   before sealing.
3. **Charge termination vs. sync load** (no power-path): a sync drawing more than 10 mA
   while full can stop termination until the 10 h timer runs out. **Mitigation:** sync early,
   0 dBm, 100 mA charge.
4. **Sync time over BLE**: at the 5 KB/s Boswell measured, a full day takes ~14 h at
   24 kbps and ~19 h at 32 kbps, longer than the night. **Mitigation:** USB CDC is the
   primary path (~15 min to ~1 h, **ESTIMATE**); BLE is the plain-charger fallback and
   for on-demand pulls.
5. **Omi's 24 MHz SPI request is really 8 MHz** (SPIM2). That is harmless, but don't plan on more.
6. **The IMU is powered at boot** by the Zephyr board DTS, which costs about 1 mA unless it is handled.
7. **Pin overlap with Omi DK2 firmware** (I2S on D1-D3, haptic on D6, D5 long-press =
   power off). Bench only; mitigated with a series resistor on CD, the switch semantics,
   and running the Omi test before the mic board is wired.
8. **The IM73D122's clock window:** the nRF52840's default PDM clock (1.032 MHz) is
   outside the mic's specified ranges. **Mitigation:** 1.28 MHz/ratio 80 via the nrfx
   enums, checked on a scope in T6b. RF coupling of the 1.28 MHz lines (P1.11 is a
   low-frequency pin) is untested.
9. **The exposed USB-C port** is used every night and open to sweat and lint while worn.
   **Mitigation:** a printed dust cap, VBUS dead on battery (T2), BLE as the fallback if
   the port fails, and SWD-free recovery over BLE SMP.

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
- Infineon IM73D122 datasheet (PDM clock ranges, SNR, current, power-up time):
  <https://www.infineon.com/dgdl/Infineon-IM73D122-DataSheet-v01_00-EN.pdf?fileId=8ac78c8c83cd3081018409cafdfb46db>
- Nordic: nRF52840 Product Specification (SPIM, PDM, USBD, POWER/USBREG, WDT, CC310, SAADC),
  nRF52840 errata (anomaly 198), and nRF Connect SDK docs (partition manager, external
  flash MCUboot secondary slot, SoftDevice Controller, PSA crypto).
  <https://docs.nordicsemi.com/bundle/ps_nrf52840/page/keyfeatures_html5.html>,
  <https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/index.html>
- MCUboot: <https://docs.mcuboot.com/>
- Texas Instruments BQ25101 datasheet: <https://www.ti.com/lit/ds/symlink/bq25101.pdf>
- Opus codec (Xiph.Org): <https://opus-codec.org/docs/>
