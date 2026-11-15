// =====================================================================
//  Eagle Capsule - wearable enclosure (OpenSCAD, fully parametric)
//  License: MIT (see repository LICENSE)
//
//  Part dimensions come from the makers' published data:
//    Seeed Studio      - XIAO nRF52840 Sense (21 x 17.8 mm); XIAO nRF54LM20A Sense
//                        (KiCad + STEP files) and its 2.4 GHz FPC antenna A-04
//    Pololu            - #2597 microSD breakout (20.3 x 17.8 mm)
//    Adafruit          - #4899 XTSD 512 MB SD NAND (EagleCAD file), #805 SPDT slide switch
//    Infineon          - IM73D122 PDM microphone (4 x 3 x 1.2 mm LLGA, bottom port)
//    Core Electronics  - CE04375 400 mAh and CE04377 1100 mAh LiPo
//    Little Bird       - LB-00237 600 mAh LiPo
//  Anything marked (?) below is NOT verified. Measure it with calipers
//  when the parts arrive and change the parameter (see hardware/README.md).
//
//  Variants: battery, storage, board, mic, preset, skin_pad (see [Variants]).
//  USB-C on the side wall is the only charging and sync port, in every variant.
//  hardware/variants.txt lists every combination that must render cleanly.
//
//  Coordinate system (capsule frame):
//    X = across the front face (left/right as you look at the bezel)
//    Y = up the front face (+Y = lanyard end, -Y = bottom edge)
//    Z = thickness, out of the front face (z = 0 is the inner floor,
//        the skin-side dome is below z = 0, the bezel is on top)
//
//  Render one part:   openscad -D 'part="body"' -o body.stl capsule.scad
//  Parts: assembly | fit_check | body | lid | bezel | pegs | usb_plug | gasket |
//         skin_pad | print_plate | interference | none
//  bezel    = the eagle plate (bezel_style = "eagle", default) or the flush bezel ("flush");
//  pegs     = the eagle plate's three separate peg pins (the flush bezel has them built in);
//  usb_plug = the optional dust cap for the USB-C port;
//  gasket   = the mic seal: a punch template for the IM73D122 board's ring (mic = "im73d122"),
//             or the ring / foam pad on the XIAO's own mic (mic = "onboard")
// =====================================================================

/* [What to render] */
part = "assembly";

/* [Global] */
tol      = 0.2;    // printer clearance, per side, for parts that fit together
clr      = 1.2;    // air gap between electronics and the inner wall
$fn      = 40;

/* [Variants] */
// Every combination listed in hardware/variants.txt renders and passes the asserts.
// "600" = LB-00237 600 mAh (default, see [Battery]) | "400" = CE04375 400 mAh (~38 x 25 x 6 ?)
// "1100" = CE04377 1100 mAh, 51 x 34 x 6, 21 g
battery  = "600";
// "pololu_sd" = Pololu #2597 microSD breakout | "sd_nand" = Adafruit #4899 XTSD 512 MB
storage  = "pololu_sd";
// "nrf52840" = XIAO nRF52840 Sense (chip antenna on the board)
// "nrf54lm20a" = XIAO nRF54LM20A Sense (external FPC antenna on an IPEX4 lead)
board    = "nrf52840";
// "im73d122" = Infineon IM73D122 on a small custom board flat inside the lid (default)
// "onboard"  = the XIAO's own PDM mic under the port (ring gasket, or foam pad on the nRF54LM20A)
mic      = "im73d122";
// "default" | "slim" (thin bezel, flatter back: 1.6 mm thinner; the USB-C port stays).
// The preset only fills in the two parameters marked PRESET below.
preset   = "default";
// Optional TPU skin pad on the domed back (part="skin_pad"). false = body unchanged.
skin_pad = false;
// Which end of the XIAO the chip antenna is at (NOT confirmed yet):
// "far_end" = opposite the USB-C (expected), "usb_end" = same end as USB-C.
// The antenna end always goes to the plastic-only LEFT wall, overhanging the
// battery; this flips the XIAO (and the USB-C port: right wall -> left wall) to match.
antenna_at = "far_end";
// Lid fastening: "screws" = 2x M1.6 x 8 self-tapping into bosses
//                "snap"   = 4 bumps on the lid into a groove in the rim
lid_fastening = "screws";

// PRESET parameters. Leave them undef and the preset decides; give one a value
// (in the file or with -D, e.g. -D 'bezel_t=1.2') and that value wins over the preset.
//                    default  slim
bezel_t          = undef;   // 1.6      1.0    bezel thickness over the lid
back_depth       = undef;   // 2.6      1.6    dome: shell thickness at the centre of the skin side

/* [Shell] */
wall        = 2.0;   // side wall
R_out       = 6.0;   // plan-view corner radius of the pebble
back_inset  = 10;    // dome: how far in from the edge the dome flattens out
back_steps  = 10;
lid_t       = 1.2;
rabbet      = 0.6;   // lid sits in a step this wide inside the rim
front_ch    = 1.0;   // 45 deg chamfer on the front edge (prints face-down)
headroom    = 0.4;   // gap above the tallest board part

/* [XIAO nRF52840 Sense - Seeed Studio, board = "nrf52840"] */
xiao_l        = 21.0;
xiao_w        = 17.8;
xiao_pcb_t    = 1.0;   // (?) PCB thickness
xiao_h        = 4.2;   // (?) total height incl. USB-C ("about 4 mm")
usb_w         = 9.0;   // (?) USB-C receptacle width
usb_h         = 3.2;   // (?) USB-C receptacle height
usb_overhang  = 1.0;   // (?) receptacle sticks out past the PCB edge
xiao_parts_h  = 1.6;   // (?) tallest part on the top face other than the USB-C (shield can, IMU)
ant_len       = 5.0;   // (?) length of the chip-antenna zone at its end
ant_overhang  = 6.0;   // how far the antenna end sticks out past the battery edge
// PDM mic (WMM7035DTTJ0 / MSM261-class, ~64 dB(A) SNR), on the TOP side (?)
mic_from_usb  = 10.5;  // (?) mic centre, measured along the board from the USB-C end.
                       // Must leave the gasket clear of the USB-C shell (assert below);
                       // 9 mm put the gasket ring on top of the receptacle.
mic_from_edge = 5.0;   // (?) mic centre from the long edge facing the capsule bottom
mic_pkg       = [3.5, 2.65, 1.0];  // (?) package L x W x H

/* [XIAO nRF54LM20A Sense - Seeed Studio, board = "nrf54lm20a"] */
// From Seeed's own KiCad project + STEP model (XIAO_nRF54LM20A_V1.0_SCH&PCB_260508.zip,
// wiki "Resources"). Board frame: "from_usb" is along the board from the USB-C end,
// "from_edge" is from the long edge with 5V/GND/3V3/D10-D7, which faces the capsule bottom.
// No chip antenna: the only antenna is an external FPC on an IPEX4 (MHF4) lead.
lm_l             = 20.955;
lm_w             = 17.78;
lm_pcb_t         = 1.6;
lm_h             = 4.86;   // board bottom to the top of the USB-C shell
lm_usb_w         = 8.94;
lm_usb_h         = 3.26;   // shell height above the board's top face (taken as sitting on it (?))
lm_usb_overhang  = 2.44;   // past the board edge in the STEP; the KiCad User.1 layer says 1.6 (?)
lm_usb_len       = 8.04;   // shell length (5.6 over the board + the overhang)
lm_parts_h       = 1.2;    // (?) tallest part on the top face other than the USB-C (IPEX4 plug, mic)
lm_mic_from_usb  = 19.43;  // MSM261DGT006 PDM mic, 4 x 2 x 1.1 mm, top port (its footprint has
lm_mic_from_edge = 13.22;  //   no PCB sound hole), 0.5 mm from the far board edge
lm_mic_pkg       = [2.0, 4.0, 1.16];   // X (along the board) x Y x height above the top face
lm_ipex_from_usb  = 19.43; // IPEX Gen 4 receptacle ECT818000500 (ANT2), top face, far end
lm_ipex_from_edge = 9.46;
ipex_plug        = [3.0, 2.0, 1.2];   // (?) mated MHF4 plug: along its cable x across x height
                                      //     above the PCB (I-PEX: 1.2 mm max mated height)

/* [2.4 GHz FPC antenna A-04 - Seeed SKU 100039813, board = "nrf54lm20a"] */
// Datasheet: 35.2 x 8.5 mm radiator, 0.81 mm coax 50 +/- 2 mm long, IPEX4 plug, 3M adhesive.
// The coax is soldered at the middle of one long edge. Ships with the Sense (per the wiki).
// It sticks flat into a pocket on the LEFT (plastic-only) inner wall, feed edge DOWN, with
// fpc_keepout of air to the battery and the boards.
fpc_l        = 35.2;
fpc_w        = 8.5;
fpc_t        = 0.3;   // (?) not published: flex + adhesive
fpc_pocket   = 0.3;   // locating recess in the wall; the FPC face ends up flush with it
fpc_keepout  = 5.5;   // (?) rule of thumb for FPC antennas (5 mm minimum, more is better)
coax_d       = 0.81;
coax_len     = 50.0;
coax_bend_r  = 2.0;   // (?) minimum bend radius used for the U-turn under the FPC
coil_r       = 4.5;   // spare coax is coiled flat on top of the XIAO, inside this ring
coil_at      = [9.0, 9.46];   // ring centre in board coordinates (from the FAR end, from_edge)
coil_lift    = 0.9;   // ring sits on the parts under it (tallest there ~0.86: the IMU is outside it)
// Mic seal for this board: the mic is too close to the board edge and the IPEX4 plug for
// the ring gasket, so a foam pad with a hole is pressed onto the mic's lid instead.
mpad_t       = 1.0;   // (?) closed-cell foam (PORON-type), punched to the mic outline
mpad_hole    = 1.0;
mpad_squeeze = 0.3;
mpad_pocket  = 0.6;   // the pad sits this deep in the lid's holder
mpad_wall    = 0.6;   // holder wall around the pad

/* [USB-C port: the only charging + sync port] */
// An open slot in the side wall, in front of the XIAO's receptacle, that takes a normal
// cable's overmould (the plug goes ~4 mm into the case). part="usb_plug" is an optional dust cap.
usb_plug_w    = 12.4;  // (?) overmould width: a common full-size cable; measure yours
usb_plug_h    = 6.5;   // (?) overmould thickness

/* [Storage: Pololu #2597 microSD breakout, storage = "pololu_sd"] */
sd_l             = 20.3;
sd_w             = 17.8;
sd_h             = 3.5;   // incl. card
sd_card_overhang = 3.0;   // (?) card sticks out past the board edge (points LEFT)
sd_card_w        = 11.0;  // microSD card width

/* [Storage: Adafruit #4899 XTSD 512 MB SD NAND, storage = "sd_nand"] */
// Outline, holes and header from Adafruit's EagleCAD file
// (github.com/adafruit/Adafruit-SPI-Flash-SD-Card-PCB): 0.85" x 0.70", 2.54 mm corner radius.
// The chip is soldered on, so nothing overhangs the board.
nand_l      = 21.59;  // along X
nand_w      = 17.78;  // along Y; the 7-pin header row runs along the +Y edge in this layout
nand_h      = 2.9;    // PCB + tallest part (Adafruit: "21.4 x 17.7 x 2.9 mm")
nand_pcb_t  = 1.6;    // (?) not stated; the usual Adafruit board
nand_wire_h = 1.0;    // (?) solder fillets + wires leaving the header holes flat, on top

/* [Battery] */
// "400"  Core Electronics CE04375: 38 x 25 x 6 mm, 11 g (the listing doesn't say whether
//        that includes the PCM end, hence (?))
// "600"  Little Bird Electronics LB-00237, 600 mAh: 29 x 36 x 5.5 mm, 10.5 g (?) as listed,
//        PCM assumed folded inside that outline. Neither Core nor Adafruit sells a ~600 mAh
//        protected 2-pin cell (Nov 2026); Adafruit #1578 (500 mAh, 29 x 36 x 4.75 mm, 10.5 g)
//        has the same outline and fits this variant too.
// "1100" Core Electronics CE04377: 51 x 34 x 6 mm, 21 g
batt_gap   = 1.0;   // foam tape between battery and the boards above it
batt_dims  = battery == "1100" ? [34, 51, 6.0]   // [across X, along Y, thick]
           : battery == "600"  ? [29, 36, 5.5]   // (?) as listed
                               : [25, 38, 6.0];  // (?) 400 mAh, incl. PCM end
batt_end_gap = 1.5; // air between the battery's PCM end and the bottom wall (folded leads)

