# The two shops from 7.2 and the little helpers every side system shares (Quests, Tutors, Tavla, Hotspots).
#  · FIVE SIPS (7.2's CAFE + openShopUI('cafe')): opens after the Five Sips owner's simit task (npc.fivesips = 2).
#    Cocktail +12 HP, 3 bill stacks (ammo), a tavla set (+20 mana), Turkish coffee (+20% speed 2 min), and
#    backpack food (simit, çay, ayran, lokum, baklava, börek).
#  · KUYUMCU ZEYNEP (VENDORS / openShopUI('jewel')) at the bazaar (-125, 58.5): 4 pieces of gear made for her
#    level with a rarity bonus, new stock every 15 min or when she levels up, price = gearValue × 3.
# Shared helpers: lira, weapons, the hunt gate, gear + backpack food in 7.2's save format (gear / eq / gu / bag)
# when no inventory system is around, task pickups lying in the world, neon signs, tip cards, and a kill hub
# (every monster death, once, to whoever listens).
class_name Shops
extends Node

static var me: Shops
static var D := {}
var torii: Node3D
var hud: Hud
var world: Node3D

# ---------------------------------------------------------------- shared helpers
static func data() -> Dictionary:
	if D.is_empty(): D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/shop.json"))
	return D

static func lira() -> int: return SaveBridge.get_i("lira")
static func add_lira(n: int) -> void:
	SaveBridge.data["lira"] = maxi(0, lira() + n)
	Bus.emit_ev("lira", {"delta": n})          # a notification: the lira is already in the save

static func xp(n: int) -> void:
	if Lessons.me: Lessons.me.xp(n)
	else: SaveBridge.gain_xp(n)

static func teach(w: String) -> void:
	if Lessons.me: Lessons.me.teach(w)

static func sfx(n: String, at = null) -> void:
	var d := {"name": n}
	if at is Vector3: d["pos"] = at
	Bus.emit_ev("sfx", d)

static func npcs() -> Dictionary:
	if not (SaveBridge.data.get("npc") is Dictionary): SaveBridge.data["npc"] = {}
	return SaveBridge.data["npc"]

static func flat2(p: Node3D, x: float, z: float) -> float:
	var dx := x - p.global_position.x; var dz := z - p.global_position.z
	return dx * dx + dz * dz

# the player through the contract, without needing her script to compile first
static func heal(p: Node, n: int) -> void:
	if p == null: return
	if p.has_method("heal"): p.heal(n)
	else:
		p.hp = mini(p.max_hp, p.hp + n)
		if p.has_signal("hp_changed"): p.hp_changed.emit(p.hp, p.max_hp)

static func hurt(p: Node, n: int) -> void:
	if p == null: return
	if p.has_method("take_hit"): p.take_hit(n)
	else: p.hp = maxi(1, p.hp - n)

static func mana(p: Node, n: float) -> void:
	if p and p.has_method("add_mana"): p.add_mana(n)

static func mana_full(p: Node) -> void:
	if p and p.has_method("add_mana"): p.add_mana(float(p.get("max_mana") if p.get("max_mana") != null else 100.0))

# giveWeapon(): the same weap / dur fields the missions use
static func give_weapon(id: String) -> bool:
	var weap: Array = SaveBridge.data["weap"] if SaveBridge.data.get("weap") is Array else ["katana"]
	if weap.has(id): return false
	weap.append(id)
	var dur: Dictionary = SaveBridge.data["dur"] if SaveBridge.data.get("dur") is Dictionary else {}
	var ws: Dictionary = {}
	if Missions.me: ws = Missions.me.D.get("weapons", {}).get(id, {})
	var dv = ws.get("dur", 40)
	dur[id] = 9999 if (dv == null or str(dv) == "inf" or float(dv) > 9999) else dv
	SaveBridge.data["weap"] = weap; SaveBridge.data["dur"] = dur
	Bus.emit_ev("weapon_gained", {"id": id})
	return true

