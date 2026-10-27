# Turns Vinrax's "PSX Secretary Character" (CC-BY style: free to use, credit Vinrax —
# https://vinrax.itch.io/psx-secretary-character) into Torii for the game.
# Run inside Blender (the MCP) with the FBX imported and its arms posed down / stretched
# onto the game's joints, then baked to an object called 'sec_baked' (see README.md).
#
# What it does: re-UVs every face into Torii's own texture atlas (skin / face / top / bot /
# hair / braid / shoe regions — the same canvas the game paints for her, so outfits, level
# costumes and Lory's dark palette all still work), adds her face decal and nine beaded box
# braids, re-weights the mesh onto the game's joint names and exports torii.glb.
#
# Game space = three.js: y up, +z is her front. Blender space: z up, -y front.
import bpy, bmesh, math, colorsys
from mathutils import Vector

REG = {"skin":[0.005859375,0.744140625,0.255859375,0.994140625],"face":[0.267578125,0.744140625,0.517578125,0.994140625],
       "top":[0.529296875,0.806640625,0.779296875,0.994140625],"bot":[0.005859375,0.576171875,0.255859375,0.732421875],
       "hair":[0.267578125,0.607421875,0.517578125,0.732421875],"braid":[0.529296875,0.482421875,0.591796875,0.732421875],
       "shoe":[0.603515625,0.607421875,0.728515625,0.732421875],"sole":[0.740234375,0.669921875,0.802734375,0.732421875]}
HEAD = (0, 2.0, 0)
ARM = {s: (0.222*s, 1.715, 0) for s in (-1, 1)}
LEG = {s: (0.118*s, 0.92, 0) for s in (-1, 1)}
NB = 9
BRAID = [(math.sin(a)*.153, 2.0-.045, -math.cos(a)*.16+.004) for a in (-1.85+i*(3.7/(NB-1)) for i in range(NB))]
SN = {-1: 'm', 1: 'p'}
MAT_ATLAS, MAT_FACE, MAT_BEAD = 0, 1, 2
# her face texture covers this box on the flat front of the head (game space):
# (unused, half-width, chin y, forehead y); the front itself sits at z = FACE_Z
FACE_BOX = (0, .115, 1.865, 2.145)
FACE_Z = .135
# the secretary rig's bones -> the game's joint groups (her left, .L, is +x = the game's s=+1)
GMAP = {'hips': 'body', 'spine': 'body', 'chest': 'body', 'neck': 'body', 'shoulder.L': 'body', 'shoulder.R': 'body',
        'head': 'head'}
for side, s in (('L', 'p'), ('R', 'm')):
    GMAP.update({'upper_arm.'+side: 'arm_'+s, 'forearm.'+side: 'elb_'+s, 'hand.'+side: 'elb_'+s, 'thumb.'+side: 'elb_'+s,
                 'thigh.'+side: 'leg_'+s, 'shin.'+side: 'kn_'+s, 'foot.'+side: 'kn_'+s, 'toe.'+side: 'kn_'+s})

SRC_FBX = '/Users/kaan/Downloads/female-secretary-character-psx/source/female_secretary/female_secretary.fbx'

