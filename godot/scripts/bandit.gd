# Bandit, ported from updateBandit() in 7.2: he trots after Torii, keeping just behind her on one side,
# tail always wagging. Faster when she's on the bike; if he's lost (>24 m) he pops back next to her.
extends Node3D

var torii: CharacterBody3D
var legs: Array[Node3D] = []
var tail: Node3D
var t := 0.0

func setup(model: Node3D, follow: CharacterBody3D) -> void:
	torii = follow
	add_child(model)
	for i in 4: legs.append(model.find_child("leg_%d" % i, true, false))
	tail = model.find_child("tail", true, false)

func _ground(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 3, z), Vector3(x, from_y - 12, z))
	q.exclude = [torii.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else from_y

func _physics_process(dt: float) -> void:
	if not torii: return
	t += dt
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
		var sp: float = min(d * 3.2, 30.0 if torii.on_bike else 10.5)
		position.x += dx / d * sp * dt; position.z += dz / d * sp * dt
		rotation.y = atan2(dx, dz)
	var mov := d > .6
	position.y = _ground(position.x, position.z, p.y) + (absf(sin(t * 9)) * .14 if mov else 0.0)
	if tail: tail.rotation.y = sin(t * 10) * .55
	for i in legs.size():
		if legs[i]: legs[i].rotation.x = sin(t * 11 + (i % 2) * PI) * .5 if mov else 0.0
