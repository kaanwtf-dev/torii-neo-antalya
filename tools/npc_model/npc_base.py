# NPC base models (one male, one female) from Kaan's "PS1-Style NPC Base Model Reference Sheet.png".
# Run inside Blender (MCP): exec this file, then build('male') / build('female'), bake_base(), bake_variants(),
# export(). Everything is measured from the sheet automatically: each figure's outline is read row by row in
# the front and side views and turned into low-poly rings (torso+head, two legs, two A-pose arms), then the
# sheet's own front/back/side pictures are projected on and baked into a small PS1 texture. Outfit variations
# reuse the same mesh and UVs; only the texture changes (the head keeps the base's face and hair).
#
# Game space (same as Torii / Godot): y up, +z = front, +x = their left. Joint names match Torii's rig:
# body, head, arm_m/p, elb_m/p, leg_m/p, kn_m/p (m = their right/-x). Bones point up with no roll
# (identity rest in glTF); REST POSE = the sheet's A-pose.
import bpy, bmesh, math
import numpy as np
from mathutils import Vector

SHEET = '/Users/kaan/Claude/Video Game Torii/assets/screenshots/PS1-Style NPC Base Model Reference Sheet.png'
# figure boxes on the sheet (x0, x1, top, sole) — found by tools/npc_model (npcfind) on the 1536x1024 sheet
FIG = {
    'male': {'front': (21, 173, 63, 399), 'left': (200, 264, 63, 399), 'back': (281, 426, 63, 399), 'right': (452, 516, 56, 399), 'h': 2.2},
    'female': {'front': (784, 940, 74, 404), 'left': (962, 1027, 74, 403), 'back': (1040, 1185, 74, 402), 'right': (1189, 1250, 74, 401), 'h': 2.15},
}
VARIANTS = {
    'male': [(23, 118, 751, 966), (128, 217, 748, 967), (228, 320, 745, 967), (334, 424, 743, 968), (436, 529, 741, 967), (540, 636, 740, 967)],
    'female': [(983, 1068, 756, 966), (1076, 1155, 755, 966), (1163, 1242, 756, 966), (1248, 1329, 755, 965), (1337, 1421, 756, 965), (1429, 1517, 756, 965)],
}
# projections read the sheet itself (a colour-bled copy was tried: it smeared stripes into the thin arms)
BLEED = SHEET
TEX = 256
_img = None

def G(x, y, z): return Vector((x, -z, y))

def sheet():
    global _img
    if _img is None:
        im = bpy.data.images.load(SHEET, check_existing=True)
        W, H = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3]
        bg = np.median(a[440:450, 10:400].reshape(-1, 3), 0)
        # sensitive threshold: her dark hair and black tops sit very close to the sheet's background colour
        _img = (im, a, np.abs(a-bg).sum(2) > 14/255)
    return _img

def runs(row, gap=3, minlen=3):
    """[(l, r)] of figure pixels in a mask row; gaps up to `gap` px are bridged (dark clothes vs background)"""
    xs = np.where(row)[0]
    if not len(xs): return []
    out = []; s = p = xs[0]
    for x in xs[1:]:
        if x-p > gap+1:
            if p-s+1 >= minlen: out.append((s, p))
            s = x
        p = x
    if p-s+1 >= minlen: out.append((s, p))
    return out

class Mesh:
    def __init__(s): s.v = []; s.w = []; s.f = []
    def vert(s, p, w): s.v.append(p); s.w.append(dict(w)); return len(s.v)-1

def ring(M, c, a, bf, bb, n, w, ex=Vector((1, 0, 0)), ez=Vector((0, 0, 1))):
    out = []
    for k in range(n):
        t = 2*math.pi*k/n
        s_, c_ = math.sin(t), math.cos(t)
        out.append(M.vert(c+ex*(a*s_)+ez*((bf if c_ >= 0 else bb)*c_), w))
    return out

