# The HUD: 7.2's #hud (updateHUD) made into a PS1 action-RPG HUD, in 7.2's neon colours, at full window
# resolution on top of the pixelated 3D. Top left: the level badge, HP (with the number, a white damage
# trail and a jiggle when she's hit), MANA, STAMINA (fades away when full, NEFES NEFESE when winded) and
# XP bars, then 7.2's #stats (clock, unit/lesson tag, LVL + outfit name (COSTUMES), INT, words, lira that rolls up, ammo, the food line)
# and the buff chips (updateBuffs). Top right: the round minimap (minimap.gd, 7.2's drawMinimap) with the
# objective under it. Top centre: a compass with the objective on it, and the boss bar (name, phase
# marks). Bottom: the current weapon (durability, ammo, rarity colour; 7.2's weapon line) and the skill
# bar (hotbar.gd, 7.2's #skills). In the world: the lock-on reticle with the target's name, level and HP,
# small bars over monsters she just hit, and an on-screen objective marker that slides to the screen
# edge when it's off-screen. Low HP: the screen edges pulse red (and a heartbeat "sfx").
# Also still: the dialogue box (Kaan's calls, people talking), the choice box, banners, the toast stack,
# SKIP THIS LESSON / SAVE & LOAD, crosshair + click-to-look hint, LOOKING BACK [C].
# Text takes 7.2's markup as BBCode ([b], [i]). Keys like 7.2: E / Enter / Space next line, ESC skips the
# rest of a call, 1-9 picks a choice, E closes it.
# Other systems are optional: Skills.me (hotbar(), active_buffs()), Arsenal.me (hud_info()), player fields
# (mana, stamina, lock_target...) are all read defensively, so the HUD works before they exist.
class_name Hud
extends CanvasLayer

signal save_pressed

var hp_bar: ProgressBar
var obj: RichTextLabel
var ban: RichTextLabel
var toasts: VBoxContainer
var box: PanelContainer
var who: Label
var line: RichTextLabel
var hint: Label
var skip_btn: Button
var save_btn: Button
var look_label: Label
var cross: ColorRect
var lock_hint: PanelContainer
var _ban_t := 0.0
var _say_who := ""
var _say_q: Array = []
var _say_done: Callable
# ---- the action-RPG part ----
const STATS_Y := 74.0
var C_PINK := Color("ff5fa2")
var C_CYAN := Color("7bf7ff")
var C_GOLD := Color("ffd66b")
var C_PURP := Color("b06bff")
# 7.2's RARCOL
const RARCOL := {"Unarmed": "e8e8f2", "Common": "b8b8c4", "Uncommon": "5fff9e", "Rare": "5fb0ff", "Epic": "c07bff",
	"LEGENDARY": "ffa53a", "CURSED": "ff3b3b", "TAVLA CHAMPION": "ffd66b", "Mission": "ff5fa2",
	"Mission · FEARED": "ff2d5e", "Mission · RIGGED": "ffd66b", "MISSION LEGENDARY": "ffe9a0"}
# 7.2's COSTUMES names (applyCostume: her outfit follows her level, 1..30)
const FITS := ["Şehirli Kız · Street Fit", "Plaj Bikinisi · Beach Bikini", "Yazlık Elbise · Sundress",
	"Spor Kıyafeti · Gym Fit", "Hemşire · Nurse", "Doktor · Doctor", "Bilim İnsanı · Scientist", "Polis · Police",
	"DJ TORİİ 🎧", "Şef · Chef Whites 👩‍🍳", "Pilot · Aviator ✈️", "Astronot · Astronaut 👩‍🚀", "Dansçı · Ballerina 🩰",
	"Kaşif · Explorer 🧭", "Kraliçe · Neon Queen 👑", "Korsan · Pirate 🏴‍☠️", "Ninja · Gece Gölgesi 🥷",
	"Melek · Neon Angel 😇", "EFSANE TORİİ · LEGEND 🌟", "Pazarcı · Bazaar Trader 🧿", "Kaptan · Sea Captain ⚓",
	"Zeybek · Efe Warrior ⚔️", "Şarkıcı · Pop Star 🎤", "Kış Modası · Winter Coat 🧥", "Çiftçi · Vineyard Farmer 🍇",
	"Sanatçı · Painter 🎨", "Mimar · Architect 📐", "Tanrıça · Neon Goddess 🔮", "Antalya Rüyası · Dream 🌴",
	"TORİİ THE ETERNAL 👑✨"]
# 7.2's FOOD icons, for the snack line
const FOOD_IC := {"simit": "🥯", "doner": "🥙", "borek": "🥟", "kaktus": "🌵", "ayran": "🥛", "cay": "🫖",
	"kahve": "☕", "baklava": "🍯", "lokum": "🍬", "matcha": "🍵"}
var player: Node3D                  # set by bind()
var pins := {}                      # id -> {pos: Vector3, col: Color}: extra map/compass markers (quests, bounties)
var minimap: Control
var hotbar: Control
var _font: FontVariation
var _cv: Control
var _low: ColorRect
var _stats: RichTextLabel
var _pops: Array = []               # HUD-space "+12 XP" / "+₺30" pop-ups
var _t := 0.0
var _hp := 100.0
var _mhp := 100.0
var _hp_trail := 1.0                # the white part of the HP bar that drains after a hit
var _hp_jig := 0.0
var _stam_a := 1.0
var _stam_full_t := 0.0
var _xp_show := 0.0                 # 0..1, eases to the real fill
var _lvl := -1
var _lvl_pulse := 0.0
var _lira := -1
var _lira_show := 0.0
var _xp_last := -1
var _poll := 0.0
var _night := false
var _recent := {}                   # Enemy -> seconds its little bar stays up after she hits it
var _boss: Node3D
var _boss_trail := 1.0
var _boss_scan := 0.0
var _beat := 0.0
var _marker = null                  # set_marker(): a custom objective point (Vector3) instead of the mission beam
static var _cls := {}
var _bound := false
static var _wstats := {}
var _low_mat: ShaderMaterial

