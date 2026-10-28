# Torii from Kaan's turnaround sheet (assets/screenshots/Retro Low-Poly Character Turnaround Sheet.png).
# Run inside Blender (MCP): exec this file, then build() / bake() / rig() / export().
#
# Game space (same as the game and the Godot port): y up, +z = her front, +x = her left, head top 2.2.
# Sheet -> game: k = 2.2/455 per pixel, front view centre x=202.5, sole at row 497.
# Measured from the sheet: shoulders y~1.71, arm thickness .116 (shoulder) -> .044 (wrist),
# crop top 1.53-1.74, bare midriff 1.42-1.52, jacket tied at 1.36 hanging to ~.72 on the sides and back,
# wide-leg jeans splaying to x~±.2 at the ankle, sneakers ~.36 long.
import bpy, bmesh, math
from mathutils import Vector

K = 2.2/455
SHEET = {'cx_front': 202.5, 'cx_back': 746.5, 'cz_side1': 498.0, 'cz_side2': 1017.0, 'sole': 497.0, 'W': 1448, 'H': 1086}

def G(x, y, z): return Vector((x, -z, y))          # game -> Blender

class Mesh:
    def __init__(s): s.v = []; s.w = []; s.f = []; s.part = []
    def vert(s, p, w): s.v.append(p); s.w.append(dict(w)); return len(s.v)-1
    def face(s, idx, part): s.f.append(tuple(idx)); s.part.append(part)

def ring(M, c, e1, e2, a, bpos, bneg, n, w, ang0=0.0):
    """n verts round centre c: e1*a*sin + e2*b*cos (b = bpos on the +e2 side, bneg on the -e2 side)"""
    out = []
    for k in range(n):
        t = ang0+2*math.pi*k/n
        s_, c_ = math.sin(t), math.cos(t)
        out.append(M.vert(c+e1*(a*s_)+e2*((bpos if c_ >= 0 else bneg)*c_), w))
    return out

def loft(M, rings, part, cap0=None, cap1=None):
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n): M.face((r0[k], r0[(k+1) % n], r1[(k+1) % n], r1[k]), part)
    for cap, r in ((cap0, rings[0]), (cap1, rings[-1])):
        if cap is None: continue
        c = M.vert(cap[0], cap[1])
        for k in range(n): M.face((r[k], r[(k+1) % n], c), part)

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))      # game axes (converted at the end)

def lerpw(t, a, b):
    out = {}
    for k in set(a) | set(b): out[k] = a.get(k, 0)*(1-t)+b.get(k, 0)*t
    return {k: v for k, v in out.items() if v > 1e-3}

