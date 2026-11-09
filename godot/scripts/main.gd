# The game's root: builds the world (the real Neo Antalya exported from 7.2), Torii, Bandit and the bike,
# loads her torii_save, then wires every system (sky, sound, fx, weapons, items, skills, story, menus,
# shops/quests/tutors/tavla, monsters) and runs 7.2's interact() E dispatcher. Rendered PS1-style: the 3D
# draws at a third of the window and gets blown up with hard pixels. Systems talk over Bus (bus.gd).
extends Node

const PIXEL := 3                   # 960x720 window -> 320x240 3D, like a PS1

var spawn := Vector3(0, .05, 0)
var lamps: Array[OmniLight3D] = []   # every street lamp; only the ones near her are switched on
var torii: Node3D
var _hud: Hud
var _lessons: Lessons
var _lamp_t := 0.0
# 7.2's five checkpoints: touch one for full HP, a save, and a new place to wake up after fainting
const CHECKPOINTS := [[-16, -8, "EV · HOME"], [116, 2, "PLAJ · BEACH"], [60, -52, "MARKET"], [60, 50, "JAYNA"], [-40, -132, "STOCKTON KAPISI"]]
var checkpoints: Array = []
const LAMP_RANGE := 40.0
const LAMP_MAX := 12                 # the web renderer handles a handful of lights well, not 192

