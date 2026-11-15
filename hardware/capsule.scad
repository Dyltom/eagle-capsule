// =====================================================================
//  Eagle Capsule - wearable enclosure (OpenSCAD, fully parametric)
//  License: MIT (see repository LICENSE)
//
//  Part dimensions come from the makers' published data:
//    Seeed Studio      - XIAO nRF52840 Sense (21 x 17.8 mm); XIAO nRF54LM20A Sense
//                        (KiCad + STEP files) and its 2.4 GHz FPC antenna A-04
//    Pololu            - #2597 microSD breakout (20.3 x 17.8 mm)
//    Adafruit          - #4899 XTSD 512 MB SD NAND (EagleCAD file), #5358 DIY magnetic
//                        connector, #805 SPDT slide switch
//    Core Electronics  - CE04375 400 mAh and CE04377 1100 mAh LiPo
//    Little Bird       - LB-00237 600 mAh LiPo
//  Anything marked (?) below is NOT verified. Measure it with calipers
//  when the parts arrive and change the parameter (see hardware/README.md).
//
//  Variants: battery, storage, board, preset, skin_pad (see [Variants]).
//  hardware/variants.txt lists every combination that must render cleanly.
//
//  Coordinate system (capsule frame):
//    X = across the front face (left/right as you look at the bezel)
//    Y = up the front face (+Y = lanyard end, -Y = magnetic connector edge)
//    Z = thickness, out of the front face (z = 0 is the inner floor,
//        the skin-side dome is below z = 0, the bezel is on top)
//
//  Render one part:   openscad -D 'part="body"' -o body.stl capsule.scad
//  Parts: assembly | fit_check | body | lid | bezel | usb_plug | gasket |
//         skin_pad | print_plate | interference | none
// =====================================================================

/* [What to render] */
part = "assembly";

/* [Global] */
tol      = 0.2;    // printer clearance, per side, for parts that fit together
clr      = 1.2;    // air gap between electronics and the inner wall
$fn      = 40;

/* [Variants] */
// Every combination listed in hardware/variants.txt renders and passes the asserts.
// "400" = CE04375 400 mAh (~38 x 25 x 6 ?) | "600" = see [Battery] | "1100" = 51 x 34 x 6, 21 g
battery  = "400";
// "pololu_sd" = Pololu #2597 microSD breakout | "sd_nand" = Adafruit #4899 XTSD 512 MB
storage  = "pololu_sd";
// "nrf52840" = XIAO nRF52840 Sense (chip antenna on the board)
// "nrf54lm20a" = XIAO nRF54LM20A Sense (external FPC antenna on an IPEX4 lead)
board    = "nrf52840";
// "default" | "slim" (no USB-C tunnel, thin bezel, flatter back: 15.4 mm with the defaults).
// The preset only fills in the three parameters marked PRESET below.
preset   = "default";
// Optional TPU skin pad on the domed back (part="skin_pad"). false = body unchanged.
skin_pad = false;
// Which end of the XIAO the chip antenna is at (NOT confirmed yet):
// "far_end" = opposite the USB-C (expected), "usb_end" = same end as USB-C.
// The antenna end always goes to the plastic-only LEFT wall, overhanging the
// battery; this flips the XIAO (and the USB-C service tunnel) to match.
antenna_at = "far_end";
// Lid fastening: "screws" = 2x M1.6 x 8 self-tapping into bosses
//                "snap"   = 4 bumps on the lid into a groove in the rim
lid_fastening = "screws";

// PRESET parameters. Leave them undef and the preset decides; give one a value
// (in the file or with -D, e.g. -D 'bezel_t=1.2') and that value wins over the preset.
//                    default  slim
usb_service_port = undef;   // true     false  USB-C recovery tunnel (+ plug cap) in the side wall
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
conn_floor  = 3.0;   // height of the connector above the inner floor

