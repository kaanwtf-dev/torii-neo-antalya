# The tavla screen, ported from 7.2's #tavla / #tvBetBox (TRK-05..08): the stake screen (tvOpenBet / closeBet /
# tvBetGo: any amount up to min(table cap, her lira), 0 / 25% / 50% / MAX, match to 1/3/5/7, OTOROLL), then the
# board (tvDraw: 24 points, bar, off tray, flat clean checkers — pink hers, ink theirs), spinning dice
# (tvSpinDice), click-or-drag moves with a flying checker (tvPickSource / tvDoMove / tvFlyStart), ↩ GERİ AL
# (8 moves back, right-click, Z or Backspace — tvSnapshot / tvUndo), ZAR AT / 🔄 ZAR HAKKI (re-rolls earned in
# the pre-game Turkish quiz, tvPreGameQuiz) / SIRAYI BİTİR / OTOROLL / ÇIK, the per-opponent turn clock
# (a "slow" taunt at 18 s, a random move at 0, paused while a taunt is up — tvLoop / tvTimeout), the AI's turn
# (tvAITurn, Kaan's open re-rolls), and the trash talk (TRASH / KAANTALK / TAUNT / TVFLAVOR / tvTaunt: a Turkish
# line + English, sm / lg / mega with a shake, spoken in the mob's voice). Mars (gammon) = 2 points.
# Esc leaves the table ("Kaçtın mı?"). It's an overlay ("tavla"), so the world waits.
class_name TavlaUI
extends CanvasLayer

const TVW := 760.0
const TVH := 470.0
const TVPW := 53.3
const TVL := 20.0
const TVR := 680.0
const TVBARX := 340.0
const TVBARW := 30.0
const BO := Vector2(100, 112)          # where the board sits on the 960x720 screen
const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURP := Color("b06bff")

var T: Tavla
var root: Control
var board: Control
var who_l: RichTextLabel
var score_l: RichTextLabel
var msg_l: RichTextLabel
var b_roll: Button
var b_rer: Button
var b_undo: Button
var b_done: Button
var b_auto: Button
var b_quit: Button
var taunt_box: PanelContainer
var taunt_l: RichTextLabel
var bet: PanelContainer
var bet_in: LineEdit
var bet_msg: Label
var bet_len := 3
var bet_npc := {}
var _len_btns: Array = []
var _auto_b2: Button

var M := {}                     # match: npc, target, my, opp, stake
var G := {}                     # game: s, turn, dice, rolled, used, sel, dests, off_ok, legal, busy, rerolls, hist, cheat
var clock := 60.0
var clock_max := 60.0
var nagged := false
var taunt := {}
var fly := {}
var spin := {}
var drag := {}
var auto := false
var _gid := 0
var _dismissed := 0

func setup(t: Tavla) -> void:
	T = t; layer = 4
	# widescreen (8.2): the dim covers the whole window; the table itself is a 960x720 block kept in the real centre
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_STOP; root.visible = false; add_child(root)
	var bg := ColorRect.new(); bg.color = Color(.03, .01, .07, .92); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(bg)
	var fr := Control.new(); Shops.center(fr, Vector2.ZERO, Screen.BASE); fr.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(fr)
	who_l = Shops.rich("", 17, Color("ffe9fb"), 860); who_l.position = Vector2(50, 18); fr.add_child(who_l)
	score_l = Shops.rich("", 15, GOLD, 860); score_l.position = Vector2(50, 50); fr.add_child(score_l)
	board = Control.new(); board.position = BO; board.size = Vector2(TVW, TVH); board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.draw.connect(_draw_board); board.gui_input.connect(_board_input); fr.add_child(board)
	msg_l = Shops.rich("", 15, Color("ffe9fb"), 860); msg_l.position = Vector2(50, 592); fr.add_child(msg_l)
	var row := HBoxContainer.new(); row.position = Vector2(50, 650); row.add_theme_constant_override("separation", 8); fr.add_child(row)
	b_roll = Shops.button("🎲 ZAR AT", GOLD, 15); b_roll.pressed.connect(roll); row.add_child(b_roll)
	b_rer = Shops.button("🔄 ZAR HAKKI (0)", Color("5fff9e"), 15); b_rer.pressed.connect(reroll); row.add_child(b_rer)
	b_undo = Shops.button("↩ GERİ AL (0)", GOLD, 15); b_undo.pressed.connect(undo); row.add_child(b_undo)
	b_done = Shops.button("✔ SIRAYI BİTİR", CYAN, 15); b_done.pressed.connect(func(): if G.get("turn") == 1 and not G.get("busy", true): end_turn()); row.add_child(b_done)
	b_auto = Shops.button("", PURP, 13); b_auto.pressed.connect(func(): set_auto(not auto)); row.add_child(b_auto)
	b_quit = Shops.button("✕ ÇIK", PINK, 15); b_quit.pressed.connect(quit); row.add_child(b_quit)
	taunt_box = PanelContainer.new(); taunt_box.visible = false; taunt_box.mouse_filter = Control.MOUSE_FILTER_STOP
	taunt_box.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close_taunt(); _dismissed = Time.get_ticks_msec())
	taunt_l = Shops.rich("", 20, Color.WHITE, 520); taunt_box.add_child(taunt_l); fr.add_child(taunt_box)
	_build_bet()
	set_auto(false)

static func _sb(col: Color) -> StyleBoxFlat: return Shops.panel_box(col)

