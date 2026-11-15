# Hardware: capsule and dock (OpenSCAD)

Two parametric files. Every size that matters is a named parameter at the top,
and every unverified one is marked `(?)`. The files check themselves:
`assert()`s stop the render if parts collide, and `interference` must render empty.

| File | What it makes |
|---|---|
| [`capsule.scad`](capsule.scad) | The wearable: body (skin side + walls + bail), lid (carries the mic port and the recording-LED light pipe), the snap-on front: the **eagle plate** (default, with its 3 peg pins) or the original flush bezel, USB-C plug cap, mic gasket, optional TPU skin pad |
| [`dock.scad`](dock.scad) | Nightstand dock: weighted base, 30° keyed cradle (clears the eagle's wings and head), dock half of the magnetic connector, bay for the USB-C breakout and Schottky diode, bottom plate. It reads the capsule's sizes from `capsule.scad`, so the cradle follows any capsule change, including every variant below. |
| [`variants.txt`](variants.txt) | Every variant combination that must render cleanly, one per line as `-D` assignments |

## Render

OpenSCAD 2021.01 or newer. STLs go in `hardware/build/`, which git ignores.

```bash
cd hardware && mkdir -p build
for p in body lid bezel pegs usb_plug gasket; do openscad -D "part=\"$p\"" -o build/$p.stl capsule.scad; done
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
first value of each: the original core (37.4 × 49.7 × 18.6 mm) wearing the eagle plate.

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
| `bezel_style` | `"eagle"` (default) | The snap-on front is the eagle plate: spread wings and a head that overhang the core. See [Eagle plate](#eagle-plate-the-default-front) |
| | `"flush"` | The original bezel, flush with the core, with the engraved low-poly emblem. Same STL as before this option existed |
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
- **Bezel / eagle plate:** a matching hole cut straight through, whatever the emblem (custom 2D
  emblems passed to the flush `bezel()` get it too). On the eagle plate it sits on the chest, with
  no relief within 0.8 mm of it, and the pipe is cut flush with the plate face.
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
empty, and `body`, `lid`, `bezel`, `pegs` and the dock with no assertion failure. Every line
without `bezel_style` gets the eagle plate (the default). The core is the same with either front.

| battery | storage | board | preset | Core W × H × T (mm) | Eagle plate W × H × T (mm) | Dock, eagle (mm) | Dock, flush (mm) |
|---|---|---|---|---|---|---|---|
| 400 | pololu_sd | nrf52840 | default | **37.4 × 49.7 × 18.6** | **70 × 59.3 × 6.0** | **57.4 × 64.5** | 57.4 × 63.0 |
| 400 | sd_nand | nrf52840 | default | 37.4 × 49.7 × 18.6 | 70 × 59.3 × 6.0 | 57.4 × 64.5 | 57.4 × 63.0 |
| 400 | pololu_sd | nrf54lm20a | default | 40.1 × 49.7 × 19.2 | 70 × 59.3 × 6.0 | 60.1 × 65.1 | 60.1 × 63.5 |
| 400 | sd_nand | nrf54lm20a | default | 38.4 × 49.7 × 19.2 | 70 × 59.3 × 6.0 | 58.4 × 65.1 | 58.4 × 63.5 |
| 600 | pololu_sd | nrf52840 | default | 41.4 × 49.3 × 18.1 | 70 × 58.9 × 6.0 | 61.4 × 63.9 | 61.4 × 62.3 |
| 600 | sd_nand | nrf52840 | default | 41.4 × 49.3 × 18.1 | 70 × 58.9 × 6.0 | 61.4 × 63.9 | 61.4 × 62.3 |
| 600 | pololu_sd | nrf54lm20a | default | 40.1 × 49.3 × 18.7 | 70 × 58.9 × 6.0 | 60.1 × 64.4 | 60.1 × 62.9 |
| 600 | sd_nand | nrf54lm20a | default | 39.7 × 49.3 × 18.7 | 70 × 58.9 × 6.0 | 59.7 × 64.4 | 59.7 × 62.9 |
| 1100 | pololu_sd | nrf52840 | default | 46.4 × 62.7 × 18.6 | 70 × 72.3 × 6.0 | 66.4 × 71.0 | 66.4 × 69.5 |
| 1100 | sd_nand | nrf52840 | default | 46.4 × 62.7 × 18.6 | 70 × 72.3 × 6.0 | 66.4 × 71.0 | 66.4 × 69.5 |
| 1100 | pololu_sd | nrf54lm20a | default | 44.7 × 62.7 × 19.2 | 70 × 72.3 × 6.0 | 64.7 × 71.6 | 64.7 × 70.0 |
| 1100 | sd_nand | nrf54lm20a | default | 44.7 × 62.7 × 19.2 | 70 × 72.3 × 6.0 | 64.7 × 71.6 | 64.7 × 70.0 |
| 400 | pololu_sd | nrf52840 | slim | 37.4 × 49.7 × 15.4 | 70 × 59.3 × 6.0 | 57.4 × 62.3 | 57.4 × 60.2 |
| 400 | sd_nand | nrf52840 | slim | 37.4 × 49.7 × 15.4 | 70 × 59.3 × 6.0 | 57.4 × 62.3 | 57.4 × 60.2 |
| 1100 | pololu_sd | nrf52840 | slim | 46.4 × 62.7 × 15.4 | 70 × 72.3 × 6.0 | 66.4 × 68.8 | 66.4 × 66.7 |
| 1100 | sd_nand | nrf52840 | slim | 46.4 × 62.7 × 15.4 | 70 × 72.3 × 6.0 | 66.4 × 68.8 | 66.4 × 66.7 |
| 400 | sd_nand | nrf54lm20a | slim | 38.4 × 49.7 × 16.1 | 70 × 59.3 × 6.0 | 58.4 × 62.8 | 58.4 × 60.8 |
| 600 | sd_nand | nrf54lm20a | slim | 39.7 × 49.3 × 15.6 | 70 × 58.9 × 6.0 | 59.7 × 62.2 | 59.7 × 60.1 |
| 1100 | sd_nand | nrf54lm20a | slim | 44.7 × 62.7 × 16.1 | 70 × 72.3 × 6.0 | 64.7 × 69.3 | not in the list |
| 1100 | pololu_sd | nrf52840 | default, `wing_span=78` | 46.4 × 62.7 × 18.6 | 78 × 72.3 × 6.0 | 66.4 × 71.0 | |
| 400 | pololu_sd | nrf52840 | default + skin pad | 37.4 × 49.7 × 18.6 (19.1 with the pad) | 70 × 59.3 × 6.0 | 57.4 × 64.9 | 57.4 × 63.4 |
| 400 | pololu_sd | nrf52840 | slim + skin pad | 37.4 × 49.7 × 15.4 (15.9 with the pad) | 70 × 59.3 × 6.0 | 57.4 × 62.7 | 57.4 × 60.6 |

The flush column is the dock with `bezel_style="flush"`; `variants.txt` renders it for the default,
slim, 1100 mAh and 600 mAh/nRF54LM20A lines, and it is the same STL as before the eagle plate existed.

Every core adds the 6.7 mm bail on top; with the eagle plate the head covers it, and the plate's H
includes the head (9.6 mm above the core). What the table shows:

- **SD NAND never makes the capsule bigger.** With the nRF52840 the battery sets the width
  either way. With the nRF54LM20A it saves 1.7 mm of width at 400 mAh, because there is no card
  to keep out of the antenna keepout.
- **The nRF54LM20A is 0.6 mm thicker.** Its PCB is 1.6 mm (the nRF52840's is taken as 1.0 (?))
  and its USB-C is taller. With 400 mAh it is wider, because the switch legs beside the storage board set
  the width (`FIT switch leg tips` = 0.5 mm). With 1100 mAh it is 1.7 mm narrower, because its
  keepout (5.5 mm) is smaller than the nRF52840's overhang strip (7.2 mm).
- **600 mAh is wider and shorter than 400** (its cell is 29 mm across, not 25) and 0.5 mm
  thinner. It holds 50% more charge for 4 mm of width.

## Eagle plate (the default front)

The capsule's core is a rounded box on purpose: it is the smallest shell around a rectangular
battery and two rectangular boards, and the asserts above set every millimetre of it. The front
is the part that is free to change, so the swappable snap-on front is a full eagle silhouette
that overhangs the core: spread wings, a head on top, a waist and a fanned tail. It reads as a bird
at a glance; the core stays exactly the size it was (37.4 × 49.7 × 18.6 mm by default, every
variant). `bezel_style = "flush"` brings back the original flush bezel, and nothing else changes:
the body and lid come out identical with either front.

**The design.** Original, low-poly (faceted) to match the engraved emblem: a front-facing head with
a hooked beak and a V brow, wings spread almost level with four fingered primaries and three
scalloped secondaries, coverts and a leading-edge band on each wing, a few rows of breast facets
and a five-feather tail. There is no shield, crown, sceptre, arrows, legs or talons, lettering or
profile head, so it doesn't read as a coat of arms (the US Great Seal, the German, Mexican or
Polish eagles), a military badge or a brand mark. Keep it that way if you edit it.

| Default (400 mAh) | mm | Parameter |
|---|---|---|
| Plate overall W × H × T | **70 × 59.3 × 6.0** | `wing_span`; H includes the head, `head_top` = 9.6 above the core |
| Wing overhang past the core | 16.3 a side (asserted 10–20) | `wing_span` |
| Plate | 2.2 flat (asserted 2.0–2.5), relief 0.4–1.2 on top, head 6.0 | `wing_t`, `relief_min`, `relief_max` |
| Capsule thickness with the plate | 20.4 at the body and wings, 23.0 at the head (slim: 17.8 / 20.4) | |
| Wing root trailing edge | 20.5 below the core's top edge | `wing_drop` (and `wing_lift` for dihedral) |
| Waist / tail | 22 wide at 42% of the core's height; the tail fans out to the full width | `waist_w`, `waist_frac`, `tail_flare` |
| Weight | eagle plate 5.95 cm³ ≈ **7.6 g PETG** (+ 3 pins, 0.05 g); flush bezel 3.6 g | |

With the 1100 mAh cell the core is 9 mm wider, so the default 70 mm span overhangs only 11.8 mm a
side; `wing_span=78` (in `variants.txt`) keeps the 400 mAh proportions.

**How it goes together.**

- **Flat back.** The plate sits on the lid and the body rim (z = top of the rim) where it overlaps
  the core: the shoulders and the head over the top of the core and the bail, the tail over the
  bottom (it covers the two lid screws and keeps the pry notch). The waist leaves the core's sides
  bare around the privacy switch.
- **Pegs.** The same three split pegs in the same lid holes. The plate prints back-down, so the pegs
  are separate pins (`part="pegs"`): each has a 1.5 mm shank that goes into a 1.6 mm socket in the
  plate's back (`pin_sock`), glued with CA or epoxy. The flush bezel keeps its built-in pegs.
- **Overhang.** The wings are 2.2 mm of plate with no support behind them. A raised band along each
  leading edge (1.2 mm, `rib_h`) from the shoulder to the wrist and a long scapular feather down the
  wing root (0.9 mm) stiffen the root; every feather adds a 0.4–1.0 mm ridge.
- **Cord.** The head hides the bail. A 9.4 × 3.5 mm tunnel in its back starts below the bail slot and
  leaves through the crown, under a 1.5 mm roof (1.0 under the engraved eyes). A flat 8 × 2.5 mm cord
  goes through the slot from the back, up the tunnel and out over the crown, as it did over the
  bail before. Asserts: the tunnel reaches below the slot, is at least 0.6 mm wider and 0.3 mm taller
  than the cord, the head reaches past the slot, and the walls and roof keep their plastic.
- **Mic port and LED window.** The same holes, wherever they land on the bird (the chest by default,
  the left shoulder on the nRF54LM20A). No relief within 1.5 mm of the mic port's edge (asserted
  >= 1.5, `relief_port_clr`) or 0.8 mm of the LED window; the head must stay 1.5 mm from the port;
  both holes must be at least 1 mm inside the plate's edge. The light pipe is cut flush with the
  plate face, 2.2 mm above the lid.
- **Switch.** The wings stay at least 5 mm above the privacy switch (`sw_access`; 7.0 mm by default,
  20 mm on the 1100 mAh core), and the waist leaves the side wall around it uncovered.

**Snagging and comfort.** Every outer tip and corner is rounded to at least 2 mm (`tip_r`, asserted).
The wing and head edges have a 1.0 mm 45° chamfer on the back, toward the chest (`wing_back_ch`), and
0.6 mm in front. The wings sit at the front face, a core's thickness off the chest, so they never
press on it; they are flat and 70 mm across, about a large brooch. They can still catch a seatbelt or
a jacket zip, which is when the flush bezel is the better front. Where the waist uncovers the core,
the rim's edge is square (the flush bezel's chamfer used to cover it): break it with fine sandpaper.

**Plastic only.** Print the plate (and the pins) in plain plastic: PETG, PLA or ASA. No metal inserts,
metallic paint, metal-filled ("bronze", "copper", "steel") or conductive filament: the plate lies right
over the antenna (the chip antenna on the nRF52840, the FPC on the nRF54LM20A) and the mic port.

**Dock.** The cradle clears the plate: its seat cut adds each convex piece of the plate (the core
area, the head, every wing piece), grown by the seat clearance and swept along the slide-in path, so
the cut follows the bird's outline instead of filling the space between the wings. The front lip
moves out by the plate's thickness. The footprint grows from 57.4 × 63.0 to **57.4 × 64.5 mm** (same
width; the wings are light, so the base doesn't need to widen). The wings ride 20.8 mm above the
base top and 46.8 mm above the table, and their tips overhang the base sides by 6.3 mm. New
asserts: the wings clear the base by >= 1 mm, clear the cheeks by >= 1 mm, and don't reach the
table. The existing ones (mic above the base, switch uncovered, connector pocket vs bay, weight
pocket vs seat) all still hold.

## Current numbers (default parameters, 400 mAh cell)

Rendered with OpenSCAD 2021.01 on 2026-11-15.

| | Size (mm) | Notes |
|---|---|---|
| Capsule outer | **37.4 W × 49.7 H × 18.6 T** | + 6.7 mm bail on top |
| Capsule cavity | 33.4 × 45.7 × 13.2 | |
| Eagle plate | 70 × 59.3 × 6.0 (wings 2.2 + relief) | Capsule with it: 20.4 mm thick at the body, 23.0 at the head |
| Shell plastic | body 8.1 + lid 2.0 + eagle plate 5.95 cm³ (flush bezel 2.8) | **≈ 20.6 g in PETG** printed near-solid (16.6 with the flush bezel) |
| Parts | | ≈ 19.6 g ([`tools/feasibility.py`](../tools/feasibility.py)) |
| **Capsule total** | | **≈ 40 g** before the cord (≈ 36 g with the flush bezel) |
| Dock | 57.4 × 64.5 × 40.3 (76.7 with the eagle capsule in it, to the head) | ≈ 86 g PETG at 100% (print at 15–20% infill, ~35 g) + 40–60 g steel weight. Flush: 57.4 × 63.0 |
| 1100 mAh variant | 46.4 × 62.7 × 18.6 | `battery = "1100"`; the dock grows to 66.4 × 71.0 (69.5 flush) |

Fit checks the files print on every render:

```
FIT antenna overhang past battery = 6 mm (antenna zone 5)
FIT usb tunnel floor above battery = 0.4 mm
FIT mic chamber above mic = 4.6 mm (foam 2 mm)
FIT gasket ring to USB-C shell = 0.1 mm
FIT switch leg tips to SD board = 2.1 mm
DOCK mic port is 26.2 mm above the base top, aimed 30 deg above horizontal
DOCK connector bottom is 8.2 mm above the bottom plate
```

With the eagle plate (the default) the capsule and the dock add:

```
EAGLE plate W x H x T = 70 x 59.3 x 6 mm  (wings 2.2 + 0.4..1.2 relief; capsule with the plate 23 mm thick at the head, 20.4 at the wings)
FIT eagle: wings overhang 16.3 mm a side, 7 mm above the switch; cord tunnel 9.4 x 3.5 under a 1.5 mm roof; relief to mic port 1.5 mm, port / LED / pegs inside the plate edge by 11.8 / 9.7 / 5.4 mm, head to mic port 8.9 mm, head to LED 9.8 mm
DOCK eagle wings: lowest point 46.8 mm above the table, 20.8 mm above the base top, 18.5 mm past the cheeks; wing tips 6.3 mm past the base sides
```

(The mic port sits 26.2 mm above the base with the eagle and 25.9 mm with the flush bezel: the
port opens on the plate face, 0.6 mm further out.)

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
| Eagle plate (`bezel`, default) | **Back down, relief up** (`print_plate` does this). The back is flat everywhere except the cord tunnel and the three peg sockets | None. The cord tunnel is a 9.4 mm bridge; the back chamfers are 45°. 0.12–0.16 mm layers for crisp facets, 100% infill (it is 2.2 mm thick). Add a brim if the wing tips lift. Plain plastic only (see [Eagle plate](#eagle-plate-the-default-front)) |
| Peg pins (`pegs`, eagle only) | Standing, shank down | None. 2.2 mm × 3.5 mm: print slowly (or with something taller beside them for cooling) and make a few spares |
| Flush bezel (`bezel_style="flush"`) | Face down. The emblem prints on the bed side, so it comes out crisp | None. Silk PLA or PETG, plain plastic only (no metal-filled "bronze" filament: it sits over the antenna and the mic) |
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
7. Front: **eagle plate:** push a peg pin into each of the three sockets in the plate's back,
   shank first, with a drop of CA or epoxy, and let it cure. Push the flat cord through the bail
   slot from the back and lay it up over the bail, then press the plate's pegs through the lid
   until they click: the cord now runs up the tunnel behind the head and out over the crown.
   **Flush bezel:** its pegs are built in; press them through the lid. Either way, prise it off at
   the notch in the bottom seam to swap.
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
[LICENSE](../LICENSE)). The low-poly eagle emblem and the eagle plate are original designs.
