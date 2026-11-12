# Every monster and boss. 7.2's ENEMY table (assets/missions/missions.json "enemies"), spawnEnemy,
# mobLevel / lvTag, hitEnemy, killEnemy and updateEnemies — rebuilt as a PS1 action game's monsters
# (think Medievil / Tenchu): each kind has an archetype with its own moves, and every attack has a TELL —
# a wind-up pose, an orange blink, "!" for heavy ones, "⚠" or a red circle on the ground for ones you
# must roll out of — so she can roll, block or parry. Hits flinch them, heavy hits / broken poise stagger
# them, a parry dazes them. They walk on the real city (move_and_slide), keep out of each other's way,
# talk Turkish (MOBTALK), and die with a fall, a sink and a burst.
#   archetypes: skirm (fast, circles in and darts), brute (slow, armoured wind-ups, overhead slams),
#   archer / caster / lobber (keep their distance, shoot, curse circles, arcing bottles), charger (paws the
#   ground then charges in a line, dazed if it hits a wall), ghost (floats, phases out), swarm (cats).
#   Bosses keep set_phases (7.2's PHASE: caster, charger, enrage, summon) and add slams with a ring tell,
#   Karen's summons and an enrage at 30% HP.
# NEW kinds (not in 7.2): cat (stray-cat swarm), thug (scooter gang lobber), jinn (neon cin caster).
class_name Enemy
extends CharacterBody3D

signal died(e)

static var DATA := {}
const NEW_STATS := {   # NEW kinds: 7.2-style stat rows
	"cat": {"hp": 14, "sp": 6.6, "dmg": 4, "xp": 5, "snd": "meow", "name": "Sokak Kedisi"},
	"thug": {"hp": 55, "sp": 4.2, "dmg": 11, "xp": 24, "snd": "honk", "name": "Scooter Thug"},
	"jinn": {"hp": 80, "sp": 3.0, "dmg": 14, "xp": 40, "snd": "woosh2", "name": "Neon Cin", "ghost": true},
}
# kind -> archetype, attack list, gait, Lv tag height (7.2 MOBH), body radius
const KIND := {
	"imp": {"arch": "skirm", "atk": ["jab", "pounce"], "gait": "hop", "h": 1.75, "r": .35},
	"thot": {"arch": "skirm", "atk": ["jab", "swipe"], "gait": "strut", "h": 2.35, "r": .38},
	"scorpion": {"arch": "skirm", "atk": ["sting", "jab"], "gait": "skitter", "h": 1.35, "r": .5},
	"zombie": {"arch": "brute", "atk": ["bite", "swipe"], "gait": "shamble", "h": 2.35, "r": .4},
	"mummy": {"arch": "brute", "atk": ["swipe", "slam"], "gait": "shamble", "h": 2.5, "r": .42},
	"skeleton": {"arch": "archer", "atk": ["arrow", "shove"], "gait": "rattle", "h": 2.35, "r": .38},
	"witch": {"arch": "caster", "atk": ["hex", "curse"], "gait": "hover", "h": 2.95, "r": .4},
	"ghost": {"arch": "ghost", "atk": ["drain"], "gait": "float", "h": 2.25, "r": .4},
	"spirit": {"arch": "ghost", "atk": ["drain"], "gait": "float", "h": 2.25, "r": .4},
	"wisp": {"arch": "ghost", "atk": ["drain"], "gait": "float", "h": 2.05, "r": .4},
	"okuz": {"arch": "charger", "atk": ["gore"], "gait": "quad", "h": 2.75, "r": .75},
	"driver": {"arch": "charger", "atk": ["gore"], "gait": "car", "h": 3.25, "r": 1.0},
	"cruze": {"arch": "charger", "atk": ["gore", "bslam"], "gait": "car", "h": 2.4, "r": 1.0},
	"karen": {"arch": "brute", "atk": ["swipe", "slam", "hex"], "gait": "walk", "h": 2.4, "r": .42},
	"aga": {"arch": "brute", "atk": ["swipe", "bslam", "lob"], "gait": "walk", "h": 2.7, "r": .45},
	"lory": {"arch": "skirm", "atk": ["jab", "swipe", "slam"], "gait": "lory", "h": 2.55, "r": .36},
	"vergi": {"arch": "skirm", "atk": ["swipe", "jab", "lob"], "gait": "walk", "h": 2.7, "r": .42},
	"kapici": {"arch": "brute", "atk": ["swipe", "slam"], "gait": "walk", "h": 2.7, "r": .45},
	"cat": {"arch": "swarm", "atk": ["pounce"], "gait": "cat", "h": .95, "r": .28},
	"thug": {"arch": "lobber", "atk": ["lob", "jab"], "gait": "walk", "h": 2.4, "r": .4},
	"jinn": {"arch": "caster", "atk": ["orb3", "curse"], "gait": "float", "h": 2.6, "r": .45},
}
const ARCH := {
	"skirm": {"poise": 10.0, "orbit": 3.4, "turn": 10.0},
	"brute": {"poise": 40.0, "armor": true, "turn": 5.0},
	"archer": {"poise": 8.0, "kite": Vector2(11, 15), "turn": 8.0},
	"caster": {"poise": 8.0, "kite": Vector2(11, 15), "turn": 8.0},
	"lobber": {"poise": 12.0, "kite": Vector2(8, 13), "turn": 8.0},
	"charger": {"poise": 50.0, "armor": true, "turn": 4.0},
	"ghost": {"poise": 14.0, "turn": 6.0},
	"swarm": {"poise": 0.0, "orbit": 2.6, "turn": 12.0},
}
# rng: starts from this far; wind: tell time; act: active frames; rec: recovery (the window to punish);
# mult: x its damage; reach/arc: the hit; lunge: forward m/s while striking; kind: what her block sees
const ATK := {
	"jab": {"rng": 2.0, "wind": .34, "act": .12, "rec": .45, "mult": .8, "reach": 2.1, "arc": 1.3, "lunge": 6.0, "pose": "jab", "cd": 1.1},
	"swipe": {"rng": 2.2, "wind": .5, "act": .16, "rec": .6, "mult": 1.0, "reach": 2.4, "arc": 1.8, "lunge": 3.0, "pose": "swipe", "cd": 1.4},
	"slam": {"rng": 2.5, "wind": .85, "act": .16, "rec": 1.0, "mult": 1.6, "reach": 2.8, "arc": 1.4, "lunge": 2.5, "pose": "slam", "cd": 3.2, "kind": "heavy", "tell": "!", "kb": 7.0},
	"bite": {"rng": 3.4, "wind": .55, "act": .28, "rec": .8, "mult": 1.1, "reach": 1.9, "arc": 1.1, "lunge": 9.0, "pose": "lunge", "cd": 2.0},
	"pounce": {"rng": 4.0, "wind": .3, "act": .32, "rec": .55, "mult": .75, "reach": 1.6, "arc": 1.3, "lunge": 11.0, "pose": "pounce", "cd": 1.6, "hop": 5.0},
	"sting": {"rng": 2.3, "wind": .45, "act": .12, "rec": .55, "mult": 1.0, "reach": 2.5, "arc": 1.1, "lunge": 4.0, "pose": "sting", "cd": 1.8, "status": "poison"},
	"shove": {"rng": 2.0, "wind": .35, "act": .12, "rec": .5, "mult": .6, "reach": 2.1, "arc": 1.4, "lunge": 2.0, "pose": "jab", "cd": 1.6, "kb": 6.0},
	"gore": {"rng": 2.8, "wind": .5, "act": .18, "rec": .8, "mult": 1.2, "reach": 2.9, "arc": 1.3, "lunge": 4.0, "pose": "toss", "cd": 2.2, "kb": 9.0, "kind": "heavy"},
	"drain": {"rng": 4.5, "wind": .6, "act": .5, "rec": .7, "mult": 1.0, "reach": 1.7, "arc": 1.5, "lunge": 8.0, "pose": "drain", "cd": 2.4},
	"arrow": {"rng": 40.0, "min": 3.0, "wind": .6, "rec": .5, "mult": 1.0, "pose": "bow", "cd": 2.1, "shot": "arrow"},
	"hex": {"rng": 40.0, "min": 3.0, "wind": .55, "rec": .5, "mult": 1.0, "pose": "cast", "cd": 2.8, "shot": "hex"},
	"orb3": {"rng": 30.0, "min": 3.0, "wind": .6, "rec": .6, "mult": .7, "pose": "cast", "cd": 3.2, "shot": "orb3"},
	"lob": {"rng": 18.0, "min": 4.0, "wind": .55, "rec": .5, "mult": 1.1, "pose": "throw", "cd": 2.6, "shot": "lob"},
	"curse": {"rng": 22.0, "min": 0.0, "wind": .4, "rec": .6, "mult": 1.3, "pose": "cast", "cd": 7.0, "shot": "curse"},
	"bslam": {"rng": 4.5, "wind": 1.1, "act": .15, "rec": 1.2, "mult": 1.8, "pose": "slam", "cd": 6.0, "shot": "bslam", "tell": "⚠"},
}
# 7.2 MOBTALK (Turkish + English gloss) — and lines for the ones 7.2 had none for
const TALK := {
	"imp": [["Yakala!", "Catch her!"], ["Küçük!", "Little one!"], ["Hızlı!", "Fast!"], ["Gel buraya!", "Come here!"], ["Seni buldum!", "I found you!"]],
	"okuz": [["Çekil önümden!", "Get out of my way!"], ["Ben geçerim!", "I go first!"], ["Sıra mı var?", "Is there a queue?"], ["Kaba mıyım? Kabayım!", "Am I rude? I am rude!"], ["Bana ne!", "What do I care!"], ["Öff!", "Ugh!"], ["Sen kimsin?", "Who even are you?"], ["Bastım gaza!", "I hit the gas!"], ["Özür dilemem!", "I will not apologise!"], ["Hoşça kal demem!", "I do not say goodbye!"]],
	"zombie": [["Açım!", "I am hungry!"], ["Beyin...", "Brain..."], ["Mesai!", "Overtime!"], ["Toplantı!", "Meeting!"], ["Yorgunum", "I am tired"], ["Work... work...", ""]],
	"thot": [["Kim bu?", "Who is this?"], ["Çirkin!", "Ugly!"], ["Bana bak!", "Look at me!"], ["Whatever!", ""], ["Benim!", "Mine!"]],
	"ghost": [["Soğuk...", "Cold..."], ["Gel bana", "Come to me"], ["Buradayım", "I am here"], ["Korkuyor musun?", "Are you scared?"]],
	"witch": [["Lanet olsun!", "Curse you!"], ["Büyü!", "Magic!"], ["Kızım!", "My girl!"], ["Nazar değsin!", "May the evil eye strike!"]],
	"skeleton": [["Kemik!", "Bone!"], ["Ok!", "Arrow!"], ["Ölüm...", "Death..."], ["Nişan al", "Take aim"]],
	"mummy": [["Bin yıl...", "A thousand years..."], ["Uyandım", "I woke up"], ["Yavaş...", "Slow..."], ["Çok eski", "Very old"]],
	"driver": [["Korna!", "Horn!"], ["Sinyal versene!", "Use your signal!"], ["Dikkat et!", "Watch out!"], ["Öğrenci sürücü!", "Student driver!"]],
	"cruze": [["Yıkanmadım", "I was not washed"], ["İki bin on yedi!", "Two thousand seventeen!"], ["Koku!", "Smell!"]],
	"karen": [["Müdürü çağır!", "Call the manager!"], ["Son e-postama göre", "Per my last email"], ["Kovuldun!", "You are fired!"], ["Fazla mesai!", "Overtime!"]],
	"spirit": [["Ata...", "Ancestor..."], ["Hatırla", "Remember"], ["Maske", "Mask"]],
	"scorpion": [["Sok!", "Sting!"], ["Kum!", "Sand!"], ["Zehir", "Venom"]],
	"wisp": [["Geçmiş...", "The past..."], ["Anı", "Memory"], ["Kal benimle", "Stay with me"]],
	"lory": [["Ben senim.", "I am you."], ["Daha iyiyim!", "I am better!"], ["Aynaya bak!", "Look in the mirror!"]],
	"vergi": [["Vergi ver!", "Pay your tax!"], ["Fatura!", "Invoice!"], ["Ceza!", "Fine!"]],
	"kapici": [["Ekmek aldın mı?", "Did you buy bread?"], ["Çöp!", "Rubbish!"], ["Kapı kapalı!", "The door is closed!"]],
	"aga": [["Paramı ver!", "Give me my money!"], ["Burası benim çarşım!", "This is my bazaar!"], ["Pazarlık yok!", "No haggling!"]],
	"cat": [["Miyav!", "Meow!"], ["Mama ver!", "Give me food!"], ["Hıhh!", "Hiss!"]],
	"thug": [["Kaç!", "Run!"], ["Yol ver!", "Make way!"], ["Bu sokak bizim!", "This street is ours!"]],
	"jinn": [["Dilek tut!", "Make a wish!"], ["Lamba benim!", "The lamp is mine!"], ["Üç dilek...", "Three wishes..."]],
}
const LAYER := 4                 # physics layer 3: monsters (they collide with the city = layer 1 only)
const GRAV := 22.0

