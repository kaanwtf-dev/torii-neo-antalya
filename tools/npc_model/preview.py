# Textured orthographic previews of the NPC bases next to the sheet (for checking by eye).
import bpy, math
from mathutils import Vector

def render(ob_name, img_name, out, view='front', h=2.2, res=(300, 520)):
    sc = bpy.context.scene
    try: sc.render.engine = 'BLENDER_WORKBENCH'
    except TypeError: pass
    sh = sc.display.shading; sh.light = 'FLAT'; sh.color_type = 'TEXTURE'
    sc.render.film_transparent = False
    cam_d = bpy.data.cameras.get('npccam') or bpy.data.cameras.new('npccam')
    cam = bpy.data.objects.get('npccam') or bpy.data.objects.new('npccam', cam_d)
    if cam.name not in sc.collection.objects: sc.collection.objects.link(cam)
    cam_d.type = 'ORTHO'; cam_d.ortho_scale = h*1.08
    ob = bpy.data.objects[ob_name]; base = ob.matrix_world.translation
    for o in sc.objects:
        if o.type == 'MESH': o.hide_render = o.name != ob_name
    d = {'front': (Vector((0, -10, 0)), (math.pi/2, 0, 0)), 'back': (Vector((0, 10, 0)), (math.pi/2, 0, math.pi)),
         'side': (Vector((10, 0, 0)), (math.pi/2, 0, math.pi/2)), 'q34': (Vector((-7, -7, 0)), (math.pi/2, 0, -math.pi/4))}[view]
    cam.location = base+d[0]+Vector((0, 0, h/2)); cam.rotation_euler = d[1]; sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res; sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'; sc.render.filepath = out
    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win): bpy.ops.render.render(write_still=True)
    for o in sc.objects:
        if o.type == 'MESH': o.hide_render = False
