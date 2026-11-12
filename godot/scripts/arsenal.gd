# Her weapons, the 7.2 way: WEAPONS (missions.json "weapons"), tryAttack's ranged + shock branches, ammo
# (7.2's one shared pool, save field `ammo`), useDurability (wears once per swing / shot, 10-uses warning,
# BROKEN banner, then her best DPS), giveWeapon / equipBestDps / dryFallback, cycleWeapon (skips empty guns),
# and the hold-Q wheel's keys (qHeld / openWheel / closeWheel: tap < 220 ms = next weapon, hold = the wheel,
# time crawls at .2 while it's up). Plus ammo drops, weaponDirector's random weapons lying in the city, and what
# each weapon does on a hit.
# Better than 7.2: the mission guns each shoot their own thing (see projectile.gd), a soft auto-aim / her
# lock-on target, a heavy (right click) volley, and Josh's Device actually reaches (7.2's zap, 8 m round her).
# Save fields (all 7.2's): ammo, weap, wi, dur, bassD (read only). Nothing new is written.
class_name Arsenal
extends Node

static var me: Arsenal
const HOLD_MS := 220
# ranged weapons: what they fire (projectile.gd kinds) and their trick
const SPEC := {
	"bills": {"kind": "bills", "col": "4fbf72", "spd": 23.0, "life": 1.3, "kb": 6.0, "snd_hit": "cash", "desc": "Bill stacks · big knockback"},
	"nazarw": {"kind": "bead", "col": "3f8fff", "spd": 30.0, "life": 1.2, "pierce": 2, "status": "slow", "sec": 2.0, "kb": 3.0, "snd_hit": "sting", "desc": "Pierces 3 · slows them"},
	"penashuri": {"kind": "pick", "col": "ff5fa2", "spd": 27.0, "life": 1.0, "count": 3, "spread": .16, "mult": .6, "kb": 2.5, "snd_hit": "clack", "desc": "3 picks in a fan"},
	"balllauncher": {"kind": "ball", "col": "d8ff4a", "spd": 21.0, "life": 2.6, "grav": 12.0, "bounce": 3, "kb": 5.0, "snd_hit": "drop", "desc": "Bounces off walls and heads"},
	"stapler": {"kind": "staple", "col": "cfd8ff", "spd": 36.0, "life": .9, "burst": 2, "mult": .65, "status": "slow", "sec": 1.5, "kb": 1.5, "snd_hit": "clack", "desc": "Double staple · pins them"},
	"loadeddice": {"kind": "die", "col": "ffd66b", "spd": 22.0, "life": 1.4, "dice": true, "kb": 4.0, "snd_hit": "coinflip", "desc": "Rolls 1-6 · rigged high"},
	"turntable": {"kind": "disc", "col": "b06bff", "spd": 22.0, "life": 2.2, "pierce": 99, "boomer": true, "kb": 3.0, "snd_hit": "dance", "desc": "Comes back · cuts through all"},
}
# melee weapons with a trick on hit: player.gd merges these into enemy.hit(dmg, dir, opts)
const MELEE := {
	"candle": {"status": "burn", "sec": 3.0, "desc": "Sets them on fire"},
	"sunblade": {"status": "burn", "sec": 2.5, "desc": "Sun fire on every hit"},
	"rattle": {"status": "poison", "sec": 4.0, "desc": "Snake bite · poison"},
	"syringe": {"status": "poison", "sec": 3.0, "desc": "Poisons them"},
	"cactus": {"status": "poison", "sec": 2.5, "stagger": .4, "desc": "Spines · poison"},
	"kilim": {"status": "slow", "sec": 2.0, "desc": "Tangles them · slow"},
	"mask": {"status": "slow", "sec": 2.5, "desc": "Scares them · slow"},
	"terlik": {"status": "fear", "sec": 2.5, "kb": 11.0, "stagger": .6, "desc": "FEARED · they run from you"},
	"oar": {"kb": 13.0, "desc": "Huge knockback"},
	"bass": {"kb": 10.0, "desc": "Wide sweep · knockback"},
	"djembe": {"kb": 11.0, "stagger": .3, "desc": "Wide boom · knockback"},
	"tepsi": {"stagger": .35, "desc": "Clangs them dizzy"},
	"balta": {"stagger": .5, "desc": "Heavy chop · staggers"},
	"tavlaw": {"stagger": .5, "desc": "Board slam · staggers"},
	"parasol": {"kb": 8.0, "desc": "Wide sweep · knockback"},
}