static var _scenes := {}
static var _red: StandardMaterial3D
static var _tell: StandardMaterial3D
static var _tell_red: StandardMaterial3D
static var _shadow_mesh: PlaneMesh
static var _tokens := 0          # how many monsters may be winding up a melee hit at once (fair fights)
static var _striker: Enemy = null
static var _last_res := {}
static var _cb_hit: Callable
static var _cb_atk: Callable
static var _voice_ms := -10000
static var voice_on := true      # the V key owner can switch monster voices off
static var _plate_root: Control

var type := "imp"
var kind := "imp"
var hp := 20.0
var max_hp := 20.0
var sp := 5.0
var dmg := 6
var xp := 8
var level := 1
var flags := {}
var phases: Array = []
var elite := false
var guard := false               # chest duels: this one fights Bandit instead of her
var torii: CharacterBody3D
var radius := .4
var aggro := 30.0
var arch := "skirm"
var info := {}
var attacks: Array = []
var floater := false
var snd := "chitter"
var mname := "Imp"
var tag_h := 2.3
# rig
var vis: Node3D
var model: Node3D
var pose: ToriiPose
var legs: Array = []
var arms: Array = []
var knees: Array = []
var elbows: Array = []
var quads: Array = []
var head: Node3D
var tail: Node3D
var crown: MeshInstance3D
var base_scale := 1.0
var _meshes: Array = []
var _overlay: Material = null    # what the model wears normally (gold for elites)
var _cur_ov: Material = null
# brain
var state := "idle"
var st_t := 0.0
var st_len := 1.0
var atk := {}
var atk_id := ""
var atk_hit := false
var cds := {}
var gcd := 0.0
var poise := 10.0
var poise_max := 10.0
var poise_t := 0.0
var hitstop := 0.0
var last_src := ""                                     # who landed the last hit ("" = Torii; bandit / ally / dot) — Fx only freezes time for hers
var flash_t := 0.0
var kb := Vector3.ZERO
var status := {}
var _dot_t := 0.0
var noticed := false
var home := Vector3.ZERO
var _wander_to := Vector3.ZERO
var _wander_t := 0.0
var _stuck_t := 0.0
var _stuck_p := Vector3.ZERO
var _ground_t := 0.0
var _ground_y := 0.0
var _snap := true
var t := 0.0
var gp := 0.0
var ph := 0.0
var orbit_dir := 1.0
var dodge_cd := 0.0
var talk_cd := 0.0
var ch_dir := Vector3.ZERO
var ch_cd := 2.0
var sum_t := 5.0
var enraged := false
var phase_t := 0.0
var phase_cd := 6.0
var _q66 := false
var _q33 := false
var _tok := false
var dead_t := 0.0
var fall_dir := 1.0
# plate (Lv tag + HP bar), drawn crisp at window resolution like Fx labels
var plate: Control
var plate_lab: Label
var plate_bar: ColorRect

# ---------------------------------------------------------------- spawn (missions.gd uses this signature)
# opts (all optional): lv (force a level), night (tougher), roam (the spawner's own), guard
static func spawn(parent: Node, kind_: String, at: Vector3, target: CharacterBody3D, is_elite := false, opts := {}) -> Enemy:
	_load_data()
	var e := Enemy.new(); parent.add_child(e); e.add_to_group("enemies")
	e.position = at; e.setup(kind_, target, is_elite, opts)
	return e

static func _load_data() -> void:
	if not DATA.is_empty(): return
	DATA = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["enemies"]
	for k in NEW_STATS: if not DATA.has(k): DATA[k] = NEW_STATS[k]

