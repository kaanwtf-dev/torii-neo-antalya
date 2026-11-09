# The level-up show, perk cards, every-5th-level milestones and the first-time "how it works" cards,
# ported from 7.2: levelUpShow / updateLevelUp / fireworkBurst (5.2 s: banner, stats toast, shockwave
# 45+7·lvl that scares monsters off, fireworks + glitter, a dance, invulnerable, teaches "seviye", saves
# right away = CRT-01), PERKS / drawPerks / takePerk / openPerks / pickPerk / closePerks (1-2-3 or click,
# SONRA = keep them for later; opens by itself after the show), MILESTONES / checkMilestones /
# milestoneCard (msd, +50 max HP per 5 levels after 30), TIPS / tip() / showTip / closeTip (save `tips`).
# It watches the save's level, so a level from anywhere (kills, lessons, missions) gets the show.
class_name LevelUp
extends CanvasLayer

static var me: LevelUp
const LU_DUR := 5.2
var player
var hud: Hud
var D := {}
var _last := 0
var show_t := 0.0
var _fw := 0.0
var perk_auto_t := -1.0             # > 0: open the perk pick when it runs out (7.2's S.perkAutoT)
var _cards: Array = []              # milestone cards waiting: {m, t}
var _tipq: Array = []
var _hand: Array = []
var _perk: PanelContainer
var _perk_body: VBoxContainer
var _tip: PanelContainer
var _tip_body: VBoxContainer
var _tip_frame := -1

static func queue_tip(id: String) -> void:
	if me: me.tip(id)

func setup(p, h: Hud) -> void:
	me = self; player = p; hud = h; layer = 6
	D = Stats.data()
	_last = Stats.lvl()
	_perk = _panel(Color("ffd66b")); _perk_body = _perk.get_child(0)
	_tip = _panel(Color("7bf7ff")); _tip_body = _tip.get_child(0)
	# no check_milestones() on load: 7.2 only catches up at the next level-up (loading must not rewrite msd)

# other systems can add their own cards: LevelUp.me.add_tips({"race": {"t": "...", "l": ["..."]}})
func add_tips(t: Dictionary) -> void:
	for k in t: D["TIPS"][k] = t[k]

func _panel(col: Color) -> PanelContainer:
	var p := PanelContainer.new(); p.visible = false
	# anchored on the centre and growing both ways, so it stays centred whatever its content
	p.anchor_left = .5; p.anchor_right = .5; p.anchor_top = .5; p.anchor_bottom = .5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH; p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.06, .03, .12, .97); sb.border_color = col
	sb.set_border_width_all(3); sb.set_corner_radius_all(14); sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb); add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); p.add_child(v)
	return p

