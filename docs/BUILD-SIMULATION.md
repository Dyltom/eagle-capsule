# Dry-run build: the whole project, start to finish, on paper

This is a complete pretend build, done before buying anything. Each stage lists
what you'd do, how long it takes, what goes wrong, and a **gate**: a pass/fail
check that tells you whether to keep going, change course, or stop. Numbers
come from [`tools/feasibility.py`](../tools/feasibility.py), and the corrections
come from [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md).

Time estimates assume evenings and weekends, AI writing the code, and someone
who can solder through-hole and has a Bambu A1 mini or P1S.

---

## Stage 0: decide (1 evening)

| Decision | Recommendation | Why |
|---|---|---|
| Build or buy? | **Build the DIY capsule now** (cheap, in stock, fully yours). **Pre-order a reSpeaker Clip** as a benchmark or fallback if one turns up. | The Clip (nRF5340, Wi-Fi, a proper charger chip, two mics, open firmware) beats the DIY build on audio and sync but is in pre-sale with a 14–18 h battery. See [ALTERNATIVES](ALTERNATIVES.md). |
| Legal posture | Solo mode by default; a hardware pause; consent from your household | [LEGAL](LEGAL.md). In NSW this isn't optional. |
| Storage | microSD (32 GB high-endurance) sealed inside, **or** soldered SD NAND (Adafruit #4899, 512 MB) | A card gives ~90–180 days of buffer; NAND is smaller and has no contacts to work loose but holds only ~1.5–3 days. With nightly sync, both work. Default: microSD, so a weekend away can't overflow it. |
| Sync | BLE first; dock UART as an upgrade | BLE needs no extra hardware. Two UART wires through the spare pogo pins guarantee the overnight sync fits even on Windows. |

**Gate 0:** you're comfortable with the legal constraints in your state. If not, stop here.

## Stage 1: order (≈ A$110–130 delivered)

| Qty | Part | Core SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| **2** | Seeed XIAO nRF52840 **Sense** | Seeed 102010469 | 2 × 28–30 | One for the bench, one for the build. A spare saves a week if you cook a pad. |
| 2 | LiPo 3.7 V 400 mAh | CE04375 | 2 × 5.55 | Measure on arrival (footprint/weight unconfirmed). Check it has a protection PCB. |
| 1 | Pololu microSD breakout 3.3 V | POLOLU-2597 | ~8 | Not the 2587 (that one is 5 V with level shifters). |
| 1 | Adafruit DIY Magnetic Connector, right angle, 4 pins | ADA5358 | ~13 | One mated pair. Buy 2 if you want a second dock. |
| 2 | SPDT slide switch | ADA805 | 2 × 1.90 | |
| 1 | 26 AWG silicone wire | ADA2517 | ~13 | Not ~$6 as originally quoted. |
| 2 | Schottky diode (1N5817/SS14 class) | any | ~1 | For the dock's 5V line (no back-feed). |
| 1 | 32 GB **high-endurance** microSD | Officeworks/JB | ~15 | Continuous writes wear out ordinary cards. |
| — | Kapton tape, thin open-cell foam, flux, heat-shrink, PETG filament | | ~20 | |
| 1 | Raspberry Pi Debug Probe (or a spare Pico flashed as debugprobe) | Core | ~20 | **Needed once**: installs MCUboot through the XIAO's SWD pads so firmware can update over the air after sealing ([FIRMWARE](FIRMWARE.md)). |
| opt | Nordic Power Profiler Kit II | | ~150 | Only if you want to tune battery life seriously; a µA-range multimeter is enough to start. |

LiPos ship by road only. Expect 3–7 business days.

**Gate 1:** add everything to a Core cart in a browser and confirm price and stock. (Their site blocks automated checks, so some prices above come from cached pages.)

## Stage 2: bench bring-up, no soldering into a case yet (2–3 evenings)

Everything is on the bench with USB power first, then battery power.

1. Flash a Zephyr "blinky" over USB (double-tap reset → UF2 drive). *Risk: a charge-only cable → use a data cable.*
2. **Mic test:** record 30 s of PDM to RAM and dump it over USB serial → listen on the PC. Check it at 0.3 m, 1 m and 2 m.
3. **SD test:** solder header pins on the Pololu board and breadboard it on D8/D9/D10 plus CS. Write 1 h of fake chunks, verify the hashes, pull power mid-write, and check the filesystem survives.
4. **Antenna/mic location:** confirm on the real board which end the chip antenna is at and where the mic port is. Update the two CAD parameters.
5. **VBUS diode check:** multimeter continuity from the USB-C VBUS pin to the 5V pad (expected: a direct connection, no diode).
6. **MCUboot via SWD:** solder fine wires to the underside SWD pads, flash MCUboot with the debug probe, and prove that a BLE OTA update and a rollback both work. This is the last chance to use SWD before the case is sealed.
7. **Current measurement** (multimeter in series with the battery): idle, recording, recording + SD, IMU off vs on. Put the real values into `tools/feasibility.py`.

**Gate 2, the most important one.**

| Check | Pass | If it fails |
|---|---|---|
| Average current while recording to SD | **≤ 8 mA** (model typical 3.2, worst 7.6) | > 8 mA: gate the IMU, try another SD card, add a MOSFET to switch the card's power, or move to the 1100 mAh cell (bigger capsule) |
| Speech intelligible to Whisper at 1 m | Transcript word error rate looks usable | Try 24–32 kbps, mic gain, port geometry; worst case, an internal mic upgrade on a small board ([ALTERNATIVES §3](ALTERNATIVES.md)) |
| SD survives power cuts | No corrupted filesystem in 20 pulls | Use a raw ring layout instead of FAT ([FIRMWARE](FIRMWARE.md)) |
| BLE bulk throughput to your PC | ≥ 15 KB/s sustained | Add the dock UART (two wires) |

## Stage 3: firmware MVP (1–2 weeks of evenings, AI-written)

The milestones are in [FIRMWARE.md](FIRMWARE.md). The MVP is PDM → Opus 24 kbps (the firmware recommendation; 16 is the floor, Omi uses 32) → encrypt → 60 s chunk files on SD, plus a BLE list/fetch/ack sync, time sync from the host, and the pause switch. The host side already exists as a tested reference implementation in [`host/`](../host/README.md), running against a simulated device.

*Risk: Opus encoder RAM/CPU on the M4F.* Omi already ships this on the same board (32 kbps, complexity 3), so it's proven.

**Gate 3:** 24 h on the bench running from battery → you get ~24 h of audio on the PC, transcribed, with no gaps over 1 s, and the battery is still above 40%.

## Stage 4: print and fit (2–4 evenings, 3–6 test prints)

1. Print a **fit-check shell** in cheap PLA at 0.2 mm (~40 min on an A1 mini). Drop the real parts in.
2. Measure: the battery's real footprint, the ADA5358 body, the switch position. Update the CAD parameters and reprint. Expect 2–3 loops.
3. The final shell is in **PETG**. PLA softens in a hot car; PETG and ASA don't.
4. Print the bezel separately (silk/bronze PLA or PETG). See [`concepts/`](../concepts/README.md) for directions.

**Gate 4:** the capsule closes without forcing it, nothing presses on the SD card or USB-C, and the outer size is **≤ ~38 × 50 × 19 mm** (the CAD's 37.4 × 49.7 × 18.6) and **≤ ~38 g**. If it's bigger, see the trade-offs in [`hardware/`](../hardware/README.md).

## Stage 5: final assembly (1 evening)

Wiring is pin-by-pin in [WIRING.md](WIRING.md). Order: battery leads via the protection PCB to the BAT pads (the switch is *not* on the battery line) → SD wires → pogo half → switch → mic foam and gasket → Kapton over the bare pads → close.

*Risks:* shorting the LiPo (cut and strip one lead at a time), heat into the cell (keep the iron off the pouch), and a cold joint on the BAT pads (tug-test every wire).

**Gate 5:** the post-assembly current matches the bench current within 10%, and BLE RSSI at 3 m through the closed shell is within 6 dB of the bare board.

## Stage 6: dock (1–2 evenings)

Print the dock, glue in the other ADA5358 half (with the cradle keyed so it only fits one way), run 5V through a Schottky diode, add an optional UART to a USB-serial adapter or a small Wi-Fi bridge board, and weight the base with coins or steel shot.

**Gate 6:** it snaps on in the dark in one go, the charge LED lights, the capsule keeps recording, and the overnight sync finishes before morning.

## Stage 7: home pipeline (1 week, AI-written)

The PC runs the sync client, then decrypts, then server-side VAD (Silero), then faster-whisper, then SQLite + FTS5 search and daily Markdown notes. The reference code is in [`host/`](../host/README.md).

*Risk: compute.* 16 h/day of audio. With a GPU, large-v3 takes about 20–40 min a night. On CPU only, use the small or medium int8 models plus VAD, which runs for hours overnight. That's OK, but worth knowing.

**Gate 7:** you can search for "what did I say about X last Tuesday" and get the right clip.

## Stage 8: one-week live trial

Track: hours recorded vs hours worn, battery % at bedtime, sync duration, comfort (neck, sleep), skin irritation, transcript quality, and what you'd actually look up.

**Gate 8 (keep or kill):** after a week, do you use the data? If yes → v2 (better bezel, mic tuning, maybe the Clip). If no → you've spent ~A$130 and some evenings, not A$400 on a closed gadget.

## Failure drills (rehearsed on paper)

| Scenario | What happens | Designed response |
|---|---|---|
| Pendant lost on a train | A stranger has the device | Every chunk is encrypted to your home key, so the SD is unreadable. You lose at most the data since the last sync. |
| PC off for a 3-day trip | No sync | The 32 GB ring buffer holds ~90+ days. Nothing is lost. |
| Battery runs flat | The clock is lost | Chunks carry a boot ID and a monotonic counter; the host re-anchors the time at the next sync. |
| Firmware bug bricks it | Sealed case | MCUboot + BLE OTA rollback; the capped USB-C service port is for UF2 recovery. |
| Hot car, 70 °C dash | Shell deforms; LiPo stress | PETG/ASA shell. Don't leave it in a car (LiPo guidance applies anyway). |
| Someone asks "are you recording me?" | Social or legal | The visible indicator plus the pause switch; delete a time range on the server. |
| Plugged into USB while on the dock | Back-feed between supplies | The Schottky diode in the dock line. |

## Verdict

**Viable, at low cost (~A$110–130 in parts) and with no physical blockers.**
The main risks are measured current (Gate 2) and audio quality under a shirt.
Both are tested on the bench before the case is ever printed. The plan is set up
so the most likely failures show up in the first two evenings with ~A$60 of
parts on a breadboard.
