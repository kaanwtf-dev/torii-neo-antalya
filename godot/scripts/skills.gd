# Skills, timed buffs and the boss battle quiz, ported from 7.2:
#   SKILLS / skillMana / useSkill / danceBlast, banditStrike (+ updateBandit's S.bStrike), cocktailSplash,
#   bassDrop, battleCry, nazarShield, starRain; the #buffs list (BUFFS / addBuff live in items.gd, we show them);
#   battleQuiz; finishQ's +10 mana per right answer; the arena / final-mission "mana full" rewards.
# Keys like 7.2: R or 1 = Dance Blast, 2..7 = the rest of 7.2's bar. NEW in Godot: 8 Rüzgar Koşusu (a wind dash
# with i-frames), 9 Nazar Mermisi (a homing nazar shot), 0 Çay Molası (heal + regen + haste).
# Each skill costs mana (x the player's "manacost" mod = BÜYÜCÜ perk), has a cooldown and refuses like 7.2 (level
# lock, no bass, on the bike, not enough mana). Big ones get a PS1-style wind-up: a ground ring tell, then the slam.
# 7.2 never saved its cooldown rewards, so they're re-derived from progress: arena done = Battle Cry 40 s,
# DJ set done = Dance Blast 6 s, Bandit's friend helped (npc.banditfriend >= 2) = Bandit Strike 18 s.
# Buffs: buff(id, sec, mods) writes the player's mods as "buff:<id>" and clears itself. The HUD reads hotbar() and
# active_buffs() (ours + items.gd's food buffs + her statuses like burn / slow / shield).
# Battle quiz: enemy.gd emits "boss_quiz" at 66% and 33% boss HP; we ask one question when no menu is up.
# Right = boss stunned 3.5 s, next hit +50% (player.crit_next), +10 HP. Wrong = boss heals 10%, she takes 10.
class_name Skills
extends Node

static var me: Skills

# 7.2's SKILLS (same order = same keys), then the new ones
const SK := [
	{"id": "dance", "n": "Dance Blast", "ic": "💃", "mana": 30, "cd": 8.0},
	{"id": "bandit", "n": "Bandit Strike", "ic": "🐶", "mana": 20, "cd": 25.0},
	{"id": "cocktail", "n": "Cocktail Splash", "ic": "🍹", "mana": 35, "cd": 14.0},
	{"id": "bass", "n": "Bass Drop", "ic": "🎸", "mana": 60, "cd": 40.0, "need": "bass"},
	{"id": "cry", "n": "Battle Cry", "ic": "🗣️", "mana": 45, "cd": 60.0},
	{"id": "nazar", "n": "Nazar Kalkanı", "ic": "🧿", "mana": 50, "cd": 45.0, "lv": 10},
	{"id": "stars", "n": "Yıldız Yağmuru", "ic": "🌠", "mana": 70, "cd": 50.0, "lv": 25},
	{"id": "dash", "n": "Rüzgar Koşusu", "ic": "💨", "mana": 20, "cd": 5.0, "lv": 3, "new": true},
	{"id": "bolt", "n": "Nazar Mermisi", "ic": "🔵", "mana": 15, "cd": 2.5, "lv": 6, "new": true},
	{"id": "tea", "n": "Çay Molası", "ic": "🫖", "mana": 40, "cd": 30.0, "lv": 15, "new": true},
]
const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

# fallback copy of 7.2's BUFFS, only used when items.gd isn't there (it owns food buffs)
const BUFFS := {
	"dmg2": {"n": "DOUBLE DAMAGE", "ic": "🍯", "dur": 10.0, "mods": {"dmg": 2.0}},
	"spd": {"n": "SPEED RUSH", "ic": "🫖", "dur": 10.0, "mods": {"speed": 1.5}},
	"shield": {"n": "NAZAR SHIELD", "ic": "🧿", "dur": 12.0, "mods": {"def": 3.0}},
	"regen": {"n": "LOKUM REGEN", "ic": "🍬", "dur": 10.0, "mods": {"regen": 3.6}},
	"lucky": {"n": "GODS' FAVOUR", "ic": "🎲", "dur": 20.0, "mods": {}},
	"focus": {"n": "MATCHA FOCUS", "ic": "🍵", "dur": 45.0, "mods": {"xp": 2.0}},
	"caffeine": {"n": "CAFFEINE RUSH", "ic": "☕", "dur": 30.0, "mods": {"cd": .62}},
}
# her statuses as HUD chips (player.status)
const STATUS := {"burn": ["🔥", "BURNING"], "poison": ["☠️", "POISONED"], "slow": ["🐌", "SLOWED"],
	"stun": ["💫", "STUNNED"], "shield": ["🧿", "KALKAN"], "haste": ["⚡", "HASTE"]}