/* [XIAO nRF52840 Sense - Seeed Studio, board = "nrf52840"] */
xiao_l        = 21.0;
xiao_w        = 17.8;
xiao_pcb_t    = 1.0;   // (?) PCB thickness
xiao_h        = 4.2;   // (?) total height incl. USB-C ("about 4 mm")
usb_w         = 9.0;   // (?) USB-C receptacle width
usb_h         = 3.2;   // (?) USB-C receptacle height
usb_overhang  = 1.0;   // (?) receptacle sticks out past the PCB edge
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
// fpc_keepout of air to the battery, the boards and the magnets.
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

/* [USB-C service cable] */
// USB-C cable plug that must fit the service tunnel (slim overmould)
usb_plug_w    = 12.0;  // (?) overmould width
usb_plug_h    = 6.0;   // (?) overmould thickness

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
conn_gap   = 1.5;   // space between connector back and battery (PCM wires)

/* [Adafruit #5358 magnetic connector - MEASURE ON ARRIVAL] */
conn_l = 21.0;  // (?) along the bottom edge
conn_d = 7.0;   // (?) depth into the case (mating face -> back)
conn_h = 7.0;   // (?) height
// keying slot in the capsule bottom (dock has the matching rib)
key_w = 3.0; key_h = 2.0; key_d = 3.0; key_dx = 6.0;

/* [Adafruit #805 slide switch] */
sw_l        = 8.6;   // (?) body length (slide direction, along Y)
sw_w        = 3.6;   // (?) body width (Z in the case)
sw_d        = 3.5;   // (?) body depth (X, into the case)
sw_act      = [1.6, 1.6, 2.0]; // (?) actuator: slide-dir x width x protrusion
sw_travel   = 1.5;   // (?) actuator travel
sw_leg_l    = 3.0;   // trim the legs to this length
sw_flush    = 0.3;   // actuator tip sits this far below the outer surface
sw_pocket   = 1.2;   // finger recess depth around the actuator

/* [Mic port] */
port_d      = 1.0;   // through-hole in the lid (front face)
port_len    = 0.8;   // length of that hole before the foam chamber
foam_dia    = 5.0;   // foam disc diameter
foam_t      = 2.0;   // foam disc thickness (the recess is at least this deep)
gasket_id   = 5.0;   // (?) needs a clear ring of PCB around the mic
gasket_od   = 7.0;
gasket_t    = 1.3;
gasket_groove = 0.6;
gasket_squeeze = 0.3;
bezel_port_d = 2.0;  // bigger hole in the bezel so it never shades the port

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
assert(one_of(preset, ["default", "slim"]), str("preset must be \"default\" or \"slim\", got ", preset));

// PRESET resolution: an explicit value (file or -D) wins, undef takes the preset's value
function preset_pick(v, dflt, slim) = !is_undef(v) ? v : (preset == "slim" ? slim : dflt);
usb_port   = preset_pick(usb_service_port, true, false);
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
mic_seal   = lm ? "pad" : "ring";   // see [Mic port] and the LM20A block

// Antenna rule.
//   nrf52840:   the chip-antenna end of the XIAO overhangs the battery by ant_overhang,
//               over the plastic-only LEFT wall (assert: overhang >= ant_len).
//   nrf54lm20a: no antenna on the board. The FPC is on the LEFT wall and the battery, both
//               boards (and the microSD card) start fpc_keepout away from its face.
xiao_flip  = !lm && (antenna_at == "usb_end");   // the LM20A's USB-C always faces right
fpc_x1     = fpc_t - fpc_pocket;                  // FPC inner face (cavity frame x)
keep_x0    = lm ? fpc_x1 + fpc_keepout : clr;     // nothing metal left of this (LM20A)
batt_x0    = lm ? keep_x0 : clr + ant_overhang;
batt_y0    = conn_d - wall + conn_gap;
batt_x1    = batt_x0 + batt_dims[0];
batt_y1    = batt_y0 + batt_dims[1];
batt_t     = batt_dims[2];

