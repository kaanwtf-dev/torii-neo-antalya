# Shared feedback, ported from 7.2 and used everywhere:
#  puff()  — pooled billboard particles (dust, hit sparks, kill bursts, confetti), 7.2's puff/updateParts
#  label() — floating text over the world (damage numbers, +XP, speech bubbles), drawn crisp at window
#            resolution like 7.2's HTML labels, not inside the pixelated 3D
#  shake() — camera shake (the player's camera reads shake_t)
#  flash() — the red hurt / pink heal glow round the screen edges (7.2's vig)
#  dark()  — the dark screen for fainting and flights (7.2's #deadO)
# New in the Godot build (PS1 juice: chunky additive pixels, nothing soft or noisy):
#  hit_spark(pos, kind)        — sparks + a flare per hit type: light/heavy/crit/block/parry/magic/burn/poison/shock/hurt
#  slash(from, to, col, pivot) — a glowing ribbon along the weapon arc for .15 s; swipe() builds the arc for you
#  ring(pos, r, sec, col)      — ground tell for enemy AoE: fills up, blinks, pops (ring_stop() cancels it)
#  shockwave(), muzzle(), heal(), level_up(), dust(), splash(), explosion(), flash_screen()
#  hitstop(sec)                — a tiny time_scale dip on big hits; never while a menu/overlay is up
# It also listens on the Bus (enemy_hit, player_hit, enemy_died, level_up, respawn, pickup, player_attack,
# sfx, enemy_tell, quiz_answer) so hits get sparks + hit-stop, swings get trails, jumps/landings/rolls kick
# up dust, ranged shots flash, and enemy wind-ups with a radius get a ground ring, without anyone calling it.
# Set auto = false to switch that off. Calls are de-duped per frame, so a system calling hit_spark itself
# for the same hit costs nothing extra.
class_name Fx
extends Node

static var me: Fx
const CONF := [Color("ff5fa2"), Color("7bf7ff"), Color("ffd66b"), Color("b06bff"), Color("5fff9e")]
const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURP := Color("b06bff")
# hit type -> [spark colours, count, speed, gravity, life, flare size, flare colour]
const HITS := {
	"light": [[Color("ffffff"), Color("ffe04d"), Color("7bf7ff")], 7, 5.0, 9.0, .26, 1.0, Color("fff2b0")],
	"heavy": [[Color("ffd66b"), Color("ff9a3a"), Color("ffffff")], 14, 7.0, 10.0, .34, 1.8, Color("ffb85a")],
	"crit": [[Color("ffd66b"), Color("ff5fa2"), Color("ffffff")], 18, 8.0, 8.0, .4, 2.2, Color("ffd66b")],
	"block": [[Color("7bf7ff"), Color("ffffff")], 8, 4.0, 7.0, .22, 1.0, Color("7bf7ff")],
	"parry": [[Color("7bf7ff"), Color("ffffff"), Color("b06bff")], 16, 7.5, 5.0, .38, 2.6, Color("bffaff")],
	"magic": [[Color("b06bff"), Color("ff5fa2"), Color("7bf7ff")], 10, 3.0, -1.0, .5, 1.4, Color("b06bff")],
	"burn": [[Color("ff9a3a"), Color("ffd66b"), Color("ff5f3a")], 9, 2.2, -3.0, .55, 1.2, Color("ff9a3a")],
	"poison": [[Color("5fff9e"), Color("9aff5f")], 8, 1.8, -1.5, .6, 1.0, Color("5fff9e")],
	"shock": [[Color("ffffff"), Color("7bf7ff")], 12, 9.0, 0.0, .14, 1.6, Color("e8fdff")],
	"hurt": [[Color("ff5fa2"), Color("ff3a5a"), Color("ffffff")], 8, 4.5, 9.0, .28, 1.1, Color("ff8ab8")],
}

var world: Node3D
var cam: Camera3D
var shake_t := 0.0
var auto := true                 # react to Bus hit events by itself
var _parts: Array = []           # {m, v, life, max, grow, g}
var _labs: Array = []            # {n, p, vy, life, max}
var _sparks: Array = []          # {m, v, life, max, g, s0}  additive pixel sparks + flares
var _slashes: Array = []         # {m, im, outer, inner, col, life, max}
var _rings: Array = []           # {m, life, max, kind, r0, r1, col, pop}
var _pillars: Array = []         # {m, life, max}
var _vig: ColorRect
var _vig_a := 0.0
var _scr: ColorRect
var _scr_a := 0.0
var _scr_rate := 4.0
var _dark: ColorRect
var _tw: Tween
var _spark_tex: ImageTexture
var _flare_tex: ImageTexture
var _last_spark := {"f": -1, "p": Vector3.ZERO}
# hit-stop: real-time end (usec) and the time_scale to give back
var _hs_on := false
var _hs_end := 0
var _hs_prev := 1.0
var _tslog := "--tslog" in OS.get_cmdline_user_args()
var _tsl_since := 0

