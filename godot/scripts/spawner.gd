# The roaming spawn director — 7.2's spawnDirector() (+ updateEnemies' >95 m despawn) and the stinky Cruze
# (initStinkCar / moveStinkCar / updateStink, STINK_SPOTS).
#   Every 6.2 s (4.5 s once the story is done, faster at night) a monster turns up 30-55 m from her, kept
#   inside the zone (ZB), never near Kaan's home or a checkpoint, never on a roof. The cap is 7.2's
#   4 + level + minutes played (max +7) (+3 free play). The pool grows with her level like 7.2; the hunt
#   gate's monster is mixed in x3 and epics come at 28% while the gate still owes some (CMB-V01).
#   Rare minibosses: 7.2's 5% per tick from level 6 (Lory by the beach, Vergi downtown, Kapıcı midtown),
#   plus NEW: one is guaranteed every ~6 min of roaming at level 6+ so she actually meets them.
#   NEW: night (Bus "night", or the computer clock until someone sends it) = more of them, tougher
#   (+1 level, +HP/+damage in Enemy.setup), ghosts/skeletons earlier, neon jinns only at night,
#   and stray-cat packs come in threes to fives (the swarm).
# Pauses while a menu is open (Overlay.any()), while paused = true (missions/cutscenes), and for a moment
# after she faints. Spawner.me.clear_near(pos, r) sweeps the roaming ones away (cutscenes, safe moments).
class_name Spawner
extends Node

static var me: Spawner

# 7.2 ZB: [x0, x1, z0, z1] per zone
const ZB := {"city": [-520, 152, -424, 332], "cam": [562, 638, -38, 38], "az": [562, 638, 262, 338], "liv": [562, 638, -338, -262]}
const HOME := Vector2(-24, -8)                   # Kaan's place (7.2: no spawns within 20 m)
const SAFE := [[-24, -8, 22.0], [-16, -8, 14.0], [116, 2, 14.0], [60, -52, 14.0], [60, 50, 14.0], [-40, -132, 14.0]]
const STINK_SPOTS := [[-52, -7], [44, -30], [-88, 34], [16, -96], [-116, -58], [72, 28], [-30, 110], [-150, 20], [100, -110], [-70, -128]]
const DESPAWN := 95.0

var world: Node3D
var torii: CharacterBody3D
var paused := false
var night := false
var _night_bus := false                          # true once anyone sends Bus "night" (then the clock is ignored)
var enabled := true
var _t := 4.0
var _calm := 0.0
var _mini_t := 360.0
var _desp_t := 1.0
var _clock_t := 0.0
var _start_ms := 0
var safe: Array = []                             # [x, z, r] extra safe spots others add (add_safe)
# the stinky Cruze
var stink: Node3D
var _stink_move := 25.0
var _stink_cd := 0.0
var _stink_told := false

func setup(w: Node3D, p: CharacterBody3D) -> void:
	me = self; world = w; torii = p
	_start_ms = Time.get_ticks_msec()
	safe = SAFE.duplicate(true)
	Bus.on("night", func(d: Dictionary):
		_night_bus = true; _set_night(bool(d.get("on", false))))
	Bus.on("faint", func(_d): _calm = 12.0)
	Bus.on("respawn", func(_d): _calm = maxf(_calm, 8.0))
	_clock_night()
	_init_stink()

func add_safe(at: Vector3, r: float) -> void: safe.append([at.x, at.z, r])

# sweep the roaming ones (and, with every_one, anything that isn't a boss / chest keeper) out of an area
func clear_near(pos: Vector3, r: float, every_one := false) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Enemy) or e.is_boss() or e.guard: continue
		if not every_one and not e.has_meta("roam"): continue
		var d: Vector3 = e.global_position - pos; d.y = 0
		if d.length() < r:
			if Fx.me: Fx.me.puff(e.global_position + Vector3(0, 1, 0), [Color("b06bff"), Color("8ff2ff")], 6, 1.2, 1.4, .5)
			e.queue_free()

func zone_of(p: Vector3) -> String:
	for z in ZB:
		var B: Array = ZB[z]
		if p.x > B[0] and p.x < B[1] and p.z > B[2] and p.z < B[3]: return z
	return "city"

func _lvl() -> int: return maxi(1, SaveBridge.get_i("lvl", 1))

func _set_night(on: bool) -> void:
	if on == night: return
	night = on
	var hud := Enemy._hud()
	if on and hud: hud.toast("🌙 [b]Gece oldu.[/b] Night: more monsters, and meaner. [i]gece[/i] = night", 6.0)
	if on: _t = minf(_t, 2.0)