/* [Adafruit #805 slide switch] */
sw_l        = 8.6;   // (?) body length (slide direction, along Y)
sw_w        = 3.6;   // (?) body width (Z in the case)
sw_d        = 3.5;   // (?) body depth (X, into the case)
sw_act      = [1.6, 1.6, 2.0]; // (?) actuator: slide-dir x width x protrusion
sw_travel   = 1.5;   // (?) actuator travel
sw_leg_l    = 3.0;   // trim the legs to this length
sw_flush    = 0.3;   // actuator tip sits this far below the outer surface
sw_pocket   = 1.2;   // finger recess depth around the actuator

/* [Mic port - both mics] */
port_d       = 1.0;  // through-hole in the lid (front face), >= 1.0 mm
bezel_port_d = 2.0;  // bigger hole in the bezel so it never shades the port

/* [IM73D122 mic board - mic = "im73d122"] */
// A custom ~8 x 6 mm board: IM73D122 (bottom port) + 1 uF 0402 on the back, a 0.8 mm sound hole
// through the board under the mic, 4 edge pads (VDD, GND, CLK, DATA) on the -X 6 mm edge.
// It lies flat on the inside of the lid, mic facing into the case. Stack from outside:
// lid (port_d hole) -> compressed gasket ring -> board hole -> mic.
// It slides into a pocket under the lid, wire edge last: two rails hold its long edges, a stop
// wall at the closed end puts the hole on the port, and the gasket's compression holds it.
mic_port_x   = 0;     // port across the capsule (capsule frame; 0 = centreline, the eagle's breast)
mic_port_dy  = -3.5;  // port centre relative to the XIAO's lower edge (cavity Y): the pocket
                      // then laps 0.5 mm over the XIAO's pad strip, clear of the LED pipe
mpcb_l       = 8.0;   // (?) board length (X); the wires leave the -X end
mpcb_w       = 6.0;   // (?) board width (Y)
mpcb_t       = 0.8;   // (?) PCB thickness
mpcb_hole    = 0.8;   // sound hole through the board, under the mic's port
mpcb_port    = 2.5;   // (?) hole centre from the closed (+X) end, centred across the width
mpcb_parts   = [5.0, 3.6, 1.2];  // (?) mic + 1 uF cap on the back, centred on the hole: X x Y x height
mpcb_pads    = 1.5;   // (?) wire pads along the -X end, on the back
mwire_d      = 0.8;   // 30 AWG silicone wire (Adafruit #3164 / #3169), 4 of them, side by side
mgk_t        = 0.5;   // (?) gasket ring, free thickness: closed-cell silicone sponge or PORON
mgk_squeeze  = 0.15;  // compressed to mgk_t - mgk_squeeze (asserted 0.3..0.5)
mgk_id       = 1.5;
mgk_od       = 4.0;
mpk_wall     = 0.8;   // pocket wall around the board
mpk_lip      = 0.5;   // rail lip under each long edge of the board
mpk_lip_t    = 0.6;   // rail lip thickness
mic_wall_max = 1.5;   // most plastic allowed at the port (lid thickness there)
mic_clr      = 0.2;   // air between the board (pocket, parts, wires) and anything else

/* [Onboard mic seal - mic = "onboard"] */
port_len    = 0.8;   // length of the lid hole before the foam chamber
foam_dia    = 5.0;   // foam disc diameter
foam_t      = 2.0;   // foam disc thickness (the recess is at least this deep)
gasket_id   = 5.0;   // (?) needs a clear ring of PCB around the mic
gasket_od   = 7.0;
gasket_t    = 1.3;
gasket_groove = 0.6;
gasket_squeeze = 0.3;

/* [Recording LED window - REQUIRED (docs/LEGAL.md, docs/WIRING.md section 5)] */
// A light pipe from the XIAO's onboard RGB LED straight up through the lid and the bezel,
// flush with the front face. Use a 1.75 mm offcut of clear PETG/PC filament or 2 mm
// acrylic rod. An external LED on D3 can sit under the pipe instead (WIRING.md section 5).
led_pipe_d   = 1.75;  // light pipe diameter
led_gap      = 0.3;   // air between the LED and the bottom of the pipe
led_recess   = 0.1;   // pipe top sits this far below the front face
led_sleeve_w = 0.8;   // wall of the guide sleeve under the lid
led_web      = 2.0;   // minimum plastic between the LED window and the mic port (assert)
// onboard RGB LED (board coordinates as for the mic). nRF54LM20A: LED1 in Seeed's KiCad file.
led_from_usb    = 2.9;    // (?) XIAO nRF52840 Sense: assumed the same spot as the LM20A
led_from_edge   = 2.95;   // (?) beside the USB-C, on the bottom-facing edge side
lm_led_from_usb  = 2.89;  // nRF54LM20A LED1 (FC-B1010RGBT, 1 x 1 x 0.85 mm)
lm_led_from_edge = 2.95;
led_pkg      = [1.0, 1.0, 0.85];   // (?) for the nRF52840

/* [Lanyard / bail] */
bail_style = "flat";   // "flat" = slot for flat cord, "round" = loop for round cord
cord_w = 8.0;  cord_t = 2.5;  cord_round_d = 3.0;
bail_wall = 1.8;  bail_thick = 4.5;

/* [Screws / pegs] */
screw_pilot = 1.3;  screw_clear = 1.8;  screw_head = 3.2;
boss_r = 2.1;  boss_inset = 2.4;
peg_d = 2.2;  peg_barb = 0.25;  peg_slot = 0.6;  peg_inset = 3.5;

/* [Emblem] */
emblem_ridge = 0.45;     // raised line between low-poly facets
emblem_margin = 5.0;     // emblem width = face width - 2 x margin

/* [Front plate style] */
// "eagle" = snap-on eagle plate: spread wings and a head that overhang the pebble (default)
// "flush" = the original bezel, flush with the pebble, with the engraved low-poly emblem.
// Only the bezel part and the stand seat change; the body, lid and electronics don't.
bezel_style = "eagle";

/* [Eagle plate - bezel_style = "eagle"] */
// The wing is drawn in design units: u runs out from the pebble's side (u = 16 is the
// outermost feather tip), v runs up from the pebble's top edge (mm).
wing_span    = 70;    // overall width, wing tip to wing tip (60-80; overhang 10-20 mm a side)
wing_drop    = 20.5;  // wing root trailing edge sits this far below the pebble's top edge
wing_lift    = 0;     // dihedral: raises the outer wing by this much (negative = droop)
wing_t       = 2.2;   // plate thickness: flat back on the lid, the wings overhang at this
tip_r        = 2.0;   // radius of every outer tip and corner (doesn't snag clothing)
wing_back_ch = 1.0;   // 45 deg chamfer on the wing and head undersides, toward the chest
plate_ch     = 0.6;   // front edge chamfer on the wings and head
rib_h        = 1.2;   // stiffening band along the wing's leading edge (the root's scapular is 0.75 x)
relief_min   = 0.4;   // feather facets stand this far (min .. max) above the plate face
relief_max   = 1.2;
relief_port_clr = 1.5;  // no relief within this of the mic port's edge (assert >= 1.5)
relief_led_clr  = 0.8;  // ... nor of the LED window's edge
head_w       = 15;    // head width (it hides the bail)
head_top     = 9.6;   // head crown above the pebble's top edge
head_chin    = 7.5;   // beak tip below the pebble's top edge
head_roof    = 1.5;   // plastic over the cord tunnel behind the head
eye_d        = 0.5;   // engraved eye depth
cord_tunnel_clr = 0.4;  // extra air around the cord in the tunnel behind the head
waist_w      = 22;    // body width at the waist, between the wings and the tail fan
waist_frac   = 0.42;  // waist height above the pebble's bottom edge, as a fraction of its height
breast_rows  = 5;     // rows of breast feathers under the beak (scaled up on taller pebbles)
breast_w     = 24;    // width of the oval patch they fill
tail_flare   = 6;     // the tail fans out to the pebble's full width at the bottom (covers the screws)
sw_access    = 5.0;   // the wing stays this far above the privacy switch (finger room)
pin_sock     = 1.6;   // socket depth for the separate peg pins in the plate's back

/* [Skin pad - optional, skin_pad = true, TPU 95A] */
pad_t       = 1.0;   // pad thickness (0.8-1.2 is comfortable in TPU 95A)
pad_recess  = 0.5;   // pocket depth in the back; the pad stands pad_t - pad_recess proud
pad_margin  = 5.0;   // pad edge this far in from the outline (keeps the pocket off the thin rim)
pad_floor   = 0.8;   // minimum shell left under the pocket (assert)
pad_chamfer = 0.4;   // skin-side edge chamfer

// =====================================================================
//  Derived layout  (cavity frame: x,y from the inner bottom-left corner)
// =====================================================================
function one_of(v, list) = len([for (x = list) if (x == v) 1]) > 0;
assert(one_of(battery, ["400", "600", "1100"]), str("battery must be \"400\", \"600\" or \"1100\" (a quoted string), got ", battery));
assert(one_of(storage, ["pololu_sd", "sd_nand"]), str("storage must be \"pololu_sd\" or \"sd_nand\", got ", storage));
assert(one_of(board, ["nrf52840", "nrf54lm20a"]), str("board must be \"nrf52840\" or \"nrf54lm20a\", got ", board));
assert(one_of(mic, ["im73d122", "onboard"]), str("mic must be \"im73d122\" or \"onboard\", got ", mic));
assert(one_of(preset, ["default", "slim"]), str("preset must be \"default\" or \"slim\", got ", preset));
assert(one_of(bezel_style, ["eagle", "flush"]), str("bezel_style must be \"eagle\" or \"flush\", got ", bezel_style));
eagle = (bezel_style == "eagle");

// PRESET resolution: an explicit value (file or -D) wins, undef takes the preset's value
function preset_pick(v, dflt, slim) = !is_undef(v) ? v : (preset == "slim" ? slim : dflt);
bezel_th   = preset_pick(bezel_t, 1.6, 1.0);
dome_d     = preset_pick(back_depth, 2.6, 1.6);

// ---- the board: every board-specific number goes through these ----
lm         = (board == "nrf54lm20a");
bd_l       = lm ? lm_l : xiao_l;
bd_w       = lm ? lm_w : xiao_w;
bd_pcb_t   = lm ? lm_pcb_t : xiao_pcb_t;
bd_h       = lm ? lm_h : xiao_h;
bd_usb_w   = lm ? lm_usb_w : usb_w;
bd_usb_h   = lm ? lm_usb_h : usb_h;
bd_usb_over = lm ? lm_usb_overhang : usb_overhang;
bd_usb_len = lm ? lm_usb_len : 7.3;
bd_mic_u   = lm ? lm_mic_from_usb : mic_from_usb;
bd_mic_e   = lm ? lm_mic_from_edge : mic_from_edge;
bd_mic_pkg = lm ? lm_mic_pkg : mic_pkg;
bd_parts_h = lm ? lm_parts_h : xiao_parts_h;
ext_mic    = (mic == "im73d122");
// how the port is sealed: "board" = IM73D122 board in the lid pocket; on the XIAO's own mic,
// "ring" = gasket ring on the PCB (nRF52840), "pad" = foam pad on the mic's lid (nRF54LM20A)
mic_seal   = ext_mic ? "board" : lm ? "pad" : "ring";

// Antenna rule.
//   nrf52840:   the chip-antenna end of the XIAO overhangs the battery by ant_overhang,
//               over the plastic-only LEFT wall (assert: overhang >= ant_len).
//   nrf54lm20a: no antenna on the board. The FPC is on the LEFT wall and the battery, both
//               boards (and the microSD card) start fpc_keepout away from its face.
xiao_flip  = !lm && (antenna_at == "usb_end");   // the LM20A's USB-C always faces right
fpc_x1     = fpc_t - fpc_pocket;                  // FPC inner face (cavity frame x)
keep_x0    = lm ? fpc_x1 + fpc_keepout : clr;     // nothing metal left of this (LM20A)
batt_x0    = lm ? keep_x0 : clr + ant_overhang;
batt_y0    = batt_end_gap;
batt_x1    = batt_x0 + batt_dims[0];
batt_y1    = batt_y0 + batt_dims[1];
batt_t     = batt_dims[2];

xiao_x0    = lm ? keep_x0 : clr + (xiao_flip ? bd_usb_over : 0);
xiao_x1    = xiao_x0 + bd_l;
usb_face_x = xiao_flip ? xiao_x0 - bd_usb_over : xiao_x1 + bd_usb_over;

// lid screw bosses in the two bottom corners; they hang from the rim down to just above the
// battery, and the storage board starts right of the left one
screws     = (lid_fastening == "screws");
boss_z0    = batt_t + 0.5;
boss_keep  = boss_inset + boss_r + 0.3;

