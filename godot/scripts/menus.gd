# The menus around the game, from 7.2:
#   title()      #title / #tMenu: TORİİ · Neo Antalya, NEW GAME / CONTINUE, the controls card, the footer
#                (startBtn asks before erasing; here the old save is also copied to Downloads first).
#                CONTINUE = startPlay(true): '🛬 WELCOME BACK, TORİİ'; NEW GAME = playOpening, then the
#                first words (Görüşürüz bebeğim, gece, köpek, ay) and mission 1 (startPlay(false)).
#   pause        #opts / openOpts / closeOpts (P, ESC closes): the whole game stops (tree paused + Overlay
#                "pause"); Müzik / Ses efekt sliders, GRAFİK, NEON GLOW, MONSTER VOICES, SUNGLASSES,
#                FULLSCREEN, REHBER · GUIDE, WHAT'S NEW, DEVAM, SAVE & LOAD (save_ui.gd).
#   patch notes  PATCHES / showPatch / closePatch: pops up once per version (save `gPatch`, new), lists
#                this version's groups + the 3 before it. assets/story/godot.json "patch" is the top entry.
#   guide        GUIDE / openGuide / closeGuide: every section, with her own numbers.
#   toggle bar   #btns + #ver (bottom right, while the mouse is free) and the E prompt line (#prompt,
#                setPrompt) over the skill bar: shops, quests, gods, fountains, simit carts, DJ, the bike.
#   keys         P pause · X fullscreen · G sunglasses (7.2's keys; nobody else reads them).
# Save fields: shades (7.2), gPatch, gGfx, gGlow (new, Godot only; NIGHT GRADE = gGrade is sky.gd's).
# Volumes/voice stay Audio's.
# Dev runs (--autoplay etc.) never show the title: Missions starts the story by itself.
class_name Menus
extends CanvasLayer

static var me: Menus
static var fresh := false              # NEW GAME wiped the save and reloaded: go straight to the opening
const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURP := Color("b06bff")
var GAME_VER := "ALPHA 8.0 · GAME GAME"
var PATCHES: Array = []
var torii: CharacterBody3D
var hud: CanvasLayer
var save_ui: Node
var _root: Control
var _title: Control
var _confirm: Control
var _pause: Control
var _guide: Control
var _patch: Control
var _bar: VBoxContainer
var _ver: Label
var _prompt: Label
var _prompt_t := 0.0
var _mus: HSlider
var _sfx: HSlider
var _opt_btns := {}
var _shades: Node3D
var _guide_secs := {}
var _guide_scroll: ScrollContainer
var _guide_from_pause := false
var _hud_was := true
var title_up := false

func setup(p: CharacterBody3D, h: CanvasLayer, sui: Node) -> void:
	me = self; torii = p; hud = h; save_ui = sui
	name = "Menus"; layer = 40; process_mode = Node.PROCESS_MODE_ALWAYS
	var G = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/godot.json"))
	var S = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/story72.json"))
	if G is Dictionary:
		GAME_VER = str(G.get("ver", GAME_VER))
		if G.has("patch"): PATCHES.append(G["patch"])
	if S is Dictionary: PATCHES.append_array(S.get("patches", []))
	_root = Control.new(); _root.set_anchors_preset(Control.PRESET_FULL_RECT); _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_bar()
	_prompt = Label.new(); _prompt.position = Vector2(180, 606); _prompt.size = Vector2(600, 26)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", GOLD); _prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9)); _prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt)
	call_deferred("_apply_display")
	if SaveBridge.data.get("shades", false) == true: call_deferred("set_shades", true, true)

# ---------------------------------------------------------------- little UI kit (7.2's neon cards)
func _panel(col: Color, min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, .97); sb.border_color = col
	sb.set_border_width_all(2); sb.set_corner_radius_all(14); sb.set_content_margin_all(20)
	sb.shadow_color = Color(col, .25); sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb); p.custom_minimum_size = min_size
	return p

func _center_layer(child: Control, dim := .55) -> Control:
	var bg := ColorRect.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.color = Color(.02, .01, .05, dim)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(cc); cc.add_child(child); _root.add_child(bg)
	return bg

