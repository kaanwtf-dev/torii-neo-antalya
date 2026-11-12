# 🔠 YAZI BOYUTU · TEXT SIZE — 7.2's UI size slider (optFs / applyOpts --fs), as steps on the pause menu.
# One multiplier for every text-heavy box: save field `gFs` (default 1.0 = the sizes written in the code).
#   UiScale.k()              the multiplier now (read from the save, so NEW GAME / reloads keep it)
#   UiScale.px(17)           a font size at the current text size (cap = the most this one may grow)
#   UiScale.bb(text)         scales the [font_size=N] tags inside BBCode
#   UiScale.wide(620, 900)   a box width/height that grows with the text (never below the base, at most max)
#   UiScale.apply(node)      (re)scales a built box and everything in it from the sizes it was built with, so
#                            build at the normal sizes, then apply; calling it again later is safe
#   Bus "ui_scale" {k}       fires when she changes it (the HUD re-applies itself live)
# At 100% every function returns exactly what it was given.
class_name UiScale
extends RefCounted

const STEPS := [0.8, 1.0, 1.25, 1.5, 1.75]
const KEYS_RICH := ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]

static var dev_k := 0.0        # dev only (--fs=N): this run's text size, never written to the save

static func k() -> float:
	if dev_k > 0.0: return clampf(dev_k, 0.5, 3.0)
	var v = SaveBridge.data.get("gFs", 1.0)
	return clampf(float(v), 0.5, 3.0) if (v is float or v is int) else 1.0

static func px(n: float, cap := 9.0) -> int: return maxi(1, roundi(n * minf(k(), cap)))

static func wide(base: float, mx: float) -> float:
	var s := k()
	return base if s <= 1.0 else minf(mx, base * s)

static func bb(t: String, cap := 9.0) -> String:
	if is_equal_approx(minf(k(), cap), 1.0) or not t.contains("[font_size="): return t
	var re := RegEx.new(); re.compile("\\[font_size=(\\d+)\\]")
	var out := ""; var at := 0
	for m in re.search_all(t):
		out += t.substr(at, m.get_start() - at) + "[font_size=%d]" % px(float(m.get_string(1)), cap)
		at = m.get_end()
	return out + t.substr(at)

static func apply(root: Node, cap := 9.0) -> void:
	if root == null or not is_instance_valid(root): return
	var list: Array = [root]
	list.append_array(root.find_children("*", "Control", true, false))
	for c in list:
		if not (c is Label or c is Button or c is LineEdit or c is RichTextLabel) or c.has_meta("fs_skip"): continue
		if not c.has_meta("fs0"):                 # the size it was built with (an override or the theme's)
			var base := {}
			for key in (KEYS_RICH if c is RichTextLabel else ["font_size"]): base[key] = c.get_theme_font_size(key)
			c.set_meta("fs0", base)
		var b: Dictionary = c.get_meta("fs0")
		for key in b: c.add_theme_font_size_override(key, px(float(b[key]), cap))

static func label() -> String: return "%d%%" % roundi(k() * 100.0)

# the pause menu's button: the next step (after the biggest, back to the smallest)
static func cycle() -> void:
	var now := k()
	var nx: float = STEPS[0]
	for s in STEPS:
		if s > now + .001: nx = s; break
	SaveBridge.data["gFs"] = nx; dev_k = 0.0
	Bus.emit_ev("ui_scale", {"k": nx})

# dev only: --fs=1.75 sets the text size for this run; --fsdemo=DIR opens every scaled box once, saves a
# screenshot of each into DIR, then quits (use with --continue and --savedir=)
static func dev(main: Node, hud: Hud) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fs="):
			dev_k = float(a.substr(5)); Bus.emit_ev("ui_scale", {"k": k()})
		if a.begins_with("--fsdemo="): _demo(main, hud, a.substr(9))
		if a.begins_with("--menudemo="): _menudemo(main, hud, a.substr(11))
		if a.begins_with("--smoke82="): _smoke(main, hud, a.substr(10))

static func _shot(main: Node, dir: String, n: String) -> void:
	await main.get_tree().create_timer(.5, true).timeout
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])
	print("FSDEMO ", n)