# a hunt-gate "kill" from somewhere that isn't a gate monster (a won tavla match, Kaan's bounty mobs).
# Returns how many are still wanted (-1 = no hunt open).
static func gate_credit(elite := false, why := "") -> int:
	var M = Missions.me
	if M == null or M.gate.is_empty(): return -1
	if M.has_method("gate_credit"): return int(M.gate_credit(elite, why))
	var g: Dictionary = M.gate
	if elite and int(g.get("eleft", 0)) > 0: g["eleft"] = int(g["eleft"]) - 1
	elif int(g.get("left", 0)) > 0: g["left"] = int(g["left"]) - 1
	elif int(g.get("eleft", 0)) > 0: g["eleft"] = int(g["eleft"]) - 1
	SaveBridge.data["gate"] = g.duplicate()
	var left := maxi(0, int(g.get("left", 0))) + maxi(0, int(g.get("eleft", 0)))
	if left <= 0 and M.has_method("_gate_done"): M._gate_done()
	return left

static func gate_needs() -> int:
	var M = Missions.me
	if M == null or M.gate.is_empty(): return 0
	return maxi(0, int(M.gate.get("left", 0))) + maxi(0, int(M.gate.get("eleft", 0)))

# first-time help cards (7.2's tip(id), remembered in the save's `tips` like 7.2)
static func tip(id: String, title: String, lines: Array) -> void:
	if not (SaveBridge.data.get("tips") is Dictionary): SaveBridge.data["tips"] = {}
	if SaveBridge.data["tips"].get(id): return
	SaveBridge.data["tips"][id] = 1
	if me and me.hud: me._when_free(func(): me.hud.say(title, lines))

func _when_free(cb: Callable) -> void:
	var n := 0
	while Overlay.any() and n < 240:
		n += 1; await get_tree().create_timer(.25).timeout
	cb.call()

# 7.2's neonSign(): a glowing billboard word over someone's head
static func sign3d(text: String, col: Color, size := 64) -> Label3D:
	var l := Label3D.new(); l.text = text; l.modulate = col; l.font_size = size; l.pixel_size = .01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.shaded = false; l.double_sided = true
	l.outline_size = 10; l.outline_modulate = Color(0, 0, 0, .8); l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return l

static func ground_y(x: float, z: float, from := 60.0) -> float:
	if me == null or me.world == null: return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from, z), Vector3(x, -30, z))
	if me.torii is CollisionObject3D: q.exclude = [me.torii.get_rid()]
	var hit := me.world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0

static func panel_box(col: Color, alpha := .96) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, alpha); sb.border_color = col
	sb.set_border_width_all(2); sb.set_corner_radius_all(12); sb.set_content_margin_all(14)
	return sb

static func button(t: String, col: Color, size := 15) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size); b.add_theme_color_override("font_color", Color("ffe9fb"))
	var st := StyleBoxFlat.new(); st.bg_color = Color(.12, .06, .2, .95); st.border_color = col
	st.set_border_width_all(2); st.set_corner_radius_all(8); st.set_content_margin_all(7)
	var hv := st.duplicate(); hv.bg_color = Color(.2, .1, .3, .95)
	b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", hv); b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("disabled", st)
	return b

