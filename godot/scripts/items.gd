# Everything she can pick up, carry, wear or open — ported from 7.2 and data in assets/items/items.json:
#  - loot from kills (killEnemy + lootDrop): XP, a purse of coins that flies to her, ammo, food, buffs, gear
#  - world pickups (PICK / scatterPickups / updatePickups / collect): cocktails, tavla sets, cigarettes,
#    glasses (+1 INT), simits, shells, ammo, weapons lying around, buff snacks; magnet, bob, 100 s respawn
#  - gear (RAR, SLOTS, GEARBASE, makeGear, equipGear, sellGear, gainGear, spawnGearDrop)
#  - the backpack of Turkish food (FOOD, addFood, eatFood, quickEat on H) and the timed buffs (BUFFS)
#  - the 50 hidden nazar beads (NZ_SPOTS, findNazar, NZREW) — found ones stay found (save `nz`)
#  - the 12 guarded chests (CHESTLOOT, chestInteract → keeper duel → chestWon); E via try_interact()
# Save fields are 7.2's: gear, eq, gu, bag, nz, lira, ammo, int, cigs, weap, dur, wi, mh, mm, ms, pp.
class_name Items
extends Node

static var me: Items
var D := {}
var W := {}                         # 7.2 WEAPONS (missions.json)
var world: Node3D
var player                          # Torii (player.gd)
var hud: Hud
var t := 0.0
var buffs := {}                     # buff id -> seconds left
var pickups: Array = []             # {node, type, base:Vector3, live, respawn, wait, ph, item, mission}
var coins: Array = []               # pooled {node, live, v, val, age, gy}
var nazars: Array = []              # {node, i, pos}
var chests: Array = []
var duel: Node3D = null             # the chest keeper she's fighting
var _cocktails: Array = []
var _wdrop_t := 12.0
var _regen_acc := 0.0
var _buff_box: VBoxContainer
var _mats := {}
var _ready_world := false
const MAGNET := 7.0
const COIN_MAGNET := 16.0
const SLOT_IDS := ["eye", "jew", "shoe", "bag", "bike"]

func setup(w: Node3D, p, h: Hud) -> void:
	me = self; world = w; player = p; hud = h
	D = Stats.data()
	W = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["weapons"]
	sanitize()
	Stats.apply(player)
	Bus.on("enemy_died", _on_kill)
	var cl := CanvasLayer.new(); cl.layer = 1; add_child(cl)
	_buff_box = VBoxContainer.new(); _buff_box.position = Vector2(706, 270); _buff_box.size = Vector2(240, 120)
	_buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; cl.add_child(_buff_box)
	# the world needs a physics frame before rays can find the ground
	await get_tree().physics_frame
	await get_tree().physics_frame
	_build_nazars()
	_scatter()
	for s in D["CHEST_SPOTS"]: _spawn_chest(float(s[0]), float(s[1]))
	_ready_world = true

# ---------------------------------------------------------------- save (7.2's loadExtra)
func sanitize() -> void:
	var d := SaveBridge.data
	var gb := {}
	for g in D["GEARBASE"]: gb[g["id"]] = true
	var gear: Array = []
	if d.get("gear") is Array:
		for it in d["gear"]:
			if it is Dictionary and gb.has(str(it.get("b", ""))) and it.get("st") is Dictionary:
				it["u"] = int(it.get("u", 0)); it["r"] = clampi(int(it.get("r", 0)), 0, 4); it["lv"] = maxi(1, int(it.get("lv", 1)))
				gear.append(it)
	var eq := {"eye": null, "jew": null, "shoe": null, "bag": null, "bike": null}
	if d.get("eq") is Dictionary:
		for k in d["eq"]: eq[k] = d["eq"][k]
	for k in eq:
		if eq[k] == null: continue
		var u := int(eq[k]); eq[k] = null
		for it in gear: if it["u"] == u: eq[k] = u
	var gu := SaveBridge.get_i("gu")
	for it in gear: gu = maxi(gu, int(it["u"]))
	var bag := {}
	if d.get("bag") is Dictionary:
		for k in d["bag"]:
			var n = d["bag"][k]
			if (n is int or n is float) and int(n) > 0: bag[k] = int(n)
	var nz: Array = []
	if d.get("nz") is Array:
		for i in d["nz"]:
			if (i is int or i is float) and int(i) >= 0 and int(i) < D["NZ_SPOTS"].size() and not nz.has(int(i)): nz.append(int(i))
	d["gear"] = gear; d["eq"] = eq; d["gu"] = gu; d["bag"] = bag; d["nz"] = nz

func _save() -> void: SaveBridge.write()
func _toast(s: String, secs := 5.0, bad := false) -> void: if hud: hud.toast(s, secs, bad)
func _banner(title: String, sub := "") -> void:
	if hud: hud.banner(title + ("\n[font_size=16]%s[/font_size]" % sub if sub != "" else ""))
func _sfx(n: String, at := Vector3.INF) -> void:
	var dd := {"name": n}
	if at != Vector3.INF: dd["pos"] = at
	Bus.emit_ev("sfx", dd)
func _teach(w: String) -> void: if Lessons.me: Lessons.me.teach(w)
func _lab(text: String, col: Color, life := 1.1, up := 2.7) -> void:
	if Fx.me and is_instance_valid(player): Fx.me.label(player.global_position + Vector3(0, up, 0), text, col, life)
func _alive() -> bool: return is_instance_valid(player) and not player.dead

func heal(n: int) -> void:
	if n <= 0 or not is_instance_valid(player): return
	if player.has_method("heal"): player.heal(n)
	else:
		player.hp = mini(player.max_hp, player.hp + n); player.hp_changed.emit(player.hp, player.max_hp)
func add_mana(n: float) -> void:
	if not is_instance_valid(player): return
	if player.has_method("add_mana"): player.add_mana(n)
	elif "mana" in player: player.mana = minf(float(player.max_mana), float(player.mana) + n)
func _hurt(n: int, kind: String) -> void:
	if is_instance_valid(player): player.take_hit(n, player.global_position, kind)

# ---------------------------------------------------------------- buffs (7.2's BUFFS / addBuff)
func add_buff(k: String) -> void:
	var B: Dictionary = D["BUFFS"].get(k, {})
	if B.is_empty(): return
	buffs[k] = float(B["dur"])
	_toast("%s [b]%s[/b] for %ds!" % [B["ic"], B["n"], int(B["dur"])], 5.0)
	_sfx("ding")
	if not is_instance_valid(player): return
	match k:
		"shield": if player.has_method("set_status"): player.set_status("shield", float(B["dur"]))
		_: _buff_mods()

func has_buff(k: String) -> bool: return float(buffs.get(k, 0.0)) > 0.0

func buff_list() -> Array:
	var out := []
	for k in buffs:
		var B: Dictionary = D["BUFFS"][k]
		out.append({"id": k, "ic": B["ic"], "n": B["n"], "left": float(buffs[k])})
	return out

# double damage / speed rush / caffeine reach the player as mods; regen, focus and luck are ours
func _buff_mods() -> void:
	if not is_instance_valid(player) or not player.has_method("set_mod"): return
	player.clear_mods("buff")
	if has_buff("dmg2"): player.set_mod("buff", "dmg", 2.0)
	var sp := 1.0
	if has_buff("spd"): sp *= 1.5
	if sp != 1.0: player.set_mod("buff", "speed", sp)
	if has_buff("caffeine"): player.set_mod("buff", "cd", .62)

