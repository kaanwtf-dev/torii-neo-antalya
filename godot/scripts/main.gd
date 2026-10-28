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
	_people(world, p)
	# her save (the same torii_save 7.2 uses), the HUD, and mission 1
	SaveBridge.load_save()
	p.max_hp = SaveBridge.get_i("mh", 100); p.heal_full()
	p.equip_from_save()
	var hud := Hud.new(); add_child(hud)
	p.hp_changed.connect(hud.set_hp); hud.set_hp(p.hp, p.max_hp)
	# the Turkish course (7.2's 16 units) and its quiz screen
	var quiz := QuizUI.new(); add_child(quiz)
	var lessons := Lessons.new(); lessons.name = "Lessons"; add_child(lessons); lessons.setup(p, hud, quiz)
	var m := Missions.new(); m.name = "Missions"; add_child(m)
	m.setup(world, p, hud, lessons)
	for a in OS.get_cmdline_user_args(): if a.begins_with("--autoplay="): _dev_autoplay(m, p, lessons, quiz, hud, int(a.substr(11)))
	if "--lessontest" in OS.get_cmdline_user_args(): _dev_lessontest(lessons, quiz, hud)
	_dev_shot(p)

# developer check only: earn a lesson with 5 kills, screenshot the lesson page and the quiz, answer
# everything right, then quit (run with --savedir= on a copy of a real 7.2 save)
func _dev_lessontest(L: Lessons, q: QuizUI, hud: Hud) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args(): if a.begins_with("--shots="): dir = a.substr(8)
	await get_tree().create_timer(1.0).timeout
	hud.call_box("", "")
	for i in 5: L.lesson_tick()
	await get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	if dir != "": get_viewport().get_texture().get_image().save_png(dir + "/l_lesson.png")
	var ev := InputEventKey.new(); ev.keycode = KEY_ENTER; ev.pressed = true; q._unhandled_input(ev)
	await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	if dir != "": get_viewport().get_texture().get_image().save_png(dir + "/l_quiz.png")
	var n := 0
	while QuizUI.open and n < 40:
		n += 1
		match q.cur.get("kind", "mc"):
			"fill": q.fill.text = str(q.cur["answer"][0] if q.cur["answer"] is Array else q.cur["answer"]); q._submit_fill()
			"order": q.picked = q.cur["words"].duplicate(); q.pool = []; q._submit_order()
			_: q._pick(int(q.cur["a"]))
		await get_tree().create_timer(1.6).timeout
	print("LESSONTEST answered ", n, " ul=", SaveBridge.data.get("ul"), " lesson=", SaveBridge.data.get("lesson"), " xp=", SaveBridge.data.get("xp"), " lvl=", SaveBridge.data.get("lvl"))
	get_tree().quit()

