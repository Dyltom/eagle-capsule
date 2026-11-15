// Eagle crest: the default front plate (bezel_style = "crest"). Included by capsule.scad.
//
// Original design: a heraldic "displayed" eagle, head in profile with a hooked beak,
// wings raised and fingered, feathered legs with talons and a fanned tail, in raised
// relief on a bezel that stays inside the pebble's outline (nothing overhangs).
// It is drawn in design units on a 100 x 110 box and stretched to the face, so it
// fits every battery / board variant. The bezel prints back-down, relief up; the
// three split pegs are separate pins (part="pegs") pressed into sockets in its back.

/* [Eagle crest - bezel_style = "crest"] */
crest_margin = 2.2;    // relief stays this far inside the pebble outline (front chamfer + 1.2)
crest_h      = 1.3;    // tallest relief (head) above the bezel face
crest_taper  = 0.45;   // inward slope on each relief piece's sides (reads as an edge, prints clean)
crest_port_clr = 1.5;  // flat face kept around the mic port edge (assert >= 1.5)
crest_led_clr  = 0.8;  // ... and around the LED window edge
crest_line   = 0.35;   // engraved detail line width (eye, cere, breast)

CR_W = 100;  CR_H = 110;   // design box
function crest_s() = [(OW - 2 * crest_margin) / CR_W, (OH - 2 * crest_margin) / CR_H];

// one convex relief piece: base outline at the face, top inset by crest_taper, height h
module crest_piece(h) hull() {
    translate([0, 0, z_top - 0.01]) linear_extrude(0.01) children();
    translate([0, 0, z_top + h - 0.01]) linear_extrude(0.01) offset(delta = -crest_taper) children();
}
module crest_scale() scale([crest_s()[0], crest_s()[1], 1]) children();

// feather: hull of a root disc and a tip disc
module feather2d(p0, p1, r0, r1) hull() { translate(p0) circle(r0, $fn = 20); translate(p1) circle(r1, $fn = 20); }

// ---------------- design (right half where mirrored; head faces the viewer's left) ----------------
// wing arm (leading edge), shoulder -> elbow -> wrist
cr_S = [9, 14];  cr_E = [25, 28];  cr_W = [40, 37];
// flight feathers: [t along arm 0..1 (S..E..W), angle deg, length, root r, tip r, height]
cr_flight = [
    [0.00, -97, 30, 4.0, 3.3, 0.62],
    [0.13, -88, 31, 4.0, 3.3, 0.68],
    [0.26, -78, 31, 4.0, 3.3, 0.62],
    [0.39, -67, 30, 3.9, 3.2, 0.68],
    [0.52, -55, 28, 3.8, 3.0, 0.62],
    [0.65, -41, 25, 3.6, 2.8, 0.68],
    [0.78, -26, 20, 3.4, 2.6, 0.62],
    [0.90, -10, 13, 3.2, 2.4, 0.68],
    [0.99,   8,  6, 3.0, 2.2, 0.62],
];
function cr_arm(t) = t < 0.5 ? cr_S + (cr_E - cr_S) * (t * 2) : cr_E + (cr_W - cr_E) * ((t - 0.5) * 2);
// coverts: a second, shorter row over the feather roots
cr_covert = [
    [0.04, -94, 14, 4.6, 3.8], [0.20, -82, 14, 4.6, 3.8], [0.36, -69, 13, 4.5, 3.7],
    [0.52, -55, 12, 4.3, 3.5], [0.68, -40, 10, 4.0, 3.3], [0.84, -24, 7, 3.6, 3.0],
];

module cr_flight2d(f) feather2d(cr_arm(f[0]), cr_arm(f[0]) + f[2] * [cos(f[1]), sin(f[1])], f[3], f[4]);
module cr_covert2d(f) feather2d(cr_arm(f[0]), cr_arm(f[0]) + f[2] * [cos(f[1]), sin(f[1])], f[3], f[4]);
module cr_armband2d() { hull() { translate(cr_S) circle(3.6, $fn = 20); translate(cr_E) circle(3.4, $fn = 20); }
                        hull() { translate(cr_E) circle(3.4, $fn = 20); translate(cr_W) circle(2.8, $fn = 20); } }

cr_torso = [[-7, 22], [7, 22], [11, 13], [12.5, 2], [11, -10], [7, -21], [-7, -21], [-11, -10], [-12.5, 2], [-11, 13]];
// head (profile, facing the viewer's left): rounded crown, heavy brow, hooked beak
cr_eye = [-3.2, 37.2];
module cr_neck2d()  hull() { translate([-6.5, 21]) circle(7, $fn = 32); translate([6.5, 21]) circle(7, $fn = 32);
                             translate([1, 31]) circle(7.5, $fn = 32); }
module cr_crown2d() hull() { translate([1, 37]) circle(8.5, $fn = 40); translate([5, 30]) circle(6.5, $fn = 32);
                             translate([-4, 31.5]) circle(6, $fn = 32); }
