# Hardware: capsule and dock (OpenSCAD)

Two parametric files. Every size that matters is a named parameter at the top,
and every unverified one is marked `(?)`. The files check themselves:
`assert()`s stop the render if parts collide, and `interference` must render empty.

| File | What it makes |
|---|---|
| [`capsule.scad`](capsule.scad) | The wearable: body (skin side + walls + bail), lid (carries the mic port and the recording-LED light pipe), snap-on eagle bezel, USB-C plug cap, mic gasket, optional TPU skin pad |
| [`dock.scad`](dock.scad) | Nightstand dock: weighted base, 30° keyed cradle, dock half of the magnetic connector, bay for the USB-C breakout and Schottky diode, bottom plate. It reads the capsule's sizes from `capsule.scad`, so the cradle follows any capsule change, including every variant below. |
| [`variants.txt`](variants.txt) | Every variant combination that must render cleanly, one per line as `-D` assignments |

## Render

OpenSCAD 2021.01 or newer. STLs go in `hardware/build/`, which git ignores.

```bash
cd hardware && mkdir -p build
for p in body lid bezel usb_plug gasket; do openscad -D "part=\"$p\"" -o build/$p.stl capsule.scad; done
for p in dock bottom_plate;              do openscad -D "part=\"$p\"" -o build/$p.stl dock.scad; done
openscad -D 'part="interference"' -o build/i.stl capsule.scad   # must say "top level object is empty"
openscad -D 'part="skin_pad"' -o build/skin_pad.stl capsule.scad     # optional, TPU (see below)
```

Pass the same variant settings to every part, and to the dock. `-D` reaches the
capsule sizes the dock reads, so the cradle follows:

```bash
V=(-D 'battery="1100"' -D 'storage="sd_nand"' -D 'board="nrf54lm20a"' -D 'preset="slim"')
openscad "${V[@]}" -D 'part="body"' -o build/body.stl capsule.scad
openscad "${V[@]}" -D 'part="dock"' -o build/dock.stl dock.scad
```

**Quote string values.** `-D 'battery="1100"'` works. `-D battery=1100` passes a
number, and the file stops with "battery must be "400", "600" or "1100" (a quoted string)".

Other views: `assembly`, `fit_check` (electronics as coloured ghost blocks inside a
half-section of the shell), `print_plate`, and for the dock `assembly` and `section`
(a cut through the connector to check the seat and the wire path).

## Variants

Set these at the top of `capsule.scad` or with `-D`. With no `-D` at all you get the
first value of each, which is the original design (37.4 × 49.7 × 18.6 mm).

