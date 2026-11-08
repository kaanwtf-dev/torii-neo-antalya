# The story: all 20 of Kaan's missions from 7.2 (assets/missions/missions.json, made by
# tools/missions/convert_missions.py), with 7.2's step types: goto, collect, kill (any kill of the step's
# monster counts, waves keep coming until it's done), return, zone (stay in the area; some make her dance),
# deliver (beat the clock; late / squished told mid-run), travel (fly to Cameroon / Arizona / Livermore and
# back), boss (an intro shot, phases with a rev + shake + flash + burst), god (heads-or-tails at a shrine),
# choice (answer in Turkish) and photo (T photographs what's on screen; the ghosts fight back).
# 7.2 names: startMission / playCall / advanceStep / updateMission / missionComplete / STEP.deliver /
# STEP.photo / STEP.choice / takePhoto / checkPhases / godFlip / startGate / gateComplete / proceedTo /
# advanceUnit / finishGame. Each mission opens with Kaan's call (a Cutscene), ends with XP, its phrase, its
# rewards, sometimes a MEANWHILE at Hellspace scene — then a HUNT GATE (clear N monsters) and, when the next
# mission is in a new book unit, that unit's lessons first. The last one rolls the credits.
# The trickster gods' shrines (GODS / godFlip) work any time, not just in mission 14: 40₺ a flip.
# The gold beam + spinning marker + the arrow over her head point at the target (7.2 marker / navG).
# Bus: emits mission_start {i}, mission_done {i}; listens to enemy_died (kill steps + the hunt gate).
# Save fields like 7.2: next, mid, gate, unit, ul, weap, dur, mh, mm, lira, npc (god_<id>, met_<id>),
# gods, bassD, done. Nothing new.
class_name Missions
extends Node

static var me: Missions
var D := {}
var M: Array = []
var GODS: Array = []
var world: Node3D
var torii: CharacterBody3D
var hud: Hud
var lessons: Lessons
var beam: MeshInstance3D
var marker: Node3D                   # the spinning diamond on the target
var arrow: Node3D                    # the arrow over her head

var began := false                   # Menus' CONTINUE / NEW GAME (or a dev run) starts the story
var counts_all_kills := true         # hotspots.gd / shops.gd: we count every kill ourselves (7.2 killEnemy)
var idx := -1
var m := {}
var step := -1
var count := 0
var zone_t := 0.0
var kills_left := 0
var extra := 0
var mobs: Array = []                 # this step's live monsters
var pickups: Array = []              # [{node, item}]
var deliver := {}
var boss: Enemy
var shots := 0
var photo := {}                      # {shot: [enemies], icons: {enemy: Label3D}}
var photo_ghosts: Array = []         # (old name, kept for anything that reads it)
var choice_open := false
var choice_order: Array = []         # the shuffled order the current choice shows its answers in
var gate := {}
var gate_mobs: Array = []
var waiting_lessons := -1            # next mission index waiting for this unit's lessons
var _auto := false                   # dev --autoplay: the gods always lose, nothing costs lira
var _t := 0.0
var _gnd_t := 0.0
var _gnd_y := 0.0
var _god_busy := false
var _gates_done := 0
var _stink: Node3D                   # the stinky Cruze, hidden while its boss twin is up (mission 6)
var _idle_t := 0.0

func setup(w: Node3D, p: CharacterBody3D, h: Hud, l: Lessons) -> void:
	me = self; world = w; torii = p; hud = h; lessons = l
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))
	M = D["missions"]
	var S = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/story72.json"))
	if S is Dictionary: GODS = S.get("gods", [])
	for a in OS.get_cmdline_user_args(): if a.begins_with("--autoplay="): _auto = true
	_build_nav()
	Bus.on("enemy_died", _on_kill)
	# a hunt that was open when she quit comes back as it was (7.2 applySave); a mission in progress wins
	var mid = SaveBridge.data.get("mid")
	var g = SaveBridge.data.get("gate")
	if (mid == null or str(mid) == "") and g is Dictionary: _resume_gate(g)
	_shrine_signs()
	call_deferred("_auto_begin")

# with no title screen (Menus not wired) or in dev runs the story starts by itself, like it always did
func _auto_begin() -> void:
	if began: return
	if dev_run() or not _has_menus(): begin()

func _has_menus() -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "Menus":
			var o = load(c["path"]).get("me")
			return is_instance_valid(o)
	return false

static func dev_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay=") or a in ["--lessontest", "--fps", "--savecheck", "--godkey", "--fxtest", "--welcome"] or a.begins_with("--shot="): return true
	return false

# carry on where her save says (7.2: `mid` = a mission in progress, `gate` = a hunt, else `next`)
func begin() -> void:
	if began: return
	began = true
	var mid = SaveBridge.data.get("mid")
	if mid != null and str(mid) != "":
		for i in M.size(): if M[i]["id"] == mid: start(i); return
	if not gate.is_empty(): return
	var nxt := SaveBridge.get_i("next", 0)
	if nxt < M.size(): proceed_to(nxt)
	else: hud.toast("🌴 Every mission is done — free play! The tables, the gods and Old Soul are all still open ❤", 7.0)

# ---------------------------------------------------------------- Kaan's calls
# the dialogue box pages with E / Enter / Space and ESC skips the rest. Like 7.2's whenFree() a call never
# opens under a quiz or another box: it waits (up to a minute) for the screen
func phone(who: String, lines: Array, done: Callable) -> void:
	var tries := 0
	while (Overlay.any() or Cutscene.busy()) and tries < 240:
		tries += 1
		await get_tree().create_timer(.25).timeout
	hud.say(who, lines, done)