func setup(kind_: String, target: CharacterBody3D, is_elite: bool, opts := {}) -> void:
	_hook_bus()
	type = kind_ if DATA.has(kind_) else "imp"; kind = type; torii = target; elite = is_elite
	guard = bool(opts.get("guard", false))
	if opts.get("roam", false): set_meta("roam", true)
	var s: Dictionary = DATA[type]
	info = KIND.get(type, KIND["imp"]); arch = info["arch"]; attacks = (info["atk"] as Array).duplicate()
	for f in ["caster", "archer", "ghost", "boss", "charger", "mini", "steals", "sum", "rare"]:
		if s.get(f, false): flags[f] = true
	floater = flags.has("ghost")
	if flags.has("boss") and not attacks.has("bslam"): attacks.append("bslam")   # every boss gets the ring slam
	snd = str(s.get("snd", "chitter")); mname = str(s.get("name", type))
	var night := bool(opts.get("night", Spawner.me != null and Spawner.me.night))
	# 7.2 spawnEnemy: her level sets theirs — +11% HP and +8% damage per level; above her pays more XP
	level = mob_level(s, at_pos(), elite, opts.merged({"night": night}))
	var her := maxi(1, SaveBridge.get_i("lvl", 1))
	var hpm := 1.0 + .11 * (level - 1); var dmm := 1.0 + .08 * (level - 1)
	var xpm := clampf(1.0 + .12 * (level - her), .5, 2.0)
	max_hp = roundf(float(s["hp"]) * (3.0 if elite else 1.0) * hpm * (1.1 if night else 1.0)); hp = max_hp
	dmg = int(round(float(s["dmg"]) * (1.7 if elite else 1.0) * dmm * (1.15 if night else 1.0)))
	xp = int(round(float(s["xp"]) * (4.0 if elite else 1.0) * xpm))
	sp = float(s["sp"]) * randf_range(.85, 1.15)
	aggro = (70.0 if flags.has("boss") else (42.0 if arch in ["archer", "caster", "lobber"] else 30.0)) + (6.0 if night else 0.0)
	var A: Dictionary = ARCH[arch]
	poise_max = float(A.get("poise", 10.0)) * (2.0 if flags.has("mini") else 1.0) * (1.5 if elite else 1.0); poise = poise_max
	radius = float(info["r"]); tag_h = float(info["h"])
	ph = randf() * TAU; t = randf() * 10.0; orbit_dir = 1.0 if randf() < .5 else -1.0
	home = position
	# body: the city is layer 1; monsters sit on their own layer and only bump into the city
	collision_layer = 0 if floater else LAYER
	collision_mask = 0 if floater else 1
	floor_snap_length = .6; floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = radius * (1.2 if elite else 1.0); cap.height = maxf(cap.radius * 2.0 + .1, minf(tag_h * .8, 2.2))
	cs.shape = cap; cs.position.y = cap.height / 2.0; add_child(cs)
	_build_model()
	_shadow()
	_make_plate()
	if flags.has("mini"): _mini_appears()
	if flags.has("boss") and Fx.me: Fx.me.shake(.3)

func at_pos() -> Vector3: return position

func _build_model() -> void:
	vis = Node3D.new(); vis.name = "vis"; add_child(vis)
	model = MobModels.build(type)
	if model == null:
		var path := "res://assets/imp/imp.glb" if type == "imp" else "res://assets/mobs/%s.glb" % type
		if not ResourceLoader.exists(path): path = "res://assets/imp/imp.glb"
		if not _scenes.has(path): _scenes[path] = load(path)
		model = (_scenes[path] as PackedScene).instantiate(); Tint.apply(model)
	vis.add_child(model)
	pose = model.get_meta("pose") if model.has_meta("pose") else null
	for i in 2:
		legs.append(model.find_child("leg_%d" % i, true, false)); arms.append(model.find_child("arm_%d" % i, true, false))
		knees.append(model.find_child("kn_%d" % i, true, false)); elbows.append(model.find_child("el_%d" % i, true, false))
	for i in 4:
		var q := model.find_child("q_%d" % i, true, false)
		if q: quads.append(q)
	head = model.find_child("head", true, false); tail = model.find_child("tail", true, false)
	base_scale = (1.35 if elite else 1.0) * (1.15 if flags.has("mini") else 1.0)
	vis.scale = Vector3.ONE * base_scale
	_meshes = model.find_children("*", "MeshInstance3D", true, false)
	if elite:
		var m := StandardMaterial3D.new(); m.albedo_color = Color(1, .85, .35, .35); m.emission_enabled = true
		m.emission = Color(.5, .38, .05); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; _overlay = m
		crown = MobModels.cyl(vis, 0, .22, .38, Vector3(0, tag_h - .15, 0), Color("ffd66b"), Vector3.ZERO, 5, true)
	_cur_ov = null; _set_ov(_overlay)
	if not _red:
		_red = _ovmat(Color(1, .12, .12, .62)); _tell = _ovmat(Color(1, .8, .3, .55)); _tell_red = _ovmat(Color(1, .2, .1, .6))

static func _ovmat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _set_ov(m: Material) -> void:
	if m == _cur_ov: return
	_cur_ov = m
	for n in _meshes: if is_instance_valid(n): n.material_overlay = m

# 7.2's blobShadow: a soft dark disc, so you can read where they stand (and where a pounce lands)
func _shadow() -> void:
	if not _shadow_mesh:
		var tex := GradientTexture2D.new(); tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(.5, .5); tex.fill_to = Vector2(1, .5); tex.width = 32; tex.height = 32
		var g := Gradient.new(); g.set_color(0, Color(0, 0, 0, 1)); g.set_color(1, Color(0, 0, 0, 0)); tex.gradient = g
		var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; sm.albedo_texture = tex; sm.albedo_color = Color(1, 1, 1, .4)
		_shadow_mesh = PlaneMesh.new(); _shadow_mesh.size = Vector2(1, 1); _shadow_mesh.material = sm
	var s := MeshInstance3D.new(); s.mesh = _shadow_mesh; s.position.y = .04
	s.scale = Vector3.ONE * radius * 3.2 * base_scale; s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)

# ---------------------------------------------------------------- levels (7.2 zoneLvBonus / mobLevel / lvColor)
static func zone_bonus(p: Vector3) -> int:
	if p.x > 400: return 1                                      # abroad
	if Vector2(p.x + 382, p.z + 300).length() < 139: return 3   # the mountain
	if p.x < -250 or p.z < -250 or p.x > 170: return 2
	if p.z > 200: return 1
	return 0

static func mob_level(s: Dictionary, at: Vector3, is_elite: bool, opts := {}) -> int:
	var her := maxi(1, SaveBridge.get_i("lvl", 1))
	var L := her + zone_bonus(at) + (1 if randf() < .3 else 0) - (1 if randf() < .25 else 0)
	if is_elite: L += 1
	if s.get("mini", false): L += 2
	if s.get("boss", false): L = maxi(L, her + 1)
	if opts.get("night", false): L += 1
	if opts.has("lv"): L = int(opts["lv"])
	return maxi(1, L)

static func lv_color(L: int) -> Color:
	var d := L - maxi(1, SaveBridge.get_i("lvl", 1))
	if d <= -3: return Color("9a94a8")
	if d < 0: return Color("5fff9e")
	if d <= 1: return Color("ffe9fb")
	if d == 2: return Color("ffb03a")
	return Color("ff3b3b")

func _make_plate() -> void:
	if not Fx.me: return
	if not is_instance_valid(_plate_root):
		var cl := CanvasLayer.new(); cl.layer = 2; Fx.me.add_child(cl)
		_plate_root = Control.new(); _plate_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_plate_root.mouse_filter = Control.MOUSE_FILTER_IGNORE; cl.add_child(_plate_root)
	plate = Control.new(); plate.mouse_filter = Control.MOUSE_FILTER_IGNORE; plate.visible = false
	_plate_root.add_child(plate)
	plate_lab = Label.new(); plate_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var big := flags.has("boss") or flags.has("mini")
	plate_lab.add_theme_font_size_override("font_size", 15 if big else 13)
	plate_lab.add_theme_color_override("font_outline_color", Color(.05, .02, .1, .95)); plate_lab.add_theme_constant_override("outline_size", 6)
	plate_lab.add_theme_color_override("font_color", Color("ffd66b") if elite else lv_color(level))
	plate_lab.text = ("👑 " if elite else "") + "Lv %d" % level + ((" · " + mname) if big or elite else "")
	plate.add_child(plate_lab)
	var w := 90.0 if big else 46.0
	var bg := ColorRect.new(); bg.color = Color(.05, .02, .1, .85); bg.size = Vector2(w + 2, 6); bg.position = Vector2(-1, 20)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; plate.add_child(bg)
	plate_bar = ColorRect.new(); plate_bar.color = Color("ffd66b") if elite else Color("ff5fa2"); plate_bar.size = Vector2(w, 4)
	plate_bar.position = Vector2(0, 21); plate_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; plate.add_child(plate_bar)
	plate.set_meta("w", w)

# where its head is, for speech: the same point the Lv plate hangs from. say() puts the bubble above the plate
const BUBBLE_LIFT := 28.0      # px: the plate hangs 22 px over head_point and is ~24 px tall
func head_point() -> Vector3: return global_position + Vector3(0, tag_h * base_scale + .25, 0)

