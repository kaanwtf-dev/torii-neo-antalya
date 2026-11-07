# Torii — 7.2's controls: W/S (or ↑/↓) walk, A/D strafe, ←/→ turn her, the mouse aims, Shift sprints,
# Space jumps, E gets on/off the bike, F / left click attacks, Q (tap) or the mouse wheel next weapon
# (hold Q = Arsenal's weapon wheel), C looks behind. On the bike: W pedal, S brake/reverse, A/D (or ←/→)
# steer, Space boost, Space held into a corner = drift; the camera drifts back behind the bike 1.3 s after
# the mouse stops (7.2's updatePlayer / updateCam / bikeCrash / bikeRam).
# New in Godot (PS1 action feel): RIGHT mouse heavy attack (hold to charge), Left Ctrl dodge roll (i-frames),
# Z block (start it just before a hit = PARRY), Tab lock-on (Tab again = next target), jump at a ledge to
# grab it and climb up. Movement has weight (acceleration, coyote time, jump buffer, variable jump height),
# stamina pays for sprint / roll / heavy / bike boost (7.2's winded rule), mana regenerates slowly.
# The moves live in combat.gd, the lock-on marker in lockon.gd, the poses in torii_pose.gd.
# While an overlay is open (a lesson, a call, a choice, the save screen) she waits and can't be hurt.
# At 0 HP she faints like 7.2 (die): −10% lira, −30% of this level's XP, back at her checkpoint.
# Mods: other systems (perks, gear, buffs, skills) call set_mod(source, key, value) / clear_mods(source).
#   Multiplied across sources: dmg, speed, cd (attack time), bike, boostcost, sprintcost, rdmg, manacost, kb.
#   def = damage taken factor (stats.gd writes 1 - armour; a value > 1 like a shield's 3.0 means "divide by").
#   Added: crit (chance), regen (HP/s), mregen (mana/s), sregen (stamina regen +%).
extends CharacterBody3D

signal hp_changed(hp, max_hp)
signal stats_changed()

const WALK := 7.3                  # 7.2: forward 7.3, back 4.3, strafe 6.2
const BACK := 4.3
const STRAFE := 6.2
const SPRINT := 1.62               # Shift: forward x1.62, strafe x1.34
const TURN := 2.95                 # arrow keys turn her, for anyone without a mouse
const JUMP := 7.4
const GRAVITY := 22.0
const FALL_G := 1.3                # she falls a bit faster than she rises: weight
const MAX_FALL := 42.0
const ACCEL := 46.0                # ground: speeding up / slowing down (m/s²)
const DECEL := 34.0
const AIR_ACCEL := 13.0            # air control
const COYOTE := .12                # a jump still works this long after running off an edge
const JUMP_BUF := .14              # ...and a jump pressed this early before landing still happens
const ROLL_T := .5
const ROLL_IFR := .35              # untouchable for the first .35 s of a roll
const ROLL_SPD := 11.5
const ROLL_COST := 20.0
const PARRY_WIN := .18             # block pressed this soon before a hit = parry
const SPRINT_COST := 26.0          # 7.2: 26/s x sprintcost
const MANA_REGEN := .5             # per second (7.2 had none; tavla / food still top it up)
const SLIDE_ANGLE := 47.0          # steeper ground than this: she slides down it
const SENS := 0.0022               # 7.2's mouse look
# 7.2's ZB: the city rectangle, and the three 76 m islands abroad
const BOUNDS := {"city": [-520, 152, -424, 332], "cam": [562, 638, -38, 38], "az": [562, 638, 262, 338], "liv": [562, 638, -338, -262]}
const MUL_KEYS := ["dmg", "speed", "cd", "bike", "boostcost", "sprintcost", "rdmg", "manacost", "kb", "def"]

var yaw := 0.0                     # where the camera looks; on foot she faces it, on the bike it's free
var pitch := .12                   # 7.2: higher = camera up and looking down; mouse down raises it
var heading := 0.0                 # the bike's own direction
var look_t := -10.0                # last mouse movement (the riding camera re-centres 1.3 s after)
var look_back := false
var cam_off := 0.0                 # dev shots only: swing the camera round her
var _cam_snap := true
var _cam_py := 0.0                 # her height as the camera sees it (eased, so jumps/climbs don't jolt)
var model: Node3D
var pose: ToriiPose
var cam: Camera3D
var shadow: MeshInstance3D
var combat: Combat
var _lock: LockOn
var t := 0.0
var spawn := Vector3(-24, .05, -8) # the city start (main.gd sets it); her checkpoint wins when she has one
var dead := false
var water: Array = []              # the sea and the river as [x0, x1, z0, z1, surface y] (main.gd)
var _safe := Vector3.ZERO          # last dry spot (water pushes her back here)
var _fall_vy := 0.0
# ---- the contract other systems use ----
var max_hp := 100
var hp := 100
var max_stamina := 100.0           # 7.2 save "ms"
var stamina := 100.0
var winded := false                # 7.2: emptied the bar, can't sprint/roll until it's back past 25%
var max_mana := 100.0              # 7.2 save "mm"
var mana := 50.0                   # 7.2 starts every load at min(50, max)
var lock_target: Node3D = null
var blocking := false
var rolling := false
var sprinting := false
var weapon := {"id": "katana", "n": "Katana 🗡", "dmg": 26.0, "cd": .45, "rng": 2.6, "arc": 1.1, "snd": "whoosh"}
var mods := {}                     # the combined multipliers (see the header)
var status := {}                   # id -> seconds left: burn, poison, slow, stun, shield, haste
var crit_next := false             # the next hit crits x1.5 (parry riposte, skills)
var immune_t := 0.0                # > 0: nothing hurts her (the level-up show)
var dance_t := 0.0                 # > 0: she's dancing (mission zones, victories, skills)
var cast_t := 0.0                  # > 0: skill-casting pose
var eat_t := 0.0                   # > 0: eating pose
var orbit_t := 0.0                 # > 0: the camera circles her (7.2's level-up show); see cam_orbit()
var drunk_t := 0.0                 # > 0: tipsy — the camera rolls, she drifts (7.2's drunk)
var hand: Node3D
var hurt_cd := 0.0
var air_t := 0.0                   # seconds since she left the ground
var ledge := ""                    # "", "hang", "climb"
var _mod_src := {}                 # source -> {key: value}
var _sig := 0
# moving
var _coyote := 0.0
var _jump_buf := 0.0
var _jumping := false
var _floor_y := 0.0                # last ground height she stood on
var _stam_wait := 0.0              # stamina only refills after a short breather
var _roll_t := 0.0
var _roll_dir := Vector3.FORWARD
var _roll_buf := 0.0
var _block_t0 := -10.0
var _flinch_t := 0.0
var _sq := 1.0                     # landing squash (1 = none)
var _ledge_t := 0.0
var _ledge_a := Vector3.ZERO       # hang spot
var _ledge_b := Vector3.ZERO       # standing spot on top
var _ledge_from := Vector3.ZERO
var _step_k := 0
var _dot_acc := 0.0
var _regen_acc := 0.0
var _fx_t := 0.0
var _orbit_len := 1.0
var _told := {}                    # one-time hints this session
var _lvl_seen := -1
# the bike
var bike: Node3D
var wheels: Array[Node3D] = []
var crank: Node3D
var on_bike := false
var bspeed := 0.0
var lean := 0.0
var boost_cd := 0.0
var drifting := false
var drift_t := 0.0
var slide := 0.0
var wobble_t := 0.0
var wipe := ""                     # off the bike: "fly", "down", "getup"
var _wipe_t := 0.0
var _wipe_hard := 0.0
var _wipe_spin := 0.0
var _wipe_side := 1.0
var _spin_a := 0.0
var _bike_down := Vector3.ZERO
const BIKE_REACH := 2.6

func set_bike(b: Node3D) -> void:
	bike = b
	for n in ["wheel_f", "wheel_b"]: wheels.append(b.find_child(n, true, false))
	crank = b.find_child("crank", true, false)