const FIRE := [Color("ffd66b"), Color("b06bff"), Color("ff5fa2"), Color("7bf7ff")]

var torii: CharacterBody3D
var hud: Hud
var bandit: Node3D
var cds: Array[float] = []
var cd_base: Array[float] = []
var buffs := {}                 # id -> {left, total, icon, name, bad}
var _st_total := {}             # status id -> the longest it's been this time (for the chip's drain line)
var _unlocked := {}             # skill ids she had at the last check (for the "unlocked!" toast)
var _strike: Node3D = null      # Bandit Strike's target while he runs at it
var _strike_t := 0.0
var _dash := {}                 # {t, dir, hit}
var _bolts: Array = []          # {node, target, dir, life}
var _stars: Array = []          # {t, e, dmg}
var _later: Array = []          # wind-ups: {t, cb} (ticks with the game, stops under menus)
var _bq: Array = []             # bosses waiting for their battle quiz
var _quiz_hooked := false
var _refresh_t := 0.0

func setup(p: CharacterBody3D, h: Hud, ban: Node3D = null) -> void:
	me = self; torii = p; hud = h; bandit = ban
	cds.resize(SK.size()); cds.fill(0.0)
	cd_base.resize(SK.size())
	refresh()
	for i in SK.size(): if not _locked(i): _unlocked[SK[i]["id"]] = true
	Bus.on("boss_quiz", _on_boss_quiz)
	Bus.on("mission_done", _on_mission_done)
	Bus.on("level_up", func(_d): _check_unlocks())
	Bus.on("faint", func(_d): clear_buffs(); _end_strike(); _later.clear(); _dash = {})
	_hook_quiz()

func _hook_quiz() -> void:
	if _quiz_hooked or not Lessons.me or not Lessons.me.quiz: return
	Lessons.me.quiz.answered.connect(_on_answer); _quiz_hooked = true

# cooldowns from progress (7.2 changed SKILLS[i].cd in rewards and never saved it)
func refresh() -> void:
	for i in SK.size(): cd_base[i] = float(SK[i]["cd"])
	var nx := SaveBridge.get_i("next")
	var all_done: bool = SaveBridge.data.get("done", false) == true
	if nx >= 17 or all_done: cd_base[4] = 40.0          # MISSION 17 (arena, index 16) reward
	if nx >= 18 or all_done: cd_base[0] = 6.0           # MISSION 18 (djset, index 17) reward
	var npc = SaveBridge.data.get("npc", {})
	if npc is Dictionary:
		var bf = npc.get("banditfriend", 0)
		if (bf is int or bf is float) and bf >= 2: cd_base[1] = 18.0   # Bandit's friend got his bone back

# ---- save / perk helpers ----
func _lvl() -> int: return maxi(1, SaveBridge.get_i("lvl", 1))
func _pk(id: String) -> int:
	var p = SaveBridge.data.get("perks", {})
	if not (p is Dictionary): return 0
	var v = p.get(id, 0)
	return int(v) if (v is int or v is float) else 0

func mana_cost(i: int) -> int:                       # skillMana: stat('manacost') = the BÜYÜCÜ perk
	var m := maxf(.5, 1.0 - .1 * _pk("buyucu"))
	if torii and torii.has_method("mod"): m = float(torii.mod("manacost"))
	return int(round(float(SK[i]["mana"]) * m))
func cd_total(i: int) -> float:
	return cd_base[i] * ((1.0 - .25 * _pk("sadik")) if i == 1 else 1.0)
func _locked(i: int) -> bool: return _lvl() < int(SK[i].get("lv", 0))
func _missing(i: int) -> bool:
	if not SK[i].has("need"): return false
	var weap = SaveBridge.data.get("weap", [])
	return not (weap is Array and weap.has(SK[i]["need"]))

func _toast(t: String, d := 3.5, bad := false) -> void:
	if hud: hud.toast(t, d, bad)
func _sfx(n: String) -> void:
	Bus.emit_ev("sfx", {"name": n, "pos": torii.global_position if torii else Vector3.ZERO})