| Parameter | Values | What changes |
|---|---|---|
| `battery` | `"400"` (default) | Core Electronics CE04375, 38 × 25 × 6 mm (?), 11 g |
| | `"600"` | Little Bird Electronics LB-00237, 600 mAh, 29 × 36 × 5.5 mm (?), 10.5 g. Neither Core nor Adafruit sells a ~600 mAh protected 2-pin cell (checked Nov 2026). Adafruit #1578 (500 mAh, 29 × 36 × 4.75 mm, 10.5 g) has the same outline and fits too |
| | `"1100"` | Core Electronics CE04377, 51 × 34 × 6 mm, 21 g |
| `storage` | `"pololu_sd"` (default) | Pololu #2597 microSD breakout, 20.3 × 17.8 mm; the card sticks out 3 mm (?) to the left |
| | `"sd_nand"` | Adafruit #4899 XTSD 512 MB SD NAND, 21.59 × 17.78 mm (Adafruit's EagleCAD file), 2.9 mm tall. Soldered chip, so nothing overhangs. Same SPI wiring (WIRING.md) |
| `board` | `"nrf52840"` (default) | XIAO nRF52840 Sense, chip antenna on the board. **Antenna rule:** the antenna end overhangs the battery by `ant_overhang` (6 mm) over the plastic-only left wall; assert `overhang >= ant_len` |
| | `"nrf54lm20a"` | XIAO nRF54LM20A Sense. No antenna on the board: an IPEX4 (MHF4) lead to the bundled FPC antenna A-04 (35.2 × 8.5 mm). **Antenna rule:** the FPC sticks into a 0.3 mm pocket on the plastic-only left wall, feed edge down. The battery, both boards and the microSD card start `fpc_keepout` (5.5 mm (?)) from its face, and the magnets are at least that far away. The XIAO no longer needs to overhang. The coax U-turns under the FPC (`coax_bend_r`), climbs the keepout gap, crosses the board end over the plug, and the spare length coils in a ring on top of the XIAO. Asserts check every step, the coax length and the coil. The mic sits 0.5 mm from the board edge next to the IPEX4 plug, so it is sealed with a foam pad on the mic's lid (`mic_seal = "pad"`) instead of the ring gasket |
| `preset` | `"default"` | `usb_service_port = true`, `bezel_t = 1.6`, `back_depth = 2.6` |
| | `"slim"` | `usb_service_port = false`, `bezel_t = 1.0`, `back_depth = 1.6`: 3.2 mm thinner. Recovery then needs the dock UART (MCUboot serial recovery, FIRMWARE.md M17) |
| `skin_pad` | `false` (default) / `true` | `true` cuts a 0.5 mm pocket in the domed back for the TPU skin pad (`part="skin_pad"`), and the dock seat makes room for it. `false` leaves the body exactly as before |

**How the preset and overrides combine.** The three preset parameters default to
`undef`. Leave one undef and the preset fills it in; give it a value (in the file or
with `-D`) and your value wins. So `-D 'preset="slim"' -D 'bezel_t=1.6'` is slim with
the thick bezel (16.0 mm). Inside the file, use the resolved values `usb_port`,
`bezel_th` and `dome_d`, never the raw parameters.

### Recording LED window (every variant)

The recording indicator is required (docs/LEGAL.md, WIRING.md section 5). Every variant has
a light-pipe window on the front face, right above the XIAO's onboard RGB LED, beside the USB-C:

- **Light pipe:** a 1.75 mm offcut of clear PETG or PC filament (`led_pipe_d`), or 2 mm acrylic rod
  with `led_pipe_d = 2`. It runs from 0.3 mm above the LED to 0.1 mm below the front face.
- **Lid:** a guide sleeve hangs under the lid, starting above the USB-C shell so it clears it.
- **Bezel:** a matching hole cut straight through, whatever the emblem (custom 2D emblems
  passed to `bezel()` get it too). With the default eagle it sits just right of the head.
- **External LED instead:** an LED on D3 can be glued under the pipe in place of the onboard one.
- **Asserts:** the window keeps `led_web` (2 mm) of plastic to the mic port. The sleeve clears
  the lid's mic boss, the pipe clears the USB-C shell, and the pipe sits over the XIAO (so it
  can't reach the battery or the storage board). It also clears the bezel pegs and, on the
  nRF54LM20A, the coax coil.
- **Peg moves:** with `antenna_at = "usb_end"` the LED lands in the top-left corner, so that
  bezel peg moves inward to clear it. No other variant moves a peg.

```
FIT LED window: 5.8 mm of plastic to the mic port, sleeve to mic boss 1.9 mm, pipe to USB-C shell 0.58 mm
```

The holes don't change any outer size.

### Every combination in `variants.txt`

Rendered with OpenSCAD 2021.01 on 2026-11-15. Every line rendered `interference`
empty, and `body`, `lid`, `bezel` and the dock with no assertion failure.

