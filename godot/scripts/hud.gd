# On-screen bits for the slice: HP bar, the current objective, Kaan's phone call box, banners and toasts.
# Drawn at full window resolution on top of the pixelated 3D, in 7.2's neon colours.
class_name Hud
extends CanvasLayer

var hp_bar: ProgressBar
var obj: Label
var box: PanelContainer
var who: Label
var line: Label
var ban: Label
var tst: Label
var _ban_t := 0.0
var _tst_t := 0.0

func _ready() -> void:
	hp_bar = ProgressBar.new(); hp_bar.position = Vector2(14, 12); hp_bar.size = Vector2(220, 18)
	hp_bar.show_percentage = false; hp_bar.max_value = 100; hp_bar.value = 100
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("ff5fa2"); hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, .55); hp_bar.add_theme_stylebox_override("background", bg)
	add_child(hp_bar)
	var hpl := Label.new(); hpl.text = "HP"; hpl.position = Vector2(18, 11); hpl.add_theme_font_size_override("font_size", 13); add_child(hpl)
	obj = _label(Vector2(560, 12), 16, Color("7bf7ff")); obj.size = Vector2(390, 60)
	obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; obj.autowrap_mode = TextServer.AUTOWRAP_WORD
	ban = _label(Vector2(0, 150), 30, Color("ffd66b")); ban.size = Vector2(960, 50); ban.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tst = _label(Vector2(130, 520), 18, Color.WHITE); tst.size = Vector2(700, 80)
	tst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tst.autowrap_mode = TextServer.AUTOWRAP_WORD
	box = PanelContainer.new(); box.position = Vector2(120, 560); box.size = Vector2(720, 130); box.visible = false
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.08, .04, .14, .92); sb.border_color = Color("ff5fa2")
	sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.set_content_margin_all(14)
	box.add_theme_stylebox_override("panel", sb); add_child(box)
	var v := VBoxContainer.new(); box.add_child(v)
	who = Label.new(); who.add_theme_color_override("font_color", Color("ff5fa2")); who.add_theme_font_size_override("font_size", 16); v.add_child(who)
	line = Label.new(); line.autowrap_mode = TextServer.AUTOWRAP_WORD; line.custom_minimum_size = Vector2(690, 0)
	line.add_theme_font_size_override("font_size", 18); v.add_child(line)
	var hint := Label.new(); hint.text = "ENTER ▸"; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color("7bf7ff")); hint.add_theme_font_size_override("font_size", 13); v.add_child(hint)

func _label(at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new(); l.position = at; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); l.add_theme_constant_override("outline_size", 6)
	add_child(l); return l

func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp; hp_bar.value = hp

func objective(t: String) -> void: obj.text = t
func call_box(name: String, t: String) -> void:
	box.visible = t != ""; who.text = name; line.text = t
func banner(t: String) -> void: ban.text = t; _ban_t = 3.0
func toast(t: String, dur := 3.0) -> void: tst.text = t; _tst_t = dur

# a question with buttons (the bazaar haggle, the gods' coin game); pauses her like a quiz does
var _choice: PanelContainer
func choose(who_: String, text_: String, opts: Array, cb: Callable) -> void:
	if _choice: _choice.queue_free()
	_choice = PanelContainer.new(); _choice.position = Vector2(140, 200); _choice.size = Vector2(680, 0)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, 1); sb.border_color = Color("ffd66b")
	sb.set_border_width_all(2); sb.set_corner_radius_all(12); sb.set_content_margin_all(18)
	_choice.add_theme_stylebox_override("panel", sb); add_child(_choice)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); _choice.add_child(v)
	var w := Label.new(); w.text = who_; w.add_theme_color_override("font_color", Color("ffd66b")); w.add_theme_font_size_override("font_size", 16); v.add_child(w)
	var q := RichTextLabel.new(); q.bbcode_enabled = true; q.fit_content = true; q.text = text_; q.custom_minimum_size = Vector2(640, 0)
	q.add_theme_font_size_override("normal_font_size", 18); q.add_theme_font_size_override("bold_font_size", 18); q.add_theme_font_size_override("italics_font_size", 18); v.add_child(q)
	for i in opts.size():
		var b := Button.new(); b.text = "%d. %s" % [i + 1, opts[i]]; b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			_choice.queue_free(); _choice = null; QuizUI.open = false; Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			cb.call(i))
		v.add_child(b)
	QuizUI.open = true; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(dt: float) -> void:
	_ban_t -= dt; _tst_t -= dt
	ban.visible = _ban_t > 0; tst.visible = _tst_t > 0
