# Her numbers, all in one place: 7.2's stat() (level growth, perks, worn gear, 30 nazars, post-30
# prestige), pk() / gearStat(), and gainXP's bonuses (ÇALIŞKAN, gear XP, matcha focus) on top of
# SaveBridge.gain_xp (which already does xpFor, lvlMul, INT and the per-level growth).
# Stats.apply(player) pushes it all into the player as mods ("level", "perks", "gear", "nazar") and sets
# max HP / mana / stamina from the save (7.2 bakes flat gear + perk HP/mana/stamina into mh/mm/ms).
# Also: the İKİNCİ NEFES save (nefes2), ŞİFALI VURUŞ heal on kill is in Items, the HUD's data (hud_data)
# and the clock word for the time of day (7.2's partOfDay).
class_name Stats
extends RefCounted

const DMG_PER_LV := .03
static var D := {}                  # assets/items/items.json (shared with Items / InventoryUI / LevelUp)
static var streak_tier := 0         # combat can set this (7.2's kill-streak tier) — ÖFKE adds 6% per tier
static var _nefes_t := -999.0       # last İKİNCİ NEFES (once every 90 s)
static var _hooked := false

static func data() -> Dictionary:
	if D.is_empty():
		D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/items/items.json"))
	return D

static func lvl() -> int: return maxi(1, SaveBridge.get_i("lvl", 1))

static func pk(id: String) -> int:
	var p = SaveBridge.data.get("perks")
	if not (p is Dictionary): return 0
	var v = p.get(id, 0)
	return int(v) if (v is int or v is float) else 0

# the summed stats of what she's wearing (7.2's S.gearTot)
static func gear_tot() -> Dictionary:
	var tot := {}
	var eq = SaveBridge.data.get("eq")
	var gear = SaveBridge.data.get("gear")
	if not (eq is Dictionary) or not (gear is Array): return tot
	for sl in eq:
		var u = eq[sl]
		if u == null: continue
		for it in gear:
			if it is Dictionary and int(it.get("u", -1)) == int(u):
				var st: Dictionary = it.get("st", {})
				for k in st: tot[k] = float(tot.get(k, 0.0)) + float(st[k])
				break
	return tot

static func gear_stat(k: String) -> float: return float(gear_tot().get(k, 0.0))

static func nz_count() -> int:
	var nz = SaveBridge.data.get("nz")
	return (nz as Array).size() if nz is Array else 0

static func has_buff(k: String) -> bool: return Items.me != null and Items.me.has_buff(k)

# 7.2's stat(k), same numbers
static func stat(k: String) -> float:
	var L := lvl()
	var post30 := maxi(0, int(floor((L - 30) / 5.0)))
	match k:
		"dmg": return 1.0 + DMG_PER_LV * (L - 1) + .12 * pk("keskin") + gear_stat("dmg") + (streak_tier * .06 if pk("ofke") > 0 else 0.0) \
			+ post30 * .05 + (.08 if nz_count() >= 30 else 0.0)
		"rdmg": return .2 * pk("nisanci")
		"crit": return .03 + .06 * pk("kritik") + gear_stat("crit")
		"cd": return maxf(.55, 1.0 - .08 * pk("seri") - gear_stat("cd"))
		"armor": return minf(.6, .07 * pk("zirh") + gear_stat("armor"))
		"spd": return 1.0 + .06 * pk("hizli") + gear_stat("spd")
		"xp": return .1 * pk("caliskan") + gear_stat("xp")
		"lira": return .15 * pk("zengin") + gear_stat("lira")
		"luck": return .25 * pk("sansli") + gear_stat("luck") + (.5 if has_buff("lucky") else 0.0)
		"magnet": return 1.0 + .6 * pk("miknatis")
		"bike": return 1.0 + .1 * pk("pedal") + gear_stat("bike") + (.12 if L >= 15 else 0.0)
		"boostcost": return maxf(.4, 1.0 - .2 * pk("pedal") - gear_stat("boost"))
		"sprintcost": return maxf(.4, 1.0 - .15 * pk("maraton"))
		"manacost": return maxf(.5, 1.0 - .1 * pk("buyucu"))
		"food": return 1.0 + .4 * pk("asci")
	return 0.0

