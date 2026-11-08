# Torii's poses, ported from poseTorii() in the HTML game (ALPHA 7.2) — same numbers, same feel.
#
# The HTML rig had joint groups whose rest pose was arms DOWN; this model's rest pose is a T-pose.
# So every arm gets ARMS_DOWN first, then the old rotation on top; elbows get the old rotation
# expressed in the turned-down arm's frame (conjugated). Legs, body and head rest exactly as before.
# Rotations are three.js Euler 'XYZ' (R = Rx * Ry * Rz) — same axes in Godot (y up, +z = her front).
# Signs: arm/leg x < 0 = forward/up, knee > 0 and elbow < 0 fold, body x > 0 leans forward, body y < 0
# turns her weapon side (+x arm) through. 7.2's walk/idle/ride/dance/swing are untouched; the Godot moveset
# adds the 3 combo swings and the heavy wind-up/release (+ kick versions), slam, roll tuck, block, ledge hang/climb,
# hurt flinch, cast, eat, bike tumble/lie/get-up/wobble and the mouse-pitch lean. Those are drawn ON TOP of
# update() with a blend weight (w), so they ease in and out.
class_name ToriiPose
extends RefCounted

const ARMS_DOWN := 1.28            # radians from T-pose to hanging beside the hips

var sk: Skeleton3D
var b := {}                        # bone name -> index
var ph := 0.0                      # stride phase
var _down := {}                    # side -> Quaternion turning that arm down
var body_rest := Vector3.ZERO

# down: radians from the model's rest pose to arms hanging straight (Torii: T-pose -> 1.28; the NPC
# bases rest in an A-pose, so they pass their own, measured from the rig)
func _init(skeleton: Skeleton3D, down: float = ARMS_DOWN) -> void:
	sk = skeleton
	for n in ["body", "head", "arm_m", "arm_p", "elb_m", "elb_p", "leg_m", "leg_p", "kn_m", "kn_p"]:
		b[n] = sk.find_bone(n)
	_down[-1] = Quaternion(Vector3(0, 0, 1), down)         # the right arm (-x) swings down
	_down[1] = Quaternion(Vector3(0, 0, 1), -down)         # the left arm (+x)
	body_rest = sk.get_bone_rest(b["body"]).origin

static func eul(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion(Vector3.RIGHT, x) * Quaternion(Vector3.UP, y) * Quaternion(Vector3.BACK, z)

func _side(s: int) -> String:
	return "p" if s > 0 else "m"

# ---- the same little helpers poseTorii used ----
# w < 1 blends the new pose over whatever update() already put on that bone this frame, so the action
# poses (swings, block, cast...) ease in and out of the walk/idle instead of popping
var w := 1.0
func _rq(i: int, q: Quaternion) -> void:
	if w >= .999: sk.set_bone_pose_rotation(i, q)
	elif w > .001: sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i).slerp(q, w))
func leg(s: int, x: float, z: float = 0.0) -> void:
	_rq(b["leg_" + _side(s)], eul(x, 0, z))
func knee(s: int, v: float) -> void:            # knees only fold backwards
	_rq(b["kn_" + _side(s)], eul(max(0.0, v)))
func arm(s: int, x: float, y: float = 0.0, z: float = 0.0) -> void:
	_rq(b["arm_" + _side(s)], eul(x, y, z) * _down[s])
func elbow(s: int, v: float) -> void:           # elbows only fold forwards
	var d: Quaternion = _down[s]
	_rq(b["elb_" + _side(s)], d.inverse() * eul(min(0.0, v)) * d)
func body(x: float, y: float, z: float, lift: float = 0.0) -> void:
	_rq(b["body"], eul(x, y, z))
	var to := body_rest + Vector3(0, lift, 0)
	sk.set_bone_pose_position(b["body"], to if w >= .999 else sk.get_bone_pose_position(b["body"]).lerp(to, maxf(0.0, w)))
func head(x: float, y: float = 0.0, z: float = 0.0) -> void:
	_rq(b["head"], eul(x, y, z))