// storage board: the same slot for both, the switch stays centred on it
nand       = (storage == "sd_nand");
stor_l     = nand ? nand_l : sd_l;
stor_w     = nand ? nand_w : sd_w;
stor_h     = nand ? nand_h + nand_wire_h : sd_h;
stor_pcb_t = nand ? nand_pcb_t : 1.6;
stor_over  = nand ? 0 : sd_card_overhang;   // the microSD card sticks out LEFT; SD NAND doesn't
sd_card_y0 = (stor_w - sd_card_w) / 2;      // the card's lower edge, from the board's
sd_x0      = max(keep_x0 + stor_over, screws ? boss_keep : 0);
sd_x1      = sd_x0 + stor_l;
sd_y0      = batt_y0;
sd_y1      = sd_y0 + stor_w;
board_gap  = 2.0;
xiao_y0    = max(sd_y1 + board_gap, batt_y1 - bd_w);
xiao_y1    = xiao_y0 + bd_w;

board_z0   = batt_t + batt_gap;
xiao_top   = board_z0 + bd_h;
sd_top     = board_z0 + stor_h;
pcb_top    = board_z0 + bd_pcb_t;
usb_cz     = pcb_top + bd_usb_h / 2;
usb_yc     = (xiao_y0 + xiao_y1) / 2;
tun_w      = usb_plug_w + 2 * tol;
tun_h      = usb_plug_h + 2 * tol;

r_in       = R_out - wall;
sw_inset   = (wall - sw_flush) - sw_act[2] + 0;   // body face sits this far outside the inner wall
cav_x      = max(batt_x1 + clr,
                 sd_x1 + 0.5 + sw_leg_l + sw_d - sw_inset,
                 max(xiao_x1, usb_face_x) + 2);
// the nRF54LM20A's FPC antenna needs the straight part of the left wall to be fpc_l long
cav_y      = max(max(batt_y1, xiao_y1) + clr, lm ? fpc_l + 2 * (r_in + 0.3) : 0);
OW    = cav_x + 2 * wall;
OH    = cav_y + 2 * wall;
CX = -cav_x / 2;  CY = -cav_y / 2;   // capsule frame offset (cavity centred on the origin)

sw_yc    = (sd_y0 + sd_y1) / 2;
sw_z0    = batt_t + 0.6;
sw_x1    = cav_x + sw_inset;         // actuator-side face of the switch body
sw_x0    = sw_x1 - sw_d;

// board coordinates -> cavity frame (u from the USB-C end, e from the bottom-facing edge)
function bpt_x(u) = xiao_flip ? xiao_x0 + u : xiao_x1 - u;
function bpt_y(e) = xiao_flip ? xiao_y1 - e : xiao_y0 + e;
onb_x    = bpt_x(bd_mic_u);          // the XIAO's own mic
onb_y    = bpt_y(bd_mic_e);
mic_top  = pcb_top + bd_mic_pkg[2];
usb_inner = bd_usb_len - bd_usb_over;   // receptacle length over the PCB
ux0      = xiao_flip ? xiao_x0 - bd_usb_over : xiao_x1 - bd_usb_len + bd_usb_over;   // USB-C shell
usb_shell_z1 = pcb_top + bd_usb_h;

// the mic port (cavity frame): over the XIAO's mic, or where the IM73D122 board goes
mic_x    = ext_mic ? mic_port_x - CX : onb_x;
mic_y    = ext_mic ? xiao_y0 + mic_port_dy : onb_y;

// ---- IM73D122 board (cavity frame). Depths are below the lid's inner face. ----
mgk_c    = mgk_t - mgk_squeeze;                 // compressed gasket
mb_x0    = mic_x + mpcb_port - mpcb_l;          // wire end (-X), open end of the pocket
mb_x1    = mic_x + mpcb_port;                   // closed end, against the stop wall
mb_y0    = mic_y - mpcb_w / 2;
mb_y1    = mic_y + mpcb_w / 2;
mwire_w  = 4 * mwire_d + 3 * 0.2;
// [name, plan lo, plan hi, depth of its lowest point below the lid, depth of its top]
mic_pieces = [
    ["mic pocket", [mb_x0 + 0.5, mb_y0 - tol - mpk_wall], [mb_x1 + tol + mpk_wall, mb_y1 + tol + mpk_wall],
                   mgk_c + mpcb_t + mpk_lip_t, 0],
    ["mic board",  [mb_x0, mb_y0], [mb_x1, mb_y1], mgk_c + mpcb_t, mgk_c],
    ["mic + cap",  [mic_x - mpcb_parts[0] / 2, mic_y - mpcb_parts[1] / 2],
                   [mic_x + mpcb_parts[0] / 2, mic_y + mpcb_parts[1] / 2], mgk_c + mpcb_t + mpcb_parts[2], mgk_c + mpcb_t],
    ["mic wires",  [mb_x0 - 3, mic_y - mwire_w / 2], [mb_x0 + mpcb_pads, mic_y + mwire_w / 2],
                   mgk_c + mpcb_t + mwire_d, mgk_c + mpcb_t]];
mic_depth = max([for (p = mic_pieces) p[3]]);

// what sits under the lid, as boxes [name, lo, hi] (cavity frame); the board must clear them
function box3(n, lo, hi) = [n, lo, hi];
low_obstacles = concat(
    [box3("battery", [batt_x0, batt_y0, 0], [batt_x1, batt_y1, batt_t]),
     box3("XIAO", [xiao_x0, xiao_y0, board_z0], [xiao_x1, xiao_y1, pcb_top + bd_parts_h]),
     box3("USB-C shell", [ux0, usb_yc - bd_usb_w / 2, pcb_top], [ux0 + bd_usb_len, usb_yc + bd_usb_w / 2, usb_shell_z1]),
     box3("USB-C plug", [xiao_flip ? -wall : usb_face_x, usb_yc - tun_w / 2, usb_cz - tun_h / 2],
                        [xiao_flip ? usb_face_x : cav_x + wall, usb_yc + tun_w / 2, usb_cz + tun_h / 2]),
     box3("storage board", [sd_x0, sd_y0, board_z0], [sd_x1, sd_y1, board_z0 + stor_pcb_t]),
     box3("switch", [sw_x0 - sw_leg_l, sw_yc - sw_l / 2 - tol - 1, sw_z0 - 0.5], [cav_x, sw_yc + sw_l / 2 + tol + 1, sw_z0 + sw_w])],
    nand ? [box3("SD NAND parts", [sd_x0 + 1, sd_y0 + 1, board_z0], [sd_x1 - 1, sd_y1 - 4, board_z0 + nand_h]),
            box3("SD NAND header wires", [sd_x0 + 1.5, sd_y1 - 3.6, board_z0], [sd_x1 - 1.5, sd_y1 - 1.4, sd_top])]
         : [box3("microSD card", [sd_x0 - sd_card_overhang, sd_y0 + sd_card_y0, board_z0],
                 [sd_x0 + 15 - sd_card_overhang, sd_y0 + sd_card_y0 + sd_card_w, sd_top])],
    lm ? [box3("coax coil + plug", [xiao_x0 - coax_d - 0.6, xiao_y0 + coil_at[1] - coil_r, pcb_top],
               [xiao_x0 + coil_at[0] + coil_r + 2, xiao_y0 + coil_at[1] + coil_r, pcb_top + coil_lift + 2.5 * coax_d])] : []);
// keep the board's copper off the antenna: the chip-antenna end (nRF52840), the FPC keepout (nRF54LM20A)
zone_obstacles = lm ? [box3("FPC antenna keepout", [-wall, 0, -10], [fpc_t - fpc_pocket + fpc_keepout, 100, 100])]
                    : [box3("chip antenna zone", [xiao_x0 - 10, xiao_y0, -10], [xiao_x0 + ant_len, xiao_y1, 100])];
function plan_gap(a0, a1, b0, b1) = max(b0[0] - a1[0], a0[0] - b1[0], b0[1] - a1[1], a0[1] - b1[1]);
function box_gap(a0, a1, b0, b1) = max(plan_gap(a0, a1, b0, b1), b0[2] - a1[2], a0[2] - b1[2]);
// the cavity is deep enough for the board stack over whatever sits under it
mic_need_top = max(concat([0], [for (p = mic_pieces, o = low_obstacles)
                   if (plan_gap(p[1], p[2], o[1], o[2]) < mic_clr) o[2][2] + mic_clr + p[3]]));

cav_top    = max(xiao_top + headroom,
                 sd_top + headroom,
                 usb_cz + tun_h / 2 + 0.4,                 // the USB-C port (every variant)
                 ext_mic ? mic_need_top : 0);

z_lid_bot  = cav_top;
z_rim      = cav_top + lid_t;
z_top      = z_rim + bezel_th;
// mic = "onboard": lid mic boss. "ring": a cylinder down to the TPU ring on the PCB around
// the mic. "pad": a narrow holder down onto a foam pad on the mic's lid, widening into the
// foam chamber only above the IPEX4 plug.
mhold      = [bd_mic_pkg[0] + 2 * (tol + mpad_wall), bd_mic_pkg[1] + 2 * (tol + mpad_wall)];
boss_bot   = mic_seal == "ring" ? pcb_top + gasket_t - gasket_groove - gasket_squeeze
                                : mic_top + mpad_t - mpad_squeeze - mpad_pocket;
mic_boss_d = mic_seal == "ring" ? gasket_od + 1.2 : foam_dia + 1.2;
wide_z     = mic_seal == "ring" ? boss_bot : pcb_top + ipex_plug[2] + 0.3;   // where the boss gets wide
chamber_z  = mic_seal == "ring" ? mic_top : max(wide_z, boss_bot + mpad_pocket);   // foam chamber floor (ring: the mic)
boss_half_x = mic_seal == "ring" ? mic_boss_d / 2 : max(mhold[0] / 2, mic_boss_d / 2);
usb_gasket_gap = (bd_mic_u - boss_half_x) - usb_inner;   // lid mic boss vs USB-C shell

// ---- LM20A: FPC antenna, IPEX4 plug and coax route (cavity frame) ----
fpc_y0     = cav_y / 2 - fpc_l / 2;
fpc_y1     = fpc_y0 + fpc_l;
fpc_z0     = coax_bend_r + coax_d / 2 + 0.3;    // feed edge, with the U-turn below it
fpc_z1     = fpc_z0 + fpc_w;
fpc_cy     = cav_y / 2;                          // the coax leaves the middle of the long edge
ipex_x     = bpt_x(lm_ipex_from_usb);
ipex_y     = bpt_y(lm_ipex_from_edge);
coil_cx    = xiao_x0 + coil_at[0];               // the far end is the left end (USB-C right)
coil_cy    = xiao_y0 + coil_at[1];
coil_z     = pcb_top + coil_lift;                // two layers of coax fit above this
cr         = coax_d / 2;
riser_x    = fpc_x1 + cr + 2 * coax_bend_r;      // coax climbs here after the U-turn
z_over     = coil_z + coax_d + cr;               // coax crosses over the plug at this height
coax_path  = concat(
    [[coil_cx - coil_r, ipex_y, z_over],                    // leaves the coil, heading left
     [xiao_x0 - cr - 0.3, ipex_y, z_over],                  // past the board end
     [riser_x, ipex_y, z_over - coax_bend_r],
     [riser_x, fpc_cy, fpc_z0]],                            // down the keepout gap
    [for (a = [0 : 30 : 180]) [fpc_x1 + cr + coax_bend_r + coax_bend_r * cos(a), fpc_cy,
                               fpc_z0 - coax_bend_r * sin(a)]],   // U-turn under the FPC
    [[fpc_x1 + cr, fpc_cy, fpc_z0 + 1.5]]);                 // up onto the solder tab
function plen(p, i = 0) = i >= len(p) - 1 ? 0 : norm(p[i + 1] - p[i]) + plen(p, i + 1);
coax_fixed = plen(coax_path) + (coil_cx - coil_r - ipex_x) + 2;   // + plug / tab allowances
coax_spare = coax_len - coax_fixed;
coil_turns = coax_spare / (2 * PI * coil_r);

