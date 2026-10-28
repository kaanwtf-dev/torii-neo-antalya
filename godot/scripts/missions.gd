# The story: all 20 of Kaan's missions from 7.2 (assets/missions/missions.json, made by
# tools/missions/convert_missions.py), with 7.2's step types: goto, collect, kill (waves until the count is
# done), return, zone (stay in the area; some make her dance), deliver (beat the clock), travel (fly to
# Cameroon / Arizona / Livermore and back), boss (phases), god (heads-or-tails at a shrine), choice (answer in
# Turkish) and photo (T to photograph ghosts). Each mission starts with Kaan's call and ends with XP, its
# phrase, its rewards — then a HUNT GATE (clear N monsters) and, when the next mission is in a new book unit,
# that unit's lessons first. Save fields like 7.2: next, mid, gate, unit, ul, weap, dur, mh, mm, lira, npc.
class_name Missions
extends Node

var D := {}
var M: Array = []
var world: Node3D
var torii: CharacterBody3D
var hud: Hud
var lessons: Lessons
var beam: MeshInstance3D

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
var photo_ghosts: Array = []
var choice_open := false
var call_lines: Array = []
var call_who := ""
var call_done: Callable
var gate := {}
var gate_mobs: Array = []
var waiting_lessons := -1            # next mission index waiting for this unit's lessons

func setup(w: Node3D, p: CharacterBody3D, h: Hud, l: Lessons) -> void:
	world = w; torii = p; hud = h; lessons = l
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))
	M = D["missions"]
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = .5; cm.bottom_radius = .5; cm.height = 60
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, .85, .3, .35); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = mat; beam.mesh = cm; beam.visible = false; world.add_child(beam)
	# carry on where her save says (7.2: `mid` = a mission in progress, `gate` = a hunt, else `next`)
	var nxt := SaveBridge.get_i("next", 0)
	var mid = SaveBridge.data.get("mid")
	if mid != null and str(mid) != "":
		for i in M.size(): if M[i]["id"] == mid: start(i); return
	var g = SaveBridge.data.get("gate")
	if g is Dictionary: _resume_gate(g); return
	if nxt < M.size(): proceed_to(nxt)
	else: hud.toast("🌴 Every mission is done — free play! ❤", 6.0)

# ---------------------------------------------------------------- Kaan's calls
func phone(who: String, lines: Array, done: Callable) -> void:
	call_who = who; call_lines = lines.duplicate(); call_done = done
	hud.call_box(who, call_lines.pop_front())

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	if hud.box.visible and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER):
		if call_lines.size(): hud.call_box(call_who, call_lines.pop_front())
		else:
			hud.call_box("", "")
			var cb := call_done; call_done = Callable()
			if cb.is_valid(): cb.call()
		get_viewport().set_input_as_handled()
	elif e.keycode == KEY_T and step >= 0 and _st().get("t") == "photo": _snap()
	elif e.keycode == KEY_E and step >= 0 and _st().get("t") == "god" and _near(4.0): _god()

# ---------------------------------------------------------------- missions
func start(i: int) -> void:
	idx = i; m = M[i]; step = -1; count = 0; extra = 0; pickups = []
	SaveBridge.data["next"] = i; SaveBridge.data["mid"] = m["id"]
	SaveBridge.data["unit"] = max(SaveBridge.get_i("unit", 1), int(m["unit"]))
	var go := func():
		if m.has("start"):
			for w in m["start"].get("teach", []): lessons.teach(w)
		SaveBridge.write()
		hud.banner(m["title"])
		_advance()
	if m.has("intro"): phone(m["intro"]["name"], m["intro"]["lines"], go)
	else: go.call()

func _st() -> Dictionary:
	if not m.has("steps"): return {}   # no mission running (e.g. after the last one)
	return m["steps"][step] if step >= 0 and step < m["steps"].size() else {}