func setup(torii_scene: PackedScene) -> void:
	add_to_group("player")
	Engine.time_scale = 1.0
	floor_max_angle = deg_to_rad(55.0); floor_snap_length = .35
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = .32; cap.height = 2.2
	col.shape = cap; col.position.y = 1.1; add_child(col)
	model = torii_scene.instantiate()
	model.rotation.y = PI                     # the model faces +z; Godot's forward is -z
	add_child(model)
	var sk := _find_skeleton(model)
	if sk:
		pose = ToriiPose.new(sk)
		# her weapon hand: 7.2 hangs it .3 below the elbow of her +x arm, in the arms-down frame
		var ba := BoneAttachment3D.new(); ba.bone_name = "elb_p"; sk.add_child(ba)
		hand = Node3D.new(); hand.basis = Basis(Vector3(0, 0, 1), ToriiPose.ARMS_DOWN); ba.add_child(hand)
		var off := Node3D.new(); off.position = Vector3(0, -.3, 0); hand.add_child(off); hand = off
	cam = Camera3D.new(); cam.fov = 62; cam.near = .05; cam.far = 400; cam.top_level = true
	add_child(cam); cam.current = true
	# 7.2's blobShadow(player,.6,.42): a soft dark disc on the ground — it also shows where a jump lands
	var tex := GradientTexture2D.new(); tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(.5, .5); tex.fill_to = Vector2(1, .5); tex.width = 32; tex.height = 32
	var g := Gradient.new(); g.set_color(0, Color(0, 0, 0, 1)); g.set_color(1, Color(0, 0, 0, 0)); tex.gradient = g
	var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; sm.albedo_texture = tex; sm.albedo_color = Color(1, 1, 1, .42)
	var pm := PlaneMesh.new(); pm.size = Vector2(1.38, 1.38); pm.material = sm
	shadow = MeshInstance3D.new(); shadow.mesh = pm; shadow.top_level = true
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(shadow)
	combat = Combat.new(self)
	_lock = LockOn.new(); add_child(_lock)
	_recalc()
	_keys()
	Bus.on("level_up", func(_d): if is_instance_valid(self): refresh_from_save(); stamina = max_stamina)

# the new keys (only added if main.gd hasn't already): Left Ctrl roll, Z block, Tab lock-on.
# RIGHT mouse (heavy) is read straight from the mouse.
func _keys() -> void:
	for a in [["roll", KEY_CTRL], ["block", KEY_Z], ["lock_on", KEY_TAB]]:
		if InputMap.has_action(a[0]): continue
		InputMap.add_action(a[0])
		var ev := InputEventKey.new(); ev.keycode = a[1]; InputMap.action_add_event(a[0], ev)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s: return s
	return null

# max stamina / mana from the save (7.2's ms / mm); called when the save is in and on level-ups
func refresh_from_save() -> void:
	max_stamina = float(maxi(10, SaveBridge.get_i("ms", 100)))
	max_mana = float(maxi(10, SaveBridge.get_i("mm", 100)))
	if _lvl_seen < 0: stamina = max_stamina; mana = minf(50.0, max_mana)    # 7.2's applySave
	stamina = minf(stamina, max_stamina); mana = minf(mana, max_mana)
	_lvl_seen = SaveBridge.get_i("lvl", 1)
	stats_changed.emit()

# ---------------- mods ----------------
func set_mod(source: String, key: String, value: float) -> void:
	if not _mod_src.has(source): _mod_src[source] = {}
	_mod_src[source][key] = value
	_recalc()

func clear_mods(source: String) -> void:
	if _mod_src.erase(source): _recalc()

func mod(key: String) -> float:
	return float(mods.get(key, 1.0 if MUL_KEYS.has(key) else 0.0))

func _recalc() -> void:
	mods = {"dmg": 1.0, "speed": 1.0, "def": 1.0, "crit": 0.0, "regen": 0.0, "cd": 1.0, "bike": 1.0,
		"boostcost": 1.0, "sprintcost": 1.0, "rdmg": 1.0, "manacost": 1.0, "kb": 1.0, "mregen": 0.0, "sregen": 0.0}
	for s in _mod_src:
		for k in _mod_src[s]:
			var v := float(_mod_src[s][k])
			if k == "def": mods[k] = mods[k] * (v if v <= 1.0 else 1.0 / v)   # both styles mean "less damage"
			elif MUL_KEYS.has(k) or not mods.has(k) and v != 0.0 and k not in ["crit", "regen", "mregen", "sregen"]: mods[k] = float(mods.get(k, 1.0)) * v
			else: mods[k] = float(mods.get(k, 0.0)) + v
	stats_changed.emit()

# ---------------- statuses ----------------
func set_status(id: String, sec: float) -> void:
	var had := status.has(id)
	status[id] = maxf(float(status.get(id, 0.0)), sec)
	if id == "stun":
		if combat: combat.cancel()
		_roll_t = 0.0; rolling = false; blocking = false
	if not had: stats_changed.emit()
	if id == "stun" and not had and Fx.me: Fx.me.label(global_position + Vector3(0, 3.0, 0), "💫", Color("ffd66b"), .8)

func has_status(id: String) -> bool: return status.get(id, 0.0) > 0.0

func stun(sec: float) -> void: set_status("stun", sec)

func _tick_status(dt: float) -> void:
	for k in status.keys():
		status[k] -= dt
		if status[k] <= 0: status.erase(k); stats_changed.emit()
	# burn 4 HP/s, poison 3 HP/s; neither can finish her off on its own
	var dps := (4.0 if has_status("burn") else 0.0) + (3.0 if has_status("poison") else 0.0)
	if dps > 0:
		_dot_acc += dps * dt
		if _dot_acc >= 1.0:
			var n := int(_dot_acc); _dot_acc -= n
			hp = maxi(1, hp - n); hp_changed.emit(hp, max_hp)
	var rg := mod("regen")
	if rg > 0 and hp < max_hp:
		_regen_acc += rg * dt
		if _regen_acc >= 1.0:
			var n := int(_regen_acc); _regen_acc -= n
			hp = mini(max_hp, hp + n); hp_changed.emit(hp, max_hp)
	_fx_t -= dt
	if _fx_t <= 0 and Fx.me and not status.is_empty():
		_fx_t = .12
		var at := global_position + Vector3(0, 1.2, 0)
		if has_status("burn"): Fx.me.puff(at, [Color("ff8a3d"), Color("ffd66b")], 1, .4, 1.6, .4, .3)
		if has_status("poison"): Fx.me.puff(at, Color("5fff9e"), 1, .4, 1.0, .5, .3)
		if has_status("stun"): Fx.me.puff(global_position + Vector3(0, 2.4, 0), Color("ffd66b"), 1, .5, .2, .4)
		if has_status("slow"): Fx.me.puff(global_position + Vector3(0, .3, 0), Color("8ff2ff"), 1, .4, .2, .5)
		if has_status("shield"): Fx.me.puff(at, Color("7bf7ff"), 1, .7, .4, .4, .4)
		if has_status("haste") and Vector2(velocity.x, velocity.z).length() > 3: Fx.me.puff(at - facing() * .5, Color("ff5fa2"), 1, .2, .2, .3)

# ---------------- stamina / mana / hp ----------------
func spend_stamina(n: float) -> bool:
	if winded or stamina <= 0.0: return false
	stamina = maxf(0.0, stamina - n); _stam_wait = .55
	if stamina <= 0.0: _wind_out()
	return true

func _wind_out() -> void:
	winded = true; sprinting = false
	_sfx("winded")
	if Fx.me: Fx.me.label(global_position + Vector3(0, 3.4, 0), "nefesim kesildi! 😮‍💨", Color("ffd66b"), 1.4)

func say_tired() -> void:
	_sfx("no")
	if t - float(_told.get("tired_t", -9.0)) > 2.0:
		_told["tired_t"] = t
		if Fx.me: Fx.me.label(global_position + Vector3(0, 3.4, 0), "nefesim yok! 😮‍💨", Color("ffd66b"), 1.1)

func spend_mana(n: float) -> bool:
	if mana < n: return false
	mana -= n; stats_changed.emit()
	return true

func add_mana(n: float) -> void:
	mana = clampf(mana + n, 0.0, max_mana); stats_changed.emit()

func heal(n: int) -> void:
	hp = clampi(hp + n, 0, max_hp); hp_changed.emit(hp, max_hp)

func heal_full() -> void:
	hp = max_hp; hp_changed.emit(hp, max_hp)

func _regen(dt: float, moving: bool) -> void:
	_stam_wait -= dt
	if not on_bike and not sprinting and _stam_wait <= 0 and not blocking and not rolling:
		stamina = minf(max_stamina, stamina + (15.0 if moving else 24.0) * (1.0 + mod("sregen")) * dt)   # 7.2
	if winded and stamina > max_stamina * .25: winded = false
	mana = minf(max_mana, mana + (MANA_REGEN + mod("mregen")) * dt)
	var sg := int(stamina) * 7919 + int(mana) * 31 + (1 if winded else 0) + (2 if blocking else 0) + status.size() * 5
	if sg != _sig: _sig = sg; stats_changed.emit()