// recording LED light pipe (cavity frame)
led_u      = lm ? lm_led_from_usb : led_from_usb;
led_e      = lm ? lm_led_from_edge : led_from_edge;
led_x      = bpt_x(led_u);
led_y      = bpt_y(led_e);
led_top    = pcb_top + led_pkg[2];
led_hole_d = led_pipe_d + 2 * tol;
pipe_z0    = led_top + led_gap;
plate_face = eagle ? z_rim + wing_t : z_top;   // front face of the bezel / eagle plate (flat part)
pipe_z1    = plate_face - led_recess;
// the guide sleeve hangs under the lid, but only above the USB-C shell (it sits beside it)
sleeve_z0  = max(pipe_z0, usb_shell_z1 + 0.3);
sleeve_d   = led_hole_d + 2 * led_sleeve_w;
// clearances the asserts check
led_mic_web   = norm([led_x - mic_x, led_y - mic_y]) - (led_hole_d + max(bezel_port_d, port_d)) / 2;
led_boss_gap  = norm([led_x - mic_x, led_y - mic_y]) - sleeve_d / 2   // mic = "onboard" only
                - (mic_seal == "ring" ? mic_boss_d / 2 : norm([mhold[0], mhold[1]]) / 2);
led_usb_gap   = abs(led_e - bd_w / 2) - bd_usb_w / 2 - led_pipe_d / 2;   // pipe beside the USB-C shell
led_on_board  = led_u > led_pipe_d / 2 && led_u < bd_l - led_pipe_d / 2 && led_e > led_pipe_d / 2 && led_e < bd_w - led_pipe_d / 2;
// bezel pegs: a peg that would land on the LED window steps inward along X to clear it
// (only happens with antenna_at = "usb_end", where the LED ends up in the top-left corner)
led_peg_need  = (peg_d + 2 * tol) / 2 + sleeve_d / 2 + 0.6;
function peg_clear(p) = norm([p[0] - led_x, p[1] - led_y]) >= led_peg_need ? p
    : [led_x + (p[0] < cav_x / 2 ? 1 : -1) * sqrt(max(0, pow(led_peg_need, 2) - pow(p[1] - led_y, 2))), p[1]];
peg_list      = [for (p = [[peg_inset, cav_y - peg_inset], [cav_x - peg_inset, cav_y - peg_inset], [cav_x / 2, peg_inset]])
                 peg_clear(p)];
function dist_to_pts(p, pts) = min([for (q = pts) norm([p[0] - q[0], p[1] - q[1]])]);
led_peg_gap   = dist_to_pts([led_x, led_y], peg_list) - (peg_d + 2 * tol) / 2 - sleeve_d / 2;
led_coil_gap  = norm([led_x - coil_cx, led_y - coil_cy]) - (coil_r + cr) - sleeve_d / 2;

// IM73D122 board: every piece against everything under (and hanging from) the lid
peg_hole_r    = peg_d / 2 + tol;
high_obstacles = concat(
    [box3("LED light-pipe sleeve", [led_x - sleeve_d / 2, led_y - sleeve_d / 2, sleeve_z0],
                                   [led_x + sleeve_d / 2, led_y + sleeve_d / 2, z_rim])],
    screws ? [for (p = [[boss_inset, boss_inset], [cav_x - boss_inset, boss_inset]])
              box3("lid screw boss", [p[0] - boss_r, p[1] - boss_r, boss_z0], [p[0] + boss_r, p[1] + boss_r, z_rim])] : [],
    [for (p = peg_list) box3("bezel peg", [p[0] - peg_hole_r - 0.4, p[1] - peg_hole_r - 0.4, z_lid_bot - 0.8 - 0.1],
                                          [p[0] + peg_hole_r + 0.4, p[1] + peg_hole_r + 0.4, z_rim])]);
mic_boxes = [for (p = mic_pieces) [p[0], concat(p[1], [z_lid_bot - p[3]]), concat(p[2], [z_lid_bot - p[4]])]];
mic_gaps  = [for (m = mic_boxes, o = concat(low_obstacles, high_obstacles, zone_obstacles))
             [str(m[0], " to ", o[0]), box_gap(m[1], m[2], o[1], o[2])]];
mic_gap_min = min([for (g = mic_gaps) g[1]]);
mic_tightest = [for (g = mic_gaps) if (g[1] == mic_gap_min) g[0]][0];
mic_lid_port = lid_t;                    // plastic the sound passes through in the lid
mgk_on_board = min(mb_x1 - mic_x, mic_x - mb_x0, mic_y - mb_y0, mb_y1 - mic_y) - mgk_od / 2;

// skin pad: dome height at the pocket edge, and how far the flat-printed pad must bend
function dome_z(inset) = inset >= back_inset ? -dome_d : -dome_d * sin(acos(1 - inset / back_inset));
pad_proud  = pad_t - pad_recess;
pad_floor_left = -dome_z(pad_margin) - pad_recess;   // thinnest shell under the pocket
pad_sag    = dome_z(pad_margin) + dome_d;            // rim-to-centre rise the flat pad bends through

// ---- eagle plate (capsule frame: origin at the pebble centre) ----
yT       = OH / 2;                       // pebble top edge
hw       = OW / 2;                       // pebble half width
wing_over = wing_span / 2 - hw;          // how far each wing overhangs the pebble
wk       = (wing_span / 2 - tip_r - hw) / 16;   // design u -> mm (u = 16: outermost tip centre)
wv       = wing_drop / 20.5;                    // design v -> mm
function wpt(p, s = 1) = [s * (hw + p[0] * wk), yT + p[1] * wv + wing_lift * p[0] / 16];
// right wing, inner panel (convex): wing points (design units) + shoulder points (mm, at the head)
wing_arm   = [[0, -20.5], [10, -8], [11, 0.5], [7, 3.6], [0, 2.6]];
function wing_arm_pts(s) = concat([for (q = wing_arm) wpt(q, s)],
    [[s * (hh - 1), yT + 0.8], [s * (hh - 1), yT - 6], [s * (hw - 3), yT - wing_drop + 1]]);
// feathers: [base uv, base radius, tip uv, facet height at the base, at the tip]
// 4 fingered primaries at the tip, 3 secondaries scalloping the trailing edge
wing_feathers = [
    [[8.0,  1.8], 2.6, [14.6,  4.6], 1.0, 0.5],
    [[9.0,  0.0], 2.6, [16.0, -0.2], 1.0, 0.5],
    [[8.6, -2.2], 2.6, [15.2, -5.0], 0.9, 0.45],
    [[7.8, -4.4], 2.6, [13.4, -9.4], 0.9, 0.45],
    [[7.2, -7.4], 2.6, [9.8, -13.0], 0.8, 0.4],
    [[4.6, -11.0], 2.6, [6.2, -16.2], 0.8, 0.4],
    [[1.8, -14.4], 2.6, [2.6, -19.0], 0.7, 0.4]];
// coverts: shorter feathers laid over the inner panel (inside the silhouette); the last one is
// the scapular along the wing root, which doubles as the root's stiffening rib
wing_coverts = [
    [[6.0, -1.0], 2.0, [9.8, -6.6], 0.8, 0.45],
    [[3.4, -3.6], 2.0, [6.8, -10.0], 0.8, 0.45],
    [[1.2, -6.6], 2.0, [3.8, -13.4], 0.7, 0.4],
    [[4.4,  0.2], 1.8, [6.4, -3.6], 0.6, 0.4],
    [[1.8, -1.6], 1.8, [3.0, -5.6], 0.6, 0.4],
    [[0.2,  0.0], 2.0, [0.6, -18.2], 0.75 * rib_h, 0.5],
    [[-2.6, -1.2], 1.8, [-1.6, -6.4], 0.6, 0.4],
    [[-5.6, -1.6], 1.8, [-4.6, -6.0], 0.5, 0.4]];
// leading-edge rib: a raised band from the shoulder to the wrist (centres; it tapers, see eagle_wing)
function wing_lead(s) = [[s * (hh + 1.4), yT - 0.4], wpt([0, 1.0], s), wpt([6.8, 2.1], s), wpt([9.6, -0.4], s)];

// body: an hourglass under the head (torso, waist, fanned tail), clipped to the pebble
waist_y  = -OH / 2 + waist_frac * OH;
torso_pts = [[-hw - 1, yT + 1], [hw + 1, yT + 1], [hw + 1, yT - wing_drop + 1],
             [waist_w / 2, waist_y], [-waist_w / 2, waist_y], [-hw - 1, yT - wing_drop + 1]];
tail_pts  = [[-waist_w / 2, waist_y + 3], [waist_w / 2, waist_y + 3], [hw + tail_flare, -OH / 2 - 1],
             [-hw - tail_flare, -OH / 2 - 1]];
// a band down the middle that lies inside torso + tail together (for the plate-edge asserts only)
spine_pts = [[-waist_w / 2, -OH / 2], [waist_w / 2, -OH / 2], [waist_w / 2, yT], [-waist_w / 2, yT]];

// head: hides the bail; the cord runs up a tunnel in its back, out over the crown
cord_pass_w = (bail_style == "flat" ? cord_w : cord_round_d) + 0.6;   // the bail slot
cord_pass_t = (bail_style == "flat" ? cord_t : cord_round_d) + 0.6;
slot_y1  = OH / 2 + bail_ext() - bail_wall;            // bail slot, front opening: top edge
slot_y0  = slot_y1 - cord_pass_t;                      //                          bottom edge
ctun_w   = cord_pass_w + 2 * cord_tunnel_clr;         // tunnel behind the head
ctun_h   = cord_pass_t + cord_tunnel_clr;             // its height above the bail face
ctun_y0  = slot_y0 - 0.5;                             // starts below the slot, open at the crown
head_t   = ctun_h + head_roof;                        // head plateau above z_rim
hh       = head_w / 2;
head_pts = [[-0.8 * hh, yT + head_top], [0.8 * hh, yT + head_top], [hh, yT + head_top - 3.5],
            [hh, yT + 1], [0.6 * hh, yT - 3.5], [0, yT - head_chin], [-0.6 * hh, yT - 3.5],
            [-hh, yT + 1], [-hh, yT + head_top - 3.5]];
head_up  = ctun_h + 0.8;                              // head edge height where it covers the tunnel
eye_y    = yT + 2.4;

// relief keep-outs around the mic port and the LED window
port_cx  = mic_x + CX;  port_cy = mic_y + CY;
led_cx   = led_x + CX;  led_cy  = led_y + CY;
port_keep = max(bezel_port_d, port_d) / 2 + relief_port_clr;
led_keep  = led_hole_d / 2 + relief_led_clr;

// distance from a point to a convex polygon (0 inside)
function seg_d(p, a, b) = let(ab = b - a, t = max(0, min(1, ((p - a) * ab) / (ab * ab)))) norm(p - (a + t * ab));
function inside_cvx(p, pts) = let(n = len(pts), c = [for (i = [0 : n - 1])
    let(a = pts[i], b = pts[(i + 1) % n]) (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])])
    min(c) >= 0 || max(c) <= 0;
function poly_d(p, pts) = inside_cvx(p, pts) ? 0
    : min([for (i = [0 : len(pts) - 1]) seg_d(p, pts[i], pts[(i + 1) % len(pts)])]);
function poly_in(p, pts) = inside_cvx(p, pts)   // > 0: this far inside a convex polygon
    ? min([for (i = [0 : len(pts) - 1]) seg_d(p, pts[i], pts[(i + 1) % len(pts)])]) : -poly_d(p, pts);
// how far a point sits inside the plate (body + inner wing panels; corners rounded off)
function plate_in(p) = max(poly_in(p, torso_pts), poly_in(p, tail_pts), poly_in(p, spine_pts),
                           poly_in(p, wing_arm_pts(1)) - tip_r / 2, poly_in(p, wing_arm_pts(-1)) - tip_r / 2);
port_in_plate = plate_in([port_cx, port_cy]) - max(bezel_port_d, port_d) / 2;
led_in_plate  = plate_in([led_cx, led_cy]) - led_hole_d / 2;
peg_in_plate  = min([for (q = peg_list) plate_in([q[0] + CX, q[1] + CY])]) - peg_d / 2;
port_head_gap = poly_d([port_cx, port_cy], head_pts) - max(bezel_port_d, port_d) / 2;
led_head_gap  = poly_d([led_cx, led_cy], head_pts) - led_hole_d / 2;

// wing: lowest point on the switch (right) side, and the overall plate size
wing_low_y = min(concat([wpt(wing_arm[0])[1]],
                        [for (f = wing_feathers) wpt(f[2])[1] - tip_r]));
sw_top_y   = sw_yc + sw_l / 2 + CY;
plate_top  = max(yT + head_top, max([for (f = wing_feathers) wpt(f[2])[1] + tip_r]));
plate_W    = 2 * max([for (f = wing_feathers) wpt(f[2])[0] + tip_r]);
plate_H    = plate_top + OH / 2;
plate_T    = head_t + 1.0;                             // head plateau + brow / beak facets