func _unhandled_input(e: InputEvent) -> void:
	if not began or Overlay.any() or not (e is InputEventKey and e.pressed and not e.echo): return
	if e.keycode == KEY_T:
		if step >= 0 and _st().get("t") == "photo":
			_shutter(); _snap(); get_viewport().set_input_as_handled()
		elif not _quest_photo():
			_shutter()
			hud.toast("📸 [i]Güzel fotoğraf![/i] (nice photo!) — photos only count during a 📸 photo hunt.", 3.0)
			get_viewport().set_input_as_handled()
	elif e.keycode == KEY_E and not Overlay.just_closed():
		var G := _god_near(4.0)
		if not G.is_empty() and not bool(torii.get("on_bike")):
			_god_talk(G); get_viewport().set_input_as_handled()     # (or this same E would close the coin toss it opened)

func _quest_photo() -> bool:
	return Quests.me != null and Quests.me.has_method("cur_step") and str(Quests.me.cur_step().get("t", "")) == "photo"

# what the E line says (Menus shows it): the gods' shrines
func prompt(p: Node3D) -> String:
	if not began or p == null: return ""
	var G := _god_near(4.0)
	if G.is_empty(): return ""
	var npc: Dictionary = _npc()
	return "E: %s %s" % ["say hi to" if npc.get("god_" + str(G["id"])) == "won" else "flip a coin with", str(G["name"]).split(" ·")[0]]

# ---------------------------------------------------------------- missions
func start(i: int) -> void:
	_end_step()
	idx = i; m = M[i]; step = -1; count = 0; extra = 0; pickups = []
	SaveBridge.data["next"] = i; SaveBridge.data["mid"] = m["id"]
	SaveBridge.data["unit"] = maxi(SaveBridge.get_i("unit", 1), int(m["unit"]))
	var mm := m
	var go := func():
		if m != mm: return                                  # something else started meanwhile
		if m.has("start"):
			for w in m["start"].get("teach", []): lessons.teach(w)
		SaveBridge.write()
		hud.banner(m["title"])
		Audio.sfx("ding")
		Bus.emit_ev("mission_start", {"i": i})
		_advance()
	if m.has("intro"):
		if Cutscene.me: Cutscene.me.call_scene(m, i, go)        # 7.2 playCall: a little movie
		else: phone(m["intro"]["name"], m["intro"]["lines"], go)
	else: go.call()

func _st() -> Dictionary:
	if not m.has("steps"): return {}   # no mission running (e.g. after the last one)
	return m["steps"][step] if step >= 0 and step < m["steps"].size() else {}

func _advance() -> void:
	_end_step()
	step += 1; count = 0; zone_t = 0.0
	if step >= m["steps"].size(): _complete(); return
	var st := _st()
	match st["t"]:
		"collect":
			if pickups.is_empty(): _spawn_pickups()
		"kill":
			kills_left = int(st["n"]) + extra
			_wave(st)
			for k in extra:                                   # a late start (the 5 AM tote run) brings extra trouble
				var x := Enemy.spawn(world, str(st["mob"]) if st.get("mob") else "thot",
					Vector3(float(st["x"]) + randf_range(-9, 9), 0, float(st["z"]) + randf_range(-6, 6)), torii)
				mobs.append(x)
			extra = 0
			if st.has("bn"): hud.banner(st["bn"])
			Audio.sfx("groan")
		"deliver": _deliver_start(st)
		"boss": _boss_start(st)
		"travel":
			hud.toast("✈️ [b]Boarding...[/b] " + str(st.get("lab", "")), 4.2)
			_travel(st["zone"]); return
		"photo": _photo_start(st)
		"choice": Tips.tip("choice")
		_: Audio.sfx("ding")
	hud.toast("🎯 " + str(st.get("lab", "")), 5.5)
	SaveBridge.write()

# 7.2's STEP[...].end(): whatever the last step left in the world goes
func _end_step() -> void:
	for ic in (photo.get("icons", {}) as Dictionary).values(): if is_instance_valid(ic): ic.queue_free()
	photo = {}; photo_ghosts = []
	deliver = {}
	choice_open = false

func _spawn_pickups() -> void:
	for p in m.get("pickups", []):
		for k in int(p["n"]):
			var path := "res://assets/pickups/%s.glb" % p["item"]
			if not ResourceLoader.exists(path): continue
			var node: Node3D = load(path).instantiate(); Tint.apply(node); world.add_child(node)
			node.position = Vector3(p["x"][0] + randf_range(p["x"][1], p["x"][2]), .6, p["z"][0] + randf_range(p["z"][1], p["z"][2]))
			pickups.append({"node": node, "item": p["item"]})

func _wave(st: Dictionary) -> void:
	for spec in st.get("mobs", [{"mob": "imp", "n": 3, "x": [st["x"], -8, 8], "z": [st["z"], -8, 8]}]):
		for k in int(spec.get("n", 1)):
			var kind: String = spec["pool"].pick_random() if spec.has("pool") else str(spec.get("mob", "imp"))
			var at := Vector3(spec["x"][0] + randf_range(spec["x"][1], spec["x"][2]), 0, spec["z"][0] + randf_range(spec["z"][1], spec["z"][2]))
			mobs.append(Enemy.spawn(world, kind, at, torii, randf() < float(spec.get("elite", 0))))

# 7.2 killEnemy: ANY kill counts — the step's monster (or anything when the step takes anything), the
# gate's type, roaming monsters and boss adds included
func _on_kill(d: Dictionary) -> void:
	var e = d.get("enemy")
	mobs.erase(e); gate_mobs.erase(e)
	var kind := str(d.get("kind", ""))
	if not gate.is_empty():
		var match_: bool = gate["type"] == null or str(gate["type"]) == kind
		if bool(d.get("elite", false)) and int(gate["eleft"]) > 0: gate["eleft"] = int(gate["eleft"]) - 1
		elif match_ and int(gate["left"]) > 0: gate["left"] = int(gate["left"]) - 1
		SaveBridge.data["gate"] = gate.duplicate()
		if int(gate["left"]) <= 0 and int(gate["eleft"]) <= 0: _gate_done()
	var st := _st()
	if st.get("t") == "kill" and kills_left > 0:
		var want = st.get("mob")
		if want == null or str(want) == kind:
			kills_left -= 1
			if kills_left <= 0: _advance()