# ---------------- weapons ----------------
func hold(weapon_scene: PackedScene, stats: Dictionary) -> void:
	weapon = stats
	if not hand: return
	for c in hand.get_children(): c.queue_free()
	if weapon_scene: hand.add_child(weapon_scene.instantiate())

# her weapons = the save's `weap` list (7.2's names and stats); Q or the mouse wheel switches
static var WSTATS := {}
static func _wstats() -> Dictionary:
	if WSTATS.is_empty(): WSTATS = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["weapons"]
	return WSTATS

func equip_from_save() -> void:
	refresh_from_save()
	var weap: Array = SaveBridge.data.get("weap", ["katana"])
	if weap.is_empty(): equip("kick"); return
	var wi := clampi(SaveBridge.get_i("wi"), 0, weap.size() - 1)
	equip(weap[wi])

func equip(id: String) -> void:
	var W := _wstats()
	var w: Dictionary = W.get(id, W["kick"])
	if not W.has(id): id = "kick"
	var path := "res://assets/weapons/%s.glb" % id
	var dmg := float(w["dmg"])
	var bd = SaveBridge.data.get("bassD")                # Pena's reward: the bass hits harder (7.2's bassD)
	if id == "bass" and (bd is float or bd is int) and float(bd) > 0: dmg = float(bd)
	var st := {"id": id, "n": w.get("n", id), "dmg": dmg, "cd": float(w["cd"]), "rng": float(w["rng"]), "arc": float(w["arc"]),
		"snd": str(w.get("snd", "whoosh")), "ranged": w.get("ranged", false) == true, "shock": w.get("shock", false) == true,
		"dur": w.get("dur"), "rar": w.get("rar", "")}
	hold(load(path) if ResourceLoader.exists(path) else null, st)
	if combat: combat.cancel()
	stats_changed.emit()

func next_weapon() -> void:
	var a := arsenal()
	if a: a.cycle(self); return                   # Arsenal skips empty guns and knows bare hands
	var weap: Array = SaveBridge.data.get("weap", ["katana"])
	if weap.size() < 2: return
	var wi := (weap.find(weapon["id"]) + 1) % weap.size()
	SaveBridge.data["wi"] = wi; equip(weap[wi])
	_sfx("clack")
	toast("%s · %d dmg" % [weapon["n"], int(weapon["dmg"])], 2.0)

# 7.2's useDurability(): every SWING wears the weapon (not every hit); at 10 left she's warned; at zero it
# breaks, she switches to her best one (7.2's equipBestDps) or bare-hand kicks, and the game saves
func wear() -> void:
	var a := arsenal()
	if a: a.wear(self); return                    # Arsenal owns durability when it's there (same rules)
	var id: String = weapon["id"]
	if id == "kick" or weapon.get("dur") == null: return
	var dur: Dictionary = SaveBridge.data.get("dur", {})
	dur[id] = float(dur.get(id, weapon["dur"])) - 1; SaveBridge.data["dur"] = dur
	if dur[id] <= 0:
		var weap: Array = SaveBridge.data.get("weap", [])
		weap.erase(id); dur.erase(id); SaveBridge.data["weap"] = weap
		var nm: String = weapon["n"]
		var best := ""
		var bd := -1.0
		var W := _wstats()
		for w in weap:
			if not W.has(w): continue
			var dps := float(W[w]["dmg"]) / maxf(.1, float(W[w]["cd"]))
			if dps > bd: bd = dps; best = w
		SaveBridge.data["wi"] = maxi(0, weap.find(best))
		equip(best if best != "" else "kick")
		_sfx("no"); _sfx("thud")
		toast("💥 [b]%s BROKE![/b] %s" % [nm, ("Switched to [b]%s[/b] (your best DPS)" % weapon["n"]) if best != "" else "Bare hands now — you can still KICK 🦵"], 8.0)
		if Lessons.me: Lessons.me.hud.banner("💥 WEAPON BROKEN\n[font_size=16]Find another one![/font_size]")
		SaveBridge.write()
	elif int(dur[id]) == 10:
		toast("⚠️ [b]%s[/b] is about to break! (10 uses left)" % weapon["n"], 5.0, true)

# Arsenal (weapon wheel, guns, Josh's Device, durability) — null when main.gd hasn't made one
func arsenal() -> Arsenal:
	return Arsenal.me if Arsenal.me != null and is_instance_valid(Arsenal.me) else null

static func alive(e) -> bool: return LockOn.alive(e)

# every hit she lands goes through here (combo, heavy, slam, bike ram, parry stagger)
# (the weapon's own trick from Arsenal.melee_opts — burn, poison, slow, extra knockback — rides along)
func hit_enemy(e, dmg: float, dir: Vector3, opts := {}) -> void:
	if not alive(e): return
	var a := arsenal()
	if a and dmg > 0 and not opts.get("no_trick", false):
		var mo: Dictionary = a.melee_opts(str(weapon.get("id", "")))
		if mo.has("status") and not opts.has("status"): opts["status"] = mo["status"]; opts["status_t"] = float(mo.get("sec", 3.0))
		if mo.has("kb"): opts["kb"] = maxf(float(opts.get("kb", 0.0)), float(mo["kb"]))
		if mo.has("stagger"): opts["stagger"] = maxf(float(opts.get("stagger", 0.0)), float(mo["stagger"]))
	if opts.has("kb"): opts["kb"] = float(opts["kb"]) * mod("kb")
	if e.get_method_argument_count("hit") >= 3: e.hit(dmg, dir, opts)
	else: e.hit(dmg, dir)

func facing() -> Vector3:
	var f := -global_transform.basis.z; f.y = 0
	return f.normalized() if f.length() > .01 else Vector3.FORWARD

func hand_pos() -> Vector3:
	return hand.global_position if hand else global_position + Vector3(0, 1.3, 0) + facing() * .4

func lunge(v: float) -> void:
	if not is_on_floor(): return
	var f := facing()
	velocity.x = f.x * v; velocity.z = f.z * v

func knockback(dir: Vector3, force: float) -> void:
	if wipe != "" or ledge != "": return
	dir.y = 0
	if dir.length() < .01: return
	dir = dir.normalized() * force
	velocity.x += dir.x; velocity.z += dir.z

func squash(a: float) -> void: _sq = minf(_sq, 1.0 - clampf(a, 0.0, .5) * .6)

func act(id: String, sec: float) -> void:            # one-shot poses for other systems: "cast", "eat", "dance"
	match id:
		"cast": cast_t = maxf(cast_t, sec)
		"eat": eat_t = maxf(eat_t, sec)
		"dance": dance_t = maxf(dance_t, sec)

func cam_orbit(sec: float) -> void:                   # 7.2's level-up show: one slow circle round her
	orbit_t = sec; _orbit_len = maxf(.1, sec)

# a short freeze on a solid hit (the whole game dips, like a PS1 hit-pause)
# (Fx owns time_scale so two freezes never fight over restoring it; no Fx = no freeze)
func hitstop(sec: float) -> void:
	if sec > 0 and Fx.me: Fx.me.hitstop(sec)

func toast(txt: String, secs := 3.0, bad := false) -> void:
	if Lessons.me: Lessons.me.hud.toast(txt, secs, bad)

func _sfx(n: String) -> void:
	Bus.emit_ev("sfx", {"name": n, "pos": global_position})

