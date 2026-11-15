// =====================================================================
//  Eagle Capsule - bedside stand (OpenSCAD, fully parametric)
//  License: MIT (see repository LICENSE)
//
//  A printed stand with no electronics: it holds the capsule (eagle plate or flush bezel)
//  on its bottom edge, face toward the bed, leaning back `tilt` degrees. Charging and sync
//  go through a normal USB-C cable in the capsule's side port, which can stay plugged in
//  while the capsule sits here. Every capsule dimension comes from capsule.scad, so the
//  seat follows any capsule change and every variant (pass the same -D settings).
//
//  Stand frame: X = across the stand, -Y = front (toward the bed), Z = up, z = 0 is the table.
//
//  Render:   openscad -D 'part="stand"' -o stand.stl dock.scad
//  Parts: assembly | stand | print_plate | section | capsule | capsule_shell | capsule_plate | cable | none
//  (capsule*, cable: the posed capsule, split into shell and front plate, and the plugged-in cable, for previews)
// =====================================================================
use <capsule.scad>

/* [What to render] */
part = "assembly";

/* [Global] */
tol = 0.2;          // printer clearance per side
seat_clr = 0.3;     // extra air around the capsule in the seat
$fn = 48;

/* [Seat] */
tilt        = 30;   // capsule leans back this far from vertical (face aims up at the bed)
seat_depth  = 5;    // the capsule's bottom edge sits this far below the top of the base
back_t      = 4;    // backrest thickness behind the capsule's skin side
back_frac   = 0.62; // backrest covers this fraction of the capsule length
side_t      = 3;    // seat side wall (cheek)
cheek_above = 0.5;  // cheeks rise this far (along the capsule) above the seat depth

/* [Base] */
base_h      = 18;
base_r      = 6;    // plan-view corner radius
base_margin = 10;   // base extends this far past the capsule on each side
front_reach = 12;   // base extends this far in front of the capsule face (tip resistance)

/* [Weight - optional] */
weight   = true;    // pocket in the underside for steel washers, glued in
weight_d = 30.5;    // M12-M16 washers (~30 mm OD) - (?) measure yours
weight_h = 9.0;     // ~3 washers, roughly 40-60 g of steel

/* [Feet] */
foot_d = 10.5;  foot_t = 1.0;   // recesses for 10 mm stick-on rubber feet

/* [USB-C cable left plugged in - MEASURE YOUR CABLE] */
// The plug goes straight into the capsule's side wall; its overmould sticks out sideways and the
// cable then droops to the table. The stand keeps this whole path clear, also while the capsule
// is lowered in, so the cable can stay plugged in.
usb_om_len  = 22;   // (?) overmould + strain relief, outside the capsule wall
usb_cable_d = 4.0;  // (?) cable diameter
usb_bend_r  = 10;   // (?) the radius the cable droops through after the overmould
cable_clr   = 1.0;  // air kept around the plug and the cable

// =====================================================================
//  Pose: capsule frame -> stand frame
// =====================================================================
OW = cap_OW();  OH = cap_OH();
anchor = [0, -OH / 2, 0];       // capsule's bottom edge at the inner-floor level (its lowest point)
seat_z = base_h - seat_depth;   // where the anchor sits

module pose() translate([0, 0, seat_z]) rotate([-tilt, 0, 0]) rotate([90, 0, 0]) translate(-anchor) children();
function rx(a, p) = [p[0], p[1] * cos(a) - p[2] * sin(a), p[1] * sin(a) + p[2] * cos(a)];
function to_stand(p) = rx(-tilt, rx(90, p - anchor)) + [0, 0, seat_z];
ins = rx(-tilt, rx(90, [0, 1, 0]));   // slide-in direction: the capsule's +Y axis

// key points of the posed capsule
p_face_top = to_stand([0, OH / 2, cap_ztop()]);
p_back_top = to_stand([0, OH / 2, cap_zmin()]);
p_face_bot = to_stand([0, -OH / 2, cap_ztop()]);
p_back_bot = to_stand([0, -OH / 2, cap_zmin()]);
p_mic      = to_stand(cap_mic());
p_sw       = to_stand(cap_switch());
wing_pts   = [for (p = cap_wing_pts()) to_stand(p)];
p_plate_top = to_stand([0, OH / 2 + 10, cap_plate_top()]);   // around the head (height report)

