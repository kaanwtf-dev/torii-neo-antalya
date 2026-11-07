# Day and night on HER real clock, the sky and the PS1 picture. Ported from 7.2:
#  DAYK / dayState / sunVec / clockH / updateDayNight (the palette by the hour: sky, fog, sun, moon light,
#  ambient "hemi", neon), paintSky + skyGroup (gradient dome, 300 stars, moon + halo, sun + corona, nebula
#  ribbons), the 12 drifting clouds and the shooting star (updateSky), lit windows (winEmit / BLDMATS), the
#  lamp pools + haze cones (_lampPool / _lampCone, additive here like 7.2) and the lamp bulb halos (addGlow),
#  the Trader Joe's dawn (skyDawn / dawnMix / #dawnO), and the PS1 picture (PS1P / drawFrame: 15-bit colour
#  through a 4x4 ordered dither, plus #grade and #scan) as one canvas_item shader on the 3D view.
# Night keeps the blue-hour look Kaan approved (main.gd's old fixed colours); day/dawn/dusk come from DAYK.
# NIGHT GRADE lives here (save `gGrade`, toggle_grade()); GRAFİK and NEON GLOW are Menus' (gGfx / gGlow).
# Bus: emits "night" {on} when night starts/ends (and once at the start), "gfx" {grade} when the grade flips.
# Dev: --hour=13.5 pins the clock.
class_name SkyCycle
extends Node

static var me: SkyCycle

# h, zenith, upper, horizon, fog, sunCol, sunI, hemiSky, hemiGnd, hemiI, neon   (7.2 DAYK, exact)
const DAYK := [
	[0, 0x02040f, 0x0a1636, 0x26305a, 0x161e3a, 0xaac0ff, .00, 0x6f86c8, 0x1a1826, .85, 1.00],
	[4, 0x040818, 0x0e1a40, 0x2e3866, 0x1a2444, 0xaac0ff, .00, 0x7088cc, 0x1c1a2a, .85, 1.00],
	[5.4, 0x241a52, 0x6b3a72, 0xd8735e, 0x6b4358, 0xffb27a, .22, 0xb89ad8, 0x4a3a48, .95, .75],
	[6.6, 0x4a6ba8, 0xa88ab0, 0xffb27a, 0xa8848a, 0xffd2a0, .60, 0xbcd0f0, 0x6b5a52, .95, .35],
	[9, 0x2f6bb8, 0x7fb0da, 0xc8dcf0, 0xb8cbd8, 0xfff2d8, .80, 0x9ec8f0, 0x7a6f60, .9, .08],
	[13, 0x1e63c8, 0x6fa8e8, 0xd8e8f5, 0xc6d8e6, 0xffffff, .92, 0xa8d2ff, 0x8a7f6c, .95, .00],
	[16.5, 0x2a63b0, 0x7fa8d8, 0xd0d8e0, 0xbcc8d2, 0xfff0d0, .78, 0x9ec2ea, 0x7a6f60, .9, .10],
	[18.6, 0x3a4a90, 0xb0708a, 0xff9a5c, 0xb0707a, 0xffa060, .55, 0xc09ad0, 0x5a4048, 1.00, .45],
	[19.8, 0x101a50, 0x3a2a6a, 0xc8566a, 0x4a3a5a, 0xff7a6a, .12, 0x8a86c8, 0x2a2436, .90, .85],
	[21, 0x02040f, 0x0a1636, 0x26305a, 0x161e3a, 0xaac0ff, .00, 0x6f86c8, 0x1a1826, .85, 1.00],
	[24, 0x02040f, 0x0a1636, 0x26305a, 0x161e3a, 0xaac0ff, .00, 0x6f86c8, 0x1a1826, .85, 1.00],
]
# the blue-hour night Kaan signed off on (main.gd's old fixed environment)
const NIGHT_FOG := Color(.12, .15, .3)
const NIGHT_UP := Color(.07, .09, .22)
const NIGHT_FOG_D := .025
const DAY_FOG_D := .006
const MOON_COL := Color(.6, .68, 1)
const MOON_E := .55
const FOG_DAWN := Color("9a5a6e")