# ---------------- getting hurt ----------------
# 7.2's damagePlayer(): nothing hurts her while a lesson, call, choice or menu is up, or while she's down.
# On top: roll i-frames dodge it, the nazar shield eats it, a block takes 70% off (and stamina), a parry
# (block pressed < .18 s before) cancels it and staggers the attacker; then def/armour.
# kind: "melee" / "heavy" / "ranged" / "aoe" (blockable), "unblockable" (only a roll saves her), "crash" (the bike).
# The hurt / block / parry sounds and sparks come from Audio and Fx hearing Bus "player_hit".
func take_hit(dmg: int, from := Vector3.ZERO, kind := "melee") -> void:
	if dead or hp <= 0 or Overlay.any(): return
	if hurt_cd > 0 and kind != "crash": return
	var at := global_position
	if immune_t > 0:
		if Fx.me: Fx.me.label(at + Vector3(0, 2.9, 0), "IMMUNE ✨", Color("7bf7ff"), .9)
		return
	var dir := from - at; dir.y = 0
	if from == Vector3.ZERO or dir.length() < .01: dir = facing()
	dir = dir.normalized()
	if rolling and _roll_t > ROLL_T - ROLL_IFR and kind != "crash":
		if Fx.me: Fx.me.label(at + Vector3(0, 2.6, 0), "KAÇTIN! 💨", Color("8ff2ff"), .8)
		_sfx("woosh2")
		Bus.emit_ev("player_hit", {"dmg": 0, "pos": at, "blocked": false, "parried": false, "dodged": true, "kind": kind})
		return
	if has_status("shield"):
		if Fx.me: Fx.me.label(at + Vector3(0, 2.9, 0), "🧿 KALKAN", Color("7bf7ff"), .8)
		Bus.emit_ev("player_hit", {"dmg": 0, "pos": at, "blocked": true, "parried": false, "kind": kind})
		return
	var d := float(dmg) * mod("def")
	var blocked := false
	if blocking and kind != "crash" and kind != "unblockable" and facing().dot(dir) > -.1:
		if t - _block_t0 <= PARRY_WIN:
			_parry(from, dir, kind); return
		var cost := 8.0 + d * .5
		if stamina >= cost and not winded:
			stamina -= cost; _stam_wait = .55; d *= .3; blocked = true
			knockback(-dir, 3.0 if kind != "heavy" else 6.0)
		else:                                               # out of stamina: the guard breaks
			stamina = 0.0; _wind_out(); d *= .6; blocking = false
			set_status("stun", .7)
			_sfx("crash"); _sfx("dizzy")
			if Fx.me: Fx.me.label(at + Vector3(0, 3.0, 0), "GUARD BREAK! 💢", Color("ff5fa2"), 1.2)
	var n := int(round(d))
	if not blocked: n = maxi(1, n)
	hurt_cd = .2 if blocked else .35
	hp = maxi(0, hp - n); hp_changed.emit(hp, max_hp)
	if not blocked:
		if Fx.me: Fx.me.flash("hurt"); Fx.me.shake(.12 if kind != "heavy" else .22)
		if kind != "crash" and wipe == "":
			_flinch_t = .3
			knockback(-dir, 7.0 if kind == "heavy" else 4.5)
			if combat.state == "light" or (combat.state == "heavy" and combat.phase == "wind"): combat.cancel()
	Bus.emit_ev("player_hit", {"dmg": n, "pos": at, "blocked": blocked, "parried": false, "kind": kind})
	if hp <= 0: _faint()

# PARRY: no damage, the attacker reels, her next hit crits (x1.5), a bit of stamina back. A monster hit that
# came through Enemy.strike_torii gets Enemy.parried() (dazed 1.8 s) from the player_hit event; anything else
# close by in front gets staggered here with enemy.hit(0, dir, {stagger 1.2}). A parried shot is deflected.
func _parry(from: Vector3, dir: Vector3, kind: String) -> void:
	var at := global_position
	if Enemy._striker == null and kind != "ranged" and kind != "aoe":
		var best = null
		var bd := 3.6
		var c := from if from != Vector3.ZERO else at + dir * 1.5
		for e in get_tree().get_nodes_in_group("enemies"):
			if not alive(e): continue
			var dd: float = e.global_position.distance_to(c)
			if dd < bd: bd = dd; best = e
		if best:
			var to: Vector3 = best.global_position - at; to.y = 0
			hit_enemy(best, 0.0, to.normalized() if to.length() > .01 else dir, {"stagger": 1.2, "kb": 6.0, "no_trick": true})
	crit_next = true
	stamina = minf(max_stamina, stamina + 10.0)
	hurt_cd = .3
	if Fx.me:
		Fx.me.label(at + Vector3(0, 3.0, 0), "SAPTIRDIN! ✨ (deflect)" if kind == "ranged" else "PARRY! ✨", Color("7bf7ff"), 1.2)
		Fx.me.puff(at + Vector3(0, 1.4, 0) + dir * .6, [Color.WHITE, Color("7bf7ff")], 6, 2.2, 1.6, .3, .3)
	if not _told.has("parry"):
		_told["parry"] = true
		toast("✨ [b]PARRY![/b] Raise your guard (Z) right before a hit: no damage, they reel, your next hit crits.", 5.5)
	Bus.emit_ev("player_hit", {"dmg": 0, "pos": at, "blocked": true, "parried": true, "kind": kind})

# 7.2's die(): fainting costs 10% of her lira and 30% of this level's XP — never a level — then she wakes up
# at her last checkpoint with 70% HP and the monsters around her gone (bosses stay)
func _faint() -> void:
	dead = true
	if on_bike: _get_off()
	_end_moves()
	var lira := SaveBridge.get_i("lira")
	var lira_lost := int(round(lira * .10))
	var xp_lost := mini(SaveBridge.get_i("xp"), int(round(SaveBridge.get_i("need", 60) * .30)))
	SaveBridge.data["lira"] = maxi(0, lira - lira_lost); SaveBridge.data["xp"] = SaveBridge.get_i("xp") - xp_lost
	if lira_lost: Bus.emit_ev("lira", {"delta": -lira_lost})
	if xp_lost: Bus.emit_ev("xp", {"delta": -xp_lost})
	Bus.emit_ev("faint", {})
	if Fx.me: Fx.me.dark(.78, 1.0); Fx.me.shake(.5)
	if Lessons.me:
		Lessons.me.hud.banner("YOU FAINTED! 😵\n[font_size=16]−%d₺ · −%d XP · continuing from checkpoint[/font_size]" % [lira_lost, xp_lost])
		Lessons.me.hud.toast("😵 [b]Bayıldın![/b] Lost [b]%d₺[/b] (10%%) and [b]%d XP[/b] of this level. Your level is safe. [i]Dikkatli ol, canım.[/i]" % [lira_lost, xp_lost], 9.0, true)
	SaveBridge.write()
	await get_tree().create_timer(2.4).timeout
	global_position = respawn_point(); yaw = 0.0; heading = 0.0; velocity = Vector3.ZERO; snap_camera()
	hp = int(round(max_hp * .7)); hp_changed.emit(hp, max_hp)
	stamina = max_stamina; winded = false
	for e in get_tree().get_nodes_in_group("enemies"):
		var fl = e.get("flags")
		if e.global_position.distance_squared_to(global_position) < 900 and not (fl is Dictionary and fl.has("boss")): e.queue_free()
	if Fx.me: Fx.me.dark(0.0, 1.0)
	dead = false
	Bus.emit_ev("respawn", {})
	SaveBridge.write()

# drop whatever she was in the middle of (fainting, teleports)
func _end_moves() -> void:
	if combat: combat.cancel()
	rolling = false; _roll_t = 0.0; blocking = false; ledge = ""; lock_target = null; status = {}
	if wipe != "": wipe = ""; if bike: bike.rotation.z = .13
	_sq = 1.0; _spin_a = 0.0

# her checkpoint (7.2 saves it as resp {x, z}); abroad she wakes at that country's airport instead
func respawn_point() -> Vector3:
	var p := spawn
	var r = SaveBridge.data.get("resp")
	if r is Dictionary and (r.get("x") is int or r.get("x") is float): p = Vector3(float(r["x"]), 0, float(r["z"]))
	if global_position.x > 400 and Missions.me:
		var best := INF
		for z in ["cam", "az", "liv"]:
			var sp: Dictionary = Missions.me.D["zspawn"][z]
			var d := Vector2(sp["x"] - global_position.x, sp["z"] - global_position.z).length()
			if d < best: best = d; p = Vector3(sp["x"], 0, sp["z"])
	return Vector3(p.x, _ground_y(p.x, p.z) + .05, p.z)

func _ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z)); q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else 0.0

# dev scripts (main.gd --fxtest / --hit): an instant first combo swing
func _attack() -> void:
	if combat.busy(): return
	combat.light()
	if combat.state == "light": combat.st = combat.hit_a; combat.update(0.0)

# ---------------- input ----------------
func _unhandled_input(e: InputEvent) -> void:
	if Overlay.any() or dead: return
	var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and cap:
		combat.light()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and cap:
		combat.heavy_press()
	elif e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) and cap:
		next_weapon()                                          # 7.2: the wheel cycles weapons
	elif e is InputEventMouseButton and e.pressed and not cap:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and cap:
		if not _locked(): yaw -= e.relative.x * SENS            # locked on, the target steers her
		pitch = clampf(pitch + e.relative.y * SENS * .85, -.5, 1.0)     # mouse down looks down
		look_t = t

func _locked() -> bool:
	return lock_target != null and alive(lock_target) and not on_bike