func say(txt: String, col := Color("ffd6e8"), life := 2.6) -> void:
	if Fx.me: Fx.me.label(head_point(), txt, col, life, true, BUBBLE_LIFT)

func _plate_update() -> void:
	if not plate or not Fx.me or not Fx.me.cam: return
	var cam: Camera3D = Fx.me.cam
	var top := global_position + Vector3(0, tag_h * base_scale + .25, 0)
	var far := 75.0 if flags.has("boss") else 30.0
	if cam.is_position_behind(top) or cam.global_position.distance_squared_to(top) > far * far:
		plate.visible = false; return
	plate.visible = true
	var ratio := plate.get_viewport().get_visible_rect().size / cam.get_viewport().get_visible_rect().size
	var w: float = plate.get_meta("w")
	plate.position = cam.unproject_position(top) * ratio - Vector2(w / 2.0, 22)
	plate_lab.position.x = (w - plate_lab.size.x) / 2.0
	plate_bar.size.x = w * clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	plate_bar.get_parent().get_child(1).visible = hp < max_hp
	plate_bar.visible = hp < max_hp

func _exit_tree() -> void:
	_release()
	if plate and is_instance_valid(plate): plate.queue_free()

# ---------------------------------------------------------------- the API others use
func is_alive() -> bool: return state != "dead" and hp > 0
func fwd() -> Vector3: return Vector3(sin(rotation.y), 0, cos(rotation.y))
func is_boss() -> bool: return flags.has("boss")

func set_phases(list: Array) -> void:
	phases = list.duplicate(true)

# the contract name skills / weapons use (stun, slow, fear, burn, poison)
func set_status(id: String, sec: float) -> void: apply_status(id, sec)

# 7.2 spawnEnemy's mini branch: a rare one has found her
func _mini_appears() -> void:
	var hud := _hud()
	if hud:
		hud.banner("💀 %s APPEARED\n[font_size=16]A rare one. Turkish: [i]nadir[/i] = rare[/font_size]" % mname)
		hud.toast("💀 [b]%s[/b] — a rare miniboss has found you. Big XP if you can take it." % mname, 7.0)
	if Lessons.me: Lessons.me.teach("nadir")
	sfx("rev", position)
	if Fx.me: Fx.me.shake(.4)

# NEW: a boss under 30% loses it — faster, harder, a shockwave and a couple of its own people
const BOSS_ADDS := {"karen": ["thot", "zombie"], "aga": ["thug", "thug"], "cruze": ["imp", "imp"]}
func _enrage() -> void:
	enraged = true; sp *= 1.2; dmg = int(round(dmg * 1.15)); gcd = .2
	var hud := _hud()
	if hud: hud.banner("😡 %s IS FURIOUS!\n[font_size=16][i]kızgın[/i] = angry · watch the red circles[/font_size]" % mname)
	if Lessons.me: Lessons.me.teach("kızgın")
	sfx("enrage", global_position)
	if Fx.me:
		Fx.me.shake(.4); Fx.me.shockwave(global_position, 6.0, Color("ff3b3b"), .45)
		Fx.me.label(global_position + Vector3(0, tag_h + .6, 0), "😡 ÖFKE!", Color("ff3b3b"), 1.6)
	cds["bslam"] = .6
	for k in BOSS_ADDS.get(type, []):
		var a := randf() * TAU
		Enemy.spawn(get_parent(), k, global_position + Vector3(cos(a) * 5, 0, sin(a) * 5), torii)

func stun(sec: float) -> void:
	if not is_alive(): return
	if flags.has("boss"): sec *= .4
	_set_state("stun", sec)
	if Fx.me: Fx.me.label(global_position + Vector3(0, tag_h + .4, 0), "💫", Color("ffd66b"), sec)

# statuses: stun, slow (45% speed), fear (runs away, won't attack), burn / poison (damage over time)
func apply_status(id: String, sec := 3.0) -> void:
	if not is_alive(): return
	if id == "stun": stun(sec); return
	status[id] = maxf(float(status.get(id, 0.0)), sec)

# she (or Bandit, a skill, an ally) hits it. from_dir = the direction of the hit (knockback).
# opts: heavy, kb (force), stagger (secs), status (+ status_t), crit, src
func hit(d: float, from_dir := Vector3.ZERO, opts := {}) -> void:
	if not is_alive(): return
	if phase_t > 0:                                   # a ghost that's phased out: the hit goes through it
		if Fx.me: Fx.me.label(global_position + Vector3(0, tag_h, 0), "✧ boş", Color("cfc0e8"), .7)
		return
	var heavy := bool(opts.get("heavy", false)); var crit := bool(opts.get("crit", false))
	hp -= d; flash_t = .14; hitstop = .1 if heavy else .05
	last_src = str(opts.get("src", ""))
	if not noticed or state == "idle" or state == "notice": noticed = true; _set_state("chase")
	var dv := Vector3(from_dir.x, 0, from_dir.z)
	if dv.length_squared() < .001: dv = -fwd()
	dv = dv.normalized(); fall_dir = 1.0 if dv.dot(fwd()) < 0 else -1.0
	var mass := 4.0 if flags.has("boss") else (1.8 if ARCH[arch].get("armor", false) or flags.has("mini") else 1.0)
	kb = dv * float(opts.get("kb", 9.0 if heavy else 4.0)) / mass
	_check_phases()
	if flags.has("boss") and not enraged and hp > 0 and hp < max_hp * .3: _enrage()
	poise -= d * (1.8 if heavy else 1.0); poise_t = 2.0
	if hp > 0:
		var stag := float(opts.get("stagger", 0.0))
		if flags.has("boss"): pass                    # bosses don't flinch, they just take it
		elif stag > 0: _set_state("stagger", stag)
		elif heavy or poise <= 0: _set_state("stagger", .6); poise = poise_max
		elif not _armored(): _set_state("flinch", .22)
		if opts.has("status"): apply_status(str(opts["status"]), float(opts.get("status_t", 3.0)))
	if Fx.me:
		var col := Color("7bf7ff") if crit else (Color("ffd66b") if elite else Color("ff5fa2"))
		if crit: Fx.me.label(global_position + Vector3(0, tag_h + .6, 0), "KRİTİK! ⚡", Color("7bf7ff"), 1.2)
		Fx.me.label(global_position + Vector3(0, tag_h, 0), str(int(round(d))), col, .9)
		Fx.me.puff(global_position + Vector3(0, tag_h * .5, 0), Color("ffe04d"), 7 if heavy else 4, 1.8 if heavy else 1.5, 1.5, .4)
		if heavy: Fx.me.shake(.12)
	Bus.emit_ev("enemy_hit", {"enemy": self, "pos": global_position, "dmg": d, "heavy": heavy, "crit": crit, "src": last_src})
	sfx("enemy_hit_heavy" if heavy else "enemy_hit", global_position)
	if flags.has("boss") and hp > 0:                  # 7.2's battle quiz marks (the quiz owner listens)
		if not _q66 and hp < max_hp * .66: _q66 = true; Bus.emit_ev("boss_quiz", {"enemy": self, "at": .66})
		elif not _q33 and hp < max_hp * .33: _q33 = true; Bus.emit_ev("boss_quiz", {"enemy": self, "at": .33})
	if hp <= 0: _die()

func _armored() -> bool:
	if state == "crun": return true
	if state in ["windup", "strike"]:
		return ARCH[arch].get("armor", false) or flags.has("mini")
	return false

# her parry landed on this one's swing: it reels, stunned (her window for a free combo)
func parried() -> void:
	if not is_alive(): return
	_release(); poise = 0.0
	kb = -fwd() * 5.0
	stun(1.8)
	sfx("parry_stun", global_position)
	if Fx.me:
		Fx.me.label(global_position + Vector3(0, tag_h + .3, 0), "SERSEM! 💫 (dazed)", Color("7bf7ff"), 1.4)
		Fx.me.puff(global_position + Vector3(0, 1.4, 0), Color("7bf7ff"), 10, 2.0, 1.6, .5)

func _check_phases() -> void:
	for p in phases:
		if p.get("done", false) or hp > max_hp * float(p["at"]): continue
		p["done"] = true
		var hud := _hud()
		if hud: hud.banner("⚠️ " + str(p.get("bn", "")))
		if hud and p.get("sub", "") != "": hud.toast(p["sub"], 3.2)
		for op in p["ops"]:
			match op[0]:
				"enrage": sp *= float(op[1]); dmg = int(round(dmg * float(op[1]))); enraged = true
				"caster":
					flags["caster"] = true
					if not attacks.has("hex"): attacks.append("hex")
					cds["hex"] = .8
				"charger": flags["charger"] = true; ch_cd = 1.2
				"summon":
					for i in int(op[2]):
						var a := randf() * TAU
						Enemy.spawn(get_parent(), op[1], global_position + Vector3(cos(a) * 5, 0, sin(a) * 5), torii)