var world: Node3D
var env: Environment
var sun: DirectionalLight3D
var moon_l: DirectionalLight3D
var lamps: Array = []
var _lamp_e: Array = []
var cam: Camera3D
var box: SubViewportContainer
var ps1: ShaderMaterial

var hour := 0.0                  # the hour the sky shows (her clock, or the dawn mission's 6:12)
var neon := 1.0                  # 7.2's st.neon: 1 = full night, 0 = noon
var night := false
var dawn_mix := 0.0
var dawn_target := 0.0
var _pin_h := -1.0
var _t := 0.0
var _sent := false
var _last_h := -99.0
var _st := {}

# sky bits
var _sky: Node3D                  # follows the camera, scaled to sit inside the far plane
var _dome_mat: ShaderMaterial
var _star_mat: StandardMaterial3D
var _moon: MeshInstance3D
var _moon_halo: MeshInstance3D
var _sun_disc: MeshInstance3D
var _sun_halo: MeshInstance3D
var _nebula: Array = []
var _clouds: Array = []           # {m, ox, oz, sp}
var _cloud_mat: StandardMaterial3D
var _shoot: MeshInstance3D
var _shoot_mat: StandardMaterial3D
var _shoot_t := 6.0
var _shoot_v := Vector3.ZERO
var _shoot_age := 0.0
# the city's night materials
var _win_mats: Array = []         # lit-room windows (emission texture)
var _pool_mat: BaseMaterial3D
var _cone_mat: BaseMaterial3D
var _halo_mm: MultiMeshInstance3D
var _halo_mat: StandardMaterial3D

func _init() -> void: me = self

# ---------------------------------------------------------------- setup
# world: the 3D root; env: main's Environment; sun_light: main's DirectionalLight (it becomes the MOON, keeping
# its blue-hour colour; null = find one under world or make one); lamps: main's street-lamp OmniLights.
func setup(w: Node3D, e: Environment, sun_light: DirectionalLight3D, lamp_list: Array) -> void:
	world = w; env = e
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="): _pin_h = float(a.substr(7))
	moon_l = sun_light
	if moon_l == null:
		for c in w.get_children():
			if c is DirectionalLight3D: moon_l = c; break
	if moon_l == null:
		moon_l = DirectionalLight3D.new(); moon_l.light_color = MOON_COL; moon_l.light_energy = MOON_E
		moon_l.rotation = Vector3(-.9, .6, 0); w.add_child(moon_l)
	moon_l.shadow_enabled = false
	sun = DirectionalLight3D.new(); sun.name = "Sun"; sun.shadow_enabled = false; sun.light_energy = 0.0
	w.add_child(sun)
	lamps = lamp_list
	for l in lamps: _lamp_e.append(float(l.light_energy) if l is Light3D else 2.2)
	if env:
		env.background_mode = Environment.BG_COLOR
		env.fog_enabled = true; env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_sky_affect = 0.0
	_build_sky()
	_scan_city(w)
	_build_halos()
	Bus.on("mission_done", func(_d): _dawn_forced = false; dawn_target = 0.0)
	_tick(true)

# main hands over the 3D view: the PS1 shader goes on the SubViewportContainer (its pixel size stays Menus')
func attach_view(container: SubViewportContainer, camera: Camera3D = null) -> void:
	box = container
	if camera: cam = camera
	ps1 = make_ps1_material()
	box.material = ps1
	_tick(true)

