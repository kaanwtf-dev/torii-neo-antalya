# Paint Torii with the sheet itself: project its front / back / side views onto the mesh (blended by
# which way each surface faces) and bake that into one PS1 texture on her UVs.
import bpy, math
K = 2.2/455
SHEET_W, SHEET_H = 1448, 1086
# view: (centre column on the sheet, how game coords map to the image's x, normal weight axis)
# image column = cx + sign*coord/k, image row = r0 - height/k; 'head' views take over above the neck
KH = .37/229                     # the head close-ups: hair top (row 571) to chin (row 800) = 2.2 -> 1.83
R0H = 571+2.2/KH
VIEWS = {
    'front': (202.5, 'x', +1, ('y', -1), K, 497.0, 'body'),   # sees normals pointing Blender -y (her front)
    'back': (746.5, 'x', -1, ('y', +1), K, 497.0, 'body'),
    'side1': (498.0, 'y', -1, ('x', -1), K, 497.0, 'body'),   # camera at her right
    'side2': (1017.0, 'y', +1, ('x', +1), K, 497.0, 'body'),
    'headfront': (151.0, 'x', +1, ('y', -1), KH, R0H, 'head'),
    'headside': (443.0, 'y', -1, ('x', -1), KH, R0H, 'head'),
    'headside2': (443.0, 'y', -1, ('x', +1), KH, R0H, 'head'),   # her left side = the right close-up mirrored (same depth axis)
    'headback': (746.5, 'x', -1, ('y', +1), K, 497.0, 'head'),    # no back close-up: the body view's back
}
HEAD_FROM = 1.80                 # height where the close-ups take over

def bake(obj_name='ToriiSheet', sheet_png=None, size=512, out_png=None, power=3.0):
    ob = bpy.data.objects[obj_name]; me = ob.data
    win = bpy.context.window_manager.windows[0]
    # UVs: one smart-projected map, generous margins so the bake can bleed
    if 'bake' not in me.uv_layers: me.uv_layers.new(name='bake')
    me.uv_layers.active = me.uv_layers['bake']
    vl = bpy.context.view_layer
    for o in vl.objects: o.select_set(False)
    ob.hide_set(False); ob.select_set(True); vl.objects.active = ob
    with bpy.context.temp_override(window=win, active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=.012, area_weight=.4)
        bpy.ops.object.mode_set(mode='OBJECT')
    sheet = bpy.data.images.load(sheet_png, check_existing=True)
    tgt = bpy.data.images.get('torii_tex') or bpy.data.images.new('torii_tex', size, size, alpha=False)
    if tgt.size[0] != size: tgt.scale(size, size)
    m = bpy.data.materials.get('torii_bake') or bpy.data.materials.new('torii_bake')
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    N = nt.nodes.new; L = nt.links.new
    out = N('ShaderNodeOutputMaterial'); em = N('ShaderNodeEmission'); L(em.outputs[0], out.inputs['Surface'])
    tc = N('ShaderNodeTexCoord'); sep = N('ShaderNodeSeparateXYZ'); L(tc.outputs['Object'], sep.inputs[0])
    geo = N('ShaderNodeNewGeometry'); nsep = N('ShaderNodeSeparateXYZ'); L(geo.outputs['Normal'], nsep.inputs[0])
    def math_(op, a, b=None):
        n = N('ShaderNodeMath'); n.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: L(v, n.inputs[i])
        return n.outputs[0]
    col_sum = None; w_sum = None
    head = math_('MINIMUM', math_('MAXIMUM', math_('DIVIDE', math_('SUBTRACT', sep.outputs['Z'], HEAD_FROM), .03), 0.0), 1.0)
    body = math_('SUBTRACT', 1.0, head)
    for name, (cx, axis, sign, (naxis, nsign), k, r0, region) in VIEWS.items():
        coord = sep.outputs['X' if axis == 'x' else 'Y']
        px = math_('ADD', math_('MULTIPLY', coord, sign/k), cx)                     # sheet column
        py = math_('SUBTRACT', r0, math_('DIVIDE', sep.outputs['Z'], k))            # sheet row
        u = math_('DIVIDE', px, SHEET_W); v = math_('SUBTRACT', 1.0, math_('DIVIDE', py, SHEET_H))
        cmb = N('ShaderNodeCombineXYZ'); L(u, cmb.inputs[0]); L(v, cmb.inputs[1])
        tex = N('ShaderNodeTexImage'); tex.image = sheet; tex.interpolation = 'Closest'; tex.extension = 'EXTEND'
        L(cmb.outputs[0], tex.inputs['Vector'])
        nv = nsep.outputs['X' if naxis == 'x' else 'Y']
        w = math_('ADD', math_('POWER', math_('MAXIMUM', math_('MULTIPLY', nv, nsign), 0.0), power), .002)
        w = math_('MULTIPLY', w, head if region == 'head' else body)
        mix = N('ShaderNodeVectorMath'); mix.operation = 'SCALE'; L(tex.outputs['Color'], mix.inputs[0]); L(w, mix.inputs['Scale'])
        if col_sum is None: col_sum, w_sum = mix.outputs[0], w
        else:
            a = N('ShaderNodeVectorMath'); a.operation = 'ADD'; L(col_sum, a.inputs[0]); L(mix.outputs[0], a.inputs[1]); col_sum = a.outputs[0]
            w_sum = math_('ADD', w_sum, w)
    norm = N('ShaderNodeVectorMath'); norm.operation = 'SCALE'; L(col_sum, norm.inputs[0]); L(math_('DIVIDE', 1.0, w_sum), norm.inputs['Scale'])
    L(norm.outputs[0], em.inputs['Color'])
    img_node = N('ShaderNodeTexImage'); img_node.image = tgt; nt.nodes.active = img_node; img_node.select = True
    keep = [s.material for s in ob.material_slots]
    me.materials.clear(); me.materials.append(m)
    sc = bpy.context.scene
    old_engine = sc.render.engine
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 1; sc.cycles.device = 'CPU'
    sc.render.bake.margin = 6; sc.render.bake.use_clear = True
    with bpy.context.temp_override(window=win, active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.bake(type='EMIT')
    sc.render.engine = old_engine
    if out_png:
        tgt.filepath_raw = out_png; tgt.file_format = 'PNG'; tgt.save()
    # show the result on the model: one plain material with the baked texture
    fm = bpy.data.materials.get('torii') or bpy.data.materials.new('torii')
    fm.use_nodes = True; fnt = fm.node_tree
    bs = next(n for n in fnt.nodes if n.type == 'BSDF_PRINCIPLED')
    for n in [n for n in fnt.nodes if n.type == 'TEX_IMAGE']: fnt.nodes.remove(n)
    t = fnt.nodes.new('ShaderNodeTexImage'); t.image = tgt; t.interpolation = 'Closest'
    fnt.links.new(t.outputs['Color'], bs.inputs['Base Color'])
    bs.inputs['Roughness'].default_value = 1.0
    me.materials.clear(); me.materials.append(fm)
    return tgt
