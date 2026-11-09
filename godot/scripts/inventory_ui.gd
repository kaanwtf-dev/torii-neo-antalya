# The inventory (I) — 7.2's INVTABS / openInv / renderInv / UIKEYS.inv, drawn at full window resolution
# in 7.2's neon colours. Tabs: 🎽 KUŞANIM gear (5 slots, wear / take off / sell, ▲▼ against what she
# wears, sell all common, click a slot to filter), 🎒 ÇANTA food (eat), 🃏 KARTLAR perk cards (open one),
# 🧿 KOLEKSİYON nazars by region + rewards + sayings, 📜 GÖREVLER quests (J opens it straight there),
# 📊 DURUM the stats sheet. Keys: I / Esc close, ← → (or Tab) switch tabs, H quick-eat.
# Pauses the fight through Overlay "inv".
class_name InventoryUI
extends CanvasLayer

static var me: InventoryUI
# the side-quest system can hand in its own panel: func() -> String (BBCode). Otherwise we show the story.
static var quest_panel: Callable
var player
var D := {}
var tab := "gear"
var filt := ""
var panel: PanelContainer
var money: Label
var tabs_row: HBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var _open_frame := -1

const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURPLE := Color("b06bff")
const TXT := Color("e8e4f8")

func setup(p) -> void:
	me = self; player = p; layer = 5
	D = Stats.data()
	panel = PanelContainer.new(); panel.position = Vector2(30, 24); panel.size = Vector2(900, 672); panel.visible = false
	panel.add_theme_stylebox_override("panel", _sb(Color(.05, .025, .1, .97), PINK, 3, 14, 16))
	add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); panel.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	var title := _rich(top, "[color=#ff5fa2][b]🎒 ENVANTER[/b][/color] [color=#9a94a8]inventory[/color]", 22, 400)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money = Label.new(); money.add_theme_font_size_override("font_size", 18); money.add_theme_color_override("font_color", GOLD); top.add_child(money)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(16, 0); top.add_child(sp)
	top.add_child(_btn("✕ [I]", close, PINK))
	tabs_row = HBoxContainer.new(); tabs_row.add_theme_constant_override("separation", 6); v.add_child(tabs_row)
	scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(860, 540); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", 8); body.custom_minimum_size = Vector2(844, 0); scroll.add_child(body)
	var hint := Label.new(); hint.text = "I / ESC close  ·  ← → switch tabs  ·  H quick-eat"; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13); hint.add_theme_color_override("font_color", CYAN); v.add_child(hint)

# ---------------------------------------------------------------- small UI kit
func _sb(bg: Color, border: Color, bw := 2, rad := 10, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border; s.set_border_width_all(bw)
	s.set_corner_radius_all(rad); s.set_content_margin_all(pad); return s

func _rich(parent: Node, text: String, size := 15, w := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false; r.text = UiScale.bb(text)
	r.add_theme_color_override("default_color", TXT); r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: r.add_theme_font_size_override(k, size)
	if w > 0: r.custom_minimum_size = Vector2(w, 0)
	parent.add_child(r); return r

func _btn(text: String, cb: Callable, col := CYAN, size := 13) -> Button:
	var b := Button.new(); b.text = text; b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size); b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _sb(Color(.1, .06, .18, 1), col, 2, 8, 6))
	b.add_theme_stylebox_override("hover", _sb(Color(.18, .1, .3, 1), col, 2, 8, 6))
	b.add_theme_stylebox_override("pressed", _sb(Color(.25, .12, .4, 1), col, 2, 8, 6))
	b.pressed.connect(cb); return b

func _card(parent: Node, border: Color, w := 0.0) -> VBoxContainer:
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", _sb(Color(.09, .05, .16, 1), border, 2, 10, 10))
	if w > 0: p.custom_minimum_size = Vector2(w, 0)
	parent.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); p.add_child(v)
	return v

func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new(); g.columns = cols; g.add_theme_constant_override("h_separation", 10); g.add_theme_constant_override("v_separation", 10)
	body.add_child(g); return g