func _rich(parent: Node, t: String, size := 16, col := Color("e8e4f8"), w := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: r.add_theme_font_size_override(k, size)
	r.add_theme_color_override("default_color", col)
	if w > 0: r.custom_minimum_size = Vector2(w, 0)
	r.text = t; parent.add_child(r)
	return r

func _btn(parent: Node, t: String, cb: Callable, col := CYAN, size := 16, alt := true) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	var n := StyleBoxFlat.new(); n.bg_color = Color(.12, .07, .2, .95) if alt else Color(col, .9)
	n.border_color = col; n.set_border_width_all(2); n.set_corner_radius_all(9); n.set_content_margin_all(8)
	var hv := n.duplicate() as StyleBoxFlat; hv.bg_color = Color(col, .35) if alt else Color(col, 1)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", hv); b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_color_override("font_color", col if alt else Color("12081e"))
	b.add_theme_color_override("font_hover_color", Color.WHITE if alt else Color("12081e"))
	b.pressed.connect(func():
		Audio.sfx("menu_select")
		cb.call())
	parent.add_child(b)
	return b

func _row(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new(); h.alignment = BoxContainer.ALIGNMENT_CENTER; h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	return h

func _vbox(parent: Node, sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); parent.add_child(v)
	return v

# ---------------------------------------------------------------- TITLE (#title / startPlay)
# main.gd calls this once everything is built (not in dev runs). fresh = NEW GAME just reloaded the scene.
func title() -> void:
	if Missions.dev_run(): return                 # dev runs: Missions starts the story by itself
	if fresh:
		fresh = false; _new_game(); return
	title_up = true
	if Audio.me: Audio.me.set_music_mode("intro")      # 7.2's IM title theme
	Overlay.open("title")
	if hud: _hud_was = hud.visible; hud.visible = false
	if Cutscene.me: Cutscene.me.backdrop(true)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); v.alignment = BoxContainer.ALIGNMENT_CENTER
	var bg := Control.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new(); shade.set_anchors_preset(Control.PRESET_FULL_RECT); shade.color = Color(.03, .01, .08, .45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; bg.add_child(shade)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); bg.add_child(cc); cc.add_child(v)
	_root.add_child(bg); _title = bg
	var h1 := _rich(v, "[center][b]TORİİ[/b][/center]", 92, PINK, 700)
	h1.add_theme_constant_override("outline_size", 14); h1.add_theme_color_override("font_outline_color", Color(PINK, .3))
	_rich(v, "[center]Neo Antalya[/center]", 36, CYAN, 700)
	_rich(v, "[center]Braids. A dog. A red bike. A city full of neon.\nRide, fight, level up, and learn Turkish on the way. 🌴[/center]", 16, Color("e8dcff"), 700)
	var ctr := _panel(PURP); v.add_child(ctr)
	_rich(ctr, "[center][b]🖱 MOUSE[/b] look & aim · [b]W/S[/b] forward/back · [b]A/D[/b] strafe · [b]←/→[/b] turn\n" +
		"[b]SPACE[/b] jump [color=#9a94a8](bike boost)[/color] · [b]SHIFT[/b] sprint · [b]E[/b] interact / talk / bike\n" +
		"[b]CLICK[/b] or [b]F[/b] attack · [b]RIGHT CLICK[/b] heavy · [b]Left CTRL[/b] roll · [b]hold Z[/b] block / parry · [b]TAB[/b] lock-on\n" +
		"[b]HOLD Q[/b] weapon wheel · [b]1-0[/b] skills [color=#9a94a8](R too)[/color] · [b]C[/b] look behind · [b]T[/b] photo\n" +
		"[b]I[/b] bag & gear · [b]J[/b] quests · [b]H[/b] eat a snack · [b]X[/b] fullscreen · [b]P[/b] pause & options[/center]", 14, Color("d8ccf4"), 720)
	var row := _row(v)
	var has_save := not SaveBridge.is_new() or SaveBridge.get_i("lvl", 1) > 1 or SaveBridge.get_i("next") > 0
	if has_save:
		var c := _btn(row, "CONTINUE ⟳", _continue, PINK, 22, false)
		c.custom_minimum_size = Vector2(230, 0)
	var n := _btn(row, "NEW GAME ▶", _ask_new.bind(has_save), CYAN, 22, has_save)
	n.custom_minimum_size = Vector2(230, 0)
	_rich(v, "[center]Kaan is waiting for you ❤ · Bandit is ready 🐶[/center]", 15, GOLD, 700)
	_rich(v, "[center][color=#8a7fb0]%s[/color][/center]" % GAME_VER, 12, Color.WHITE, 700)

func _close_title() -> void:
	title_up = false
	if _title: _title.queue_free(); _title = null
	if _confirm: _confirm.queue_free(); _confirm = null
	if Cutscene.me: Cutscene.me.backdrop(false)
	if hud: hud.visible = _hud_was
	if Audio.me: Audio.me.set_music_mode("world")
	Overlay.close("title")

func _continue() -> void:
	_close_title()
	if hud and hud.has_method("banner"): hud.banner("🛬 WELCOME BACK, TORİİ\n[font_size=16]Your adventure continues[/font_size]")
	Audio.sfx("chuckle")
	if Missions.me: Missions.me.begin()
	_patch_later()

func _ask_new(has_save: bool) -> void:
	if not has_save: _close_title(); _new_game(); return
	var p := _panel(PINK)
	var v := _vbox(p, 14)
	var words := (SaveBridge.data.get("words", []) as Array).size() if SaveBridge.data.get("words") is Array else 0
	_rich(v, "[center][b]⚠️ START OVER?[/b][/center]", 24, PINK, 560)
	_rich(v, ("[center]This will [b]ERASE[/b] your save: [b]level %d[/b], %d Turkish words, mission %d.\n" +
		"A copy goes to your [b]Downloads[/b] folder first, so you can load it back later\n(💾 SAVE & LOAD → LOAD FROM A FILE).[/center]") %
		[SaveBridge.get_i("lvl", 1), words, SaveBridge.get_i("next") + 1], 16, Color("e8e4f8"), 560)
	var r := _row(v)
	_btn(r, "◀ NO, GO BACK", func():
		if _confirm: _confirm.queue_free(); _confirm = null, CYAN, 17)
	_btn(r, "YES, START OVER", _wipe, PINK, 17, false)
	_confirm = _center_layer(p, .6)

# the old save goes to a file first, then a clean 7.2-shaped save (her settings kept), then a fresh start
func _wipe() -> void:
	var raw := SaveBridge.export_text()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := (dir if dir != "" else OS.get_user_data_dir()) + "/torii-save-before-new-game-%s.json" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = OS.get_user_data_dir() + "/torii-save-before-new-game-%s.json" % stamp
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if hud and hud.has_method("toast"): hud.toast("💾 Couldn't make the safety copy, so your save was NOT erased.", 8.0, true)
		if _confirm: _confirm.queue_free(); _confirm = null
		return
	f.store_string(raw); f.close()
	var keep := {}
	for k in ["musVol", "sfxVol", "voiceOn", "musicOn", "shades", "gGfx", "gGlow", "gGrade", "gPatch"]:
		if SaveBridge.data.has(k): keep[k] = SaveBridge.data[k]
	SaveBridge.data = keep
	SaveBridge.write()
	fresh = true
	Overlay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()

# startPlay(false): the opening, the first words, then mission 1
func _new_game() -> void:
	var go := func():
		Audio.sfx("bark"); Audio.sfx("chuckle")
		_teach_later(["Görüşürüz bebeğim", "gece"], 1.4)
		_teach_later(["köpek", "ay"], 4.0)
		await get_tree().create_timer(6.2).timeout
		if Missions.me: Missions.me.begin()
		_patch_later()
	if Cutscene.me: Cutscene.me.opening(go)
	else: go.call()

func _teach_later(words: Array, sec: float) -> void:
	await get_tree().create_timer(sec).timeout
	if Lessons.me:
		for w in words: Lessons.me.teach(w)

# ---------------------------------------------------------------- PAUSE / OPTIONS (#opts)
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if _guide:
		if k in [KEY_ESCAPE, KEY_P, KEY_ENTER, KEY_KP_ENTER]: close_guide(); get_viewport().set_input_as_handled()
		return
	if _patch:
		if k in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]: close_patch(); get_viewport().set_input_as_handled()
		return
	if _pause:
		if k in [KEY_ESCAPE, KEY_P]: close_pause(); get_viewport().set_input_as_handled()
		elif k == KEY_X: toggle_fullscreen()
		return
	if title_up or QuizUI.open: return
	if k == KEY_X: toggle_fullscreen(); get_viewport().set_input_as_handled()
	elif Overlay.any(): return
	elif k == KEY_P: open_pause(); get_viewport().set_input_as_handled()
	elif k == KEY_G: set_shades(not _shades_on()); get_viewport().set_input_as_handled()

