# The cutscene player — 7.2's playCut / cutShot / cutNext / endCut / cutKey / cutUpdate / closeUp /
# whenFree / cineEl, and the scenes built on it:
#   call_scene()  7.2's playCall: 📱 GELEN ARAMA card, Torii in her phone pose says "Alo?", the caller's
#                 lines shot on the caller (Kaan with his phone, DJ Cool Cat, Bandit), Torii answers with
#                 a REPLIES line in Turkish, then the ÜNİTE · MISSION title card with a fanfare
#   hell_scene()  7.2's HELLSCENES / hsShots / buildHellSet / paintScreen / animSet: CEO Karen's corner
#                 office, built far off the map (HS = 1500, 1500), with the intern imp and the zombie
#                 accountant and the HR monitor that shows Torii's file
#   opening()     7.2's playOpening (a brand-new game)        ending()  7.2's playEnding (credits + epilogue)
#   boss_intro()  one shot on a mission boss with its title card (new; 7.2 only had the banner + sound)
#   backdrop()    a slow flight over the city behind the title screen
# A shot: {cam, cam2, look, look2 (Vector3 or a Callable returning one), dur, move, who, col, line, title,
#          say (TTS), sfx, flash, auto, set (Callable), leave (Callable), act (Callable(t, dt))}
# While a scene plays: letterbox, the HUD hides, it is an Overlay ("cut") so she can't be hurt and every
# monster/clock waits, the Spawner pauses. E / Enter / Space / click = next line, ESC = skip it all.
# Also here: Kaan's balcony idle (7.2 updateKaan): a drag on the cigarette with smoke when she's away, and
# the phone-to-cheek pose for him and Torii during calls.
# Story text: assets/story/story72.json (exported from 7.2) and assets/story/godot.json (credits).
class_name Cutscene
extends CanvasLayer

static var me: Cutscene
const HS := Vector3(1500, 0, 1500)
const C_GOLD := "#ffd66b"
const C_TORII := "#ff9ecf"
var world: Node3D
var torii: CharacterBody3D
var hud: CanvasLayer
var cam: Camera3D
var S := {}                  # story72.json
var G := {}                  # godot.json
var active := false
var shots: Array = []
var idx := -1
var st := 0.0
var cur := {}
var _c0: Variant = null
var _c1: Variant = null
var _l0: Variant = null
var _l1: Variant = null
var _cb := Callable()
var cut_pose := ""           # "phone" | "dance" | "" (7.2's S.cutPose)
var auto := false            # dev runs (--autoplay) page through by themselves
var _t := 0.0
var _sp_was := false
var _hud_was := true
var _bars := 0.0
var _bars_to := 0.0
var _title_a := 0.0
var _flash_a := 0.0
var _backdrop := false
# ui
var _top: ColorRect
var _bot: ColorRect
var _who: Label
var _line: RichTextLabel
var _next: Label
var _title: RichTextLabel
var _skip: Label
var _flash: ColorRect
# the Hellspace set
var _set: Node3D
var _karen: Node3D
var _karen_head: Node3D
var _imp: Node3D
var _zomb: Node3D
var _scr_lines: Label3D
var _phone: MeshInstance3D
var _kaan_smoke := 2.2

func setup(w: Node3D, p: CharacterBody3D, h: CanvasLayer) -> void:
	me = self; world = w; torii = p; hud = h
	name = "Cutscene"; layer = 30; process_priority = 100        # after the player and the people pose themselves
	process_mode = Node.PROCESS_MODE_ALWAYS
	S = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/story72.json"))
	G = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/godot.json"))
	for a in OS.get_cmdline_user_args(): if a.begins_with("--autoplay="): auto = true
	cam = Camera3D.new(); cam.fov = 58; cam.near = .05; cam.far = 400; cam.name = "CutCam"
	world.add_child(cam)
	_ui()

