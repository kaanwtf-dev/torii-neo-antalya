# The city moving on its own: 7.2's traffic (buildWorld cars + carModel + updateCars), the blimp with its
# "TÜRKÇE ÖĞREN!" neon ad, the 9 circling birds (updateSky) and the plane circling over the rooftops (plane2).
# The 7.2 export baked the blimp and the birds into city.glb wherever they were at that moment (frozen in
# mid-air), so setup() cuts those triangles back out of the city chunks first and then adds moving ones.
# Cars: six neon-lit cars drive back and forth on the road grid (x/z lines -120..40, lanes ±2.2, 9-14 m/s,
# x roads stop at 92 so they never drive onto the sand). Walking in front of one hurts (8, knockback, toast
# with dikkat, teaches araba) — NEW: a honk first when she's in its path, and a roll gets her through.
# They freeze while a menu/lesson is up, like the monsters. Head/tail light halos glow only after dark.
class_name WorldLife
extends Node

static var me: WorldLife

const CAR_COLS := [Color("d94f6b"), Color("4fd9c3"), Color("e8c34f"), Color("8a6bff"), Color("5fb0ff"), Color("3a3a48")]
const LINES := [-120.0, -80.0, -40.0, 0.0, 40.0]
const BIRD_COL := Color("2a2438")
# where the export froze the blimp (chunk_3_-2) and the birds (Material_10 wing quads above the roofs)
const BLIMP_BOX := AABB(Vector3(185, 70, 76), Vector3(52, 42, 42))

var world: Node3D
var player: Node3D
var cars: Array = []        # {g, ax, line, lane, u, dir, sp, halos, honk, gy, gt}
var birds: Array = []       # {g, w: [l, r], ph, r, h, sp, cx, cz}
var blimp: Node3D
var plane: Node3D
var _plane_lights: Array = []
var _halo_mats: Array = []
var _t := 0.0
var _hurt_cd := 0.0
var _told := false
var _view_far := 0.0        # Quality's VIEW far plane when shorter than FAR (0 = FAR, nothing changes)

func _init() -> void: me = self

func setup(w: Node3D, p: Node3D) -> void:
	world = w; player = p
	var cut := _strip_baked(w)
	if cut > 0: print("WorldLife: cut %d frozen sky triangles out of the city" % cut)
	for i in 6: _car(i)
	for i in 9: _bird()
	_blimp()
	_plane()
	set_view_far(_view_far)

# the plane and the birds don't take fog, so at VIEW MID/NEAR they'd pop at the far plane: fade them out first
# (the blimp orbits ~150 m from the camera, always inside the shortest view)
func set_view_far(far: float) -> void:
	_view_far = far if far < 399.0 else 0.0
	var roots: Array = [plane] if plane else []
	for b in birds: roots.append(b["g"])
	for r in roots:
		for mi in (r as Node).find_children("*", "GeometryInstance3D", true, false):
			var g := mi as GeometryInstance3D
			g.visibility_range_end = maxf(0.0, _view_far - 40.0)   # +-30 m fade either way stays inside the far plane
			g.visibility_range_end_margin = 30.0 if _view_far > 0.0 else 0.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if _view_far > 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

# ---------------------------------------------------------------- cutting the frozen copies out
func _strip_baked(root: Node) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for c in x.get_children(): stack.append(c)
		if not (x is MeshInstance3D): continue
		var mi := x as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh): continue
		var box := mi.global_transform * mi.get_aabb()
		if box.end.y < 45.0: continue
		n += _strip_mesh(mi, box)
	return n

func _is_bird_mat(m: Material) -> bool:
	if not (m is BaseMaterial3D): return false
	var b := m as BaseMaterial3D
	if b.resource_name == "Material_10": return true
	var c := b.albedo_color
	return b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and absf(c.r - .165) < .02 and absf(c.g - .141) < .02 and absf(c.b - .22) < .02

func _strip_mesh(mi: MeshInstance3D, box: AABB) -> int:
	var src := mi.mesh as ArrayMesh
	var xf := mi.global_transform
	var in_blimp := box.intersects(BLIMP_BOX)
	var plan := []          # per surface: filtered index array or null (= unchanged)
	var cut := 0
	for s in src.get_surface_count():
		var mat := src.surface_get_material(s)
		var bird := _is_bird_mat(mat) and box.end.x > -300.0
		if not bird and not in_blimp:
			plan.append(null); continue
		var arr := src.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if idx.is_empty(): plan.append(null); continue
		var keep := PackedInt32Array()
		for i in range(0, idx.size(), 3):
			var a := xf * verts[idx[i]]; var b := xf * verts[idx[i + 1]]; var c := xf * verts[idx[i + 2]]
			var lo := minf(a.y, minf(b.y, c.y))
			var drop := false
			if bird and lo > 45.0 and a.x > -300.0: drop = true
			if in_blimp and lo > 70.0 and BLIMP_BOX.has_point(a) and BLIMP_BOX.has_point(b) and BLIMP_BOX.has_point(c): drop = true
			if drop: cut += 1
			else: keep.append(idx[i]); keep.append(idx[i + 1]); keep.append(idx[i + 2])
		if keep.size() == idx.size(): plan.append(null); continue
		arr[Mesh.ARRAY_INDEX] = keep
		plan.append(arr)
	if cut == 0: return 0
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr = plan[s]
		if arr == null: arr = src.surface_get_arrays(s)
		elif (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): continue
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	mi.mesh = out
	return cut

