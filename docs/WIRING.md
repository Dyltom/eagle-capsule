# Eagle Capsule - Wiring

This is the pin-by-pin wiring for the capsule. Every pin choice below is
justified, and anything we have not measured on real hardware is marked
**VERIFY**. Firmware behaviour that depends on this wiring is in
[`FIRMWARE.md`](FIRMWARE.md). The sync/encryption protocol over BLE and the dock
UART is in [`SYNC-PROTOCOL.md`](SYNC-PROTOCOL.md) and is not repeated here.

Parts: Seeed XIAO nRF52840 Sense, Pololu #2597 microSD breakout, a 400 mAh LiPo
with a protection PCB (PCM), an Adafruit #805 SPDT slide switch, an Adafruit
#5358 4-pin magnetic pogo connector, and optionally one LED with a resistor.

---

## 1. Pin-by-pin table

XIAO header names (D0-D10) map to nRF52840 GPIOs as shown in the Seeed wiki
pinout and the Zephyr `xiao_ble` board files.

| XIAO pin | nRF52840 | Eagle Capsule use | Connects to | Omi DK2 use of the same pin | Notes |
|---|---|---|---|---|---|
| D0 / A0 | P0.02 | **SD CS** (active low) | #2597 `CS` | SD CS (`cs-gpios = <&gpio0 2 ...>`) | Same as DK2, so Omi firmware finds the card unmodified. |
| D1 / A1 | P0.03 | **SD card detect** | #2597 `CD` via **1 kΩ** series | I2S SDOUT (speaker) | `CD` is shorted to GND with no card and floats with a card in. Use the internal pull-up, enabled only while sampling. Card present = HIGH. The 1 kΩ protects the pin if Omi DK2 firmware drives it as I2S while no card is inserted. |
| D2 / A2 | P0.28 | spare | - | I2S LRCK | Keep free. It was SD CS on Omi DK1 `-spisd`. |
| D3 / A3 | P0.29 | **Recording LED** (optional, active high) | LED anode via resistor, cathode to GND | I2S SCK | See section 5. It will flicker if you bench-test Omi DK2 firmware, which is harmless. |
| D4 / A4 | P0.04 | optional **SD power enable** (active high) | EN of a load switch, e.g. TPS22916/TPS22917 | Speaker enable, driven HIGH | It must be active **high**: Omi drives D4 high, so the card stays powered under Omi firmware too. Without a load switch, leave it unconnected. |
| D5 / A5 | P0.05 | **Privacy switch input** | #805 common (middle) pin | Button input (rising edge) | SPDT wiring, see section 4. No pull resistor is needed, so there is zero static current. |
| D6 | P1.11 | **UART TX** (capsule to dock) | Pogo pin 3 via **1 kΩ** | Haptic output | The default `uart0` TX in Zephyr's `xiao_ble` board. |
| D7 | P1.12 | **UART RX** (dock to capsule) | Pogo pin 4 via **1 kΩ** | - | The default `uart0` RX in Zephyr's `xiao_ble` board. |
| D8 | P1.13 | **SPI SCK** | #2597 `SCLK` | SPI SCK | Same as DK2. |
| D9 | P1.14 | **SPI MISO** | #2597 `DO` | SPI MISO | Same as DK2. |
| D10 | P1.15 | **SPI MOSI** | #2597 `DI` | SPI MOSI | Same as DK2. |
| 3V3 | - | 3.3 V rail | #2597 `VDD` (or via the load switch), #805 one end | - | Put a **22 µF** ceramic at the #2597 VDD pin to absorb SD write current spikes (tens of mA). **VERIFY** the XIAO regulator's current rating on the schematic. |
| GND | - | ground | #2597 `GND`, #805 other end, LED cathode, pogo pin 2 | - | Use a star-ish return. Don't daisy-chain the SD ground through thin wire. |
| 5V | VBUS | dock power in | Pogo pin 1 | - | Connected straight to USB-C VBUS, see section 3. |
| BAT+ / BAT- (pads under the board) | - | battery | LiPo **through its PCM**, always connected | - | See section 4 for why there is no switch here. |