| battery | storage | board | preset | Capsule W × H × T (mm) | Dock footprint (mm) |
|---|---|---|---|---|---|
| 400 | pololu_sd | nrf52840 | default | **37.4 × 49.7 × 18.6** | 57.4 × 63.0 |
| 400 | sd_nand | nrf52840 | default | 37.4 × 49.7 × 18.6 | 57.4 × 63.0 |
| 400 | pololu_sd | nrf54lm20a | default | 40.1 × 49.7 × 19.2 | 60.1 × 63.5 |
| 400 | sd_nand | nrf54lm20a | default | 38.4 × 49.7 × 19.2 | 58.4 × 63.5 |
| 600 | pololu_sd | nrf52840 | default | 41.4 × 49.3 × 18.1 | 61.4 × 62.3 |
| 600 | sd_nand | nrf52840 | default | 41.4 × 49.3 × 18.1 | 61.4 × 62.3 |
| 600 | pololu_sd | nrf54lm20a | default | 40.1 × 49.3 × 18.7 | 60.1 × 62.9 |
| 600 | sd_nand | nrf54lm20a | default | 39.7 × 49.3 × 18.7 | 59.7 × 62.9 |
| 1100 | pololu_sd | nrf52840 | default | 46.4 × 62.7 × 18.6 | 66.4 × 69.5 |
| 1100 | sd_nand | nrf52840 | default | 46.4 × 62.7 × 18.6 | 66.4 × 69.5 |
| 1100 | pololu_sd | nrf54lm20a | default | 44.7 × 62.7 × 19.2 | 64.7 × 70.0 |
| 1100 | sd_nand | nrf54lm20a | default | 44.7 × 62.7 × 19.2 | 64.7 × 70.0 |
| 400 | pololu_sd | nrf52840 | slim | 37.4 × 49.7 × 15.4 | 57.4 × 60.2 |
| 400 | sd_nand | nrf52840 | slim | 37.4 × 49.7 × 15.4 | 57.4 × 60.2 |
| 1100 | pololu_sd | nrf52840 | slim | 46.4 × 62.7 × 15.4 | 66.4 × 66.7 |
| 1100 | sd_nand | nrf52840 | slim | 46.4 × 62.7 × 15.4 | 66.4 × 66.7 |
| 400 | sd_nand | nrf54lm20a | slim | 38.4 × 49.7 × 16.1 | 58.4 × 60.8 |
| 600 | sd_nand | nrf54lm20a | slim | 39.7 × 49.3 × 15.6 | 59.7 × 60.1 |
| 400 | pololu_sd | nrf52840 | default + skin pad | 37.4 × 49.7 × 18.6 (19.1 with the pad) | 57.4 × 63.4 |
| 400 | pololu_sd | nrf52840 | slim + skin pad | 37.4 × 49.7 × 15.4 (15.9 with the pad) | 57.4 × 60.6 |

All of them add the 6.7 mm bail on top. What the table shows:

- **SD NAND never makes the capsule bigger.** With the nRF52840 the battery sets the width
  either way. With the nRF54LM20A it saves 1.7 mm of width at 400 mAh, because there is no card
  to keep out of the antenna keepout.
