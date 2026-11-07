# Torii's melee moveset — 7.2's tryAttack() / hitEnemy() / useDurability() grown into a PS1 action set:
#  light (F / left click): a 3-hit chain (forehand, backhand, overhead finisher with knockback); bare hands
#     kick instead (snap, roundhouse, spin kick). Press again during a swing to queue the next hit.
#  heavy (RIGHT mouse): a wind-up you can hold to charge, costs stamina, staggers and launches
#  jump attack (attack in the air): a downward slam that hits all round her on landing
#  sprint attack (attack while sprinting): a dashing slash through everything in front
#  Josh's Device keeps 7.2's shock (zaps everyone near, shocks her too, never kills her);
#  ranged weapons go to Arsenal.fire() when Arsenal is there.
# The weapon's 7.2 stats (dmg / cd / rng / arc) set the feel: low cd = quick, light chains; high cd =
# slow heavy swings. Every swing wears the weapon like 7.2 (per swing, not per hit). Every swing draws a
# blade ribbon (Fx.swipe); the finisher / heavy / slam add hit-stop and shake. The swing and hit sounds,
# damage numbers and sparks come from Audio / Fx / Enemy hearing Bus "player_attack" and "enemy_hit".
class_name Combat
extends RefCounted

var p                                # the player (player.gd)
var state := ""                      # "", "light", "heavy", "slam", "dash", "shock"
var phase := ""                      # heavy: "wind" / "go"; slam: "air" / "land"
var step := 0                        # light chain step 0..2
var st := 0.0                        # seconds into the current move
var dur := .4
var hit_a := .1                      # the hit window (seconds into the move)
var hit_b := .2
var queued := false                  # attack pressed mid-swing: the next chain hit follows
var chain_t := 0.0                   # time left to carry on the chain after a swing ends
var charge := 0.0                    # heavy: 0..1 while held
var _hits := {}                      # enemies already hit by this move
var _connected := false
var _glow_t := 0.0
var _trailed := false

const STEP_DMG := [1.0, 1.15, 1.7]
const STEP_ARC := [1.0, 1.1, 1.3]
const STEP_RNG := [1.0, 1.0, 1.15]
const STEP_DUR := [.34, .36, .52]     # mid-weight weapon; the weapon's tempo scales these
const STEP_HIT := [[.1, .2], [.11, .21], [.2, .32]]
const HEAVY_COST := 18.0
const DASH_COST := 10.0

func _init(player) -> void:
	p = player

func busy() -> bool: return state != ""

# past the hit window: a roll, a jump or the next attack may cut the recovery short
func can_cancel() -> bool:
	return state == "" or ((state == "light" or state == "dash" or (state == "slam" and phase == "land")
		or (state == "heavy" and phase == "go")) and st > hit_b + .02)

# how much she can move while attacking (heavy wind-up roots her)
func move_mult() -> float:
	match state:
		"light": return .35 if st < hit_b else .6
		"heavy": return .15
		"slam": return .0 if phase == "land" else 1.0
		"shock": return .4
	return 1.0

func cancel() -> void:
	state = ""; phase = ""; queued = false; charge = 0.0

# weapon weight class from 7.2's stats
func wclass() -> String:
	var w: Dictionary = p.weapon
	if w.get("id", "") == "kick": return "kick"
	var cd: float = w.get("cd", .45)
	if cd <= .36: return "fast"
	if cd >= .8 or (w.get("dmg", 0.0) >= 60.0 and cd >= .6): return "heavy"
	return "mid"

# swing speed: 7.2's cd (katana .45 = 1.0), the seri perk / caffeine (mods cd) and haste
func tempo() -> float:
	var cd: float = p.weapon.get("cd", .45)
	var tp := clampf(sqrt(.45 / maxf(.1, cd)), .72, 1.4)
	tp /= maxf(.4, p.mod("cd"))
	if p.has_status("haste"): tp *= 1.2
	return tp

func _kick() -> bool: return p.weapon.get("id", "") == "kick"

# ---------------- input ----------------
func light() -> void:
	if p.on_bike:
		p.toast("Bisiklette savaşamazsın! 🚲 (Not while riding!)", 2.0, true); return
	if p.dance_t > 0 or p.has_status("stun") or p.rolling or p.ledge != "": return
	if state == "light":
		queued = true; return
	if state != "" and not (state == "dash" and can_cancel()): return
	var ars = p.arsenal()
	if ars and ars.is_ranged(p.weapon):                     # guns + Josh's Device: Arsenal fires (and emits)
		ars.fire(p)
		p.cast_t = maxf(p.cast_t, .18)
		return
	if p.weapon.get("shock", false): _start_shock(); return
	if not p.is_on_floor() and p.air_t > .12:
		_start_slam(); return
	if p.sprinting and p.spend_stamina(DASH_COST):
		_start_dash(); return
	step = (step + 1) % 3 if chain_t > 0 else 0
	_start_light()