func _teach(w: String) -> void:
	if Lessons.me: Lessons.me.teach(w)
func _dance(sec: float) -> void:                     # 7.2's dance(sec)
	if torii.has_method("act"): torii.act("dance", sec)
	elif "dance_t" in torii: torii.dance_t = maxf(torii.dance_t, sec)
func _cast(sec: float) -> void:                      # the cast pose (pose.cast)
	if torii.has_method("act"): torii.act("cast", sec)
	elif "cast_t" in torii: torii.cast_t = maxf(torii.cast_t, sec)
func _mana() -> float:
	var m = torii.get("mana")
	return float(m) if m != null else 0.0
func _at(y := 1.2) -> Vector3: return torii.global_position + Vector3(0, y, 0)
func _feet() -> Vector3: return torii.global_position + Vector3(0, .05, 0)
func _facing() -> Vector3:
	var f: Vector3 = torii.facing() if torii.has_method("facing") else -torii.global_transform.basis.z
	f.y = 0
	return f.normalized() if f.length() > .01 else Vector3.FORWARD
func _after(sec: float, cb: Callable) -> void: _later.append({"t": sec, "cb": cb})

# ---- casting (useSkill) ----
func use(i: int) -> void:
	if i < 0 or i >= SK.size() or not torii: return
	if torii.dead or Overlay.any(): return
	var sk: Dictionary = SK[i]
	if _locked(i):
		_toast("🔒 [b]%s[/b] unlocks at [b]level %d[/b]." % [sk["n"], int(sk["lv"])], 3.5, true); _sfx("no"); return
	if torii.on_bike: _toast("Skills don't work on the bike! 🚲", 3.0, true); return
	if _missing(i): _toast("🔒 [b]%s[/b] requires the Bass Guitar!" % sk["n"], 3.5, true); _sfx("no"); return
	if cds[i] > 0: _sfx("no"); return
	if "status" in torii and torii.status is Dictionary and float(torii.status.get("stun", 0.0)) > 0: _sfx("no"); return
	var cost := mana_cost(i)
	if _mana() < cost or not torii.spend_mana(cost):
		_toast("Not enough mana! 🎲 Backgammon boards restore mana", 3.5, true); _sfx("no"); return
	cds[i] = cd_total(i)
	var ok := true
	match sk["id"]:
		"dance": _s_dance()
		"bandit": ok = _s_bandit()
		"cocktail": _s_cocktail()
		"bass": _s_bass()
		"cry": _s_cry()
		"nazar": _s_nazar()
		"stars": _s_stars()
		"dash": _s_dash()
		"bolt": _s_bolt()
		"tea": _s_tea()
	if not ok:                                        # 7.2: no target for Bandit = mana back, 2 s cooldown
		cds[i] = 2.0; torii.add_mana(cost); return
	Bus.emit_ev("skill_used", {"id": sk["id"]})

func use_slot(i: int) -> void: use(i)                # hotbar clicks

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo or Overlay.any(): return
	var k: int = e.keycode if e.keycode != 0 else e.physical_keycode
	var i := -1
	if k == KEY_R: i = 0
	elif k >= KEY_1 and k <= KEY_9: i = k - KEY_1
	elif k == KEY_0: i = 9
	if i >= 0 and i < SK.size():
		use(i); get_viewport().set_input_as_handled()

# ---- enemies ----
func _alive(e) -> bool:
	if not is_instance_valid(e): return false
	return e.is_alive() if e.has_method("is_alive") else float(e.hp) > 0

func _enemies_in(r: float, from := Vector3.INF) -> Array:
	var c := torii.global_position if from == Vector3.INF else from
	var out := []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if not e or not _alive(e): continue
		var d := e.global_position - c; d.y = 0
		if d.length_squared() < r * r: out.append(e)
	return out

func _nearest(r: float, cone := -2.0) -> Node3D:
	var lt = torii.get("lock_target")
	if lt is Node3D and _alive(lt) and lt.global_position.distance_to(torii.global_position) < r: return lt
	var best: Node3D = null
	var bd := r
	var f := _facing()
	for e in _enemies_in(r):
		var to: Vector3 = e.global_position - torii.global_position; to.y = 0
		var d := to.length()
		if d < bd and (cone < -1.0 or d < .01 or f.dot(to / d) > cone): bd = d; best = e
	return best

