// =====================================================================
//  Eagle Capsule - nightstand dock (OpenSCAD, fully parametric)
//  License: MIT (see repository LICENSE)
//
//  Pulls every capsule dimension from capsule.scad, so change the capsule
//  there and the cradle follows. The capsule stands on its connector edge,
//  face toward the bed, leaning back `tilt` degrees, and slides in along
//  its own long axis. With the eagle plate (bezel_style = "eagle") the seat also clears the
//  plate, and the wings ride above the base.
//
//  Dock frame: X = across the dock, -Y = front (toward the bed), Z = up,
//  z = 0 is the table.
//
//  Render one part:   openscad -D 'part="dock"' -o dock.stl dock.scad
//  Parts: assembly | dock | bottom_plate | print_plate | section | none
//
//  Inside the base (bottom bay, closed by the bottom plate):
//    - a USB-C breakout (e.g. Adafruit #4090) with its receptacle in the back wall
//    - the Schottky diode in the 5 V line (WIRING.md section 3), on flying leads
//    - an optional 3.3 V USB-UART bridge for the dock UART (FIRMWARE.md)
//    - a steel weight (stacked washers) so the dock doesn't tip when you dock
// =====================================================================
use <capsule.scad>

/* [What to render] */
part = "assembly";

/* [Global] */
tol = 0.2;          // printer clearance per side
seat_clr = 0.3;     // extra air around the capsule in the cradle
$fn = 48;

/* [Cradle] */
tilt        = 30;   // capsule leans back this far from vertical (face aims up at the bed)
seat_depth  = 8;    // capsule's connector edge sits this far below the top of the base
back_t      = 4;    // backrest thickness behind the capsule's skin side
back_frac   = 0.62; // backrest covers this fraction of the capsule length
side_t      = 3;    // cradle side wall
cheek_above = 1;    // cheeks rise this far (along the capsule) above the seat depth

/* [Base] */
base_h      = 26;
base_r      = 6;    // plan-view corner radius
base_margin = 10;   // base extends this far past the capsule footprint on each side
front_reach = 12;   // base extends this far in front of the capsule face (tip resistance)
wall        = 2.4;
plate_t     = 2.0;  // bottom plate thickness (sits in a rebate)

/* [Dock connector half - Adafruit #5358, MEASURE ON ARRIVAL] */
dconn_l = 21.0;  // (?) same estimates as the capsule half
dconn_d = 7.0;   // (?) depth below the mating face
dconn_h = 7.0;   // (?)
wire_d  = 5.0;   // wire channel from the connector to the bay

/* [USB-C breakout - Adafruit #4090 (?) ] */
usb_bo  = [18.0, 13.0, 5.0];  // (?) board L (along Y) x W x height incl. receptacle
usbc_win = [9.4, 3.6];        // receptacle window in the back wall (W x H)
usbc_z   = 3.6;               // receptacle centre above the bottom of the base (?)

/* [Weight] */
weight_d = 30.5;    // pocket for M12-M16 washers (~30 mm OD) - (?) measure yours
weight_h = 9.0;     // ~3 washers, roughly 40-60 g of steel

/* [Feet / screws] */
foot_d = 10.5;  foot_t = 1.0;   // recess for 10 mm stick-on rubber feet
screw_pilot = 1.6;  screw_clear = 2.2;  screw_head = 4.0;  boss_r = 3.2;

// =====================================================================
//  Pose: capsule frame -> dock frame
// =====================================================================
OW = cap_OW();  OH = cap_OH();
cf = cap_conn_face();                 // connector mating-face centre (capsule frame)

// where the connector face lands, chosen so the capsule's lowest point sits seat_depth deep
seat_y  = 0;
seat_z  = base_h - seat_depth;

module pose() translate([0, seat_y, seat_z]) rotate([-tilt, 0, 0]) rotate([90, 0, 0])
    translate(-cf) children();

// capsule-frame point -> dock frame (same transform as pose())
function rx(a, p) = [p[0], p[1] * cos(a) - p[2] * sin(a), p[1] * sin(a) + p[2] * cos(a)];
function to_dock(p) = rx(-tilt, rx(90, p - cf)) + [0, seat_y, seat_z];

// slide-in direction: the capsule's +Y axis in the dock frame
ins = rx(-tilt, rx(90, [0, 1, 0]));

// footprint of the posed capsule (a few key points)
p_face_top = to_dock([0, OH / 2, cap_ztop()]);
p_back_top = to_dock([0, OH / 2, cap_zmin()]);
p_face_bot = to_dock([0, -OH / 2, cap_ztop()]);
p_back_bot = to_dock([0, -OH / 2, cap_zmin()]);
p_mic      = to_dock(cap_mic());
// eagle plate (bezel_style = "eagle"): the outline points of the wings where they overhang the pebble
wing_pts   = [for (p = cap_wing_pts()) to_dock(p)];
p_plate_top = to_dock([0, OH / 2 + 10, cap_plate_top()]);   // around the head (for the height report)