xiao_x0    = lm ? keep_x0 : clr + (xiao_flip ? bd_usb_over : 0);
xiao_x1    = xiao_x0 + bd_l;
usb_face_x = xiao_flip ? xiao_x0 - bd_usb_over : xiao_x1 + bd_usb_over;

// storage board: the same slot for both, the switch stays centred on it
nand       = (storage == "sd_nand");
stor_l     = nand ? nand_l : sd_l;
stor_w     = nand ? nand_w : sd_w;
stor_h     = nand ? nand_h + nand_wire_h : sd_h;
stor_pcb_t = nand ? nand_pcb_t : 1.6;
stor_over  = nand ? 0 : sd_card_overhang;   // the microSD card sticks out LEFT; SD NAND doesn't
sd_x0      = keep_x0 + stor_over;
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
tun_w      = usb_plug_w + 2 * tol;
tun_h      = usb_plug_h + 2 * tol;

sw_inset   = (wall - sw_flush) - sw_act[2] + 0;   // body face sits this far outside the inner wall
cav_x      = max(batt_x1 + clr,
                 sd_x1 + 0.5 + sw_leg_l + sw_d - sw_inset,
                 max(xiao_x1, usb_face_x) + 2);
cav_y      = max(batt_y1, xiao_y1) + clr;
cav_top    = max(xiao_top + headroom,
                 sd_top + headroom,
                 conn_floor + conn_h + tol + headroom,
                 usb_port ? usb_cz + tun_h / 2 + 0.4 : 0);

z_lid_bot  = cav_top;
z_rim      = cav_top + lid_t;
z_top      = z_rim + bezel_th;

OW    = cav_x + 2 * wall;
OH    = cav_y + 2 * wall;
r_in  = R_out - wall;

conn_cx  = cav_x / 2;               // connector centred on the bottom edge
conn_z0  = conn_floor;
conn_cz  = conn_z0 + conn_h / 2;
sw_yc    = (sd_y0 + sd_y1) / 2;
sw_z0    = batt_t + 0.6;
sw_x1    = cav_x + sw_inset;         // actuator-side face of the switch body
sw_x0    = sw_x1 - sw_d;

// board coordinates -> cavity frame (u from the USB-C end, e from the bottom-facing edge)
function bpt_x(u) = xiao_flip ? xiao_x0 + u : xiao_x1 - u;
function bpt_y(e) = xiao_flip ? xiao_y1 - e : xiao_y0 + e;
mic_x    = bpt_x(bd_mic_u);
mic_y    = bpt_y(bd_mic_e);
mic_top  = pcb_top + bd_mic_pkg[2];
usb_inner = bd_usb_len - bd_usb_over;   // receptacle length over the PCB
// lid mic boss. "ring": a cylinder down to the TPU ring on the PCB around the mic.
// "pad": a narrow holder down onto a foam pad on the mic's lid, widening into the foam
// chamber only above the IPEX4 plug.
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
// nearest metal to the FPC face: the battery / boards (keep_x0) and the magnetic connector
fpc_conn_dist = norm([conn_cx - conn_l / 2 - fpc_x1, max(0, fpc_y0 - (conn_d - wall))]);

// recording LED light pipe (cavity frame)
led_u      = lm ? lm_led_from_usb : led_from_usb;
led_e      = lm ? lm_led_from_edge : led_from_edge;
led_x      = bpt_x(led_u);
led_y      = bpt_y(led_e);
led_top    = pcb_top + led_pkg[2];
led_hole_d = led_pipe_d + 2 * tol;
pipe_z0    = led_top + led_gap;
pipe_z1    = z_top - led_recess;
usb_shell_z1 = pcb_top + bd_usb_h;
// the guide sleeve hangs under the lid, but only above the USB-C shell (it sits beside it)
sleeve_z0  = max(pipe_z0, usb_shell_z1 + 0.3);
sleeve_d   = led_hole_d + 2 * led_sleeve_w;
// clearances the asserts check
led_mic_web   = norm([led_x - mic_x, led_y - mic_y]) - (led_hole_d + max(bezel_port_d, port_d)) / 2;
led_boss_gap  = norm([led_x - mic_x, led_y - mic_y]) - sleeve_d / 2
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