# ---------------------------------------------------------------- open / close
func open(t := "") -> void:
	if not Items.me: return
	if t != "": tab = t
	if not panel.visible:
		if Overlay.any() or (is_instance_valid(player) and player.dead): return
		panel.visible = true; Overlay.open("inv"); _open_frame = Engine.get_process_frames()
		Bus.emit_ev("sfx", {"name": "ding"})
	render()

func close() -> void:
	if not panel.visible: return
	panel.visible = false; Overlay.close("inv")

func is_open() -> bool: return panel.visible

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.keycode
	if not panel.visible:
		if k == KEY_I: open(); get_viewport().set_input_as_handled()
		elif k == KEY_J: open("quests"); get_viewport().set_input_as_handled()
		return
	if Engine.get_process_frames() == _open_frame: return
	var ids: Array = (D["INVTABS"] as Array).map(func(x): return x[0])
	match k:
		KEY_I, KEY_ESCAPE: close()
		KEY_J: tab = "quests"; render()
		KEY_LEFT, KEY_RIGHT, KEY_TAB:
			var i := ids.find(tab)
			tab = ids[(i + (-1 if k == KEY_LEFT else 1) + ids.size()) % ids.size()]; render()
		KEY_H: Items.me.quick_eat(); render()
		_: return
	get_viewport().set_input_as_handled()

