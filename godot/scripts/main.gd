# Vertical slice: Torii, Bandit and the bike in the real Neo Antalya (exported from 7.2), mission 1 and
# her torii_save. Rendered PS1-style: the 3D draws at a third of the window and gets blown up with hard pixels.
extends Node

const PIXEL := 3                   # 960x720 window -> 320x240 3D, like a PS1

var spawn := Vector3(0, .05, 0)
var lamps: Array[OmniLight3D] = []   # every street lamp; only the ones near her are switched on
var torii: Node3D
var _lamp_t := 0.0
const LAMP_RANGE := 40.0
const LAMP_MAX := 12                 # the web renderer handles a handful of lights well, not 192

func _ready() -> void:
	_inputs()
	var box := SubViewportContainer.new()
	box.stretch = true; box.stretch_shrink = PIXEL
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var vp := SubViewport.new(); vp.msaa_3d = Viewport.MSAA_DISABLED
	box.add_child(vp)
	var world := Node3D.new(); world.name = "World"; vp.add_child(world)
	_build_world(world)
	var p := CharacterBody3D.new(); p.name = "Torii"
	p.set_script(load("res://scripts/player.gd"))
	world.add_child(p)
	p.setup(load("res://assets/torii/torii.glb"))
	p.position = spawn
	torii = p
	# the red bike, parked where it is in 7.2, and Bandit next to her (both exported from 7.2)
	var bike: Node3D = load("res://assets/bike/bike.glb").instantiate()
	Tint.apply(bike)
	world.add_child(bike); bike.position = Vector3(-20, 0, -11); bike.rotation.z = .13
	p.set_bike(bike)
	var ban := Node3D.new(); ban.name = "Bandit"; ban.set_script(load("res://scripts/bandit.gd"))
	world.add_child(ban); ban.position = Vector3(-25.5, 0, -7)
	var ban_model: Node3D = load("res://assets/bandit/bandit.glb").instantiate()
	Tint.apply(ban_model)            # his black fur is a vertex tint over the shared monster atlas
	ban.setup(ban_model, p)
	_update_lamps()
	# her save (the same torii_save 7.2 uses), the HUD, and mission 1
	SaveBridge.load_save()
	p.max_hp = SaveBridge.get_i("mh", 100); p.heal_full()
	p.hold(load("res://assets/weapons/katana.glb"), p.weapon)
	var hud := Hud.new(); add_child(hud)
	p.hp_changed.connect(hud.set_hp); hud.set_hp(p.hp, p.max_hp)
	var m := Node.new(); m.name = "Mission1"; m.set_script(load("res://scripts/mission1.gd")); add_child(m)
	m.setup(world, p, hud)
	if "--m1test" in OS.get_cmdline_user_args(): _dev_m1test(m, p)
	_dev_shot(p)

# developer check only: play mission 1 start to finish by itself, then quit (used against a copy of a
# real 7.2 save with --savedir=, to prove the save round-trips)
func _dev_m1test(m: Node, p: CharacterBody3D) -> void:
	var frames := func(n):
		for i in n: await get_tree().physics_frame
	await frames.call(10)
	m.hud.call_box("", ""); m._start()
	p.global_position = Vector3(60, .5, -54); await frames.call(10)
	print("M1TEST after goto: step ", m.step)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--m1shot="):                     # a frame of the imp fight, then stop
			p.yaw = PI * .5; await frames.call(70)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(9)); get_tree().quit(); return
	for e in get_tree().get_nodes_in_group("enemies"): e.hit(99)
	await frames.call(5)
	print("M1TEST after imps: step ", m.step, " kills ", m.kills)
	for a in m.avos.duplicate():
		if is_instance_valid(a): p.global_position = a.global_position; await frames.call(4)
	print("M1TEST after avocados: step ", m.step)
	p.global_position = Vector3(-24, .5, -12); await frames.call(10)
	print("M1TEST done: step ", m.step, " running ", m.running)
	get_tree().quit()

func _fps_probe() -> void:
	await get_tree().create_timer(3.0).timeout
	var f := 0; var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame; f += 1
	print("FPS ", f / 4.0, "  lamps on ", lamps.filter(func(l): return l.visible).size(), "/", lamps.size())
	get_tree().quit()

# developer check only: `godot --path godot -- --shot=/path.png [--walk] [--front]` saves one frame and quits
func _dev_shot(p: Node3D) -> void:
	var path := ""; var walk := false; var front := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		walk = walk or a == "--walk"; front = front or a == "--front"
		if a == "--fps": _fps_probe()
	if path == "": return
	if front: p.yaw = PI; p.get_node("CamPivot").rotation.y = PI
	if "--bike" in OS.get_cmdline_user_args():
		p.global_position = Vector3(-20, .05, -10); p._get_on()
		Input.action_press("move_forward")
		if "--turn" in OS.get_cmdline_user_args(): Input.action_press("move_left")
		if "--side" in OS.get_cmdline_user_args(): p.get_node("CamPivot").rotation.y = PI / 2
	elif walk: Input.action_press("move_forward")
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _inputs() -> void:
	var map := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "attack": [KEY_F]}
	for a in map:
		if not InputMap.has_action(a): InputMap.add_action(a)
		for k in map[a]:
			var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(a, e)

func _build_world(w: Node3D) -> void:
	# blue-hour night, like 7.1: deep blue sky, haze swallowing the far side
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(.07, .09, .22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.32, .36, .55); env.ambient_light_energy = .9
	env.fog_enabled = true; env.fog_light_color = Color(.12, .15, .3); env.fog_density = .025
	var we := WorldEnvironment.new(); we.environment = env; w.add_child(we)
	var moon := DirectionalLight3D.new(); moon.light_color = Color(.6, .68, 1); moon.light_energy = .55
	moon.rotation = Vector3(-.9, .6, 0); w.add_child(moon)
	# the real Neo Antalya: the static world exported from the 7.2 game with its 7.1 PS1 textures
	# (tools/city/merge_city.py), cut into 60 m chunks; every chunk is solid ground/walls for her
	var city: Node3D = load("res://assets/city/city.glb").instantiate()
	w.add_child(city)
	_solidify(city)
	Tint.apply(city)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/city_data.json"))
	if data:
		for lp in data["lampPosts"]:
			_lamp(w, Vector3(lp[0], lp[1], lp[2]))
		spawn = Vector3(data["spawn"][0], data["spawn"][1] + .05, data["spawn"][2])

func _solidify(n: Node) -> void:
	if n is MeshInstance3D: n.create_trimesh_collision()
	for c in n.get_children(): _solidify(c)

func _lamp(w: Node3D, at: Vector3) -> void:
	var l := OmniLight3D.new(); l.light_color = Color(1, .62, .28); l.light_energy = 2.2; l.omni_range = 9
	l.position = at + Vector3(0, 4.0, 0); l.visible = false; w.add_child(l); lamps.append(l)

func _process(dt: float) -> void:
	_lamp_t -= dt
	if _lamp_t <= 0.0:
		_lamp_t = .5
		_update_lamps()

func _update_lamps() -> void:
	if not torii: return
	var here := torii.global_position
	var near := lamps.filter(func(l): return l.global_position.distance_to(here) < LAMP_RANGE)
	near.sort_custom(func(a, b): return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	var on := {}
	for i in min(LAMP_MAX, near.size()): on[near[i]] = true
	for l in lamps: l.visible = on.has(l)