func _buffs_tick(dt: float) -> void:
	var gone := false
	for k in buffs.keys():
		buffs[k] = float(buffs[k]) - dt
		if buffs[k] <= 0: buffs.erase(k); gone = true
	if gone: _buff_mods()
	if has_buff("regen") and _alive() and player.hp < player.max_hp:
		_regen_acc += 3.6 * dt                    # 7.2: +.06 HP a frame
		if _regen_acc >= 1.0:
			var n := int(_regen_acc); _regen_acc -= n
			player.hp = mini(player.max_hp, player.hp + n); player.hp_changed.emit(player.hp, player.max_hp)
	# the little #buffs list
	var want := buff_list()
	while _buff_box.get_child_count() < want.size():
		var l := Label.new(); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; l.custom_minimum_size = Vector2(240, 0)
		l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_color", Color("ffd66b"))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); l.add_theme_constant_override("outline_size", 5)
		_buff_box.add_child(l)
	for i in _buff_box.get_child_count():
		var l: Label = _buff_box.get_child(i)
		l.visible = i < want.size()
		if l.visible: l.text = "%s %s %ds" % [want[i]["ic"], want[i]["n"], ceili(want[i]["left"])]

# ---------------------------------------------------------------- gear
func rar_cap() -> int:
	var L := Stats.lvl()
	return 4 if L >= 30 else (3 if L >= 20 else (2 if L >= 5 else 1))

func base_of(it: Dictionary) -> Dictionary:
	for g in D["GEARBASE"]: if g["id"] == it.get("b"): return g
	return D["GEARBASE"][0]

func gear_name(it: Dictionary) -> String: return str(it["n"]) if it.has("n") else str(base_of(it)["tr"])
func gear_value(it: Dictionary) -> int: return int(round((10 + 6 * int(it["lv"])) * (1 + int(it["r"]) * 1.6)))
func rar_col(r: int) -> String: return str(D["RAR"][clampi(r, 0, 4)]["c"])

func eq_item(sl: String) -> Dictionary:
	var u = SaveBridge.data["eq"].get(sl)
	if u == null: return {}
	for it in SaveBridge.data["gear"]: if int(it["u"]) == int(u): return it
	return {}

func stat_txt(k: String, v: float) -> String:
	var N = D["STATN"].get(k)
	if N == null: return ""
	return ("+%d%%" % int(round(v * 100)) if N[2] == "%" else "+%d" % int(round(v))) + " " + str(N[1])

func _stat_roll(k: String, r: int, L: int) -> float:
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
		"bagx": return 1 + floorf(r / 1.5)
	return 0.0

func roll_rar(bonus := 0.0) -> int:
	var cap := rar_cap()
	var ws: Array[float] = []
	var tot := 0.0
	for i in 5:
		var w := 0.0 if i > cap else float(D["RAR"][i]["w"]) * pow(1.0 + bonus * 2.2, i)
		ws.append(w); tot += w
	var r := randf() * tot
	for i in 5:
		r -= ws[i]
		if r <= 0: return i
	return 0

# 7.2's makeGear(o): o may have b (base id), s (slot), r (rarity), lv, bonus, n (a special name)
func make_gear(o := {}) -> Dictionary:
	var B: Dictionary
	if o.has("b"): B = base_of({"b": o["b"]})
	else: B = (D["GEARBASE"] as Array).filter(func(g): return not o.has("s") or g["s"] == o["s"]).pick_random()
	var r := int(o["r"]) if o.has("r") else roll_rar(float(o.get("bonus", 0.0)))
	var L := maxi(1, int(round(float(o.get("lv", Stats.lvl())))))
	var st := {}
	st[B["p"]] = _stat_roll(B["p"], r, L)
	var sec: Array = (B["sec"] as Array).duplicate(); sec.shuffle()
	for k in sec.slice(0, [0, 1, 1, 2, 3][r]): st[k] = float(st.get(k, 0.0)) + _stat_roll(k, r, L) * randf_range(.55, .8)
	for k in st:
		if D["FLATST"].has(k): st[k] = maxi(1, int(round(st[k])))
		else: st[k] = round(float(st[k]) * 200.0) / 200.0
	var gu := SaveBridge.get_i("gu") + 1; SaveBridge.data["gu"] = gu
	var it := {"u": gu, "b": B["id"], "r": r, "lv": L, "st": st}
	if o.has("n"): it["n"] = o["n"]
	return it

# flat HP / mana / stamina live inside the stored maxima, so wearing adds them and taking off removes them
func _apply_flat(it: Dictionary, sg: int) -> void:
	if it.is_empty(): return
	var st: Dictionary = it["st"]
	if st.has("hp"):
		SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + sg * int(st["hp"])
		if is_instance_valid(player):
			player.max_hp = SaveBridge.get_i("mh", 100)
			player.hp = clampi(player.hp + (int(st["hp"]) if sg > 0 else 0), 1, player.max_hp)
	if st.has("mana"): SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + sg * int(st["mana"])
	if st.has("stam"): SaveBridge.data["ms"] = SaveBridge.get_i("ms", 100) + sg * int(st["stam"])

func equip_gear(u: int) -> void:
	var it := {}
	for g in SaveBridge.data["gear"]: if int(g["u"]) == u: it = g
	if it.is_empty(): return
	var sl: String = base_of(it)["s"]
	var old := eq_item(sl)
	if not old.is_empty() and int(old["u"]) == u: return
	_apply_flat(old, -1); SaveBridge.data["eq"][sl] = u; _apply_flat(it, 1)
	Stats.apply(player); _sfx("ding"); _save()

func unequip_gear(sl: String) -> void:
	var old := eq_item(sl)
	if old.is_empty(): return
	_apply_flat(old, -1); SaveBridge.data["eq"][sl] = null
	Stats.apply(player); _save()

func sell_gear(u: int, quiet := false) -> void:
	var it := {}
	for g in SaveBridge.data["gear"]: if int(g["u"]) == u: it = g
	if it.is_empty(): return
	var sl: String = base_of(it)["s"]
	var cur = SaveBridge.data["eq"].get(sl)
	if cur != null and int(cur) == u: unequip_gear(sl)
	SaveBridge.data["gear"] = (SaveBridge.data["gear"] as Array).filter(func(g): return int(g["u"]) != u)
	var v := gear_value(it); Stats.add_lira(v); _sfx("cash")
	if not quiet: _toast("💸 Sold [color=%s]%s[/color] for [b]%d₺[/b] · [i]satmak[/i] = to sell" % [rar_col(it["r"]), gear_name(it), v], 3.5)
	_save()

func sell_commons() -> int:
	var n := 0; var tot := 0
	var worn: Array = SaveBridge.data["eq"].values().filter(func(x): return x != null).map(func(x): return int(x))
	for g in (SaveBridge.data["gear"] as Array).duplicate():
		if int(g["r"]) == 0 and not worn.has(int(g["u"])):
			tot += gear_value(g); sell_gear(int(g["u"]), true); n += 1
	if n: _toast("💸 Sold [b]%d[/b] common piece%s for [b]%d₺[/b]" % [n, "" if n == 1 else "s", tot], 3.5)
	return n