# on the bike (7.2's onBike branch): crouched over the bars, pedalling, banking with the bike
func ride(t: float, bike_speed: float, lean: float) -> void:
	var p := t * maxf(3.0, absf(bike_speed) * .9)
	leg(-1, -1.25 + sin(p) * .35); leg(1, -1.25 - sin(p) * .35)
	knee(-1, 1.5 - sin(p) * .5); knee(1, 1.5 + sin(p) * .5)
	arm(-1, -.85, 0, -.12); elbow(-1, -.35)
	arm(1, -.85, 0, .12); elbow(1, -.35)
	body(.34, -lean * .5, lean * 1.25, .42 + absf(sin(p)) * .02)
	head(0, lean * .7, -lean * .45)       # head stays closer to level and looks through the corner

# dancing (7.2's dancing branch): arms up, hips swaying, braids flying
func dance(t: float) -> void:
	var d := t * 11.0
	arm(-1, -2.7 + sin(d) * .5, 0, -.4 + sin(d * .5) * .3); arm(1, -2.7 + cos(d) * .5, 0, .4 - sin(d * .5) * .3)
	leg(-1, sin(d) * .25, sin(d) * .1); leg(1, -sin(d) * .25, -sin(d) * .1)
	elbow(-1, -1.5 + sin(d) * .5); elbow(1, -1.5 + cos(d) * .5)
	knee(-1, .35 + sin(d) * .3); knee(1, .35 - sin(d) * .3)
	body(0, sin(d * .5) * .4, sin(d) * .09, absf(sin(d)) * .14)
	head(0, -sin(d * .5) * .3, sin(d * .5) * .18)

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
	w = 1.0
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

# ======== the Godot moveset (new; same rig, same helpers) ========
var spin := 0.0                    # extra turn of her whole model (spin kick) — the player applies it

# blend envelope: in over `fin`, out over the last `fout` of p (0..1)
static func env(p: float, fin := .1, fout := .3) -> float:
	return smoothstep(0.0, fin, p) * (1.0 - smoothstep(1.0 - fout, 1.0, p))

# the light combo: step 0 forehand slash, 1 rising backhand, 2 two-handed overhead finisher.
# p = 0..1 through the move; the strike itself is the fast middle part
func combo(step: int, p: float, kick := false) -> void:
	w = env(p, .1, .32); spin = 0.0
	var s := smoothstep(.26, .48, p)
	if kick: _kick(step, p, s); w = 1.0; return
	match step:
		0:
			arm(1, lerpf(-1.1, -1.45, s), 0, lerpf(-1.3, .6, s)); elbow(1, lerpf(-1.1, -.15, s))
			arm(-1, lerpf(-.3, .5, s), 0, .3); elbow(-1, -.9)
			body(lerpf(.05, .14, s), lerpf(.55, -.6, s), -.05 * s, -.04 * s); head(0, lerpf(-.2, .25, s))
			leg(-1, -.38 * s); leg(1, .3 * s); knee(-1, .35 * s); knee(1, .2)
		1:
			arm(1, lerpf(-.35, -2.5, s), 0, lerpf(.75, -.95, s)); elbow(1, lerpf(-1.4, -.2, s))
			arm(-1, lerpf(.4, -.4, s), 0, .35); elbow(-1, -1.0)
			body(lerpf(.16, -.06, s), lerpf(-.5, .5, s), .06 * s, -.03); head(0, lerpf(.2, -.2, s))
			leg(1, -.3 * s); leg(-1, .26 * s); knee(1, .3 * s); knee(-1, .22)
		_:
			arm(1, lerpf(-2.95, -.35, s), 0, lerpf(-.15, -.1, s)); elbow(1, lerpf(-1.3, -.1, s))
			arm(-1, lerpf(-2.6, -.5, s), 0, lerpf(.2, .1, s)); elbow(-1, lerpf(-1.2, -.4, s))
			body(lerpf(-.18, .5, s), lerpf(.15, -.15, s), 0, lerpf(.06, -.12, s)); head(.25 * s)
			leg(-1, -.7 * s); knee(-1, .6 * s); leg(1, .45 * s); knee(1, .5 * s)
	w = 1.0

