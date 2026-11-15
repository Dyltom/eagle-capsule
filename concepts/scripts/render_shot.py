"""Render one Eagle Capsule concept shot.

Usage:
  ~/opt/blender.sh -b --factory-startup -P concepts/scripts/render_shot.py -- <shot> [--samples N] [--pct P]

Shots: lowpoly, minimal, crest, exploded, dock, scale, scale-top, cad
(dock and cad import the real CAD STLs from hardware/build/; the others use the
hand-built concept model in ec_common.py)
"""
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import ec_common as ec  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.normpath(os.path.join(HERE, '..', 'renders'))
FILES = {
    'lowpoly': '01-lowpoly.png', 'minimal': '02-minimal.png', 'crest': '03-crest.png',
    'exploded': '04-exploded.png', 'dock': '05-stand-nightstand.png', 'scale': '06-scale.png',
    'scale-top': '07-scale-top.png', 'cad': '08-cad.png',
    'size': '09-size.png', 'size-top': '10-size-top.png',
}


# ------------------------------------------------------------------ hero shots
def shot_hero(style):
    ec.cyclorama((0.60, 0.60, 0.61))
    root, objs = ec.build_capsule(style)
    # lie face-up on the seamless: the curved back touches the floor at its centre
    root.location = (0, 0, -ec.Z_BACK)
    tgt = (2.0, 0.0, 6.0)
    ec.studio_lights(tgt, key_az=-150)
    ec.world(strength=0.12)
    ec.camera(ec.orbit(tgt, 200, 48, 290), tgt, lens=100)


# ------------------------------------------------------------------ exploded
def shot_exploded():
    ec.cyclorama((0.66, 0.66, 0.67))
    st = ec.STYLES['minimal']
    gap = 13.0
    parts = {}
    tub = ec.body_mesh('back shell', ec.M(st['body']), 'tub')
    ec.solidify(tub)
    ec.cut_features(tub, {'pogo', 'switch'})
    lid = ec.body_mesh('front shell', ec.M(st['body']), 'lid')
    ec.solidify(lid)
    ec.cut_features(lid, {'mic'})
    ec.engrave_minimal(lid)
    bail = ec.bail(ec.M(st['body']))
    bez = ec.bezel_ring('bezel', ec.M(st['bezel']))
    mic = ec.mic_parts('minimal')
    strip = ec.pogo_strip()
    knob = ec.switch_knob()
    bat_z0 = -5.4
    bat = ec.battery(bat_z0)
    pcb_z0 = 0.9
    xiao = ec.xiao(-21.0, pcb_z0)   # XIAO toward the bottom (mic/pogo end)
    sd = ec.sd_board(0.5, pcb_z0)

    # explode along local +Z (stack goes up), pogo strip out along -X
    def move(objs, dz=0.0, dx=0.0):
        for o in objs:
            for v in o.data.vertices:
                v.co.z += dz
                v.co.x += dx
    move([tub, bail, knob], 0)
    move(bat, gap * 1.0)
    move(xiao + sd, gap * 2.0)
    move([lid] + mic, gap * 3.2)
    move([bez], gap * 4.0)
    move(strip, 0, -16.0)
    allobjs = [tub, bail, knob, lid, bez] + mic + strip + bat + xiao + sd
    root = ec.empty('exploded')
    ec.parent_all(root, allobjs)
    root.location = (0, 0, -ec.Z_BACK)
    bpy.context.view_layer.update()

    tgt = Vector((0.0, 0.0, 34.0))
    cam = ec.camera(ec.orbit(tgt, 235, 26, 440), tgt, lens=70)
    ec.studio_lights(tgt, key_az=-150)
    ec.world(strength=0.15)

    # labels: text in the camera plane, leader to the part
    labels = [
        ('Front shell + engraved mark, mic foam well', Vector((-8, 6, ec.Z_TOP + gap * 3.2))),
        ('Bezel', Vector((6, 12.5, ec.Z_TOP + 0.4 + gap * 4.0))),
        ('XIAO nRF52840 (21 x 17.8)', Vector((-11, 8.9, pcb_z0 + 1.2 + gap * 2))),
        ('microSD board (20.3 x 17.8)', Vector((10, 8.9, pcb_z0 + 1.2 + gap * 2))),
        ('400 mAh LiPo (38 x 25 x 6)', Vector((5, 12.5, bat_z0 + 4 + gap))),
        ('Back shell, slide switch, bail', Vector((5, ec.B, -1.0))),
        ('4-pin magnetic pogo strip', Vector((ec.LAND_X - 17, 10.5, ec.STRIP_Z))),
    ]
    q = cam.rotation_quaternion
    right = q @ Vector((1, 0, 0))
    up = q @ Vector((0, 1, 0))
    fwd = q @ Vector((0, 0, -1))
    for i, (txt, p_local) in enumerate(labels):
        p = root.matrix_world @ p_local
        # project into a column on the right of the frame
        rel = p - cam.location
        depth = rel.dot(fwd)
        side = -1 if 'pogo' in txt or 'XIAO' in txt else 1
        anchor = p + right * side * 34 + up * 2
        cu = bpy.data.curves.new('label', 'FONT')
        cu.body = txt
        cu.size = 3.3
        cu.align_x = 'LEFT' if side > 0 else 'RIGHT'
        cu.align_y = 'CENTER'
        t = ec.link(bpy.data.objects.new('label', cu))
        t.data.materials.append(ec.M('label'))
        t.rotation_mode = 'QUATERNION'
        t.rotation_quaternion = q
        t.location = anchor + right * side * 1.5
        ec.rod('leader', p, anchor, 0.12, ec.M('leader'))


