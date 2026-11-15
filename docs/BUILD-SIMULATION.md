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
| Legal posture | Solo mode by default; a firmware-enforced privacy switch; the recording indicator on whenever worn; consent from your household | [LEGAL](LEGAL.md). In NSW this isn't optional. |
| Storage | microSD (32 GB high-endurance) sealed inside, **or** soldered SD NAND (Adafruit #4899, 512 MB) | A card gives ~80 days of buffer (256 KiB slots); NAND has no contacts to work loose but holds only ~1.3 days ungated. With nightly sync, both work. Default: microSD, so a weekend away can't overflow it. |
| Sync | **Dock UART from the start** (primary); BLE as the fallback when docked with no UART host, and for on-demand pulls (not a continuous daytime link) | Boswell measured a BLE file pull at **5.07 kB/s** on this board while it kept recording. At that rate a 24 kbps day (~260 MB) takes ~14 h, longer than the night. Two UART wires through the spare pogo pins move it in ~0.8 h at ~90 KB/s. USB data over the pogo pins was considered and rejected: D+/D− across sprung magnetic contacts is a signal-integrity risk, and USB mass storage fights the recorder for the card. See [ADVERSARIAL-REVIEW](ADVERSARIAL-REVIEW.md#second-review-chatgpt-nov-2026). |

**Gate 0:** you're comfortable with the legal constraints in your state. If not, stop here.

## Stage 1: order (≈ A$165–180 in parts, plus ≈ A$175 of one-off tools)

Prices are inc GST. "estimate" means we didn't find a current price; check it in the cart.

**Required: in the capsule and dock**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Seeed XIAO nRF52840 **Sense** | Seeed 102010469 | ~29 | |
| 1 | LiPo 3.7 V 400 mAh | CE04375 | 5.55 | Measure on arrival (footprint/weight unconfirmed). Check it has a protection PCB. |
| 1 | Pololu microSD breakout 3.3 V | POLOLU-2597 | ~8 | Not the 2587 (that one is 5 V with level shifters). |
| 1 | 32 GB **high-endurance** microSD | Officeworks/JB | ~15 | Continuous writes wear out ordinary cards. |
| 1 | Adafruit DIY Magnetic Connector, right angle, 4 pins | ADA5358 | ~13 | One mated pair: one half in the capsule, one in the dock. **Stock risk:** a Nov 2026 quote showed it out of stock at Core (in stock at Adafruit on 15 Nov 2026). Check it first, because nothing else in the dock works without it. |
| 1 | SPDT slide switch | ADA805 | 1.90 | The privacy switch. |
| 1 | 26 AWG silicone wire, 25 ft (7.6 m) | ADA2517 (black) or ADA2518 (white) | ~13 | Battery and 5 V. Not ~$6 as originally quoted. |
| 1 | 30 AWG silicone wire, 50 ft (15.2 m), 0.8 mm OD | ADA3164 (black) or ADA3169 (white) | 10.95 | SPI, UART, switch and LED signals ([WIRING §6](WIRING.md)). |
| 1 | Recording-indicator LED, 0603 red/amber, high efficiency | any | ~1 (estimate) | Required when worn ([LEGAL](LEGAL.md)); or use the onboard RGB through a light pipe. |
| 1 | Resistors: 3 × 1 kΩ (D1, D6, D7), 2 × 4.7 kΩ (LED, dock RX line) | any | ~3 (estimate) | |
| 1 | Capacitors: 22 µF + 100 nF ceramic at the SD VDD pin | any | ~2 (estimate) | |
| 2 | Schottky diode (1N5817/SS14 class) | any | ~1 | For the dock's 5V line (no back-feed). |
| 1 | Adafruit USB-C breakout, downstream | ADA4090 | ~7 (estimate; A$7.69 at Pakronics) | Dock power in ([hardware/](../hardware/README.md)). |
| 1 | 5 V USB supply + USB-C cable for the dock | any | 0–15 (estimate) | 0 if you reuse a phone charger. |
| 1 | 3.3 V USB-serial adapter that does 1 Mbaud (CP2102/FT232 class) | any | ~10 (estimate) | The dock UART to the PC. It's the primary sync path, so it isn't optional. |
| 1 | Screws: 2 × M1.6 × 8 self-tappers (lid), 4 × M2 self-tappers (dock), rubber feet | any | ~8 (estimate) | |
| 1 | Mic gasket: TPU 95A, or 1.5 mm closed-cell foam | any | ~5 (estimate) | |
| 1 | Steel washers (dock weight), cord for the pendant | hardware shop | ~10 (estimate) | |
| — | Kapton tape, thin open-cell foam, flux, heat-shrink, PETG filament | | ~20 | |
| | **Subtotal** | | **≈ 165–180** | The range is the dock supply (reused or bought). |

**Required: one-off tools (you keep them)**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Raspberry Pi Debug Probe (or a spare Pico flashed as debugprobe) | Core | ~20 | **Needed once**: installs MCUboot through the XIAO's SWD pads so firmware can update over the air after sealing ([FIRMWARE](FIRMWARE.md)). |
| 1 | Nordic Power Profiler Kit II (or another averaging power analyser) | nRF-PPK2 | ~155 (DigiKey AU / element14 AU; ~245–250 at some retailers) | **Needed for Gate 2.** A multimeter in series misses ms-scale SD/radio bursts and its burden voltage can brown out the board ([FIRMWARE](FIRMWARE.md) §11). |
| | **Subtotal** | | **≈ 175** | |

**Recommended**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Second XIAO nRF52840 Sense | Seeed 102010469 | ~29 | One for the bench, one for the build. A spare saves a week if you cook a pad. |
| 1 | Spare 400 mAh LiPo | CE04375 | 5.55 | |
| 1 | Spare slide switch | ADA805 | 1.90 | |
| | **Subtotal** | | **≈ 37** | |

**Optional**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Second magnetic connector pair | ADA5358 | ~13 | A second dock. |
| 1 | SD load switch (TPS22916/TPS22917 class) on D4 | any | ~3 (estimate) | Only if Gate 2 shows SD idle current matters. |
| 1 | SD NAND 512 MB instead of microSD + Pololu | ADA4899 | 17.40 | ~1.3 days ungated (256 KiB slots); see [ALTERNATIVES](ALTERNATIVES.md). |
| 1 | 1100 mAh LiPo (bigger capsule) | CE04377 | 8.65 | Core's URL and image say 1000 mAh; the listing is 1100 mAh. |

LiPos ship by road only. Expect 3–7 business days.

**Gate 1:** add everything to a Core cart in a browser and confirm price and stock. (Their site blocks automated checks, so some prices above come from cached pages.)

## Stage 2: bench bring-up, no soldering into a case yet (2–3 evenings)

Everything is on the bench with USB power first, then battery power.

1. Flash a Zephyr "blinky" over USB (double-tap reset → UF2 drive). *Risk: a charge-only cable → use a data cable.*
2. **Mic test:** record 30 s of PDM to RAM and dump it over USB serial → listen on the PC. Check it at 0.3 m, 1 m and 2 m.
3. **SD test:** solder header pins on the Pololu board and breadboard it on D8/D9/D10 plus CS. Write 1 h of fake chunks to the raw ring (decided, [FIRMWARE §8](FIRMWARE.md)), verify the hashes, pull power mid-write, and check the ring recovers.
4. **Antenna/mic location:** confirm on the real board which end the chip antenna is at and where the mic port is. Update the two CAD parameters.
5. **VBUS diode check:** multimeter continuity from the USB-C VBUS pin to the 5V pad (expected: a direct connection, no diode).
6. **MCUboot via SWD:** solder fine wires to the underside SWD pads, flash MCUboot with the debug probe, and prove that a BLE OTA update and a rollback both work. This is the last chance to use SWD before the case is sealed.
7. **Current measurement** with the **PPK2** (source-meter mode at 3.7–3.8 V on the BAT pads, cell removed; [FIRMWARE §11](FIRMWARE.md)): idle, recording, recording + SD, IMU off vs on. A multimeter in series misses ms bursts and can brown out the board, so it doesn't count for this gate. Put the real values into `tools/feasibility.py`. Until then, every current figure is an estimate: ours (3.2 / 7.6 mA), Boswell's "near 8 mA" budget while live-streaming, and the second review's 10–30 mA chart.
8. **Placement test** (one evening, with a friend who has agreed to be recorded). Put the battery-powered board in a small box with a port hole roughly where the capsule's will be, and record the same 2-minute script in three placements: **outside the shirt at the upper chest**, **at the collar edge**, and **fully under a T-shirt**. Do each one in a **quiet room**, **outdoors** and **walking**: 9 recordings. The script should include names, numbers and a commitment ("I'll send Sam the quote by Friday"). Transcribe them all with the host pipeline and score each on: names right, the commitment captured word for word, and word error rate as a rough guide. Fabric rub while walking is the expected failure.

**Gate 2, the most important one.**

| Check | Pass | If it fails |
|---|---|---|
| Average current while recording to SD, measured on the PPK2 over ≥ 10 min | **≤ 8 mA** (model typical 3.2, worst 7.6) | > 8 mA: gate the IMU, try another SD card, add a MOSFET to switch the card's power, or move to the 1100 mAh cell (bigger capsule) |
| Speech intelligible to Whisper at 1 m | Transcript word error rate looks usable | Try 24–32 kbps, mic gain, port geometry; worst case, an internal mic upgrade on a small board ([ALTERNATIVES §3](ALTERNATIVES.md)) |
| Placement test (step 8) | At least one placement you'd actually wear gets names and commitments right in all three settings | Change the port position or windscreen, or wear it outside the shirt. If under-shirt fails everywhere, say so in the docs rather than promise it |
| Raw ring survives power cuts (raw ring is decided; this checks it) | The ring recovers in 20 pulls, losing at most the slot being written (≤ 60 s) | Fix the ring's recovery code before going on ([FIRMWARE §8](FIRMWARE.md)) |
| Dock UART throughput (USB-serial adapter at 1 Mbaud) | A day's audio (~260 MB) in < 2 h, i.e. ≥ ~36 KB/s sustained (model: ~90 KB/s) | Check the adapter supports 1 Mbaud, shorten the wires, add flow control, or drop to 460800 baud (~45 KB/s, still fits the night) |
| BLE bulk throughput to your PC (sets expectations only) | Record the KB/s while recording continues. ≥ 5 KB/s is enough for on-demand pulls and a docked fallback, but a full ungated day takes 14–19 h at 5 KB/s, so a fallback night only part-clears the backlog | Under 5 KB/s: BLE is only for status and small pulls. The dock UART carries the archive anyway |

## Stage 3: firmware MVP (1–2 weeks of evenings, AI-written)

The milestones are in [FIRMWARE.md](FIRMWARE.md). The MVP is PDM → Opus 24 kbps (the firmware recommendation; 16 is the floor, Omi uses 32) → encrypt → 60 s chunk files on SD, plus a list/fetch/ack sync over the dock UART and BLE (the same protocol on both), time sync from the host, and the pause switch. The host side already exists as a tested reference implementation in [`host/`](../host/README.md), running against a simulated device.

*Risk: Opus encoder RAM/CPU on the M4F.* Omi already ships this on the same board (32 kbps, complexity 3), so it's proven. Give the codec thread a **24 KB** stack to start with: Boswell overflowed a smaller one on this board, and measured a 17,944 B high-water mark at 24,576 B.

**Gate 3:** 24 h on the bench running from battery → you get ~24 h of audio on the PC, transcribed, with no gaps over 1 s, and the battery still has **≥ 35%** of its usable capacity. This matches Gate 2: the docs assume 300 mAh usable of 400 (the worst case), and 8 mA × 24 h = 192 mAh leaves 108 mAh = 36%. (A 40% bar would need ≤ 7.5 mA.) A real 16 h day at 8 mA uses only 43%.

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

Print the dock, glue in the other ADA5358 half (with the cradle keyed so it only fits one way), run 5V through a Schottky diode, wire pogo pins 3 and 4 as the UART to the USB-serial adapter (or a small Wi-Fi bridge board later), and weight the base with coins or steel shot.

**Gate 6:** it snaps on in the dark in one go, the charge LED lights, the capsule keeps recording, and the overnight sync finishes before morning.

**LiPo safety (it charges unattended every night, sealed, next to your bed).** Use a
cell with a protection PCB, and keep the BQ25101's 10 h safety timer (don't
defeat it in firmware). Stand the dock on a hard, non-flammable surface, not on
fabric or paper. A sealed shell hides swelling, so check monthly that the lid
still sits flat and the capsule seats in the dock as before; retire any cell
that has swollen, been punctured or run hot. Never charge it in a hot car.

## Stage 7: home pipeline (1 week, AI-written)

The PC runs the sync client, then decrypts, then server-side VAD (Silero), then faster-whisper, then SQLite + FTS5 search and daily Markdown notes. The reference code is in [`host/`](../host/README.md).

*Risk: compute.* 16 h/day of audio. With a GPU, large-v3 takes about 20–40 min a night. On CPU only, use the small or medium int8 models plus VAD, which runs for hours overnight. That's OK, but worth knowing. On an Apple Silicon Mac, see "Running it at home" in [`host/README.md`](../host/README.md): faster-whisper runs on the CPU there unless you try CTranslate2's new experimental Metal backend.

What sits on top of the transcripts (provenance, correction, guarding against false memories) is in [MEMORY.md](MEMORY.md).

**Gate 7:** you can search for "what did I say about X last Tuesday" and get the right clip, with a link to the audio and the transcript span.

## Stage 8: one-week live trial

Track: hours recorded vs hours worn, battery % at bedtime, sync duration, comfort (neck, sleep), skin irritation, transcript quality, and what you'd actually look up.

**Gate 8 (keep or kill):** after a week, do you use the data? If yes → v2 (better bezel, mic tuning, maybe the Clip). If no → you've spent ~A$170 in parts (plus tools you keep) and some evenings, not A$400 on a closed gadget.

## Failure drills (rehearsed on paper)

| Scenario | What happens | Designed response |
|---|---|---|
| Pendant lost on a train | A stranger has the device | Every chunk is encrypted to your home key, so the SD is unreadable. You lose at most the data since the last sync. |
| PC off for a 3-day trip | No sync | The 32 GB ring buffer holds ~80 days. Nothing is lost. (On the 512 MB SD NAND option, ~1.3 days, the ring would overwrite the oldest un-ACKed audio.) |
| Battery runs flat | The clock is lost | Chunks carry a boot ID and a monotonic counter; the host re-anchors the time at the next sync. |
| Firmware bug bricks it | Sealed case | MCUboot swap-with-revert over BLE; last resort is MCUboot serial recovery over the dock UART, or SMP over USB CDC through the capped USB-C service port while the app still runs. UF2 is gone once MCUboot is installed. |
| Hot car, 70 °C dash | Shell deforms; LiPo stress | PETG/ASA shell. Don't leave it in a car (LiPo guidance applies anyway). |
| Someone asks "are you recording me?" | Social or legal | The visible indicator plus the pause switch; delete a time range on the server. |
| Plugged into USB while on the dock | Back-feed between supplies | The Schottky diode in the dock line. |

## Verdict

**Viable, at low cost (~A$165–180 in parts, plus ~A$175 of one-off tools: the debug probe and the PPK2) and with no physical blockers.**
The main risks are measured current (Gate 2) and audio quality under a shirt.
Both are tested on the bench before the case is ever printed. The plan is set up
so the most likely failures show up in the first two evenings with ~A$60 of
parts on a breadboard and the PPK2.