# 7.2's PS1P pass + #grade + #scan + #dawnO, for the SubViewportContainer that shows the 3D
static func make_ps1_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform float dither_on = 1.0;
uniform float grade = 1.0;
uniform float scan = 1.0;
uniform float dawn = 0.0;
float b2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float b4(vec2 a){ return b2(0.5 * a) * 0.25 + b2(a); }
void fragment(){
	vec3 c = texture(TEXTURE, UV).rgb;
	// PlayStation 15-bit colour through a 4x4 ordered dither, per 3D pixel
	if (dither_on > 0.5) {
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
		float d = (b4(px) - 0.47) / 31.0;
		c = floor(clamp(c + d, 0.0, 1.0) * 31.0 + 0.5) / 31.0;
	}
	// #grade: vignette, blue hour up top, sodium warmth at street level
	vec2 cc = vec2(0.5, 0.44);
	vec2 q = (UV - cc) / vec2(0.5, 0.56);
	float r = length(q) / 1.4142;
	float va = r < 0.42 ? 0.0 : (r < 0.78 ? mix(0.0, 0.42, (r - 0.42) / 0.36) : mix(0.42, 0.72, clamp((r - 0.78) / 0.22, 0.0, 1.0)));
	c = mix(c, vec3(0.022, 0.006, 0.055), va * grade);
	float y = UV.y;
	float ta = y < 0.38 ? mix(0.14, 0.0, y / 0.38) : 0.0;
	c = mix(c, vec3(0.157, 0.275, 0.667), ta * grade);
	float wa = y < 0.8 ? 0.0 : mix(0.05, 0.07, (y - 0.8) / 0.2);
	wa = y > 0.38 && y < 0.8 ? mix(0.0, 0.05, (y - 0.38) / 0.42) : wa;
	c = mix(c, vec3(1.0, 0.63, 0.31), wa * grade);
	// #dawnO: the pink 5 AM wash
	vec3 dc = y < 0.55 ? mix(vec3(1.0, 0.59, 0.35), vec3(1.0, 0.35, 0.55), y / 0.55) : mix(vec3(1.0, 0.35, 0.55), vec3(1.0, 0.78, 0.47), (y - 0.55) / 0.45);
	float da = y < 0.55 ? mix(0.28, 0.16, y / 0.55) : mix(0.16, 0.1, (y - 0.55) / 0.45);
	c = mix(c, dc, da * dawn);
	// #scan: thin dark lines every 4 window pixels
	if (mod(FRAGCOORD.y, 4.0) < 1.0) c *= 1.0 - 0.055 * scan;
	COLOR = vec4(c, 1.0);
}
"""
	var m := ShaderMaterial.new(); m.shader = s
	return m

# ---------------------------------------------------------------- the sky (7.2 skyGroup, built at 7.2's sizes)
func _unlit(col: Color, alpha := false, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = col; m.disable_fog = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if alpha or add:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if add: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

# a soft round glow / ring texture (a clean radial gradient, nothing noisy)
static func glow_tex(ring := false, size := 32) -> GradientTexture2D:
	var g := Gradient.new()
	if ring:
		g.offsets = PackedFloat32Array([0.0, .54, .6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	else:
		g.offsets = PackedFloat32Array([0.0, .35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, .45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new(); t.gradient = g; t.width = size; t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(.5, .5); t.fill_to = Vector2(1, .5)
	return t

func _build_sky() -> void:
	_sky = Node3D.new(); _sky.name = "Sky"; world.add_child(_sky)
	# the dome: a gradient by height (zenith / upper / horizon / fog), no texture at all
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, shadows_disabled;
uniform vec3 zen; uniform vec3 up; uniform vec3 hor; uniform vec3 fogc;
varying vec3 d;
void vertex(){ d = VERTEX; }
void fragment(){
	float s = acos(clamp(normalize(d).y, -1.0, 1.0)) / 3.14159;   // 0 top, .5 horizon, 1 straight down
	vec3 c = s < 0.38 ? mix(zen, up, s / 0.38) : (s < 0.5 ? mix(up, hor, (s - 0.38) / 0.12) : mix(hor, fogc, clamp((s - 0.5) / 0.06, 0.0, 1.0)));
	ALBEDO = c;
}
"""
	_dome_mat = ShaderMaterial.new(); _dome_mat.shader = sh; _dome_mat.render_priority = -100
	var sm := SphereMesh.new(); sm.radius = 420; sm.height = 840; sm.radial_segments = 16; sm.rings = 12
	var dome := MeshInstance3D.new(); dome.mesh = sm; dome.material_override = _dome_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _sky.add_child(dome)
	# 300 stars
	var rng := RandomNumberGenerator.new(); rng.seed = 7272
	var pts := PackedVector3Array()
	for i in 300:
		var th := rng.randf_range(0, TAU); var ph := rng.randf_range(.12, 1.2)
		pts.append(Vector3(400 * sin(ph) * cos(th), 400 * cos(ph), 400 * sin(ph) * sin(th)))
	var am := ArrayMesh.new(); var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = pts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	_star_mat = _unlit(Color("cfd8ff"), true); _star_mat.use_point_size = true; _star_mat.point_size = 1.6
	var stars := MeshInstance3D.new(); stars.mesh = am; stars.material_override = _star_mat; _sky.add_child(stars)
	# moon + halo, sun + corona
	var mm := SphereMesh.new(); mm.radius = 16; mm.height = 32; mm.radial_segments = 12; mm.rings = 6
	_moon = MeshInstance3D.new(); _moon.mesh = mm; _moon.material_override = _unlit(Color("ffeccf")); _sky.add_child(_moon)
	_moon_halo = _billboard(68, Color(1, .88, .75, .13), glow_tex(true), false); _sky.add_child(_moon_halo)
	var sd := SphereMesh.new(); sd.radius = 19; sd.height = 38; sd.radial_segments = 14; sd.rings = 7
	_sun_disc = MeshInstance3D.new(); _sun_disc.mesh = sd; _sun_disc.material_override = _unlit(Color("fff4d0")); _sky.add_child(_sun_disc)
	_sun_halo = _billboard(140, Color(1, .89, .63, .16), glow_tex(false), true); _sky.add_child(_sun_halo)
	# nebula ribbons over the horizon (pink, cyan, purple)
	var nc: Array[Color] = [Color("ff2d78"), Color("7bf7ff"), Color("b06bff")]
	for i in 3:
		var q := QuadMesh.new(); q.size = Vector2(620, 120)
		var nb := MeshInstance3D.new(); nb.mesh = q
		var nm := _unlit(Color(nc[i], .07), true); nm.cull_mode = BaseMaterial3D.CULL_DISABLED
		nm.albedo_texture = glow_tex(false); nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR   # soft ribbon, no hard edges
		nb.material_override = nm
		nb.position = Vector3(0, 120 + i * 40, -330 + i * 24); nb.rotation.z = (i - 1) * .13
		_sky.add_child(nb); _nebula.append(nb)
	# 12 clouds: soft purple puffs drifting with her (in the world, not the dome)
	_cloud_mat = _unlit(Color(1, 1, 1, .5), true)
	_cloud_mat.albedo_texture = _cloud_tex(); _cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_cloud_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	for i in 12:
		var q := QuadMesh.new(); q.size = Vector2(rng.randf_range(70, 150), rng.randf_range(24, 44))
		var c := MeshInstance3D.new(); c.mesh = q; c.material_override = _cloud_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf_range(0, TAU); var r := rng.randf_range(40, 150)
		c.position.y = rng.randf_range(62, 118)
		world.add_child(c)
		_clouds.append({"m": c, "ox": cos(a) * r, "oz": sin(a) * r, "sp": rng.randf_range(1.2, 3.6)})
	# the shooting star
	var bm := BoxMesh.new(); bm.size = Vector3(.35, .35, 9)
	_shoot_mat = _unlit(Color(1, 1, 1, .9), true)
	_shoot = MeshInstance3D.new(); _shoot.mesh = bm; _shoot.material_override = _shoot_mat; _shoot.visible = false
	world.add_child(_shoot)

