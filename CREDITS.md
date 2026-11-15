# Credits

Eagle Capsule builds on other people's work. Credit for the ideas, parts and
software goes to the people below. If something here is yours and it is missing
or wrong, please open an issue and we'll fix it.

## Inspiration and prior art

| Who | What we took from it | Link | License |
|---|---|---|---|
| **BasedHardware / Omi** | The idea that a Seeed XIAO nRF52840 Sense plus a LiPo can be an open-source wearable AI recorder. Also the DevKit 1/2 reference designs, the Opus-over-BLE firmware approach, the microSD offline storage in DevKit 2, and the Python BLE decoder. | https://github.com/BasedHardware/omi | MIT (check the repo for per-folder terms) |
| **Creator of the YouTube build video** that started this project (the DIY Omi-style pendant build) | The proof that someone from a software background can build one | https://www.youtube.com/watch?v=NQvFSRMcvz4 | - |
| **Seeed Studio reSpeaker Clip** | Evaluated as the best buy-and-customise alternative: open wearable recorder, nRF5340, Wi-Fi sync | https://github.com/Seeed-Studio/reSpeaker_Clip | Apache-2.0 |
| **Boswell** (GitHub user leakydata) | A reference only; we copied no code. Its measurements on the same XIAO nRF52840 Sense shaped our numbers: Opus stack high-water, worst SD write, BLE file-pull rate, and the replayed-frame `boot_id` bug. Its rule that every remembered item must cite the words it came from, and who said them, shaped [`docs/MEMORY.md`](docs/MEMORY.md). | https://github.com/leakydata/boswell | Apache-2.0 |
| **Friend, Limitless Pendant, Plaud NotePin, Bee** | Commercial reference points for weight, form factor and how a wearable recorder fits into daily life | their respective sites | proprietary; used only for comparison |

## Hardware

| Part | Maker | Notes |
|---|---|---|
| XIAO nRF52840 Sense (102010469) | **Seeed Studio** | MCU, PDM mic, IMU and LiPo charger. Docs: https://wiki.seeedstudio.com/XIAO_BLE/ |
| nRF52840 SoC, Power Profiler Kit II | **Nordic Semiconductor** | The radio and CPU; the PPK2 measures current for Gate 2 |
| BQ25101 charger IC | **Texas Instruments** | The charger on the XIAO |
| IM73D122 PDM MEMS microphone | **Infineon Technologies** | The capsule's mic, on a small custom PCB. Datasheet: https://www.infineon.com/dgdl/Infineon-IM73D122-DataSheet-v01_00-EN.pdf?fileId=8ac78c8c83cd3081018409cafdfb46db |
| microSD breakout #2597 | **Pololu** | https://www.pololu.com/product/2597 |
| Slide switch #805, silicone wire #2517/2518 (26 AWG) and #3164/3169 (30 AWG). Evaluated and dropped: Qi receiver #1901, and the DIY Magnetic Connector #5358 and USB-C breakout #4090 of the earlier pogo dock (USB-C on the XIAO replaced them) | **Adafruit Industries** | https://www.adafruit.com |
| SPI SD NAND #4899 (optional alternative to microSD) | **Adafruit Industries** | |
| Debug Probe | **Raspberry Pi Ltd** | One-time SWD flashing of MCUboot |
| LiPo cells CE04375 (400 mAh) / CE04377 (1100 mAh), both options | **Core Electronics** | Australian supplier for the parts list: https://core-electronics.com.au |
| LiPo cell LB-00237 (600 mAh, the default) | **Little Bird Electronics** | https://littlebirdelectronics.com.au/products/lithium-ion-polymer-battery-3-7v-600mah |
| IM73D122 supply | **DigiKey** | https://www.digikey.com.au/en/products/detail/infineon-technologies/IM73D122V01XTMA1/16999563 |

## Software we plan to use

| Project | Use | License |
|---|---|---|
| Zephyr RTOS / nRF Connect SDK | Firmware base | Apache-2.0 / Nordic 5-Clause |
| Opus codec (Xiph.Org) | Audio compression on the device | BSD-3-Clause |
| OpenAI Whisper and SYSTRAN faster-whisper | Local transcription | MIT |
| Silero VAD | Server-side voice activity detection | MIT |
| bleak | BLE from Python on the PC | MIT |
| pyserial | USB CDC serial sync from Python on the PC | BSD-3-Clause |
| pyca/cryptography | X25519, HKDF, AES-GCM in the host pipeline | Apache-2.0 / BSD |
| MCUboot | Bootloader for over-the-air updates | Apache-2.0 |
| OpenSCAD | Parametric enclosure | GPL-2.0 (the tool; models we make with it are ours) |
| Blender | Concept renders | GPL-2.0+ (the tool; renders are ours) |

## How this plan was made

- The first parts list and architecture came from a planning conversation with
  **Google Gemini**, which cited ZeroShot Studio for its battery-life estimates.
- **Anthropic's Claude** (Claude Code, Opus 5.5) did the independent check: it
  verified parts against vendor pages, built the feasibility model, wrote the
  dry-run build and set up this repository.
- A second review by **OpenAI's ChatGPT** (Nov 2026) was checked claim by claim
  in the same way. Its verdicts are at the end of
  [`docs/ADVERSARIAL-REVIEW.md`](docs/ADVERSARIAL-REVIEW.md).
- Every claim we kept from the original plan has been rechecked. Claims that
  turned out wrong are listed in [`docs/ADVERSARIAL-REVIEW.md`](docs/ADVERSARIAL-REVIEW.md).

Trademarks (Omi, XIAO, Adafruit, Pololu, Nordic, Infineon, Bambu Lab, and others) belong
to their owners. This project is not affiliated with or endorsed by any of them.