# ---------------------------------------------------------------- death (7.2 killEnemy)
func _die() -> void:
	hp = 0; _release(); state = "dead"; dead_t = 0.0
	remove_from_group("enemies"); collision_layer = 0
	if plate and is_instance_valid(plate): plate.queue_free(); plate = null
	SaveBridge.data["kills"] = SaveBridge.get_i("kills") + 1
	var mult: float = Streaks.me.bump() if is_instance_valid(Streaks.me) else 1.0    # 7.2 killEnemy: bumpStreak(), streakMult()
	var sxp := int(round(xp * mult))
	var paid := false
	if Lessons.me:
		if not Items.me: Lessons.me.xp(sxp); paid = true    # Items._on_kill pays XP (× the streak) when it's wired
		Lessons.me.lesson_tick()
		match type:
			"ghost": Lessons.me.teach("hayalet")
			"karen": Lessons.me.teach("patron")
			"scorpion": Lessons.me.teach("akrep")
	var p := global_position
	sfx(snd, p); sfx("enemy_die", p)
	var hud := _hud()
	if Fx.me:                       # a kill should read instantly: big number, ring of sparks, a thump
		Fx.me.label(p + Vector3(0, tag_h + .8, 0), "+%d XP" % sxp + (" ×%.2f" % mult if mult > 1 else ""), Color("ffd66b") if mult > 1 else Color("8ff2ff"), 1.5)
		Fx.me.puff(p + Vector3(0, 1.4, 0), [Color("ffd66b"), Color("ff5fa2"), Color("8ff2ff")] if mult > 1 else [Color("b06bff"), Color("8ff2ff")], int(round(10 + mult * 8)), 2.2, 2.6, .9, .6)
		Fx.me.shake(.5 if flags.has("boss") else (.35 if flags.has("mini") else .12))
		if randf() < .3: Fx.me.label(p + Vector3(0, tag_h * base_scale + .25, 0), ["\"Ahhh...\"", "\"Yeter!\" (Enough!)", "\"Hayır!\" (No!)"].pick_random(), Color("ffd6e8"), 1.8, true, BUBBLE_LIFT)
	if elite and not flags.has("boss") and hud:
		hud.banner("👑 EPIC %s DOWN!\n[font_size=16]+%d XP[/font_size]" % [mname, xp])
	if flags.has("mini"):
		if not Items.me:                                  # Items gives the 120-260₺ + weapon drop when it's wired
			var bonus := randi_range(120, 260)
			SaveBridge.data["lira"] = SaveBridge.get_i("lira") + bonus
			Bus.emit_ev("lira", {"delta": bonus})
		if hud: hud.banner("💀 %s DEFEATED!\n[font_size=16]Rare kill · +%d XP[/font_size]" % [mname, xp])
		if "dance_t" in torii: torii.set("dance_t", 1.6)
		if Fx.me: Fx.me.puff(p + Vector3(0, 1.5, 0), Fx.CONF, 26, 3, 3, 1.2)
		sfx("fanfare", p)
		if type == "lory" and hud: hud.toast("💀 [b]LORY down.[/b] She looked like you. She fought like you. She was not you.", 9.0)
	if flags.has("boss"):
		if hud: hud.banner("💥 %s DEFEATED!\n[font_size=16]Boss down![/font_size]" % mname)
		if Fx.me: Fx.me.puff(p + Vector3(0, 1.5, 0), Fx.CONF, 30, 3.5, 3.5, 1.3)
	var purse := int(round((randi_range(40, 60) if elite else randi_range(6, 18)) * mult))   # lira scales with the streak too
	died.emit(self)
	Bus.emit_ev("enemy_died", {"enemy": self, "pos": p, "kind": type, "elite": elite, "xp": xp, "boss": flags.has("boss"),
		"mini": flags.has("mini"), "level": level, "lira": purse, "roam": has_meta("roam"), "xp_paid": paid, "mult": mult, "src": last_src})

func _death_anim(dt: float) -> void:
	dead_t += dt
	global_position += kb * dt; kb *= pow(.02, dt)
	if floater:                                       # spirits rise and flicker out
		vis.position.y += dt * 1.6; vis.visible = fmod(dead_t, .1) < .065
		vis.scale = Vector3.ONE * base_scale * maxf(.05, 1.0 - dead_t)
	else:                                             # fall over, then sink into the ground
		var u := minf(dead_t / .45, 1.0)
		vis.rotation = Vector3(-1.45 * fall_dir * u * u, vis.rotation.y, vis.rotation.z * (1.0 - u))
		if dead_t > .6:
			vis.position.y -= dt * 1.1
			vis.scale = Vector3.ONE * base_scale * maxf(.05, 1.0 - (dead_t - .6) * 1.6)
	if dead_t > 1.05:
		if Fx.me: Fx.me.puff(global_position + Vector3(0, .6, 0), [Color("b06bff"), Color("ff5fa2"), Color("8ff2ff")], 12, 1.8, 2.2, .7)
		queue_free()

# ---------------------------------------------------------------- the brain
func _physics_process(dt: float) -> void:
	if state == "dead" or not is_instance_valid(torii): return
	if Overlay.any(): return              # 7.2's loop freezes the fight during calls and quizzes
	if _snap: _snap = false; _place_on_ground()
	if hitstop > 0: hitstop -= dt; return
	t += dt; gcd -= dt; dodge_cd -= dt; talk_cd -= dt; ch_cd -= dt; poise_t -= dt
	for k in cds.keys(): cds[k] = float(cds[k]) - dt
	if poise_t <= 0: poise = poise_max
	_tick_status(dt)
	if state == "dead": return
	var tg: Node3D = _target()
	var to := tg.global_position - global_position; to.y = 0
	var d := to.length()
	var dir := to / d if d > .01 else fwd()
	var her_down := bool(torii.get("dead")) if "dead" in torii else false
	var spd := sp * (.45 if status.has("slow") else 1.0)
	var move := Vector3.ZERO
	_ghost_phase(dt)
	match state:
		"idle":
			move = _wander(dt, spd)
			if d < aggro and not her_down: _notice()
		"notice":
			st_t -= dt; _face(dir, dt, 2.0)
			if st_t <= 0: _set_state("chase")
		"chase":
			if her_down or (d > aggro * 1.6 and not flags.has("boss")): _set_state("idle")
			else:
				move = _chase(dir, d, spd, dt)
				if not status.has("fear"): _think(d, dir, dt)
		"windup":
			st_t -= dt; _face(dir, dt, .35)                # tracks her slowly: side-step and it whiffs
			if atk_id == "pounce" or atk_id == "bite": move = Vector3.ZERO
			if st_t <= 0: _release_attack()
		"strike":
			st_t -= dt
			move = fwd() * float(atk.get("lunge", 0.0)) * clampf(st_t / maxf(.01, st_len) + .3, 0.0, 1.0)
			if not atk_hit and d < float(atk.get("reach", 2.0)) + radius and absf(fwd().signed_angle_to(dir, Vector3.UP)) < float(atk.get("arc", 1.2)) * .5 + .2:
				_land_hit(dir)
			if st_t <= 0: _set_state("recover", float(atk.get("rec", .5)))
		"recover", "flinch", "stagger", "stun":
			st_t -= dt
			if st_t <= 0: _set_state("chase")
		"cwind", "crun", "daze":
			move = _charge(dt, dir, d)
	# feel: knockback slides them, they push apart, gravity, walls
	var sep := _separation()
	velocity.x = move.x + kb.x + sep.x; velocity.z = move.z + kb.z + sep.z
	kb *= pow(.02, dt)
	if floater:
		velocity.y = 0.0
		_ground_t -= dt
		if _ground_t <= 0: _ground_t = .15; _ground_y = _ray_ground(global_position.x, global_position.z, global_position.y + 1.5, global_position.y)
		global_position.y = lerpf(global_position.y, _ground_y, minf(1.0, dt * 6.0))
	else:
		if not is_on_floor(): velocity.y -= GRAV * dt
		elif velocity.y < 0: velocity.y = -.5
	var want := Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	if not floater and global_position.y < -40.0: _snap = true
	if state == "crun" and want > 4.0 and Vector2(get_real_velocity().x, get_real_velocity().z).length() < want * .4 and is_on_wall():
		_wall_bonk()
	# 7.2: pushed out to ~1.05 m from her, so they never stand inside her
	var pd := global_position - torii.global_position; pd.y = 0
	var minr := radius + .55
	if pd.length() < minr and pd.length() > .001 and not floater: global_position += pd.normalized() * (minr - pd.length())
	# stuck on a kerb or a low wall while chasing: hop it
	_stuck_t -= dt
	if _stuck_t <= 0:
		_stuck_t = 1.4
		if state == "chase" and not floater and d > 3.0 and global_position.distance_to(_stuck_p) < .5 and is_on_floor(): velocity.y = 7.5
		_stuck_p = global_position
	if state == "chase" and d < 15.0 and not her_down: _first_sight()
	if flags.has("sum") and state != "stun": _summon(dt, d)