# ================================================================ the stake screen (tvOpenBet)
func _build_bet() -> void:
	bet = PanelContainer.new(); Shops.center(bet, Vector2(180, 130), Vector2(600, 0)); bet.visible = false
	bet.add_theme_stylebox_override("panel", _sb(GOLD)); add_child(bet)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); bet.add_child(v)
	v.add_child(Shops.rich("", 20, GOLD, 570)); v.add_child(Shops.rich("", 14, Color("bfeefc"), 570)); v.add_child(Shops.rich("", 14, Color("ffe9fb"), 570))
	var ir := HBoxContainer.new(); v.add_child(ir)
	var lab := Label.new(); lab.text = "Bahis · stake (₺): "; lab.add_theme_font_size_override("font_size", 16); ir.add_child(lab)
	bet_in = LineEdit.new(); bet_in.custom_minimum_size = Vector2(160, 0); bet_in.add_theme_font_size_override("font_size", 18)
	bet_in.text_submitted.connect(func(_t): _bet_go()); ir.add_child(bet_in)
	var q := HBoxContainer.new(); q.name = "quick"; q.add_theme_constant_override("separation", 6); v.add_child(q)
	var lr := HBoxContainer.new(); lr.add_theme_constant_override("separation", 6); v.add_child(lr)
	var ll := Label.new(); ll.text = "Maç · first to: "; ll.add_theme_font_size_override("font_size", 15); lr.add_child(ll)
	_len_btns = []
	for n in [1, 3, 5, 7]:
		var b := Shops.button(str(n), CYAN, 15); b.pressed.connect(func(): bet_len = n; _paint_len()); lr.add_child(b); _len_btns.append([n, b])
	_auto_b2 = Shops.button("", PURP, 13); _auto_b2.pressed.connect(func(): set_auto(not auto)); v.add_child(_auto_b2)
	bet_msg = Label.new(); bet_msg.add_theme_color_override("font_color", Color("ff6b8a")); bet_msg.add_theme_font_size_override("font_size", 14); v.add_child(bet_msg)
	var br := HBoxContainer.new(); br.add_theme_constant_override("separation", 10); v.add_child(br)
	var go := Shops.button("⚂ OTUR · PLAY", GOLD, 17); go.pressed.connect(_bet_go); br.add_child(go)
	var no := Shops.button("Vazgeç · cancel", PINK, 15); no.pressed.connect(close_bet); br.add_child(no)

func _paint_len() -> void:
	for p in _len_btns: (p[1] as Button).modulate = Color(1.3, 1.3, 1.3) if p[0] == bet_len else Color(.7, .7, .75)

func open_bet(N: Dictionary) -> void:
	bet_npc = N; bet_len = 3
	var cap := mini(int(N["cap"]), Shops.lira())
	var v: VBoxContainer = bet.get_child(0)
	(v.get_child(0) as RichTextLabel).text = "⚂ " + str(N["name"])
	(v.get_child(1) as RichTextLabel).text = "%s\n[color=#ffd66b]ZORLUK / DIFFICULTY [b]%d/10[/b][/color] [color=#ff5fa2]%s[/color] · %ds per turn" % [N["title"], int(N["diff"]), Tavla.diff_stars(int(N["diff"])), int(N["time"])]
	(v.get_child(2) as RichTextLabel).text = "Bu masanın limiti: [b]%d₺[/b] [i](this table's cap — tougher opponents allow bigger bets)[/i]\nCebinde: [b]%d₺[/b] · Kazanırsan iki katı. [i](Win and it doubles.)[/i]" % [int(N["cap"]), Shops.lira()]
	bet_in.text = str(mini(50, cap))
	var q: HBoxContainer = v.get_node("quick")
	for c in q.get_children(): c.queue_free()
	for f in [0.0, .25, .5, 1.0]:
		var amt := 0 if f == 0.0 else int(floor(cap * f / 10.0)) * 10
		var b := Shops.button("Bahissiz (0₺)" if f == 0.0 else (("MAX %d₺" % amt) if f == 1.0 else "%d₺" % amt), CYAN, 13)
		b.pressed.connect(func(): bet_in.text = str(amt); bet_msg.text = ""); q.add_child(b)
	bet_msg.text = ""; _paint_len(); set_auto(auto)
	bet.visible = true; Overlay.open("tavla_bet")

func close_bet() -> void:
	bet.visible = false; Overlay.close("tavla_bet")

func _bet_go() -> void:
	if bet_npc.is_empty(): return
	var t := bet_in.text.strip_edges()
	if not t.is_valid_int() or int(t) < 0: bet_msg.text = "Geçerli bir sayı gir. (Enter a valid number.)"; return
	var v := int(t)
	if v > int(bet_npc["cap"]): bet_msg.text = "Bu masanın limiti %d₺! (Over this table's cap.)" % int(bet_npc["cap"]); return
	if v > Shops.lira(): bet_msg.text = "O kadar paran yok! (You don't have that much.)"; return
	var N := bet_npc
	close_bet(); begin(N, bet_len, v)

func set_auto(on: bool) -> void:
	auto = on
	var t := "🎲 OTOROLL: " + ("AÇIK (on)" if on else "KAPALI (off)")
	b_auto.text = t
	if _auto_b2: _auto_b2.text = t
	if on and not G.is_empty() and G["turn"] == 1 and (G["rolled"] as Array).is_empty() and can_play(): roll()