# shops.gd's gate_credit lands here: Kaan's bounty mobs are already counted by _on_kill (they die like any
# monster), a won tavla match is a kill of its own
func gate_credit(elite := false, why := "") -> int:
	if gate.is_empty(): return -1
	if why not in ["kaan", "bounty"]:
		if elite and int(gate["eleft"]) > 0: gate["eleft"] = int(gate["eleft"]) - 1
		elif int(gate["left"]) > 0: gate["left"] = int(gate["left"]) - 1
		elif int(gate["eleft"]) > 0: gate["eleft"] = int(gate["eleft"]) - 1
		SaveBridge.data["gate"] = gate.duplicate()
	var left := maxi(0, int(gate["left"])) + maxi(0, int(gate["eleft"]))
	if left <= 0: _gate_done()
	return left

func _near(r: float) -> bool:
	var st := _st()
	return Vector2(torii.global_position.x - st["x"], torii.global_position.z - st["z"]).length() < r

func _process(dt: float) -> void:
	if not began: return
	_t += dt
	_gate_tick()
	_nav(dt)
	_watch_boss()
	if waiting_lessons >= 0 and not lessons.active and not Overlay.any():
		if SaveBridge.get_i("ul") >= lessons.unit_lessons(lessons.unit()).size():
			var nx := waiting_lessons; waiting_lessons = -1; _advance_unit(nx)
		elif not lessons.pend: lessons.pend = true
	if step < 0 or m.is_empty():
		_idle_t -= dt
		if gate.is_empty() and _idle_t <= 0:
			_idle_t = 1.0
			hud.objective(_idle_text())
		return
	if Overlay.any(): return      # calls, quizzes and choices pause the clock
	var st := _st()
	if st.is_empty(): return
	var here := torii.global_position
	for p in pickups.duplicate():
		if not is_instance_valid(p["node"]): pickups.erase(p); continue
		p["node"].rotation.y += dt * 2.0
		if st["t"] == "collect" and p["item"] == st["item"] and p["node"].global_position.distance_to(here) < 1.8:
			p["node"].queue_free(); pickups.erase(p); count += 1
			Audio.sfx("pickup")
			if Items.me: Items.me.effect(str(p["item"]))          # 7.2 collect(): its word / XP / heal (PRG-15)
			Bus.emit_ev("pickup", {"id": str(p["item"]), "kind": "mission", "pos": here})
			hud.toast("%s %d/%d" % [p["item"], count, int(st["n"])], 1.4)
			if count >= int(st["n"]): _advance(); return
	var d := 0.0
	if st.has("x"): d = Vector2(here.x - st["x"], here.z - st["z"]).length()
	var info := ""
	var counts := ""
	match st["t"]:
		"goto":
			info = "📍 %dm" % d
			if d < 6.0: _advance(); return
		"return":
			info = "📍 %dm" % d
			if d < 4.5: _complete(); return
		"collect": counts = " · %d/%d" % [count, int(st["n"])]; info = "📍 %dm" % d
		"zone":
			if d < float(st["r"]):
				zone_t += dt
				if st.get("dance", false): torii.dance_t = .4
				info = "⏳ %ds" % ceili(maxf(0.0, float(st["dur"]) - zone_t))
				if zone_t >= float(st["dur"]): _advance(); return
			else: info = "📍 %dm · get in the area!" % d
		"kill":
			counts = " · %d left" % kills_left
			info = "⚔️ %d to go" % kills_left
			mobs = mobs.filter(func(e): return is_instance_valid(e) and e.is_alive())
			if mobs.is_empty() and kills_left > 0: _wave(st)          # 7.2 keeps them coming until the count is done
		"boss": info = "💀 BOSS HP: %d" % (maxi(0, ceili(boss.hp)) if is_instance_valid(boss) else 0)
		"deliver":
			info = _deliver_tick(dt, st)
			if deliver.is_empty(): return
		"god":
			var won: bool = _npc().get("god_" + str(st["id"])) == "won"
			info = "✅" if won else "🪙 %dm · press E at the shrine" % d
			if won and not _god_busy and not Overlay.any(): _advance(); return
		"choice":
			info = "📍 %dm" % d
			if d < 6.0 and not choice_open: _choice(st)
		"photo":
			_photo_tick(dt, st)
			info = "📸 %d/%d · press T when it's on screen" % [shots, int(st["n"])]
		"travel": info = "✈️"
	hud.objective("[color=#ff5fa2][b][color=#8ff2ff]📖 UNIT %d/16[/color] · %s[/b][/color]\n[color=#f2e8ff]%s%s[/color]\n[color=#ffd66b]%s[/color]" %
		[int(m["unit"]), m["title"], st.get("lab", ""), counts, info])

# ---------------------------------------------------------------- the marker + arrow (7.2 marker / navG)
func _build_nav() -> void:
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = .5; cm.bottom_radius = .5; cm.height = 60
	var mat := _unlit(Color(1, .85, .3, .35), true)
	cm.material = mat; beam.mesh = cm; beam.visible = false; world.add_child(beam)
	marker = Node3D.new(); marker.name = "MissionMarker"; marker.visible = false; world.add_child(marker)
	for s in [1.0, -1.0]:
		var c := MeshInstance3D.new(); var cn := CylinderMesh.new()
		cn.top_radius = 0.0; cn.bottom_radius = .55; cn.height = .8; cn.radial_segments = 4; cn.rings = 1
		c.mesh = cn; c.material_override = _unlit(Color("ffd66b")); c.position.y = .4 * s
		if s < 0: c.rotation.x = PI
		marker.add_child(c)
	arrow = Node3D.new(); arrow.name = "NavArrow"; arrow.visible = false; world.add_child(arrow)
	var pm := PrismMesh.new(); pm.size = Vector3(.62, .9, .14)
	var a := MeshInstance3D.new(); a.mesh = pm; a.material_override = _unlit(Color("ffd66b"))
	a.rotation.x = PI / 2; a.position.z = .2; arrow.add_child(a)       # the prism's tip points +z