func setup(w: Node3D, camera: Camera3D) -> void:
	me = self; world = w; cam = camera
	var tex := GradientTexture2D.new(); tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(.5, .5); tex.fill_to = Vector2(1, .5); tex.width = 32; tex.height = 32
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0)); tex.gradient = g
	var quad := QuadMesh.new(); quad.size = Vector2(.42, .42)
	for i in 110:
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = tex; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var m := MeshInstance3D.new(); m.mesh = quad; m.material_override = mat; m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_parts.append({"m": m, "v": Vector3.ZERO, "life": 0.0, "max": 1.0, "grow": 0.0, "g": 0.0})
	_build_juice(w)
	# labels + edge glow just above the 3D; the dark screen above every panel but the save screen
	var low := CanvasLayer.new(); low.layer = 2; add_child(low)
	var box := Control.new(); box.set_anchors_preset(Control.PRESET_FULL_RECT); box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low.add_child(box)
	_scr = ColorRect.new(); _scr.set_anchors_preset(Control.PRESET_FULL_RECT); _scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scr.color = Color(1, 1, 1, 0); box.add_child(_scr)
	for i in 16:
		var n := Label.new(); n.visible = false; n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_theme_font_size_override("font_size", 18)
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9)); n.add_theme_constant_override("outline_size", 7)
		box.add_child(n); _labs.append({"n": n, "p": Vector3.ZERO, "vy": 0.0, "life": 0.0, "max": 1.0})
	_vig = ColorRect.new(); _vig.set_anchors_preset(Control.PRESET_FULL_RECT); _vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 col : source_color = vec4(1.0, 0.08, 0.2, 0.75);
uniform float amt = 0.0;
uniform float asp = 1.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	d.x = max(0.0, 1.0 - (1.0 - d.x) * asp);   // widescreen: asp = canvas width / 960, so the side glow keeps its 4:3 width at the real edges
	float e = smoothstep(0.35, 1.25, max(d.x, d.y) * 0.55 + length(d) * 0.5);
	COLOR = vec4(col.rgb, col.a * e * amt);
}"""
	var sm := ShaderMaterial.new(); sm.shader = sh; _vig.material = sm; box.add_child(_vig)
	var top := CanvasLayer.new(); top.layer = 9; add_child(top)
	_dark = ColorRect.new(); _dark.set_anchors_preset(Control.PRESET_FULL_RECT); _dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark.color = Color(20 / 255.0, 0, 10 / 255.0, 0); top.add_child(_dark)
	Bus.on("enemy_hit", _on_enemy_hit)
	Bus.on("player_hit", _on_player_hit)
	Bus.on("enemy_died", _on_enemy_died)
	Bus.on("level_up", _on_level_up)
	Bus.on("respawn", _on_respawn)
	Bus.on("pickup", _on_pickup)
	Bus.on("player_attack", _on_attack)
	Bus.on("sfx", _on_sfx)
	Bus.on("enemy_tell", _on_tell)
	Bus.on("quiz_answer", _on_quiz)

# the PS1 bits: tiny hard-edged textures, additive, no filtering
func _px_tex(size: int, star: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var dx := absf(x - c); var dy := absf(y - c)
			var a := 0.0
			if star:
				if dx + dy <= c * .55: a = 1.0                                   # bright core
				elif (dx < .9 or dy < .9) and dx + dy <= c + .5: a = .75         # the four points
				elif dx + dy <= c * .8: a = .45
			else:
				if dx + dy <= c * .5: a = 1.0
				elif dx + dy <= c + .2: a = .6
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _add_mat(t: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; mat.albedo_texture = t; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

func _build_juice(w: Node3D) -> void:
	_spark_tex = _px_tex(8, false); _flare_tex = _px_tex(16, true)
	var q := QuadMesh.new(); q.size = Vector2(.22, .22)
	for i in 90:
		var m := MeshInstance3D.new(); m.mesh = q; m.material_override = _add_mat(_spark_tex); m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_sparks.append({"m": m, "v": Vector3.ZERO, "life": 0.0, "max": 1.0, "g": 0.0, "s0": 1.0})
	var fq := QuadMesh.new(); fq.size = Vector2(.7, .7)
	for i in 8:                                                  # flares live at the end of the spark pool
		var m := MeshInstance3D.new(); m.mesh = fq; m.material_override = _add_mat(_flare_tex); m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_sparks.append({"m": m, "v": Vector3.ZERO, "life": 0.0, "max": 1.0, "g": 0.0, "s0": 1.0, "flare": true})
	# slash ribbons: one shared additive vertex-colour material
	var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.vertex_color_use_as_albedo = true; rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for i in 8:
		var im := ImmediateMesh.new()
		var m := MeshInstance3D.new(); m.mesh = im; m.material_override = rm; m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_slashes.append({"m": m, "im": im, "outer": PackedVector3Array(), "inner": PackedVector3Array(), "col": Color.WHITE, "life": 0.0, "max": 1.0})
	# ground rings (AoE tells and shockwaves)
	var rs := Shader.new()
	rs.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.37, 0.64, 1.0);
uniform float prog = 0.0;
uniform float alpha = 1.0;
uniform float edge = 0.08;
uniform float fill = 1.0;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	if (d > 1.0) discard;
	float ring = step(1.0 - edge, d);
	float inner = step(d, prog) * 0.28 * fill;
	float front = step(prog - 0.07, d) * step(d, prog) * 0.45 * fill;
	float a = max(ring, inner + front) * alpha;
	a = floor(a * 4.0 + 0.5) / 4.0;
	ALBEDO = col.rgb;
	ALPHA = a;
}"""
	var pm := PlaneMesh.new(); pm.size = Vector2(2, 2)
	for i in 10:
		var mat := ShaderMaterial.new(); mat.shader = rs
		var m := MeshInstance3D.new(); m.mesh = pm; m.material_override = mat; m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_rings.append({"m": m, "life": 0.0, "max": 1.0, "kind": "tell", "r0": 1.0, "r1": 1.0, "col": PINK, "pop": 0.0})
	# level-up pillar: an open 8-sided tube with scrolling bands
	var ps := Shader.new()
	ps.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.84, 0.42, 1.0);