func _billboard(size: float, col: Color, tex: Texture2D, add: bool) -> MeshInstance3D:
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	var m := _unlit(col, true, add); m.albedo_texture = tex; m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var mi := MeshInstance3D.new(); mi.mesh = q; mi.material_override = m
	return mi

# 7.2's cloudTex: 26 soft blobs on a 128x64 canvas (fixed seed, so every run looks the same)
func _cloud_tex() -> ImageTexture:
	var w := 64; var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new(); rng.seed = 26
	var acc := PackedFloat32Array(); acc.resize(w * h)
	for i in 26:
		var cx := rng.randf_range(7, w - 7); var cy := rng.randf_range(9, h - 5); var r := rng.randf_range(3.5, 8.5)
		for y in h:
			for x in w:
				var dd := Vector2(x - cx, y - cy).length() / r
				if dd < 1.0: acc[y * w + x] = maxf(acc[y * w + x], .5 * (1.0 - dd))
	for y in h:
		for x in w:
			var a := acc[y * w + x]
			if a > 0: img.set_pixel(x, y, Color(.75, .67, .88, minf(1.0, a * 1.6)))
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- the city's night bits
# lit windows (the 40 facade materials with an emission texture), lamp pools (Material_665) and haze
# cones (Material_666): glTF can't say "additive", so they come in as plain alpha; make them glow again
func _scan_city(n: Node) -> void:
	var seen := {}
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for c in x.get_children(): stack.append(c)
		if not (x is MeshInstance3D): continue
		var mi := x as MeshInstance3D
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			if not (m is BaseMaterial3D) or seen.has(m): continue
			seen[m] = true
			var bm := m as BaseMaterial3D
			var nm := bm.resource_name
			if bm.emission_enabled and bm.emission_texture != null: _win_mats.append(bm)
			elif nm == "Material_665" or _is_lamp(bm, .6): _pool_mat = bm
			elif nm == "Material_666" or _is_lamp(bm, .07): _cone_mat = bm
	for m in [_pool_mat, _cone_mat]:
		if m:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if _pool_mat: _pool_mat.disable_fog = true