func heavy_press() -> void:
	if p.on_bike:
		p.toast("Bisiklette savaşamazsın! 🚲 (Not while riding!)", 2.0, true); return
	if p.dance_t > 0 or p.has_status("stun") or p.rolling or p.ledge != "" or not p.is_on_floor(): return
	if state != "" and not (state == "light" and can_cancel()): return      # L, L, HEAVY works
	var ars = p.arsenal()
	if ars and ars.is_ranged(p.weapon):                     # right click with a gun = Arsenal's heavy volley
		ars.fire(p, true)
		p.cast_t = maxf(p.cast_t, .25)
		return
	if not p.spend_stamina(HEAVY_COST):
		p.say_tired(); return
	state = "heavy"; phase = "wind"; st = 0.0; charge = 0.0; _hits = {}; _connected = false; queued = false
	_sfx("charge")

# ---------------- moves ----------------
func _begin(s: String, d: float, a: float, b: float) -> void:
	state = s; st = 0.0; dur = d; hit_a = a; hit_b = b; _hits = {}; _connected = false; queued = false; _trailed = false

func _start_light() -> void:
	var tp := tempo()
	var k := 1.12 if wclass() == "heavy" else (.9 if wclass() == "fast" else 1.0)
	_begin("light", STEP_DUR[step] * k / tp, STEP_HIT[step][0] * k / tp, STEP_HIT[step][1] * k / tp)
	_swing_fx()
	# a little step into the swing; locked on and out of reach, she lunges further to close in
	var reach: float = p.weapon.get("rng", 2.4)
	var lv := 2.6 + (2.0 if step == 2 else 0.0)
	if p.lock_target and is_instance_valid(p.lock_target):
		var d: float = (p.lock_target.global_position - p.global_position).length()
		if d > reach * .8: lv = clampf((d - reach * .6) * 3.5, lv, 9.0)
	p.lunge(lv)
	Bus.emit_ev("player_attack", {"kind": "light", "combo": step + 1})

func _swing_fx() -> void:
	p.wear()
	var id: String = p.weapon.get("id", "")
	var f: Vector3 = p.facing()
	if Fx.me and id == "bass": Fx.me.puff(p.global_position + f * 1.5 + Vector3(0, 1.2, 0), Color("7bf7ff"), 10, 2.4, 1.4, .5, .9)
	if Fx.me and id == "zeybek": Fx.me.puff(p.global_position + f * 1.6 + Vector3(0, 1.4, 0), Color("ffe9a0"), 8, 2.0, 1.6, .45, .8)

func _start_dash() -> void:
	_begin("dash", .42 / clampf(tempo(), .85, 1.2), .04, .3)
	step = 0; chain_t = 0.0
	_swing_fx(); _sfx("woosh2")
	p.lunge(14.0)
	Bus.emit_ev("player_attack", {"kind": "light", "combo": 0})

func _start_slam() -> void:
	_begin("slam", 9.0, 0.0, 0.0); phase = "air"
	p.velocity.y = -20.0
	_swing_fx()
	Bus.emit_ev("player_attack", {"kind": "heavy", "combo": 0})