def loft(M, rings, cap0=None, cap1=None):
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n): M.f.append((r0[k], r0[(k+1) % n], r1[(k+1) % n], r1[k]))
    for cap, r in ((cap0, rings[0]), (cap1, rings[-1])):
        if cap is None: continue
        c = M.vert(cap[0], cap[1])
        for k in range(n): M.f.append((r[k], r[(k+1) % n], c))

def lerpw(t, a, b):
    t = min(1, max(0, t)); out = {}
    for k in set(a) | set(b): out[k] = a.get(k, 0)*(1-t)+b.get(k, 0)*t
    return {k: v for k, v in out.items() if v > 1e-3}

def measure(kind):
    """read the front + side outlines into world-space profiles"""
    _, img, m = sheet()
    F = FIG[kind]; x0, x1, top, sole = F['front']; k = F['h']/(sole-top)
    cx = (x0+x1)/2
    sx0, sx1, stop, ssole = F['left']; ks = F['h']/(ssole-stop)
    # which way the side figure faces: the face (skin) side of the head is the brighter one
    hr = slice(stop+int((ssole-stop)*.06), stop+int((ssole-stop)*.11))
    mid = (sx0+sx1)//2
    lum = img[hr, sx0:sx1].mean(2)
    front_right = lum[:, mid-sx0:].mean() > lum[:, :mid-sx0].mean()
    P = {'k': k, 'cx': cx, 'front_right': bool(front_right), 'rows': []}
    for y in range(top, sole+1, 2):
        fr = runs(m[y, x0:x1+1]); sr = runs(m[y if y <= ssole else ssole, sx0:sx1+1])
        wy = (sole-y)*k
        P['rows'].append({'y': wy, 'f': [((a+x0)-cx, (b+x0)-cx) for a, b in fr],
                          's': [(a+sx0, b+sx0) for a, b in sr]})
    # side axis: centre of the side outline at hip height
    hip = [r for r in P['rows'] if abs(r['y']-F['h']*.45) < .03 and r['s']]
    sc = np.mean([(r['s'][0][0]+r['s'][-1][1])/2 for r in hip]) if hip else (sx0+sx1)/2
    for r in P['rows']:
        if r['s']:
            a, b = r['s'][0][0]-sc, r['s'][-1][1]-sc
            r['z'] = (b*ks, a*ks) if front_right else (-a*ks, -b*ks)   # (front extent, back extent) in world z
        else: r['z'] = None
        r['f'] = [(a*k, b*k) for a, b in r['f']]
    return P