// ---------------- info functions (used by dock.scad, the stand) ----------------
function cap_OW()        = OW;
function cap_OH()        = OH;
function cap_zmin()      = -dome_d - (skin_pad ? pad_proud : 0);   // incl. the skin pad
function cap_ztop()      = eagle ? z_rim + wing_t + relief_max : z_top;   // front face over the pebble
function cap_zrim()      = z_rim;
function cap_mic()       = [mic_x + CX, mic_y + CY, plate_face];
function cap_switch_y()  = [sw_yc - sw_l / 2 + CY, sw_yc + sw_l / 2 + CY];
function cap_switch()    = [OW / 2, sw_yc + CY, sw_z0 + sw_w / 2];   // actuator, on the right wall
// USB-C port: centre of the slot on the outer side wall, and which wall (+1 right, -1 left)
function cap_usb()       = [(xiao_flip ? -1 : 1) * OW / 2, usb_yc + CY, usb_cz];
function cap_usb_side()  = xiao_flip ? -1 : 1;
function cap_usb_plug()  = [usb_plug_w, usb_plug_h];   // cable overmould: across (Y) x thick (Z)
function cap_bail_top()  = OH / 2 + bail_ext();
function bail_ext()      = (bail_style == "flat" ? cord_t : cord_round_d) + 0.6 + 2 * bail_wall;
function cap_eagle()     = eagle;
// eagle plate envelope for the stand: convex pieces (plate_env_piece(i)) and the outline points
// of the parts that overhang the pebble, at the back and front of the plate
function cap_plate_n()   = eagle ? 2 + 2 * (1 + len(wing_feathers)) : 0;
function cap_plate_top() = z_rim + plate_T;
function cap_wing_pts()  = !eagle ? [] : [for (s = [-1, 1], z = [z_rim, z_rim + wing_t + relief_max],
    p = concat(wing_arm_pts(s),
               [for (f = wing_feathers, a = [0 : 45 : 315]) wpt(f[2], s) + tip_r * [cos(a), sin(a)]]))
    if (abs(p[0]) > hw) [p[0], p[1], z]];

// ---------------- report ----------------
echo(str("CAPSULE battery=", battery, " storage=", storage, " board=", board, " mic=", mic, " preset=", preset,
         lm ? "" : str(" antenna_at=", antenna_at)));
echo(str("CAPSULE outer W x H x T = ", OW, " x ", OH, " x ", z_top + dome_d,
         " mm  (+", bail_ext(), " mm bail)"));
echo(str("CAPSULE cavity = ", cav_x, " x ", cav_y, " x ", cav_top));
if (eagle) {
    echo(str("EAGLE plate W x H x T = ", plate_W, " x ", plate_H, " x ", plate_T,
             " mm  (wings ", wing_t, " + ", relief_min, "..", relief_max, " relief; capsule with the plate ",
             z_rim + plate_T + dome_d, " mm thick at the head, ", z_rim + wing_t + relief_max + dome_d, " at the wings)"));
    echo(str("FIT eagle: wings overhang ", wing_over, " mm a side, ", wing_low_y - sw_top_y,
             " mm above the switch; cord tunnel ", ctun_w, " x ", ctun_h, " under a ", head_roof,
             " mm roof; relief to mic port ", port_keep - max(bezel_port_d, port_d) / 2,
             " mm, port / LED / pegs inside the plate edge by ", port_in_plate, " / ", led_in_plate, " / ", peg_in_plate,
             " mm, head to mic port ", port_head_gap, " mm, head to LED ", led_head_gap, " mm"));
}
if (lm) {
    echo(str("FIT FPC antenna to battery / boards = ", keep_x0 - fpc_x1, " mm (keepout ", fpc_keepout, ")"));
    echo(str("FIT FPC on the wall: y ", fpc_y0, "..", fpc_y1, " of the straight ", r_in, "..", cav_y - r_in,
             ", top ", fpc_z1, " under the lid at ", z_lid_bot));
    echo(str("FIT coax: ", coax_fixed, " mm routed, ", coax_spare, " mm spare = ", coil_turns,
             " turns in the coil (2 fit)"));
} else
    echo(str("FIT antenna overhang past battery = ", batt_x0 - xiao_x0, " mm (antenna zone ", ant_len, ")"));
echo(str("FIT USB-C port (", xiao_flip ? "left" : "right", " wall, ", usb_yc + CY, " mm above the centre): slot ",
         tun_w, " x ", tun_h, ", floor ", (usb_cz - tun_h / 2) - batt_t, " mm above the battery",
         xiao_flip ? " (not over it)" : "", ", plug ", z_rim - (usb_cz + tun_h / 2),
         " mm under the lid rim", eagle ? " (it slides in behind the wing)" : ""));
if (ext_mic) {
    echo(str("FIT mic board IM73D122: port at x ", mic_x + CX, ", y ", mic_y + CY, " (capsule frame); stack lid ",
             mic_lid_port, " + gasket ", mgk_c, " + board ", mpcb_t, " + mic ", mpcb_parts[2], " = ", mic_depth + lid_t,
             " mm under the front of the lid"));
    echo(str("FIT mic board clearance: tightest ", mic_gap_min, " mm (", mic_tightest, ")"));
} else {
    echo(str("FIT mic chamber above mic = ", (z_rim - port_len) - chamber_z,
             " mm (foam ", foam_t, " mm, seal: ", mic_seal, ")"));
    echo(str("FIT ", mic_seal == "ring" ? "gasket ring" : "mic pad holder", " to USB-C shell = ", usb_gasket_gap, " mm"));
}
echo(str("FIT switch leg tips to SD board = ", (sw_x0 - sw_leg_l) - sd_x1, " mm"));
echo(str("FIT LED window: ", led_mic_web, " mm of plastic to the mic port",
         ext_mic ? "" : str(", sleeve to mic boss ", led_boss_gap, " mm"), ", pipe to USB-C shell ", led_usb_gap, " mm"));
if (screws)
    echo(str("FIT lid screw bosses: ", z_lid_bot - boss_z0, " mm long, ", boss_z0 - batt_t, " mm above the battery"));

// antenna rules, one per board
if (lm) {
    assert(keep_x0 - fpc_x1 >= fpc_keepout, "FPC antenna is closer than fpc_keepout to the battery or a board");
    assert(min(batt_x0, xiao_x0, sd_x0 - stor_over) >= keep_x0, "battery, XIAO or storage inside the FPC keepout");
    assert(fpc_y0 >= r_in + 0.3 && fpc_y1 <= cav_y - r_in - 0.3,
           "FPC antenna is longer than the straight part of the left wall (cavity too short)");
    assert(fpc_z1 <= z_lid_bot - 0.3, "FPC antenna is taller than the cavity");
    assert(riser_x + cr <= keep_x0 - 0.2, "coax U-turn (coax_bend_r) doesn't fit in the FPC keepout gap");
    assert(coax_spare >= 0, "coax is too short to reach the FPC on this layout");
    assert(coil_turns <= 2, "too much spare coax for the coil ring: raise coil_r or shorten the lead");
    assert(z_over + cr <= z_lid_bot - 0.2, "no room for the coax over the IPEX4 plug under the lid");
} else
    assert(batt_x0 - xiao_x0 >= ant_len, "antenna zone is over the battery");
assert(usb_cz - tun_h / 2 > batt_t || xiao_flip, "USB-C port slot hits the battery");
assert(usb_yc + tun_w / 2 <= cav_y - 1 && usb_yc - tun_w / 2 >= 1, "USB-C port slot breaks into the top or bottom wall");
assert(sw_x0 - sw_leg_l > sd_x1, "switch legs hit the SD board");
assert(!screws || z_lid_bot - boss_z0 >= 6.5, "lid screw bosses are shorter than the M1.6 x 8 screw needs (6.5 mm)");
if (ext_mic) {
    // IM73D122 board: acoustic stack-up
    assert(port_d >= 1.0, "mic port in the lid must be at least 1.0 mm");
    assert(mic_lid_port <= mic_wall_max, str("lid is ", mic_lid_port, " mm at the mic port (max mic_wall_max): counterbore it"));
    assert(mgk_c >= 0.3 && mgk_c <= 0.5, str("mic gasket compresses to ", mgk_c, " mm (0.3..0.5 wanted)"));
    assert(mgk_id >= max(port_d, mpcb_hole) + 0.3, "mic gasket hole must be wider than the lid port and the board's sound hole");
    assert(mgk_on_board >= 0.3, "mic gasket ring hangs over the edge of the mic board");
    assert(bezel_port_d >= port_d + 0.6, "the bezel / plate hole must be wider than the lid port");
    assert(mpcb_parts[1] / 2 <= mpcb_w / 2 - mpk_lip - 0.2, "mic board parts don't pass between the pocket rails");
    assert(mpcb_parts[0] / 2 <= mpcb_port && mpcb_l - mpcb_port - mpcb_parts[0] / 2 >= mpcb_pads,
           "mic and cap don't fit between the closed end and the wire pads");
    assert(mpk_lip - tol >= 0.25, "pocket rails hold the mic board's edges by under 0.25 mm");
    // IM73D122 board: clear of the boards, battery, USB-C, LED pipe, bosses, pegs and antenna
    for (g = mic_gaps) assert(g[1] >= mic_clr, str("mic board: ", g[0], " only ", g[1], " mm apart (needs mic_clr)"));
} else {
    assert((z_rim - port_len) - chamber_z >= foam_t, "no room for the foam disc");
    assert(usb_gasket_gap >= 0, "mic boss / gasket sits on the USB-C receptacle: re-measure mic_from_usb");
}
// recording LED window (required)
assert(led_on_board, "LED light pipe is not over the XIAO (it must sit on the LED, clear of the battery and boards)");
assert(led_mic_web >= led_web, str("LED window is only ", led_mic_web, " mm from the mic port (needs led_web)"));
assert(ext_mic || led_boss_gap >= 0.4, "LED guide sleeve runs into the lid's mic boss");
assert(led_usb_gap >= 0.2, "LED light pipe hits the USB-C shell");
assert(led_peg_gap >= 0.4, "LED window runs into a bezel peg hole");
assert(!lm || led_coil_gap >= 0.3, "LED light pipe runs into the coax coil");
assert(pipe_z0 > led_top && sleeve_z0 < z_lid_bot, "LED light pipe has no room above the LED");
if (mic_seal == "pad")
    assert(boss_bot > pcb_top + ipex_plug[2] || mic_y - mhold[1] / 2 > ipex_y + ipex_plug[1] / 2,
           "the mic pad holder lands on the IPEX4 plug");
if (skin_pad) {
    echo(str("FIT skin pad: ", pad_t, " mm TPU, ", pad_proud, " mm proud (capsule ", z_top + dome_d + pad_proud,
             " mm thick with it), shell under the pocket ", pad_floor_left, " mm, pad bends ", pad_sag, " mm"));
    assert(pad_proud > 0, "skin pad: pad_t must be more than pad_recess or it sits below the shell");
    assert(pad_floor_left >= pad_floor, str("skin pad: only ", pad_floor_left,
           " mm of shell left under the pocket; raise pad_margin or lower pad_recess"));
    assert(pad_sag <= 0.6, "skin pad: the dome is too deep for a flat-printed pad to bend into; raise pad_margin");
}
if (eagle) {
    assert(wing_over >= 10 && wing_over <= 20, str("eagle wings overhang the pebble ", wing_over,
           " mm a side (10-20 wanted): change wing_span"));
    assert(tip_r >= 2, "eagle: outer tips must be rounded to at least 2 mm (tip_r)");
    assert(rib_h >= relief_min && rib_h <= relief_max, "eagle: rib_h outside relief_min..relief_max");
    for (f = concat(wing_feathers, wing_coverts))
        assert(f[3] >= relief_min && f[3] <= relief_max && f[4] >= relief_min && f[4] <= relief_max,
               "eagle: feather facet height outside relief_min..relief_max");
    assert(wing_t >= 2.0 && wing_t <= 2.5, "eagle: wing_t should be 2.0-2.5 mm (self-supporting overhang)");
    assert(relief_port_clr >= 1.5, "eagle: relief must stay >= 1.5 mm from the mic port edge");
    assert(port_head_gap >= relief_port_clr, str("eagle: the head is only ", port_head_gap,
           " mm from the mic port (it would shade it)"));
    assert(led_head_gap >= relief_led_clr, "eagle: the head covers the LED window");
    assert(port_in_plate >= 1.0 && led_in_plate >= 1.0, str("eagle: the mic port or LED window is within 1 mm of the plate edge (",
           port_in_plate, ", ", led_in_plate, "): change waist_w / waist_frac"));
    assert(peg_in_plate >= 1.2, str("eagle: a peg socket is only ", peg_in_plate, " mm inside the plate edge"));
    assert(wing_low_y >= sw_top_y + sw_access, str("eagle: the wing is only ", wing_low_y - sw_top_y,
           " mm above the privacy switch (needs sw_access): raise the wing (wing_drop)"));
    // cord: a flat cord must still thread through the bail slot and out over the crown
    assert(ctun_y0 <= slot_y0 - 0.4, "eagle: cord tunnel doesn't reach below the bail slot");
    assert(ctun_w >= cord_pass_w + 0.6 && ctun_h >= cord_pass_t + 0.3, "eagle: cord tunnel too small for the cord");
    assert(yT + head_top >= slot_y1 + 1, "eagle: the head must reach past the bail slot");
    assert(hh - ctun_w / 2 >= 2.4, "eagle: head walls beside the cord tunnel are under ~1.2 mm after rounding");
    assert(head_up - ctun_h >= 0.6 && head_roof - eye_d >= 1.0, "eagle: too little plastic over the cord tunnel");
    assert(pin_sock <= wing_t - 0.6, "eagle: peg socket leaves under 0.6 mm of plate");
}