func gain_gear(it: Dictionary, quiet := false) -> void:
	var gear: Array = SaveBridge.data["gear"]
	if gear.size() >= int(D["GEARMAX"]):
		var v := gear_value(it); Stats.add_lira(v); _sfx("cash")
		_toast("🎒 Gear bag full — sold [color=%s]%s[/color] for %d₺. Sell old pieces in the inventory [I]." % [rar_col(it["r"]), gear_name(it), v], 6.5, true)
		_save(); return
	gear.append(it)
	var B := base_of(it); var R: Dictionary = D["RAR"][int(it["r"])]
	var auto: bool = SaveBridge.data["eq"].get(B["s"]) == null      # an empty slot gets it straight away
	if auto: equip_gear(int(it["u"]))
	if not quiet:
		var sts := []
		for k in it["st"]: sts.append(stat_txt(k, float(it["st"][k])))
		_toast("%s [color=%s]%s[/color] · %s %s · Lv %d\n[font_size=14]%s[/font_size]\n%s" % [B["ic"], R["c"], gear_name(it), R["n"], B["en"], int(it["lv"]),
			" · ".join(sts), "[color=#5fff9e]✔ put on straight away[/color]" if auto else "press [b]I[/b] to compare"], 7.0)
		if int(it["r"]) >= 3: _banner("%s %s!" % [B["ic"], R["n"]], gear_name(it)); _sfx("divine")
		else: _sfx("ding")
		LevelUp.queue_tip("gear")
	_save()

# ---------------------------------------------------------------- the backpack
func bag() -> Dictionary: return SaveBridge.data["bag"]
func bag_cap() -> int:
	var L := Stats.lvl()
	return 8 + (4 if L >= 5 else 0) + (4 if L >= 20 else 0) + int(Stats.gear_stat("bagx"))
func bag_used() -> int: return bag().keys().filter(func(k): return int(bag()[k]) > 0).size()

func add_food(k: String, n := 1) -> bool:
	if not D["FOOD"].has(k): return false
	var have := int(bag().get(k, 0))
	if have >= int(D["STACK"]): return false
	if have == 0 and bag_used() >= bag_cap(): return false
	bag()[k] = mini(int(D["STACK"]), have + n)
	return true

func food_desc(k: String) -> String:
	var F: Dictionary = D["FOOD"][k]; var o := []
	if F.has("heal"): o.append("heals %d%% HP" % int(round(float(F["heal"]) * 100 * Stats.stat("food"))))
	if F.has("stam"): o.append("full stamina" if float(F["stam"]) >= 1 else "+half stamina")
	if F.has("mana"): o.append("+%d mana" % int(F["mana"]))
	if F.has("buff") and D["BUFFS"].has(F["buff"]):
		var B: Dictionary = D["BUFFS"][F["buff"]]; o.append("%s %s" % [B["ic"], str(B["n"]).to_lower()])
	return " · ".join(o)

func eat_food(k: String) -> bool:
	var F: Dictionary = D["FOOD"].get(k, {})
	if F.is_empty() or int(bag().get(k, 0)) <= 0 or not _alive(): return false
	bag()[k] = int(bag()[k]) - 1
	if int(bag()[k]) <= 0: bag().erase(k)
	if F.has("heal"):
		heal(int(round(player.max_hp * float(F["heal"]) * Stats.stat("food"))))
		if Fx.me: Fx.me.flash("heal")
	if F.has("stam") and "stamina" in player:
		player.stamina = minf(float(player.max_stamina), float(player.stamina) + float(player.max_stamina) * float(F["stam"]))
		if "winded" in player: player.winded = false
	if F.has("mana"): add_mana(float(F["mana"]))
	if F.has("buff"): add_buff(F["buff"])
	_sfx("eat")
	_lab("%s Afiyet olsun!" % F["ic"], Color("ffd66b"), 1.3, 2.9)
	_teach(str(F.get("w", F["tr"])))
	_save()
	return true

# H: the smallest snack that heals what she's missing; a stamina drink when she's out of breath
func quick_eat() -> void:
	if not _alive(): return
	var miss: float = 1.0 - float(player.hp) / float(maxi(1, player.max_hp))
	var have: Array = bag().keys().filter(func(k): return int(bag()[k]) > 0 and D["FOOD"].has(k))
	if have.is_empty():
		_toast("🎒 [b]Çantan boş[/b] — no food in your backpack. Buy some at [b]Five Sips ☕[/b], or pick it up off monsters.", 4.5, true)
		_sfx("no"); return
	var food: Dictionary = D["FOOD"]
	var heals: Array = have.filter(func(k): return food[k].has("heal"))
	heals.sort_custom(func(a, b): return float(food[a]["heal"]) < float(food[b]["heal"]))
	if miss < .05:
		var st = null
		for k in have: if food[k].has("stam"): st = k; break
		if st != null and "stamina" in player and float(player.stamina) < float(player.max_stamina) * .5: eat_food(st); return
		_toast("😋 [b]Tokum![/b] [i](I'm full)[/i] — your HP is already full. [i]tok[/i] = full, [i]aç[/i] = hungry.", 3.5)
		_teach("tok"); return
	if heals.is_empty(): eat_food(have[0]); return
	var pick: String = heals[heals.size() - 1]
	for k in heals:
		if float(food[k]["heal"]) * Stats.stat("food") >= miss: pick = k; break
	eat_food(pick)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_H and not Overlay.any():
		quick_eat(); get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- weapons on the ground
func roll_weapon() -> String:
	if Arsenal.me: return Arsenal.me.roll_weapon()
	var tot := 0.0
	for k in W: tot += float(W[k].get("w", 0))
	var r := randf() * tot
	for k in W:
		r -= float(W[k].get("w", 0))
		if float(W[k].get("w", 0)) > 0 and r <= 0: return k
	return "oklava"

func _dps(id: String) -> float:
	var w: Dictionary = W.get(id, W["kick"])
	return float(w["dmg"]) / maxf(.05, float(w["cd"]))

# 7.2's giveWeapon(): add it (fresh durability), and hold it if it's her hardest hitter. Arsenal owns
# weapons when it's running; this is the fallback.
func give_weapon(id: String) -> void:
	if not W.has(id): return
	if Arsenal.me: Arsenal.me.give_weapon(id); return
	var weap: Array = SaveBridge.data.get("weap", ["katana"])
	if not weap.has(id): weap.append(id)
	SaveBridge.data["weap"] = weap
	var dur: Dictionary = SaveBridge.data.get("dur", {})
	var dv = W[id].get("dur")
	dur[id] = 9999 if dv == null else dv
	SaveBridge.data["dur"] = dur
	var cur: String = player.weapon.get("id", "kick") if is_instance_valid(player) else "kick"
	var n: String = W[id]["n"]
	if _dps(id) > _dps(cur):
		SaveBridge.data["wi"] = weap.find(id)
		if is_instance_valid(player): player.equip(id)
		_toast("🆕 [b]%s[/b] — equipped, it's your best DPS. 💥%d dmg" % [n, int(W[id]["dmg"])], 6.0)
	else:
		_toast("🆕 Picked up [b]%s[/b] (%d DPS) — keeping [b]%s[/b]. [b]Q[/b] to switch." % [n, int(_dps(id)), W.get(cur, W["kick"])["n"]], 6.0)
	_save()

