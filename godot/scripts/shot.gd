# A monster's ranged attack (7.2: casters' purple shots, skeleton archers' arrows). Flies straight at where
# Torii was; touching her hurts. Dodge by moving.
class_name Shot
extends MeshInstance3D

var vel := Vector3.ZERO
var dmg := 8
var life := 2.5
var torii: Node3D

static func fire(parent: Node, from: Vector3, target: Node3D, damage: int, arrow: bool) -> void:
	var s := Shot.new(); parent.add_child(s)
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(.85, .8, .6) if arrow else Color(.7, .3, 1)
	if arrow:
		var b := BoxMesh.new(); b.size = Vector3(.05, .05, .6); b.material = m; s.mesh = b
	else:
		var sp := SphereMesh.new(); sp.radius = .22; sp.height = .44; sp.material = m; s.mesh = sp
	s.global_position = from; s.torii = target; s.dmg = damage
	var aim := target.global_position + Vector3(0, 1.1, 0)
	s.vel = (aim - from).normalized() * (16.0 if arrow else 11.0)
	s.look_at_from_position(from, aim)

func _physics_process(dt: float) -> void:
	global_position += vel * dt; life -= dt
	if torii and global_position.distance_to(torii.global_position + Vector3(0, 1.1, 0)) < .8:
		torii.take_hit(dmg); queue_free(); return
	if life <= 0: queue_free()