# skill hits go through her damage mods (Battle Cry, baklava, perks) and spend 7.2's critNext like a swing does
func _hit(e, dmg: float, opts := {}) -> void:
	if not _alive(e): return
	var m = torii.get("mods")
	var mul: float = float(m.get("dmg", 1.0)) if m is Dictionary else 1.0
	if "crit_next" in torii and torii.crit_next:
		mul *= 1.5; torii.crit_next = false; opts = opts.duplicate(); opts["crit"] = true
	var dir: Vector3 = e.global_position - torii.global_position; dir.y = 0
	dir = dir.normalized() if dir.length() > .01 else _facing()
	opts["src"] = "skill"
	e.hit(dmg * mul, dir, opts)

func _estatus(e, id: String, sec: float) -> void:
	if not _alive(e): return
	if e.has_method("apply_status"): e.apply_status(id, sec)
	elif id == "stun" and e.has_method("stun"): e.stun(sec)

func _wave(color: Color, r: float, sec := .35) -> void:  # a ground shockwave out to the skill's radius
	if Fx.me: Fx.me.shockwave(_feet(), r, color, sec)

# ---- 7.2's skills ----
func _s_dance() -> void:
	_dance(1.7); _sfx("dance"); _sfx("bassHit")
	_toast("💃 [b]DANCE BLAST![/b]")
	var dans := _pk("dans")
	var r := sqrt(45.0) * (1.0 + .2 * dans)          # 7.2: R² = 45 · (1 + .2 dans)²
	if Fx.me: Fx.me.puff(_at(), Fx.CONF, 30, 4.2, 3.0, 1.1); Fx.me.shake(.15)
	_wave(Color("ff5fa2"), r)
	for e in _enemies_in(r): _hit(e, round(36.0 * (1.0 + .4 * dans)), {"kb": 14.0, "heavy": true, "stagger": .5})

func _s_bandit() -> bool:
	var best := _nearest(16.0)
	if not best:
		_toast("No target in range for Bandit! 🐶", 2.8, true); return false
	_strike = best; _strike_t = 3.0; _sfx("bark")
	if bandit: bandit.set_physics_process(false)        # he's ours until he bites
	if Fx.me and bandit: Fx.me.label(bandit.global_position + Vector3(0, 1.4, 0), "HAV! 🐶", Color("ffd66b"), .8)
	_toast("🐶 [b]BANDIT STRIKE![/b] Get 'em, boy!")
	return true

func _bite() -> void:
	var tgt := _strike
	_hit(tgt, round(60.0 * (1.0 + .5 * _pk("sadik"))), {"stagger": 2.0})
	_estatus(tgt, "stun", 2.0)
	_sfx("bark"); _sfx("bark")
	var at: Vector3 = (bandit.global_position if bandit else tgt.global_position)
	if Fx.me:
		Fx.me.label(at + Vector3(0, 1.8, 0), "CHOMP!! 🐶⚡", Color("ffd66b"), 1.6)
		Fx.me.puff(tgt.global_position + Vector3(0, 1, 0), Color("ffd66b"), 10, 2.0, 2.0, .6)
		Fx.me.shake(.15)
	_end_strike()

func _end_strike() -> void:
	_strike = null
	if bandit and is_instance_valid(bandit): bandit.set_physics_process(true)

func _s_cocktail() -> void:
	_sfx("heal"); _sfx("whoosh"); _dance(.8)
	_toast("🍹 [b]COCKTAIL SPLASH![/b] Sticky enemies are slow enemies")
	if Fx.me: Fx.me.puff(_at(1.4), Color("ff5fa2"), 26, 4.0, 2.6, 1.0)
	_wave(Color("ff8fc0"), 8.0, .45)
	for e in _enemies_in(8.0): _hit(e, 25.0, {"status": "slow", "status_t": 4.0})

# wind-up: she lifts the bass, a cyan ring marks the blast, then the drop lands
func _s_bass() -> void:
	_cast(.45); _sfx("charge")
	if Fx.me: Fx.me.ring(_feet(), 12.0, .4, Color("7bf7ff"))
	_after(.4, func():
		_sfx("bassHit"); _sfx("bassHit"); _sfx("drum"); _dance(1.5)
		if Fx.me:
			Fx.me.shake(.6); Fx.me.puff(_at(), Color("7bf7ff"), 40, 5.0, 3.5, 1.3)
			Fx.me.flash_screen(Color("7bf7ff"), .25, .12)
		_wave(Color("7bf7ff"), 12.0, .5)
		_toast("🎸 [b]BASS DROP![/b] The whole block felt that", 4.0)
		for e in _enemies_in(12.0): _hit(e, 90.0, {"kb": 22.0, "heavy": true, "stagger": .8}))