# ================================================================ match + game flow
func begin(N: Dictionary, target: int, stake: int) -> void:
	M = {"npc": N, "target": target, "my": 0, "opp": 0, "stake": stake}
	clock_max = float(N.get("time", 60)); clock = clock_max; nagged = false; taunt = {}; fly = {}; spin = {}; drag = {}
	who_l.text = "⚂ [b]%s[/b] · [color=#8ff2ff]%s[/color] · [color=#ffd66b]ZORLUK %d/10[/color] [color=#ff5fa2]%s[/color]" % [N["name"], N["title"], int(N["diff"]), Tavla.diff_stars(int(N["diff"]))]
	root.visible = true; Overlay.open("tavla")
	_score()
	new_game(true)
	if N.get("cheat", 0):
		_msg("⚠️ [b]Uyarı:[/b] Kaan %d kere zarı tekrar atabilir. [i](He gets %d re-rolls a game. He calls it fiancé privileges.)[/i]" % [int(N["cheat"]), int(N["cheat"])])

func _score() -> void:
	if M.is_empty(): return
	score_l.text = "MAÇ: [b]%d[/b] – [b]%d[/b] (ilk %d) · Bahis: [b]%d₺[/b]%s" % [int(M["my"]), int(M["opp"]), int(M["target"]), int(M["stake"]),
		(" · [color=#ff5fa2]🎲 hile: %d[/color]" % int(G.get("cheat", 0))) if M["npc"].get("cheat", 0) and not G.is_empty() else ""]

func _msg(t: String) -> void: msg_l.text = t

func _after(sec: float, cb: Callable) -> void:
	var gid := _gid
	get_tree().create_timer(sec).timeout.connect(func(): if gid == _gid and root.visible: cb.call())

func new_game(first: bool) -> void:
	_gid += 1; taunt = {}; taunt_box.visible = false
	var a := Tavla.d6(); var b := Tavla.d6()
	while a == b: a = Tavla.d6(); b = Tavla.d6()
	var who := 1 if a > b else -1
	G = {"s": Tavla.new_state(), "turn": who, "dice": [], "rolled": [], "used": [], "sel": null, "dests": [], "off_ok": false,
		"legal": [], "busy": true, "rerolls": 0, "hist": [], "cheat": int(M["npc"].get("cheat", 0))}
	clock = clock_max; nagged = false
	_buttons()
	if first: say_taunt("start")
	_pre_quiz(func():
		_msg("Açılış zarı: sen [b]%d[/b], o [b]%d[/b] → %s · Maç %d–%d" % [a, b, "[b]sen başlıyorsun[/b] [i](you start)[/i]" if who > 0 else "[b]o başlıyor[/b] [i](they start)[/i]", int(M["my"]), int(M["opp"])])
		G["busy"] = false; _buttons()
		if who < 0: G["busy"] = true; _after(.9, ai_turn)
		elif auto: _after(.7, func(): if can_play() and (G["rolled"] as Array).is_empty(): roll())
		_score())

# tvPreGameQuiz(): 5 questions, mistakes first; 5/5 = 3 re-rolls, 4/5 = 2, 3/5 = 1, +12 XP each right
func _pre_quiz(cb: Callable) -> void:
	if Lessons.me == null: cb.call(); return
	var qs: Array = Lessons.me.tavla_quiz_set()
	if qs.is_empty(): cb.call(); return
	var reviewing := not Lessons.me.missed_qs(1).is_empty()
	_msg("📖 [b]Oyun öncesi Türkçe![/b] 5 questions%s. Each correct answer earns a [b]zar hakkı[/b] (re-roll)." % (" — including ones you missed before" if reviewing else ""))
	var gid := _gid
	Lessons.me.quiz.run(qs, func(score):
		if gid != _gid or not root.visible: return
		var right: int = (score as Array).count(true)
		var rr := 3 if right >= 5 else (2 if right >= 4 else (1 if right >= 3 else 0))
		G["rerolls"] = rr
		if right > 0: Shops.xp(right * 12)
		cb.call()
		_msg("📖 [b]%d/5 doğru.[/b] %s" % [right, ("Kazandığın zar hakkı: [b]%d[/b] [i](%d re-roll%s this game)[/i]" % [rr, rr, "s" if rr > 1 else ""]) if rr else "Bu oyunda zar hakkın yok. [i](No re-rolls this game.)[/i]"])
		_buttons(),
		"📖 TAVLA ÖNCESİ · " + str(M["npc"]["short"]), true)

func can_play() -> bool:
	return not G.is_empty() and G["turn"] == 1 and not G["busy"] and fly.is_empty() and taunt.is_empty() and spin.is_empty() and not QuizUI.open

func _buttons() -> void:
	if G.is_empty(): return
	var mine: bool = G["turn"] == 1 and not G["busy"]
	var rolled: bool = not (G["rolled"] as Array).is_empty()
	b_roll.disabled = not mine or rolled
	b_done.disabled = not (mine and rolled and ((G["legal"] as Array).is_empty() or (G["dice"] as Array).is_empty()))
	b_rer.visible = int(G["rerolls"]) > 0 and G["turn"] == 1
	b_rer.text = "🔄 ZAR HAKKI (%d)" % int(G["rerolls"])
	var can_undo := mine and not (G["hist"] as Array).is_empty() and fly.is_empty()
	b_undo.visible = can_undo
	b_undo.text = "↩ GERİ AL (%d)" % (G["hist"] as Array).size()

func roll() -> void:
	if G.is_empty() or not (G["rolled"] as Array).is_empty() or not can_play(): return
	var a := Tavla.d6(); var b := Tavla.d6()
	G["rolled"] = [a, a, a, a] if a == b else [a, b]
	G["used"] = (G["rolled"] as Array).map(func(_x): return 0)
	G["dice"] = (G["rolled"] as Array).duplicate()
	_msg("🎲 zar dönüyor... [i](rolling...)[/i]"); _buttons()
	_spin(func():
		_msg("🎲 [b]%s[/b]%s" % [Tavla.zar_name(a, b), (" · [i]zar hakkın: %d[/i]" % int(G["rerolls"])) if int(G["rerolls"]) else ""])
		if a == b: _after(.5, func(): say_taunt("herDouble"))
		refresh_legal())