var W := {}                       # the weapon table
var player                        # player.gd (untyped: it has no class_name)
var wheel: WeaponWheel
var unarmed := false              # 7.2's S.unarmed: bare hands even though she owns weapons
var _cd := 0.0
var _q_down := false
var _q_at := 0
var _ts := 1.0
var _bt := 0.0

func setup(p) -> void:
	me = self; player = p
	W = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["weapons"]
	wheel = WeaponWheel.new(); wheel.name = "WeaponWheel"; add_child(wheel)
	unarmed = _cur() == "kick" and not _weap().is_empty()

# ---- little helpers ----
func _weap() -> Array: return SaveBridge.data["weap"] if SaveBridge.data.get("weap") is Array else []
func _durs() -> Dictionary: return SaveBridge.data["dur"] if SaveBridge.data.get("dur") is Dictionary else {}
func _cur() -> String:
	if player == null: return "kick"
	var w = player.get("weapon")
	return str(w.get("id", "kick")) if w is Dictionary else "kick"
func _mod(p, key: String, def: float) -> float:
	var m = p.get("mods") if p else null
	return float(m.get(key, def)) if m is Dictionary else def
func _toast(t: String, dur := 4.5, bad := false) -> void:
	if Lessons.me and Lessons.me.hud: Lessons.me.hud.toast(t, dur, bad)
func _banner(t: String) -> void:
	if Lessons.me and Lessons.me.hud: Lessons.me.hud.banner(t)
func _sfx(n: String, at = null) -> void:
	var d := {"name": n}
	if at is Vector3: d["pos"] = at
	Bus.emit_ev("sfx", d)
func _alive(e) -> bool:
	if e == null or not is_instance_valid(e): return false
	if e.has_method("is_alive"): return e.is_alive()
	return float(e.get("hp")) > 0
func _facing(p) -> Vector3:
	var f: Vector3 = p.facing() if p.has_method("facing") else -p.global_transform.basis.z
	f.y = 0
	return f.normalized() if f.length() > .01 else Vector3.FORWARD

# ---- ammo: one pool for every ranged weapon, like 7.2 (id is there for later per-gun ammo) ----
func ammo(_id := "") -> int: return SaveBridge.get_i("ammo")

func add_ammo(_id: String, n: int) -> void:
	var a := maxi(0, ammo() + n)
	SaveBridge.data["ammo"] = a
	Bus.emit_ev("ammo", {"ammo": a, "delta": n})

func is_ranged(w: Dictionary) -> bool:            # true = Arsenal handles this attack (guns + the shock device)
	var id := str(w.get("id", ""))
	var s: Dictionary = W.get(id, w)
	return bool(s.get("ranged", false)) or bool(s.get("shock", false))

func is_dry(id: String) -> bool:                  # 7.2's isDry: a gun with nothing to fire
	return W.has(id) and bool(W[id].get("ranged", false)) and ammo() <= 0

func _dmg_of(id: String) -> float:
	var w: Dictionary = W.get(id, W.get("kick", {}))
	var d := float(w.get("dmg", 9))
	var b = SaveBridge.data.get("bassD")                 # Pena's reward: the bass hits harder (7.2's bassD)
	if id == "bass" and (b is float or b is int) and float(b) > 0: d = float(b)
	return d

# a weapon's real damage (the bass uses her saved bassD); player.equip should use this too
func dmg_of(id: String) -> float: return _dmg_of(id)

static func speed_word(cd: float) -> String:
	return "Very Fast" if cd <= .3 else ("Fast" if cd <= .5 else ("Medium" if cd <= .8 else "Slow"))

static func _letters(s: String) -> bool:
	for i in s.length():
		var u := s.unicode_at(i)
		if (u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122): return true
	return false

