# Bandit, her black dog — 7.2's updateBandit(): he trots after Torii, just behind her on one side, tail
# always wagging; faster when she's on the bike; lost (>24 m) = he pops back next to her.
#   Barks (BND-01): "hav hav! 🐶" every 9-19 s, "HAV HAV!! 🐶⚠️" every 4-7 s when a monster is within 9 m.
#   Chest duels (BND-03): Bus "duel" on = he plants himself between her and the crowd he's holding off
#   (the monsters with guard = true chase HIM) and bites them ("HAV!" / "GRRR" / "ÇEKİL!").
#   NEW: he helps in every fight — every few seconds he darts at a monster close to her, bites (small damage,
#   a flinch, a bark) and runs back. Bandit Strike (skill 2) lives in skills.gd and drives him itself.
class_name Bandit
extends Node3D

static var me: Bandit

const BITE_LINES := ["HAV! 🐶", "GRRR 🐶", "ÇEKİL! 🐶 (get away!)", "HAV HAV! 🐶"]

var torii: CharacterBody3D
var legs: Array[Node3D] = []
var tail: Node3D
var head: Node3D
var t := 0.0
var _next_bark := 6.0
var _bite_cd := 3.0
var _dash: Enemy = null          # the monster he's running at
var _dash_t := 0.0
var _back_t := 0.0                # after a bite: trot back before trying again
var _duel := false
var _yelp_cd := 0.0
var _ray_t := 0.0
var _gy := 0.0

func setup(model: Node3D, follow: CharacterBody3D) -> void:
	me = self; torii = follow
	add_child(model)
	for i in 4: legs.append(model.find_child("leg_%d" % i, true, false))
	tail = model.find_child("tail", true, false)
	head = model.find_child("head", true, false)
	Bus.on("duel", func(d: Dictionary): _duel = bool(d.get("on", false)))
	Bus.on("faint", func(_d): _dash = null; _duel = false)
	_gy = position.y

func _ground(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 3, z), Vector3(x, from_y - 12, z))
	q.exclude = [torii.get_rid()]; q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else from_y

# a monster on chest-duel crowd duty hit him: a yelp, he shakes it off (he never goes down)
func yelp() -> void:
	if _yelp_cd > 0: return
	_yelp_cd = 1.2
	Enemy.sfx("yelp", global_position)
	if Fx.me: Fx.me.label(global_position + Vector3(0, 1.4, 0), "KAİ! 🐶", Color("ffb0c8"), .8)

func _bark(danger: bool) -> void:
	Enemy.sfx("bark", global_position)
	if Fx.me: Fx.me.label(global_position + Vector3(0, 1.6, 0), "HAV HAV!! 🐶⚠️" if danger else "hav hav! 🐶", Color("ffd66b"), 1.4, true)

func _alive(e) -> bool:
	return is_instance_valid(e) and e is Enemy and e.is_alive()

func _physics_process(dt: float) -> void:
	if not torii or Overlay.any(): return
	t += dt; _bite_cd -= dt; _yelp_cd -= dt; _back_t -= dt
	var her_down := bool(torii.get("dead"))
	if _duel and _duel_tick(dt): return
	if _dash != null and _dash_tick(dt): return
	_follow(dt)
	# barks: a warning when something's close
	_next_bark -= dt
	var near := _nearest(9.0, global_position)
	if near != null and _next_bark > 7.0: _next_bark = 1.0     # something just showed up: warn her soon
	if _next_bark <= 0:
		_bark(near != null); _next_bark = randf_range(4, 7) if near != null else randf_range(9, 19)
	# NEW: he joins in — a monster close to her gets bitten every few seconds
	if not her_down and not torii.on_bike and _bite_cd <= 0 and _back_t <= 0:
		var tg := _nearest(7.0, torii.global_position)
		if tg != null and tg.global_position.distance_to(global_position) < 14.0 and not tg.is_boss():
			_dash = tg; _dash_t = 1.6

func _nearest(r: float, from: Vector3) -> Enemy:
	var best: Enemy = null; var bd := r
	for n in get_tree().get_nodes_in_group("enemies"):
		if not _alive(n): continue
		var e: Enemy = n
		if e.phase_t > 0: continue
		var d := e.global_position - from; d.y = 0
		if d.length() < bd: bd = d.length(); best = e
	return best