func _s_cry() -> void:
	buff("cry", 8.0, {"dmg": 2.0}, "🗣️", "HADİ BAKALIM · 2× DAMAGE")
	Tts.say("Hadi bakalım!"); _sfx("rev"); _dance(.8)
	_teach("Hadi bakalım!")
	_toast("🗣️ [b]\"HADİ BAKALIM!\"[/b] · 2× damage for 8s — nearby enemies flee!", 5.0)
	if Fx.me: Fx.me.puff(_at(1.8), [Color("ffd66b"), Color("ff9a3d")], 18, 2.5, 2.0, .8); Fx.me.shake(.1)
	_wave(Color("ffd66b"), 10.0, .4)
	for e in _enemies_in(10.0): _estatus(e, "fear", 3.0)

func _s_nazar() -> void:
	torii.set_status("shield", 5.0)                   # 7.2's shieldUntil: nothing touches her
	_sfx("divine"); _sfx("nazar"); _dance(.5)
	_toast("🧿 [b]NAZAR KALKANI![/b] Nothing can touch you for 5 seconds. [i]Nazar değmesin![/i]", 4.5)
	if Fx.me: Fx.me.puff(_at(1.4), [Color("1f6fd0"), Color("f2f6ff"), Color("7bf7ff")], 30, 2.6, 2.2, 1.1)
	_wave(Color("2f7bff"), 2.6, .5)
	_teach("nazar boncuğu")

func _s_stars() -> void:
	_sfx("firework"); _sfx("divine"); _cast(.8)
	if Fx.me: Fx.me.shake(.5)
	var tg := _enemies_in(22.0)
	var dmg := float(70 + _lvl() * 6)
	_toast("🌠 [b]YILDIZ YAĞMURU![/b] %s · [i]yıldız[/i] = star" % (("%d target%s" % [tg.size(), "s" if tg.size() > 1 else ""]) if tg.size() else "the sky answers"), 4.5)
	for k in maxi(6, tg.size()):
		_stars.append({"t": .12 + k * .15, "e": tg[k % tg.size()] if tg.size() else null, "dmg": dmg})

# ---- new in Godot ----
# Rüzgar Koşusu: a quick wind dash (≈7 m) she can't be hurt in, towards the lock / whoever's in front;
# anything she passes through gets hit and shoved
func _s_dash() -> void:
	var dir := _facing()
	var lt := _nearest(9.0, .5)
	if lt:
		var to := lt.global_position - torii.global_position; to.y = 0
		if to.length() > .5: dir = to.normalized()
	_dash = {"t": .22, "dir": dir, "hit": {}}
	torii.set_status("shield", .35)
	_cast(.3); _sfx("whoosh"); _sfx("roll")
	_toast("💨 [b]RÜZGAR KOŞUSU![/b] · [i]rüzgar[/i] = wind", 2.5)
	_teach("rüzgar")

# Nazar Mermisi: a nazar bead shot that homes in on the locked / nearest monster in front of her
func _s_bolt() -> void:
	var tgt := _nearest(28.0, .2)
	var orb := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = .26; sm.height = .52; sm.radial_segments = 6; sm.rings = 3
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("2f7bff"); sm.material = mat; mi.mesh = sm; orb.add_child(mi)
	var core := MeshInstance3D.new()                  # the white of the eye
	var cm := SphereMesh.new(); cm.radius = .14; cm.height = .28; cm.radial_segments = 6; cm.rings = 3
	var cmat := StandardMaterial3D.new(); cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color("f2f6ff"); cm.material = cmat; core.mesh = cm; core.position = Vector3(0, 0, -.16)
	orb.add_child(core)
	for c in [mi, core]: c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torii.get_parent().add_child(orb)
	orb.global_position = _at(1.3) + _facing() * .7
	_bolts.append({"node": orb, "target": tgt, "dir": _facing(), "life": 2.5})
	_cast(.25); _sfx("zap")
	if Fx.me: Fx.me.muzzle(orb.global_position, _facing(), Color("7bf7ff"))

