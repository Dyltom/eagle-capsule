# Adversarial review of the original plan

The starting plan came from a Gemini conversation (see [CREDITS](../CREDITS.md)).
This page re-checks each of its claims against primary sources: vendor pages,
the Seeed wiki, the TI BQ25101 datasheet, the Nordic product spec and the
BasedHardware/omi source. Verdicts: ✅ holds, ⚠️ partly right / needs a change,
❌ wrong.

## Claims about parts

| Claim | Verdict | What's actually true |
|---|---|---|
| The XIAO nRF52840 Sense is the right brain | ✅ | It is still the best-documented option: Omi DevKit 1/2 used it, and it has a PDM mic, IMU, charger, and BLE. The Omi devkits are now **legacy / community support** (current Omi firmware targets their own CV1 board), so we fork the firmware rather than expect updates. See [ALTERNATIVES](ALTERNATIVES.md). |
| Core SKU `SS102010469`, $29.45 | ⚠️ | Couldn't confirm the SKU or price (Core blocks automated checks). DigiKey AU lists ~A$27.81. Check in the cart. |
| 400 mAh cell `CE04375`, $5.55, 38×25×6 mm, 11 g | ⚠️ | SKU, price and 6 mm thickness are confirmed. **Footprint, weight and protection PCB are not confirmed.** Measure on arrival; the CAD is parametric. |
| 1100 mAh `CE04377`, 51×34×6 mm, 21 g | ⚠️ | Dimensions are confirmed, but Core's URL and image say *1000* mAh. |
| Pololu `#2597` is 3.3 V direct, 20.3×17.8 mm | ✅ | Correct. It also has a **card-detect** pin (needs a pull-up) that the plan didn't use. |
| `ADA5358` magnetic connector, 21×7×7 mm, self-aligning | ⚠️ | It is one mated pair at 2.54 mm pitch, and the magnets repel if reversed. **No dimensions or current rating are published**, and there is **no mechanical keying**, so the dock cradle must provide it. |
| Qi receiver `ADA1901` coil is 48×32 mm | ⚠️ | The *panel* is 48×32 mm; the coil is 40×29 mm. The conclusion (too big for a 400 mAh capsule) still holds. |
| 26 AWG wire ~$6.15 | ❌ | Closer to **A$12–14** per 7.6 m spool. |
| ICS-43434 mic (`ADA6049`) as an upgrade | ⚠️ | Adafruit lists the ICS-43434 as **discontinued** (they suggest the SPH0645). It's moot anyway, because the requirement is no external mic. |

## Claims from the "5 hidden failure modes" review

| # | Original claim | Verdict | Correction |
|---|---|---|---|
| 1 | Qi plus a magnetic clasp causes heat and Foreign Object Detection trips. Use pogo pins. | ✅ | Pogo pins are the right call: smaller, cheaper, no heat. **Add:** a Schottky diode in the dock's 5V line. The XIAO's 5V pin connects straight to USB-C VBUS with no diode, so a dock plus a USB cable would back-feed. |
| 2 | 50 mA charging stalls overnight; set P0.13 LOW for 100 mA | ⚠️ | The pin polarity is right (LOW = 100 mA, high-Z = 50 mA) and the BQ25101 fast-charge timer is a fixed 10 h. **But it's a non-problem in practice:** a day off the dock uses only ~50–120 mAh (see the model), which refills in 1–2 h even at 50 mA. The real issue it missed: the **BQ25101 has no power-path**. Recording on the dock draws from the battery node while charging, which can confuse termination (10% of ICHG = 10 mA, the same order as the load). Use 100 mA and log VBAT on the bench. |
| 3 | 24 h of 16 kbps Opus = 173 MB, ~60 min over BLE, so VAD is needed | ⚠️ | The arithmetic is right, but the conclusion is off. The dock gives an **8 h** sync window, so 173 MB fits easily at ≥10 KB/s. The real risk is **Windows BLE throughput** (estimated 10–60 KB/s), combined with Omi's actual default of **32 kbps** (346 MB/day). Fix: use the dock's two spare pogo pins as a **UART** (~90 KB/s, deterministic). Do VAD on the **server** so nothing is lost on the device. |
| 4 | Two-tier stack-up avoids antenna detuning | ❌ | Self-contradictory: it says "keep the battery away from the antenna", then puts the 38 mm battery directly under the 41.3 mm top tier, so only ~3–4 mm of the board overhangs. The XIAO's chip antenna end must sit in that overhang against a plastic-only wall. The CAD enforces this, and the antenna end is a parameter until confirmed on the real board. |
| 5 | A 30° dock aimed at the bed picks up sleep audio at 0.5–1.5 m | ⚠️ | Plausible but unproven. A ~64 dB(A) SNR MEMS mic will catch speech and snoring at 1 m; quiet breathing is doubtful. Test it before designing around it. |

## What the original review missed entirely

1. **The law (the biggest viability risk).** Always-on recording of other people
   is restricted in every Australian state. In **NSW** (and WA, SA, TAS, ACT) even
   a party to a conversation generally needs **all parties' consent**. Recording
   conversations you are not part of is an offence everywhere. See
   [LEGAL.md](LEGAL.md). This shapes the design: a hardware **pause** control, a
   visible **recording indicator**, and private-by-default storage.
2. **A lost device means a privacy disaster.** A sealed microSD holding months of
   everyone's conversations in plaintext. Fix: encrypt every chunk on the device
   to the home server's public key (X25519 + AES-GCM). The device can write but
   never read its own archive. See [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md).
3. **The IMU leaks about 1.1 mA if you leave it powered.** That alone is a third
   of the budget. Gate it.
4. **The SD card idles at 0.1–1 mA, and SPI lines leak.** This can rival the MCU.
   Measure your actual card, and consider a MOSFET to switch the card's power.
5. **The slide switch.** Wired in the battery line (as Omi did), it means "can
   only charge when ON" and loses the clock when OFF. Better: the battery stays
   connected (the cell's protection PCB is the safety cut-off) and the switch
   becomes a **hardware mic/recording pause** input. See [WIRING.md](WIRING.md).
6. **Timekeeping.** The nRF52840 has no battery-backed calendar clock. Chunks
   carry a monotonic counter plus a boot ID, and the host pushes UTC on every
   sync and reconciles.
7. **Firmware updates in a sealed case.** We need BLE OTA (MCUboot/SMP) or an
   accessible USB-C service port. The CAD keeps a capped USB-C port for recovery.
8. **PLA in a hot Australian car** softens at ~55–60 °C. Print in **PETG** (A1
   mini OK) or **ASA** (P1S).
9. **Transcription compute at home.** 16 h of audio a day through Whisper needs
   a GPU, or a smaller model and a long overnight batch on a CPU. Server-side VAD
   cuts this 2–3×.

## Net verdict

The concept is **viable**. Nothing physical blocks it, and the power budget has
2–4× margin on a 400 mAh cell. The plan needed corrections (diode, antenna
placement, switch role, UART sync, encryption, IMU gating). The legal
constraints are a design input, not an afterthought.
