# Eagle Capsule - Wiring

This is the pin-by-pin wiring for the capsule. Every pin choice below is
justified, and anything we have not measured on real hardware is marked
**VERIFY**. Firmware behaviour that depends on this wiring is in
[`FIRMWARE.md`](FIRMWARE.md). The sync/encryption protocol over USB CDC and BLE
is in [`SYNC-PROTOCOL.md`](SYNC-PROTOCOL.md) and is not repeated here.

Parts: Seeed XIAO nRF52840 Sense, Pololu #2597 microSD breakout, a 600 mAh LiPo
(Little Bird LB-00237; 400 and 1100 mAh are options) with a protection PCB (PCM),
an Adafruit #805 SPDT slide switch, a small custom PCB carrying one **Infineon
IM73D122** PDM mic (section 1a), and one recording-indicator LED with a resistor
(required, section 5).

**Charging and sync are both through the XIAO's own USB-C port** (section 3).
There is no dock connector, no pogo pins and nothing wired to the 5V pin.

> **What changed (Nov 2026, owner decisions):** the magnetic pogo connector
> (Adafruit #5358), the dock's Schottky diode, its USB-C breakout and the dock UART
> on D6/D7 are gone. USB-C is the only charge and sync path. D6 and D7 were freed
> and now carry the mic data line and the optional SD power enable. The default cell
> is 600 mAh, and the stock mic is replaced by an IM73D122 board.

---

## 1. Pin-by-pin table

XIAO header names (D0-D10) map to nRF52840 GPIOs as shown in the Seeed wiki
pinout and the Zephyr `xiao_ble` board files.

| XIAO pin | nRF52840 | Eagle Capsule use | Connects to | Omi DK2 use of the same pin | Notes |
|---|---|---|---|---|---|
| D0 / A0 | P0.02 | **SD CS** (active low) | #2597 `CS` | SD CS (`cs-gpios = <&gpio0 2 ...>`) | Same as DK2, so Omi firmware finds the card unmodified. |
| D1 / A1 | P0.03 | **SD card detect** | #2597 `CD` via **1 kΩ** series | I2S SDOUT (speaker) | `CD` is shorted to GND with no card and floats with a card in. Use the internal pull-up, enabled only while sampling. Card present = HIGH. The 1 kΩ protects the pin if Omi DK2 firmware drives it as I2S while no card is inserted. |
| D2 / A2 | P0.28 | **External mic power** (static, active high) | Mic board `VDD` | I2S LRCK | Feeds the IM73D122 (~0.7-1 mA) straight from the GPIO. Use high drive (H1); the drop at ~1 mA should be ~0.1 V (**VERIFY**), and the mic runs from 1.62 V. P0.28 is a "low-frequency I/O only" pin, which is fine for a static supply. LOW = mic unpowered (privacy, section 4). |
| D3 / A3 | P0.29 | **Recording LED** (required indicator, active high) | LED anode via resistor, cathode to GND | I2S SCK | See section 5. It will flicker if you bench-test Omi DK2 firmware, which is harmless. |
| D4 / A4 | P0.04 | **PDM CLK** to the mic (1.28 MHz) | Mic board `CLK` | Speaker enable, driven HIGH | P0.04 is a **full-speed** pin; most of the free header pins (P0.02/03/28/29, P1.10-P1.15) are "standard drive, low-frequency I/O only" per the nRF52840 PS, so the clock goes here. |
| D5 / A5 | P0.05 | **Privacy switch input** | #805 common (middle) pin | Button input (rising edge) | SPDT wiring, see section 4. No pull resistor is needed, so there is zero static current. |
| D6 | P1.11 | **PDM DATA** from the mic (input) | Mic board `DATA` via an optional **100 Ω** | Haptic output | An input, so the low-frequency pin class doesn't matter. It is `uart0` TX in Zephyr's `xiao_ble` board: **disable `uart0`**. Coupling of the 1.28 MHz data line into the radio is **untested**. |
| D7 | P1.12 | optional **SD power enable** (active high) | EN of a load switch, e.g. TPS22916/TPS22917, plus a 1 MΩ pull-up to 3V3 | - | Moved from D4. Omi DK2 firmware leaves this pin alone, so the pull-up keeps the card powered under Omi firmware and during boot (3.3 µA only while firmware holds it LOW). **VERIFY** the switch's EN threshold and any internal pull-down. Without a load switch, leave it unconnected (it is then the spare pin). |
| D8 | P1.13 | **SPI SCK** | #2597 `SCLK` | SPI SCK | Same as DK2. |
| D9 | P1.14 | **SPI MISO** | #2597 `DO` | SPI MISO | Same as DK2. |
| D10 | P1.15 | **SPI MOSI** | #2597 `DI` | SPI MOSI | Same as DK2. |
| 3V3 | - | 3.3 V rail | #2597 `VDD` (or via the load switch), #805 one end | - | Put a **22 µF** ceramic at the #2597 VDD pin to absorb SD write current spikes (tens of mA). **VERIFY** the XIAO regulator's current rating on the schematic. |
| GND | - | ground | #2597 `GND`, #805 other end, LED cathode, mic board `GND` | - | Use a star-ish return. Don't daisy-chain the SD ground through thin wire. Give the mic board its own ground wire. |
| 5V | VBUS | **nothing** | - | - | It *is* the USB-C VBUS net (section 3). Never wire anything to it: no second supply, no connector. |
| BAT+ / BAT- (pads under the board) | - | battery | LiPo **through its PCM**, always connected | - | See section 4 for why there is no switch here. |

### Pins on the XIAO you don't wire but must handle in firmware

| nRF52840 | Function on the XIAO Sense | Rule |
|---|---|---|
| P0.13 | BQ25101 charge current select | **LOW = 100 mA, HIGH or high-Z = 50 mA** (Seeed wiki). Drive it LOW whenever USB power is present. 100 mA is 0.17 C for 600 mAh (0.25 C for 400). |
| P0.14 | VBAT divider enable (`READ_BAT`) | **Keep it LOW, always.** Driving it HIGH while charging can put battery-side voltage on P0.31 and damage it (Seeed wiki warning). The divider leak with P0.14 low is about 4.2 V / 1.5 MΩ ≈ 3 µA, which is negligible. Never configure it as an output HIGH, and never leave it to a default that could float high. |
| P0.31 / AIN7 | VBAT sense (about 1/3 divider) | Read it with the SAADC: internal 0.6 V reference, gain 1/6, acquisition time ≥ 40 µs because the source is high-impedance. The reading is inflated while charging, so read it when the charger is idle or apply an offset. |
| P0.17 | BQ25101 `/CHG` (charge LED) | Input, LOW while charging. **VERIFY** on the schematic. Do not enable Zephyr's `pwm0` node: its default pinctrl targets P0.17. |
| P1.08 | LSM6DS3TR-C power enable | The Zephyr DTS marks it `regulator-boot-on`, so the **IMU is powered at boot**. Firmware must either put the IMU in accel-only low-power mode or switch P1.08 off. Left in its default state the IMU costs about 1 mA. |
| P0.07 / P0.27 | IMU I2C SDA / SCL (`i2c0`) | Internal. Don't enable `spi0`, which shares the instance with `i2c0`. |
| P0.11 | IMU INT1 | Wake-on-motion interrupt. |
| P1.10 | Onboard PDM mic power | **Hold it LOW: the onboard mic stays off.** The Zephyr board files don't mark this regulator boot-on. Only the stock-mic fallback build drives it HIGH. |
| P1.00 / P0.16 | Onboard mic PDM CLK / DIN | Not on the headers. Unused with the IM73D122: leave them as disconnected inputs (`pdm0` pinctrl moves to D4/D6). |
| P0.26 / P0.30 / P0.06 | Onboard R / G / B LED, **active low** | Usable as the recording indicator through a light pipe, see section 5. |
| P0.09 / P0.10 | NFC pads | Unused. If you ever use them as GPIO, set `CONFIG_NFCT_PINS_AS_GPIOS`. |
| SWDIO / SWCLK pads | debug | Needed **once** to replace the UF2 bootloader with MCUboot (see FIRMWARE.md). On bench units, solder thin wires to them before sealing. |

### Peripheral-instance check (no conflicts)

- `spi2` carries the SD card (D8-D10). `i2c0` carries the IMU. `pdm0` carries the
  external mic (CLK D4, DIN D6). `usbd` carries sync and charging detection on
  the USB-C port. `saadc` and `qspi` (onboard 2 MB flash) are separate peripherals.
  **`uart0` is disabled**: its default pins are D6/D7.
- On the nRF52840, SPI0/TWI0 and SPI1/TWI1 share hardware instances. We use
  `i2c0` and `spi2`, so nothing collides. Keep `i2c1` disabled: its
  default pinctrl is D4/D5, our PDM clock and privacy-switch pins.
- **SPI speed:** Omi's overlay asks for 24 MHz on `spi2`, but SPIM0-2 on the
  nRF52840 top out at **8 MHz**. Only SPIM3 reaches 32 MHz, and it has
  erratum 198 (see the Nordic nRF52840 Product Specification and errata).
  Zephyr clamps the request, so the card actually runs at 8 MHz, about 1 MB/s
  raw. That covers the about 4 KB/s recording rate plus the 100-300 KB/s (estimated)
  USB CDC sync read rate, but during a sync the SD bus, not USB, is the likely limit. Set `spi-max-frequency = <8000000>` so the
  overlay matches what the hardware actually does.

### 1a. The mic board (IM73D122)

A ~8 × 6 mm PCB, 0.6-0.8 mm thick, carrying the IM73D122 (4 × 3 × 1.2 mm LLGA-5,
bottom port), a **1 µF 0402** at VDD, an optional 100 Ω on DATA, and an L/R
solder jumper (to GND = one channel; firmware reads that channel). Four edge pads:
`VDD`, `GND`, `CLK`, `DATA`, each to the XIAO on 30 AWG silicone wire (short, under
~5 cm). A **0.8 mm plated or plain through-hole** under the mic's sound port; take
its exact offset from Infineon's footprint drawing (**VERIFY**). Total height about
1.8-2.0 mm.

- **Mounting:** flat on the inside of the lid, mic facing in, the board's hole over
  the lid's port. Stack-up from outside: lid hole ≥ 1.0 mm (lid wall ≤ 1.5 mm at the
  port, counterbored if needed) → 0.3-0.5 mm closed-cell silicone or PORON gasket,
  ~1.5 mm ID, compressed → PCB hole → mic. An optional 3-4 mm hydrophobic acoustic
  membrane on the outside costs ~1-2 dB (unverified). Port on the outward face, slightly
  recessed, with a felt or foam cap against fabric rub.