# gainXP() with every bonus 7.2 had; shows "+n XP" over her. Returns levels gained (LevelUp shows them).
# the extra XP her bonuses add on top of n raw XP (for kills, where enemy.gd pays the raw part itself)
static func xp_bonus(n: int) -> int:
	return maxi(0, int(round(n * (1.0 + stat("xp")) * (2.0 if has_buff("focus") else 1.0))) - n)

static func gain_xp(n: int, at := Vector3.INF, raw := false) -> int:
	if n <= 0: return 0
	var m := 1.0 if raw else (1.0 + stat("xp")) * (2.0 if has_buff("focus") else 1.0)
	var n2 := int(round(n * m))
	var shown := int(round(n2 * (1.0 + .1 * (lvl() - 1)) * (1.0 + SaveBridge.get_i("int") * .08)))
	var up := SaveBridge.gain_xp(n2)
	Bus.emit_ev("xp", {"delta": shown})
	if Fx.me and not raw:
		var p: Vector3 = at
		if p == Vector3.INF and Items.me and is_instance_valid(Items.me.player): p = Items.me.player.global_position + Vector3(0, 2.8, 0)
		if p != Vector3.INF: Fx.me.label(p, "+%d XP" % shown, Color("ffd66b"), 1.0)
	if up > 0:
		SaveBridge.write()                  # CRT-01: a level-up is saved the moment it happens
		if LevelUp.me: LevelUp.me.check()
	return up

static func add_lira(n: int) -> void:
	if n == 0: return
	SaveBridge.data["lira"] = maxi(0, SaveBridge.get_i("lira") + n)
	Bus.emit_ev("lira", {"delta": n})

# push the stat layer into the player. Mods (see player.set_mod): dmg / speed / cd / bike / rdmg are
# multipliers, def = damage-taken multiplier (1 - armour), crit is additive. Max HP / mana / stamina come
# from the save (mh / mm / ms), which already hold perks and worn flat gear like 7.2.
static func apply(p) -> void:
	if p == null or not is_instance_valid(p): return
	_hook()
	var L := lvl()
	var post30 := maxi(0, int(floor((L - 30) / 5.0)))
	var gt := gear_tot()
	if p.has_method("set_mod"):
		p.set_mod("level", "dmg", 1.0 + DMG_PER_LV * (L - 1) + post30 * .05)
		p.set_mod("level", "crit", .03)
		p.set_mod("level", "bike", stat("bike"))     # 7.2 ADDS pedal + gear + level 15, so the whole stat lives here
		p.set_mod("perks", "dmg", 1.0 + .12 * pk("keskin") + (streak_tier * .06 if pk("ofke") > 0 else 0.0))
		p.set_mod("perks", "rdmg", 1.0 + .2 * pk("nisanci"))
		p.set_mod("perks", "crit", .06 * pk("kritik"))
		p.set_mod("perks", "cd", maxf(.55, 1.0 - .08 * pk("seri")))
		p.set_mod("perks", "def", 1.0 - minf(.6, .07 * pk("zirh")))
		p.set_mod("perks", "speed", 1.0 + .06 * pk("hizli"))
		p.set_mod("perks", "bike", 1.0)
		p.set_mod("perks", "boostcost", stat("boostcost"))   # 7.2: max(.4, 1 - .2 pedal - gear boost), one number
		p.set_mod("perks", "sprintcost", maxf(.4, 1.0 - .15 * pk("maraton")))
		p.set_mod("perks", "manacost", maxf(.5, 1.0 - .1 * pk("buyucu")))
		p.set_mod("gear", "dmg", 1.0 + float(gt.get("dmg", 0.0)))
		p.set_mod("gear", "crit", float(gt.get("crit", 0.0)))
		p.set_mod("gear", "def", 1.0 - minf(.6, float(gt.get("armor", 0.0))))
		p.set_mod("gear", "speed", 1.0 + float(gt.get("spd", 0.0)))
		p.set_mod("gear", "bike", 1.0)
		p.set_mod("gear", "boostcost", 1.0)
		p.set_mod("nazar", "dmg", 1.08 if nz_count() >= 30 else 1.0)
	_pset(p, "max_hp", SaveBridge.get_i("mh", 100))
	_pset(p, "max_mana", float(SaveBridge.get_i("mm", 100)))
	_pset(p, "max_stamina", float(SaveBridge.get_i("ms", 100)))
	if "hp" in p and "max_hp" in p:
		p.hp = mini(int(p.hp), int(p.max_hp))
		if p.has_signal("hp_changed"): p.hp_changed.emit(p.hp, p.max_hp)
	if "mana" in p: p.mana = minf(float(p.mana), float(p.max_mana))
	if "stamina" in p: p.stamina = minf(float(p.stamina), float(p.max_stamina))
	if p.has_signal("stats_changed"): p.stats_changed.emit()