# 7.2's shock weapon (Josh's Device): everything in range is zapped, stunned and slowed; it bites her too
func _start_shock() -> void:
	var w: Dictionary = p.weapon
	_begin("shock", maxf(.3, float(w.get("cd", .8)) / tempo()), 0.0, 0.0)
	p.wear(); _sfx("zap")
	var n := 0
	for e in _enemies():
		var to: Vector3 = e.global_position - p.global_position; to.y = 0
		if to.length() > float(w.get("rng", 8.0)): continue
		n += 1
		p.hit_enemy(e, _dmg(1.0)[0], to.normalized(), {"stagger": .8, "status": "stun", "kb": 3.0})
		if Fx.me:
			for i in range(1, 7):
				var f2 := i / 7.0
				Fx.me.puff(p.global_position + to * f2 + Vector3(randf_range(-.25, .25), 1.4 + randf_range(-.3, .3), randf_range(-.25, .25)),
					[Color("7bf7ff"), Color.WHITE, Color("b06bff")], 1, .4, .6, .28)
	if Fx.me:
		Fx.me.puff(p.global_position + Vector3(0, 1.5, 0), Color("7bf7ff"), 10, 2.4, 2.0, .5, .7); Fx.me.shake(.25)
	var self_d := 5 if n > 0 else 3
	p.hp = maxi(3, p.hp - self_d); p.hp_changed.emit(p.hp, p.max_hp)
	if Fx.me:
		Fx.me.flash("hurt"); Fx.me.label(p.global_position + Vector3(0, 3, 0), "-%d ⚡ (it shocks YOU too)" % self_d, Color("ff9ecf"), 1.5)
	if n > 0: p.toast("📡 [b]ZAP![/b] %d enem%s shocked & stunned · you took %d 🙃" % [n, "y" if n == 1 else "ies", self_d], 4.5)
	Bus.emit_ev("player_attack", {"kind": "light", "combo": 0})

# ---------------- per frame ----------------
func update(dt: float) -> void:
	chain_t -= dt
	if state == "": return
	st += dt
	match state:
		"light":
			if not _trailed and st >= hit_a * .7: _trail()
			if st >= hit_a and st <= hit_b:
				_strike(float(p.weapon.get("rng", 2.4)) * STEP_RNG[step], float(p.weapon.get("arc", 1.1)) * STEP_ARC[step], STEP_DMG[step],
					{"kb": 14.0 if step == 2 else 5.0, "stagger": .5 if step == 2 else .15, "heavy": step == 2}, step == 2)
			if queued and st >= hit_b + .03 and step < 2:
				step += 1; _start_light(); return
			if st >= dur:
				chain_t = .32 if step < 2 else 0.0
				if step == 2: step = 0
				state = ""
		"dash":
			if not _trailed: _trail()
			if st >= hit_a and st <= hit_b:
				_strike(float(p.weapon.get("rng", 2.4)) + .6, 1.2, 1.4, {"kb": 10.0, "stagger": .4}, true)
			if st >= dur: state = ""
		"shock":
			if st >= dur: state = ""
		"slam":
			if phase == "air":
				p.velocity.y = minf(p.velocity.y, -20.0)
				if p.is_on_floor() or st > 3.0: _slam_land()
			elif st >= .38: state = ""; phase = ""
		"heavy":
			if phase == "wind":
				var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
				var min_w := .34 / tempo()
				if held:
					var was := charge
					charge = clampf((st - min_w) / .55, 0.0, 1.0)
					if charge >= 1.0 and was < 1.0:      # fully charged: a flash in her hands
						_sfx("ding")
						if Fx.me: Fx.me.puff(p.hand_pos(), [Color.WHITE, Color("7bf7ff")], 6, 1.2, 1.0, .3, .5)
				_glow_t -= dt
				if _glow_t <= 0 and Fx.me:          # the tell: sparks gathering in her hand
					_glow_t = .07
					Fx.me.puff(p.hand_pos(), [Color("ff5fa2"), Color("ffd66b")] if charge < 1.0 else [Color.WHITE, Color("7bf7ff")], 1, .3, .6, .25)
				if st >= min_w and (not held or st >= min_w + 1.4):
					var tp := tempo()
					phase = "go"; st = 0.0; dur = .46 / clampf(tp, .8, 1.25); hit_a = .07; hit_b = .17
					p.lunge(4.0 + charge * 3.0)
					_trailed = false
					Bus.emit_ev("player_attack", {"kind": "heavy", "combo": 0})
					p.wear()
			else:
				if not _trailed and st >= hit_a * .5: _trail()
				if st >= hit_a and st <= hit_b:
					var r: float = float(p.weapon.get("rng", 2.4)) * (1.1 + charge * .15)
					_strike(r, float(p.weapon.get("arc", 1.1)) * 1.25, 2.2 + charge * 1.2,
						{"heavy": true, "kb": 15.0 + charge * 8.0, "stagger": 1.0 + charge * .6}, true)
				if st >= dur: state = ""; phase = ""; charge = 0.0