func _spin(cb: Callable) -> void:
	spin = {"t": .75, "rx": randf() * 6, "done": cb}
	Shops.sfx("drop"); _after(.14, func(): Shops.sfx("drop")); _after(.34, func(): Shops.sfx("ding"))

func refresh_legal() -> void:
	G["legal"] = Tavla.legal(G["s"], 1, G["dice"])
	G["dests"] = []; G["sel"] = null; G["off_ok"] = false
	if (G["dice"] as Array).is_empty(): _msg("Sıra bitti — [b]SIRAYI BİTİR[/b] to hand over.")
	elif (G["legal"] as Array).is_empty() and not (G["rolled"] as Array).is_empty():
		_msg("[b]Oynayacak hamlen yok![/b] [i](You have no legal move!)[/i] Turn passes.")
		var g := G
		_after(1.6, func(): if is_same(G, g) and G["turn"] == 1: end_turn())
	_buttons()
	if auto and not (G["rolled"] as Array).is_empty() and (G["dice"] as Array).is_empty() and fly.is_empty():
		var g2 := G
		_after(.6, func(): if is_same(G, g2) and G["turn"] == 1 and not G["busy"] and (G["dice"] as Array).is_empty() and taunt.is_empty(): end_turn())

func deselect() -> void:
	G["sel"] = null; G["dests"] = []; G["off_ok"] = false
	_msg("Taş bırakıldı. [i](Put back — pick another one.)[/i]")

func pick_source(i: int) -> void:
	if G["sel"] != null and int(G["sel"]) == i: deselect(); return
	if int(G["s"]["bar"][0]) > 0 and i != -1:
		_msg("[b]Kırık taşın var![/b] [i](You have a checker on the bar!)[/i] Click the bar first."); return
	var ms: Array = (G["legal"] as Array).filter(func(m): return int(m["from"]) == i)
	if ms.is_empty(): deselect(); return
	G["sel"] = i
	G["dests"] = ms.filter(func(m): return int(m["to"]) >= 0).map(func(m): return int(m["to"]))
	G["off_ok"] = ms.any(func(m): return int(m["to"]) == -99)
	if G["off_ok"]: _msg("Click the [b]OFF tray[/b] (right) to bear this one off — [i]toplama[/i].")
	else: _msg("Bir hedef seç, ya da taşa tekrar bas ve bırak. [i](Pick a target, or click it again to put it back.)[/i]")

func _snapshot() -> void:
	var h: Array = G["hist"]
	h.append({"s": Tavla.clone(G["s"]), "dice": (G["dice"] as Array).duplicate(), "used": (G["used"] as Array).duplicate()})
	if h.size() > 8: h.pop_front()

func undo() -> void:
	if G.is_empty() or G["turn"] != 1 or G["busy"] or not fly.is_empty() or (G["hist"] as Array).is_empty(): return
	var h: Dictionary = (G["hist"] as Array).pop_back()
	G["s"] = h["s"]; G["dice"] = h["dice"]; G["used"] = h["used"]
	G["sel"] = null; G["dests"] = []; G["off_ok"] = false
	Shops.sfx("drop")
	var n := (G["hist"] as Array).size()
	_msg("↩ [b]Hamle geri alındı.[/b] [i](Move undone — take your time.)[/i]" + (" %d more to rewind." % n if n else ""))
	G["legal"] = Tavla.legal(G["s"], 1, G["dice"])
	_buttons()

func do_move(to: int) -> void:
	var m := {}
	for x in G["legal"]:
		if G["sel"] != null and int(x["from"]) == int(G["sel"]) and int(x["to"]) == to: m = x; break
	if m.is_empty(): return
	_snapshot()
	var src := _src_pos(G["s"], 1, int(m["from"]))
	var before := int(G["s"]["bar"][1])
	var ns := Tavla.apply(G["s"], 1, m)
	var dst := _dst_pos(ns, 1, to)
	G["busy"] = true; G["sel"] = null; G["dests"] = []
	Shops.sfx("drop")
	# the flying checker leaves its stack straight away
	var tmp := Tavla.clone(G["s"])
	if int(m["from"]) == -1: tmp["bar"][0] = int(tmp["bar"][0]) - 1
	else: tmp["p"][int(m["from"])] = int(tmp["p"][int(m["from"])]) - 1
	G["s"] = tmp
	var g := G
	_fly(src, dst, 1, func():
		if not is_same(G, g): return
		G["s"] = ns
		var di := (G["dice"] as Array).find(int(m["d"]))
		if di >= 0: (G["dice"] as Array).remove_at(di)
		_use(int(m["d"]))
		if int(ns["bar"][1]) > before: Shops.sfx("ding"); say_taunt("sheHit")
		G["busy"] = false
		if Tavla.winner(G["s"]) != 0: game_over(1); return
		refresh_legal()
		if not (G["dice"] as Array).is_empty():
			_msg("Taş oynandı. [b]↩ GERİ AL[/b] · sağ tık · [b]Z[/b] — istersen geri koy. [i](Moved. Undo with the button, right-click or Z — the clock is still yours.)[/i]"))

func _use(d: int) -> void:
	var r: Array = G["rolled"]; var u: Array = G["used"]
	for i in r.size():
		if int(u[i]) == 0 and int(r[i]) == d: u[i] = 1; break