# button actions (7.2's data-a handlers)
func _set_tab(id: String) -> void: tab = id; render()
func _slot_click(ev: InputEvent, sid: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		filt = "" if filt == sid else sid; render()
func _do(a: String, arg: String) -> void:
	var I := Items.me
	match a:
		"uneq": I.unequip_gear(arg)
		"all": filt = ""
		"sellc": I.sell_commons()
		"eq": I.equip_gear(int(arg))
		"sell": I.sell_gear(int(arg))
		"eat": I.eat_food(arg)
		"open":
			close()
			if LevelUp.me: LevelUp.me.open_perks()
			return
	render()

# ---------------------------------------------------------------- render (renderInv)
func render() -> void:
	if not panel.visible: return
	money.text = "₺ %d · Lv %d" % [SaveBridge.get_i("lira"), Stats.lvl()]
	for c in tabs_row.get_children(): tabs_row.remove_child(c); c.queue_free()      # gone now, so the row never measures 12 tabs
	for tb in D["INVTABS"]:
		var id: String = tb[0]
		var label: String = tb[1]
		if id == "cards" and SaveBridge.get_i("pp") > 0: label += "  (%d)" % SaveBridge.get_i("pp")
		var b := _btn(label, _set_tab.bind(id), GOLD if tab == id else PURPLE, 14)
		if tab == id: b.add_theme_stylebox_override("normal", _sb(Color(.3, .14, .32, 1), GOLD, 2, 8, 6))
		tabs_row.add_child(b)
	for c in body.get_children(): body.remove_child(c); c.queue_free()
	match tab:
		"gear": _gear()
		"bag": _bag()
		"cards": _cards()
		"nazar": _nazar()
		"quests": _quests()
		_: _stats()
	scroll.scroll_vertical = 0
	# 🔠 TEXT SIZE (UiScale): everything scales; the tabs grow less so they stay on one line, the list gets shorter
	UiScale.apply(panel); UiScale.apply(tabs_row, 1.25)
	scroll.custom_minimum_size.y = 540.0 - maxf(0.0, UiScale.k() - 1.0) * 90.0; panel.size = Vector2(900, 672)

func _gear_card(parent: Node, it: Dictionary, cmp = null) -> void:
	var I := Items.me
	var B := I.base_of(it); var R: Dictionary = D["RAR"][int(it["r"])]
	var rows := []
	for k in it["st"]:
		var arrow := ""
		if cmp != null:
			var ov := float((cmp as Dictionary).get("st", {}).get(k, 0.0)) if cmp is Dictionary else 0.0
			var dv := float(it["st"][k]) - ov
			if absf(dv) > 1e-6: arrow = " [color=#5fff9e]▲[/color]" if dv > 0 else " [color=#ff5f7a]▼[/color]"
		rows.append(I.stat_txt(k, float(it["st"][k])) + arrow)
	# compare also shows what she'd lose (stats the worn piece has and this one doesn't)
	if cmp is Dictionary and not (cmp as Dictionary).is_empty():
		for k in cmp["st"]:
			if not it["st"].has(k): rows.append("[color=#ff5f7a]%s ▼[/color]" % I.stat_txt(k, float(cmp["st"][k])).replace("+", "−"))
	_rich(parent, "[color=%s][b]%s %s[/b][/color]\n[font_size=12][color=#b8b0d8]%s [i]%s[/i] · %s · Lv %d[/color][/font_size]\n%s" % [R["c"], B["ic"], I.gear_name(it),
		R["n"], R["en"], B["en"], int(it["lv"]), "\n".join(rows)], 14, 0)

func _gear() -> void:
	var I := Items.me
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 12); body.add_child(cols)
	var left := VBoxContainer.new(); left.custom_minimum_size = Vector2(290, 0); left.add_theme_constant_override("separation", 8); cols.add_child(left)
	for sl in D["SLOTS"]:
		var sid: String = sl["id"]
		var v := _card(left, GOLD if filt == sid else Color("5a4a7a"), 290)
		var pc: PanelContainer = v.get_parent()
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		pc.gui_input.connect(_slot_click.bind(sid))
		_rich(v, "[b]%s %s[/b] [i][color=#9a94a8]%s[/color][/i]" % [sl["ic"], sl["tr"], sl["en"]], 14, 260)
		var it := I.eq_item(sid)
		if it.is_empty(): _rich(v, "[color=#6a6488]— boş · empty —[/color]", 13, 260)
		else:
			_gear_card(v, it)
			v.add_child(_btn("ÇIKAR · take off", _do.bind("uneq", sid), PINK, 12))
	var right := VBoxContainer.new(); right.add_theme_constant_override("separation", 8); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(right)
	var gear: Array = SaveBridge.data["gear"]
	var head := HBoxContainer.new(); right.add_child(head)
	var fname := ""
	for sl in D["SLOTS"]: if sl["id"] == filt: fname = sl["en"]
	var lh := _rich(head, "[color=#7bf7ff]%d/%d pieces[/color]%s" % [gear.size(), int(D["GEARMAX"]), (" · showing %s" % fname) if filt != "" else " · click a slot to filter"], 13, 0)
	lh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if filt != "": head.add_child(_btn("show all", _do.bind("all", ""), CYAN, 12))
	head.add_child(_btn("sell all common", _do.bind("sellc", ""), PINK, 12))
	var list: Array = gear.filter(func(g): return filt == "" or I.base_of(g)["s"] == filt)
	list.sort_custom(func(a, b): return int(a["r"]) > int(b["r"]) or (int(a["r"]) == int(b["r"]) and int(a["lv"]) > int(b["lv"])))
	if list.is_empty():
		_rich(right, "[color=#9a94a8]No gear yet. Monsters drop it now and then — elites, chests and bosses much more often. It glows with a beam of light.[/color]", 14, 520)
	for it in list:
		var sl: String = I.base_of(it)["s"]
		var cur = SaveBridge.data["eq"].get(sl)
		var on: bool = cur != null and int(cur) == int(it["u"])
		var v := _card(right, Color(I.rar_col(int(it["r"]))), 0)
		var row := HBoxContainer.new(); v.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		_gear_card(info, it, null if on else I.eq_item(sl))
		var bv := VBoxContainer.new(); row.add_child(bv)
		var u := int(it["u"])
		if on: _rich(bv, "[color=#5fff9e]✔ TAKILI · worn[/color]", 13, 130)
		else: bv.add_child(_btn("TAK · wear", _do.bind("eq", str(u)), Color("5fff9e"), 12))
		bv.add_child(_btn("SAT · sell %d₺" % I.gear_value(it), _do.bind("sell", str(u)), PINK, 12))