func _rich(parent: Node, text: String, size := 16, col := Color("e8e4f8"), w := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.text = text; r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.add_theme_color_override("default_color", col)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: r.add_theme_font_size_override(k, size)
	if w > 0: r.custom_minimum_size = Vector2(w, 0)
	parent.add_child(r); return r

func _center(p: PanelContainer) -> void:
	p.offset_left = 0; p.offset_right = 0; p.offset_top = 0; p.offset_bottom = 0

func _sfx(n: String) -> void: Bus.emit_ev("sfx", {"name": n})

# ---------------------------------------------------------------- the show
func check() -> void:
	var L := Stats.lvl()
	if L > _last:
		var g := L - _last; _last = L; _show(g)
	elif L < _last: _last = L

func _show(gained: int) -> void:
	var L := Stats.lvl()
	show_t = LU_DUR; _fw = 0.0
	Stats.apply(player)
	if is_instance_valid(player):
		player.hp = player.max_hp; player.hp_changed.emit(player.hp, player.max_hp)
		if "stamina" in player: player.stamina = float(player.max_stamina)
		if "dance_t" in player: player.dance_t = LU_DUR
		if player.has_method("set_status"): player.set_status("shield", LU_DUR)   # invulnerable through the show
		elif "hurt_cd" in player: player.hurt_cd = LU_DUR
	if hud:
		hud.banner("⭐ LEVEL %d ⭐\n[font_size=16]✨ invulnerable[/font_size]" % L)
		hud.toast("⭐ [b]LEVEL %d![/b]\n[font_size=14]❤️ +%d max HP · 🗡 +%d%% damage · 🔮 +%d mana · 🏃‍♀️ +%d stamina · 🃏 perk card%s coming[/font_size]" % [L,
			12 * gained, 3 * gained, 3 * gained, 2 * gained, "s" if gained > 1 else ""], 8.0)
	check_milestones()
	perk_auto_t = LU_DUR + .4
	tip("levels")
	if Lessons.me: Lessons.me.teach("seviye")
	_sfx("levelup"); _sfx("fanfare")
	# one-time shockwave: everything close takes a hit and runs
	var hits := 0
	var dmg := 45 + L * 7
	if is_instance_valid(player):
		var pp: Vector3 = player.global_position
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or (e.has_method("is_alive") and not e.is_alive()) or ("hp" in e and e.hp <= 0): continue
			var to: Vector3 = e.global_position - pp; to.y = 0
			if to.length() >= 28.0: continue
			var dir := to.normalized() if to.length() > .01 else Vector3.FORWARD
			e.hit(float(dmg), dir, {"heavy": true, "kb": 28.0, "stagger": 1.2, "status": "fear", "status_t": LU_DUR + 1.5})
			hits += 1
		if hits and hud: hud.toast("💥 [b]LEVEL-UP SHOCKWAVE![/b] %d enem%s blasted for %d — they're fleeing!" % [hits, "y" if hits == 1 else "ies", dmg], 6.0)
		if Fx.me:
			for i in 3: _firework(pp + Vector3(randf_range(-6, 6), randf_range(6, 11), randf_range(-6, 6)))
			Fx.me.puff(pp + Vector3(0, 1.2, 0), Fx.CONF, 40, 6, 3.4, 1.4, 1.1)
			Fx.me.shake(.35)
	SaveBridge.write()                  # CRT-01: a level from kills is saved the moment it happens
	Bus.emit_ev("level_up", {"level": L})

func _firework(at: Vector3) -> void:
	if not Fx.me: return
	Fx.me.puff(at, Fx.CONF.pick_random(), 17, 7.0, 6.0, 1.1)
	_sfx("firework")

func _show_tick(dt: float) -> void:
	show_t -= dt
	if not is_instance_valid(player) or not Fx.me: return
	var pp: Vector3 = player.global_position
	_fw -= dt
	if _fw <= 0:
		_fw = randf_range(.28, .55)
		_firework(pp + Vector3(randf_range(-16, 16), randf_range(7, 17), randf_range(-16, 16)))
	if randf() < dt * 22.0:
		Fx.me.puff(pp + Vector3(randf_range(-1.4, 1.4), randf_range(.4, 2.6), randf_range(-1.4, 1.4)), Fx.CONF, 1, .5, 1.4, .9)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("apply_status") and e.global_position.distance_squared_to(pp) < 90: e.apply_status("fear", .5)

# ---------------------------------------------------------------- milestones (every 5th level)
func milestone_for(L: int) -> Dictionary:
	for m in D["MILESTONES"]: if int(m["lv"]) == L: return m
	if L > 30 and L % 5 == 0:
		return {"lv": L, "ic": "🌟", "t": "YILDIZ %d · PRESTIGE" % (L / 5 - 6), "d": "[b]+50 max HP[/b] and [b]+5% damage[/b], forever."}
	return {}

func check_milestones() -> void:
	var L := Stats.lvl()
	var msd: Dictionary = SaveBridge.data["msd"] if SaveBridge.data.get("msd") is Dictionary else {}
	var changed := false
	for v in range(5, L + 1, 5):
		if msd.has(str(v)): continue
		msd[str(v)] = 1; changed = true
		if v > 30:
			SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + 50
			if is_instance_valid(player): player.max_hp = SaveBridge.get_i("mh", 100); player.hp += 50
		var m := milestone_for(v)
		if not m.is_empty(): _cards.append({"m": m, "t": (LU_DUR - .6) if show_t > 0 else 1.0})
	if changed:
		SaveBridge.data["msd"] = msd
		Stats.apply(player)
		if not SaveBridge.data.is_empty(): SaveBridge.write()

func _card(m: Dictionary) -> void:
	if not hud: return
	hud.banner("%s %s\n[font_size=16]Level %d milestone[/font_size]" % [m["ic"], m["t"], int(m["lv"])])
	hud.toast("🏆 [b]SEVİYE %d ÖDÜLÜ[/b] · %s [b]%s[/b]\n%s" % [int(m["lv"]), m["ic"], m["t"], m["d"]], 11.0)
	_sfx("divine")

# ---------------------------------------------------------------- perk cards
func _dots(p: Dictionary) -> String:
	var s := ""
	for i in int(p["max"]): s += "●" if i < Stats.pk(p["id"]) else "○"
	return s

func draw_perks() -> Array:
	var pool: Array = (D["PERKS"] as Array).filter(func(p): return Stats.pk(p["id"]) < int(p["max"]))
	var out := []
	while out.size() < 3 and pool.size():
		var tot := 0.0
		for p in pool: tot += float(p["w"])
		var r := randf() * tot; var ix := 0
		while ix < pool.size():
			r -= float(pool[ix]["w"])
			if r <= 0: break
			ix += 1
		out.append(pool.pop_at(mini(ix, pool.size() - 1)))
	return out

func take_perk(id: String) -> bool:
	var P := {}
	for p in D["PERKS"]: if p["id"] == id: P = p
	if P.is_empty() or Stats.pk(id) >= int(P["max"]): return false
	var perks: Dictionary = SaveBridge.data["perks"] if SaveBridge.data.get("perks") is Dictionary else {}
	perks[id] = Stats.pk(id) + 1; SaveBridge.data["perks"] = perks
	match id:
		"dayanikli":
			SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + 40
			if is_instance_valid(player): player.max_hp = SaveBridge.get_i("mh", 100); player.hp += 40
		"maraton":
			SaveBridge.data["ms"] = SaveBridge.get_i("ms", 100) + 25
			if is_instance_valid(player) and "stamina" in player: player.max_stamina = float(SaveBridge.get_i("ms", 100)); player.stamina += 25.0
		"buyucu":
			SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + 20
			if is_instance_valid(player) and "mana" in player: player.max_mana = float(SaveBridge.get_i("mm", 100)); player.mana += 20.0
		"ogrenci": SaveBridge.data["int"] = SaveBridge.get_i("int") + 2
	Stats.apply(player)
	return true

func open_perks() -> void:
	if SaveBridge.get_i("pp") <= 0: return
	_hand = draw_perks()
	if _hand.is_empty(): SaveBridge.data["pp"] = 0; return
	for c in _perk_body.get_children(): c.queue_free()
	var tips: Dictionary = SaveBridge.data["tips"] if SaveBridge.data.get("tips") is Dictionary else {}
	var first: bool = not tips.has("perks")
	tips["perks"] = 1; SaveBridge.data["tips"] = tips
	_rich(_perk_body, "[center][color=#ffd66b][b]⭐ PERK KARTI[/b][/color] [color=#b8b0d8]· seviye %d[/color][/center]" % Stats.lvl(), 24, Color.WHITE, 820)
	if first: _rich(_perk_body, "\n".join(D["TIPS"]["perks"]["l"]), 14, Color("cfe9ff"), 820)
	var pp := SaveBridge.get_i("pp")
	_rich(_perk_body, "[center]Pick one. You keep it forever%s[/center]" % (" · [b]%d cards[/b] waiting" % pp if pp > 1 else ""), 15, Color("e8e4f8"), 820)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 16); row.alignment = BoxContainer.ALIGNMENT_CENTER
	_perk_body.add_child(row)
	for i in _hand.size():
		var p: Dictionary = _hand[i]
		var b := Button.new(); b.custom_minimum_size = Vector2(250, 270); b.focus_mode = Control.FOCUS_NONE
		var col := Color(str(p["c"]))
		for st_name in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new(); sb.bg_color = Color(.1, .05, .18, 1) if st_name == "normal" else Color(.16, .08, .26, 1)
			sb.border_color = col; sb.set_border_width_all(3 if st_name == "normal" else 4); sb.set_corner_radius_all(12)
			b.add_theme_stylebox_override(st_name, sb)
		b.pressed.connect(pick_perk.bind(i))
		var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.offset_left = 12; v.offset_right = -12; v.offset_top = 10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(v)
		var rank := Stats.pk(p["id"])
		_rich(v, "[center][color=#ffd66b]%d[/color]\n[font_size=40]%s[/font_size]\n[color=%s][b]%s[/b][/color]\n[color=#b8b0d8]([i]%s[/i])[/color][/center]" % [i + 1, p["ic"], p["c"], p["tr"], p["en"]], 20, Color.WHITE, 226)
		_rich(v, "[center]%s[/center]" % p["d"], 14, Color("e8e4f8"), 226)
		_rich(v, "[center][color=#ffd66b]%s[/color] %s[/center]" % ["RANK %d/%d" % [rank + 1, int(p["max"])] if rank else "NEW", _dots(p)], 13, Color.WHITE, 226)
		row.add_child(b)
	var later := Button.new(); later.text = "SONRA · save them for later [ESC]"; later.focus_mode = Control.FOCUS_NONE
	later.add_theme_font_size_override("font_size", 15); later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(close_perks); _perk_body.add_child(later)
	_rich(_perk_body, "[center]1 · 2 · 3 or click a card · unopened cards wait in your 🎒 inventory (I)[/center]", 13, Color("7bf7ff"), 820)
	_perk.visible = true; _center(_perk)
	Overlay.open("perk"); _sfx("ding")

