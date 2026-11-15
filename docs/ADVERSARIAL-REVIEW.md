# Adversarial review of the original plan

The starting plan came from a Gemini conversation (see [CREDITS](../CREDITS.md)).
This page re-checks each of its claims against primary sources: vendor pages,
the Seeed wiki, the TI BQ25101 datasheet, the Nordic product spec and the
BasedHardware/omi source. A second AI review (ChatGPT, Nov 2026) is checked
[further down](#second-review-chatgpt-nov-2026). Verdicts: ✅ holds, ⚠️ partly right / needs a change,
❌ wrong. The owner's later decisions (USB-C only, 600 mAh, IM73D122 mic) are
[at the end](#what-changed-after-the-reviews-owner-decisions-nov-2026); the review text
above them is kept as it was written.

## Claims about parts

| Claim | Verdict | What's actually true |
|---|---|---|
| The XIAO nRF52840 Sense is the right brain | ✅ | It is still the best-documented option: Omi DevKit 1/2 used it, and it has a PDM mic, IMU, charger, and BLE. The Omi devkits are now **legacy / community support** (current Omi firmware targets their own CV1 board), so we fork the firmware rather than expect updates. See [ALTERNATIVES](ALTERNATIVES.md). |
| Core SKU `SS102010469`, $29.45 | ⚠️ | Couldn't confirm the SKU or price (Core blocks automated checks). DigiKey AU lists ~A$27.81. Check in the cart. |
| 400 mAh cell `CE04375`, $5.55, 38×25×6 mm, 11 g | ⚠️ | SKU, price and 6 mm thickness are confirmed. **Footprint, weight and protection PCB are not confirmed.** Measure on arrival; the CAD is parametric. |
| 1100 mAh `CE04377`, 51×34×6 mm, 21 g | ✅ | Confirmed: Core's title and description say **1100 mAh**, 51×34×6 mm, 21 g, with a protection circuit. The URL and image still say 1000 mAh, and Core's page notes that 1100 is correct. |
| Pololu `#2597` is 3.3 V direct, 20.3×17.8 mm | ✅ | Correct. It also has a **card-detect** pin (needs a pull-up) that the plan didn't use. |
| `ADA5358` magnetic connector, 21×7×7 mm, self-aligning | ⚠️ | It is one mated pair at 2.54 mm pitch, and the magnets repel if reversed. **No dimensions or current rating are published**, and there is **no mechanical keying**, so the dock cradle must provide it. |
| Qi receiver `ADA1901` coil is 48×32 mm | ⚠️ | The *panel* is 48×32 mm; the coil is 40×29 mm. The conclusion (too big for a 400 mAh capsule) still holds. |
| 26 AWG wire ~$6.15 | ❌ | Closer to **A$12–14** per 7.6 m spool. |
| ICS-43434 mic (`ADA6049`) as an upgrade | ⚠️ | Adafruit lists the ICS-43434 as **discontinued** (they suggest the SPH0645). It's moot anyway, because the requirement is no external mic. |

## Claims from the "5 hidden failure modes" review

| # | Original claim | Verdict | Correction |
|---|---|---|---|
| 1 | Qi plus a magnetic clasp causes heat and Foreign Object Detection trips. Use pogo pins. | ✅ | Pogo pins are the right call: smaller, cheaper, no heat. **Add:** a Schottky diode in the dock's 5V line. The XIAO's 5V pin connects straight to USB-C VBUS with no diode, so a dock plus a USB cable would back-feed. |
| 2 | 50 mA charging stalls overnight; set P0.13 LOW for 100 mA | ⚠️ | The pin polarity is right (LOW = 100 mA, high-Z = 50 mA) and the BQ25101 fast-charge timer is a fixed 10 h. **But it's a non-problem in practice:** a day off the dock uses only ~50–120 mAh (see the model), which refills in 0.7–2.1 h at 100 mA. At 50 mA the worst case is ~5–6 h (50 − 7.6 mA load − 17 mA sync radio ≈ 25 mA net; 122 mAh ÷ 25 mA ≈ 5 h, plus the CV taper), still inside the 10 h timer. The real issue it missed: the **BQ25101 has no power-path**. Recording on the dock draws from the battery node while charging, which can confuse termination (10% of ICHG = 10 mA, the same order as the load). Use 100 mA and log VBAT on the bench. |
| 3 | 24 h of 16 kbps Opus = 173 MB, ~60 min over BLE, so VAD is needed | ⚠️ | The arithmetic is right, but the conclusion is off. The dock gives an **8 h** sync window, so 173 MB fits easily at ≥10 KB/s. The real risk is **Windows BLE throughput** (estimated 10–60 KB/s), combined with Omi's actual default of **32 kbps** (346 MB/day). Fix: use the dock's two spare pogo pins as a **UART** (~90 KB/s, deterministic). Do VAD on the **server** so nothing is lost on the device. |
| 4 | Two-tier stack-up avoids antenna detuning | ❌ | Self-contradictory: it says "keep the battery away from the antenna", then puts the 38 mm battery directly under the 42.3 mm top tier, so only ~4.3 mm of the board overhangs. The XIAO's chip antenna end must sit in that overhang against a plastic-only wall. The CAD enforces this, and the antenna end is a parameter until confirmed on the real board. |
| 5 | A 30° dock aimed at the bed picks up sleep audio at 0.5–1.5 m | ⚠️ | Plausible but unproven. A ~64 dB(A) SNR MEMS mic will catch speech and snoring at 1 m; quiet breathing is doubtful. Test it before designing around it. |

## What the original review missed entirely

1. **The law (the biggest viability risk).** Always-on recording of other people
   is restricted in every Australian state. In **NSW** (and WA, SA, TAS, ACT) even
   a party to a conversation generally needs **all parties' consent**. Recording
   conversations you are not part of is an offence everywhere. See
   [LEGAL.md](LEGAL.md). This shapes the design: a physical **privacy switch** (firmware-enforced), a
   visible **recording indicator**, and private-by-default storage. (NSW also has a
   second limb for a party: a recording not made to communicate the conversation
   to non-parties. Whether a personal archive fits it is untested. See LEGAL.)
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
   becomes a **privacy input**: firmware stops the PDM and cuts mic power (P1.10
   LOW). It is firmware-enforced, not a hardware kill. See [WIRING.md](WIRING.md).
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

The concept is **viable**. Nothing physical blocks it. Against 24 h of
continuous recording a 400 mAh cell has ~1.6× margin in the worst case (39 h)
and ~4.5× typical (108 h); against a 16 h day, 2.4× to 6.8×. The plan needed corrections (diode, antenna
placement, switch role, UART sync, encryption, IMU gating). The legal
constraints are a design input, not an afterthought. (Since then the default cell is
600 mAh: ~57 h worst, ~152 h typical. The diode and UART sync were later dropped with the
dock; see the end of this page.)

## Second review: ChatGPT (Nov 2026)

The owner pasted a second AI review of the same Gemini plan, written by ChatGPT.
Each claim was checked the same way: primary sources first, labelled where we
could only find an estimate.

| Claim | Verdict | Evidence |
|---|---|---|
| Flashing Omi DK2 firmware for microSD is wrong; use the `devkitv1-spisd` config | ❌ | Wrong **for our wiring**. In BasedHardware/omi `omi/firmware/devkit/overlay/`, `xiao_ble_sense_devkitv1-spisd.overlay` puts SD CS on **P0.28** (`gpio0 28`), has no I2S and leaves `uart0` on. `xiao_ble_sense_devkitv2-adafruit.overlay` puts SD CS on **P0.02** (`gpio0 2`; its comment wrongly says P0.28), has I2S on P0.29/P0.28/P0.03 and turns `uart0` off. Both share SPI2 (SCK P1.13, MOSI P1.15, MISO P1.14, 24 MHz). [WIRING](WIRING.md) puts CS on D0/P0.02 to match DK2, with a 1 kΩ on D1 because DK2 drives it as I2S. `spisd` would only be right with CS on P0.28. [FIRMWARE](FIRMWARE.md) M1 stays "DK2 unmodified on our wiring". |
| Omi CV1 is a better hardware reference (nRF5340, 2× T5838, 512 MB NAND, magnetic pogo, open hardware, US$129 promo, 10–14 h vs "2–3 days") | ✅ | Matches [ALTERNATIVES](ALTERNATIVES.md), which already lists all of these. Its 150 mAh cell and ~25.5 mm size are **not confirmed** (Omi's electronics page gives only PCB sizes). It missed the **Seeed reSpeaker Clip**, which ALTERNATIVES ranks first: open firmware, microSD, and sync to your own PC with no cloud. |
| Omi offline storage is "experimental" | ⚠️ | It was. Omi CV1 firmware **v3.0.24** (9 Nov 2026) says "audio is kept until the phone confirms it". It also adds safe-mode recovery after a bad boot, keeps mute on through disconnects and reboots, keeps offline recording going when the SD card is slow to start, and skips the low-battery shutdown while charging. That is our ACK-before-reclaim rule ([SYNC-PROTOCOL](SYNC-PROTOCOL.md)), arrived at independently. ([release](https://github.com/BasedHardware/omi/releases/tag/Omi_CV1_v3.0.24)) |
| Seeed XIAO nRF54LM20A Sense is a better board | ⚠️ | A serious **v2** candidate, not v1: 512 KB RAM (room for Opus), nPM1300 PMIC, 8 MB flash. But recorder firmware for it is immature, and it uses an **external** antenna on an IPEX4 connector, which needs room in the enclosure. Seeed's "3.87 mA active wireless" figure is **unverified**, and it isn't a recording workload anyway. Added to [ALTERNATIVES §2](ALTERNATIVES.md). |
| 400 mAh runs 11–34 h at 10–30 mA | ⚠️ | The arithmetic holds (400 mAh × 85% usable ÷ 10–30 mA), but the currents are **illustrative, not measured**. The closest evidence is Boswell's itemised budget for the same board, "near 8 mA" while live-streaming over BLE, and that is an estimate too. Our model ([`tools/feasibility.py`](../tools/feasibility.py)) gives 3.2 mA typical / 7.6 mA worst with the radio mostly off. Gate 2 (bench current) decides. |
| Room for a 600 mAh cell | ✅ | The CAD already has an 1100 mAh variant, and a 600 mAh option is being added in [`hardware/`](../hardware/README.md). |
| 100 mA charging takes ≥ 4 h from empty | ✅ | True, but rarely relevant: a typical day off the dock uses 50–120 mAh, which refills in 0.7–2.1 h at 100 mA. |
| BLE sync at 50 KB/s moves 230 MB in 77 min | ❌ | The arithmetic is right; the rate is optimistic. Boswell **measured** 5.07 kB/s pulling a file over GATT notifications while still recording, on the same board ([STANDALONE_CAPTURE.md](https://github.com/leakydata/boswell/blob/main/STANDALONE_CAPTURE.md)). That transfer is throttled on purpose so recording keeps running, so it is a floor, not the chip's limit. At 5 KB/s a 24 kbps day (~260 MB) takes ~14 h, more than a night. So the **dock UART** (~90 KB/s, ~0.8 h) becomes the primary sync path. BLE becomes the fallback on a dock with no UART host, plus on-demand pulls; it stays off or barely advertising while worn. |
| Dock with USB data over two pogo pins | ⚠️ | Considered and rejected. USB D+/D− across sprung magnetic contacts is a signal-integrity risk, and USB mass storage fights the recorder for the filesystem (Boswell refuses BLE transfers while a USB host owns the volume, for the same reason). A UART is two wires, any speed works, and the firmware keeps owning the card. |
| Size allowance 52–58 × 33–40 × 14–18 mm, 25–35 g | ✅ | Our CAD is 37.4 × 49.7 × 18.6 mm, ~36 g: shorter than the range, inside it on width, 0.6 mm thicker and ~1 g heavier than its upper end. (Now 41.4 × 44.3 × 18.35 mm with the 600 mAh cell and no dock connector, ~38 g with the eagle plate: wider than the range, 0.35 mm thicker, ~3 g heavier.) |
| Mute must work with USB power present | ✅ | Already covered: [WIRING](WIRING.md), "Docked 'off' isn't off". |
| Test three wearing placements for transcription quality | ✅ | Good idea, and it wasn't explicit. Added to Gate 2 in [BUILD-SIMULATION](BUILD-SIMULATION.md) as a placement protocol. |
| Security: authenticated access, encryption at rest, physical off control, status indication, home interface only on the private network or Tailscale | ✅ | The first four are in [SYNC-PROTOCOL](SYNC-PROTOCOL.md) (LESC bonding + AUTH, X25519/AES-GCM per chunk), [WIRING](WIRING.md) and [LEGAL](LEGAL.md). The network note is now in [`host/README.md`](../host/README.md). |
| Mac at home: whisper.cpp on Apple Silicon, storage on a NAS | ⚠️ | whisper.cpp runs fully on the GPU via Metal, with an optional Core ML encoder on the Neural Engine. Our host uses **faster-whisper**, whose CTranslate2 backend only gained an **experimental** Metal (`device="mps"`) backend in v4.9.0 (10 Nov 2026), and `device="auto"` still picks the CPU. We haven't tested faster-whisper on MPS. See "Running it at home" in [`host/README.md`](../host/README.md). |
| A memory layer, not just a recorder | ✅ | Right, and missing. New page: [MEMORY.md](MEMORY.md). |
| Prices (Core, AUD inc GST): XIAO $29.45, CE04375 $5.55, POLOLU-2597 $8.30, ADA5358 $12.80 (out of stock), ADA805 $1.90, wire ADA2518 $12.65; prototype $90–140 | ⚠️ | We couldn't recheck them: Core blocks automated checks. ADA2518 is the **white** 25 ft (7.6 m) 26 AWG silicone wire, and ADA2517 is the same wire in **black**, so both SKUs are valid. ADA5358 was in stock at Adafruit on 15 Nov 2026, but Core's stock is unknown. Treat it as the part most likely to hold up the order. |

Boswell ([leakydata/boswell](https://github.com/leakydata/boswell), Apache-2.0)
is a small, early, local-first recorder: Zephyr firmware on the same XIAO
nRF52840 Sense, with Opus, SD, BLE and USB offload. It's the most useful outside
evidence in this round, because it reports measurements from real hardware:

| Boswell finding (on hardware) | What it means for us |
|---|---|
| The Opus capture thread overflowed its stack. It was fixed at a 24,576 B stack, with a measured high-water mark of 17,944 B | [FIRMWARE](FIRMWARE.md) now starts the codec stack at **24 KB** (it was 16–24), then measures. |
| Worst single SD write: 203 ms, absorbed by a RAM ring | Inside the 100–500 ms stall our 16 KB encoded queue (~5 s at 24 kbps) is sized for. |
| Frames replayed from flash after a reboot were filed under the current boot's `boot_id` | Our chunk header carries the `boot_id` of the boot that **captured** the audio ([SYNC-PROTOCOL](SYNC-PROTOCOL.md)). Keep that true for any replay or recovery path, too. |
| ZF-06: "BLE control is unauthenticated" (its own review) | We need LESC bonding plus protocol AUTH before any destructive command. |
| BLE file transfer is refused while a USB host owns the volume | Another reason not to expose the card as USB mass storage. |
| Transcription wants NVIDIA CUDA, then Apple MPS, then CPU | The same trade-off as our host ([`host/README.md`](../host/README.md)). |

### What changed in the plan

- **The dock UART is built from the start** and is the primary sync path (superseded: USB CDC over the capsule's USB-C port replaced it, see the next section). BLE is the fallback (docked with no UART host, or an on-demand pull), not a continuous daytime link, and its Gate 2 check now only sets expectations ([BUILD-SIMULATION](BUILD-SIMULATION.md)).
- Gate 2 gains a **three-placement audio test** (upper chest outside the shirt, collar edge, under a T-shirt) × (quiet room, outdoors, walking), judged on names and commitments.
- The codec thread stack starts at **24 KB** (Boswell's measurement), not 16.
- **XIAO nRF54LM20A Sense** and **Boswell** are added to [ALTERNATIVES](ALTERNATIVES.md). Boswell is also in [CREDITS](../CREDITS.md) as a reference; we copied no code.
- New [MEMORY.md](MEMORY.md): provenance, said / verified / committed / inferred, correction and deletion, and guarding against false memories.
- [`host/README.md`](../host/README.md) gains "Running it at home" (NAS for storage, Apple Silicon Mac for transcription, private network or Tailscale only).
- The wire SKU note now says that ADA2517 and ADA2518 are the same wire in black and white, and ADA5358 stock is flagged as a risk.

## What changed after the reviews (owner decisions, Nov 2026)

Three decisions by the owner, applied across the docs. The verdicts above are kept as
written; where they cite the pogo dock, its diode or the dock UART, read them as history.

| Decision | What it replaces | Why, and the cost |
|---|---|---|
| **USB-C is the only charge and sync path.** Plug a cable into the capsule's side port: any charger charges it (100 mA, still recording); the PC also syncs it over **USB CDC-ACM** with the same SLIP + CRC-32 framing. BLE stays as the wireless fallback and on-demand pull. The nightstand dock becomes an optional printed stand with no electronics | The ADA5358 magnetic pogo connector, the dock's Schottky diode (claim 1 above), its USB-C breakout, and the dock UART through the spare pogo pins (claim 3 and the ChatGPT row on BLE sync) with a USB-serial adapter | Fewer parts (~A$30 less), no back-feed problem to design around (nothing else feeds the 5V pin), no pin map that can mate rotated, and a faster link: USB CDC is estimated at ~100–300 KB/s, vs ~90 KB/s for the UART (an **estimate**; T11 measures it). The earlier objection to "USB data over two pogo pins" (sprung magnetic contacts) doesn't apply to a real USB-C plug. Cost: the USB-C port is worn-exposed (dust cap, sweat, lint, connector wear), and plugging in is a two-handed job in the dark. [WIRING §3](WIRING.md), [SYNC-PROTOCOL §5](SYNC-PROTOCOL.md) |
| **Default battery 600 mAh** (Little Bird LB-00237, 29 × 36 × 5.5 mm, 10.5 g) | The 400 mAh CE04375 default (now an option, as is 1100 mAh) | 50% more charge for ~4 mm of width (CAD). Model: ~152 h typical, ~57 h worst. Gate 3's bar moves from 35% to 55% left ([BUILD-SIMULATION](BUILD-SIMULATION.md)). The listing claims built-in protection; not yet checked on a cell |
| **Better mic: one Infineon IM73D122 on a small custom PCB** (PDM CLK D4, DATA D6, power D2; onboard mic held off) | The stock mic for v1, and the T5838 upgrade path in [ALTERNATIVES §3](ALTERNATIVES.md#3-microphone-choice) | ~+6–7 dB SNR at our 1.28 MHz clock (unverified), ~+0.1–0.5 mA (unverified), ~A$70–80. **Correction:** the earlier T5838 recommendation was wrong for the nRF52840, whose 16 kHz PDM clocks (1.0–1.33 MHz) fall between the T5838's low-power and high-quality modes. The IM73D122's normal mode (1.2–1.65 MHz) covers 1.28 MHz; the 1.032 MHz default is out of its spec. Gate 2 compares it with the stock mic |