func _follow(dt: float) -> void:
	var f := -torii.global_transform.basis.z           # her forward
	var p := torii.global_position
	var tx := p.x - f.x * 1.6 - f.z * 1.15
	var tz := p.z - f.z * 1.6 + f.x * 1.15
	var dx := tx - position.x
	var dz := tz - position.z
	var d := sqrt(dx * dx + dz * dz)
	if d > 24.0:
		position = Vector3(tx, p.y, tz)
	elif d > .35:
		var sp: float = minf(d * 3.2, 30.0 if torii.on_bike else 10.5)
		position.x += dx / d * sp * dt; position.z += dz / d * sp * dt
		rotation.y = atan2(dx, dz)
	_animate(d > .6, 11.0, .5, .14, p.y)

func _animate(mov: bool, rate: float, swing: float, bob: float, ref_y: float) -> void:
	_ray_t -= get_physics_process_delta_time()
	if _ray_t <= 0: _ray_t = .05; _gy = _ground(position.x, position.z, maxf(ref_y, position.y))
	position.y = _gy + (absf(sin(t * 9)) * bob if mov else 0.0)
	if tail: tail.rotation.y = sin(t * 10) * .55
	for i in legs.size():
		if legs[i]: legs[i].rotation.x = sin(t * rate + (i % 2) * PI) * swing if mov else 0.0

# run at the target, bite, then trot back to her
func _dash_tick(dt: float) -> bool:
	_dash_t -= dt
	if not _alive(_dash) or _dash_t <= 0: _dash = null; _bite_cd = 1.5; return false
	var to := _dash.global_position - global_position; to.y = 0
	var reach: float = _dash.radius + .9
	if to.length() > reach:
		position += to.normalized() * 17.0 * dt; rotation.y = atan2(to.x, to.z)
		_animate(true, 18.0, .8, .25, _dash.global_position.y)
		return true
	_bite(_dash, false)
	_dash = null; _back_t = 1.2; _bite_cd = randf_range(3.5, 5.5)
	return false

func _bite(e: Enemy, duel: bool) -> void:
	var L := maxi(1, SaveBridge.get_i("lvl", 1))
	var dmg := 7.0 if duel else 6.0 + L * 1.2
	var dir := e.global_position - global_position; dir.y = 0
	e.hit(dmg, dir.normalized() if dir.length() > .01 else Vector3.FORWARD, {"kb": 3.0, "src": "bandit"})
	Enemy.sfx("bark", global_position)
	if head: head.rotation.x = .4
	if Fx.me:
		Fx.me.label(global_position + Vector3(0, 1.5, 0), BITE_LINES.pick_random(), Color("ffd66b"), 1.0, true)
		Fx.me.puff(e.global_position + Vector3(0, .8, 0), Color("ffd66b"), 5, 1.0, 1.0, .4)

# chest duel: stand between her and the held crowd, bite whoever's close
func _duel_tick(dt: float) -> bool:
	var held: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if _alive(n) and n.guard: held.append(n)
	if held.is_empty(): return false
	var c := Vector3.ZERO
	for e in held: c += e.global_position
	c /= held.size()
	var p := torii.global_position
	var g := p + (c - p) * .42
	var to := g - global_position; to.y = 0
	var bd := to.length()
	if bd > 1.0:
		position += to / bd * minf(14.0, bd * 3.0) * dt; rotation.y = atan2(to.x, to.z)
	_animate(true, 15.0, .6, .16, p.y)
	if randf() < dt * .7: Enemy.sfx("bark", global_position)
	if _bite_cd <= 0:
		for e in held:
			if e.global_position.distance_to(global_position) < e.radius + 1.6:
				_bite(e, true); _bite_cd = 1.1; break
	if head: head.rotation.x = lerpf(head.rotation.x, 0.0, minf(1.0, dt * 6))
	return true

func _process(dt: float) -> void:
	if head and _dash == null and not _duel: head.rotation.x = lerpf(head.rotation.x, 0.0, minf(1.0, dt * 6))
