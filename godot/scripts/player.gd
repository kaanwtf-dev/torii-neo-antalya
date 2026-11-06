# Torii — 7.2's controls: W/S (or ↑/↓) walk, A/D strafe, ←/→ turn her, the mouse aims, Shift sprints,
# Space jumps, E gets on/off the bike, F / left click attacks, Q next weapon. On the bike: W pedal,
# S brake/reverse, A/D (or ←/→) steer, Space boost; the mouse only looks around and the camera drifts back
# behind the bike 1.3 s after it stops (7.2's updatePlayer / updateCam). While an overlay is open (a
# lesson, a call, a choice, the save screen) she waits and can't be hurt.
extends CharacterBody3D

const WALK := 7.3                  # 7.2: forward 7.3, back 4.3, strafe 6.2
const BACK := 4.3
const STRAFE := 6.2
const SPRINT := 1.62               # Shift: forward x1.62, strafe x1.34
const TURN := 2.95                 # arrow keys turn her, for anyone without a mouse
const JUMP := 7.4
const GRAVITY := 22.0
const SENS := 0.0022               # 7.2's mouse look

var yaw := 0.0                     # where the camera looks; on foot she faces it, on the bike it's free
var pitch := .12                   # 7.2: higher = camera up and looking down; mouse down raises it
var heading := 0.0                 # the bike's own direction
var look_t := -10.0                # last mouse movement (the riding camera re-centres 1.3 s after)
var look_back := false
var cam_off := 0.0                 # dev shots only: swing the camera round her
var _cam_snap := true
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
var dance_t := 0.0                    # > 0: she's dancing (mission zones, victories)

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
	cam = Camera3D.new(); cam.fov = 62; cam.near = .05; cam.far = 400; cam.top_level = true
	add_child(cam); cam.current = true

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
	if weapon_scene: hand.add_child(weapon_scene.instantiate())

# her weapons = the save's `weap` list (7.2's names and stats); Q switches to the next one
static var WSTATS := {}
func equip_from_save() -> void:
	if WSTATS.is_empty(): WSTATS = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["weapons"]
	var weap: Array = SaveBridge.data.get("weap", ["katana"])
	if weap.is_empty(): weap = ["kick"]
	var wi := clampi(SaveBridge.get_i("wi"), 0, weap.size() - 1)
	equip(weap[wi])

func equip(id: String) -> void:
	if WSTATS.is_empty(): WSTATS = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["weapons"]
	var w: Dictionary = WSTATS.get(id, WSTATS["kick"])
	var path := "res://assets/weapons/%s.glb" % id
	hold(load(path) if ResourceLoader.exists(path) else null,
		{"id": id, "n": w.get("n", id), "dmg": float(w["dmg"]), "cd": float(w["cd"]), "rng": float(w["rng"]), "arc": float(w["arc"])})

func next_weapon() -> void:
	var weap: Array = SaveBridge.data.get("weap", ["katana"])
	if weap.size() < 2: return
	var wi := (weap.find(weapon["id"]) + 1) % weap.size()
	SaveBridge.data["wi"] = wi; equip(weap[wi])
	if Lessons.me: Lessons.me.hud.toast("%s · %d dmg" % [weapon["n"], int(weapon["dmg"])], 2.0)

# 7.2's damagePlayer(): nothing hurts her while a lesson, call, choice or menu is up
func take_hit(dmg: int) -> void:
	if hurt_cd > 0 or Overlay.any(): return
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
			_wear()

# every landed hit wears a weapon down; at zero it breaks, she swaps to the next one, and (like 7.2) it saves
func _wear() -> void:
	var id: String = weapon["id"]
	if id == "kick": return
	var dur: Dictionary = SaveBridge.data.get("dur", {})
	if not dur.has(id): return
	dur[id] = float(dur[id]) - 1; SaveBridge.data["dur"] = dur
	if dur[id] <= 0:
		var weap: Array = SaveBridge.data.get("weap", [])
		weap.erase(id); dur.erase(id); SaveBridge.data["weap"] = weap
		if Lessons.me: Lessons.me.hud.toast("💥 %s broke!" % weapon["n"], 3.0, true)
		SaveBridge.data["wi"] = 0
		equip(weap[0] if weap.size() else "kick")
		SaveBridge.write()

func _unhandled_input(e: InputEvent) -> void:
	if Overlay.any(): return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_attack()
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * SENS
		pitch = clampf(pitch + e.relative.y * SENS * .85, -.5, 1.0)     # mouse down looks down
		look_t = t

