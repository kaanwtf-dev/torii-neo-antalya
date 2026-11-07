# The Turkish lesson + quiz screen, ported from 7.2 (say() lesson box, runQuiz/nextQ/finishQ):
# the lesson one line per page (E / Enter / Space, like 7.2's dialogue box), multiple choice (click or
# 1-4), type-the-answer (accents optional), tap-the-words-in-order (Enter checks), progress dots,
# ✅/❌ feedback with the explanation, and QUİZİ GEÇ (K) on the quizzes 7.2 lets her skip.
# It's an overlay: the fight stops while it's open. Every quiz of 3+ questions ends with the score toast
# (Lessons.summary, 7.2's nextQ); answers make 7.2's sounds (fx.yes / fx.chuckle / fx.no) and a wrong one
# flashes the screen red (vig('hurt')).
class_name QuizUI
extends CanvasLayer

signal answered(ok: bool, q: Dictionary)

static var open := false
var panel: PanelContainer
var tag: Label
var vis: Label
var text: RichTextLabel
var prog: HBoxContainer
var opts: GridContainer
var fill: LineEdit
var order_box: VBoxContainer
var slot: HFlowContainer
var bank: HFlowContainer
var feed: RichTextLabel
var hint: Label
var cont: Label
var queue: Array = []
var cur := {}
var score: Array[bool] = []
var total := 0
var lock := false
var done_cb: Callable
var lesson_cb: Callable
var picked: Array = []
var pool: Array = []
var pages: Array = []
var qskip: Button
var _run := 0                 # bumps every quiz, so a stale feedback timer can't touch the next one

func _ready() -> void:
	layer = 5
	open = false
	panel = PanelContainer.new(); panel.position = Vector2(110, 120); panel.size = Vector2(740, 480); panel.visible = false
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, 1.0); sb.border_color = Color("ff5fa2")
	sb.set_border_width_all(2); sb.set_corner_radius_all(12); sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb); add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); panel.add_child(v)
	tag = _lab(v, 14, Color("ffd66b")); tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog = HBoxContainer.new(); prog.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(prog)
	vis = _lab(v, 40, Color.WHITE); vis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text = RichTextLabel.new(); text.bbcode_enabled = true; text.fit_content = true; text.custom_minimum_size = Vector2(700, 0)
	text.add_theme_font_size_override("normal_font_size", 20); text.add_theme_font_size_override("bold_font_size", 20)
	text.add_theme_font_size_override("italics_font_size", 20); text.add_theme_color_override("default_color", Color.WHITE)
	v.add_child(text)
	hint = _lab(v, 12, Color("8a7aae")); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opts = GridContainer.new(); opts.columns = 2; opts.add_theme_constant_override("h_separation", 10)
	opts.add_theme_constant_override("v_separation", 10); v.add_child(opts)
	fill = LineEdit.new(); fill.placeholder_text = "type here, press ENTER"; fill.add_theme_font_size_override("font_size", 20)
	fill.text_submitted.connect(func(_t): _submit_fill()); v.add_child(fill)
	order_box = VBoxContainer.new(); v.add_child(order_box)
	slot = HFlowContainer.new(); order_box.add_child(slot)
	bank = HFlowContainer.new(); order_box.add_child(bank)
	var ok_btn := Button.new(); ok_btn.text = "CHECK ✓"; ok_btn.pressed.connect(_submit_order); order_box.add_child(ok_btn)
	feed = RichTextLabel.new(); feed.bbcode_enabled = true; feed.fit_content = true; feed.custom_minimum_size = Vector2(700, 0)
	feed.add_theme_font_size_override("normal_font_size", 17); feed.add_theme_font_size_override("bold_font_size", 17); v.add_child(feed)
	cont = _lab(v, 13, Color("7bf7ff")); cont.text = "[E] continue"; cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qskip = Button.new(); qskip.text = "⏭ QUİZİ GEÇ · SKIP (no re-roll bonus)  [K]"; qskip.focus_mode = Control.FOCUS_NONE
	qskip.add_theme_font_size_override("font_size", 13); qskip.add_theme_color_override("font_color", Color("d8ffe8"))
	qskip.visible = false; qskip.pressed.connect(skip_all); v.add_child(qskip)

