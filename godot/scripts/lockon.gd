# Lock-on (Tab, new in Godot): picks the monster most in front of her within 22 m; Tab again cycles to the
# next one, and after the last one it lets go. Drops by itself when the target dies or gets past 28 m.
# The player strafes round the target while locked and the camera frames both. This node is the pink
# marker spinning over the target's head; the player keeps the target in player.lock_target.
class_name LockOn
extends Node3D

const RANGE := 22.0
const KEEP := 28.0
var _seen: Array = []                # ids already cycled through this round
var _mesh: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	top_level = true
	var m := PrismMesh.new(); m.size = Vector3(.42, .42, .12)
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ff5fa2"); mat.no_depth_test = true; mat.render_priority = 10
	m.material = mat
	_mesh = MeshInstance3D.new(); _mesh.mesh = m; _mesh.rotation.z = PI     # pointing down at it
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(_mesh)
	visible = false

static func alive(e) -> bool:
	if e == null or not is_instance_valid(e) or (e is Node and not e.is_inside_tree()): return false
	if e.has_method("is_alive"): return e.is_alive()
	var h = e.get("hp")
	return h == null or float(h) > 0.0

# Tab: lock the best target, or move on to the next; returns the new target (null = let go)
func cycle(p: Node3D, cur, fwd: Vector3) -> Node3D:
	if not alive(cur): cur = null; _seen = []
	elif not _seen.has(cur.get_instance_id()): _seen.append(cur.get_instance_id())
	var best: Node3D = null
	var bs := INF
	for e in p.get_tree().get_nodes_in_group("enemies"):
		if not alive(e) or e == cur or _seen.has(e.get_instance_id()): continue
		var to: Vector3 = e.global_position - p.global_position; to.y = 0
		var d := to.length()
		if d > RANGE: continue
		var dot := fwd.dot(to / d) if d > .01 else 1.0
		if dot < .15 and d > 5.0: continue                    # behind her and not close: skip
		var s := d * (1.6 - dot)
		if s < bs: bs = s; best = e as Node3D
	if best == null: _seen = []
	return best

# every frame: is the target still worth holding? Moves the marker; returns the target or null
func tick(p: Node3D, cur, dt: float) -> Node3D:
	_t += dt
	if not alive(cur) or cur.global_position.distance_to(p.global_position) > KEEP: cur = null
	visible = cur != null
	if cur:
		var h := 2.7
		var fl = cur.get("flags")
		if fl is Dictionary and fl.has("boss"): h = 4.4
		elif cur.get("elite"): h = 3.4
		global_position = cur.global_position + Vector3(0, h + sin(_t * 5.0) * .12, 0)
		_mesh.rotation.y = _t * 3.0
	return cur