def build(kind):
    P = measure(kind); h = FIG[kind]['h']; M = Mesh()
    rows = P['rows']
    def centre_run(r):
        for a, b in r['f']:
            if a <= 0 <= b: return (a, b)
        return None
    # landmarks
    neck = h*.86                                    # hair/sleeves make a measured neck unreliable
    crotch = max(r['y'] for r in rows if r['y'] < h*.6 and not centre_run(r))
    arm_rows = [r for r in rows if crotch < r['y'] < neck and len(r['f']) >= 3]
    armpit = max(r['y'] for r in arm_rows)
    hand_bot = min(r['y'] for r in rows if r['y'] > crotch-.35 and len(r['f']) >= 3) if arm_rows else crotch
    J = {'body': (0, 0, 0)}
    def torso_span(r):
        # dark clothes/hair read as background, so never trust a single run: above the armpits take the
        # whole span (head, hair, shoulders); below them, everything between the two arms
        f = r['f']
        if r['y'] >= armpit: mid = [ab for ab in f if abs(ab[0]) < .34 and abs(ab[1]) < .34]
        else: mid = f[1:-1] if len(f) >= 3 else [ab for ab in f if abs(ab[0]) < .3 and abs(ab[1]) < .3]
        return (min(a for a, b in mid), max(b for a, b in mid)) if mid else None
    # ---- torso + head: one tube from the crown to the crotch (10 sides)
    T = []
    for r in rows[::4]:
        cr = torso_span(r)
        if not cr or r['z'] is None or r['y'] < crotch-.02: continue
        a, b = cr; zf, zb = r['z']
        rx = max(.03, (b-a)/2); cxx = (a+b)/2
        if r['y'] < armpit+.02 or r['y'] > neck:   # below the armpit the run is the torso only; above the neck the head
            pass
        else:                                       # between: the run includes the shoulders — keep it, arms blend in
            pass
        cz = (zf+zb)/2; dz = max(.03, (zf-zb)/2)
        w = {'head': 1} if r['y'] > neck+.03 else lerpw((r['y']-(neck-.04))/.07, {'body': 1}, {'head': 1})
        T.append(ring(M, Vector((cxx, r['y'], cz)), rx, dz, dz, 10, w))
    T = T[::-1]                                     # bottom -> top
    loft(M, T, cap0=(Vector((0, crotch-.03, 0)), {'body': 1}), cap1=(Vector((0, rows[0]['y'], 0)), {'head': 1}))
    J['head'] = (0, neck, 0)
    # ---- legs: two tubes from just above the crotch to the sole (8 sides), knee halfway
    knee = crotch*.52
    for s in (-1, 1):
        n = 'p' if s > 0 else 'm'; L = []
        for r in rows[::4]:
            if r['y'] > crotch+.08: continue
            legs = [ab for ab in r['f'] if (ab[0]+ab[1])/2*s > 0]
            if r['y'] > crotch: legs = [(0, s*.16)] if s > 0 else [(-.16, 0)]
            if not legs or r['z'] is None: continue
            a, b = legs[-1] if s < 0 else legs[0]         # the innermost piece: hands hang further out
            zf, zb = r['z']; cz = (zf+zb)/2; dz = max(.03, (zf-zb)/2)
            w = lerpw((knee+.06-r['y'])/.12, {'leg_'+n: 1}, {'kn_'+n: 1})
            L.append(ring(M, Vector(((a+b)/2, max(r['y'], .0), cz)), max(.03, (b-a)/2), dz, dz, 8, w))
        L = L[::-1]
        sole_c = sum((M.v[i] for i in L[0]), Vector())/len(L[0])
        loft(M, L, cap0=(Vector((sole_c.x, 0, sole_c.z)), {'kn_'+n: 1}))
        lx = [M.v[i].x for i in L[-1]]; J['leg_'+n] = (sum(lx)/len(lx), crotch+.04, 0)
        kx = [ (M.v[r_[0]].x+M.v[r_[4]].x)/2 for r_ in L if abs(M.v[r_[0]].y-knee) < .06]
        J['kn_'+n] = (kx[0] if kx else J['leg_'+n][0], knee, 0)
    # ---- arms (A-pose): follow the arm's outline down from the armpit to the fingertips (8 sides)
    for s in (-1, 1):
        n = 'p' if s > 0 else 'm'; pts = []
        for r in rows[::3]:
            if not (hand_bot-.02 <= r['y'] <= armpit) or len(r['f']) < 3: continue
            a, b = r['f'][0] if s < 0 else r['f'][-1]
            pts.append((r['y'], (a+b)/2, max(.025, (b-a)/2)))
        if len(pts) < 2: continue
        # extend the line up to the shoulder, inside the torso
        (y0, x0_, _), (y1, x1_, _) = pts[0], pts[min(3, len(pts)-1)]
        slope = (x0_-x1_)/max(1e-3, y0-y1)
        sh_y = neck-.14; sh_x = x0_+slope*(sh_y-y0)
        pts = [(sh_y, sh_x, pts[0][2]*1.15)]+pts
        L_arm = sum(math.hypot(pts[i+1][0]-pts[i][0], pts[i+1][1]-pts[i][1]) for i in range(len(pts)-1))
        A = []; acc = 0
        for i, (yy, xx, rr) in enumerate(pts):
            if i: acc += math.hypot(yy-pts[i-1][0], xx-pts[i-1][1])
            t = acc/max(1e-3, L_arm)
            w = lerpw((t-.42)/.1, {'arm_'+n: 1}, {'elb_'+n: 1}) if t > .1 else lerpw(t/.1, {'body': .5, 'arm_'+n: .5}, {'arm_'+n: 1})
            # ring perpendicular-ish to the arm: keep it horizontal (PS1 arms are tubes anyway)
            A.append(ring(M, Vector((xx, yy, -.01)), rr, rr*.9, rr*.9, 8, w))
            if abs(t-.45) < .08 and 'elb_'+n not in J: J['elb_'+n] = (xx, yy, -.01)
        loft(M, A, cap1=(Vector((pts[-1][1], pts[-1][0]-.02, -.01)), {'elb_'+n: 1}))
        J['arm_'+n] = (sh_x, sh_y, -.01)
        J.setdefault('elb_'+n, (pts[len(pts)//2][1], pts[len(pts)//2][0], -.01))
    # shoulders/sleeves are part of the torso tube: let their outer half follow the arm
    for i, p in enumerate(M.v):
        if 'body' in M.w[i] and len(M.w[i]) == 1 and neck-.30 < p.y < neck-.02:
            for s in (-1, 1):
                n = 'p' if s > 0 else 'm'
                if 'arm_'+n in J and p.x*s > abs(J['arm_'+n][0])*.6:
                    t = min(1, (p.x*s-abs(J['arm_'+n][0])*.6)/(abs(J['arm_'+n][0])*.5))
                    M.w[i] = lerpw(t*.8, {'body': 1}, {'arm_'+n: 1})
    ob = make_object(M, kind)
    rig(ob, kind, J)
    LAND[kind] = {'neck': neck, 'crotch': crotch}
    return ob, J

LAND = {}

def make_object(M, kind):
    coll = bpy.data.collections.get('NPC') or bpy.data.collections.new('NPC')
    if coll.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(coll)
    name = 'npc_'+kind
    for o in [o for o in coll.objects if o.name.startswith(name)]: bpy.data.objects.remove(o)
    me = bpy.data.meshes.new(name); ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
    bm = bmesh.new(); dl = bm.verts.layers.deform.verify()
    groups = sorted({k for w in M.w for k in w})
    for g in groups: ob.vertex_groups.new(name=g)
    vs = [bm.verts.new(G(*p)) for p in M.v]
    for v, w in zip(vs, M.w):
        t = sum(w.values()) or 1
        for k, x in w.items(): v[dl][groups.index(k)] = x/t
    for idx in M.f:
        try: f = bm.faces.new([vs[i] for i in idx]); f.smooth = False
        except ValueError: pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return ob

PARENT = {'head': 'body', 'arm_m': 'body', 'arm_p': 'body', 'elb_m': 'arm_m', 'elb_p': 'arm_p',
          'leg_m': 'body', 'leg_p': 'body', 'kn_m': 'leg_m', 'kn_p': 'leg_p'}

def rig(ob, kind, J):
    coll = ob.users_collection[0]; name = 'rig_'+kind
    old = bpy.data.objects.get(name)
    if old: bpy.data.objects.remove(old)
    ad = bpy.data.armatures.new(name); arm = bpy.data.objects.new(name, ad); coll.objects.link(arm)
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win, active_object=arm, object=arm, selected_objects=[arm]):
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode='EDIT')
        for n, p in J.items():
            eb = ad.edit_bones.new(n); eb.head = G(*p); eb.tail = G(*p)+Vector((0, 0, .08)); eb.roll = 0
        for n in J:
            if n in PARENT and PARENT[n] in J: ad.edit_bones[n].parent = ad.edit_bones[PARENT[n]]
        bpy.ops.object.mode_set(mode='OBJECT')
    ob.parent = arm
    ob.modifiers.new('rig', 'ARMATURE').object = arm
    return arm

# ---------------------------------------------------------------- texturing
def _proj_material(name, views, head_from=None, head_tex=None, side_band=None):
    """emission material = blend of orthographic sheet projections; views: [(cx, sole, k, axis, sign, (naxis, nsign))]
    head_tex: above head_from, copy this image through the UVs instead (variants keep the base face/hair)"""
    im = bpy.data.images.load(BLEED, check_existing=True); W, H = im.size
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear(); N = nt.nodes.new; L = nt.links.new
    out = N('ShaderNodeOutputMaterial'); em = N('ShaderNodeEmission'); L(em.outputs[0], out.inputs['Surface'])
    tc = N('ShaderNodeTexCoord'); sep = N('ShaderNodeSeparateXYZ'); L(tc.outputs['Object'], sep.inputs[0])
    geo = N('ShaderNodeNewGeometry'); ns = N('ShaderNodeSeparateXYZ'); L(geo.outputs['Normal'], ns.inputs[0])
    def mth(op, a, b=None):
        n = N('ShaderNodeMath'); n.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: L(v, n.inputs[i])
        return n.outputs[0]
    csum = wsum = None
    for cx, sole, k, axis, sign, (na, nsg) in views:
        px = mth('ADD', mth('MULTIPLY', sep.outputs['X' if axis == 'x' else 'Y'], sign/k), cx)
        py = mth('SUBTRACT', sole, mth('DIVIDE', sep.outputs['Z'], k))
        cmb = N('ShaderNodeCombineXYZ'); L(mth('DIVIDE', px, W), cmb.inputs[0]); L(mth('SUBTRACT', 1.0, mth('DIVIDE', py, H)), cmb.inputs[1])
        tx = N('ShaderNodeTexImage'); tx.image = im; tx.interpolation = 'Closest'; tx.extension = 'EXTEND'; L(cmb.outputs[0], tx.inputs['Vector'])
        if na is None: w = mth('ADD', 0.0, 1.0)
        else: w = mth('ADD', mth('POWER', mth('MAXIMUM', mth('MULTIPLY', ns.outputs['X' if na == 'x' else 'Y'], nsg), 0.0), 3.0), .002)
        if side_band and na == 'x':
            # side pictures show the hanging arms over the torso: use them only on the head and the legs
            lo, hi = side_band
            above = mth('GREATER_THAN', sep.outputs['Z'], hi); below = mth('LESS_THAN', sep.outputs['Z'], lo)
            w = mth('MULTIPLY', w, mth('MAXIMUM', above, below))
        sc = N('ShaderNodeVectorMath'); sc.operation = 'SCALE'; L(tx.outputs['Color'], sc.inputs[0]); L(w, sc.inputs['Scale'])
        if csum is None: csum, wsum = sc.outputs[0], w
        else:
            ad = N('ShaderNodeVectorMath'); ad.operation = 'ADD'; L(csum, ad.inputs[0]); L(sc.outputs[0], ad.inputs[1]); csum = ad.outputs[0]
            wsum = mth('ADD', wsum, w)
    nm = N('ShaderNodeVectorMath'); nm.operation = 'SCALE'; L(csum, nm.inputs[0]); L(mth('DIVIDE', 1.0, wsum), nm.inputs['Scale'])
    col = nm.outputs[0]
    if head_tex is not None:
        ht = N('ShaderNodeTexImage'); ht.image = head_tex; ht.interpolation = 'Closest'
        uvn = N('ShaderNodeUVMap'); uvn.uv_map = 'bake'; L(uvn.outputs[0], ht.inputs['Vector'])
        hm = mth('MINIMUM', mth('MAXIMUM', mth('DIVIDE', mth('SUBTRACT', sep.outputs['Z'], head_from), .02), 0.0), 1.0)
        mix = N('ShaderNodeMix'); mix.data_type = 'RGBA'; L(hm, mix.inputs['Factor']); L(col, mix.inputs[6]); L(ht.outputs['Color'], mix.inputs[7])
        col = mix.outputs[2]
    L(col, em.inputs['Color'])
    return m

def _bake(ob, mat, img_name):
    me = ob.data; win = bpy.context.window_manager.windows[0]
    tgt = bpy.data.images.get(img_name) or bpy.data.images.new(img_name, TEX, TEX, alpha=False)
    node = mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image = tgt; mat.node_tree.nodes.active = node
    me.materials.clear(); me.materials.append(mat)
    sc = bpy.context.scene; old = sc.render.engine
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 1; sc.cycles.device = 'CPU'
    sc.render.bake.margin = 4; sc.render.bake.use_clear = True
    for o in bpy.context.view_layer.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(window=win, active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.bake(type='EMIT')
    sc.render.engine = old
    return tgt

def uv(ob):
    me = ob.data; win = bpy.context.window_manager.windows[0]
    if 'bake' not in me.uv_layers: me.uv_layers.new(name='bake')
    me.uv_layers.active = me.uv_layers['bake']
    for o in bpy.context.view_layer.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(window=win, active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=.015, area_weight=.4)
        bpy.ops.object.mode_set(mode='OBJECT')

def bake_base(kind):
    ob = bpy.data.objects['npc_'+kind]; F = FIG[kind]; uv(ob)
    def v(box, axis, sign, nrm, facing=None):
        x0, x1, top, sole = box; k = F['h']/(sole-top); return ((x0+x1)/2, sole, k, axis, sign, nrm)
    P = measure(kind); fr = P['front_right']
    # left view = camera on their left (+x) if the face points image-right, else on their right
    views = [v(F['front'], 'x', 1, ('y', -1)), v(F['back'], 'x', -1, ('y', 1)),
             v(F['left'], 'y', -1 if fr else 1, ('x', -1 if fr else 1)), v(F['right'], 'y', 1 if fr else -1, ('x', 1 if fr else -1))]
    mat = _proj_material('npcbake_'+kind, views, side_band=(LAND[kind]['crotch'], LAND[kind]['neck']-.06))
    return _bake(ob, mat, kind+'_base')

def bake_variants(kind, head_from):
    ob = bpy.data.objects['npc_'+kind]; F = FIG[kind]; base = bpy.data.images[kind+'_base']; out = []
    for i, (x0, x1, top, sole) in enumerate(VARIANTS[kind]):
        k = F['h']/(sole-top); cx = (x0+x1)/2
        views = [(cx, sole, k, 'x', 1, (None, 0))]       # front picture only: wrapped all the way round
        mat = _proj_material(f'npcbake_{kind}_{i}', views, head_from=head_from, head_tex=base)
        out.append(_bake(ob, mat, f'{kind}_{i}'))
    return out

def export(kind, outdir):
    """<outdir>/npc_<kind>.glb (mesh + A-pose rig + base texture, nearest-filtered) and <kind>_<i>.png outfits"""
    import os
    ob = bpy.data.objects['npc_'+kind]; arm = bpy.data.objects['rig_'+kind]
    loc = arm.location.copy(); arm.location = (0, 0, 0)
    base = bpy.data.images[kind+'_base']
    m = bpy.data.materials.get('npc_'+kind) or bpy.data.materials.new('npc_'+kind)
    m.use_nodes = True; nt = m.node_tree; bs = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE']: nt.nodes.remove(n)
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = base; t.interpolation = 'Closest'
    nt.links.new(t.outputs['Color'], bs.inputs['Base Color']); bs.inputs['Roughness'].default_value = 1
    ob.data.materials.clear(); ob.data.materials.append(m)
    for img in [base]+[bpy.data.images[f'{kind}_{i}'] for i in range(len(VARIANTS[kind]))]:
        img.filepath_raw = os.path.join(outdir, img.name+'.png'); img.file_format = 'PNG'; img.save()
    for o in bpy.context.view_layer.objects: o.select_set(False)
    ob.select_set(True); arm.select_set(True)
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win):
        bpy.ops.export_scene.gltf(filepath=os.path.join(outdir, 'npc_'+kind+'.glb'), export_format='GLB', use_selection=True,
                                  export_image_format='AUTO', export_animations=False, export_skins=True, export_yup=True,
                                  export_normals=True, export_materials='EXPORT')
    arm.location = loc