// skin pad: dome height at the pocket edge, and how far the flat-printed pad must bend
function dome_z(inset) = inset >= back_inset ? -dome_d : -dome_d * sin(acos(1 - inset / back_inset));
pad_proud  = pad_t - pad_recess;
pad_floor_left = -dome_z(pad_margin) - pad_recess;   // thinnest shell under the pocket
pad_sag    = dome_z(pad_margin) + dome_d;            // rim-to-centre rise the flat pad bends through

// capsule frame offset (cavity centred on the origin)
CX = -cav_x / 2;  CY = -cav_y / 2;

// ---------------- info functions (used by dock.scad) ----------------
function cap_OW()        = OW;
function cap_OH()        = OH;
function cap_zmin()      = -dome_d - (skin_pad ? pad_proud : 0);   // incl. the skin pad
function cap_ztop()      = z_top;
function cap_zrim()      = z_rim;
function cap_conn_face() = [conn_cx + CX, -OH / 2, conn_cz];   // mating-face centre
function cap_mic()       = [mic_x + CX, mic_y + CY, z_top];
function cap_switch_y()  = [sw_yc - sw_l / 2 + CY, sw_yc + sw_l / 2 + CY];
function cap_key()       = [conn_cx + key_dx + CX, 0.3 + key_h / 2];   // x, z of key slot centre
function cap_bail_top()  = OH / 2 + bail_ext();
function bail_ext()      = (bail_style == "flat" ? cord_t : cord_round_d) + 0.6 + 2 * bail_wall;

// ---------------- report ----------------
echo(str("CAPSULE battery=", battery, " storage=", storage, " board=", board, " preset=", preset,
         lm ? "" : str(" antenna_at=", antenna_at)));
echo(str("CAPSULE outer W x H x T = ", OW, " x ", OH, " x ", z_top + dome_d,
         " mm  (+", bail_ext(), " mm bail)"));
echo(str("CAPSULE cavity = ", cav_x, " x ", cav_y, " x ", cav_top));
if (lm) {
    echo(str("FIT FPC antenna to battery / boards = ", keep_x0 - fpc_x1, " mm, to the magnets = ",
             fpc_conn_dist, " mm (keepout ", fpc_keepout, ")"));
    echo(str("FIT FPC on the wall: y ", fpc_y0, "..", fpc_y1, " of the straight ", r_in, "..", cav_y - r_in,
             ", top ", fpc_z1, " under the lid at ", z_lid_bot));
    echo(str("FIT coax: ", coax_fixed, " mm routed, ", coax_spare, " mm spare = ", coil_turns,
             " turns in the coil (2 fit)"));
} else
    echo(str("FIT antenna overhang past battery = ", batt_x0 - xiao_x0, " mm (antenna zone ", ant_len, ")"));
echo(str("FIT usb tunnel floor above battery = ",
         (usb_cz - tun_h / 2) - batt_t, " mm  (only matters where the tunnel is over the battery: ",
         xiao_flip ? "no" : "yes", ")"));
echo(str("FIT mic chamber above mic = ", (z_rim - port_len) - chamber_z,
         " mm (foam ", foam_t, " mm, seal: ", mic_seal, ")"));
echo(str("FIT ", mic_seal == "ring" ? "gasket ring" : "mic pad holder", " to USB-C shell = ", usb_gasket_gap, " mm"));
echo(str("FIT switch leg tips to SD board = ", (sw_x0 - sw_leg_l) - sd_x1, " mm"));
echo(str("FIT LED window: ", led_mic_web, " mm of plastic to the mic port, sleeve to mic boss ", led_boss_gap,
         " mm, pipe to USB-C shell ", led_usb_gap, " mm"));

