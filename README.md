# 🦅 Eagle Capsule

**An open, private, always-on wearable memory recorder.** A ~38 g pebble worn
on a cord records your day. At night a USB-C cable charges it and syncs it, and on
an optional printed stand by the bed it records sleep audio while it charges.
Everything syncs to **your own computer**: encrypted on the device, transcribed
locally, and searchable. No accounts, no vendor cloud.

> **Status: paper-validated, not yet built.** This repo is the complete pre-purchase
> dry run: parts checked against vendor pages, a numerical feasibility model, CAD,
> firmware architecture, a tested host-side sync pipeline against a simulated device,
> and concept renders. The physical build comes next.

> ⚠️ **Read [docs/LEGAL.md](docs/LEGAL.md) first.** Recording other people's private
> conversations without consent is an offence in every Australian state. In NSW even
> a party to the conversation needs everyone's consent unless a narrow exception
> applies, and it is untested whether a personal memory archive fits one.
> The design includes a firmware-enforced privacy switch (it cuts power to the mic) and a
> recording indicator for this reason.

![concepts](concepts/renders/01-lowpoly.png)

## Verdict

**Viable. About A$210–250 in parts (~A$70–80 of it is the mic upgrade: five IM73D122s and five assembled boards) plus ~A$175 of one-off tools (debug probe, power analyser), no physical blockers.**