def build():
    M = Mesh()
    # ---- torso: crotch -> neck (body), neck top goes to the head
    T = [(.80, .20, .12, .12, -.04), (.90, .215, .13, .14, -.03), (1.05, .205, .13, .14, -.02), (1.20, .185, .12, .13, -.01),
         (1.36, .150, .11, .105, .01), (1.45, .138, .10, .095, .015), (1.52, .16, .11, .10, .02), (1.60, .172, .135, .10, .02),
         (1.68, .178, .11, .10, .01), (1.735, .165, .085, .09, .0), (1.775, .085, .065, .065, -.005), (1.84, .052, .05, .05, -.01),
         (1.90, .048, .046, .046, -.01)]
    rings = []
    for y, rx, zf, zb, cz in T:
        w = {'body': 1} if y < 1.85 else {'head': .6, 'body': .4}
        rings.append(ring(M, Vector((0, y, cz)), X, Z, rx, zf, zb, 10, w))
    loft(M, rings, 'torso', cap0=(Vector((0, .78, -.04)), {'body': 1}), cap1=(Vector((0, 1.92, -.01)), {'head': 1}))

    # ---- the jacket tied round her waist: long at the sides/back, open at the front below the knot
    J = []
    for y, rx, zf, zb, cz in [(1.37, .17, .125, .12, .01), (1.30, .20, .13, .14, .0), (1.18, .25, .16, .17, .0),
                               (1.00, .285, .18, .16, .01), (.84, .305, .18, .15, .02), (.72, .315, .17, .14, .02)]:
        row = []
        for k in range(10):
            t = 2*math.pi*k/10
            s_, c_ = math.sin(t), math.cos(t)
            front = max(0.0, c_)**2                                   # 1 at the front centre
            yy = max(y, 1.12+.06*(front-.6)/.4) if front > .6 else y   # the front stops at the knot
            p = Vector((s_*rx, yy, cz+(zf if c_ >= 0 else zb)*c_))
            side = 'leg_p' if s_ > 0 else 'leg_m'
            tl = min(1, max(0, (1.25-yy)/.5))
            row.append(M.vert(p, lerpw(tl*.5, {'body': 1}, {side: 1})))
        J.append(row)
    loft(M, J, 'jacket')
    # the knot: a fat lump at the front of the waist
    kc = Vector((.0, 1.27, .115))
    kr = [ring(M, kc+Vector((0, dy, 0)), X, Z, a, b, b, 6, {'body': 1}) for dy, a, b in ((.07, .03, .02), (.03, .075, .04), (-.04, .07, .04), (-.09, .03, .02))]
    loft(M, kr, 'jacket')

    # ---- wide-leg jeans, splaying out to the ankle, and sneakers
    for s in (-1, 1):
        n = 'p' if s > 0 else 'm'
        L = []
        for y, x, z, rx, rz in [(.98, .105, -.03, .095, .11), (.80, .125, -.04, .105, .12), (.62, .145, -.055, .105, .12),
                                 (.42, .17, -.07, .11, .125), (.24, .19, -.08, .115, .13), (.19, .195, -.08, .115, .13)]:
            w = lerpw(min(1, max(0, (.62-y)/.2)), {'leg_'+n: 1}, {'kn_'+n: 1})
            L.append(ring(M, Vector((x*s, y, z)), X, Z, rx, rz, rz, 8, w))
        loft(M, L, 'jeans', cap0=(Vector((.195*s, .21, -.08)), {'kn_'+n: 1}))
        S = []
        for y, rx, zf, zb in [(.0, .075, .25, .17), (.035, .08, .26, .175), (.10, .078, .23, .16), (.16, .065, .12, .12), (.19, .05, .06, .08)]:
            S.append(ring(M, Vector((.205*s, y, -.03)), X, Z, rx, zf, zb, 8, {'kn_'+n: 1}))
        loft(M, S, 'shoe', cap0=(Vector((.205*s, .0, .0)), {'kn_'+n: 1}), cap1=(Vector((.205*s, .195, -.04)), {'kn_'+n: 1}))

    # ---- arms (T-pose along ±x), palms down, with a thumb
    for s in (-1, 1):
        n = 'p' if s > 0 else 'm'
        A = []
        for x, ry, rz, yc in [(.13, .06, .06, 1.742), (.20, .062, .06, 1.745), (.30, .05, .05, 1.74), (.40, .045, .045, 1.735),
                               (.47, .04, .04, 1.73), (.58, .036, .036, 1.725), (.70, .026, .03, 1.718), (.74, .022, .042, 1.716),
                               (.82, .02, .045, 1.712), (.885, .012, .03, 1.705)]:
            if x < .22: w = lerpw((x-.13)/.09, {'body': 1}, {'arm_'+n: 1})
            elif x < .44: w = {'arm_'+n: 1}
            elif x < .50: w = lerpw((x-.44)/.06, {'arm_'+n: 1}, {'elb_'+n: 1})
            else: w = {'elb_'+n: 1}
            A.append(ring(M, Vector((x*s, yc, -.01)), Y, Z, ry, rz, rz, 8, w, ang0=math.pi/8))
        loft(M, A, 'arm', cap0=(Vector((.12*s, 1.74, -.01)), {'body': 1}), cap1=(Vector((.895*s, 1.705, -.01)), {'elb_'+n: 1}))
        th = [ring(M, Vector((xx*s, 1.71, .035+dz)), X*s, Y, r, r, r, 5, {'elb_'+n: 1}) for xx, dz, r in ((.735, 0, .014), (.765, .02, .011), (.79, .03, .007))]
        loft(M, th, 'arm')

    # ---- head: skull with a flat-ish face
    H = []
    for y, rx, zf, zb, cz in [(1.83, .035, .04, .03, .045), (1.86, .075, .085, .07, .03), (1.91, .095, .115, .095, .015), (1.97, .105, .125, .11, .0),
                               (2.03, .108, .12, .12, -.005), (2.09, .104, .105, .12, -.01), (2.14, .085, .08, .1, -.015), (2.175, .05, .05, .065, -.02)]:
        H.append(ring(M, Vector((0, y, cz)), X, Z, rx, zf, zb, 10, {'head': 1}))
    loft(M, H, 'head', cap0=(Vector((0, 1.825, .05)), {'head': 1}), cap1=(Vector((0, 2.19, -.02)), {'head': 1}))
    # hair: a cap over the skull, a curtain of braids down her back, clumps over each shoulder
    HC = []
    for y, rx, zf, zb, cz in [(1.93, .145, .06, .165, -.02), (2.0, .148, .085, .175, -.02), (2.07, .145, .118, .17, -.02), (2.13, .125, .1, .155, -.02),
                               (2.175, .085, .07, .11, -.025)]:
        HC.append(ring(M, Vector((0, y, cz)), X, Z, rx, zf, zb, 12, {'head': 1}))
    loft(M, HC, 'hair', cap1=(Vector((0, 2.205, -.02)), {'head': 1}))
    BK = []
    for y, hw, zc, d in [(1.97, .13, -.15, .05), (1.80, .135, -.155, .05), (1.62, .13, -.16, .045), (1.40, .105, -.16, .035)]:
        BK.append(ring(M, Vector((0, y, zc)), X, Z, hw, d, d, 8, lerpw(min(1, (1.97-y)/.5), {'head': 1}, {'head': .5, 'body': .5})))
    loft(M, BK, 'hair', cap1=(Vector((0, 1.38, -.16)), {'head': .5, 'body': .5}))
    for s in (-1, 1):
        SC = []
        for y, x, z, a, b in [(1.98, .14, -.01, .035, .05), (1.85, .15, .0, .038, .045), (1.72, .155, .015, .032, .035), (1.62, .15, .02, .024, .025)]:
            SC.append(ring(M, Vector((x*s, y, z)), X, Z, a, b, b, 6, lerpw(min(1, (1.98-y)/.36), {'head': 1}, {'head': .3, 'body': .7})))
        loft(M, SC, 'hair', cap1=(Vector((.15*s, 1.60, .02)), {'body': .7, 'head': .3}))
    return make_object(M)