y_front = min(p_face_bot[1], p_face_top[1]) - front_reach;
y_back  = max(p_back_top[1], p_back_bot[1]) + back_t + 6;
dock_w  = OW + 2 * base_margin;
dock_d  = y_back - y_front;
dock_cy = (y_front + y_back) / 2;

// the dock connector half, described in the capsule frame (just past the bottom edge)
module dconn_box(grow = 0) pose()
    translate([cf[0] - dconn_l / 2 - grow, -OH / 2 - dconn_d - grow, cf[2] - dconn_h / 2 - grow])
        cube([dconn_l + 2 * grow, dconn_d + 2 * grow + 0.01, dconn_h + 2 * grow]);
dconn_bottom = min([for (sx = [-1, 1], sz = [-1, 1])
    to_dock([cf[0] + sx * dconn_l / 2, -OH / 2 - dconn_d, cf[2] + sz * dconn_h / 2])[2]]);

cheek_top = -OH / 2 + seat_depth / cos(tilt) + cheek_above;   // capsule frame Y
bay_top   = plate_t + usb_bo[2] + 0.5;
weight_top = plate_t + weight_h;
weight_y  = y_front + wall + weight_d / 2 + 2;
// lowest point of the seat (the skin-side bottom corners of the capsule)
seat_low = min([for (sx = [-1, 1], sz = [cap_zmin(), cap_ztop()])
    to_dock([sx * OW / 2, -OH / 2, sz])[2]]) - tol - seat_clr;

// ---------------- report ----------------
echo(str("DOCK footprint = ", dock_w, " x ", dock_d, " mm, height ",
         max(p_back_top[2], p_face_top[2], cap_eagle() ? p_plate_top[2] : 0), " mm with capsule"));
echo(str("DOCK mic port is ", p_mic[2] - base_h, " mm above the base top, aimed ", tilt, " deg above horizontal"));
echo(str("DOCK connector bottom is ", dconn_bottom - plate_t, " mm above the bottom plate"));
echo(str("DOCK seat floor ", seat_low, " mm, bay top ", bay_top, " mm, weight pocket top ", weight_top, " mm"));
echo(str("DOCK base reaches ", p_face_bot[1] - y_front, " mm in front of the capsule face (tip resistance)"));

assert(p_mic[2] > base_h + 3, "the base covers the mic port");
assert(cap_switch_y()[0] > cheek_top + 1, "the cradle covers the privacy switch");
assert(dconn_bottom > bay_top + 1, "the dock connector pocket runs into the bay");
assert(seat_low > weight_top + 1.5, "the weight pocket runs into the seat");
if (cap_eagle()) {
    // the wings ride above the base and the cheeks: they must clear the dock by >= 1 mm
    // (inside the base's width) and the table (outside it)
    wing_low_in  = min([for (p = wing_pts) if (abs(p[0]) <= dock_w / 2 + 1) p[2]]);
    wing_low_all = min([for (p = wing_pts) p[2]]);
    wing_y_min   = min([for (p = cap_wing_pts()) p[1]]);
    echo(str("DOCK eagle wings: lowest point ", wing_low_all, " mm above the table, ",
             wing_low_in - base_h, " mm above the base top, ", wing_y_min - cheek_top, " mm past the cheeks; wing tips ",
             max([for (p = wing_pts) abs(p[0])]) - dock_w / 2, " mm past the base sides"));
    assert(wing_low_in >= base_h + 1, "the eagle's wings hit the dock base");
    assert(wing_y_min >= cheek_top + 1, "the eagle's wings hit the cradle cheeks");
    assert(wing_low_all >= 1, "the eagle's wing tips hit the table");
}

// =====================================================================
//  Shapes
// =====================================================================
module rrect(w, h, r) offset(r = r) square([w - 2 * r, h - 2 * r], center = true);
module footprint(inset = 0) translate([0, dock_cy]) offset(delta = -inset) rrect(dock_w, dock_d, base_r);

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

// backrest: a slab behind the capsule's skin side, hulled down to the base
module backrest() hull() {
    pose() translate([-OW / 2 + 2, -OH / 2 - dconn_d, cap_zmin() - back_t])
        cube([OW - 4, OH * back_frac + dconn_d, back_t + 2]);
    translate([0, 0, base_h - 1]) linear_extrude(1) intersection() {
        footprint(2);
        translate([-OW / 2 + 2, p_back_bot[1] - 4]) square([OW - 4, 30]);
    }
}