# ---------------------------------------------------------------- building
static func _mat(col: Color, unlit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = col
	if unlit: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.roughness = .55
	return m

static func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m; mi.position = at
	parent.add_child(mi); return mi

func _halo(parent: Node3D, at: Vector3, col: Color, size: float) -> MeshInstance3D:
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED; m.disable_fog = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.albedo_color = Color(col, .85)
	m.albedo_texture = SkyCycle.glow_tex(false, 16)
	var mi := MeshInstance3D.new(); mi.mesh = q; mi.material_override = m; mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi); _halo_mats.append(m)
	return mi

# 7.2 carModel(): a tapered body, a four-sided glass cabin, four wheels with rims, bumpers, lights
func _car(i: int) -> void:
	var g := Node3D.new(); g.name = "Car%d" % i; world.add_child(g)
	var paint := _mat(CAR_COLS[i]); paint.metallic = .3; paint.roughness = .35
	_box(g, Vector3(2, .66, 4.3), Vector3(0, .68, 0), paint)
	var nose := _box(g, Vector3(1.8, .2, 1.0), Vector3(0, 1.06, 1.55), paint); nose.rotation.x = .1
	var cm := CylinderMesh.new(); cm.top_radius = .82; cm.bottom_radius = 1.08; cm.height = .6; cm.radial_segments = 4; cm.rings = 1
	var cab := MeshInstance3D.new(); cab.mesh = cm; cab.position = Vector3(0, 1.3, -.2)
	cab.rotation.y = PI / 4; cab.scale = Vector3(.92, 1, 1.52)
	var glass := _mat(Color("2b3350")); glass.metallic = .6; glass.roughness = .2
	cab.material_override = glass; g.add_child(cab)
	var tire := _mat(Color("1c1a22")); var rim := _mat(Color("b8bcc8"))
	for wx in [-1.0, 1.0]:
		for wz in [-1.45, 1.45]:
			var wm := CylinderMesh.new(); wm.top_radius = .42; wm.bottom_radius = .42; wm.height = .3; wm.radial_segments = 8
			var w := MeshInstance3D.new(); w.mesh = wm; w.material_override = tire
			w.position = Vector3(wx * .93, .42, wz); w.rotation.z = PI / 2; g.add_child(w)
			var rm := CylinderMesh.new(); rm.top_radius = .24; rm.bottom_radius = .24; rm.height = .31; rm.radial_segments = 6
			var r := MeshInstance3D.new(); r.mesh = rm; r.material_override = rim
			r.position = w.position; r.rotation.z = PI / 2; g.add_child(r)
	var bump := _mat(Color("2a2a30"))
	_box(g, Vector3(2.02, .18, .2), Vector3(0, .44, 2.18), bump)
	_box(g, Vector3(2.02, .18, .2), Vector3(0, .44, -2.18), bump)
	var hl := _mat(Color("fff2b0"), true); var tl := _mat(Color("ff2d3a"), true)
	for s in [-1.0, 1.0]:
		_box(g, Vector3(.4, .16, .08), Vector3(.6 * s, .72, 2.17), hl)
		_box(g, Vector3(.5, .14, .08), Vector3(.62 * s, .74, -2.17), tl)
	var halos := [_halo(g, Vector3(0, .72, 2.35), Color("fff0b0"), 3.4), _halo(g, Vector3(0, .72, -2.3), Color("ff2d3a"), 2.2)]
	# a soft blob shadow
	var sq := QuadMesh.new(); sq.size = Vector2(2.6, 5.0); sq.orientation = PlaneMesh.FACE_Y
	var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; sm.albedo_color = Color(0, 0, 0, .4)
	sm.albedo_texture = SkyCycle.glow_tex(false, 16); sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var sh := MeshInstance3D.new(); sh.mesh = sq; sh.material_override = sm; sh.position.y = .04
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; g.add_child(sh)
	var ax := "x" if i % 2 == 0 else "z"
	var lane: float = [-2.2, 2.2].pick_random()
	cars.append({"g": g, "ax": ax, "line": float(LINES.pick_random()), "lane": lane, "u": randf_range(-150, 80),
		"dir": 1.0 if lane > 0 else -1.0, "sp": randf_range(9, 14), "halos": halos, "honk": 0.0, "gy": 0.0, "gt": 0.0})