# everything the wheel / HUD / shops need about one weapon
func weapon_info(id: String) -> Dictionary:
	var w: Dictionary = W.get(id, W.get("kick", {}))
	var n := str(w.get("n", id))
	var nm := n
	var icon := "🗡"
	var sp := n.rfind(" ")
	if sp > 0 and not _letters(n.substr(sp + 1)): nm = n.substr(0, sp); icon = n.substr(sp + 1)
	var dv = w.get("dur")
	var dmax := -1 if (dv == null or float(dv) >= 9000) else int(dv)
	var cur := dmax
	if dmax > 0 and _durs().has(id):
		var c := float(_durs()[id])
		if c >= 9000: dmax = -1
		cur = int(round(c))
	var dmg := _dmg_of(id)
	var cd := float(w.get("cd", .5))
	var ranged := bool(w.get("ranged", false))
	var desc := str(SPEC.get(id, MELEE.get(id, {})).get("desc", ""))
	if w.get("shock", false): desc = "Zaps all round · stuns · shocks you too"
	return {"id": id, "n": n, "name": nm, "icon": icon, "dmg": dmg, "cd": cd, "rng": float(w.get("rng", 0)),
		"arc": float(w.get("arc", 0)), "snd": str(w.get("snd", "thud")), "rar": str(w.get("rar", "Common")),
		"ranged": ranged, "shock": bool(w.get("shock", false)), "dur_max": dmax, "dur": cur, "dps": dmg / maxf(cd, .05),
		"speed": speed_word(cd), "dry": ranged and ammo() <= 0, "ammo": ammo() if ranged else -1, "desc": desc,
		"owned": id == "kick" or _weap().has(id)}

# 7.2's wStats line for toasts
func stats_line(id: String) -> String:
	var i := weapon_info(id)
	return "%s · %s · 💥%d dmg · ⚡%s%s%s" % [i["n"], i["rar"], int(i["dmg"]), i["speed"],
		" · 🎯RANGED (uses 🧿 ammo)" if i["ranged"] else "",
		" · ∞ durability" if i["dur_max"] <= 0 else " · 🔧%d uses" % i["dur"]]

# what hud.gd's weapon box draws (dur_max null = unbreakable / ∞)
func hud_info() -> Dictionary:
	var i := weapon_info(_cur())
	if unarmed or _cur() == "kick": i["rar"] = "Unarmed"
	return {"n": i["n"], "dmg": i["dmg"], "rar": i["rar"], "dur": null if i["dur_max"] <= 0 else i["dur"],
		"dur_max": null if i["dur_max"] <= 0 else i["dur_max"], "ammo": ammo(), "ranged": i["ranged"]}

# a melee weapon's trick for enemy.hit opts ({} for plain ones)
func melee_opts(id: String) -> Dictionary:
	var o: Dictionary = MELEE.get(id, {}).duplicate()
	o.erase("desc")
	if o.has("sec"): o["status_t"] = o["sec"]            # enemy.hit reads status_t
	return o

# 7.2's hitEnemy maths: her damage mods (gear/perks/buffs), ranged perk, crit-next (skills), crit chance
func roll_damage(p, base: float, ranged := true) -> Array:
	var d := base * _mod(p, "dmg", 1.0) * (_mod(p, "rdmg", 1.0) if ranged else 1.0)    # rdmg is a multiplier (1 = none)
	var crit := false
	if p and "crit_next" in p and p.crit_next:
		d *= 1.5; p.crit_next = false; crit = true
	elif randf() < _mod(p, "crit", 0.0):
		d *= 1.8; crit = true
	return [roundf(d), crit]

