# Dry-run build: the whole project, start to finish, on paper

This is a complete pretend build, done before buying anything. Each stage lists
what you'd do, how long it takes, what goes wrong, and a **gate**: a pass/fail
check that tells you whether to keep going, change course, or stop. Numbers
come from [`tools/feasibility.py`](../tools/feasibility.py), and the corrections
come from [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md).

Time estimates assume evenings and weekends, AI writing the code, and someone
who can solder through-hole and has a Bambu A1 mini or P1S.

> **What changed (Nov 2026, owner decisions):** USB-C is the only charge and sync
> path, so the magnetic pogo connector (ADA5358), the dock's Schottky diodes, its USB-C
> breakout (ADA4090) and the USB-serial adapter are out, and the nightstand dock is now
> an optional printed stand with no electronics. The default cell is 600 mAh (Little
> Bird LB-00237). The mic is an Infineon IM73D122 on a small custom PCB. The BOM, gates
> and totals below are recomputed for all three.

---

## Stage 0: decide (1 evening)

| Decision | Recommendation | Why |
|---|---|---|
| Build or buy? | **Build the DIY capsule now** (cheap, in stock, fully yours). **Pre-order a reSpeaker Clip** as a benchmark or fallback if one turns up. | The Clip (nRF5340, Wi-Fi, a proper charger chip, two mics, open firmware) beats the DIY build on audio and sync but is in pre-sale with a 14–18 h battery. See [ALTERNATIVES](ALTERNATIVES.md). |
| Legal posture | Solo mode by default; a firmware-enforced privacy switch; the recording indicator on whenever worn; consent from your household | [LEGAL](LEGAL.md). In NSW this isn't optional. |
| Storage | microSD (32 GB high-endurance) sealed inside, **or** soldered SD NAND (Adafruit #4899, 512 MB) | A card gives ~80 days of buffer (256 KiB slots); NAND has no contacts to work loose but holds only ~1.3 days ungated. With nightly sync, both work. Default: microSD, so a weekend away can't overflow it. |
| Charge + sync | **USB-C cable into the capsule's side port** for both. Plugged into the PC, the firmware syncs over USB CDC (primary); on a plain charger it only charges, and BLE is the fallback and the on-demand pull (not a continuous daytime link) | Boswell measured a BLE file pull at **5.07 kB/s** on this board while it kept recording. At that rate a 24 kbps day (~260 MB) takes ~14 h, longer than the night. USB CDC moves it in ~15 min (300 KB/s, **estimate**; ~1 h at a pessimistic 100 KB/s and 32 kbps). The firmware keeps owning the card: no USB mass storage. The cost is a worn-exposed USB-C port (dust cap, sweat, wear: [WIRING §3](WIRING.md)). See [ADVERSARIAL-REVIEW](ADVERSARIAL-REVIEW.md#what-changed-after-the-reviews-owner-decisions-nov-2026). |
| Mic | **Infineon IM73D122 on a small custom PCB**; the stock XIAO mic is the fallback | ~+6-7 dB SNR over the stock mic at our 1.28 MHz clock (unverified). No breakout exists, so it needs a tiny PCB. See [ALTERNATIVES §3](ALTERNATIVES.md#3-microphone-choice) |

**Gate 0:** you're comfortable with the legal constraints in your state. If not, stop here.

## Stage 1: order (≈ A$210–250 in parts, plus ≈ A$175 of one-off tools)

Prices are inc GST unless noted. "estimate" means we didn't find a current price; check it in the cart.

**Required: in the capsule**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Seeed XIAO nRF52840 **Sense** | Seeed 102010469 | ~29 | |
| 1 | LiPo 3.7 V **600 mAh**, 29 × 36 × 5.5 mm, 10.5 g, 2-pin JST-PH | Little Bird LB-00237 | 11.30 | [Listing](https://littlebirdelectronics.com.au/products/lithium-ion-polymer-battery-3-7v-600mah) (GST not stated; in stock 15 Nov 2026). The listing says it has built-in protection (overcharge, over-discharge at 3.0 V, short circuit); **check the PCM is really there, and whether it sits inside the 5.5 mm,** on arrival. |
| 1 | Pololu microSD breakout 3.3 V | POLOLU-2597 | ~8 | Not the 2587 (that one is 5 V with level shifters). |
| 1 | 32 GB **high-endurance** microSD | Officeworks/JB | ~15 | Continuous writes wear out ordinary cards. |
| 5 | **Infineon IM73D122** PDM mic (IM73D122V01XTMA1) | DigiKey AU 16999563 | 20.15 (5 × 4.03) | [DigiKey AU](https://www.digikey.com.au/en/products/detail/infineon-technologies/IM73D122V01XTMA1/16999563): 40,749 in stock (15 Nov 2026). One goes in the capsule; the rest cover reflow mistakes and a second board. Add shipping if the order is under DigiKey's free-shipping threshold. LCSC/JLC C5563886 showed 0 stock. |
| 5 | **Mic PCB**, ~8 × 6 mm, 0.6-0.8 mm, IM73D122 + 1 µF 0402 + optional 100 Ω, 4 edge pads, 0.8 mm sound hole ([WIRING §1a](WIRING.md)) | PCBWay (or JLCPCB) | ~47–62 (estimate: US$30–40 assembled, consigning the DigiKey mics) | Or **bare boards** (~US$2, ≈ A$3) reflowed on a hotplate, saving ~A$45–60 but adding a hotplate to the tools. A bottom-port LLGA can't be hand-soldered with an iron. Plus shipping (estimate). |
| 1 | SPDT slide switch | ADA805 | 1.90 | The privacy switch. |
| 1 | 26 AWG silicone wire, 25 ft (7.6 m) | ADA2517 (black) or ADA2518 (white) | ~13 | Battery leads. Not ~$6 as originally quoted. |
| 1 | 30 AWG silicone wire, 50 ft (15.2 m), 0.8 mm OD | ADA3164 (black) or ADA3169 (white) | 10.95 | SPI, switch, LED and the four mic-board wires ([WIRING §6](WIRING.md)). |
| 1 | Recording-indicator LED, 0603 red/amber, high efficiency | any | ~1 (estimate) | Required when worn ([LEGAL](LEGAL.md)); or use the onboard RGB through a light pipe. |
| 1 | Resistors: 1 kΩ (D1), 4.7 kΩ (LED), 100 Ω (mic DATA, if not on the mic PCB) | any | ~2 (estimate) | |
| 1 | Capacitors: 22 µF + 100 nF ceramic at the SD VDD pin | any | ~2 (estimate) | The mic's 1 µF is on the mic PCB. |
| 1 | **Good USB-C cable**: data-capable (not charge-only), with a slim plug overmould that fits the capsule's port slot | any | ~10–15 (estimate) | The charge **and** sync path, used every night. Check its overmould against `usb_plug_w` / `usb_plug_h` in [`hardware/`](../hardware/README.md). |
| 1 | USB charger for the bedside stand | any | 0–15 (estimate) | 0 if you reuse a phone charger, or if the cable runs to the PC or home server. |
| 1 | Mic gasket: 0.3–0.5 mm closed-cell silicone or PORON sheet (cut a ~1.5 mm ID ring) | any | ~5 (estimate) | Seals the lid port to the mic PCB ([WIRING §1a](WIRING.md)). |
| 1 | Screws: 2 × M1.6 × 8 self-tappers (lid); rubber feet for the stand | any | ~5 (estimate) | |
| 1 | Steel washers (stand weight), cord for the pendant | hardware shop | ~10 (estimate) | |
| — | Kapton tape, thin open-cell foam, flux, heat-shrink, PETG and TPU filament (shell, stand, USB-C dust cap) | | ~20 | |
| | **Subtotal** | | **≈ 210–250** | The range is the mic PCB route and price, the cable, and whether you buy a charger. Without the mic upgrade (stock mic) it is ≈ A$145–165. |

The arithmetic: fixed lines 29 + 11.30 + 8 + 15 + 20.15 + 1.90 + 13 + 10.95 + 1 + 2 + 2 + 5 + 5 + 10 + 20 = **154.30**;
plus mic PCBs 47–62, cable 10–15, charger 0–15 → **211–246**.

**Required: one-off tools (you keep them)**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Raspberry Pi Debug Probe (or a spare Pico flashed as debugprobe) | Core | ~20 | **Needed once**: installs MCUboot through the XIAO's SWD pads so firmware can update over the air or over USB after sealing ([FIRMWARE](FIRMWARE.md)). |
| 1 | Nordic Power Profiler Kit II (or another averaging power analyser) | nRF-PPK2 | ~155 (DigiKey AU / element14 AU; ~245–250 at some retailers) | **Needed for Gate 2.** A multimeter in series misses ms-scale SD/radio bursts and its burden voltage can brown out the board ([FIRMWARE](FIRMWARE.md) §11). |
| | **Subtotal** | | **≈ 175** | Add a small reflow hotplate (~A$40, estimate) only on the bare-board mic route. |

**Recommended**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Second XIAO nRF52840 Sense | Seeed 102010469 | ~29 | One for the bench, one for the build. A spare saves a week if you cook a pad. |
| 1 | Spare 600 mAh LiPo | LB-00237 | 11.30 | |
| 1 | Spare slide switch | ADA805 | 1.90 | |
| | **Subtotal** | | **≈ 42** | |

**Optional**

| Qty | Part | SKU | ≈ A$ | Notes |
|---|---|---|---|---|
| 1 | Second USB-C cable (a second charging spot, or one for the PC and one for the stand) | any | ~10–15 (estimate) | |
| 1 | Hydrophobic acoustic membrane, 3–4 mm, adhesive | any | ~5 (estimate) | Outside the mic port against sweat and rain; costs ~1–2 dB (unverified). |
| 1 | SD load switch (TPS22916/TPS22917 class) on D7, plus a 1 MΩ pull-up | any | ~3 (estimate) | Only if Gate 2 shows SD idle current matters. |
| 1 | SD NAND 512 MB instead of microSD + Pololu | ADA4899 | 17.40 | ~1.3 days ungated (256 KiB slots); see [ALTERNATIVES](ALTERNATIVES.md). |
| 1 | 1100 mAh LiPo (bigger capsule) | CE04377 | 8.65 | Core's URL and image say 1000 mAh; the listing is 1100 mAh. |
| 1 | 400 mAh LiPo (smaller capsule, ~4 mm narrower) | CE04375 | 5.55 | The earlier default. Footprint, weight and protection PCB unconfirmed. |

LiPos ship by road only. Expect 3–7 business days. DigiKey and PCBWay ship from overseas;
order the mics and boards first, because the boards are the longest lead (a week or two, estimate).

**Gate 1:** add everything to the Core, Little Bird and DigiKey carts in a browser and confirm price and stock (Core blocks automated checks, so some prices above come from cached pages), and get a PCBWay quote for the mic board.

## Stage 2: bench bring-up, no soldering into a case yet (2–3 evenings)

Everything is on the bench with USB power first, then battery power.

1. Flash a Zephyr "blinky" over USB (double-tap reset → UF2 drive). *Risk: a charge-only cable → use a data cable.*
2. **Mic test, stock then IM73D122:** record 30 s of PDM to RAM with the **stock** mic and dump it over USB serial → listen on the PC. Check it at 0.3 m, 1 m and 2 m. Then wire the IM73D122 board to D4/D6/D2 (30 AWG, short), check the PDM clock reads **1.28 MHz** on a logic analyser, and repeat the same capture ([FIRMWARE](FIRMWARE.md) T6/T6b). Keep both sets of files for step 8.
3. **SD test:** solder header pins on the Pololu board and breadboard it on D8/D9/D10 plus CS. Write 1 h of fake chunks to the raw ring (decided, [FIRMWARE §8](FIRMWARE.md)), verify the hashes, pull power mid-write, and check the ring recovers.
4. **Antenna location:** confirm on the real board which end the chip antenna is at, and update the CAD parameter. Measure the mic PCB (outline, thickness, sound-hole position) for the lid port.
5. **VBUS check:** multimeter continuity from the USB-C VBUS pin to the 5V pad (expected: a direct connection, no diode), then battery only: the 5V pad reads ~0 V ([WIRING §3](WIRING.md)).
6. **MCUboot via SWD:** solder fine wires to the underside SWD pads, flash MCUboot with the debug probe, and prove that a BLE OTA update, an SMP update over USB CDC, a USB CDC serial recovery and a rollback all work. This is the last chance to use SWD before the case is sealed.
7. **Current measurement** with the **PPK2** (source-meter mode at 3.7–3.8 V on the BAT pads, cell removed; [FIRMWARE §11](FIRMWARE.md)): idle, recording (stock mic and IM73D122), recording + SD, IMU off vs on. A multimeter in series misses ms bursts and can brown out the board, so it doesn't count for this gate. Put the real values into `tools/feasibility.py`. Until then, every current figure is an estimate: ours (3.35 / 7.9 mA with the IM73D122; 3.15 / 7.6 with the stock mic), Boswell's "near 8 mA" budget while live-streaming, and the second review's 10–30 mA chart.
8. **Placement test** (one evening, with a friend who has agreed to be recorded). Put the battery-powered board in a small box with a port hole roughly where the capsule's will be, and record the same 2-minute script in three placements: **outside the shirt at the upper chest**, **at the collar edge**, and **fully under a T-shirt**. Do each one in a **quiet room**, **outdoors** and **walking**: 9 recordings. The script should include names, numbers and a commitment ("I'll send Sam the quote by Friday"). Transcribe them all with the host pipeline and score each on: names right, the commitment captured word for word, and word error rate as a rough guide. Fabric rub while walking is the expected failure.
9. **Stock vs IM73D122** (same evening, same script). Repeat the quiet-room and walking cells of step 8 at the upper chest with **both** mics, in the box with the IM73D122 board mounted behind its port and gasket, plus one **bedside** cell: the box on the nightstand at ~30°, someone speaking quietly at 1.5 m. Switch mics with the firmware build flag, not by moving the box. Score as in step 8, and compare the noise floor in a silent 10 s stretch (dBFS). It is a blind test if a friend renames the files before you listen.

**Gate 2, the most important one.**

| Check | Pass | If it fails |
|---|---|---|
| Average current while recording to SD, measured on the PPK2 over ≥ 10 min | **≤ 8 mA** (model typical 3.35, worst 7.9, with the IM73D122). At 8 mA the 600 mAh cell still gives 450 ÷ 8 ≈ 56 h | > 8 mA: gate the IMU, try another SD card, add a MOSFET to switch the card's power, or move to the 1100 mAh cell (bigger capsule) |
| Speech intelligible to Whisper at 1 m | Transcript word error rate looks usable | Try 24–32 kbps, mic gain, port geometry, the L/R jumper and PDM edge ([FIRMWARE §3](FIRMWARE.md)) |
| Stock vs IM73D122 (step 9) | The IM73D122 is no worse on any cell, and its silent-stretch noise floor is lower (a few dB expected, unverified) | Check the 1.28 MHz clock, the gasket seal and the sound hole. If it still isn't better, ship the stock mic (build flag) and keep the board for v2 |
| Placement test (step 8) | At least one placement you'd actually wear gets names and commitments right in all three settings | Change the port position or windscreen, or wear it outside the shirt. If under-shirt fails everywhere, say so in the docs rather than promise it |
| Raw ring survives power cuts (raw ring is decided; this checks it) | The ring recovers in 20 pulls, losing at most the slot being written (≤ 60 s) | Fix the ring's recovery code before going on ([FIRMWARE §8](FIRMWARE.md)) |
| USB CDC sync throughput (host `SerialTransport`, recording continues) | A 32 kbps day (~346 MB) in < 1 h, i.e. ≥ ~100 KB/s sustained (model: 300 KB/s typical, an **estimate**) | Read the SD in larger multi-block runs, raise `max_frame`, check the host isn't reading 1 byte at a time. Even 50 KB/s moves a 24 kbps day in ~1.4 h, well inside the night |
| BLE bulk throughput to your PC (sets expectations only) | Record the KB/s while recording continues. ≥ 5 KB/s is enough for on-demand pulls and a plain-charger fallback, but a full ungated day takes 14–19 h at 5 KB/s, so a fallback night only part-clears the backlog | Under 5 KB/s: BLE is only for status and small pulls. USB CDC carries the archive anyway |

## Stage 3: firmware MVP (1–2 weeks of evenings, AI-written)

The milestones are in [FIRMWARE.md](FIRMWARE.md). The MVP is PDM → Opus 24 kbps (the firmware recommendation; 16 is the floor, Omi uses 32) → encrypt → 60 s chunk files on SD, plus a list/fetch/ack sync over USB CDC and BLE (the same protocol on both), time sync from the host, and the pause switch. The host side already exists as a tested reference implementation in [`host/`](../host/README.md), running against a simulated device.

*Risk: Opus encoder RAM/CPU on the M4F.* Omi already ships this on the same board (32 kbps, complexity 3), so it's proven. Give the codec thread a **24 KB** stack to start with: Boswell overflowed a smaller one on this board, and measured a 17,944 B high-water mark at 24,576 B.

**Gate 3:** 24 h on the bench running from battery → you get ~24 h of audio on the PC, transcribed, with no gaps over 1 s, and the battery still has **≥ 55%** of its usable capacity. This matches Gate 2 for the 600 mAh cell: the model's worst case is 75% usable, 600 × 0.75 = 450 mAh; 8 mA × 24 h = 192 mAh leaves 258 mAh = 57%. A 55% bar allows up to 450 × 0.45 ÷ 24 ≈ 8.4 mA; a 60% bar would need ≤ 7.5 mA (450 × 0.40 ÷ 24). A real 16 h day at 8 mA uses 128 mAh, 28%. (With the optional 400 mAh cell the bar is ≥ 35%: 300 − 192 = 108 mAh = 36%.)

## Stage 4: print and fit (2–4 evenings, 3–6 test prints)

1. Print a **fit-check shell** in cheap PLA at 0.2 mm (~40 min on an A1 mini). Drop the real parts in.
2. Measure: the battery's real footprint, the mic PCB and its sound hole against the lid port, the switch position, and whether your USB-C cable's plug seats fully through the side slot. Update the CAD parameters and reprint. Expect 2–3 loops.
3. The final shell is in **PETG**. PLA softens in a hot car; PETG and ASA don't.
4. Print the bezel separately (silk/bronze PLA or PETG). See [`concepts/`](../concepts/README.md) for directions.

**Gate 4:** the capsule closes without forcing it, nothing presses on the SD card or USB-C, the cable plugs in fully and the dust cap holds, and the outer size is **≤ ~42 × 50 × 19 mm** (the CAD's 600 mAh core, 41.4 × 49.3 × 18.1; provisional until the CAD has the USB-C slot and mic board) and **≤ ~42 g** with the eagle plate. If it's bigger, see the trade-offs in [`hardware/`](../hardware/README.md).

## Stage 5: final assembly (1 evening)

Wiring is pin-by-pin in [WIRING.md](WIRING.md). Order: battery leads via the protection PCB to the BAT pads (the switch is *not* on the battery line) → SD wires → switch → mic PCB on the lid (gasket under it, four 30 AWG wires to D2/D4/D6/GND) → Kapton over the bare pads → close with the USB-C lined up in its slot.

*Risks:* shorting the LiPo (cut and strip one lead at a time), heat into the cell (keep the iron off the pouch), and a cold joint on the BAT pads (tug-test every wire).

**Gate 5:** the post-assembly current matches the bench current within 10%, BLE RSSI at 3 m through the closed shell is within 6 dB of the bare board, a USB CDC sync and a charge work through the closed shell's slot, and a 30 s recording through the lid port matches the bench IM73D122 recording (no whistle or muffling from the port).

## Stage 6: bedside stand, optional (1 evening)

Print the stand: no electronics, just a weighted cradle holding the capsule at ~30° facing the bed, with a channel for the USB-C cable. Weight the base with washers or steel shot. Run the cable to a USB charger, or to the PC or home server if it's in reach (then it syncs on the stand too; otherwise sync by plugging into the PC some other time, or let BLE fall back).

**Gate 6:** you can drop the capsule in and plug the cable in, in the dark, in one go; the charge LED lights, the capsule keeps recording, and the plug isn't levered by the cradle. If the cable runs to the PC, the overnight sync finishes before morning.

**LiPo safety (it charges unattended every night, sealed, next to your bed).** Use a
cell with a protection PCB, and keep the BQ25101's 10 h safety timer (don't
defeat it in firmware). Stand it on a hard, non-flammable surface, not on
fabric or paper. A sealed shell hides swelling, so check monthly that the lid
still sits flat and the capsule seats in the stand as before; retire any cell
that has swollen, been punctured or run hot. Never charge it in a hot car. Don't
plug it in with sweat or lint in the port: wipe, dry and clear it first.

## Stage 7: home pipeline (1 week, AI-written)

The PC runs the sync client, then decrypts, then server-side VAD (Silero), then faster-whisper, then SQLite + FTS5 search and daily Markdown notes. The reference code is in [`host/`](../host/README.md).

*Risk: compute.* 16 h/day of audio. With a GPU, large-v3 takes about 20–40 min a night. On CPU only, use the small or medium int8 models plus VAD, which runs for hours overnight. That's OK, but worth knowing. On an Apple Silicon Mac, see "Running it at home" in [`host/README.md`](../host/README.md): faster-whisper runs on the CPU there unless you try CTranslate2's new experimental Metal backend.

What sits on top of the transcripts (provenance, correction, guarding against false memories) is in [MEMORY.md](MEMORY.md).

**Gate 7:** you can search for "what did I say about X last Tuesday" and get the right clip, with a link to the audio and the transcript span.

## Stage 8: one-week live trial

Track: hours recorded vs hours worn, battery % at bedtime, sync duration, comfort (neck, sleep), skin irritation, transcript quality, and what you'd actually look up.

**Gate 8 (keep or kill):** after a week, do you use the data? If yes → v2 (better bezel, mic tuning, maybe the Clip). If no → you've spent ~A$230 in parts (plus tools you keep) and some evenings, not A$400 on a closed gadget.

## Failure drills (rehearsed on paper)

| Scenario | What happens | Designed response |
|---|---|---|
| Pendant lost on a train | A stranger has the device | Every chunk is encrypted to your home key, so the SD is unreadable. You lose at most the data since the last sync. |
| PC off for a 3-day trip | No sync | The 32 GB ring buffer holds ~80 days. Nothing is lost. (On the 512 MB SD NAND option, ~1.3 days, the ring would overwrite the oldest un-ACKed audio.) |
| Battery runs flat | The clock is lost | Chunks carry a boot ID and a monotonic counter; the host re-anchors the time at the next sync. |
| Firmware bug bricks it | Sealed case | MCUboot swap-with-revert over BLE or USB CDC; last resort is MCUboot serial recovery over USB CDC through the same USB-C port. UF2 is gone once MCUboot is installed. |
| Hot car, 70 °C dash | Shell deforms; LiPo stress | PETG/ASA shell. Don't leave it in a car (LiPo guidance applies anyway). |
| Someone asks "are you recording me?" | Social or legal | The visible indicator plus the pause switch; delete a time range on the server. |
| USB-C port full of lint, or corroded by sweat | Won't charge or sync | Clear it with a wooden toothpick; the dust cap prevents most of it. If the port dies, BLE still syncs (slowly) and the cell lasts ~2–6 days; then open the case and replace the XIAO. |
| Plugged into a public USB port | A stranger's host sees the device | It can read INFO but can't AUTH, so it can't list, fetch or delete ([SYNC-PROTOCOL §8](SYNC-PROTOCOL.md)). Use a charger or charge-only cable away from home. |

## Verdict

**Viable, at low cost (~A$210–250 in parts, ~A$70–80 of it the mic upgrade, plus ~A$175 of one-off tools: the debug probe and the PPK2) and with no physical blockers.**
The main risks are measured current (Gate 2) and audio quality under a shirt.
Both are tested on the bench before the case is ever printed. The plan is set up
so the most likely failures show up in the first two evenings with ~A$60 of
parts on a breadboard and the PPK2.
