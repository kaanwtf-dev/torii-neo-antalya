# Every monster and boss, with 7.2's stats (assets/missions/missions.json "enemies"): chase Torii and hit her
# up close; archers and casters shoot from range (purple shots — dodge them); ghosts float; chargers wind up
# and dash in a straight line, then stand dazed; bosses change at their phase marks (7.2's PHASE: caster,
# charger, enrage, summon). Epic (elite) ones are bigger, gold and twice as tough. Kills give XP, count
# towards the next Turkish lesson, and tell whoever spawned them (the mission or the hunt gate).
class_name Enemy
extends Node3D

signal died(e)

static var DATA := {}
var type := "imp"
var hp := 20.0
var max_hp := 20.0
var sp := 5.0
var dmg := 6
var xp := 8
var flags := {}
var phases: Array = []
var elite := false
var torii: CharacterBody3D
var legs: Array = []
var arms: Array = []
var head: Node3D
var t := 0.0
var cd := 0.0
var shoot_cd := 2.0
var hurt := 0.0
var ch := {"st": "idle", "t": 1.2, "dir": Vector3.ZERO}
var base_scale := 1.0

static func spawn(parent: Node, kind: String, at: Vector3, target: CharacterBody3D, is_elite := false) -> Enemy:
	if DATA.is_empty():
		DATA = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))["enemies"]
	var e := Enemy.new(); parent.add_child(e); e.add_to_group("enemies")
	e.position = at; e.setup(kind, target, is_elite)
	return e

func setup(kind: String, target: CharacterBody3D, is_elite: bool) -> void:
	type = kind; torii = target; elite = is_elite
	var s: Dictionary = DATA.get(kind, DATA["imp"])
	max_hp = float(s["hp"]) * (2.0 if elite else 1.0); hp = max_hp
	sp = float(s["sp"]); dmg = int(s["dmg"]); xp = int(s["xp"]) * (2 if elite else 1)
	for f in ["caster", "archer", "ghost", "boss", "charger"]: if s.get(f, false): flags[f] = true
	var path := "res://assets/imp/imp.glb" if kind == "imp" else "res://assets/mobs/%s.glb" % kind
	if not ResourceLoader.exists(path): path = "res://assets/imp/imp.glb"
	var model: Node3D = load(path).instantiate(); Tint.apply(model); add_child(model)
	for i in 2:
		legs.append(model.find_child("leg_%d" % i, true, false)); arms.append(model.find_child("arm_%d" % i, true, false))
	head = model.find_child("head", true, false)
	base_scale = 1.3 if elite else 1.0
	if elite:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var m := StandardMaterial3D.new(); m.albedo_color = Color(1, .8, .3); m.emission_enabled = true
			m.emission = Color(.4, .3, .05); n.material_overlay = m
	t = randf() * 10.0

func set_phases(list: Array) -> void:
	phases = list.duplicate(true)

func hit(d: float) -> void:
	if hp <= 0: return
	hp -= d; hurt = .18
	_check_phases()
	if hp <= 0:
		if Lessons.me:
			Lessons.me.xp(xp); Lessons.me.lesson_tick()
		SaveBridge.data["kills"] = SaveBridge.get_i("kills") + 1
		died.emit(self); queue_free()

func _check_phases() -> void:
	for p in phases:
		if p.get("done", false) or hp > max_hp * float(p["at"]): continue
		p["done"] = true
		if Lessons.me: Lessons.me.hud.banner("⚠️ " + str(p.get("bn", "")))
		if Lessons.me and p.get("sub", "") != "": Lessons.me.hud.toast(p["sub"], 3.2)
		for op in p["ops"]:
			match op[0]:
				"enrage": sp *= float(op[1]); dmg = int(round(dmg * float(op[1])))
				"caster": flags["caster"] = true; shoot_cd = .8
				"charger": flags["charger"] = true; ch = {"st": "idle", "t": 1.2, "dir": Vector3.ZERO}
				"summon":
					for i in int(op[2]):
						var a := randf() * TAU
						Enemy.spawn(get_parent(), op[1], global_position + Vector3(cos(a) * 5, 0, sin(a) * 5), torii)

func _physics_process(dt: float) -> void:
	if not torii or hp <= 0: return
	t += dt; cd -= dt; hurt -= dt; shoot_cd -= dt
	var to := torii.global_position - global_position; to.y = 0
	var d := to.length()
	var moving := false
	if flags.has("charger") and d < 30.0:
		moving = _charge(dt, to, d)
	elif d < 30.0 and d > (6.0 if flags.has("archer") or flags.has("caster") else 1.1):
		position += to / d * sp * dt; moving = true
	if d > .01 and ch["st"] != "dash": rotation.y = atan2(to.x, to.z)
	if (flags.has("caster") or flags.has("archer")) and d < 16.0 and shoot_cd <= 0:
		shoot_cd = 1.6 if flags.has("archer") else 2.2
		Shot.fire(get_parent(), global_position + Vector3(0, 1.2, 0), torii, dmg, flags.has("archer"))
	position.y = (1.0 + sin(t * 2.0) * .25) if flags.has("ghost") else (absf(sin(t * 7.0)) * .1 if moving else 0.0)
	scale = Vector3.ONE * base_scale * (1.2 if hurt > 0 else 1.0)
	for i in 2:
		var s := sin(t * 9.0 + i * PI) * (.6 if moving else 0.0)
		if legs[i]: legs[i].rotation.x = s
		if arms[i]: arms[i].rotation.x = -s * .7
	if d <= (2.2 if flags.has("boss") else 1.3) and cd <= 0:
		cd = 1.0; torii.take_hit(dmg)

# charger: stand, wind up, dash in a straight line, then dazed (hit it now!)
func _charge(dt: float, to: Vector3, d: float) -> bool:
	ch["t"] -= dt
	match ch["st"]:
		"idle":
			if d > 1.5: position += to / d * sp * .6 * dt
			if ch["t"] <= 0: ch = {"st": "wind", "t": .6, "dir": to / max(d, .01)}
			return true
		"wind":
			if ch["t"] <= 0: ch["st"] = "dash"; ch["t"] = 1.0
			return false
		"dash":
			position += ch["dir"] * sp * 3.0 * dt
			if d < 1.6 and cd <= 0: cd = 1.0; torii.take_hit(int(dmg * 1.5))
			if ch["t"] <= 0: ch = {"st": "dazed", "t": 1.2, "dir": Vector3.ZERO}
			return true
		_:
			if ch["t"] <= 0: ch = {"st": "idle", "t": 2.0, "dir": Vector3.ZERO}
			return false