### Pins on the XIAO you don't wire but must handle in firmware

| nRF52840 | Function on the XIAO Sense | Rule |
|---|---|---|
| P0.13 | BQ25101 charge current select | **LOW = 100 mA, HIGH or high-Z = 50 mA** (Seeed wiki). Drive it LOW when docked. 100 mA is 0.25 C for 400 mAh. |
| P0.14 | VBAT divider enable (`READ_BAT`) | **Keep it LOW, always.** Driving it HIGH while charging can put battery-side voltage on P0.31 and damage it (Seeed wiki warning). The divider leak with P0.14 low is about 4.2 V / 1.5 MΩ ≈ 3 µA, which is negligible. Never configure it as an output HIGH, and never leave it to a default that could float high. |
| P0.31 / AIN7 | VBAT sense (about 1/3 divider) | Read it with the SAADC: internal 0.6 V reference, gain 1/6, acquisition time ≥ 40 µs because the source is high-impedance. The reading is inflated while charging, so read it when the charger is idle or apply an offset. |
| P0.17 | BQ25101 `/CHG` (charge LED) | Input, LOW while charging. **VERIFY** on the schematic. Do not enable Zephyr's `pwm0` node: its default pinctrl targets P0.17. |
| P1.08 | LSM6DS3TR-C power enable | The Zephyr DTS marks it `regulator-boot-on`, so the **IMU is powered at boot**. Firmware must either put the IMU in accel-only low-power mode or switch P1.08 off. Left in its default state the IMU costs about 1 mA. |
| P0.07 / P0.27 | IMU I2C SDA / SCL (`i2c0`) | Internal. Don't enable `spi0`, which shares the instance with `i2c0`. |
| P0.11 | IMU INT1 | Wake-on-motion interrupt. |
| P1.10 | PDM mic power | HIGH = mic on. It is the only hard "mic off" lever, see section 4. |
| P1.00 / P0.16 | PDM CLK / DIN | Internal mic. |
| P0.26 / P0.30 / P0.06 | Onboard R / G / B LED, **active low** | Usable as the recording indicator through a light pipe, see section 5. |
| P0.09 / P0.10 | NFC pads | Unused. If you ever use them as GPIO, set `CONFIG_NFCT_PINS_AS_GPIOS`. |
| SWDIO / SWCLK pads | debug | Needed **once** to replace the UF2 bootloader with MCUboot (see FIRMWARE.md). On bench units, solder thin wires to them before sealing. |

### Peripheral-instance check (no conflicts)

- `spi2` carries the SD card (D8-D10). `i2c0` carries the IMU. `uart0` carries the
  dock UART (D6/D7). `pdm0`, `saadc` and `qspi` (onboard 2 MB flash) are
  separate peripherals.
- On the nRF52840, SPI0/TWI0 and SPI1/TWI1 share hardware instances. We use
  `i2c0` and `spi2`, so nothing collides. Keep `i2c1` disabled: its
  default pinctrl is D4/D5, our SD-enable and privacy-switch pins.
- **SPI speed:** Omi's overlay asks for 24 MHz on `spi2`, but SPIM0-2 on the
  nRF52840 top out at **8 MHz**. Only SPIM3 reaches 32 MHz, and it has
  erratum 198 (see the Nordic nRF52840 Product Specification and errata).
  Zephyr clamps the request, so the card actually runs at 8 MHz, about 1 MB/s
  raw. That is far more than the about 4 KB/s recording rate and the ≤ 90 KB/s
  sync read rate need. Set `spi-max-frequency = <8000000>` so the
  overlay matches what the hardware actually does.

---

## 2. ASCII wiring diagram