// =====================================================================
//  Basic shapes
// =====================================================================
module rrect(w, h, r) {
    rr = max(r, 0.01);
    offset(r = rr) square([max(w - 2 * rr, 0.01), max(h - 2 * rr, 0.01)], center = true);
}
module outline(inset = 0) offset(delta = -inset) rrect(OW, OH, R_out);
module slab(inset, z) translate([0, 0, z]) linear_extrude(0.01) outline(inset);

// Outer pebble. grow > 0 inflates it (used for the stand seat clearance).
module pebble(grow = 0) {
    hull() {
        for (i = [0 : back_steps]) {
            a = 90 * i / back_steps;
            slab(back_inset * (1 - cos(a)) - grow, -dome_d * sin(a) - grow);
        }
        slab(-grow, z_top - front_ch);
        slab(front_ch - grow, z_top + grow);
    }
}
module capsule_envelope(grow = 0) {   // pebble + bail (+ skin pad), for the stand
    pebble(grow);
    bail_solid(grow);
    if (skin_pad) translate([0, 0, -pad_proud]) pebble(grow);
}

module C() translate([CX, CY, 0]) children();          // cavity frame -> capsule frame
module box(p0, p1) translate(p0) cube([p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]);

// =====================================================================
//  Electronics ghosts (capsule frame)
// =====================================================================
// LM20A: FPC in its wall pocket, IPEX4 plug, the coax route and the coil ring (cavity frame)
module lm_antenna() {
    color("Gold", 0.85) box([-fpc_pocket + 0.02, fpc_y0, fpc_z0], [fpc_x1, fpc_y1, fpc_z1]);
    color("Goldenrod", 0.9) box([ipex_x - 1.0, ipex_y - ipex_plug[1] / 2, pcb_top],
                                [ipex_x - 1.0 + ipex_plug[0], ipex_y + ipex_plug[1] / 2, pcb_top + ipex_plug[2]]);
    color("Black", 0.9) {
        // plug -> coil, then the coil (space for two layers)
        hull() for (x = [ipex_x + 2.0, coil_cx - coil_r]) translate([x, ipex_y, coil_z + cr]) sphere(d = coax_d, $fn = 12);
        translate([coil_cx, coil_cy, coil_z]) rotate_extrude($fn = 48)
            translate([coil_r - cr, 0]) square([coax_d, 2 * coax_d]);
        // coil -> over the plug -> down the keepout gap -> U-turn -> FPC
        for (i = [0 : len(coax_path) - 2]) hull() {
            translate(coax_path[i]) sphere(d = coax_d, $fn = 12);
            translate(coax_path[i + 1]) sphere(d = coax_d, $fn = 12);
        }
    }
}

// IM73D122 board as fitted in the lid pocket: board, mic + cap, the four wires leaving the -X end
module mic_board() {
    zf = z_lid_bot - mgk_c;  zb = zf - mpcb_t;
    color("DarkGreen", 0.9) difference() {
        box([mb_x0, mb_y0, zb], [mb_x1, mb_y1, zf]);
        translate([mic_x, mic_y, zb - 1]) cylinder(d = mpcb_hole, h = mpcb_t + 2, $fn = 16);
    }
    color("Black", 0.9) box([mic_x - mpcb_parts[0] / 2, mic_y - mpcb_parts[1] / 2, zb - mpcb_parts[2]],
                            [mic_x + mpcb_parts[0] / 2, mic_y + mpcb_parts[1] / 2, zb]);
    color("Crimson", 0.9) for (i = [0 : 3])
        translate([mb_x0 - 3, mic_y - mwire_w / 2 + mwire_d / 2 + i * (mwire_d + 0.2), zb - mwire_d / 2])
            rotate([0, 90, 0]) cylinder(d = mwire_d, h = 3 + mpcb_pads, $fn = 12);
}
// its gasket ring, compressed between the lid and the board (assembly view only)
module mic_gasket_fitted() C() translate([mic_x, mic_y, z_lid_bot - mgk_c]) difference() {
    cylinder(d = mgk_od, h = mgk_c, $fn = 32);
    translate([0, 0, -1]) cylinder(d = mgk_id, h = mgk_c + 2, $fn = 24);
}

module electronics() {
    C() {
        // battery (+ PCM end toward the bottom wall)
        color("RoyalBlue", 0.75) box([batt_x0, batt_y0, 0], [batt_x1, batt_y1, batt_t]);
        color("White", 0.8) box([batt_x0 + 2, batt_y0, batt_t - 0.01], [batt_x1 - 2, batt_y0 + 4, batt_t + 0.01]);
        // XIAO
        color("ForestGreen", 0.8) box([xiao_x0, xiao_y0, board_z0], [xiao_x1, xiao_y1, pcb_top]);
        if (!lm)   // chip-antenna zone, always at the LEFT end
            color("Gold", 0.8) box([xiao_x0, xiao_y0 + 2, pcb_top], [xiao_x0 + ant_len, xiao_y1 - 2, pcb_top + 0.8]);
        color("Silver", 0.9) box([ux0, usb_yc - bd_usb_w / 2, pcb_top], [ux0 + bd_usb_len, usb_yc + bd_usb_w / 2, usb_shell_z1]);
        color("Red", 0.9) translate([onb_x, onb_y, pcb_top + bd_mic_pkg[2] / 2])   // the XIAO's own mic
            cube(bd_mic_pkg, center = true);
        if (ext_mic) mic_board();
        // onboard RGB LED and the light pipe up to the front face (counts in interference)
        color("White", 0.9) translate([led_x, led_y, pcb_top + led_pkg[2] / 2]) cube(led_pkg, center = true);
        color("LightCyan", 0.7) translate([led_x, led_y, pipe_z0]) cylinder(d = led_pipe_d, h = pipe_z1 - pipe_z0, $fn = 24);
        if (lm) lm_antenna();
        // storage board
        color("MediumPurple", 0.8) box([sd_x0, sd_y0, board_z0], [sd_x1, sd_y1, board_z0 + stor_pcb_t]);
        if (nand) {   // parts envelope + the header wire joints along the +Y edge
            color("DimGray", 0.9) box([sd_x0 + 1, sd_y0 + 1, board_z0 + stor_pcb_t], [sd_x1 - 1, sd_y1 - 4, board_z0 + nand_h]);
            color("Silver", 0.9) box([sd_x0 + 1.5, sd_y1 - 3.6, board_z0 + stor_pcb_t], [sd_x1 - 1.5, sd_y1 - 1.4, sd_top]);
        } else        // microSD card, overhanging to the LEFT
            color("DimGray", 0.9) box([sd_x0 - sd_card_overhang, (sd_y0 + sd_y1 - sd_card_w) / 2, board_z0 + 1.6],
                                      [sd_x0 + 15 - sd_card_overhang, (sd_y0 + sd_y1 + sd_card_w) / 2, sd_top]);
        // slide switch, actuator out through the right wall
        color("DarkOrange", 0.85) box([sw_x0, sw_yc - sw_l / 2, sw_z0], [sw_x1, sw_yc + sw_l / 2, sw_z0 + sw_w]);
        color("Black", 0.9) box([sw_x1, sw_yc - sw_act[0] / 2, sw_z0 + (sw_w - sw_act[1]) / 2],
                                [sw_x1 + sw_act[2], sw_yc + sw_act[0] / 2, sw_z0 + (sw_w + sw_act[1]) / 2]);
        color("Silver", 0.8) box([sw_x0 - sw_leg_l, sw_yc - 2.8, sw_z0 + sw_w / 2 - 0.3],
                                 [sw_x0, sw_yc + 2.8, sw_z0 + sw_w / 2 + 0.3]);
    }
}

// =====================================================================
//  Body (back + walls)
// =====================================================================
module bail_solid(grow = 0) {
    e = bail_ext();
    bw = (bail_style == "flat" ? cord_w : cord_round_d) + 0.6 + 2 * bail_wall + 2;
    translate([0, OH / 2 - 2, z_rim - bail_thick - grow])
        linear_extrude(bail_thick + 2 * grow)
            hull() {
                translate([-bw / 2, 0]) square([bw, 0.1]);
                for (s = [-1, 1]) translate([s * (bw / 2 - 2.5), 2 + e - 2.5]) circle(r = 2.5 + grow);
            }
}
module bail_hole() {
    e = bail_ext();
    sy = OH / 2 + e - bail_wall;
    if (bail_style == "flat")
        translate([0, sy - (cord_t + 0.6) / 2, z_rim - bail_thick / 2])
            cube([cord_w + 0.6, cord_t + 0.6, bail_thick + 2], center = true);
    else
        translate([0, sy - (cord_round_d + 0.6) / 2, z_rim - bail_thick - 1])
            cylinder(d = cord_round_d + 0.6, h = bail_thick + 2);
}

module boss_positions() C() for (p = [[boss_inset, boss_inset], [cav_x - boss_inset, boss_inset]])
    translate([p[0], p[1], 0]) children();
module peg_positions() C() for (p = peg_list) translate([p[0], p[1], 0]) children();

module body_internal() {
    C() {
        // plastic-only rib under the very end of the XIAO (antenna end); the LM20A sits on the battery
        if (!lm) box([0, xiao_y0 + 2, 0], [xiao_x0 + 1.0, xiao_y1 - 2, board_z0]);
        // switch retaining ribs
        for (s = [-1, 1]) box([sw_x0, sw_yc + s * (sw_l / 2 + tol) + (s > 0 ? 0 : -1), sw_z0 - 0.5],
                              [cav_x + 0.01, sw_yc + s * (sw_l / 2 + tol) + (s > 0 ? 1 : 0), sw_z0 + sw_w]);
    }
    if (screws)   // they hang from the rim to just above the battery
        boss_positions() translate([0, 0, boss_z0]) cylinder(r = boss_r, h = z_lid_bot - boss_z0);
}

module body_cuts() {
    // cavity and lid rabbet
    linear_extrude(z_rim + 1) rrect(cav_x, cav_y, r_in);
    translate([0, 0, z_lid_bot]) linear_extrude(lid_t + 1) rrect(cav_x + 2 * rabbet, cav_y + 2 * rabbet, r_in + rabbet);
    if (lid_fastening == "snap")
        translate([0, 0, z_lid_bot + lid_t / 2 - 0.3]) linear_extrude(0.6)
            rrect(cav_x + 2 * rabbet + 0.6, cav_y + 2 * rabbet + 0.6, r_in + rabbet + 0.3);
    // bezel pry notch at the bottom seam
    translate([0, -OH / 2, z_rim - 0.6]) cube([8, 2 * wall, 1.2], center = true);
    C() {
        // switch: actuator window (with travel) and finger recess
        wy = sw_act[0] + sw_travel + 2 * tol;
        wz = sw_act[1] + 2 * tol;
        sz = sw_z0 + sw_w / 2;
        box([cav_x - 1, sw_yc - wy / 2, sz - wz / 2], [cav_x + wall + 1, sw_yc + wy / 2, sz + wz / 2]);
        box([cav_x + wall - sw_pocket, sw_yc - wy / 2 - 1.5, sz - wz / 2 - 1.2], [cav_x + wall + 1, sw_yc + wy / 2 + 1.5, sz + wz / 2 + 1.2]);
        // LM20A: flat locating pocket for the FPC antenna in the left wall
        if (lm) box([-fpc_pocket, fpc_y0 - tol, fpc_z0 - tol], [0.01, fpc_y1 + tol, fpc_z1 + tol]);
        // USB-C port: open slot for the cable overmould + the dust cap's flange recess
        yc = usb_yc;
        if (xiao_flip) {
            box([-wall - 1, yc - tun_w / 2, usb_cz - tun_h / 2], [usb_face_x + 0.01, yc + tun_w / 2, usb_cz + tun_h / 2]);
            box([-wall - 1, yc - tun_w / 2 - 1, usb_cz - tun_h / 2 - 1], [-wall + 0.6, yc + tun_w / 2 + 1, usb_cz + tun_h / 2 + 1]);
        } else {
            box([usb_face_x - 0.01, yc - tun_w / 2, usb_cz - tun_h / 2], [cav_x + wall + 1, yc + tun_w / 2, usb_cz + tun_h / 2]);
            box([cav_x + wall - 0.6, yc - tun_w / 2 - 1, usb_cz - tun_h / 2 - 1], [cav_x + wall + 1, yc + tun_w / 2 + 1, usb_cz + tun_h / 2 + 1]);
        }
    }
    if (screws)
        boss_positions() translate([0, 0, z_lid_bot - 6]) cylinder(d = screw_pilot, h = 7);
    bail_hole();
    if (skin_pad) pad_pocket();
}