# ---------------- every frame ----------------
func _physics_process(dt: float) -> void:
	t += dt
	hurt_cd -= dt; immune_t -= dt; cast_t -= dt; eat_t -= dt; orbit_t -= dt; drunk_t -= dt
	if Overlay.any() or dead:                 # lessons, calls, choices and menus pause her; so does fainting
		velocity = Vector3.ZERO
		if pose:
			if on_bike: pose.ride(t, 0.0, lean)
			else: pose.update(dt, t, false, 0.0, false, 0.0)
		_model_xf(dt)
		_camera(dt); _shadow()
		return
	var fresh := not Overlay.just_closed()    # the E / Space that closed a box isn't hers to use
	_tick_status(dt)
	lock_target = _lock.tick(self, lock_target, dt) if not on_bike else null
	if not on_bike: _lock.visible = lock_target != null
	else: _lock.visible = false
	if wipe != "":
		_wipe_tick(dt); return
	if fresh and Input.is_action_just_pressed("interact") and bike:
		if on_bike:
			if absf(bspeed) > 5: toast("Slow down first! 🚲", 2.5, true)
			else: _get_off()
		elif global_position.distance_to(bike.global_position) < BIKE_REACH and global_position.x < 400: _get_on()
	if fresh and Input.is_action_just_pressed("attack"): combat.light()
	# Q: Arsenal reads it itself (tap = next weapon, hold = the wheel); without Arsenal a tap = next weapon
	if Input.is_action_just_pressed("weapon") and arsenal() == null: next_weapon()
	if Input.is_action_just_pressed("look_back"): _set_look(not look_back)
	if Input.is_action_just_pressed("lock_on") and not on_bike:
		lock_target = _lock.cycle(self, lock_target, _cam_fwd())
		_sfx("lock_on" if lock_target else "lock_off")
		if lock_target and not _told.has("lock"):
			_told["lock"] = true
			toast("🎯 [b]Locked on![/b] A/D circle round it · TAB = next target · TAB on the last one lets go", 5.0)
	if on_bike:
		_ride(dt, fresh)
		return
	combat.update(dt)
	if ledge != "":
		_ledge_tick(dt); return
	_move(dt, fresh)

func _cam_fwd() -> Vector3:
	var cy := yaw + (PI if look_back else 0.0)
	return Vector3(-sin(cy), 0, -cos(cy))

func _move(dt: float, fresh: bool) -> void:
	var stunned := has_status("stun")
	var dancing := dance_t > 0
	dance_t -= dt
	var floor := is_on_floor()
	if floor:
		_coyote = COYOTE; air_t = 0.0; _floor_y = global_position.y
	else:
		_coyote -= dt; air_t += dt
	# turning: the arrows (7.2), or the lock-on target pulls her round to face it
	if _locked():
		var to := lock_target.global_position - global_position
		var want := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want, 1.0 - pow(.0004, dt))
	elif not stunned:
		yaw += (Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")) * TURN * dt
	if drunk_t > 0: yaw += sin(t * 2.2) * .5 * dt
	var fwd := 0.0 if stunned else Input.get_axis("move_back", "move_forward")
	var side := 0.0 if stunned else Input.get_axis("move_left", "move_right")
	var sp := WALK * fwd if fwd > 0 else BACK * fwd
	var st := side * STRAFE
	var mult := mod("speed")
	if dancing: mult *= .25
	if has_status("slow"): mult *= .5
	if has_status("haste"): mult *= 1.35
	if drunk_t > 0: mult *= .85
	# guard (hold Z): on the ground, not mid-move; the moment it goes up starts the parry window
	var want_block := Input.is_action_pressed("block") and floor and not stunned and not rolling and not dancing and combat.can_cancel()
	if want_block and not blocking:
		_block_t0 = t
		if combat.busy(): combat.cancel()
	blocking = want_block
	if blocking: mult *= .4
	mult *= combat.move_mult()
	# SHIFT sprint, paid for in stamina (7.2): empty = winded until it's back past a quarter
	var want_run := Input.is_action_pressed("sprint") and (sp != 0 or st != 0) and not dancing and not blocking and not combat.busy()
	sprinting = false
	if want_run and not winded and stamina > 0:
		sp *= SPRINT; st *= 1.34; sprinting = true
		stamina = maxf(0.0, stamina - SPRINT_COST * mod("sprintcost") * dt); _stam_wait = .45
		if stamina <= 0: _wind_out()
		if not _told.has("sprint"):
			_told["sprint"] = true
			toast("🏃‍♀️ [b]Sprint[/b] — hold SHIFT. [i]koşmak[/i] = to run. Watch the green bar.", 5.2)
	var target := Basis(Vector3.UP, yaw) * Vector3(st, 0, -sp) * mult
	# dodge roll (Left Ctrl): buffered a moment, so pressing it a touch early in a swing still rolls
	if Input.is_action_just_pressed("roll"): _roll_buf = .15
	_roll_buf -= dt
	if _roll_buf > 0 and floor and not rolling and not stunned and not dancing and combat.can_cancel() and not blocking:
		_roll_buf = 0.0
		if spend_stamina(ROLL_COST):
			combat.cancel(); rolling = true; _roll_t = ROLL_T
			var d := Vector3(target.x, 0, target.z)
			_roll_dir = d.normalized() if d.length() > .2 else facing()
			_sfx("roll")
			if Fx.me: Fx.me.puff(global_position + Vector3(0, .2, 0), Color("cabfd8"), 5, .9, .5, .4, .7)
		else: say_tired()
	var hv := Vector2(velocity.x, velocity.z)
	if rolling:
		_roll_t -= dt
		var k := _roll_t / ROLL_T                          # fast out of the blocks, easing at the end
		var v := _roll_dir * ROLL_SPD * (.45 + .55 * k)
		hv = Vector2(v.x, v.z)
		if _roll_t <= 0: rolling = false
		elif _roll_t < .14 and (Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("jump")): rolling = false   # roll-cancel
	elif combat.state == "dash" and combat.st < .24:
		var f := facing()
		hv = Vector2(f.x, f.z) * 13.0                        # the sprint attack carries her through
	else:
		var tv := Vector2(target.x, target.z)
		var acc := (ACCEL if tv.length() >= hv.length() else DECEL) if floor else AIR_ACCEL
		# steep ground: she slides down it and can't walk back up
		if floor and get_floor_angle() > deg_to_rad(SLIDE_ANGLE):
			var n := get_floor_normal()
			var down := Vector2(n.x, n.z).normalized()
			hv += down * 20.0 * dt
			acc *= .25
			if Fx.me and randf() < dt * 12: Fx.me.puff(global_position + Vector3(0, .15, 0), Color("9a94a8"), 1, .4, .4, .35, .5)
		hv = hv.move_toward(tv, acc * dt)
	velocity.x = hv.x; velocity.z = hv.y
	# jump: buffered, with coyote time; letting go of Space early makes it a hop
	if fresh and Input.is_action_just_pressed("jump"): _jump_buf = JUMP_BUF
	_jump_buf -= dt
	if _jump_buf > 0 and _coyote > 0 and not dancing and not stunned and not blocking and not rolling and combat.can_cancel():
		if combat.busy(): combat.cancel()
		velocity.y = JUMP; _jump_buf = 0.0; _coyote = 0.0; _jumping = true; floor = false
		_sfx("jump")
		if Fx.me: Fx.me.puff(global_position + Vector3(0, .2, 0), Color("cabfd8"), 6, .9, .7, .45, .7)
	if _jumping and velocity.y > 0 and not Input.is_action_pressed("jump"):
		velocity.y *= .5; _jumping = false
	if velocity.y <= 0: _jumping = false
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * (FALL_G if velocity.y < 0 else 1.0) * dt, -MAX_FALL)
	rotation.y = yaw
	var was_air := not is_on_floor()
	_fall_vy = velocity.y
	var want := Vector3(velocity.x, 0, velocity.z)      # (move_and_slide zeroes this against the lip)
	move_and_slide()
	if is_on_wall(): _step_up(want * dt)
	_stay_on_land()
	if was_air and is_on_floor(): _land(_fall_vy)
	# jumping at a wall with a ledge on top: grab it
	if not is_on_floor() and air_t > .08 and fwd > 0 and velocity.y < 4.0 and not combat.busy(): _try_ledge()
	var ground := Vector2(velocity.x, velocity.z).length()
	if running_dust() and Fx.me and randf() < dt * 9:
		Fx.me.puff(global_position + Vector3(0, .18, 0), Color("9a94a8"), 1, .5, .5, .35, .5)
	_regen(dt, ground > .3)
	_pose(dt, ground)
	_camera(dt); _shadow()