func _advance() -> void:
	step += 1; count = 0; zone_t = 0.0
	if step >= m["steps"].size(): _complete(); return
	var st := _st()
	beam.visible = st["t"] not in ["kill", "travel", "boss"]
	if st.has("x"): beam.global_position = Vector3(st["x"], 30, st["z"])
	match st["t"]:
		"collect":
			if pickups.is_empty(): _spawn_pickups()
		"kill":
			kills_left = int(st["n"]) + extra; extra = 0
			_wave(st)
			if st.has("bn"): hud.banner(st["bn"])
		"deliver":
			var to: Array = st["to"]
			var d := torii.global_position.distance_to(Vector3(to[0], 0, to[1]))
			deliver = {"t": 0.0, "limit": st["time"][0] + d / st["time"][1], "broken": false}
			beam.global_position = Vector3(to[0], 30, to[1])
			if st.has("bn"): hud.banner(st["bn"])
		"boss":
			boss = Enemy.spawn(world, st["boss"], Vector3(st["x"], 0, st["z"]), torii)
			boss.set_phases(st.get("phases", []))
			boss.died.connect(func(_e):
				boss = null
				for b in st.get("after", []): hud.banner(b)
				if _st() == st: _advance())
			hud.banner(st.get("bn", "⚔️ BOSS!"))
		"travel":
			_travel(st["zone"]); return
		"photo":
			shots = 0; photo_ghosts = []
			for k in int(st["n"]) + 2:
				var g := Enemy.spawn(world, st.get("mob", "ghost"), Vector3(st["x"] + randf_range(-14, 14), 0, st["z"] + randf_range(-14, 14)), torii)
				g.dmg = 0; g.sp = 0.6; photo_ghosts.append(g)
			if st.has("bn"): hud.banner(st["bn"])
	hud.toast("🎯 " + str(st.get("lab", "")), 5.5)
	SaveBridge.write()

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
			var kind: String = spec["pool"].pick_random() if spec.has("pool") else spec.get("mob", "imp")
			var at := Vector3(spec["x"][0] + randf_range(spec["x"][1], spec["x"][2]), 0, spec["z"][0] + randf_range(spec["z"][1], spec["z"][2]))
			var e := Enemy.spawn(world, kind, at, torii, randf() < float(spec.get("elite", 0)))
			mobs.append(e)
			e.died.connect(func(x):
				mobs.erase(x)
				if _st().get("t") == "kill":
					kills_left -= 1
					if kills_left <= 0: _advance())

func _near(r: float) -> bool:
	var st := _st()
	return Vector2(torii.global_position.x - st["x"], torii.global_position.z - st["z"]).length() < r

func _process(dt: float) -> void:
	_gate_tick()
	if waiting_lessons >= 0 and not lessons.active and not QuizUI.open and not hud.box.visible:
		if SaveBridge.get_i("ul") >= lessons.unit_lessons(lessons.unit()).size():
			var nx := waiting_lessons; waiting_lessons = -1; _advance_unit(nx)
		elif not lessons.pend: lessons.pend = true
	if step < 0 or m.is_empty() or QuizUI.open: return
	var st := _st()
	if st.is_empty(): return
	var here := torii.global_position
	for p in pickups.duplicate():
		if not is_instance_valid(p["node"]): pickups.erase(p); continue
		p["node"].rotation.y += dt * 2.0
		if st["t"] == "collect" and p["item"] == st["item"] and p["node"].global_position.distance_to(here) < 1.8:
			p["node"].queue_free(); pickups.erase(p); count += 1
			hud.toast("%s %d/%d" % [p["item"], count, int(st["n"])], 1.4)
			if count >= int(st["n"]): _advance(); return
	var d := 0.0
	if st.has("x"): d = Vector2(here.x - st["x"], here.z - st["z"]).length()
	var info := ""
	match st["t"]:
		"goto":
			info = "📍 %dm" % d
			if d < 6.0: _advance(); return
		"return":
			info = "📍 %dm" % d
			if d < 4.5: _complete(); return
		"collect": info = "%d/%d" % [count, int(st["n"])]
		"zone":
			if d < float(st["r"]):
				zone_t += dt
				if st.get("dance", false): torii.dance_t = .4
				info = "⏳ %ds" % ceil(max(0.0, float(st["dur"]) - zone_t))
				if zone_t >= float(st["dur"]): _advance(); return
			else: info = "📍 %dm · get in the area!" % d
		"kill":
			info = "⚔️ %d to go" % kills_left
			if mobs.is_empty() and kills_left > 0: _wave(st)          # 7.2 keeps them coming until the count is done
		"boss": info = "💀 BOSS HP: %d" % (max(0, ceil(boss.hp)) if boss else 0)
		"deliver":
			deliver["t"] += dt
			var to: Array = st["to"]
			var dd := Vector2(here.x - to[0], here.z - to[1]).length()
			info = "⏱ %ds · 📍 %dm" % [max(0, ceil(deliver["limit"] - deliver["t"])), dd]
			if st.get("fragile", false) and torii.on_bike and torii.is_on_wall() and absf(torii.bspeed) > 6: deliver["broken"] = true
			if dd < 4.5: _deliver_done(st); return
		"god": info = "🪙 %dm · press E at the shrine" % d
		"choice":
			info = "📍 %dm" % d
			if d < 6.0 and not choice_open: _choice(st)
		"photo": info = "📸 %d/%d · press T" % [shots, int(st["n"])]
	hud.objective("📖 UNIT %d/16 · %s\n%s · %s" % [int(m["unit"]), m["title"], st.get("lab", ""), info])