func _ready() -> void:
	Bus.reset()                        # Bus subscriptions are static: a reload (NEW GAME, a loaded file) starts clean
	Overlay.reset()                    # a reload (after loading a save file) starts with nothing open
	get_tree().auto_accept_quit = false   # quitting goes through _quit(): save, stop the voices and sound jobs first
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
	# the sky by the hour (7.2 DAYK / updateDayNight): owns fog, background and ambient from here on, plus
	# the PS1 dither / NIGHT GRADE pass on the 3D view
	var sky := SkyCycle.new(); sky.name = "Sky"; add_child(sky); sky.setup(world, env, moon, lamps)
	sky.attach_view(box, null)
	var p := CharacterBody3D.new(); p.name = "Torii"
	p.set_script(load("res://scripts/player.gd"))
	world.add_child(p)
	p.setup(load("res://assets/torii/torii.glb"))
	p.position = spawn; p.spawn = spawn; p.water = water_rects
	torii = p
	# shared feedback: particles, floating numbers and bubbles, shake, screen flashes and fades; then every sound
	var fx := Fx.new(); fx.name = "Fx"; add_child(fx); fx.setup(world, p.cam)
	var au := Audio.new(); au.name = "Audio"; add_child(au); au.setup(world, p.cam)
	# the red bike, parked where it is in 7.2, and Bandit next to her (both exported from 7.2)
	var bike: Node3D = load("res://assets/bike/bike.glb").instantiate()
	Tint.apply(bike)
	world.add_child(bike); bike.position = Vector3(-20, 0, -11); bike.rotation.z = .13
	p.set_bike(bike)
	var ban := Node3D.new(); ban.name = "Bandit"; ban.set_script(load("res://scripts/bandit.gd"))
	world.add_child(ban); ban.position = Vector3(-25.5, 0, -7); ban.add_to_group("bandit")
	var ban_model: Node3D = load("res://assets/bandit/bandit.glb").instantiate()
	Tint.apply(ban_model)            # his black fur is a vertex tint over the shared monster atlas
	ban.setup(ban_model, p)
	_update_lamps()
	_people(world, p)
	# cars, birds, the blimp and the plane (7.2 updateCars / birds / blimp)
	var life := WorldLife.new(); life.name = "WorldLife"; add_child(life); life.setup(world, p)
	# her save (the same torii_save 7.2 uses), the HUD, and the story
	for a in OS.get_cmdline_user_args():                 # dev: --import=FILE does what dragging a file in does
		if a.begins_with("--savedir="): SaveBridge.file_dir = a.substr(10)
		if a.begins_with("--import="): print("IMPORT lvl=", SaveBridge.import_text(FileAccess.get_file_as_string(a.substr(9))))
	var loaded := SaveBridge.load_save()
	p.max_hp = SaveBridge.get_i("mh", 100); p.heal_full()
	p.equip_from_save()
	if SaveBridge.data.get("resp") is Dictionary: p.position = p.respawn_point()   # 7.2 starts her at her checkpoint
	var hud := Hud.new(); add_child(hud); _hud = hud
	p.hp_changed.connect(hud.set_hp); hud.set_hp(p.hp, p.max_hp)
	hud.bind(p)                                       # minimap, skill bar, bars, boss bar, compass
	# the Turkish course (7.2's 16 units) and its quiz screen
	var quiz := QuizUI.new(); add_child(quiz)
	var lessons := Lessons.new(); lessons.name = "Lessons"; add_child(lessons); lessons.setup(p, hud, quiz); _lessons = lessons
	var m := Missions.new(); m.name = "Missions"; add_child(m)
	# 💾 SAVE & LOAD; with no save yet (a new Mac install) it first asks her to bring her browser save
	var save_ui := SaveUI.new(); add_child(save_ui)
	hud.save_pressed.connect(func():
		if not Overlay.any(): save_ui.open_panel(false))
	if "--welcome" in OS.get_cmdline_user_args(): save_ui.open_panel(true)     # dev: screenshot that screen
	elif not loaded and not _dev():
		save_ui.open_panel(true)
		await save_ui.closed                  # (loading a file restarts the game on it instead)
	# ---- the game systems (each one is a Node with `static var me`; they talk over Bus) ----
	# weapons: Q tap / hold-Q wheel, guns + ammo, durability, drops (after equip_from_save)
	var ars := Arsenal.new(); ars.name = "Arsenal"; add_child(ars); ars.setup(p)
	# kill streaks (before Items, so a reload starts at 0 before her stats are pushed)
	var streaks := Streaks.new(); streaks.name = "Streaks"; add_child(streaks); streaks.setup(p, hud)
	# nazars, food, gear, chests, kill loot (setup is a coroutine: no await), then the level-up show + perks,
	# then the I / J bag
	var items := Items.new(); items.name = "Items"; add_child(items); items.setup(world, p, hud)
	var lu := LevelUp.new(); lu.name = "LevelUp"; add_child(lu); lu.setup(p, hud)
	var inv := InventoryUI.new(); inv.name = "InventoryUI"; add_child(inv); inv.setup(p)
	# the bike's parts (worn bike-slot gear) and the level-15 neon underglow (7.2 applyBikeLook2)
	var blook := BikeLook.new(); blook.name = "BikeLook"; add_child(blook); blook.setup(bike, p)
	# skills on R / 1..0, buffs, the boss battle quiz (Bandit Strike drives Bandit)
	var skills := Skills.new(); skills.name = "Skills"; add_child(skills); skills.setup(p, hud, ban)
	# cutscenes (calls, boss intros, Hellspace, opening, credits) and the title / pause / guide / patch menus;
	# both must exist before Missions.setup so the story waits for the title
	var cut := Cutscene.new(); add_child(cut); cut.setup(world, p, hud)
	var menus := Menus.new(); add_child(menus); menus.setup(p, hud, save_ui)
	# the auto quality governor (7.2 autoGfx): a slow Mac steps GRAFİK / VIEW down on its own, with a toast
	var qual := Quality.new(); add_child(qual); qual.setup(p, hud)
	m.setup(world, p, hud, lessons)
	# roaming monsters, night packs, minibosses, the stinky Cruze
	var spawner := Spawner.new(); spawner.name = "Spawner"; add_child(spawner); spawner.setup(world, p)
	if _quiet_dev(): spawner.enabled = false
	# the E people: Shops first (it resets the kill hub the others register on), all on main so their
	# CanvasLayers draw at full window size
	var shops := Shops.new(); shops.name = "Shops"; add_child(shops); shops.setup(world, p, hud)
	var quests := Quests.new(); quests.name = "Quests"; add_child(quests); quests.setup(world, p, hud)
	var tutors := Tutors.new(); tutors.name = "Tutors"; add_child(tutors); tutors.setup(world, p, hud)
	var tavla := Tavla.new(); tavla.name = "Tavla"; add_child(tavla); tavla.setup(world, p, hud)
	var hot := Hotspots.new(); hot.name = "Hotspots"; add_child(hot); hot.setup(world, p, hud)
	var inter := Interactables.new(); inter.name = "Interactables"; add_child(inter); inter.setup(world, p, hud)
	# first-time cards for the new moves (combo, roll, block, lock-on, skills, wheel, bag)
	var tips := Tips.new(); add_child(tips); tips.setup(p)
	if "--godkey" in OS.get_cmdline_user_args(): _dev_godkey(m, p, hud); return
	if "--fxtest" in OS.get_cmdline_user_args(): _dev_fxtest(p, hud); return
	for a in OS.get_cmdline_user_args(): if a.begins_with("--quittest="): _dev_quittest(a.substr(11))
	for a in OS.get_cmdline_user_args():                # dev: --probe=x0,x1,z prints the ground height every metre
		if a.begins_with("--probe="):
			var v := a.substr(8).split(",")
			await get_tree().physics_frame; await get_tree().physics_frame
			var out := []
			for x in range(int(v[0]), int(v[1]), -1 if int(v[1]) < int(v[0]) else 1):
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40, float(v[2])), Vector3(x, -20, float(v[2])))
				var h := world.get_world_3d().direct_space_state.intersect_ray(q)
				out.append("%d:%s" % [x, ("%.2f" % h["position"].y) if h else "-"])
			print("PROBE ", " ".join(out)); get_tree().quit(); return
	if "--savecheck" in OS.get_cmdline_user_args():      # dev: load + repair + resume, write it, report, quit
		SaveBridge.write()
		print("SAVECHECK ", JSON.stringify({"gate": m.gate, "loaded_from": SaveBridge.loaded_from}))
		get_tree().quit(); return
	if loaded:                              # 7.2's applySave() / loadGame() messages
		hud.toast("💾 Progress restored — level %d, %d Turkish words known 🇹🇷" % [SaveBridge.get_i("lvl", 1), (SaveBridge.data.get("words", []) as Array).size()], 7.0)
		if SaveBridge.loaded_from != SaveBridge.KEY:
			hud.toast("💾 The main save was unreadable — restored from a backup instead. You may have lost a few minutes, no more.", 9.0, true)
	for a in OS.get_cmdline_user_args(): if a.begins_with("--autoplay="): _dev_autoplay(m, p, lessons, quiz, hud, int(a.substr(11)))
	if "--lessontest" in OS.get_cmdline_user_args(): _dev_lessontest(lessons, quiz, hud)
	_dev_shot(p)
	for a in OS.get_cmdline_user_args(): if a.begins_with("--brawl="): _dev_brawl(p, float(a.substr(8)))
	# the real start: VHS intro -> title (CONTINUE / NEW GAME starts the story). Dev runs skip both.
	if not _dev() and not Missions.dev_run():
		if "--continue" in OS.get_cmdline_user_args():          # dev: skip the VHS intro and press CONTINUE on the title
			menus.title(); await get_tree().process_frame; menus._continue(); return
		Intro.run(self, menus.title, world, [p, ban, null])