func _physics_process(dt: float) -> void:
	t += dt
	attack_cd -= dt; attack_t -= dt; hurt_cd -= dt
	if Overlay.any():                         # lessons, calls, choices and menus pause her
		velocity = Vector3.ZERO
		if pose:
			if on_bike: pose.ride(t, 0.0, lean)
			else: pose.update(dt, t, false, 0.0, false, 0.0)
		_camera(dt)
		return
	var fresh := not Overlay.just_closed()    # the E / Space that closed a box isn't hers to use
	if fresh and Input.is_action_just_pressed("interact") and bike:
		if on_bike: _get_off()
		elif global_position.distance_to(bike.global_position) < BIKE_REACH: _get_on()
	if fresh and Input.is_action_just_pressed("attack"): _attack()
	if Input.is_action_just_pressed("weapon"): next_weapon()
	if on_bike:
		_ride(dt, fresh)
		return
	yaw += (Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")) * TURN * dt
	var fwd := Input.get_axis("move_back", "move_forward")
	var sp := WALK if fwd > 0 else (-BACK if fwd < 0 else 0.0)
	var st := Input.get_axis("move_left", "move_right") * STRAFE
	if dance_t > 0: sp *= .25; st *= .25
	if Input.is_action_pressed("sprint") and (sp != 0 or st != 0) and dance_t <= 0:
		sp *= SPRINT; st *= 1.34
	rotation.y = yaw
	var dir := Basis(Vector3.UP, yaw) * Vector3(st, 0, -sp)
	velocity.x = dir.x; velocity.z = dir.z
	if is_on_floor():
		if fresh and Input.is_action_just_pressed("jump"): velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	_camera(dt)
	var ground := Vector2(velocity.x, velocity.z).length()
	dance_t -= dt
	if pose:
		pose.update(dt, t, ground > .2, ground, not is_on_floor(), velocity.y)
		if dance_t > 0 and ground < .2 and is_on_floor(): pose.dance(t)
		if attack_t > 0: pose.swing(1.0 - attack_t / .28)

# 7.2's updateCam(): orbit behind her, raised and over her right shoulder so the view looks past her head;
# further back and lower over the shoulder on the bike; eased in (almost at once while the mouse is captured)
func _camera(dt: float) -> void:
	if not cam: return
	if on_bike and t - look_t > 1.3:
		yaw += wrapf(heading - yaw, -PI, PI) * minf(1.0, dt * 3.4)
	var cy := yaw + (PI if look_back else 0.0) + cam_off
	var dist := 9.4 if on_bike else 7.4
	var pit := clampf(pitch + .14, -.32, .8) if on_bike else pitch
	var hd := cos(pit) * dist
	var vd := sin(pit) * dist
	var f := Vector3(-sin(cy), 0, -cos(cy))
	var r := Vector3(cos(cy), 0, -sin(cy))
	var sh := .4 if on_bike else 1.05
	var p := global_position
	var target := p - f * hd + r * sh
	target.y = maxf(1.1, (3.9 if on_bike else 3.35) + vd + p.y)
	var k := 1.0 - pow(4e-9 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else 6e-4, dt)
	if _cam_snap: k = 1.0; _cam_snap = false
	cam.global_position = cam.global_position.lerp(target, k)
	var look := p + f * 7.0 + r * sh
	look.y = 2.45 + p.y - sin(pit) * 7.0 * .92
	cam.look_at(look, Vector3.UP)

# after a teleport (flights, respawns): put the camera straight behind her instead of sweeping across town
func snap_camera() -> void:
	_cam_snap = true

func _get_on() -> void:
	on_bike = true; bspeed = 0.0
	global_position = Vector3(bike.global_position.x, global_position.y, bike.global_position.z)
	heading = bike.rotation.y - PI                  # the bike model faces +z, she faces -z
	yaw = heading
	bike.rotation.z = 0

func _get_off() -> void:
	on_bike = false; bspeed = 0.0
	yaw = heading                                    # on foot she faces where the bike pointed
	bike.rotation.z = .13                           # parked on its stand, like 7.2
	global_position += global_transform.basis.x * 1.0   # step off to her right

func _ride(dt: float, fresh := true) -> void:
	var up := Input.is_action_pressed("move_forward")
	var dn := Input.is_action_pressed("move_back")
	var st := clampf(Input.get_axis("move_right", "move_left") + Input.get_action_strength("turn_left")
		- Input.get_action_strength("turn_right"), -1.0, 1.0)            # + = turn left (A/D or the arrows)
	var tf := clampf(1.75 - bspeed * .028, .6, 1.75)          # tighter turns when slow
	if absf(bspeed) > .5: heading += st * tf * dt * (-.6 if bspeed < 0 else 1.0)
	if up: bspeed += 15 * dt
	if dn: bspeed -= (27 if bspeed > 0 else 9) * dt
	bspeed -= (4.2 + bspeed * .11 if bspeed > 0 else -3.4) * dt
	bspeed = clampf(bspeed, -5.5, 27)
	boost_cd -= dt
	if fresh and Input.is_action_just_pressed("jump") and boost_cd <= 0 and bspeed > 1:
		bspeed = min(31.0, bspeed + 7.5); boost_cd = 1.15
	rotation.y = heading
	var f := -global_transform.basis.z
	velocity.x = f.x * bspeed; velocity.z = f.z * bspeed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if is_on_wall() and absf(bspeed) > 3.5: bspeed *= .4   # 7.2 crashes above 9 — the tumble comes later
	lean = -st * .24 * min(1.0, absf(bspeed) / 13.0)
	bike.global_position = global_position
	bike.rotation = Vector3(0, heading + PI, lean)
	for w in wheels:
		if w: w.rotation.x -= bspeed * dt * 2
	if crank: crank.rotation.x -= max(0.0, bspeed) * dt * 1.1
	_camera(dt)
	if pose: pose.ride(t, bspeed, lean)