| Question | Answer | Source |
|---|---|---|
| Battery life (600 mAh) | **~152 h typical, ~57 h worst case** recording continuously; a 16 h day uses 11–28% of the battery. 400 and 1100 mAh cells stay as options | [`tools/feasibility.py`](tools/feasibility.py) |
| Charging | **USB-C only**: plug any USB charger or the PC into the capsule's side port. 0.8–2.2 h to refill a day at 100 mA, while still recording | same |
| Storage | 24 kbps Opus = ~260 MB/day; a 32 GB card is a ~80-day ring buffer (fixed 256 KiB slots, one per 60 s chunk, at any bitrate) | same |
| Sync | **USB CDC over the same cable** when it's plugged into the PC or home server: a day in **~15 min at 24 kbps** (~1 h worst case, 32 kbps at 100 KB/s). The USB rate is an **estimate** until measured. BLE is the wireless fallback (a plain charger, no PC) and the on-demand pull; at the 5 KB/s [Boswell](https://github.com/leakydata/boswell) measured on this board a full day takes ~14 h, so it isn't the nightly path | same + [SYNC-PROTOCOL](docs/SYNC-PROTOCOL.md) |
| Microphone | **Infineon IM73D122** on a small custom PCB (~70 dB(A) SNR at our 1.28 MHz clock vs ~64 for the stock XIAO mic, unverified); the stock mic is the fallback | [ALTERNATIVES §3](docs/ALTERNATIVES.md#3-microphone-choice) |
| Size / weight | Core **41.4 × 44.3 × 18.35 mm** (+6.7 mm bail); 19.65 mm over the relief eagle crest on the front (nothing overhangs), **~35 g**. Size pictures: [concepts/](concepts/README.md) From the CAD (600 mAh, IM73D122 mic board, USB-C slot) | [hardware/](hardware/README.md) |
| Better hardware? | The **Seeed reSpeaker Clip** (open firmware, nRF5340, Wi-Fi) is the best buy-and-customise option if you can get one; otherwise build this | [ALTERNATIVES](docs/ALTERNATIVES.md) |
| What could kill it | Measured current > 8 mA, or audio under a shirt too poor. Both are tested on the bench in the first two evenings, before printing anything. The exposed USB-C port (sweat, lint, wear) is the new mechanical risk | [BUILD-SIMULATION](docs/BUILD-SIMULATION.md) |

## Architecture

```
 ┌──────── capsule (worn / plugged in) ────────┐  USB-C cable: charge     ┌──────── your PC / home server ──────┐
 │ IM73D122 PDM mic → Opus 24 kbps → encrypt   │  + USB CDC sync          │ sync client → verify SHA-256 → ACK  │
 │ to host public key → 60 s chunks → microSD  │═════════════════════════▶│ → decrypt → VAD → faster-whisper    │
 │ ring buffer. Privacy: firmware cuts mic     │  BLE (fallback, pulls)   │ → SQLite FTS5 + daily Markdown      │
 │ power. XIAO nRF52840 Sense · 600 mAh LiPo   │─────────────────────────▶│                                     │
 └─────────────────────────────────────────────┘                          └─────────────────────────────────────┘
   optional printed stand (no electronics): holds it at ~30° facing the bed, cable plugged in, recording sleep audio
   on a plain USB charger (no PC): it charges and records; sync waits for the PC or falls back to BLE
```

## Repository map

| Path | What's there |
|---|---|
| [docs/BUILD-SIMULATION.md](docs/BUILD-SIMULATION.md) | **Start here.** The whole build, start to finish, on paper, with go/no-go gates and failure drills |
| [docs/ADVERSARIAL-REVIEW.md](docs/ADVERSARIAL-REVIEW.md) | Every claim in the original plan, checked: what held, what was wrong |
| [docs/ALTERNATIVES.md](docs/ALTERNATIVES.md) | Build vs buy; other boards; mic upgrades |
| [docs/WIRING.md](docs/WIRING.md) | Pin-by-pin wiring and diagrams: mic board, SD, switch, LED, USB-C |
| [docs/FIRMWARE.md](docs/FIRMWARE.md) | Zephyr/NCS firmware architecture, RAM/flash budget, test plan, milestones |
| [docs/SYNC-PROTOCOL.md](docs/SYNC-PROTOCOL.md) | Chunk format, list/fetch/ack sync over USB CDC or BLE, encryption at rest, time reconciliation |
| [docs/LEGAL.md](docs/LEGAL.md) | Australian recording law and the design rules that follow from it |
| [docs/MEMORY.md](docs/MEMORY.md) | The memory layer: every fact cites its audio, said / verified / committed / inferred, correction and deletion, false-memory guards |
| [tools/feasibility.py](tools/feasibility.py) | Power, charge, storage, sync, fit and weight model (`--worst` for the pessimistic case) |
| [host/](host/README.md) | Reference sync client (with a USB serial transport) plus a device simulator, with 45 passing tests (durability, filing, link security, bad-chunk, limit and serial cases) |
| [hardware/](hardware/README.md) | Parametric OpenSCAD capsule and bedside stand, self-checking fit asserts, print and assembly notes |
| [concepts/](concepts/README.md) | Blender concept renders (sized to the CAD) and the three eagle bezel directions |

## Quick start (no hardware needed)

```bash
python3 tools/feasibility.py            # typical case
python3 tools/feasibility.py --worst    # pessimistic case
cd host && python3 -m unittest -v       # sync pipeline against the simulated device
python3 hardware/check_cad.py           # every CAD variant: compiles, asserts hold, no interference (needs OpenSCAD)
```

## Credits

This project stands on **[BasedHardware/omi](https://github.com/BasedHardware/omi)**
(MIT), whose DevKits proved the XIAO nRF52840 Sense approach, plus hardware from
**Seeed Studio, Nordic, TI, Infineon, Adafruit and Pololu**, parts supplied by **Core
Electronics, Little Bird Electronics and DigiKey**, and software from **Zephyr, Xiph Opus,
Whisper/faster-whisper, Silero VAD, bleak, pyserial, OpenSCAD and Blender**. The initial plan came from a **Google
Gemini** conversation. It was independently checked and expanded by
**Anthropic's Claude** (Claude Code). Full list: **[CREDITS.md](CREDITS.md)**.

Not affiliated with or endorsed by any of the above. MIT licensed. See [LICENSE](LICENSE).