static func rich(t: String, size := 16, col := Color.WHITE, w := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.add_theme_color_override("default_color", col)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: r.add_theme_font_size_override(k, size)
	if w > 0: r.custom_minimum_size = Vector2(w, 0)
	r.text = t; return r

# ---- gear and the backpack, in 7.2's save format (S.gear / S.eq / S.gu / S.bag) ----
static func _inv() -> Node:
	if me == null or not me.is_inside_tree(): return null
	return me.get_tree().get_first_node_in_group("inventory")

static func rar_cap() -> int:
	var L := SaveBridge.get_i("lvl", 1)
	return 4 if L >= 30 else (3 if L >= 20 else (2 if L >= 5 else 1))

static func gbase(id: String) -> Dictionary:
	for g in data()["GEARBASE"]: if g["id"] == id: return g
	return data()["GEARBASE"][0]

static func _stat_roll(k: String, r: int, L: int) -> float:
	match k:
		"dmg": return .03 + .016 * r + .0018 * L
		"crit": return .02 + .011 * r + .0008 * L
		"spd": return .02 + .012 * r + .0005 * L
		"xp": return .04 + .02 * r + .001 * L
		"lira": return .05 + .03 * r + .001 * L
		"luck": return .06 + .035 * r
		"armor": return .02 + .012 * r + .0008 * L
		"hp": return 12 + 10 * r + 2.2 * L
		"mana", "stam": return 8 + 6 * r + 1.1 * L
		"bike": return .03 + .02 * r + .0008 * L
		"boost": return .06 + .035 * r
		"bagx": return 1 + floor(r / 1.5)
	return 0.0

static func _roll_rar(bonus: float) -> int:
	var cap := rar_cap(); var ws: Array[float] = []; var tot := 0.0
	var rs: Array = data()["RAR"]
	for i in rs.size():
		var w: float = 0.0 if i > cap else float(rs[i]["w"]) * pow(1.0 + bonus * 2.2, i)
		ws.append(w); tot += w
	var r := randf() * tot
	for i in ws.size():
		r -= ws[i]
		if r <= 0: return i
	return 0

# makeGear(o): o = {b, s, r, lv, bonus, n}
static func make_gear(o: Dictionary) -> Dictionary:
	var inv := _inv()
	if inv and inv.has_method("make_gear"): return inv.make_gear(o)
	var pool: Array = data()["GEARBASE"].filter(func(g): return not o.has("s") or g["s"] == o["s"])
	var B: Dictionary = gbase(o["b"]) if o.has("b") else pool.pick_random()
	var r: int = int(o["r"]) if o.has("r") else _roll_rar(float(o.get("bonus", 0.0)))
	var L := maxi(1, int(round(float(o.get("lv", SaveBridge.get_i("lvl", 1))))))
	var st := {}; st[B["p"]] = _stat_roll(B["p"], r, L)
	var sec: Array = B["sec"].duplicate(); sec.shuffle()
	for k in sec.slice(0, [0, 1, 1, 2, 3][clampi(r, 0, 4)]):
		st[k] = float(st.get(k, 0.0)) + _stat_roll(k, r, L) * randf_range(.55, .8)
	for k in st.keys():
		st[k] = maxf(1.0, round(st[k])) if k in ["hp", "mana", "stam", "bagx"] else round(st[k] * 200.0) / 200.0
	var gu := SaveBridge.get_i("gu") + 1
	SaveBridge.data["gu"] = gu
	var it := {"u": gu, "b": B["id"], "r": r, "lv": L, "st": st}
	if o.has("n"): it["n"] = o["n"]
	return it

static func gear_value(it: Dictionary) -> int:
	return int(round((10 + 6 * float(it.get("lv", 1))) * (1 + float(it.get("r", 0)) * 1.6)))

static func gear_name(it: Dictionary) -> String: return str(it.get("n", gbase(it["b"])["tr"]))

static func gear_text(it: Dictionary) -> String:
	var B := gbase(it["b"]); var R: Dictionary = data()["RAR"][clampi(int(it["r"]), 0, 4)]
	var sts := []
	for k in it["st"]:
		var N: Array = data()["STATN"].get(k, ["", k, ""])
		var v: float = it["st"][k]
		var num: String = ("+%d%%" % roundi(v * 100)) if N[2] == "%" else ("+%d" % roundi(v))
		sts.append(num + " " + str(N[1]))
	return "%s [b][color=%s]%s[/color][/b] · %s %s · Lv %d\n[font_size=13]%s[/font_size]" % [B["ic"], R["c"], gear_name(it), R["n"], B["en"], int(it["lv"]), " · ".join(sts)]

# gainGear(it): into the gear bag (30 max — a full bag sells it), an empty slot puts it on straight away
static func gain_gear(it: Dictionary) -> void:
	var inv := _inv()
	if inv and inv.has_method("gain_gear"): inv.gain_gear(it); return
	var gear: Array = SaveBridge.data["gear"] if SaveBridge.data.get("gear") is Array else []
	if gear.size() >= 30:
		var v := gear_value(it); add_lira(v)
		if me: me.hud.toast("🎒 Gear bag full — sold [b]%s[/b] for %d₺." % [gear_name(it), v], 6.5, true)
		return
	gear.append(it); SaveBridge.data["gear"] = gear
	var eq: Dictionary = SaveBridge.data["eq"] if SaveBridge.data.get("eq") is Dictionary else {"eye": null, "jew": null, "shoe": null, "bag": null, "bike": null}
	var sl: String = gbase(it["b"])["s"]
	var auto: bool = eq.get(sl) == null
	if auto:
		eq[sl] = it["u"]
		# 7.2's applyFlat(): flat HP / mana / stamina live inside the stored maxima
		var st: Dictionary = it["st"]
		if st.has("hp"): SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + int(st["hp"])
		if st.has("mana"): SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + int(st["mana"])
		if st.has("stam"): SaveBridge.data["ms"] = SaveBridge.get_i("ms", 100) + int(st["stam"])
	SaveBridge.data["eq"] = eq
	if me: me.hud.toast(gear_text(it) + ("\n[color=#5fff9e]✔ put on straight away[/color]" if auto else "\n[i]press I to compare[/i]"), 7.0)
	Bus.emit_ev("gear_gained", {"item": it, "equipped": auto})
	sfx("divine" if int(it["r"]) >= 3 else "ding")
	SaveBridge.write()

static func bag() -> Dictionary:
	if not (SaveBridge.data.get("bag") is Dictionary): SaveBridge.data["bag"] = {}
	return SaveBridge.data["bag"]

# addFood(k, n): 10 per stack, 8 slots (+ backpack gear)
static func add_food(k: String, n := 1) -> bool:
	var inv := _inv()
	if inv and inv.has_method("add_food"): return bool(inv.add_food(k, n))
	if not data()["FOOD"].has(k): return false
	var b := bag(); var have := int(b.get(k, 0))
	if have >= 10: return false
	var used := 0
	for x in b: if int(b[x]) > 0: used += 1
	if have == 0 and used >= 8 + SaveBridge.get_i("bagx"): return false
	b[k] = mini(10, have + n)
	Bus.emit_ev("bag_changed", {"id": k})
	return true

# ---- task items lying in the world (shells, simit, cocktails, Bandit's friend's bone, Mert's pages) ----
var items: Array = []           # {node, kind, cb}
func drop_item(kind: String, at: Vector3, cb: Callable) -> Node3D:
	var n := Node3D.new(); world.add_child(n)
	var path := "res://assets/pickups/%s.glb" % kind
	if ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate(); Tint.apply(m); n.add_child(m)
	else:
		var col: Color = {"cocktail": Color("ff5fa2"), "bone": Color("f2ead8"), "sayfa": Color("fff8e8")}.get(kind, Color("ffd66b"))
		var sz: Vector3 = {"cocktail": Vector3(.22, .4, .22), "bone": Vector3(.6, .12, .14), "sayfa": Vector3(.36, .46, .02)}.get(kind, Vector3(.3, .3, .3))
		var mi := Npc._box(n, sz, Vector3.ZERO, col)
		var mat: StandardMaterial3D = mi.material_override; mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = .4
	var s := sign3d({"cocktail": "🍹", "bone": "🦴", "sayfa": "📄", "shell": "🐚", "simit": "🥯"}.get(kind, "✨"), Color.WHITE, 48)
	s.position.y = .9; n.add_child(s)
	n.position = Vector3(at.x, ground_y(at.x, at.z) + .7, at.z)
	items.append({"node": n, "kind": kind, "cb": cb})
	return n

func clear_items(cb: Callable) -> void:
	for it in items.duplicate():
		if it["cb"] == cb:
			if is_instance_valid(it["node"]): it["node"].queue_free()
			items.erase(it)

# ---- the kill hub: every monster death reaches each listener exactly once ----
static var _kill_subs: Array = []
static var _seen := {}
static func on_kill(cb: Callable) -> void: _kill_subs.append(cb)

func _kill(e) -> void:
	if e == null or not is_instance_valid(e): return
	var id: int = e.get_instance_id()
	if _seen.has(id): return
	_seen[id] = Time.get_ticks_msec()
	for cb in _kill_subs.duplicate():
		if cb.is_valid(): cb.call(e)

func _hook_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_signal("died") and not e.has_meta("side_hooked"):
			e.set_meta("side_hooked", true)
			e.died.connect(func(x): _kill(x))
	var now := Time.get_ticks_msec()
	for k in _seen.keys(): if now - int(_seen[k]) > 20000: _seen.erase(k)

static func kind_of(e) -> String:
	var k = e.get("kind") if e.get("kind") != null else e.get("type")
	return str(k) if k != null else ""

# ---------------------------------------------------------------- the shops
var _layer: CanvasLayer
var _panel: PanelContainer
var kind := ""
var stock: Array = []
var stock_t := 0.0
var stock_lv := -1
var _hook_t := 0.0

func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	me = self; world = w; torii = p; hud = h
	_kill_subs = []; _seen = {}
	Bus.on("enemy_died", func(d): _kill(d.get("enemy")))
	_layer = CanvasLayer.new(); _layer.layer = 6; add_child(_layer)
	for V in data()["VENDORS"]:
		var y := ground_y(V["x"], V["z"])
		var s := sign3d("💍 KUYUMCU", Color("ffd66b"), 80); s.position = Vector3(V["x"], y + 3.2, V["z"]); world.add_child(s)

func is_open() -> bool: return _panel != null

func prompt(p: Node3D) -> String:
	for V in data()["VENDORS"]:
		if flat2(p, V["x"], V["z"]) < 12: return "E: 💍 KUYUMCU ZEYNEP — gear for sale"
	return ""

# 7.2's vendorNear() + openShopUI(V.id)
func try_interact(p: Node3D) -> bool:
	for V in data()["VENDORS"]:
		if flat2(p, V["x"], V["z"]) < 12:
			var n := Npc.find_near(Vector3(V["x"], 0, V["z"]), 2.0)
			if n: n.face(p.global_position)
			open(V["id"]); return true
	return false

func open(k: String) -> void:
	kind = k
	var now := Time.get_ticks_msec() / 1000.0
	if k == "jewel" and (now > stock_t or stock.is_empty() or stock_lv != SaveBridge.get_i("lvl", 1)):
		stock = []
		for i in 4: stock.append(make_gear({"lv": SaveBridge.get_i("lvl", 1), "bonus": .25}))
		stock_lv = SaveBridge.get_i("lvl", 1); stock_t = now + 900.0
	Overlay.open("shop"); sfx("ding")
	_render()

func close() -> void:
	if _panel: _panel.queue_free(); _panel = null
	Overlay.close("shop"); SaveBridge.write()

func _render() -> void:
	if _panel: _panel.queue_free()
	_panel = PanelContainer.new(); _panel.position = Vector2(70, 60); _panel.size = Vector2(820, 600)
	_panel.add_theme_stylebox_override("panel", panel_box(Color("ffd66b") if kind == "jewel" else Color("ff5fa2")))
	_layer.add_child(_panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); _panel.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	var left := Time.get_ticks_msec() / 1000.0
	var title := "☕ FIVE SIPS  [font_size=13][color=#bfb0e0]\"Ne alırsın, kızım?\" · what'll you have?[/color][/font_size]" if kind == "cafe" \
		else "💍 KUYUMCU ZEYNEP  [font_size=13][color=#bfb0e0]the bazaar jeweller · new stock in %d min[/color][/font_size]" % maxi(0, ceili((stock_t - left) / 60.0))
	var tl := rich(title, 20, Color("ffd66b"), 600); top.add_child(tl)
	var money := rich("[right]₺ %d[/right]" % lira(), 20, Color("ffd66b"), 110); top.add_child(money)
	var x := button("✕", Color("ff5fa2")); x.pressed.connect(close); top.add_child(x)
	if kind == "cafe":
		var used := 0
		for k in bag(): if int(bag()[k]) > 0: used += 1
		v.add_child(rich("Food goes into your backpack (%d/%d slots) — eat it later with [b]H[/b]." % [used, 8 + SaveBridge.get_i("bagx")], 14, Color("bfeefc"), 780))
	else:
		v.add_child(rich("Green ▲ = better than what you're wearing in that slot. \"[i]Pahalı mı? Pazarlık yok![/i]\" — expensive? No haggling!", 14, Color("bfeefc"), 780))
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(780, 470); v.add_child(sc)
	var grid := GridContainer.new(); grid.columns = 2 if kind == "jewel" else 3
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10); sc.add_child(grid)
	if kind == "cafe":
		var cafe: Array = data()["CAFE"]
		for i in cafe.size(): grid.add_child(_cafe_card(i, cafe[i]))
	else:
		for i in stock.size(): grid.add_child(_gear_card(i, stock[i]))
	v.add_child(rich("[right][color=#8a7aae]ESC / E close[/color][/right]", 12, Color.WHITE, 780))