static func _demo(main: Node, hud: Hud, dir: String) -> void:
	await main.get_tree().create_timer(3.0, true).timeout
	if Menus.me: Menus.me.close_patch()
	await main.call("_dev_clear", hud)         # the story's opening call scene / tip card
	await main.get_tree().create_timer(1.0, true).timeout
	if Menus.me: Menus.me.close_patch()        # an older save's patch notes pop up once that call is over
	await _shot(main, dir, "hud")
	var cs = Cutscene.me
	if cs:
		cs.play([{"who": "Kaan", "line": "Bebeğim! [Merhaba] (hello) — a long subtitle line to see how the letterbox holds it at this size.", "title": "BÖLÜM 1 · THE AVOCADO RUN"}])
		await _shot(main, dir, "cut"); cs.end(true)
	var L = Lessons.me
	if L and L.quiz:
		L.quiz.show_lesson("Selamlar · Greetings", ["[b]Merhaba[/b] (hello) works any time of day. [b]Günaydın[/b] (good morning) is for the morning, and [b]İyi akşamlar[/b] (good evening) for later."], func(): pass)
		await _shot(main, dir, "lesson")
		L.quiz.run([{"text": "What does [b]Teşekkür ederim[/b] mean?", "vis": "🙏", "opts": ["thank you very much", "good morning", "see you later, my friend", "excuse me"], "a": 0}], func(_s): pass)
		await _shot(main, dir, "quiz"); L.quiz.queue = []; L.quiz.done_cb = Callable(); L.quiz.total = 0; L.quiz._show(false)
	hud.toast("🍉 [b]Karpuz[/b] (watermelon) — a long toast line to see how the wrapping looks at this size", 9.0)
	hud.toast("💰 +30₺ · [b]+12 XP[/b]", 9.0)
	hud.banner("⭐ LEVEL 12 ⭐\n[font_size=16]✨ invulnerable[/font_size]")
	hud.say("Kaan 📞", ["Bebeğim! [b]Merhaba[/b] (hello) — the imps are back at the fountain, can you go check it out for me? Bandit knows the way."])
	await _shot(main, dir, "say")
	hud.skip_say()
	hud.choose("🪙 Tanrı · God", "Yazı mı tura mı? [i](Heads or tails?)[/i] Bet 40₺ on the coin, Torii.", ["Yazı · heads", "Tura · tails", "Hayır · no thanks, I am just walking past"], func(_i): pass)
	await _shot(main, dir, "choice")
	hud._pick_choice(-1)
	if LevelUp.me:
		LevelUp.me._show_tip("combo"); await _shot(main, dir, "tip"); LevelUp.me.close_tip()
	if Menus.me:
		Menus.me.open_pause(); await _shot(main, dir, "pause")
		Menus.me.open_guide(true); await _shot(main, dir, "guide")
		Menus.me.close_guide(); Menus.me.close_pause()
		Menus.me.show_patch(true); await _shot(main, dir, "patch"); Menus.me.close_patch()
	if InventoryUI.me:
		InventoryUI.me.open("gear"); await _shot(main, dir, "inv_gear")
		InventoryUI.me.open("bag"); await _shot(main, dir, "inv_bag"); InventoryUI.me.close()
	main.call("_quit")

# dev only: --menudemo=DIR (with --continue --savedir=, any --resolution / --fs=) saves a shot of every menu,
# bag tab and card (title, NEW GAME confirm, pause, guide, patch notes, the I bag tabs, perk pick, tip card,
# milestone card, the toggle bar + buff list), then quits. For the widescreen checks.
static func _menudemo(main: Node, hud: Hud, dir: String) -> void:
	await main.get_tree().create_timer(3.0, true).timeout
	if Menus.me: Menus.me.close_patch()
	await main.call("_dev_clear", hud)
	await main.get_tree().create_timer(1.0, true).timeout
	if Menus.me: Menus.me.close_patch()
	var M = Menus.me
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Items.me: Items.me.buffs["regen"] = 30.0; Items.me.buffs["lucky"] = 30.0
	if M: M._prompt_t = 99.0; M._prompt.text = "E: ride the Diamond Back 🚲"; M._prompt.visible = true
	await _shot(main, dir, "bar")
	if M:
		M._prompt_t = 0.0
		M.title(); await _shot(main, dir, "title")
		M._ask_new(true); await _shot(main, dir, "confirm")
		M._close_title()
		M.open_pause(); await _shot(main, dir, "pause")
		M.open_guide(true); await _shot(main, dir, "guide")
		M.close_guide(); M.close_pause()
		M.show_patch(true); await _shot(main, dir, "patch"); M.close_patch()
	if InventoryUI.me:
		for t in ["gear", "bag", "cards", "nazar", "quests", "stats"]:
			InventoryUI.me.open(t); await _shot(main, dir, "inv_" + t)
		InventoryUI.me.close()
	if LevelUp.me:
		var pp0 = SaveBridge.data.get("pp")
		SaveBridge.data["pp"] = maxi(1, SaveBridge.get_i("pp"))
		LevelUp.me.open_perks(); await _shot(main, dir, "perks")
		SaveBridge.data["pp"] = 0; LevelUp.me.close_perks()
		if pp0 == null: SaveBridge.data.erase("pp")
		else: SaveBridge.data["pp"] = pp0
		LevelUp.me._show_tip("combo"); await _shot(main, dir, "tip"); LevelUp.me.close_tip()
		LevelUp.me._card(LevelUp.me.milestone_for(10)); await main.get_tree().create_timer(.6, true).timeout
		await _shot(main, dir, "milestone")
	main.call("_quit")