func _ready() -> void:
	hp_bar = ProgressBar.new(); hp_bar.position = Vector2(14, 12); hp_bar.size = Vector2(220, 18)
	hp_bar.show_percentage = false; hp_bar.max_value = 100; hp_bar.value = 100
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("ff5fa2"); hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, .55); hp_bar.add_theme_stylebox_override("background", bg)
	add_child(hp_bar); hp_bar.visible = false          # kept for anything that reads it; the drawn bars below show HP
	_font = FontVariation.new(); _font.base_font = ThemeDB.fallback_font; _font.variation_embolden = .6
	# low HP: the screen edges pulse red, under everything else on the HUD
	_low = ColorRect.new(); _low.set_anchors_preset(Control.PRESET_FULL_RECT); _low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsh := Shader.new()
	lsh.code = """shader_type canvas_item;
uniform float amt = 0.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float e = smoothstep(0.45, 1.3, max(d.x, d.y) * 0.5 + length(d) * 0.5);
	COLOR = vec4(1.0, 0.1, 0.25, e * amt);
}"""
	var lsm := ShaderMaterial.new(); lsm.shader = lsh; _low.material = lsm; _low_mat = lsm; add_child(_low)
	# everything drawn by hand (bars, badge, compass, boss bar, reticle, markers, weapon, buffs)
	_cv = Control.new(); _cv.set_anchors_preset(Control.PRESET_FULL_RECT); _cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cv); _cv.draw.connect(_draw_hud)
	_stats = _rich(Vector2(12, STATS_Y), Vector2(330, 122), 12, Color("e8dcff"))
	_stats.add_theme_constant_override("outline_size", 4)
	for i in 6:
		var pl := _label(Vector2.ZERO, "", 14, Color.WHITE); pl.visible = false
		_pops.append({"n": pl, "t": 0.0})
	obj = _rich(Vector2(590, 154), Vector2(362, 110), 15, Color("7bf7ff"))       # under the minimap
	ban = _rich(Vector2(0, 236), Vector2(960, 70), 30, Color("ffd66b"))
	# 7.2's #toasts: a column at the bottom, up to three at once, newest last
	toasts = VBoxContainer.new(); toasts.position = Vector2(80, 300); toasts.size = Vector2(800, 340)
	toasts.alignment = BoxContainer.ALIGNMENT_END; toasts.add_theme_constant_override("separation", 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(toasts)
	box = PanelContainer.new(); box.position = Vector2(120, 560); box.size = Vector2(720, 130); box.visible = false
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.08, .04, .14, .92); sb.border_color = Color("ff5fa2")
	sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.set_content_margin_all(14)
	box.add_theme_stylebox_override("panel", sb); add_child(box)
	var v := VBoxContainer.new(); box.add_child(v)
	who = Label.new(); who.add_theme_color_override("font_color", Color("ff5fa2")); who.add_theme_font_size_override("font_size", 16); v.add_child(who)
	line = RichTextLabel.new(); line.bbcode_enabled = true; line.fit_content = true; line.scroll_active = false
	line.custom_minimum_size = Vector2(690, 0); _sizes(line, 18); v.add_child(line)
	hint = Label.new(); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color("7bf7ff")); hint.add_theme_font_size_override("font_size", 13); v.add_child(hint)
	# 7.2's #skipBtn: a standing reminder that K tests her out of a lesson (click it once the mouse is free)
	# (under the bars, above where the lesson/quiz panel starts; the stats block moves down while it shows)
	skip_btn = _button("⏭ SKIP THIS LESSON\nAlready know it? Answer 3 questions\ncorrectly and move on.  [K]", Vector2(10, STATS_Y - 2), Color("3dff9e"), 11)
	skip_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT; skip_btn.visible = false
	save_btn = _button("💾 SAVE & LOAD", Vector2(800, 684), Color("7bf7ff"), 13)
	save_btn.pressed.connect(func(): save_pressed.emit())
	# 7.2's #cross / #lockHint / LOOKING BACK [C]
	cross = ColorRect.new(); cross.color = Color("7bf7ff"); cross.size = Vector2(5, 5); cross.position = Vector2(478, 358)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(cross)
	lock_hint = PanelContainer.new(); lock_hint.position = Vector2(300, 38); lock_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE    # under the compass, clear of the toasts
	var hs := StyleBoxFlat.new(); hs.bg_color = Color(.04, .02, .08, .85); hs.border_color = Color("7bf7ff")
	hs.set_border_width_all(2); hs.set_corner_radius_all(10); hs.set_content_margin_all(9)
	lock_hint.add_theme_stylebox_override("panel", hs); add_child(lock_hint)
	var hl := Label.new(); hl.text = "🖱 Click to look around  ·  ESC to release the mouse"
	hl.add_theme_font_size_override("font_size", 14); hl.add_theme_color_override("font_color", Color("bfeefc")); lock_hint.add_child(hl)
	look_label = _label(Vector2(800, 656), "👁 LOOKING BACK [C]", 13, Color("ffd66b")); look_label.visible = false

func _label(at: Vector2, t: String, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = t; l.position = at; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col); l.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	l.add_theme_constant_override("outline_size", 5); l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l); return l

func _button(t: String, at: Vector2, col: Color, size: int) -> Button:
	var b := Button.new(); b.text = t; b.position = at; b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size); b.add_theme_color_override("font_color", Color("d8ffe8"))
	var st := StyleBoxFlat.new(); st.bg_color = Color(.05, .12, .1, .88); st.border_color = col
	st.set_border_width_all(2); st.set_corner_radius_all(8); st.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", st); b.add_theme_stylebox_override("pressed", st)
	add_child(b); return b

func _sizes(r: RichTextLabel, size: int) -> void:
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: r.add_theme_font_size_override(k, size)

func _rich(at: Vector2, sz: Vector2, size: int, col: Color) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.position = at; r.size = sz; r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.add_theme_color_override("default_color", col); _sizes(r, size)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); r.add_theme_constant_override("outline_size", 6)
	add_child(r); return r

