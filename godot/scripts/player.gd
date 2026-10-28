# Torii — same controls as the HTML game: WASD / arrows move (A/D strafe), mouse looks,
# Shift sprints, Space jumps, E gets on/off the bike. On the bike: W pedal, S brake/reverse,
# A/D steer, Space boost (numbers from 7.2's updatePlayer). Third-person camera behind her.
extends CharacterBody3D

const WALK := 4.6
const SPRINT := 1.62               # forward multiplier while sprinting (strafe gets 1.34), as in 7.2
const JUMP := 7.4
const GRAVITY := 22.0
const SENS := 0.0028

var yaw := 0.0
var pitch := -0.12
var model: Node3D
var pose: ToriiPose
var cam: Camera3D
var t := 0.0
# the bike
var bike: Node3D
var wheels: Array[Node3D] = []
var crank: Node3D
var on_bike := false
var bspeed := 0.0
var lean := 0.0
var boost_cd := 0.0
const BIKE_REACH := 2.6
# fighting (7.2 katana: 26 dmg, .45 s cooldown, 2.6 m reach, 1.1 rad arc; a swing lasts .28 s)
signal hp_changed(hp, max_hp)
var max_hp := 100
var hp := 100
var weapon := {"id": "katana", "dmg": 26.0, "cd": .45, "rng": 2.6, "arc": 1.1}
var attack_t := 0.0
var attack_cd := 0.0
var hand: Node3D
var hurt_cd := 0.0

func set_bike(b: Node3D) -> void:
	bike = b
	for n in ["wheel_f", "wheel_b"]: wheels.append(b.find_child(n, true, false))
	crank = b.find_child("crank", true, false)

func setup(torii_scene: PackedScene) -> void:
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
	var pivot := Node3D.new(); pivot.name = "CamPivot"; pivot.position.y = 1.75; add_child(pivot)
	cam = Camera3D.new(); cam.fov = 60; cam.near = .05; cam.far = 400
	cam.position = Vector3(.45, .35, 3.4); pivot.add_child(cam); cam.current = true

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s: return s
	return null

func hold(weapon_scene: PackedScene, stats: Dictionary) -> void:
	weapon = stats
	if not hand: return
	for c in hand.get_children(): c.queue_free()
	hand.add_child(weapon_scene.instantiate())

func take_hit(dmg: int) -> void:
	if hurt_cd > 0: return
	hurt_cd = .4
	hp = max(0, hp - dmg); hp_changed.emit(hp, max_hp)

func heal_full() -> void:
	hp = max_hp; hp_changed.emit(hp, max_hp)

func _attack() -> void:
	if attack_cd > 0 or on_bike: return
	attack_cd = weapon["cd"]; attack_t = .28
	var f := -global_transform.basis.z
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.global_position - global_position; to.y = 0
		if to.length() <= weapon["rng"] and absf(f.signed_angle_to(to.normalized(), Vector3.UP)) <= weapon["arc"]:
			e.hit(weapon["dmg"])

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_attack()
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * SENS
		pitch = clampf(pitch - e.relative.y * SENS, -1.0, .6)

func _physics_process(dt: float) -> void:
	t += dt
	if Input.is_action_just_pressed("interact") and bike:
		if on_bike: _get_off()
		elif global_position.distance_to(bike.global_position) < BIKE_REACH: _get_on()
	attack_cd -= dt; attack_t -= dt; hurt_cd -= dt
	if Input.is_action_just_pressed("attack"): _attack()
	if on_bike:
		_ride(dt)
		return
	var fwd := Input.get_axis("move_back", "move_forward")
	var strafe := Input.get_axis("move_left", "move_right")
	var run := Input.is_action_pressed("sprint") and (fwd != 0 or strafe != 0)
	var sp := fwd * WALK * (SPRINT if run else 1.0)
	var st := strafe * WALK * .8 * (1.34 if run else 1.0)
	rotation.y = yaw
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := basis_y * Vector3(st, 0, -sp)
	velocity.x = dir.x; velocity.z = dir.z
	if is_on_floor():
		if Input.is_action_just_pressed("jump"): velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	$CamPivot.rotation.x = pitch
	var ground := Vector2(velocity.x, velocity.z).length()
	if pose:
		pose.update(dt, t, ground > .2, ground, not is_on_floor(), velocity.y)
		if attack_t > 0: pose.swing(1.0 - attack_t / .28)

func _get_on() -> void:
	on_bike = true; bspeed = 0.0
	global_position = Vector3(bike.global_position.x, global_position.y, bike.global_position.z)
	yaw = bike.rotation.y - PI                      # the bike model faces +z, she faces -z
	bike.rotation.z = 0

func _get_off() -> void:
	on_bike = false; bspeed = 0.0
	bike.rotation.z = .13                           # parked on its stand, like 7.2
	global_position += global_transform.basis.x * 1.0   # step off to her right

func _ride(dt: float) -> void:
	var up := Input.is_action_pressed("move_forward")
	var dn := Input.is_action_pressed("move_back")
	var st := Input.get_axis("move_right", "move_left")      # + = turn left
	var tf := clampf(1.75 - bspeed * .028, .6, 1.75)          # tighter turns when slow
	if absf(bspeed) > .5: yaw += st * tf * dt * (-.6 if bspeed < 0 else 1.0)
	if up: bspeed += 15 * dt
	if dn: bspeed -= (27 if bspeed > 0 else 9) * dt
	bspeed -= (4.2 + bspeed * .11 if bspeed > 0 else -3.4) * dt
	bspeed = clampf(bspeed, -5.5, 27)
	boost_cd -= dt
	if Input.is_action_just_pressed("jump") and boost_cd <= 0 and bspeed > 1:
		bspeed = min(31.0, bspeed + 7.5); boost_cd = 1.15
	rotation.y = yaw
	var f := -global_transform.basis.z
	velocity.x = f.x * bspeed; velocity.z = f.z * bspeed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if is_on_wall() and absf(bspeed) > 3.5: bspeed *= .4   # 7.2 crashes above 9 — the tumble comes later
	lean = -st * .24 * min(1.0, absf(bspeed) / 13.0)
	bike.global_position = global_position
	bike.rotation = Vector3(0, yaw + PI, lean)
	for w in wheels:
		if w: w.rotation.x -= bspeed * dt * 2
	if crank: crank.rotation.x -= max(0.0, bspeed) * dt * 1.1
	$CamPivot.rotation.x = pitch
	if pose: pose.ride(t, bspeed, lean)
