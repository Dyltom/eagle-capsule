# Alternatives: better hardware, or just buy something?

*Researched 15 November 2026. Prices move and several products are in pre-sale, so check every price and stock level before buying. "~A$" means a rough conversion at about A$1.55 per US$ (check the current rate). Where sources disagreed, both figures are given.*

## Recommendation

1. **Buy a Seeed Studio reSpeaker Clip first, if you can get one.** It is very close to a finished Eagle Capsule: nRF5340 + nRF7002, dual PDM mics, Opus audio stored on a microSD card plus 64 Mbit flash, a 4-pin magnetic charging base, and **Apache-2.0 firmware** on Zephyr/nRF Connect SDK. A Python SDK pulls recordings over BLE or over the Clip's own Wi-Fi access point, and Seeed says no API key or backend is needed. That is exactly the "no third-party cloud, sync to my own PC" model. ([Seeed wiki](https://wiki.seeedstudio.com/respeaker_clip/), [GitHub: Seeed-Studio/reSpeaker_Clip](https://github.com/Seeed-Studio/reSpeaker_Clip), [Basic SDK guide](https://wiki.seeedstudio.com/respeaker_clip_basic_sdk_guide/))
   - **Risks to check before relying on it:** rated 14–18 h of continuous recording, which only just covers a 16 h wearing day. It is in pre-sale or out of stock at most retailers, including Pakronics in Australia (A$170.72). Its size and weight on the body haven't been published. We haven't confirmed that it keeps recording while on the charging base, which the sleep-recording plan needs. The firmware is open, so AI-written changes can add the 24/7 ring buffer and record-while-charging behaviour. You'd also be debugging someone else's code base rather than writing your own.
2. **If the Clip isn't available, or turns out too big, keep building the DIY capsule with one change: replace the Pololu #2597 microSD breakout with soldered SD NAND.** Adafruit #4899, the XTSD 512 MB, is A$17.40 at Core Electronics and comes pre-formatted FAT. You use it through the normal SD library, and it has no removable card or spring contacts to work loose. 512 MB holds roughly 3 days of ungated 16 kbps Opus. ([Core Electronics](https://core-electronics.com.au/adafruit-spi-flash-sd-card-xtsd-512-mb.html.md)) The XIAO nRF52840 Sense stays the right board for that build.
3. **Don't buy Limitless, Bee, Friend or Plaud for this project.** None of them lets you keep raw audio, all day and night, without the vendor's app or cloud. See section 1.
4. **The Omi consumer pendant is the second-best buy**, about US$129. Its firmware and hardware are MIT-licensed, it has an nRF5340, two TDK T5838 mics and 512 MB of SD NAND. But it's rated for only 10–14 h, and pulling stored audio to your own PC without Omi's app means writing your own sync code.
5. **A better microphone is a small win for sleep and room audio, and it isn't worth a custom PCB in version 1.** A quiet bedroom's own noise is about as loud as a cheap MEMS mic's self-noise. Mic placement, the acoustic port and fabric noise matter more. See section 3.

**One non-hardware point that matters more than any part choice.** In NSW, recording a private conversation without consent is an offence under s 7 of the *Surveillance Devices Act 2007* (NSW), with a maximum of 5 years and/or A$55,000. The exception for a party to the conversation is narrow: the recording must be "reasonably necessary" to protect that party's lawful interests. An always-on recorder will capture other people, and sleep audio will capture a partner. Get informed consent from household members and have a clear policy for visitors. ([NSW legislation](https://legislation.nsw.gov.au/view/whole/html/inforce/2024-07-01/act-2007-064), [Sydney Criminal Lawyers summary](https://www.sydneycriminallawyers.com.au/?p=52249))

---

## 1. Commercial options (late 2026)