# bare hands: front snap kick, roundhouse with the other leg, spinning finisher (7.2's kick: chamber + snap)
func _kick(step: int, p: float, s: float) -> void:
	var ch := smoothstep(0.0, .28, p)              # the knee comes up first
	arm(-1, -1.2, 0, -.3); elbow(-1, -1.8); arm(1, -1.0, 0, .3); elbow(1, -1.8)   # guard up
	match step:
		0:
			leg(1, lerpf(-.2, -1.5, ch)); knee(1, lerpf(1.7, .1, s) * ch + .05); knee(-1, .18)
			body(-.15 * ch, 0, 0); head(.1)
		1:
			leg(-1, lerpf(-.2, -1.25, ch), .6 * s); knee(-1, lerpf(1.6, .15, s) * ch + .05); knee(1, .2)
			body(-.05, .45 * s, -.28 * ch); head(0, -.2 * s)
		_:
			leg(1, lerpf(-.3, -1.4, ch), .3); knee(1, lerpf(1.5, .1, s) * ch + .05); knee(-1, .22)
			body(-.12, 0, .2 * ch); spin = s * TAU

# heavy attack. Wind-up (held: charge 0..1 makes her tremble), then the release p 0..1
func heavy_wind(t: float, a: float, charge: float, kick := false) -> void:
	w = smoothstep(0.0, 1.0, a)
	var tr := sin(t * 60.0) * .03 * charge
	if kick:                                       # bare hands: guard up, kicking knee chambered high, torso wound back
		arm(-1, -1.2, 0, -.3); elbow(-1, -1.8); arm(1, -1.0, 0, .3); elbow(1, -1.8)
		leg(1, -1.15, .35); knee(1, 1.9); leg(-1, -.08); knee(-1, .3 + charge * .2)
		body(-.2, .5, tr, -.04 - charge * .05); head(.1, -.3)
		w = 1.0; return
	arm(1, -2.9, 0, -.55); elbow(1, -1.5); arm(-1, -2.7, 0, .5); elbow(-1, -1.4)
	body(-.22, .65, tr, -.06 - charge * .07); head(-.1, -.3)
	leg(-1, -.35); leg(1, .35); knee(-1, .45 + charge * .2); knee(1, .4 + charge * .2)
	w = 1.0
func heavy_go(p: float, kick := false) -> void:
	w = 1.0 - smoothstep(.62, 1.0, p)
	var s := smoothstep(0.0, .3, p)
	if kick:                                       # the snap: a roundhouse, the leg sweeps round from her side
		arm(-1, -1.2, 0, -.3); elbow(-1, -1.8); arm(1, lerpf(-1.0, .4, s), 0, .3); elbow(1, -1.4)
		leg(1, lerpf(-1.15, -1.45, s), lerpf(.35, .05, s)); knee(1, lerpf(1.9, .1, smoothstep(0.0, .22, p)) + .05)
		leg(-1, -.05); knee(-1, .25)
		body(lerpf(-.2, -.3, s), lerpf(.5, -.55, s), -.12 * s, -.06); head(0, lerpf(-.3, .3, s))
		w = 1.0; return
	arm(1, lerpf(-2.9, -.25, s), 0, lerpf(-.55, .15, s)); elbow(1, lerpf(-1.5, -.05, s))
	arm(-1, lerpf(-2.7, -.45, s), 0, .2); elbow(-1, -.3)
	body(lerpf(-.22, .55, s), lerpf(.65, -.55, s), 0, lerpf(-.06, -.16, s)); head(.2 * s)
	leg(-1, -.8 * s); knee(-1, .8 * s); leg(1, .55 * s); knee(1, .6 * s)
	w = 1.0

# jump attack: weapon overhead and knees tucked on the way down, then a deep crouch on impact (p 0..1)
func slam_air() -> void:
	arm(1, -3.0, 0, -.2); elbow(1, -.4); arm(-1, -2.8, 0, .2); elbow(-1, -.5)
	leg(-1, -1.0); leg(1, -.6); knee(-1, 1.6); knee(1, 1.3); body(-.1, 0, 0); head(.2)