# ---------------------------------------------------------------- the letterbox + subtitles (cineEl)
func _ui() -> void:
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new(); _flash.set_anchors_preset(Control.PRESET_FULL_RECT); _flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(_flash)
	_top = ColorRect.new(); _top.color = Color(0, 0, 0, 1); _top.position = Vector2.ZERO; _top.size = Vector2(960, 0); root.add_child(_top)
	_bot = ColorRect.new(); _bot.color = Color(0, 0, 0, 1); _bot.position = Vector2(0, 720); _bot.size = Vector2(960, 0); root.add_child(_bot)
	for c in [_top, _bot]: c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who = Label.new(); _who.position = Vector2(110, 622); _who.size = Vector2(740, 22)
	_who.add_theme_font_size_override("font_size", 17); _who.add_theme_constant_override("outline_size", 4)
	_who.add_theme_color_override("font_outline_color", Color.BLACK); root.add_child(_who)
	_line = RichTextLabel.new(); _line.bbcode_enabled = true; _line.scroll_active = false
	_line.position = Vector2(110, 646); _line.size = Vector2(740, 70); _line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.add_theme_font_size_override("normal_font_size", 19); _line.add_theme_font_size_override("bold_font_size", 19)
	_line.add_theme_font_size_override("italics_font_size", 17); _line.add_theme_color_override("default_color", Color("f4eeff"))
	root.add_child(_line)
	_next = Label.new(); _next.text = "E ▶"; _next.position = Vector2(870, 690); _next.add_theme_font_size_override("font_size", 14)
	_next.add_theme_color_override("font_color", Color("7bf7ff")); root.add_child(_next)
	_skip = Label.new(); _skip.text = "E next · ESC skip"; _skip.position = Vector2(780, 10); _skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", Color(1, 1, 1, .55)); root.add_child(_skip)
	_title = RichTextLabel.new(); _title.bbcode_enabled = true; _title.scroll_active = false; _title.fit_content = true
	_title.position = Vector2(40, 250); _title.size = Vector2(880, 220); _title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_constant_override("outline_size", 8); _title.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	root.add_child(_title)
	for c in [_who, _line, _next, _skip, _title]: c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_ui(false)

func _set_ui(on: bool) -> void:
	for c in [_who, _line, _next, _skip, _title]: c.visible = on

# a title card from parts [[cls, text, colour?]]: U = small caps line, A = the big neon title, B = a line under it
static func card(parts: Array) -> String:
	var out := []
	for p in parts:
		var cls: String = p[0]
		var col: String = p[2] if p.size() > 2 else {"U": "#7bf7ff", "A": "#ff5fa2", "B": "#f2e8ff"}.get(cls, "#ffffff")
		var sz: int = {"U": 17, "A": 50, "B": 21}.get(cls, 20)
		var t: String = p[1]
		if cls == "A": t = "[b]%s[/b]" % t
		out.append("[font_size=%d][color=%s]%s[/color][/font_size]" % [sz, col, t])
	return "[center]%s[/center]" % "\n".join(out)

# ---------------------------------------------------------------- the player (playCut and friends)
static func busy() -> bool: return me != null and me.active

func play(list: Array, cb := Callable()) -> void:
	if list.is_empty():
		if cb.is_valid(): cb.call()
		return
	if active: end(true)
	shots = list; _cb = cb; active = true; idx = -1
	Overlay.open("cut")
	var sp = _spawner()
	if sp: _sp_was = sp.paused; sp.paused = true
	if hud: _hud_was = hud.visible; hud.visible = false
	if torii and torii.cam: cam.global_transform = torii.cam.global_transform
	cam.current = true
	_bars_to = 92.0; _set_ui(true); _title_a = 0.0
	_shot(0)

func _shot(k: int) -> void:
	if cur.has("leave"):
		var lv: Callable = cur["leave"]; cur.erase("leave")
		if lv.is_valid(): lv.call()
	if k >= shots.size(): end(false); return
	idx = k; st = 0.0; cur = shots[k]
	if cur.has("set") and (cur["set"] as Callable).is_valid(): (cur["set"] as Callable).call()
	_c0 = _v(cur.get("cam")); _c1 = _v(cur.get("cam2")) if cur.has("cam2") else _c0
	_l0 = _v(cur.get("look")); _l1 = _v(cur.get("look2")) if cur.has("look2") else _l0
	_who.text = str(cur.get("who", "")); _who.add_theme_color_override("font_color", Color(str(cur.get("col", C_GOLD))))
	_line.text = str(cur.get("line", ""))
	var has_line := _line.text != ""
	_who.visible = has_line; _line.visible = has_line
	if cur.has("title"): _title.text = str(cur["title"]); _title_a = 0.01
	else: _title_a = 0.0
	_title.modulate.a = _title_a
	if cur.has("say") and str(cur["say"]) != "": Audio.speak(str(cur["say"]))
	if cur.get("sfx", "") is String and cur.get("sfx", "") != "": Audio.sfx(str(cur["sfx"]))
	if cur.get("flash", false): _flash_a = .9

func _v(x: Variant) -> Variant:
	if x is Callable: return (x as Callable).call()
	return x

func next() -> void:
	if not active or st < .3: return          # a held key can't blow through lines
	_shot(idx + 1)