func _bag() -> void:
	var I := Items.me
	_rich(body, "[color=#7bf7ff]%d/%d slots · up to %d of each · [b]H[/b] eats the best one for your HP[/color]" % [I.bag_used(), I.bag_cap(), int(D["STACK"])], 14, 840)
	var ks: Array = I.bag().keys().filter(func(k): return int(I.bag()[k]) > 0 and D["FOOD"].has(k))
	if ks.is_empty():
		_rich(body, "[color=#9a94a8]Your backpack is empty. Food you pick up lands here instead of being eaten on the spot — monsters drop it, and it lies around the city.[/color]", 14, 840)
		return
	var g := _grid(4)
	for k in ks:
		var F: Dictionary = D["FOOD"][k]
		var v := _card(g, GOLD, 200)
		_rich(v, "[center][font_size=34]%s[/font_size]\n[b]%s[/b] ×%d\n[color=#9a94a8][i]%s[/i][/color][/center]" % [F["ic"], F["tr"], int(I.bag()[k]), F["en"]], 15, 180)
		_rich(v, "[center][font_size=12]%s[/font_size][/center]" % I.food_desc(k), 12, 180)
		var key: String = k
		v.add_child(_btn("YE · eat", _do.bind("eat", key), Color("5fff9e"), 13))

func _cards() -> void:
	var pp := SaveBridge.get_i("pp")
	var head := HBoxContainer.new(); body.add_child(head)
	if pp > 0:
		_rich(head, "[color=#ffd66b][b]%d unopened card%s[/b][/color]  " % [pp, "" if pp == 1 else "s"], 16, 0)
		head.add_child(_btn("🃏 OPEN ONE", _do.bind("open", ""), GOLD, 14))
	else: _rich(head, "[color=#9a94a8]No unopened cards — you get one every level.[/color]", 14, 600)
	var own: Array = (D["PERKS"] as Array).filter(func(p): return Stats.pk(p["id"]) > 0)
	if own.is_empty():
		_rich(body, "[color=#9a94a8]No perks yet. Level up — or open the cards you already earned.[/color]", 14, 840); return
	var g := _grid(4)
	for p in own:
		var dots := ""
		for i in int(p["max"]): dots += "●" if i < Stats.pk(p["id"]) else "○"
		var v := _card(g, Color(str(p["c"])), 200)
		_rich(v, "[center][font_size=30]%s[/font_size]\n[color=%s][b]%s[/b][/color]\n[color=#9a94a8][i]%s[/i][/color]\n[font_size=12]%s[/font_size]\n[color=#ffd66b]%s[/color][/center]" % [p["ic"], p["c"], p["tr"], p["en"], p["d"], dots], 14, 180)

func _nazar() -> void:
	var I := Items.me
	var n := Stats.nz_count()
	_rich(body, "🧿 [b]%d/50[/b] hidden nazar beads found" % n, 17, 840)
	var bar := ProgressBar.new(); bar.max_value = 50; bar.value = n; bar.show_percentage = false; bar.custom_minimum_size = Vector2(840, 14)
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("4fb4ff"); fill.set_corner_radius_all(6); bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, .5); bg.set_corner_radius_all(6); bar.add_theme_stylebox_override("background", bg)
	body.add_child(bar)
	var g := _grid(5)
	for r in D["NZREG"]:
		var tot := 0; var f := 0
		for j in D["NZ_SPOTS"].size():
			if D["NZ_SPOTS"][j][2] == r:
				tot += 1
				if I.found(j): f += 1
		var v := _card(g, Color("4fb4ff") if f < tot else Color("5fff9e"), 158)
		_rich(v, "[center][b]%s[/b]\n[font_size=26]%s[/font_size]\n[b]%d[/b] / %d[/center]" % [D["NZREG"][r], "✅" if f == tot else "🧿", f, tot], 14, 140)
	_rich(body, "\n[color=#ffd66b][b]Rewards[/b][/color]", 15, 840)
	for R in D["NZREW"]:
		var got := n >= int(R["n"])
		var rl := _rich(body, "%s [b]%d[/b] — %s" % ["✅" if got else "🔒", int(R["n"]), R["t"]], 14, 840)
		rl.modulate = Color.WHITE if got else Color(1, 1, 1, .6)
	if n:
		_rich(body, "\n[color=#ffd66b][b]Sayings you have found[/b][/color]", 15, 840)
		var lines: Array = D["NZLINES"]
		for i in mini(n, lines.size()):
			_rich(body, "[color=#ffd66b]%s[/color] — [i]%s[/i]" % [lines[i][0], lines[i][1]], 14, 840)