# ------------------------------------------------------------------ CAD parts
BUILD = os.path.normpath(os.path.join(HERE, '..', '..', 'hardware', 'build'))


def import_stl(name, mat, sharp=40):
    """Import hardware/build/<name>.stl (render it with OpenSCAD first, see concepts/README.md)."""
    path = os.path.join(BUILD, name + '.stl')
    if not os.path.exists(path):
        raise SystemExit(f'missing {path}: render the CAD STLs first (concepts/README.md, "Re-render")')
    bpy.ops.wm.stl_import(filepath=path)
    o = bpy.context.selected_objects[0]
    o.name = name
    o.data.materials.append(mat)
    ec.shade(o, sharp)
    return o


def cad_materials():
    shell = ec.add_noise_bump(ec.pmat('PETG charcoal', (0.035, 0.036, 0.04), 0.42), 3.0, 0.02)
    plate = ec.add_noise_bump(ec.pmat('PETG bronze', (0.30, 0.17, 0.07), 0.38), 3.0, 0.02)
    return shell, plate


# ------------------------------------------------------------------ CAD capsule hero
def shot_cad():
    """The real capsule from hardware/capsule.scad: body, lid and eagle crest plate (default variant)."""
    ec.cyclorama((0.60, 0.60, 0.61))
    shell, plate = cad_materials()
    objs = [import_stl('body', shell), import_stl('lid', shell), import_stl('bezel', plate, 30)]
    zmin = min((o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box)
    for o in objs:
        o.location.z -= zmin   # the domed back rests on the floor
    tgt = (0.0, 2.0, 9.0)
    ec.studio_lights(tgt, key_az=-150)
    ec.world(strength=0.12)
    ec.camera(ec.orbit(tgt, 300, 42, 260), tgt, lens=85)


# ------------------------------------------------------------------ stand on nightstand
def shot_dock():
    """The real stand, posed capsule and plugged-in cable from hardware/dock.scad."""
    feet = 0.9
    shell, plate = cad_materials()
    objs = [import_stl('stand', ec.add_noise_bump(ec.pmat('stand warm grey', (0.36, 0.34, 0.31), 0.6), 3.0, 0.03)),
            import_stl('capsule_shell', shell), import_stl('capsule_plate', plate, 30),
            import_stl('cable', ec.pmat('cable jacket', (0.04, 0.04, 0.042), 0.55), 60)]
    for o in objs:
        o.location.z = feet
    base = objs[0]
    bb = [base.matrix_world @ Vector(c) for c in base.bound_box]
    x0, x1 = min(v.x for v in bb), max(v.x for v in bb)
    y0, y1 = min(v.y for v in bb), max(v.y for v in bb)
    ec.box('rubber feet', (x1 - x0 - 8, y1 - y0 - 8, feet), ((x0 + x1) / 2, (y0 + y1) / 2, feet / 2),
           ec.pmat('rubber', (0.02, 0.02, 0.02), 0.9), bev=0.3)
    # the cable's CAD ends at the table beside the stand; carry it on toward the back
    cb = objs[3]
    cbb = [cb.matrix_world @ Vector(c) for c in cb.bound_box]
    cx = max(v.x for v in cbb) - 2.0
    cy = (min(v.y for v in cbb) + max(v.y for v in cbb)) / 2
    cu = bpy.data.curves.new('cable run', 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 2.0
    cu.bevel_resolution = 4
    sp = cu.splines.new('BEZIER')
    pts = [(cx, cy, 2.0), (cx + 10, cy + 8, 2.0), (cx + 30, cy + 50, 2.0), (cx + 80, cy + 120, 2.0), (cx + 200, cy + 180, 2.0)]
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    cab = ec.link(bpy.data.objects.new('cable run', cu))
    cab.data.materials.append(ec.pmat('cable jacket', (0.04, 0.04, 0.042), 0.55))

    # nightstand
    wood = wood_mat()
    top = ec.box('nightstand top', (700, 420, 24), (60, 40, -12), wood, bev=1.5)
    wall = ec.box('wall', (2000, 20, 1500), (0, 300, 700), ec.pmat('wall', (0.52, 0.47, 0.42), 0.9))
    b1 = ec.box('book', (150, 105, 22), (-170, 150, 11), ec.pmat('book cover', (0.12, 0.17, 0.25), 0.6), bev=1.0)
    b1.rotation_euler.z = math.radians(8)
    b2 = ec.box('book2', (140, 100, 18), (-168, 152, 31), ec.pmat('book cover 2', (0.45, 0.30, 0.18), 0.6), bev=1.0)
    b2.rotation_euler.z = math.radians(-4)
    pages = ec.box('pages', (146, 101, 18.5), (-170, 150, 11), ec.pmat('pages', (0.75, 0.72, 0.65), 0.8))
    pages.rotation_euler.z = math.radians(8)

    tgt = Vector((0, 4, 28))
    cam = ec.camera(ec.orbit(tgt, 240, 16, 330), tgt, lens=60)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = (cam.location - Vector((0, -6, 30))).length
    cam.data.dof.aperture_fstop = 0.006
    k = 5e4
    ec.area('lamp', (-260, -40, 330), tgt, 260, 40 * k, (1.0, 0.78, 0.55))
    ec.area('fill', (220, -300, 160), tgt, 400, 7 * k, (0.80, 0.88, 1.0))
    ec.area('rim', (120, 260, 200), tgt, 200, 14 * k, (1.0, 0.85, 0.7))
    ec.world((0.35, 0.33, 0.32), 0.10)


def wood_mat():
    mat = bpy.data.materials.new('walnut')
    nt, b = ec._principled(mat)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (0.004, 0.03, 0.03)
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.inputs['Scale'].default_value = 3.0
    wave.inputs['Distortion'].default_value = 6.0
    wave.inputs['Detail'].default_value = 4.0
    wave.inputs['Detail Scale'].default_value = 2.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (0.09, 0.045, 0.022, 1)
    ramp.color_ramp.elements[1].color = (0.22, 0.12, 0.06, 1)
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], wave.inputs['Vector'])
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.42
    b.inputs['Coat Weight'].default_value = 0.3
    return mat


