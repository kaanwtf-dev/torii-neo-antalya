# The HUD: HP bar, the objective, the dialogue box (Kaan's calls, people talking), the choice box, banners,
# the toast stack, and the SKIP THIS LESSON / SAVE & LOAD buttons. Text takes 7.2's markup as BBCode
# ([b], [i]). Keys like 7.2: E / Enter / Space next line, ESC skips the rest of a call, 1-9 picks a choice,
# E closes it. Drawn at full window resolution on top of the pixelated 3D, in 7.2's neon colours.
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
var _ban_t := 0.0
var _say_who := ""
var _say_q: Array = []
var _say_done: Callable

func _ready() -> void:
	hp_bar = ProgressBar.new(); hp_bar.position = Vector2(14, 12); hp_bar.size = Vector2(220, 18)
	hp_bar.show_percentage = false; hp_bar.max_value = 100; hp_bar.value = 100
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("ff5fa2"); hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, .55); hp_bar.add_theme_stylebox_override("background", bg)
	add_child(hp_bar)
	var hpl := Label.new(); hpl.text = "HP"; hpl.position = Vector2(18, 11); hpl.add_theme_font_size_override("font_size", 13); add_child(hpl)
	obj = _rich(Vector2(500, 12), Vector2(450, 80), 16, Color("7bf7ff"))
	ban = _rich(Vector2(0, 150), Vector2(960, 60), 30, Color("ffd66b"))
	# 7.2's #toasts: a column at the bottom, up to three at once, newest last
	toasts = VBoxContainer.new(); toasts.position = Vector2(80, 210); toasts.size = Vector2(800, 340)
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
	# (under the HP bar: the lesson/quiz panel covers 7.2's spot further down)
	skip_btn = _button("⏭ SKIP THIS LESSON\nAlready know it? Answer 3 questions\ncorrectly and move on.  [K]", Vector2(10, 40), Color("3dff9e"), 11)
	skip_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT; skip_btn.visible = false
	save_btn = _button("💾 SAVE & LOAD", Vector2(800, 684), Color("7bf7ff"), 13)
	save_btn.pressed.connect(func(): save_pressed.emit())

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

func objective(t: String) -> void: obj.text = "[right]%s[/right]" % t
func banner(t: String) -> void: ban.text = "[center]%s[/center]" % t; _ban_t = 3.0

# 7.2's toast(html, ms, bad): up to three stacked, each on its own timer; bold words in cyan like .toast b;
# a red border for warnings
func toast(t: String, dur := 6.0, bad := false) -> void:
	while toasts.get_child_count() >= 3:
		var old := toasts.get_child(0); toasts.remove_child(old); old.queue_free()
	var p := PanelContainer.new(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(20 / 255.0, 8 / 255.0, 38 / 255.0, .92)
	sb.border_color = Color("ff3b3b") if bad else Color("ff5fa2"); sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	sb.content_margin_left = 20; sb.content_margin_right = 20; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.custom_minimum_size = Vector2(620, 0); r.mouse_filter = Control.MOUSE_FILTER_IGNORE; _sizes(r, 17)
	r.text = "[center]%s[/center]" % t.replace("[b]", "[b][color=#7bf7ff]").replace("[/b]", "[/color][/b]")
	p.add_child(r); p.set_meta("t", dur); toasts.add_child(p)

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
	for p in toasts.get_children():
		var left: float = p.get_meta("t") - dt; p.set_meta("t", left)
		if left <= 0: toasts.remove_child(p); p.queue_free()