func end(skipped: bool) -> void:
	if not active: return
	if skipped:
		for j in range(maxi(0, idx), shots.size()):
			var s: Dictionary = shots[j]
			if s.has("leave") and (s["leave"] as Callable).is_valid(): (s["leave"] as Callable).call()
			s.erase("leave")
	active = false; shots = []; cur = {}; cut_pose = ""
	_show_phone(false)
	Overlay.close("cut")
	var sp = _spawner()
	if sp: sp.paused = _sp_was
	if hud: hud.visible = _hud_was
	_bars_to = 0.0; _set_ui(false); _title_a = 0.0
	if not _backdrop and torii and torii.cam:
		torii.cam.current = true
		if torii.has_method("snap_camera"): torii.snap_camera()
	var cb := _cb; _cb = Callable()
	if cb.is_valid(): cb.call()

func _input(e: InputEvent) -> void:
	if not active: return
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.keycode
		if k == KEY_ESCAPE: end(true)
		elif k in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: next()
		get_viewport().set_input_as_handled()          # nothing else hears keys while a scene plays
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		next(); get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_t += dt
	# letterbox bars, title fade, flash
	_bars = move_toward(_bars, _bars_to, dt * 260.0)
	_top.size = Vector2(960, _bars); _bot.position = Vector2(0, 720 - _bars); _bot.size = Vector2(960, _bars)
	_top.visible = _bars > .5; _bot.visible = _bars > .5
	if _title_a > 0: _title_a = minf(1.0, _title_a + dt * 2.5); _title.modulate.a = _title_a
	_flash_a = maxf(0.0, _flash_a - dt * 2.2); _flash.color = Color(1, 1, 1, _flash_a)
	_kaan_idle(dt)
	if _set and _set.visible: _anim_set()
	if not active:
		if _backdrop: _backdrop_tick()
		return
	st += dt
	var has_line := str(cur.get("line", "")) != ""
	var dur := float(cur.get("dur", 0.0 if has_line else 2.6))
	var mv := float(cur.get("move", dur if dur > 0 else 4.0))
	var u := clampf(st / maxf(.01, mv), 0.0, 1.0)
	var ee := u * u * (3.0 - 2.0 * u)
	if _c0 is Vector3: cam.global_position = (_c0 as Vector3).lerp(_c1 as Vector3, ee)
	if _l0 is Vector3:
		var look: Vector3 = (_l0 as Vector3).lerp(_l1 as Vector3, ee)
		if look.distance_squared_to(cam.global_position) > .01 and absf((look - cam.global_position).normalized().y) < .995:
			cam.look_at(look, Vector3.UP)
	if cur.has("act") and (cur["act"] as Callable).is_valid(): (cur["act"] as Callable).call(st, dt)
	_poses()
	_next.visible = has_line and st > .3
	if not has_line and st >= dur: _shot(idx + 1)
	elif has_line and ((auto and st >= .35) or (cur.has("auto") and st >= float(cur["auto"]))): _shot(idx + 1)

# her phone pose / her credits dance, laid over whatever the player posed this frame
func _poses() -> void:
	if not torii or torii.pose == null: return
	var P: ToriiPose = torii.pose
	P.w = 1.0
	match cut_pose:
		"phone":
			P.arm(1, -1.36, 0, .105); P.elbow(1, -2.52); P.head(0, -.1, .12)
			_show_phone(true)
		"dance": P.dance(_t); _show_phone(false)
		_: _show_phone(false)

func _show_phone(on: bool) -> void:
	if not torii or torii.hand == null: return
	if on and _phone == null:
		_phone = MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(.07, .14, .025); _phone.mesh = bm
		_phone.material_override = _mat(Color("1a1626"))
		var scr := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(.055, .11); scr.mesh = qm
		scr.material_override = _mat(Color("ff5fa2")); scr.position = Vector3(0, 0, .014); _phone.add_child(scr)
		torii.hand.get_parent().add_child(_phone); _phone.position = torii.hand.position
	if _phone: _phone.visible = on
	torii.hand.visible = not on                  # the weapon goes away while she talks (7.2)

func when_free(cb: Callable) -> void:
	var n := 0
	while (Overlay.any() or active or (torii and torii.get("dead") == true)) and n < 240:
		n += 1
		await get_tree().create_timer(.25).timeout
	cb.call()

func _spawner() -> Object:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "Spawner":
			var o = load(c["path"]).get("me")
			return o if is_instance_valid(o) else null
	return null

# ---------------------------------------------------------------- camera helpers (closeUp / clearView)
func _fwd(o: Node3D) -> Vector3:
	if o == torii and torii.has_method("facing"): return torii.facing()
	var f := o.global_transform.basis.z; f.y = 0
	return f.normalized() if f.length() > .01 else Vector3.BACK

