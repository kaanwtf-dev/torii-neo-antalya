# Everyone in the city who isn't Torii: one of the two NPC bases (Kaan's NPC sheet) wearing one of its
# outfit textures. Placed and animated like 7.2's person() people: walkers loop round their square
# (updatePeds), the rest stand and idle (idlePerson) or sit (sitPerson), Kaan waves from his balcony
# when she's near (updateKaan). Pose numbers are 7.2's, through ToriiPose's joint helpers.
class_name Npc
extends Node3D

const PERSON_H := 2.06          # 7.2's people are ~2.05-2.1 m; the bases are 2.2 / 2.15
const BASES := {"male": ["res://assets/npc/npc_male.glb", 2.2], "female": ["res://assets/npc/npc_female.glb", 2.15]}
static var _scenes := {}
static var _hips := {}

var mode := "idle"              # idle / walk / sit / kaan
var pose: ToriiPose
var ph := 0.0                   # each person's own phase, so nobody moves in lockstep
var walk := {}                  # walkers: cx, cz, t, sp
var torii: Node3D
var base_y := 0.0
var t := 0.0
var _ground_cd := 0.0

# kind: "male"/"female"; outfit: texture path; sc: 7.2's scale (kids are ~0.65)
func setup(kind: String, outfit: String, sc: float, who: Node3D) -> void:
	torii = who; scene_kind = kind
	if not _scenes.has(kind): _scenes[kind] = load(BASES[kind][0])
	var model: Node3D = _scenes[kind].instantiate()
	add_child(model)
	scale = Vector3.ONE * sc * PERSON_H / BASES[kind][1]
	var tex: Texture2D = load(outfit)
	var sk: Skeleton3D
	for n in model.find_children("*", "", true, false):
		if n is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS; m.roughness = 1
			n.material_override = m
		elif n is Skeleton3D: sk = n
	if sk:
		# the bases rest in an A-pose: measure how far the arms have to swing to hang straight
		var sh := sk.get_bone_global_rest(sk.find_bone("arm_p")).origin
		var el := sk.get_bone_global_rest(sk.find_bone("elb_p")).origin
		pose = ToriiPose.new(sk, atan2(el.x - sh.x, sh.y - el.y))
		if not _hips.has(kind): _hips[kind] = sk.get_bone_global_rest(sk.find_bone("leg_p")).origin.y
	ph = randf() * TAU

func _process(dt: float) -> void:
	if not pose: return
	t += dt
	# people far from her don't need animating
	if torii and global_position.distance_squared_to(torii.global_position) > 90.0 * 90.0: return
	match mode:
		"walk": _walk(dt)
		"sit": _sit()
		"kaan": _kaan()
		_: _idle()

func _walk(dt: float) -> void:
	walk.t = fmod(walk.t + walk.sp * dt, 4.0)
	var h := 17.0
	var seg := int(walk.t)
	var u: float = (walk.t - seg) * 2.0 - 1.0
	var x: float = walk.cx; var z: float = walk.cz; var ry := 0.0
	match seg:
		0: x += u * h; z -= h; ry = PI / 2
		1: x += h; z += u * h; ry = 0.0
		2: x -= u * h; z += h; ry = -PI / 2
		_: x -= h; z -= u * h; ry = PI
	var phase := t * 6.4 + ph
	_gait(phase, .5)
	_ground_cd -= dt
	if _ground_cd <= 0:
		_ground_cd = .25; base_y = _ground(x, z)
	position = Vector3(x, base_y + absf(sin(phase)) * .05, z); rotation.y = ry

# walkPerson(): opposed legs, counter-swinging arms, knees fold on the back-swing, elbows carried bent
func _gait(phase: float, amp: float) -> void:
	var sw := sin(phase)
	pose.leg(-1, sw * amp); pose.leg(1, -sw * amp)
	pose.arm(-1, -sw * amp * .72, 0, .08); pose.arm(1, sw * amp * .72, 0, -.08)
	pose.knee(-1, amp * max(0.0, -sin(phase - .9)) * 1.15 + .05)
	pose.knee(1, amp * max(0.0, sin(phase - .9)) * 1.15 + .05)
	pose.elbow(-1, -.22 - amp * max(0.0, sw) * .7); pose.elbow(1, -.22 - amp * max(0.0, -sw) * .7)
	pose.body(0, 0, 0); pose.head(0, sw * .09)

# idlePerson(): breathing, a slow weight shift, now and then a look around
func _idle() -> void:
	var br := sin(t * 1.4 + ph); var sh := sin(t * .37 + ph)
	pose.leg(-1, .02 + sh * .02, .03); pose.leg(1, -.02 - sh * .02, -.03)
	pose.knee(-1, .05 + max(0.0, sh) * .1); pose.knee(1, .05 + max(0.0, -sh) * .1)
	pose.arm(-1, br * .05, 0, .09 + sh * .04); pose.arm(1, sin(t * 1.4 + ph + 1) * .05, 0, -.09 + sh * .04)
	pose.elbow(-1, -.18 + br * .05); pose.elbow(1, -.18 - br * .05)
	pose.body(0, 0, 0, br * .012)
	var glance := sin(t * .21 + ph * 2.3)
	pose.head(br * .03, (((glance - .86) * 7.0) if glance > .86 else 0.0) * (1.0 if fmod(ph, 2.0) < 1.0 else -1.0) - sh * .12)

# sitPerson(): thighs forward, shins down, hands in the lap
func _sit() -> void:
	pose.leg(-1, -1.5, .06); pose.leg(1, -1.5, -.06)
	pose.knee(-1, 1.4); pose.knee(1, 1.4)
	pose.arm(-1, -.45, 0, -.1); pose.arm(1, -.45, 0, .1)
	pose.elbow(-1, -.8); pose.elbow(1, -.8)
	pose.body(0, 0, 0); pose.head(sin(t * 1.4 + ph) * .03, sin(t * .3 + ph) * .2)

# updateKaan(): idles on the balcony, waves at her when she's close
func _kaan() -> void:
	_idle()
	if torii and global_position.distance_squared_to(torii.global_position) < 340.0:
		pose.arm(1, 0, 0, 2.5 + sin(t * 7) * .4); pose.elbow(1, -.3)

# seat height in 7.2 = its person's origin + 0.8·scale: put this base's hips there
func sit_at(y: float, sc: float) -> void:
	mode = "sit"
	position.y = y + .8 * sc - _hips.get(scene_kind, 1.0) * scale.y + .02

var scene_kind := "male"

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, base_y + 4, z), Vector3(x, base_y - 8, z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else base_y