uniform float alpha = 1.0;
uniform float t = 0.0;
uniform float h = 9.0;
varying float hy;
void vertex() { hy = VERTEX.y / h + 0.5; }
void fragment() {
	float band = step(0.5, fract(hy * 7.0 - t * 2.5));
	float a = (0.3 + 0.35 * band) * (1.0 - hy) * alpha;
	a = floor(a * 5.0 + 0.5) / 5.0;
	ALBEDO = col.rgb;
	ALPHA = a;
}"""
	var cyl := CylinderMesh.new(); cyl.top_radius = .8; cyl.bottom_radius = 1.05; cyl.height = 9.0
	cyl.radial_segments = 8; cyl.rings = 1; cyl.cap_top = false; cyl.cap_bottom = false
	for i in 2:
		var mat := ShaderMaterial.new(); mat.shader = ps
		var m := MeshInstance3D.new(); m.mesh = cyl; m.material_override = mat; m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.add_child(m)
		_pillars.append({"m": m, "life": 0.0, "max": 1.0, "at": Vector3.ZERO})

# 7.2: puff(x,y,z,color,n,spread,up,life,grow). color: one Color or an Array to pick from. g = gravity (new)
func puff(at: Vector3, color, n: int, spread: float, up: float, life: float, grow := 0.0, g := 0.0) -> void:
	var c := 0
	for p in _parts:
		if p["life"] > 0: continue
		var m: MeshInstance3D = p["m"]
		var col: Color = color.pick_random() if color is Array else color
		m.material_override.albedo_color = col; m.visible = true
		m.position = at + Vector3(randf_range(-.3, .3), randf_range(-.2, .2), randf_range(-.3, .3))
		m.scale = Vector3.ONE * randf_range(.7, 1.3)
		p["v"] = Vector3(randf_range(-spread, spread), randf_range(up * .4, up), randf_range(-spread, spread))
		p["life"] = life * randf_range(.7, 1.3); p["max"] = p["life"]; p["grow"] = grow; p["g"] = g
		c += 1
		if c >= n: break

# 7.2: label(x,y,z,txt,color,life,bubble). Plain labels float up; bubbles (people talking) stay put
# lift >= 0: the label's BOTTOM sits that many px above the point (a monster's bubble clears its Lv plate)
func label(at: Vector3, text: String, color := Color.WHITE, life := 1.1, bubble := false, lift := -1.0) -> void:
	var L: Dictionary = _labs[0]
	for x in _labs:
		if x["life"] <= 0: L = x; break
	var n: Label = L["n"]
	n.text = text; n.add_theme_color_override("font_color", color)
	n.add_theme_font_size_override("font_size", 15 if bubble else 18)
	if bubble:
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(.08, .03, .15, .86); sb.border_color = color
		sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.set_content_margin_all(7)
		n.add_theme_stylebox_override("normal", sb)
	else: n.remove_theme_stylebox_override("normal")
	n.reset_size()
	L["p"] = at; L["vy"] = 0.0 if bubble else 1.1; L["life"] = life; L["max"] = life; L["lift"] = lift

func shake(t: float) -> void: shake_t = maxf(shake_t, t)

# edge glow. kinds: hurt (red), heal (pink), parry (cyan), crit / gold, poison (green)
func flash(kind := "hurt") -> void:
	var c := Color(1, .47, .75, .55)
	match kind:
		"hurt": c = Color(1, .08, .2, .75)
		"parry": c = Color(.48, .97, 1, .6)
		"crit", "gold": c = Color(1, .84, .42, .55)
		"poison": c = Color(.37, 1, .62, .55)
	_vig.material.set_shader_parameter("col", c)
	_vig.material.set_shader_parameter("asp", Screen.w() / Screen.BASE.x)
	_vig_a = 1.0

# a whole-screen blink (parry, boss kill, level-up). Kept light: strength is the peak alpha
func flash_screen(color := Color.WHITE, strength := .45, sec := .12) -> void:
	_scr.color = Color(color, maxf(_scr.color.a, strength)); _scr_rate = _scr.color.a / maxf(.03, sec)

# fade the screen to `a` (0 = clear) over `secs`; tint = faint (dark red) or travel (near black)
func dark(a: float, secs := 1.0, travel := false) -> void:
	if _tw: _tw.kill()
	var base := Color(5 / 255.0, 2 / 255.0, 12 / 255.0) if travel else Color(20 / 255.0, 0, 10 / 255.0)
	if a > 0: _dark.color = Color(base, _dark.color.a)
	_tw = create_tween(); _tw.tween_property(_dark, "color:a", a, secs)

# ---- sparks ----
func _spark(at: Vector3, col: Color, v: Vector3, life: float, g: float, size := 1.0) -> void:
	for p in _sparks:
		if p["life"] > 0 or p.has("flare"): continue
		var m: MeshInstance3D = p["m"]
		m.material_override.albedo_color = col; m.position = at; m.visible = true
		p["s0"] = size * randf_range(.7, 1.3); m.scale = Vector3.ONE * p["s0"]
		p["v"] = v; p["life"] = life * randf_range(.7, 1.3); p["max"] = p["life"]; p["g"] = g
		return

func _flare(at: Vector3, col: Color, size: float, life := .09) -> void:
	for p in _sparks:
		if p["life"] > 0 or not p.has("flare"): continue
		var m: MeshInstance3D = p["m"]
		m.material_override.albedo_color = col; m.position = at; m.visible = true
		p["s0"] = size; m.scale = Vector3.ONE * size
		p["v"] = Vector3.ZERO; p["life"] = life; p["max"] = life; p["g"] = 0.0
		return

func burst(at: Vector3, cols: Array, n: int, speed: float, g := 8.0, life := .3, dir := Vector3.ZERO, size := 1.0) -> void:
	for i in n:
		var v := Vector3(randf_range(-1, 1), randf_range(-.2, 1), randf_range(-1, 1)).normalized() * speed * randf_range(.5, 1.1)
		if dir != Vector3.ZERO: v = (v * .55 + dir.normalized() * speed * .7)
		v.y += speed * .35
		_spark(at, cols.pick_random(), v, life, g, size)

# one call per hit. kind: light heavy crit block parry magic burn poison shock hurt. dir = the way it flies
func hit_spark(at: Vector3, kind := "light", dir := Vector3.ZERO) -> void:
	var f := Engine.get_process_frames()
	if _last_spark["f"] == f and at.distance_to(_last_spark["p"]) < .45: return
	_last_spark = {"f": f, "p": at}
	var H: Array = HITS.get(kind, HITS["light"])
	burst(at, H[0], H[1], H[2], H[3], H[4], dir)
	_flare(at, H[6], H[5], .1 if kind in ["heavy", "crit", "parry"] else .07)
	match kind:
		"heavy":
			puff(at - Vector3(0, .7, 0), Color("9a94a8"), 5, 1.2, .6, .4, .6); shake(.16)
		"crit":
			shockwave(at - Vector3(0, .9, 0), 2.2, GOLD, .25); shake(.2)
		"parry":
			shockwave(at - Vector3(0, .9, 0), 3.0, CYAN, .3); flash_screen(CYAN, .22, .12); flash("parry"); shake(.12)
		"block":
			shake(.06)

# ---- slashes ----
# a ribbon along an arc. With `pivot` (a Vector3, e.g. her chest) the arc swings round it like a blade;
# without one it's a straight streak that bows a little upward. width = how deep the band is.
func slash(from: Vector3, to: Vector3, color := CYAN, pivot: Variant = null, width := .5, life := .15) -> void:
	var outer := PackedVector3Array(); var inner := PackedVector3Array()
	var N := 12
	if pivot is Vector3:
		var a: Vector3 = from - pivot; var c: Vector3 = to - pivot
		if a.length() < .05 or c.length() < .05: return
		for i in N + 1:
			var t := float(i) / N
			var d := a.slerp(c, t)
			outer.append(pivot + d); inner.append(pivot + d.normalized() * maxf(.05, d.length() - width))
	else:
		var dir := to - from
		if dir.length() < .05: return
		var side := Vector3.UP
		if cam: side = dir.cross(cam.global_position - from).normalized()
		for i in N + 1:
			var t := float(i) / N
			var p := from.lerp(to, t) + Vector3.UP * sin(PI * t) * .25
			outer.append(p); inner.append(p - side * width * (.4 + .6 * sin(PI * t)))
	_ribbon(outer, inner, color, life)

# the arc in front of someone: center = her feet, fwd = where she faces, arc in radians, tilt rolls the
# swing plane (0 = flat sweep, ±1 = diagonal, PI/2 = overhead chop). reverse swings the other way.
func swipe(center: Vector3, fwd: Vector3, radius := 2.0, arc := 2.2, color := CYAN, height := 1.0, tilt := 0.0, reverse := false, life := .15, width := .55) -> void:
	fwd.y = 0.0
	if fwd.length() < .01: return
	fwd = fwd.normalized()
	var up := Vector3.UP.rotated(fwd, tilt)
	var c := center + Vector3.UP * height
	var outer := PackedVector3Array(); var inner := PackedVector3Array()
	var N := 14
	for i in N + 1:
		var t := float(i) / N
		var ang := lerpf(arc * .5, -arc * .5, t) * (-1.0 if reverse else 1.0)
		var d := fwd.rotated(up, ang)
		outer.append(c + d * radius); inner.append(c + d * maxf(.1, radius - width))
	_ribbon(outer, inner, color, life)

func _ribbon(outer: PackedVector3Array, inner: PackedVector3Array, col: Color, life: float) -> void:
	var S: Dictionary = _slashes[0]
	for s in _slashes:
		if s["life"] <= 0: S = s; break
	S["outer"] = outer; S["inner"] = inner; S["col"] = col; S["life"] = life; S["max"] = life
	S["m"].visible = true
	_draw_ribbon(S)

func _draw_ribbon(S: Dictionary) -> void:
	var im: ImmediateMesh = S["im"]; im.clear_surfaces()
	var outer: PackedVector3Array = S["outer"]; var inner: PackedVector3Array = S["inner"]
	var n := outer.size()
	if n < 2: return
	var k: float = 1.0 - S["life"] / S["max"]                 # 0 -> 1 over its life
	var shown := clampf(k / .45, .08, 1.0)                    # the blade sweeps it out, then it fades
	var fade := pow(clampf(S["life"] / S["max"], 0.0, 1.0), .7)
	var last := maxi(1, int(round((n - 1) * shown)))
	var col: Color = S["col"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in last + 1:
		var t := float(i) / last
		var a := fade * (.12 + .88 * t)
		a = floor(a * 4.0 + .5) / 4.0                          # banded, PS1-style
		var hot := col.lerp(Color.WHITE, .55)
		im.surface_set_color(Color(hot.r * a, hot.g * a, hot.b * a, a)); im.surface_add_vertex(outer[i])
		var b := a * .35
		im.surface_set_color(Color(col.r * b, col.g * b, col.b * b, b)); im.surface_add_vertex(inner[i])
	im.surface_end()

# ---- ground rings ----
# an enemy AoE warning: the disc fills over `sec`, blinks near the end, pops. Returns the ring so the
# caller can move it (ring.global_position) or cancel it with ring_stop().
func ring(at: Vector3, radius: float, sec: float, color := PINK) -> MeshInstance3D:
	var R := _free_ring()
	R["kind"] = "tell"; R["life"] = sec + .14; R["max"] = sec; R["col"] = color; R["r0"] = radius; R["r1"] = radius; R["pop"] = .14
	var m: MeshInstance3D = R["m"]
	m.position = at + Vector3(0, .06, 0); m.scale = Vector3(radius, 1, radius); m.visible = true
	var mat: ShaderMaterial = m.material_override
	mat.set_shader_parameter("col", color); mat.set_shader_parameter("prog", 0.0)
	mat.set_shader_parameter("alpha", 1.0); mat.set_shader_parameter("fill", 1.0); mat.set_shader_parameter("edge", clampf(.18 / radius, .03, .2))
	return m

func ring_stop(m: MeshInstance3D) -> void:
	for R in _rings:
		if R["m"] == m: R["life"] = 0.0; m.visible = false

# an expanding outline (parry, crits, stomps, boss landings)
func shockwave(at: Vector3, radius := 2.5, color := CYAN, sec := .3) -> void:
	var R := _free_ring()
	R["kind"] = "wave"; R["life"] = sec; R["max"] = sec; R["col"] = color; R["r0"] = .3; R["r1"] = radius; R["pop"] = 0.0
	var m: MeshInstance3D = R["m"]
	m.position = at + Vector3(0, .07, 0); m.scale = Vector3(.3, 1, .3); m.visible = true
	var mat: ShaderMaterial = m.material_override
	mat.set_shader_parameter("col", color); mat.set_shader_parameter("prog", 0.0)
	mat.set_shader_parameter("alpha", 1.0); mat.set_shader_parameter("fill", 0.0); mat.set_shader_parameter("edge", .14)

func _free_ring() -> Dictionary:
	var best: Dictionary = _rings[0]
	for R in _rings:
		if R["life"] <= 0: return R
		if R["life"] < best["life"]: best = R
	return best

# ---- one-liners for everyone else ----
func muzzle(at: Vector3, dir := Vector3.ZERO, color := GOLD) -> void:
	_flare(at, color, 1.4, .06)
	burst(at, [color, Color.WHITE], 6, 6.0, 0.0, .12, dir, .8)
	puff(at, Color("cabfd8"), 2, .3, .4, .35, .5)

func heal(at: Vector3) -> void:
	for i in 14:
		var a := randf() * TAU
		var p := at + Vector3(cos(a) * .6, randf_range(0, 1.6), sin(a) * .6)
		_spark(p, [Color("5fff9e"), Color("ff9ad0"), Color.WHITE].pick_random(), Vector3(0, randf_range(1.4, 2.6), 0), .9, -.4, .9)

func level_up(at: Vector3) -> void:
	for P in _pillars:
		if P["life"] > 0: continue
		P["life"] = 1.5; P["max"] = 1.5; P["at"] = at
		var m: MeshInstance3D = P["m"]; m.position = at; m.scale = Vector3(1, .05, 1); m.visible = true
		break
	puff(at + Vector3(0, 1.5, 0), CONF, 24, 2.6, 5.0, 1.2, 0.0, 4.0)
	for i in 20:
		var a := i * .9
		_spark(at + Vector3(cos(a) * .9, i * .15, sin(a) * .9), CONF.pick_random(), Vector3(-sin(a) * 1.5, 3.2, cos(a) * 1.5), 1.0, -.5, 1.1)
	flash_screen(GOLD, .3, .4); flash("gold")

func dust(at: Vector3, n := 6, color := Color("9a94a8")) -> void:
	puff(at + Vector3(0, .15, 0), color, n, .9, .7, .45, .7)

func splash(at: Vector3) -> void:
	puff(at + Vector3(0, .1, 0), [Color("bfe8ff"), Color.WHITE, CYAN], 14, 1.6, 4.5, .8, .2, 9.0)
	shockwave(at, 1.8, Color("7bc8ff"), .5)

func explosion(at: Vector3, radius := 3.0) -> void:
	_flare(at + Vector3(0, .8, 0), Color("ffb85a"), 3.2, .14)
	burst(at + Vector3(0, .8, 0), [Color("ffd66b"), Color("ff9a3a"), Color("ff5fa2"), Color.WHITE], 24, 9.0, 9.0, .5)
	puff(at + Vector3(0, .6, 0), [Color("cabfd8"), Color("9a94a8")], 14, 2.4, 2.6, 1.0, 1.0)
	shockwave(at, radius, Color("ff9a3a"), .35)
	shake(.35); flash_screen(Color("ffb85a"), .25, .2)

# hit-stop: freeze the world for a blink so a hit lands. Real time, capped at .25 s, and never while
# a lesson / menu / dialogue is up (and it lets go the moment one opens). Fx is the ONE owner of
# time_scale for hit-pauses (player.hitstop just calls this), so two freezes never fight over it.
func hitstop(sec := .06, scale := .05) -> void:
	if sec <= 0.0 or Overlay.any() or get_tree().paused: return
	var now := Time.get_ticks_usec()
	if not _hs_on:
		_hs_prev = Engine.time_scale if Engine.time_scale >= .5 else 1.0; _hs_on = true
	_hs_end = maxi(_hs_end, now + int(minf(sec, .25) * 1000000.0))
	Engine.time_scale = minf(_hs_prev, scale)

# the end is checked every frame against the real clock (_process). It used to hang on a one-shot timer, and
# that timer could miss: the world then stayed at 5% speed — "slow motion lasts forever", and a victory
# dance at 5% speed looked stuck (Kaan, 11-11)
func _hs_check() -> void:
	if _hs_on and (Time.get_ticks_usec() >= _hs_end or Overlay.any()):
		if not Overlay.is_open("wheel"): Engine.time_scale = _hs_prev   # the wheel opened mid-freeze: it owns the .2 now
		_hs_on = false

# only HER hits freeze time. Bandit's bites, the Josh squad's hits and burn/poison kills happen while she isn't
# swinging, so a freeze for them felt like the world randomly going slow-mo (Kaan, 11-11: "not during weapon selection")
func _hers(d: Dictionary) -> bool:
	return not (str(d.get("src", "")) in ["bandit", "ally", "dot"])

func _exit_tree() -> void:
	if _hs_on: Engine.time_scale = _hs_prev; _hs_on = false

# ---- the Bus: hits feel like hits without anyone asking ----
func _feet(d: Dictionary) -> Vector3:
	var p: Variant = d.get("pos")
	if p is Vector3: return p
	var e: Variant = d.get("enemy")
	if e is Node3D and is_instance_valid(e): return e.global_position
	return Vector3.INF

func _on_enemy_hit(d: Dictionary) -> void:
	if not auto: return
	var p := _feet(d)
	if p == Vector3.INF: return
	var kind := "crit" if d.get("crit", false) else ("heavy" if d.get("heavy", false) else "light")
	var st := str(d.get("status", ""))
	if st in ["burn", "poison", "shock"]: kind = st
	var dir := Vector3.ZERO
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl: dir = (p - pl.global_position).normalized()
	hit_spark(p + Vector3(0, 1.1, 0), kind, dir)
	if _hers(d): hitstop({"crit": .09, "heavy": .07}.get(kind, .035))

func _on_player_hit(d: Dictionary) -> void:
	if not auto: return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var p: Vector3 = pl.global_position if pl else _feet(d)
	if p == Vector3.INF: return
	if d.get("parried", false): hit_spark(p + Vector3(0, 1.2, 0), "parry"); hitstop(.1)
	elif d.get("blocked", false): hit_spark(p + Vector3(0, 1.2, 0), "block"); hitstop(.04)
	elif int(d.get("dmg", 0)) > 0: hit_spark(p + Vector3(0, 1.1, 0), "hurt"); hitstop(.05)

func _on_enemy_died(d: Dictionary) -> void:
	if not auto: return
	var p := _feet(d)
	if p == Vector3.INF: return
	if d.get("boss", false):
		explosion(p, 4.0); hitstop(.16); flash_screen(Color.WHITE, .4, .3)
	elif _hers(d): hitstop(.05)

func _on_level_up(_d: Dictionary) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl: level_up(pl.global_position)

func _on_respawn(_d: Dictionary) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl: heal(pl.global_position)

func _on_pickup(d: Dictionary) -> void:
	var p: Variant = d.get("pos")
	if not (p is Vector3): return
	var k := str(d.get("kind", ""))
	var cols := [CYAN, Color.WHITE, Color("3a7bff")] if k == "nazar" else ([GOLD, Color.WHITE] if k in ["coin", "lira", "chest"] else [PINK, GOLD, Color.WHITE])
	burst(p + Vector3(0, .6, 0), cols, 8, 2.5, -1.0, .45)

# swing trails: the combo chain alternates the blade's path, the finisher chops overhead, heavies go wide
# and gold, dashes/kicks are a straight streak; guns/bows get a muzzle flash at her hand
const TRAIL := [Color("7bf7ff"), Color("ff5fa2"), Color("b06bff"), Color("ffd66b")]
func _on_attack(d: Dictionary) -> void:
	if not auto: return
	var pl = get_tree().get_first_node_in_group("player")
	if not (pl is Node3D): return
	var f: Vector3 = pl.facing() if pl.has_method("facing") else -pl.global_transform.basis.z
	var w: Dictionary = pl.weapon if "weapon" in pl and pl.weapon is Dictionary else {}
	var kind := str(d.get("kind", "light")); var c := int(d.get("combo", 0))
	if kind == "ranged" or w.get("ranged", false):
		var hp: Vector3 = pl.hand_pos() if pl.has_method("hand_pos") else pl.global_position + Vector3(0, 1.2, 0)
		muzzle(hp + f * .4, f); return
	var reach := clampf(float(w.get("rng", 2.4)) * .85, 1.4, 3.6)
	var at: Vector3 = pl.global_position
	if kind == "heavy":
		swipe(at, f, reach + .4, 2.8, GOLD, 1.0, .25, false, .2, .8)
		return
	match c:
		1: swipe(at, f, reach, 2.1, TRAIL[0], 1.05, .35, false)
		2: swipe(at, f, reach, 2.2, TRAIL[1], 1.0, -.45, true)
		3: swipe(at, f, reach + .2, 2.0, TRAIL[3], 1.0, PI * .45, false, .18, .65)
		_:
			var from := at + Vector3.UP * 1.0 + f * .3
			slash(from, from + f * (reach + .6), TRAIL[2], null, .4, .14)

# the body's sounds already go over the Bus with a position: dust (and splashes) come along for free
func _on_sfx(d: Dictionary) -> void:
	if not auto: return
	var p: Variant = d.get("pos")
	if not (p is Vector3): return
	var at: Vector3 = p
	match str(d.get("name", "")):
		"land": dust(at, 7)
		"land_hard", "slam": dust(at, 12); shockwave(at, 2.0, Color("cabfd8"), .3)
		"jump", "roll", "dodge", "climb", "drift", "crash": dust(at, 5)
		"step":
			if d.get("run", false) and randf() < .35: dust(at, 2)
			if str(d.get("surface", "")) == "water": puff(at + Vector3(0, .1, 0), [Color("bfe8ff"), CYAN], 3, .6, 1.6, .4, .1, 6.0)
		"step_water", "splash": splash(at)
		"explosion": explosion(at)
		"heal": heal(at)

# an enemy wind-up that hits an area: {pos or enemy, radius, sec, color?}. No radius = no ring
func _on_tell(d: Dictionary) -> void:
	if not auto: return
	var r := float(d.get("radius", 0.0))
	var p := _feet(d)
	if r <= 0.0 or p == Vector3.INF: return
	ring(p, r, float(d.get("sec", .8)), d.get("color", PINK) if d.get("color") is Color else PINK)

# lessons / quizzes: a wrong answer costs HP in 7.2 and flashes red
func _on_quiz(d: Dictionary) -> void:
	if not d.get("ok", false): flash("hurt"); shake(.08)
	else: flash("heal")

func _process(dt: float) -> void:
	shake_t = maxf(0.0, shake_t - dt)
	_vig_a = maxf(0.0, _vig_a - dt / .45)
	_vig.material.set_shader_parameter("amt", _vig_a)
	if _scr.color.a > 0: _scr.color.a = maxf(0.0, _scr.color.a - _scr_rate * dt)
	if _hs_on: _hs_check()
	elif Engine.time_scale < .99 and not Overlay.is_open("wheel"):
		Engine.time_scale = 1.0                    # safety net: nothing else may leave the world slowed
	if _tslog:                                     # dev: --tslog reports any slow-down longer than half a second
		if Engine.time_scale >= .99: _tsl_since = 0
		elif _tsl_since == 0: _tsl_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _tsl_since > 500:
			print("TSLOG slowed for 500 ms: time_scale=", Engine.time_scale, " hitstop=", _hs_on, " wheel=", Overlay.is_open("wheel")); _tsl_since = Time.get_ticks_msec() + 100000
	for p in _parts:
		if p["life"] <= 0: continue
		p["life"] -= dt
		var m: MeshInstance3D = p["m"]
		if p["life"] <= 0: m.visible = false; continue
		if p["g"] != 0.0: p["v"].y -= p["g"] * dt
		m.position += p["v"] * dt
		if p["grow"] > 0: m.scale += Vector3.ONE * p["grow"] * dt
		m.material_override.albedo_color.a = minf(.85, p["life"] / p["max"])
	for p in _sparks:
		if p["life"] <= 0: continue
		p["life"] -= dt
		var m: MeshInstance3D = p["m"]
		if p["life"] <= 0: m.visible = false; continue
		var k: float = p["life"] / p["max"]
		if p.has("flare"):
			m.scale = Vector3.ONE * p["s0"] * (.6 + .6 * k)
		else:
			p["v"].y -= p["g"] * dt; p["v"] *= maxf(0.0, 1.0 - 2.2 * dt)
			m.position += p["v"] * dt
			m.scale = Vector3.ONE * p["s0"] * (.35 + .65 * k)
		m.material_override.albedo_color.a = ceilf(k * 3.0) / 3.0       # stepped fade, no soft smear
	for S in _slashes:
		if S["life"] <= 0: continue
		S["life"] -= dt
		if S["life"] <= 0: S["m"].visible = false; S["im"].clear_surfaces(); continue
		_draw_ribbon(S)
	for R in _rings:
		if R["life"] <= 0: continue
		R["life"] -= dt
		var m: MeshInstance3D = R["m"]
		if R["life"] <= 0: m.visible = false; continue
		var mat: ShaderMaterial = m.material_override
		if R["kind"] == "wave":
			var k: float = 1.0 - R["life"] / R["max"]
			var r: float = lerpf(R["r0"], R["r1"], 1.0 - pow(1.0 - k, 2.0))
			m.scale = Vector3(r, 1, r); mat.set_shader_parameter("alpha", 1.0 - k)
		else:
			var left: float = R["life"] - R["pop"]                      # time until it goes off
			if left > 0:
				var k: float = 1.0 - left / R["max"]
				mat.set_shader_parameter("prog", k)
				var blink := 1.0 if k < .7 else (1.0 if fmod(left, .12) > .05 else .45)
				mat.set_shader_parameter("alpha", blink)
			else:
				mat.set_shader_parameter("prog", 1.0); mat.set_shader_parameter("alpha", R["life"] / R["pop"] * 1.6)
	for P in _pillars:
		if P["life"] <= 0: continue
		P["life"] -= dt
		var m: MeshInstance3D = P["m"]
		if P["life"] <= 0: m.visible = false; continue
		var age: float = P["max"] - P["life"]
		var sy := minf(1.0, age / .25)
		m.scale = Vector3(1, maxf(.05, sy), 1); m.position = P["at"] + Vector3(0, 4.5 * sy, 0)    # grows up from her feet
		var mat: ShaderMaterial = m.material_override
		mat.set_shader_parameter("t", age); mat.set_shader_parameter("alpha", minf(1.0, P["life"] / (P["max"] * .6)))
	var ratio := Vector2.ONE
	if cam: ratio = get_viewport().get_visible_rect().size / cam.get_viewport().get_visible_rect().size
	for L in _labs:
		var n: Label = L["n"]
		if L["life"] <= 0: n.visible = false; continue
		L["life"] -= dt; L["p"].y += L["vy"] * dt
		if L["life"] <= 0 or not cam or cam.is_position_behind(L["p"]): n.visible = false; continue
		n.visible = true
		var lift: float = L.get("lift", -1.0)
		n.position = cam.unproject_position(L["p"]) * ratio - (n.size / 2.0 if lift < 0 else Vector2(n.size.x / 2.0, n.size.y + lift))
		n.modulate.a = minf(1.0, L["life"] / L["max"] * 2.0)