func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp; hp_bar.value = hp
	if hp < _hp: _hp_jig = .3                       # hit: the bar jiggles, the white trail drains after
	_hp = float(hp); _mhp = maxf(1.0, float(max_hp))
	if _hp / _mhp > _hp_trail: _hp_trail = _hp / _mhp

# main calls this once Torii exists: the bars, the minimap and the skill bar follow her from then on
func bind(p: Node3D) -> void:
	player = p
	if p.has_signal("hp_changed") and not p.is_connected("hp_changed", set_hp): p.connect("hp_changed", set_hp)
	if p.get("hp") != null and p.get("max_hp") != null: set_hp(int(p.get("hp")), int(p.get("max_hp")))
	if not minimap:
		var mm = preload("res://scripts/minimap.gd").new(); add_child(mm); move_child(mm, _cv.get_index() + 1)
		mm.setup(p, self); minimap = mm
	if not hotbar:
		var hb = preload("res://scripts/hotbar.gd").new(); add_child(hb); hb.setup(self); hotbar = hb
	if _bound: return
	_bound = true
	for ev in ["xp", "lira", "level_up"]: Bus.on(ev, func(_d): _poll = 0.0)
	Bus.on("enemy_hit", func(d):
		var e = d.get("enemy")
		if is_instance_valid(e) and e is Node3D: _recent[e] = 3.0)
	Bus.on("enemy_died", func(d): _recent.erase(d.get("enemy")))
	Bus.on("night", func(d): _night = bool(d.get("on", false)))
	Bus.on("player_hit", func(_d): _hp_jig = .3)

# another system's singleton (Skills.me, Arsenal.me...) without naming its class, so this file still
# parses before that system exists
func _script(cname: String) -> Script:
	if not _cls.has(cname):
		var sc: Script = null
		for c in ProjectSettings.get_global_class_list():
			if c["class"] == cname: sc = load(c["path"]); break
		_cls[cname] = sc
	return _cls[cname]

func sys(cname: String) -> Object:
	var s := _script(cname)
	if s == null: return null
	var o = s.get("me")
	return o if is_instance_valid(o) else null

# a custom objective point for the compass, minimap and on-screen marker (null = the mission beam again)
func set_marker(at) -> void: _marker = at
func pin(id: String, at: Vector3, col := Color("3dff9e")) -> void: pins[id] = {"pos": at, "col": col}
func unpin(id: String) -> void: pins.erase(id)

func objective_point() -> Variant:
	if _marker is Vector3: return _marker
	var ms := sys("Missions")
	var bm = ms.get("beam") if ms else null
	if bm is Node3D and is_instance_valid(bm) and bm.visible:
		var b: Vector3 = bm.global_position
		return Vector3(b.x, (player.global_position.y if player else 0.0) + 1.6, b.z)
	return null

func objective(t: String) -> void: obj.text = "[right]%s[/right]" % t
func banner(t: String) -> void: ban.text = "[center]%s[/center]" % t; _ban_t = 3.0

# 7.2's toast(html, ms, bad): up to three stacked, each on its own timer; bold words in cyan like .toast b;
# a red border for warnings
func toast(t: String, dur := 6.0, bad := false) -> void:
	if OS.get_cmdline_user_args().has("--toastlog"): print("TOAST %d %s" % [Time.get_ticks_msec(), Rich.plain(t)])
	while toasts.get_child_count() >= 3:
		var old := toasts.get_child(0); toasts.remove_child(old); old.queue_free()
	if toasts.get_child_count() >= 2:          # a third one coming: the oldest steps aside soon, so three don't wall her off
		var o := toasts.get_child(0); o.set_meta("t", minf(float(o.get_meta("t", 1.2)), 1.2))
	var p := PanelContainer.new(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(20 / 255.0, 8 / 255.0, 38 / 255.0, .92)
	sb.border_color = Color("ff3b3b") if bad else Color("ff5fa2"); sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	sb.content_margin_left = 20; sb.content_margin_right = 20; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; _sizes(r, 17)
	r.text = "[center]%s[/center]" % t.replace("[b]", "[b][color=#7bf7ff]").replace("[/b]", "[/color][/b]")
	# as wide as its longest line (7.2's toasts hug their text), 620 at most, so three don't wall her off
	var widest := 0.0
	var fnt := r.get_theme_font("bold_font")
	for ln in _untag(t).split("\n"): widest = maxf(widest, fnt.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
	r.custom_minimum_size = Vector2(clampf(widest + 12.0, 160.0, 620.0), 0)
	p.add_child(r); p.set_meta("t", dur); toasts.add_child(p)

static func _untag(t: String) -> String:
	var re := RegEx.new(); re.compile("\\[[^\\]]*\\]")
	return re.sub(t, "", true)

# ---- the dialogue box: Kaan's calls and anyone talking (7.2's say() / playCall) ----
func say(who_: String, lines: Array, done := Callable()) -> void:
	_say_who = who_; _say_q = lines.duplicate(); _say_done = done
	if _say_q.is_empty(): _say_q = [""]
	_show_line()

func _show_line() -> void:
	box.visible = true; Overlay.open("say")
	who.text = _say_who; line.text = str(_say_q[0]); hint.text = "[E] continue  ·  ESC skip"

func next_line() -> void:
	if not box.visible: return
	_say_q.pop_front()
	if _say_q.size(): _show_line()
	else: _close_say()

func skip_say() -> void:
	if not box.visible: return
	_say_q.clear(); _close_say()

func _close_say() -> void:
	box.visible = false; Overlay.close("say")
	var cb := _say_done; _say_done = Callable()
	if cb.is_valid(): cb.call()

# ---- a question with numbered answers (the bazaar haggle, the gods' coin game): 7.2's dlgChoices ----
# cb gets the answer's index, or -1 when she closes it with E
var _choice: PanelContainer
var _choice_cb: Callable
var _choice_n := 0
var _choice_frame := -1                # the frame it opened in: that frame's key press isn't an answer
func choose(who_: String, text_: String, opts: Array, cb: Callable) -> void:
	_choice_frame = Engine.get_process_frames()
	if _choice: _choice.queue_free()
	_choice = PanelContainer.new(); _choice.position = Vector2(140, 200); _choice.size = Vector2(680, 0)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, 1); sb.border_color = Color("ffd66b")
	sb.set_border_width_all(2); sb.set_corner_radius_all(12); sb.set_content_margin_all(18)
	_choice.add_theme_stylebox_override("panel", sb); add_child(_choice)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); _choice.add_child(v)
	var w := Label.new(); w.text = who_; w.add_theme_color_override("font_color", Color("ffd66b")); w.add_theme_font_size_override("font_size", 16); v.add_child(w)
	var q := RichTextLabel.new(); q.bbcode_enabled = true; q.fit_content = true; q.scroll_active = false; q.text = text_
	q.custom_minimum_size = Vector2(640, 0); _sizes(q, 18); v.add_child(q)
	for i in opts.size():
		var b := Button.new(); b.text = "%d. %s" % [i + 1, Rich.plain(str(opts[i]))]; b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(_pick_choice.bind(i)); v.add_child(b)
	var h := Label.new(); h.text = "[1-%d] choose  ·  [E] close" % opts.size(); h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_theme_color_override("font_color", Color("7bf7ff")); h.add_theme_font_size_override("font_size", 13); v.add_child(h)
	_choice_cb = cb; _choice_n = opts.size()
	Overlay.open("choice")