# closing the window saves first (7.2 saved at every event; this catches whatever happened since). Not
# before a save exists (BRING YOUR SAVE still up), and SaveBridge itself refuses while an import waits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

# the orderly quit (close button, Cmd+Q): save, hush the voices, let every background sound job finish, drop the
# cached materials, THEN quit. Left to the engine's own teardown, a voice mid-sentence or a sound job still running
# crashed Godot on quit ("recursive_mutex lock failed")
var _quitting := false
func _quit() -> void:
	if _quitting: return
	_quitting = true
	if not SaveBridge.data.is_empty(): SaveBridge.write()
	if Audio.me: Audio.me.shutdown()
	else: DisplayServer.tts_stop()
	get_tree().paused = false
	for i in 3: await get_tree().process_frame
	await get_tree().create_timer(.2, true).timeout          # the speech engine reports its cancel before we go
	_drop_statics()
	get_tree().quit()

# every static cache that holds a resource (materials, textures, scenes, scripts) — all rebuilt lazily when needed
static func _drop_statics() -> void:
	Enemy._scenes.clear(); Enemy._red = null; Enemy._tell = null; Enemy._tell_red = null; Enemy._shadow_mesh = null
	Npc._scenes.clear(); MobModels._mats.clear(); Projectile._mats.clear(); Projectile._glow = null
	Shot._m.clear(); Tavla._board_tex = null; Hud._cls.clear(); InventoryUI._cls.clear()

# drop every static Callable (Bus subs hold lambdas bound to the player & co) while the scripts are still
# alive — left to the engine's own shutdown they crashed Godot on quit (recursive_mutex lock failed)
func _exit_tree() -> void:
	Bus.reset()
	InventoryUI.quest_panel = Callable(); Enemy._cb_hit = Callable(); Enemy._cb_atk = Callable()
	_drop_statics()

# developer check only: --quittest=tts|reload|close quits the way the quit crash was seen, and prints QUITTEST
func _dev_quittest(mode: String) -> void:
	await get_tree().create_timer(2.0).timeout
	if mode == "reload":
		if not get_tree().has_meta("qt_reloaded"):
			get_tree().set_meta("qt_reloaded", true); print("QUITTEST reloading"); get_tree().reload_current_scene(); return
		await get_tree().create_timer(2.0).timeout
	if mode == "tts" and Audio.me:
		print("QUITTEST tts=", Audio.me.say("Merhaba! Bugün çok güzel bir gün, değil mi? Hadi biraz Türkçe konuşalım.", "tr"))
		await get_tree().create_timer(.4).timeout
	print("QUITTEST quitting via close request")
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)

# dev runs (autoplay, lesson test, screenshots) never stop at the BRING YOUR SAVE screen
func _dev() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay=") or a == "--lessontest" or a.begins_with("--shot=") or a == "--fps" or a == "--savecheck" or a == "--godkey" or a == "--fxtest" or a.begins_with("--probe=") or a.begins_with("--brawl="): return true
	return false

# dev checks that need a calm city: no roaming monsters walking into the shot / test
func _quiet_dev() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a in ["--lessontest", "--fxtest", "--godkey", "--savecheck", "--fps"] or a.begins_with("--probe="): return true
	return false

# 7.2's interact(): ONE E, first taker wins, in 7.2's order. The bike (player.gd) comes first, and the
# trickster gods are Missions' own (it reads E itself, before this, as a child of main). Children get
# _unhandled_input before main, so a box that used this E (say, choose, shop panel) already ate it.
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.is_action("interact")): return
	if not torii or torii.get("dead") or Overlay.any() or Overlay.just_closed() or Cutscene.busy(): return
	if Menus.me and Menus.me.title_up: return
	if torii.get("on_bike"): return
	var bk = torii.get("bike")
	if bk is Node3D and (bk as Node3D).global_position.distance_to(torii.global_position) < 2.6 and torii.global_position.x < 400: return
	if _interact(torii): get_viewport().set_input_as_handled()