# ---- firing (F / left click with a gun; heavy = right click: a 3-shot volley for 2 ammo) ----
func fire(p, heavy := false) -> void:
	if p == null or p.get("dead"): return
	if p.get("on_bike"): _toast("Bisiklette savaşamazsın! 🚲 (Not while riding!)", 2.0, true); return
	if _cd > 0: return
	if p.get("rolling") or (p.has_method("has_status") and p.has_status("stun")) or p.get("ledge") not in [null, ""]: return
	var id := _cur()
	var info := weapon_info(id)
	if info["shock"]: _shock(p, info, heavy); return
	if not info["ranged"]: return
	if ammo() <= 0:
		_sfx("no")
		_toast("🧿 Out of ammo! Mobs drop nazar beads rarely — or buy at Five Sips ☕", 5.2, true)
		dry_fallback(p)
		return
	var cost := mini(2 if heavy else 1, ammo())
	add_ammo(id, -cost)
	_cd = float(info["cd"]) * _mod(p, "cd", 1.0) * (1.5 if heavy else 1.0)
	if "attack_cd" in p: p.attack_cd = _cd
	if "attack_t" in p: p.attack_t = .28
	var spec: Dictionary = SPEC.get(id, SPEC["bills"])
	var f := _facing(p)
	var from: Vector3 = p.global_position + Vector3(0, 1.4, 0) + f * .9
	var dir := _aim(p, from, f)
	var c := spec.duplicate()
	c["dmg"] = info["dmg"]; c["heavy"] = heavy
	c["mult"] = float(spec.get("mult", 1.0)) * (1.25 if heavy else 1.0)
	if spec.get("dice", false):                          # loaded: high faces come up more
		var face: int = [1, 2, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 6].pick_random()
		c["mult"] = float(c["mult"]) * face / 3.5
		if face == 6: c["status"] = "stun"; c["sec"] = .6
		if Fx.me: Fx.me.label(p.global_position + Vector3(0, 3.0, 0), "⚂ %d%s" % [face, "!" if face == 6 else ""], Color("ffd66b") if face >= 5 else Color("cfc0e8"), 1.0)
	var count := int(spec.get("count", 1))
	if heavy: count = maxi(3, count + 2)
	var spread := float(spec.get("spread", .14))
	var parent: Node = p.get_parent()
	for b in int(spec.get("burst", 1)):
		var start := from - dir * (.7 * b)                # the burst's 2nd shot trails just behind the 1st
		for i in count:
			var d := dir.rotated(Vector3.UP, (i - (count - 1) / 2.0) * spread)
			Projectile.shoot(parent, start, d, c, p)
	# muzzle flash + a little kick
	if Fx.me:
		Fx.me.puff(from, [Color(str(spec["col"])), Color.WHITE, Color("ffe04d")], 7, .7, .8, .22, .9)
		Fx.me.shake(.07 if heavy else .03)
	if heavy and p.has_method("knockback"): p.knockback(-f, 3.0)
	if heavy and "cast_t" in p: p.cast_t = maxf(float(p.cast_t), .3)
	_sfx(str(info["snd"]), from)
	# combat.gd already sends player_attack for the left-click shot; the right-click volley comes only from here
	if heavy: Bus.emit_ev("player_attack", {"kind": "ranged", "combo": 0, "heavy": true, "id": id})
	wear(p)
	if ammo() <= 0 and _cur() == id: dry_fallback(p)      # she just spent her last round

# lock-on target first, else a soft auto-aim: the nearest monster within ~13° of where she faces, 32 m
func _aim(p, from: Vector3, f: Vector3) -> Vector3:
	var t = p.get("lock_target")
	if not _alive(t):
		t = null
		var best := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			if not _alive(e): continue
			var to: Vector3 = e.global_position - p.global_position; to.y = 0
			var dist := to.length()
			if dist > 32.0 or dist < .5: continue
			var ang := absf(f.signed_angle_to(to / dist, Vector3.UP))
			if ang > .23: continue
			var score := dist * (1.0 + ang * 4.0)
			if score < best: best = score; t = e
	if t == null: return f
	var big: bool = t.get("flags") is Dictionary and t.flags.has("boss")
	var aim: Vector3 = t.global_position + Vector3(0, 1.6 if big else 1.1, 0) - from
	return aim.normalized()

# 7.2's Josh's Device: shocks every monster within 8 m (stun .8 s, slow 2.5 s) — and her, 5 HP (3 if it
# hit nothing), but it can never take her below 3
func _shock(p, info: Dictionary, heavy: bool) -> void:
	_cd = float(info["cd"]) * _mod(p, "cd", 1.0) * (1.5 if heavy else 1.0)
	if "attack_cd" in p: p.attack_cd = _cd
	if "attack_t" in p: p.attack_t = .28
	_sfx("zap", p.global_position)
	var R := float(info["rng"]) * (1.35 if heavy else 1.0)
	var me_at: Vector3 = p.global_position
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not _alive(e): continue
		var to: Vector3 = e.global_position - me_at; to.y = 0
		if to.length() > R: continue
		n += 1
		var r := roll_damage(p, float(info["dmg"]) * (1.25 if heavy else 1.0), false)
		e.hit(float(r[0]), to.normalized(), {"status": "stun", "status_t": .8, "kb": 2.0, "crit": r[1], "heavy": heavy, "shock": true})
		if is_instance_valid(e) and e.has_method("apply_status"): e.apply_status("slow", 2.5)
		if Fx.me:                                         # an arc of sparks from her to it
			for i in range(1, 7):
				var k := i / 7.0
				Fx.me.puff(me_at + to * k + Vector3(randf_range(-.25, .25), 1.4 + randf_range(-.3, .3), randf_range(-.25, .25)),
					[Color("7bf7ff"), Color.WHITE, Color("b06bff")], 1, .4, .6, .28)
	if Fx.me:
		Fx.me.puff(me_at + Vector3(0, 1.5, 0), Color("7bf7ff"), 10, 2.4, 2.0, .5, .7)
		Fx.me.shake(.25); Fx.me.flash("hurt")
	var hurt := 5 if n > 0 else 3
	if "hp" in p:
		var h := int(p.hp)
		p.hp = maxi(mini(h, 3), h - hurt)
		if p.has_signal("hp_changed"): p.hp_changed.emit(p.hp, p.max_hp)
	if Fx.me: Fx.me.label(me_at + Vector3(0, 3, 0), "-%d ⚡ (it shocks YOU too)" % hurt, Color("ff9ecf"), 1.5)
	if n > 0: _toast("📡 [b]ZAP![/b] %d enem%s shocked & stunned · you took %d 🙃" % [n, "y" if n == 1 else "ies", hurt], 4.5)
	if heavy: Bus.emit_ev("player_attack", {"kind": "ranged", "combo": 0, "heavy": true, "id": info["id"], "shock": true})
	wear(p)