func _slam_land() -> void:
	phase = "land"; st = 0.0
	var at: Vector3 = p.global_position
	var n := _strike(3.4, PI, 1.5, {"heavy": true, "kb": 11.0, "stagger": .7}, true, true)
	if Fx.me:
		for i in 14:
			var a := i / 14.0 * TAU
			Fx.me.puff(at + Vector3(cos(a) * 1.4, .2, sin(a) * 1.4), [Color("cabfd8"), Color("9a94a8")], 1, 1.4, .8, .5, .9)
		Fx.me.puff(at + Vector3(0, .4, 0), [Color("ff5fa2"), Color("ffd66b")], 8, 2.2, 1.6, .45, .6)
		Fx.me.shake(.32 if n > 0 else .2)
		Fx.me.shockwave(at, 3.4, Fx.PINK, .3)
	_sfx("land_hard"); _sfx("thud")
	p.squash(.3)

# 7.2's hitEnemy damage: weapon dmg x her mods (level, perks, gear, buffs) x the move; crits x1.8
# (a parry riposte or skill's crit_next: x1.5, like 7.2's critNext)
func _dmg(mult: float) -> Array:
	var d: float = float(p.weapon.get("dmg", 9.0)) * mult * p.mod("dmg")
	var crit := false
	if p.crit_next: d *= 1.5; p.crit_next = false; crit = true
	elif randf() < p.mod("crit"): d *= 1.8; crit = true
	return [float(round(d)), crit]

func _enemies() -> Array:
	return p.get_tree().get_nodes_in_group("enemies").filter(func(e): return p.alive(e))

# hits everything in the arc once per move; returns how many it hit
func _strike(rng: float, arc: float, mult: float, opts: Dictionary, big := false, ring := false) -> int:
	var n := 0
	var f: Vector3 = p.facing()
	var c: Vector3 = p.global_position
	for e in _enemies():
		var id: int = e.get_instance_id()
		if _hits.has(id): continue
		var to: Vector3 = e.global_position - c
		if absf(to.y) > 2.8: continue
		to.y = 0
		var d := to.length()
		var extra := 1.0 if (e.get("flags") is Dictionary and e.flags.has("boss")) else (.4 if e.get("elite") else 0.0)
		if d > rng + extra: continue
		if not ring and d > .45 and absf(f.signed_angle_to(to / d, Vector3.UP)) > arc: continue
		_hits[id] = true
		var r := _dmg(mult)
		var o := opts.duplicate(); o["crit"] = r[1]
		var dir := to / d if d > .01 else f
		p.hit_enemy(e, r[0], dir, o)
		n += 1
	if n > 0 and not _connected:                          # the first contact of a move: a bigger freeze on big ones
		_connected = true
		var heavy: bool = opts.get("heavy", false)
		if big: p.hitstop(.1 if heavy else .075)
		if Fx.me and big: Fx.me.shake(.22 if heavy else .12)
	return n

# the blade ribbon for the current move (PS1 banded trail): forehand flat, backhand rising the other way,
# finisher an overhead chop in pink, heavy a wide gold arc, kicks low and short, the spin kick all the way round
func _trail() -> void:
	_trailed = true
	if not Fx.me: return
	var f: Vector3 = p.facing()
	var at: Vector3 = p.global_position
	var r: float = clampf(float(p.weapon.get("rng", 2.4)), 1.4, 3.6)
	var life := clampf(hit_b - hit_a + .1, .12, .3)
	if _kick():
		match state:
			"light":
				if step == 2: Fx.me.swipe(at, f, 1.7, TAU * .95, Fx.PINK, .9, 0.0, false, .22, .6)
				else: Fx.me.swipe(at, f, 1.6, 1.4, Fx.CYAN, .8 if step == 0 else 1.1, .5 * (1 if step == 0 else -1), step == 1, life, .45)
			_: Fx.me.swipe(at, f, 1.8, 1.2, Fx.CYAN, .9, 0.0, false, life, .5)
		return
	match state:
		"light":
			match step:
				0: Fx.me.swipe(at, f, r, 2.2, Fx.CYAN, 1.25, .35, false, life, .55)
				1: Fx.me.swipe(at, f, r, 2.3, Fx.CYAN, 1.35, -.6, true, life, .55)
				_: Fx.me.swipe(at, f, r * 1.1, 2.0, Fx.PINK, 1.0, PI / 2, false, life + .04, .7)
		"dash": Fx.me.swipe(at, f, r + .4, 1.5, Fx.CYAN, 1.15, 0.0, false, .2, .6)
		"heavy": Fx.me.swipe(at, f, r * 1.15, 2.7, Fx.GOLD if charge < 1.0 else Color.WHITE, 1.15, .2, false, .24, .85)

func _sfx(n: String) -> void:
	Bus.emit_ev("sfx", {"name": n, "pos": p.global_position})