func pick_perk(i: int) -> void:
	if not _perk.visible or i < 0 or i >= _hand.size(): return
	var p: Dictionary = _hand[i]
	if take_perk(p["id"]):
		SaveBridge.data["pp"] = maxi(0, SaveBridge.get_i("pp") - 1)
		_sfx("levelup")
		if hud: hud.toast("%s [b]%s[/b] [i](%s)[/i] — %s" % [p["ic"], p["tr"], p["en"], p["d"]], 6.0)
		if Fx.me and is_instance_valid(player):
			Fx.me.puff(player.global_position + Vector3(0, 1.6, 0), [Color("ffd66b"), Color("b06bff"), Color("ff5fa2")], 18, 2.2, 2.6, 1.0)
	SaveBridge.write()
	if SaveBridge.get_i("pp") > 0: open_perks()
	else: close_perks()

func close_perks() -> void:
	if not _perk.visible: return
	_perk.visible = false; Overlay.close("perk")
	_hand = []; perk_auto_t = -1.0
	var pp := SaveBridge.get_i("pp")
	if pp > 0 and hud: hud.toast("🃏 [b]%d perk card%s saved.[/b] Open them any time from your inventory — press [b]I[/b]." % [pp, "" if pp == 1 else "s"], 6.0)

# ---------------------------------------------------------------- how-it-works cards (UI-15)
func tip(id: String) -> void:
	if not D["TIPS"].has(id) or _tipq.has(id): return
	var tips = SaveBridge.data.get("tips")
	if tips is Dictionary and tips.has(id): return
	_tipq.append(id)