func _unlit(c: Color, alpha := false) -> StandardMaterial3D:
	var m2 := StandardMaterial3D.new(); m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m2.albedo_color = c
	if alpha: m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m2

# where the marker goes: the step's spot, the boss, the drop-off, the next thing to photograph
func _target() -> Variant:
	if step < 0 or m.is_empty(): return null
	var st := _st()
	match str(st.get("t", "")):
		"", "travel": return null
		"boss": return boss.global_position if is_instance_valid(boss) else null
		"deliver":
			var to: Array = st["to"]
			return Vector3(float(to[0]), 0, float(to[1]))
		"photo":
			var t := _photo_targets(st)
			if t.size(): return (t[0] as Node3D).global_position
	if st.has("x"): return Vector3(float(st["x"]), 0, float(st["z"]))
	return null

func _nav(dt: float) -> void:
	var tg = _target()
	var on: bool = tg is Vector3 and not Cutscene.busy()
	beam.visible = tg is Vector3
	marker.visible = on; arrow.visible = false
	if not (tg is Vector3): return
	var t3: Vector3 = tg
	beam.global_position = Vector3(t3.x, 30, t3.z)
	_gnd_t -= dt
	if _gnd_t <= 0:
		_gnd_t = .5
		var q := PhysicsRayQueryParameters3D.create(Vector3(t3.x, t3.y + 40, t3.z), Vector3(t3.x, t3.y - 30, t3.z)); q.collision_mask = 1
		var h := world.get_world_3d().direct_space_state.intersect_ray(q)
		_gnd_y = h["position"].y if h else t3.y
	marker.global_position = Vector3(t3.x, _gnd_y + 3.0 + sin(_t * 3.0) * .35, t3.z)
	marker.rotation.y += dt * 1.8
	var here := torii.global_position
	var flat := Vector2(t3.x - here.x, t3.z - here.z)
	arrow.visible = on and flat.length() > 8.0 and not bool(torii.get("dead"))
	arrow.global_position = here + Vector3(0, 3.4 + sin(_t * 4.0) * .15, 0)
	arrow.rotation = Vector3(0, atan2(flat.x, flat.y), 0)

# ---------------------------------------------------------------- bosses
func _boss_start(st: Dictionary) -> void:
	if str(st["boss"]) == "cruze": _hide_stink(true)
	boss = Enemy.spawn(world, st["boss"], Vector3(st["x"], 0, st["z"]), torii)
	boss.set_phases(st.get("phases", []))
	var b := boss
	boss.died.connect(func(_e):
		if boss == b: boss = null
		for x in st.get("after", []): hud.banner(x)
		if str(st["boss"]) == "cruze": _hide_stink(false)
		if _st() == st: _advance())
	var bn := str(st.get("bn", "⚔️ BOSS!"))
	hud.banner(bn)
	var snd := str((D["enemies"].get(st["boss"], {}) as Dictionary).get("snd", "growl"))
	Audio.sfx(snd)
	if Cutscene.me: Cutscene.me.boss_intro(boss, bn, str(st.get("lab", "")), snd)

# 7.2 checkPhases' feedback: enemy.gd flips the phase and runs its ops, this adds the rev, the shake, the
# red flash and the burst, the phases tip — and Karen's meeting comes early (7.2 e.sumT = 3)
func _watch_boss() -> void:
	if not is_instance_valid(boss): return
	for p in boss.phases:
		if not (p is Dictionary) or not p.get("done", false) or p.get("_fx", false): continue
		p["_fx"] = true
		var at := boss.global_position + Vector3(0, 1.6, 0)
		Audio.sfx("rev", at)
		if Fx.me:
			Fx.me.shake(.5); Fx.me.flash_screen(Color(1, .18, .18), .4, .35)
			Fx.me.burst(at, [Color("ff2d2d"), Color("ffd66b"), Color("b06bff")], 26, 6.0, 8.0, 1.1)
		Tips.tip("phases")
		if boss.type == "karen": boss.sum_t = minf(boss.sum_t, 3.0)

# mission 6: the parked stinky Cruze goes while the boss Cruze is up, and comes back washed (7.2 cruzeClean)
func _hide_stink(hide: bool) -> void:
	var sp = Spawner.me
	if hide:
		if sp and is_instance_valid(sp.stink):
			_stink = sp.stink; sp.stink = null; _stink.visible = false
		return
	if not is_instance_valid(_stink): return
	_stink.position = Vector3(-52, _stink.position.y, -7); _stink.visible = true
	if Fx.me: Fx.me.puff(_stink.global_position + Vector3(0, 1.2, 0), Color("9fe8ff"), 18, 2.2, 2.6, 1.0)
	hud.banner("✨ SPARKLING CLEAN!")
	_stink = null                     # washed: no more smell this session

# ---------------------------------------------------------------- deliveries (7.2 STEP.deliver)
func _deliver_start(st: Dictionary) -> void:
	var to: Array = st["to"]
	var dist := torii.global_position.distance_to(Vector3(to[0], 0, to[1]))
	deliver = {"t": 0.0, "limit": float(st["time"][0]) + dist / float(st["time"][1]), "broken": false, "late": false,
		"wipe": str(torii.get("wipe")) != ""}
	hud.banner("📦 " + str(st.get("bn", "KURYE · DELIVERY")))
	lessons.teach("kurye"); lessons.teach("acele et!")
	Tips.tip("deliver")
	hud.toast("⏱ [b]%d seconds.[/b] [i]Acele et![/i] (hurry!)%s" % [int(deliver["limit"]),
		" · [b]fragile[/b] — don't crash!" if st.get("fragile", false) else ""], 4.2)