func slam_land(p: float) -> void:
	w = 1.0 - smoothstep(.45, 1.0, p)
	arm(1, -.55, 0, -.1); elbow(1, -.1); arm(-1, -.4, 0, .5); elbow(-1, -.3)
	leg(-1, -1.0); leg(1, .3); knee(-1, 1.4); knee(1, 1.5); body(.6, 0, 0, -.35); head(.3)
	w = 1.0

# dodge roll: a tight tuck — the player flips the whole model round her hips
func roll() -> void:
	leg(-1, -1.7); leg(1, -1.6); knee(-1, 2.2); knee(1, 2.1)
	arm(-1, -1.4, 0, -.2); arm(1, -1.4, 0, .2); elbow(-1, -1.9); elbow(1, -1.9)
	body(.6, 0, 0, -.2); head(.6)

# guard up (hold Z): weapon arm across the front, the other arm covering, knees soft. k = blend 0..1
func block(k: float) -> void:
	w = k
	arm(1, -1.55, 0, .95); elbow(1, -1.25); arm(-1, -1.25, 0, -.7); elbow(-1, -1.7)
	body(.12, -.15, 0, -.05); head(.1); leg(-1, -.2); leg(1, .15); knee(-1, .3); knee(1, .3)
	w = 1.0

# hanging off a ledge by both hands, then pulling herself up and over (p 0..1)
func ledge_hang(t: float) -> void:
	arm(-1, -3.0, 0, -.15); arm(1, -3.0, 0, .15); elbow(-1, -.25); elbow(1, -.25)
	leg(-1, .05 + sin(t * 3.0) * .1); leg(1, -.05 - sin(t * 3.0) * .1); knee(-1, .25); knee(1, .3)
	body(-.05, 0, 0); head(-.25)
func ledge_climb(p: float) -> void:
	var up := smoothstep(0.0, .55, p)
	var over := smoothstep(.5, 1.0, p)
	arm(-1, lerpf(-3.0, -.6, up), 0, -.2); arm(1, lerpf(-3.0, -.6, up), 0, .2)
	elbow(-1, lerpf(-.3, -1.6, up) * (1.0 - over) - .1); elbow(1, lerpf(-.3, -1.6, up) * (1.0 - over) - .1)
	leg(1, lerpf(0.0, -1.4, up) * (1.0 - over)); knee(1, lerpf(.3, 1.9, up) * (1.0 - over))
	leg(-1, .2 * up * (1.0 - over)); knee(-1, .3 + .6 * up * (1.0 - over))
	body(.35 * up * (1.0 - over * .8), 0, 0, -.1 * up * (1.0 - over)); head(.2 * up * (1.0 - over))

# a hit she didn't block: rocks back (p 0..1 through the flinch)
func flinch(p: float) -> void:
	w = 1.0 - smoothstep(.3, 1.0, p)
	body(-.32, .15, .08); head(-.35, 0, .1)
	arm(-1, -.5, 0, .5); arm(1, -.5, 0, -.5); elbow(-1, -.6); elbow(1, -.6)
	w = 1.0

# casting a skill: both hands pushed out, a little pulse (skills set the player's cast_t)
func cast(t: float, k := 1.0) -> void:
	w = k
	arm(-1, -1.75, 0, -.25); arm(1, -1.75, 0, .25); elbow(-1, -.15); elbow(1, -.15)
	body(-.08, 0, 0, .04 + sin(t * 14.0) * .02); head(-.15)
	w = 1.0

# eating: hand to mouth, chewing nods
func eat(t: float, k := 1.0) -> void:
	w = k
	arm(1, -1.9, 0, .55); elbow(1, -2.3 + sin(t * 12.0) * .15)
	head(.12 + sin(t * 12.0) * .06); body(.05, 0, 0)
	w = 1.0

# off the bike (7.2's wipe): curled up flying, flat on her front, pushing herself back up (p 0..1)
func tumble(t: float) -> void:
	roll()
	arm(-1, -2.2 + sin(t * 26.0) * .6, 0, -.9); arm(1, -2.2 + cos(t * 26.0) * .6, 0, .9)
func lie() -> void:
	leg(-1, 0, .05); leg(1, 0, -.05); knee(-1, .1); knee(1, .15)
	arm(-1, -2.9, 0, -.25); arm(1, -2.9, 0, .25); elbow(-1, -.2); elbow(1, -.2)
	body(0, 0, 0); head(-.4)
