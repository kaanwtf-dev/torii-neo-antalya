# Torii's poses, ported from poseTorii() in the HTML game (ALPHA 7.2) — same numbers, same feel.
#
# The HTML rig had joint groups whose rest pose was arms DOWN; this model's rest pose is a T-pose.
# So every arm gets ARMS_DOWN first, then the old rotation on top; elbows get the old rotation
# expressed in the turned-down arm's frame (conjugated). Legs, body and head rest exactly as before.
# Rotations are three.js Euler 'XYZ' (R = Rx * Ry * Rz) — same axes in Godot (y up, +z = her front).
class_name ToriiPose
extends RefCounted

const ARMS_DOWN := 1.28            # radians from T-pose to hanging beside the hips

var sk: Skeleton3D
var b := {}                        # bone name -> index
var ph := 0.0                      # stride phase
var _down := {}                    # side -> Quaternion turning that arm down
var body_rest := Vector3.ZERO

func _init(skeleton: Skeleton3D) -> void:
	sk = skeleton
	for n in ["body", "head", "arm_m", "arm_p", "elb_m", "elb_p", "leg_m", "leg_p", "kn_m", "kn_p"]:
		b[n] = sk.find_bone(n)
	_down[-1] = Quaternion(Vector3(0, 0, 1), ARMS_DOWN)    # her right arm (-x) swings down
	_down[1] = Quaternion(Vector3(0, 0, 1), -ARMS_DOWN)    # her left arm (+x)
	body_rest = sk.get_bone_rest(b["body"]).origin

static func eul(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion(Vector3.RIGHT, x) * Quaternion(Vector3.UP, y) * Quaternion(Vector3.BACK, z)

func _side(s: int) -> String:
	return "p" if s > 0 else "m"

# ---- the same little helpers poseTorii used ----
func leg(s: int, x: float, z: float = 0.0) -> void:
	sk.set_bone_pose_rotation(b["leg_" + _side(s)], eul(x, 0, z))
func knee(s: int, v: float) -> void:            # knees only fold backwards
	sk.set_bone_pose_rotation(b["kn_" + _side(s)], eul(max(0.0, v)))
func arm(s: int, x: float, y: float = 0.0, z: float = 0.0) -> void:
	sk.set_bone_pose_rotation(b["arm_" + _side(s)], eul(x, y, z) * _down[s])
func elbow(s: int, v: float) -> void:           # elbows only fold forwards
	var d: Quaternion = _down[s]
	sk.set_bone_pose_rotation(b["elb_" + _side(s)], d.inverse() * eul(min(0.0, v)) * d)
func body(x: float, y: float, z: float, lift: float = 0.0) -> void:
	sk.set_bone_pose_rotation(b["body"], eul(x, y, z))
	sk.set_bone_pose_position(b["body"], body_rest + Vector3(0, lift, 0))
func head(x: float, y: float = 0.0, z: float = 0.0) -> void:
	sk.set_bone_pose_rotation(b["head"], eul(x, y, z))

# on the bike (7.2's onBike branch): crouched over the bars, pedalling, banking with the bike
func ride(t: float, bike_speed: float, lean: float) -> void:
	var p := t * maxf(3.0, absf(bike_speed) * .9)
	leg(-1, -1.25 + sin(p) * .35); leg(1, -1.25 - sin(p) * .35)
	knee(-1, 1.5 - sin(p) * .5); knee(1, 1.5 + sin(p) * .5)
	arm(-1, -.85, 0, -.12); elbow(-1, -.35)
	arm(1, -.85, 0, .12); elbow(1, -.35)
	body(.34, -lean * .5, lean * 1.25, .42 + absf(sin(p)) * .02)
	head(0, lean * .7, -lean * .45)       # head stays closer to level and looks through the corner

# a weapon swing, on top of whatever she's doing (7.2's attack branch, non-kick): p = 0..1 through it
func swing(p: float) -> void:
	var ease := (p / .35) if p < .35 else (1.0 - (p - .35) / .65)
	arm(1, -2.6 + p * 2.4, 0, -.28)
	elbow(1, -1.35 * (1.0 - p) - .1)            # cocked back, then extends
	arm(-1, .5 * ease); elbow(-1, -.5 - .5 * ease)  # the other arm counterbalances
	knee(-1, .1 + .2 * ease); knee(1, .1 + .12 * ease)
	body(.10 * ease, -.34 * ease, 0)            # the whole torso swings through
	head(0, .2 * ease)

# moving: walking/running; spd: ground speed (m/s); air: not on the ground; vy: vertical speed
func update(dt: float, t: float, moving: bool, spd: float, air: bool, vy: float) -> void:
	spd = min(9.0, spd)
	ph += (spd * 1.15 if moving else 0.0) * dt
	var w := ph
	var run := clampf(spd / 7.3, 0.0, 1.0)
	if moving:
		var amp := .42 + run * .34
		var armamp := .34 + run * .42
		var sw := sin(w)
		leg(-1, sw * amp, .03); leg(1, -sw * amp, -.03)
		# the knee folds on the back-swing and straightens as the foot reaches forward
		knee(-1, (.16 + run * .5) * max(0.0, -sin(w - .9)) + .06)
		knee(1, (.16 + run * .5) * max(0.0, -sin(w + PI - .9)) + .06)
		arm(-1, -sw * armamp, 0, .06 + run * .1)
		elbow(-1, -.25 - run * .55 - max(0.0, sw) * (.2 + run * .5))
		arm(1, sw * armamp, 0, -.06 - run * .1)
		elbow(1, -.25 - run * .55 - max(0.0, -sw) * (.2 + run * .5))
		body(run * .13, -sw * (.10 + run * .06), sw * (.02 + run * .03), absf(sw) * (.045 + run * .05))
		head(-run * .10, sw * (.10 + run * .06))
	else:
		var br2 := sin(t * 1.5)                 # breathing
		var sh := sin(t * .42)                  # slow weight shift
		leg(-1, 0, .02 + sh * .02); leg(1, 0, -.02 + sh * .02)
		knee(-1, .05 + max(0.0, sh) * .12); knee(1, .05 + max(0.0, -sh) * .12)
		arm(-1, br2 * .045, 0, .1 + sh * .05); elbow(-1, -.16 + br2 * .05)
		arm(1, sin(t * 1.5 + 1) * .045, 0, -.1 + sh * .05); elbow(1, -.16 + sin(t * 1.5 + 1) * .05)
		body(0, sh * .07, sh * .035, br2 * .014)
		head(0, -sh * .16, sh * .05)
	# airborne — legs tuck on the way up, reach for the ground on the way down
	if air:
		var rise := clampf(vy / 7.4, -1.0, 1.0)
		leg(-1, -.55 + rise * .3); leg(1, .4 - rise * .25)
		knee(-1, .95 - rise * .25); knee(1, .3)
		arm(-1, -1.15 - rise * .55, 0, .34); elbow(-1, -.55)
		arm(1, -1.15 - rise * .55, 0, -.34); elbow(1, -.55)
		body(-rise * .14, 0, 0, 0)