func open_pause() -> void:
	if _pause: return
	get_tree().paused = true; Overlay.open("pause")
	var p := _panel(PINK, Vector2(520, 0))
	var v := _vbox(p, 12)
	_rich(v, "[center][b]⚙ AYARLAR · OPTIONS[/b][/center]", 24, PINK, 480)
	var prev := _panel(PURP); v.add_child(prev)
	var lvl := SaveBridge.get_i("lvl", 1)
	_rich(prev, "[center]Örnek metin — [b]Merhaba Torii![/b] [i](paused)[/i]\n[color=#ff7ab0]HP %d / %d[/color] · LVL %d · %d₺[/center]" %
		[int(torii.get("hp")) if torii else 0, int(torii.get("max_hp")) if torii else 0, lvl, SaveBridge.get_i("lira")], 15, Color("e8e4f8"), 440)
	var A = Audio.me
	_mus = _slider(v, "🎵 Müzik", int(A.mus_vol) if A else 16, func(x): if Audio.me: Audio.me.set_music_volume(int(x)))
	_sfx = _slider(v, "🔊 Ses efekt", int(A.sfx_vol) if A else 90, func(x): if Audio.me: Audio.me.set_sfx_volume(int(x)))
	var r1 := _row(v)
	_opt_btns["gfx"] = _btn(r1, "", _cycle_gfx, CYAN, 15)
	_opt_btns["glow"] = _btn(r1, "", func():
		_set_flag("gGlow", not _glow_on()); _apply_glow()
		_opt_text(), CYAN, 15)
	if SkyCycle.me:
		_opt_btns["grade"] = _btn(r1, "", func(): SkyCycle.me.toggle_grade(); SaveBridge.write(); _opt_text(), CYAN, 15)
	var r2 := _row(v)
	_opt_btns["voice"] = _btn(r2, "", func():
		if Audio.me: Audio.me.set_voice(not Audio.me.voice_on)
		_opt_text(), CYAN, 15)
	_opt_btns["shades"] = _btn(r2, "", func(): set_shades(not _shades_on()); _opt_text(), CYAN, 15)
	_opt_btns["fs"] = _btn(r2, "", func(): toggle_fullscreen(); _opt_text(), CYAN, 15)
	var r3 := _row(v)
	_btn(r3, "📘 REHBER · GUIDE", func(): open_guide(true), GOLD, 15)
	_btn(r3, "📜 WHAT'S NEW", func(): show_patch(true), GOLD, 15)
	var r4 := _row(v)
	_btn(r4, "▶ DEVAM (resume)", close_pause, PINK, 18, false)
	_btn(r4, "💾 SAVE & LOAD", func():
		close_pause()
		if save_ui and not Overlay.any(): save_ui.open_panel(false), CYAN, 16)
	_rich(v, "[center][color=#8a7fb0]P / ESC resume · %s[/color][/center]" % GAME_VER, 12, Color.WHITE, 480)
	_opt_text()
	_pause = _center_layer(p, .5)
	Audio.sfx("ui_open")