module body() {
    difference() {
        union() {
            intersection() {
                pebble();
                translate([-200, -200, -50]) cube([400, 400, 50 + z_rim]);
            }
            bail_solid();
            intersection() {   // internal features, kept inside the cavity outline
                body_internal();
                linear_extrude(z_lid_bot) rrect(cav_x + 0.02, cav_y + 0.02, r_in);
            }
        }
        body_cuts();
    }
}

// =====================================================================
//  Lid (front plate, carries the mic acoustic port)
// =====================================================================
// IM73D122 board pocket under the lid: two long walls with a rail lip under each long edge of
// the board and a stop wall at the closed (+X) end; open at the wire end. The board slides in
// along X with its gasket ring, which is squeezed between the lid and the board.
module mic_pocket() C() {
    zl = z_lid_bot - mgk_c - mpcb_t - mpk_lip_t;     // bottom of the rails
    zb = z_lid_bot - mgk_c - mpcb_t;                 // the board's back face rests on the rails
    wx0 = mb_x0 + 0.5;
    difference() {
        box([wx0, mb_y0 - tol - mpk_wall, zl], [mb_x1 + tol + mpk_wall, mb_y1 + tol + mpk_wall, z_lid_bot + 0.01]);
        box([wx0 - 1, mb_y0 - tol, zb], [mb_x1 + tol, mb_y1 + tol, z_lid_bot + 1]);                // board + gasket
        box([wx0 - 1, mb_y0 + mpk_lip, zl - 1], [mb_x1 + tol, mb_y1 - mpk_lip, zb + 0.01]);         // between the rails
    }
}

module lid() {
    lw = cav_x + 2 * rabbet - 2 * tol;
    lh = cav_y + 2 * rabbet - 2 * tol;
    difference() {
        union() {
            translate([0, 0, z_lid_bot]) linear_extrude(lid_t) rrect(lw, lh, r_in + rabbet - tol);
            if (ext_mic) mic_pocket();
            // mic = "onboard": mic boss down to the gasket (ring) or the foam pad on the mic (pad)
            else C() translate([mic_x, mic_y, 0]) {
                translate([0, 0, wide_z]) cylinder(d = mic_boss_d, h = z_lid_bot - wide_z + 0.01);
                if (mic_seal == "pad")
                    translate([-mhold[0] / 2, -mhold[1] / 2, boss_bot]) cube([mhold[0], mhold[1], z_lid_bot - boss_bot + 0.01]);
            }
            // LED light-pipe guide sleeve
            C() translate([led_x, led_y, sleeve_z0]) cylinder(d = sleeve_d, h = z_lid_bot - sleeve_z0 + 0.01, $fn = 32);
            if (lid_fastening == "snap")
                for (p = [[0, lh / 2], [0, -lh / 2], [lw / 2, 0], [-lw / 2, 0]])
                    translate([p[0], p[1], z_lid_bot + lid_t / 2]) scale([p[0] == 0 ? 3 : 1, p[0] == 0 ? 1 : 3, 1])
                        sphere(d = 0.9, $fn = 16);
        }
        C() translate([mic_x, mic_y, 0]) {
            if (ext_mic)   // straight through the lid, onto the gasket ring
                translate([0, 0, z_lid_bot - 1]) cylinder(d = port_d, h = lid_t + 2, $fn = 24);
            else
                translate([0, 0, z_rim - port_len - 0.01]) cylinder(d = port_d, h = port_len + 1, $fn = 24);   // 1 mm port
            if (mic_seal == "ring") {
                translate([0, 0, boss_bot - 1]) cylinder(d = foam_dia, h = z_rim - port_len - boss_bot + 1);   // foam + air chamber
                translate([0, 0, boss_bot - 1]) difference() {                                                 // gasket groove
                    cylinder(d = gasket_od + 2 * tol, h = 1 + gasket_groove);
                    translate([0, 0, -1]) cylinder(d = gasket_id - 2 * tol, h = 3 + gasket_groove);
                }
            } else if (mic_seal == "pad") {
                translate([0, 0, chamber_z]) cylinder(d = foam_dia, h = z_rim - port_len - chamber_z);         // foam + air chamber
                translate([-bd_mic_pkg[0] / 2 - tol, -bd_mic_pkg[1] / 2 - tol, boss_bot - 1])                  // foam pad pocket
                    cube([bd_mic_pkg[0] + 2 * tol, bd_mic_pkg[1] + 2 * tol, 1 + mpad_pocket]);
                translate([0, 0, boss_bot]) cylinder(d = mpad_hole + 0.4, h = chamber_z - boss_bot + 0.01, $fn = 24);
            }
        }
        if (screws)
            boss_positions() {
                translate([0, 0, z_lid_bot - 1]) cylinder(d = screw_clear, h = lid_t + 2);
                translate([0, 0, z_rim - (screw_head - screw_clear) / 2 - 0.01])
                    cylinder(d1 = screw_clear, d2 = screw_head, h = (screw_head - screw_clear) / 2 + 0.02);
            }
        peg_positions() translate([0, 0, z_lid_bot - 1]) cylinder(d = peg_d + 2 * tol, h = lid_t + 2);
        C() translate([led_x, led_y, sleeve_z0 - 1]) cylinder(d = led_hole_d, h = z_rim - sleeve_z0 + 2, $fn = 24);
    }
}

// =====================================================================
//  Bezel (snap-on, swappable): the eagle plate (default) or the flush bezel
// =====================================================================
module bezel(emblem_depth = 0.5) {
    if (eagle) eagle_plate();
    else if ($children > 0) flush_bezel(emblem_depth) children();
    else flush_bezel(emblem_depth);
}

// Low-poly eagle, original design. Each facet = [engrave depth, points].
// Coordinates in mm for a 28 mm wingspan; right wing is mirrored for the left.
eagle_wing = [
    [0.45, [[2.6, 5.8], [6, 9], [10.5, 10.2], [9, 6]]],
    [0.25, [[9, 6], [10.5, 10.2], [14, 9.6]]],
    [0.60, [[9, 6], [14, 9.6], [13.2, 6.8]]],
    [0.35, [[9, 6], [13.2, 6.8], [11.8, 4.4]]],
    [0.55, [[2.6, 5.8], [9, 6], [11.8, 4.4], [9.6, 2.4]]],
    [0.30, [[2.6, 5.8], [9.6, 2.4], [7, 1.0]]],
    [0.50, [[2.6, 5.8], [7, 1.0], [4.4, 0.3], [2.6, 0.8]]]
];
eagle_body = [
    [0.30, [[-2, 6], [2, 6], [1.6, 8.6], [0, 9.6], [-1.6, 8.6]]],                         // head
    [0.65, [[-1, 6], [1, 6], [0, 4.2]]],                                                  // beak
    [0.50, [[-2, 6], [-1, 6], [0, 4.2], [1, 6], [2, 6], [2.4, 0.6], [0, -1.0], [-2.4, 0.6]]], // chest
    [0.40, [[-1.6, -1.6], [1.6, -1.6], [2.6, -5.6], [0, -4.6], [-2.6, -5.6]]]            // tail
];
eagle_span = 28;  eagle_cy = 2.3;   // centre offset of the drawing

// One facet at depth d. Override by calling bezel() with 2D children.
module eagle_facets(s) {
    for (f = eagle_body) children_facet(f, s, false);
    for (f = eagle_wing) { children_facet(f, s, false); children_facet(f, s, true); }
}
module children_facet(f, s, mir) {
    translate([0, 0, z_top - f[0]]) linear_extrude(f[0] + 1)
        offset(delta = -emblem_ridge / 2)
            scale([mir ? -s : s, s]) translate([0, -eagle_cy]) polygon(f[1]);
}

module bezel_peg() {
    // split peg with a barb that snaps under the lid
    h = lid_t + 0.8;
    difference() {
        union() {
            translate([0, 0, z_rim - h]) cylinder(d = peg_d, h = h + 0.01, $fn = 24);
            translate([0, 0, z_rim - h]) cylinder(d1 = peg_d + 2 * peg_barb, d2 = peg_d, h = 0.6, $fn = 24);
        }
        translate([-peg_slot / 2, -peg_d, z_rim - h - 0.1]) cube([peg_slot, 2 * peg_d, h * 0.7]);
    }
}

// bezel_style = "flush": the original bezel. 2D children replace the engraved eagle.
module flush_bezel(emblem_depth = 0.5) {
    s = (OW - 2 * emblem_margin) / eagle_span;
    difference() {
        union() {
            intersection() {
                pebble();
                translate([-200, -200, z_rim]) cube([400, 400, 50]);
            }
            peg_positions() bezel_peg();
        }
        if ($children > 0)
            translate([0, 0, z_top - emblem_depth]) linear_extrude(emblem_depth + 1) children();
        else
            eagle_facets(s);
        C() translate([mic_x, mic_y, z_rim - 1]) cylinder(d = bezel_port_d, h = bezel_th + 2, $fn = 24);
        C() translate([led_x, led_y, z_rim - 1]) cylinder(d = led_hole_d, h = bezel_th + 2, $fn = 24);   // LED window
        translate([0, -OH / 2, z_rim]) cube([8, 2 * wall, 1.2], center = true);   // pry notch
    }
}


// ---------------------------------------------------------------------
//  Eagle plate (bezel_style = "eagle"). Original design: a front-facing, low-poly
//  eagle with spread, fingered wings. It covers the pebble's front, overhangs it with
//  the wings and hides the bail behind the head. Prints back-down, relief up; the
//  three split pegs are separate pins (part="pegs") pressed into sockets in its back.
// ---------------------------------------------------------------------
module rpoly(pts, r) offset(r = r) offset(delta = -r) polygon(pts);

// convex plate piece: flat back on z_rim (chamfered by cb toward the chest), thickness t,
// front chamfer cf, hulled with raised facet points [x, y, height above z_rim]
module cplate(t, cb, cf, pts = []) hull() {
    translate([0, 0, z_rim]) linear_extrude(0.01) offset(delta = -cb) children();
    translate([0, 0, z_rim + cb]) linear_extrude(t - cb - cf) children();
    translate([0, 0, z_rim + t - 0.01]) linear_extrude(0.01) offset(delta = -cf) children();
    for (p = pts) translate([p[0], p[1], z_rim + p[2] - 0.01]) cube(0.02, center = true);
}

module wing_arm_2d(s) offset(r = tip_r) offset(delta = -tip_r) hull() polygon(wing_arm_pts(s));
module torso_2d() intersection() { outline(); polygon(torso_pts); }
module tail_2d()  intersection() { outline(); polygon(tail_pts); }
module feather_2d(f, s) hull() {
    translate(wpt(f[0], s)) circle(r = f[1], $fn = 32);
    translate(wpt(f[2], s)) circle(r = tip_r, $fn = 32);
}
module head_2d() rpoly(head_pts, tip_r);

module eagle_wing(s) {
    cplate(wing_t, wing_back_ch, plate_ch) wing_arm_2d(s);
    L = wing_lead(s);  R = [2.4, 2.2, 1.9, 1.5];   // tapers toward the wrist
    for (i = [0 : len(L) - 2])   // ridge sits toward the leading edge, so the band slopes back
        cplate(wing_t, wing_back_ch, plate_ch, [concat(L[i] + [0, 0.7], [wing_t + rib_h]),
                                                concat(L[i + 1] + [0, 0.6], [wing_t + rib_h * (i == len(L) - 2 ? 0.8 : 1)])])
            hull() for (j = [i, i + 1]) translate(L[j]) circle(r = R[j], $fn = 6);
    for (f = concat(wing_feathers, wing_coverts)) {
        b = wpt(f[0], s);  t = wpt(f[2], s);  d = (t - b) / norm(t - b);
        cplate(wing_t, wing_back_ch, plate_ch, [concat(b, [wing_t + f[3]]), concat(t - 0.8 * tip_r * d, [wing_t + f[4]])])
            feather_2d(f, s);
    }
}