y_front = min(p_face_bot[1], p_face_top[1]) - front_reach;
y_back  = max(p_back_top[1], p_back_bot[1]) + back_t + 6;
stand_w = OW + 2 * base_margin;
stand_d = y_back - y_front;
stand_cy = (y_front + y_back) / 2;

cheek_top = -OH / 2 + seat_depth / cos(tilt) + cheek_above;   // capsule frame Y
// lowest point of the seat (the skin-side bottom corners of the capsule, conservatively)
seat_low = min([for (sx = [-1, 1], sz = [cap_zmin(), cap_ztop()])
    to_stand([sx * OW / 2, -OH / 2, sz])[2]]) - tol - seat_clr;

// ---- USB-C plug + cable (capsule frame for the plug, stand frame for the droop) ----
us   = cap_usb_side();               // +1: port in the right wall, -1: left
up   = cap_usb();                    // port centre on the outer wall
pw   = cap_usb_plug()[0];  ph = cap_usb_plug()[1];
om_x1 = up[0] + us * usb_om_len;     // end of the overmould
// overmould corners, posed
om_corners = [for (x = [up[0], om_x1], dy = [-1, 1], dz = [-1, 1]) to_stand([x, up[1] + dy * pw / 2, up[2] + dz * ph / 2])];
om_low   = min([for (p = om_corners) p[2]]);
p_om_end = to_stand([om_x1, up[1], up[2]]);
// the cable leaves the overmould sideways and droops through usb_bend_r to vertical, then down to the table
bend_c   = p_om_end + [0, 0, -usb_bend_r];
cable_path = concat([for (a = [0 : 15 : 90]) bend_c + usb_bend_r * [us * sin(a), 0, cos(a)]],
                    [[bend_c[0] + us * usb_bend_r, bend_c[1], 0]]);
drop_x   = abs(bend_c[0] + us * usb_bend_r);               // the vertical part of the cable
drop_gap = drop_x - usb_cable_d / 2 - stand_w / 2;          // > 0: it drops beside the base
cheek_x  = OW / 2 + side_t + tol + seat_clr;                // outer face of a cheek

// ---------------- report ----------------
echo(str("STAND footprint = ", stand_w, " x ", stand_d, " mm, height ", base_h, " mm (",
         max(p_back_top[2], p_face_top[2], cap_eagle() ? p_plate_top[2] : 0), " with the capsule)"));
echo(str("STAND mic port is ", p_mic[2] - base_h, " mm above the base top, aimed ", tilt, " deg above horizontal"));
echo(str("STAND privacy switch is ", p_sw[2] - base_h, " mm above the base top, ",
         (cap_switch_y()[0] - cheek_top), " mm above the cheeks"));
echo(str("STAND USB-C plug (", us > 0 ? "right" : "left", " side): overmould ", om_low - base_h, " mm above the base top, ",
         (up[1] - pw / 2) - cheek_top, " mm above the cheeks; the cable drops ",
         drop_gap >= 0 ? str(drop_gap, " mm beside the base") : str("through the cable notch, ", -drop_gap, " mm in from the base edge")));
echo(str("STAND seat floor ", seat_low, " mm", weight ? str(", weight pocket top ", weight_h, " mm") : "",
         "; base reaches ", p_face_bot[1] - y_front, " mm in front of the capsule face"));

assert(p_mic[2] > base_h + 3, "the base covers the mic port");
assert(cap_switch_y()[0] > cheek_top + 1, "the seat cheeks cover the privacy switch");
assert(p_sw[2] > base_h + 3, "the privacy switch is too close to the base top to reach");
assert(!weight || seat_low > weight_h + 1.5, "the weight pocket runs into the seat");
// the plug and the start of its droop clear the base and the cheeks without cutting them
assert(om_low >= base_h + cable_clr, "the USB-C plug overmould hits the base top");
assert(up[1] - pw / 2 >= cheek_top + cable_clr, "the USB-C plug overmould hits a seat cheek");
assert(bend_c[2] - usb_cable_d / 2 >= base_h + cable_clr, "the USB-C cable bends into the base top");
assert(drop_x - usb_cable_d / 2 >= cheek_x + 2, "the USB-C cable would drop through a seat cheek (lengthen usb_om_len)");
if (cap_eagle()) {
    // the wings ride above the base and the cheeks: they must clear the stand by >= 1 mm
    // (inside the base's width) and the table (outside it)
    wing_low_in  = min(concat([1e3], [for (p = wing_pts) if (abs(p[0]) <= stand_w / 2 + 1) p[2]]));
    wing_low_all = min([for (p = wing_pts) p[2]]);
    wing_y_min   = min([for (p = cap_wing_pts()) p[1]]);
    echo(str("STAND eagle wings: lowest point ", wing_low_all, " mm above the table, ",
             wing_low_in - base_h, " mm above the base top, ", wing_y_min - cheek_top, " mm past the cheeks; wing tips ",
             max([for (p = wing_pts) abs(p[0])]) - stand_w / 2, " mm past the base sides"));
    assert(wing_low_in >= base_h + 1, "the eagle's wings hit the stand base");
    assert(wing_y_min >= cheek_top + 1, "the eagle's wings hit the seat cheeks");
    assert(wing_low_all >= 1, "the eagle's wing tips hit the table");
}