func _interact(p: Node3D) -> bool:
	if Hotspots.me and Hotspots.me.try_kaan(p): return true             # Kaan's contracts, up on the balcony
	if Items.me and Items.me.try_interact(p): return true               # locked chests
	if Quests.me and Quests.me.try_interact(p): return true             # quest givers
	if Shops.me and Shops.me.try_interact(p): return true               # Five Sips / Kuyumcu Zeynep
	if Tutors.me and Tutors.me.try_soul(p): return true                 # Old Soul
	if Tavla.me and Tavla.me.try_interact(p): return true               # the tavla tables
	if Interactables.me and Interactables.me.try_josh(p): return true   # Josh in Stockton
	if Tutors.me and Tutors.me.try_npc(p): return true                  # the grammar tutors
	if Interactables.me and Interactables.me.try_props(p): return true  # fountains, simit carts
	if Hotspots.me and Hotspots.me.try_travel(p): return true           # the airport gate / airstrip
	if Interactables.me and Interactables.me.try_dj(p): return true     # the DJ booth
	return false

# developer check only (batch 2): the river stops her at the bank, a checkpoint heals and becomes her
# wake-up spot, a hit shows a number and sparks, fainting costs 10% lira / 30% of the level's XP and
# wakes her at the checkpoint with 70% HP. Prints one FXTEST line per part, then quits.
func _dev_fxtest(p: CharacterBody3D, hud: Hud) -> void:
	await get_tree().create_timer(.6).timeout
	await _dev_clear(hud)
	await get_tree().create_timer(.4).timeout
	# 1. walk west at the river from the east bank (the channel is x -234..-194, the bridge deck z ±5.5)
	p.global_position = Vector3(-186, 1, 60); p.yaw = PI / 2
	for f in 10: await get_tree().physics_frame
	Input.action_press("move_forward")
	var min_x := 999.0
	for f in 150:
		await get_tree().physics_frame
		if LevelUp.me: LevelUp.me.close_tip()
		min_x = minf(min_x, p.global_position.x)
	Input.action_release("move_forward")
	print("FXTEST water: walked west from x=-186, got as far as x=%.1f (river edge -194) y=%.1f" % [min_x, p.global_position.y])
	# ...but Tower Bridge (deck z ±5.5, x -236..-192, ramps beyond) still takes her across
	print("FXTEST open boxes: ", Overlay._open.keys()); await _dev_clear(hud)
	p.global_position = Vector3(-176, 1, 0); p.yaw = PI / 2
	for f in 10: await get_tree().physics_frame
	Input.action_press("move_forward")
	var top := 0.0
	for f in 840:
		await get_tree().physics_frame
		if LevelUp.me: LevelUp.me.close_tip()          # a first-time card popping up mid-walk
		top = maxf(top, p.global_position.y)
	Input.action_release("move_forward")
	print("FXTEST bridge: from x=-176 to x=%.1f (over and down the far ramp if < -250), highest y=%.1f %s" % [p.global_position.x, top, Overlay._open.keys()])
	# 2. checkpoint EV · HOME at (-16, -8)
	await _dev_clear(hud)
	p.hp = 40; p.global_position = Vector3(-16, .5, -8.5)
	for f in 30: await get_tree().physics_frame
	print("FXTEST checkpoint: hp=%d/%d resp=%s" % [p.hp, p.max_hp, SaveBridge.data.get("resp")])
	# 3. a hit: number + sparks
	await _dev_clear(hud)
	p.global_position = Vector3(-24, .5, -2); p.yaw = 0.0
	for f in 5: await get_tree().physics_frame
	var e := Enemy.spawn(p.get_parent(), "imp", p.global_position + Vector3(0, 0, -1.6), p); e.sp = 0.0; e.dmg = 0
	e.max_hp = 500.0; e.hp = 500.0                          # (a katana one-shots a normal imp)
	for f in 3: await get_tree().physics_frame
	p._attack()
	await get_tree().process_frame
	var labs := Fx.me._labs.filter(func(L): return L["life"] > 0).size()
	var parts := Fx.me._parts.filter(func(q): return q["life"] > 0).size()
	print("FXTEST hit: imp hp %.0f/%.0f, knockback %.1f m/s, labels up %d, particles up %d" % [e.hp, e.max_hp, e.kb.length(), labs, parts])
	# 4. faint
	await _dev_clear(hud)
	SaveBridge.data["lira"] = 1000
	var xp0 := SaveBridge.get_i("xp"); var need := SaveBridge.get_i("need", 60)
	p.global_position = Vector3(-60, .5, -30); p.hurt_cd = 0.0; p.hp = 3
	p.take_hit(10)
	print("FXTEST faint: dead=%s right away" % p.dead)
	await get_tree().create_timer(2.9).timeout
	print("FXTEST faint: woke at (%.0f, %.0f) hp=%d/%d lira=%d (was 1000) xp=%d (was %d, need %d) dead=%s" % [p.global_position.x, p.global_position.z,
		p.hp, p.max_hp, SaveBridge.get_i("lira"), SaveBridge.get_i("xp"), xp0, need, p.dead])
	get_tree().quit()

# dev checks: clear whatever the story opened at the start (mission 1's call scene, its dialogue, a tip card)
func _dev_clear(hud: Hud) -> void:
	for i in 30:
		if Cutscene.busy(): Cutscene.me.end(true)
		hud.skip_say()
		if LevelUp.me: LevelUp.me.close_tip()
		await get_tree().process_frame
		if not Overlay.any(): return