func _lab(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new(); l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD; parent.add_child(l); return l

func _show(on: bool) -> void:
	panel.visible = on; open = on
	if on: Overlay.open("quiz")
	else: Overlay.close("quiz"); qskip.visible = false

# the lesson's explanation first, one line per page like 7.2's say() box, then whatever comes next
func show_lesson(title: String, lines: Array, then: Callable) -> void:
	_reset(); _show(true); lesson_cb = then; pages = lines.duplicate()
	tag.text = title; vis.text = "📖"
	_page()

func _page() -> void:
	text.text = str(pages[0]) if pages.size() else ""
	cont.visible = true

func _next_page() -> void:
	pages.pop_front()
	if pages.size(): _page(); return
	var cb := lesson_cb; lesson_cb = Callable(); _show(false); cb.call()

# skippable = 7.2's runQuiz(..., skippable): revision and practice quizzes show QUİZİ GEÇ
func run(qs: Array, on_done: Callable, tag_text := "TURKISH QUIZ 🇹🇷", skippable := false) -> void:
	_run += 1
	queue = qs.duplicate(); done_cb = on_done; score = []; total = qs.size(); lesson_cb = Callable(); pages = []
	tag.text = tag_text; _show(true); qskip.visible = skippable; _next()

# 7.2's quizSkipAll(): drop the rest of the quiz and move on
func skip_all() -> void:
	if not open or not qskip.visible: return
	_run += 1
	queue = []; lock = true; total = 0; _show(false)
	if Lessons.me: Lessons.me.hud.toast("⏭ Quiz atlandı. [i](Quiz skipped — no re-rolls this game.)[/i]", 5.0)
	var cb := done_cb; done_cb = Callable()
	if cb.is_valid(): cb.call(score)

func _reset() -> void:
	for c in opts.get_children(): c.queue_free()
	for c in prog.get_children(): c.queue_free()
	opts.visible = false; fill.visible = false; order_box.visible = false; cont.visible = false
	feed.text = ""; hint.text = ""

func _dots() -> void:
	for c in prog.get_children(): c.queue_free()
	for i in total:
		var d := ColorRect.new(); d.custom_minimum_size = Vector2(16, 6)
		d.color = (Color("3dff9e") if score[i] else Color("ff4d6d")) if i < score.size() else (Color("ffd66b") if i == score.size() else Color(1, 1, 1, .2))
		prog.add_child(d)

func _next() -> void:
	_reset()
	if queue.is_empty():
		_show(false)
		if total > 2 and Lessons.me: Lessons.me.summary(score)
		var cb := done_cb; done_cb = Callable()
		if cb.is_valid(): cb.call(score)
		return
	cur = queue.pop_front(); lock = false
	vis.text = cur.get("vis", "✍️"); text.text = cur.get("text", "")
	_dots()
	match cur.get("kind", "mc"):
		"fill":
			hint.text = "TYPE YOUR ANSWER — accents optional"
			fill.visible = true; fill.text = ""; fill.editable = true; fill.grab_focus.call_deferred()
		"order":
			hint.text = "TAP THE WORDS IN THE RIGHT ORDER — remember: the verb goes LAST"
			order_box.visible = true; picked = []; pool = cur["words"].duplicate(); pool.shuffle(); _draw_order()
		_:
			# options are shuffled every single time
			var pairs := []
			for i in cur["opts"].size(): pairs.append([cur["opts"][i], i == int(cur.get("a", 0))])
			pairs.shuffle()
			cur = cur.duplicate(); cur["opts"] = pairs.map(func(p): return p[0])
			cur["a"] = pairs.find(pairs.filter(func(p): return p[1])[0])
			opts.visible = true
			for i in cur["opts"].size():
				var b := Button.new(); b.text = "%d. %s" % [i + 1, cur["opts"][i]]; b.custom_minimum_size = Vector2(340, 44)
				b.add_theme_font_size_override("font_size", 18); b.pressed.connect(_pick.bind(i)); opts.add_child(b)
	if cur.has("say"): Tts.say(cur["say"])

func _draw_order() -> void:
	for c in slot.get_children(): c.queue_free()
	for c in bank.get_children(): c.queue_free()
	for i in picked.size():
		var b := Button.new(); b.text = picked[i]; b.pressed.connect(func():
			if lock: return
			pool.append(picked[i]); picked.remove_at(i); _draw_order()); slot.add_child(b)
	for i in pool.size():
		var b := Button.new(); b.text = pool[i]; b.pressed.connect(func():
			if lock: return
			picked.append(pool[i]); pool.remove_at(i); _draw_order()); bank.add_child(b)

static func norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["ı", "i"], ["i̇", "i"], ["ş", "s"], ["ğ", "g"], ["ü", "u"], ["ö", "o"], ["ç", "c"]]: s = s.replace(pair[0], pair[1])
	for p in [".", ",", "!", "?", ";", ":", "'", "\""]: s = s.replace(p, "")
	return " ".join(s.split(" ", false)).strip_edges()