func close_pause() -> void:
	if not _pause: return
	_pause.queue_free(); _pause = null; _opt_btns = {}
	get_tree().paused = false; Overlay.close("pause")
	SaveBridge.write()
	Audio.sfx("ui_close")

func _slider(parent: Node, label: String, val: int, cb: Callable) -> HSlider:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); parent.add_child(h)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(130, 0); l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("e8e4f8")); h.add_child(l)
	var s := HSlider.new(); s.min_value = 0; s.max_value = 100; s.step = 1; s.value = val; s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(250, 22); s.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(s)
	var n := Label.new(); n.text = "%d%%" % val; n.custom_minimum_size = Vector2(50, 0); n.add_theme_color_override("font_color", GOLD)
	h.add_child(n)
	s.value_changed.connect(func(x: float):
		n.text = "%d%%" % int(x)
		cb.call(x))
	return s

func _opt_text() -> void:
	if _opt_btns.is_empty(): return
	_opt_btns["gfx"].text = "🎨 GRAFİK: %s" % ["PS1", "SHARP", "SMOOTH"][clampi(SaveBridge.get_i("gGfx"), 0, 2)]
	_opt_btns["glow"].text = "✨ NEON GLOW: %s" % ("ON" if _glow_on() else "OFF")
	if SkyCycle.me and _opt_btns.has("grade"): _opt_btns["grade"].text = SkyCycle.me.grade_label()
	_opt_btns["voice"].text = "🔊 MONSTER VOICES: %s" % ("ON" if Audio.me == null or Audio.me.voice_on else "OFF")
	_opt_btns["shades"].text = "🕶 SHADES: %s" % ("ON" if _shades_on() else "OFF")
	_opt_btns["fs"].text = "⛶ FULLSCREEN [X]"

func _flag(k: String) -> bool: return SaveBridge.data.get(k, false) == true
func _set_flag(k: String, v: bool) -> void: SaveBridge.data[k] = v
# NEON GLOW is on unless she turned it off (sky.gd reads gGlow the same way for the lamp/car halos)
func _glow_on() -> bool: return SaveBridge.data.get("gGlow", true) != false