# developer check only: plays the story by itself for `n` missions (calls, quizzes, every step type, hunt
# gates, unit lessons), then quits — run with --savedir= on a copy of a real 7.2 save
func _dev_autoplay(M: Missions, p: CharacterBody3D, L: Lessons, q: QuizUI, hud: Hud, n: int) -> void:
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true
	var start_next := SaveBridge.get_i("next")
	var tries := 0
	while SaveBridge.get_i("next") < start_next + n and tries < 60000:
		tries += 1
		await get_tree().create_timer(.05).timeout
		if hud.box.visible: M._unhandled_input(enter); continue
		if hud._choice:                                  # bazaar haggle / coin toss: take the right answer
			var st: Dictionary = M._st()
			var pick := 0
			if st.get("t") == "choice": for i in st["opts"].size(): if st["opts"][i].get("ok", false): pick = i
			var btns := hud._choice.find_children("*", "Button", true, false)
			if btns.size() > pick: btns[pick].pressed.emit()
			continue
		if QuizUI.open:
			if q.lesson_cb.is_valid(): q._unhandled_input(enter)
			elif not q.lock:
				match q.cur.get("kind", "mc"):
					"fill": q.fill.text = str(q.cur["answer"][0] if q.cur["answer"] is Array else q.cur["answer"]); q._submit_fill()
					"order": q.picked = q.cur["words"].duplicate(); q.pool = []; q._submit_order()
					_: q._pick(int(q.cur["a"]))
			continue
		for e in get_tree().get_nodes_in_group("enemies"): if e.hp > 0 and e.dmg > 0: e.hit(9999)
		var st: Dictionary = M._st()
		if st.is_empty(): continue
		match st["t"]:
			"goto", "return", "zone", "choice", "god":
				p.global_position = Vector3(st["x"], 1.0, st["z"])
				if st["t"] == "god": M._god()
			"collect":
				for pk in M.pickups: if is_instance_valid(pk["node"]) and pk["item"] == st["item"]: p.global_position = pk["node"].global_position; break
			"deliver": p.global_position = Vector3(st["to"][0], 1.0, st["to"][1])
			"photo": M._advance()
	print("AUTOPLAY next=", SaveBridge.get_i("next"), " unit=", SaveBridge.get_i("unit"), " ul=", SaveBridge.get_i("ul"), " lvl=", SaveBridge.get_i("lvl"),
		" weap=", SaveBridge.data.get("weap"), " lira=", SaveBridge.get_i("lira"), " mh=", SaveBridge.get_i("mh"), " gate=", SaveBridge.data.get("gate"), " tries=", tries)
	get_tree().quit()

# every person in the city (7.2's walkers, shopkeepers, café/tavla regulars, named NPCs, Kaan) as one of
# the two NPC bases in an outfit from Kaan's sheet; positions, poses and walking loops come from 7.2
const WOMEN := ["TEYZE", "DEFNE"]
func _people(world: Node3D, p: Node3D) -> void:
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://assets/npc/people.json"))
	if not list: return
	var i := 0
	for d in list:
		i += 1
		var n := Npc.new(); world.add_child(n)
		var female: bool = (i % 2 == 0) and d["name"] == ""      # unnamed people alternate; named ones by name
		for w in WOMEN: if String(d["name"]).contains(w): female = true
		var kind := "female" if female else "male"
		var outfit := "res://assets/npc/%s_%d.png" % [kind, (i * 7 + 3) % 6]
		if d["kind"] == "kaan":
			kind = "male"; outfit = "res://assets/npc/male_base.png"      # Kaan: the sheet's base outfit
		n.setup(kind, outfit, float(d["sc"]), p)
		n.position = Vector3(d["x"], d["y"], d["z"]); n.rotation.y = d["ry"]; n.base_y = d["y"]
		if d["kind"] == "kaan": n.mode = "kaan"
		elif d["kind"] == "ped":
			n.mode = "walk"; n.walk = {"cx": float(d["ped"]["cx"]), "cz": float(d["ped"]["cz"]), "t": float(d["ped"]["t"]), "sp": float(d["ped"]["sp"])}
		elif d["seated"]: n.sit_at(float(d["y"]), float(d["sc"]))

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mobs="):                        # --mobs=zombie,ghost,... : line some up in front of her
			var kinds := a.substr(7).split(",")
			for i in kinds.size():
				var e := Enemy.spawn(p.get_parent(), kinds[i], p.global_position + Vector3((i - kinds.size() / 2.0) * 2.2, 0, -6.5), p)
				e.sp = 0.0; e.dmg = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):                          # --at=x,z,yaw : stand somewhere else for the shot
			var v := a.substr(5).split(",")
			p.global_position = Vector3(float(v[0]), 1.0, float(v[1])); p.yaw = float(v[2])
			if v.size() > 3: p.pitch = float(v[3])
	if "--npcinfo" in OS.get_cmdline_user_args():
		var all := get_tree().root.find_children("*", "Npc", true, false)
		var modes := {}
		for n in all: modes[n.mode] = modes.get(n.mode, 0) + 1
		print("NPCS ", all.size(), " ", modes, " kaan at ", all.filter(func(n): return n.mode == "kaan").map(func(n): return n.global_position))
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
		"move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "attack": [KEY_F], "weapon": [KEY_Q]}
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
