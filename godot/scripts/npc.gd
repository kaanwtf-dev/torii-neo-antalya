# Everyone in the city who isn't Torii: one of the two NPC bases (Kaan's NPC sheet) wearing one of its
# outfit textures. Placed and animated like 7.2's person() people: walkers loop round their square
# (updatePeds), the rest stand and idle (idlePerson) or sit (sitPerson), Kaan waves from his balcony
# when she's near (updateKaan). Pose numbers are 7.2's, through ToriiPose's joint helpers.
# Side content (batch 2): who each person is (assets/side/npc_identity.json — names and the right body for
# 7.2's women and men, STY-28), a registry so shops / quests / tutors can find "their" person and make them
# face her, a "puppet" mode for people other scripts move (chase runners, escorts, rivals), and low-poly
# stand-ins for 7.2's animal tutors (makeCat / makeGoldDog / makeDino / makeKusum / makeBanditUpright, CRT-03).
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
var greet_cd := 0.0
# 7.2's GREET, with the English underneath (TRK-17)
const GREET := ["Merhaba! 👋 (hello)", "Günaydın! 🌅 (good morning)", "Nasılsın? 🙂 (how are you?)", "İyi geceler! 🌙 (good night)", "N'aber? 😎 (what's up?)"]
static var all: Array = []          # every person, for Npc.find_near()
static var _ident := {}
var npc_name := ""
var puppet_speed := 0.0         # mode "puppet": someone else moves us; > 0 = walking/running gait

# kind: "male"/"female"; outfit: texture path; sc: 7.2's scale (kids are ~0.65)
func setup(kind: String, outfit: String, sc: float, who: Node3D) -> void:
	torii = who; scene_kind = kind
	all.append(self)
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
		"puppet":
			if puppet_speed > .3: _gait(t * (6.4 + puppet_speed * .5) + ph, minf(.85, .4 + puppet_speed * .05))
			else: _idle()
		"still": pass
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
	# walkers greet her as they pass (updatePeds) — and that's how she learns "merhaba"
	greet_cd -= dt
	if torii and greet_cd <= 0 and Lessons.me and position.distance_squared_to(torii.global_position) < 20.0:
		greet_cd = 16.0
		# a speech bubble over the walker, like 7.2 (it used to be a toast at the bottom)
		if Fx.me: Fx.me.label(global_position + Vector3(0, 2.3, 0), GREET.pick_random(), Color("ffe9fb"), 2.6, true)
		Lessons.me.teach("merhaba")

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

func _exit_tree() -> void:
	all.erase(self)

# ---- who is who (main.gd asks this for every people.json entry; i = 0-based index in the list) ----
# {kind: "male"/"female"/"" (= main's own choice), name, skip (someone else builds this one), outfit: "base"}
static func identity(i: int) -> Dictionary:
	if _ident.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/npc_identity.json"))
		_ident = j if j is Dictionary else {"-": {}}
	return _ident.get(str(i), {})

static func find_near(at: Vector3, r: float) -> Npc:
	var best: Npc = null
	var bd := r * r
	for n in all:
		if not is_instance_valid(n): continue
		var dx: float = n.global_position.x - at.x
		var dz: float = n.global_position.z - at.z
		if dx * dx + dz * dz < bd: bd = dx * dx + dz * dz; best = n
	return best

# turn to look at her (people she's talking to)
func face(p: Vector3) -> void:
	rotation.y = atan2(p.x - global_position.x, p.z - global_position.z)