- **The nRF54LM20A is 0.6 mm thicker.** Its PCB is 1.6 mm (the nRF52840's is taken as 1.0 (?))
  and its USB-C is taller. With 400 mAh it is wider, because the switch legs beside the storage board set
  the width (`FIT switch leg tips` = 0.5 mm). With 1100 mAh it is 1.7 mm narrower, because its
  keepout (5.5 mm) is smaller than the nRF52840's overhang strip (7.2 mm).
- **600 mAh is wider and shorter than 400** (its cell is 29 mm across, not 25) and 0.5 mm
  thinner. It holds 50% more charge for 4 mm of width.

## Current numbers (default parameters, 400 mAh cell)

Rendered with OpenSCAD 2021.01 on 2026-11-15.

| | Size (mm) | Notes |
|---|---|---|
| Capsule outer | **37.4 W × 49.7 H × 18.6 T** | + 6.7 mm bail on top |
| Capsule cavity | 33.4 × 45.7 × 13.2 | |
| Shell plastic | body 8.1 + lid 2.0 + bezel 2.8 cm³ | **≈ 16.6 g in PETG** printed near-solid |
| Parts | | ≈ 19.6 g ([`tools/feasibility.py`](../tools/feasibility.py)) |
| **Capsule total** | | **≈ 36 g** before the cord |
| Dock | 57.4 × 63.0 × 40.3 (65.8 with the capsule in it) | ≈ 84 g PETG at 100% (print at 15–20% infill, ~35 g) + 40–60 g steel weight |
| 1100 mAh variant | 46.4 × 62.7 × 18.6 | `battery = "1100"`; the dock grows to 66.4 × 69.5 |

Fit checks the files print on every render:

```
FIT antenna overhang past battery = 6 mm (antenna zone 5)
FIT usb tunnel floor above battery = 0.4 mm
FIT mic chamber above mic = 4.6 mm (foam 2 mm)
FIT gasket ring to USB-C shell = 0.1 mm
FIT switch leg tips to SD board = 2.1 mm
DOCK mic port is 25.9 mm above the base top, aimed 30 deg above horizontal
DOCK connector bottom is 8.2 mm above the bottom plate
```

With `board = "nrf54lm20a"` (400 mAh, SD NAND) the antenna lines replace the overhang line:

```
FIT FPC antenna to battery / boards = 5.5 mm, to the magnets = 6.7 mm (keepout 5.5)
FIT FPC on the wall: y 5.25..40.45 of the straight 4..41.7, top 11.205 under the lid at 13.83
FIT coax: 34.6 mm routed, 15.4 mm spare = 0.55 turns in the coil (2 fit)
FIT mic chamber above mic = 3.77 mm (foam 2 mm, seal: pad)
```

With `skin_pad = true`:

```
FIT skin pad: 1 mm TPU, 0.5 mm proud (capsule 19.1 mm thick with it), shell under the pocket 1.75 mm, pad bends 0.35 mm
```

In `slim` the shell under the pocket is 0.89 mm. The assert stops below `pad_floor` (0.8 mm).

### This is bigger than the paper estimate

`feasibility.py` estimated ~54 × 29 × 15 mm from a box model. The CAD comes out
shorter but wider and thicker. The reasons, and what each costs:

| Cause | Thickness | Option |
|---|---|---|
| USB-C service tunnel sized for a 12 × 6 mm cable overmould | +1.6 mm | `usb_service_port = false` → 17.0 mm. Recovery then needs the dock UART (MCUboot serial recovery, FIRMWARE.md M17) |
| Curved skin-side back | +2.6 mm | `back_depth = 1.6` → −1.0 mm, flatter on the chest |
| Separate bezel over the lid | +1.6 mm | `bezel_t = 1.0` → −0.6 mm, shallower emblem |
| All three | | **15.4 mm**: `preset = "slim"` |

The width comes from the antenna rule: the XIAO's antenna end hangs 6 mm past
the battery, next to a plastic-only wall, and the slide switch sits inside the
opposite wall. Measure the real parts before trading any of this away.

## Measure these when the parts arrive

Calipers, then change the parameter and re-render. The `(?)` ones matter most:

| Parameter | Why it matters |
|---|---|
| `batt_dims` (400 mAh pouch incl. the protection PCB and wires) | Drives the whole layout. Core Electronics doesn't publish a footprint |
| `conn_l`, `conn_d`, `conn_h`, `dconn_*` (Adafruit #5358) | No dimensions are published. Sets the connector window and the dock pocket |
| `mic_from_usb`, `mic_from_edge`, `mic_pkg` | Where the PDM mic really is on the XIAO Sense. Sets the acoustic port and gasket. **At 9 mm the gasket sat on the USB-C shell**; 10.5 mm clears it by 0.1 mm. Re-measure, and the `assert` re-checks it |
| `xiao_h`, `usb_w`, `usb_h`, `usb_overhang` | The USB-C receptacle sets the tunnel and the cavity height |
| `antenna_at` | Which end the chip antenna is at. It must sit over the plastic-only wall |
| `usb_plug_w`, `usb_plug_h` | Your actual USB-C cable's overmould, if you keep the service port |
| `sd_card_overhang` | How far the card sticks out of the Pololu board |
| `nand_pcb_t`, `nand_wire_h` (Adafruit #4899) | Board thickness isn't published (1.6 assumed). Height of the wire joints on the header holes. The outline is from Adafruit's own board file |
| `batt_dims` for `"600"` (LB-00237) | The listing's 29 × 36 × 5.5 mm; check whether the PCM and wires are inside it |
| `lm_usb_overhang`, `lm_usb_h` (nRF54LM20A) | The STEP shows the USB-C 2.44 mm past the board, but the KiCad layer says 1.6. The shell may also sit partly below the board's top face. This sets the tunnel position |
| `ipex_plug` | Mated MHF4 plug size and height (1.2 mm max per I-PEX). The lid's mic pad holder clears it by 0.06 mm vertically |
| `fpc_t`, `coax_bend_r`, `coax_len` | FPC thickness with its adhesive isn't published. Bend the coax to the U-turn radius and check that it doesn't kink. Check the lead length (50 ± 2 mm) |
| `fpc_keepout` | A rule of thumb, not a Seeed figure. If BLE range is poor in the case, more keepout is the first fix (it adds width) |
| `lm_mic_*`, `mpad_t` | From Seeed's KiCad file (a top-port MSM261DGT006, 4 × 2 mm, 0.5 mm from the board edge). Check that the sound hole is on the top, and punch the foam pad to fit |
| `pad_t`, `pad_recess` (skin pad) | Your TPU's printed thickness. The pad should stand about 0.5 mm proud |
| `led_from_usb`, `led_from_edge`, `led_pkg` (nRF52840) | Where the onboard RGB LED is. The nRF52840 position is assumed to match the nRF54LM20A's (from Seeed's KiCad file, 2.9 mm from the USB-C end, 2.95 mm from the edge). The light pipe must sit right over it |
| `led_pipe_d` | Your light-pipe stock: clear 1.75 mm filament or 2 mm acrylic rod |

Also needed, and not printed: **Adafruit #3164 / #3169 30 AWG silicone wire** for the
signal wiring, and a **Nordic Power Profiler Kit II (PPK2)**. The PPK2 is required for Gate 2:
the current measurement in BUILD-SIMULATION.
| `sw_*` (Adafruit #805) | Actuator size and travel for the flush window |
| `weight_d`, `usb_bo` (dock) | Your washers and your USB-C breakout board |

Then print one `body` in draft quality (0.28 mm, 2 walls) as a fit test before the
real print. That is BUILD-SIMULATION gate 4.

## Printing (Bambu A1 mini / P1S, or any 0.4 mm nozzle)

**PETG**, not PLA: PLA softens in a hot Australian car (above ~55 °C). PETG at
0.16–0.2 mm layers, 4 walls, 40% gyroid infill for the capsule (it's mostly walls anyway).

| Part | Orientation | Supports |
|---|---|---|
| Body | Rim down, curved back up (`print_plate` does this) | Tree supports only under the bail slot; the switch window and tunnel bridge |
| Lid | Outer face down | None. If the light pipe is tight in the LED sleeve, open the hole with a 2 mm drill |
| Bezel | Face down. The emblem prints on the bed side, so it comes out crisp | None. Silk/bronze PLA or PETG; this is the swappable cosmetic part |
| USB plug cap | Flange down | None |
| Gasket | Flat | None. Print in TPU 95A, or punch it from 1.5 mm closed-cell foam. With the nRF54LM20A, `gasket` is a 2 × 4 mm pad template: punch it from 1 mm closed-cell foam with a 1 mm hole, since it is too small to print well |
| Skin pad (optional) | Flat, skin side up (the chamfer prints on top) | None. **TPU 95A**, 0.2 mm layers, 100% infill, slow (20–25 mm/s), on its own plate. It prints flat and bends 0.35 mm (0.21 in slim) into the domed pocket. Stick it in with thin double-sided tape (e.g. 3M 9474 transfer tape) so it can come out for washing |
| Dock | Base down, cradle up | None (the seat opens upward) |
| Dock bottom plate | Flat | None. 15–20% infill is enough for the dock |

## Assembly order

1. **Bench-test the electronics first** (BUILD-SIMULATION stages 1–3). Nothing
   goes in a shell until it records, syncs and passes the current measurement.
2. Battery into the body on foam tape, protection-PCB end toward the connector.
3. Magnetic connector into its window, flush with the outside, on its pedestal.
   **Check magnet polarity against the dock half first** (WIRING.md section 3).
   Glue it with a little epoxy.
4. Slide switch between its ribs, actuator through the window.
5. SD breakout (connector end) and XIAO (bail end) on foam tape above the battery. The XIAO's antenna end goes
   over the left (plastic-only) wall, and the USB-C lines up with the tunnel.
   **nRF54LM20A:** the XIAO sits fully over the battery instead. Peel the FPC antenna and stick it into the
   pocket on the left wall, feed edge down, then clip the IPEX4 plug on (press straight down; MHF4
   doesn't take sideways force). Run the coax in a U-turn under the FPC, up the gap, over the plug,
   and coil the spare length flat in the marked ring on top of the XIAO. A dab of Kapton tape holds the coil.
   Put nothing metal (screws, foil tape, the battery leads) between the FPC and the battery.
6. Gasket on the XIAO around the mic (nRF54LM20A: the foam pad into the lid's holder, hole over the
   mic), foam disc into the lid's recess. Push the light pipe into the lid's LED sleeve, lid on,
   and check the pipe lines up with the RGB LED. Cut it flush after the bezel goes on (step 7).
   Two M1.6 × 8 self-tappers (or the `snap` variant).
7. Bezel: press the three split pegs through the lid until they click. Prise it off
   at the notch in the bottom seam to swap emblems.
8. Optional skin pad: wipe the pocket with isopropyl alcohol, tape the pad in, chamfered side out.
9. Dock: USB-C breakout against the back wall, Schottky in the 5 V line
   (anode at the supply), dock connector half into its pocket (pins up, polarity
   checked), wires down the channel. Washers in the weight pocket, bottom plate on
   with four M2 self-tappers, rubber feet in the recesses.

## Fit check (what `part="fit_check"` shows)

A half-section of the body and lid, cut down the long axis, with the electronics
as coloured blocks: the battery (blue) on the skin side, with the XIAO (green, gold antenna
zone at the left end) and the SD board (purple) above it, the XIAO toward the bail end
and the SD board toward the connector. The
connector (goldenrod) sits flush in the bottom edge, the switch (orange) is in the right wall,
the USB-C (silver) faces the tunnel, and the mic (red) is under the lid's port and
foam chamber. The light pipe (pale cyan) rises from the RGB LED (white) through the lid and bezel. The bezel is a translucent blue overlay. Nothing should poke through a wall.
`interference` renders the overlap of the electronics and the shell, and must be empty.

With `board = "nrf54lm20a"` the gold zone is the FPC antenna in its wall pocket instead. The IPEX4
plug is goldenrod and the coax (black) runs from the plug to its coil ring and down the
keepout gap to the FPC. All of these count in `interference`.

## Credits

Part dimensions come from the makers' published data: **Seeed Studio** (XIAO
nRF52840 Sense; XIAO nRF54LM20A Sense KiCad and STEP files; 2.4 GHz FPC Antenna A-04 datasheet),
**Pololu** (#2597 microSD breakout), **Adafruit** (#4899 XTSD SD NAND board file, #5358 magnetic
connector, #805 slide switch, #4090 USB-C breakout), **Core Electronics**
(CE04375 400 mAh and CE04377 1100 mAh LiPo) and **Little Bird Electronics** (LB-00237 600 mAh LiPo). Modelled in **OpenSCAD** (GPL-2.0; the models are MIT, see
[LICENSE](../LICENSE)). The low-poly eagle is an original design.
