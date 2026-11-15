"""Eagle Capsule concept renders: shared geometry, materials and studio helpers.

All units are millimetres (1 Blender unit = 1 mm). Cycles treats units as
metres, so light powers are scaled up (k = 5e4) compared with a metre-scale scene.

Capsule local frame (before posing):
  +X = top of device (bail end), -X = bottom edge (pogo strip)
  +Y = side with the slide switch
  +Z = front face (bezel, emblem, mic port), -Z = curved skin-side back
Emblems are authored in "face" coordinates (u, v): u = image-right when the
capsule is seen front-on with the bail up, v = up.  Mapping: x = v, y = -u.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- dimensions
# Matched to hardware/capsule.scad (outer 37.4 W x 49.7 H x 18.6 T mm, +6.7 mm bail).
# Re-check these whenever the CAD changes size.
A = 24.85       # body half-length (49.7 mm body; bail adds ~6.7 mm)
B = 18.7        # body half-width (37.4 mm)
P = 4.5         # plan superellipse exponent (rounded rectangle)
N_RING = 256    # vertices per ring
Z_TOP = 7.0     # flat front face
Z_ST = 3.75     # top of straight side wall (start of front fillet)
FILLET = Z_TOP - Z_ST
Z_SB = -8.3     # bottom of straight side wall (start of back curve)
Z_BACK = -10.9  # centre of curved back  -> body 17.9 mm, +0.7 bezel = 18.6 mm
BEZ_OUT, BEZ_IN, BEZ_H = 3.4, 5.0, 0.7
MIC_X = 8.85    # mic port centre: over the XIAO's mic, upper half of the face (CAD cap_mic())
MIC_Y = 5.0     # ... 5 mm left of centre as seen from the front
MIC_R = 1.7     # foam well radius (1 mm port at its floor)
STRIP_Z = -1.8  # pogo strip centre height on the bottom edge
LAND_X = -24.2  # flat land on the bottom edge that the 21x7 strip sits in
SWITCH_X, SWITCH_Z = -7.45, 0.1   # lower half of the right-hand side (CAD)
SW_S = -1       # -Y = the right-hand side as seen from the front
BAIL_HOLE = (25.05, 30.05)  # x-range of the cord tunnel (5.0 mm for a 4-5 mm flat cord)
BAIL_ZC = 3.85    # the CAD bail is flush with the front rim
WALL = 1.2


# ---------------------------------------------------------------- scene utils
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 0.001
    sc.unit_settings.length_unit = 'MILLIMETERS'
    return sc


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_obj(name, verts, faces, mat=None, smooth=False, sharp_angle=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    if mat:
        me.materials.append(mat)
    if smooth:
        shade(obj, sharp_angle)
    return obj


def shade(obj, sharp_angle=35.0):
    """Smooth shading with edges sharper than sharp_angle kept crisp."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.smooth = True
    if sharp_angle is not None:
        lim = math.radians(sharp_angle)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                e.smooth = e.calc_face_angle(0.0) < lim
            else:
                e.smooth = False
    bm.to_mesh(me)
    bm.free()


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False


def apply_mods(obj):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def boolean(obj, cutter, op='DIFFERENCE', transfer=False, remove=True, tolerant=False):
    m = obj.modifiers.new('bool', 'BOOLEAN')
    m.operation = op
    m.object = cutter
    m.solver = 'EXACT'
    if tolerant:   # cutters that aren't clean manifolds (bevelled curves, prism soups)
        m.use_self = True
        m.use_hole_tolerant = True
    if transfer:
        m.material_mode = 'TRANSFER'
    cutter.hide_render = True
    apply_mods(obj)
    if remove:
        bpy.data.objects.remove(cutter)
    return obj


