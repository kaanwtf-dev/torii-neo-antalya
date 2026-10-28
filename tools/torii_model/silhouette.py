# Render orthographic silhouettes of the model at the sheet's exact scale (for comparing with the sheet).
import bpy, math
from mathutils import Vector
K = 2.2/455
VIEWS = {  # name: (crop x0, x1 on the sheet, camera location, rotation)
    'front': ((10, 396), 202.5, (0, -10, 0), (math.pi/2, 0, 0)),
    'side1': ((440, 555), 498.0, (-10, 0, 0), (math.pi/2, 0, -math.pi/2)),
    'back': ((560, 935), 746.5, (0, 10, 0), (math.pi/2, 0, math.pi)),
}
ROWS = (30, 505)

def render(obj_name, out_dir):
    sc = bpy.context.scene
    old = (sc.render.engine, sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.film_transparent)
    try: sc.render.engine = 'BLENDER_WORKBENCH'
    except TypeError: pass
    sh = sc.display.shading
    sh.light = 'FLAT'; sh.color_type = 'SINGLE'; sh.single_color = (1, 1, 1)
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    cam_d = bpy.data.cameras.get('silcam') or bpy.data.cameras.new('silcam')
    cam = bpy.data.objects.get('silcam') or bpy.data.objects.new('silcam', cam_d)
    if cam.name not in sc.collection.objects: sc.collection.objects.link(cam)
    cam_d.type = 'ORTHO'
    hide = [o for o in sc.objects if o.type == 'MESH' and o.name != obj_name and not o.hide_render]
    for o in hide: o.hide_render = True
    h = ROWS[1]-ROWS[0]; yc = (497-(ROWS[0]+ROWS[1])/2)*K
    for name, ((x0, x1), cx, loc, rot) in VIEWS.items():
        w = x1-x0
        sc.render.resolution_x, sc.render.resolution_y = w, h; sc.render.resolution_percentage = 100
        cam_d.ortho_scale = max(w, h)*K
        off = ((x0+x1)/2-cx)*K                       # crop centre relative to the figure axis, along image-right
        loc = Vector(loc); loc.z = yc
        if name == 'front': loc.x = off
        elif name == 'back': loc.x = -off
        else: loc.y = -off
        cam.location = loc; cam.rotation_euler = rot
        sc.camera = cam
        sc.render.filepath = out_dir+'sil_'+name+'.png'
        bpy.ops.render.render(write_still=True)
    for o in hide: o.hide_render = False
    sc.render.engine, sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.film_transparent = old