func _target() -> Node3D:
	if guard and Bandit.me and is_instance_valid(Bandit.me): return Bandit.me
	return torii

func _face(dir: Vector3, dt: float, mul := 1.0) -> void:
	if dir.length_squared() < .0001: return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(float(ARCH[arch].get("turn", 8.0)) * mul * dt * (.5 if flags.has("boss") else 1.0), 0.0, 1.0))

func _set_state(s: String, dur := 0.0) -> void:
	if state == "dead": return
	if _tok and not (s in ["windup", "strike", "recover"]): _release()
	state = s; st_t = dur; st_len = maxf(.01, dur)

func _release() -> void:
	if _tok: _tok = false; _tokens = maxi(0, _tokens - 1)

func _grab_token() -> bool:
	if _tok: return true
	if flags.has("boss") or flags.has("mini"): return true
	var night: bool = Spawner.me != null and Spawner.me.night
	if _tokens >= (3 if night else 2): return false
	_tokens += 1; _tok = true
	return true

func _wander(dt: float, spd: float) -> Vector3:
	_wander_t -= dt
	if _wander_t <= 0:
		_wander_t = randf_range(2.5, 5.0)
		_wander_to = global_position if randf() < .4 else home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	var to := _wander_to - global_position; to.y = 0
	if to.length() < .6: return Vector3.ZERO
	_face(to.normalized(), dt, .5)
	return to.normalized() * spd * .35

func _notice() -> void:
	noticed = true
	_set_state("notice", .2 if flags.has("boss") else .45)
	if is_on_floor(): velocity.y = 3.5
	if Fx.me: Fx.me.label(global_position + Vector3(0, tag_h + .3, 0), "!", Color("ffd66b"), .8)
	sfx("enemy_notice", global_position)

var _seen := false
func _first_sight() -> void:            # 7.2: the first time it spots her, it says something out loud
	if _seen: return
	_seen = true
	_talk(.7)

func _chase(dir: Vector3, d: float, spd: float, dt: float) -> Vector3:
	if status.has("fear"): _face(-dir, dt); return -dir * spd
	var A: Dictionary = ARCH[arch]
	if A.has("kite"):                                 # archers / casters / lobbers hold their distance
		var k: Vector2 = A["kite"]
		_face(dir, dt)
		if d < k.x: return -dir * spd
		if d > k.y: return dir * spd
		if randf() < dt * .25: orbit_dir = -orbit_dir
		return Vector3(-dir.z, 0, dir.x) * orbit_dir * spd * .4
	var orbit := float(A.get("orbit", 0.0))
	var ready := gcd <= 0 and (_tok or _tokens < 2 or flags.has("boss") or flags.has("mini"))
	if orbit > 0 and not ready and d < orbit + 3.0:   # skirmishers circle her, waiting for their turn
		_face(dir, dt)
		if randf() < dt * .3: orbit_dir = -orbit_dir
		var tang := Vector3(-dir.z, 0, dir.x) * orbit_dir
		return (tang * .9 + dir * clampf(d - orbit, -1.0, 1.0)).normalized() * spd * .7
	var stop := (2.0 if flags.has("boss") else 1.15) if ready else 2.6
	_face(dir, dt)
	return dir * spd if d > stop else Vector3.ZERO

func _think(d: float, dir: Vector3, dt: float) -> void:
	if gcd > 0 or dmg <= 0: return
	if flags.has("charger") and ch_cd <= 0 and d > 5.5 and d < 30.0:   # line her up from a run-up and go
		_set_state("cwind", .95 * (.8 if enraged else 1.0))
		sfx("groan", global_position)
		if Fx.me: Fx.me.label(global_position + Vector3(0, tag_h + .5, 0), "⚠️ ŞARJ! CHARGING", Color("ff6b3b"), 1.4)
		return
	var ok: Array = []
	for id in attacks:
		var A: Dictionary = ATK[id]
		if float(cds.get(id, 0.0)) > 0: continue
		if d > float(A["rng"]) or d < float(A.get("min", 0.0)): continue
		ok.append(id)
	if ok.is_empty(): return
	var id: String = ok.pick_random()
	if not ATK[id].has("shot") and not _grab_token(): return
	_start_attack(id)

func _start_attack(id: String) -> void:
	atk_id = id; atk = ATK[id]; atk_hit = false
	var w := float(atk["wind"]) * (.75 if enraged else 1.0)
	_set_state("windup", w)
	cds[id] = float(atk["cd"]); gcd = (.25 if flags.has("boss") else .5 + randf() * .6)
	sfx("enemy_windup", global_position)
	var tell := str(atk.get("tell", "!" if atk.get("kind", "") == "heavy" else ""))
	if tell != "" and Fx.me:
		Fx.me.label(global_position + Vector3(0, tag_h + .4, 0), tell, Color("ff3b3b") if tell == "⚠" else Color("ffb03a"), w + .2)
	var sh := str(atk.get("shot", ""))
	var world := get_parent()
	if sh == "bslam":                                 # the ring IS the tell: get out of it
		Shot.ring(world, Vector3(global_position.x, global_position.y, global_position.z), 5.5, w, int(round(dmg * float(atk["mult"]))), torii, "unblockable", Color("ff3b3b"), self)
	elif sh == "curse":                               # a curse circle under her feet
		var at := torii.global_position
		Shot.ring(world, at, 2.4, w + 1.2, int(round(dmg * float(atk["mult"]))), torii, "aoe", Color("b06bff"), self)

# end of the wind-up: melee goes into its swing, ranged lets go
func _release_attack() -> void:
	var sh := str(atk.get("shot", ""))
	var world := get_parent()
	var from := global_position + Vector3(0, tag_h * .55, 0) + fwd() * .6
	var dm := int(round(dmg * float(atk["mult"])))
	match sh:
		"arrow", "hex": Shot.shoot(world, from, torii, dm, sh, 0.0, self)
		"orb3":
			for s in [-.22, 0.0, .22]: Shot.shoot(world, from, torii, dm, "orb", s, self)
		"lob":
			var lead: Vector3 = torii.velocity * .5 if "velocity" in torii else Vector3.ZERO
			Shot.lob(world, from, torii.global_position + Vector3(lead.x, 0, lead.z), dm, 1.1, 1.9, self)
		"bslam":
			if Fx.me: Fx.me.shake(.3)
			_set_state("strike", float(atk.get("act", .15))); atk_hit = true; return
		"curse": pass
		_:
			_set_state("strike", float(atk.get("act", .15)))
			sfx("enemy_swing", global_position)
			if atk.has("hop") and is_on_floor(): velocity.y = float(atk["hop"])
			return
	_set_state("recover", float(atk.get("rec", .5)))

func _land_hit(dir: Vector3) -> void:
	atk_hit = true
	var dm := int(round(dmg * float(atk.get("mult", 1.0))))
	if dm <= 0: return
	if guard and _target() != torii:
		if Bandit.me: Bandit.me.yelp()
		return
	var res := strike_torii(torii, dm, global_position, str(atk.get("kind", "melee")), self)
	if res.is_empty() or res.get("parried", false): return
	if res.get("blocked", false):
		kb = -fwd() * 3.0                              # bounced off her guard
		return
	if atk.has("kb") and torii.has_method("knockback"): torii.knockback(dir, float(atk["kb"]))
	if atk.has("status") and torii.has_method("set_status"): torii.set_status(str(atk["status"]), 3.0)
	_landed()

# 7.2 mobAttack: 55% of hits say something; Vergi takes lira; 1% Josh crashes in with backup
func _landed() -> void:
	_talk(.55)
	if flags.has("steals"):
		var lira := SaveBridge.get_i("lira")
		if lira > 0:
			var n := mini(lira, randi_range(8, 25))
			SaveBridge.data["lira"] = lira - n; Bus.emit_ev("lira", {"delta": -n})
			if Fx.me: Fx.me.label(global_position + Vector3(0, tag_h + .5, 0), "−%d₺ VERGİ!" % n, Color("ff3b5f"), 1.6)
			var hud := _hud()
			if hud: hud.toast("🧾 [b]VERGİ MEMURU took %d₺![/b] [i](vergi = tax)[/i] Kill him to stop it!" % n, 4.5, true)
			if Lessons.me: Lessons.me.teach("vergi")
			sfx("coin", global_position)
	if randf() < .01: Ally.summon(get_parent(), torii)