# GRAFİK (save gGfx): how big the 3D pixels are (main.gd draws the 3D at a third of the window = PS1).
# Menus owns GRAFİK and NEON GLOW; sky.gd only owns NIGHT GRADE (gGrade) and hides its halos on gGlow false.
func _cycle_gfx() -> void:
	SaveBridge.data["gGfx"] = (SaveBridge.get_i("gGfx") + 1) % 3
	_apply_gfx()
	_opt_text()

func _apply_display() -> void:
	_apply_gfx(); _apply_glow()

func _apply_gfx() -> void:
	var shrink: int = [3, 2, 1][clampi(SaveBridge.get_i("gGfx"), 0, 2)]
	for c in get_tree().root.find_children("*", "SubViewportContainer", true, false):
		(c as SubViewportContainer).stretch_shrink = shrink

func _apply_glow() -> void:
	for w in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		if env == null: continue
		env.glow_enabled = _glow_on() and SkyCycle.me == null      # with sky.gd the glow is its lamp halos
		if env.glow_enabled: env.glow_intensity = .7; env.glow_bloom = .08; env.glow_hdr_threshold = .9

func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------------------------------------------------------- 🕶 sunglasses (G, 7.2 setShades + save `shades`)
func _shades_on() -> bool: return _shades != null and _shades.visible

func set_shades(on: bool, quiet := false) -> void:
	if on and _shades == null: _build_shades()
	if _shades: _shades.visible = on
	SaveBridge.data["shades"] = on
	if not quiet:
		if hud and hud.has_method("toast"): hud.toast("🕶 Sunglasses on. Çok havalı! [i](So cool!)[/i]" if on else "🕶 Sunglasses off.", 3.0)
		Audio.sfx("menu_select"); SaveBridge.write()

# the frame style and colours follow the sunglasses she wears in the eye slot (GearLook, 7.2 buildShadesInto)
func _build_shades() -> void:
	if GearLook.me: _shades = GearLook.me.shades_node()

# ---------------------------------------------------------------- WHAT'S NEW (PATCHES / showPatch)
func _patch_later() -> void:
	await get_tree().create_timer(.9).timeout
	if str(SaveBridge.data.get("gPatch", "")) == GAME_VER: return
	if Cutscene.me: Cutscene.me.when_free(func(): show_patch(false))
	else: show_patch(false)

func show_patch(force: bool) -> void:
	if PATCHES.is_empty() or _patch: return
	if not force and str(SaveBridge.data.get("gPatch", "")) == GAME_VER: return
	SaveBridge.data["gPatch"] = GAME_VER; SaveBridge.write()
	var P: Dictionary = PATCHES[0]
	var p := _panel(CYAN, Vector2(700, 0))
	var v := _vbox(p, 8)
	_rich(v, "[center][b]✨ %s · %s[/b][/center]" % [P["v"], P["t"]], 21, CYAN, 660)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(660, 430); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := _vbox(sc, 4); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for g in P["groups"]:
		_rich(body, "[b]%s[/b]" % g[0], 17, GOLD, 630)
		for l in g[1]: _rich(body, "· " + str(l), 15, Color("e8e4f8"), 630)
	_rich(body, "[b]📜 EARLIER[/b]", 17, GOLD, 630)
	for q in PATCHES.slice(1, 4): _rich(body, "[color=#b8b0d0]· [b]%s[/b] — %s[/color]" % [q["v"], q["t"]], 14, Color.WHITE, 630)
	var r := _row(v)
	_btn(r, "HADİ! · LET'S GO ▶", close_patch, PINK, 17, false)
	_patch = _center_layer(p, .55)
	_patch.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: close_patch())      # 7.2: clicking the backdrop closes it
	if not _pause: Overlay.open("patch")

func close_patch() -> void:
	if not _patch: return
	_patch.queue_free(); _patch = null
	Overlay.close("patch")

# ---------------------------------------------------------------- 📘 THE GUIDE (GUIDE / openGuide)
func _tips() -> Dictionary:
	var D: Dictionary = LevelUp.me.D if LevelUp.me else Stats.data()
	return D.get("TIPS", {})