func _pick_choice(i: int) -> void:
	if not _choice: return
	_choice.queue_free(); _choice = null; Overlay.close("choice")
	var cb := _choice_cb; _choice_cb = Callable()
	if cb.is_valid(): cb.call(i)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	if QuizUI.open or Overlay.is_open("save"): return       # the panel on top owns the keys
	var k: int = e.keycode
	if _choice:
		if Engine.get_process_frames() == _choice_frame: return
		if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < _choice_n: _pick_choice(k - KEY_1)
		elif k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER: _pick_choice(-1)    # 7.2's dlgNext closes a choice
		else: return
		get_viewport().set_input_as_handled()
	elif box.visible:
		if k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE: next_line()
		elif k == KEY_ESCAPE: skip_say()
		else: return
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_ban_t -= dt
	ban.visible = _ban_t > 0
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cross.visible = captured and not Overlay.any()
	lock_hint.visible = not captured and not Overlay.any()
	# toasts sit low (under her body, above the skill bar) like 7.2's; above the call box while it's up
	toasts.position.y = 210.0 if box.visible else 300.0
	for p in toasts.get_children():
		var left: float = p.get_meta("t") - dt; p.set_meta("t", left)
		if left <= 0: toasts.remove_child(p); p.queue_free()
	if player and _alive(player.get("lock_target")): cross.visible = false     # the reticle takes over
	_t += dt
	_tick(dt)
	_cv.queue_redraw()

# ---------------- the action-RPG HUD ----------------
func _pv(k: String, def: float) -> float:
	if not player: return def
	var v = player.get(k)
	return float(v) if (v is int or v is float) else def

func _alive(e) -> bool:
	if e == null or not is_instance_valid(e) or not (e is Node3D) or not e.is_inside_tree(): return false
	if e.has_method("is_alive"): return e.is_alive()
	var h = e.get("hp")
	return h == null or float(h) > 0

func _pop(t: String, at: Vector2, col: Color) -> void:
	for P in _pops:
		if P["t"] > 0: continue
		var n: Label = P["n"]; n.text = t; n.add_theme_color_override("font_color", col)
		n.position = at; n.visible = true; P["t"] = 1.2; return

func _tick(dt: float) -> void:
	# bars ease, the trail drains, low HP pulses
	var hpf := _hp / _mhp
	_hp_trail = maxf(hpf, _hp_trail - dt * (.35 if _hp_trail - hpf < .3 else .8))
	_hp_jig = maxf(0.0, _hp_jig - dt)
	_lvl_pulse = maxf(0.0, _lvl_pulse - dt)
	var low: bool = player != null and player.get("dead") != true and hpf < .3 and _hp > 0
	var la := 0.0
	if low:
		la = (.35 + .25 * sin(_t * 6.0)) * (1.0 - hpf / .3 * .5)
		_beat -= dt
		if _beat <= 0: _beat = .9; Bus.emit_ev("sfx", {"name": "heartbeat"})
	_low_mat.set_shader_parameter("amt", la)
	# stamina: fades out after a second at full, comes straight back when she uses it
	var st := _pv("stamina", 100.0); var mst := maxf(1.0, _pv("max_stamina", 100.0))
	if st >= mst - .5 and player and player.get("winded") != true: _stam_full_t += dt
	else: _stam_full_t = 0.0
	_stam_a = move_toward(_stam_a, 0.0 if _stam_full_t > 1.2 else 1.0, dt * (1.5 if _stam_full_t > 1.2 else 8.0))
	# the save-side numbers: a few times a second (Bus xp/lira/level_up refresh it straight away)
	_poll -= dt
	if _poll <= 0:
		_poll = .25; _read_save()
	_lira_show = move_toward(_lira_show, float(_lira), maxf(1.0, absf(float(_lira) - _lira_show)) * dt * 6.0)
	var xpf := float(SaveBridge.get_i("xp")) / maxf(1.0, float(SaveBridge.get_i("need", SaveBridge.xp_for(maxi(1, _lvl)))))
	_xp_show = move_toward(_xp_show, clampf(xpf, 0, 1), dt * 1.2)
	_stats_text()
	for P in _pops:
		if P["t"] <= 0: continue
		P["t"] -= dt
		var n: Label = P["n"]
		n.position.y -= dt * 22.0; n.modulate.a = clampf(P["t"] / .5, 0, 1)
		if P["t"] <= 0: n.visible = false
	# monsters she just hit keep a small bar a few seconds
	for e in _recent.keys():
		_recent[e] -= dt
		if _recent[e] <= 0 or not _alive(e): _recent.erase(e)
	# the boss bar: the mission boss, else a boss / miniboss close by
	_boss_scan -= dt
	if _boss_scan <= 0:
		_boss_scan = .3; _boss = null
		var ms := sys("Missions")
		var qs := sys("Quests")
		if ms and _alive(ms.get("boss")): _boss = ms.get("boss")
		elif qs and _alive(qs.get("boss")): _boss = qs.get("boss")
		elif player:
			for e in get_tree().get_nodes_in_group("enemies"):
				var fl = e.get("flags")
				if fl is Dictionary and (fl.has("boss") or fl.has("miniboss")) and _alive(e) and e.global_position.distance_to(player.global_position) < 45.0:
					_boss = e; break
	if _alive(_boss):
		var f := float(_boss.get("hp")) / maxf(1.0, float(_boss.get("max_hp")))
		_boss_trail = maxf(f, _boss_trail - dt * .3)
	else: _boss_trail = 1.0

