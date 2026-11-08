# The Diamond Back's looks (7.2 applyBikeLook2): from level 15 a pink neon underglow + a cyan strip under
# the frame (NEON DIAMOND BACK, the level-15 milestone card says it), and whichever bike part she wears:
# lastik = neon tyres in the item's colour, zil = a gold bell on the bar, zincirb = a chrome chainring,
# far = a neon headlight (a real SpotLight3D that lights the road at night). Small code meshes on the
# bike model (bike.glb, +z forward like 7.2), flat colours, glow where 7.2 glowed. Rebuilt only when
# her level-15 state or the worn part changes (player.stats_changed fires on equip / unequip / level-up).
# Dev: --bikelook=lastik,zil,zincirb,far,glow shows those parts whatever the save says (screenshots only).
class_name BikeLook
extends Node

var bike: Node3D
var player: Node
var _key := "?"
var _glow: Node3D
var _bell: MeshInstance3D
var _ring: MeshInstance3D
var _lamp: Node3D
var _spot: SpotLight3D
var _tires: Array = []
var _dev: Array = []
var _t := 0.0

func setup(b: Node3D, p: Node) -> void:
	bike = b; player = p
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bikelook="): _dev = Array(a.substr(11).split(","))
	for n in ["wheel_f", "wheel_b"]:
		var w := b.find_child(n, true, false)
		if w == null: continue
		for c in w.get_children():        # the tyre is the wheel's big torus (the spokes are thin boxes)
			if c is MeshInstance3D and c.mesh and c.mesh.get_aabb().size.x > .9: _tires.append(c); break
	_build()
	if p and p.has_signal("stats_changed"): p.stats_changed.connect(refresh)
	refresh()

# what she wears in the bike slot: [base id, colour] (7.2's eqItem('bike') / GB(part))
func _part() -> Array:
	var eq = SaveBridge.data.get("eq")
	var gear = SaveBridge.data.get("gear")
	if not (eq is Dictionary) or not (gear is Array) or eq.get("bike") == null: return ["", Color.WHITE]
	for it in gear:
		if it is Dictionary and int(it.get("u", -1)) == int(eq["bike"]):
			for g in Stats.data()["GEARBASE"]:
				if g["id"] == it.get("b") and g["s"] == "bike": return [str(g["id"]), Color(str(g["col"]))]
	return ["", Color.WHITE]

func _col(id: String) -> Color:
	for g in Stats.data()["GEARBASE"]: if g["id"] == id: return Color(str(g["col"]))
	return Color.WHITE

func refresh() -> void:
	if not is_instance_valid(bike): return
	var neon := Stats.lvl() >= 15
	var pr := _part()
	var pid: String = pr[0]; var pc: Color = pr[1]
	var key := "%s|%s|%s" % [neon, pid, pc.to_html()]
	if not _dev.is_empty(): key = "dev"
	if key == _key: return
	_key = key
	var has := func(id: String) -> bool: return _dev.has(id) if not _dev.is_empty() else pid == id
	_glow.visible = _dev.has("glow") if not _dev.is_empty() else neon
	var tc := pc if pid == "lastik" else _col("lastik")
	for t in _tires:
		if has.call("lastik"):
			var m := StandardMaterial3D.new(); m.albedo_color = tc
			m.emission_enabled = true; m.emission = tc * .5      # 7.2: emissive = colour x .5
			t.material_override = m
		else: t.material_override = null
	_bell.visible = has.call("zil")
	_ring.visible = has.call("zincirb")
	_lamp.visible = has.call("far")
	_t = 0.0

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or not _lamp or not _lamp.visible: return
	_t = .5
	var night: float = SkyCycle.me.neon if SkyCycle.me else 1.0     # 1 = full night, 0 = noon
	_spot.visible = night > .2
	_spot.light_energy = 3.2 * night

# ---------------------------------------------------------------- the parts (7.2 sizes and places)
func _mat(c: Color, glow := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif glow > 0.0: m.emission_enabled = true; m.emission = c * glow
	return m

# a soft additive glow (7.2's AdditiveBlending planes / addGlow sprites)
func _glow_mat(c: Color, a: float, plateau := .5) -> StandardMaterial3D:
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, plateau, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, .8), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new(); tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(.5, .5); tex.fill_to = Vector2(1, .5); tex.width = 32; tex.height = 32
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false; m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex; m.albedo_color = Color(c.r, c.g, c.b, a)
	return m

func _mi(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build() -> void:
	# NEON DIAMOND BACK: a pink pool on the road under the bike + a cyan strip below the frame
	_glow = Node3D.new(); _glow.name = "Underglow"; bike.add_child(_glow)
	var pm := PlaneMesh.new(); pm.size = Vector2(1.3, 2.6)
	_mi(pm, _glow_mat(Color("ff2dd0"), .75, .45), Vector3(0, .06, 0), _glow)
	var strip := BoxMesh.new(); strip.size = Vector3(.05, .05, 1.2)
	_mi(strip, _mat(Color("7bf7ff"), 0.0, true), Vector3(0, .55, 0), _glow)
	# zil: a gold half-dome bell on the left of the handlebar
	var sm := SphereMesh.new(); sm.radius = .06; sm.height = .06; sm.is_hemisphere = true
	sm.radial_segments = 10; sm.rings = 3
	_bell = _mi(sm, _mat(_col("zil"), .35), Vector3(-.22, 1.33, .72), bike)
	# zincirb: a chrome chainring beside the crank (axis along x, like the cranks turn)
	var tm := TorusMesh.new(); tm.inner_radius = .12; tm.outer_radius = .16; tm.rings = 18; tm.ring_segments = 6
	_ring = _mi(tm, _mat(_col("zincirb"), .25), Vector3(.06, .5, .05), bike)
	_ring.rotation.z = PI / 2
	var mm := _ring.material_override as StandardMaterial3D; mm.metallic = .8; mm.roughness = .25
	# far: a lamp under the bar — housing in the item's neon colour, a warm white face, a halo and a spot
	_lamp = Node3D.new(); _lamp.name = "Headlight"; _lamp.position = Vector3(0, 1.18, .84); bike.add_child(_lamp)
	var hb := BoxMesh.new(); hb.size = Vector3(.16, .12, .08)
	_mi(hb, _mat(_col("far"), .6), Vector3(0, 0, -.01), _lamp)
	var lb := BoxMesh.new(); lb.size = Vector3(.12, .08, .02)
	_mi(lb, _mat(Color("fff2d0"), 0.0, true), Vector3(0, 0, .035), _lamp)
	var q := QuadMesh.new(); q.size = Vector2(.8, .8)
	var hm := _glow_mat(Color("fff0c0"), .8, .15); hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mi(q, hm, Vector3(0, 0, .1), _lamp)
	_spot = SpotLight3D.new(); _spot.light_color = Color("fff0c0"); _spot.spot_range = 22.0; _spot.spot_angle = 26.0
	_spot.spot_attenuation = .8; _spot.shadow_enabled = false; _spot.light_energy = 3.2
	_spot.position = Vector3(0, 0, .12)
	_spot.basis = Basis.looking_at(Vector3(0, -.3, 1).normalized(), Vector3.UP)   # forward (+z) and down at the road
	_lamp.add_child(_spot)
	_glow.visible = false; _bell.visible = false; _ring.visible = false; _lamp.visible = false