- **Why one mic, not two:** a second mic gains ~3 dB against self-noise only, costs
  ~0.7 mA, 1.5-2× the Opus CPU and stereo bitrate. One IM73D122 alone is ~+6-7 dB
  over the stock mic (both unverified).
- **Build:** assembled by PCBWay (~US$30-40 for 5, sending them DigiKey parts), or
  bare boards (~US$2) reflowed on a hotplate. An LLGA bottom-port part can't be
  hand-soldered with an iron. Prices unverified.
- **No breakout exists:** no hobby board carries the IM73D122 (or the T5838 or
  IM70D122), and Infineon's KIT_IM73D122V01_FLEX showed 0 stock with a 97-week lead
  (Nov 2026). Adafruit's PDM mics #3492/#4346 are MP34DT01-class (~61 dB SNR),
  worse than the stock mic.
- **If it is silent or noisy:** flip the L/R jumper or the PDM sampling edge in
  firmware (FIRMWARE.md §3), before suspecting the board.

---

## 2. ASCII wiring diagram

```
                 USB-C cable (charger or PC) ===> [USB-C]  through a slot in the capsule wall
                         +------------------------------+
                         |   XIAO nRF52840 Sense (top)  |
                         |            [USB-C]           |
  #2597 CS  <------------| D0  P0.02          5V (VBUS) |  (nothing: it is USB-C VBUS)
  #2597 CD  <--[1k]------| D1  P0.03                GND |----+
  MIC VDD   <------------| D2  P0.28                3V3 |--+ |
  LED  <--[R, sec.5]-----| D3  P0.29          D10 P1.15 |--|-|-------------> #2597 DI  (MOSI)
  MIC CLK   <------------| D4  P0.04          D9  P1.14 |--|-|-------------> #2597 DO  (MISO)
  #805 COMMON  ----------| D5  P0.05          D8  P1.13 |--|-|-------------> #2597 SCLK
  MIC DATA  >--[100R]----| D6  P1.11          D7  P1.12 |--|-|-------------> SD-EN (opt, 1M pull-up to 3V3)
                         +------------------------------+  | |
                          underside: BAT+  BAT-  SWDIO SWCLK | |
                                      |     |              | |
          LiPo 600 mAh  (+)--[PCM]----+     |              | |
                        (-)--[PCM]----------+              | |
                                                           | |
   #805 SPDT:   end A ---------------- 3V3 ----------------+ |
                common -------------- D5                   | |
                end B ---------------- GND ------------------+
                                                           | |
   #2597:  VDD ---- 3V3 (or load-switch OUT) --[22uF to GND]-+ |
           GND ---------------------------------------------- -+
           CD  ---- [1k] ---- D1   (CD shorts to GND only when no card)

   Mic board (IM73D122, on the lid):  VDD -- D2 (+1uF to GND on the board)   GND -- GND
                                      CLK -- D4                              DATA -[100R]- D6
                                      L/R jumper to GND; sound hole over the lid port + gasket

   LED (required):  D3 --[R]--|>|-- GND        (or onboard RGB through a light pipe)
   Onboard mic: P1.10 held LOW (off); P1.00 / P0.16 unused.
```