// antenna rules, one per board
if (lm) {
    assert(keep_x0 - fpc_x1 >= fpc_keepout, "FPC antenna is closer than fpc_keepout to the battery or a board");
    assert(min(batt_x0, xiao_x0, sd_x0 - stor_over) >= keep_x0, "battery, XIAO or storage inside the FPC keepout");
    assert(fpc_conn_dist >= fpc_keepout, "FPC antenna is closer than fpc_keepout to the magnetic connector");
    assert(fpc_y0 >= r_in + 0.3 && fpc_y1 <= cav_y - r_in - 0.3,
           "FPC antenna is longer than the straight part of the left wall (cavity too short)");
    assert(fpc_z1 <= z_lid_bot - 0.3, "FPC antenna is taller than the cavity");
    assert(riser_x + cr <= keep_x0 - 0.2, "coax U-turn (coax_bend_r) doesn't fit in the FPC keepout gap");
    assert(coax_spare >= 0, "coax is too short to reach the FPC on this layout");
    assert(coil_turns <= 2, "too much spare coax for the coil ring: raise coil_r or shorten the lead");
    assert(z_over + cr <= z_lid_bot - 0.2, "no room for the coax over the IPEX4 plug under the lid");
} else
    assert(batt_x0 - xiao_x0 >= ant_len, "antenna zone is over the battery");
assert(usb_cz - tun_h / 2 > batt_t || xiao_flip, "USB tunnel hits the battery");
assert((z_rim - port_len) - chamber_z >= foam_t, "no room for the foam disc");
assert(usb_gasket_gap >= 0, "mic boss / gasket sits on the USB-C receptacle: re-measure mic_from_usb");
assert(sw_x0 - sw_leg_l > sd_x1, "switch legs hit the SD board");
// recording LED window (required)
assert(led_on_board, "LED light pipe is not over the XIAO (it must sit on the LED, clear of the battery and boards)");
assert(led_mic_web >= led_web, str("LED window is only ", led_mic_web, " mm from the mic port (needs led_web)"));
assert(led_boss_gap >= 0.4, "LED guide sleeve runs into the lid's mic boss");
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

// =====================================================================
//  Basic shapes
// =====================================================================
module rrect(w, h, r) {
    rr = max(r, 0.01);
    offset(r = rr) square([max(w - 2 * rr, 0.01), max(h - 2 * rr, 0.01)], center = true);
}
module outline(inset = 0) offset(delta = -inset) rrect(OW, OH, R_out);
module slab(inset, z) translate([0, 0, z]) linear_extrude(0.01) outline(inset);

