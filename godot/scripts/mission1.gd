# MISSION 1 · THE AVOCADO RUN — ported from MISSIONS[0] ('avo') in 7.2, same steps, places and reward:
# Kaan's call → ride to Safeway → clear 3 parking-lot imps → grab 3 avocados → bring them back to Kaan.
# Reward: the Avocado Flail + 70 XP (+8 per imp). Progress goes into torii_save exactly like 7.2:
# `mid` = "avo" while it runs, then `next` = 1, the flail in `weap`/`dur`, XP and kills added.
extends Node

const CALL := ["Bebeğim! We're out of avocados and I refuse to live like this. 🥑",
	"Ride to Safeway — and heads up, imps have taken over the parking lot. Turkish word of the day: avokado. Easy one."]
const STEPS := [
	{"t": "goto", "at": Vector3(60, 0, -54), "r": 6.0, "lab": "Ride to Safeway 🛒 (grab the bike!)"},
	{"t": "kill", "at": Vector3(60, 0, -52), "n": 3, "lab": "Clear 3 parking-lot imps 👹"},
	{"t": "collect", "at": Vector3(60, 0, -52), "n": 3, "lab": "Grab 3 avocados 🥑"},
	{"t": "return", "at": Vector3(-24, 0, -12), "r": 4.0, "lab": "Bring them back to Kaan 🏠"}]
const AVOS := [Vector3(55, 0, -51), Vector3(60, 0, -49), Vector3(65, 0, -51)]
const FLAIL := {"id": "avoflail", "dmg": 22.0, "cd": .42, "rng": 2.7, "arc": 1.2}

var world: Node3D
var torii: CharacterBody3D
var hud: Hud
var step := -1
var count := 0
var call_i := 0
var beam: MeshInstance3D
var avos: Array[Node3D] = []
var kills := 0
var running := false

func setup(w: Node3D, p: CharacterBody3D, h: Hud) -> void:
	world = w; torii = p; hud = h
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = .5; cm.bottom_radius = .5; cm.height = 60
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, .85, .3, .35); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = m; beam.mesh = cm; beam.visible = false; world.add_child(beam)
	var nxt := SaveBridge.get_i("next", 0)
	var mid = SaveBridge.data.get("mid")
	if nxt == 0 or mid == "avo":
		hud.call_box("KAAN 📱", CALL[0])
		running = true
	else:
		hud.toast("Mission 1 is already done in your save — free roam in the Godot preview 🌃", 6.0)

func _unhandled_input(e: InputEvent) -> void:
	if step == -1 and running and (e.is_action_pressed("ui_accept") or (e is InputEventKey and e.pressed and e.keycode == KEY_ENTER)):
		call_i += 1
		if call_i < CALL.size(): hud.call_box("KAAN 📱", CALL[call_i])
		else:
			hud.call_box("", "")
			_start()

func _start() -> void:
	SaveBridge.data["mid"] = "avo"; SaveBridge.data["next"] = 0; SaveBridge.write()
	hud.banner("MISSION 1 · THE AVOCADO RUN")
	_goto_step(0)

func _goto_step(i: int) -> void:
	step = i; count = 0
	if step >= STEPS.size():
		_complete(); return
	var s: Dictionary = STEPS[step]
	beam.global_position = s["at"] + Vector3(0, 30, 0); beam.visible = s["t"] != "kill"
	if s["t"] == "kill":
		hud.banner("PARKING LOT IMPS! 👹")
		for k in 3:
			var imp := Node3D.new(); imp.set_script(load("res://scripts/imp.gd")); imp.add_to_group("enemies")
			world.add_child(imp)
			imp.position = Vector3(60 + randf_range(-8, 8), 0, -50 + randf_range(-4, 4))
			var model: Node3D = load("res://assets/imp/imp.glb").instantiate(); Tint.apply(model)
			imp.setup(model, torii)
			imp.died.connect(_on_imp_died)
	elif s["t"] == "collect":
		for at in AVOS:
			var a: Node3D = load("res://assets/pickups/avocado.glb").instantiate(); Tint.apply(a)
			world.add_child(a); a.position = at + Vector3(0, .6, 0); avos.append(a)
	_label()

func _label() -> void:
	var s: Dictionary = STEPS[step]
	var lab: String = s["lab"]
	if s.has("n"): lab += "  %d/%d" % [count, s["n"]]
	hud.objective(lab)

func _on_imp_died(_imp) -> void:
	kills += 1; count += 1
	var up := SaveBridge.gain_xp(8)
	hud.toast("+XP 👹" + ("  ·  LEVEL UP! ✨" if up else ""), 1.6)
	if up: _level_up()
	_label()
	if count >= STEPS[step]["n"]: _goto_step(step + 1)

func _physics_process(dt: float) -> void:
	if torii.hp <= 0:
		# she goes down: back at Kaan's door with full health, the mission carries on
		hud.toast("Ouch… back at Kaan's. 💫", 3.0)
		torii.global_position = Vector3(-24, .05, -10); torii.heal_full()
	if step < 0 or step >= STEPS.size(): return
	var s: Dictionary = STEPS[step]
	var here := torii.global_position
	for a in avos:
		if is_instance_valid(a):
			a.rotation.y += dt * 2.0
			if a.global_position.distance_to(here) < 1.6:
				a.queue_free(); count += 1; hud.toast("🥑 avokado!", 1.2); _label()
	if s["t"] == "collect" and count >= s["n"]: _goto_step(step + 1); return
	if s["t"] in ["goto", "return"]:
		var at: Vector3 = s["at"]
		if Vector2(here.x - at.x, here.z - at.z).length() < s["r"]: _goto_step(step + 1)

func _level_up() -> void:
	hud.banner("LEVEL %d ✨" % SaveBridge.get_i("lvl", 1))
	torii.max_hp = SaveBridge.get_i("mh", 100); torii.heal_full()

func _complete() -> void:
	beam.visible = false; running = false
	hud.objective("")
	hud.banner("MISSION COMPLETE 🥑")
	if Lessons.me: Lessons.me.teach("avokado")
	hud.toast("🆕 Avocado Flail 🥑 — mission reward!\n+70 XP · Ne kadar? = How much?", 7.0)
	var d := SaveBridge.data
	d["next"] = 1; d["mid"] = null
	if SaveBridge.gain_xp(70): _level_up()
	d["kills"] = SaveBridge.get_i("kills") + kills
	var weap: Array = d.get("weap", ["katana"])
	if not weap.has("avoflail"): weap.append("avoflail")
	d["weap"] = weap
	var dur: Dictionary = d.get("dur", {})
	dur["avoflail"] = 38; d["dur"] = dur
	SaveBridge.write()
