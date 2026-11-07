# The opening, ported from 7.2's intro (INTRO / introInit / introFrame / introGo / introScene / introToMenu /
# introEnd, the drawing in drawVHS / drawKaanCard / drawSunset / iSun / iMountains / iPalm / drawLogo /
# drawCard / drawScan, the cast portraits in introPortraits / portraitCam / IPORT / ICAST):
#   VHS "press any key" screen (PLAY ▶, her clock in Turkish OSD, BAŞLAMAK İÇİN BİR TUŞA BAS)
#   → any key: 0-3.6 s "BİR KAAN YAPIMI" neon card, 3.6 s the synthwave sunset fades in (sliced sun rising,
#     two mountain ridges, the rushing grid, four palms), 7.2-12.2 s the chrome TORİİ logo slams in with the
#     yellow "Neo Antalya" neon script, 12-19.2 s BAŞROLDE: Torii, Bandit and Kaan on cards (real renders of
#     them standing in the city), then the title menu (Menus.me.title) over the dimmed sunset.
#   Any key during the show skips to the menu. Music: Audio.me.set_music_mode("intro") (7.2's IM track),
#   back to "world" when the title closes.
# Drawn at full window resolution on a CanvasLayer (39, just under Menus' 40). Overlay "intro" while it runs.
class_name Intro
extends CanvasLayer

static var me: Intro

const T_END := 19.2
const IMON := ["OCA", "ŞUB", "MAR", "NİS", "MAY", "HAZ", "TEM", "AĞU", "EYL", "EKİ", "KAS", "ARA"]
# [camera height, look height, distance, angle off their nose, look this far ahead of them] (7.2 IPORT)
const IPORT := [[1.85, 1.42, 3.5, .35, 0.0], [1.05, .6, 2.6, .6, .3], [1.85, 1.42, 3.4, .3, 0.0]]
const ICAST := [{"n": "TORİİ", "l": "the girl with the braids", "col": "ffd66b", "rot": -.05},
	{"n": "BANDIT", "l": "the goodest boy in Antalya", "col": "b06bff", "rot": .045},
	{"n": "KAAN", "l": "the man on the balcony ❤", "col": "ff9e2d", "rot": -.035}]

var ph := "vhs"                   # vhs | play | menu | done
var keep_behind_title := true     # 7.2 kept the sunset running behind the title menu
var world: Node3D
var cast: Array = []              # [torii, bandit, kaan] Node3Ds (missing ones are looked up / skipped)
var _on_done: Callable
var _done_called := false
var _t0 := 0.0
var _menu_frames := 0
var _fade := 1.0
var _cv: Control                  # everything under the logo
var _logo: Control                # the logo's chrome gradient (a shader)
var _top: Control                 # logo rim + script, flash, cast cards, scanlines
var _logo_mat: ShaderMaterial
var _cards: Array = [null, null, null]
var _last_card := -1
var _fb: SystemFont               # 'Arial Black' italic (IFONT.block)
var _fbu: SystemFont              # upright block
var _fs: SystemFont               # brush script (IFONT.script)
var _fm: SystemFont               # Courier
var _mnt: Array = []
var _mnt_size := Vector2.ZERO
var _rad: GradientTexture2D       # white soft dot (glows, glints)
var _vig: GradientTexture2D
var _haze: GradientTexture2D
var _W := 960.0
var _H := 720.0
var _T := 0.0
var _t := 0.0

# main calls this instead of Menus.me.title() (on_done = that). Skipped for NEW GAME's reload and headless runs.
static func run(parent: Node, on_done: Callable, w: Node3D = null, who: Array = []) -> Intro:
	if Menus.fresh or DisplayServer.get_name() == "headless":
		on_done.call(); return null
	var i := Intro.new(); i._on_done = on_done; i.world = w; i.cast = who
	parent.add_child(i)
	return i