---

## 3. USB-C: charging, sync and the 5V pin

One cable does both. Plug it into the capsule's side port:

- **Any USB charger:** the XIAO's BQ25101 charges at 100 mA (P0.13 LOW) while
  recording continues. No USB enumeration happens, so the firmware knows there is no
  PC (FIRMWARE.md §5).
- **The PC or home server:** it also charges, and the firmware enumerates as a USB
  CDC-ACM serial port. The sync protocol runs over it (SYNC-PROTOCOL.md §5.2).
- **The optional bedside stand** is printed plastic with no electronics. It holds the
  capsule at ~30° facing the bed with the cable plugged in, so it records sleep audio
  while it charges ([hardware/](../hardware/README.md)).

**Is there a diode between USB-C VBUS and the XIAO 5V pin?** No. On the XIAO
nRF52840 (Sense) the 5V pin is the USB-C VBUS net directly. That is what the
schematic linked from the Seeed wiki shows, and Seeed documents powering the board
through the 5V pin as equivalent to USB. So:

1. **Nothing else may feed the 5V pin.** A second supply on it would be tied straight
   to whatever is on the USB-C cable. Leave the pin unconnected (this design has no
   other power input, so there is nothing to back-feed).
2. **Is VBUS live when the capsule runs on battery?** It should be about 0 V: the
   BQ25101 does not pass battery current back to its input. **VERIFY with a
   multimeter** (battery only, 5V pin to GND, test T2). This matters more now, because
   the USB-C contacts are exposed to sweat whenever the cap is off: with VBUS dead and
   D+/D− idle there is no driven voltage across them to electrolyse.