// =====================================================================
//  Shapes
// =====================================================================
module rrect(w, h, r) offset(r = r) square([w - 2 * r, h - 2 * r], center = true);
module footprint(inset = 0) translate([0, stand_cy]) offset(delta = -inset) rrect(stand_w, stand_d, base_r);

// capsule envelope + its slide-in path, grown for clearance
// (the eagle plate's convex pieces are swept one by one, so the cut follows its outline)
module seat_cut() {
    hull() {
        pose() capsule_envelope(tol + seat_clr);
        translate(ins * 80) pose() capsule_envelope(tol + seat_clr);
    }
    if (cap_plate_n() > 0) for (i = [0 : cap_plate_n() - 1]) hull() {
        pose() plate_env_piece(i, tol + seat_clr);
        translate(ins * 80) pose() plate_env_piece(i, tol + seat_clr);
    }
}

// the plugged-in cable: overmould (swept along the slide-in path) and the droop to the table
module cable_volume(grow = 0, sweep = true) {
    om = [[min(up[0], om_x1), up[1] - pw / 2 - grow, up[2] - ph / 2 - grow],
          [max(up[0], om_x1), up[1] + pw / 2 + grow, up[2] + ph / 2 + grow]];
    hull() for (k = sweep ? [0, 80] : [0]) translate(ins * k) pose() translate(om[0]) cube(om[1] - om[0]);
    for (i = [0 : len(cable_path) - 2]) hull() for (p = [cable_path[i], cable_path[i + 1]])
        translate(p) sphere(d = usb_cable_d + 2 * grow, $fn = 16);
}

// backrest: a slab behind the capsule's skin side, hulled down to the base
module backrest() hull() {
    pose() translate([-OW / 2 + 2, -OH / 2 - 6, cap_zmin() - back_t]) cube([OW - 4, OH * back_frac + 6, back_t + 2]);
    translate([0, 0, base_h - 1]) linear_extrude(1) intersection() {
        footprint(2);
        translate([-OW / 2 + 2, p_back_bot[1] - 4]) square([OW - 4, 30]);
    }
}

// low side cheeks so the capsule can't slide sideways off the seat
module cheeks() pose() translate([-cheek_x, -OH / 2 - 6, cap_zmin() - back_t])
    cube([2 * cheek_x, 6 + (cheek_top + OH / 2), cap_ztop() - cap_zmin() + back_t + side_t]);

module stand() {
    difference() {
        union() {
            linear_extrude(base_h) footprint();
            backrest();
            cheeks();
        }
        seat_cut();
        cable_volume(cable_clr);   // the cable notch (only cuts where the cable would land on the base)
        if (weight) translate([0, stand_cy, -1]) cylinder(d = weight_d + 2 * tol, h = weight_h + 1);
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx * (stand_w / 2 - 8), stand_cy + sy * (stand_d / 2 - 8), -0.01]) cylinder(d = foot_d, h = foot_t);
    }
}

module capsule_posed() pose() { body(); lid(); bezel(); }

module assembly() {
    color("DimGray") stand();
    color("SaddleBrown") capsule_posed();
    color("Black") cable_volume(0, false);
}

module section() difference() {   // cut down the middle to check the seat
    assembly();
    translate([0, -200, -1]) cube([400, 400, 200]);
}

if (part == "assembly")    assembly();
if (part == "stand")       stand();
if (part == "print_plate") stand();   // base down; the seat opens upward, no supports
if (part == "section")     section();
if (part == "capsule")     capsule_posed();
if (part == "cable")       cable_volume(0, false);
if (part == "capsule_shell") pose() { body(); lid(); }   // the posed capsule split by colour, for renders
if (part == "capsule_plate") pose() bezel();