# ---------------------------------------------------------------- special steps
func _deliver_done(st: Dictionary) -> void:
	var fast: bool = deliver["t"] <= deliver["limit"] and not deliver["broken"]
	var e: Dictionary = st.get("fast", {}) if fast else st.get("late", {})
	if not fast:
		hud.banner(st.get("brokeMsg", "") if deliver["broken"] else st.get("lateMsg", "Too late!"))
	_effects(e)
	if e.has("extra"): extra = int(e["extra"])
	if _st() == st:
		if step >= m["steps"].size() - 1: _complete()
		else: _advance()

func _travel(zone: String) -> void:
	var sp: Dictionary = D["zspawn"][zone]
	if torii.on_bike: torii._get_off()
	hud.banner("🛬 WELCOME HOME" if zone == "city" else "🛫 " + str(D["zname"].get(zone, zone)))
	torii.global_position = Vector3(sp["x"], 1.0, sp["z"])
	torii.yaw = PI if zone == "city" else -PI / 2
	if zone != "city": lessons.teach("uçak"); lessons.teach("havalimanı")
	await get_tree().create_timer(1.5).timeout
	_advance()

func _choice(st: Dictionary) -> void:
	choice_open = true
	var opts: Array = st["opts"].map(func(o): return "%s  (%s)" % [o["t"], o.get("en", "")])
	hud.choose(st.get("who", ""), str(st.get("q", "")) + ("\n[i]%s[/i]" % st["hint"] if st.has("hint") else ""), opts, func(i):
		var o: Dictionary = st["opts"][i]
		hud.toast(o.get("r", ""), 5.0)
		if o.get("ok", false):
			lessons.xp(25); _advance()
		await get_tree().create_timer(2.5).timeout
		choice_open = false)

func _god() -> void:
	var st := _st()
	var gid: String = st["id"]
	var npc: Dictionary = SaveBridge.data.get("npc", {})
	var score := [0, 0]
	var round_ := func(self_ref):
		hud.choose(gid.to_upper() + " 🪙", "Yazı mı, tura mı? [i](Heads or tails?)[/i]  First to 2 wins.  You %d · %s %d" % [score[0], gid.to_upper(), score[1]],
			["Yazı", "Tura"], func(i):
				var flip := randi() % 2
				if flip == i: score[0] += 1
				else: score[1] += 1
				hud.toast("🪙 %s! %s" % ["Yazı" if flip == 0 else "Tura", "You win the toss!" if flip == i else "The god wins this one."], 2.0)
				await get_tree().create_timer(1.2).timeout
				if score[0] >= 2:
					npc["god_" + gid] = "won"; SaveBridge.data["npc"] = npc
					hud.banner("🪙 YOU BEAT %s!" % gid.to_upper()); _advance()
				elif score[1] >= 2: hud.toast("😈 %s wins. Press E to try again." % gid.to_upper(), 4.0)
				else: self_ref.call(self_ref))
	round_.call(round_)

func _snap() -> void:
	var st := _st()
	var f := -torii.global_transform.basis.z
	for g in photo_ghosts:
		if not is_instance_valid(g): continue
		var to: Vector3 = g.global_position - torii.global_position
		if to.length() < float(st.get("range", 45)) and absf(f.signed_angle_to(Vector3(to.x, 0, to.z).normalized(), Vector3.UP)) < .5:
			shots += 1; photo_ghosts.erase(g); g.queue_free()
			hud.toast("📸 Got one! %d/%d" % [shots, int(st["n"])], 1.6)
			if shots >= int(st["n"]):
				for o in photo_ghosts: if is_instance_valid(o): o.queue_free()
				photo_ghosts = []
				hud.banner(st.get("done", "📸 PROOF!")); _advance()
			return
	hud.toast("📸 No ghost in the shot…", 1.4)

# ---------------------------------------------------------------- rewards
func _effects(e: Dictionary) -> void:
	if e.has("xp"): lessons.xp(int(e["xp"]))
	if e.has("lira"): SaveBridge.data["lira"] = SaveBridge.get_i("lira") + int(e["lira"])
	if e.has("mh"):
		SaveBridge.data["mh"] = SaveBridge.get_i("mh", 100) + int(e["mh"])
		torii.max_hp = SaveBridge.get_i("mh", 100); torii.heal_full()
	if e.has("mm"): SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + int(e["mm"])
	var weap: Array = SaveBridge.data.get("weap", [])
	var dur: Dictionary = SaveBridge.data.get("dur", {})
	for w in e.get("weapons", []):
		if not weap.has(w): weap.append(w)
		var ws: Dictionary = D["weapons"].get(w, {})
		var dv = ws.get("dur", 40)
		dur[w] = 9999 if (dv == null or str(dv) == "inf" or float(dv) > 9999) else dv
		hud.toast("🆕 %s — mission reward!" % ws.get("n", w), 5.0)
	SaveBridge.data["weap"] = weap; SaveBridge.data["dur"] = dur
	for w in e.get("teach", []): lessons.teach(w)
	var msg: String = e.get("msg", "")
	if msg != "" and not msg.begins_with("🆕 [b]"): hud.toast(msg, 7.0)