func _clear(a: Vector3, b: Vector3, skip: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var ex: Array[RID] = []
	if torii: ex.append(torii.get_rid())
	if skip is CollisionObject3D: ex.append((skip as CollisionObject3D).get_rid())
	q.exclude = ex
	return world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# a close-up that never ends up inside a wall: {cam, look} as Callables, worked out when the shot starts
func close_up(o: Node3D, h: float, dist := 2.6, side := .55) -> Dictionary:
	var pick := func() -> Vector3:
		var p := o.global_position
		var f := _fwd(o)
		var ry := atan2(f.x, f.z)
		var head := p + Vector3(0, h * .93, 0)
		for off in [0.0, .45, -.45, .9, -.9, 1.4, -1.4, PI]:
			var a: float = ry + off + side * .35
			var c := Vector3(p.x + sin(a) * dist, p.y + h * .96, p.z + cos(a) * dist)
			if _clear(head, c, o): return c
		return Vector3(p.x + sin(ry) * dist, p.y + h * .96, p.z + cos(ry) * dist)
	var look := func() -> Vector3: return o.global_position + Vector3(0, h * .93, 0)
	return {"cam": pick, "look": look}

func _behind(back: float, up: float) -> Callable:
	return func() -> Vector3:
		var f := _fwd(torii)
		return torii.global_position - f * back + Vector3(0, up, 0)

func _at_torii(y: float) -> Callable:
	return func() -> Vector3: return torii.global_position + Vector3(0, y, 0)

# ---------------------------------------------------------------- the people in it
func kaan() -> Node3D:
	for n in Npc.all:
		if is_instance_valid(n) and n.mode == "kaan": return n
	return null

func _speaker(who: String) -> Dictionary:
	var k := kaan()
	if "KAAN" in who.to_upper() and k: return {"o": k, "h": 1.95, "kind": "kaan"}
	if "BANDIT" in who.to_upper() and Bandit.me: return {"o": Bandit.me, "h": .95, "kind": "bandit"}
	for n in Npc.all:
		if not is_instance_valid(n) or n.npc_name == "": continue
		var key := " ".join(n.npc_name.split(" ").slice(0, 2))
		if key != "" and key in who: return {"o": n, "h": 2.05, "kind": "npc"}
	return {"o": torii, "h": 1.95, "kind": "torii"}

# updateKaan: a drag on the cigarette every 6 s with a little smoke when she's away; the phone on calls
func _kaan_idle(dt: float) -> void:
	var k := kaan()
	if k == null or k.pose == null or torii == null: return
	var d2: float = k.global_position.distance_squared_to(torii.global_position)
	if d2 > 90.0 * 90.0 and not active: return
	var P: ToriiPose = k.pose
	P.w = 1.0
	if cut_pose == "phone":
		P.arm(1, -1.36, 0, .105); P.elbow(1, -2.52); P.head(.04, -.1, .12)
		return
	if d2 < 340.0: return                        # npc.gd waves at her
	var cyc := fmod(_t, 6.0) / 6.0
	var up := sin(cyc / .28 * PI) if cyc < .28 else 0.0
	P.arm(1, -.3 - up * .9, 0, .1); P.elbow(1, -.4 - up * 1.8)
	_kaan_smoke -= dt
	if _kaan_smoke <= 0 and Fx.me:
		_kaan_smoke = 2.2
		Fx.me.puff(k.global_position + Vector3(.25, 1.75, .2), Color("d8d8cc"), 2, .25, .75, 2.2, .4)

# ---------------------------------------------------------------- 📱 the incoming call (playCall)
func call_scene(m: Dictionary, mi: int, cb: Callable) -> void:
	when_free(func(): play(call_shots(m, mi), cb))

func call_shots(m: Dictionary, mi: int) -> Array:
	var intro: Dictionary = m.get("intro", {})
	var who := str(intro.get("name", "KAAN 📱"))
	var sp := _speaker(who)
	var is_call: bool = sp["kind"] in ["kaan", "npc"] or "📱" in who
	var tor := close_up(torii, 1.95, 2.4, .6)
	var spk := close_up(sp["o"], sp["h"], 2.2 if sp["kind"] == "bandit" else 2.5, .6)
	var R: Array = S["replies"]
	var rep: Array = R[(mi + 3) % R.size()]
	var out := []
	if is_call:
		out.append({"cam": tor["cam"], "look": tor["look"], "dur": 1.5, "sfx": "ding", "set": _pose_to.bind("phone"),
			"title": card([["U", "📱 GELEN ARAMA"], ["B", "incoming call · " + who.replace("📱", "").strip_edges()]])})
		out.append({"cam": tor["cam"], "look": tor["look"], "who": "TORİİ", "col": C_TORII, "line": "Alo? [i](Hello?)[/i]", "say": "Alo?"})
	for L in intro.get("lines", []):
		out.append({"cam": spk["cam"], "look": spk["look"], "who": who, "col": C_GOLD, "line": str(L)})
	out.append({"cam": tor["cam"], "look": tor["look"], "who": "TORİİ", "col": C_TORII,
		"line": "%s [i](%s)[/i]" % [rep[0], rep[1]], "say": rep[0]})
	out.append({"cam": _behind(8, 5), "look": _at_torii(1.6), "dur": 2.8, "set": _pose_to.bind(""),
		"title": mission_card(m), "sfx": "fanfare"})
	return out

static func mission_card(m: Dictionary) -> String:
	var parts := str(m.get("title", "")).split("·")
	var u := int(m.get("unit", 1))
	var rest := "·".join(parts.slice(1)).strip_edges() if parts.size() > 1 else ""
	return card([["U", "📖 ÜNİTE %d · UNIT %d" % [u, u]], ["A", parts[0].strip_edges()], ["B", rest]])

# ---------------------------------------------------------------- a boss walks in
# 7.2 showed a banner and played the boss's sound; here it's one shot on the boss with its title card
func boss_intro(e: Node3D, bn: String, lab: String, snd: String) -> void:
	if not is_instance_valid(e): return
	when_free(func():
		if not is_instance_valid(e): return
		var c := close_up(e, 2.4, 6.0, .3)
		play([{"cam": c["cam"], "look": c["look"], "dur": 2.6, "sfx": snd, "flash": true,
			"title": card([["U", "⚔️ BOSS"], ["A", bn], ["B", lab]])}]))

# ---------------------------------------------------------------- the opening (playOpening)
func opening(cb: Callable) -> void:
	when_free(func():
		var k := kaan()
		var sh := [{"title": card(S["opening_title"]), "cam": Vector3(40, 62, 120), "cam2": Vector3(-10, 34, 40),
			"look": Vector3(-24, 6, -20), "look2": Vector3(-24, 6, -24), "dur": 5.2, "sfx": "fanfare"}]
		if k:
			var c := close_up(k, 1.95, 2.8, .4)
			sh.append({"cam": c["cam"], "look": c["look"], "who": "KAAN ❤", "col": C_GOLD,
				"line": "Görüşürüz bebeğim! 💨 [i](See you later, baby!)[/i]", "say": "Görüşürüz bebeğim"})
		var t := close_up(torii, 1.95, 2.6, -.5)
		sh.append({"cam": t["cam"], "look": t["look"], "who": "TORİİ", "col": C_TORII,
			"line": "Hadi Bandit! Gidiyoruz! [i](Come on Bandit! We're going!)[/i]", "say": "Hadi Bandit", "sfx": "bark"})
		sh.append({"cam": Vector3(-86, 3, -70), "look": Vector3(-100, 6, -96), "look2": Vector3(-100, 44, -96), "dur": 4.2,
			"title": card(S["opening_tower"]), "sfx": "karen"})
		play(sh, cb))

# ---------------------------------------------------------------- the end (playEnding)
func ending(cb := Callable()) -> void:
	when_free(func():
		var sh := []
		var words: int = (SaveBridge.data.get("words", []) as Array).size() if SaveBridge.data.get("words") is Array else 0
		var cr: Array = G.get("credits", [])
		for i in cr.size():
			var parts: Array = (cr[i] as Array).duplicate(true)
			for p in parts:
				if "%d" in str(p[1]): p[1] = str(p[1]) % words
			var a0 := i * .9
			var y := 3.0 + i * .6
			var c0 := func() -> Vector3: return torii.global_position + Vector3(cos(a0) * 9, y, sin(a0) * 9)
			var c1 := func() -> Vector3: return torii.global_position + Vector3(cos(a0 + .6) * 8, y + .4, sin(a0 + .6) * 8)
			sh.append({"title": card(parts), "dur": 4.2, "cam": c0, "cam2": c1, "look": _at_torii(1.5),
				"set": _pose_to.bind("dance"), "sfx": "fanfare" if i == 0 else ""})
		var ep: Dictionary = S["epilogue"]
		sh.append_array(hs_shots(str(ep["screen"]), ep["lines"]))
		play(sh, cb))

# ---------------------------------------------------------------- MEANWHILE at Hellspace Wealth
static func has_hell(id: String) -> bool: return me != null and (me.S.get("hell", {}) as Dictionary).has(id)

func hell_scene(id: String, cb := Callable()) -> void:
	var H: Dictionary = S.get("hell", {})
	if not H.has(id):
		if cb.is_valid(): cb.call()
		return
	when_free(func(): play(hs_shots(str(H[id]["screen"]), H[id]["lines"]), cb))

func _hp(x: float, y: float, z: float) -> Vector3: return HS + Vector3(x, y, z)

func hs_shots(screen: String, lines: Array) -> Array:
	_build_set()
	var sh := [{"title": card(S["meanwhile"]), "cam": _hp(-5.5, 3.6, 5.2), "cam2": _hp(-3.2, 2.6, 3.2), "look": _hp(0, 1.6, -2.5),
			"dur": 3.4, "sfx": "karen", "set": _hs_open.bind(screen)},
		{"cam": _hp(2, 2.45, -4.1), "cam2": _hp(1.6, 2.25, -3.6), "look": _hp(.9, 1.6, -1.35), "dur": 3.0}]
	var CAM := {"karen": [_hp(.9, 2.8, -.5), _hp(0, 2.62, -2.7)], "imp": [_hp(1.6, 1.5, 1.4), _hp(2.8, 1.1, -.4)],
		"zomb": [_hp(-1.8, 2.3, 1.2), _hp(-2.9, 2.1, -.7)], "wide": [_hp(0, 3.3, 4.2), _hp(0, 1.9, -2)]}
	var WHO := {"karen": "CEO KAREN 👩‍💼", "imp": "STAJYER IMP · the intern", "zomb": "ZOMBİ MUHASEBECİ · accounting"}
	for L in lines:
		var c: Array = CAM.get(L[0], CAM["wide"])
		sh.append({"cam": c[0], "look": c[1], "who": WHO.get(L[0], ""), "col": "#ff4d4d" if L[0] == "karen" else "#d9c8ff",
			"line": str(L[1]), "sfx": str(L[2]) if L.size() > 2 else ""})
	sh[sh.size() - 1]["leave"] = _hs_close
	return sh

func _pose_to(p: String) -> void: cut_pose = p
func _hs_open(screen: String) -> void:
	cut_pose = ""; _paint(screen); _set.visible = true
func _hs_close() -> void:
	if _set: _set.visible = false

# ---------------------------------------------------------------- the title screen backdrop
func backdrop(on: bool) -> void:
	_backdrop = on
	if on:
		cam.current = true; _backdrop_tick()
	elif not active and torii and torii.cam:
		torii.cam.current = true
		if torii.has_method("snap_camera"): torii.snap_camera()

func _backdrop_tick() -> void:
	var a := _t * .05
	cam.global_position = Vector3(-24 + cos(a) * 95, 46 + sin(_t * .13) * 4, -20 + sin(a) * 95)
	cam.look_at(Vector3(-24, 4, -20), Vector3.UP)

# ---------------------------------------------------------------- building the office (buildHellSet)
func _mat(c: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex: m.albedo_texture = tex
	return m

func _box(p: Node3D, size: Vector3, at: Vector3, c: Color, rot := Vector3.ZERO, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	mi.material_override = _mat(c, tex); mi.position = at; mi.rotation = rot; p.add_child(mi)
	return mi

func _cyl(p: Node3D, top: float, bot: float, h: float, at: Vector3, c: Color, sides := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = top; cm.bottom_radius = bot; cm.height = h
	cm.radial_segments = sides; cm.rings = 1; mi.mesh = cm; mi.material_override = _mat(c); mi.position = at; p.add_child(mi)
	return mi

func _quad(p: Node3D, size: Vector2, at: Vector3, rot_y: float, c: Color, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = size; mi.mesh = qm
	mi.material_override = _mat(c, tex); mi.position = at; mi.rotation.y = rot_y; p.add_child(mi)
	return mi

func _text(p: Node3D, t: String, at: Vector3, rot_y: float, c: Color, size := 32, px := .006) -> Label3D:
	var l := Label3D.new(); l.text = t; l.modulate = c; l.font_size = size; l.pixel_size = px; l.shaded = false
	l.outline_size = 0; l.position = at; l.rotation.y = rot_y; l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.add_child(l)
	return l

func _tex(img: Image) -> ImageTexture: return ImageTexture.create_from_image(img)

# Torii's tiny HR-file portrait, as clean pixel art: braids, face, pink top, crossed out in red
func _portrait() -> Image:
	var im := Image.create(24, 30, false, Image.FORMAT_RGBA8); im.fill(Color("2a1030"))
	im.fill_rect(Rect2i(5, 4, 14, 16), Color("4a3122"))       # hair
	im.fill_rect(Rect2i(7, 6, 10, 12), Color("ba8760"))       # face
	for i in 5: im.fill_rect(Rect2i(5 + i * 3, 16, 2, 9), Color("4a3122"))   # braids
	im.fill_rect(Rect2i(7, 23, 10, 7), Color("ff5fa2"))       # the pink top
	im.fill_rect(Rect2i(9, 10, 2, 2), Color("1a0a0a")); im.fill_rect(Rect2i(13, 10, 2, 2), Color("1a0a0a"))
	im.fill_rect(Rect2i(10, 14, 4, 1), Color("d94f7a"))       # smile
	for i in 24:
		var y := int(i * 30.0 / 24.0)
		for d in 2:
			im.set_pixel(clampi(i + d, 0, 23), y, Color("ff2d2d")); im.set_pixel(clampi(23 - i - d, 0, 23), y, Color("ff2d2d"))
	return im

# the city at night through the glass: a gradient, a red moon, black towers with lit windows (seeded = clean)
func _skyline() -> Image:
	var W := 128; var H := 43
	var im := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		var k := float(y) / H
		var c := Color("12031e").lerp(Color("5a0f3a"), clampf(k / .7, 0, 1)) if k < .7 else Color("5a0f3a").lerp(Color("ff4d6b"), (k - .7) / .3)
		for x in W: im.set_pixel(x, y, c)
	for y in range(-5, 6):
		for x in range(-5, 6): if x * x + y * y <= 25: im.set_pixel(100 + x, 13 + y, Color("ff5a5a"))
	var rng := RandomNumberGenerator.new(); rng.seed = 46
	var x := 0
	var lit := [Color("ffd66b"), Color("ff9ecf"), Color("8ff2ff")]
	while x < W:
		var w := rng.randi_range(5, 12); var h := rng.randi_range(10, 33)
		im.fill_rect(Rect2i(x, H - h, w, h), Color("0c0310"))
		for wy in range(H - h + 2, H - 2, 3):
			for wx in range(x + 1, x + w - 1, 2):
				if wx < W and rng.randf() < .35: im.set_pixel(wx, wy, lit[rng.randi() % 3])
		x += w + rng.randi_range(1, 2)
	for i in 5: im.fill_rect(Rect2i(i * W / 4, 0, 1, H), Color(0, 0, 0, .6))   # the window frames
	return im

func _stripes(base: Color, w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8); im.fill(base)
	for x in range(0, w, 8): im.fill_rect(Rect2i(x, 0, 1, h), base.darkened(.18))
	im.fill_rect(Rect2i(0, h - 3, w, 3), base.darkened(.25))
	return im

func _mob(path: String, at: Vector3, ry: float) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = load(path).instantiate()
	Tint.apply(n); _set.add_child(n); n.position = at; n.rotation.y = ry
	return n

func _build_set() -> void:
	if _set: return
	_set = Node3D.new(); _set.name = "HellspaceSet"; world.add_child(_set); _set.position = HS; _set.visible = false
	# the room, seen from inside
	var room := MeshInstance3D.new(); var rb := BoxMesh.new(); rb.size = Vector3(13, 4.8, 10); rb.flip_faces = true
	room.mesh = rb; room.material_override = _mat(Color("6a2a58"), _tex(_stripes(Color.WHITE, 32, 32)))
	(room.material_override as StandardMaterial3D).albedo_color = Color("5a2450"); room.position.y = 2.4; _set.add_child(room)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(13, 10); fl.mesh = pm
	var fim := Image.create(32, 32, false, Image.FORMAT_RGBA8); fim.fill(Color("5a1020"))
	fim.fill_rect(Rect2i(3, 3, 26, 1), Color("8a4030")); fim.fill_rect(Rect2i(3, 28, 26, 1), Color("8a4030"))
	fim.fill_rect(Rect2i(3, 3, 1, 26), Color("8a4030")); fim.fill_rect(Rect2i(28, 3, 1, 26), Color("8a4030"))
	fl.material_override = _mat(Color.WHITE, _tex(fim)); fl.position.y = .01; _set.add_child(fl)
	# the view: the city at night through a wall of glass + the neon sign
	_quad(_set, Vector2(9, 3), Vector3(0, 2.5, -4.95), 0.0, Color.WHITE, _tex(_skyline()))
	var sign := _text(_set, "HELLSPACE WEALTH", Vector3(0, 4.3, -4.9), 0.0, Color("ff2d2d"), 96, .01)
	sign.outline_size = 12; sign.outline_modulate = Color(1, .1, .1, .35)
	# desk, lamp, monitor
	var dk := Color("2a1420")
	_box(_set, Vector3(3.6, .12, 1.4), Vector3(0, .95, -1.6), dk)
	for sx in [-1.6, 1.6]: _box(_set, Vector3(.15, .9, 1.3), Vector3(sx, .46, -1.6), dk)
	var mon := Node3D.new(); mon.position = Vector3(.9, 1.6, -1.35); mon.rotation.y = -.35; _set.add_child(mon)
	_box(mon, Vector3(1.25, .82, .06), Vector3.ZERO, Color("121218"))
	_box(mon, Vector3(.1, .4, .1), Vector3(0, -.55, 0), Color("121218"))
	_quad(mon, Vector2(1.15, .72), Vector3(0, 0, -.035), PI, Color("10030c"))     # the screen faces Karen (-z)
	_text(mon, "HELLSPACE HR · FILE #0001", Vector3(.0, .29, -.04), PI, Color("ff2d2d"), 22, .0035)
	_quad(mon, Vector2(.26, .33), Vector3(.38, -.02, -.04), PI, Color.WHITE, _tex(_portrait()))
	# (the screen faces -z, so its left edge is at +x)
	var nm := _text(mon, "TORİİ", Vector3(.2, .16, -.04), PI, Color("ffd6d6"), 22, .0035)
	var stt := _text(mon, "STATUS: QUIT", Vector3(.2, .08, -.04), PI, Color("ff6b6b"), 22, .0035)
	_scr_lines = _text(mon, "", Vector3(.2, -.1, -.04), PI, Color("ffe08a"), 18, .0035)
	for L in [nm, stt, _scr_lines]:
		L.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; L.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_cyl(_set, .03, .03, .6, Vector3(-1.3, 1.3, -1.8), dk, 5)
	_cyl(_set, .05, .22, .25, Vector3(-1.3, 1.62, -1.8), Color("ff4d4d"), 10)
	# the Employee of the Month poster she kept, and crossed out
	var post := Node3D.new(); post.position = Vector3(-6.45, 2.5, -1); post.rotation.y = PI / 2; _set.add_child(post)
	_quad(post, Vector2(1.3, 1.7), Vector3.ZERO, 0.0, Color("f2e8d8"))
	_text(post, "EMPLOYEE\nOF THE MONTH", Vector3(0, .62, .01), 0.0, Color("8e2438"), 28, .005)
	_quad(post, Vector2(.62, .78), Vector3(0, .02, .01), 0.0, Color.WHITE, _tex(_portrait()))
	_text(post, "TORİİ\n2019 · 2020 · 2021", Vector3(0, -.6, .01), 0.0, Color("1a1a1a"), 24, .005)
	for s in [-1, 1]: _box(post, Vector3(1.9, .06, .01), Vector3(0, 0, .02), Color("ff1a1a"), Vector3(0, 0, s * .92))
	# filing cabinets and a sad office plant
	for i in 3: _box(_set, Vector3(.9, 1.5, .7), Vector3(5.6, .75, -3.8 + i * 1.1), Color("4a4a5a"))
	_cyl(_set, .3, .24, .5, Vector3(-5.4, .25, -4), Color("6b3a2a"))
	for i in 8:
		var a := i / 8.0 * TAU; var tl := .45 + (i % 3) * .15
		_box(_set, Vector3(.08, .8, .03), Vector3(-5.4 + sin(a) * .12, .85, -4 + cos(a) * .12), Color("8a9a4a"), Vector3(cos(a) * tl, 0, -sin(a) * tl))
	# a warm red light so the cast reads
	var om := OmniLight3D.new(); om.light_color = Color(1, .45, .5); om.light_energy = 1.6; om.omni_range = 11; om.position = Vector3(0, 3.6, 1)
	_set.add_child(om)
	var om2 := OmniLight3D.new(); om2.light_color = Color(1, .3, .45); om2.light_energy = .9; om2.omni_range = 7; om2.position = Vector3(0, 2, -3.8)
	_set.add_child(om2)
	# the cast
	_karen = _mob("res://assets/mobs/karen.glb", Vector3(0, 0, -2.7), 0.0)
	if _karen:
		_karen_head = _karen.find_child("head", true, false) as Node3D
		for a in _karen.find_children("arm_*", "", true, false): (a as Node3D).rotation.x = -.25
	_imp = _mob("res://assets/imp/imp.glb", Vector3(2.8, 0, -.4), -.6)
	if _imp: _cyl(_imp, .08, .06, .16, Vector3(.3, .95, .3), Color("f2f2f2"))
	_zomb = _mob("res://assets/mobs/zombie.glb", Vector3(-2.9, 0, -.7), .5)
	if _zomb: for a in _zomb.find_children("arm_*", "", true, false): (a as Node3D).rotation.x = -.4

func _paint(txt: String) -> void:
	if _scr_lines: _scr_lines.text = txt

func _anim_set() -> void:
	if _karen:
		_karen.position.y = sin(_t * 1.3) * .01
		if _karen_head: _karen_head.rotation.y = sin(_t * .7) * .25
	if _imp: _imp.position.y = absf(sin(_t * 6)) * .12; _imp.rotation.z = sin(_t * 6) * .08
	if _zomb: _zomb.rotation.z = .08 + sin(_t * .9) * .05