# Çay Molası: a tea break — 25% HP now, a little regen and haste for 6 s
func _s_tea() -> void:
	torii.heal(int(round(torii.max_hp * .25)))
	buff("tea", 6.0, {"regen": torii.max_hp * .03}, "🫖", "ÇAY MOLASI")
	torii.set_status("haste", 6.0)
	_sfx("drink"); _sfx("heal"); _cast(.6)
	if Fx.me: Fx.me.flash("heal"); Fx.me.heal(_at(.2)); Fx.me.puff(_at(1.6), [Color("f2f6ff"), Color("ffd66b")], 14, .8, 1.6, 1.2, .5)
	_toast("🫖 [b]ÇAY MOLASI![/b] A tea break fixes everything · [i]çay[/i] = tea")
	_teach("çay")

# ---- buffs ----
# any system: Skills.me.buff("kahve", 120, {"speed": 1.2}, "☕", "TÜRK KAHVESİ"). Re-buffing refreshes the timer.
func buff(id: String, sec: float, mods := {}, icon := "", title := "", bad := false) -> void:
	if not torii: return
	var src := "buff:" + id
	torii.clear_mods(src)
	for k in mods: torii.set_mod(src, k, float(mods[k]))
	buffs[id] = {"left": sec, "total": sec, "icon": icon if icon != "" else "✨", "name": title if title != "" else id.to_upper(), "bad": bad}

# the same thing for bad ones (7.2's hex slow, drunk, Josh's slow): shown red-flagged in active_buffs()
func debuff(id: String, sec: float, mods := {}, icon := "", title := "") -> void:
	buff(id, sec, mods, icon, title, true)

# 7.2's addBuff(k): dmg2 spd shield regen lucky focus caffeine. items.gd owns them; this is the fallback.
func add_buff(k: String) -> void:
	if Items.me and is_instance_valid(Items.me): Items.me.add_buff(k); return
	if not BUFFS.has(k): return
	var B: Dictionary = BUFFS[k]
	buff(k, float(B["dur"]), B["mods"], B["ic"], B["n"])
	_toast("%s [b]%s[/b] for %ds!" % [B["ic"], B["n"], int(B["dur"])], 5.0); _sfx("ding")

func has_buff(id: String) -> bool:
	if buffs.has(id): return true
	return Items.me != null and is_instance_valid(Items.me) and Items.me.has_buff(id)

func clear_buff(id: String) -> void:
	if not buffs.has(id): return
	buffs.erase(id)
	if torii: torii.clear_mods("buff:" + id)

func clear_buffs() -> void:
	for id in buffs.keys(): clear_buff(id)

# for the HUD: [{id, icon, ic, name, n, left, total, max, bad}] — ours, items.gd's food buffs, her statuses
func active_buffs() -> Array:
	var out := []
	for id in buffs:
		var b: Dictionary = buffs[id]
		out.append(_chip(id, b["icon"], b["name"], b["left"], b["total"], b["bad"]))
	var item_shield := false
	if Items.me and is_instance_valid(Items.me):
		for b in Items.me.buff_list():
			var k := str(b.get("id", ""))
			if k == "shield": item_shield = true
			var tot := float(b.get("left", 1.0))
			var BD = Items.me.D.get("BUFFS", {})
			if BD is Dictionary and BD.has(k): tot = float(BD[k].get("dur", tot))
			out.append(_chip(k, str(b.get("ic", "✨")), str(b.get("n", k)), float(b.get("left", 0.0)), tot, false))
	if torii and "status" in torii and torii.status is Dictionary:
		for k in torii.status:
			var left := float(torii.status[k])
			if left <= .05 or not STATUS.has(k): continue
			_st_total[k] = maxf(float(_st_total.get(k, 0.0)), left)
			if k == "shield" and (item_shield or left < .5): continue   # the item chip says it already / dash blips
			out.append(_chip("st:" + k, STATUS[k][0], STATUS[k][1], left, _st_total[k], k in ["burn", "poison", "slow", "stun"]))
		for k in _st_total.keys(): if not torii.status.has(k): _st_total.erase(k)
	return out

func _chip(id: String, ic: String, n: String, left: float, total: float, bad: bool) -> Dictionary:
	return {"id": id, "icon": ic, "ic": ic, "name": n, "n": n, "left": left, "total": total, "max": total, "bad": bad}