# ---- durability (7.2's useDurability: once per swing or shot, hit or miss) ----
func wear(p) -> void:
	var id := _cur()
	if id == "kick" or not W.has(id): return
	var dv = W[id].get("dur")
	if dv == null: return
	var dur := _durs()
	var c := float(dur.get(id, dv))
	if c >= 9000: return                                 # unbreakable
	var left := int(round(c)) - 1
	dur[id] = left; SaveBridge.data["dur"] = dur
	if left <= 0: _break(p, id)
	elif left == 10: _toast("⚠️ [b]%s[/b] is about to break! (10 uses left)" % W[id]["n"], 5.0, true)

func _break(p, id: String) -> void:
	var nm := str(W[id]["n"])
	var weap := _weap(); weap.erase(id); SaveBridge.data["weap"] = weap
	var dur := _durs(); dur.erase(id); SaveBridge.data["dur"] = dur
	SaveBridge.data["wi"] = 0
	var nb := equip_best(p) if weap.size() else ""
	if nb == "": equip_id(p, "kick")
	_sfx("no"); _sfx("thud")
	_toast("💥 [b]%s BROKE![/b] %s" % [nm, ("Switched to [b]%s[/b] (your best DPS)" % W[nb]["n"]) if nb != "" else "Bare hands now — you can still KICK 🦵"], 8.0)
	_banner("💥 WEAPON BROKEN\n[font_size=16]Find another one![/font_size]")
	Bus.emit_ev("weapon_broke", {"id": id})
	SaveBridge.write()

# ---- choosing what's in her hand ----
func equip_id(p, id: String) -> void:
	if p == null: return
	if id == "kick" or not _weap().has(id):
		unarmed = true; id = "kick"
	else:
		unarmed = false; SaveBridge.data["wi"] = _weap().find(id)
	p.equip(id)
	Bus.emit_ev("weapon_equip", {"id": id})

# the best thing she can actually swing right now (a gun with no ammo doesn't count)
func best_dps() -> String:
	var best := ""
	var bv := -1.0
	for k in _weap():
		if not W.has(k) or is_dry(k): continue
		var v := _dmg_of(k) / maxf(float(W[k]["cd"]), .05)
		if v > bv: bv = v; best = k
	return best

func equip_best(p) -> String:
	var k := best_dps()
	if k == "":
		if _weap().size(): equip_id(p, "kick")       # bare hands beat an empty gun
		return ""
	equip_id(p, k)
	return k

func dry_fallback(p) -> void:
	var k := best_dps()
	if k != "":
		equip_id(p, k); _toast("🧿 Out of ammo — switched to [b]%s[/b]" % W[k]["n"], 3.8)
	else:
		equip_id(p, "kick"); _toast("🧿 Out of ammo and nothing else to swing — bare hands 🦵", 3.8)
	_sfx("no")