# nobody owns the day/night Bus event yet: use the computer clock like 7.2's partOfDay (gece < 5:12, ≥ 20:24)
func _clock_night() -> void:
	if _night_bus: return
	var tm := Time.get_datetime_dict_from_system()
	var h: float = float(tm["hour"]) + float(tm["minute"]) / 60.0
	_set_night(h < 5.2 or h >= 20.4)

func _process(dt: float) -> void:
	if not enabled or not is_instance_valid(torii) or Overlay.any(): return
	_clock_t -= dt
	if _clock_t <= 0: _clock_t = 30.0; _clock_night()
	_stink_tick(dt)
	_desp_t -= dt
	if _desp_t <= 0: _desp_t = 1.0; _despawn()
	if paused or bool(torii.get("dead")): return
	if _calm > 0: _calm -= dt; return
	if zone_of(torii.global_position) == "city" and _lvl() >= 6: _mini_t -= dt
	_t -= dt
	if _t > 0: return
	var done := bool(SaveBridge.data.get("done", false))
	_t = (4.5 if done else 6.2) * (.75 if night else 1.0)
	_tick(done)

# 7.2: anything >95 m from her goes (bosses and chest keepers stay; mission monsters too — they're not roamers)
func _despawn() -> void:
	var p := torii.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Enemy) or not e.has_meta("roam") or e.is_boss() or e.guard: continue
		var d: Vector3 = e.global_position - p; d.y = 0
		if d.length() > DESPAWN: e.queue_free()

func _tick(done: bool) -> void:
	var L := _lvl()
	var zone := zone_of(torii.global_position)
	var mins := float(Time.get_ticks_msec() - _start_ms) / 60000.0
	var cap := (4 + L + mini(7, int(mins)) + (3 if done else 0) + (3 if night else 0)) if zone == "city" else (4 + int(L / 2.0) + (2 if night else 0))
	var alive := get_tree().get_nodes_in_group("enemies").size()
	if alive >= cap: return
	var at := _spot(zone)
	if at == Vector3.INF: return
	var gate = SaveBridge.data.get("gate")
	var g: Dictionary = gate if gate is Dictionary else {}
	var pool: Array = _pool(zone, L, at, g)
	var kind: String = pool.pick_random()
	if _mini_t <= 0 and zone == "city" and not _mini_alive():         # NEW: the guaranteed rare one
		kind = _mini_for(torii.global_position, true); _mini_t = randf_range(330, 420)
	elif _is_mini(kind): _mini_t = randf_range(330, 420)
	var elite_ch := .28 if int(g.get("eleft", 0)) > 0 else minf(.15, .05 + L * .01) + (.05 if night else 0.0)
	if _is_mini(kind): elite_ch = 0.0
	if kind == "cat":                                                 # NEW: strays come as a pack
		var n := randi_range(3, 5) + (1 if night else 0)
		for i in n:
			var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			_spawn("cat", at + off, randf() < elite_ch * .5)
		return
	_spawn(kind, at, randf() < elite_ch)

func _is_mini(kind: String) -> bool:
	Enemy._load_data()
	return bool((Enemy.DATA.get(kind, {}) as Dictionary).get("mini", false))

func _mini_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.flags.has("mini"): return true
	return false

# 7.2: each rare one lives in its part of the city. force = pick the nearest fit when she's elsewhere
func _mini_for(p: Vector3, force := false) -> String:
	if p.x > 84: return "lory"
	if p.x < -70 and p.z < -40: return "vergi"
	if p.x > -45 and p.x < 10 and p.z > -40 and p.z < 25: return "kapici"
	if not force: return ""
	return ["lory", "vergi", "kapici"].pick_random()

func _pool(zone: String, L: int, _at: Vector3, g: Dictionary) -> Array:
	match zone:
		"cam": return ["spirit"]
		"az": return ["scorpion"]
		"liv": return ["wisp"]
	var pool: Array = ["imp", "imp"]
	if L >= 2: pool.append("zombie")
	if L >= 3: pool.append("thot")
	if L >= 4 or (night and L >= 2): pool.append_array(["ghost", "skeleton"])
	if L >= 5: pool.append("witch")
	if L >= 6: pool.append("mummy")
	if L >= 5: pool.append("okuz")
	if L >= 7 and randf() < .06: pool.append("driver")
	# NEW kinds
	if L >= 2: pool.append("cat")
	if L >= 4: pool.append("thug")
	if night:
		pool.append_array(["ghost", "zombie"])
		if L >= 5: pool.append("jinn")
	# 7.2's rare minibosses, each tied to a part of the city
	if L >= 6 and randf() < .05 and not _mini_alive():
		var m := _mini_for(torii.global_position)
		if m != "": pool = [m]
	if g.get("type") is String and str(g["type"]) != "" and int(g.get("left", 0)) > 0:
		for i in 3: pool.append(str(g["type"]))
	return pool