# for the HUD hotbar: [{id, name, icon, key, cd_left, cd_total, cd_max, mana, ready, locked, lv, lock_text, nomana, new}]
func hotbar() -> Array:
	var out := []
	var mana := _mana() if torii else 0.0
	for i in SK.size():
		var sk: Dictionary = SK[i]
		var lk := _locked(i)
		var miss := _missing(i)
		var cost := mana_cost(i)
		out.append({"id": sk["id"], "name": sk["n"], "icon": sk["ic"], "key": KEYS[i],
			"cd_left": maxf(0.0, cds[i]), "cd_total": cd_total(i), "cd_max": cd_total(i), "mana": cost,
			"ready": not lk and not miss and cds[i] <= 0 and mana >= cost and torii != null and not torii.on_bike,
			"locked": lk, "lv": int(sk.get("lv", 0)), "lock_text": ("Lv%d" % int(sk["lv"])) if lk else ("🎸" if miss else ""),
			"nomana": miss or mana < cost, "new": sk.get("new", false)})
	return out

func _check_unlocks() -> void:
	for i in SK.size():
		var id: String = SK[i]["id"]
		if _locked(i) or _unlocked.has(id): continue
		_unlocked[id] = true
		_toast("🔓 New skill: %s [b]%s[/b] — press [b]%s[/b]!" % [SK[i]["ic"], SK[i]["n"], KEYS[i]], 7.0)
		_sfx("fanfare")

func _on_mission_done(d: Dictionary) -> void:
	refresh()
	var i := int(d.get("i", -1))
	if (i == 16 or i == 19) and torii: torii.add_mana(torii.max_mana)   # 7.2's arena + final rewards fill mana

# ---- the +10 mana every right answer gives (finishQ) ----
func _on_answer(ok: bool, _q: Dictionary) -> void:
	if ok and torii: torii.add_mana(10)

# ---- battle quiz (battleQuiz) ----
func _on_boss_quiz(d: Dictionary) -> void:
	var e = d.get("enemy")
	if _alive(e) and not _bq.has(e): _bq.append(e)

func _battle_quiz(e) -> void:
	var L := Lessons.me
	var D: Dictionary = L.data
	var q := {}
	var gq: Array = D.get("GQ", [])
	if randf() < .6 and gq.size():                    # grammarQ()
		var g: Dictionary = gq.pick_random()
		q = {"kind": "mc", "text": g["q"], "opts": g["opts"], "a": int(g["a"]), "expl": g.get("expl", "")}
	else:                                             # vocabQ(WORDS.filter(w => w.t >= 2))
		var pool: Array = D.get("WORDS", []).filter(func(w): return int(w["t"]) >= 2)
		if pool.is_empty(): pool = D.get("WORDS", [])
		if pool.is_empty(): return
		q = L._vocab_q(pool)
	q["vis"] = "⚔️"
	L.quiz.run([q], func(score): _battle_result(e, score.size() > 0 and score[0]), "⚔️ BATTLE QUIZ")

func _battle_result(e, ok: bool) -> void:
	if not _alive(e) or not torii: return
	var nm := "BOSS"
	if Enemy.DATA.has(e.type): nm = str(Enemy.DATA[e.type].get("name", nm)).to_upper()
	if ok:
		e.stun(3.5 / .4)                              # enemy.stun() cuts boss stuns to 40%; 7.2 gave the full 3.5 s
		if "crit_next" in torii: torii.crit_next = true
		torii.heal(10); _sfx("yes")
		if Fx.me: Fx.me.label(e.global_position + Vector3(0, 3.0, 0), "STUNNED! ⚡", Color("ffd66b"), 1.4)
		_toast("⚡ [b]%s STUNNED![/b] Your Turkish is a weapon — next hit +50%%!" % nm, 6.0)
	else:
		e.hp = minf(e.max_hp, e.hp + e.max_hp * .1)
		torii.hp = maxi(1, torii.hp - 10); torii.hp_changed.emit(torii.hp, torii.max_hp); _sfx("no"); _sfx("hurt")
		if Fx.me: Fx.me.flash("hurt"); Fx.me.shake(.2)
		_toast("💢 Wrong! The boss fed on that mistake and healed 10%!", 6.0, true)