# ---- ÖKÜZ / cars: paws the ground, then charges in a dead straight line (7.2 charger branch)
func _charge(dt: float, dir: Vector3, d: float) -> Vector3:
	st_t -= dt
	match state:
		"cwind":
			_face(dir, dt, 1.5)
			if Fx.me and randf() < dt * 20: Fx.me.puff(global_position + dir * 1.4 + Vector3(0, .2, 0), Color("8a7a68"), 1, .7, .7, .5, .7)
			if st_t <= 0:
				ch_dir = dir; atk_hit = false
				_set_state("crun", 1.35)
				sfx("rev", global_position)
				if randf() < .6: say("\"BEN GEÇERİM!\" (I am coming through!)", Color("ffd6e8"), 2.0)
			return Vector3.ZERO
		"crun":
			rotation.y = atan2(ch_dir.x, ch_dir.z)
			if Fx.me and randf() < dt * 26: Fx.me.puff(global_position + Vector3(0, .2, 0), Color("8a7a68"), 1, .9, .8, .5, .8)
			var to := torii.global_position - global_position; to.y = 0
			if not atk_hit and to.length() < radius + 1.1 and absf(torii.global_position.y - global_position.y) < 2.0:
				atk_hit = true
				var res := strike_torii(torii, int(round(dmg * 1.5)), global_position, "heavy", self)
				if not res.is_empty() and not res.get("parried", false):
					if not res.get("blocked", false):
						if torii.has_method("knockback"): torii.knockback(ch_dir, 10.0)
						_landed()
					if Fx.me: Fx.me.shake(.5)
				if state == "crun": _set_state("daze", 1.6)
				return Vector3.ZERO
			if st_t <= 0: _set_state("daze", 1.5)
			var cs := 24.0 if type in ["driver", "cruze"] else 21.0
			return ch_dir * cs * (.45 if status.has("slow") else 1.0)
		_:
			if st_t <= 0: ch_cd = randf_range(3.4, 5.6); _set_state("chase")
			return Vector3.ZERO

# ran into a wall — knocks itself silly, which is the window to hit it
func _wall_bonk() -> void:
	_set_state("daze", 2.6)
	sfx("thud", global_position)
	if Fx.me:
		Fx.me.shake(.45)
		Fx.me.puff(global_position + fwd() * 1.2 + Vector3(0, 1.4, 0), [Color("8a7a68"), Color("cabfd8")], 14, 2.0, 2.4, .9, 1.2)
		Fx.me.label(global_position + Vector3(0, tag_h + .5, 0), ("ÖKÜZ! 🌟" if type == "okuz" else "BONK! 🌟"), Color("ffd66b"), 1.8)
	hit(26.0, -fwd(), {"stagger": 0.01})
	if is_alive(): _set_state("daze", 2.6)

# CEO Karen: every 8 s within 45 m, "EVERYONE — MEETING, NOW!" and a thot or zombie (7.2 e.sum)
func _summon(dt: float, d: float) -> void:
	sum_t -= dt
	if sum_t > 0 or d > 45.0: return
	sum_t = 3.0 if enraged else 8.0
	var a := randf() * TAU
	Enemy.spawn(get_parent(), "thot" if randf() < .5 else "zombie", global_position + Vector3(cos(a) * 4, 0, sin(a) * 4), torii)
	say("\"EVERYONE — MEETING, NOW!\" 📢", Color("ff5fa2"), 2.6)
	sfx("karen", global_position)

# ghosts fade out now and then: hits pass through, and they drift faster
func _ghost_phase(dt: float) -> void:
	if arch != "ghost": return
	phase_t -= dt; phase_cd -= dt
	if phase_cd <= 0 and state == "chase":
		phase_cd = randf_range(5.0, 8.0); phase_t = 1.2
		sfx("woosh2", global_position)

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or not (o is Enemy): continue
		var dv: Vector3 = global_position - o.global_position; dv.y = 0
		var l := dv.length(); var minr: float = radius + o.radius + .25
		if l < minr:
			if l < .001: dv = Vector3(randf() - .5, 0, randf() - .5); l = .001
			push += dv / l * (minr - l) * 6.0
	return push

func _tick_status(dt: float) -> void:
	for k in status.keys():
		status[k] = float(status[k]) - dt
		if status[k] <= 0: status.erase(k)
	if not (status.has("burn") or status.has("poison")): return
	_dot_t -= dt
	if _dot_t > 0: return
	_dot_t = .5
	var n := maxf(1.0, max_hp * .015 + 1.0)
	hp -= n; flash_t = .06
	if Fx.me:
		var c := Color("ff7a2d") if status.has("burn") else Color("5fff9e")
		Fx.me.label(global_position + Vector3(0, tag_h, 0), str(int(n)), c, .6)
		Fx.me.puff(global_position + Vector3(0, tag_h * .5, 0), c, 2, .6, 1.2, .5)
	if hp <= 0: last_src = "dot"; _die()

func _place_on_ground() -> void:
	var y := _ray_ground(global_position.x, global_position.z, global_position.y + 40.0, global_position.y)
	global_position.y = y + (0.0 if floater else .05); _ground_y = y

func _ray_ground(x: float, z: float, from_y: float, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 60.0, z)); q.collision_mask = 1
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h["position"].y if h else fallback

func _talk(chance: float) -> void:
	if talk_cd > 0 or randf() > chance or not Fx.me: return
	talk_cd = 4.0
	var lines: Array = TALK.get(type, [["Hey!", ""]])
	var ln: Array = lines.pick_random()
	var txt := "\"%s\"" % ln[0] + ((" (%s)" % ln[1]) if str(ln[1]) != "" else "")
	say(txt, Color("ffd6e8"), 2.6)
	sfx(snd, global_position)
	var now := Time.get_ticks_msec()
	if voice_on and str(ln[1]) != "" and now - _voice_ms > 2600 and global_position.distance_to(torii.global_position) < 20.0:
		_voice_ms = now; Tts.say(str(ln[0]))

# ---------------------------------------------------------------- looks: gaits (7.2's per-species), tells, reactions
func _process(dt: float) -> void:
	if state == "dead":
		if not Overlay.any(): _death_anim(dt)
		return
	if Overlay.any(): return
	flash_t -= dt
	var ov: Material = _overlay
	if flash_t > 0: ov = _red
	elif state in ["windup", "cwind"] and st_t < st_len * .6 and fmod(st_t, .14) < .07:
		ov = _tell_red if (atk.get("tell", "") == "⚠" or state == "cwind") else _tell
	elif enraged and fmod(t, .5) < .1: ov = _tell_red
	_set_ov(ov)
	vis.visible = not (phase_t > 0 and fmod(t, .1) < .05)
	if hitstop <= 0: _animate(dt)
	if crown: crown.rotation.y += dt * 2.0
	_plate_update()