# developer check only: E at a real god shrine (already met, stake in her purse), pressed through the real
# input path. The coin toss must stay open (it used to open and close on the same press); a second E closes it.
func _dev_godkey(M: Missions, p: Node3D, hud: Hud) -> void:
	await get_tree().create_timer(.5).timeout
	await _dev_clear(hud)
	await get_tree().create_timer(.2).timeout
	var G: Dictionary = M.GODS[0]
	var npc = SaveBridge.data.get("npc")
	if not (npc is Dictionary): npc = {}; SaveBridge.data["npc"] = npc
	npc["met_" + str(G["id"])] = 1
	SaveBridge.data["lira"] = maxi(SaveBridge.get_i("lira"), 200)
	p.global_position = Vector3(float(G["x"]) + 1.0, 1.0, float(G["z"]))
	for f in 6: await get_tree().physics_frame
	var res := []
	for i in 2:
		for pressed in [true, false]:
			var ev := InputEventKey.new(); ev.keycode = KEY_E; ev.physical_keycode = KEY_E; ev.pressed = pressed
			Input.parse_input_event(ev)
			for f in 4: await get_tree().physics_frame
		res.append(hud._choice != null)
	print("GODKEY open_after_first_E=", res[0], " open_after_second_E=", res[1], " on_bike=", p.on_bike)
	get_tree().quit()

# developer check only: earn a lesson with 5 kills, screenshot the lesson page and the quiz, answer
# everything right, then quit (run with --savedir= on a copy of a real 7.2 save)
func _dev_lessontest(L: Lessons, q: QuizUI, hud: Hud) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args(): if a.begins_with("--shots="): dir = a.substr(8)
	await get_tree().create_timer(1.0).timeout
	await _dev_clear(hud)
	for i in 5: L.lesson_tick()
	await get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	if dir != "": get_viewport().get_texture().get_image().save_png(dir + "/l_lesson.png")
	var ev := InputEventKey.new(); ev.keycode = KEY_ENTER; ev.pressed = true
	while q.lesson_cb.is_valid(): q._unhandled_input(ev)          # page through the lesson's lines
	await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	if dir != "": get_viewport().get_texture().get_image().save_png(dir + "/l_quiz.png")
	var n := 0
	var hint := "--hint" in OS.get_cmdline_user_args()      # also buy a 💡 hint once per question kind (shot each)
	if hint: SaveBridge.data["lira"] = 100
	var hinted := {}
	while QuizUI.open and n < 40:
		n += 1
		var kind: String = q.cur.get("kind", "mc")
		if hint and not hinted.has(kind):
			hinted[kind] = true
			var h := InputEventKey.new(); h.keycode = KEY_H; h.pressed = true; q._unhandled_input(h)
			await get_tree().create_timer(.3).timeout
			await RenderingServer.frame_post_draw
			if dir != "": get_viewport().get_texture().get_image().save_png(dir + "/l_hint_%s.png" % kind)
			print("LESSONTEST hint ", kind, " lira=", SaveBridge.get_i("lira"))
		match kind:
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
		if "--apdebug" in OS.get_cmdline_user_args() and tries % 100 == 0:
			print("AP ", tries, " idx=", M.idx, " step=", M.step, " open=", Overlay._open.keys(), " st=", M._st().get("t"))
		if LevelUp.me and Overlay.is_open("tip"): LevelUp.me.close_tip(); continue      # first-time cards
		if LevelUp.me and Overlay.is_open("perk"): LevelUp.me.pick_perk(0); continue    # level-up perk pick
		if hud.box.visible: hud.next_line(); continue
		if hud._choice:                                  # bazaar haggle / coin toss: take the right answer
			var st: Dictionary = M._st()
			var pick := 0
			if st.get("t") == "choice":
				for k in M.choice_order.size(): if st["opts"][M.choice_order[k]].get("ok", false): pick = k
			hud._pick_choice(pick)
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