func _is_lamp(m: BaseMaterial3D, a: float) -> bool:
	var c := m.albedo_color
	return m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and absf(c.r - 1.0) < .02 and absf(c.g - .68) < .04 and absf(c.a - a) < .02

# 7.2's addGlow on every lamp bulb: one additive billboard each, all in one MultiMesh
func _build_halos() -> void:
	if lamps.is_empty(): return
	var q := QuadMesh.new(); q.size = Vector2(5.5, 5.5)
	_halo_mat = _unlit(Color(1, .69, .38, .85), true, true)
	_halo_mat.albedo_texture = glow_tex(false, 16); _halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = q
	mm.instance_count = lamps.size()
	for i in lamps.size():
		var l: Node3D = lamps[i]
		mm.set_instance_transform(i, Transform3D(Basis(), l.position + Vector3(0, .9, 0)))
	_halo_mm = MultiMeshInstance3D.new(); _halo_mm.name = "LampHalos"; _halo_mm.multimesh = mm
	_halo_mm.material_override = _halo_mat; _halo_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_halo_mm)

# ---------------------------------------------------------------- the clock
static func clock_h() -> float:
	var d := Time.get_time_dict_from_system()
	return float(d["hour"]) + float(d["minute"]) / 60.0 + float(d["second"]) / 3600.0

static func _hex(n: int) -> Color:
	return Color(((n >> 16) & 255) / 255.0, ((n >> 8) & 255) / 255.0, (n & 255) / 255.0)

static func day_state(h: float) -> Dictionary:
	var i := 0
	while i < DAYK.size() - 2 and float(DAYK[i + 1][0]) <= h: i += 1
	var A: Array = DAYK[i]; var B: Array = DAYK[i + 1]
	var t := clampf((h - float(A[0])) / maxf(.0001, float(B[0]) - float(A[0])), 0.0, 1.0)
	return {"zen": _hex(A[1]).lerp(_hex(B[1]), t), "up": _hex(A[2]).lerp(_hex(B[2]), t),
		"hor": _hex(A[3]).lerp(_hex(B[3]), t), "fog": _hex(A[4]).lerp(_hex(B[4]), t),
		"sunC": _hex(A[5]).lerp(_hex(B[5]), t), "sunI": lerpf(A[6], B[6], t),
		"hemiS": _hex(A[7]).lerp(_hex(B[7]), t), "hemiG": _hex(A[8]).lerp(_hex(B[8]), t),
		"hemiI": lerpf(A[9], B[9], t), "neon": lerpf(A[10], B[10], t)}

# up at 6am, highest at 13:00, down at 20:00
static func sun_vec(h: float) -> Vector3:
	var a := (h - 6.0) / 13.4 * PI
	return Vector3(cos(a) * .86, sin(a), -.42)

# 7.2 partOfDay: what she'd call this hour, in Turkish [tr, en, emoji]
static func part_of_day(h: float) -> Array:
	if h < 5.2: return ["gece", "night", "🌙"]
	if h < 7: return ["şafak", "dawn", "🌅"]
	if h < 11: return ["sabah", "morning", "🌤"]
	if h < 15: return ["öğle", "midday", "☀️"]
	if h < 18.4: return ["ikindi", "afternoon", "🌇"]
	if h < 20.4: return ["akşam", "evening", "🌆"]
	return ["gece", "night", "🌙"]