# ------------------------------------------------------------------ scale reference
def grid_mat():
    mat = bpy.data.materials.new('10 mm grid mat')
    nt, b = ec._principled(mat)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Object'], sep.inputs['Vector'])

    def line(axis_out, period, width):
        # distance (mm) to nearest grid line along one axis
        m1 = nt.nodes.new('ShaderNodeMath')
        m1.operation = 'DIVIDE'
        m1.inputs[1].default_value = period
        nt.links.new(axis_out, m1.inputs[0])
        m2 = nt.nodes.new('ShaderNodeMath')
        m2.operation = 'PINGPONG'
        m2.inputs[1].default_value = 0.5
        nt.links.new(m1.outputs[0], m2.inputs[0])
        m3 = nt.nodes.new('ShaderNodeMath')
        m3.operation = 'LESS_THAN'
        m3.inputs[1].default_value = width / period
        nt.links.new(m2.outputs[0], m3.inputs[0])
        return m3.outputs[0]

    def either(a, c):
        m = nt.nodes.new('ShaderNodeMath')
        m.operation = 'MAXIMUM'
        nt.links.new(a, m.inputs[0])
        nt.links.new(c, m.inputs[1])
        return m.outputs[0]
    major = either(line(sep.outputs['X'], 10, 0.22), line(sep.outputs['Y'], 10, 0.22))
    minor = either(line(sep.outputs['X'], 1, 0.06), line(sep.outputs['Y'], 1, 0.06))
    mix1 = nt.nodes.new('ShaderNodeMix')
    mix1.data_type = 'RGBA'
    mix1.inputs['A'].default_value = (0.72, 0.72, 0.70, 1)
    mix1.inputs['B'].default_value = (0.55, 0.55, 0.54, 1)
    nt.links.new(minor, mix1.inputs['Factor'])
    mix2 = nt.nodes.new('ShaderNodeMix')
    mix2.data_type = 'RGBA'
    nt.links.new(mix1.outputs['Result'], mix2.inputs['A'])
    mix2.inputs['B'].default_value = (0.25, 0.25, 0.25, 1)
    nt.links.new(major, mix2.inputs['Factor'])
    nt.links.new(mix2.outputs['Result'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.8
    return mat


def scale_props():
    # AA battery, 50.5 mm long incl. the + nub, 14.5 mm diameter, lying along X
    r = 7.25
    yb = -ec.B - 9.0 - r
    wrap = ec.pmat('AA wrap', (0.05, 0.12, 0.30), 0.35)
    band = ec.pmat('AA band', (0.70, 0.70, 0.72), 0.3, 0.0)
    x0 = -25.0
    can = ec.cyl('AA body', r, 49.5, (x0 + 49.5 / 2, yb, r), 'X', wrap, seg=96)
    stripe = ec.cyl('AA stripe', r + 0.03, 8.0, (x0 + 49.5 - 6.5, yb, r), 'X', band, seg=96)
    neg = ec.cyl('AA - end', r - 0.6, 0.3, (x0 - 0.1, yb, r), 'X', ec.M('steel'), seg=64)
    nub = ec.cyl('AA + nub', 2.75, 1.0, (x0 + 49.5 + 0.5, yb, r), 'X', ec.M('steel'), seg=48)
    # AUD 1 dollar coin: 25 mm, 3 mm, aluminium-bronze (plain stand-in, no real coin artwork)
    al_br = ec.pmat('aluminium bronze', (0.78, 0.55, 0.22), 0.28, 1.0)
    cx, cy = ec.A + 8.0 + 12.5 + 6.0, 4.0
    coin = ec.cyl('coin', 12.5, 3.0, (cx, cy, 1.5), 'Z', al_br, seg=128)
    field = ec.cyl('field', 11.2, 1.0, (cx, cy, 3.0 + 0.2), 'Z', smooth=False)
    ec.boolean(coin, field)
    ec.shade(coin, 40)
    return [can, stripe, neg, nub, coin]


def shot_scale(top=False):
    ec.cyclorama((0.62, 0.62, 0.63))
    mat = ec.box('grid mat', (200, 130, 1.0), (10, -5, 0.5), grid_mat(), bev=0.3)
    root, objs = ec.build_capsule('minimal')
    root.location = (0, 0, -ec.Z_BACK + 1.0)
    props = scale_props()
    for p in props:
        for v in p.data.vertices:
            v.co.z += 1.0
    tgt = Vector((10, -10, 5))
    if top:
        ec.camera(tgt + Vector((0, 0, 600)), tgt, ortho=118)
        bpy.context.scene.camera.rotation_mode = 'XYZ'
        bpy.context.scene.camera.rotation_euler = (0, 0, 0)
    else:
        ec.camera(ec.orbit(tgt, 250, 38, 420), tgt, lens=105)
    ec.studio_lights(tgt, key_az=-120)
    ec.world(strength=0.15)


# ------------------------------------------------------------------ CAD size reference
def rounded_slab(name, w, h, t, r, loc, mat):
    """A w x h rectangle with corner radius r, t thick, lying flat with its base at loc.z."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = t / 2
    sp = cu.splines.new('POLY')
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(9):
            a = math.radians(a0 + 90 * i / 8)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), 0, 1))
    sp.points.add(len(pts) - 1)
    for pt, co in zip(sp.points, pts):
        pt.co = co
    sp.use_cyclic_u = True
    o = ec.link(bpy.data.objects.new(name, cu))
    o.location = (loc[0], loc[1], loc[2] + t / 2)
    cu.materials.append(mat)
    return o


def label(text, loc, size=4.2, rot=0.0):
    cu = bpy.data.curves.new('label', 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    cu.extrude = 0.05
    o = ec.link(bpy.data.objects.new('label ' + text, cu))
    o.location = loc
    o.rotation_euler.z = math.radians(rot)
    cu.materials.append(ec.pmat('label ink', (0.03, 0.03, 0.035), 0.7))
    return o


def shot_size(top=False):
    """The CAD capsule (crest plate) beside a bank card, an AA cell and a 25 mm coin on a 10 mm grid."""
    ec.cyclorama((0.62, 0.62, 0.63))
    mat_t = 1.0
    ec.box('grid mat', (260, 170, mat_t), (-35, -18, mat_t / 2), grid_mat(), bev=0.3)
    shell, plate = cad_materials()
    objs = [import_stl('body', shell), import_stl('lid', shell), import_stl('bezel', plate, 30)]
    bb = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    zmin = min(v.z for v in bb)
    cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
    cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
    for o in objs:   # the domed back rests on the mat, centred at the origin
        o.location = (-cx, -cy, mat_t - zmin)
    w = max(v.x for v in bb) - min(v.x for v in bb)
    h = max(v.y for v in bb) - min(v.y for v in bb)
    t = max(v.z for v in bb) - zmin
    # ISO/IEC 7810 ID-1 card: 85.6 x 53.98 x 0.76 mm, 3.18 mm corners (plain, no branding)
    card_x = -w / 2 - 10 - 85.6 / 2
    rounded_slab('bank card', 85.6, 53.98, 0.76, 3.18, (card_x, 0, mat_t),
                 ec.pmat('card', (0.08, 0.20, 0.32), 0.35))
    rounded_slab('card chip', 11.0, 8.5, 0.1, 1.2, (card_x - 26, 4, mat_t + 0.76),
                 ec.pmat('chip', (0.70, 0.58, 0.30), 0.3, 1.0))
    # AA cell, 50.5 x 14.5 mm, lying beside the capsule
    r = 7.25
    ax = w / 2 + 10 + r
    ec.cyl('AA body', r, 49.5, (ax, 0, mat_t + r), 'Y', ec.pmat('AA wrap', (0.05, 0.12, 0.30), 0.35), seg=96)
    ec.cyl('AA stripe', r + 0.03, 8.0, (ax, 18.0, mat_t + r), 'Y',
           ec.pmat('AA band', (0.70, 0.70, 0.72), 0.3, 0.0), seg=96)
    ec.cyl('AA + nub', 2.75, 1.0, (ax, 49.5 / 2 + 0.5, mat_t + r), 'Y', ec.M('steel'), seg=48)
    # 25 mm coin the size of an Australian $1 (plain stand-in, no coin artwork)
    al_br = ec.pmat('aluminium bronze', (0.78, 0.55, 0.22), 0.28, 1.0)
    coin = ec.cyl('coin', 12.5, 3.0, (0, -h / 2 - 10 - 12.5, mat_t + 1.5), 'Z', al_br, seg=128)
    field = ec.cyl('field', 11.2, 1.0, (0, -h / 2 - 10 - 12.5, mat_t + 3.2), 'Z', smooth=False)
    ec.boolean(coin, field)
    ec.shade(coin, 40)
    label(f'capsule {w:.1f} x {h:.1f} x {t:.1f} mm (with loop)', (0, h / 2 + 6, mat_t + 0.01))
    label('bank card 85.6 x 54', (card_x, -36, mat_t + 0.01))
    label('AA 50.5 mm', (ax + 2, -36, mat_t + 0.01))
    label('25 mm coin', (0, -h / 2 - 10 - 25 - 7, mat_t + 0.01))
    tgt = Vector((-36, -18, 4))
    if top:
        ec.camera(tgt + Vector((0, 0, 600)), tgt, ortho=195)
        bpy.context.scene.camera.rotation_mode = 'XYZ'
        bpy.context.scene.camera.rotation_euler = (0, 0, 0)
    else:
        ec.camera(ec.orbit(tgt + Vector((0, 8, 0)), 262, 38, 480), tgt + Vector((0, 8, 0)), lens=85)
    ec.studio_lights(tgt, key_az=-120)
    ec.world(strength=0.15)



SHOTS = {
    'lowpoly': lambda: shot_hero('lowpoly'),
    'minimal': lambda: shot_hero('minimal'),
    'crest': lambda: shot_hero('crest'),
    'exploded': shot_exploded,
    'dock': shot_dock,
    'cad': shot_cad,
    'size': lambda: shot_size(False),
    'size-top': lambda: shot_size(True),
    'scale': lambda: shot_scale(False),
    'scale-top': lambda: shot_scale(True),
}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    shot = argv[0] if argv else 'lowpoly'
    samples, pct, out = 96, 100, None
    i = 1
    while i < len(argv):
        if argv[i] == '--samples':
            samples = int(argv[i + 1]); i += 2
        elif argv[i] == '--pct':
            pct = int(argv[i + 1]); i += 2
        elif argv[i] == '--out':
            out = argv[i + 1]; i += 2
        else:
            raise SystemExit(f'unknown arg {argv[i]}')
    ec.reset()
    t0 = time.time()
    SHOTS[shot]()
    t1 = time.time()
    ec.render_settings(samples=samples, pct=pct)
    sc = bpy.context.scene
    path = out or os.path.join(OUTDIR, FILES[shot])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    t2 = time.time()
    print(f'ECRENDER {shot} build={t1 - t0:.1f}s render={t2 - t1:.1f}s -> {path}')


main()