func _deliver_tick(dt: float, st: Dictionary) -> String:
	deliver["t"] += dt
	var to: Array = st["to"]
	var here := torii.global_position
	var dd := Vector2(here.x - to[0], here.z - to[1]).length()
	# fragile: a bike wipe-out squishes it (7.2 S.wipePhase), right when it happens
	var wiping := str(torii.get("wipe")) != ""
	if st.get("fragile", false) and not deliver["broken"] and wiping and not deliver["wipe"]:
		deliver["broken"] = true; Audio.sfx("no")
		hud.toast("💥 [b]%s[/b]" % st.get("brokeMsg", "It broke!"), 5.0, true)
	deliver["wipe"] = wiping
	if not deliver["late"] and deliver["t"] > deliver["limit"]:
		deliver["late"] = true; Audio.sfx("no")
		hud.toast("⏱ [b]%s[/b] — get it there anyway." % st.get("lateMsg", "Too late for the bonus"), 5.0, true)
	if dd < 4.5: _deliver_done(st); return ""
	return "📦 %s%s · 📍 %dm" % ["late" if deliver["late"] else "⏱ %.1fs" % maxf(0.0, deliver["limit"] - deliver["t"]),
		" · 💥" if deliver["broken"] else "", dd]

func _deliver_done(st: Dictionary) -> void:
	var fast: bool = not deliver["late"] and not deliver["broken"]
	var e: Dictionary = st.get("fast", {}) if fast else st.get("late", {})
	if fast:
		hud.banner("📦 TESLİM! · DELIVERED! %.1fs" % float(deliver["t"])); Audio.sfx("fanfare")
	elif e.is_empty() and m.get("id") == "bday":
		hud.toast("🍯 The baklava is a little squished. He will love it anyway." if deliver["broken"] else "🎂 A little late — he pretended not to notice.", 6.5)
	deliver = {}
	_effects(e)
	if e.has("extra"): extra = int(e["extra"])
	if _st() == st:
		if step >= m["steps"].size() - 1: _complete()
		else: _advance()

# 7.2's travelTo(): the screen goes dark for the flight, then she's there
func _travel(zone: String) -> void:
	var sp: Dictionary = D["zspawn"][zone]
	if torii.on_bike: torii._get_off()
	if Fx.me: Fx.me.dark(.96, .45, true)
	await get_tree().create_timer(.9).timeout
	hud.banner("🛬 WELCOME HOME" if zone == "city" else "🛫 " + str(D["zname"].get(zone, zone)))
	torii.global_position = Vector3(sp["x"], 1.0, sp["z"])
	torii.yaw = PI if zone == "city" else -PI / 2
	torii.snap_camera()
	if zone != "city": lessons.teach("uçak"); lessons.teach("havalimanı")
	if Fx.me: Fx.me.dark(0.0, .8)
	await get_tree().create_timer(1.0).timeout
	_advance()

# 7.2's STEP.choice: the answers in a new random order every time; the person answers in the dialogue box;
# right = +20 XP and on, wrong = "try again", closed with E = asked again in 4 seconds
func _choice(st: Dictionary) -> void:
	choice_open = true
	choice_order = range(st["opts"].size()); choice_order.shuffle()
	var opts: Array = choice_order.map(func(i): return "%s%s" % [st["opts"][i]["t"],
		(" (%s)" % st["opts"][i]["en"]) if str(st["opts"][i].get("en", "")) != "" else ""])
	var who: String = st.get("who", "")
	hud.choose(who, str(st.get("q", "")) + ("\n[i]%s[/i]" % st["hint"] if st.has("hint") else ""), opts, func(k):
		if k < 0:
			await get_tree().create_timer(4.0).timeout
			choice_open = false; return
		var o: Dictionary = st["opts"][choice_order[k]]
		var r: String = str(o.get("r", ""))
		if o.get("ok", false):
			Audio.sfx("yes")
			hud.say(who, [r if r != "" else "Aferin! 👏 [i](Well done!)[/i]"], func():
				lessons.xp(20)
				if _st() == st: _advance())
		else:
			Audio.sfx("no")
			hud.say(who, [(r if r != "" else "Hmm... olmadı. [i](That's not it.)[/i]") + " — try again."], func(): choice_open = false))

# ---------------------------------------------------------------- the trickster gods (GODS / godFlip)
func _npc() -> Dictionary:
	if not (SaveBridge.data.get("npc") is Dictionary): SaveBridge.data["npc"] = {}
	return SaveBridge.data["npc"]

func _god_near(r: float) -> Dictionary:
	if torii == null: return {}
	for G in GODS:
		if Vector2(torii.global_position.x - float(G["x"]), torii.global_position.z - float(G["z"])).length() < r: return G
	return {}

func _god_of(id: String) -> Dictionary:
	for G in GODS: if str(G["id"]) == id: return G
	return {"id": id, "name": id.to_upper() + " 🪙", "greet": []}

# the mission's god step (and dev autoplay) go through the same shrine talk
func _god() -> void:
	var st := _st()
	if st.get("t") == "god": _god_talk(_god_of(str(st["id"])))

func _god_talk(G: Dictionary) -> void:
	if _god_busy: return
	var npc := _npc()
	var id := str(G["id"])
	if not npc.has("met_" + id) and (G.get("greet", []) as Array).size():
		npc["met_" + id] = 1; SaveBridge.write()
		hud.say(str(G["name"]), G["greet"], func(): _god_flip(G))
		return
	_god_flip(G)

func _has_buff(id: String) -> bool:
	if Skills.me: return Skills.me.has_buff(id)
	return Items.me != null and Items.me.has_buff(id)