func _pick(i: int) -> void:
	if lock: return
	var a := int(cur["a"])
	opts.get_child(i).modulate = Color("3dff9e") if i == a else Color("ff4d6d")
	if i != a: opts.get_child(a).modulate = Color("3dff9e")
	_finish(i == a, cur["opts"][a])

func _submit_fill() -> void:
	if lock or not fill.visible: return
	if fill.text.strip_edges() == "": feed.text = "Type something first!"; return
	var acc: Array = cur["answer"] if cur["answer"] is Array else [cur["answer"]]
	_finish(acc.any(func(a): return norm(a) == norm(fill.text)), acc[0]); fill.editable = false

func _submit_order() -> void:
	if lock: return
	if picked.size() < cur["words"].size(): feed.text = "Use all the words first!"; return
	_finish(norm(" ".join(picked)) == norm(" ".join(cur["words"])), " ".join(cur["words"]))

func _finish(ok: bool, correct: String) -> void:
	lock = true; score.append(ok); _dots()
	if ok:
		feed.text = "[color=#3dff9e]DOĞRU! ✅ Correct! +15 XP +10 mana[/color]"
		Bus.emit_ev("sfx", {"name": "yes"})
		if randf() < .35: Bus.emit_ev("sfx", {"name": "chuckle"})
	else:
		Bus.emit_ev("sfx", {"name": "no"})
		if Fx.me: Fx.me.flash("hurt")
		feed.text = "[color=#ff4d6d]Wrong ❌[/color] Answer: [b]%s[/b]" % correct
		if cur.get("expl", "") != "": feed.text += "\n[color=#8ff2ff]%s[/color]" % cur["expl"]
	answered.emit(ok, cur)
	var run_id := _run
	await get_tree().create_timer(1.4 if ok else 3.2).timeout
	if run_id == _run and open: _next()

func _unhandled_input(e: InputEvent) -> void:
	if not open: return
	if e is InputEventKey and e.pressed and not e.echo:
		var enter: bool = e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER
		if lesson_cb.is_valid() and (enter or e.keycode == KEY_E or e.keycode == KEY_SPACE):
			_next_page()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_K and qskip.visible:
			skip_all()
			get_viewport().set_input_as_handled()
		elif order_box.visible and enter:
			_submit_order()
			get_viewport().set_input_as_handled()
		elif opts.visible and e.keycode >= KEY_1 and e.keycode <= KEY_4:
			var i: int = e.keycode - KEY_1
			if i < opts.get_child_count(): _pick(i)
			get_viewport().set_input_as_handled()