func _card(col: Color, w: float) -> VBoxContainer:
	var p := PanelContainer.new(); p.custom_minimum_size = Vector2(w, 0)
	var sb := panel_box(col, .9); sb.set_content_margin_all(9); sb.set_corner_radius_all(9); p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); p.add_child(v); return v

func _cafe_card(i: int, c: Dictionary) -> Control:
	var v := _card(Color("ff5fa2"), 245)
	var price := 0
	if c.has("food"):
		var F: Dictionary = data()["FOOD"][c["food"]]; price = int(F["p"])
		var have := int(bag().get(c["food"], 0))
		v.add_child(rich("[center][font_size=30]%s[/font_size]\n[b]%s[/b]\n[color=#bfb0e0]%s · backpack%s[/color]\n[color=#8ff2ff]%s[/color][/center]" % [F["ic"], F["tr"], F["en"], (" (have %d)" % have) if have else "", _food_desc(F)], 14, Color.WHITE, 225))
	else:
		price = int(c["p"])
		v.add_child(rich("[center][font_size=30]%s[/font_size]\n[b]%s[/b]\n[color=#bfb0e0]%s[/color][/center]" % [c["ic"], c["n"], c["en"]], 14, Color.WHITE, 225))
	var b := button("AL · buy %d₺" % price, Color("ffd66b"), 14); b.pressed.connect(_buy.bind(i)); v.add_child(b)
	return v.get_parent()