```
                         +------------------------------+
                         |   XIAO nRF52840 Sense (top)  |
                         |            [USB-C]           |
  #2597 CS  <------------| D0  P0.02          5V (VBUS) |------------+-----> POGO 1 (5V)
  #2597 CD  <--[1k]------| D1  P0.03                GND |----+-------|-----> POGO 2 (GND)
   (spare)               | D2  P0.28                3V3 |--+ |       |
  LED  <--[R, sec.5]-----| D3  P0.29          D10 P1.15 |--|-|-------|-----> #2597 DI  (MOSI)
  SD-EN (opt) <----------| D4  P0.04          D9  P1.14 |--|-|-------|-----> #2597 DO  (MISO)
  #805 COMMON  ----------| D5  P0.05          D8  P1.13 |--|-|-------|-----> #2597 SCLK
  POGO 3 (TX) <--[1k]----| D6  P1.11          D7  P1.12 |--|-|--[1k]-+-----< POGO 4 (RX)
                         +------------------------------+  | |
                          underside: BAT+  BAT-  SWDIO SWCLK | |
                                      |     |              | |
          LiPo 400 mAh  (+)--[PCM]----+     |              | |
                        (-)--[PCM]----------+              | |
                                                           | |
   #805 SPDT:   end A ---------------- 3V3 ----------------+ |
                common -------------- D5                   | |
                end B ---------------- GND ------------------+
                                                           | |
   #2597:  VDD ---- 3V3 (or load-switch OUT) --[22uF to GND]-+ |
           GND ---------------------------------------------- -+
           CD  ---- [1k] ---- D1   (CD shorts to GND only when no card)

   LED (optional):  D3 --[R]--|>|-- GND        (or onboard RGB through a light pipe)

   Dock side of the pogo connector (NOT inside the capsule):
     5 V supply --|>|-- POGO 1        Schottky, anode at the supply, e.g. SS14/BAT54-class
     GND -------------- POGO 2
     bridge RX <------- POGO 3        3.3 V logic only, never 5 V
     bridge TX --[4.7k]- POGO 4       bridge stays idle/high-Z until it sees capsule TX idle-high
```

---

## 3. Pogo connector, 5 V and back-feed

Pin map for the #5358 (4 contacts): **1 = 5V, 2 = GND, 3 = UART TX from the
capsule, 4 = UART RX into the capsule.** Put GND on a contact that
mates first or sits in the middle if the connector allows it. Check the #5358's
magnet polarity: the connector must not be able to mate rotated 180°,
or 5V lands on a UART pin. **VERIFY** this before soldering.

**Is there a diode between USB-C VBUS and the XIAO 5V pin?** No. On the XIAO
nRF52840 (Sense) the 5V pin is the USB-C VBUS net directly. That is what the
schematic linked from the Seeed wiki shows, and Seeed documents powering the board
through the 5V pin as equivalent to USB. The consequences:

1. **The dock must supply its own back-feed protection.** Put a Schottky in
   series on the dock side (anode at the supply, cathode at pogo pin 1). Without it, a
   capsule that is also on USB-C would push PC VBUS backwards into the dock's
   supply. A 0.3-0.4 V Schottky drop leaves about 4.6 V at the BQ25101 input,
   which is enough to charge a 4.2 V cell. **VERIFY** against the BQ25101 VIN /
   UVLO / dropout figures in the TI datasheet.
2. **Never dock while USB-C is plugged in** on bench units. The two 5 V
   sources would be tied together through the capsule. The diode stops dock-side
   damage but not a fight between two supplies of similar voltage.
3. **Is the capsule's pogo 5V pin live when it's worn?** It should be
   about 0 V when running on battery: the BQ25101 does not pass battery current
   back to its input. **VERIFY with a multimeter** (battery only, measure 5V
   pin to GND) before trusting it. If it reads anything above a few hundred mV, add a
   Schottky inside the capsule too, accepting about 0.35 V less charge headroom.
4. Sweat bridging the exposed pogo pins: with 5V dead on battery and the UART
   pins high-Z when undocked (firmware rule, FIRMWARE.md section 5), there is no
   driven voltage across the contacts, so there is nothing to electrolyse. The 1 kΩ series
   resistors limit current if the dock drives a pin while the capsule's battery is flat.
   This also avoids phantom-powering the nRF52840 through its ESD diodes.
   For the same reason, the dock bridge must not transmit until it sees the capsule's
   TX idle-high.