func getup(p: float) -> void:
	var q := smoothstep(.25, 1.0, p)
	leg(-1, lerpf(-1.4, 0, q)); knee(-1, lerpf(1.9, .05, q)); leg(1, lerpf(.2, 0, q)); knee(1, lerpf(2.2, .05, q))
	arm(-1, lerpf(-1.2, 0, q), 0, .1); arm(1, lerpf(-1.2, 0, q), 0, -.1); elbow(-1, lerpf(-.4, -.16, q)); elbow(1, lerpf(-.4, -.16, q))
	body(lerpf(.7, 0, q), 0, 0, lerpf(-.3, 0, q)); head(lerpf(-.3, 0, q))
# 'zor tuttun!' — arms flailing while she fights to keep the bike up (k fades it out)
func wobble(t: float, k: float) -> void:
	w = clampf(k, 0.0, 1.0)
	arm(-1, -2.2 + sin(t * 30.0) * .6, 0, -.9); arm(1, -2.2 + cos(t * 30.0) * .6, 0, .9)
	elbow(-1, -.4); elbow(1, -.4)
	w = 1.0

# 7.2: her upper body leans with the mouse pitch so aiming reads on screen (added on top of the body bone)
func aim(pitch: float) -> void:
	var i: int = b["body"]
	sk.set_bone_pose_rotation(i, eul(clampf(pitch * .3, -.18, .3)) * sk.get_bone_pose_rotation(i))

# ======== braid swing (7.2's tor.braids) ========
# Her model is one mesh, but the braids down her back are their own island of it, skinned 100% to the head.
# braid_rig() gives that island one extra bone, "braid" (a child of the head, pivot at the top of the braids;
# the weights fade from the head at the top to the braid bone at the tips), on a COPY of her mesh and skin
# (Lory is built from the same glb and keeps the originals). At rest the bone does nothing, so she looks
# exactly the same. braids() swings it on a spring from how fast the braid tips move in her head's frame:
# running trails them back, side steps / turns / bike leans swing them sideways, falling lifts them,
# stops and landings bounce. They only swing away from her back, never into it. If anything about the mesh
# isn't what we expect, there's no braid bone and nothing changes.
var _br := -1                      # the braid bone (-1: no braid swing)
var _br_tip := Vector3.ZERO        # a point near the braid tips, in the head bone's space
var _br_prev := Vector3.ZERO
var _br_has := false
var _br_a := Vector2.ZERO          # x: swing back (+ = out behind her), y: sideways (+ = towards her +x)
var _br_v := Vector2.ZERO