func _food_desc(F: Dictionary) -> String:
	var o := []
	if F.has("heal"): o.append("heals %d%% HP" % roundi(float(F["heal"]) * 100))
	if F.has("stam"): o.append("full stamina" if float(F["stam"]) >= 1 else "+half stamina")
	if F.has("mana"): o.append("+%d mana" % int(F["mana"]))
	if F.has("buff"): o.append({"regen": "♥ regen", "spd": "💨 speed", "dmg2": "💪 damage", "caffeine": "☕ caffeine", "focus": "🧠 focus"}.get(F["buff"], F["buff"]))
	return " · ".join(o)

func _gear_card(i: int, it) -> Control:
	var v := _card(Color(data()["RAR"][clampi(int(it["r"]), 0, 4)]["c"]) if it is Dictionary else Color("4a3b66"), 375)
	if not (it is Dictionary):
		v.add_child(rich("[center][color=#8a7aae]SATILDI · sold[/color][/center]", 15, Color.WHITE, 355)); return v.get_parent()
	var cmp := ""
	var eq: Dictionary = SaveBridge.data["eq"] if SaveBridge.data.get("eq") is Dictionary else {}
	var sl: String = gbase(it["b"])["s"]
	var worn = null
	for g in (SaveBridge.data.get("gear", []) as Array): if g is Dictionary and g.get("u") == eq.get(sl): worn = g
	if worn == null: cmp = "\n[color=#5fff9e]▲ empty slot[/color]"
	elif gear_value(it) > gear_value(worn): cmp = "\n[color=#5fff9e]▲ better than your %s[/color]" % gear_name(worn)
	v.add_child(rich(gear_text(it) + cmp, 15, Color.WHITE, 355))
	var b := button("AL · buy %d₺" % (gear_value(it) * 3), Color("ffd66b"), 14); b.pressed.connect(_buy_gear.bind(i)); v.add_child(b)
	return v.get_parent()