def make_object(M, name='ToriiSheet'):
    coll = bpy.data.collections.get('TORII3') or bpy.data.collections.new('TORII3')
    if coll.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects): bpy.data.objects.remove(o)
    me = bpy.data.meshes.new(name); ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    groups = sorted({k for w in M.w for k in w})
    for g in groups: ob.vertex_groups.new(name=g)
    vs = [bm.verts.new(G(*p)) for p in M.v]
    for v, w in zip(vs, M.w):
        t = sum(w.values()) or 1
        for k, x in w.items(): v[dl][groups.index(k)] = x/t
    parts = sorted(set(M.part))
    for idx, part in zip(M.f, M.part):
        try: f = bm.faces.new([vs[i] for i in idx])
        except ValueError: continue
        f.material_index = parts.index(part); f.smooth = False
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    for p in parts:
        m = bpy.data.materials.get('part_'+p) or bpy.data.materials.new('part_'+p); me.materials.append(m)
    return ob

# ---- rig: same joint names as the HTML game (body, head, arm_*/elb_*, leg_*/kn_*), T-pose rest.
# Bones point straight up with no roll, so every bone's rest rotation is identity in glTF and the
# game's pose numbers (rotation.x/y/z per joint) apply directly. Arms-down standing is done in code.
JOINTS = {'body': ((0, 0, 0), None), 'head': ((0, 1.86, -.01), 'body')}
for _s in (-1, 1):
    _n = 'p' if _s > 0 else 'm'
    JOINTS['arm_'+_n] = ((.15*_s, 1.745, -.01), 'body'); JOINTS['elb_'+_n] = ((.46*_s, 1.732, -.01), 'arm_'+_n)
    JOINTS['leg_'+_n] = ((.105*_s, .95, -.03), 'body'); JOINTS['kn_'+_n] = ((.155*_s, .52, -.065), 'leg_'+_n)

def rig(obj_name='ToriiSheet'):
    ob = bpy.data.objects[obj_name]; coll = ob.users_collection[0]
    old = bpy.data.objects.get('ToriiSheetRig')
    if old: bpy.data.objects.remove(old)
    ad = bpy.data.armatures.new('ToriiSheetRig'); arm = bpy.data.objects.new('ToriiSheetRig', ad); coll.objects.link(arm)
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win, active_object=arm, object=arm, selected_objects=[arm]):
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode='EDIT')
        for n, (p, par) in JOINTS.items():
            eb = ad.edit_bones.new(n); eb.head = G(*p); eb.tail = G(*p)+Vector((0, 0, .08)); eb.roll = 0
        for n, (p, par) in JOINTS.items():
            if par: ad.edit_bones[n].parent = ad.edit_bones[par]
        bpy.ops.object.mode_set(mode='OBJECT')
    ob.parent = arm
    for m in [m for m in ob.modifiers if m.type == 'ARMATURE']: ob.modifiers.remove(m)
    ob.modifiers.new('rig', 'ARMATURE').object = arm
    return arm

def pose(arm, rots):
    """rots: {bone: (rx, ry, rz)} in the game's convention (three.js Euler XYZ)"""
    for b in arm.pose.bones:
        b.rotation_mode = 'ZYX'; b.rotation_euler = (0, 0, 0)
    for n, r in rots.items():
        b = arm.pose.bones[n]; b.rotation_euler = r   # an up-pointing, roll-0 bone's local x/y/z ARE the game's x/y/z
    bpy.context.view_layer.update()