**The port is now worn-exposed.** It is the one opening the capsule needs every day:

- A **printed dust cap** (TPU, or PETG with a friction fit) closes it while worn. Lint
  packs into an open USB-C socket and stops the plug seating; clear it with a wooden
  toothpick, never metal.
- **Sweat:** wipe the capsule and let the port dry before plugging in. Look at the
  contacts monthly for green or black corrosion.
- **Wear:** USB-C receptacles are commonly rated around 10,000 mating cycles (check
  the XIAO's part; **VERIFY**). Once a night is ~3,650 cycles in ten years, so wear is
  not the limit. A loose plug is: keep the cable's overmould supported by the slot
  so the receptacle doesn't take side loads, and don't leave the capsule hanging from
  the cable.
- The receptacle is soldered to the XIAO only, so a yank on the cable stresses the
  board. The shell's slot should take that load (hardware/).

**Plug detection** is free: the nRF52840's own VBUS pin sits on the same net,
so the POWER peripheral's `USBDETECTED` / `USBREMOVED` events fire when a cable with
power is plugged in. USB enumeration then tells a PC (configured) from a plain charger
(never enumerates) (FIRMWARE.md §5).

---

## 4. Battery, the slide switch, and "privacy / off"

### What a battery-line switch would break

If the #805 interrupted the battery (the Omi DevKit approach), then:

- **Charging stops when the switch is off.** The BQ25101 charges whatever is on
  BAT+. With the switch open, the cell is disconnected, so the cable charges nothing.
  Omi's own docs say the DevKit "can only charge when powered ON". For a device that
  is plugged in every night, this is a trap: switch it "off" for privacy at night and
  it is flat by morning.
- **Timekeeping is lost.** The nRF52840 has no separately backed RTC. Cutting
  the battery erases the clock and boot state, and every off/on cycle creates a time gap
  that has to be repaired at the next sync.
- **Plugged-in "off" isn't off.** With USB 5 V present, the XIAO runs from
  VBUS even with the battery cut, so the mic could still be powered.
- **Hot-plugging the cell** through a tiny slide switch arcs and bounces into
  the regulator.

### Recommendation: keep the battery connected and use the switch as a record/privacy input

- **The LiPo stays connected through its PCM at all times.** The PCM handles
  over-discharge, over-charge and short-circuit. Firmware's own low-voltage cutoff
  (System OFF below about 3.4 V, FIRMWARE.md section 5) keeps the cell away from the
  PCM's hard trip.
- **The #805 (SPDT) is wired to D5:** common to D5, one end to 3V3, the other end to GND.
  Because the pin is always driven to a rail, there is no pull resistor and
  **no static current** in either position. A pull-up switch to GND would leak
  about 250 µA through the internal ~13 kΩ pull-up for as long as privacy mode lasted.
- **Semantics: D5 LOW = recording, D5 HIGH = privacy (paused).** LOW
  is the "button released" state Omi expects. Omi DK2 firmware treats D5 held high
  for 3 s as a long press and **powers off**, so bench-test Omi firmware with
  the switch on "record".
- **In privacy, firmware** stops PDM, **drives D2 LOW so the external
  mic is unpowered, and keeps P1.10 LOW so the onboard mic stays off**, flushes and closes the current chunk (the next chunk carries the
  encrypted `after_privacy` flag, SYNC-PROTOCOL.md §3), and keeps time, BLE sync, charging and the watchdog running. That
  is a stronger guarantee than a "mute" flag. It is still enforced by firmware, which
  is acceptable here because the owner writes and signs the firmware (FIRMWARE.md
  section 9). The recording LED goes off, so the state is visible. Describe it
  as a **firmware-enforced** privacy switch, not a hardware kill.
- **On-demand sync:** flicking privacy→record→privacy→record within 3 s opens a
  2-minute BLE pull window for the bonded host (FIRMWARE.md §5).
- A **true hardware mic kill** is now within reach, because the mic is on our own
  board: a DPDT switch whose second pole sits in series between D2 and the mic's VDD
  would cut the mic in hardware, whatever the firmware does. The onboard mic would still
  be firmware-held off (P1.10), so it is only a full kill if P1.10's trace is also cut.
  Not in v1 (the #805 is single-pole); it is the upgrade path.
- **Long-term storage / shipping** is handled by a firmware "storage mode"
  (System OFF, wake on VBUS) sent from the PC, not by a hard switch.

### If you insist on a hard power cut anyway

Interrupt **BAT+** between the PCM output and the XIAO BAT+ pad. Never interrupt
the negative lead: cutting ground leaves the SD card, the mic board and the USB-C
contacts with return paths through I/O ESD diodes. Accept that the device can't charge while it is off,
and that time resets on every cycle.

---

## 5. Recording-indicator LED (required when worn)

Why include one: recording conversations is regulated, and the rules differ by place.
Many places allow a participant to record (one-party consent). Others need everyone's
consent (all-party consent; for example California Penal Code §632, and several
Australian state surveillance-devices acts restrict recording private
conversations and/or using the recordings). A light **does not create consent**, but it
does a few useful things:
it is honest signalling to the people around you, it tells you at a glance whether
you're recording or in privacy mode, and it is cheap. This is not legal advice:
check the law where you live, and turn the device to privacy (section 4) in
settings where recording isn't OK.

Options:

1. **External LED on D3 (P0.29), active high.** Use a high-efficiency 0603
   red/amber LED with a **4.7-10 kΩ** resistor, about 0.1-0.3 mA when lit. Better still,
   firmware blinks it (for example 20 ms every 2 s), so the average is in the µA range.
   Mount it behind a thin translucent window in the shell.
2. **Onboard RGB through a light pipe** (P0.26/P0.30/P0.06, active low, with
   the XIAO's own resistors). No extra wiring, but the board LEDs are brighter and
   draw more, so blink them sparingly.

Rule: the indicator is **required whenever the capsule records unplugged**
(worn, or left on a table). A slow red blink means recording, off means privacy.
While plugged in (on the bedside stand) it may be dimmed or turned off at night
(configurable), because it is in your own bedroom. Sleep-audio recording on the stand
is a deliberate choice by the owner. If you share the bedroom, ask. See [LEGAL](LEGAL.md).

---

## 6. Build notes

- Silicone wire: 26 AWG (#2517 black / #2518 white, 7.6 m) for the battery;
  30 AWG (#3164 black / #3169 white, 15.2 m, 0.8 mm OD) for signals and the mic board.
- Keep the mic CLK and DATA wires short and away from the SD clock (D8) and the
  antenna end. Twist each with a ground wire if there is room.
- Keep SPI wires short (< 5 cm) and the same length. Even at 8 MHz, long SPI
  wires make ringing that corrupts SD transfers.
- Add a 100 nF next to the 22 µF at the SD VDD pin.
- Insulate the XIAO underside (Kapton) where the LiPo touches it. The BAT pads and
  SWD pads are exposed.
- **Bench-test Omi DK2 firmware (M1/T14) before the mic board is wired**, or with it
  unplugged: Omi drives D2 as I2S LRCK (it would toggle the mic's power) and D6 as
  the haptic output (it would fight the mic's DATA output).
- Before closing the case: test every peripheral (FIRMWARE.md section 11),
  verify that the 5V pin is at 0 V on battery, and do a charge-and-sync over USB-C
  with the shell closed and the cable through the slot.

---

## Sources

- Seeed Studio, *XIAO nRF52840 (Sense) wiki*: pinout, P0.13 charge-current
  polarity, P0.14/P0.31 battery-read warning, battery pads, and the schematic
  in its resources section. <https://wiki.seeedstudio.com/XIAO_BLE/>
- BasedHardware/omi, DevKit 2 overlay
  `omi/firmware/devkit/overlay/xiao_ble_sense_devkitv2-adafruit.overlay`
  (commit 2e2a0b3, 2025-10-21): SPI2 P1.13/P1.14/P1.15, CS `gpio0 2`.
  Its comment says "P0.28", but the value is P0.02, and the value is what
  counts. I2S on P0.29/P0.28/P0.03. Also `src/button.c` (D5 input, D4 driven high,
  3 s long press = off), `src/speaker.c` (haptic P1.11, speaker enable P0.04),
  `src/transport.c` (IMU power P1.08), `src/config.h` (PDM P0.16/P1.00, mic
  power P1.10). <https://github.com/BasedHardware/omi/tree/main/omi/firmware/devkit>
- Zephyr, `boards/seeed/xiao_ble/` (`xiao_ble-pinctrl.dtsi`: uart0 P1.11/P1.12,
  i2c0 P0.07/P0.27, i2c1 P0.04/P0.05, pwm0 P0.17, pdm0 P1.00/P0.16;
  `xiao_ble_nrf52840_sense.dts`: IMU power regulator on P1.08 `regulator-boot-on`,
  mic enable P1.10, not boot-on).
  <https://github.com/zephyrproject-rtos/zephyr/tree/main/boards/seeed/xiao_ble>
- Nordic Semiconductor, *nRF52840 Product Specification* (SPIM speeds, POWER
  USB VBUS detection, SAADC, GPIO pin classes: P0.02/P0.03/P0.28/P0.29/P1.10-P1.15
  "standard drive, low frequency I/O only", P0.04/P0.05 full speed) and
  *nRF52840 errata* (anomaly 198, SPIM3).
  <https://docs.nordicsemi.com/bundle/ps_nrf52840/page/keyfeatures_html5.html>
- Texas Instruments, *BQ25101 datasheet* (no power-path, ISET, safety timer,
  termination). <https://www.ti.com/lit/ds/symlink/bq25101.pdf>
- Infineon, *IM73D122 datasheet* v1.0 (supply 1.62-3.6 V, PDM clock ranges, SNR,
  current, power-up time, footprint).
  <https://www.infineon.com/dgdl/Infineon-IM73D122-DataSheet-v01_00-EN.pdf?fileId=8ac78c8c83cd3081018409cafdfb46db>
- Pololu, *#2597 microSD breakout* (no regulator or level shifting; CD shorted to
  GND with no card, floating with a card). <https://www.pololu.com/product/2597>