// low side cheeks so the capsule can't slide sideways off the seat
module cheeks() pose() translate([-OW / 2 - side_t - tol - seat_clr, -OH / 2 - dconn_d, cap_zmin() - back_t])
    cube([OW + 2 * (side_t + tol + seat_clr), dconn_d + (cheek_top + OH / 2), cap_ztop() - cap_zmin() + back_t + side_t]);

// keying rib: matches the slot in the capsule's bottom edge (the magnets aren't keyed)
module key_rib() {
    k = cap_key();   // [x, z] in the capsule frame
    pose() translate([k[0] - (3.0 - 2 * tol) / 2, -OH / 2 - 1, k[1] - (2.0 - 2 * tol) / 2])
        cube([3.0 - 2 * tol, 1 + 3.0 - 0.6, 2.0 - 2 * tol]);
}

module bay_cuts() {
    // shallow bay under the whole base (USB-C breakout, diode, bridge), open at the bottom
    translate([0, 0, -1]) linear_extrude(bay_top + 1) footprint(wall);
    // deeper pocket for the steel weight, at the front (the capsule leans back)
    translate([0, weight_y, -1]) cylinder(d = weight_d + 2 * tol, h = weight_top + 1);
    // plate rebate
    translate([0, 0, -1]) linear_extrude(plate_t + 1) footprint(wall - 1.2);
    // USB-C window in the back wall
    translate([-usbc_win[0] / 2, y_back - wall - 1, plate_t + usbc_z - usbc_win[1] / 2]) cube([usbc_win[0], wall + 2, usbc_win[1]]);
    // wire channel from the connector pocket down into the bay
    hull() {
        translate(to_dock([cf[0], -OH / 2 - dconn_d + wire_d / 2, cf[2]])) sphere(d = wire_d);
        translate([to_dock(cf)[0], to_dock(cf)[1], plate_t]) cylinder(d = wire_d, h = 1);
    }
}

module screw_positions() for (sx = [-1, 1], sy = [-1, 1])
    translate([sx * (dock_w / 2 - wall - boss_r + 0.6), dock_cy + sy * (dock_d / 2 - wall - boss_r + 0.6), 0]) children();

// =====================================================================
//  Parts
// =====================================================================
module dock() {
    difference() {
        union() {
            difference() {
                union() {
                    linear_extrude(base_h) footprint();
                    backrest();
                    cheeks();
                }
                seat_cut();
                dconn_box(tol);
                bay_cuts();
            }
            key_rib();
            // screw bosses for the bottom plate
            intersection() {
                screw_positions() translate([0, 0, plate_t]) cylinder(r = boss_r, h = bay_top - plate_t + 0.6);
                linear_extrude(base_h) footprint(0.5);
            }
        }
        screw_positions() translate([0, 0, plate_t - 0.01]) cylinder(d = screw_pilot, h = 8);
    }
}

module bottom_plate() {
    t = plate_t;
    difference() {
        union() {
            linear_extrude(t) footprint(wall - 1.2 + tol);
            // fence that locates the USB-C breakout against the back wall
            translate([0, y_back - wall - usb_bo[0] / 2 - tol, t]) difference() {
                cube([usb_bo[1] + 2 * tol + 2.4, usb_bo[0] + 2 * tol + 2.4, 3], center = true);
                cube([usb_bo[1] + 2 * tol, usb_bo[0] + 2 * tol, 10], center = true);
                translate([0, usb_bo[0] / 2, 0]) cube([usb_bo[1] - 4, 6, 10], center = true);
            }
        }
        screw_positions() {
            translate([0, 0, -1]) cylinder(d = screw_clear, h = t + 2);
            translate([0, 0, -0.01]) cylinder(d1 = screw_head, d2 = screw_clear, h = (screw_head - screw_clear) / 2);
        }
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx * (dock_w / 2 - 9), dock_cy + sy * (dock_d / 2 - 9), -0.01]) cylinder(d = foot_d, h = foot_t);
    }
}

module capsule_ghost() color("SaddleBrown", 0.6) pose() { capsule_envelope(0); if (cap_eagle()) bezel(); }

module assembly() {
    color("DimGray") dock();
    color("Black") bottom_plate();
    capsule_ghost();
    color("Goldenrod") dconn_box(0);
}

module section() difference() {   // cut through the connector to check the seat and wiring
    assembly();
    translate([to_dock(cf)[0], -200, -1]) cube([400, 400, 200]);
}

module print_plate() {
    dock();                                            // prints base-down, no supports under the seat
    translate([dock_w + 10, 0, 0]) bottom_plate();
}

if (part == "assembly")     assembly();
if (part == "dock")         dock();
if (part == "bottom_plate") bottom_plate();
if (part == "print_plate")  print_plate();
if (part == "section")      section();