func _fly(a: Vector2, b: Vector2, pl: int, cb: Callable) -> void:
	fly = {"a": a, "b": b, "pl": pl, "t": 0.0, "dur": .34, "cb": cb}

func end_turn() -> void:
	if G.is_empty(): return
	G["turn"] = -1; G["rolled"] = []; G["dice"] = []; G["used"] = []; G["sel"] = null; G["dests"] = []; G["busy"] = true
	G["hist"] = []; nagged = false
	_buttons()
	_after(.5, ai_turn)

# tvAITurn(): roll (Kaan re-rolls weak throws), pick the best line, play it move by move
func ai_turn() -> void:
	if G.is_empty(): return
	var N: Dictionary = M["npc"]
	var a := Tavla.d6(); var b := Tavla.d6()
	if int(G["cheat"]) > 0 and a != b and a + b < 7:
		G["cheat"] = int(G["cheat"]) - 1
		var c: Array = (T.D["KAANCHEAT"] as Array).pick_random()
		taunt = {"tr": c[0], "en": c[1], "size": "lg", "ttl": 5.0, "tilt": randf_range(-.04, .04), "flavor": "*picks the dice straight back up*"}
		_show_taunt()
		_voice(c)
		Shops.sfx("no"); Shops.sfx("coinflip")
		_msg("😤 [b]KAAN ZARI TEKRAR ATTI![/b] (%d cheat left) — [i]he re-rolled a bad throw. There is no rule for this.[/i]" % int(G["cheat"]))
		_score()
		a = Tavla.d6(); b = Tavla.d6()
	var dice := [a, a, a, a] if a == b else [a, b]
	G["rolled"] = dice.duplicate(); G["used"] = dice.map(func(_x): return 0); G["turn"] = -1
	_msg("[b]%s[/b] zar atıyor..." % N["short"])
	var g := G
	_spin(func():
		if not is_same(G, g): return
		_msg("[b]%s[/b] attı: 🎲 [b]%s[/b]" % [N["short"], Tavla.zar_name(a, b)])
		if a == b: _after(.4, func(): say_taunt("theirDouble"))
		var seq: Array = Tavla.best_seq(G["s"], -1, dice, float(N["diff"]), bool(N.get("deep", false)))
		_ai_step(seq, 0, g))

func _ai_step(seq: Array, k: int, g: Dictionary) -> void:
	if not is_same(G, g) or not root.visible: return
	if not taunt.is_empty(): _after(.2, func(): _ai_step(seq, k, g)); return      # let her read the trash talk first
	if k >= seq.size():
		if Tavla.winner(G["s"]) != 0: game_over(-1); return
		G["turn"] = 1; G["rolled"] = []; G["dice"] = []; G["used"] = []; G["busy"] = false; G["legal"] = []
		clock = clock_max; nagged = false
		_buttons()
		_msg("Sıra sende — [b]ZAR AT[/b]. [i](Your turn — roll.)[/i]")
		if auto: _after(.45, func(): if can_play() and (G["rolled"] as Array).is_empty(): roll())
		return
	var m: Dictionary = seq[k]
	var src := _src_pos(G["s"], -1, int(m["from"]))
	var before := int(G["s"]["bar"][0])
	var ns := Tavla.apply(G["s"], -1, m)
	var dst := _dst_pos(ns, -1, int(m["to"]))
	var tmp := Tavla.clone(G["s"])
	if int(m["from"]) == -1: tmp["bar"][1] = int(tmp["bar"][1]) - 1
	else: tmp["p"][int(m["from"])] = int(tmp["p"][int(m["from"])]) + 1
	G["s"] = tmp
	Shops.sfx("drop")
	_fly(src, dst, -1, func():
		if not is_same(G, g): return
		G["s"] = ns; _use(int(m["d"]))
		if int(ns["bar"][0]) > before: Shops.sfx("no"); say_taunt("theyHit")
		_after(.18, func(): _ai_step(seq, k + 1, g)))

func reroll() -> void:
	if G.is_empty() or int(G["rerolls"]) <= 0 or (G["rolled"] as Array).is_empty() or G["busy"] or not fly.is_empty(): return
	if (G["used"] as Array).any(func(f): return int(f) != 0):
		_msg("Zaten hamle yaptın — bu turda zar hakkı kullanılamaz."); return
	G["rerolls"] = int(G["rerolls"]) - 1; G["rolled"] = []; G["dice"] = []; G["used"] = []; G["hist"] = []
	_msg("🔄 [b]Zar hakkı kullanıldı![/b] [i](Re-roll used — earned from your Turkish.)[/i] Roll again.")
	_buttons(); roll()

# tvTimeout(): her clock ran out, a random legal move is played for her
func _timeout() -> void:
	if G.is_empty() or G["busy"]: return
	_msg("⏰ [b]Süre doldu![/b] [i](Time is up!)[/i] A move was played for you.")
	Shops.sfx("no")
	var lm: Array = G["legal"]
	if lm.size():
		var m: Dictionary = lm.pick_random()
		G["sel"] = int(m["from"]); do_move(int(m["to"]))
	else: end_turn()