func _bird() -> void:
	var b := Node3D.new(); world.add_child(b)
	var m := _mat(BIRD_COL, true); m.disable_fog = true
	var wings := []
	for s in [-1.0, 1.0]:
		var piv := Node3D.new(); b.add_child(piv)
		_box(piv, Vector3(1.5, .1, .45), Vector3(.8 * s, 0, 0), m)
		piv.rotation.z = -.35 * s; wings.append(piv)
	birds.append({"g": b, "w": wings, "ph": randf_range(0, 6), "r": randf_range(45, 150), "h": randf_range(48, 88),
		"sp": randf_range(.09, .2), "cx": randf_range(-90, 90), "cz": randf_range(-90, 90)})

# the blimp: hull, pink fins, a cabin, and the neon ad on both flanks
func _blimp() -> void:
	blimp = Node3D.new(); blimp.name = "Blimp"; world.add_child(blimp)
	var hull_m := _mat(Color("e8d8f0")); hull_m.emission_enabled = true; hull_m.emission = Color("2a1a3a"); hull_m.disable_fog = true
	var sm := SphereMesh.new(); sm.radius = 9; sm.height = 18; sm.radial_segments = 12; sm.rings = 6
	var hull := MeshInstance3D.new(); hull.mesh = sm; hull.material_override = hull_m; hull.scale = Vector3(1, .5, 2.5)
	blimp.add_child(hull)
	var fin_m := _mat(Color("ff5fa2")); fin_m.disable_fog = true
	_box(blimp, Vector3(.4, 5, 4), Vector3(0, 0, -19), fin_m)
	_box(blimp, Vector3(9, .4, 4), Vector3(0, 0, -19), fin_m)
	var cab_m := _mat(Color("3a3550")); cab_m.disable_fog = true
	_box(blimp, Vector3(2.4, 1.6, 5), Vector3(0, -4.6, 0), cab_m)
	var tex := _text_tex("TÜRKÇE ÖĞREN! 🇹🇷", Color("7bf7ff"))
	for s in [-1.0, 1.0]:
		var q := QuadMesh.new(); q.size = Vector2(22, 4)
		var am := StandardMaterial3D.new(); am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; am.albedo_texture = tex; am.disable_fog = true
		am.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var ad := MeshInstance3D.new(); ad.mesh = q; ad.material_override = am
		ad.position = Vector3(9.2 * s, 0, 0); ad.rotation.y = PI / 2 * s
		blimp.add_child(ad)
	blimp.position = Vector3(0, 105, 0)

# neon words for the blimp: drawn once by a small SubViewport and kept as its texture
func _text_tex(text: String, col: Color) -> Texture2D:
	var vp := SubViewport.new(); vp.size = Vector2i(352, 64); vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new(); l.text = text; l.size = Vector2(352, 64)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 40); l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("1a0630")); l.add_theme_constant_override("outline_size", 10)
	vp.add_child(l); add_child(vp)
	return vp.get_texture()

# a little plane circling high over the rooftops, wing lights blinking
func _plane() -> void:
	plane = Node3D.new(); plane.name = "Plane"; world.add_child(plane)
	var body := _mat(Color("e8e4f0")); body.disable_fog = true
	var stripe := _mat(Color("ff5fa2")); stripe.disable_fog = true
	_box(plane, Vector3(1.4, 1.4, 9), Vector3.ZERO, body)
	_box(plane, Vector3(11, .2, 1.8), Vector3(0, 0, .4), body)
	_box(plane, Vector3(4, .2, 1.2), Vector3(0, 0, -3.8), body)
	_box(plane, Vector3(.2, 2, 1.4), Vector3(0, 1, -3.9), stripe)
	_box(plane, Vector3(1.45, .3, 7), Vector3(0, .1, .2), stripe)
	for s in [-1.0, 1.0]:
		var lm := _mat(Color("ff3b3b") if s < 0 else Color("3dff9e"), true); lm.disable_fog = true
		_plane_lights.append(_box(plane, Vector3(.4, .4, .4), Vector3(5.6 * s, 0, .4), lm))