# developer check only: `-- --brawl=40 --savedir=DIR` = free play (no story) with roaming monsters plus a pack
# dropped round her, and a dumb bot that fights for SEC seconds: walks at the nearest one, light/heavy
# chains, rolls, blocks, lock-on, skills, jumps. Prints one BRAWL line with what happened, then quits.
func _dev_brawl(p: CharacterBody3D, sec: float) -> void:
	await get_tree().create_timer(1.0).timeout
	var c := {"kills": 0, "hits": 0, "hurt": 0, "faints": 0, "skills": 0, "lvlups": 0}
	Bus.on("enemy_died", func(_d): c["kills"] += 1)
	Bus.on("enemy_hit", func(_d): c["hits"] += 1)
	Bus.on("player_hit", func(_d): c["hurt"] += 1)
	Bus.on("faint", func(_d): c["faints"] += 1)
	Bus.on("skill_used", func(_d): c["skills"] += 1)
	Bus.on("level_up", func(_d): c["lvlups"] += 1)
	var kinds := ["zombie", "imp", "ghost", "thot", "zombie"]
	for i in kinds.size():
		Enemy.spawn(p.get_parent(), kinds[i], p.global_position + Vector3(cos(i * 1.3) * 7.0, 0, sin(i * 1.3) * 7.0), p)
	var t0 := Time.get_ticks_msec(); var k := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await get_tree().create_timer(.1).timeout
		k += 1
		if LevelUp.me and Overlay.is_open("tip"): LevelUp.me.close_tip(); continue
		if LevelUp.me and Overlay.is_open("perk"): LevelUp.me.pick_perk(0); continue
		if _hud.box.visible: _hud.next_line(); continue
		for o in Overlay._open.keys(): Overlay.close(o)
		if p.dead: continue
		var best: Node3D = null; var bd := 1e9
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("is_alive") and e.is_alive():
				var dd: float = e.global_position.distance_to(p.global_position)
				if dd < bd: bd = dd; best = e
		for a in ["move_forward", "block", "roll", "sprint", "jump"]: Input.action_release(a)
		if best == null:
			if k % 50 == 0: Enemy.spawn(p.get_parent(), kinds[k % kinds.size()], p.global_position + Vector3(6, 0, 4), p)
			continue
		var to := best.global_position - p.global_position; to.y = 0
		p.yaw = atan2(-to.x, -to.z)
		if bd > 2.2: Input.action_press("move_forward")
		if bd > 6.0 and k % 23 == 0: Input.action_press("sprint")
		match k % 17:
			3: p.combat.heavy_press()
			7: Input.action_press("roll")
			11: Input.action_press("block")
			13: if Skills.me: Skills.me.use(k % 5)
			15: Input.action_press("jump")
			16: p.lock_target = best
			_:
				if bd < 3.0: p.combat.light()
	for a in ["move_forward", "block", "roll", "sprint", "jump"]: Input.action_release(a)
	print("BRAWL ", JSON.stringify(c), " hp=", p.hp, "/", p.max_hp, " st=", int(p.stamina), " mana=", int(p.mana), " lvl=", SaveBridge.get_i("lvl", 1),
		" mobs=", get_tree().get_nodes_in_group("enemies").size(), " pos=", p.global_position.snapped(Vector3.ONE))
	get_tree().quit()

# every person in the city (7.2's walkers, shopkeepers, café/tavla regulars, named NPCs, Kaan) as one of
# the two NPC bases in an outfit from Kaan's sheet; positions, poses and walking loops come from 7.2.
# Npc.from_people picks name/body from npc_identity.json (and skips the 6 tavla spots, Tavla builds those)
func _people(world: Node3D, p: Node3D) -> void:
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://assets/npc/people.json"))
	if not list: return
	var i0 := 0
	for d in list:
		Npc.from_people(world, d, i0, p)
		i0 += 1

func _fps_probe() -> void:
	await get_tree().create_timer(3.0).timeout
	var f := 0; var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame; f += 1
	print("FPS ", f / 4.0, "  lamps on ", lamps.filter(func(l): return l.visible).size(), "/", lamps.size())
	get_tree().quit()

# developer check only: `godot --path godot -- --shot=/path.png [--walk] [--front] [--inv]` saves one frame and quits
func _dev_shot(p: Node3D) -> void:
	var path := ""; var walk := false; var front := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		walk = walk or a == "--walk"; front = front or a == "--front"
		if a == "--fps": _fps_probe()
	if path == "": return
	if "--clear" in OS.get_cmdline_user_args():           # --clear: close the story's opening call first
		await get_tree().create_timer(.4).timeout
		var hs := get_tree().root.find_children("*", "Hud", true, false)
		if hs.size(): await _dev_clear(hs[0])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mobs="):                        # --mobs=zombie,ghost,... : line some up in front of her
			var kinds := a.substr(7).split(",")
			for i in kinds.size():
				var close := "--hit" in OS.get_cmdline_user_args()      # --hit: within sword reach, and she swings
				var e := Enemy.spawn(p.get_parent(), kinds[i], p.global_position + Vector3((i - (kinds.size() - 1) / 2.0) * (1.1 if close else 2.2), 0, -1.8 if close else -6.5), p)
				e.sp = 0.0; e.dmg = 0; e.max_hp = 999.0; e.hp = 999.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):                          # --at=x,z,yaw[,pitch] : stand somewhere else for the shot
			var v := a.substr(5).split(",")
			p.global_position = Vector3(float(v[0]), 1.0, float(v[1])); p.yaw = float(v[2])
			if v.size() > 3: p.pitch = float(v[3])           # 7.2's pitch: higher = looking down from above
			p.snap_camera()
	if "--npcinfo" in OS.get_cmdline_user_args():
		var all := get_tree().root.find_children("*", "Npc", true, false)
		var modes := {}
		for n in all: modes[n.mode] = modes.get(n.mode, 0) + 1
		print("NPCS ", all.size(), " ", modes, " kaan at ", all.filter(func(n): return n.mode == "kaan").map(func(n): return n.global_position))
	if front: p.yaw = PI; p.cam_off = PI; p.snap_camera()
	for a in OS.get_cmdline_user_args():                    # --bikelook=... shots: close the story's opening call first
		if a.begins_with("--bikelook="): await get_tree().create_timer(.5).timeout; await _dev_clear(_hud)
	if "--bike" in OS.get_cmdline_user_args():
		p.global_position = Vector3(-20, .05, -10); p._get_on()
		Input.action_press("move_forward")
		if "--turn" in OS.get_cmdline_user_args(): Input.action_press("move_left")
		if "--side" in OS.get_cmdline_user_args(): p.cam_off = PI / 2
		p.snap_camera()
	elif walk:
		if "--close" in OS.get_cmdline_user_args():      # --close: close-ups instead (<path>_<view>_<stand|run>.png)
			await _dev_closeups(p, path.get_basename()); get_tree().quit(); return
		Input.action_press("move_forward")
	if "--hit" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.3).timeout
		p._attack()
		await get_tree().create_timer(.18).timeout
	else: await get_tree().create_timer(1.6).timeout
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--inv") and InventoryUI.me:       # --inv / --inv=gear|bag|cards|nazar|quests|stats : the I bag open
			InventoryUI.me.open(a.substr(6) if a.length() > 6 else "")
			await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