# a spot 30-55 m out, inside the zone, not at home / a checkpoint, on open ground (not a roof, not water)
func _spot(zone: String) -> Vector3:
	var B: Array = ZB[zone]
	var p := torii.global_position
	for tries in 4:
		var a := randf() * TAU; var dd := randf_range(30.0, 55.0)
		var x := clampf(p.x + sin(a) * dd, B[0] + 4, B[1] - 4)
		var z := clampf(p.z + cos(a) * dd, B[2] + 4, B[3] - 4)
		if zone == "city":
			if Vector2(x, z).distance_to(HOME) < 20.0: continue
			if x > 100 and randf() < .55: continue                    # 7.2: the beach is quieter
		var bad := false
		for s in safe:
			if Vector2(x - float(s[0]), z - float(s[1])).length() < float(s[2]): bad = true; break
		if bad: continue
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, p.y + 30.0, z), Vector3(x, p.y - 30.0, z)); q.collision_mask = 1
		var h := world.get_world_3d().direct_space_state.intersect_ray(q)
		if h.is_empty(): continue
		var y: float = h["position"].y
		if y > p.y + 4.5 or y < p.y - 8.0: continue                   # roofs and drops
		if (h["normal"] as Vector3).y < .7: continue
		var w = torii.get("water")
		if w is Array and _in_water(w, x, z): continue
		return Vector3(x, y + .1, z)
	return Vector3.INF

func _in_water(rects: Array, x: float, z: float) -> bool:
	for r in rects:
		if r is Array and r.size() >= 4 and x > float(r[0]) and x < float(r[1]) and z > float(r[2]) and z < float(r[3]): return true
	return false

func _spawn(kind: String, at: Vector3, elite: bool) -> Enemy:
	var e := Enemy.spawn(world, kind, at, torii, elite, {"roam": true, "night": night})
	e._snap = false                                                  # _spot already found the ground
	return e

# ---------------------------------------------------------------- HAZ-01: the stinky Cruze
func _init_stink() -> void:
	var path := "res://assets/mobs/cruze.glb"
	if not ResourceLoader.exists(path): return
	stink = (load(path) as PackedScene).instantiate(); Tint.apply(stink)
	stink.name = "StinkCruze"; world.add_child(stink)
	stink.position = Vector3(-52, 0, -7); _stink_move = .5     # placed for real once the world has physics

func _place_stink(s: Array) -> void:
	var x := float(s[0]); var z := float(s[1])
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z)); q.collision_mask = 1
	var h := world.get_world_3d().direct_space_state.intersect_ray(q)
	stink.position = Vector3(x, h["position"].y if h else 0.0, z); stink.rotation.y = randf() * TAU

func _stink_tick(dt: float) -> void:
	if not stink or not is_instance_valid(stink): return
	var city := zone_of(torii.global_position) == "city"
	stink.visible = city
	if not city: return
	_stink_move -= dt
	if _stink_move <= 0:
		_stink_move = randf_range(45, 80); _place_stink(STINK_SPOTS.pick_random())
	if Fx.me and randf() < dt * 3:
		Fx.me.puff(stink.global_position + Vector3(randf_range(-1.5, 1.5), 1, randf_range(-2, 2)), [Color("7a8a3a"), Color("9aa84e")], 1, .5, 1.1, 2.2, .6)
	_stink_cd -= dt
	var d := stink.global_position - torii.global_position; d.y = 0
	if d.length() < 8.0 and _stink_cd <= 0 and not bool(torii.get("dead")):
		_stink_cd = 2.0
		var shield: bool = torii.has_method("has_status") and bool(torii.call("has_status", "shield"))
		if shield:                                    # 7.2: the shield only takes the edge off (2 instead of 6)
			torii.set("hp", maxi(1, int(torii.get("hp")) - 2)); torii.emit_signal("hp_changed", torii.get("hp"), torii.get("max_hp"))
		else: torii.call("take_hit", 6, stink.global_position, "stink")
		Enemy.sfx("stink", torii.global_position)
		if Fx.me: Fx.me.flash_screen(Color("9aa84e"), .3, .6)
		var hud := Enemy._hud()
		if hud and not _stink_told:
			_stink_told = true
			hud.toast("🤢 [b]THAT SMELL![/b] Your car has not been washed since 2017 · Turkish: [i]koku[/i] = smell", 6.0, true)
		if Lessons.me: Lessons.me.teach("koku")