func time_of_day() -> float:
	var c := _pin_h if _pin_h >= 0.0 else clock_h()
	return lerpf(c, 6.2, dawn_mix) if dawn_mix > .5 else c

# 7.2 skyDawn(on): the Trader Joe's mission's 5 AM sky (missions.json start.dawn). Also picked up by itself.
var _dawn_forced := false
func dawn(on: bool) -> void: _dawn_forced = on; dawn_target = 1.0 if on else 0.0

# ---------------------------------------------------------------- every frame
func _process(dt: float) -> void:
	if world == null: return
	if cam == null or not is_instance_valid(cam): cam = world.get_viewport().get_camera_3d()
	_dawn_watch()
	dawn_mix = move_toward(dawn_mix, dawn_target, dt * .35)
	if ps1:
		ps1.set_shader_parameter("dawn", minf(dawn_target * .85, dawn_mix * 1.4))
	_t -= dt
	if _t <= 0.0: _t = 1.0; _tick(false)
	_follow(dt)

# the dawn mission, without missions.gd having to call anyone: its data says start.dawn = true
func _dawn_watch() -> void:
	var M = Missions.me
	if M == null: return
	var on := _dawn_forced
	if int(M.step) >= 0 and M.m is Dictionary:
		var st = M.m.get("start", {})
		on = on or (st is Dictionary and bool(st.get("dawn", false)))
	dawn_target = 1.0 if on else 0.0

# 7.2 updateDayNight(): once a second, push one dayState() through everything that cares about the hour
func _tick(force: bool) -> void:
	var h := time_of_day(); hour = h
	if not force and absf(h - _last_h) < .003 and _sent: return
	_last_h = h
	var st := day_state(h); _st = st
	var k: float = st["neon"]; neon = k
	# sky dome: DAYK by day, the approved blue hour by night
	var fogc: Color = (st["fog"] as Color).lerp(NIGHT_FOG, k).lerp(FOG_DAWN, dawn_mix * .5)
	var upc: Color = (st["up"] as Color).lerp(NIGHT_UP, k * .6)
	_dome_mat.set_shader_parameter("zen", st["zen"])
	_dome_mat.set_shader_parameter("up", upc)
	_dome_mat.set_shader_parameter("hor", st["hor"])
	_dome_mat.set_shader_parameter("fogc", fogc)
	if env:
		env.background_color = fogc
		env.fog_light_color = fogc
		env.fog_density = lerpf(DAY_FOG_D, NIGHT_FOG_D, k)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = (st["hemiS"] as Color).lerp(st["hemiG"], .35)
		env.ambient_light_energy = float(st["hemiI"]) * 1.05
	# sun and moon ride the same arc, half a day apart
	var v := sun_vec(h)
	_sun_disc.position = v * 380; _sun_halo.position = _sun_disc.position
	_sun_disc.visible = v.y > -.12; _sun_halo.visible = _sun_disc.visible
	_moon.position = -v * 380; _moon_halo.position = _moon.position
	_moon.visible = -v.y > -.12; _moon_halo.visible = _moon.visible
	_aim(sun, Vector3(v.x, maxf(.06, v.y), v.z))
	sun.light_color = st["sunC"]; sun.light_energy = maxf(0.0, st["sunI"]); sun.visible = sun.light_energy > .01
	_aim(moon_l, Vector3(-v.x, maxf(.35, -v.y), -v.z))
	moon_l.light_color = MOON_COL; moon_l.light_energy = MOON_E * k; moon_l.visible = k > .02
	_star_mat.albedo_color.a = clampf(k * 1.15 - .15, 0.0, 1.0)
	for i in _nebula.size(): (_nebula[i].material_override as StandardMaterial3D).albedo_color.a = .07 * (.35 + .65 * k)
	_cloud_mat.albedo_color = Color(1, .97, .98).lerp(Color(1, 1, 1), k)
	_cloud_mat.albedo_color.a = .5
	# neon, lamps and lit windows only after dark
	for m in _win_mats: (m as BaseMaterial3D).emission_energy_multiplier = k
	if _pool_mat: _pool_mat.albedo_color.a = .6 * k
	if _cone_mat: _cone_mat.albedo_color.a = .07 * k
	for i in lamps.size():
		if is_instance_valid(lamps[i]): lamps[i].light_energy = float(_lamp_e[i]) * k
	if _halo_mat: _halo_mat.albedo_color.a = .85 * k
	if _halo_mm: _halo_mm.visible = glow_on() and k > .03
	# the grade has no business being strong at noon
	if ps1:
		var g := 1.0 if grade_on() else 0.0
		ps1.set_shader_parameter("dither_on", g)
		ps1.set_shader_parameter("grade", g * (.18 + .82 * k))
		ps1.set_shader_parameter("scan", g * (.25 + .75 * k))
	# night starts / ends (with a little hysteresis so dusk doesn't flicker it)
	var was := night
	if night and k < .45: night = false
	elif not night and k > .55: night = true
	if night != was or not _sent:
		_sent = true
		Bus.emit_ev("night", {"on": night})