# dev only: --smoke82=DIR (with --continue --savedir=, any --resolution): the widescreen smoke tour (play HUD, the
# weapon wheel, a call in the letterbox, a lesson, a quiz, pause / options, the bag, the title), then quits.
# --smokeresize=WxH: after the first round the window changes to that size and the tour runs again (rs_*.png).
static func _smoke(main: Node, hud: Hud, dir: String) -> void:
	var rs := ""
	for a in OS.get_cmdline_user_args(): if a.begins_with("--smokeresize="): rs = a.substr(14)
	await main.get_tree().create_timer(3.0, true).timeout
	if Menus.me: Menus.me.close_patch()
	await main.call("_dev_clear", hud)
	await main.get_tree().create_timer(1.0, true).timeout
	if Menus.me: Menus.me.close_patch()
	await _smoke_round(main, hud, dir, "")
	if rs != "":
		var wh := rs.split("x")
		main.get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		await main.get_tree().create_timer(1.0, true, false, true).timeout
		await _smoke_round(main, hud, dir, "rs_")
	main.call("_quit")

static func _smoke_round(main: Node, hud: Hud, dir: String, pre: String) -> void:
	await _shot(main, dir, pre + "hud")
	if Arsenal.me:
		Arsenal.me.open_wheel()
		await main.get_tree().create_timer(.6, true, false, true).timeout
		await RenderingServer.frame_post_draw
		main.get_viewport().get_texture().get_image().save_png("%s/%swheel.png" % [dir, pre]); print("FSDEMO ", pre, "wheel")
		Arsenal.me.close_wheel(false)
	var cs = Cutscene.me
	if cs:
		cs.play([{"who": "Kaan", "line": "Bebeğim! [Merhaba] (hello) — a long subtitle line to see how the letterbox holds it at this size.", "title": "BÖLÜM 1 · THE AVOCADO RUN"}])
		await _shot(main, dir, pre + "cut"); cs.end(true)
	var L = Lessons.me
	if L and L.quiz:
		L.quiz.show_lesson("Selamlar · Greetings", ["[b]Merhaba[/b] (hello) works any time of day. [b]Günaydın[/b] (good morning) is for the morning, and [b]İyi akşamlar[/b] (good evening) for later."], func(): pass)
		await _shot(main, dir, pre + "lesson")
		L.quiz.run([{"text": "What does [b]Teşekkür ederim[/b] mean?", "vis": "🙏", "opts": ["thank you very much", "good morning", "see you later, my friend", "excuse me"], "a": 0}], func(_s): pass)
		await _shot(main, dir, pre + "quiz"); L.quiz.queue = []; L.quiz.done_cb = Callable(); L.quiz.total = 0; L.quiz._show(false)
	if Menus.me:
		Menus.me.open_pause(); await _shot(main, dir, pre + "pause"); Menus.me.close_pause()
	if InventoryUI.me:
		InventoryUI.me.open("bag"); await _shot(main, dir, pre + "inv_bag"); InventoryUI.me.close()
	if Menus.me:
		Menus.me.title(); await _shot(main, dir, pre + "title"); Menus.me._close_title()
	await main.get_tree().create_timer(.4, true).timeout