# ---------------------------------------------------------------- models
func _mat(c: Color, unshaded := false, alpha := 1.0, add := false, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [c.to_html(), unshaded, alpha, add, emit]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new(); m.albedo_color = Color(c, alpha)
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0 or add: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if add: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.no_depth_test = false; m.disable_fog = true
	if emit > 0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

func _mi(parent: Node3D, mesh: Mesh, mat: Material, at := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new(); m.mesh = mesh; m.material_override = mat; m.position = at; m.rotation = rot
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(m); return m

func _cyl(top: float, bot: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bot; c.height = h; c.radial_segments = seg; c.rings = 1; return c
func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b
func _torus(r: float, w: float) -> TorusMesh:
	var t2 := TorusMesh.new(); t2.inner_radius = r - w; t2.outer_radius = r + w; t2.rings = 12; t2.ring_segments = 5; return t2

func _octa(s: float) -> ArrayMesh:
	var v := [Vector3(0, s, 0), Vector3(s, 0, 0), Vector3(0, 0, s), Vector3(-s, 0, 0), Vector3(0, 0, -s), Vector3(0, -s, 0)]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = v[1 + i]; var b: Vector3 = v[1 + (i + 1) % 4]
		for tri in [[v[0], b, a], [v[5], a, b]]:
			for p in tri: st.add_vertex(p)
	st.generate_normals()
	return st.commit()

const GLB := ["avocado", "baklava", "borek", "cay", "doner", "flower", "fruit", "nazar", "pena", "photo", "shell", "simit", "tote"]
func _model(type: String) -> Node3D:
	var g := Node3D.new()
	if GLB.has(type):
		var n: Node3D = load("res://assets/pickups/%s.glb" % type).instantiate(); Tint.apply(n); g.add_child(n); return g
	if W.has(type):
		var path := "res://assets/weapons/%s.glb" % type
		if ResourceLoader.exists(path):
			var wn: Node3D = load(path).instantiate(); Tint.apply(wn); wn.rotation.z = .7; g.add_child(wn); return g
	match type:
		"cocktail":
			_mi(g, _cyl(.34, 0.0, .5, 6), _mat(Color("ff5fa2"), false, 1.0, false, .4), Vector3(0, .25, 0))
			_mi(g, _cyl(.04, .04, .42, 4), _mat(Color("ffe9fb")), Vector3(0, -.1, 0))
			var s := SphereMesh.new(); s.radius = .09; s.height = .18; s.radial_segments = 5; s.rings = 3
			_mi(g, s, _mat(Color("ff2d5e"), true), Vector3(.18, .55, 0))
		"tavla":
			_mi(g, _box(.7, .12, .5), _mat(Color("7a4a2b")))
			_mi(g, _box(.72, .05, .1), _mat(Color("ffd66b"), true), Vector3(0, .07, 0))
		"glasses":
			for dx in [-.2, .2]: _mi(g, _torus(.16, .04), _mat(Color("7bf7ff"), true), Vector3(dx, 0, 0), Vector3(PI / 2, 0, 0))
			_mi(g, _box(.12, .03, .03), _mat(Color("7bf7ff"), true))
		"cig":
			_mi(g, _cyl(.05, .05, .6, 5), _mat(Color("f2f2f2")), Vector3.ZERO, Vector3(0, 0, PI / 2))
			_mi(g, _cyl(.055, .055, .1, 5), _mat(Color("ff6a2d"), true), Vector3(.3, 0, 0), Vector3(0, 0, PI / 2))
		"ammo":
			for i in 3: _mi(g, _box(.5, .07, .26), _mat(Color("6fd08a")), Vector3(0, i * .08 - .08, 0), Vector3(0, i * .3, 0))
			_mi(g, _box(.1, .26, .28), _mat(Color("ffd66b"), true))
		"lokum":
			for i in 3: _mi(g, _box(.2, .2, .2), _mat(Color("ffa8d0")), Vector3((i - 1) * .24, 0, 0), Vector3(0, i * .5, 0))
		"matcha", "coffee", "ayran":
			var c: Color = {"matcha": Color("7fc96b"), "coffee": Color("6b3a1f"), "ayran": Color("f4f6ff")}[type]
			_mi(g, _cyl(.2, .16, .34, 8), _mat(c), Vector3(0, .05, 0))
			_mi(g, _cyl(.21, .21, .06, 8), _mat(Color("7bf7ff") if type == "ayran" else Color("f4f6ff"), true), Vector3(0, .1, 0))
		_:
			_mi(g, _octa(.25), _mat(Color("ffd66b"), false, 1.0, false, .4))
	return g

# ---------------------------------------------------------------- pickups in the world
func _ground(x: float, z: float) -> float:
	if not world: return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	if is_instance_valid(player): q.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else 0.0

func _wet(x: float, z: float) -> bool:
	if is_instance_valid(player) and "water" in player:
		for r in player.water: if x > r[0] and x < r[1] and z > r[2] and z < r[3]: return true
	return false

# a street-level dry spot near (x, z): roofs and water don't count (7.2 shoved things out of buildings)
func _street(x: float, z: float, spread := 0.0) -> Vector3:
	for i in 12:
		var r := spread if i == 0 else maxf(spread, 6.0)
		var px := x + (randf_range(-r, r) if r > 0 else 0.0)
		var pz := z + (randf_range(-r, r) if r > 0 else 0.0)
		var y := _ground(px, pz)
		if y < 1.6 and not _wet(px, pz): return Vector3(px, y, pz)
	return Vector3(x, _ground(x, z), z)

func spawn_pickup(type: String, at: Vector3, respawn := 100.0, mission := false) -> Dictionary:
	# weapons lying around and loot ammo are Arsenal's pickups (it gives, repairs and counts them)
	if Arsenal.me and W.has(type) and respawn <= 0.0 and not mission: Arsenal.me.drop_weapon(type, at); return {}
	var g := _model(type)
	var disc := _mi(g, _cyl(.5, .5, .04, 10), _mat(Color("ff3b3b") if type == "cig" else Color("ff9ecf"), true, .32), Vector3(0, -.85, 0))
	disc.name = "disc"
	world.add_child(g); g.position = at + Vector3(0, 1.15, 0)
	var p := {"node": g, "type": type, "base": at, "live": true, "respawn": respawn, "wait": 0.0, "ph": randf() * 6.0, "mission": mission}
	pickups.append(p)
	return p

func spawn_gear_drop(at: Vector3, it: Dictionary) -> void:
	var col := Color(rar_col(int(it["r"])))
	var g := Node3D.new()
	_mi(g, _octa(.34), _mat(Color(str(base_of(it).get("col", "#ffffff"))).lerp(col, .4), false, 1.0, false, .35))
	_mi(g, _cyl(.07, .16, 9, 6), _mat(col, true, .42, true), Vector3(0, 3.6, 0))
	_mi(g, _torus(.6, .05), _mat(col, true), Vector3(0, -.85, 0))
	world.add_child(g); g.position = at + Vector3(0, 1.15, 0)
	pickups.append({"node": g, "type": "gear", "item": it, "base": at, "live": true, "respawn": 0.0, "wait": 0.0, "ph": randf() * 6.0, "mission": false})

# 7.2's scatterPickups()
func _scatter() -> void:
	for i in 9: spawn_pickup("cocktail", _street(randf_range(86, 146), randf_range(-90, 90)))
	for i in 3: spawn_pickup("cocktail", _street([-60, -20, 20].pick_random() + randf_range(-12, 12), [-20, 20].pick_random() + randf_range(-12, 12)))
	for i in 5: spawn_pickup("tavla", _street([-100, -60, -20, 20, 60].pick_random() + randf_range(-13, 13), [-100, -60, -20, 20, 60].pick_random() + randf_range(-13, 13)))
	for i in 5: spawn_pickup("cig", _street([-110, -70, -30, 10, 50].pick_random() + randf_range(-4, 4), [-70, -30, 10, 50].pick_random() + randf_range(-4, 4)))
	for i in 3: spawn_pickup("glasses", _street([-90, -50, 30, 70].pick_random() + randf_range(-8, 8), [-90, 10, 70].pick_random() + randf_range(-8, 8)), 0.0)
	for i in 4: spawn_pickup("simit", _street(-100 + randf_range(-14, 14), 30 + randf_range(-6, 14)))
	for i in 6: spawn_pickup("shell", _street(randf_range(108, 148), randf_range(-120, 120)))
	spawn_pickup("ammo", _street(-104, -96), 0.0)
	spawn_pickup("ammo", _street(30, 116), 0.0)
	for i in 6: spawn_pickup(roll_weapon(), _street(randf_range(-192, 146), randf_range(-192, 168)), 0.0)
	for i in 3:
		var s: Array = D["WSPOTS"].pick_random()
		spawn_pickup("nazar", _street(float(s[0]) + randf_range(-6, 6), float(s[1]) + randf_range(-6, 6)), 0.0)
	spawn_pickup("baklava", _street(-140, 60), 0.0)
	spawn_pickup("cay", _street(20, 26), 0.0)
	spawn_pickup("lokum", _street(-186, 100), 0.0)

# 7.2's weaponDirector(): every 26-46 s a weapon turns up somewhere away from her (up to 7 lying around)
func _weapon_director(dt: float) -> void:
	if Arsenal.me: return                   # Arsenal runs its own (same rules)
	_wdrop_t -= dt
	if _wdrop_t > 0 or not is_instance_valid(player) or player.global_position.x > 400: return
	_wdrop_t = randf_range(26, 46)
	if pickups.filter(func(p): return p["live"] and W.has(p["type"])).size() >= 7: return
	for i in 20:
		var x := randf_range(-192, 146); var z := randf_range(-192, 168)
		if Vector2(x - player.global_position.x, z - player.global_position.z).length() < 30: continue
		var y := _ground(x, z)
		if y > 1.6 or _wet(x, z): continue
		spawn_pickup(roll_weapon(), Vector3(x, y, z), 0.0); return

func _pickups_tick(dt: float) -> void:
	var pp: Vector3 = player.global_position
	var on_bike: bool = player.on_bike
	var pr := MAGNET * Stats.stat("magnet")
	for p in pickups.duplicate():
		var g: Node3D = p["node"]
		if not p["live"]:
			p["wait"] += dt
			if p["wait"] > p["respawn"]: p["live"] = true; p["wait"] = 0.0; g.visible = true
			continue
		g.rotation.y += dt * 2.6
		var base: Vector3 = p["base"]
		g.position.y = base.y + 1.15 + sin(t * 2.2 + p["ph"]) * .16
		var dx: float = g.position.x - pp.x; var dz: float = g.position.z - pp.z
		var d2 := dx * dx + dz * dz
		var harmful: bool = p["type"] == "cig"          # cigarettes never fly to her: she has to want one
		if not harmful and d2 < pr * pr and d2 > 2.0 and absf(base.y - pp.y) < 3.0:
			var d := sqrt(d2); var step := minf(9.0, (pr - d) * 2.2) * dt
			g.position.x -= dx / d * step; g.position.z -= dz / d * step
			p["base"] = Vector3(g.position.x, base.y, g.position.z)
		var grab := 1.1 if harmful else (5.6 if on_bike else 2.6)
		if d2 < grab and absf(g.position.y - 1.15 - pp.y) < 2.4: _collect(p)

func _collect(p: Dictionary) -> void:
	p["live"] = false; p["wait"] = 0.0
	var g: Node3D = p["node"]; g.visible = false
	var T: String = p["type"]
	var at: Vector3 = g.global_position
	if p["respawn"] <= 0.0: pickups.erase(p); g.queue_free()
	Bus.emit_ev("pickup", {"id": T, "kind": "gear" if T == "gear" else ("weapon" if W.has(T) else "item"), "pos": at})
	_sfx("pickup", at)
	if Fx.me: Fx.me.puff(at, [Color("ff9ecf"), Color("ffd66b"), Color("7bf7ff")], 8, 1.2, 1.8, .6)
	if T == "gear": gain_gear(p["item"]); return
	var fk = D["FOODPICK"].get(T)
	if fk != null and not p["mission"] and add_food(fk, 1):
		var F: Dictionary = D["FOOD"][fk]
		_lab("+1 %s %s" % [F["ic"], F["tr"]], Color("ffe08a"))
		_toast("%s [b]%s[/b] [i](%s)[/i] → backpack · [b]H[/b] to eat (%d)" % [F["ic"], F["tr"], F["en"], int(bag()[fk])], 3.5)
		_teach(str(F.get("w", F["tr"]))); LevelUp.queue_tip("bag"); Stats.gain_xp(3)
		_save(); return
	effect(T)
	_save()

# what a pickup does when it isn't stored (7.2's collect() branches). Missions can call this for their
# story items too (simit, shell, avocado, döner, pena, börek, tote, flower, fruit, photo, baklava, çay, nazar).
func effect(T: String) -> void:
	match T:
		"cocktail":
			var now := t
			_cocktails.append(now); _cocktails = _cocktails.filter(func(c): return now - c < 25.0)
			_teach("kokteyl")
			if _cocktails.size() >= 4:
				_cocktails.clear(); _sfx("cough")
				if player.has_method("set_status"): player.set_status("slow", 9.0)
				_hurt(15, "drunk")
				_toast("🍹🍹🍹 TOO MANY COCKTAILS! Turkish: [b]çok fazla[/b] = too much! (-15)", 5.0, true)
			else: heal(12); _sfx("heal"); Stats.gain_xp(2)
		"tavla": add_mana(20); _teach("tavla"); _sfx("ding"); Stats.gain_xp(2)
		"glasses":
			SaveBridge.data["int"] = SaveBridge.get_i("int") + 1; _teach("gözlük"); _sfx("ding"); _sfx("chuckle")
			_toast("👓 +1 INT! Turkish: [b]zeka[/b] = intelligence · XP bonus +8%"); Stats.gain_xp(4)
		"cig":
			_teach("sigara"); _sfx("cough"); Stats.gain_xp(3)
			add_mana(25); SaveBridge.data["cigs"] = SaveBridge.get_i("cigs") + 1
			_lab("+25 MANA", Color("8ff2ff"), 1.2, 3.0); _lab("−28 HP 🚬", Color("ff3b3b"), 1.4, 3.6)
			_hurt(28, "smoke")
			var c := SaveBridge.get_i("cigs")
			_toast("🚬 [b]SİGARA · +25 mana, −28 HP.[/b] [i]\"Sigara içen insan, sağlıklı insandır.\"[/i] — Mert. (He is wrong. [b]sağlığa zararlı[/b] = harmful to health.)" +
				("\nThat is %d of them. [i]Öksürüyorsun.[/i] You are coughing." % c if c > 4 else ""), 7.0, true)
		"simit": heal(6); _teach("simit"); _sfx("heal"); Stats.gain_xp(3)
		"shell": _teach("deniz kabuğu"); _sfx("ding"); Stats.gain_xp(6)
		"avocado": _teach("avokado"); _sfx("ding"); Stats.gain_xp(2)
		"doner": _teach("döner"); _sfx("heal"); heal(8)
		"pena": _teach("pena"); _sfx("ding"); Stats.gain_xp(4)
		"borek": heal(15); _teach("börek"); _sfx("heal")
		"ammo":
			SaveBridge.data["ammo"] = SaveBridge.get_i("ammo") + 3; _sfx("cash")
			_toast("💵 [b]+3 bill stacks[/b] (Bill Box ammo)", 4.5)
		"tote": _teach("çanta"); _sfx("ding")
		"flower": _teach("çiçek"); _sfx("ding")
		"fruit": heal(8); _teach("kaktüs"); _sfx("heal")
		"photo": _teach("fotoğraf"); _sfx("ding")
		"bone": _teach("kemik"); _sfx("ding")
		"baklava": add_buff("dmg2"); _teach("baklava"); Stats.gain_xp(8); heal(10)
		"cay": add_buff("spd"); _teach("çay"); Stats.gain_xp(8)
		"lokum": add_buff("regen"); _teach("lokum"); Stats.gain_xp(8)
		"nazar": add_buff("shield"); _teach("nazar boncuğu"); Stats.gain_xp(10)
		"matcha":
			add_buff("focus"); _teach("matcha"); Stats.gain_xp(20); add_mana(30)
			_toast("🍵 [b]MATCHA[/b] — Old Soul's finest. +30 mana, double XP for 45s 🧠", 6.5)
		"coffee":
			add_buff("caffeine"); _teach("kahve"); Stats.gain_xp(20); heal(20)
			_toast("☕ [b]COFFEE[/b] — five sips, properly made. +20 HP, faster attacks for 30s ⚡", 6.5)
		_:
			if W.has(T):
				give_weapon(T)
				_banner("⚔️ %s!" % W[T]["n"], "%s weapon found!" % W[T].get("rar", ""))
				_sfx("weapon"); Stats.gain_xp(15)
				var tw := {"sis": "şiş", "balta": "balta", "zeybek": "kılıç", "oklava": "oklava", "nazarw": "nazar boncuğu"}
				if tw.has(T): _teach(tw[T])

# ---------------------------------------------------------------- coins (dropCoins / updateCoins)
func drop_coins(at: Vector3, total: int, n := 2) -> void:
	n = clampi(n, 1, 9)
	var each := maxi(1, int(round(float(total) / n)))
	for i in n:
		var c = null
		for x in coins: if not x["live"]: c = x; break
		if c == null:
			var g := Node3D.new(); world.add_child(g)
			_mi(g, _cyl(.26, .26, .07, 10), _mat(Color("ffd24a"), false, 1.0, false, .3), Vector3.ZERO, Vector3(PI / 2, 0, 0))
			c = {"node": g, "live": false}; coins.append(c)
		var a := randf() * TAU
		var gy := _ground(at.x, at.z)
		c["live"] = true; c["val"] = each; c["age"] = 0.0; c["gy"] = gy
		c["node"].visible = true; c["node"].global_position = Vector3(at.x, gy + 1.2, at.z)
		c["v"] = Vector3(cos(a) * randf_range(2.5, 5.5), randf_range(4, 6.5), sin(a) * randf_range(2.5, 5.5))

func _coins_tick(dt: float) -> void:
	var pp: Vector3 = player.global_position
	var mr := COIN_MAGNET * Stats.stat("magnet")
	for c in coins:
		if not c["live"]: continue
		c["age"] += dt
		var g: Node3D = c["node"]; g.rotation.y += dt * 7.0
		var v: Vector3 = c["v"]
		var dx := pp.x - g.position.x; var dz := pp.z - g.position.z
		var d := sqrt(dx * dx + dz * dz)
		if c["age"] > .35 and d < mr and not player.dead:       # magnetised once it has settled
			var pull := minf(34.0, 7.0 + (mr - d) * 2.4)
			v.x += dx / maxf(d, .01) * pull * dt * 3.2; v.z += dz / maxf(d, .01) * pull * dt * 3.2
			v.y += ((pp.y + 1.2) - g.position.y) * 9.0 * dt
			v *= .93
		else:
			v.y -= 17.0 * dt
			if g.position.y <= float(c["gy"]) + .3 and v.y < 0: v.y = -v.y * .45; v.x *= .6; v.z *= .6
		c["v"] = v
		g.position += v * dt
		# (7.2 let a coin vanish after 9 s; here she keeps it)
		if d < 1.4 or c["age"] > 9.0:
			var val := int(round(float(c["val"]) * (1.0 + Stats.stat("lira"))))
			Stats.add_lira(val); _sfx("coin")
			_lab("+%d₺" % val, Color("ffd66b"), .7, 2.6)
			c["live"] = false; g.visible = false

# ---------------------------------------------------------------- kills (killEnemy + lootDrop)
# d = {enemy, pos, kind, elite, xp, boss, mini, level, lira, roam}. enemy.gd's _die() already pays the
# base XP (through Lessons, which saves a level-up right away = CRT-01), the kill count and the mini-boss
# purse; here: the XP bonuses (ÇALIŞKAN, gear, matcha), the coins, the loot, ŞİFALI VURUŞ.
func _on_kill(d: Dictionary) -> void:
	if not world: return
	var at: Vector3 = d.get("pos", Vector3.ZERO)
	var e = d.get("enemy")
	var elite: bool = d.get("elite", false)
	var boss: bool = d.get("boss", false)
	var mini: bool = d.get("mini", false) or (is_instance_valid(e) and "flags" in e and e.flags.has("mini"))
	var kind: String = str(d.get("kind", ""))
	var luck := 1.0 + Stats.stat("luck")
	var xp := int(d.get("xp", 0))
	if Lessons.me: Stats.gain_xp(Stats.xp_bonus(xp), Vector3.INF, true)      # the base XP is paid already
	else: Stats.gain_xp(xp, at + Vector3(0, 3.1, 0))
	if Stats.pk("sifa") > 0 and _alive(): heal(int(round(player.max_hp * .02 * Stats.pk("sifa"))))
	# lira flies to her (7.2: 6-18, elites 40-60)
	var purse := int(d.get("lira", randi_range(40, 60) if elite else randi_range(6, 18)))
	drop_coins(at, purse, 4 if elite or mini or boss else 2)
	if randf() < (1.0 if boss else (.5 if elite else .07)): _drop_ammo(_street(at.x, at.z, 1.0))
	if randf() < .035 * luck: spawn_pickup(["baklava", "cay", "lokum", "nazar"].pick_random(), _street(at.x, at.z, .5), 0.0)
	# gear: 3% normal, 30% elite, always from a boss or a mini-boss (× luck)
	var ch := 1.0 if (boss or mini) else (.3 if elite else .03)
	if randf() < ch * luck:
		var lv := int(d.get("level", e.level if is_instance_valid(e) and "level" in e else Stats.lvl()))
		spawn_gear_drop(_street(at.x, at.z, .6), make_gear({"lv": lv, "bonus": .9 if boss else (.6 if mini else (.3 if elite else 0.0))}))
	if randf() < .05 * luck: spawn_pickup(["simit", "simit", "ayran", "doner", "borek"].pick_random(), _street(at.x, at.z, 1.0), 0.0)
	var r := randf()
	if kind == "zombie" and r < .45: spawn_pickup("cocktail" if r < .25 else "tavla", _street(at.x, at.z, .3), 0.0)
	elif kind == "imp" and r < .14: spawn_pickup("cocktail", _street(at.x, at.z, .3), 0.0)
	elif kind == "thot" and r < .3: spawn_pickup("cocktail", _street(at.x, at.z, .3), 0.0)
	elif kind == "ghost" and r < .25: spawn_pickup("tavla", _street(at.x, at.z, .3), 0.0)
	if mini:                                # (enemy.gd already paid the 120-260₺ and played the fanfare)
		spawn_pickup(roll_weapon(), _street(at.x, at.z, .5), 0.0)
		_drop_ammo(_street(at.x + 1.5, at.z, .3))

func _drop_ammo(at: Vector3) -> void:
	if Arsenal.me: Arsenal.me.drop_ammo(at, 3)
	else: spawn_pickup("ammo", at, 0.0)

# ---------------------------------------------------------------- the 50 hidden nazar beads
func found(i: int) -> bool: return (SaveBridge.data["nz"] as Array).has(i)

func _build_nazars() -> void:
	var beam_m := _mat(Color("4fb4ff"), true, .22, true)
	var beam := _cyl(.05, .22, 26, 6)
	var scene: PackedScene = load("res://assets/pickups/nazar.glb")
	for i in D["NZ_SPOTS"].size():
		var s: Array = D["NZ_SPOTS"][i]
		var x := float(s[0]); var z := float(s[1])
		var y := _ground(x, z)
		var g := Node3D.new(); world.add_child(g)
		var bead: Node3D = scene.instantiate(); Tint.apply(bead); bead.name = "bead"; g.add_child(bead)
		_mi(g, beam, beam_m, Vector3(0, 13, 0))
		g.position = Vector3(x, y + 1.3, z); g.visible = false
		nazars.append({"node": g, "i": i, "pos": Vector3(x, y, z)})

func _nazars_tick(dt: float) -> void:
	var pp: Vector3 = player.global_position
	for o in nazars:
		var g: Node3D = o["node"]
		if found(o["i"]):
			if g.visible: g.visible = false
			continue
		var at: Vector3 = o["pos"]
		var d2 := Vector2(at.x - pp.x, at.z - pp.z).length_squared()
		g.visible = d2 < 120 * 120
		if not g.visible: continue
		g.get_node("bead").rotation.y += dt * 1.6
		g.position.y = at.y + 1.3 + sin(t * 2 + o["i"]) * .18
		if d2 < 3.2 and absf(pp.y - at.y) < 2.2: find_nazar(o)

func find_nazar(o: Dictionary) -> void:
	var i: int = o["i"]
	if found(i): return
	(SaveBridge.data["nz"] as Array).append(i); o["node"].visible = false
	var n: int = (SaveBridge.data["nz"] as Array).size()
	var L: Array = D["NZLINES"][(n - 1) % D["NZLINES"].size()]
	var reg: String = D["NZ_SPOTS"][i][2]
	var left := 0
	for j in D["NZ_SPOTS"].size(): if D["NZ_SPOTS"][j][2] == reg and not found(j): left += 1
	_sfx("divine"); _sfx("coin")
	if Fx.me: Fx.me.puff(o["pos"] + Vector3(0, 1.3, 0), [Color("1f6fd0"), Color("f4f8ff"), Color("4fb4ff")], 22, 1.8, 2.4, 1.0)
	Stats.gain_xp(25); Stats.add_lira(15)
	_banner("🧿 GİZLİ NAZAR · %d/50" % n, "\"%s\" — %s" % [L[0], L[1]])
	_toast("🧿 [b]Hidden nazar %d/50[/b] · %s%s\n[color=#ffd66b]%s[/color] [i](%s)[/i] · +15₺" % [n, D["NZREG"][reg],
		(" — %d more hidden here" % left) if left else " — all found here! ✅", L[0], L[1]], 8.0)
	LevelUp.queue_tip("nazar")
	_nz_reward(n)
	Stats.apply(player)                     # 30 beads = +8% damage
	_save()

func _nz_reward(n: int) -> void:
	var R := {}
	for x in D["NZREW"]: if int(x["n"]) == n: R = x
	if R.is_empty(): return
	match n:
		10:
			SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + 50
			player.max_hp = SaveBridge.get_i("mh", 100); heal(50)
		20: gain_gear(make_gear({"b": "aviator", "r": 3, "n": "Nazar Gözü"}))
		40: gain_gear(make_gear({"b": "nazark", "r": 4, "n": "Mavi Boncuk"}))
		50:
			Stats.add_lira(5000); SaveBridge.data["pp"] = SaveBridge.get_i("pp") + 3
			if LevelUp.me: LevelUp.me.perk_auto_t = 2.5
	await get_tree().create_timer(1.8).timeout
	_banner("🧿 %d NAZAR!" % n, "Ödül: " + str(R["t"]))
	_toast("🏆 [b]%d hidden nazars found![/b] Reward: [b]%s[/b]" % [n, R["t"]], 10.0)
	_sfx("fanfare")

# ---------------------------------------------------------------- guarded chests
func _spawn_chest(x: float, z: float) -> void:
	var at := _street(x, z)
	var g := Node3D.new(); world.add_child(g); g.position = at
	var wood := _mat(Color("6b4a2f")); var iron := _mat(Color("8a8a95")); var gold := _mat(Color("ffd24a"), false, 1.0, false, .5)
	_mi(g, _box(1.7, .95, 1.15), wood, Vector3(0, .48, 0))
	var lid := Node3D.new(); lid.position = Vector3(0, .95, -.575); g.add_child(lid)
	_mi(lid, _box(1.7, .32, 1.15), wood, Vector3(0, .16, .575))
	_mi(lid, _box(1.74, .06, 1.19), iron, Vector3(0, .32, .575))
	for s in [-1, 1]: _mi(g, _box(.13, 1.0, 1.2), iron, Vector3(s * .55, .48, 0))
	var lock := _mi(g, _box(.3, .34, .16), gold, Vector3(0, .82, .6))
	var gm := _mat(Color("ffd24a"), true, .25, true).duplicate() as StandardMaterial3D
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var glow := _mi(g, QuadMesh.new(), gm, Vector3(0, 1.1, 0)); glow.scale = Vector3.ONE * 3.2
	var lab := Label3D.new(); lab.text = "🔒 KİLİTLİ — [E]"; lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color("ffd24a"); lab.outline_modulate = Color(0, 0, 0, .9); lab.font_size = 40; lab.outline_size = 10
	lab.pixel_size = .008; lab.position = Vector3(0, 2.9, 0); lab.no_depth_test = true; g.add_child(lab)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(2.0, 1.3, 1.5)
	cs.shape = bs; cs.position.y = .65; body.add_child(cs); g.add_child(body)
	chests.append({"g": g, "lid": lid, "lock": lock, "sign": lab, "x": at.x, "z": at.z, "open": false, "keeper": null,
		"loot": _pick_loot(), "typ": D["CHEST_KEEPERS"].pick_random()})

func _pick_loot() -> Dictionary:
	var tot := 0.0
	for L in D["CHESTLOOT"]: tot += float(L["w"])
	var r := randf() * tot
	for L in D["CHESTLOOT"]:
		r -= float(L["w"])
		if r <= 0: return L
	return D["CHESTLOOT"][0]

func _chest_near() -> Dictionary:
	if not is_instance_valid(player): return {}
	for c in chests:
		if c["open"] or c["keeper"] != null: continue
		if Vector2(c["x"] - player.global_position.x, c["z"] - player.global_position.z).length_squared() < 12.0: return c
	return {}

# main's E dispatcher asks this first: true = E was used on a chest
func try_interact(_p = null) -> bool:
	var c := _chest_near()
	if c.is_empty() or not hud: return false
	if is_instance_valid(duel):
		_toast("⚔️ Finish the keeper you already woke up first.", 3.5, true); return true
	var kn := str(Enemy.DATA.get(c["typ"], {}).get("name", "something")) if not Enemy.DATA.is_empty() else "something"
	hud.choose("🔒 KİLİTLİ SANDIK", "A heavy chest with a bad lock and a worse smell around it.\nSomething is standing over it — [b]%s[/b], and a big one. Break the lock and it will want a fair fight: just you and it.\nBandit will keep everything else off your back while you do. [i]sandık[/i] = chest · [i]bekçi[/i] = keeper · [i]kilit[/i] = lock" % kn,
		["🔓 Kilidi kır · Break the lock and fight", "🚶‍♀️ Şimdi değil · Not yet"], func(i):
			if i == 0 and not c["open"] and c["keeper"] == null: _start_duel(c))
	return true

func _start_duel(c: Dictionary) -> void:
	var k := Enemy.spawn(world, c["typ"], Vector3(c["x"] + 2.6, 0, c["z"] + 2.6), player, true)
	k.max_hp = round(k.max_hp * 1.35); k.hp = k.max_hp
	c["keeper"] = k; duel = k
	k.died.connect(func(_e): _chest_won(c))
	var held := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == k: continue
		if Vector2(e.global_position.x - c["x"], e.global_position.z - c["z"]).length_squared() < 4900:
			held += 1
			if "guard" in e: e.guard = true
	Bus.emit_ev("duel", {"on": true, "keeper": k, "pos": Vector3(c["x"], 0, c["z"])})
	_banner("⚔️ SANDIK BEKÇİSİ", "The keeper wants a fair fight — Bandit has the rest 🐶")
	_toast("⚔️ [b]One on one.[/b] Bandit is holding off %s other%s. Beat the keeper and the chest is yours. [i]bekçi[/i] = guard." % [str(held) if held else "the", "" if held == 1 else "s"], 8.0)
	_sfx("rev")
	if Fx.me: Fx.me.shake(.4)
	c["sign"].visible = false

func _end_duel() -> void:
	duel = null
	for e in get_tree().get_nodes_in_group("enemies"): if "guard" in e: e.guard = false
	Bus.emit_ev("duel", {"on": false})

func _chest_won(c: Dictionary) -> void:
	if c["open"]: return
	c["open"] = true; c["keeper"] = null; _end_duel()
	c["lid"].rotation.x = -2.1; c["lock"].visible = false
	var at := Vector3(c["x"], c["g"].position.y, c["z"])
	_banner("🗝 SANDIK AÇILDI!", c["loot"]["n"]); _sfx("fanfare"); _sfx("chest")
	if "dance_t" in player: player.dance_t = 1.8
	if Fx.me: Fx.me.puff(at + Vector3(0, 1.6, 0), [Color("ffd24a"), Color("fff2b0"), Color("8ff2ff")], 30, 2.6, 3.4, 1.3, 1.1)
	drop_coins(at, randi_range(90, 220), 5)
	match c["loot"]["id"]:
		"para":
			var v := randi_range(320, 760); Stats.add_lira(v)
			_toast("💰 [b]%d₺[/b] — the keeper had been saving up. [i]para[/i] = money." % v, 6.0)
		"cephane":
			SaveBridge.data["ammo"] = SaveBridge.get_i("ammo") + randi_range(14, 30)
			_toast("🧿 [b]Nazar beads![/b] Ranged weapons are back in business. [i]boncuk[/i] = bead.", 6.0)
		"silah":
			var k := roll_weapon(); give_weapon(k)
			_toast("🗡 A weapon was locked in there — [b]%s[/b]." % W[k]["n"], 6.0)
		"hazine":
			Stats.add_lira(randi_range(200, 400)); Stats.gain_xp(180)
			var bs := ["baklava", "cay", "lokum", "nazar"]
			for i in 4: spawn_pickup(bs[i], _street(at.x + cos(i * 1.6) * 2, at.z + sin(i * 1.6) * 2, .2), 0.0)
			_toast("✨ [b]Hazine![/b] Lira, XP and every buff in the game. [i]hazine[/i] = treasure.", 7.0)
		"kitap":
			Stats.gain_xp(260); SaveBridge.data["int"] = SaveBridge.get_i("int") + 2
			_toast("📚 [b]Somebody's Turkish notebook.[/b] +260 XP, +2 INT. [i]kitap[/i] = book.", 7.0)
	# every chest has a piece of gear in it, better than a street drop
	spawn_gear_drop(_street(at.x + 1.8, at.z + .6, .2), make_gear({"lv": Stats.lvl() + 1, "bonus": .5}))
	Stats.gain_xp(220)
	c["sign"].text = "✅ AÇILDI"; c["sign"].modulate = Color("3dff9e"); c["sign"].visible = true
	_save()

func _chests_tick() -> void:
	for c in chests:
		if c["open"] or c["keeper"] == null: continue
		if not is_instance_valid(c["keeper"]) or not c["keeper"].is_inside_tree():
			# the keeper vanished without dying (she fainted and woke up elsewhere): the chest locks again
			c["keeper"] = null; c["sign"].visible = true; _end_duel()

# ----------------------------------------------------------------
func _process(dt: float) -> void:
	if not _ready_world or not is_instance_valid(player) or Overlay.any(): return
	t += dt
	_buffs_tick(dt)
	if player.dead: return
	_pickups_tick(dt)
	_coins_tick(dt)
	_nazars_tick(dt)
	_chests_tick()
	_weapon_director(dt)
