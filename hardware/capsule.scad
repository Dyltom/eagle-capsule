// =====================================================================
//  Eagle Capsule - wearable enclosure (OpenSCAD, fully parametric)
//  License: MIT (see repository LICENSE)
//
//  Part dimensions come from the makers' published data:
//    Seeed Studio      - XIAO nRF52840 Sense (21 x 17.8 mm)
//    Pololu            - #2597 microSD breakout (20.3 x 17.8 mm)
//    Adafruit          - #5358 DIY magnetic connector, #805 SPDT slide switch
//    Core Electronics  - CE04375 400 mAh LiPo (and the 1100 mAh option)
//  Anything marked (?) below is NOT verified. Measure it with calipers
//  when the parts arrive and change the parameter (see hardware/README.md).
//
//  Coordinate system (capsule frame):
//    X = across the front face (left/right as you look at the bezel)
//    Y = up the front face (+Y = lanyard end, -Y = magnetic connector edge)
//    Z = thickness, out of the front face (z = 0 is the inner floor,
//        the skin-side dome is below z = 0, the bezel is on top)
//
//  Render one part:   openscad -D 'part="body"' -o body.stl capsule.scad
//  Parts: assembly | fit_check | body | lid | bezel | usb_plug | gasket |
//         print_plate | interference | none
// =====================================================================

/* [What to render] */
part = "assembly";

/* [Global] */
tol      = 0.2;    // printer clearance, per side, for parts that fit together
clr      = 1.2;    // air gap between electronics and the inner wall
$fn      = 40;

/* [Variants] */
// "400" = CE04375 400 mAh (~38 x 25 x 6 ?)  |  "1100" = 51 x 34 x 6, 21 g
battery  = "400";
// Which end of the XIAO the chip antenna is at (NOT confirmed yet):
// "far_end" = opposite the USB-C (expected), "usb_end" = same end as USB-C.
// The antenna end always goes to the plastic-only LEFT wall, overhanging the
// battery; this flips the XIAO (and the USB-C service tunnel) to match.
antenna_at = "far_end";
// Lid fastening: "screws" = 2x M1.6 x 8 self-tapping into bosses
//                "snap"   = 4 bumps on the lid into a groove in the rim
lid_fastening = "screws";
usb_service_port = true;   // USB-C recovery tunnel (+ plug cap) in the side wall

/* [Shell] */
wall        = 2.0;   // side wall
R_out       = 6.0;   // plan-view corner radius of the pebble
back_depth  = 2.6;   // dome: shell thickness at the centre of the skin side
back_inset  = 10;    // dome: how far in from the edge the dome flattens out
back_steps  = 10;
lid_t       = 1.2;
rabbet      = 0.6;   // lid sits in a step this wide inside the rim
bezel_t     = 1.6;
front_ch    = 1.0;   // 45 deg chamfer on the front edge (prints face-down)
headroom    = 0.4;   // gap above the tallest board part
conn_floor  = 3.0;   // height of the connector above the inner floor

/* [XIAO nRF52840 Sense - Seeed Studio] */
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
// USB-C cable plug that must fit the service tunnel (slim overmould)
usb_plug_w    = 12.0;  // (?) overmould width
usb_plug_h    = 6.0;   // (?) overmould thickness

/* [Pololu #2597 microSD breakout] */
sd_l             = 20.3;
sd_w             = 17.8;
sd_h             = 3.5;   // incl. card
sd_card_overhang = 3.0;   // (?) card sticks out past the board edge (points LEFT)
sd_card_w        = 11.0;  // microSD card width

/* [Battery] */
batt_gap   = 1.0;   // foam tape between battery and the boards above it
batt_dims  = battery == "1100" ? [34, 51, 6.0]   // [across X, along Y, thick]
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

// =====================================================================
//  Derived layout  (cavity frame: x,y from the inner bottom-left corner)
// =====================================================================
xiao_flip  = (antenna_at == "usb_end");
batt_x0    = clr + ant_overhang;
batt_y0    = conn_d - wall + conn_gap;
batt_x1    = batt_x0 + batt_dims[0];
batt_y1    = batt_y0 + batt_dims[1];
batt_t     = batt_dims[2];

xiao_x0    = clr + (xiao_flip ? usb_overhang : 0);
xiao_x1    = xiao_x0 + xiao_l;
usb_face_x = xiao_flip ? xiao_x0 - usb_overhang : xiao_x1 + usb_overhang;

sd_x0      = clr + sd_card_overhang;
sd_x1      = sd_x0 + sd_l;
sd_y0      = batt_y0;
sd_y1      = sd_y0 + sd_w;
board_gap  = 2.0;
xiao_y0    = max(sd_y1 + board_gap, batt_y1 - xiao_w);
xiao_y1    = xiao_y0 + xiao_w;