func game_over(w: int) -> void:
	var lo: int = int(G["s"]["off"][1]) if w > 0 else int(G["s"]["off"][0])
	var pts := 2 if lo == 0 else 1                      # mars (gammon) counts double in tavla
	if w > 0: M["my"] = int(M["my"]) + pts
	else: M["opp"] = int(M["opp"]) + pts
	G["busy"] = true; _buttons(); b_roll.disabled = true; b_done.disabled = true
	var mars := " [b]MARS![/b] [i](gammon — double points!)[/i]" if pts == 2 else ""
	_msg(("🎉 [b]Oyunu kazandın![/b] [i](You won the game!)[/i]%s +%d" % [mars, pts]) if w > 0 else ("😤 [b]%s oyunu aldı.[/b] [i](They took the game.)[/i]%s +%d" % [M["npc"]["short"], mars, pts]))
	Shops.sfx("fanfare" if w > 0 else "no")
	_after(.9, func(): say_taunt("theyLose" if w > 0 else "theyWin"))
	_score()
	_after(3.2, func():
		if int(M["my"]) >= int(M["target"]) or int(M["opp"]) >= int(M["target"]): _match_over()
		else: new_game(false))

func _match_over() -> void:
	var m := M
	_close(); T.match_over(m)

func _close() -> void:
	_gid += 1
	root.visible = false; Overlay.close("tavla"); G = {}; drag = {}; fly = {}; spin = {}; taunt = {}; taunt_box.visible = false

# the ÇIK button / Esc
func quit() -> void:
	if QuizUI.open and Lessons.me: Lessons.me.quiz.skip_all()
	_close()
	if T.hud: T.hud.toast("You left the table. [i]Kaçtın mı?[/i] (Did you run away?) 😏", 5.0)

# ================================================================ trash talk (tvTaunt)
func say_taunt(kind: String) -> void:
	if M.is_empty(): return
	var size := "sm"
	if kind == "theyHit": size = "mega" if randf() < .35 else "lg"
	elif kind == "theirDouble": size = "mega" if randf() < .18 else ("lg" if randf() < .5 else "sm")
	elif kind == "theyWin": size = "lg"
	if size == "sm" and randf() < .07: size = "mega"
	var is_kaan: bool = M["npc"]["id"] == "kaan"
	var TA: Dictionary = T.D["TAUNT"]
	var t: Array
	if is_kaan: t = (T.D["KAANTALK"] as Array).pick_random() if randf() < .75 else (T.D["TRASH"] as Array).pick_random()
	else: t = (T.D["TRASH"] as Array).pick_random() if randf() < .45 or not TA.has(kind) else (TA[kind] as Array).pick_random()
	if not is_kaan and size == "mega" and randf() < .55: t = (TA["menace"] as Array).pick_random()
	if is_kaan and size == "mega": t = (T.D["KAANTALK"] as Array).pick_random()
	var fl = null
	if size != "sm" and randf() < (.9 if size == "mega" else .45): fl = (T.D["TVFLAVOR"] as Array).pick_random()
	taunt = {"tr": t[0], "en": t[1], "size": size, "ttl": 5.0, "tilt": 0.0 if size == "sm" else randf_range(-.045, .045), "flavor": fl}
	if size != "sm":
		Shops.sfx("thud")
		if Fx.me: Fx.me.shake(.3)
	if size == "mega": Shops.sfx("rev")
	_show_taunt(); _voice(t)

func _voice(t: Array) -> void:
	if Audio.me: Audio.me.mob_talk(str(M["npc"]["mob"]), T.opp_pos(str(M["npc"]["id"])), true, [t[0], t[1]])

func _show_taunt() -> void:
	var sz := {"sm": 19, "lg": 27, "mega": 40}.get(taunt["size"], 19) as int
	var col := PINK if taunt["size"] == "mega" else (GOLD if taunt["size"] == "lg" else CYAN)
	taunt_box.add_theme_stylebox_override("panel", _sb(col))
	var face := {"imp": "👹", "zombie": "🧟", "thot": "💅", "witch": "🧙", "mummy": "🧻", "karen": "😈", "kaan": "❤"}.get(str(M["npc"]["mob"]), "⚂") as String
	var tx := "[center][font_size=%d]%s [b]%s[/b][/font_size]\n[font_size=%d][color=#bfb0e0][i](%s)[/i][/color][/font_size]" % [sz, face, taunt["tr"], maxi(13, sz / 2), taunt["en"]]
	if taunt["flavor"] != null: tx += "\n[font_size=13][color=#8a7aae]%s[/color][/font_size]" % taunt["flavor"]
	tx += "[/center]"
	taunt_l.custom_minimum_size = Vector2(520 if taunt["size"] != "mega" else 760, 0)
	taunt_l.text = tx
	taunt_box.visible = true; taunt_box.size = Vector2.ZERO
	taunt_box.rotation = float(taunt["tilt"])
	await get_tree().process_frame
	if is_instance_valid(taunt_box): taunt_box.position = Vector2(480, 330) - taunt_box.size / 2.0

func close_taunt() -> bool:
	if taunt.is_empty(): return false
	taunt = {}; taunt_box.visible = false; Shops.sfx("drop"); return true

# ================================================================ geometry (tvPtX / tvCkPos / tvHit)
static func pt_x(i: int) -> float:
	if i < 6: return TVR - (i + .5) * TVPW
	if i < 12: return TVBARX - (i - 6 + .5) * TVPW
	if i < 18: return TVL + (i - 12 + .5) * TVPW
	return TVBARX + TVBARW + (i - 18 + .5) * TVPW

static func is_top(i: int) -> bool: return i >= 12

static func ck_pos(i: int, k: int, n: int) -> Vector2:
	var sp := 30.0 if n <= 5 else 150.0 / float(n - 1)
	return Vector2(pt_x(i), 52 + k * sp) if is_top(i) else Vector2(pt_x(i), 418 - k * sp)

static func bar_pos(pl: int, k: int) -> Vector2:
	return Vector2(TVBARX + TVBARW / 2.0, 290 + k * 28) if pl > 0 else Vector2(TVBARX + TVBARW / 2.0, 180 - k * 28)