func _read_save() -> void:
	var lvl := SaveBridge.get_i("lvl", 1)
	if _lvl >= 0 and lvl > _lvl: _lvl_pulse = 1.6; _pop("LEVEL UP!", Vector2(64, 66), C_GOLD)
	var xp := SaveBridge.get_i("xp")
	if _xp_last >= 0 and lvl == _lvl and xp > _xp_last: _pop("+%d XP" % (xp - _xp_last), Vector2(280, 52), Color("ffe08a"))
	_lvl = lvl; _xp_last = xp
	var li := SaveBridge.get_i("lira")
	if _lira < 0: _lira_show = li
	elif li != _lira:
		_pop(("+₺%d" % (li - _lira)) if li > _lira else ("−₺%d" % (_lira - li)), Vector2(110, _stats.position.y - 4), C_GOLD if li > _lira else Color("ff6b6b"))
	_lira = li

func _stats_text() -> void:
	var d := SaveBridge.data
	var lines: Array = []
	var sky := sys("SkyCycle")                  # sky.gd's clock (the same, dawn-aware hour the sky shows)
	var dn := sys("DayNight")
	if sky and sky.has_method("clock_text"):
		lines.append(str(sky.call("clock_text")))
	elif dn and dn.get("hour") != null:
		var h := float(dn.get("hour"))
		var pod: Array = ["gece", "night", "🌙"] if h < 5.2 or h >= 20.4 else ["şafak", "dawn", "🌅"] if h < 7 else ["sabah", "morning", "🌤"] if h < 11 else ["öğle", "midday", "☀️"] if h < 15 else ["ikindi", "afternoon", "🌇"] if h < 18.4 else ["akşam", "evening", "🌆"]
		lines.append("%s %02d:%02d [color=#bfb0dd]%s · %s[/color]" % [pod[2], int(h), int(fmod(h, 1.0) * 60), pod[0], pod[1]])
	elif _night: lines.append("🌙 [color=#bfb0dd]gece · night[/color]")
	var unit := SaveBridge.get_i("unit", 1)
	var ms = d.get("mastered", {})
	var done: bool = ms is Dictionary and (ms.get(str(unit)) == true or ms.get(unit) == true)
	lines.append("📖 [b][color=#8ff2ff]UNIT %d/16[/color][/b] [color=#bfb0dd]ders %d/3[/color]%s" % [unit, mini(SaveBridge.get_i("ul"), 3), " [color=#3dff9e]✅[/color]" if done else ""])
	lines.append("LVL [b][color=#ffd66b]%d[/color][/b] · [color=#ff9ecf]%s[/color]" % [maxi(1, _lvl), FITS[clampi(maxi(1, _lvl), 1, FITS.size()) - 1]])
	var words: int = (d.get("words", []) as Array).size() if d.get("words") is Array else 0
	lines.append("🧠 INT [b][color=#ffd66b]%d[/color][/b] · 📚 WORDS [b][color=#ffd66b]%d[/color][/b]" % [SaveBridge.get_i("int"), words])
	lines.append("₺ [b][color=#ffd66b]%d[/color][/b] · 💵 AMMO [b][color=#ffd66b]%d[/color][/b]" % [int(round(_lira_show)), SaveBridge.get_i("ammo")])
	var bag = d.get("bag", {})
	var food := ""
	if bag is Dictionary:
		var n := 0
		for k in bag:
			if int(bag[k]) <= 0: continue
			n += 1
			if n <= 4: food += "%s×%d " % [FOOD_IC.get(k, "🍴"), int(bag[k])]
		if n > 4: food += "… "
	lines.append("🎒 %s[color=#9a8cc0][H eat · I bag][/color]" % (food if food != "" else "no food "))
	var tx := "\n".join(lines)
	if _stats.text != tx: _stats.text = tx
	# the SKIP button sits where the stats start; push them below it while it shows
	_stats.position.y = STATS_Y + (70.0 if skip_btn.visible else 0.0)
	_stats.visible = not Overlay.any()

# ---- drawing helpers ----
func _text(c: CanvasItem, at: Vector2, t: String, sz: int, col: Color, al := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	c.draw_string_outline(_font, at, t, al, w, sz, 4, Color(0, 0, 0, .85 * col.a))   # the outline fades with the text
	c.draw_string(_font, at, t, al, w, sz, col)

func _grad(r: Rect2, a: Color, b: Color) -> void:
	if r.size.x <= .5: return
	_cv.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([a, b, b, a]))

# 7.2's .bar: dark box, purple border, a two-tone glowing fill, the label inside
func _bar(r: Rect2, f: float, trail: float, a: Color, b: Color, txt: String, alpha := 1.0) -> void:
	f = clampf(f, 0, 1)
	_cv.draw_rect(r.grow(2), Color(.29, .23, .4, alpha))
	_cv.draw_rect(r, Color(.086, .06, .133, alpha))
	if trail > f: _cv.draw_rect(Rect2(r.position + Vector2(r.size.x * f, 0), Vector2(r.size.x * (clampf(trail, 0, 1) - f), r.size.y)), Color(1, .9, .95, .6 * alpha))
	var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
	if fr.size.x > 1: _cv.draw_rect(fr.grow(1.5), Color(a, .22 * alpha))
	_grad(fr, Color(a, alpha), Color(b, alpha))
	if fr.size.x > 1: _cv.draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(1.0, r.size.y * .3))), Color(1, 1, 1, .16 * alpha))
	if txt != "": _text(_cv, Vector2(r.position.x + 5, r.position.y + r.size.y * .5 + 3.6), txt, 10, Color(1, 1, 1, alpha))