board_z0   = batt_t + batt_gap;
xiao_top   = board_z0 + xiao_h;
sd_top     = board_z0 + sd_h;
pcb_top    = board_z0 + xiao_pcb_t;
usb_cz     = pcb_top + usb_h / 2;
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
                 usb_service_port ? usb_cz + tun_h / 2 + 0.4 : 0);

z_lid_bot  = cav_top;
z_rim      = cav_top + lid_t;
z_top      = z_rim + bezel_t;

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

mic_x    = xiao_flip ? xiao_x0 + mic_from_usb : xiao_x1 - mic_from_usb;
mic_y    = xiao_flip ? xiao_y1 - mic_from_edge : xiao_y0 + mic_from_edge;
usb_inner = 7.3 - usb_overhang;     // receptacle length over the PCB
boss_bot = pcb_top + gasket_t - gasket_groove - gasket_squeeze;
mic_boss_d = gasket_od + 1.2;
usb_gasket_gap = (mic_from_usb - mic_boss_d / 2) - usb_inner;   // lid mic boss vs USB-C shell

// capsule frame offset (cavity centred on the origin)
CX = -cav_x / 2;  CY = -cav_y / 2;

// ---------------- info functions (used by dock.scad) ----------------
function cap_OW()        = OW;
function cap_OH()        = OH;
function cap_zmin()      = -back_depth;
function cap_ztop()      = z_top;
function cap_zrim()      = z_rim;
function cap_conn_face() = [conn_cx + CX, -OH / 2, conn_cz];   // mating-face centre
function cap_mic()       = [mic_x + CX, mic_y + CY, z_top];
function cap_switch_y()  = [sw_yc - sw_l / 2 + CY, sw_yc + sw_l / 2 + CY];
function cap_key()       = [conn_cx + key_dx + CX, 0.3 + key_h / 2];   // x, z of key slot centre
function cap_bail_top()  = OH / 2 + bail_ext();
function bail_ext()      = (bail_style == "flat" ? cord_t : cord_round_d) + 0.6 + 2 * bail_wall;

// ---------------- report ----------------
echo(str("CAPSULE battery=", battery, " antenna_at=", antenna_at));
echo(str("CAPSULE outer W x H x T = ", OW, " x ", OH, " x ", z_top + back_depth,
         " mm  (+", bail_ext(), " mm bail)"));
echo(str("CAPSULE cavity = ", cav_x, " x ", cav_y, " x ", cav_top));
echo(str("FIT antenna overhang past battery = ", batt_x0 - xiao_x0, " mm (antenna zone ", ant_len, ")"));
echo(str("FIT usb tunnel floor above battery = ",
         (usb_cz - tun_h / 2) - batt_t, " mm  (only matters where the tunnel is over the battery: ",
         xiao_flip ? "no" : "yes", ")"));
echo(str("FIT mic chamber above mic = ", (z_rim - port_len) - (pcb_top + mic_pkg[2]),
         " mm (foam ", foam_t, " mm)"));
echo(str("FIT gasket ring to USB-C shell = ", usb_gasket_gap, " mm"));
echo(str("FIT switch leg tips to SD board = ", (sw_x0 - sw_leg_l) - sd_x1, " mm"));

assert(batt_x0 - xiao_x0 >= ant_len, "antenna zone is over the battery");
assert(usb_cz - tun_h / 2 > batt_t || xiao_flip, "USB tunnel hits the battery");
assert((z_rim - port_len) - (pcb_top + mic_pkg[2]) >= foam_t, "no room for the foam disc");
assert(usb_gasket_gap >= 0, "mic boss / gasket sits on the USB-C receptacle: re-measure mic_from_usb");
assert(sw_x0 - sw_leg_l > sd_x1, "switch legs hit the SD board");

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
            slab(back_inset * (1 - cos(a)) - grow, -back_depth * sin(a) - grow);
        }
        slab(-grow, z_top - front_ch);
        slab(front_ch - grow, z_top + grow);
    }
}
module capsule_envelope(grow = 0) {   // pebble + bail, for the dock
    pebble(grow);
    bail_solid(grow);
}

module C() translate([CX, CY, 0]) children();          // cavity frame -> capsule frame
module box(p0, p1) translate(p0) cube([p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]);