func _guide_list() -> Array:
	var T := _tips()
	var D := Stats.data()
	var lvl := Stats.lvl()
	var out := []
	out.append({"id": "keys", "ic": "🎮", "n": "Controls", "t": "KONTROLLER · CONTROLS", "l": [
		"[b]W A S D[/b] move · [b]← →[/b] turn · [b]MOUSE[/b] look & aim (click to lock it) · [b]SPACE[/b] jump, or boost on the bike · [b]SHIFT[/b] sprint (uses stamina)",
		"[b]CLICK[/b] or [b]F[/b] attack (press in rhythm for a combo) · [b]RIGHT CLICK[/b] heavy hit (hold to charge)",
		"[b]Left CTRL[/b] dodge roll · [b]hold Z[/b] block (just before a hit = parry) · [b]TAB[/b] lock-on / next target",
		"Tap [b]Q[/b] or the mouse wheel = next weapon · [b]HOLD Q[/b] weapon wheel · [b]E[/b] talk, open, get on and off the bike",
		"[b]1-0[/b] skills ([b]R[/b] is Dance Blast too) · [b]I[/b] bag & gear · [b]J[/b] quests · [b]H[/b] eat your best snack · [b]T[/b] take a photo",
		"[b]C[/b] look behind · [b]G[/b] sunglasses · [b]V[/b] monster voices · [b]M[/b] music · [b]X[/b] fullscreen · [b]P[/b] pause",
		"Lessons and quizzes: [b]1-4[/b] to answer · [b]E[/b] next line · [b]K[/b] skip · [b]H[/b] buy a 💡 hint (15₺, one per question)"]})
	out.append({"id": "fight", "ic": "⚔️", "n": "Fighting", "t": "DÖVÜŞ · FIGHTING", "sub": ["combo", "roll", "block", "lockon"]})
	var mana := "You: [b]%d / %d[/b] mana right now." % [int(torii.get("mana")), int(torii.get("max_mana"))] if torii else ""
	out.append({"id": "skills", "ic": "✨", "n": "Skills", "tip": "skills", "x": [mana] if mana != "" else []})
	var weap = SaveBridge.data.get("weap", [])
	out.append({"id": "wheel", "ic": "🗡", "n": "Weapons", "tip": "wheel", "x": ["You own [b]%d[/b] weapons." % (weap.size() if weap is Array else 0)]})
	out.append({"id": "levels", "ic": "⭐", "n": "Levels", "tip": "levels",
		"x": ["You: [b]level %d[/b] · %d / %d XP to the next one." % [lvl, SaveBridge.get_i("xp"), SaveBridge.get_i("need", 60)]]})
	var own := []
	var perks = SaveBridge.data.get("perks", {})
	for P in D.get("PERKS", []):
		var n := Stats.pk(str(P["id"]))
		if n > 0: own.append("%s %s ×%d" % [P["ic"], P["tr"], n])
	out.append({"id": "perks", "ic": "🃏", "n": "Perk cards", "t": "PERK KARTLARI · PERK CARDS", "l": [
		"Every level up gives you a [b]perk card[/b]. Open it, pick [b]one of three[/b], and that perk is yours forever.",
		"Picking a perk you already have [b]ranks it up[/b] — the dots on the card show how far it can go.",
		"Not in the mood to choose? [b]SONRA[/b] keeps the card. Open it later from your bag ([b]I[/b]).",
		"Each card name is a Turkish word, with the English right under it."],
		"x": ["Cards waiting: [b]%d[/b]%s" % [SaveBridge.get_i("pp"), (" · yours: " + " · ".join(own)) if own.size() else ""]]})
	var ml := []
	for M in D.get("MILESTONES", []):
		ml.append("%s [b]Level %d[/b] · %s — %s" % ["✅" if lvl >= int(M["lv"]) else "🔒", int(M["lv"]), M["t"], M["d"]])
	ml.append("After level 30: every 5 levels gives [b]+50 max HP[/b] and [b]+5% damage[/b], with no end.")
	out.append({"id": "miles", "ic": "🏆", "n": "Every 5th level", "t": "HER 5 SEVİYEDE · EVERY 5TH LEVEL", "l": ml})
	out.append({"id": "moblv", "ic": "🎯", "n": "Monster levels", "tip": "moblv"})
	out.append({"id": "phases", "ic": "⚠️", "n": "Boss phases", "tip": "phases"})
	var gx := []
	var RAR: Array = D.get("RAR", [])
	if RAR.size():
		var cap: int = Items.me.rar_cap() if Items.me else 0
		var rs := []
		for i in RAR.size(): rs.append("[color=%s][b]%s[/b][/color] (%s)%s" % [RAR[i]["c"], RAR[i]["n"], RAR[i]["en"], " 🔒" if i > cap else ""])
		gx.append("Rarity, worst to best: " + " · ".join(rs))
		gx.append("Right now the best that can drop for you is [color=%s][b]%s[/b][/color]." % [RAR[clampi(cap, 0, RAR.size() - 1)]["c"], RAR[clampi(cap, 0, RAR.size() - 1)]["en"]])
	out.append({"id": "gear", "ic": "🕶", "n": "Gear", "tip": "gear", "x": gx})
	out.append({"id": "bag", "ic": "🎒", "n": "Backpack", "tip": "bag",
		"x": ["Your backpack: [b]%d / %d[/b] slots used." % [Items.me.bag_used(), Items.me.bag_cap()]] if Items.me else []})
	out.append({"id": "nazar", "ic": "🧿", "n": "Nazar beads", "tip": "nazar", "x": ["Found so far: [b]%d / %d[/b]." % [Stats.nz_count(), (D.get("NZ_SPOTS", []) as Array).size()]]})
	out.append({"id": "quests", "ic": "📜", "n": "Side quests", "tip": "quests", "x": [Quests.me.log_bbcode()] if Quests.me else []})
	out.append({"id": "bag2", "ic": "🎒", "n": "Your bag", "tip": "inventory"})
	out.append({"id": "types", "ic": "🗺", "n": "Mission types", "t": "GÖREV TÜRLERİ · MISSION TYPES", "sub": ["race", "chase", "escort", "deliver", "photo", "choice"]})
	out.append({"id": "story", "ic": "🎬", "n": "Story", "t": "HİKAYE · THE STORY", "l": [
		"Missions open with a [b]phone call[/b]. [b]E[/b] moves to the next line, [b]ESC[/b] skips the whole scene.",
		"After some story missions the camera cuts to [b]Hellspace Wealth[/b], where CEO Karen is plotting against you. Those can be skipped too.",
		"Nothing can hurt you while a scene is playing.",
		"Out in the city: the three [b]trickster gods[/b] bet 40₺ on a coin toss, [b]fountains[/b] heal you, [b]simit carts[/b] sell simit, and the [b]DJ decks[/b] at Club Holo are yours."],
		"x": ["Missions done: [b]%d / 20[/b]%s" % [mini(20, SaveBridge.get_i("next")), " · 🌴 FREE PLAY" if SaveBridge.data.get("done") == true else ""]]})
	out.append({"id": "saves", "ic": "💾", "n": "Saving", "t": "KAYIT · SAVING", "l": [
		"The game saves by itself, all the time. [b]💾 SAVE & LOAD[/b] on this pause menu gives you a file to keep somewhere safe.",
		"Same save as the browser game: bring it over with that file, and take it back the same way.",
		"Fainting costs a little lira and XP — [b]never a level[/b], and never your gear."]})
	for G in out:
		if G.has("tip") and not G.has("t"): G["t"] = (T.get(G["tip"], {}) as Dictionary).get("t", G["n"])
	return out