func _god_flip(G: Dictionary) -> void:
	var npc := _npc()
	var id := str(G["id"])
	var nm := str(G["name"])
	if npc.get("god_" + id) == "won":
		hud.say(nm, ["You already beat me, mortal. Take your [i]şans[/i] and go. 🪙"]); return
	var lucky := _has_buff("lucky")
	hud.choose(nm, "[b]Yazı mı, tura mı?[/b] [i](Heads or tails?)[/i]\nStake: [b]40₺[/b] — you have %d₺%s" % [SaveBridge.get_i("lira"),
		"\n[color=#5fff9e]🎲 The gods favour you right now...[/color]" if lucky else ""],
		["🪙 YAZI (heads)", "🎲 TURA (tails)", "Walk away"], func(i):
			if i < 0 or i >= 2: return
			if SaveBridge.get_i("lira") < 40 and not _auto:
				hud.toast("You need [b]40₺[/b] to challenge a god. Kill monsters for coins 💰", 5.0, true); Audio.sfx("no"); return
			if not _auto: Stats.add_lira(-40)
			Audio.sfx("coinflip")
			lessons.teach("yazı tura"); lessons.teach("şans"); lessons.teach("kader")
			var flip: int = i if (_auto or randf() < (.75 if lucky else .5)) else 1 - i
			var face := "YAZI 🪙" if flip == 0 else "TURA 🎲"
			_god_busy = true
			await get_tree().create_timer(.9).timeout
			_god_busy = false
			if flip == i:
				npc["god_" + id] = "won"; SaveBridge.data["npc"] = npc
				SaveBridge.data["gods"] = SaveBridge.get_i("gods") + 1
				hud.banner("🪙 %s — YOU WIN!\n[font_size=16]The god is amused[/font_size]" % face)
				Audio.sfx("divine"); Audio.sfx("fanfare"); torii.dance_t = 2.0
				Stats.add_lira(120); lessons.xp(60)
				if Skills.me: Skills.me.add_buff("lucky")
				elif Items.me: Items.me.add_buff("lucky")
				hud.say(nm, ["[b]%s[/b]. Hah! The mortal calls it correctly. 😤" % face,
					"Take 120₺ and my favour. [i]Şansın açık olsun[/i] — may your luck be open."])
				SaveBridge.write()
			else:
				hud.banner("🪙 %s — you lose\n[font_size=16]The gods laugh[/font_size]" % face); Audio.sfx("no")
				torii.hp = maxi(1, int(torii.hp) - 12); torii.emit_signal("hp_changed", torii.hp, torii.max_hp)    # never faints her
				if Fx.me: Fx.me.flash_screen(Color(1, .2, .3), .35, .3)
				hud.say(nm, ["[b]%s[/b]. Wrong. 😈" % face, "Fate is not a friend, Torii. Try again when you have more coin."]))

# the shrines are baked into city.glb (frozen); a name sign over each so she can find them
func _shrine_signs() -> void:
	await get_tree().physics_frame; await get_tree().physics_frame
	for G in GODS:
		var x := float(G["x"]); var z := float(G["z"])
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z)); q.collision_mask = 1
		var h := world.get_world_3d().direct_space_state.intersect_ray(q)
		var l := Label3D.new(); l.text = "🪙 " + str(G["name"]).split(" ·")[0]
		l.modulate = Color(str(G.get("col", "#ffd66b"))); l.font_size = 64; l.pixel_size = .02; l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.shaded = false; l.no_depth_test = false
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		world.add_child(l); l.global_position = Vector3(x, (h["position"].y if h else 0.0) + 5.4, z)

# ---------------------------------------------------------------- photo hunts (7.2 STEP.photo / takePhoto)
func _photo_start(st: Dictionary) -> void:
	shots = 0; photo = {"shot": [], "icons": {}}
	var kind := str(st.get("mob", "ghost"))
	for k in int(st["n"]):
		_photo_spawn(st, kind, randf_range(6, 14))
	hud.banner("📸 %s · press T" % st.get("bn", "FOTOĞRAF AVI · PHOTO HUNT"))
	lessons.teach("fotoğraf çekmek")
	Tips.tip("photo")

func _photo_spawn(st: Dictionary, kind: String, r: float) -> void:
	var a := randf() * TAU
	var c := Vector3(float(st.get("x", torii.global_position.x)), 0, float(st.get("z", torii.global_position.z)))
	photo_ghosts.append(Enemy.spawn(world, kind, c + Vector3(cos(a) * r, 0, sin(a) * r), torii))