# ---- the clock ----
func _physics_process(dt: float) -> void:
	if not torii: return
	_hook_quiz()
	_refresh_t -= dt
	if _refresh_t <= 0: _refresh_t = 2.0; refresh()       # quest / mission rewards land without telling us
	if not _bq.is_empty() and not Overlay.any() and not QuizUI.open and Lessons.me and not torii.dead:
		var b = _bq.pop_front()
		if _alive(b): _battle_quiz(b)
	if Overlay.any(): return                         # the fight stops while a menu is up; so do timers
	for i in cds.size(): cds[i] = maxf(0.0, cds[i] - dt)
	for id in buffs.keys():
		buffs[id]["left"] -= dt
		if buffs[id]["left"] <= 0: clear_buff(id)
	for w in _later.duplicate():
		w["t"] -= dt
		if w["t"] <= 0:
			_later.erase(w)
			if not torii.dead: (w["cb"] as Callable).call()
	_tick_strike(dt)
	_tick_dash(dt)
	_tick_bolts(dt)
	_tick_stars(dt)

func _tick_strike(dt: float) -> void:
	if _strike == null: return
	_strike_t -= dt
	if not _alive(_strike) or _strike_t <= 0: _end_strike(); return
	if not bandit or not is_instance_valid(bandit): _bite(); return
	var to := _strike.global_position - bandit.global_position; to.y = 0
	if to.length() > 1.1:
		bandit.global_position += to.normalized() * 32.0 * dt
		bandit.rotation.y = atan2(to.x, to.z)
		bandit.global_position.y = _strike.global_position.y + absf(sin(_strike_t * 14.0)) * .3
		var legs = bandit.get("legs")
		if legs is Array:
			for k in legs.size():
				if legs[k]: legs[k].rotation.x = sin(_strike_t * 18.0 + (k % 2) * PI) * .8
		if Fx.me and randf() < dt * 20: Fx.me.puff(bandit.global_position + Vector3(0, .3, 0), Color("9a94a8"), 1, .4, .4, .3)
	else: _bite()

func _tick_dash(dt: float) -> void:
	if _dash.is_empty(): return
	_dash["t"] -= dt
	torii.move_and_collide(_dash["dir"] * 34.0 * dt)
	if Fx.me: Fx.me.puff(_at(.9), [Color("7bf7ff"), Color("f2f6ff")], 2, .3, .3, .35)
	for e in _enemies_in(1.8):
		if _dash["hit"].has(e): continue
		_dash["hit"][e] = true
		_hit(e, float(30 + 2 * _lvl()), {"kb": 10.0, "stagger": .4})
	if _dash["t"] <= 0: _dash = {}

func _tick_bolts(dt: float) -> void:
	for b in _bolts.duplicate():
		var n: Node3D = b["node"]
		if not is_instance_valid(n): _bolts.erase(b); continue
		b["life"] -= dt
		var tg = b["target"]
		if _alive(tg):                               # steer towards the target's chest
			var want: Vector3 = (tg.global_position + Vector3(0, 1.0, 0) - n.global_position).normalized()
			b["dir"] = (b["dir"] as Vector3).lerp(want, minf(1.0, dt * 9.0)).normalized()
		n.global_position += b["dir"] * 24.0 * dt
		n.rotate_y(dt * 12.0)
		if Fx.me and randf() < dt * 30: Fx.me.puff(n.global_position, [Color("2f7bff"), Color("f2f6ff")], 1, .2, .2, .3)
		var hit: Node3D = null
		for e in _enemies_in(1.1, n.global_position):
			if absf(e.global_position.y + 1.0 - n.global_position.y) < 1.8: hit = e; break
		if hit:
			_hit(hit, float(40 + 3 * _lvl()), {"stagger": .5})
			if Fx.me: Fx.me.puff(n.global_position, [Color("2f7bff"), Color("f2f6ff"), Color("7bf7ff")], 12, 1.6, 1.4, .5)
			b["life"] = 0.0
		if b["life"] <= 0:
			n.queue_free(); _bolts.erase(b)

func _tick_stars(dt: float) -> void:
	for s in _stars.duplicate():
		s["t"] -= dt
		if s["t"] > 0: continue
		_stars.erase(s)
		var e = s["e"]
		var at := torii.global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
		if _alive(e): at = e.global_position
		if Fx.me:
			Fx.me.puff(Vector3(at.x, at.y + randf_range(3, 6), at.z), FIRE.pick_random(), 16, 2.4, 1.2, .9, .4)
			Fx.me.puff(at + Vector3(0, .5, 0), [Color("ffd66b"), Color.WHITE], 10, 1.8, 2.4, .7)
			Fx.me.shockwave(at + Vector3(0, .05, 0), 2.0, FIRE.pick_random(), .3)
		_sfx("firework")
		if _alive(e): _hit(e, s["dmg"], {"stagger": .3})