// =====================================================================
//  Electronics ghosts (capsule frame)
// =====================================================================
module electronics() {
    C() {
        // battery (+ PCM end toward the connector)
        color("RoyalBlue", 0.75) box([batt_x0, batt_y0, 0], [batt_x1, batt_y1, batt_t]);
        color("White", 0.8) box([batt_x0 + 2, batt_y0, batt_t - 0.01], [batt_x1 - 2, batt_y0 + 4, batt_t + 0.01]);
        // XIAO
        color("ForestGreen", 0.8) box([xiao_x0, xiao_y0, board_z0], [xiao_x1, xiao_y1, pcb_top]);
        ax0 = xiao_flip ? xiao_x0 : xiao_x0;     // antenna zone always at the LEFT end
        color("Gold", 0.8) box([ax0, xiao_y0 + 2, pcb_top], [ax0 + ant_len, xiao_y1 - 2, pcb_top + 0.8]);
        ux = xiao_flip ? xiao_x0 - usb_overhang : xiao_x1 - 7.3 + usb_overhang;
        color("Silver", 0.9) box([ux, (xiao_y0 + xiao_y1 - usb_w) / 2, pcb_top],
                                 [ux + 7.3, (xiao_y0 + xiao_y1 + usb_w) / 2, pcb_top + usb_h]);
        color("Red", 0.9) translate([mic_x, mic_y, pcb_top + mic_pkg[2] / 2])
            cube(mic_pkg, center = true);
        // SD breakout + card (card overhangs to the LEFT)
        color("MediumPurple", 0.8) box([sd_x0, sd_y0, board_z0], [sd_x1, sd_y1, board_z0 + 1.6]);
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
module peg_positions() C() for (p = [[peg_inset, cav_y - peg_inset], [cav_x - peg_inset, cav_y - peg_inset],
                                       [cav_x / 2, peg_inset]])
    translate([p[0], p[1], 0]) children();

module body_internal() {
    C() {
        // connector pedestal + back stop
        box([conn_cx - conn_l / 2 - 1, 0, 0], [conn_cx + conn_l / 2 + 1, -wall + conn_d + tol, conn_z0 - tol]);
        for (s = [-1, 1]) translate([conn_cx + s * (conn_l / 2 - 3) - 1, -wall + conn_d + tol, 0])
            cube([2, 1.2, conn_z0 + conn_h / 2]);
        // plastic-only rib under the very end of the XIAO (antenna end)
        box([0, xiao_y0 + 2, 0], [xiao_x0 + 1.0, xiao_y1 - 2, board_z0]);
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
        // USB-C service tunnel + plug-cap counterbore
        if (usb_service_port) {
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
            // mic boss down to the gasket
            C() translate([mic_x, mic_y, boss_bot]) cylinder(d = mic_boss_d, h = z_lid_bot - boss_bot + 0.01);
            if (lid_fastening == "snap")
                for (p = [[0, lh / 2], [0, -lh / 2], [lw / 2, 0], [-lw / 2, 0]])
                    translate([p[0], p[1], z_lid_bot + lid_t / 2]) scale([p[0] == 0 ? 3 : 1, p[0] == 0 ? 1 : 3, 1])
                        sphere(d = 0.9, $fn = 16);
        }
        C() translate([mic_x, mic_y, 0]) {
            translate([0, 0, z_rim - port_len - 0.01]) cylinder(d = port_d, h = port_len + 1, $fn = 24);   // 1 mm port
            translate([0, 0, boss_bot - 1]) cylinder(d = foam_dia, h = z_rim - port_len - boss_bot + 1);   // foam + air chamber
            translate([0, 0, boss_bot - 1]) difference() {                                                 // gasket groove
                cylinder(d = gasket_od + 2 * tol, h = 1 + gasket_groove);
                translate([0, 0, -1]) cylinder(d = gasket_id - 2 * tol, h = 3 + gasket_groove);
            }
        }
        if (lid_fastening == "screws")
            boss_positions() {
                translate([0, 0, z_lid_bot - 1]) cylinder(d = screw_clear, h = lid_t + 2);
                translate([0, 0, z_rim - (screw_head - screw_clear) / 2 - 0.01])
                    cylinder(d1 = screw_clear, d2 = screw_head, h = (screw_head - screw_clear) / 2 + 0.02);
            }
        peg_positions() translate([0, 0, z_lid_bot - 1]) cylinder(d = peg_d + 2 * tol, h = lid_t + 2);
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
        C() translate([mic_x, mic_y, z_rim - 1]) cylinder(d = bezel_port_d, h = bezel_t + 2, $fn = 24);
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
module gasket() {     // print in TPU 95A, or punch from 1.5 mm closed-cell foam
    difference() {
        cylinder(d = gasket_od, h = gasket_t);
        translate([0, 0, -1]) cylinder(d = gasket_id, h = gasket_t + 2);
    }
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
}

module assembly() {
    color("Tan") body();
    color("Wheat") lid();
    color("SaddleBrown") bezel();
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
