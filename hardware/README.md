# Hardware: capsule and dock (OpenSCAD)

Two parametric files. Every size that matters is a named parameter at the top,
and every unverified one is marked `(?)`. The files check themselves:
`assert()`s stop the render if parts collide, and `interference` must render empty.

| File | What it makes |
|---|---|
| [`capsule.scad`](capsule.scad) | The wearable: body (skin side + walls + bail), lid (carries the mic port), snap-on eagle bezel, USB-C plug cap, mic gasket |
| [`dock.scad`](dock.scad) | Nightstand dock: weighted base, 30° keyed cradle, dock half of the magnetic connector, bay for the USB-C breakout and Schottky diode, bottom plate. It reads the capsule's sizes from `capsule.scad`, so the cradle follows any capsule change. |

## Render

OpenSCAD 2021.01 or newer. STLs go in `hardware/build/`, which git ignores.

```bash
cd hardware && mkdir -p build
for p in body lid bezel usb_plug gasket; do openscad -D "part=\"$p\"" -o build/$p.stl capsule.scad; done
for p in dock bottom_plate;              do openscad -D "part=\"$p\"" -o build/$p.stl dock.scad; done
openscad -D 'part="interference"' -o build/i.stl capsule.scad   # must say "top level object is empty"
```

Other views: `assembly`, `fit_check` (electronics as coloured ghost blocks inside a
half-section of the shell), `print_plate`, and for the dock `assembly` and `section`
(a cut through the connector to check the seat and the wire path).

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

### This is bigger than the paper estimate

`feasibility.py` estimated ~54 × 29 × 15 mm from a box model. The CAD comes out
shorter but wider and thicker. The reasons, and what each costs:

| Cause | Thickness | Option |
|---|---|---|
| USB-C service tunnel sized for a 12 × 6 mm cable overmould | +1.6 mm | `usb_service_port = false` → 17.0 mm. Recovery then needs the dock UART (MCUboot serial recovery, FIRMWARE.md M17) |
| Curved skin-side back | +2.6 mm | `back_depth = 1.6` → −1.0 mm, flatter on the chest |
| Separate bezel over the lid | +1.6 mm | `bezel_t = 1.0` → −0.6 mm, shallower emblem |
| All three | | **15.4 mm** |

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
| Lid | Outer face down | None |
| Bezel | Face down. The emblem prints on the bed side, so it comes out crisp | None. Silk/bronze PLA or PETG; this is the swappable cosmetic part |
| USB plug cap | Flange down | None |
| Gasket | Flat | None. Print in TPU 95A, or punch it from 1.5 mm closed-cell foam |
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
6. Gasket on the XIAO around the mic, foam disc into the lid's recess, lid on.
   Two M1.6 × 8 self-tappers (or the `snap` variant).
7. Bezel: press the three split pegs through the lid until they click. Prise it off
   at the notch in the bottom seam to swap emblems.
8. Dock: USB-C breakout against the back wall, Schottky in the 5 V line
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
foam chamber. The bezel is a translucent blue overlay. Nothing should poke through a wall.
`interference` renders the overlap of the electronics and the shell, and must be empty.

## Credits

Part dimensions come from the makers' published data: **Seeed Studio** (XIAO
nRF52840 Sense), **Pololu** (#2597 microSD breakout), **Adafruit** (#5358 magnetic
connector, #805 slide switch, #4090 USB-C breakout) and **Core Electronics**
(CE04375 400 mAh LiPo). Modelled in **OpenSCAD** (GPL-2.0; the models are MIT, see
[LICENSE](../LICENSE)). The low-poly eagle is an original design.