func _show_tip(id: String) -> void:
	var T: Dictionary = D["TIPS"][id]
	var tips: Dictionary = SaveBridge.data["tips"] if SaveBridge.data.get("tips") is Dictionary else {}
	tips[id] = 1; SaveBridge.data["tips"] = tips
	for c in _tip_body.get_children(): c.queue_free()
	var tw := UiScale.wide(620, 900)          # 🔠 TEXT SIZE: a wider card, so bigger words still fit the screen
	_rich(_tip_body, "[color=#7bf7ff]📘 NASIL ÇALIŞIR · HOW IT WORKS[/color]", 13, Color.WHITE, tw)
	_rich(_tip_body, "[b]%s[/b]" % T["t"], 22, Color("ffd66b"), tw)
	for l in T["l"]: _rich(_tip_body, "• " + str(l).replace("[b]", "[b][color=#7bf7ff]").replace("[/b]", "[/color][/b]"), 16, Color("e8e4f8"), tw)
	var ok := Button.new(); ok.text = "ANLADIM · GOT IT ▶"; ok.focus_mode = Control.FOCUS_NONE; ok.add_theme_font_size_override("font_size", 16)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; ok.pressed.connect(close_tip); _tip_body.add_child(ok)
	_rich(_tip_body, "[center][color=#9a94a8]Enter / E / Space / Esc closes it[/color][/center]", 12, Color.WHITE, tw)
	UiScale.apply(_tip)
	_tip.visible = true; _center(_tip); _tip_frame = Engine.get_process_frames()
	Overlay.open("tip"); _sfx("ding")
	SaveBridge.write()

func close_tip() -> void:
	if not _tip.visible: return
	_tip.visible = false; Overlay.close("tip")

# ----------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.keycode
	if _perk.visible:
		if k >= KEY_1 and k <= KEY_3: pick_perk(k - KEY_1)
		elif k == KEY_ESCAPE: close_perks()
		else: return
		get_viewport().set_input_as_handled()
	elif _tip.visible:
		if Engine.get_process_frames() == _tip_frame: return
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_ESCAPE, KEY_SPACE]: close_tip(); get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	check()
	if show_t > 0: _show_tick(dt)
	for c in _cards.duplicate():
		c["t"] -= dt
		if c["t"] <= 0: _cards.erase(c); _card(c["m"])
	if perk_auto_t > 0:
		perk_auto_t -= dt
		if perk_auto_t <= 0:
			perk_auto_t = -1.0
			if Overlay.any() or (is_instance_valid(player) and player.dead): perk_auto_t = 1.0      # try again once she's free
			else: open_perks()
	if _tipq.size() and show_t <= 0 and not Overlay.any() and perk_auto_t <= 0:
		_show_tip(_tipq.pop_front())