# 7.2's giveWeapon: a new weapon is added with full durability and she switches to her best DPS
func give_weapon(id: String, silent := false) -> void:
	if not W.has(id): return
	var weap := _weap()
	if not weap.has(id): weap.append(id); SaveBridge.data["weap"] = weap
	var dur := _durs(); var dv = W[id].get("dur")
	dur[id] = 9999 if dv == null else int(dv); SaveBridge.data["dur"] = dur
	unarmed = false
	var best := equip_best(player)
	if best == "": best = id
	Bus.emit_ev("weapon_new", {"id": id})
	if silent: return
	if best == id:
		_toast("🆕 [b]%s[/b] — equipped, it's your best DPS.\n[font_size=14]%s[/font_size]" % [W[id]["n"], stats_line(id)], 8.0)
	else:
		_toast("🆕 Picked up [b]%s[/b] (%d DPS) — keeping [b]%s[/b] (%d DPS). Hold [b]Q[/b] to switch." % [W[id]["n"],
			int(round(weapon_info(id)["dps"])), W[best]["n"], int(round(weapon_info(best)["dps"]))], 8.0)

# 7.2's cycleWeapon: tap Q / the mouse wheel; steps over guns with no ammo
func cycle(p) -> void:
	var weap := _weap()
	var cur := _cur()
	if unarmed or cur == "kick":
		for k in weap:
			if W.has(k) and not is_dry(k):
				equip_id(p, k); _sfx("drop"); _toast("🗡 " + stats_line(k), 4.5); return
		if weap.size(): _sfx("no"); _toast("🧿 Everything you have is out of ammo.", 3.5, true)
		return
	if weap.size() < 2: return
	var i := weap.find(cur)
	for _n in weap.size():
		i = (i + 1) % weap.size()
		if not is_dry(weap[i]): break
	if is_dry(weap[i]) or weap[i] == cur: return
	equip_id(p, weap[i]); _sfx("drop"); _toast("🗡 " + stats_line(weap[i]), 4.5)

# ---- hold Q: tap = next weapon, hold 220 ms = the wheel ----
func hold_q_down() -> void:
	if _q_down: return
	if Overlay.any() and not wheel.is_open: return
	_q_down = true; _q_at = Time.get_ticks_msec()

func hold_q_up() -> void:
	if not _q_down and not wheel.is_open: return
	var held := Time.get_ticks_msec() - _q_at
	_q_down = false
	if wheel.is_open: close_wheel(true)
	elif held < HOLD_MS and not Overlay.any() and player and not player.get("dead"): cycle(player)

func _wheel_list() -> Array:
	var l := _weap().duplicate()
	if not l.has("kick"): l.append("kick")              # bare hands is always an option
	return l

func open_wheel() -> void:
	if wheel.is_open or player == null or player.get("dead") or Overlay.any(): return
	var list := _wheel_list()
	wheel.show_wheel(list, list.map(weapon_info), _cur())
	Overlay.open("wheel")
	# time crawls while she picks (a hit-stop's .05 isn't "normal", so that one comes back as 1)
	_ts = Engine.time_scale if Engine.time_scale >= .5 else 1.0
	Engine.time_scale = .2
	_sfx("drop")

func close_wheel(commit: bool) -> void:
	if not wheel.is_open: return
	var k := wheel.picked()
	wheel.hide_wheel()
	Engine.time_scale = _ts                              # always back to normal (Fx's safety net agrees)
	Overlay.close("wheel")
	if not commit or k == "": return
	if is_dry(k):                                        # an empty gun is not a choice
		_sfx("no")
		_toast("🧿 [b]%s[/b] has no ammo — you can't equip it. Mobs drop nazar beads, or buy them at Five Sips ☕" % W[k]["n"], 5.0, true)
	elif k == "kick":
		equip_id(player, "kick"); _sfx("thud")
		_toast("🦵 [b]Bare hands.[/b] Turkish: [i]tekme[/i] = kick. Nothing to break.", 5.0)
	elif _weap().has(k):
		equip_id(player, k); _sfx("ding")
		_toast("🗡 [b]%s[/b] — %s" % [W[k]["n"], stats_line(k)], 5.0)

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.is_action("weapon"):
		if not e.echo:
			if e.pressed: hold_q_down()
			else: hold_q_up()
		if wheel.is_open or _q_down or not e.pressed: get_viewport().set_input_as_handled()
		return
	if not wheel.is_open:
		# in the world: the mouse wheel = next weapon (skips empty guns), right click with a gun = the volley
		if e is InputEventMouseButton and e.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and not Overlay.any() and player and not player.get("dead"):
			if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if not player.get("on_bike"): cycle(player)
				get_viewport().set_input_as_handled()
			elif e.button_index == MOUSE_BUTTON_RIGHT and player.get("weapon") is Dictionary and is_ranged(player.weapon):
				fire(player, true)
				get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseMotion:
		if wheel.aim(e.relative): _sfx("drop")
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP: wheel.step(-1)
			MOUSE_BUTTON_WHEEL_DOWN: wheel.step(1)
			MOUSE_BUTTON_LEFT: close_wheel(true); _q_down = false
	elif e is InputEventKey and e.pressed and not e.echo:
		var kc: int = e.keycode if e.keycode != 0 else e.physical_keycode
		if kc >= KEY_1 and kc <= KEY_9: wheel.set_pick(kc - KEY_1); _sfx("ding")
		elif kc == KEY_D or kc == KEY_RIGHT: wheel.step(1)
		elif kc == KEY_A or kc == KEY_LEFT: wheel.step(-1)
		elif kc == KEY_ESCAPE: close_wheel(false); _q_down = false
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER: close_wheel(true); _q_down = false
	get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_cd -= dt
	if wheel.is_open and (Overlay.count() > 1 or player == null or player.get("dead")):
		close_wheel(false); _q_down = false                # something else took the screen: the wheel lets go
	if _q_down and not wheel.is_open and Time.get_ticks_msec() - _q_at >= HOLD_MS: open_wheel()
	if Overlay.any() or player == null: return
	_director(dt)
	# 7.2's applyWeapon backstop: she never stays holding an empty gun (a save loaded with 0 ammo, say)
	_bt -= dt
	if _bt <= 0:
		_bt = .5
		if not player.get("dead") and is_dry(_cur()):
			var k := best_dps()
			equip_id(player, k if k != "" else "kick")