# another system's singleton by class name, looked up at runtime so this file parses on its own
static var _cls := {}
func _sys(cname: String) -> Object:
	if not _cls.has(cname):
		_cls[cname] = null
		for c in ProjectSettings.get_global_class_list():
			if c["class"] == cname: _cls[cname] = load(c["path"]); break
	var sc = _cls[cname]
	if sc == null: return null
	var o = sc.get("me")
	return o if is_instance_valid(o) else null

func _quests() -> void:
	if quest_panel.is_valid():
		_rich(body, str(quest_panel.call()), 14, 840); return
	# the side quests (quests.gd's log) on top, then the story so far (Kaan's 20 missions)
	var qs := _sys("Quests")
	if qs and qs.has_method("log_bbcode"):
		_rich(body, "[color=#ffd66b][b]📜 YAN GÖREVLER · SIDE QUESTS[/b][/color]\n" + str(qs.call("log_bbcode")) + "\n", 14, 840)
	var ms: Array = []
	var mi := _sys("Missions")
	if mi and mi.get("M") is Array and (mi.get("M") as Array).size(): ms = mi.get("M")
	else: ms = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["missions"]
	var nx := SaveBridge.get_i("next")
	var done: bool = SaveBridge.data.get("done", false) == true
	_rich(body, "[color=#ffd66b][b]📜 KAAN'S MISSIONS[/b][/color] [color=#9a94a8]· %d / %d[/color]" % [ms.size() if done else mini(nx, ms.size()), ms.size()], 16, 840)
	var g := _grid(2)
	for i in ms.size():
		var st := "✅" if (done or i < nx) else ("▶" if i == nx else "🔒")
		var title := str(ms[i].get("title", ms[i].get("id", "?")))
		if st == "🔒": title = "[color=#6a6488]%s[/color]" % title
		var v := _card(g, GOLD if st == "▶" else Color("3a2f55"), 412)
		_rich(v, "%s  %s" % [st, title], 14, 390)
	var q = SaveBridge.data.get("q")
	if q is Dictionary and not q.is_empty() and not qs:
		_rich(body, "\n[color=#9a94a8]Side quests started: %d — talk to people with a gold [b]![/b] over their heads.[/color]" % q.size(), 13, 840)

func _stats() -> void:
	var p = player
	var pct := func(v: float) -> String: return "%d%%" % int(round(v * 100))
	var words = SaveBridge.data.get("words", [])
	var rows := [["⭐ Level", "%d · XP %d/%d" % [Stats.lvl(), SaveBridge.get_i("xp"), SaveBridge.xp_for(Stats.lvl())]],
		["❤️ Max HP", str(p.max_hp if is_instance_valid(p) else SaveBridge.get_i("mh", 100))],
		["🔮 Max mana", str(SaveBridge.get_i("mm", 100))], ["🏃‍♀️ Max stamina", str(SaveBridge.get_i("ms", 100))],
		["🗡 Damage", "×%.2f" % Stats.stat("dmg")], ["💥 Crit chance", pct.call(Stats.stat("crit"))],
		["🛡 Damage taken", "−" + pct.call(Stats.stat("armor"))], ["👟 Run speed", pct.call(Stats.stat("spd"))],
		["🚲 Bike speed", pct.call(Stats.stat("bike"))], ["📈 XP bonus", "+" + pct.call(Stats.stat("xp") + SaveBridge.get_i("int") * .08)],
		["💰 Lira bonus", "+" + pct.call(Stats.stat("lira"))], ["🍀 Drop luck", "+" + pct.call(Stats.stat("luck"))],
		["🧠 INT", str(SaveBridge.get_i("int"))], ["📚 Turkish words", str((words as Array).size() if words is Array else 0)],
		["⚔️ Monsters beaten", str(SaveBridge.get_i("kills"))], ["🧿 Nazars", "%d/50" % Stats.nz_count()],
		["💰 Lira", "%d₺" % SaveBridge.get_i("lira")], ["🧿 Ammo", str(SaveBridge.get_i("ammo"))]]
	var g := _grid(2)
	for r in rows:
		var v := _card(g, Color("3a2f55"), 412)
		_rich(v, "[color=#b8b0d8]%s[/color]   [b][color=#ffd66b]%s[/color][/b]" % [r[0], r[1]], 15, 390)
