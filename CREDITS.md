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
| **Friend, Limitless Pendant, Plaud NotePin, Bee** | Commercial reference points for weight, form factor and how a wearable recorder fits into daily life | their respective sites | proprietary; used only for comparison |

## Hardware

| Part | Maker | Notes |
|---|---|---|
| XIAO nRF52840 Sense (102010469) | **Seeed Studio** | MCU, PDM mic, IMU and LiPo charger. Docs: https://wiki.seeedstudio.com/XIAO_BLE/ |
| nRF52840 SoC | **Nordic Semiconductor** | The radio and CPU |
| BQ25101 charger IC | **Texas Instruments** | The charger on the XIAO |
| microSD breakout #2597 | **Pololu** | https://www.pololu.com/product/2597 |
| DIY Magnetic Connector #5358, slide switch #805, silicone wire #2517/2518, Qi receiver #1901 (evaluated and rejected) | **Adafruit Industries** | https://www.adafruit.com |
| SPI SD NAND #4899 (optional alternative to microSD) | **Adafruit Industries** | |
| Debug Probe | **Raspberry Pi Ltd** | One-time SWD flashing of MCUboot |
| LiPo cells CE04375 / CE04377 | **Core Electronics** | Australian supplier for the parts list: https://core-electronics.com.au |

## Software we plan to use

| Project | Use | License |
|---|---|---|
| Zephyr RTOS / nRF Connect SDK | Firmware base | Apache-2.0 / Nordic 5-Clause |
| Opus codec (Xiph.Org) | Audio compression on the device | BSD-3-Clause |
| OpenAI Whisper and SYSTRAN faster-whisper | Local transcription | MIT |
| Silero VAD | Server-side voice activity detection | MIT |
| bleak | BLE from Python on the PC | MIT |
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
- Every claim we kept from the original plan has been rechecked. Claims that
  turned out wrong are listed in [`docs/ADVERSARIAL-REVIEW.md`](docs/ADVERSARIAL-REVIEW.md).

Trademarks (Omi, XIAO, Adafruit, Pololu, Nordic, Bambu Lab, and others) belong
to their owners. This project is not affiliated with or endorsed by any of them.