def bevel(obj, width, segments=3, angle=40):
    m = obj.modifiers.new('bevel', 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    apply_mods(obj)
    return obj


def box(name, size, loc=(0, 0, 0), mat=None, bev=0.0, seg=3):
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx + loc[0], v.co.y * sy + loc[1], v.co.z * sz + loc[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    if mat:
        me.materials.append(mat)
    if bev > 0:
        bevel(obj, bev, seg)
        shade(obj, 50)
    return obj


def cyl(name, r, depth, loc=(0, 0, 0), axis='Z', mat=None, seg=64, r2=None, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r, radius2=r if r2 is None else r2, depth=depth)
    rot = {'Z': Matrix.Identity(3),
           'X': Matrix.Rotation(math.radians(90), 3, 'Y'),
           'Y': Matrix.Rotation(math.radians(-90), 3, 'X')}[axis]
    for v in bm.verts:
        v.co = rot @ v.co + Vector(loc)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    if mat:
        me.materials.append(mat)
    if smooth:
        shade(obj, 40)
    return obj


def rod(name, p0, p1, r, mat):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = cyl(name, r, d.length, (0, 0, 0), 'Z', mat, seg=16)
    o.matrix_world = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    return o


def empty(name):
    return link(bpy.data.objects.new(name, None))


def parent_all(root, objs):
    for o in objs:
        o.parent = root


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = d.to_track_quat('-Z', 'Y')


# ---------------------------------------------------------------- materials
def _principled(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    return nt, nt.nodes['Principled BSDF']


def pmat(name, color, rough=0.5, metal=0.0, **kw):
    mat = bpy.data.materials.new(name)
    nt, b = _principled(mat)
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    for k, v in kw.items():
        b.inputs[k].default_value = v
    mat.diffuse_color = (*color, 1)
    return mat


def add_noise_bump(mat, scale=2.0, strength=0.05, detail=6.0, dist=0.02):
    nt = mat.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = scale
    nz.inputs['Detail'].default_value = detail
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = strength
    bump.inputs['Distance'].default_value = dist
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    nt.links.new(nz.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return mat


def speckle(mat, c1, c2, scale=3.0):
    """Mix two base colours with fine noise (stone / PETG speckle)."""
    nt = mat.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = scale
    nz.inputs['Detail'].default_value = 10
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].position = 0.65
    ramp.color_ramp.elements[1].color = (*c2, 1)
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    nt.links.new(nz.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    return mat


_MATS = {}


def M(key):
    """Shared material library (created on first use)."""
    if key in _MATS:
        return _MATS[key]
    f = {
        'charcoal':   lambda: add_noise_bump(pmat('charcoal matte', (0.030, 0.031, 0.033), 0.72), 4.0, 0.04),
        'charcoal_satin': lambda: pmat('charcoal satin', (0.050, 0.050, 0.053), 0.38),
        'bronze':     lambda: pmat('bronze', (0.62, 0.33, 0.15), 0.30, 1.0),
        'stone':      lambda: speckle(pmat('stone satin', (0.30, 0.29, 0.27), 0.42),
                                      (0.27, 0.26, 0.245), (0.34, 0.33, 0.31), 6.0),
        'stone_dark': lambda: pmat('stone dark', (0.16, 0.155, 0.15), 0.35),
        'groove':     lambda: pmat('engraved groove', (0.045, 0.045, 0.045), 0.6),
        'green':      lambda: pmat('dark green PETG', (0.010, 0.050, 0.024), 0.24,
                                   **{'Coat Weight': 0.25, 'Coat Roughness': 0.15}),
        'brass':      lambda: pmat('brass', (0.80, 0.58, 0.22), 0.26, 1.0),
        'foam':       lambda: add_noise_bump(pmat('acoustic foam', (0.012, 0.012, 0.013), 1.0), 60.0, 0.5, 4, 0.1),
        'black':      lambda: pmat('black hole', (0.0, 0.0, 0.0), 1.0),
        'strip':      lambda: pmat('pogo strip plastic', (0.02, 0.02, 0.022), 0.45),
        'gold':       lambda: pmat('gold plating', (0.95, 0.70, 0.32), 0.18, 1.0),
        'steel':      lambda: pmat('nickel', (0.80, 0.80, 0.80), 0.22, 1.0),
        'pcb_blue':   lambda: pmat('blue soldermask', (0.015, 0.06, 0.22), 0.32),
        'pcb_green':  lambda: pmat('green soldermask', (0.02, 0.17, 0.05), 0.32),
        'pouch':      lambda: add_noise_bump(pmat('LiPo pouch', (0.74, 0.75, 0.78), 0.32, 0.9), 0.35, 0.25, 3, 0.15),
        'kapton':     lambda: pmat('kapton', (0.80, 0.38, 0.04), 0.25),
        'chip':       lambda: pmat('IC package', (0.02, 0.02, 0.02), 0.5),
        'wire_red':   lambda: pmat('red wire', (0.55, 0.02, 0.02), 0.4),
        'wire_blk':   lambda: pmat('black wire', (0.02, 0.02, 0.02), 0.4),
        'label':      lambda: pmat('label', (0.03, 0.03, 0.03), 0.5),
        'leader':     lambda: pmat('leader', (0.10, 0.10, 0.10), 0.6),
    }[key]
    _MATS[key] = f()
    return _MATS[key]


STYLES = {
    'lowpoly': dict(body='charcoal', bezel='bronze', emblem='charcoal_satin', accent='bronze'),
    'minimal': dict(body='stone', bezel='stone_dark', emblem='groove', accent='groove'),
    'crest':   dict(body='green', bezel='brass', emblem='green', accent='brass'),
}


# ---------------------------------------------------------------- outline / rings
def _outline(n=N_RING):
    t = np.linspace(0, 2 * np.pi, 20000, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    x = A * np.sign(c) * np.abs(c) ** (2 / P)
    y = B * np.sign(s) * np.abs(s) ** (2 / P)
    xc, yc = np.append(x, x[0]), np.append(y, y[0])
    seg = np.hypot(np.diff(xc), np.diff(yc))
    cum = np.concatenate([[0], np.cumsum(seg)])
    tt = np.linspace(0, cum[-1], n, endpoint=False)
    pts = np.stack([np.interp(tt, cum, xc), np.interp(tt, cum, yc)], 1)
    tan = np.roll(pts, -1, 0) - np.roll(pts, 1, 0)
    tan /= np.linalg.norm(tan, axis=1)[:, None]
    nrm = np.stack([tan[:, 1], -tan[:, 0]], 1)  # outward for CCW outline
    return pts, nrm


OUT, NRM = _outline()


def ring(d=0.0, s=1.0, z=0.0):
    p = s * (OUT - d * NRM)
    return [(float(a), float(b), float(z)) for a, b in p]


def loft(name, rings, bottom=None, top=None, cyclic=False, mat=None):
    n = len(rings[0])
    verts = [v for r in rings for v in r]
    faces = []
    nr = len(rings)
    for k in range(nr if cyclic else nr - 1):
        k2 = (k + 1) % nr
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, k * n + j, k2 * n + j, k2 * n + i))
    if bottom is not None:
        c = len(verts)
        verts.append(bottom)
        faces += [(c, (i + 1) % n, i) for i in range(n)]
    if top is not None:
        c = len(verts)
        verts.append(top)
        base = (nr - 1) * n
        faces += [(c, base + i, base + (i + 1) % n) for i in range(n)]
    return mesh_obj(name, verts, faces, mat, smooth=True, sharp_angle=40)


def back_rings():
    out = []
    for th in np.linspace(0.12, math.pi / 2, 16):
        out.append(ring(0, math.sin(th), Z_SB - (Z_SB - Z_BACK) * math.cos(th)))
    return out


def side_rings(z0=Z_SB, z1=Z_ST, n=6):
    return [ring(0, 1, z) for z in np.linspace(z0, z1, n)]


def front_rings():
    out = []
    for ph in np.linspace(0, math.pi / 2, 18)[1:]:
        out.append(ring(FILLET * (1 - math.cos(ph)), 1, Z_ST + FILLET * math.sin(ph)))
    dc = FILLET + 0.3
    out.append(ring(dc, 1, Z_TOP))
    for s in (0.85, 0.65, 0.45, 0.25):
        p = [(s * x, s * y, Z_TOP) for x, y, _ in ring(dc, 1, Z_TOP)]
        out.append(p)
    return out


def body_mesh(name, mat, part='full'):
    if part == 'full':
        rings = back_rings() + side_rings()[1:] + front_rings()
        return loft(name, rings, (0, 0, Z_BACK), (0, 0, Z_TOP), mat=mat)
    if part == 'tub':
        rings = back_rings() + side_rings()[1:]
        return loft(name, rings, (0, 0, Z_BACK), None, mat=mat)
    if part == 'lid':
        rings = [ring(0, 1, Z_ST)] + front_rings()
        return loft(name, rings, None, (0, 0, Z_TOP), mat=mat)
    raise ValueError(part)


def solidify(obj, t=WALL):
    m = obj.modifiers.new('solid', 'SOLIDIFY')
    m.thickness = t
    m.offset = 1.0   # normals point outward; offset 1 grows along -normal?  see below
    m.use_even_offset = True
    m.offset = -1.0  # inward
    apply_mods(obj)
    shade(obj, 40)
    return obj


def bezel_ring(name, mat, d_out=BEZ_OUT, d_in=BEZ_IN, h=BEZ_H, ch=0.18):
    z0, z1 = Z_TOP - 0.15, Z_TOP + h
    prof = [(d_out, z0), (d_out, z1 - ch), (d_out + ch, z1), (d_in - ch, z1), (d_in, z1 - ch), (d_in, z0)]
    return loft(name, [ring(d, 1, z) for d, z in prof], cyclic=True, mat=mat)


# ---------------------------------------------------------------- features
def cut_features(shell, which):
    """Apply feature cuts. which: subset of {'pogo','switch','mic'}."""
    if 'pogo' in which:
        # flat land on the curved bottom edge, then a pocket for the strip
        land = box('land', (10, 23.4, 7.8), (LAND_X - 5, 0, STRIP_Z))
        boolean(shell, land)
        pocket = box('pocket', (4, 21.2, 7.2), (LAND_X + 2 - 0.01, 0, STRIP_Z))
        boolean(shell, pocket)
    if 'switch' in which:
        slot = box('slot', (7.0, 4, 2.6), (SWITCH_X, SW_S * (B - 1.0 + 2), SWITCH_Z), bev=0.0)
        boolean(shell, slot)
    if 'mic' in which:
        well = cyl('well', MIC_R, 1.6, (MIC_X, MIC_Y, Z_TOP), r2=MIC_R + 0.45, smooth=False)
        # cone: r at bottom (Z_TOP-0.8), flared 0.45 at top -> small chamfer
        boolean(shell, well)
        hole = cyl('hole', 0.5, 6, (MIC_X, MIC_Y, Z_TOP - 3), smooth=False)
        boolean(shell, hole)
    shade(shell, 40)
    return shell


def mic_parts(style):
    foam = cyl('mic foam', MIC_R - 0.02, 0.35, (MIC_X, MIC_Y, Z_TOP - 0.8 - 0.15), mat=M('foam'))
    port = cyl('mic port cut', 0.5, 1.0, (MIC_X, MIC_Y, Z_TOP - 0.8))
    boolean(foam, port)
    shade(foam, 40)
    dark = cyl('mic port', 0.52, 0.2, (MIC_X, MIC_Y, Z_TOP - 1.25), mat=M('black'))
    return [foam, dark]


def pogo_strip():
    s = box('pogo strip', (2.0, 21.0, 7.0), (LAND_X + 1.0, 0, STRIP_Z), M('strip'), bev=0.4)
    pins = []
    for y in (-6.0, -2.0, 2.0, 6.0):
        p = cyl('pogo pad', 0.85, 0.3, (LAND_X - 0.02, y, STRIP_Z), 'X', M('gold'), seg=32)
        pins.append(p)
    return [s] + pins


def switch_knob():
    return box('slide switch', (2.4, 1.6, 1.4), (SWITCH_X - 1.6, SW_S * (B - 0.85), SWITCH_Z), M('strip'), bev=0.25)


def bail(mat):
    x0, x1 = BAIL_HOLE
    tab = box('bail', (x1 + 1.2 - 21.0, 9.0, 4.4), ((x1 + 1.2 + 21.0) / 2, 0, BAIL_ZC), mat, bev=1.2, seg=5)
    hole = box('bail hole', (x1 - x0, 14, 2.0), ((x0 + x1) / 2, 0, BAIL_ZC), bev=0.0)
    boolean(tab, hole)
    shade(tab, 50)
    return tab


# ---------------------------------------------------------------- emblems
def uv2xy(u, v):
    return v, -u


def emblem_lowpoly(style):
    """Faceted eagle with raised, spread wings. Returns list of objects."""
    R = {  # right half (u > 0); centre points have u == 0
        'S': (2.6, 7.5, .55), 'A': (5.6, 13.6, .45), 'T': (9.4, 17.0, .30), 'C': (6.3, 10.0, 1.0),
        'F1': (10.4, 13.2, .30), 'N1': (8.6, 11.4, .55), 'F2': (10.5, 8.8, .30), 'N2': (8.4, 6.7, .55),
        'F3': (9.7, 4.0, .30), 'D': (5.6, 4.6, .85), 'N3': (7.4, 2.5, .50), 'F4': (8.0, -0.6, .30),
        'N4': (5.6, 0.3, .50), 'F5': (5.0, -3.2, .30), 'Bw': (3.0, 1.0, .60),
        'HL': (2.6, 15.4, .45), 'NK': (2.1, 11.8, .50), 'Kb': (1.0, 13.2, 1.0), 'W': (2.2, -4.0, .50),
        'T1': (4.4, -11.4, .30), 't12': (2.4, -9.4, .45), 'T2': (1.4, -12.2, .30),
    }
    Cn = {'Htop': (0, 17.6, .5), 'Hc': (0, 14.6, 1.1), 'Kt': (0, 10.6, 1.35), 'Cc': (0, 6.5, 1.1),
          'Bc': (0, -0.5, 1.0), 'Th': (0, -5.2, .8), 't0': (0, -10.4, .45)}
    wing = [('S', 'A', 'C'), ('A', 'T', 'C'), ('T', 'F1', 'C'), ('F1', 'N1', 'C'), ('N1', 'F2', 'C'),
            ('F2', 'N2', 'C'), ('C', 'N2', 'D'), ('N2', 'F3', 'D'), ('F3', 'N3', 'D'), ('D', 'N3', 'N4'),
            ('N3', 'F4', 'N4'), ('D', 'N4', 'Bw'), ('N4', 'F5', 'Bw'), ('S', 'C', 'D'), ('S', 'D', 'Bw')]
    body = [('Htop', 'HL', 'Hc'), ('HL', 'NK', 'Hc'), ('NK', 'Kb', 'Hc'), ('NK', 'Kt', 'Kb'),
            ('NK', 'S', 'Cc'), ('NK', 'Cc', 'Kt'), ('S', 'Bw', 'Cc'), ('Bw', 'Bc', 'Cc'),
            ('Bw', 'W', 'Bc'), ('W', 'Th', 'Bc'),
            ('Th', 'W', 'T1'), ('Th', 'T1', 't12'), ('Th', 't12', 'T2'), ('Th', 'T2', 't0')]
    beak = [('Hc', 'Kb', 'Kt')]  # per side, plus centre triangle below

    def P(name, side):
        if name in Cn:
            u, v, h = Cn[name]
        else:
            u, v, h = R[name]
        return (side * u, v, h)

    tris_main, tris_accent = [], []
    for side in (1, -1):
        for t in wing + body:
            tris_main.append([P(n, side) for n in t])
        for t in beak:
            tris_accent.append([P(n, side) for n in t])
    hscale = 0.7
    z_bot = Z_TOP - 0.3

    def prisms(name, tris, mat):
        verts, faces = [], []
        for tri in tris:
            b = len(verts)
            for u, v, h in tri:
                x, y = uv2xy(u, v)
                verts.append((x, y, Z_TOP + h * hscale))
            for u, v, h in tri:
                x, y = uv2xy(u, v)
                verts.append((x, y, z_bot))
            faces += [(b, b + 1, b + 2), (b + 5, b + 4, b + 3)]
            for i in range(3):
                j = (i + 1) % 3
                faces.append((b + i, b + 3 + i, b + 3 + j, b + j))
        o = mesh_obj(name, verts, faces, mat)
        flat(o)
        return o
    st = STYLES[style]
    out = [prisms('emblem facets', tris_main, M(st['emblem'])),
           prisms('emblem beak', tris_accent, M(st['accent']))]
    for o in out:   # keep the mic port clear (the CAD bezel has a 2 mm hole there too)
        boolean(o, cyl('port clear', MIC_R + 0.3, 8, (MIC_X, MIC_Y, Z_TOP), smooth=False), tolerant=True)
        flat(o)
    return out


def catmull(pts, n=24):
    pts = [np.array(p, float) for p in pts]
    ext = [2 * pts[0] - pts[1]] + pts + [2 * pts[-1] - pts[-2]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


MINIMAL_STROKES = [
    # eagle head in profile: back of neck, crown, hooked beak curling back
    [(-5.6, -6.0), (-5.6, -0.5), (-4.3, 4.6), (-1.4, 8.4), (2.6, 9.7), (6.0, 8.6), (7.9, 6.1),
     (7.6, 3.4), (6.2, 4.4)],
    # chevron (wings) underneath
    [(-8.8, -6.8), (0.0, -12.4), (8.8, -6.8)],
]
MINIMAL_EYE = (2.7, 6.3)
MIC_UV = (-MIC_Y, MIC_X)   # mic port in face coordinates (x = v, y = -u)
# The minimal mark is mirrored (head faces left) and shifted so the mic port is the eagle's eye.
_MIN_SHIFT = (MIC_UV[0] + MINIMAL_EYE[0], MIC_UV[1] - MINIMAL_EYE[1])
MINIMAL_STROKES = [[(-u + _MIN_SHIFT[0], v + _MIN_SHIFT[1]) for u, v in st] for st in MINIMAL_STROKES]


def engrave_minimal(shell, depth=0.42):
    """Cut the line mark into the shell as a round-bottomed groove (dark infill material)."""
    cutters = []
    for k, stroke in enumerate(MINIMAL_STROKES):
        pts = catmull(stroke, 28) if len(stroke) > 3 else _polyline_round(stroke)
        cu = bpy.data.curves.new(f'stroke{k}', 'CURVE')
        cu.dimensions = '3D'
        cu.bevel_depth = depth
        cu.bevel_resolution = 4
        cu.use_fill_caps = True
        sp = cu.splines.new('POLY')
        sp.points.add(len(pts) - 1)
        for i, (u, v) in enumerate(pts):
            x, y = uv2xy(u, v)
            sp.points[i].co = (x, y, Z_TOP, 1)
        ob = link(bpy.data.objects.new(f'stroke{k}', cu))
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(ob)
        mo = link(bpy.data.objects.new(f'strokemesh{k}', me))
        me.materials.append(M('groove'))
        # round end caps
        for (u, v) in (pts[0], pts[-1]):
            x, y = uv2xy(u, v)
            sph = _sphere('cap', depth, (x, y, Z_TOP), M('groove'))
            cutters.append(sph)
        cutters.append(mo)
    # no separate eye: the mic port is the eye
    for c in cutters:
        boolean(shell, c, transfer=True, tolerant=True)
    shade(shell, 40)
    return shell


def _polyline_round(stroke, r=1.2, n=10):
    """Polyline with slightly rounded corners."""
    pts = [np.array(p, float) for p in stroke]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        p1 = b + (a - b) / np.linalg.norm(a - b) * r
        p2 = b + (c - b) / np.linalg.norm(c - b) * r
        for t in np.linspace(0, 1, n):
            out.append((1 - t) ** 2 * p1 + 2 * (1 - t) * t * b + t * t * p2)
    out.append(pts[-1])
    return out


def _sphere(name, r, loc, mat):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=r)
    for v in bm.verts:
        v.co += Vector(loc)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    me.materials.append(mat)
    return o


# ---- crest relief (height field projected onto the body, wraps over the fillet)
def _seg(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / L2, 0, 1)
    qx, qy = ax + t * dx, ay + t * dy
    return np.hypot(px - qx, py - qy), t


def _feather(px, py, a, b, w0, w1, h, edge=0.55, vane=True):
    d, t = _seg(px, py, a, b)
    w = w0 + (w1 - w0) * t
    inside = d < w
    prof = np.sqrt(np.clip(1 - (d / w) ** 2, 0, 1))
    hh = h * (edge + (1 - edge) * prof)
    if vane:
        hh = hh - 0.07 * (d < 0.09) * (t > 0.08)
    return np.where(inside, hh, 0.0)


def _ellipse(px, py, c, r, h, edge=0.5):
    q = ((px - c[0]) / r[0]) ** 2 + ((py - c[1]) / r[1]) ** 2
    return np.where(q < 1, h * (edge + (1 - edge) * np.sqrt(np.clip(1 - q, 0, 1))), 0.0)


def crest_height(u, v):
    H = np.zeros_like(u)
    au = np.abs(u)
    # wings (mirrored by using |u|)
    S = (2.8, 7.6)
    Wr = (8.6, 12.2)
    # coverts along the arm
    H = np.maximum(H, _feather(au, v, S, Wr, 2.2, 1.6, 0.95, vane=False))
    # secondaries hanging from the arm, pointing down/out
    for k, t in enumerate(np.linspace(0.05, 0.95, 6)):
        a = (S[0] + (Wr[0] - S[0]) * t, S[1] + (Wr[1] - S[1]) * t)
        ang = math.radians(-112 + 26 * t)
        L = 6.2 + 1.2 * t
        b = (a[0] + L * math.cos(ang), a[1] + L * math.sin(ang))
        H = np.maximum(H, _feather(au, v, a, b, 0.95, 0.75, 0.72 - 0.02 * k))
    # primaries fanning from the wrist; outer ones wrap over the edge fillet
    for k, (ang, L) in enumerate([(66, 5.4), (46, 6.0), (26, 6.3), (6, 6.4), (-14, 6.2)]):
        a = Wr
        r = math.radians(ang)
        b = (a[0] + L * math.cos(r), a[1] + L * math.sin(r))
        H = np.maximum(H, _feather(au, v, a, b, 0.95, 0.62, 0.80 - 0.03 * k))
    # tail fan
    for ang in (-90, -75, -60):
        r = math.radians(ang)
        a = (0.0, -3.0)
        b = (a[0] + 8.4 * math.cos(r), a[1] + 8.4 * math.sin(r))
        H = np.maximum(H, _feather(au, v, a, b, 0.85, 1.15, 0.85))
    # talons
    H = np.maximum(H, _feather(au, v, (1.4, -2.0), (2.6, -4.8), 0.7, 0.45, 1.05, vane=False))
    # body with chevron feather rows
    body = _ellipse(u, v, (0, 3.2), (3.5, 7.2), 1.30)
    rows = 0.10 * ((np.mod(v + 0.55 * au, 1.6) / 1.6) > 0.82)
    body = np.where(body > 0, body - rows * (v < 7.5), 0)
    H = np.maximum(H, body)
    # head (turned to the right) + hooked beak
    H = np.maximum(H, _ellipse(u, v, (0.5, 11.6), (2.7, 2.5), 1.45))
    H = np.maximum(H, _feather(u, v, (2.2, 12.1), (4.9, 11.2), 1.05, 0.40, 1.50, edge=0.7, vane=False))
    H = np.maximum(H, _feather(u, v, (4.9, 11.2), (4.55, 10.1), 0.40, 0.22, 1.40, edge=0.8, vane=False))
    # eye socket
    eye = np.hypot(u - 1.5, v - 12.4) < 0.42
    H = np.where(eye, H - 0.35, H)
    return H


def emblem_crest(body, style, step=0.09):
    us = np.arange(-15.4, 15.4 + 1e-6, step)
    vs = np.arange(-15.0, 19.0 + 1e-6, step)
    nu, nv = len(us), len(vs)
    U, V = np.meshgrid(us, vs)  # shape (nv, nu)
    Hm = crest_height(U, V)
    Hm[np.hypot(U - MIC_UV[0], V - MIC_UV[1]) < MIC_R + 0.9] = 0.0   # keep the mic port clear
    keep_v = Hm > 1e-4
    # faces kept if any corner has height
    any_h = keep_v[:-1, :-1] | keep_v[1:, :-1] | keep_v[:-1, 1:] | keep_v[1:, 1:]
    idx = -np.ones((nv, nu), int)
    used = np.zeros((nv, nu), bool)
    jj, ii = np.nonzero(any_h)
    for dj, di in ((0, 0), (1, 0), (0, 1), (1, 1)):
        used[jj + dj, ii + di] = True
    idx[used] = np.arange(used.sum())
    X, Y = uv2xy(U, V)
    verts = np.stack([X[used], Y[used], np.full(used.sum(), 30.0)], 1)
    faces = np.stack([idx[jj, ii], idx[jj, ii + 1], idx[jj + 1, ii + 1], idx[jj + 1, ii]], 1)
    me = bpy.data.meshes.new('crest relief')
    me.from_pydata(verts.tolist(), [], faces.tolist())
    obj = link(bpy.data.objects.new('crest relief', me))
    me.materials.append(M(STYLES[style]['emblem']))
    hmax = float(Hm.max())
    vg = obj.vertex_groups.new(name='h')
    w = (Hm[used] / hmax)
    for i, wi in enumerate(w):
        if wi > 0:
            vg.add([i], float(wi), 'REPLACE')
    sw = obj.modifiers.new('wrap', 'SHRINKWRAP')
    sw.wrap_method = 'PROJECT'
    sw.use_project_z = True
    sw.use_negative_direction = True
    sw.use_positive_direction = False
    sw.target = body
    sw.offset = 0.02
    dp = obj.modifiers.new('relief', 'DISPLACE')
    dp.direction = 'NORMAL'
    dp.mid_level = 0.0
    dp.strength = hmax
    dp.vertex_group = 'h'
    for p in me.polygons:
        p.use_smooth = True
    apply_mods(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def crest_bezel_cut(bez):
    for s in (1, -1):
        c = box('bezcut', (15.5, 8.0, 6), (8.4, s * (B - 1.0), Z_TOP))
        boolean(bez, c)
    shade(bez, 40)
    return bez


# ---------------------------------------------------------------- internals
def battery(z0):
    """400 mAh LiPo pouch 38 x 25 x 6, protection PCB under kapton at one end."""
    objs = []
    p = box('LiPo 38x25x6', (34.5, 25.0, 6.0), (-1.75, 0, z0 + 3.0), M('pouch'), bev=1.0, seg=4)
    objs.append(p)
    k = box('protection PCB (kapton)', (3.5, 22.0, 3.6), (17.25, 0, z0 + 3.0), M('kapton'), bev=0.5)
    objs.append(k)
    for i, (y, m) in enumerate(((-3.0, 'wire_red'), (-1.0, 'wire_blk'))):
        objs.append(rod('lead', (19.0, y, z0 + 3.2), (22.0, y + 2, z0 + 5.6), 0.45, M(m)))
    return objs


def xiao(x0, z0):
    """XIAO nRF52840: 21 x 17.8 PCB, RF shield can, USB-C at the outer end."""
    objs = []
    cx = x0 + 10.5
    objs.append(box('XIAO PCB', (21.0, 17.8, 1.2), (cx, 0, z0 + 0.6), M('pcb_blue'), bev=0.3))
    objs.append(box('nRF52840 shield', (11.5, 10.0, 1.8), (cx + 2.0, 0, z0 + 1.2 + 0.9), M('steel'), bev=0.2))
    objs.append(box('USB-C', (7.3, 9.0, 3.2), (x0 + 3.3, 0, z0 + 1.2 + 1.3), M('steel'), bev=0.8, seg=4))
    for i in range(7):
        for s in (-1, 1):
            objs.append(cyl('castellation', 0.45, 1.3, (x0 + 2.0 + i * 2.54, s * 8.4, z0 + 0.6), mat=M('gold'), seg=16))
    objs.append(box('PDM mic', (3.5, 2.6, 1.0), (x0 + 16.5, -5.5, z0 + 1.7), M('steel'), bev=0.15))
    objs.append(box('IMU', (2.5, 3.0, 0.8), (x0 + 16.5, 5.0, z0 + 1.6), M('chip'), bev=0.1))
    return objs


def sd_board(x0, z0):
    """Pololu-style microSD breakout 20.3 x 17.8 with push-push socket."""
    objs = []
    cx = x0 + 10.15
    objs.append(box('microSD PCB', (20.3, 17.8, 1.2), (cx, 0, z0 + 0.6), M('pcb_green'), bev=0.3))
    objs.append(box('microSD socket', (14.5, 14.0, 1.8), (cx + 1.5, 0, z0 + 1.2 + 0.9), M('steel'), bev=0.15))
    objs.append(box('microSD card', (3.0, 11.0, 0.9), (cx + 1.5 - 8.3, 0, z0 + 1.8), M('chip'), bev=0.1))
    objs.append(box('regulator', (3.0, 3.0, 1.0), (x0 + 3.0, -5.5, z0 + 1.7), M('chip'), bev=0.1))
    for i in range(6):
        objs.append(cyl('pad', 0.6, 1.25, (x0 + 18.3, -6.35 + i * 2.54, z0 + 0.6), mat=M('gold'), seg=16))
    return objs


# ---------------------------------------------------------------- assembled capsule
def build_capsule(style, name='capsule'):
    st = STYLES[style]
    root = empty(name)
    objs = []
    body = body_mesh('shell', M(st['body']), 'full')
    cut_features(body, {'pogo', 'switch', 'mic'})
    if style == 'minimal':
        engrave_minimal(body)
    objs.append(body)
    objs.append(bail(M(st['body'])))
    bez = bezel_ring('bezel', M(st['bezel']))
    if style == 'crest':
        crest_bezel_cut(bez)
        objs.append(emblem_crest(body, style))
    if style == 'lowpoly':
        objs += emblem_lowpoly(style)
    objs.append(bez)
    objs += mic_parts(style)
    objs += pogo_strip()
    objs.append(switch_knob())
    parent_all(root, objs)
    return root, objs


def cutter_shape(scale=(1.02, 1.03, 1.06)):
    """Slightly oversized capsule (body + bail block) used to carve the dock seat."""
    c = body_mesh('cutter', None, 'full')
    bt = box('bailcut', (10.5, 10.0, 5.4), (26.35, 0, BAIL_ZC))
    boolean(c, bt, 'UNION')
    for v in c.data.vertices:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], (v.co.z - Z_SB / 2) * scale[2] + Z_SB / 2))
    return c


def pose_matrix(tilt_deg, loc_local_ref, world_target):
    """Upright capsule (bail up), front facing -Y, top leaning back (+Y) by tilt_deg.
    Places local point loc_local_ref at world_target."""
    s, c = math.sin(math.radians(tilt_deg)), math.cos(math.radians(tilt_deg))
    R = Matrix(((0, -1, 0), (s, 0, -c), (c, 0, s)))
    t = Vector(world_target) - R @ Vector(loc_local_ref)
    m = R.to_4x4()
    m.translation = t
    return m


# ---------------------------------------------------------------- studio
def cyclorama(color=(0.62, 0.62, 0.63), radius=600.0, back=1100.0, size=4000.0):
    """Seamless backdrop: flat floor at z = 0 out to y = back - radius, then curving up."""
    prof = [(-size, 0.0)]
    prof += [(back - radius + radius * math.sin(a), radius - radius * math.cos(a))
             for a in np.linspace(0, math.pi / 2, 24)]
    prof += [(back, size)]
    verts, faces = [], []
    for x in (-size, size):
        for y, z in prof:
            verts.append((x, y, z))
    n = len(prof)
    for i in range(n - 1):
        faces.append((i, i + 1, n + i + 1, n + i))
    mat = pmat('seamless', color, 0.85)
    o = mesh_obj('seamless', verts, faces, mat, smooth=True, sharp_angle=None)
    return o


def area(name, loc, target, size, power, color=(1, 1, 1), size_y=None):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = power
    ld.color = color
    if size_y:
        ld.shape = 'RECTANGLE'
        ld.size, ld.size_y = size, size_y
    else:
        ld.shape = 'DISK'
        ld.size = size
    o = link(bpy.data.objects.new(name, ld))
    o.location = loc
    look_at(o, target)
    return o


def world(color=(0.5, 0.5, 0.52), strength=0.15):
    w = bpy.data.worlds.new('world')
    w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (*color, 1)
    bg.inputs['Strength'].default_value = strength
    bpy.context.scene.world = w
    return w


def camera(loc, target, lens=85.0, ortho=None):
    cd = bpy.data.cameras.new('cam')
    cd.lens = lens
    cd.sensor_width = 36
    cd.clip_start = 1.0
    cd.clip_end = 20000.0
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    o = link(bpy.data.objects.new('cam', cd))
    o.location = loc
    look_at(o, target)
    bpy.context.scene.camera = o
    return o


def orbit(target, az_deg, el_deg, dist):
    az, el = math.radians(az_deg), math.radians(el_deg)
    t = Vector(target)
    return t + dist * Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def studio_lights(target, scale=1.0, key_az=-130, warm=False):
    t = Vector(target)
    k = 5e4 * scale
    key_col = (1.0, 0.93, 0.85) if warm else (1.0, 0.97, 0.94)
    area('key', orbit(t, key_az, 50, 420), t, 320, 30 * k, key_col)
    area('fill', orbit(t, key_az + 120, 25, 520), t, 450, 10 * k, (0.92, 0.96, 1.0))
    area('rim', orbit(t, key_az + 200, 35, 450), t, 220, 22 * k, (1, 1, 1))
    area('top', t + Vector((0, 0, 600)), t, 600, 10 * k)


def render_settings(samples=96, res=(1200, 900), pct=100, exposure=0.0, look='AgX - Medium High Contrast'):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 8
    sc.cycles.glossy_bounces = 4
    sc.cycles.transmission_bounces = 6
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 10.0
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = pct
    sc.render.threads_mode = 'FIXED'
    sc.render.threads = 16
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'AgX'
    try:
        sc.view_settings.look = look
    except TypeError:
        pass
    sc.view_settings.exposure = exposure