def prep(fbx=SRC_FBX):
    """import the FBX, scale her to the game (head top 2.2), hang the arms straight down and
    stretch the bones so hips/knees/shoulders/elbows land on the game's joints, then bake
    that into a plain mesh 'sec_baked' (still carrying the original vertex groups)"""
    from mathutils import Matrix, Quaternion
    win = bpy.context.window_manager.windows[0]
    before = set(bpy.data.objects)
    with bpy.context.temp_override(window=win):
        bpy.ops.import_scene.fbx(filepath=fbx)
    new = [o for o in bpy.data.objects if o not in before]
    a = next(o for o in new if o.type == 'ARMATURE'); m = next(o for o in new if o.type == 'MESH')
    S = 2.2/1.653
    a.scale = (S, S, S); bpy.context.view_layer.update()
    with bpy.context.temp_override(window=win, active_object=a, object=a, selected_objects=[a, m], selected_editable_objects=[a, m]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for n in ('neck', 'shoulder.L', 'shoulder.R', 'thigh.L', 'thigh.R', 'shin.L', 'shin.R', 'foot.L', 'foot.R', 'chest',
              'forearm.L', 'forearm.R', 'hand.L', 'hand.R', 'head'):
        a.data.bones[n].inherit_scale = 'NONE'
    P = a.pose.bones
    for pb in P: pb.rotation_mode = 'QUATERNION'
    P['hips'].location = (0, -.189, 0)                       # hips down to the game's .92
    for sd in 'LR':
        P['thigh.'+sd].scale = (1, .40/a.data.bones['thigh.'+sd].length, 1)
        P['shin.'+sd].scale = (1, .36/a.data.bones['shin.'+sd].length, 1)
    k = .69/.566                                              # a longer torso: shoulders up to 1.715
    P['spine'].scale = (1, k, 1); P['chest'].scale = (1, k, 1); P['neck'].scale = (1, 1.25, 1)
    P['chest'].rotation_quaternion = Quaternion((1, 0, 0), .12)   # stand up straight over the hips
    bpy.context.view_layer.update()
    def point_down(pb):
        loc, rot, sc = pb.matrix.decompose()
        q = (pb.tail-pb.head).normalized().rotation_difference(Vector((0, 0, -1)))
        pb.matrix = Matrix.Translation(loc)@(q.to_matrix().to_4x4()@rot.to_matrix().to_4x4())@Matrix.Diagonal(sc.to_4d())
        bpy.context.view_layer.update()
    for sd in 'LR':
        for n in ('upper_arm.', 'forearm.', 'hand.'): point_down(P[n+sd])
        P['upper_arm.'+sd].scale = (1, .28/a.data.bones['upper_arm.'+sd].length, 1)
        P['forearm.'+sd].scale = (1, .25/a.data.bones['forearm.'+sd].length, 1)
    bpy.context.view_layer.update()
    old = bpy.data.objects.get('sec_baked')
    if old: bpy.data.objects.remove(old)
    b = m.copy(); b.data = m.data.copy(); b.name = 'sec_baked'; m.users_collection[0].objects.link(b)
    with bpy.context.temp_override(window=win, active_object=b, object=b, selected_objects=[b], selected_editable_objects=[b]):
        bpy.ops.object.modifier_apply(modifier=b.modifiers[0].name)
    mw = b.matrix_world.copy(); b.parent = None; b.data.transform(mw); b.matrix_world.identity()
    b.data.transform(Matrix.Translation((0, -.05, 0)))      # torso centred over the game's joint line
    for o in new: o.hide_set(True)
    return b

def g2b(p): return Vector((p[0], -p[2], p[1]))
def b2g(v): return (v.x, v.z, -v.y)
def auv(reg, u, v):
    r = REG[reg]; u = min(1, max(0, u)); v = min(1, max(0, v))
    return (r[0]+u*(r[2]-r[0]), r[1]+v*(r[3]-r[1]))
def lathe_u(dx, dz):
    """the game's lathe convention: u = .5 at the front, seam at the back"""
    return (math.atan2(-dx, -dz) % (2*math.pi))/(2*math.pi)

def classify(ob, img):
    """per face: (region, game-bone) from the source texture colour + the old weights"""
    W, H = img.size; px = img.pixels[:]
    def col(u, v):
        x = min(W-1, max(0, int(u % 1*W))); y = min(H-1, max(0, int(v % 1*H))); i = (y*W+x)*4; return px[i:i+3]
    uvl = ob.data.uv_layers.active.data; names = [g.name for g in ob.vertex_groups]
    out = []
    for p in ob.data.polygons:
        cs = [col(*uvl[l].uv) for l in p.loop_indices]
        cu = sum(uvl[l].uv.x for l in p.loop_indices)/p.loop_total; cv = sum(uvl[l].uv.y for l in p.loop_indices)/p.loop_total
        cs.append(col(cu, cv))
        h, s, v = colorsys.rgb_to_hsv(*[sum(c[i] for c in cs)/len(cs) for i in range(3)])
        w = {}
        for vi in p.vertices:
            for g in ob.data.vertices[vi].groups: w[names[g.group]] = w.get(names[g.group], 0)+g.weight
        dom = max(w, key=w.get)
        if dom.startswith(('foot', 'toe')): reg = 'shoe'
        elif dom == 'head':
            reg = 'hair' if (v > .76 and s < .47 and not (cu < .27 and cv > .68)) else 'skin'
        elif s >= .6 and v > .25:
            reg = 'skin' if dom.startswith(('upper_arm', 'forearm', 'hand')) else 'top'   # bare arms, like before
        elif v < .25: reg = 'bot'                                                      # the skirt -> her denim
        else: reg = 'skin'
        out.append((reg, dom))
    return out

def build(src_name='sec_baked'):
    src = bpy.data.objects[src_name]
    img = next(n.image for n in src.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and n.image.size[0])
    cls = classify(src, img)
    coll = bpy.data.collections.get('TORII2') or bpy.data.collections.new('TORII2')
    if coll.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects): bpy.data.objects.remove(o)

    bm = bmesh.new(); bm.from_mesh(src.data)
    uvl = bm.loops.layers.uv.active; dl = bm.verts.layers.deform.active
    names = [g.name for g in src.vertex_groups]
    bm.faces.ensure_lookup_table()
    # region extents (game y) for the v coordinate of each band
    ext = {}
    for f, (reg, dom) in zip(bm.faces, cls):
        for v in f.verts:
            y = v.co.z; lo, hi = ext.get(reg, (9, -9)); ext[reg] = (min(lo, y), max(hi, y))
    def axis(dom, reg):
        """the vertical axis a band is wrapped around: the limb's own, or the body's"""
        if reg in ('top', 'bot'): return (0.0, -0.01)
        if reg == 'hair' or dom in ('head', 'neck'): return (0.0, -0.03)
        g = GMAP.get(dom, 'body')
        if g[:-2] in ('arm', 'elb'): return (ARM[1 if g[-1] == 'p' else -1][0], -0.04)
        if g[:-2] in ('leg', 'kn'): return (LEG[1 if g[-1] == 'p' else -1][0], -0.0)
        return (0.0, -0.01)
    for f, (reg, dom) in zip(bm.faces, cls):
        ax = axis(dom, reg); lo, hi = ext[reg]
        if reg == 'skin' and GMAP.get(dom, 'body') != 'body':
            lo, hi = -0.0, 2.2
        us = []
        for l in f.loops:
            x, y, z = b2g(l.vert.co)
            us.append(lathe_u(x-ax[0], z-ax[1]))
        if max(us)-min(us) > .5: us = [u+1 if u < .5 else u for u in us]
        if min(us) >= 1: us = [u-1 for u in us]
        for l, u in zip(f.loops, us):
            y = l.vert.co.z; v = (y-lo)/max(1e-4, hi-lo)
            if reg == 'shoe': v = .2+.7*v
            l[uvl].uv = auv(reg, u % 1.0001, v)
        f.material_index = MAT_ATLAS; f.smooth = False
    # re-weight onto the game's joints
    gi = {}
    new_groups = sorted(set(GMAP.values()))
    for v in bm.verts:
        acc = {}
        for k, w in v[dl].items():
            g = GMAP.get(names[k], 'body'); acc[g] = acc.get(g, 0)+w
        v[dl].clear()
        t = sum(acc.values()) or 1
        for g, w in acc.items(): v[dl][new_groups.index(g)] = w/t
    me = bpy.data.meshes.new('TorBody'); bm.to_mesh(me); bm.free()
    body = bpy.data.objects.new('TorBody', me); coll.objects.link(body)
    for g in new_groups: body.vertex_groups.new(name=g)

    # shoes become their own meshes so gear can swap them
    shoes = {}
    for s in (-1, 1):
        bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
        keep = [f for f, (reg, dom) in zip(bm.faces, cls) if reg == 'shoe' and (f.calc_center_median().x > 0) == (s > 0)]
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in set(keep)], context='FACES_ONLY')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        sm = bpy.data.meshes.new('shoe_'+SN[s]); bm.to_mesh(sm); bm.free()
        so = bpy.data.objects.new('shoe_'+SN[s], sm); coll.objects.link(so)
        for g in new_groups: so.vertex_groups.new(name=g)
        shoes[s] = so
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f, (reg, dom) in zip(bm.faces, cls) if reg == 'shoe'], context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    dl = bm.verts.layers.deform.active

    # her face is FLAT, PS1 style: the nose and the sculpting in front are pressed into one
    # gently curved front, and her (low-res photo) face texture goes straight on from the front
    hix0 = new_groups.index('head')
    hv = [v for v in bm.verts if v[dl].get(hix0, 0) > .99]
    hc = sum((v.co for v in hv), Vector())/len(hv)
    zs = [v.co.z for v in hv]; hc.z = (min(zs)+max(zs))/2+.01
    for v in hv:
        x, y, z = b2g(v.co)
        if abs(x) < FACE_BOX[1] and FACE_BOX[2]-.02 < y < FACE_BOX[3]+.01 and z > .05:
            fz = FACE_Z-2.2*x*x-max(0, FACE_BOX[2]+.05-y)*.5       # rounds off at the sides and the chin
            v.co = g2b((x, y, min(z, fz) if y > FACE_BOX[3]-.03 else fz))
    uv0 = bm.loops.layers.uv.active; sk = REG['skin']
    inskin = lambda f: all(sk[0] <= l[uv0].uv.x <= sk[2] and sk[1] <= l[uv0].uv.y <= sk[3] for l in f.loops)
    front = [f for f in bm.faces if inskin(f) and all(v[dl].get(hix0, 0) > .99 for v in f.verts)
             and all(b2g(v.co)[2] > .03 for v in f.verts)]
    dec = bmesh.new()
    vmap = {}
    for f in front:
        vs = []
        for v in f.verts:
            if v not in vmap: vmap[v] = dec.verts.new(v.co+Vector((0, -.004, 0)))   # a hair in front
            vs.append(vmap[v])
        try: dec.faces.new(vs)
        except ValueError: pass
    bmesh.ops.subdivide_edges(dec, edges=dec.edges[:], cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(dec, faces=dec.faces[:])
    duv = dec.loops.layers.uv.new('UVMap')
    def face_uv(co):
        x, y, z = b2g(co)
        return (.5+x/(2*FACE_BOX[1]), (y-FACE_BOX[2])/(FACE_BOX[3]-FACE_BOX[2]))
    drop = []
    for f in dec.faces:
        uvs = [face_uv(l.vert.co) for l in f.loops]
        if all(not (0 <= u <= 1 and 0 <= v <= 1) for u, v in uvs): drop.append(f); continue
        f.material_index = MAT_FACE
        for l, (u, v) in zip(f.loops, uvs): l[duv].uv = auv('face', u, v)
    bmesh.ops.delete(dec, geom=drop, context='FACES_ONLY')
    ddl = dec.verts.layers.deform.verify()
    for v in dec.verts: v[ddl][new_groups.index('head')] = 1.0
    dme = bpy.data.meshes.new('decal'); dec.to_mesh(dme); dec.free()
    bm.to_mesh(me); bm.free()

    # box braids (square PS1 tubes, bending at the mid joint) and a bead on each
    br = bmesh.new(); buv = br.loops.layers.uv.new('UVMap'); bdl = br.verts.layers.deform.verify()
    all_groups = new_groups+['br%d' % i for i in range(NB)]+['mid%d' % i for i in range(NB)]
    for g in all_groups[len(new_groups):]: body.vertex_groups.new(name=g)
    hcg = b2g(hc)
    global BRAID
    yr = hcg[1]-.035                                            # ear level
    hair_r = {}
    hix = new_groups.index('head')
    for v in me.vertices:
        if sum(g.weight for g in v.groups if g.group == hix) > .99 and abs(v.co.z-yr) < .06:
            d = b2g(v.co); a = math.atan2(d[0]-hcg[0], -(d[2]-hcg[2]))
            hair_r[round(a, 1)] = max(hair_r.get(round(a, 1), 0), math.hypot(d[0]-hcg[0], d[2]-hcg[2]))
    rmax = max(hair_r.values())
    def rad_at(a):
        near = [r for k, r in hair_r.items() if abs(((k-a+math.pi) % (2*math.pi))-math.pi) < .35]
        return max(near) if near else rmax
    BRAID = []
    for i in range(NB):
        a = -1.85+i*(3.7/(NB-1)); r = rad_at(a)*.97
        BRAID.append((hcg[0]+math.sin(a)*r, yr, hcg[2]-math.cos(a)*r))
    def ring(c, y, r, n, ang0, wts):
        row = []
        for k in range(n):
            th = ang0+2*math.pi*k/n
            v = br.verts.new(g2b((c[0]+r*math.sin(th), y, c[2]+r*math.cos(th))))
            for g, w in wts.items(): v[bdl][all_groups.index(g)] = w
            row.append(v)
        return row
    for i, c in enumerate(BRAID):
        a, b = 'br%d' % i, 'mid%d' % i
        # each braid starts tucked up under the hair and hangs from its root
        dx, dz = c[0]-hcg[0], c[2]-hcg[2]; L = math.hypot(dx, dz) or 1
        tuck = (c[0]-dx/L*.03, 0, c[2]-dz/L*.03)
        prof = [(.07, .02, {a: 1}, tuck), (0.0, .028, {a: 1}, None), (-.13, .031, {a: 1}, None), (-.27, .03, {a: 1}, None),
                (-.40, .028, {a: .5, b: .5}, None), (-.53, .026, {b: 1}, None), (-.64, .022, {b: 1}, None)]
        rows = []
        for y, r, w, at in prof:
            p = at or c
            rows.append((y, ring((p[0], 0, p[2]), c[1]+y, r, 4, math.pi/4, w)))
        vb = lambda y: min(.95, 1+(y+.4)/.27 if y < -.4 else 1+min(0, y)/.4)
        for (y0, r0), (y1, r1) in zip(rows[1:], rows[:-1]):
            for k in range(4):
                f = br.faces.new((r0[k], r0[(k+1) % 4], r1[(k+1) % 4], r1[k]))
                u0, u1 = k/4, (k+1)/4
                for l, uv in zip(f.loops, ((u0, vb(y0)), (u1, vb(y0)), (u1, vb(y1)), (u0, vb(y1)))): l[buv].uv = auv('braid', *uv)
        endc = br.verts.new(g2b((c[0], c[1]-.67, c[2]))); endc[bdl][all_groups.index(b)] = 1.0
        last = rows[-1][1]
        for k in range(4):
            f = br.faces.new((last[(k+1) % 4], last[k], endc))
            for l in f.loops: l[buv].uv = auv('braid', .5, .05)
        # the bead: a little hexagonal crystal
        bc = (c[0], c[1]-.70, c[2]); hx = [br.verts.new(g2b((bc[0]+.036*math.sin(t), bc[1], bc[2]+.036*math.cos(t))))
                                          for t in (j*math.pi/3 for j in range(6))]
        tp = br.verts.new(g2b((bc[0], bc[1]+.045, bc[2]))); bt = br.verts.new(g2b((bc[0], bc[1]-.045, bc[2])))
        for v in hx+[tp, bt]: v[bdl][all_groups.index(b)] = 1.0
        for j in range(6):
            for f in (br.faces.new((hx[j], hx[(j+1) % 6], tp)), br.faces.new((hx[(j+1) % 6], hx[j], bt))):
                f.material_index = MAT_BEAD
                for l in f.loops: l[buv].uv = (.5, .5)
    bme = bpy.data.meshes.new('braids'); br.to_mesh(bme); br.free()
    # merge decal + braids into the body
    parts = []
    for nm, msh, groups in (('decal', dme, new_groups), ('braids', bme, all_groups)):
        o = bpy.data.objects.new(nm, msh); coll.objects.link(o)
        for g in groups: o.vertex_groups.new(name=g)
        parts.append(o)
    mats = materials()
    for o in [body]+parts+list(shoes.values()):
        if len(o.data.materials): o.data.materials.clear()   # careful: clear() resets every face to slot 0
        for m in mats: o.data.materials.append(m)
        for p in o.data.polygons: p.use_smooth = False
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win, active_object=body, object=body, selected_objects=[body]+parts,
                                   selected_editable_objects=[body]+parts):
        bpy.ops.object.join()
    for so in shoes.values():
        while len(so.data.materials) > 1: so.data.materials.pop()
    rig = make_rig(coll)
    for o in [body]+list(shoes.values()):
        o.parent = rig; o.modifiers.new('rig', 'ARMATURE').object = rig
    return coll