| Product (maker) | Price | Battery (recording) | Offline storage | Get raw audio locally, without the vendor cloud? | Weight | Verdict |
|---|---|---|---|---|---|---|
| **reSpeaker Clip** (Seeed Studio) | A$170.72 Pakronics (out of stock); £79.10 Pi Hut; €99.95–109.95 OpenELAB (pre-sale) | 14–18 h continuous | 2 GB stated on the wiki (~140–250 h of Opus); the repo lists microSD + 64 Mbit flash | **Yes.** Apache-2.0 firmware, Python SDK, BLE and Wi-Fi AP (UDP, CRC-checked) sync, USB mass storage of the SD card | Not published (0.08 kg listed is probably the packaged weight) | **Best fit. Buy if available.** |
| **Omi pendant, CV1** (Based Hardware) | US$129 promo (list US$179), ~A$200; ships worldwide | 10–14 h on the product listings; the page also says "2–3 days" (probably not continuous recording) | 512 MB SD NAND (CSNP4GCR01) | **Partly.** Firmware, hardware files and SDKs are MIT. Live BLE audio is easy to get with the SDK; offline-storage sync to your own PC needs custom code | Not published | Good fallback, short battery |
| Omi DevKit 1 / DevKit 2 (Based Hardware) | **No longer sold** | — | DevKit 2: 8 GB | Yes (open) | — | Not buyable; our design is essentially a DevKit 2 rebuild |
| **Limitless Pendant** (now Meta) | **Discontinued for new buyers** since Meta's acquisition on 5 Dec 2025 | Reviewers measured 6–10 h, not the advertised 100 h | None: cloud only | No. Existing users must accept new terms; service ended in the EU, UK and other regions | ~32 mm × 16 mm; weight not published | Not available |
| **Bee Frontier / Eclipse** (Amazon) | US$74.99 / US$99.99 (launched 15 Oct 2026, US); no official AU listing found | Up to 7 days (Frontier) | **Doesn't keep raw audio.** It is processed and deleted; only transcripts are kept | No | Not published | Wrong product for an audio archive |
| **Friend** (Friend, Avi Schiffmann's company) | US$249 (July 2026 relaunch) | Up to 15 h claimed; some users reported ~4 h on the older model | Reports conflict (a 32 MB ring buffer of about 3 h, or none) | No: a cloud "companion" | Not published | Not suitable |
| **Plaud NotePin** (Plaud) | A$269 (Plaud AU); A$244.78 + GST PB Tech | ~20 h continuous | 64 GB | **Only through the Plaud app.** USB is not mass storage. The app can export MP3/WAV | 16.6 g (without clip) | Best battery and storage of the closed devices, but not designed for 24/7 or open sync |

Sources: reSpeaker Clip: [Seeed wiki](https://wiki.seeedstudio.com/respeaker_clip/), [GitHub repo](https://github.com/Seeed-Studio/reSpeaker_Clip), [Pakronics](https://www.pakronics.com.au/products/respeaker-clip-open-wearable-ai-recorder-ss100020126), [The Pi Hut](https://thepihut.com/products/respeaker-clip-open-wearable-ai-recorder), [OpenELAB](https://openelab.com/products/seeed-studio-respeaker-clip-open-wearable-ai-recorder). Omi: [product page](https://www.omi.me/pages/pendant), [CV1 electronics](https://docs.omi.me/doc/hardware/consumer/electronics.md), [consumer hardware licence](https://docs.omi.me/doc/hardware/consumer), [DevKit 2 docs](https://docs.omi.me/doc/hardware/DevKit2), [Python SDK](https://docs.omi.me/doc/developer/sdk/python), [Layer3 Labs on DevKit availability](https://www.layer3labs.io/guides/omi-dev-kit-2), [BasedHardware/omi](https://github.com/BasedHardware/omi). Limitless: [limitless.ai](https://limitless.ai/), [TechInformed](https://techinformed.com/meta-acquires-limitless-pendant-users-moved-to-free-unlimited-plan/), [fast.io review](https://fast.io/resources/limitless-ai-review-2026/). Bee: [TechCrunch, 15 Oct 2026](https://techcrunch.com/2026/10/15/amazons-bee-launches-two-new-personal-AI-devices-starting-at-75). Friend: [The Gadgeteer](https://the-gadgeteer.com/2026/07/31/friend-ai-pendant-voice-wearable-249-price/), [Let's Data Science](https://letsdatascience.com/news/friend-relaunches-ai-pendant-with-speaker-for-249-85de4fb2). Plaud: [Plaud AU review page](https://au.plaud.ai/blogs/articles/plaud-notepin-review), [Plaud hardware comparison](https://www.plaud.ai/pages/hardware-comparison), [PB Tech](https://www.pbtech.com/au/product/AUDPAU0004/Plaud-AI-Note-Taker-Plaud-NotePin---Sunset-Purple), [Plaud support: USB access](https://support.plaud.ai/hc/en-us/articles/53788775968409-Can-I-access-Plaud-NotePin-S-recordings-by-connecting-to-a-PC-via-USB).

Note on names: the open-source project now called **Omi** (Based Hardware) was originally called "Friend". It is unrelated to the closed **Friend** pendant from friend.com.

### Open-hardware pendants worth knowing about

| Project (author) | Hardware | Storage | Licence | Notes |
|---|---|---|---|---|
| **Omi CV1 / DevKits** (Based Hardware) | nRF5340 + nRF7002 (CV1); XIAO nRF52840 Sense (DevKits) | SD NAND / microSD | MIT (KiCad, Gerbers, STEP, BOM, firmware) | The main prior art; already credited in CREDITS.md. [docs](https://docs.omi.me/doc/hardware/consumer) |
| **reSpeaker Clip** (Seeed Studio) | nRF5340 + nRF7002 + nPM1300 PMIC | microSD + 64 Mbit flash | Apache-2.0 firmware and SDKs; no schematics in the repo | [repo](https://github.com/Seeed-Studio/reSpeaker_Clip) |
| **Omoidase** (Marvil) | ESP32, Wi-Fi sync, microSD, USB-C | microSD | AGPLv3 software, CERN-OHL-S v2 hardware | [Codeberg](https://codeberg.org/marvil/omoidase), [write-up](https://marvil.co/blog/portfolio/2025-11-10-omoidase/) |
| **Aura** (GitHub user thesohamdatta) | XIAO ESP32-S3, Omi-compatible | — | Open (STLs on GitHub) | ~US$50–70 build. [docs](https://thesohamdatta.github.io/aura/docs.html) |
| **Owl** (Owl project contributors) | ESP32-S3 / Sony Spresense | — | Open source | Always-on wearable AI platform. [overview](https://osrtos.com/projects/owl-always-on-wearable-ai) |

The ESP32-based projects all share the power problem described in section 2.

---

## 2. Alternative DIY boards

Data budget for sizing storage: 16 kbps Opus is about 7.2 MB per hour, or about 173 MB per 24 h without voice-activity gating (32 kbps doubles that).

| Board (maker) | SoC | Onboard mic | Charger | Flash for audio | Recording current | Firmware ecosystem | Verdict |
|---|---|---|---|---|---|---|---|
| **XIAO nRF52840 Sense** (Seeed), *current plan* | nRF52840, 64 MHz M4F | PDM; the wiki now lists **WMM7035DTTJ0** (older batches used MSM261D3526H1CPM) | BQ25101, 50/100 mA | 2 MB QSPI (about 17 min of audio) | Low single-digit mA (our model: ~3–4 mA) | Mature: Zephyr/NCS, Arduino, and Omi DevKit firmware to copy from | **Keep** |
| **XIAO nRF54L15 Sense** (Seeed) | nRF54L15, 128 MHz M33 | PDM **MSM261DGT006** | Built-in PMIC/charger (part not stated) | 1.5 MB on-chip NVM; no large external flash | Probably lower than nRF52840 for the same Opus job (newer process); not measured | NCS ≥ 3.0.1 only; young, with no Omi port | A small power gain for a lot of porting risk; not worth it yet |
| **XIAO ESP32S3 Sense** (Seeed) | ESP32-S3 | PDM on the camera add-on board | 100 mA | 8 MB flash + 8 MB PSRAM + **onboard microSD slot** | **~54–65 mA** average while recording to SD (Seeed's figure) | Arduino/ESP-IDF | **Ruled out:** about 6 h from 400 mAh |
| **Arduino Nano 33 BLE Sense Rev2** (Arduino) | nRF52840 | MP34DT06JTR (ST, ~64 dB SNR) | **None** | 1 MB internal | Like the XIAO | Arduino Mbed | Bigger (45 × 18 mm), no charger: worse in every way |
| **Nordic Thingy:53** (Nordic) | nRF5340 | VM3011 PDM, wake-on-sound | nPM1100 | — | — | NCS | A large dev box with a 1350–1500 mAh cell: a lab tool, not a wearable |
| nRF5340 in a pendant (Omi CV1, reSpeaker Clip) | nRF5340 | T5838 ×2 (Omi) | BQ25101 / nPM1300 | 512 MB SD NAND / microSD | — | NCS | Only comes as finished products; no small nRF5340 + mic + charger dev board exists |

Sources: [XIAO nRF52840 wiki](https://wiki.seeedstudio.com/XIAO_BLE/), [XIAO nRF54L15 Sense wiki](https://wiki.seeedstudio.com/xiao_nrf54l15_sense_getting_started/), [CNX Software on the nRF54L15 XIAO](https://www.cnx-software.com/2025/07/31/seeed-studio-xiao-nrf54l15-usb-c-boards-support-matter-thread-zigbee-and-amazon-sidewalk/), [XIAO ESP32S3 wiki (power table)](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/), [Arduino Nano 33 BLE Sense Rev2 docs](https://docs.arduino.cc/hardware/nano-33-ble-sense-rev2), [Nordic Thingy:53 hardware guide](https://docs.nordicsemi.com/r/bundle/ug_thingy53/page/ug/thingy53/intro/frontpage.html).

### Would big onboard QSPI flash remove the microSD breakout?

**Mostly, no.** No board in the XIAO size class has more than a few MB of flash, and 2 MB holds about 17 minutes of audio. NOR flash big enough for a day (128 MB or more) is costly and isn't on any of these boards.

The right swap is **SD NAND**: an SD card in a solderable chip package. Omi CV1 does exactly this with a 512 MB CSNP4GCR01. For us the easy version is **Adafruit #4899, the XTSD 512 MB breakout**. It uses the same SPI wiring and the same Zephyr `disk/sdmmc` + FAT code as the Pololu card, and does its own wear levelling and ECC.

Trade-offs: 512 MB is about 3 days at 16 kbps without gating, about 1.5 days at 32 kbps, and more with VAD. That is enough, because the device syncs every night. You can't pull the chip and read it in a PC, but you couldn't do that with a microSD card sealed inside the capsule either. It also removes the card-slot spring contacts, the most likely thing to fail in a capsule that gets knocked about. ([Core Electronics](https://core-electronics.com.au/adafruit-spi-flash-sd-card-xtsd-512-mb.html.md), [OSHWA certification](https://certification.oshwa.org/us001077.html))

---

## 3. Microphone choice

| Mic | Where | SNR | Notes |
|---|---|---|---|
| WMM7035DTTJ0 (Will Semi) | XIAO nRF52840 Sense, per the current wiki | **Not published** (the family is marketed as "high SNR") | We couldn't find a datasheet |
| MSM261D3526H1CPM (MEMSensing) | Earlier XIAO nRF52840 Sense, XIAO ESP32S3 Sense | ~64 dB(A) (secondary summary; we couldn't check the image-only datasheet) | Top port, −26 dBFS |
| MSM261DGT006 (MEMSensing) | XIAO nRF54L15 Sense | Not found | — |
| MP34DT06JTR (ST) | Nano 33 BLE Sense Rev2 | ~64 dB | — |
| **TDK T5838** | Omi CV1 (×2) | **68 dB(A)** HQ mode at 310–330 µA; 65 dB(A) low-power mode at 120–130 µA | **Acoustic Activity Detect** at ~20 µA can wake the MCU on sound. Bottom port, 3.5 × 2.65 mm |
| **Infineon IM73D122** | — (bare part) | **73 dB(A)** | ~980 µA; 4 × 3 mm LLGA; no breakout found; long lead times reported |

Sources: [Seeed XIAO wiki](https://wiki.seeedstudio.com/XIAO_BLE/), [MSM261D3526H1CPM datasheet (MEMSensing)](https://cdn.shopify.com/s/files/1/0174/1800/files/mic-MSM261D3526H1CPM-ENG.pdf), [TDK T5838 datasheet](https://www.mouser.lt/catalog/specsheets/TDK_DS-000383-T5838-v1.0.pdf), [TDK T5838 announcement](https://invensense.tdk.com/news-media/tdk-introduces-worlds-lowest-power-PDM-microphone-with-acoustic-activity-detect/), [Infineon IM73D122](https://infineon.com/cms/en/product/sensor/mems-microphones/mems-microphones-for-consumer/im73d122).

**Is a better mic worth it for sleep and room capture at 0.5–1.5 m?** Self-noise equals 94 dB SPL minus SNR:

- A ~64 dB(A) mic has about **30 dB(A)** of self-noise.
- A T5838 has about 26 dB(A). An IM73D122 has about 21 dB(A).
- A quiet bedroom is roughly 25–35 dB(A) (a typical figure, not measured here). Normal speech at 1 m is roughly 55–60 dB SPL, and drops about 6 dB per doubling of distance.

So for daytime talking, any of these mics is fine. For quiet sleep-talk at 1.5 m, the stock mic's hiss is about as loud as the room. A 73 dB(A) part would give a few dB of real improvement, not a transformation. In practice these matter more:

- **Placement and the acoustic port:** a clear port hole, a short sealed path to the mic and a light mesh, not a mic buried behind 2 mm of PETG.
- **Fabric:** under a shirt, cloth rubbing against the capsule is the dominant noise, and no mic SNR fixes it. Put the port on the outward face and add a small foam or felt windscreen. The reSpeaker Clip's SpeexDSP noise suppression and AGC chain is worth copying in firmware.
- **On the dock at night:** the capsule sits still in open air, which is the best case. Use a higher bitrate (32 kbps) and turn off aggressive AGC at night.

The upgrade path, if v1 recordings disappoint: a T5838 on a tiny custom PCB (JLCPCB/PCBWay with assembly) wired to the XIAO's PDM pins. It gives +4 dB SNR plus the hardware wake-on-sound feature, which could save power during silent stretches. It is not worth it before you've heard v1 audio. An extra mic inside the **dock** is another option for sleep audio: nothing dangles from the wearable, though it does add a second recording device.

---

## 4. Bottom line

- **Buy, don't build, if a reSpeaker Clip can be had.** It is the only thing on the market that is open, stores Opus locally, docks magnetically and syncs to your own PC with no cloud. About A$170 is less than the DIY parts plus your time. Check the battery against your 16 h day and confirm it records while on its base. If it doesn't, the Apache-2.0 firmware lets AI-written code fix that.
- **Otherwise build as planned**, with Adafruit #4899 SD NAND instead of the Pololu microSD, the stock XIAO nRF52840 Sense mic, and careful port design. Keep the Omi DevKit 2 firmware (MIT) as the reference.
- **Skip** Limitless (discontinued), Bee (doesn't keep audio), Friend (cloud companion), Plaud (app-gated) and the ESP32-S3 boards (about 15× the power draw).
- Sort out **consent** with the people you live with before switching on 24/7 recording.

*Credits: product and project names belong to their owners: Seeed Studio, Based Hardware (Omi), Meta/Limitless, Amazon/Bee, Friend, Plaud, Nordic Semiconductor, Arduino, Adafruit Industries, Pololu, TDK InvenSense, Infineon, MEMSensing, Will Semiconductor, STMicroelectronics, Marvil (Omoidase), the Aura and Owl authors, and the retailers cited (Core Electronics, Pakronics, The Pi Hut, OpenELAB, PB Tech). This project is not affiliated with any of them.*
