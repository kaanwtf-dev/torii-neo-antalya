# City for the Godot port: the static world exported from the running 7.2 game (GLTFExporter),
# cleaned up in Blender. Run inside Blender (MCP): exec this file, then merge(src_glb, out_glb).
# - de-duplicates the ~2,700 cloned materials (same texture + colour + emission = one material)
# - joins the ~4,800 meshes into one mesh per map chunk (CHUNK metres) so Godot can cull them
#   and draws one call per material per chunk.
import bpy, math
from collections import defaultdict

CHUNK = 60.0

def _key(m):
    if not m or not m.use_nodes: return ('none',)
    nt = m.node_tree
    bs = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    # every image the material uses, wherever it's plugged in (unlit sign materials feed
    # emission/background nodes, not Base Color — missing that merged all signs into one)
    img = tuple(sorted(n.image.name for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image))
    # texture tiling (the game's map.repeat/offset arrive as a Mapping node) must match too
    tiling = tuple(tuple(round(v, 3) for v in n.inputs[s].default_value)
                   for n in nt.nodes if n.type == 'MAPPING' for s in ('Location', 'Rotation', 'Scale'))
    img = (img, tiling)
    unlit = any(n.type in ('BACKGROUND', 'EMISSION') for n in nt.nodes) or 'unlit' in m.name.lower()
    col = tuple(round(v, 2) for v in bs.inputs['Base Color'].default_value) if bs else ()
    em = tuple(round(v, 2) for v in bs.inputs['Emission Color'].default_value) if bs and 'Emission Color' in bs.inputs else ()
    es = round(bs.inputs['Emission Strength'].default_value, 2) if bs and 'Emission Strength' in bs.inputs else 0
    vc = any(n.type in ('VERTEX_COLOR', 'ATTRIBUTE') for n in nt.nodes)
    return (img, col, em, es, m.blend_method if hasattr(m, 'blend_method') else '', vc, unlit)

def merge(src, out):
    for o in list(bpy.data.objects):
        if o.users_collection and o.users_collection[0].name == 'CITY': bpy.data.objects.remove(o)
    coll = bpy.data.collections.get('CITY') or bpy.data.collections.new('CITY')
    if coll.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(coll)
    before = set(bpy.data.objects)
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win):
        bpy.ops.import_scene.gltf(filepath=src)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection): c.objects.unlink(o)
        coll.objects.link(o)
    meshes = [o for o in new if o.type == 'MESH']
    # 1) one material per look
    canon = {}
    n_before = len({s.material for o in meshes for s in o.material_slots if s.material})
    for o in meshes:
        for s in o.material_slots:
            k = _key(s.material)
            canon.setdefault(k, s.material)
            s.material = canon[k]
    # 2) bake transforms, bucket by chunk, join
    buckets = defaultdict(list)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None; o.matrix_world = mw
        if o.data.users > 1: o.data = o.data.copy()
        o.data.transform(o.matrix_world); o.matrix_world.identity()
        if not o.data.vertices: continue
        c = sum((v.co for v in o.data.vertices), o.data.vertices[0].co*0)/len(o.data.vertices)
        buckets[(math.floor(c.x/CHUNK), math.floor(c.y/CHUNK))].append(o)
    for o in new:
        if o.type != 'MESH': bpy.data.objects.remove(o)
    chunks = []
    for (i, j), objs in buckets.items():
        with bpy.context.temp_override(window=win, active_object=objs[0], object=objs[0], selected_objects=objs, selected_editable_objects=objs):
            bpy.ops.object.join()
        objs[0].name = f'chunk_{i}_{j}'; chunks.append(objs[0])
    n_after = len({s.material for o in chunks for s in o.material_slots if s.material})
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in chunks: o.select_set(True)
    with bpy.context.temp_override(window=win):
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_image_format='AUTO',
                                  export_animations=False, export_skins=False, export_yup=True, export_normals=True,
                                  export_materials='EXPORT', export_vertex_color='ACTIVE')
    return {'materials_before': n_before, 'materials_after': n_after, 'chunks': len(chunks),
            'tris': sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in chunks)}
