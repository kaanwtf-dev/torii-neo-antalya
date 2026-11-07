# Josh's conspiracy squad — 7.2's summonAlly / updateAllies / ALLY (ALY-01). On 1% of monster hits Josh pops
# up in a cloud of weed smoke ("I TOLD YOU THEY WERE REAL!") and leaves an alien (70 HP, 22 dmg) or a drone
# bird (55 HP, 17 dmg) for 60 s (3 at most). It hunts the nearest monster within 45 m, talks Turkish, takes
# half of what it's fighting's damage now and then, shows its last 10 seconds, and says goodbye.
# Models are MobModels.alien() / drone() / josh() (7.2 makeAlien / makeDroneBird / joshBody).
class_name Ally
extends Node3D

const DEF := {
	"alien": {"hp": 70, "dmg": 22, "sp": 5.2, "name": "👽 Josh's Alien",
		"lines": [["Beni götür!", "Take me!"], ["Selam dünyalı!", "Hello earthling!"], ["Gerçek dışarıda", "The truth is out there"], ["Dost!", "Friend!"]]},
	"drone": {"hp": 55, "dmg": 17, "sp": 7.4, "name": "🐦 Drone Bird",
		"lines": [["Kuş değilim", "I am not a bird"], ["Gözlüyorum", "I am watching"], ["Bip bip!", "Beep beep!"], ["Görev kabul", "Mission accepted"]]},
}

static var _josh: Node3D
static var _josh_t := 0.0

var type := "alien"
var torii: Node3D
var hp := 70.0
var max_hp := 70.0
var dmg := 22.0
var sp := 5.2
var life := 60.0
var atk_cd := 0.0
var hit_cd := 0.0
var line_cd := 2.0
var ph := 0.0
var t := 0.0
var model: Node3D
var _arms: Array = []
var _legs: Array = []
var _gy := 0.0
var _ray_t := 0.0

static func summon(parent: Node, tg: Node3D) -> void:
	if not is_instance_valid(tg) or not parent: return
	var tree := parent.get_tree()
	if tree.get_nodes_in_group("allies").size() >= 3: return
	var typ := "alien" if randf() < .5 else "drone"
	var f: Vector3 = -tg.global_transform.basis.z
	var at := tg.global_position - f * 3.0 + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	# Josh materialises in weed smoke, says his line, and goes again
	if not is_instance_valid(_josh):
		_josh = MobModels.josh(); parent.add_child(_josh)
		var pose: ToriiPose = _josh.get_meta("pose") if _josh.has_meta("pose") else null
		if pose: pose.arm(1, -1.2, 0, -.2); pose.elbow(1, -1.4)
	_josh.visible = true; _josh.global_position = at + Vector3(0, 0, 1.5)
	var to := tg.global_position - _josh.global_position
	_josh.rotation.y = atan2(to.x, to.z); _josh_t = 2.6
	if Fx.me:
		Fx.me.puff(at + Vector3(0, 1.2, 1.5), [Color("7fbf5f"), Color("9ad87a"), Color("c8e8b0")], 22, 2.2, 1.6, 2.4, .9)
		Fx.me.label(at + Vector3(0, 3.1, 1.5), "\"I TOLD YOU THEY WERE REAL!\" 👽", Color("d8ffd8"), 3.6, true)
	Enemy.sfx("woosh2", at)
	var a := Ally.new(); a.type = typ; parent.add_child(a); a.global_position = at; a._setup(tg)
	var hud := Enemy._hud()
	if hud:
		hud.toast("🌿 [b]JOSH APPEARED![/b] He summoned %s to fight for you — 60 seconds!" % DEF[typ]["name"], 8.0)
		hud.banner("👽 CONSPIRACY BACKUP\n[font_size=16]Josh was right all along?![/font_size]")

static var _josh_owner: Ally = null        # one ally ticks Josh's pop-up
static func _josh_tick(by: Ally, dt: float) -> void:
	if is_instance_valid(_josh_owner) and _josh_owner != by: return
	_josh_owner = by
	if not is_instance_valid(_josh) or not _josh.visible: return
	_josh_t -= dt
	if Fx.me and randf() < dt * 4: Fx.me.puff(_josh.global_position + Vector3(randf_range(-.4, .4), 1.7, 0), [Color("9ad87a"), Color("c8e8b0")], 1, .4, .7, 1.8, .5)
	if _josh_t <= 0:
		if Fx.me: Fx.me.puff(_josh.global_position + Vector3(0, 1.2, 0), [Color("7fbf5f"), Color("c8e8b0")], 18, 2.0, 1.5, 2.2, .8)
		_josh.visible = false
		Enemy.sfx("woosh2", _josh.global_position)