# ---- 7.2's animal / creature people, PS1-style boxes with vertex colours (clean flat colours) ----
static func _box(parent: Node3D, size: Vector3, at: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; m.mesh = bm
	var mat := StandardMaterial3D.new(); mat.albedo_color = col; mat.roughness = 1
	m.material_override = mat; m.position = at; m.rotation = rot; parent.add_child(m); return m

# kind: cat (Pamuk), fatcat, cleo, golddog, banditman, dino, kusum
static func critter(kind: String) -> Node3D:
	var g := Node3D.new(); g.name = kind
	match kind:
		"cat", "fatcat", "cleo":
			var c := Color("f4f2ee") if kind == "cat" else (Color("d8a53e") if kind == "fatcat" else Color("2a2438"))
			var k := 1.0 if kind == "cat" else (1.9 if kind == "fatcat" else 1.15)
			var body := Node3D.new(); body.scale = Vector3.ONE * k; g.add_child(body)
			_box(body, Vector3(.28 * (1.4 if kind == "fatcat" else 1.0), .26, .55), Vector3(0, .3, 0), c)
			var head := _box(body, Vector3(.26, .24, .22), Vector3(0, .5, .32), c); head.name = "head"
			for s in [-1, 1]:
				_box(body, Vector3(.07, .1, .05), Vector3(.08 * s, .66, .3), c, Vector3(0, 0, .3 * s))
				_box(body, Vector3(.05, .04, .01), Vector3(.065 * s, .52, .435), Color("6fd06f") if kind != "cleo" else Color("ffd66b"))
			_box(body, Vector3(.03, .02, .01), Vector3(0, .47, .435), Color("ff9ecf"))
			var tail := Node3D.new(); tail.name = "tail"; tail.position = Vector3(0, .38, -.27); tail.rotation.x = -.8; body.add_child(tail)
			_box(tail, Vector3(.05, .05, .4), Vector3(0, 0, -.2), c)
			var legs := []
			for sx in [-1, 1]: for sz in [-1, 1]: legs.append(_box(body, Vector3(.07, .2, .07), Vector3(.09 * sx, .1, .19 * sz), c))
			g.set_meta("legs", legs)
		"golddog", "banditman":
			var c := Color("d8a650") if kind == "golddog" else Color("1a1a1f")
			var up := kind == "banditman"
			var b := Node3D.new(); g.add_child(b)
			if up: b.rotation.x = -1.35; b.position = Vector3(0, .62, -.3)
			_box(b, Vector3(.4, .42, .8), Vector3(0, .52, 0), c)
			_box(b, Vector3(.34, .32, .36), Vector3(0, .86, .5), c)
			_box(b, Vector3(.18, .14, .2), Vector3(0, .8, .74), c.lightened(.15))
			_box(b, Vector3(.08, .06, .04), Vector3(0, .84, .85), Color("141418"))
			for s in [-1, 1]: _box(b, Vector3(.08, .2, .12), Vector3(.17 * s, .92, .44), c.darkened(.2), Vector3(0, 0, .25 * s))
			if not up:
				for sx in [-1, 1]: for sz in [-1, 1]: _box(b, Vector3(.1, .42, .1), Vector3(.12 * sx, .21, .27 * sz), c)
			else:
				for sx in [-1, 1]: _box(b, Vector3(.1, .5, .1), Vector3(.13 * sx, .3, -.34), c)
			_box(b, Vector3(.05, .05, .4), Vector3(0, .66, -.5), c, Vector3(.8, 0, 0))
			_box(b, Vector3(.3, .14, .05), Vector3(0, .66, .66), Color("2f6fd0") if kind == "golddog" else Color("ff5fa2"))
		"dino":
			var gr := Color("3d9a4a")
			_box(g, Vector3(.9, 1.2, .8), Vector3(0, 1.2, 0), gr)
			_box(g, Vector3(.6, .9, .2), Vector3(0, 1.15, .4), Color("d8ecb0"))
			_box(g, Vector3(.5, .45, .7), Vector3(0, 2.05, .25), gr)
			_box(g, Vector3(.3, .32, .26), Vector3(0, 2.38, .25), Color("b02d3a"))          # the fez
			_box(g, Vector3(.3, .3, 1.2), Vector3(0, .85, -.8), gr, Vector3(-.5, 0, 0))     # tail
			for s in [-1, 1]:
				_box(g, Vector3(.3, .7, .35), Vector3(.3 * s, .35, 0), gr)
				_box(g, Vector3(.12, .4, .12), Vector3(.45 * s, 1.5, .3), gr, Vector3(-.9, 0, 0))
				_box(g, Vector3(.08, .08, .02), Vector3(.14 * s, 2.15, .61), Color("101018"))
			for i in 5: _box(g, Vector3(.08, .2, .2), Vector3(0, 2.1 - i * .3, -.35 - i * .12), Color("f0a040"))
			_box(g, Vector3(.92, .7, .82), Vector3(0, 1.3, -.02), Color("b02d3a").darkened(.1))   # waistcoat
		"kusum":
			_box(g, Vector3(.6, .04, .04), Vector3(0, 1.2, 0), Color("c8a040"))                    # brass perch
			_box(g, Vector3(.04, .3, .04), Vector3(0, 1.05, 0), Color("c8a040"))
			_box(g, Vector3(.12, .16, .12), Vector3(0, 1.32, 0), Color("5fbf3a"))
			_box(g, Vector3(.1, .1, .1), Vector3(0, 1.45, .02), Color("f2e04a"))
			_box(g, Vector3(.04, .03, .04), Vector3(0, 1.43, .08), Color("3a7fc8"))
			_box(g, Vector3(.06, .18, .04), Vector3(0, 1.2, -.08), Color("3a7fc8"), Vector3(-.4, 0, 0))
	return g

# Pamuk's walk (catAnim): the four legs trot, the tail swishes
static func critter_anim(g: Node3D, t: float, moving: bool) -> void:
	var legs: Array = g.get_meta("legs", [])
	for i in legs.size():
		legs[i].rotation.x = sin(t * 12 + (i % 2) * PI) * .6 if moving else 0.0
	var tl := g.find_child("tail", true, false)
	if tl: tl.rotation.y = sin(t * 3) * .4

# ---- one people.json entry → a person (main.gd's _people() loop body, now with who-is-who) ----
# i0 = the entry's 0-based index. Returns null for spots someone else builds (tavla opponents, Kaan at his
# tavla table — Tavla builds those). Names come up as a small neon tag over named people.
const WOMEN_NAMES := ["TEYZE", "DEFNE"]
static func from_people(world: Node3D, d: Dictionary, i0: int, who: Node3D) -> Npc:
	var idn := identity(i0)
	if idn.get("skip", false): return null
	var i := i0 + 1                         # main.gd's old 1-based counter, so outfits don't reshuffle
	var nm: String = str(idn.get("name", "")) if str(idn.get("name", "")) != "" else str(d.get("name", ""))
	var female: bool = (i % 2 == 0) and str(d.get("name", "")) == ""
	for w in WOMEN_NAMES: if nm.contains(w): female = true
	var kind := "female" if female else "male"
	if str(idn.get("kind", "")) != "": kind = str(idn["kind"])
	var outfit := "res://assets/npc/%s_%d.png" % [kind, (i * 7 + 3) % 6]
	if d.get("kind") == "kaan" or idn.get("outfit") == "base":
		if d.get("kind") == "kaan": kind = "male"
		outfit = "res://assets/npc/%s_base.png" % kind      # Kaan: the sheet's base outfit
	var n := Npc.new(); world.add_child(n)
	n.setup(kind, outfit, float(d.get("sc", 1.0)), who)
	n.npc_name = nm
	n.position = Vector3(float(d["x"]), float(d["y"]), float(d["z"])); n.rotation.y = float(d.get("ry", 0.0)); n.base_y = float(d["y"])
	if d.get("kind") == "kaan": n.mode = "kaan"
	elif d.get("kind") == "ped" and d.get("ped") is Dictionary:
		var pd: Dictionary = d["ped"]
		n.mode = "walk"; n.walk = {"cx": float(pd["cx"]), "cz": float(pd["cz"]), "t": float(pd["t"]), "sp": float(pd["sp"])}
	elif d.get("seated", false): n.sit_at(float(d["y"]), float(d.get("sc", 1.0)))
	return n

# Old Soul's mastered tutors turn green (7.2's soulPaint); also used for the tavla Kaan's tint
func tint(c: Color) -> void:
	for m in find_children("*", "MeshInstance3D", true, false):
		var mat = (m as MeshInstance3D).material_override
		if mat is StandardMaterial3D: (mat as StandardMaterial3D).albedo_color = c