func open_guide(from_pause := false) -> void:
	if _guide: return
	_guide_from_pause = from_pause
	if _pause: _pause.visible = false
	if not from_pause: Overlay.open("guide")
	var T := _tips()
	var p := _panel(GOLD, Vector2(800, 0))
	var v := _vbox(p, 8)
	_rich(v, "[b]📘 REHBER · GUIDE[/b]  [color=#9a94a8][font_size=14]everything in the game, explained[/font_size][/color]", 22, GOLD, 760)
	var idx := HFlowContainer.new(); idx.add_theme_constant_override("h_separation", 6); idx.add_theme_constant_override("v_separation", 6)
	idx.custom_minimum_size = Vector2(760, 0); v.add_child(idx)
	_guide_scroll = ScrollContainer.new(); _guide_scroll.custom_minimum_size = Vector2(760, 440)
	_guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(_guide_scroll)
	var body := _vbox(_guide_scroll, 14); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_secs = {}
	for G in _guide_list():
		var sec := _vbox(body, 4)
		_guide_secs[G["id"]] = sec
		_rich(sec, "[b]%s %s[/b]" % [G["ic"], G["t"]], 18, PINK, 730)
		var lines: Array = []
		if G.has("tip"): lines.append_array((T.get(G["tip"], {}) as Dictionary).get("l", []))
		lines.append_array(G.get("l", []))
		for l in lines: _rich(sec, "· " + str(l), 15, Color("e8e4f8"), 730)
		for k in G.get("sub", []):
			var U: Dictionary = T.get(k, {})
			if U.is_empty(): continue
			_rich(sec, "[b]%s[/b]" % U["t"], 16, CYAN, 730)
			for l in U["l"]: _rich(sec, "· " + str(l), 15, Color("e8e4f8"), 730)
		for l in G.get("x", []): if str(l) != "": _rich(sec, str(l), 15, Color("5fff9e"), 730)
		var chip := _btn(idx, "%s %s" % [G["ic"], G["n"]], _guide_jump.bind(G["id"]), CYAN, 13)
		chip.custom_minimum_size = Vector2(0, 0)
	var r := _row(v)
	_btn(r, "◀ GERİ · BACK [ESC]", close_guide, PINK, 16, false)
	_guide = _center_layer(p, .6)