# dev only (--shot=PATH --walk --close [--clear]): her from the front, side and back, standing then running
func _dev_closeups(p: Node3D, base: String) -> void:
	var c := Camera3D.new(); c.fov = 40; p.add_child(c); c.make_current()
	for run in [false, true]:
		if run: Input.action_press("move_forward")
		await get_tree().create_timer(1.2 if run else .6).timeout
		for v in [["front", Vector3(0, 1.3, -4.4)], ["side", Vector3(4.4, 1.3, 0)], ["back", Vector3(0, 1.5, 4.4)]]:
			c.position = v[1]; c.look_at(p.to_global(Vector3(0, 1.15, 0)))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			print("CLOSEUP ", v[0], " run=", run, " braid=", p.pose._br_a if p.pose else null)
			get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [base, v[0], "run" if run else "stand"])

func _inputs() -> void:
	# 7.2's keys: A/D strafe, the arrows ←/→ TURN her (and steer the bike like A/D), ↑/↓ walk like W/S
	var map := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A], "move_right": [KEY_D],
		"turn_left": [KEY_LEFT], "turn_right": [KEY_RIGHT], "sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E],
		"attack": [KEY_F], "weapon": [KEY_Q], "look_back": [KEY_C],
		# the new moves (8.0): Left Ctrl dodge roll, hold Z block (early = parry), Tab lock-on. RIGHT mouse
		# (heavy) is read straight from the mouse by player.gd; the other keys belong to their systems:
		# R/1..0 Skills, I/J InventoryUI, H Items, M/V Audio, P/X/G Menus, T Missions/Quests, K Lessons
		"roll": [KEY_CTRL], "block": [KEY_Z], "lock_on": [KEY_TAB]}
	for a in map:
		if not InputMap.has_action(a): InputMap.add_action(a)
		for k in map[a]:
			var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(a, e)

var env: Environment                 # the world's Environment and moon light (SkyCycle takes them over)
var moon: DirectionalLight3D
func _build_world(w: Node3D) -> void:
	# blue-hour night, like 7.1: deep blue sky, haze swallowing the far side
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(.07, .09, .22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.32, .36, .55); env.ambient_light_energy = .9
	env.fog_enabled = true; env.fog_light_color = Color(.12, .15, .3); env.fog_density = .025
	var we := WorldEnvironment.new(); we.environment = env; w.add_child(we)
	moon = DirectionalLight3D.new(); moon.light_color = Color(.6, .68, 1); moon.light_energy = .55
	moon.rotation = Vector3(-.9, .6, 0); w.add_child(moon)
	# the real Neo Antalya: the static world exported from the 7.2 game with its 7.1 PS1 textures
	# (tools/city/merge_city.py), cut into 60 m chunks; every chunk is solid ground/walls for her
	var city: Node3D = load("res://assets/city/city.glb").instantiate()
	w.add_child(city)
	# the scenery that moves on its own (club neon, ferry, windmill, gods' coins, water): lifted out of the frozen
	# chunks before they become colliders
	var amb := Ambient.new(); amb.name = "Ambient"; add_child(amb); amb.setup(w, city)
	_solidify(city)
	Tint.apply(city)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/city_data.json"))
	if data:
		for lp in data["lampPosts"]:
			_lamp(w, Vector3(lp[0], lp[1], lp[2]))
		spawn = Vector3(data["spawn"][0], data["spawn"][1] + .05, data["spawn"][2])
	_checkpoints(w)

func _solidify(n: Node) -> void:
	if n is MeshInstance3D: _collide(n)
	for c in n.get_children(): _solidify(c)

# Only opaque surfaces are solid. See-through ones (the lamps' haze cones and light pools, neon signs, shop
# glass, puddles) are walk-through like in 7.2. The sea and the river are recorded as water areas, which stop
# her at the shore (player.gd) — so the river is crossed on Tower Bridge, as in 7.2.
var water_rects: Array = []          # [x0, x1, z0, z1, surface y]
# 7.2 only had flat colliders, so some of its scenery was walked straight through. These blocks stay
# walk-through here too: Tower Bridge's two stone tower bases sit right across the deck (7.2: BoxGeometry
# 5 x 7 x deckW+4 at x -200 / -228), and solid they'd wall the bridge off.
const WALK_THROUGH := [AABB(Vector3(-202.6, -.2, -7.6), Vector3(5.2, 7.4, 15.2)),
	AABB(Vector3(-230.6, -.2, -7.6), Vector3(5.2, 7.4, 15.2))]
