# A parking-lot imp (7.2 stats: 20 HP, speed 5.1, hits for 6, worth 8 XP). Chases Torii when she's
# close, scratches her when it reaches her, flies apart when her weapon lands.
extends Node3D

signal died(imp)

const HP := 20.0
const SPEED := 5.1
const DMG := 6
const XP := 8
var hp := HP
var torii: CharacterBody3D
var head: Node3D
var cd := 0.0
var t := 0.0
var hurt := 0.0

func setup(model: Node3D, target: CharacterBody3D) -> void:
	torii = target; add_child(model)
	head = model.find_child("head", true, false)
	t = randf() * 10.0

func hit(dmg: float) -> void:
	hp -= dmg; hurt = .18
	if hp <= 0:
		if Lessons.me: Lessons.me.lesson_tick()         # 7.2: a Turkish lesson every 5 kills
		died.emit(self); queue_free()

func _physics_process(dt: float) -> void:
	if not torii: return
	t += dt; cd -= dt; hurt -= dt
	var to := torii.global_position - global_position; to.y = 0
	var d := to.length()
	if d < 25.0 and d > 1.1:
		position += to / d * SPEED * dt
	if d > .01: rotation.y = atan2(to.x, to.z)          # the model faces +z
	position.y = absf(sin(t * 7.0)) * .15                   # scuttling hop
	scale = Vector3.ONE * (1.25 if hurt > 0 else 1.0)
	if d <= 1.3 and cd <= 0:
		cd = 1.0
		torii.take_hit(DMG)