func _aim(l: DirectionalLight3D, to_light: Vector3) -> void:
	var d := -to_light.normalized()
	var upv := Vector3.UP if absf(d.y) < .98 else Vector3.FORWARD
	l.global_transform = Transform3D(Basis.looking_at(d, upv), Vector3.ZERO)

# the sky is re-centred on her camera every frame (7.2 followSky), clouds drift relative to her
func _follow(dt: float) -> void:
	if cam == null: return
	var cp := cam.global_position
	_sky.global_position = Vector3(cp.x, 0, cp.z)
	_sky.scale = Vector3.ONE * maxf(.25, cam.far * .92 / 420.0)
	for c in _clouds:
		c["ox"] = float(c["ox"]) + float(c["sp"]) * dt
		if c["ox"] > 170.0: c["ox"] = -170.0
		var m: MeshInstance3D = c["m"]
		m.global_position = Vector3(cp.x + float(c["ox"]), m.global_position.y, cp.z + float(c["oz"]))
	# shooting stars, only once it's properly dark
	_shoot_t -= dt
	if _shoot_t <= 0 and not _shoot.visible and neon > .6:
		_shoot.visible = true; _shoot_age = 0.0
		_shoot.global_position = cp + Vector3(randf_range(-260, 260), randf_range(150, 230), randf_range(-260, 260))
		_shoot_v = Vector3(randf_range(-90, 90), -randf_range(30, 60), randf_range(-90, 90))
		_shoot.look_at(_shoot.global_position + _shoot_v, Vector3.UP)
	if _shoot.visible:
		_shoot_age += dt
		_shoot.global_position += _shoot_v * dt
		_shoot_mat.albedo_color.a = maxf(0.0, .9 - _shoot_age * .6)
		if _shoot_age > 1.5: _shoot.visible = false; _shoot_t = randf_range(7, 22)
	elif _shoot_t <= 0: _shoot_t = 3.0

# ---------------------------------------------------------------- NIGHT GRADE (7.2 optGrade)
# GRAFİK (pixel size) and NEON GLOW (bloom) belong to Menus (save gGfx / gGlow); the grade is ours, save
# `gGrade` (new, Godot only, default on). The lamp/car halos hide only once she's switched NEON GLOW off.
func grade_on() -> bool: return SaveBridge.data.get("gGrade", true) != false
func glow_on() -> bool: return SaveBridge.data.get("gGlow", true) != false

func toggle_grade() -> String:
	SaveBridge.data["gGrade"] = not grade_on()
	_tick(true)
	Bus.emit_ev("gfx", {"grade": grade_on()})
	return grade_label()
func grade_label() -> String: return "🎞 NIGHT GRADE: " + ("ON" if grade_on() else "OFF")

# what the HUD clock can show: "14:05 · öğle · midday ☀️"
func clock_text() -> String:
	var h := time_of_day()
	var pd := part_of_day(h)
	return "%02d:%02d · %s · %s %s" % [int(h) % 24, int(fmod(h, 1.0) * 60.0), pd[0], pd[1], pd[2]]