func _complete() -> void:
	beam.visible = false
	for p in pickups: if is_instance_valid(p["node"]): p["node"].queue_free()
	pickups = []
	hud.objective("Kaan is waiting... ❤")
	hud.banner("✅ MISSION COMPLETE! +%d XP ❤" % int(m["xp"]))
	torii.dance_t = 3.0
	lessons.xp(int(m["xp"]))
	if m.get("phrase"): lessons.teach(m["phrase"])
	_effects(m.get("reward", {}))
	lessons.quiz_pend = true
	var done := idx
	SaveBridge.data["next"] = done + 1; SaveBridge.data["mid"] = null
	step = -1; m = {}
	SaveBridge.write()
	await get_tree().create_timer(5.2).timeout
	if done + 1 < M.size(): _start_gate(done + 1)
	else:
		hud.banner("💖 TORİİ IS FREE! Seni seviyorum ❤")
		SaveBridge.data["done"] = true; SaveBridge.write()

# ---------------------------------------------------------------- hunt gate + units
func _start_gate(nx: int) -> void:
	var G: Dictionary = D["gates"][min(nx - 1, D["gates"].size() - 1)]
	gate = {"next": nx, "type": G.get("type"), "left": int(G["n"]), "eleft": int(G.get("elite", 0))}
	SaveBridge.data["gate"] = gate.duplicate(); SaveBridge.write()
	var tn: String = (str(D["enemies"][G["type"]]["name"]) + "s") if G.get("type") else "monsters (any kind)"
	hud.banner("⚔️ HUNT GATE")
	phone("KAAN 📱", ["Bebeğim, the streets are getting rough out there... 😤",
		"Clear out [b]%d %s[/b]%s before your next task. Dikkatli ol! [i](Be careful!)[/i]" % [gate["left"], tn, (" and [b]%d EPIC 👑[/b]" % gate["eleft"]) if gate["eleft"] else ""]], func(): pass)

func _resume_gate(g: Dictionary) -> void:
	gate = {"next": int(g["next"]), "type": g.get("type"), "left": int(g["left"]), "eleft": int(g.get("eleft", 0))}

func _gate_tick() -> void:
	if gate.is_empty() or hud.box.visible: return
	var tn: String = (str(D["enemies"][gate["type"]]["name"]) + "s") if gate["type"] else "any monsters"
	hud.objective("⚔️ HUNT GATE\nDefeat %s: %d left%s" % [tn, max(0, gate["left"]), (" · EPIC 👑: %d" % gate["eleft"]) if gate["eleft"] > 0 else ""])
	gate_mobs = gate_mobs.filter(func(e): return is_instance_valid(e))
	var want := mini(3, maxi(0, gate["left"]) + maxi(0, gate["eleft"]))   # extra kills must not hide the epics still owed
	while gate_mobs.size() < want:
		var a := randf() * TAU; var r := randf_range(18, 28)
		var kind: String = gate["type"] if gate["type"] else ["imp", "zombie", "thot", "ghost"].pick_random()
		var epic: bool = gate["eleft"] > 0 and gate["left"] <= 0
		var e := Enemy.spawn(world, kind, torii.global_position + Vector3(cos(a) * r, 0, sin(a) * r), torii, epic)
		gate_mobs.append(e)
		e.died.connect(func(x):
			if gate.is_empty(): return
			if x.elite and gate["eleft"] > 0: gate["eleft"] -= 1
			else: gate["left"] = maxi(0, gate["left"] - 1)
			SaveBridge.data["gate"] = gate.duplicate()
			if gate["left"] <= 0 and gate["eleft"] <= 0: _gate_done())

func _gate_done() -> void:
	var nx: int = gate["next"]; gate = {}
	for e in gate_mobs: if is_instance_valid(e): e.queue_free()
	gate_mobs = []
	SaveBridge.data["gate"] = null
	hud.banner("✅ GATE CLEARED!"); torii.dance_t = 2.0; lessons.xp(30); SaveBridge.write()
	await get_tree().create_timer(3.6).timeout
	proceed_to(nx)

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
	SaveBridge.data["lira"] = SaveBridge.get_i("lira") + 80 + old * 20
	lessons.xp(60 + old * 10)
	hud.banner("🎓 UNIT %d TAMAMLANDI · Unit %d unlocked" % [old, SaveBridge.get_i("unit")])
	torii.dance_t = 3.0; SaveBridge.write()
	await get_tree().create_timer(4.2).timeout
	start(nx)