func running_dust() -> bool: return sprinting and is_on_floor()

func _land(vy: float) -> void:
	if vy < -9:                                        # 7.2: a hard landing thuds and kicks up dust
		_sfx("land_hard" if vy < -16 else "land")
		squash(clampf((-vy - 9.0) / 20.0, .12, .4))
		if Fx.me: Fx.me.puff(global_position + Vector3(0, .15, 0), Color("9a94a8"), 5, .8, .5, .35, .6)
		if vy < -18 and Fx.me: Fx.me.shake(.12)
	else:
		_sfx("step")
		squash(.08)

# ---------------- ledges ----------------
# jumping at a wall: a ray at chest height finds it, a ray down just behind its face finds a flat top
# 0.55-2.5 m above her feet (and at most ~2.6 m above where she jumped from) with room to stand
func _try_ledge() -> void:
	var f := facing()
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var from := feet + Vector3(0, 1.1, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + f * .85); q.exclude = [get_rid()]
	var w := space.intersect_ray(q)
	if w.is_empty() or absf(w["normal"].y) > .35: return
	var into: Vector3 = -w["normal"]; into.y = 0; into = into.normalized()
	var top_from: Vector3 = w["position"] + into * .32; top_from.y = feet.y + 2.9
	var q2 := PhysicsRayQueryParameters3D.create(top_from, Vector3(top_from.x, feet.y + .5, top_from.z)); q2.exclude = [get_rid()]
	var top := space.intersect_ray(q2)
	if top.is_empty() or top["normal"].y < .75: return
	var ty: float = top["position"].y
	var h := ty - feet.y
	if h < .55 or h > 2.5 or ty - _floor_y > 2.6: return
	var stand := Vector3(top_from.x, ty + .06, top_from.z) + into * .2
	if test_move(Transform3D(Basis.IDENTITY, stand + Vector3(0, .05, 0)), Vector3(0, .1, 0)): return    # no room up there
	ledge = "hang" if h > 1.3 else "climb"
	_ledge_t = 0.0; _ledge_from = feet; _ledge_b = stand
	_ledge_a = Vector3(w["position"].x, maxf(feet.y, ty - 2.15), w["position"].z) - into * .34
	yaw = atan2(-into.x, -into.z); rotation.y = yaw
	velocity = Vector3.ZERO; combat.cancel(); rolling = false
	_sfx("clack")
	if Fx.me: Fx.me.puff(Vector3(w["position"].x, ty, w["position"].z), Color("cabfd8"), 3, .5, .3, .3, .4)

func _ledge_tick(dt: float) -> void:
	_ledge_t += dt
	velocity = Vector3.ZERO
	if ledge == "hang":
		global_position = _ledge_from.lerp(_ledge_a, minf(1.0, _ledge_t / .08))
		if pose: pose.update(dt, t, false, 0.0, false, 0.0); pose.ledge_hang(t)
		if _ledge_t >= .2:
			ledge = "climb"; _ledge_t = 0.0; _ledge_from = global_position; _sfx("jump")
	else:
		var dur := .45
		var k := minf(1.0, _ledge_t / dur)
		var up := smoothstep(0.0, .6, k)
		var over := smoothstep(.5, 1.0, k)
		var p := _ledge_from.lerp(Vector3(_ledge_from.x, _ledge_b.y, _ledge_from.z), up)
		global_position = Vector3(lerpf(p.x, _ledge_b.x, over), p.y, lerpf(p.z, _ledge_b.z, over))
		if pose: pose.update(dt, t, false, 0.0, false, 0.0); pose.ledge_climb(k)
		if k >= 1.0:
			ledge = ""; _floor_y = global_position.y; squash(.08); _sfx("step")
	_model_xf(dt)
	_regen(dt, false)
	_camera(dt); _shadow()

# ---------------- poses ----------------
func _pose(dt: float, ground: float) -> void:
	if not pose: _model_xf(dt); return
	var air := not is_on_floor()
	pose.update(dt, t, ground > .2, ground, air, velocity.y)
	pose.spin = 0.0
	# a footstep every half stride (Bus "sfx" step)
	var k := int(floor(pose.ph / PI))
	if k != _step_k:
		_step_k = k
		if not air and ground > .5: Bus.emit_ev("sfx", {"name": "step", "pos": global_position, "run": sprinting})
	var kick: bool = weapon.get("id", "") == "kick"
	if dance_t > 0: pose.dance(t)                          # 7.2 dances on the move too
	elif rolling: pose.roll()
	elif has_status("stun"): pose.wobble(t, .8)
	elif combat.state == "light": pose.combo(combat.step, combat.st / maxf(.01, combat.dur), kick)
	elif combat.state == "dash": pose.combo(0, clampf(combat.st / combat.dur, 0.0, 1.0), kick)
	elif combat.state == "heavy":
		if combat.phase == "wind": pose.heavy_wind(t, minf(1.0, combat.st / .15), combat.charge)
		else: pose.heavy_go(combat.st / maxf(.01, combat.dur))
	elif combat.state == "slam":
		if combat.phase == "air": pose.slam_air()
		else: pose.slam_land(combat.st / .38)
	elif combat.state == "shock": pose.cast(t)
	else:
		if not air: pose.aim(pitch)
		if blocking: pose.block(minf(1.0, (t - _block_t0) / .08))
		if cast_t > 0: pose.cast(t, minf(1.0, cast_t / .15))
		elif eat_t > 0: pose.eat(t, minf(1.0, eat_t / .2))
	if _flinch_t > 0:
		_flinch_t -= dt; pose.flinch(1.0 - _flinch_t / .3)
	_model_xf(dt)

# the whole model: roll flips, spin kick, bike tumble, landing squash — turned round a pivot at her hips
func _model_xf(dt: float) -> void:
	if not model: return
	_sq = move_toward(_sq, 1.0, dt * 1.6)
	var yr := 0.0
	var flip := 0.0
	var piv := 1.0
	if rolling:
		var f := facing()
		yr = f.signed_angle_to(_roll_dir, Vector3.UP)
		flip = -(1.0 - _roll_t / ROLL_T) * TAU; piv = .6
	elif wipe == "fly": flip = _spin_a
	elif wipe == "down": flip = -PI / 2; piv = .18
	elif wipe == "getup": flip = -PI / 2 * (1.0 - smoothstep(0.0, 1.0, 1.0 - _wipe_t / .85)); piv = .18
	if pose: yr += pose.spin
	var b := Basis(Vector3.UP, yr) * Basis(Vector3.RIGHT, flip) * Basis(Vector3.UP, PI)
	if _sq < .999: b = b.scaled(Vector3(1.0 + (1.0 - _sq) * .5, _sq, 1.0 + (1.0 - _sq) * .5))
	var P := Vector3(0, piv, 0)
	model.transform = Transform3D(b, P - b * P)

# curbs, ramp lips and steps up to 45 cm: she steps up onto them instead of stopping dead (7.2 used a height
# map and never had edges; the exported city has real ones, like the lip at the foot of Tower Bridge)
const STEP := .45
func _step_up(motion: Vector3) -> void:
	if motion.length() < .001: return
	var t0 := global_transform
	if test_move(t0, Vector3(0, STEP, 0)): return                 # no headroom
	var fwd := motion.normalized() * maxf(.3, motion.length())
	var up := t0.translated(Vector3(0, STEP, 0))
	if test_move(up, fwd): return                                  # still blocked when raised: a real wall
	var col := KinematicCollision3D.new()
	var raised := up.translated(fwd)
	if test_move(raised, Vector3(0, -STEP - .1, 0), col):
		global_position = raised.origin + col.get_travel()

func _set_look(v: bool) -> void:
	look_back = v
	if Lessons.me: Lessons.me.hud.look_label.visible = v

# water stops her at the shore (no swimming in 7.2 either; the river is crossed on Tower Bridge), she
# stays inside the map (7.2's ZB), and a fall out of the world brings her back to her checkpoint
func _stay_on_land() -> void:
	var g := global_position
	var wet := false
	for r in water:                    # inside a water area and not up on the bridge deck above it
		if g.x > r[0] and g.x < r[1] and g.z > r[2] and g.z < r[3] and g.y < r[4] + 1.0: wet = true; break
	if wet:
		global_position = Vector3(_safe.x, g.y, _safe.z); velocity.x = 0; velocity.z = 0; bspeed *= .3
	else:
		_safe = global_position
	var B: Array = BOUNDS["city"]
	if global_position.x > 400:
		B = BOUNDS["cam"]
		for z in ["az", "liv"]:
			if global_position.z > BOUNDS[z][2] - 60 and global_position.z < BOUNDS[z][3] + 60: B = BOUNDS[z]
	global_position.x = clampf(global_position.x, B[0], B[1]); global_position.z = clampf(global_position.z, B[2], B[3])
	if global_position.y < -12:
		global_position = respawn_point(); velocity = Vector3.ZERO; snap_camera()