def materials():
    img = bpy.data.images.get('atlas.png')
    out = []
    for name, col, alpha in (('atlas', (1, 1, 1, 1), False), ('face', (1, 1, 1, 1), True), ('bead', (.48, .97, 1, 1), False)):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True; nt = m.node_tree
        bs = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'); bs.inputs['Base Color'].default_value = col
        for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE']: nt.nodes.remove(n)
        if img and name != 'bead':
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = img; t.interpolation = 'Closest'
            nt.links.new(t.outputs['Color'], bs.inputs['Base Color'])
            if alpha: nt.links.new(t.outputs['Alpha'], bs.inputs['Alpha'])
        out.append(m)
    return out

def make_rig(coll):
    """one bone per joint group buildGirl() makes, at the same spot, no rest rotation"""
    arm_d = bpy.data.armatures.new('ToriiRig'); arm = bpy.data.objects.new('ToriiRig', arm_d); coll.objects.link(arm)
    J = {'body': ((0, 0, 0), None), 'head': (HEAD, 'body')}
    for s in (-1, 1):
        n = SN[s]
        J['arm_'+n] = (ARM[s], 'body'); J['elb_'+n] = ((ARM[s][0], ARM[s][1]-.28, 0), 'arm_'+n)
        J['leg_'+n] = (LEG[s], 'body'); J['kn_'+n] = ((LEG[s][0], LEG[s][1]-.40, 0), 'leg_'+n)
    for i, c in enumerate(BRAID):
        J['br%d' % i] = (c, 'head'); J['mid%d' % i] = ((c[0], c[1]-.4, c[2]), 'br%d' % i)
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win, active_object=arm, object=arm, selected_objects=[arm]):
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode='EDIT')
        for name, (p, par) in J.items():
            eb = arm_d.edit_bones.new(name); eb.head = g2b(p); eb.tail = g2b(p)+Vector((0, 0, .06)); eb.roll = 0
        for name, (p, par) in J.items():
            if par: arm_d.edit_bones[name].parent = arm_d.edit_bones[par]
        bpy.ops.object.mode_set(mode='OBJECT')
    return arm

def export(path, coll_name='TORII2'):
    coll = bpy.data.collections[coll_name]
    win = bpy.context.window_manager.windows[0]
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in coll.objects: o.select_set(True)
    with bpy.context.temp_override(window=win):
        # no normals: the game makes flat PS1 normals itself (toNonIndexed + computeVertexNormals)
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_image_format='NONE',
                                  export_animations=False, export_skins=True, export_yup=True, export_apply=False,
                                  export_normals=False, export_texcoords=True, export_materials='EXPORT')