func _exit_tree() -> void:
	if wheel and wheel.is_open: Engine.time_scale = _ts
	if me == self: me = null

# ---- ammo drops (the loot system calls drop_ammo; 7.2's 'ammo' pickup = +3) ----
func drop_ammo(pos: Vector3, n := 3) -> void:
	if player == null: return
	var d := AmmoDrop.new(); d.n = n
	player.get_parent().add_child(d)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 3, 0), pos + Vector3(0, -20, 0))
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	d.global_position = hit["position"] if hit else Vector3(pos.x, 0, pos.z)

# 7.2's kill drop (elites 50%, others 7%, bosses always). Off unless main.gd turns it on — meant for when
# no loot system is wired yet.
func enable_auto_loot() -> void:
	Bus.on("enemy_died", func(d: Dictionary):
		var chance := 1.0 if d.get("boss", false) else (.5 if d.get("elite", false) else .07)
		if randf() < chance and d.get("pos") is Vector3: drop_ammo(d["pos"] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))))

# ---- 7.2's weaponDirector: every 26-46 s a rarity-weighted weapon lands somewhere in the city, 30 m+ from
# her and not on a roof (7 lying around at most). Walk into it: new weapons are added, ones she has are repaired.
var director := true
var _wd_t := 12.0
func roll_weapon() -> String:
	var tot := 0.0
	for k in W: tot += float(W[k].get("w", 0))
	var r := randf() * tot
	for k in W:
		var w := float(W[k].get("w", 0))
		if w <= 0: continue
		r -= w
		if r <= 0: return k
	return "oklava"

func drop_weapon(id: String, pos: Vector3) -> void:
	if player == null or not W.has(id): return
	var d := WeaponDrop.new(); d.id = id; d.col = WeaponWheel.rar_col(str(W[id].get("rar", "")))
	player.get_parent().add_child(d); d.global_position = pos
	d.add_to_group("weapon_drops")

func _director(dt: float) -> void:
	if not director or player.global_position.x > 400: return      # the city only (not abroad)
	_wd_t -= dt
	if _wd_t > 0: return
	_wd_t = randf_range(26, 46)
	if get_tree().get_nodes_in_group("weapon_drops").size() >= 7: return
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for _i in 20:
		var x := randf_range(-192, 146)
		var z := randf_range(-192, 168)
		if Vector2(x - player.global_position.x, z - player.global_position.z).length() < 30: continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -20, z)))
		if hit.is_empty() or hit["position"].y > 1.5 or hit["normal"].y < .8: continue      # a roof, a wall top, nothing
		drop_weapon(roll_weapon(), hit["position"])
		return