func _guide_jump(id: String) -> void:
	if _guide_secs.has(id) and _guide_scroll: _guide_scroll.scroll_vertical = int((_guide_secs[id] as Control).position.y)

func close_guide() -> void:
	if not _guide: return
	_guide.queue_free(); _guide = null; _guide_secs = {}
	if _guide_from_pause and _pause: _pause.visible = true
	elif not _guide_from_pause: Overlay.close("guide")

# ---------------------------------------------------------------- the toggle bar (#btns), #ver, the E prompt
func _build_bar() -> void:
	_bar = VBoxContainer.new(); _bar.position = Vector2(812, 414); _bar.add_theme_constant_override("separation", 4)    # ends above SAVE & LOAD (y 684)
	_bar.custom_minimum_size = Vector2(144, 0); _root.add_child(_bar)
	var items := [["🔊 VOICES [V]", func(): if Audio.me: Audio.me.set_voice(not Audio.me.voice_on)],
		["👁 LOOK BEHIND [C]", func(): if torii and torii.has_method("_set_look"): torii._set_look(not torii.look_back)],
		["🕶 SUNGLASSES [G]", func(): set_shades(not _shades_on())],
		["⛶ FULLSCREEN [X]", toggle_fullscreen],
		["🎒 ÇANTA [I]", func(): if InventoryUI.me and not Overlay.any(): InventoryUI.me.open()],
		["⚙ OPTIONS [P]", open_pause],
		["📜 WHAT'S NEW", func(): show_patch(true)]]
	for it in items:
		var b := _btn(_bar, it[0], it[1], CYAN, 11)
		b.custom_minimum_size = Vector2(144, 0); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ver = Label.new(); _ver.text = "TORİİ: NEO ANTALYA — " + GAME_VER; _ver.position = Vector2(400, 704); _ver.size = Vector2(554, 14)
	_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; _ver.add_theme_font_size_override("font_size", 10)
	_ver.add_theme_color_override("font_color", Color(1, 1, 1, .4)); _ver.mouse_filter = Control.MOUSE_FILTER_IGNORE; _root.add_child(_ver)

func _process(dt: float) -> void:
	var playing := not title_up and not Cutscene.busy() and not get_tree().paused
	_bar.visible = playing and not Overlay.any() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	_ver.visible = playing
	_prompt_t -= dt
	if _prompt_t <= 0:
		_prompt_t = .15
		var t := _prompt_text() if playing and not Overlay.any() else ""
		_prompt.text = t; _prompt.visible = t != ""

# setPrompt's picks, in 7.2's order: vendors, quest givers, tutors, tavla, Kaan, the gods / fountains / simit
# / DJ, chests, the bike. Looked up by class name so a system that isn't wired yet just doesn't speak.
const PROMPTERS := ["Shops", "Quests", "Tutors", "Tavla", "Hotspots", "Interactables", "Missions", "Items"]
static var _cls := {}
static func _sys(cname: String) -> Object:
	if _cls.is_empty():
		for c in ProjectSettings.get_global_class_list(): _cls[c["class"]] = c["path"]
	if not _cls.has(cname): return null
	var o = load(_cls[cname]).get("me")
	return o if is_instance_valid(o) else null

func _prompt_text() -> String:
	if not is_instance_valid(torii) or torii.get("dead") == true: return ""
	if torii.get("on_bike") == true:
		return "E: hop off the bike" if absf(float(torii.get("bspeed"))) < 5.0 else ""
	for cn in PROMPTERS:
		var s := _sys(cn)
		if s and s.has_method("prompt"):
			var t := str(s.call("prompt", torii))
			if t != "": return t
	var bk = torii.get("bike")
	if bk is Node3D and is_instance_valid(bk) and (bk as Node3D).global_position.distance_to(torii.global_position) < 2.6:
		return "E: ride the Diamond Back 🚲"
	return ""
