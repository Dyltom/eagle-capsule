# Hardware: capsule and stand (OpenSCAD)

Two parametric files. Every size that matters is a named parameter at the top,
and every unverified one is marked `(?)`. The files check themselves:
`assert()`s stop the render if parts collide, and `interference` must render empty.

| File | What it makes |
|---|---|
| [`capsule.scad`](capsule.scad) | The wearable: body (skin side + walls + bail, with the USB-C slot in the side wall), lid (carries the mic port, the IM73D122 mic-board pocket and the recording-LED light pipe), the snap-on front: the **eagle plate** (default, with its 3 peg pins) or the original flush bezel, USB-C dust cap, mic gasket, optional TPU skin pad |
| [`dock.scad`](dock.scad) | Optional bedside **stand**, one printed part with no electronics: the capsule leans back 30° on its bottom edge, face toward the bed, and the USB-C cable can stay plugged into the side port (the stand keeps the plug and the cable's droop clear). Optional washer weight. It reads the capsule's sizes from `capsule.scad`, so the seat follows any capsule change, including every variant below. |
| [`variants.txt`](variants.txt) | Every variant combination that must render cleanly, one per line as `-D` assignments |

## Render

OpenSCAD 2021.01 or newer. STLs go in `hardware/build/`, which git ignores.

```bash
cd hardware && mkdir -p build
for p in body lid bezel pegs usb_plug gasket; do openscad -D "part=\"$p\"" -o build/$p.stl capsule.scad; done
openscad -D 'part="stand"' -o build/stand.stl dock.scad              # optional
openscad -D 'part="interference"' -o build/i.stl capsule.scad   # must say "top level object is empty"
openscad -D 'part="skin_pad"' -o build/skin_pad.stl capsule.scad     # optional, TPU (see below)
```

Pass the same variant settings to every part, and to the stand. `-D` reaches the
capsule sizes the stand reads, so the seat follows:

```bash
V=(-D 'battery="1100"' -D 'storage="sd_nand"' -D 'board="nrf54lm20a"' -D 'preset="slim"')
openscad "${V[@]}" -D 'part="body"' -o build/body.stl capsule.scad
openscad "${V[@]}" -D 'part="stand"' -o build/stand.stl dock.scad
```

**Quote string values.** `-D 'battery="1100"'` works. `-D battery=1100` passes a
number, and the file stops with an assert asking for a quoted string.

Other views: `assembly`, `fit_check` (electronics as coloured ghost blocks inside a
half-section of the shell), `print_plate`, and for the stand `assembly`, `section` (a cut down
the middle to check the seat) and `capsule` / `cable` (the posed capsule and the plugged-in cable).

## Variants

Set these at the top of `capsule.scad` or with `-D`. With no `-D` at all you get the
defaults: 600 mAh, microSD, XIAO nRF52840 Sense, the IM73D122 mic board and the eagle plate,
a core of **41.4 × 44.3 × 18.35 mm**.

| Parameter | Values | What changes |
|---|---|---|
| `battery` | `"600"` (default) | Little Bird Electronics LB-00237, 600 mAh, 29 × 36 × 5.5 mm (?), 10.5 g. Neither Core nor Adafruit sells a ~600 mAh protected 2-pin cell (checked Nov 2026). Adafruit #1578 (500 mAh, 29 × 36 × 4.75 mm, 10.5 g) has the same outline and fits too |
| | `"400"` | Core Electronics CE04375, 38 × 25 × 6 mm (?), 11 g |
| | `"1100"` | Core Electronics CE04377, 51 × 34 × 6 mm, 21 g |
| `storage` | `"pololu_sd"` (default) | Pololu #2597 microSD breakout, 20.3 × 17.8 mm; the card sticks out 3 mm (?) to the left |
| | `"sd_nand"` | Adafruit #4899 XTSD 512 MB SD NAND, 21.59 × 17.78 mm (Adafruit's EagleCAD file), 2.9 mm tall. Soldered chip, so nothing overhangs. Same SPI wiring (WIRING.md) |
| `board` | `"nrf52840"` (default) | XIAO nRF52840 Sense, chip antenna on the board. **Antenna rule:** the antenna end overhangs the battery by `ant_overhang` (6 mm) over the plastic-only left wall; assert `overhang >= ant_len` |
| | `"nrf54lm20a"` | XIAO nRF54LM20A Sense. No antenna on the board: an IPEX4 (MHF4) lead to the bundled FPC antenna A-04 (35.2 × 8.5 mm). **Antenna rule:** the FPC sticks into a 0.3 mm pocket on the plastic-only left wall, feed edge down. The battery, both boards and the microSD card start `fpc_keepout` (5.5 mm (?)) from its face. The XIAO no longer needs to overhang. The coax U-turns under the FPC (`coax_bend_r`), climbs the keepout gap, crosses the board end over the plug, and the spare length coils in a ring on top of the XIAO. Asserts check every step, the coax length and the coil. The mic sits 0.5 mm from the board edge next to the IPEX4 plug, so it is sealed with a foam pad on the mic's lid (`mic_seal = "pad"`) instead of the ring gasket (`mic="onboard"` only) |
| `mic` | `"im73d122"` (default) | Infineon IM73D122 on a custom ~8 × 6 mm board in a pocket under the lid. See [Mic board](#mic-board-im73d122-the-default) |
| | `"onboard"` | The XIAO's own PDM mic under the port (ring gasket on the nRF52840, foam pad on the nRF54LM20A), as before |
| `preset` | `"default"` | `bezel_t = 1.6`, `back_depth = 2.6` |
| | `"slim"` | `bezel_t = 1.0`, `back_depth = 1.6`: 1.6 mm thinner (16.75 mm). The USB-C port stays: it is the only charging and sync port in every variant |
| `bezel_style` | `"eagle"` (default) | The snap-on front is the eagle plate: spread wings and a head that overhang the core. See [Eagle plate](#eagle-plate-the-default-front) |
| | `"flush"` | The original bezel, flush with the core, with the engraved low-poly emblem. Same STL as before this option existed |
| `skin_pad` | `false` (default) / `true` | `true` cuts a 0.5 mm pocket in the domed back for the TPU skin pad (`part="skin_pad"`), and the stand seat makes room for it. `false` leaves the body exactly as before |

**How the preset and overrides combine.** The two preset parameters default to
`undef`. Leave one undef and the preset fills it in; give it a value (in the file or
with `-D`) and your value wins. So `-D 'preset="slim"' -D 'bezel_t=1.6'` is slim with
the thick bezel. Inside the file, use the resolved values `bezel_th` and `dome_d`, never
the raw parameters.

### USB-C port (every variant)

USB-C on the XIAO is the only charging and sync port: no dock connector, no pogo pins, nothing
on the 5V pin (WIRING.md section 3). The body has an open **12.8 × 6.9 mm slot** in the side wall
in front of the receptacle (right wall; left with `antenna_at = "usb_end"`), sized for a normal
cable's overmould (`usb_plug_w` × `usb_plug_h` = 12.4 × 6.5 mm (?), measure yours), so the plug
goes in about 4 mm. The slot floor clears the battery (0.15 mm at 600 mAh) and the plug top sits
1.6 mm under the lid rim; with the eagle plate it slides in behind the wing. `part="usb_plug"` is an
optional push-in dust cap (TPU or PETG) for when it is worn.

```
FIT USB-C port (right wall, 10.05 mm above the centre): slot 12.8 x 6.9, floor 0.15 mm above the battery, plug 1.6 mm under the lid rim (it slides in behind the wing)
```

### Mic board: IM73D122 (the default)

`mic = "im73d122"` (docs/WIRING.md section 1a, docs/ALTERNATIVES.md section 3): a custom ~8 × 6 mm
board carrying one Infineon IM73D122 (bottom port, 4 × 3 × 1.2 mm) and a 1 µF 0402 on its back,
a 0.8 mm sound hole through the board under the mic, and four edge pads (VDD, GND, CLK, DATA) on
one short end. It lies flat against the inside of the lid, mic facing into the case. Stack from
outside: lid (1 mm port) → gasket ring (0.5 mm closed-cell silicone sponge or PORON, squeezed
0.15) → board hole → mic. It slides into a pocket under the lid, wire end last: two rails hold its
long edges, a stop wall puts the hole on the port, and the gasket's compression holds it.

- **Where:** on the capsule's centreline (the eagle's breast), just below the XIAO, so the four
  30 AWG wires to D2, D4, D6 and GND are short.
- **Asserts:** the stack fits under the front of the lid (3.55 mm), the gasket squeeze stays
  0.3–0.5 mm, the lid is at most 1.5 mm thick at the port, and the pocket, parts and wires keep
  0.2 mm of air to everything else (tightest: 0.575 mm to the LED light-pipe sleeve).
- **`gasket` part:** a punch template for the ring (too thin to print well).
- **`mic = "onboard"`** keeps the old layout: the port over the XIAO's own mic with the foam
  chamber and ring gasket (or the foam pad on the nRF54LM20A). The outer size doesn't change.

```
FIT mic board IM73D122: port at x 0, y -2.35 (capsule frame); stack lid 1.2 + gasket 0.35 + board 0.8 + mic 1.2 = 3.55 mm under the front of the lid
FIT mic board clearance: tightest 0.575 mm (mic pocket to LED light-pipe sleeve)
```

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
  the lid's mic boss (or the mic-board pocket), the pipe clears the USB-C shell, and the pipe sits over the XIAO (so it
  can't reach the battery or the storage board). It also clears the bezel pegs and, on the
  nRF54LM20A, the coax coil.
- **Peg moves:** with `antenna_at = "usb_end"` the LED lands in the top-left corner, so that
  bezel peg moves inward to clear it. No other variant moves a peg.

```
FIT LED window: 4.40285 mm of plastic to the mic port, pipe to USB-C shell 0.575 mm
```

The holes don't change any outer size.

### Every combination in `variants.txt`

Rendered with OpenSCAD 2021.01 on 2026-11-15: all 45 lines rendered `interference` empty, and
`body`, `lid`, `bezel`, `pegs`, `usb_plug`, `gasket` and the stand with no assertion failure
(`python3 hardware/check_cad.py`). Every line without `bezel_style` gets the eagle plate (the
default). The core is the same with either front, and with either mic (`mic="onboard"` lines
come out the same size).

| battery | storage | board | preset | Core W × H × T (mm) | Eagle plate W × H × T (mm) | Stand, eagle (mm) | Stand, flush (mm) |
|---|---|---|---|---|---|---|---|
| 600 | pololu_sd | nrf52840 | default | **41.4 × 44.3 × 18.35** | **70 × 53.9 × 6.0** | **61.4 × 61.6** | 61.4 × 60.0 |
| 600 | sd_nand | nrf52840 | default | 41.4 × 44.3 × 18.35 | 70 × 53.9 × 6.0 | 61.4 × 61.6 |  |
| 600 | pololu_sd | nrf54lm20a | default | 40.1 × 47.8 × 18.98 | 70 × 57.4 × 6.0 | 60.1 × 63.9 |  |
| 600 | sd_nand | nrf54lm20a | default | 39.7 × 47.8 × 18.98 | 70 × 57.4 × 6.0 | 59.7 × 63.9 | 59.7 × 62.3 |
| 400 | pololu_sd | nrf52840 | default | 37.4 × 44.7 × 18.85 | 70 × 54.3 × 6.0 | 57.4 × 62.2 | 57.4 × 60.7 |
| 400 | sd_nand | nrf52840 | default | 37.69 × 44.7 × 18.85 | 70 × 54.3 × 6.0 | 57.7 × 62.2 |  |
| 400 | pololu_sd | nrf54lm20a | default | 40.1 × 47.8 × 19.48 | 70 × 57.4 × 6.0 | 60.1 × 64.3 |  |
| 400 | sd_nand | nrf54lm20a | default | 38.39 × 47.8 × 19.48 | 70 × 57.4 × 6.0 | 58.4 × 64.3 | 58.4 × 62.8 |
| 1100 | pololu_sd | nrf52840 | default | 46.4 × 57.7 × 18.85 | 70 × 67.3 × 6.0 | 66.4 × 68.7 | 66.4 × 67.2 |
| 1100 | sd_nand | nrf52840 | default | 46.4 × 57.7 × 18.85 | 70 × 67.3 × 6.0 | 66.4 × 68.7 |  |
| 1100 | pololu_sd | nrf54lm20a | default | 44.7 × 57.7 × 19.48 | 70 × 67.3 × 6.0 | 64.7 × 69.3 |  |
| 1100 | sd_nand | nrf54lm20a | default | 44.7 × 57.7 × 19.48 | 70 × 67.3 × 6.0 | 64.7 × 69.3 | 64.7 × 67.7 |
| 600 | pololu_sd | nrf52840 | slim | 41.4 × 44.3 × 16.75 | 70 × 53.9 × 6.0 | 61.4 × 60.7 | 61.4 × 58.7 |
| 600 | sd_nand | nrf52840 | slim | 41.4 × 44.3 × 16.75 | 70 × 53.9 × 6.0 | 61.4 × 60.7 |  |
| 600 | pololu_sd | nrf54lm20a | slim | 40.1 × 47.8 × 17.38 | 70 × 57.4 × 6.0 | 60.1 × 63.0 |  |
| 600 | sd_nand | nrf54lm20a | slim | 39.7 × 47.8 × 17.38 | 70 × 57.4 × 6.0 | 59.7 × 63.0 |  |
| 400 | pololu_sd | nrf52840 | slim | 37.4 × 44.7 × 17.25 | 70 × 54.3 × 6.0 | 57.4 × 61.4 |  |
| 400 | sd_nand | nrf54lm20a | slim | 38.39 × 47.8 × 17.88 | 70 × 57.4 × 6.0 | 58.4 × 63.5 |  |
| 1100 | pololu_sd | nrf52840 | slim | 46.4 × 57.7 × 17.25 | 70 × 67.3 × 6.0 | 66.4 × 67.9 |  |
| 1100 | sd_nand | nrf54lm20a | slim | 44.7 × 57.7 × 17.88 | 70 × 67.3 × 6.0 | 64.7 × 68.4 |  |

Also in the list: `wing_span=78` on the 1100 mAh core (plate 78 × 67.3 × 6.0), the skin pad
(capsule 18.85 mm thick with it, 17.25 in slim), `antenna_at="usb_end"` (port on the left wall)
and `lid_fastening="snap"`; none of them changes the core size.

Every core adds the 6.7 mm bail on top; with the eagle plate the head covers it, and the plate's H
includes the head (9.6 mm above the core). What the table shows:

- **600 mAh is the smallest core that is not short of battery.** It is 4 mm wider and 0.4 mm
  shorter than 400 mAh (its cell is 29 mm across, not 25) and 0.5 mm thinner, for 50% more charge.
- **SD NAND hardly changes the size.** With the nRF52840 the battery sets the width (SD NAND
  adds 0.3 mm at 400 mAh, where the narrow cell lets the board's width count). With the
  nRF54LM20A it saves 0.4–1.7 mm of width, because there is no card to keep out of the
  antenna keepout.
- **The nRF54LM20A is 0.6 mm thicker and 3.1–3.5 mm taller.** Its PCB is 1.6 mm (the nRF52840's is
  taken as 1.0 (?)), its USB-C is taller, and the FPC antenna needs the length of the wall.
  With 600 and 1100 mAh it is narrower, because its keepout (5.5 mm) is smaller than the
  nRF52840's overhang strip.
- **No dock connector, so every core is 5 mm shorter** than before (the 400 mAh core went from
  49.7 to 44.7 mm), and the USB-C slot adds 0.25 mm of thickness over the old service tunnel.

## Eagle plate (the default front)

The capsule's core is a rounded box on purpose: it is the smallest shell around a rectangular
battery and two rectangular boards, and the asserts above set every millimetre of it. The front
is the part that is free to change, so the swappable snap-on front is a full eagle silhouette
that overhangs the core: spread wings, a head on top, a waist and a fanned tail. It reads as a bird
at a glance; the core stays exactly the size it would be with the flush bezel (41.4 × 44.3 ×
18.35 mm by default). `bezel_style = "flush"` brings back the original flush bezel, and nothing else changes:
the body and lid come out identical with either front.

**The design.** Original, low-poly (faceted) to match the engraved emblem: a front-facing head with
a hooked beak and a V brow, wings spread almost level with four fingered primaries and three
scalloped secondaries, coverts and a leading-edge band on each wing, a few rows of breast facets
and a five-feather tail. There is no shield, crown, sceptre, arrows, legs or talons, lettering or
profile head, so it doesn't read as a coat of arms (the US Great Seal, the German, Mexican or
Polish eagles), a military badge or a brand mark. Keep it that way if you edit it.

| Default (600 mAh) | mm | Parameter |
|---|---|---|
| Plate overall W × H × T | **70 × 53.9 × 6.0** | `wing_span`; H includes the head, `head_top` = 9.6 above the core |
| Wing overhang past the core | 14.3 a side (asserted 10–20) | `wing_span` |
| Plate | 2.2 flat (asserted 2.0–2.5), relief 0.4–1.2 on top, head 6.0 | `wing_t`, `relief_min`, `relief_max` |
| Capsule thickness with the plate | 20.15 at the body and wings, 22.75 at the head (slim: 19.15 / 21.75) | |
| Wing root trailing edge | 20.5 below the core's top edge | `wing_drop` (and `wing_lift` for dihedral) |
| Waist / tail | 22 wide at 42% of the core's height; the tail fans out to the full width | `waist_w`, `waist_frac`, `tail_flare` |
| Weight | eagle plate 5.72 cm³ ≈ **7.3 g PETG** (+ 3 pins, 0.05 g) | |

With the 1100 mAh cell the core is 5 mm wider, so the default 70 mm span overhangs only 11.8 mm a
side; `wing_span=78` (in `variants.txt`) keeps the 600 mAh proportions.

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
- **Switch.** The wings stay at least 5 mm above the privacy switch (`sw_access`; 6.6 mm by default),
  and the waist leaves the side wall around it uncovered.
- **USB-C.** The wing passes over the side-wall slot; the plug slides in under it (the plug's top is
  1.6 mm under the lid rim).

**Snagging and comfort.** Every outer tip and corner is rounded to at least 2 mm (`tip_r`, asserted).
The wing and head edges have a 1.0 mm 45° chamfer on the back, toward the chest (`wing_back_ch`), and
0.6 mm in front. The wings sit at the front face, a core's thickness off the chest, so they never
press on it; they are flat and 70 mm across, about a large brooch. They can still catch a seatbelt or
a jacket zip, which is when the flush bezel is the better front. Where the waist uncovers the core,
the rim's edge is square (the flush bezel's chamfer used to cover it): break it with fine sandpaper.

**Plastic only.** Print the plate (and the pins) in plain plastic: PETG, PLA or ASA. No metal inserts,
metallic paint, metal-filled ("bronze", "copper", "steel") or conductive filament: the plate lies right
over the antenna (the chip antenna on the nRF52840, the FPC on the nRF54LM20A) and the mic port.

## Stand (optional)

`dock.scad` makes one printed part, `part="stand"`, with no electronics. The capsule drops in on its
bottom edge, face toward the bed, leaning back 30° (`tilt`), so the mic faces the room at night.
Charging and sync use a normal USB-C cable in the capsule's side port, and the cable can stay
plugged in while the capsule sits in the stand:

- **Seat.** A backrest behind the skin side and low cheeks either side; the bottom edge sits 5 mm
  (`seat_depth`) into an 18 mm base. With the eagle plate the seat cut adds each convex piece of
  the plate (the core area, the head, every wing piece), grown by the clearance and swept along the
  slide-in path, so it follows the bird's outline. The wings ride 22.3 mm above the base top.
- **Cable.** The plug's overmould (`usb_om_len` = 22 mm (?)) sticks out sideways from the port,
  then the cable droops through `usb_bend_r` to the table. The stand keeps that whole path clear,
  also while the capsule is lowered in; the overmould rides 20.4 mm above the base top and the
  cable drops 20 mm beside the base. If it would land on the base, a notch is cut for it.
- **Weight.** Optional pocket in the underside for ~3 steel washers (M12–M16, ~30 mm), glued in,
  and recesses for four 10 mm rubber feet.
- **Asserts:** the mic port and the privacy switch stay above the base and the cheeks, the plug and
  the cable clear the base and the cheeks, the weight pocket doesn't reach the seat, and the eagle's
  wings clear the base, the cheeks and the table by at least 1 mm.

```
STAND footprint = 61.4 x 61.6 mm, height 18 mm (70.1 with the capsule)
STAND mic port is 20.3 mm above the base top, aimed 30 deg above horizontal
STAND privacy switch is 9.7 mm above the base top, 1.8 mm above the cheeks
STAND USB-C plug (right side): overmould 20.4 mm above the base top, 19.7 mm above the cheeks; the cable drops 20 mm beside the base
STAND eagle wings: lowest point 40.3 mm above the table, 22.3 mm above the base top, 17.0 mm past the cheeks; wing tips 4.3 mm past the base sides
```

You don't need the stand: the capsule charges and syncs on any USB-C cable, lying on a table.

## Current numbers (default parameters: 600 mAh, IM73D122 mic board, eagle plate)

Rendered with OpenSCAD 2021.01 on 2026-11-15.

| | Size (mm) | Notes |
|---|---|---|
| Capsule outer | **41.4 W × 44.3 H × 18.35 T** | + 6.7 mm bail on top |
| Capsule cavity | 37.4 × 40.3 × 12.95 | |
| Eagle plate | 70 × 53.9 × 6.0 (wings 2.2 + relief) | Capsule with it: 20.15 mm thick at the body, 22.75 at the head |
| Shell plastic | body 8.17 + lid 1.88 + eagle plate 5.72 cm³ | **≈ 20.0 g in PETG** printed near-solid |
| Parts | | ≈ 17.4 g ([`tools/feasibility.py`](../tools/feasibility.py)) + mic board ≈ 0.3 g |
| **Capsule total** | | **≈ 38 g** before the cord |
| Stand | 61.4 × 61.6 × 18 (70.1 with the capsule in it) | 69 cm³ ≈ 88 g PETG at 100% (print at 15–20% infill, ~35 g) + optional 40–60 g steel weight |
| 1100 mAh variant | 46.4 × 57.7 × 18.85 | `battery = "1100"`; the stand grows to 66.4 × 68.7 |

Fit checks the files print on every render:

```
FIT antenna overhang past battery = 6 mm (antenna zone 5)
FIT USB-C port (right wall, 10.05 mm above the centre): slot 12.8 x 6.9, floor 0.15 mm above the battery, plug 1.6 mm under the lid rim (it slides in behind the wing)
FIT mic board IM73D122: port at x 0, y -2.35 (capsule frame); stack lid 1.2 + gasket 0.35 + board 0.8 + mic 1.2 = 3.55 mm under the front of the lid
FIT mic board clearance: tightest 0.575 mm (mic pocket to LED light-pipe sleeve)
FIT switch leg tips to SD board = 5.5 mm
FIT LED window: 4.40285 mm of plastic to the mic port, pipe to USB-C shell 0.575 mm
FIT lid screw bosses: 6.95 mm long, 0.5 mm above the battery
```

With the eagle plate (the default) the capsule adds:

```
EAGLE plate W x H x T = 70 x 53.9 x 6 mm  (wings 2.2 + 0.4..1.2 relief; capsule with the plate 22.75 mm thick at the head, 20.15 at the wings)
FIT eagle: wings overhang 14.3 mm a side, 6.6 mm above the switch; cord tunnel 9.4 x 3.5 under a 1.5 mm roof; relief to mic port 1.5 mm, port / LED / pegs inside the plate edge by 10 / 9.325 / 5.4 mm, head to mic port 16 mm, head to LED 9.49205 mm
```

With `mic = "onboard"` the mic lines become:

```
FIT mic chamber above mic = 4.85 mm (foam 2 mm, seal: ring)
FIT gasket ring to USB-C shell = 0.1 mm
```

With `board = "nrf54lm20a"` (600 mAh, SD NAND) the antenna lines replace the overhang line:

```
FIT FPC antenna to battery / boards = 5.5 mm (keepout 5.5)
FIT FPC on the wall: y 4.3..39.5 of the straight 4..39.8, top 11.205 under the lid at 13.58
FIT coax: 30.3459 mm routed, 19.6541 mm spare = 0.69512 turns in the coil (2 fit)
```

With `skin_pad = true`:

```
FIT skin pad: 1 mm TPU, 0.5 mm proud (capsule 18.85 mm thick with it), shell under the pocket 1.75167 mm, pad bends 0.348334 mm
```

In `slim` the shell under the pocket is thinner. The assert stops below `pad_floor` (0.8 mm).

### This is bigger than the paper estimate

`feasibility.py` estimated ~54 × 29 × 15 mm from a box model. The CAD comes out
shorter but wider and thicker. The reasons, and what each costs:

| Cause | Thickness | Option |
|---|---|---|
| USB-C slot sized for a 12.4 × 6.5 mm cable overmould | sets the cavity height over the battery | None: it is the only charging and sync port. A cable with a slimmer overmould (`usb_plug_h`) lowers it |
| Curved skin-side back | +2.6 mm | `back_depth = 1.6` → −1.0 mm, flatter on the chest |
| Separate bezel over the lid | +1.6 mm | `bezel_t = 1.0` → −0.6 mm, shallower emblem |
| Both | | **16.75 mm**: `preset = "slim"` |

The width comes from the 600 mAh cell (29 mm across) plus the antenna rule: the XIAO's
antenna end hangs 6 mm past the battery, next to a plastic-only wall, and the slide switch
sits inside the opposite wall. Measure the real parts before trading any of this away.

## Measure these when the parts arrive

Calipers, then change the parameter and re-render. The `(?)` ones matter most:

| Parameter | Why it matters |
|---|---|
| `batt_dims` for `"600"` (LB-00237) | Drives the whole layout. The listing's 29 × 36 × 5.5 mm; check whether the PCM and wires are inside it |
| `mpcb_*`, `mgk_t` (IM73D122 board) | Your board's real size, thickness, hole offset (from Infineon's footprint) and the gasket's free thickness. Sets the lid pocket and the squeeze |
| `mic_from_usb`, `mic_from_edge`, `mic_pkg` (`mic="onboard"`) | Where the PDM mic really is on the XIAO Sense. Sets the acoustic port and gasket. **At 9 mm the gasket sat on the USB-C shell**; 10.5 mm clears it by 0.1 mm. Re-measure, and the `assert` re-checks it |
| `xiao_h`, `usb_w`, `usb_h`, `usb_overhang` | The USB-C receptacle sets the side-wall slot and the cavity height |
| `antenna_at` | Which end the chip antenna is at. It must sit over the plastic-only wall |
| `usb_plug_w`, `usb_plug_h` | Your actual USB-C cable's overmould. Sets the side-wall slot |
| `usb_om_len`, `usb_cable_d`, `usb_bend_r` (stand) | Your cable's overmould length, diameter and how tightly it droops. Sets the stand's cable clearance |
| `sd_card_overhang` | How far the card sticks out of the Pololu board |
| `nand_pcb_t`, `nand_wire_h` (Adafruit #4899) | Board thickness isn't published (1.6 assumed). Height of the wire joints on the header holes. The outline is from Adafruit's own board file |
| `batt_dims` for `"400"` (CE04375) | Core Electronics doesn't publish a footprint |
| `lm_usb_overhang`, `lm_usb_h` (nRF54LM20A) | The STEP shows the USB-C 2.44 mm past the board, but the KiCad layer says 1.6. The shell may also sit partly below the board's top face. This sets the slot position |
| `ipex_plug` | Mated MHF4 plug size and height (1.2 mm max per I-PEX). The lid's mic pad holder clears it by 0.06 mm vertically |
| `fpc_t`, `coax_bend_r`, `coax_len` | FPC thickness with its adhesive isn't published. Bend the coax to the U-turn radius and check that it doesn't kink. Check the lead length (50 ± 2 mm) |
| `fpc_keepout` | A rule of thumb, not a Seeed figure. If BLE range is poor in the case, more keepout is the first fix (it adds width) |
| `lm_mic_*`, `mpad_t` | From Seeed's KiCad file (a top-port MSM261DGT006, 4 × 2 mm, 0.5 mm from the board edge). Check that the sound hole is on the top, and punch the foam pad to fit |
| `pad_t`, `pad_recess` (skin pad) | Your TPU's printed thickness. The pad should stand about 0.5 mm proud |
| `led_from_usb`, `led_from_edge`, `led_pkg` (nRF52840) | Where the onboard RGB LED is. The nRF52840 position is assumed to match the nRF54LM20A's (from Seeed's KiCad file, 2.9 mm from the USB-C end, 2.95 mm from the edge). The light pipe must sit right over it |
| `led_pipe_d` | Your light-pipe stock: clear 1.75 mm filament or 2 mm acrylic rod |
| `sw_*` (Adafruit #805) | Actuator size and travel for the flush window |
| `weight_d` (stand) | Your washers |

Also needed, and not printed: **Adafruit #3164 / #3169 30 AWG silicone wire** for the
signal wiring, and a **Nordic Power Profiler Kit II (PPK2)**. The PPK2 is required for Gate 2:
the current measurement in BUILD-SIMULATION.

Then print one `body` in draft quality (0.28 mm, 2 walls) as a fit test before the
real print. That is BUILD-SIMULATION gate 4.

## Printing (Bambu A1 mini / P1S, or any 0.4 mm nozzle)

**PETG**, not PLA: PLA softens in a hot Australian car (above ~55 °C). PETG at
0.16–0.2 mm layers, 4 walls, 40% gyroid infill for the capsule (it's mostly walls anyway).

| Part | Orientation | Supports |
|---|---|---|
| Body | Rim down, curved back up (`print_plate` does this) | Tree supports only under the bail slot; the switch window and the USB-C slot bridge |
| Lid | Outer face down | None. If the light pipe is tight in the LED sleeve, open the hole with a 2 mm drill |
| Eagle plate (`bezel`, default) | **Back down, relief up** (`print_plate` does this). The back is flat everywhere except the cord tunnel and the three peg sockets | None. The cord tunnel is a 9.4 mm bridge; the back chamfers are 45°. 0.12–0.16 mm layers for crisp facets, 100% infill (it is 2.2 mm thick). Add a brim if the wing tips lift. Plain plastic only (see [Eagle plate](#eagle-plate-the-default-front)) |
| Peg pins (`pegs`, eagle only) | Standing, shank down | None. 2.2 mm × 3.5 mm: print slowly (or with something taller beside them for cooling) and make a few spares |
| Flush bezel (`bezel_style="flush"`) | Face down. The emblem prints on the bed side, so it comes out crisp | None. Silk PLA or PETG, plain plastic only (no metal-filled "bronze" filament: it sits over the antenna and the mic) |
| USB-C dust cap (`usb_plug`) | Flange down | None. TPU grips best |
| Gasket | Flat | None. With the IM73D122 board (default) it is a punch template: cut the ring from 0.5 mm closed-cell silicone sponge or PORON. With `mic="onboard"`: print in TPU 95A, or punch it from 1.5 mm closed-cell foam. With the nRF54LM20A, `gasket` is a 2 × 4 mm pad template: punch it from 1 mm closed-cell foam with a 1 mm hole, since it is too small to print well |
| Skin pad (optional) | Flat, skin side up (the chamfer prints on top) | None. **TPU 95A**, 0.2 mm layers, 100% infill, slow (20–25 mm/s), on its own plate. It prints flat and bends 0.35 mm (0.21 in slim) into the domed pocket. Stick it in with thin double-sided tape (e.g. 3M 9474 transfer tape) so it can come out for washing |
| Stand | Base down, seat up | None (the seat opens upward). 15–20% infill |

## Assembly order

1. **Bench-test the electronics first** (BUILD-SIMULATION stages 1–3). Nothing
   goes in a shell until it records, syncs and passes the current measurement.
2. Battery into the body on foam tape, protection-PCB end toward the bottom wall.
3. Mic board (default): solder the four 30 AWG wires to its pads, lay the gasket ring over the
   lid's port, and slide the board into the lid pocket, wire end last, until it stops against the
   end wall (the hole is then on the port). The wires go to D2, D4, D6 and GND (WIRING.md
   section 1a).
4. Slide switch between its ribs, actuator through the window.
5. SD breakout (bottom end) and XIAO (bail end) on foam tape above the battery. The XIAO's antenna end goes
   over the left (plastic-only) wall, and the USB-C lines up with the side-wall slot: check that a
   cable plugs in fully before the lid goes on.
   **nRF54LM20A:** the XIAO sits fully over the battery instead. Peel the FPC antenna and stick it into the
   pocket on the left wall, feed edge down, then clip the IPEX4 plug on (press straight down; MHF4
   doesn't take sideways force). Run the coax in a U-turn under the FPC, up the gap, over the plug,
   and coil the spare length flat in the marked ring on top of the XIAO. A dab of Kapton tape holds the coil.
   Put nothing metal (screws, foil tape, the battery leads) between the FPC and the battery.
6. `mic="onboard"` only: gasket on the XIAO around the mic (nRF54LM20A: the foam pad into the lid's
   holder, hole over the mic), foam disc into the lid's recess. Push the light pipe into the lid's LED sleeve, lid on,
   and check the pipe lines up with the RGB LED. Cut it flush after the bezel goes on (step 7).
   Two M1.6 × 8 self-tappers (or the `snap` variant).
7. Front: **eagle plate:** push a peg pin into each of the three sockets in the plate's back,
   shank first, with a drop of CA or epoxy, and let it cure. Push the flat cord through the bail
   slot from the back and lay it up over the bail, then press the plate's pegs through the lid
   until they click: the cord now runs up the tunnel behind the head and out over the crown.
   **Flush bezel:** its pegs are built in; press them through the lid. Either way, prise it off at
   the notch in the bottom seam to swap.
8. Optional skin pad: wipe the pocket with isopropyl alcohol, tape the pad in, chamfered side out.
9. Stand (optional): washers glued into the weight pocket, rubber feet in the recesses. Plug the
   cable into the capsule, then lower the capsule into the seat with the cable hanging off the side.

## Fit check (what `part="fit_check"` shows)

A half-section of the body and lid, cut down the long axis, with the electronics
as coloured blocks: the battery (blue) on the skin side, with the XIAO (green, gold antenna
zone at the left end) and the SD board (purple) above it, the XIAO toward the bail end
and the SD board toward the bottom wall. The switch (orange) is in the right wall,
the USB-C (silver) faces its slot, and the mic board (red, under the lid's port) sits in its
pocket below the XIAO (`mic="onboard"`: the XIAO's mic under the port and foam chamber). The light pipe (pale cyan) rises from the RGB LED (white) through the lid and bezel. The bezel is a translucent blue overlay. Nothing should poke through a wall.
`interference` renders the overlap of the electronics and the shell, and must be empty.

With `board = "nrf54lm20a"` the gold zone is the FPC antenna in its wall pocket instead. The IPEX4
plug is goldenrod and the coax (black) runs from the plug to its coil ring and down the
keepout gap to the FPC. All of these count in `interference`.

## Credits

Part dimensions come from the makers' published data: **Seeed Studio** (XIAO
nRF52840 Sense; XIAO nRF54LM20A Sense KiCad and STEP files; 2.4 GHz FPC Antenna A-04 datasheet),
**Pololu** (#2597 microSD breakout), **Adafruit** (#4899 XTSD SD NAND board file, #805 slide
switch), **Infineon** (IM73D122 datasheet), **Core Electronics**
(CE04375 400 mAh and CE04377 1100 mAh LiPo) and **Little Bird Electronics** (LB-00237 600 mAh LiPo). Modelled in **OpenSCAD** (GPL-2.0; the models are MIT, see
[LICENSE](../LICENSE)). The low-poly eagle emblem and the eagle plate are original designs.
