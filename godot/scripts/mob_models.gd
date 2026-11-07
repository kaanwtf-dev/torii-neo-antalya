# Monster bodies built in code, for every 7.2 kind that has no .glb (7.2's makeOkuz, makeLory, makeVergi,
# makeKapici, makeAga, makeAlien, makeDroneBird) plus the NEW Neo Antalya ones (stray cat, scooter thug,
# neon jinn). PS1 style: a few boxes / 6-sided prisms per part, flat clean colours lit per vertex, neon
# bits unshaded. People-shaped ones (Vergi, Kapıcı, Ağa, the thug, Josh) wear an NPC sheet base so they
# animate with ToriiPose like everyone else; Lory is Torii's own model with a darker tint (her dark mirror).
# Joints are named like the exported mobs (leg_0/1, arm_0/1, kn_*, el_*, head; q_0..3 for four legs).
class_name MobModels
extends RefCounted

static var _mats := {}

static func mat(c: Color, glow := false, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), glow, alpha]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new(); m.albedo_color = Color(c, alpha); m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

static func _put(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, glow := false, alpha := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat(c, glow, alpha)
	mi.position = pos; mi.rotation = rot; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box(p: Node3D, s: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = s
	return _put(p, b, pos, c, rot, glow)

static func cyl(p: Node3D, top: float, bot: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, sides := 6, glow := false) -> MeshInstance3D:
	var m := CylinderMesh.new(); m.top_radius = top; m.bottom_radius = bot; m.height = h
	m.radial_segments = sides; m.rings = 1
	return _put(p, m, pos, c, rot, glow)

static func ball(p: Node3D, r: float, pos: Vector3, c: Color, glow := false, alpha := 1.0) -> MeshInstance3D:
	var m := SphereMesh.new(); m.radius = r; m.height = r * 2.0; m.radial_segments = 7; m.rings = 4
	return _put(p, m, pos, c, Vector3.ZERO, glow, alpha)

static func joint(p: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new(); j.name = n; j.position = pos; p.add_child(j)
	return j

# ---------------------------------------------------------------- the kinds
static func build(kind: String) -> Node3D:
	match kind:
		"okuz": return okuz()
		"cat": return cat()
		"jinn": return jinn()
		"lory": return lory()
		"vergi": return vergi()
		"kapici": return kapici()
		"aga": return aga()
		"thug": return thug()
		"alien": return alien()
		"drone": return drone()
		"josh": return josh()
	return null

# 7.2 makeOkuz: the ox. Brown hide (lighter than 7.2's so it reads at night), cream horns, red eyes, gold nose ring
static func okuz() -> Node3D:
	var g := Node3D.new()
	var hide := Color("7a5038"); var dark := Color("553624")
	box(g, Vector3(1.1, .95, 2.0), Vector3(0, 1.3, -.1), hide)
	box(g, Vector3(.95, .55, .8), Vector3(0, 1.8, .45), dark)
	cyl(g, .04, .03, .8, Vector3(0, 1.45, -1.25), dark, Vector3(.4, 0, 0), 4)
	var hd := joint(g, "head", Vector3(0, 1.4, 1.15))
	box(hd, Vector3(.62, .56, .72), Vector3(0, 0, .12), hide)
	box(hd, Vector3(.5, .34, .26), Vector3(0, -.15, .5), Color("9a7a66"))
	for s in [-1, 1]:
		cyl(hd, .03, .08, .5, Vector3(.4 * s, .26, .05), Color("f2ead8"), Vector3(0, 0, -1.2 * s), 5)
		cyl(hd, .0, .035, .25, Vector3(.66 * s, .42, .05), Color("fff6e0"), Vector3(0, 0, -.4 * s), 5)
		box(hd, Vector3(.07, .07, .04), Vector3(.2 * s, .12, .47), Color("ff3b2d"), Vector3.ZERO, true)
	cyl(hd, .09, .09, .03, Vector3(0, -.28, .62), Color("ffc83a"), Vector3(PI / 2, 0, 0), 6, true)
	var i := 0
	for sx in [-1, 1]:
		for sz in [.72, -.8]:
			var lg := joint(g, "q_%d" % i, Vector3(.36 * sx, 1.0, sz)); i += 1
			box(lg, Vector3(.26, .9, .28), Vector3(0, -.45, 0), hide)
			box(lg, Vector3(.28, .14, .32), Vector3(0, -.92, .02), Color("2a1e18"))
	return g

# NEW: a stray cat of Neo Antalya (the swarm). Orange, grey, cream or calico — all clean flat colours
static func cat() -> Node3D:
	var g := Node3D.new()
	var cols := [Color("e8913a"), Color("9a9aa8"), Color("e8d8b8"), Color("f2f0ea")]
	var c: Color = cols.pick_random()
	var patch := Color("c86a2a") if c != cols[0] else Color("f2d0a0")
	box(g, Vector3(.32, .28, .62), Vector3(0, .42, 0), c)
	box(g, Vector3(.2, .05, .3), Vector3(0, .565, -.05), patch)
	var hd := joint(g, "head", Vector3(0, .6, .36))
	box(hd, Vector3(.3, .26, .26), Vector3.ZERO, c)
	box(hd, Vector3(.14, .1, .06), Vector3(0, -.06, .14), Color("fff2ea"))
	for s in [-1, 1]:
		var e := PrismMesh.new(); e.size = Vector3(.11, .13, .05)
		_put(hd, e, Vector3(.09 * s, .18, -.02), c)
		box(hd, Vector3(.06, .05, .02), Vector3(.075 * s, .04, .135), Color("c8ff5a"), Vector3.ZERO, true)
	var tl := joint(g, "tail", Vector3(0, .5, -.3))
	box(tl, Vector3(.06, .06, .42), Vector3(0, .12, -.17), c, Vector3(-.7, 0, 0))
	var i := 0
	for sx in [-1, 1]:
		for sz in [.2, -.22]:
			var lg := joint(g, "q_%d" % i, Vector3(.1 * sx, .3, sz)); i += 1
			box(lg, Vector3(.08, .3, .08), Vector3(0, -.15, 0), c)
	return g

# NEW: Neon Cin — a jinn out of a shisha lamp. Floats on a smoke tail, cyan skin, purple vest, gold bangles
static func jinn() -> Node3D:
	var g := Node3D.new()
	var skin := Color("4fb8ff"); var gold := Color("ffd66b")
	cyl(g, .0, .2, .9, Vector3(0, .55, 0), Color("7bf7ff"), Vector3(PI, 0, 0), 6, true)
	cyl(g, .44, .2, 1.0, Vector3(0, 1.45, 0), skin)
	box(g, Vector3(.7, .5, .5), Vector3(0, 1.65, 0), Color("b06bff"))
	cyl(g, .3, .3, .12, Vector3(0, 1.08, 0), gold, Vector3.ZERO, 6, true)
	var hd := joint(g, "head", Vector3(0, 2.05, 0))
	ball(hd, .26, Vector3(0, .05, 0), skin)
	cyl(hd, .02, .1, .32, Vector3(0, .38, -.04), Color("ff5fa2"), Vector3(-.3, 0, 0), 5)
	for s in [-1, 1]:
		box(hd, Vector3(.07, .04, .03), Vector3(.1 * s, .08, .23), Color("fffbe0"), Vector3.ZERO, true)
		ball(hd, .05, Vector3(.26 * s, -.05, 0), gold, true)
	box(hd, Vector3(.12, .14, .08), Vector3(0, -.2, .18), Color("2a4a9a"))
	for s in [0, 1]:
		var sx := -1.0 if s == 0 else 1.0
		var a := joint(g, "arm_%d" % s, Vector3(.48 * sx, 1.8, 0))
		var el := joint(a, "el_%d" % s, Vector3(0, -.34, 0))
		box(a, Vector3(.15, .36, .15), Vector3(0, -.17, 0), skin)
		box(el, Vector3(.13, .32, .13), Vector3(0, -.16, 0), skin)
		cyl(el, .1, .1, .06, Vector3(0, -.26, 0), gold, Vector3.ZERO, 6, true)
	ball(g, 1.1, Vector3(0, 1.45, 0), Color("7bf7ff"), true, .08)
	return g

# ---------------------------------------------------------------- people-shaped (NPC sheet bases)
# base "male"/"female", the outfit texture, 7.2's scale. The ToriiPose rides along as meta "pose".
static func person(base: String, outfit: String, sc: float) -> Node3D:
	var info: Array = Npc.BASES[base]
	if not Npc._scenes.has(base): Npc._scenes[base] = load(info[0])
	var model: Node3D = Npc._scenes[base].instantiate()
	model.scale = Vector3.ONE * sc * Npc.PERSON_H / float(info[1])
	var tex: Texture2D = load(outfit) if ResourceLoader.exists(outfit) else null
	var sk: Skeleton3D
	for n in model.find_children("*", "", true, false):
		if n is MeshInstance3D:
			var m := StandardMaterial3D.new(); m.roughness = 1
			if tex: m.albedo_texture = tex; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			n.material_override = m
		elif n is Skeleton3D: sk = n
	if sk:
		var sh := sk.get_bone_global_rest(sk.find_bone("arm_p")).origin
		var el := sk.get_bone_global_rest(sk.find_bone("elb_p")).origin
		model.set_meta("pose", ToriiPose.new(sk, atan2(el.x - sh.x, sh.y - el.y)))
		model.set_meta("sk", sk)
	return model

# something worn on a bone (hat on the head, briefcase in the hand), in that bone's own frame
static func on_bone(model: Node3D, bone: String) -> Node3D:
	var sk: Skeleton3D = model.get_meta("sk") if model.has_meta("sk") else null
	var holder := Node3D.new()
	if not sk or sk.find_bone(bone) < 0:
		model.add_child(holder); return holder
	var ba := BoneAttachment3D.new(); ba.bone_name = bone; sk.add_child(ba); ba.add_child(holder)
	return holder

# 7.2 makeVergi: the tax inspector. Suit, green neon visor, a briefcase full of your money
static func vergi() -> Node3D:
	var g := person("male", "res://assets/npc/male_1.png", 1.15)
	box(on_bone(g, "head"), Vector3(.26, .05, .05), Vector3(0, .17, .14), Color("3dff9e"), Vector3.ZERO, true)
	var h := on_bone(g, "elb_p")
	box(h, Vector3(.42, .32, .12), Vector3(0, -.42, 0), Color("6a4628"))
	box(h, Vector3(.12, .05, .04), Vector3(0, -.24, 0), Color("ffd66b"))
	return g

# 7.2 makeKapici: the doorman. Grey stubble, a sack of everyone's bread on his back, a broom
static func kapici() -> Node3D:
	var g := person("male", "res://assets/npc/male_2.png", 1.25)
	box(on_bone(g, "body"), Vector3(.62, .7, .4), Vector3(0, .45, -.32), Color("b8ab8a"))
	var h := on_bone(g, "elb_m")
	cyl(h, .03, .03, 1.5, Vector3(0, -.3, 0), Color("a07a44"), Vector3.ZERO, 5)
	box(h, Vector3(.28, .24, .12), Vector3(0, -1.08, 0), Color("e8dcb8"))
	return g

# 7.2 makeAga: the Black Market Boss. Red fez, three gold chains, a cash case
static func aga() -> Node3D:
	var g := person("male", "res://assets/npc/male_0.png", 1.2)
	cyl(on_bone(g, "head"), .1, .13, .2, Vector3(0, .36, 0), Color("c8304a"))
	var b := on_bone(g, "body")
	for i in 3:
		var t := TorusMesh.new(); t.inner_radius = .17 - i * .03; t.outer_radius = .2 - i * .03; t.rings = 10; t.ring_segments = 4
		_put(b, t, Vector3(0, .5 - i * .1, .1), Color("ffc83a"), Vector3(PI / 2.4, 0, 0), true)
	box(on_bone(g, "elb_p"), Vector3(.5, .36, .14), Vector3(0, -.42, 0), Color("4a3020"))
	return g

# NEW: a scooter gang thug — pink neon helmet, throws bottles (the lobber)
static func thug() -> Node3D:
	var g := person("male", "res://assets/npc/male_4.png", 1.0)
	var hd := on_bone(g, "head")
	ball(hd, .2, Vector3(0, .2, 0), Color("ff5fa2"))
	box(hd, Vector3(.3, .08, .05), Vector3(0, .16, .17), Color("7bf7ff"), Vector3.ZERO, true)
	cyl(on_bone(g, "elb_p"), .04, .06, .3, Vector3(0, -.4, 0), Color("5fff9e"), Vector3.ZERO, 5, true)
	return g

# 7.2 makeLory: Torii's dark mirror — her own model, darker, red-pink aura. Moves like her (that's the point)
static func lory() -> Node3D:
	var scn: PackedScene = load("res://assets/torii/torii.glb")
	var model: Node3D = scn.instantiate()
	var tint := Color(.62, .44, .6)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				var c: BaseMaterial3D = m.duplicate(); c.albedo_color = c.albedo_color * tint
				c.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				mi.set_surface_override_material(i, c)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size():
		var sk: Skeleton3D = sks[0]
		model.set_meta("pose", ToriiPose.new(sk)); model.set_meta("sk", sk)
	ball(model, 1.3, Vector3(0, 1.3, 0), Color("ff2d78"), true, .1)
	return model

# ---------------------------------------------------------------- Josh's squad (allies, 7.2 makeAlien / makeDroneBird)
static func alien() -> Node3D:
	var g := Node3D.new(); var skin := Color("7fd96f")
	cyl(g, .22, .3, .85, Vector3(0, .75, 0), skin, Vector3.ZERO, 7)
	var hd := joint(g, "head", Vector3(0, 1.55, 0))
	var b := ball(hd, .42, Vector3.ZERO, skin); b.scale = Vector3(1, 1.25, .9)
	for s in [-1, 1]:
		var e := ball(hd, .13, Vector3(.17 * s, .05, .33), Color("1a1a24")); e.scale = Vector3(.7, 1.3, .5)
	for s in [0, 1]:
		var sx := -1.0 if s == 0 else 1.0
		var a := joint(g, "arm_%d" % s, Vector3(.3 * sx, 1.1, 0)); box(a, Vector3(.09, .55, .09), Vector3(0, -.27, 0), skin)
		var l := joint(g, "leg_%d" % s, Vector3(.12 * sx, .4, 0)); box(l, Vector3(.11, .4, .11), Vector3(0, -.2, 0), skin)
	ball(g, .9, Vector3(0, 1, 0), Color("7fff9e"), true, .14)
	return g

static func drone() -> Node3D:
	var g := Node3D.new()
	box(g, Vector3(.5, .3, .75), Vector3(0, 1.5, 0), Color("6a7588"))
	var hd := joint(g, "head", Vector3(0, 1.6, .48))
	box(hd, Vector3(.3, .26, .3), Vector3.ZERO, Color("56627a"))
	cyl(hd, 0, .09, .28, Vector3(0, -.03, .24), Color("ffa53e"), Vector3(PI / 2, 0, 0), 4)
	box(hd, Vector3(.08, .08, .04), Vector3(0, .06, .15), Color("ff3b3b"), Vector3.ZERO, true)
	for s in [0, 1]:
		var sx := -1.0 if s == 0 else 1.0
		var w := joint(g, "arm_%d" % s, Vector3(.25 * sx, 1.58, 0))
		box(w, Vector3(.85, .06, .4), Vector3(.4 * sx, 0, 0), Color("a8b2c8"))
	return g

# Josh (7.2 joshBody): the conspiracy guy — green beanie, tinfoil-silver visor, a joint glowing in his hand
static func josh() -> Node3D:
	var g := person("male", "res://assets/npc/male_3.png", 1.0)
	var hd := on_bone(g, "head")
	cyl(hd, .15, .19, .16, Vector3(0, .26, 0), Color("4f8a3a"))
	box(hd, Vector3(.3, .05, .05), Vector3(0, .17, .17), Color("d8dce8"), Vector3.ZERO, true)
	box(on_bone(g, "elb_p"), Vector3(.03, .03, .14), Vector3(0, -.36, .06), Color("ffb03a"), Vector3.ZERO, true)
	return g