func _setup(tg: Node3D) -> void:
	torii = tg; add_to_group("allies")
	var D: Dictionary = DEF[type]
	hp = float(D["hp"]); max_hp = hp; dmg = float(D["dmg"]); sp = float(D["sp"]); ph = randf() * TAU
	model = MobModels.alien() if type == "alien" else MobModels.drone()
	add_child(model)
	for i in 2:
		_arms.append(model.find_child("arm_%d" % i, true, false)); _legs.append(model.find_child("leg_%d" % i, true, false))
	_gy = global_position.y

func _ground(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 3, z), Vector3(x, from_y - 12, z)); q.collision_mask = 1
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h["position"].y if h else from_y

func _physics_process(dt: float) -> void:
	if Overlay.any() or not is_instance_valid(torii): return
	t += dt; life -= dt; atk_cd -= dt; hit_cd -= dt; line_cd -= dt
	_josh_tick(self, dt)
	if life <= 0 or hp <= 0:
		if Fx.me:
			Fx.me.puff(global_position + Vector3(0, 1.2, 0), Color("ff5f5f") if hp <= 0 else Color("7fff9e"), 14, 2.0, 2.0, .9)
			Fx.me.label(global_position + Vector3(0, 2.4, 0), "\"Görüşürüz...\" 💀" if hp <= 0 else "\"Hoşça kal!\" ✨", Color("d8ffd8"), 2.6, true)
		queue_free(); return
	# the nearest monster within 45 m, else follow her
	var best: Enemy = null; var bd := 45.0
	for n in get_tree().get_nodes_in_group("enemies"):
		if not (n is Enemy) or not n.is_alive(): continue
		var dv: Vector3 = n.global_position - global_position; dv.y = 0
		if dv.length() < bd: bd = dv.length(); best = n
	var moving := false
	if best:
		var to := best.global_position - global_position; to.y = 0
		var d := maxf(.01, to.length())
		if d > 1.7: global_position += to / d * sp * dt; moving = true
		rotation.y = atan2(to.x, to.z)
		if d < 2.2 and atk_cd <= 0:
			atk_cd = 1.1
			best.hit(dmg, to / d, {"kb": 4.0, "src": "ally"})
			Enemy.sfx("chitter" if type == "alien" else "sting", global_position)
			if line_cd <= 0: _say()
		if d < 2.4 and hit_cd <= 0:
			hit_cd = 1.4; hp -= best.dmg * .5
			if Fx.me: Fx.me.label(global_position + Vector3(0, 2.2, 0), str(int(round(best.dmg * .5))), Color("ff8a8a"), .9)
	else:
		var to := torii.global_position - global_position; to.y = 0
		var d := maxf(.01, to.length())
		if d > 3.5:
			global_position += to / d * sp * dt; rotation.y = atan2(to.x, to.z); moving = true
	_ray_t -= dt
	if _ray_t <= 0: _ray_t = .08; _gy = _ground(global_position.x, global_position.z, maxf(global_position.y, torii.global_position.y))
	if type == "drone":
		global_position.y = _gy + sin(t * 2.2 + ph) * .25
		for i in _arms.size():
			if _arms[i]: _arms[i].rotation.z = sin(t * 22 + i) * .4
	else:
		global_position.y = _gy + absf(sin(t * 5 + ph)) * .12
		for i in _legs.size():
			if _legs[i]: _legs[i].rotation.x = sin(t * 9 + i * PI) * .6 if moving else 0.0
		for i in _arms.size():
			if _arms[i]: _arms[i].rotation.x = -sin(t * 9 + i * PI) * .5 if moving else 0.0
	if life < 10 and Fx.me and randf() < dt * 2:
		Fx.me.label(global_position + Vector3(0, 2.9, 0), "%ds" % int(ceil(life)), Color("8ff2ff"), .8)

func _say() -> void:
	line_cd = randf_range(4, 8)
	var ln: Array = (DEF[type]["lines"] as Array).pick_random()
	if Fx.me: Fx.me.label(global_position + Vector3(0, 2.7, 0), "\"%s\" (%s)" % [ln[0], ln[1]], Color("c8ffd8"), 2.8, true)
	if Enemy.voice_on: Tts.say(str(ln[0]))