func _panel(r: Rect2, border: Color, glow := 0.0) -> void:
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(16 / 255.0, 7 / 255.0, 30 / 255.0, .85); sb.border_color = border
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	if glow > 0: sb.shadow_color = Color(border, .45 * glow); sb.shadow_size = int(10 * glow)
	_cv.draw_style_box(sb, r)

# world -> HUD: the 3D renders in a SubViewport at 1/3, the HUD at full res
func _to_screen(at: Vector3) -> Variant:
	var cam: Camera3D = player.get("cam") if player else null
	if not cam or not cam.is_inside_tree() or cam.is_position_behind(at): return null
	var ratio := get_viewport().get_visible_rect().size / cam.get_viewport().get_visible_rect().size
	return cam.unproject_position(at) * ratio

func _ename(e: Node) -> String:
	var ty = e.get("type")
	if ty == null: ty = e.get("kind")
	var nm := str(ty).capitalize() if ty != null else "?"
	var en = _script("Enemy")
	var data = en.get("DATA") if en else null
	if ty != null and data is Dictionary and data.has(str(ty)) and data[str(ty)] is Dictionary: nm = str(data[str(ty)].get("name", nm))
	return nm

func _top_of(e: Node3D) -> Vector3:
	var fl = e.get("flags")
	var sc := float(e.get("base_scale")) if e.get("base_scale") != null else 1.0
	var h := 3.0 if (fl is Dictionary and fl.has("boss")) else 1.7
	return e.global_position + Vector3(0, h * sc, 0)

func _draw_hud() -> void:
	var busy := Overlay.any()
	_draw_bars()
	if player and not busy:
		_draw_world()
		_draw_compass()
	_draw_boss()
	if not busy:
		_draw_buffs()
		_draw_weapon()

func _draw_bars() -> void:
	# the level badge
	var pul := _lvl_pulse / 1.6
	var br := Rect2(10, 10, 46, 46).grow(pul * 3.0)
	_panel(br, C_GOLD.lerp(Color.WHITE, pul), .6 + pul)
	_text(_cv, Vector2(10, 25), "LV", 10, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, 46)
	_text(_cv, Vector2(10, 49), str(maxi(1, _lvl)), 22 if _lvl < 100 else 16, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 46)
	var x := 64.0
	var jig := Vector2(sin(_t * 70.0) * 3.0 * _hp_jig / .3, 0)
	var hpf := _hp / _mhp
	var low := hpf < .3 and _hp > 0
	var ha := Color("ff2d78"); var hb := Color("ff7ab0")
	if low: ha = ha.lerp(Color.WHITE, (.5 + .5 * sin(_t * 9.0)) * .35)
	_bar(Rect2(Vector2(x, 10) + jig, Vector2(210, 16)), hpf, _hp_trail, ha, hb, "HP %d" % ceili(_hp))
	var mm := maxf(1.0, _pv("max_mana", float(SaveBridge.get_i("mm", 100))))
	var mn := _pv("mana", 0.0)
	_bar(Rect2(x, 31, 210, 11), mn / mm, 0, Color("19c8e6"), Color("8ff2ff"), "MANA %d" % roundi(mn))
	var st := _pv("stamina", 100.0); var mst := maxf(1.0, _pv("max_stamina", 100.0))
	if player and player.get("winded") == true:
		_bar(Rect2(x, 46, 210, 11), st / mst, 0, Color("8a6a2a"), Color("c8a83a"), "NEFES NEFESE", 1.0)
	elif _stam_a > .02:
		_bar(Rect2(x, 46, 210, 11), st / mst, 0, Color("3dff9e"), Color("c8ff8f"), "STAMINA %d" % roundi(st), _stam_a)
	var need := maxi(1, SaveBridge.get_i("need", SaveBridge.xp_for(maxi(1, _lvl))))
	var xr := Rect2(x, 61 if _stam_a > .02 or (player and player.get("winded") == true) else 46, 210, 9)
	_bar(xr, _xp_show, 0, Color("ffb52d"), Color("ffe08a"), "")
	_text(_cv, Vector2(x + 5, xr.position.y + 8), "XP %d/%d" % [SaveBridge.get_i("xp"), need], 9, Color.WHITE)
	if SaveBridge.get_i("pp") > 0: _text(_cv, Vector2(x + 214, 70), "★%d" % SaveBridge.get_i("pp"), 11, C_GOLD)