# ---------------------------------------------------------------- every frame
func _process(dt: float) -> void:
	if world == null: return
	_t += dt
	var cam := world.get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	# the blimp orbits HER slowly, the birds circle their own spots, the plane goes round the city
	if blimp:
		var a := _t * .022
		blimp.global_position = Vector3(cp.x + cos(a) * 145, 92 + sin(_t * .25) * 5, cp.z + sin(a) * 145)
		blimp.rotation.y = -a + PI / 2
	for b in birds:
		b["ph"] = float(b["ph"]) + float(b["sp"]) * dt
		var ph: float = b["ph"]
		var g: Node3D = b["g"]
		g.position = Vector3(float(b["cx"]) + cos(ph) * float(b["r"]), float(b["h"]) + sin(ph * 2) * 4, float(b["cz"]) + sin(ph) * float(b["r"]))
		g.rotation.y = -ph
		var fl := -.35 + sin(_t * 7 + ph) * .5
		b["w"][0].rotation.z = -fl; b["w"][1].rotation.z = fl
	if plane:
		var pa := _t * .05
		plane.position = Vector3(cos(pa) * 170 - 40, 84 + sin(_t * .3) * 3, sin(pa) * 170)
		plane.rotation = Vector3(0, -pa, .25)
		var on := fmod(_t, 1.2) < .15
		for l in _plane_lights: l.visible = on
	# halos only after dark (and with NEON GLOW on)
	var k := SkyCycle.me.neon if SkyCycle.me else 1.0
	var glow := SkyCycle.me.glow_on() if SkyCycle.me else true
	for m in _halo_mats: (m as StandardMaterial3D).albedo_color.a = .85 * k
	for c in cars:
		for h in c["halos"]: h.visible = glow and k > .05
	if Overlay.any(): return
	_hurt_cd -= dt
	_cars(dt)

# 7.2 updateCars(): back and forth along the road lines, bounce at the ends
func _cars(dt: float) -> void:
	var p := player
	var abroad := p != null and p.global_position.x > 400
	for c in cars:
		c["u"] = float(c["u"]) + float(c["sp"]) * float(c["dir"]) * dt
		var hi := 92.0 if c["ax"] == "x" else 150.0
		if c["u"] > hi: c["u"] = hi; c["dir"] = -1.0
		if c["u"] < -195.0: c["u"] = -195.0; c["dir"] = 1.0
		var g: Node3D = c["g"]
		var d: float = c["dir"]
		var x: float; var z: float
		if c["ax"] == "x":
			x = c["u"]; z = float(c["line"]) + float(c["lane"]) * d
			g.rotation.y = PI / 2 if d > 0 else -PI / 2
		else:
			x = float(c["line"]) + float(c["lane"]) * d; z = c["u"]
			g.rotation.y = 0.0 if d > 0 else PI
		c["gt"] = float(c["gt"]) - dt
		if c["gt"] <= 0.0:
			c["gt"] = .3; c["gy"] = _ground(x, z, float(c["gy"]))
		g.position = Vector3(x, float(c["gy"]), z)
		c["honk"] = float(c["honk"]) - dt
		if p == null or abroad or bool(p.get("dead")): continue
		var dx := x - p.global_position.x; var dz := z - p.global_position.z
		if absf(p.global_position.y - g.position.y) > 2.5: continue        # she's up on a balcony or a roof
		# NEW: a honk when she's standing in its path
		var fwd := Vector3(sin(g.rotation.y), 0, cos(g.rotation.y))
		var to_p := Vector3(-dx, 0, -dz)
		if c["honk"] <= 0.0 and to_p.length() < 14.0 and to_p.normalized().dot(fwd) > .85:
			c["honk"] = 3.5
			Bus.emit_ev("sfx", {"name": "honk", "pos": g.position})
		if dx * dx + dz * dz < 5.5 and _hurt_cd <= 0.0 and not bool(p.get("rolling")):
			_hurt_cd = 1.2
			_hit_her(p, Vector3(dx, 0, dz))

func _hit_her(p: Node3D, d: Vector3) -> void:
	var at := p.global_position + d
	if p.has_method("take_hit"): p.take_hit(8, at, "unblockable")
	var away := -d.normalized() if d.length() > .01 else -p.global_transform.basis.z
	if p.has_method("knockback"): p.knockback(away, 9.0)
	else: p.global_position += away * 2.5
	Bus.emit_ev("sfx", {"name": "crash", "pos": at})
	if Fx.me: Fx.me.shake(.25); Fx.me.puff(at + Vector3(0, .8, 0), [Color("ffd66b"), Color("ffffff")], 8, 2.0, 2.0, .4)
	if Lessons.me:
		Lessons.me.hud.toast("🚗 [b]HIT BY A CAR![/b] Turkish: [b]dikkat[/b] = watch out!" + ("" if _told else " [i](roll out of the way: Left Ctrl)[/i]"), 4.0, true)
		Lessons.me.teach("araba")
	_told = true

func _ground(x: float, z: float, keep: float) -> float:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, keep + 3.0, z), Vector3(x, keep - 6.0, z))
	if player is CollisionObject3D: q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit else keep