func _shadow() -> void:
	if not shadow: return
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, .5, 0), p + Vector3(0, -30, 0)); q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	shadow.visible = not hit.is_empty()
	if hit: shadow.global_position = hit["position"] + Vector3(0, .03, 0)

# 7.2's updateCam(): orbit behind her, raised and over her right shoulder so the view looks past her head;
# further back and lower over the shoulder on the bike; eased in (almost at once while the mouse is captured).
# Better than 7.2: if a wall is in the way the camera comes in front of it instead of sitting inside it;
# her height is eased (jumps and climbs don't jolt it); locked on, it pulls back to frame her AND the target;
# a small FOV kick while sprinting/rolling; 7.2's level-up orbit (cam_orbit) and drunk roll.
func _camera(dt: float) -> void:
	if not cam: return
	if on_bike and t - look_t > 1.3:
		yaw += wrapf(heading - yaw, -PI, PI) * minf(1.0, dt * 3.4)
	var cy := yaw + (PI if look_back else 0.0) + cam_off
	if orbit_t > 0: cy += TAU * (1.0 - orbit_t / _orbit_len)
	var dist := 9.4 if on_bike else 7.4
	var locked := _locked() and not look_back
	var tp := Vector3.ZERO
	if locked:
		tp = lock_target.global_position
		dist += clampf(Vector2(tp.x - global_position.x, tp.z - global_position.z).length() * .2, 0.0, 3.5)
	var pit := clampf(pitch + .14, -.32, .8) if on_bike else pitch
	var hd := cos(pit) * dist
	var vd := sin(pit) * dist
	var f := Vector3(-sin(cy), 0, -cos(cy))
	var r := Vector3(cos(cy), 0, -sin(cy))
	var sh := .4 if on_bike else 1.05
	var p := global_position
	_cam_py = p.y if _cam_snap else lerpf(_cam_py, p.y, 1.0 - pow(.003, dt))
	var py := _cam_py
	var target := Vector3(p.x, py, p.z) - f * hd + r * sh
	target.y = maxf(1.1, (3.9 if on_bike else 3.35) + vd + py)
	var k := 1.0 - pow(4e-9 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else 6e-4, dt)
	var head := p + Vector3(0, 1.9, 0)
	var q := PhysicsRayQueryParameters3D.create(head, target); q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		target = hit["position"] + (head - hit["position"]).normalized() * .35
		if target.distance_to(head) < cam.global_position.distance_to(head): k = 1.0   # never ease through the wall
	if _cam_snap: k = 1.0; _cam_snap = false
	cam.global_position = cam.global_position.lerp(target, k)
	var look := Vector3(p.x, py, p.z) + f * 7.0 + r * sh
	look.y = 2.45 + py - sin(pit) * 7.0 * .92
	if locked:
		var mid := Vector3(p.x, py + 1.6, p.z).lerp(tp + Vector3(0, 1.2, 0), .42)
		look = Vector3(mid.x, mid.y - sin(pit) * 2.5, mid.z) + r * sh * .5
	if look.distance_squared_to(cam.global_position) > .01: cam.look_at(look, Vector3.UP)
	if drunk_t > 0: cam.rotate_object_local(Vector3.BACK, sin(t * 1.3) * .08)
	var fov := 62.0 + (5.0 if sprinting else 0.0) + (3.0 if rolling else 0.0) + (4.0 if on_bike and bspeed > 22 else 0.0)
	cam.fov = lerpf(cam.fov, fov, minf(1.0, dt * 6.0))
	if Fx.me and Fx.me.shake_t > 0:
		cam.global_position += Vector3(randf_range(-1, 1) * Fx.me.shake_t * .5, randf_range(-1, 1) * Fx.me.shake_t * .4, 0)

# after a teleport (flights, respawns): put the camera straight behind her instead of sweeping across town
func snap_camera() -> void:
	_cam_snap = true

# ---------------- the bike (7.2's Diamond Back) ----------------
func _get_on() -> void:
	_end_moves()
	on_bike = true; bspeed = 0.0; drifting = false; drift_t = 0.0; slide = 0.0
	global_position = Vector3(bike.global_position.x, global_position.y, bike.global_position.z)
	heading = bike.rotation.y - PI                  # the bike model faces +z, she faces -z
	yaw = heading
	bike.rotation.z = 0
	_sfx("drop")
	if not _told.has("bike"):
		_told["bike"] = true
		toast("🚲 [b]Diamond Back![/b] W = pedal · S = brake · SPACE = boost · hold SPACE into a corner = DRIFT", 5.0)
		if Lessons.me: Lessons.me.teach("bisiklet")

func _get_off() -> void:
	on_bike = false; bspeed = 0.0; drifting = false; drift_t = 0.0; slide = 0.0
	yaw = heading                                    # on foot she faces where the bike pointed
	bike.rotation = Vector3(0, heading + PI, .13)   # parked on its stand, like 7.2
	global_position += global_transform.basis.x * 1.0   # step off to her right
	_sfx("drop")

func _ride(dt: float, fresh := true) -> void:
	var up := Input.is_action_pressed("move_forward")
	var dn := Input.is_action_pressed("move_back")
	var st := clampf(Input.get_axis("move_right", "move_left") + Input.get_action_strength("turn_left")
		- Input.get_action_strength("turn_right"), -1.0, 1.0)            # + = turn left (A/D or the arrows)
	var tf := clampf(1.75 - bspeed * .028, .6, 1.75)          # tighter turns when slow
	var bst := mod("bike")
	# DRIFT (7.2): Space held into a corner above 9 m/s breaks traction; a long one pays XP and lira
	var space := Input.is_action_pressed("jump") and fresh
	var want_drift := space and bspeed > 9 and absf(st) > 0
	if want_drift:
		if not drifting: drifting = true; _sfx("rev")
		drift_t += dt
		slide = lerpf(slide, st * .85, minf(1.0, dt * 4.5))
		heading += st * tf * dt * 2.15
		bspeed -= bspeed * .55 * dt
		if Fx.me and randf() < dt * 26: Fx.me.puff(global_position + Vector3(0, .16, 0), [Color("cabfd8"), Color("9a94a8")], 2, 1.1, .5, .6, .8)
		if Fx.me and drift_t > .6 and randf() < dt * 3:
			Fx.me.label(global_position + Vector3(0, 3.2, 0), "DRİFT! %.1fs" % drift_t, Color("8ff2ff"), .9)
	else:
		if drifting:
			if drift_t > .75:
				var rew := int(round(drift_t * 24)); var lir := int(round(drift_t * 14))
				if Lessons.me: Lessons.me.xp(rew)
				SaveBridge.data["lira"] = SaveBridge.get_i("lira") + lir
				Bus.emit_ev("lira", {"delta": lir})               # (Lessons.xp -> Stats already says "xp")
				if Fx.me: Fx.me.label(global_position + Vector3(0, 3.6, 0), "DRİFT +%d XP" % rew, Color("ffd66b"), 1.5)
				_sfx("ding")
			drifting = false; drift_t = 0.0
		slide = lerpf(slide, 0.0, minf(1.0, dt * 5))
		if absf(bspeed) > .5: heading += st * tf * dt * (-.6 if bspeed < 0 else 1.0)
	if up: bspeed += 15 * bst * dt
	if dn: bspeed -= (27 if bspeed > 0 else 9) * dt
	bspeed -= (4.2 + bspeed * .11 / bst if bspeed > 0 else -3.4) * dt
	rotation.y = heading
	var f := -global_transform.basis.z
	if is_on_floor() and bspeed > 0:                 # climbing costs speed, going downhill gives it back
		bspeed -= -f.dot(get_floor_normal()) * 2.0 * 7.5 * dt
	bspeed = clampf(bspeed, -5.5, 27 * bst)
	# BOOST costs stamina (7.2: 22 x boostcost); pedalling refills it, drifting is free
	boost_cd -= dt
	if space and not want_drift and boost_cd <= 0 and bspeed > 1:
		var cost := float(round(22 * mod("boostcost")))
		if stamina >= cost and not winded:
			stamina -= cost
			if stamina <= 0: winded = true
			bspeed = minf(31.0 * bst, bspeed + 7.5); boost_cd = 1.15
			_sfx("boost")
			if Fx.me: Fx.me.puff(global_position + global_transform.basis.z * 1.3 + Vector3(0, .5, 0), Color("9a94a8"), 8, 1.3, 1.8, .7, .8)
		else:
			boost_cd = .5
			if t - float(_told.get("boost_warn", -9.0)) > 4.0:
				_told["boost_warn"] = t; _sfx("no")
				if Fx.me: Fx.me.label(global_position + Vector3(0, 3.4, 0), "nefesim yok! 😮‍💨", Color("ffd66b"), 1.1)
	if not winded or stamina < max_stamina:
		stamina = minf(max_stamina, stamina + (4.0 if want_drift else 9.0) * dt)
	velocity.x = f.x * bspeed; velocity.z = f.z * bspeed
	if slide != 0.0:                                 # a drift carries her sideways too
		velocity.x += -f.z * slide * bspeed * .42; velocity.z += f.x * slide * bspeed * .42
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if is_on_wall(): _step_up(f * bspeed * dt)
	_stay_on_land()
	# hitting something: above 9 m/s head-on is a real spill (a coin flip), below that she just clips it
	if is_on_wall() and absf(bspeed) > 3.5:
		var head_on := f.dot(get_wall_normal()) < -.45
		if bspeed > 9 and head_on:
			_bike_crash(bspeed, "wall"); return
		bspeed *= .4 if head_on else .85
		_sfx("drop")
		if Fx.me: Fx.me.puff(global_position + Vector3(0, .5, 0), Color("cabfd8"), 4, 1, .9, .5, .6)
	if _bike_ram(): return
	if Fx.me and bspeed > 16 and randf() < dt * 8:
		Fx.me.puff(global_position - f * 1.2 + Vector3(0, .35, 0), Color("9a94a8"), 1, .8, 1.1, .6, .5)
	if Fx.me and absf(st) > 0 and bspeed > 14 and randf() < dt * 10:
		Fx.me.puff(global_position - f * 1.1 + Vector3(0, .25, 0), Color("cabfd8"), 1, .9, .9, .45, .6)
	wobble_t -= dt
	var wob := sin(wobble_t * 34.0) * wobble_t if wobble_t > 0 else 0.0
	lean = -st * .24 * minf(1.0, absf(bspeed) / 13.0) - slide * .3 + wob * .5
	bike.global_position = global_position
	bike.rotation = Vector3(0, heading + PI + slide * .55, lean)
	for w in wheels:
		if w: w.rotation.x -= bspeed * dt * 2
	if crank: crank.rotation.x -= maxf(0.0, bspeed) * dt * 1.1
	_regen(dt, true)
	_camera(dt); _shadow()
	if pose:
		pose.ride(t, bspeed, lean)
		if wobble_t > 0: pose.wobble(t, wobble_t / .7)
	_model_xf(dt)