static func _pset(p, k: String, v) -> void:
	if k in p: p.set(k, v)

# İKİNCİ NEFES: once every 90 s, dropping under 20% HP heals her 35% (7.2's damagePlayer)
static func _hook() -> void:
	if _hooked: return
	_hooked = true
	Bus.on("player_hit", func(_d):
		if pk("nefes2") <= 0 or not Items.me: return
		var p = Items.me.player
		if not is_instance_valid(p) or p.dead or p.hp <= 0: return
		var now := Time.get_ticks_msec() / 1000.0
		if p.hp < p.max_hp * .2 and now - _nefes_t > 90.0:
			_nefes_t = now
			var h := int(round(p.max_hp * .35))
			if p.has_method("heal"): p.heal(h)
			else: p.hp = mini(p.max_hp, p.hp + h); p.hp_changed.emit(p.hp, p.max_hp)
			if Fx.me: Fx.me.flash("heal"); Fx.me.label(p.global_position + Vector3(0, 2.9, 0), "🌬 İKİNCİ NEFES +%d" % h, Color("7bf7ff"), 1.4)
			Bus.emit_ev("sfx", {"name": "heal"}))

# 7.2's partOfDay(h): the Turkish word for the time of day, for the HUD clock
static func part_of_day(h: float) -> Array:
	if h < 5.2: return ["gece", "night", "🌙"]
	if h < 7: return ["şafak", "dawn", "🌅"]
	if h < 11: return ["sabah", "morning", "🌤"]
	if h < 15: return ["öğle", "midday", "☀️"]
	if h < 18.4: return ["ikindi", "afternoon", "🌇"]
	if h < 20.4: return ["akşam", "evening", "🌆"]
	return ["gece", "night", "🌙"]

# "🌙 21:40 gece · night" from the computer's clock, like 7.2's #clockT
static func clock_text() -> String:
	var t := Time.get_datetime_dict_from_system()
	var pd := part_of_day(t.hour + t.minute / 60.0)
	return "%s %02d:%02d %s · %s" % [pd[2], t.hour, t.minute, pd[0], pd[1]]

# everything the HUD's stat block / bars show (PRG-01, UI-16/17 data side)
static func hud_data() -> Dictionary:
	var bag := []
	var b = SaveBridge.data.get("bag")
	var food: Dictionary = data()["FOOD"]
	if b is Dictionary:
		for k in b:
			if int(b[k]) > 0 and food.has(k): bag.append({"id": k, "ic": food[k]["ic"], "n": int(b[k])})
	var words = SaveBridge.data.get("words", [])
	return {"lvl": lvl(), "xp": SaveBridge.get_i("xp"), "need": SaveBridge.xp_for(lvl()), "lira": SaveBridge.get_i("lira"),
		"int": SaveBridge.get_i("int"), "words": (words as Array).size() if words is Array else 0, "ammo": SaveBridge.get_i("ammo"),
		"bag": bag, "nz": nz_count(), "pp": SaveBridge.get_i("pp"), "unit": SaveBridge.get_i("unit", 1), "ul": SaveBridge.get_i("ul"),
		"kills": SaveBridge.get_i("kills"), "clock": clock_text(), "buffs": Items.me.buff_list() if Items.me else []}