func _photo_targets(st: Dictionary) -> Array:
	var kind := str(st.get("mob", "ghost"))
	var shot: Array = photo.get("shot", [])
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.type == kind and e.is_alive() and not shot.has(e): out.append(e)
	var here := torii.global_position
	out.sort_custom(func(a, b): return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	return out

func _photo_tick(dt: float, st: Dictionary) -> void:
	if photo.is_empty(): return
	var left := _photo_targets(st)
	# keep enough of them around (7.2: topped up as she shoots them)
	if left.size() < int(st["n"]) - shots and randf() < dt * .6: _photo_spawn(st, str(st.get("mob", "ghost")), 18.0)
	var icons: Dictionary = photo["icons"]
	for e in icons.keys():
		if not is_instance_valid(e) or not left.has(e):
			if is_instance_valid(icons[e]): icons[e].queue_free()
			icons.erase(e)
	for e in left:
		if not icons.has(e):
			var l := Label3D.new(); l.text = "📸"; l.font_size = 72; l.pixel_size = .012; l.outline_size = 8
			l.modulate = Color("ffd66b"); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.shaded = false
			world.add_child(l); icons[e] = l
		(icons[e] as Label3D).global_position = (e as Node3D).global_position + Vector3(0, 3.0 + sin(_t * 3.0) * .15, 0)

func _shutter() -> void:
	Audio.sfx("photo"); Audio.sfx("clack")
	if Fx.me: Fx.me.flash_screen(Color.WHITE, .7, .22)

# a shot counts when it's on screen (inside 85% of it) and within range of the camera
func _snap() -> void:
	var st := _st()
	if photo.is_empty(): return
	var cam: Camera3D = torii.cam if torii.get("cam") is Camera3D else get_viewport().get_camera_3d()
	if cam == null: return
	var vs := cam.get_viewport().get_visible_rect().size
	var got := 0
	for e in _photo_targets(st):
		var p: Vector3 = (e as Node3D).global_position + Vector3(0, 1.4, 0)
		if Vector2(p.x - cam.global_position.x, p.z - cam.global_position.z).length() > float(st.get("range", 45)): continue
		if cam.is_position_behind(p): continue
		var sp := cam.unproject_position(p)
		var nx := sp.x / vs.x * 2.0 - 1.0; var ny := sp.y / vs.y * 2.0 - 1.0
		if absf(nx) > .85 or absf(ny) > .85: continue
		(photo["shot"] as Array).append(e); shots += 1; got += 1
		var nm := str((D["enemies"].get(e.type, {}) as Dictionary).get("name", "📸"))
		hud.toast("📸 [b]Çek![/b] %s (%d/%d)" % [nm, mini(shots, int(st["n"])), int(st["n"])], 3.2)
		if shots >= int(st["n"]): break
	if got == 0: hud.toast("📸 Nothing in the shot — get it on screen and a bit closer, then press [b]T[/b].", 3.2)
	if shots >= int(st["n"]):
		hud.banner("📸 TAMAM!\n[font_size=16]%s[/font_size]" % st.get("done", "Great shots")); Audio.sfx("fanfare")
		_advance()

# ---------------------------------------------------------------- rewards
func _effects(e: Dictionary) -> void:
	if e.has("xp"): lessons.xp(int(e["xp"]))
	if e.has("lira"): Stats.add_lira(int(e["lira"]))
	if e.has("mh"):
		SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + int(e["mh"])
		Stats.apply(torii)
		torii.max_hp = maxi(int(torii.max_hp), SaveBridge.get_i("mh", 100)); torii.heal_full()
	if e.has("mm"):
		SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + int(e["mm"])
		Stats.apply(torii)
		torii.add_mana(9999.0)
	for w in e.get("weapons", []):
		if Arsenal.me: Arsenal.me.give_weapon(str(w))            # full durability, equips the best, toasts the stats
		else:
			var weap: Array = SaveBridge.data.get("weap", [])
			var dur: Dictionary = SaveBridge.data.get("dur", {})
			if not weap.has(w): weap.append(w)
			var ws: Dictionary = D["weapons"].get(w, {})
			var dv = ws.get("dur", 40)
			dur[w] = 9999 if (dv == null or str(dv) == "inf" or float(dv) > 9999) else dv
			SaveBridge.data["weap"] = weap; SaveBridge.data["dur"] = dur
			hud.toast("🆕 %s — mission reward!" % ws.get("n", w), 5.0)
	for w in e.get("teach", []): lessons.teach(w)
	var msg: String = e.get("msg", "")
	if msg != "" and not msg.begins_with("🆕 [b]"): hud.toast(msg, 7.0)

# the pin between missions: Kaan's waiting, or free play once the last mission is behind her (even when the
# finale's `done` flag never got saved, e.g. she quit during the ending)
func _idle_text(next_i := -1) -> String:
	if next_i < 0: next_i = SaveBridge.get_i("next")
	if SaveBridge.data.get("done") == true or next_i >= M.size():
		return "[color=#5fff9e][b]🌴 FREE PLAY[/b][/color]\n[color=#e8e4f8]The gods, the tables and Old Soul are all open[/color]"
	return "[color=#ff9ecf]Kaan is waiting... ❤[/color]"

func _complete() -> void:
	_end_step()
	beam.visible = false
	for p in pickups: if is_instance_valid(p["node"]): p["node"].queue_free()
	pickups = []
	hud.objective(_idle_text(idx + 1))
	hud.banner("✅ MISSION COMPLETE!\n[font_size=16]+%d XP ❤[/font_size]" % int(m["xp"]))
	# Kaan's "Aferin bebeğim!" over the balcony, confetti, the fanfare (7.2 missionComplete)
	var k: Node3D = Cutscene.me.kaan() if Cutscene.me else null
	if k and Fx.me: Fx.me.label(k.global_position + Vector3(0, 2.4, 0), "Aferin bebeğim! ❤ (Well done, baby!)", Color("ff9ecf"), 5.5, true)
	Audio.speak("Aferin bebeğim")
	Audio.sfx("fanfare"); Audio.sfx("chuckle")
	if Fx.me: Fx.me.burst(torii.global_position + Vector3(0, 1.5, 0), Fx.CONF, 30, 5.0, 6.0, 1.2)
	torii.dance_t = 3.0
	lessons.xp(int(m["xp"]))
	if m.get("phrase"):
		var ph := str(m["phrase"])
		get_tree().create_timer(1.8).timeout.connect(func(): lessons.teach(ph))
	if m.get("id") == "pena":                                 # 7.2: WEAPONS.bass.dmg += 10, saved as bassD
		var bd = SaveBridge.data.get("bassD")
		var base := int(bd) if (bd is float or bd is int) else int(D["weapons"].get("bass", {}).get("dmg", 42))
		SaveBridge.data["bassD"] = base + 10
	_effects(m.get("reward", {}))
	lessons.quiz_pend = true
	var done := idx
	var mid_ := str(m["id"])
	SaveBridge.data["next"] = done + 1; SaveBridge.data["mid"] = null
	step = -1; m = {}
	SaveBridge.write()
	Bus.emit_ev("mission_done", {"i": done})
	if done + 1 < M.size():
		if int(M[done + 1]["unit"]) > lessons.unit():
			hud.toast("⚔️ [b]Son adım:[/b] clear the hunt gate and Unit %d is finished." % lessons.unit(), 7.0)
		# meanwhile, at the top of the tallest tower in the city...
		if Cutscene.has_hell(mid_): get_tree().create_timer(3.6).timeout.connect(func(): Cutscene.me.hell_scene(mid_))
		get_tree().create_timer(5.2).timeout.connect(func():
			if m.is_empty() and gate.is_empty() and SaveBridge.get_i("next") == done + 1: _start_gate(done + 1))
	else:
		await get_tree().create_timer(5.2).timeout
		hud.banner("💖 TORİİ IS FREE!\n[font_size=16]\"Seni seviyorum\" ❤ One step closer to her dreams[/font_size]")
		torii.dance_t = 6.0; Audio.sfx("fanfare"); Audio.sfx("dance")
		if Fx.me: Fx.me.burst(torii.global_position + Vector3(0, 2, 0), Fx.CONF, 40, 6.0, 6.0, 1.4)
		_finish_game()
		await get_tree().create_timer(6.5).timeout
		if Cutscene.me: Cutscene.me.ending()

# 7.2 finishGame: free play from here (save `done`)
func _finish_game() -> void:
	SaveBridge.data["done"] = true
	hud.banner("🌴 KİTAP BİTTİ · THE BOOK IS DONE\n[font_size=16]All 16 units, all 20 missions ❤[/font_size]")
	hud.toast("🌟 [b]You finished every unit and every mission.[/b] Free play from here — the tables, the gods and Old Soul are all still open.", 13.0)
	torii.dance_t = maxf(torii.dance_t, 5.0)
	SaveBridge.write()

# ---------------------------------------------------------------- hunt gate + units
func _start_gate(nx: int) -> void:
	var G: Dictionary = D["gates"][mini(nx - 1, D["gates"].size() - 1)]
	gate = {"next": nx, "type": G.get("type"), "left": int(G["n"]), "eleft": int(G.get("elite", 0))}
	SaveBridge.data["gate"] = gate.duplicate(); SaveBridge.write()
	var tn: String = (str(D["enemies"][G["type"]]["name"]) + "s") if G.get("type") else "monsters (any kind)"
	hud.banner("⚔️ HUNT GATE\n[font_size=16]Clear the streets to unlock the next mission![/font_size]")
	phone("KAAN 📱", ["Bebeğim, the streets are getting rough out there... 😤",
		"Clear out [b]%d %s[/b]%s before your next task. Dikkatli ol! [i](Be careful!)[/i]" % [gate["left"], tn, (" and [b]%d EPIC 👑[/b] (the big gold ones)" % gate["eleft"]) if gate["eleft"] else ""]], func(): pass)

# like 7.2's applySave: the hunt's monster type comes from the gate table, never the save (7.2 saves don't
# carry one, and a missing type would quietly turn "8 zombies" into "any monsters")
func _resume_gate(g: Dictionary) -> void:
	var nx := int(g.get("next", 1))
	var G: Dictionary = D["gates"][clampi(nx - 1, 0, D["gates"].size() - 1)]
	gate = {"next": nx, "type": G.get("type"), "left": int(g.get("left", G["n"])), "eleft": int(g.get("eleft", 0))}

func _gate_tick() -> void:
	if gate.is_empty() or Overlay.any(): return
	var tn: String = (str(D["enemies"][gate["type"]]["name"]) + "s") if gate["type"] else "any monsters"
	hud.objective("[color=#ff5fa2][b]⚔️ HUNT GATE[/b][/color]\n[color=#f2e8ff]Defeat %s: %d left%s[/color]" % [tn, maxi(0, gate["left"]),
		(" · EPIC 👑: %d" % gate["eleft"]) if gate["eleft"] > 0 else ""])
	gate_mobs = gate_mobs.filter(func(e): return is_instance_valid(e) and e.is_alive())
	var want := mini(3, maxi(0, gate["left"]) + maxi(0, gate["eleft"]))   # extra kills must not hide the epics still owed
	while gate_mobs.size() < want:
		var a := randf() * TAU; var r := randf_range(18, 28)
		var kind: String = gate["type"] if gate["type"] else ["imp", "zombie", "thot", "ghost"].pick_random()
		var epic: bool = gate["eleft"] > 0 and gate["left"] <= 0
		gate_mobs.append(Enemy.spawn(world, kind, torii.global_position + Vector3(cos(a) * r, 0, sin(a) * r), torii, epic))

func _gate_done() -> void:
	if gate.is_empty(): return
	var nx: int = gate["next"]; gate = {}
	for e in gate_mobs: if is_instance_valid(e): e.queue_free()
	gate_mobs = []
	SaveBridge.data["gate"] = null
	hud.banner("✅ GATE CLEARED!\n[font_size=16]Well hunted![/font_size]")
	Audio.sfx("fanfare"); Audio.sfx("chuckle")
	torii.dance_t = 2.0; lessons.xp(30); SaveBridge.write()
	_gates_done += 1
	if _gates_done % 3 == 0:                    # every few gates: a file survives what the computer might lose
		get_tree().create_timer(4.2).timeout.connect(func(): hud.toast("💾 [b]Worth keeping a copy.[/b] Open [b]SAVE & LOAD[/b] (pause menu, P) and press [b]SAVE TO A FILE[/b].", 9.0))
	await get_tree().create_timer(3.6).timeout
	if m.is_empty() and gate.is_empty(): proceed_to(nx)

# 7.2's proceedTo: a new book unit only opens once every lesson of this one has been had
func proceed_to(nx: int) -> void:
	if nx >= M.size(): return
	if int(M[nx]["unit"]) > lessons.unit():
		var left := lessons.unit_lessons(lessons.unit()).size() - SaveBridge.get_i("ul")
		if left > 0:
			hud.toast("📖 Bir dakika! Unit %d has %d lesson%s left. Kaan won't send you on until you've had them." % [lessons.unit(), left, "s" if left > 1 else ""], 8.0)
			waiting_lessons = nx; lessons.pend = true
			return
		_advance_unit(nx); return
	start(nx)

func _advance_unit(nx: int) -> void:
	var old := lessons.unit()
	SaveBridge.data["unit"] = int(M[nx]["unit"]); SaveBridge.data["ul"] = 0
	Stats.add_lira(80 + old * 20)
	lessons.xp(60 + old * 10)
	hud.banner("🎓 UNIT %d TAMAMLANDI\n[font_size=16]Unit %d unlocked[/font_size]" % [old, SaveBridge.get_i("unit")])
	Audio.sfx("fanfare"); Audio.sfx("divine")
	if Fx.me: Fx.me.burst(torii.global_position + Vector3(0, 1.6, 0), Fx.CONF, 34, 5.0, 6.0, 1.3)
	torii.dance_t = 3.0; SaveBridge.write()
	await get_tree().create_timer(4.2).timeout
	if m.is_empty(): start(nx)