module eagle_head() {
    plateau = [[-ctun_w / 2 - 1, ctun_y0 - 0.6], [ctun_w / 2 + 1, ctun_y0 - 0.6],
               [ctun_w / 2 + 1, yT + head_top - 1.4], [-ctun_w / 2 - 1, yT + head_top - 1.4]];
    hull() {   // faceted dome: low at the chin, head_t over the cord tunnel
        cplate(wing_t, wing_back_ch, plate_ch) head_2d();
        cplate(head_up, wing_back_ch, plate_ch) intersection() {
            head_2d();
            translate([-50, ctun_y0 - 1]) square([100, 50]);
        }
        translate([0, 0, z_rim + head_t - 0.01]) linear_extrude(0.01) polygon(plateau);
    }
    ht = head_t;
    beak = [[0, yT + 3.4, ht + 1.0], [2.4, yT + 0.6, ht + 0.3], [-2.4, yT + 0.6, ht + 0.3],
            [1.7, yT - 3.6, ht - 0.6], [-1.7, yT - 3.6, ht - 0.6], [0, yT - head_chin - 0.6, wing_t + 1.2]];
    hull() for (p = beak, z = [p[2], wing_t]) translate([p[0], p[1], z_rim + z - 0.01]) cube(0.02, center = true);
    for (s = [-1, 1])   // brows: a V over the eyes
        hull() for (p = [[1.5, yT + 4.3, ht + 0.8], [6.0, yT + 5.3, ht + 0.6], [5.2, yT + 6.9, ht],
                         [2.0, yT + 6.0, ht], [3.6, yT + 3.9, ht]], z = [p[2], ht - 1])
            translate([s * p[0], p[1], z_rim + z - 0.01]) cube(0.02, center = true);
}

// breast feathers: staggered rows of small downward-pointing facets, and a fanned tail
module breast_feather(c, w, h, ht) hull() {
    translate([c[0], c[1], z_rim + wing_t - 0.3]) linear_extrude(0.3)
        polygon([[-w / 2, 0.5], [w / 2, 0.5], [0, -h]]);
    translate([c[0], c[1] - 0.6, z_rim + wing_t + ht - 0.01]) cube(0.02, center = true);
}
// rows from under the beak to the waist, inside the torso outline
breast_n = round(breast_rows * OH / 49.7);   // more rows on the taller 1100 mAh pebble
breast = [for (r = [0 : breast_n - 1]) let(y = yT - head_chin - 1.6 - 3.3 * r) if (y > waist_y + 3)
    for (i = [-4 : 4]) let(x = (i + (r % 2) / 2) * 4.8,
                           lim = y > yT - wing_drop ? hw - 1.5 : waist_w / 2 + (y - waist_y) * (hw - waist_w / 2) / (yT - wing_drop - waist_y) - 2.4)
        if (abs(x) + 2.2 <= min(lim, breast_w / 2 * sqrt(max(0, 1 - pow((r - 1) / (breast_n - 0.5), 2)))))
        if (norm([x - port_cx, y - 1 - port_cy]) > port_keep + 0.6 && norm([x - led_cx, y - 1 - led_cy]) > led_keep + 0.6)
            [x, y, max(relief_min, 0.85 - 0.1 * r - 0.08 * abs(i))]];
module eagle_breast() for (f = breast) breast_feather([f[0], f[1]], 4.4, 3.6, f[2]);

tail_root = [0, waist_y + 4];
module eagle_tail() for (a = [-34, -17, 0, 17, 34]) {
    d  = [sin(a), -cos(a)];  n = [cos(a), sin(a)];
    L  = (tail_root[1] + OH / 2 - 2.8) / cos(a) - (a == 0 ? 0 : 2.5);
    hull() {
        translate([0, 0, z_rim + wing_t - 0.3]) linear_extrude(0.3)
            polygon([tail_root + 2.5 * d, tail_root + 0.6 * L * d + 2.6 * n, tail_root + L * d + 1.0 * n,
                     tail_root + L * d - 1.0 * n, tail_root + 0.6 * L * d - 2.6 * n]);
        for (p = [[0.25, 1.0], [0.9, 0.5]]) translate(concat(tail_root + p[0] * L * d, [z_rim + wing_t + p[1] - 0.01]))
            cube(0.02, center = true);
    }
}

module eagle_pin() union() {   // stock split peg + a shank for the socket in the plate
    bezel_peg();
    translate([0, 0, z_rim - 0.01]) cylinder(d = peg_d, h = pin_sock - 0.1 + 0.01, $fn = 24);
}
module eagle_pins() peg_positions() eagle_pin();

// detail = false: just the plate over the pebble with its holes (for the interference check)
module eagle_plate(detail = true) {
    difference() {
        union() {
            cplate(wing_t, 0, plate_ch) torso_2d();
            cplate(wing_t, 0, plate_ch) tail_2d();
            if (detail) difference() {
                union() {
                    for (s = [-1, 1]) eagle_wing(s);
                    eagle_head();
                    eagle_breast();
                    eagle_tail();
                }
                // relief keep-outs: flat plate face around the mic port and the LED window
                for (k = [[port_cx, port_cy, port_keep], [led_cx, led_cy, led_keep]])
                    translate([k[0], k[1], z_rim + wing_t - 0.005]) rotate(22.5)
                        cylinder(r = k[2] / cos(22.5), h = 20, $fn = 8);
            }
        }
        C() translate([mic_x, mic_y, z_rim - 1]) cylinder(d = bezel_port_d, h = wing_t + 2, $fn = 24);
        C() translate([led_x, led_y, z_rim - 1]) cylinder(d = led_hole_d, h = wing_t + 2, $fn = 24);   // LED window
        translate([0, -OH / 2, z_rim]) cube([8, 2 * wall, 1.2], center = true);   // pry notch
        translate([-ctun_w / 2, ctun_y0, z_rim - 1]) cube([ctun_w, 50, ctun_h + 1]);   // cord tunnel
        for (s = [-1, 1])   // eyes
            translate([0, 0, z_rim + head_t - eye_d]) linear_extrude(5)
                polygon([[s * 2.3, eye_y + 0.8], [s * 5.4, eye_y + 1.0], [s * 4.4, eye_y - 0.5]]);
        peg_positions() {   // sockets for the peg pins
            translate([0, 0, z_rim - 0.01]) cylinder(d = peg_d, h = pin_sock, $fn = 24);
            translate([0, 0, z_rim - 0.01]) cylinder(d1 = peg_d + 0.6, d2 = peg_d, h = 0.3, $fn = 24);
        }
    }
}

// convex envelope pieces of the plate, for the stand's seat and slide path
module plate_env_piece(i, grow = 0) {
    nw = 1 + len(wing_feathers);
    zt = i == 1 ? plate_T : wing_t + relief_max;
    translate([0, 0, z_rim - grow]) linear_extrude(zt + 2 * grow) offset(r = grow)
        if (i == 0) outline();
        else if (i == 1) head_2d();
        else {
            s = (i - 2) < nw ? 1 : -1;  k = (i - 2) % nw;
            if (k == 0) wing_arm_2d(s); else feather_2d(wing_feathers[k - 1], s);
        }
}

// =====================================================================
//  Small parts
// =====================================================================
module usb_plug() {   // optional dust cap for the USB-C port slot (prints flange-down)
    fit = 0.1;
    union() {
        cube([tun_w + 2 - 2 * tol, tun_h + 2 - 2 * tol, 0.6]);
        translate([1 - tol + fit, 1 - tol + fit, 0]) cube([tun_w - 2 * fit, tun_h - 2 * fit, 0.6 + wall - 0.6 + 1.0]);
        translate([-1.5, (tun_h + 2 - 2 * tol) / 2 - 1, 0]) cube([2, 2, 0.6]);   // pull tab
    }
}
module gasket() {
    if (mic_seal == "board")   // IM73D122: template; punch it from mgk_t closed-cell silicone sponge / PORON
        difference() {
            cylinder(d = mgk_od, h = mgk_t, $fn = 48);
            translate([0, 0, -1]) cylinder(d = mgk_id, h = mgk_t + 2, $fn = 32);
        }
    else if (mic_seal == "ring")   // ring: print in TPU 95A, or punch from 1.5 mm closed-cell foam
        difference() {
            cylinder(d = gasket_od, h = gasket_t);
            translate([0, 0, -1]) cylinder(d = gasket_id, h = gasket_t + 2);
        }
    else              // pad (LM20A): a template; punch it from mpad_t closed-cell foam
        difference() {
            translate([-bd_mic_pkg[0] / 2, -bd_mic_pkg[1] / 2, 0]) cube([bd_mic_pkg[0], bd_mic_pkg[1], mpad_t]);
            translate([0, 0, -1]) cylinder(d = mpad_hole, h = mpad_t + 2, $fn = 24);
        }
}

// =====================================================================
//  Skin pad (optional): a thin TPU pad in a shallow pocket on the domed back
// =====================================================================
// everything inside the pad outline and below the back surface raised by dz
module below_back(inset, dz) intersection() {
    translate([0, 0, -50]) linear_extrude(50 - 0.01) outline(inset);
    difference() {
        translate([-200, -200, -50]) cube([400, 400, 50 - 0.01]);
        translate([0, 0, dz]) pebble();
    }
}
module pad_pocket() below_back(pad_margin, pad_recess);

// the pad as fitted (domed, for the assembly and the stand envelope check)
module skin_pad_fitted() difference() {
    below_back(pad_margin + tol, pad_recess);
    below_back(pad_margin + tol - 1, -pad_proud);
}

// the pad as printed: flat, skin side up. It is thin enough to bend the
// pad_sag mm into the domed pocket. Fix it with thin double-sided tape.
module skin_pad() hull() {
    linear_extrude(0.01) outline(pad_margin + tol);
    translate([0, 0, pad_t - 0.01]) linear_extrude(0.01) outline(pad_margin + tol + pad_chamfer);
}

// =====================================================================
//  Fit check and interference
// =====================================================================
module fit_check() {
    electronics();
    // half-section of the shell so the ghosts are visible
    %difference() { body(); translate([-200, 0, -50]) cube([400, 400, 100]); }
    %difference() { lid();  translate([-200, 0, -50]) cube([400, 400, 100]); }
    color("SkyBlue", 0.25) translate([0, 0, 0]) difference() { bezel(); translate([-200, 0, -50]) cube([400, 400, 100]); }
}
module interference() {   // must render EMPTY
    intersection() {
        electronics();
        // eagle: the plate without its relief (the relief is all above the plate face, clear of the LED pipe)
        union() { body(); lid(); if (eagle) { eagle_plate(false); eagle_pins(); } else bezel(); }
    }
}

module print_plate() {
    translate([0, 0, z_rim]) rotate([180, 0, 0]) body();                       // rim on the bed
    translate([OW + 8, 0, -z_lid_bot]) lid();                                   // outer face down
    if (eagle) {                                                                // back down, relief up
        translate([2 * OW + 16 + plate_W / 2 - OW / 2, 0, -z_rim]) eagle_plate();
        for (i = [0 : 2]) translate([OW + 8 + 6 * i, OH / 2 + 14, z_rim + pin_sock - 0.1])
            rotate([180, 0, 0]) eagle_pin();               // pins shank down
    } else
        translate([2 * OW + 16, 0, z_top]) rotate([180, 0, 0]) bezel();        // face down
    translate([0, -OH / 2 - 15, 0]) usb_plug();
    translate([25, -OH / 2 - 12, 0]) gasket();
    if (skin_pad) translate([3 * OW + 24, 0, 0]) skin_pad();   // TPU: print it on its own
}

module assembly() {
    color("Tan") body();
    color("Wheat") lid();
    color("SaddleBrown") bezel();
    if (eagle) color("Sienna") eagle_pins();
    if (skin_pad) color("DarkSlateGray") skin_pad_fitted();
    if (ext_mic) color("DimGray") mic_gasket_fitted();
    electronics();
}

if (part == "assembly")     assembly();
if (part == "fit_check")    fit_check();
if (part == "body")         body();
if (part == "lid")          lid();
if (part == "bezel")        bezel();
if (part == "pegs")         for (i = [0 : 2]) translate([6 * i, 0, z_rim + pin_sock - 0.1]) rotate([180, 0, 0]) eagle_pin();
if (part == "usb_plug")     usb_plug();
if (part == "gasket")       gasket();
if (part == "print_plate")  print_plate();
if (part == "interference") interference();
if (part == "skin_pad")     skin_pad();