# the reticle on her lock-on target, little bars over what she just hit, and the objective marker
func _draw_world() -> void:
	var lt = player.get("lock_target")
	var locked: bool = _alive(lt)
	for e in _recent:
		if e == lt or e == _boss or not _alive(e): continue
		var sp = _to_screen(_top_of(e))
		if sp == null: continue
		var a := clampf(_recent[e] / .6, 0, 1)
		var f := float(e.get("hp")) / maxf(1.0, float(e.get("max_hp")))
		var r := Rect2(sp - Vector2(22, 0), Vector2(44, 4))
		_cv.draw_rect(r.grow(1), Color(0, 0, 0, .7 * a)); _grad(Rect2(r.position, Vector2(44 * clampf(f, 0, 1), 4)), Color(1, .23, .3, a), Color(1, .5, .6, a))
	if locked:
		var sp = _to_screen(_top_of(lt) + Vector3(0, -.6, 0))
		if sp != null:
			var s := 20.0 + sin(_t * 6.0) * 2.0
			var col := C_PINK
			for i in 4:
				var a := _t * 1.6 + i * PI * .5
				var c: Vector2 = sp + Vector2(cos(a), sin(a)) * s
				var t1 := Vector2(cos(a + 2.4), sin(a + 2.4)) * 8.0; var t2 := Vector2(cos(a - 2.4), sin(a - 2.4)) * 8.0
				_cv.draw_polyline(PackedVector2Array([c + t1, c, c + t2]), Color(0, 0, 0, .6), 4.0)
				_cv.draw_polyline(PackedVector2Array([c + t1, c, c + t2]), col, 2.0)
			_cv.draw_circle(sp, 2.5, col)
			# name, level (red when she's well under it), HP
			var tp = _to_screen(_top_of(lt) + Vector3(0, .5, 0))
			if tp != null:
				var lv = lt.get("level")
				var lvs := ""
				var lcol := C_CYAN
				if lv != null:
					lvs = "  Lv%d" % int(lv)
					if int(lv) >= maxi(1, _lvl) + 3: lcol = Color("ff4d4d")
					elif int(lv) > maxi(1, _lvl): lcol = C_GOLD
				var nm := ("👑 " if lt.get("elite") == true else "") + _ename(lt)
				_text(_cv, tp + Vector2(-100, -8), nm, 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200)
				if lvs != "": _text(_cv, tp + Vector2(-100, 5), lvs.strip_edges(), 10, lcol, HORIZONTAL_ALIGNMENT_CENTER, 200)
				var f := float(lt.get("hp")) / maxf(1.0, float(lt.get("max_hp")))
				_bar(Rect2(tp + Vector2(-35, 9), Vector2(70, 5)), f, 0, Color("ff2d5e"), Color("ff8ab0"), "")
	# the objective marker: a bobbing gold diamond with the distance; on the screen's edge when off-screen
	var o = objective_point()
	if o is Vector3:
		var dist := Vector2(o.x - player.global_position.x, o.z - player.global_position.z).length()
		if dist > 6.0:
			var scr := get_viewport().get_visible_rect().size
			var m := 46.0
			var sp = _to_screen(o)
			var on: bool = sp != null and Rect2(Vector2(m, m), scr - Vector2(m, m) * 2).has_point(sp)
			var bob := sin(_t * 3.0) * 3.0
			if on:
				var p: Vector2 = sp + Vector2(0, bob)
				var dia := PackedVector2Array([p + Vector2(0, -9), p + Vector2(7, 0), p + Vector2(0, 9), p + Vector2(-7, 0)])
				_cv.draw_colored_polygon(dia, Color(C_GOLD, .9))
				var ring := dia.duplicate(); ring.append(dia[0]); _cv.draw_polyline(ring, Color(0, 0, 0, .7), 1.5)
				_text(_cv, p + Vector2(-40, 24), "%d m" % int(dist), 12, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80)
			else:
				var cam: Camera3D = player.get("cam")
				if cam:
					var lp: Vector3 = cam.global_transform.affine_inverse() * o
					var dir := Vector2(lp.x, -lp.y)
					if lp.z > 0: dir.y = absf(dir.y) + 1.0          # behind her: point down-ish, to the side it's on
					if dir.length() < .01: dir = Vector2(0, 1)
					dir = dir.normalized()
					var half := scr * .5 - Vector2(m, m)
					var k := minf(half.x / maxf(absf(dir.x), .0001), half.y / maxf(absf(dir.y), .0001))
					var p := scr * .5 + dir * k
					var a := atan2(dir.x, -dir.y)
					var tri := PackedVector2Array([p + Vector2(0, -11).rotated(a), p + Vector2(8, 6).rotated(a), p + Vector2(-8, 6).rotated(a)])
					_cv.draw_colored_polygon(tri, Color(C_GOLD, .65 + .3 * sin(_t * 5.0)))
					_text(_cv, p - dir * 22 + Vector2(-40, 4), "%d m" % int(dist), 11, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80)

# 7.2 had none; a strip at the top like a PS1 adventure: N E S W, the objective in gold, the lock-on in pink
func _draw_compass() -> void:
	var cam: Camera3D = player.get("cam")
	if not cam: return
	var f: Vector3 = -cam.global_transform.basis.z
	var h := atan2(f.x, -f.z)
	var cx := 480.0; var w := 300.0; var y := 8.0
	var r := Rect2(cx - w * .5, y, w, 20)
	_panel(r, Color("4a3b66"))
	var ppr := (w * .5 - 10) / (PI * .5)
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for i in 24:
		var a := i * PI / 12.0
		var dx := wrapf(a - h, -PI, PI)
		if absf(dx) > PI * .5: continue
		var x := cx + dx * ppr
		if i % 3 == 0:
			var nm: String = names[int(i / 3.0)]
			_text(_cv, Vector2(x - 15, y + 15), nm, 11 if nm.length() == 1 else 9, C_PINK if nm == "N" else Color("e8dcff"), HORIZONTAL_ALIGNMENT_CENTER, 30)
		else:
			_cv.draw_line(Vector2(x, y + 13), Vector2(x, y + 17), Color(.75, .7, .9, .5), 1.0)
	_cv.draw_line(Vector2(cx, y - 1), Vector2(cx, y + 3), C_CYAN, 2.0)
	var pp := player.global_position
	var marks: Array = []
	var o = objective_point()
	if o is Vector3: marks.append([o, C_GOLD])
	for k in pins: marks.append([pins[k]["pos"], pins[k].get("col", Color("3dff9e"))])
	var qs := sys("Quests")
	if qs:
		var qm = qs.get("marker")
		if qm is Node3D and is_instance_valid(qm) and qm.visible: marks.append([qm.global_position, Color("3dff9e")])
	var lt = player.get("lock_target")
	if _alive(lt): marks.append([lt.global_position, C_PINK])
	for mk in marks:
		var q: Vector3 = mk[0]
		var b := atan2(q.x - pp.x, -(q.z - pp.z))
		var dx := clampf(wrapf(b - h, -PI, PI), -PI * .5, PI * .5)
		var x := cx + dx * ppr
		var dia := PackedVector2Array([Vector2(x, y + 20), Vector2(x + 5, y + 26), Vector2(x, y + 32), Vector2(x - 5, y + 26)])
		_cv.draw_colored_polygon(dia, mk[1])