class WeaponDrop extends Node3D:
	var id := "oklava"
	var col := Color.WHITE
	var t := 0.0
	var body: Node3D

	func _ready() -> void:
		body = Node3D.new(); add_child(body); body.position.y = .9
		var path := "res://assets/weapons/%s.glb" % id
		if ResourceLoader.exists(path):
			var m: Node3D = load(path).instantiate(); body.add_child(m)
		# a thin see-through beam in its rarity colour, so she can spot it down the street
		var cy := CylinderMesh.new(); cy.top_radius = .05; cy.bottom_radius = .3; cy.height = 7.0; cy.radial_segments = 6
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color = Color(col, .28)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED; cy.material = mat
		var beam := MeshInstance3D.new(); beam.mesh = cy; beam.position.y = 3.5
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(beam)

	func _physics_process(dt: float) -> void:
		if Overlay.any(): return
		t += dt
		body.rotation.y += dt * 1.8
		body.position.y = .9 + sin(t * 2.4) * .15
		var p = Arsenal.me.player if Arsenal.me else null
		if p == null or p.get("dead") or p.get("on_bike"): return
		var to: Vector3 = p.global_position - global_position; to.y = 0
		if to.length() > 1.4: return
		Bus.emit_ev("pickup", {"id": id, "kind": "weapon", "pos": global_position})
		Bus.emit_ev("sfx", {"name": "ding", "pos": global_position})
		if Fx.me: Fx.me.puff(global_position + Vector3(0, 1, 0), [col, Color.WHITE], 12, 1.6, 2.2, .7)
		Arsenal.me.give_weapon(id)
		queue_free()

# a green bill stack with a nazar bead on top: bobs and spins, pulls in when she's close, gone after 45 s
class AmmoDrop extends Node3D:
	var n := 3
	var life := 45.0
	var t := 0.0
	var body: Node3D

	func _ready() -> void:
		body = Node3D.new(); add_child(body)
		_part(BoxMesh.new(), Vector3(.42, .2, .3), Color("4fbf72"), Vector3.ZERO)
		_part(BoxMesh.new(), Vector3(.44, .07, .16), Color("e8ffe0"), Vector3.ZERO)
		_part(SphereMesh.new(), Vector3(.36, .36, .14), Color("1f5fd0"), Vector3(0, .34, 0))
		_part(SphereMesh.new(), Vector3(.22, .22, .15), Color("f4f8ff"), Vector3(0, .34, 0))
		_part(SphereMesh.new(), Vector3(.12, .12, .16), Color("7bd0ff"), Vector3(0, .34, 0))
		_part(SphereMesh.new(), Vector3(.05, .05, .17), Color("10142a"), Vector3(0, .34, 0))

	func _part(mesh: PrimitiveMesh, sz: Vector3, col: Color, at: Vector3) -> void:
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = col
		var sm := mesh as SphereMesh
		if sm: sm.radius = .5; sm.height = 1.0; sm.radial_segments = 8; sm.rings = 4
		var bm := mesh as BoxMesh
		if bm: bm.size = Vector3.ONE
		mesh.material = m
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.scale = sz; mi.position = at
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; body.add_child(mi)

	func _physics_process(dt: float) -> void:
		if Overlay.any(): return
		t += dt; life -= dt
		if life <= 0: queue_free(); return
		body.rotation.y += dt * 2.4
		body.position.y = .5 + sin(t * 3.0) * .12
		visible = life > 8.0 or fmod(life, .4) > .15        # blinks before it goes
		var p = Arsenal.me.player if Arsenal.me else null
		if p == null or p.get("dead"): return
		var to: Vector3 = p.global_position - global_position; to.y = 0
		var d := to.length()
		if d < 4.5 and d > .05: global_position += to / d * minf(d, dt * (11.0 - d * 1.5))   # magnet
		if d < 1.1:
			Arsenal.me.add_ammo("", n)
			Bus.emit_ev("sfx", {"name": "cash", "pos": global_position})
			Bus.emit_ev("pickup", {"id": "ammo", "kind": "ammo", "pos": global_position})
			if Fx.me:
				Fx.me.label(global_position + Vector3(0, 2.2, 0), "+%d 🧿" % n, Color("8ff2ff"), 1.1)
				Fx.me.puff(global_position + Vector3(0, .6, 0), [Color("4fbf72"), Color("3f8fff"), Color.WHITE], 8, 1.2, 1.6, .5)
			if Lessons.me and Lessons.me.hud: Lessons.me.hud.toast("🧿 [b]+%d ammo[/b] for your ranged weapons" % n, 3.5)
			queue_free()