func _buy(i: int) -> void:
	var c: Dictionary = data()["CAFE"][i]
	var p: int = int(data()["FOOD"][c["food"]]["p"]) if c.has("food") else int(c["p"])
	if lira() < p:
		hud.toast("Not enough lira! Monsters drop ₺ coins", 3.5, true); sfx("no"); return
	if c.has("food"):
		if not add_food(c["food"], 1):
			hud.toast("🎒 Your backpack is full — eat something first ([b]H[/b]).", 3.5, true); sfx("no"); return
		add_lira(-p); sfx("coin")
		var F: Dictionary = data()["FOOD"][c["food"]]
		teach(str(F.get("w", F["tr"])))
	else:
		add_lira(-p); sfx("coin")
		match i:
			0: heal(torii, 12); if Fx.me: Fx.me.flash("heal")
			1: SaveBridge.data["ammo"] = SaveBridge.get_i("ammo") + 3; sfx("cash")
			2: mana(torii, 20); sfx("ding")
			3:
				if torii.has_method("set_status"): torii.set_status("haste", 120.0)
				hud.toast("☕ [b]Türk kahvesi![/b] +20% speed for 2 minutes — Afiyet olsun!", 5.0)
	_render()

func _buy_gear(i: int) -> void:
	var it = stock[i]
	if not (it is Dictionary): return
	var price := gear_value(it) * 3
	if lira() < price:
		hud.toast("Not enough lira! \"[i]Para yok, mal yok[/i]\" — no money, no goods.", 3.5, true); sfx("no"); return
	if (SaveBridge.data.get("gear", []) as Array).size() >= 30:
		hud.toast("🎒 Gear bag full — sell something first.", 3.5, true); sfx("no"); return
	add_lira(-price); stock[i] = null; gain_gear(it); _render()

func _unhandled_input(e: InputEvent) -> void:
	if _panel and e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_ESCAPE or e.keycode == KEY_E):
		close(); get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_hook_t -= dt
	if _hook_t <= 0: _hook_t = .3; _hook_enemies()
	if torii == null or Overlay.any(): return
	for it in items.duplicate():
		var n: Node3D = it["node"]
		if not is_instance_valid(n): items.erase(it); continue
		n.rotation.y += dt * 2.0
		if n.global_position.distance_squared_to(torii.global_position) < 3.2:
			items.erase(it)
			if Fx.me: Fx.me.puff(n.global_position, Fx.CONF, 10, 1.2, 2.0, .7)
			sfx("ding", n.global_position); n.queue_free()
			Bus.emit_ev("pickup", {"id": it["kind"], "kind": it["kind"], "pos": n.global_position, "side": true})
			if it["cb"].is_valid(): it["cb"].call(it["kind"])