module cr_brow2d()  hull() { translate([-8.2, 39.4]) circle(1.6, $fn = 16); translate([3.5, 41.6]) circle(2.0, $fn = 16); }
module cr_beak2d()  hull() { translate([-8.5, 36.2]) circle(4.3, $fn = 32); translate([-16.5, 35.6]) circle(2.5, $fn = 24); }
module cr_hook2d()  hull() { translate([-16.5, 35.6]) circle(2.3, $fn = 24); translate([-19.2, 29.4]) circle(0.9, $fn = 16); }
module cr_jaw2d()   hull() { translate([-8.5, 31.5]) circle(2.4, $fn = 24); translate([-14.5, 32.0]) circle(1.1, $fn = 16); }
// tail: [angle from straight down, length, height]
cr_tail = [[-26, 31, 0.72], [-13, 33, 0.80], [0, 34, 0.72], [13, 33, 0.80], [26, 31, 0.72]];
cr_tail_root = [0, -17];
// legs: thigh ("trousers") and three talons
cr_thigh = [[8, -12], [14, -20]];

module crest_relief() {
    // wings
    for (m = [0, 1]) mirror([m, 0, 0]) {
        for (f = cr_flight) crest_piece(f[5]) cr_flight2d(f);
        for (f = cr_covert) crest_piece(0.9) cr_covert2d(f);
        for (seg = [[cr_S, cr_E, 3.6, 3.4], [cr_E, cr_W, 3.4, 2.8]])
            crest_piece(1.05) feather2d(seg[0], seg[1], seg[2], seg[3]);
        // leg: feathered thigh, shank, three talons
        crest_piece(0.95) feather2d(cr_thigh[0], cr_thigh[1], 5.0, 3.6);
        crest_piece(0.9) feather2d([14, -21], [17.5, -30], 2.2, 1.8);
        for (a = [-135, -100, -65]) {   // three talons, each curling inward at the tip
            k = [17.5, -30] + 5 * [cos(a), sin(a)];
            crest_piece(0.85) feather2d([17.5, -30], k, 1.6, 1.1);
            crest_piece(0.85) feather2d(k, k + 2.6 * [cos(a - 55), sin(a - 55)], 1.1, 0.55);
        }
    }
    // tail fan
    for (t = cr_tail) crest_piece(t[2])
        feather2d(cr_tail_root, cr_tail_root + t[1] * [sin(t[0]), -cos(t[0])], 4.2, 3.6);
    // body and head
    crest_piece(1.05) polygon(cr_torso);
    crest_piece(1.1) cr_neck2d();
    crest_piece(1.15) cr_crown2d();
    crest_piece(crest_h) cr_brow2d();
    crest_piece(crest_h) cr_beak2d();
    crest_piece(crest_h - 0.1) cr_hook2d();
    crest_piece(1.05) cr_jaw2d();
}

// engraved details: eye, brow line, cere line, breast feather scallops
module crest_engrave() {
    translate([0, 0, z_top + 0.6]) linear_extrude(5) {
        translate(cr_eye) scale([1.4, 1]) circle(1.5, $fn = 24);                        // eye
        hull() { translate([-12.6, 40.2]) circle(0.45, $fn = 12); translate([-13.6, 33.2]) circle(0.45, $fn = 12); }  // cere
        hull() { translate([-7.5, 33.6]) circle(0.45, $fn = 12); translate([-16.5, 33.6]) circle(0.35, $fn = 12); }   // gape
    }
    // breast scallops (shallow), three rows of chevrons
    translate([0, 0, z_top + 0.7]) linear_extrude(5)
        for (r = [0 : 3], k = [-2 : 2]) if (abs(k) <= 2 - (r == 3 ? 1 : 0))
            translate([k * 5 + (r % 2) * 2.5 - (r % 2 && k == 2 ? 100 : 0), 12 - r * 7])
                difference() { circle(2.6, $fn = 24); translate([0, 1.1]) circle(2.6, $fn = 24); }
}

module crest_keepouts() {   // flat face around the mic port and LED window (real mm, capsule frame)
    C() translate([mic_x, mic_y, z_top - 0.005]) cylinder(r = bezel_port_d / 2 + crest_port_clr, h = 20, $fn = 32);
    C() translate([led_x, led_y, z_top - 0.005]) cylinder(r = led_hole_d / 2 + crest_led_clr, h = 20, $fn = 32);
}

module crest_bezel(detail = true) {
    difference() {
        union() {
            intersection() {
                pebble();
                translate([-200, -200, z_rim]) cube([400, 400, 50]);
            }
            if (detail) difference() {
                intersection() {
                    crest_scale() crest_relief();
                    translate([0, 0, z_top - 0.1]) linear_extrude(crest_h + 1) outline(crest_margin - 0.6);
                }
                crest_scale() crest_engrave();
                crest_keepouts();
            }
        }
        C() translate([mic_x, mic_y, z_rim - 1]) cylinder(d = bezel_port_d, h = bezel_th + crest_h + 2, $fn = 24);
        C() translate([led_x, led_y, z_rim - 1]) cylinder(d = led_hole_d, h = bezel_th + crest_h + 2, $fn = 24);
        translate([0, -OH / 2, z_rim]) cube([8, 2 * wall, 1.2], center = true);   // pry notch
        peg_positions() {   // sockets for the peg pins
            translate([0, 0, z_rim - 0.01]) cylinder(d = peg_d, h = pin_depth, $fn = 24);
            translate([0, 0, z_rim - 0.01]) cylinder(d1 = peg_d + 0.6, d2 = peg_d, h = 0.3, $fn = 24);
        }
    }
}