# 7.2's bosses only had "💀 BOSS HP" in the objective: now a proper bar with the name and phase marks
func _draw_boss() -> void:
	if not _alive(_boss): return
	var r := Rect2(270, 64, 420, 12)
	var nm := "💀 " + _ename(_boss).to_upper() + ("  👑 EPIC" if _boss.get("elite") == true else "")
	_text(_cv, Vector2(270, 59), nm, 14, Color("ff9ecf"), HORIZONTAL_ALIGNMENT_CENTER, 420)
	var f := float(_boss.get("hp")) / maxf(1.0, float(_boss.get("max_hp")))
	_bar(r, f, _boss_trail, Color("c8143c"), Color("ff5fa2"), "")
	var ph = _boss.get("phases")
	if ph is Array:
		for p in ph:
			if p is Dictionary and p.has("at"):
				var x: float = r.position.x + r.size.x * float(p["at"])
				_cv.draw_line(Vector2(x, r.position.y - 2), Vector2(x, r.end.y + 2), Color(1, 1, 1, .35) if p.get("done", false) else C_GOLD, 2.0)

# 7.2's #buffs: chips with the icon, the name, seconds left, and a draining line under each
func _draw_buffs() -> void:
	var sk := sys("Skills")
	if not sk or not sk.has_method("active_buffs"): return
	var list = sk.call("active_buffs")
	if not (list is Array): return
	var x := 12.0
	var y := _stats.position.y + 124.0 if _stats.visible else STATS_Y + 70.0
	for b in list:
		if not (b is Dictionary): continue
		var left := float(b.get("left", b.get("t", 0)))
		var mx := maxf(.1, float(b.get("total", b.get("max", b.get("dur", maxf(left, 1.0))))))
		var tx := "%s %s %ds" % [b.get("ic", b.get("icon", "✨")), b.get("n", b.get("name", "")), ceili(left)]
		var w := _font.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16
		if x + w > 330: x = 12.0; y += 26
		var r := Rect2(x, y, w, 21)
		_cv.draw_rect(r, Color(20 / 255.0, 8 / 255.0, 38 / 255.0, .82))
		_cv.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), C_PINK)
		_cv.draw_rect(Rect2(r.position + Vector2(3, r.size.y - 2), Vector2((w - 3) * clampf(left / mx, 0, 1), 2)), C_CYAN)
		_text(_cv, r.position + Vector2(9, 15), tx, 12, Color("ffe9fb"))
		x += w + 6

# the weapon she's holding: rarity colour, damage, durability (7.2's 🔧 uses, ∞ for the unbreakable ones), ammo
func _draw_weapon() -> void:
	if not player: return
	var info := {}
	var ars := sys("Arsenal")
	var pw = player.get("weapon")
	if ars and ars.has_method("hud_info"):
		var hi = ars.call("hud_info")
		if hi is Dictionary: info = hi
	elif ars and ars.has_method("weapon_info"):
		# Arsenal's weapon_info(id): dur_max <= 0 = unbreakable, ammo -1 = not a gun
		var wi = ars.call("weapon_info", str(pw.get("id", "kick")) if pw is Dictionary else "kick")
		if wi is Dictionary:
			info = wi.duplicate()
			if int(info.get("dur_max", -1)) <= 0: info["dur_max"] = null
			if int(info.get("ammo", -1)) < 0: info.erase("ammo")
	if info.is_empty():
		var w = player.get("weapon")
		if not (w is Dictionary): return
		var id := str(w.get("id", "kick"))
		if _wstats.is_empty():
			var js = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))
			if js is Dictionary: _wstats = js.get("weapons", {})
		var ws: Dictionary = _wstats.get(id, {})
		var durs = SaveBridge.data.get("dur", {})
		info = {"n": w.get("n", id), "dmg": w.get("dmg", 0), "rar": ws.get("rar", "Common"),
			"dur": durs.get(id) if durs is Dictionary else null, "dur_max": ws.get("dur"), "ammo": SaveBridge.get_i("ammo"),
			"ranged": w.get("ranged", ws.get("ranged", false))}
	var rc := Color(RARCOL.get(str(info.get("rar", "Common")), "b8b8c4"))
	var r := Rect2(10, 668, 206, 42)          # ends left of the 10-slot skill bar (x 223)
	_panel(r, rc, .35)
	_text(_cv, r.position + Vector2(10, 17), str(info.get("n", "?")), 14, rc)
	_text(_cv, r.position + Vector2(10, 17), "💥%d  [Q]" % int(info.get("dmg", 0)), 11, Color("e8dcff"), HORIZONTAL_ALIGNMENT_RIGHT, 186)
	var dm = info.get("dur_max")
	var du = info.get("dur")
	if dm == null or str(info.get("rar", "")) == "Unarmed":
		_text(_cv, r.position + Vector2(10, 34), "🔧 ∞", 11, Color("bfb0dd"))
	else:
		var cur := float(du) if du != null else float(dm)
		var f := cur / maxf(1.0, float(dm))
		var col := Color("3dff9e") if f > .5 else C_GOLD if f > .22 else Color("ff4d4d")
		_bar(Rect2(r.position + Vector2(34, 27), Vector2(84, 6)), f, 0, col, col.lightened(.3), "")
		_text(_cv, r.position + Vector2(10, 35), "🔧", 11, Color.WHITE)
		_text(_cv, r.position + Vector2(124, 35), "%d/%d" % [maxi(0, roundi(cur)), int(dm)], 10, col)
	if info.get("ranged", false) == true or int(info.get("ammo", 0)) > 0:
		var am := int(info.get("ammo", 0))
		if info.get("ranged", false) == true and am <= 0:
			_text(_cv, r.position + Vector2(10, 35), "NO AMMO", 11, Color("ff4d4d").lerp(Color.WHITE, .3 + .3 * sin(_t * 8.0)), HORIZONTAL_ALIGNMENT_RIGHT, 186)
		else: _text(_cv, r.position + Vector2(10, 35), "💵 %d" % am, 11, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 186)