# 7.2's bikeRam(): riding through a monster above 7 m/s hurts it, throws it forward... and might throw her
func _bike_ram() -> bool:
	if bspeed < 7: return false
	var f := facing()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not alive(e): continue
		var to: Vector3 = e.global_position - global_position; to.y = 0
		if to.length_squared() > 3.4: continue
		if t - float(e.get_meta("ram_t", -9.0)) < .9: continue
		e.set_meta("ram_t", t)
		var dmg := float(round(4 + bspeed * .55))
		hit_enemy(e, dmg, f, {"kb": 17.0, "stagger": .5, "heavy": true})
		_sfx("thud")
		if Fx.me:
			Fx.me.puff(e.global_position + Vector3(0, 1.2, 0), [Color("ff5fa2"), Color("ffd66b")], 10, 1.8, 1.8, .7)
			Fx.me.label(e.global_position + Vector3(0, 3, 0), "ÇARPMA! %d" % int(dmg), Color("ffd66b"), 1.2)
		hitstop(.06)
		_bike_crash(bspeed, "mob")
		return true
	return false

# 7.2's bikeCrash(): a coin flip — a wobble ('zor tuttun!', keeps 35% speed) or over the handlebars:
# she flies (spin and distance scale with speed), lands with a thud, slides face-down, gets back up
func _bike_crash(sp: float, why: String) -> void:
	var bad := randf() < .5
	var f := facing()
	if Fx.me: Fx.me.shake(.35 + sp * .02 if bad else .28)
	if not bad:
		bspeed = sp * .35; wobble_t = .7; _sfx("drop")
		if Fx.me:
			Fx.me.label(global_position + Vector3(0, 3.2, 0), "zor tuttun! 😮‍💨", Color("ffd66b"), 1.2)
			Fx.me.puff(global_position + Vector3(0, .4, 0), Color("cabfd8"), 7, 1.4, 1.2, .6, .7)
		return
	var hard := clampf((sp - 8.0) / 19.0, 0.0, 1.0)
	on_bike = false; bspeed = 0.0; drifting = false; drift_t = 0.0; slide = 0.0
	wipe = "fly"; _wipe_t = 0.0; _wipe_hard = hard
	_wipe_side = -1.0 if randf() < .5 else 1.0
	_wipe_spin = (-1.0 if randf() < .5 else 1.0) * (2.5 + hard * 7.0); _spin_a = 0.0
	velocity = f * sp * .5 + Vector3(0, 4.0 + sp * .26, 0)
	_bike_down = global_position
	yaw = heading
	_sfx("crash"); _sfx("thud")
	hurt_cd = 0.0
	take_hit(int(round(4 + sp * .35)), Vector3.ZERO, "crash")
	toast("🚲 [b]Düştün![/b] You came off the bike.", 2.6, true)
	if Fx.me:
		Fx.me.puff(global_position + Vector3(0, .6, 0), [Color("cabfd8"), Color("9a94a8"), Color("ff5fa2")], int(round(10 + hard * 16)), 2.2, 2.2, .9, .9)
		Fx.me.label(global_position + Vector3(0, 3.4, 0), "ÇARPTIN! 💥" if why == "mob" else ("UÇTUN! 🚲💥" if hard > .6 else "DÜŞTÜN! 🚲💥"), Color("ff5fa2"), 1.8)

func _wipe_tick(dt: float) -> void:
	_wipe_t += dt
	if bike:                                         # the bike stays where it fell
		bike.global_position = _bike_down + Vector3(0, .25, 0)
		bike.rotation = Vector3(0, heading + PI, _wipe_side * 1.5)
	match wipe:
		"fly":
			velocity.y -= 23.0 * dt
			move_and_slide(); _stay_on_land()
			_spin_a += _wipe_spin * dt
			if Fx.me and randf() < dt * 20 * (.3 + _wipe_hard):
				Fx.me.puff(global_position + Vector3(0, .4, 0), Color("cabfd8"), 1, .7, .6, .5, .6)
			if (is_on_floor() and velocity.y <= 0 and _wipe_t > .1) or _wipe_t > 4.0:
				wipe = "down"; _wipe_t = .45 + _wipe_hard * 1.3            # (counts down from here)
				velocity.x *= .35; velocity.z *= .35
				_sfx("thud")
				if Fx.me:
					Fx.me.shake(.2 + _wipe_hard * .35)
					Fx.me.puff(global_position + Vector3(0, .3, 0), [Color("cabfd8"), Color("9a94a8")], int(round(6 + _wipe_hard * 14)), 1.8, 1.2, .8, .9)
					if _wipe_hard > .55: Fx.me.label(global_position + Vector3(0, 2.2, 0), "AAA! 😵", Color("ff5fa2"), 1.4)
		"down":
			_wipe_t -= 2.0 * dt                       # (+dt above, so this nets −dt)
			velocity.x *= pow(.02, dt); velocity.z *= pow(.02, dt); velocity.y = -2.0
			move_and_slide(); _stay_on_land()
			if _wipe_t <= 0: wipe = "getup"; _wipe_t = .85
		"getup":
			_wipe_t -= 2.0 * dt
			velocity = Vector3.ZERO
			if _wipe_t <= 0:
				wipe = ""; _spin_a = 0.0
				if bike: bike.global_position = _bike_down; bike.rotation = Vector3(0, heading + PI, .13)
				toast("🚲 [b]Kalk bakalım.[/b] Up you get. [i]düşmek[/i] = to fall.", 3.0)
	if pose:
		pose.update(dt, t, false, 0.0, false, 0.0)
		match wipe:
			"fly": pose.tumble(t)
			"down": pose.lie()
			"getup": pose.getup(1.0 - _wipe_t / .85)
	_model_xf(dt)
	_regen(dt, false)
	_camera(dt); _shadow()