static func off_pos(pl: int, k: int) -> Vector2:
	return Vector2(722, 446 - k * 12) if pl > 0 else Vector2(722, 24 + k * 12)

func _src_pos(s: Dictionary, pl: int, from: int) -> Vector2:
	if from == -1: return bar_pos(pl, maxi(0, int(s["bar"][Tavla.bi(pl)]) - 1))
	var n := absi(int(s["p"][from]))
	return ck_pos(from, maxi(0, n - 1), n)

func _dst_pos(ns: Dictionary, pl: int, to: int) -> Vector2:
	if to == -99: return off_pos(pl, maxi(0, int(ns["off"][Tavla.bi(pl)]) - 1))
	var n := absi(int(ns["p"][to]))
	return ck_pos(to, maxi(0, n - 1), n)

static func hit_test(x: float, y: float) -> Dictionary:
	if x > TVBARX and x < TVBARX + TVBARW: return {"kind": "bar"}
	if x > TVR + 14: return {"kind": "off"}
	var top := y < TVH / 2.0
	var best := -1; var bd := 1e9
	for i in 24:
		if is_top(i) != top: continue
		var d := absf(pt_x(i) - x)
		if d < bd: bd = d; best = i
	if best < 0 or bd > TVPW / 2.0: return {}
	return {"kind": "pt", "i": best}

# ================================================================ input
func _board_input(e: InputEvent) -> void:
	if G.is_empty(): return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		if close_taunt(): return
		if G["turn"] == 1 and not G["busy"] and not (G["hist"] as Array).is_empty() and fly.is_empty(): undo()
		elif G["sel"] != null: deselect()
		return
	if e is InputEventMouseMotion and not drag.is_empty():
		drag["at"] = e.position; return
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT): return
	if e.pressed:
		if close_taunt(): _dismissed = Time.get_ticks_msec(); return
		if Time.get_ticks_msec() - _dismissed < 150 or not can_play(): return
		var h := hit_test(e.position.x, e.position.y)
		if h.is_empty(): return
		if G["sel"] != null:
			if h["kind"] == "off" and G["off_ok"]: do_move(-99); return
			if h["kind"] == "pt" and (G["dests"] as Array).has(int(h["i"])): do_move(int(h["i"])); return
		if h["kind"] == "off": deselect(); return
		var from: int = -1 if h["kind"] == "bar" else int(h["i"])
		if h["kind"] == "bar" and int(G["s"]["bar"][0]) <= 0: return
		pick_source(from)
		if G["sel"] != null and int(G["sel"]) == from: drag = {"from": from, "at": e.position}
	else:
		if drag.is_empty(): return
		var D := drag; drag = {}
		if not can_play() or G["sel"] == null or int(G["sel"]) != int(D["from"]): return
		var h := hit_test(e.position.x, e.position.y)
		if h.is_empty() or (h["kind"] == "pt" and int(h["i"]) == int(D["from"])): return     # dropped where it started = just a select
		if h["kind"] == "off":
			if G["off_ok"]: do_move(-99)
			return
		if h["kind"] == "pt" and (G["dests"] as Array).has(int(h["i"])): do_move(int(h["i"]))

func _unhandled_input(e: InputEvent) -> void:
	if not root.visible or QuizUI.open: return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Z, KEY_BACKSPACE: undo()
			KEY_ESCAPE: quit()
			_: return
		get_viewport().set_input_as_handled()

func _input(e: InputEvent) -> void:
	# the bet screen's Esc
	if bet.visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close_bet(); get_viewport().set_input_as_handled()

# ================================================================ the loop (tvLoop)
func _process(dt: float) -> void:
	if not root.visible: return
	dt = minf(dt, .05)
	if not spin.is_empty():
		spin["t"] = float(spin["t"]) - dt; spin["rx"] = float(spin["rx"]) + dt * 15.0
		if float(spin["t"]) <= 0:
			var f: Callable = spin["done"]; spin = {}
			if f.is_valid(): f.call()
	if not fly.is_empty():
		fly["t"] = float(fly["t"]) + dt
		if float(fly["t"]) >= float(fly["dur"]):
			var cb: Callable = fly["cb"]; fly = {}
			if cb.is_valid(): cb.call()
	if not taunt.is_empty():
		taunt["ttl"] = float(taunt["ttl"]) - dt
		if float(taunt["ttl"]) <= 0: close_taunt()
	# her clock waits while a taunt is up — she shouldn't be punished for reading it
	if not G.is_empty() and G["turn"] == 1 and not (G["rolled"] as Array).is_empty() and not G["busy"] and fly.is_empty() and taunt.is_empty() and spin.is_empty() and not QuizUI.open:
		clock -= dt
		if clock <= 18.0 and not nagged: nagged = true; say_taunt("slow")
		if clock <= 0: clock = 0; _timeout()
	board.queue_redraw()