func braid_rig(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh as ArrayMesh
	var skin := mi.skin
	if mesh == null or skin == null or mesh.get_surface_count() != 1 or sk.find_bone("braid") >= 0: return false
	var head_b := -1
	var named := false
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == &"head": head_b = i; named = true
		elif String(skin.get_bind_name(i)) == "" and skin.get_bind_bone(i) == b["head"]: head_b = i
	if head_b < 0: return false
	var arr := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := pos.size()
	if n == 0 or idx.is_empty() or bones.size() != wts.size() or bones.size() % n != 0: return false
	var per := bones.size() / n
	# islands of the mesh: joined by triangles and by vertices that sit on the same spot (UV seams)
	var par := []; par.resize(n)
	for i in n: par[i] = i
	for k in range(0, idx.size() - 2, 3):
		_join(par, idx[k], idx[k + 1]); _join(par, idx[k + 1], idx[k + 2])
	var spot := {}
	for i in n:
		var key := Vector3i((pos[i] * 10000.0).round())
		if spot.has(key): _join(par, i, spot[key])
		else: spot[key] = i
	# the braids = the one island that is all head (by its strongest weight) and hangs well below the head
	var head_y := skin.get_bind_pose(head_b).affine_inverse().origin.y
	var isl := {}
	for i in n:
		var r := _root(par, i)
		if not isl.has(r): isl[r] = {"v": [], "head": true, "lo": INF, "hi": -INF}
		var d: Dictionary = isl[r]
		d["v"].append(i); d["lo"] = minf(d["lo"], pos[i].y); d["hi"] = maxf(d["hi"], pos[i].y)
		var best := 0
		for j in per:
			if wts[i * per + j] > wts[i * per + best]: best = j
		if bones[i * per + best] != head_b: d["head"] = false
	var found := []
	for r in isl:
		if isl[r]["head"] and isl[r]["lo"] < head_y - .2: found.append(isl[r])
	if found.size() != 1: return false
	var br: Dictionary = found[0]
	var vs: Array = br["v"]
	var top: float = br["hi"]
	var ln: float = top - br["lo"]
	if vs.size() < 40 or vs.size() > 400 or ln < .25: return false
	var zs := 0.0; var zn := 0
	for i in vs:
		if pos[i].y > top - .06:
			zs += pos[i].z; zn += 1
	var piv := Vector3(0, top, zs / maxf(1, zn))     # mesh space: the top of the braids, centred
	# the bone (rest = the pivot in the head's frame) and its bind, on copies of the skin and mesh
	var hb := skin.get_bind_pose(head_b)
	var rest := Transform3D(Basis(), hb * piv)
	var nskin: Skin = skin.duplicate()
	var bind_i := nskin.get_bind_count()
	_br = sk.add_bone("braid")
	sk.set_bone_parent(_br, b["head"]); sk.set_bone_rest(_br, rest); sk.reset_bone_pose(_br)
	if named: nskin.add_named_bind("braid", rest.affine_inverse() * hb)
	else: nskin.add_bind(_br, rest.affine_inverse() * hb)
	for i in vs:
		var f := clampf((top - pos[i].y) / ln, 0.0, 1.0)    # 0 at the top (stays on her head) .. 1 at the tips
		for j in per:
			bones[i * per + j] = 0; wts[i * per + j] = 0.0
		bones[i * per] = head_b; wts[i * per] = 1.0 - f
		bones[i * per + 1] = bind_i; wts[i * per + 1] = f
	arr[Mesh.ARRAY_BONES] = bones; arr[Mesh.ARRAY_WEIGHTS] = wts
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	nm.surface_set_material(0, mesh.surface_get_material(0)); nm.surface_set_name(0, mesh.surface_get_name(0))
	mi.skin = nskin; mi.mesh = nm
	_br_tip = rest.origin + Vector3(0, -ln * .8, 0)
	print_verbose("ToriiPose: braid bone on %d vertices, %.2f long" % [vs.size(), ln])
	return true

func _root(par: Array, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]; x = par[x]
	return x
func _join(par: Array, a: int, c: int) -> void:
	par[_root(par, a)] = _root(par, c)

# every frame, after the body pose and the model's transform are set (the player calls it from _model_xf)
func braids(dt: float, t: float) -> void:
	if _br < 0 or dt <= 0.0: return
	var hg := sk.global_transform * sk.get_bone_global_pose(b["head"])
	var tip := hg * _br_tip
	var v := (tip - _br_prev) / dt if _br_has else Vector3.ZERO
	_br_prev = tip; _br_has = true
	if v.length() > 40.0: v = Vector3.ZERO              # a teleport, not a run
	var lv := hg.basis.orthonormalized().inverse() * v  # in her head's frame: +z = where she faces, +x = her +x side
	var want := Vector2(clampf(lv.z * .075 - lv.y * .05, 0.0, .7) + sin(t * 1.3) * .03, clampf(-lv.x * .06, -.3, .3))
	var left := minf(dt, .1)
	while left > 0.0:                                   # a bouncy spring (small steps keep it stable)
		var h := minf(left, 1.0 / 120.0); left -= h
		_br_v += ((want - _br_a) * 110.0 - _br_v * 10.0) * h
		_br_a += _br_v * h
	if _br_a.x < -.02: _br_a.x = -.02; _br_v.x = maxf(0.0, _br_v.x) * .3     # her back stops them
	if _br_a.x > .75: _br_a.x = .75; _br_v.x = minf(0.0, _br_v.x)
	if absf(_br_a.y) > .35: _br_a.y = signf(_br_a.y) * .35; _br_v.y = 0.0
	sk.set_bone_pose_rotation(_br, eul(_br_a.x, 0, _br_a.y))