func _collide(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if not mesh: return
	var solid := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_arrays(s)
		var mat := mi.get_active_material(s)
		if mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			if _is_water(mat, src[Mesh.ARRAY_VERTEX]):
				var lo := Vector3.INF; var hi := -Vector3.INF
				for v in src[Mesh.ARRAY_VERTEX]:
					var wv: Vector3 = mi.global_transform * v; lo = lo.min(wv); hi = hi.max(wv)
				water_rects.append([lo.x, hi.x, lo.z, hi.z, hi.y])
			continue
		var a := []; a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = src[Mesh.ARRAY_VERTEX]; a[Mesh.ARRAY_INDEX] = _drop_walk_through(mi, src)
		if (a[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty() and not (src[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): continue
		solid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if solid.get_surface_count() == 0: return
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); cs.shape = solid.create_trimesh_shape(); body.add_child(cs); mi.add_child(body)

# the surface's triangles minus any that lie entirely inside a WALK_THROUGH block
func _drop_walk_through(mi: MeshInstance3D, src: Array) -> PackedInt32Array:
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	if idx.is_empty(): return idx
	var box := mi.global_transform * mi.get_aabb()
	var near := WALK_THROUGH.filter(func(b): return b.intersects(box))
	if near.is_empty(): return idx
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	var keep := PackedInt32Array()
	for i in range(0, idx.size(), 3):
		var a := xf * verts[idx[i]]; var b := xf * verts[idx[i + 1]]; var c := xf * verts[idx[i + 2]]
		var inside := false
		for w in near:
			if w.has_point(a) and w.has_point(b) and w.has_point(c): inside = true; break
		if not inside: keep.append(idx[i]); keep.append(idx[i + 1]); keep.append(idx[i + 2])
	return keep

# the sea and the river: big flat see-through blue surfaces (the exported 7.2 water planes)
func _is_water(mat: BaseMaterial3D, verts: PackedVector3Array) -> bool:
	if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: return false
	var c := mat.albedo_color
	if c.b < c.r + .3 or verts.is_empty(): return false
	var lo := Vector3.INF; var hi := -Vector3.INF
	for v in verts: lo = lo.min(v); hi = hi.max(v)
	var size := hi - lo
	return size.y < .5 and size.x * size.z > 400.0

func _checkpoints(w: Node3D) -> void:
	var pm := StandardMaterial3D.new(); pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(.48, .97, 1, .3); pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; rm.albedo_color = Color("7bf7ff")
	for cp in CHECKPOINTS:
		var g := Node3D.new(); g.position = Vector3(cp[0], 0, cp[1]); w.add_child(g)
		var cm := CylinderMesh.new(); cm.top_radius = .7; cm.bottom_radius = .9; cm.height = 5; cm.cap_top = false; cm.cap_bottom = false
		var pil := MeshInstance3D.new(); pil.mesh = cm; pil.material_override = pm; pil.position.y = 2.5; g.add_child(pil)
		var tm := TorusMesh.new(); tm.inner_radius = 1.02; tm.outer_radius = 1.18
		var ring := MeshInstance3D.new(); ring.mesh = tm; ring.material_override = rm; ring.position.y = .15; g.add_child(ring)
		checkpoints.append({"g": g, "x": float(cp[0]), "z": float(cp[1]), "name": cp[2], "cd": 0.0})

# 7.2's updateCheckpoints(): full HP, a save, her new wake-up spot, a word or two
func _checkpoint_tick(dt: float) -> void:
	if not torii or not _hud or Overlay.any() or torii.dead: return
	for c in checkpoints:
		c["cd"] -= dt; c["g"].rotation.y += dt
		var dx: float = c["x"] - torii.global_position.x
		var dz: float = c["z"] - torii.global_position.z
		if dx * dx + dz * dz < 5.0 and c["cd"] <= 0:
			c["cd"] = 30.0
			SaveBridge.data["resp"] = {"x": c["x"], "z": c["z"]}
			torii.heal_full()
			if Fx.me:
				Fx.me.flash("heal"); Fx.me.puff(Vector3(c["x"], 2, c["z"]), Color("7bf7ff"), 12, 1.6, 2.6, .9)
			_hud.toast("📍 [b]CHECKPOINT[/b] · %s · HP restored · game saved 💾" % c["name"])
			var nm: String = c["name"]
			if nm.contains("EV"): _lessons.teach("ev")
			if nm.contains("PLAJ"): _lessons.teach("plaj"); _lessons.teach("deniz")
			if nm.contains("MARKET"): _lessons.teach("market")
			SaveBridge.write()

func _lamp(w: Node3D, at: Vector3) -> void:
	var l := OmniLight3D.new(); l.light_color = Color(1, .62, .28); l.light_energy = 2.2; l.omni_range = 9
	l.position = at + Vector3(0, 4.0, 0); l.visible = false; w.add_child(l); lamps.append(l)

func _process(dt: float) -> void:
	_checkpoint_tick(dt)
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
	for i in mini(LAMP_MAX, near.size()): on[near[i]] = true
	for l in lamps: l.visible = on.has(l)