// Outer pebble. grow > 0 inflates it (used for the dock cradle clearance).
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
module capsule_envelope(grow = 0) {   // pebble + bail (+ skin pad), for the dock
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

module electronics() {
    C() {
        // battery (+ PCM end toward the connector)
        color("RoyalBlue", 0.75) box([batt_x0, batt_y0, 0], [batt_x1, batt_y1, batt_t]);
        color("White", 0.8) box([batt_x0 + 2, batt_y0, batt_t - 0.01], [batt_x1 - 2, batt_y0 + 4, batt_t + 0.01]);
        // XIAO
        color("ForestGreen", 0.8) box([xiao_x0, xiao_y0, board_z0], [xiao_x1, xiao_y1, pcb_top]);
        if (!lm)   // chip-antenna zone, always at the LEFT end
            color("Gold", 0.8) box([xiao_x0, xiao_y0 + 2, pcb_top], [xiao_x0 + ant_len, xiao_y1 - 2, pcb_top + 0.8]);
        ux = xiao_flip ? xiao_x0 - bd_usb_over : xiao_x1 - bd_usb_len + bd_usb_over;
        color("Silver", 0.9) box([ux, (xiao_y0 + xiao_y1 - bd_usb_w) / 2, pcb_top],
                                 [ux + bd_usb_len, (xiao_y0 + xiao_y1 + bd_usb_w) / 2, pcb_top + bd_usb_h]);
        color("Red", 0.9) translate([mic_x, mic_y, pcb_top + bd_mic_pkg[2] / 2])
            cube(bd_mic_pkg, center = true);
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
        // magnetic connector (mating face flush with the outer bottom)
        color("Goldenrod", 0.85) box([conn_cx - conn_l / 2, -wall, conn_z0],
                                     [conn_cx + conn_l / 2, -wall + conn_d, conn_z0 + conn_h]);
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
        // connector pedestal + back stop
        box([conn_cx - conn_l / 2 - 1, 0, 0], [conn_cx + conn_l / 2 + 1, -wall + conn_d + tol, conn_z0 - tol]);
        for (s = [-1, 1]) translate([conn_cx + s * (conn_l / 2 - 3) - 1, -wall + conn_d + tol, 0])
            cube([2, 1.2, conn_z0 + conn_h / 2]);
        // plastic-only rib under the very end of the XIAO (antenna end); the LM20A sits on the battery
        if (!lm) box([0, xiao_y0 + 2, 0], [xiao_x0 + 1.0, xiao_y1 - 2, board_z0]);
        // switch retaining ribs
        for (s = [-1, 1]) box([sw_x0, sw_yc + s * (sw_l / 2 + tol) + (s > 0 ? 0 : -1), sw_z0 - 0.5],
                              [cav_x + 0.01, sw_yc + s * (sw_l / 2 + tol) + (s > 0 ? 1 : 0), sw_z0 + sw_w]);
    }
    if (lid_fastening == "screws")
        boss_positions() cylinder(r = boss_r, h = z_lid_bot);
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
        // connector window + keying slot
        box([conn_cx - conn_l / 2 - tol, -wall - 1, conn_z0 - tol], [conn_cx + conn_l / 2 + tol, 1, conn_z0 + conn_h + tol]);
        box([conn_cx + key_dx - key_w / 2, -wall - 1, 0.3], [conn_cx + key_dx + key_w / 2, -wall + key_d, 0.3 + key_h]);
        // switch: actuator window (with travel) and finger recess
        wy = sw_act[0] + sw_travel + 2 * tol;
        wz = sw_act[1] + 2 * tol;
        sz = sw_z0 + sw_w / 2;
        box([cav_x - 1, sw_yc - wy / 2, sz - wz / 2], [cav_x + wall + 1, sw_yc + wy / 2, sz + wz / 2]);
        box([cav_x + wall - sw_pocket, sw_yc - wy / 2 - 1.5, sz - wz / 2 - 1.2], [cav_x + wall + 1, sw_yc + wy / 2 + 1.5, sz + wz / 2 + 1.2]);
        // LM20A: flat locating pocket for the FPC antenna in the left wall
        if (lm) box([-fpc_pocket, fpc_y0 - tol, fpc_z0 - tol], [0.01, fpc_y1 + tol, fpc_z1 + tol]);
        // USB-C service tunnel + plug-cap counterbore
        if (usb_port) {
            yc = (xiao_y0 + xiao_y1) / 2;
            if (xiao_flip) {
                box([-wall - 1, yc - tun_w / 2, usb_cz - tun_h / 2], [usb_face_x + 0.01, yc + tun_w / 2, usb_cz + tun_h / 2]);
                box([-wall - 1, yc - tun_w / 2 - 1, usb_cz - tun_h / 2 - 1], [-wall + 0.6, yc + tun_w / 2 + 1, usb_cz + tun_h / 2 + 1]);
            } else {
                box([usb_face_x - 0.01, yc - tun_w / 2, usb_cz - tun_h / 2], [cav_x + wall + 1, yc + tun_w / 2, usb_cz + tun_h / 2]);
                box([cav_x + wall - 0.6, yc - tun_w / 2 - 1, usb_cz - tun_h / 2 - 1], [cav_x + wall + 1, yc + tun_w / 2 + 1, usb_cz + tun_h / 2 + 1]);
            }
        }
    }
    if (lid_fastening == "screws")
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
module lid() {
    lw = cav_x + 2 * rabbet - 2 * tol;
    lh = cav_y + 2 * rabbet - 2 * tol;
    difference() {
        union() {
            translate([0, 0, z_lid_bot]) linear_extrude(lid_t) rrect(lw, lh, r_in + rabbet - tol);
            // mic boss down to the gasket (ring) or the foam pad on the mic (pad)
            C() translate([mic_x, mic_y, 0]) {
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
            translate([0, 0, z_rim - port_len - 0.01]) cylinder(d = port_d, h = port_len + 1, $fn = 24);   // 1 mm port
            if (mic_seal == "ring") {
                translate([0, 0, boss_bot - 1]) cylinder(d = foam_dia, h = z_rim - port_len - boss_bot + 1);   // foam + air chamber
                translate([0, 0, boss_bot - 1]) difference() {                                                 // gasket groove
                    cylinder(d = gasket_od + 2 * tol, h = 1 + gasket_groove);
                    translate([0, 0, -1]) cylinder(d = gasket_id - 2 * tol, h = 3 + gasket_groove);
                }
            } else {
                translate([0, 0, chamber_z]) cylinder(d = foam_dia, h = z_rim - port_len - chamber_z);         // foam + air chamber
                translate([-bd_mic_pkg[0] / 2 - tol, -bd_mic_pkg[1] / 2 - tol, boss_bot - 1])                  // foam pad pocket
                    cube([bd_mic_pkg[0] + 2 * tol, bd_mic_pkg[1] + 2 * tol, 1 + mpad_pocket]);
                translate([0, 0, boss_bot]) cylinder(d = mpad_hole + 0.4, h = chamber_z - boss_bot + 0.01, $fn = 24);
            }
        }
        if (lid_fastening == "screws")
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
//  Bezel (snap-on, swappable emblem)
// =====================================================================
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

module bezel(emblem_depth = 0.5) {
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

// =====================================================================
//  Small parts
// =====================================================================
module usb_plug() {   // printed cap for the USB-C service tunnel (prints flange-down)
    fit = 0.1;
    union() {
        cube([tun_w + 2 - 2 * tol, tun_h + 2 - 2 * tol, 0.6]);
        translate([1 - tol + fit, 1 - tol + fit, 0]) cube([tun_w - 2 * fit, tun_h - 2 * fit, 0.6 + wall - 0.6 + 1.0]);
        translate([-1.5, (tun_h + 2 - 2 * tol) / 2 - 1, 0]) cube([2, 2, 0.6]);   // pull tab
    }
}
module gasket() {     // ring: print in TPU 95A, or punch from 1.5 mm closed-cell foam
    if (mic_seal == "ring")
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

// the pad as fitted (domed, for the assembly and the dock envelope check)
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
        union() { body(); lid(); bezel(); }
    }
}

module print_plate() {
    translate([0, 0, z_rim]) rotate([180, 0, 0]) body();                       // rim on the bed
    translate([OW + 8, 0, -z_lid_bot]) lid();                                   // outer face down
    translate([2 * OW + 16, 0, z_top]) rotate([180, 0, 0]) bezel();            // face down
    translate([0, -OH / 2 - 15, 0]) usb_plug();
    translate([25, -OH / 2 - 12, 0]) gasket();
    if (skin_pad) translate([3 * OW + 24, 0, 0]) skin_pad();   // TPU: print it on its own
}

module assembly() {
    color("Tan") body();
    color("Wheat") lid();
    color("SaddleBrown") bezel();
    if (skin_pad) color("DarkSlateGray") skin_pad_fitted();
    electronics();
}

if (part == "assembly")     assembly();
if (part == "fit_check")    fit_check();
if (part == "body")         body();
if (part == "lid")          lid();
if (part == "bezel")        bezel();
if (part == "usb_plug")     usb_plug();
if (part == "gasket")       gasket();
if (part == "print_plate")  print_plate();
if (part == "interference") interference();
if (part == "skin_pad")     skin_pad();