# ================================================================ drawing (tvDraw)
func _draw_board() -> void:
	var c := board
	c.draw_rect(Rect2(0, 0, TVW, TVH), Color("6b3f22"))
	c.draw_rect(Rect2(4, 4, TVW - 8, TVH - 8), Color("ffd78c", .35), false, 2.0)
	c.draw_rect(Rect2(TVL, 14, TVBARX - TVL, TVH - 28), Color("2f6b45"))
	c.draw_rect(Rect2(TVBARX + TVBARW, 14, TVR - TVBARX - TVBARW, TVH - 28), Color("2f6b45"))
	c.draw_rect(Rect2(TVBARX, 14, TVBARW, TVH - 28), Color("4a2a16"))
	c.draw_rect(Rect2(TVR + 14, 14, TVW - TVR - 24, TVH - 28), Color("3a2414"))
	if G.is_empty(): return
	var s: Dictionary = G["s"]
	var dests: Array = G["dests"]
	for i in 24:
		var x := pt_x(i); var top := is_top(i)
		var col := Color("e8d7b0") if i % 2 == 0 else Color("9a3040")
		var by := 14.0 if top else TVH - 14.0
		var ty := by + 190.0 if top else by - 190.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - TVPW / 2 + 2, by), Vector2(x + TVPW / 2 - 2, by), Vector2(x, ty)]), col)
		if dests.has(i): c.draw_colored_polygon(PackedVector2Array([Vector2(x - TVPW / 2 + 2, by), Vector2(x + TVPW / 2 - 2, by), Vector2(x, ty)]), Color(CYAN, .45))
		c.draw_string(ThemeDB.fallback_font, Vector2(x - 6, (11.0 if top else TVH - 2.0)), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, .35))
	if G["off_ok"]: c.draw_rect(Rect2(TVR + 14, TVH / 2, TVW - TVR - 24, TVH / 2 - 14), Color(CYAN, .35))
	# movable checkers glow gold before she's picked one
	var movable := {}
	if can_play() and G["sel"] == null:
		for m in G["legal"]: movable[int(m["from"])] = true
	var p: Array = s["p"]
	for i in 24:
		var n: int = p[i]
		if n == 0: continue
		var pl := 1 if n > 0 else -1; var cnt := absi(n)
		for k in cnt:
			var hl := (G["sel"] != null and int(G["sel"]) == i and k == cnt - 1) or (movable.has(i) and k == cnt - 1)
			if not drag.is_empty() and int(drag["from"]) == i and k == cnt - 1: continue
			_checker(ck_pos(i, k, cnt), pl, hl, G["sel"] != null and int(G["sel"]) == i)
	for k in int(s["bar"][0]): _checker(bar_pos(1, k), 1, movable.has(-1) or (G["sel"] != null and int(G["sel"]) == -1), false)
	for k in int(s["bar"][1]): _checker(bar_pos(-1, k), -1, false, false)
	for k in int(s["off"][0]): c.draw_rect(Rect2(off_pos(1, k) - Vector2(22, 5), Vector2(44, 10)), Color("ff7fb0"))
	for k in int(s["off"][1]): c.draw_rect(Rect2(off_pos(-1, k) - Vector2(22, 5), Vector2(44, 10)), Color("2a3048"))
	if not drag.is_empty(): _checker(drag["at"], 1, true, true)
	if not fly.is_empty():
		var u := clampf(float(fly["t"]) / float(fly["dur"]), 0, 1)
		var e := u * u * (3 - 2 * u)
		var at: Vector2 = (fly["a"] as Vector2).lerp(fly["b"], e) + Vector2(0, -sin(u * PI) * 30)
		_checker(at, int(fly["pl"]), true, false)
	_dice()
	# her clock
	if G["turn"] == 1 and not (G["rolled"] as Array).is_empty():
		var f := clampf(clock / clock_max, 0, 1)
		c.draw_rect(Rect2(TVL, 3, (TVR - TVL) * f, 6), Color("ff4d6d") if clock < 18 else GOLD)
		c.draw_string(ThemeDB.fallback_font, Vector2(TVR - 34, 12), "%ds" % ceili(clock), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _checker(at: Vector2, pl: int, hl: bool, sel: bool) -> void:
	var fill := Color("e8457e") if pl > 0 else Color("1d2436")
	var rim := Color("8e1c3c") if pl > 0 else Color("0d1018")
	board.draw_circle(at, 15, fill)
	board.draw_circle(at + Vector2(-4, -5), 5, Color(1, 1, 1, .22 if pl > 0 else .12))
	board.draw_arc(at, 15, 0, TAU, 20, CYAN if sel else (GOLD if hl else rim), 3.0 if (hl or sel) else 2.0)

func _dice() -> void:
	var r: Array = G["rolled"]
	if r.is_empty() and spin.is_empty(): return
	var cx := 525.0 if G["turn"] == 1 else 180.0
	var faces: Array = []
	if not spin.is_empty(): faces = [randi_range(1, 6), randi_range(1, 6)]
	else: faces = [r[0], r[1]] if r.size() == 2 else [r[0], r[0], r[0], r[0]]
	var u: Array = G["used"]
	for j in faces.size():
		var at := Vector2(cx + (j - (faces.size() - 1) / 2.0) * 50, TVH / 2.0)
		var used := spin.is_empty() and j < u.size() and int(u[j]) != 0
		var rot := float(spin["rx"]) * (1.0 + j * .3) if not spin.is_empty() else 0.0
		board.draw_set_transform(at, rot, Vector2.ONE)
		var dc := Color("ffd7ea") if G["turn"] == 1 else Color("f6f2ea")
		if used: dc = Color(dc, .35)
		board.draw_rect(Rect2(-18, -18, 36, 36), dc)
		board.draw_rect(Rect2(-18, -18, 36, 36), PINK if G["turn"] == 1 else Color("1a1a1a"), false, 2.0)
		for pp in _pips(int(faces[j])): board.draw_circle(pp * 11.0, 3.6, Color(.1, .1, .1, .35 if used else 1.0))
		board.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

static func _pips(n: int) -> Array:
	match n:
		1: return [Vector2.ZERO]
		2: return [Vector2(-1, -1), Vector2(1, 1)]
		3: return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
		4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5: return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
	return [Vector2(-1, -1.1), Vector2(1, -1.1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1.1), Vector2(1, 1.1)]