func _animate(dt: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	var mv := clampf(hv / maxf(1.0, sp), 0.0, 1.0)
	gp += dt * (sp * 1.1 + 1.5) * (.3 + mv)
	var sw := sin(gp)
	var hop := 0.0; var rx := 0.0; var ry := 0.0; var rz := 0.0; var sq := 1.0
	var L0 := 0.0; var L1 := 0.0; var K0 := .05; var K1 := .05
	var A0 := sin(t * 1.4 + ph) * .05; var A1 := -A0; var S0 := .08; var S1 := .08; var E0 := -.2; var E1 := -.2
	var hx := 0.0; var hy := 0.0; var amp := 0.0
	match str(info["gait"]):
		"hop": hop = absf(sin(gp * 1.6)) * .34 * mv; rz = sin(gp * 1.6) * .16; rx = mv * .12
		"float": hop = .55 + sin(t * 2.2 + ph) * .3; rz = sin(t * 1.7 + ph) * .15; rx = sin(t * 1.1 + ph) * .08; A0 = -.5 + sin(t * 2 + ph) * .2; A1 = A0
		"strut":
			hop = absf(sw) * .09 * mv; rz = sw * .13 * mv; ry = sw * .09 * mv; amp = .45
		"hover": hop = .35 + sin(t * 1.8 + ph) * .18; rz = sin(t * 1.3 + ph) * .1; amp = .15
		"shamble":
			var k := .7 if type == "mummy" else .8
			hop = absf(sin(gp * k)) * .07 * mv; rz = .07 + sin(gp * k) * .16; rx = .09
			amp = .3; A0 = -PI / 2 + sin(gp * k) * .18; A1 = -PI / 2 + sin(gp * k + 2.0) * .18
		"rattle": hop = absf(sw) * .06 * mv; rz = sw * .1 + sin(t * 17) * .02; amp = .5
		"skitter": hop = absf(sin(gp * 2)) * .05 * mv; rz = sin(gp * 2) * .09
		"car": hop = absf(sin(t * 26)) * .035; rz = sin(t * 19) * .015
		"quad", "cat":
			hop = absf(sin(gp * (2.0 if type == "cat" else 1.0))) * (.08 if type == "cat" else .06) * mv
			hx = sin(gp) * .08 * mv
		"lory": hop = absf(sw) * .07 * mv; ry = sw * .05 * mv; rz = sw * .03; amp = .5
		_: hop = absf(sw) * .05 * mv; rz = sw * .08 * mv; amp = .5
	if amp > 0:                                       # 7.2 walkPerson
		L0 = sw * amp * mv; L1 = -L0
		K0 = amp * maxf(0.0, -sin(gp - .9)) * 1.15 * mv + .05; K1 = amp * maxf(0.0, sin(gp - .9)) * 1.15 * mv + .05
		if str(info["gait"]) != "shamble":
			A0 = -sw * amp * .72 * mv; A1 = -A0
			E0 = -.22 - amp * maxf(0.0, sw) * .7 * mv; E1 = -.22 - amp * maxf(0.0, -sw) * .7 * mv
		if str(info["gait"]) == "strut": A1 = -1.9; S1 = .25; E1 = -.9          # phone up for a selfie
		if str(info["gait"]) == "rattle": A0 = -1.2; S0 = .3                      # bow held out
	# what it's doing right now goes on top
	var w := 1.0 - clampf(st_t / st_len, 0.0, 1.0)
	var pz := str(atk.get("pose", ""))
	match state:
		"windup", "strike", "recover":
			var k := 1.0 if state == "strike" else (clampf(st_t / st_len, 0.0, 1.0) if state == "recover" else w)
			var striking := state != "windup"
			match pz:
				"jab":
					if striking: A1 = -1.7 * k; E1 = 0.0; rx = .25 * k
					else: A1 = .7 * k; rx = -.12 * k
				"swipe":
					if striking: A1 = -1.4 * k; S1 = -.5 * k; ry = -.6 * k; rx = .15 * k
					else: A1 = -1.3 * k; S1 = 1.3 * k; ry = .5 * k
				"slam":
					if striking: A0 = -.8 * k; A1 = A0; rx = .4 * k; sq = 1.0 + .06 * k
					else: A0 = -2.9 * k; A1 = A0; E0 = -.4; E1 = -.4; rx = -.25 * k; sq = 1.0 - .1 * k
				"lunge":
					if striking: rx = .5 * k; A0 = -1.6 * k; A1 = A0
					else: rx = .3 * k; A0 = -1.5 * k; A1 = A0; sq = 1.0 - .12 * k
				"pounce":
					if striking: rx = .2 * k
					else: rx = .3 * k; sq = 1.0 - .25 * k
				"sting": rx = (.35 if striking else -.3) * k
				"toss":
					if striking: rx = -.35 * k; hx = -.5 * k
					else: rx = .3 * k; hx = .4 * k
				"drain":
					A0 = -1.6 * maxf(k, .5); A1 = A0; S0 = .5; S1 = .5; hop += .4 * k
					if striking: rx = .3 * k
				"bow": A0 = -1.57; A1 = -1.57; S1 = -.3; E1 = 0.0 if striking else -1.6 * k
				"cast":
					if striking: A0 = -1.5 * k; A1 = A0
					else: A0 = -2.5 * k; A1 = A0; S0 = .6 * k; S1 = S0; ry = sin(t * 14) * .2 * k
				"throw":
					if striking: A1 = -.6 * k; E1 = 0.0; rx = .25 * k
					else: A1 = -2.9 * k; E1 = -1.2 * k; rx = -.2 * k
		"flinch": rx -= .35; hx = -.4; A0 = .4; A1 = .4
		"stagger": rx -= .55 * clampf(st_t / st_len, 0.0, 1.0); rz += sin(t * 9) * .1; A0 = .6; A1 = -.3
		"stun", "daze": rz = sin(t * 22) * .14; hop = maxf(0.0, hop * .2) if not floater else hop; hx = sin(t * 6) * .3
		"notice": hop += absf(sin(w * PI)) * .25
		"cwind": hop = absf(sin(t * 26)) * .06; rx = .15; hx = .25
		"crun": rx = .12
	if (state == "stun" or state == "daze") and Fx.me and randf() < dt * 3: Fx.me.puff(global_position + Vector3(0, tag_h + .1, 0), Color("ffd66b"), 1, .5, .3, .5)
	vis.position.y = hop
	vis.rotation = Vector3(rx, ry, rz)
	vis.scale = Vector3(base_scale / sqrt(sq), base_scale * sq, base_scale / sqrt(sq))
	# limbs: bone rigs (people / Lory) through ToriiPose, the exported mobs' joint nodes directly
	if pose:
		pose.leg(-1, L0); pose.leg(1, L1); pose.knee(-1, K0); pose.knee(1, K1)
		pose.arm(-1, A0, 0, S0); pose.arm(1, A1, 0, -S1); pose.elbow(-1, E0); pose.elbow(1, E1)
		pose.body(0, 0, 0); pose.head(hx, hy)
	else:
		if legs[0]: legs[0].rotation.x = L0
		if legs[1]: legs[1].rotation.x = L1
		if knees[0]: knees[0].rotation.x = K0
		if knees[1]: knees[1].rotation.x = K1
		if arms[0]: arms[0].rotation = Vector3(A0, 0, S0)
		if arms[1]: arms[1].rotation = Vector3(A1, 0, -S1)
		if elbows[0]: elbows[0].rotation.x = E0
		if elbows[1]: elbows[1].rotation.x = E1
		if head: head.rotation = Vector3(hx, hy, 0)
	if quads.size() == 4:
		var fast := 26.0 if state == "crun" else (gp * 0.0 + 1.0)
		for i in 4:
			var q: Node3D = quads[i]
			if state == "crun": q.rotation.x = sin(t * fast + i * 1.6) * .9
			elif state == "cwind" and i == 0: q.rotation.x = sin(t * 24) * .5
			else: q.rotation.x = sin(gp * (2.0 if type == "cat" else 1.0) + (PI if i in [1, 2] else 0.0)) * .55 * mv
	if tail: tail.rotation.y = sin(t * 6 + ph) * .5

# ---------------------------------------------------------------- shared helpers (Shot, Bandit, Ally, Spawner use these)
static func sfx(name: String, pos = null) -> void:
	var d := {"name": name}
	if pos != null: d["pos"] = pos
	Bus.emit_ev("sfx", d)

static func _hud() -> Hud:
	return Lessons.me.hud if Lessons.me else null

# hurt her through the player contract. Returns what happened ({} = she dodged / wasn't hittable;
# else player_hit's {dmg, pos, blocked, parried}). A parry stuns the striker.
static func strike_torii(tg: Node3D, d: int, from: Vector3, kind_: String, by: Enemy) -> Dictionary:
	if not is_instance_valid(tg) or not tg.has_method("take_hit"): return {}
	_hook_bus()
	_last_res = {}; _striker = by
	var before = tg.get("hp")
	tg.take_hit(d, from, kind_)
	_striker = null
	var res: Dictionary = _last_res
	if res.is_empty() and (before is int or before is float) and float(tg.get("hp")) < float(before):
		res = {"dmg": float(before) - float(tg.get("hp")), "blocked": false, "parried": false}
	return res

static func _hook_bus() -> void:
	if not _cb_hit.is_valid():
		_cb_hit = func(d: Dictionary): Enemy._on_player_hit(d)
		_cb_atk = func(d: Dictionary): Enemy._on_player_attack(d)
	if not (Bus._subs.get("player_hit", []) as Array).has(_cb_hit): Bus.on("player_hit", _cb_hit)
	if not (Bus._subs.get("player_attack", []) as Array).has(_cb_atk): Bus.on("player_attack", _cb_atk)

static func _on_player_hit(d: Dictionary) -> void:
	_last_res = d.duplicate()
	if d.get("parried", false) and _striker != null and is_instance_valid(_striker): _striker.parried()

# she swings: the nimble ones (Lory above all — she knows the moves) hop back out of it
static func _on_player_attack(_d: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree: return
	for e in tree.get_nodes_in_group("enemies"):
		if not (e is Enemy) or e.state != "chase" or e.dodge_cd > 0: continue
		var ch: float = {"lory": .45, "imp": .2, "cat": .25, "thot": .15}.get(e.type, 0.0)
		if ch <= 0 or randf() > ch: continue
		var away: Vector3 = e.global_position - e.torii.global_position; away.y = 0
		if away.length() > 3.5 or away.length() < .01: continue
		e.dodge_cd = 2.5; e.kb = away.normalized() * 10.0
		if e.is_on_floor(): e.velocity.y = 4.0