**Dock detection** is free: the nRF52840's own VBUS pin sits on the same net,
so the POWER peripheral's `USBDETECTED` / `USBREMOVED` events fire when the capsule is docked
(FIRMWARE.md section 5).

---

## 4. Battery, the slide switch, and "privacy / off"

### What a battery-line switch would break

If the #805 interrupted the battery (the Omi DevKit approach), then:

- **Charging stops when the switch is off.** The BQ25101 charges whatever is on
  BAT+. With the switch open, the cell is disconnected, so the dock charges nothing.
  Omi's own docs say the DevKit "can only charge when powered ON". For a device that
  is supposed to live on a nightstand dock, this is a trap: switch it "off" for privacy
  at night and it is flat by morning.
- **Timekeeping is lost.** The nRF52840 has no separately backed RTC. Cutting
  the battery erases the clock and boot state, and every off/on cycle creates a time gap
  that has to be repaired at the next sync.
- **Docked "off" isn't off.** With USB/dock 5 V present, the XIAO runs from
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
- **In privacy, firmware** stops PDM, **drives P1.10 LOW so the
  microphone is unpowered**, flushes and closes the current chunk with a "privacy
  start" marker, and keeps time, BLE sync, charging and the watchdog running. That
  is a stronger guarantee than a "mute" flag. It is still enforced by firmware, which
  is acceptable here because the owner writes and signs the firmware (FIRMWARE.md
  section 9). The recording LED goes off, so the state is visible.
- A **true hardware mic kill** would mean cutting the onboard P1.10 trace or the PDM
  clock on the XIAO, which is fragile and voids any rework margin. We don't do it.
- **Long-term storage / shipping** is handled by a firmware "storage mode"
  (System OFF, wake on VBUS) sent from the PC, not by a hard switch.

### If you insist on a hard power cut anyway

Interrupt **BAT+** between the PCM output and the XIAO BAT+ pad. Never interrupt
the negative lead: cutting ground leaves the SD card and pogo pins with return paths
through I/O ESD diodes. Accept that the device can't charge while it is off,
and that time resets on every cycle.

---

## 5. Recording-indicator LED (optional, recommended)

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

Suggested convention: a slow red blink means recording, off means privacy, and
the LED is off on the dock at night (configurable). Sleep-audio recording on the
dock is a deliberate choice by the owner. If you share the bedroom, ask.

---

## 6. Build notes

- Silicone wire (#2517/#2518): 30 AWG for signals, 26 AWG for battery and 5V.
- Keep SPI wires short (< 5 cm) and the same length. Even at 8 MHz, long SPI
  wires make ringing that corrupts SD transfers.
- Add a 100 nF next to the 22 µF at the SD VDD pin.
- Insulate the XIAO underside (Kapton) where the LiPo touches it. The BAT pads and
  SWD pads are exposed.
- Before closing the case: test every peripheral (FIRMWARE.md section 11),
  verify that the 5V pin is at 0 V on battery, and test the dock with the Schottky in place.

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
  i2c0 P0.07/P0.27, i2c1 P0.04/P0.05, pwm0 P0.17; `xiao_ble_nrf52840_sense.dts`:
  IMU power regulator on P1.08 `regulator-boot-on`, mic enable P1.10).
  <https://github.com/zephyrproject-rtos/zephyr/tree/main/boards/seeed/xiao_ble>
- Nordic Semiconductor, *nRF52840 Product Specification* (SPIM speeds, POWER
  USB VBUS detection, SAADC) and *nRF52840 errata* (anomaly 198, SPIM3).
  <https://docs.nordicsemi.com/bundle/ps_nrf52840/page/keyfeatures_html5.html>
- Texas Instruments, *BQ25101 datasheet* (no power-path, ISET, safety timer,
  termination). <https://www.ti.com/lit/ds/symlink/bq25101.pdf>
- Pololu, *#2597 microSD breakout* (no regulator or level shifting; CD shorted to
  GND with no card, floating with a card). <https://www.pololu.com/product/2597>