func _ready() -> void:
	me = self
	name = "Intro"; layer = 39; process_mode = Node.PROCESS_MODE_ALWAYS
	Overlay.open("intro")
	_fb = _sysfont(["Arial Black", "Futura", "Impact", "Helvetica Neue"], true, 900)
	_fbu = _sysfont(["Arial Black", "Futura", "Impact", "Helvetica Neue"], false, 900)
	_fs = _sysfont(["Brush Script MT", "Snell Roundhand", "Segoe Script", "Apple Chancery"], true, 400)
	_fm = _sysfont(["Courier New", "Menlo", "Courier"], false, 700)
	_rad = _radial([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	_vig = _radial([[0.0, Color(0, 0, 0, 0)], [.35, Color(0, 0, 0, 0)], [1.0, Color(0, 0, 0, .55)]])
	_haze = _radial([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	_cv = _layer(); add_child(_cv); _cv.mouse_filter = Control.MOUSE_FILTER_STOP
	_cv.draw.connect(_paint)
	_logo = _layer(); _cv.add_child(_logo)
	_logo_mat = ShaderMaterial.new(); _logo_mat.shader = _logo_shader(); _logo.material = _logo_mat
	_logo.draw.connect(_paint_logo)
	_top = _layer(); _cv.add_child(_top)
	_top.draw.connect(_paint_top)

func _layer() -> Control:
	var c := Control.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func _sysfont(names: Array, italic: bool, weight: int) -> SystemFont:
	var f := SystemFont.new(); f.font_names = PackedStringArray(names); f.font_italic = italic; f.font_weight = weight
	return f

static func _radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var o := PackedFloat32Array(); var c := PackedColorArray()
	for s in stops: o.append(s[0]); c.append(s[1])
	g.offsets = o; g.colors = c
	var t := GradientTexture2D.new(); t.gradient = g; t.width = 128; t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(.5, .5); t.fill_to = Vector2(1, .5)
	return t

func _logo_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform float top_y = 0.0;
uniform float bot_y = 100.0;
varying float vy;
void vertex(){ vy = VERTEX.y; }
vec3 h(float r, float g, float b){ return vec3(r, g, b) / 255.0; }
vec3 grad(float t){
	if (t < 0.3) return mix(h(255.,251.,232.), h(255.,234.,160.), t / 0.3);
	if (t < 0.49) return mix(h(255.,234.,160.), h(255.,214.,107.), (t - 0.3) / 0.19);
	if (t < 0.5) return mix(h(255.,214.,107.), h(42.,10.,74.), (t - 0.49) / 0.01);
	if (t < 0.6) return mix(h(42.,10.,74.), h(106.,45.,160.), (t - 0.5) / 0.1);
	if (t < 0.8) return mix(h(106.,45.,160.), h(200.,155.,255.), (t - 0.6) / 0.2);
	return mix(h(200.,155.,255.), h(255.,228.,92.), (t - 0.8) / 0.2);
}
void fragment(){
	float t = clamp((vy - top_y) / max(1.0, bot_y - top_y), 0.0, 1.0);
	COLOR = vec4(grad(t), texture(TEXTURE, UV).a * COLOR.a);
}
"""
	return s

# ---------------------------------------------------------------- flow
func _now() -> float: return Time.get_ticks_msec() / 1000.0

func _input(e: InputEvent) -> void:
	if ph != "vhs" and ph != "play": return
	var key: bool = e is InputEventKey and e.pressed and not e.echo
	var click: bool = e is InputEventMouseButton and e.pressed
	if not key and not click: return
	get_viewport().set_input_as_handled()
	if ph == "vhs":
		if key and (e as InputEventKey).keycode == KEY_ESCAPE: return
		_go()
	else: _to_menu()

# 7.2 introGo: the show starts, the music comes in, the cast get their pictures taken
func _go() -> void:
	ph = "play"; _t0 = _now()
	if Audio.me and Audio.me.music_on: Audio.me.set_music_mode("intro")
	_portraits()

func _to_menu() -> void:
	if ph == "menu" or ph == "done": return
	ph = "menu"; _menu_frames = 0
	_cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _done_called:
		_done_called = true
		if _on_done.is_valid(): _on_done.call()
	Overlay.close("intro")
	if not keep_behind_title or Menus.me == null: _end()

# 7.2 introEnd: the game is starting; the intro music hands over to the city's
func _end() -> void:
	if ph == "done": return
	ph = "done"
	Overlay.close("intro")
	if Audio.me and Audio.me.mode == "intro": Audio.me.set_music_mode("world")

func _process(dt: float) -> void:
	_W = _cv.size.x; _H = _cv.size.y; _T = _now()
	_t = _T - _t0
	if ph == "play" and _t >= T_END: _to_menu()
	if ph == "menu":
		_menu_frames += 1
		if _menu_frames > 3 and (Menus.me == null or not Menus.me.title_up): _end()
	if ph == "done":
		_fade -= dt * 2.5
		_cv.modulate.a = maxf(0.0, _fade)
		if _fade <= 0.0: queue_free(); return
	_cv.queue_redraw(); _logo.queue_redraw(); _top.queue_redraw()

func _exit_tree() -> void:
	Overlay.close("intro")
	if me == self: me = null

# ---------------------------------------------------------------- the cast portraits (7.2 introPortraits)
func _cast_node(k: int) -> Node3D:
	if k < cast.size() and cast[k] is Node3D and is_instance_valid(cast[k]): return cast[k]
	match k:
		0: return get_tree().get_first_node_in_group("player") as Node3D
		1: return world.get_node_or_null("Bandit") as Node3D if world else null
		2:
			for n in Npc.all:
				if is_instance_valid(n) and n.mode == "kaan": return n
	return null

func _portraits() -> void:
	if world == null or not world.is_inside_tree(): return
	var space := world.get_world_3d().direct_space_state
	for k in 3:
		var o := _cast_node(k)
		if o == null: continue
		var P: Array = IPORT[k]
		var p := o.global_position
		var fw := Vector3(sin(o.global_rotation.y), 0, cos(o.global_rotation.y))
		if o.has_method("facing"): fw = o.facing()
		var yaw := atan2(fw.x, fw.z)
		p += fw * float(P[4])
		var tgt := p + Vector3(0, float(P[1]), 0)
		var best := Vector3.ZERO; var found := false
		# walk round them until nothing (a wall, a lamp post) stands in the way
		for off in [0.0, .5, -.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3]:
			var a: float = yaw + float(P[3]) + off
			var cp := p + Vector3(sin(a) * float(P[2]), float(P[0]), cos(a) * float(P[2]))
			if not found: best = cp; found = true
			var q := PhysicsRayQueryParameters3D.create(cp, tgt)
			var ex: Array[RID] = []
			if o is CollisionObject3D: ex.append((o as CollisionObject3D).get_rid())
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(tgt) < .5:
				best = cp; break
		var vp := SubViewport.new(); vp.size = Vector2i(192, 240); vp.world_3d = world.get_world_3d()
		vp.msaa_3d = Viewport.MSAA_DISABLED; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new(); cam.fov = 28; cam.near = .1; cam.far = 300
		vp.add_child(cam); add_child(vp)
		cam.global_position = best; cam.look_at(tgt, Vector3.UP); cam.current = true
		# a soft fill light so they're not lost in the night (7.2 boosted the hemisphere for the shot)
		var fill := OmniLight3D.new(); fill.light_color = Color(1, .93, .86); fill.light_energy = 1.3; fill.omni_range = 7
		world.add_child(fill); fill.global_position = best + Vector3(0, .4, 0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp): return
		var img := vp.get_texture().get_image()
		if img: _cards[k] = ImageTexture.create_from_image(img)
		fill.queue_free(); vp.queue_free()

# ---------------------------------------------------------------- drawing helpers
static func iOut(u: float) -> float: return 1.0 - pow(1.0 - clampf(u, 0, 1), 3)
static func iIn(u: float) -> float: return pow(clampf(u, 0, 1), 3)
# neon tubes don't just switch on — they stutter first
static func iFlick(u: float, s: float) -> float:
	if u <= 0: return 0.0
	if u >= .7: return 1.0
	return 1.0 if fposmod(sin((floor(u * 22) + s) * 12.9898) * 43758.5453, 1.0) > .45 else .12

static func _ca(c: Color, a: float) -> Color: return Color(c.r, c.g, c.b, c.a * a)

# a vertical gradient band: stops = [[0..1, Color], ...]
func _vgrad(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	for i in stops.size() - 1:
		var y0 := r.position.y + r.size.y * float(stops[i][0]); var y1 := r.position.y + r.size.y * float(stops[i + 1][0])
		var c0: Color = stops[i][1]; var c1: Color = stops[i + 1][1]
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]),
			PackedColorArray([c0, c0, c1, c1]))

# where to put the baseline: align 0 left / 1 centre / 2 right; mid = y is the middle of the letters
func _at(f: Font, text: String, x: float, y: float, size: int, align: int, mid: bool) -> Vector2:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var bx := x - (w * .5 if align == 1 else (w if align == 2 else 0.0))
	var by := y + ((f.get_ascent(size) - f.get_descent(size)) * .5 if mid else 0.0)
	return Vector2(bx, by)

func _text(ci: CanvasItem, f: Font, text: String, x: float, y: float, size: float, col: Color, align := 1, mid := false) -> void:
	var s := maxi(4, int(size))
	ci.draw_string(f, _at(f, text, x, y, s, align, mid), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)

# 7.2 iNeon: a blurred glow (here: wide soft outlines), the tube, a cream rim
func _neon(ci: CanvasItem, f: Font, text: String, x: float, y: float, size: float, col: Color, glow: Color, a := 1.0, align := 1, mid := false) -> void:
	var s := maxi(4, int(size))
	var at := _at(f, text, x, y, s, align, mid)
	for g in [[.6, .10], [.36, .18], [.18, .3]]:
		ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, maxi(2, int(s * float(g[0]))), _ca(glow, float(g[1]) * a))
	ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, maxi(2, int(s * .05)), Color(1, .99, .92, .85 * a))
	ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, _ca(col, a))

func _qbez(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
	return a * (1 - u) * (1 - u) + c * 2.0 * (1 - u) * u + b * u * u

# ---------------------------------------------------------------- the main layer
func _paint() -> void:
	var W := _W; var H := _H
	_cv.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	if ph == "vhs": _vhs(W, H); return
	if ph == "menu" or ph == "done":
		_sunset(W, H, 1.0)
		_cv.draw_rect(Rect2(0, 0, W, H), Color(8 / 255.0, 2 / 255.0, 20 / 255.0, .38))
		return
	var t := _t
	if t < 3.6:
		_kaan_card(W, H, t, 1.0 - (t - 3.1) / .5 if t > 3.1 else 1.0); return
	_sunset(W, H, (t - 3.6) / 3.4)
	var fade_in := clampf((t - 3.6) / 1.4, 0, 1)
	if fade_in < 1.0: _cv.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 1.0 - fade_in))
	# the logo's dark outline and purple glow, under the chrome
	if t >= 7.2 and t < 12.2:
		var L := _logo_geo(W, H, t)
		var at := _at(_fb, "TORİİ", W / 2, L["y"], L["s"], 1, false)
		var a: float = L["a"]
		_cv.draw_string_outline(_fb, at, "TORİİ", HORIZONTAL_ALIGNMENT_LEFT, -1, L["s"], int(L["s"] * .35), Color(.69, .42, 1, .14 * a))
		_cv.draw_string_outline(_fb, at, "TORİİ", HORIZONTAL_ALIGNMENT_LEFT, -1, L["s"], int(L["s"] * .2), Color(.69, .42, 1, .25 * a))
		_cv.draw_string_outline(_fb, at, "TORİİ", HORIZONTAL_ALIGNMENT_LEFT, -1, L["s"], int(L["s"] * .1), Color(.1, .02, .19, a))

# 7.2 drawLogo's size and place: slams in from 2.4x in .32 s, fades out from 11.7
func _logo_geo(W: float, H: float, t: float) -> Dictionary:
	var u := t - 7.2
	var fs := minf(W * .17, H * .24)
	var sc := lerpf(2.4, 1.0, iOut(u / .32)) if u < .32 else 1.0
	var a := 1.0 - (t - 11.7) / .5 if t > 11.7 else 1.0
	var s := int(fs * sc)
	if u < .32: s = int(s / 8) * 8                      # fewer glyph sizes while it zooms
	return {"u": u, "fs": fs, "s": maxi(8, s), "a": clampf(a, 0, 1), "y": H * .44}

# ---- VHS: the "press any key" screen
func _osd(text: String, x: float, y: float, size: int, align: int) -> void:
	var at := _at(_fm, text, x, y, size, align, false)
	_cv.draw_string(_fm, at - Vector2(2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, .16, .35, .55))
	_cv.draw_string(_fm, at + Vector2(2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(.16, .9, 1, .55))
	_cv.draw_string(_fm, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("f4f0ff"))

func _vhs(W: float, H: float) -> void:
	var T := _T
	_cv.draw_rect(Rect2(0, 0, W, H), Color("05020c"))
	var R := maxf(W, H) * .7
	_cv.draw_texture_rect(_haze, Rect2(W / 2 - R, H * .55 - R, R * 2, R * 2), false, Color(58 / 255.0, 15 / 255.0, 92 / 255.0, .55))
	var fs := int(round(minf(W * .03, H * .05)))
	var d := Time.get_datetime_dict_from_system()
	_osd("PLAY ▶", W * .06, H * .1, fs, 0)
	var hh := int(d["hour"])
	_osd(("ÖÖ " if hh < 12 else "ÖS ") + str(12 if hh % 12 == 0 else hh % 12) + ":" + "%02d" % int(d["minute"]), W * .06, H * .93, fs, 0)
	_osd("%s. %d %d" % [IMON[int(d["month"]) - 1], int(d["day"]), int(d["year"])], W * .94, H * .93, fs, 2)
	if sin(T * 4.4) > -.3:
		_neon(_cv, _fbu, "BAŞLAMAK İÇİN BİR TUŞA BAS", W / 2, H * .5, fs * 1.3, Color("ffd66b"), Color("ff9e2d"))
	_neon(_cv, _fs, "press any key", W / 2, H * .5 + fs * 1.6, fs * 1.2, Color("d9b8ff"), Color("b06bff"))
	_text(_cv, _fm, "🎧 sesi aç · turn your sound on", W / 2, H * .5 + fs * 3.1, fs * .62, Color(217 / 255.0, 184 / 255.0, 1, .7))
	# tracking noise rolling down the tape (kept soft)
	var by := (fmod(T * .23, 1.3) - .15) * H
	_cv.draw_rect(Rect2(0, by, W, H * .035), Color(1, 1, 1, .05))
	for i in 18:
		_cv.draw_rect(Rect2(randf() * W, by + randf() * H * .035, randf() * W * .08, 1), Color(1, 1, 1, randf() * .18))

# ---- "Bir Kaan yapımı"
func _kaan_card(W: float, H: float, t: float, a: float) -> void:
	_cv.draw_rect(Rect2(0, 0, W, H), Color("030108"))
	var R := maxf(W, H) * .6
	_cv.draw_texture_rect(_haze, Rect2(W / 2 - R, H / 2 - R, R * 2, R * 2), false, Color(90 / 255.0, 26 / 255.0, 110 / 255.0, .35))
	var fs := minf(W * .075, H * .11)
	_neon(_cv, _fbu, "BİR KAAN YAPIMI", W / 2, H * .46, fs, Color("ffd66b"), Color("ff9e2d"), a * iFlick(t - .3, 1), 1, true)
	_neon(_cv, _fs, "a Kaan production", W / 2, H * .46 + fs * 1.05, fs * .62, Color("d9b8ff"), Color("b06bff"), a * iFlick(t - 1.1, 5), 1, true)

# ---- the synthwave sunset: sky, stars, a sliced sun, mountains, a grid, palms
func _sunset(W: float, H: float, rise: float) -> void:
	var T := _T
	var hz := H * .63
	_vgrad(_cv, Rect2(0, 0, W, hz + 1), [[0.0, Color("06021a")], [.42, Color("24083f")], [.75, Color("5a1a6e")], [.93, Color("b0406a")], [1.0, Color("ff9e3d")]])
	for i in 110:
		var x := float(i * 397 % 1000) / 1000.0 * W; var y := float(i * 211 % 1000) / 1000.0 * hz * .72
		var tw := .5 + .5 * sin(T * 2.2 + i * 1.7)
		var s := 1.3 if i % 9 != 0 else 2.2
		_cv.draw_rect(Rect2(x, y, s, s), Color(1, 236 / 255.0, 190 / 255.0, (.2 + .7 * tw) * (1.0 - y / (hz * .8))))
	var R := minf(W * .2, H * .27)
	var sy := hz - R * .55 + (1.0 - iOut(rise)) * R * 1.6
	var G := R * 2.6
	_cv.draw_texture_rect(_haze, Rect2(W / 2 - G, sy - G, G * 2, G * 2), false, Color(1, .62, .4, .45))
	_sun(W / 2, sy, R, hz)
	if _mnt.is_empty() or _mnt_size != Vector2(W, H): _mountains(W, H, hz)
	for m in _mnt:
		_cv.draw_colored_polygon(m["pts"], m["col"])
		_cv.draw_polyline(m["pts"], m["edge"], maxf(1, H * .002))
	_vgrad(_cv, Rect2(0, hz - H * .02, W, H * .05), [[0.0, Color(1, .84, .42, 0)], [.5, Color(1, .84, .42, .85)], [1.0, Color(1, .84, .42, 0)]])
	_vgrad(_cv, Rect2(0, hz, W, H - hz), [[0.0, Color("1d0636")], [1.0, Color("07010f")]])
	# the grid: lines rush toward you, verticals meet at the sun
	var F := (H - hz) * .85; var sp := fmod(T * 1.3, 1.0)
	var lw := maxf(1, H * .0022)
	for n in 28:
		var z := n + 1 - sp
		if z < .85: continue
		var y := hz + F / z
		if y > H: continue
		_cv.draw_line(Vector2(0, y), Vector2(W, y), Color(.69, .42, 1, minf(1, .15 + 1.4 / z)), lw)
	for i in range(-18, 19):
		_cv.draw_line(Vector2(W / 2 + i * W * .004, hz), Vector2(W / 2 + i * W * .085, H), Color(.69, .42, 1, .9 if i == 0 else .7), lw)
	_vgrad(_cv, Rect2(0, hz, W, H * .08), [[0.0, Color(1, .62, .24, .35)], [1.0, Color(.11, .02, .21, 0)]])
	var ph2 := H * .62
	_palm(W * .07, H * 1.02, ph2, .18, T, false)
	_palm(W * .16, H * 1.04, ph2 * .72, .24, T + 1.3, false)
	_palm(W * .93, H * 1.02, ph2 * .95, .2, T + .7, true)
	_palm(W * .85, H * 1.05, ph2 * .66, .14, T + 2.1, true)

# 7.2 iSun: a gradient disc with seven bands cut out of its lower half (row by row, only above the horizon)
func _sun(cx: float, cy: float, R: float, hz: float) -> void:
	var stops := [[0.0, Color("fff4b0")], [.35, Color("ffd66b")], [.62, Color("ff9e2d")], [1.0, Color("d02d8a")]]
	var y := -R
	while y < R:
		var ly := y + R                                     # 0 at the top of the disc
		var sy := cy + y
		if sy > hz: break
		var cut := false
		for i in 7:
			var s0 := R * (1.02 + i * .14); var hh := R * (.02 + i * .018)
			if ly >= s0 and ly < s0 + hh: cut = true; break
		if not cut:
			var hw := sqrt(maxf(0.0, R * R - (y + 1) * (y + 1)))
			var v := ly / (R * 2)
			var c: Color = stops[0][1]
			for i in stops.size() - 1:
				if v >= float(stops[i][0]) and v <= float(stops[i + 1][0]):
					c = (stops[i][1] as Color).lerp(stops[i + 1][1], (v - float(stops[i][0])) / (float(stops[i + 1][0]) - float(stops[i][0])))
			_cv.draw_rect(Rect2(cx - hw, sy, hw * 2, 2), c)
		y += 2.0

func _mountains(W: float, H: float, hz: float) -> void:
	_mnt = []; _mnt_size = Vector2(W, H)
	var r := RandomNumberGenerator.new(); r.seed = 7
	for L in [[0, .16, Color("2a0a4a"), Color(.69, .42, 1, .8)], [1, .09, Color("15042a"), Color(1, .84, .42, .75)]]:
		var pts := PackedVector2Array([Vector2(0, hz)])
		var x := 0.0
		while x < W:
			x += W * (.03 + r.randf() * .05)
			var mid: bool = absf(x / W - .5) < .16 and int(L[0]) == 0
			var hgt: float = .25 if mid else .3 + r.randf() * .7
			pts.append(Vector2(minf(x, W), hz - H * float(L[1]) * hgt * (.9 if int(L[0]) == 1 else 1.0)))
		pts.append(Vector2(W, hz))
		_mnt.append({"pts": pts, "col": L[2], "edge": L[3]})

func _palm(x: float, y: float, h: float, lean: float, t: float, flip: bool) -> void:
	_cv.draw_set_transform(Vector2(x, y), 0, Vector2(-1 if flip else 1, 1))
	var tx := h * lean + sin(t * .8 + x * .01) * h * .012; var ty := -h
	var ink := Color("0b0214"); var rim := Color(.69, .42, 1, .55); var lw := maxf(1, h * .005)
	var trunk := PackedVector2Array()
	for k in 11: trunk.append(_qbez(Vector2(-h * .035, 0), Vector2(h * lean * .15, -h * .5), Vector2(tx - h * .012, ty), k / 10.0))
	for k in 11: trunk.append(_qbez(Vector2(tx + h * .012, ty), Vector2(h * lean * .15 + h * .05, -h * .5), Vector2(h * .035, 0), k / 10.0))
	if not Geometry2D.triangulate_polygon(trunk).is_empty(): _cv.draw_colored_polygon(trunk, ink)
	_cv.draw_polyline(trunk, rim, lw)
	var L := h * .5
	for i in 9:
		var dx := -1.0 + 2.0 * i / 8.0 + sin(t * 1.1 + i) * .025; var ax := absf(dx); var len := L * (.72 + .28 * ax)
		var e := Vector2(tx + dx * len, ty + len * (.5 * ax * ax - .12 - (.25 if ax < .25 else 0.0)))
		var c := Vector2(tx + dx * len * .5, ty - len * (.32 - .12 * ax)); var w := len * .07
		var leaf := PackedVector2Array()
		for k in 9: leaf.append(_qbez(Vector2(tx, ty), c - Vector2(0, w), e, k / 8.0))
		for k in 9: leaf.append(_qbez(e, c + Vector2(0, w * 1.6), Vector2(tx, ty + w * .6), k / 8.0))
		var tri := Geometry2D.triangulate_polygon(leaf)
		if not tri.is_empty(): _cv.draw_colored_polygon(leaf, ink)
		_cv.draw_polyline(leaf, rim, lw)
		for k in range(1, 9):
			var u := k / 9.0
			var q := _qbez(Vector2(tx, ty), c, e, u)
			_cv.draw_line(q, q + Vector2(dx * len * .05, len * (.12 + .04 * u) * (1 - u * .45)), ink, maxf(1, len * .016))
	_cv.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- the logo's chrome (shader layer)
func _paint_logo() -> void:
	if ph != "play" or _t < 7.2 or _t >= 12.2: return
	var L := _logo_geo(_W, _H, _t)
	var s: int = L["s"]
	var at := _at(_fb, "TORİİ", _W / 2, L["y"], s, 1, false)
	_logo_mat.set_shader_parameter("top_y", at.y - s * .74)
	_logo_mat.set_shader_parameter("bot_y", at.y)
	_logo.draw_string(_fb, at, "TORİİ", HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(1, 1, 1, L["a"]))

# ---------------------------------------------------------------- on top: rim, script, flash, the cast, scanlines
func _paint_top() -> void:
	var W := _W; var H := _H; var t := _t
	if ph == "play" and t >= 7.2 and t < 12.2:
		var L := _logo_geo(W, H, t)
		var s: int = L["s"]; var a: float = L["a"]; var u: float = L["u"]; var fs: float = L["fs"]
		var at := _at(_fb, "TORİİ", W / 2, L["y"], s, 1, false)
		_top.draw_string_outline(_fb, at, "TORİİ", HORIZONTAL_ALIGNMENT_LEFT, -1, s, maxi(1, int(s * .014)), Color(1, 1, 1, .6 * a))
		# a glint that runs along the chrome
		var gx := (fmod(u * .55, 1.6) - .3) * fs * 3.2 - fs * 1.6
		if gx > -fs * 1.6 and gx < fs * 1.6:
			var gc := Vector2(W / 2 + gx, L["y"] - fs * .38)
			_top.draw_texture_rect(_rad, Rect2(gc.x - fs * .3, gc.y - fs * .02, fs * .6, fs * .04), false, Color(1, 1, 1, .95 * a))
			_top.draw_texture_rect(_rad, Rect2(gc.x - fs * .02, gc.y - fs * .3, fs * .04, fs * .6), false, Color(1, 1, 1, .95 * a))
		var n := iFlick(u - .8, 3)
		if n > 0:
			_top.draw_set_transform(Vector2(W / 2, L["y"]), -.09, Vector2.ONE)
			_neon(_top, _fs, "Neo Antalya", fs * .42, fs * .66, fs * .6, Color("ffe45c"), Color("ff9e2d"), a * n)
			_top.draw_set_transform(Vector2.ZERO)
		if u < .3: _top.draw_rect(Rect2(0, 0, W, H), Color(1, 246 / 255.0, 220 / 255.0, (1 - u / .3) * .85))
	if ph == "play" and t >= 12:
		var k := int(floor((t - 12) / 2.4))
		if k < 3:
			_card(W, H, k, fmod(t - 12, 2.4) / 2.4)
			if _last_card != k:
				_last_card = k; Audio.sfx("woosh2")
		var ha := clampf((t - 12) / .4, 0, 1) * clampf((T_END - t) / .4, 0, 1)
		_neon(_top, _fbu, "BAŞROLDE · starring", W / 2, H * .085, H * .032, Color("ffd66b"), Color("b06bff"), ha)
	_scan(W, H)

# 7.2 drawCard: a tilted polaroid of each of them slides in from the right and out to the left
func _card(W: float, H: float, k: int, p: float) -> void:
	var C: Dictionary = ICAST[k]
	var col := Color(C["col"])
	var cw := minf(W * .3, H * .46); var ch := cw * 1.25
	var x := W * .5 + (1 - iOut(p / .16)) * W * .9 - iIn((p - .84) / .16) * W * .9
	_top.draw_set_transform(Vector2(x, H * .47), float(C["rot"]), Vector2.ONE)
	_top.draw_rect(Rect2(-cw / 2 + cw * .04, -ch / 2 + cw * .05, cw, ch), Color(0, 0, 0, .5))
	for g in 8:                                       # a soft neon glow round the frame
		var e: float = cw * .016 * (8 - g)
		_top.draw_rect(Rect2(-cw / 2 - cw * .03 - e, -ch / 2 - cw * .03 - e, cw * 1.06 + e * 2, ch + cw * .06 + e * 2), _ca(col, .035))
	_top.draw_rect(Rect2(-cw / 2 - cw * .03, -ch / 2 - cw * .03, cw * 1.06, ch + cw * .06), col)
	var img: Texture2D = _cards[k]
	if img: _top.draw_texture_rect(img, Rect2(-cw / 2, -ch / 2, cw, ch), false)
	else: _vgrad(_top, Rect2(-cw / 2, -ch / 2, cw, ch), [[0.0, Color("5a1a6e")], [1.0, Color("1d0636")]])
	_vgrad(_top, Rect2(-cw / 2, 0, cw, ch / 2), [[0.0, Color(.14, .03, .25, 0)], [1.0, Color(.14, .03, .25, .9)]])
	var yy := -ch / 2
	while yy < ch / 2:
		_top.draw_rect(Rect2(-cw / 2, yy, cw, 1), Color(0, 0, 0, .12)); yy += 3.0
	var fs := cw * .21
	var at := _at(_fb, C["n"], 0, ch / 2 - cw * .2, int(fs), 1, false)
	_top.draw_string_outline(_fb, at, C["n"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), int(fs * .12), Color("14042a"))
	_top.draw_string(_fb, at, C["n"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), Color("ffe9a8"))
	_neon(_top, _fs, C["l"], 0, ch / 2 - cw * .06, cw * .1, Color("ffe45c"), Color("ff9e2d"))
	_top.draw_set_transform(Vector2.ZERO)

# 7.2 drawScan: thin dark lines every 4 px and a soft vignette
func _scan(W: float, H: float) -> void:
	var y := 0.0
	while y < H:
		_top.draw_rect(Rect2(0, y, W, 1), Color(0, 0, 0, .18))
		_top.draw_rect(Rect2(0, y + 2, W, 1), Color(0, 0, 0, .06))
		y += 4.0
	var R := maxf(W, H) * .75
	_top.draw_texture_rect(_vig, Rect2(W / 2 - R, H / 2 - R, R * 2, R * 2), false)
