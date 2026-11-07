# 7.2's side quests (QGIVERS / QUESTS / questStart / questNext / questPartDone / questInteract / questPanel):
# five people with three-part stories each (assets/side/quests.json). A gold "!" over a giver = something for
# her; "⏳" = come back at a higher level. One quest part at a time, alongside the main story. The active part
# gets a green marker, an arrow over her head and a gold line under the mission text; J's quest log lists every
# chain (main.gd / the inventory decide where J goes: log_bbcode() or toggle_log()).
# Step kinds (7.2's STEP.* + quest-only ones): race (rings, bike, rival), chase, escort, deliver (pick-up, stops,
# clock), photo (T), choice (answer in Turkish), talk (go back to the giver), goto, kill, collect, boss (phases).
# Save like 7.2: q = {chain: parts done}, qa = {id, part} — a part in progress restarts from its first step.
class_name Quests
extends Node

static var me: Quests
var D := {}
var torii: Node3D
var hud: Hud
var world: Node3D
var qa := {}                    # {id, part, step, left, cnt}; empty = no quest running
var r := {}                     # the running step's own state (rings, runner, escort...)
var boss: Node3D
var givers: Array = []          # {G, mark, low}
var marker: Node3D
var nav: Node3D
var line: RichTextLabel
var _layer: CanvasLayer
var _log: PanelContainer
var _t := 0.0
var _hud_t := 0.0
var nermin: Node3D

const TIPS := {
	"quests": ["📜 SIDE QUESTS · YAN GÖREVLER", ["People around the map have their own stories for you now. Look for a gold [b]![/b] over someone's head.",
		"Every story has [b]3 parts[/b]. Talk with [b]E[/b]; each part shows its recommended level.",
		"Your active quest gets a [color=#3dff9e]green marker[/color] and its own gold line under your mission. [b]J[/b] opens the quest log.",
		"They run alongside the main story. Rewards include lira, XP and [b]named gear you can't get anywhere else[/b]."]],
	"race": ["🏁 RACES · YARIŞ", ["Ride through the glowing [b]rings[/b] in order. The [b]first ring starts the clock[/b].",
		"The arrow always points at the next ring. Some races need the bike — hop on with [b]E[/b].", "Some races have a [b]rival[/b]. Beat them to the last ring. [i]yarış[/i] = race."]],
	"chase": ["🏃 CHASES · KOVALAMACA", ["Someone is running away — [b]catch them[/b] by getting right up close (running or on the bike).",
		"Let them get too far away for too long and they escape — then you start again."]],
	"escort": ["🛡 ESCORTS · KORUMA", ["Someone needs you to get them somewhere safely. They only walk while you stay [b]close[/b].",
		"Monsters will come for them. Their health is on the quest line. If it runs out, you start over."]],
	"deliver": ["📦 DELIVERIES · KURYE", ["Pick the package up, then get it to the marked place [b]before the timer runs out[/b].",
		"The bike is your friend. [i]Acele et![/i] = hurry up!"]],
	"photo": ["📸 PHOTO HUNTS · FOTOĞRAF", ["Find what you are asked to photograph (a 📸 floats above it).", "Get it on screen, reasonably close, and press [b]T[/b]."]],
	"choice": ["💬 TURKISH CHOICES", ["Some people ask you to [b]answer in Turkish[/b]. Pick the right sentence with [b]1–4[/b].",
		"A wrong answer never ends the quest — they react, and you try again. The English is always shown."]],
}

func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	me = self; world = w; torii = p; hud = h
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/quests.json"))
	_layer = CanvasLayer.new(); _layer.layer = 3; add_child(_layer)
	line = Shops.rich("", 15, Color("ffd66b"), 450); line.position = Vector2(500, 96)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); line.add_theme_constant_override("outline_size", 6)
	_layer.add_child(line)
	for G in D["QGIVERS"]:
		var y := Shops.ground_y(G["x"], G["z"])
		var m := Shops.sign3d("!", Color("ffd66b"), 150); m.position = Vector3(G["x"], y + 3.3, G["z"]); world.add_child(m)
		var lo := Shops.sign3d("⏳", Color("9a88c0"), 90); lo.position = Vector3(G["x"], y + 3.2, G["z"]); lo.visible = false; world.add_child(lo)
		var nm := Shops.sign3d(G["name"], Color("8ff2ff"), 34); nm.position = Vector3(G["x"], y + 2.55, G["z"]); world.add_child(nm)
		givers.append({"G": G, "mark": m, "low": lo, "y": y})
	# the green quest marker and the arrow over her head (7.2's QSTATE.marker / nav)
	marker = Node3D.new(); world.add_child(marker); marker.visible = false
	var g := Color(.24, 1, .62, .85)
	var oct := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = .5; sm.height = 1.0; sm.radial_segments = 4; sm.rings = 2
	oct.mesh = sm; oct.material_override = _glow(g); oct.position.y = 3; oct.name = "oct"; marker.add_child(oct)
	var ring := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 1.7; tm.outer_radius = 1.9; tm.rings = 20; tm.ring_segments = 6
	ring.mesh = tm; ring.material_override = _glow(Color(g, .5)); ring.position.y = .1; marker.add_child(ring)
	nav = Node3D.new(); world.add_child(nav); nav.visible = false
	var cone := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0; cm.bottom_radius = .2; cm.height = .55; cm.radial_segments = 5
	cone.mesh = cm; cone.material_override = _glow(g); cone.rotation.x = -PI / 2; nav.add_child(cone)
	Shops.on_kill(_on_kill)
	Bus.on("pickup", _on_bus_pickup)
	# questLoad(): a part in progress picks up again a few seconds after loading
	if not (SaveBridge.data.get("q") is Dictionary): SaveBridge.data["q"] = {}
	var sq = SaveBridge.data.get("qa")
	if sq is Dictionary and _chain(str(sq.get("id", ""))) and _done(str(sq["id"])) == int(sq.get("part", -1)):
		await get_tree().create_timer(4.0).timeout
		if qa.is_empty():
			start(str(sq["id"])); hud.toast("📜 Your side quest picks up where it started.", 4.5)

func _on_bus_pickup(d: Dictionary) -> void:
	if not d.get("side", false): _on_item(Quests.pickup_kind(d))

# items.gd sends {id: "cocktail", kind: "item"}; side drops send {id, kind} both = the item
static func pickup_kind(d: Dictionary) -> String:
	var k := str(d.get("kind", ""))
	if k == "" or k == "item" or k == "gear" or k == "weapon": k = str(d.get("id", k))
	return k

static func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = c
	if c.a < 1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _chain(id: String) -> Dictionary:
	for Q in D["QUESTS"]: if Q["id"] == id: return Q
	return {}

func _giver(id: String) -> Dictionary:
	for G in D["QGIVERS"]: if G["id"] == id: return G
	return {}

func _done(id: String) -> int: return int((SaveBridge.data["q"] as Dictionary).get(id, 0))

func cur_step() -> Dictionary:
	if qa.is_empty(): return {}
	var P: Dictionary = _chain(qa["id"])["parts"][qa["part"]]
	return P["steps"][qa["step"]] if qa["step"] >= 0 and qa["step"] < P["steps"].size() else {}

# questAvail(): done / active / busy / low / ok
func avail(G: Dictionary) -> String:
	var Q := {}
	for x in D["QUESTS"]: if x["giver"] == G["id"]: Q = x
	if Q.is_empty(): return ""
	var pi := _done(Q["id"])
	if pi >= Q["parts"].size(): return "done"
	if not qa.is_empty(): return "active" if qa["id"] == Q["id"] else "busy"
	return "low" if SaveBridge.get_i("lvl", 1) < int(Q["parts"][pi]["rl"]) else "ok"

func _bb(s) -> String: return Rich.to_bb(str(s))
func _bbs(a: Array) -> Array: return a.map(func(x): return Rich.to_bb(str(x)))

# ---------------------------------------------------------------- flow
func start(id: String) -> void:
	var Q := _chain(id)
	if Q.is_empty(): return
	qa = {"id": id, "part": _done(id), "step": -1, "left": 0, "cnt": 0}
	SaveBridge.data["qa"] = {"id": id, "part": qa["part"]}
	Shops.tip("quests", TIPS["quests"][0], TIPS["quests"][1])
	hud.banner("📜 %s\n[font_size=18]%s[/font_size]" % [Q["t"], Q["parts"][qa["part"]]["n"]]); Shops.sfx("divine")
	next_step()

func next_step() -> void:
	if qa.is_empty(): return
	var prev := cur_step()
	if not prev.is_empty(): _end(prev)
	qa["step"] += 1; qa["cnt"] = 0
	var st := cur_step()
	if st.is_empty(): _part_done(); return
	if st.get("nermin", false): _spawn_nermin()
	_begin(st)
	hud.toast("📜 " + _bb(st.get("lab", "")), 5.0)
	_hud_line(); SaveBridge.write()

func _part_done() -> void:
	var id: String = qa["id"]; var Q := _chain(id); var P: Dictionary = Q["parts"][qa["part"]]
	qa = {}; r = {}; SaveBridge.data["qa"] = null; _hud_line()
	var G := _giver(Q["giver"])
	var fin := func():
		(SaveBridge.data["q"] as Dictionary)[id] = _done(id) + 1
		_reward(P.get("reward", {}))
		Shops.xp(int(P.get("xp", 120)))
		hud.banner("📜 GÖREV TAMAM · QUEST DONE\n[font_size=18]%s[/font_size]" % P["n"]); Shops.sfx("fanfare")
		if torii.get("dance_t") != null: torii.dance_t = 2.0
		if _done(id) >= Q["parts"].size(): hud.toast("🏆 [b]%s[/b] — you finished their whole story!" % Q["t"], 8.0)
		else: hud.toast("📜 [b]%s[/b] will have more for you soon — watch for the [color=#ffd66b]![/color]" % G.get("name", "They"), 6.0)
		SaveBridge.write()
	if P.has("outro"): _when_free(func(): hud.say(G.get("name", Q["t"]), _bbs(P["outro"]), fin))
	else: fin.call()

func _reward(R: Dictionary) -> void:
	if R.has("lira"): Shops.add_lira(int(R["lira"]))
	if R.has("int"):
		SaveBridge.data["int"] = SaveBridge.get_i("int") + int(R["int"])
		hud.toast("🧠 +%d INT — every point is +8%% XP" % int(R["int"]), 5.0)
	for k in (R.get("bag", {}) as Dictionary):
		var b := Shops.bag(); b[k] = mini(10, int(b.get(k, 0)) + int(R["bag"][k]))
	if R.has("gear"):
		var g: Dictionary = R["gear"]
		var rr: int = mini(int(g.get("rmax", 4)), Shops.rar_cap() + 1) if str(g["r"]) == "cap+1" else int(g["r"])
		Shops.gain_gear(Shops.make_gear({"b": g["b"], "r": rr, "lv": SaveBridge.get_i("lvl", 1) + int(g.get("lv", 0)), "n": g["n"]}))
	for w in R.get("teach", []): Shops.teach(w)

# questAbandon(): ⏸ put on hold
func abandon() -> void:
	if qa.is_empty(): return
	var st := cur_step()
	if not st.is_empty(): _end(st)
	if is_instance_valid(boss): boss.queue_free()
	boss = null; qa = {}; r = {}; SaveBridge.data["qa"] = null; _hud_line()
	hud.toast("📜 Quest put on hold — talk to them again whenever you like.", 4.5); SaveBridge.write()

func _when_free(cb: Callable) -> void:
	var n := 0
	while Overlay.any() and n < 240:
		n += 1; await get_tree().create_timer(.25).timeout
	cb.call()

func _on_kill(e) -> void:
	var st := cur_step()
	if st.get("t") != "kill": return
	if st.get("mob") != null and str(st["mob"]) != Shops.kind_of(e): return
	qa["left"] -= 1; _hud_line()
	if qa["left"] <= 0: next_step()

func _on_item(kind: String) -> void:
	var st := cur_step()
	if st.get("t") != "collect" or st.get("item") != kind: return
	qa["cnt"] += 1; qa["left"] -= 1; Shops.sfx("ding")
	if st.has("pages"):
		var pg: Array = st["pages"][(int(qa["cnt"]) - 1) % st["pages"].size()]
		hud.toast("📄 [b]Page %d/%d[/b]\n[color=#8ff2ff]%s[/color] — [i]%s[/i]" % [qa["cnt"], int(st["n"]), pg[0], pg[1]], 8.5)
	_hud_line()
	if qa["left"] <= 0: next_step()

# ---------------------------------------------------------------- E (questPrompt / questInteract)
func _near() -> Dictionary:
	for g in givers:
		if Shops.flat2(torii, g["G"]["x"], g["G"]["z"]) < 10: return g["G"]
	return {}

func prompt(_p: Node3D) -> String:
	var G := _near()
	if G.is_empty(): return ""
	var a := avail(G)
	var Q := {}
	for x in D["QUESTS"]: if x["giver"] == G["id"]: Q = x
	var pi := _done(Q["id"])
	match a:
		"ok": return "E: %s — ❗ new quest: %s" % [G["name"], Q["parts"][pi]["n"]]
		"active": return "E: %s — 📜%s" % [G["name"], " report back" if cur_step().get("t") == "talk" else ""]
		"low": return "E: %s — ⏳ come back at level %d" % [G["name"], int(Q["parts"][pi]["rl"])]
	return "E: talk to " + G["name"]

func try_interact(_p: Node3D) -> bool:
	var G := _near()
	if G.is_empty(): return false
	var n := Npc.find_near(Vector3(G["x"], 0, G["z"]), 2.0)
	if n: n.face(torii.global_position)
	var a := avail(G)
	var Q := {}
	for x in D["QUESTS"]: if x["giver"] == G["id"]: Q = x
	var pi := _done(Q["id"])
	var P: Dictionary = Q["parts"][mini(pi, Q["parts"].size() - 1)]
	match a:
		"active":
			var st := cur_step()
			if st.get("t") == "talk": next_step()
			else: hud.say(G["name"], ["Hadi, you've got this! 💪 — " + _bb(st.get("lab", ""))])
		"busy":
			hud.say(G["name"], ["You look busy, canım — finish what you're doing first, then come back to me. 😉", "[i](one side quest at a time · the quest log is on [b]J[/b])[/i]"])
		"low":
			hud.say(G["name"], [_bb(P["intro"][0]), "This one needs someone a little tougher. Come back at [b]level %d[/b]. 💪" % int(P["rl"])])
		"ok":
			hud.say(G["name"], _bbs(P["intro"]), func():
				hud.choose(G["name"], "[b]%s[/b] · part %d/3 · recommended level %d" % [P["n"], pi + 1, int(P["rl"])],
					["Yardım ederim! (I'll help!)", "Sonra (later)"], _accept.bind(Q["id"])))
		_:
			hud.say(G["name"], [_bb((G["chat"] as Array).pick_random())])
	return true

func _accept(i: int, id: String) -> void:
	if i == 0: start(id)

# ---------------------------------------------------------------- the quest log (questPanel)
func log_bbcode() -> String:
	var h := ""
	if not qa.is_empty():
		var Q := _chain(qa["id"])
		h += "▶ ACTIVE · [b][color=#3dff9e]%s[/color][/b] — %s\n\n" % [Q["parts"][qa["part"]]["n"], _bb(cur_step().get("lab", ""))]
	for Q in D["QUESTS"]:
		var G := _giver(Q["giver"]); var done := _done(Q["id"])
		h += "[b][color=#ffd66b]%s[/color][/b]  [color=#bfb0e0]%s[/color]\n" % [Q["t"], G["name"]]
		for i in Q["parts"].size():
			var P: Dictionary = Q["parts"][i]
			var s := "✅" if i < done else ("▶" if (not qa.is_empty() and qa["id"] == Q["id"] and qa["part"] == i) else \
				(("❗" if SaveBridge.get_i("lvl", 1) >= int(P["rl"]) else "⏳ Lv %d" % int(P["rl"])) if i == done else "🔒"))
			h += "   %s %s\n" % [s, P["n"]]
		h += "\n"
	return h + "[color=#8a7aae]Look for a gold [b]![/b] over their heads.[/color]"

func toggle_log() -> void:
	if _log: _close_log(); return
	if Overlay.any(): return
	_log = PanelContainer.new(); _log.position = Vector2(150, 70); _log.size = Vector2(660, 580)
	_log.add_theme_stylebox_override("panel", Shops.panel_box(Color("ffd66b"))); _layer.add_child(_log)
	var v := VBoxContainer.new(); _log.add_child(v)
	v.add_child(Shops.rich("[b]📜 YAN GÖREVLER · SIDE QUESTS[/b]", 20, Color("ffd66b"), 620))
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(630, 460); v.add_child(sc)
	sc.add_child(Shops.rich(log_bbcode(), 15, Color.WHITE, 600))
	var hb := HBoxContainer.new(); v.add_child(hb)
	if not qa.is_empty():
		var b := Shops.button("⏸ put on hold", Color("ff5fa2"), 14)
		b.pressed.connect(func(): abandon(); _close_log()); hb.add_child(b)
	var c := Shops.button("✕ close  [J / ESC]", Color("7bf7ff"), 14); c.pressed.connect(_close_log); hb.add_child(c)
	Overlay.open("qlog")

func _close_log() -> void:
	if _log: _log.queue_free(); _log = null
	Overlay.close("qlog")

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	if _log and (e.keycode == KEY_ESCAPE or e.keycode == KEY_J):
		_close_log(); get_viewport().set_input_as_handled(); return
	# T: a quest photo hunt (the mission's own photo step goes first, in missions.gd)
	if e.keycode == KEY_T and not Overlay.any() and cur_step().get("t") == "photo" and not r.is_empty():
		if Missions.me and Missions.me._st().get("t") == "photo": return
		_snap(); get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- steps
func _begin(st: Dictionary) -> void:
	r = {}
	match st["t"]:
		"kill":
			qa["left"] = int(st["n"])
			if st.has("spawn"):
				var sp: Dictionary = st["spawn"]
				for k in int(sp["n"]):
					var e := Enemy.spawn(world, sp["mob"], Vector3(sp["x"] + randf_range(-sp["r"], sp["r"]), 0, sp["z"] + randf_range(-sp["r"], sp["r"])), torii)
					r[e] = true
			Shops.sfx("groan")
		"collect":
			qa["left"] = int(st["n"])
			for s in st.get("pickups", []): Shops.me.drop_item(st["item"], Vector3(s[0], 0, s[1]), _on_item)
		"boss":
			boss = Enemy.spawn(world, st["boss"], Vector3(st["x"], 0, st["z"]), torii)
			if boss.has_method("set_phases"): boss.set_phases(st.get("phases", []))
			boss.died.connect(_boss_died.bind(st))
			hud.banner("%s\n[font_size=18]%s[/font_size]" % [st.get("bn", "⚔️ BOSS!"), _bb(st["lab"])]); Shops.sfx("rev")
		"race": _race_start(st)
		"chase": _chase_start(st)
		"escort": _escort_start(st)
		"deliver": _deliver_start(st)
		"photo": _photo_start(st)
		"choice": r = {"asked": false, "cool": 0.0}; Shops.tip("choice", TIPS["choice"][0], TIPS["choice"][1])

func _boss_died(_e, st: Dictionary) -> void:
	if cur_step() == st: next_step()

func _end(st: Dictionary) -> void:
	for k in ["rings", "nodes"]:
		for n in r.get(k, []): if is_instance_valid(n): n.queue_free()
	for k in ["runner", "riv", "who"]:
		if is_instance_valid(r.get(k)): r[k].queue_free()
	if st.get("t") == "collect": Shops.me.clear_items(_on_item)
	r = {}

func _tick(st: Dictionary, dt: float) -> void:
	match st["t"]:
		"goto":
			if Shops.flat2(torii, st["x"], st["z"]) < 36: next_step()
		"race": _race(st, dt)
		"chase": _chase(st, dt)
		"escort": _escort(st, dt)
		"deliver": _deliver(st, dt)
		"photo": _photo(st, dt)
		"choice": _choice(st, dt)

func target() -> Variant:
	var st := cur_step()
	if st.is_empty(): return null
	match st["t"]:
		"talk":
			var G := _giver(_chain(qa["id"])["giver"]); return Vector3(G["x"], 0, G["z"])
		"race":
			if r.has("pts"):
				var p: Array = r["pts"][mini(r["i"], r["pts"].size() - 1)]
				return Vector3(p[0], 0, p[1])
		"chase":
			if is_instance_valid(r.get("runner")): return r["runner"].global_position
		"escort":
			if r.has("path"):
				var q: Array = r["path"][r["i"]]
				return Vector3(q[0], 0, q[1])
		"deliver":
			if r.get("ph") == "pick": return Vector3(st["from"][0], 0, st["from"][1])
			if r.has("stops"):
				var s: Array = r["stops"][mini(r["i"], r["stops"].size() - 1)]
				return Vector3(s[0], 0, s[1])
		"collect":
			var best = null; var bd := INF
			for it in Shops.me.items:
				if it["kind"] == st["item"] and is_instance_valid(it["node"]):
					var d: float = it["node"].global_position.distance_squared_to(torii.global_position)
					if d < bd: bd = d; best = it["node"].global_position
			return best
		"boss":
			if is_instance_valid(boss): return boss.global_position
		"photo":
			for o in r.get("tg", []):
				if is_instance_valid(o) and not r["shot"].has(o): return o.global_position
	if st.has("x"): return Vector3(st["x"], 0, st["z"])
	return null

func _hud_line() -> void:
	if qa.is_empty(): line.text = ""; return
	var Q := _chain(qa["id"]); var st := cur_step()
	if st.is_empty(): return
	var h := "[right]📜 [b]%s[/b] [color=#c8b8a0](%d/3)[/color]\n%s" % [Q["parts"][qa["part"]]["n"], int(qa["part"]) + 1, _bb(st["lab"])]
	var extra := _step_hud(st)
	if extra == "":
		var tg = target()
		if tg is Vector3: extra = "📍 %dm" % roundi(Vector2(tg.x - torii.global_position.x, tg.z - torii.global_position.z).length())
	if extra != "": h += " · " + extra
	line.text = h + "[/right]"

func _step_hud(st: Dictionary) -> String:
	match st["t"]:
		"kill": return "%d left" % maxi(0, int(qa["left"]))
		"collect": return "%d/%d" % [int(qa["cnt"]), int(st["n"])]
		"race":
			if r.get("wait", false): return "🚲 get on your bike (E) to start"
			if not r.get("run", false): return "🏁 ride through the first ring to start · %ds" % int(st["time"])
			return "🏁 ring %d/%d · ⏱ %.1fs%s" % [r["i"], r["pts"].size(), maxf(0.0, float(st["time"]) - r["t"]),
				(" · rival %d/%d" % [mini(r["ri"], r["pts"].size()), r["pts"].size()]) if r.has("riv") else ""]
		"chase":
			if is_instance_valid(r.get("runner")):
				return "🏃 %dm away%s" % [roundi(r["runner"].global_position.distance_to(torii.global_position)), " · [color=#ff5a6e]losing them![/color]" if r["lost"] > 0 else ""]
		"escort": return "🛡 %s %d/%d ❤" % [st.get("name", "them"), maxi(0, ceili(r.get("hp", 0.0))), int(r.get("max", 100))]
		"deliver":
			if r.get("ph") == "pick": return "📦 pick it up"
			return "📦 %s⏱ %.1fs" % [("%d/%d · " % [r["i"] + 1, r["stops"].size()]) if r["stops"].size() > 1 else "", maxf(0.0, r["time"] - r["t"])]
		"photo": return "📸 %d/%d · press T when it's on screen" % [r.get("n", 0), int(st["n"])]
		"choice": return "💬 answer %s in Turkish" % st.get("whoShort", st.get("who", ""))
	return ""

# ---- race (STEP.race + raceRing / paintRings / makeRival) ----
func _ring(x: float, z: float, last: bool) -> Node3D:
	var g := Node3D.new(); world.add_child(g)
	var col := Color("ffd66b") if last else Color("7bf7ff")
	var m := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 3.2; tm.outer_radius = 3.6; tm.rings = 28; tm.ring_segments = 8
	m.mesh = tm; m.material_override = _glow(Color(col, .9)); m.rotation.x = PI / 2; m.position.y = 3.4; m.name = "ring"; g.add_child(m)
	g.position = Vector3(x, Shops.ground_y(x, z), z)
	return g

func _paint() -> void:
	for j in r["rings"].size():
		var g: Node3D = r["rings"][j]
		g.visible = j >= r["i"]
		g.scale = Vector3.ONE * (1.0 if j == r["i"] else .8)
		var m: StandardMaterial3D = g.get_node("ring").material_override; m.albedo_color.a = .95 if j == r["i"] else .28

func _race_start(st: Dictionary) -> void:
	r = {"i": 0, "t": 0.0, "run": false, "over": false, "rings": [], "pts": st["pts"], "wait": false}
	var pts: Array = st["pts"]
	for j in pts.size():
		var g := _ring(pts[j][0], pts[j][1], j == pts.size() - 1)
		var nx: Array = pts[mini(j + 1, pts.size() - 1)]; var pv: Array = pts[maxi(j - 1, 0)]
		g.rotation.y = atan2(float(nx[0]) - float(pv[0]), float(nx[1]) - float(pv[1])); r["rings"].append(g)
	_paint()
	if st.has("rival"):
		var R := Node3D.new(); world.add_child(R)
		if ResourceLoader.exists("res://assets/bike/bike.glb"):
			var b: Node3D = load("res://assets/bike/bike.glb").instantiate(); Tint.apply(b); R.add_child(b)
		var n := Npc.new(); R.add_child(n); n.setup("male", "res://assets/npc/male_2.png", 1.0, torii); n.mode = "sit"; n.position.y = .1
		var s := Shops.sign3d(st["rival"].get("name", "RAKİP"), Color("ff5fa2"), 50); s.position.y = 3.2; R.add_child(s)
		R.position = Vector3(float(pts[0][0]) + 2.5, Shops.ground_y(pts[0][0], pts[0][1]), pts[0][1])
		r["riv"] = R; r["ri"] = 1; r["rgo"] = false; r["rdone"] = false; r["rsp"] = float(st["rival"].get("sp", 16))
	hud.banner("🏁 %s\n[font_size=18]%s[/font_size]" % [st.get("bn", "YARIŞ · RACE"), _bb(st["lab"])])
	Shops.teach("yarış"); Shops.tip("race", TIPS["race"][0], TIPS["race"][1])

func _race(st: Dictionary, dt: float) -> void:
	if r.get("over", true): return
	(r["rings"][mini(r["i"], r["rings"].size() - 1)] as Node3D).rotate_y(dt * 1.5)
	if st.get("bike", false) and not torii.on_bike and not r["run"]: r["wait"] = true; return
	r["wait"] = false
	if r["run"]: r["t"] += dt
	var p: Array = r["pts"][r["i"]]
	if Shops.flat2(torii, p[0], p[1]) < (30.0 if torii.on_bike else 16.0) and absf(torii.global_position.y - Shops.ground_y(p[0], p[1])) < 5:
		if not r["run"]:
			r["run"] = true; r["t"] = 0.0; Shops.sfx("boost"); r["rgo"] = true
			hud.banner("GİT! · GO!\n[font_size=18]⏱ %ds%s[/font_size]" % [int(st["time"]), (" · beat " + st["rival"].get("name", "the rival")) if r.has("riv") else ""])
		r["i"] += 1; Shops.sfx("ding")
		if r["i"] >= r["pts"].size():
			r["over"] = true
			if r.has("riv") and r["rdone"]: _race_lose(st, "🏁 [b]%s got there first.[/b]" % st["rival"].get("name", "The rival")); return
			if r["t"] <= float(st["time"]):
				hud.banner("🏁 KAZANDIN! · YOU WON!\n[font_size=18]%.1fs[/font_size]" % r["t"]); Shops.sfx("fanfare"); Shops.teach("kazandın!")
				next_step()
			else: _race_lose(st, "⏱ [b]Too slow[/b] — %.1fs, you needed %ds." % [r["t"], int(st["time"])])
			return
		_paint()
	if r.has("riv") and r["rgo"] and not r["rdone"]:
		var R: Node3D = r["riv"]; var q: Array = r["pts"][mini(r["ri"], r["pts"].size() - 1)]
		var to := Vector3(q[0], 0, q[1]) - Vector3(R.global_position.x, 0, R.global_position.z)
		var lead: int = r["ri"] - r["i"]
		var sp: float = r["rsp"] * (.82 if lead > 1 else (1.18 if lead < -1 else 1.0))     # rubber band
		if to.length() < 2.5:
			r["ri"] += 1
			if r["ri"] >= r["pts"].size(): r["rdone"] = true
		else:
			R.global_position += to.normalized() * sp * dt; R.rotation.y = atan2(to.x, to.z)
		R.global_position.y = Shops.ground_y(R.global_position.x, R.global_position.z)
	if r["run"] and r["t"] > float(st["time"]): _race_lose(st, "⏱ [b]Time's up![/b]")

func _race_lose(st: Dictionary, why: String) -> void:
	hud.toast(why + " [b]Tekrar dene![/b] Ride back through the first ring to go again.", 6.5, true); Shops.sfx("no")
	r["i"] = 0; r["t"] = 0.0; r["run"] = false; r["over"] = false
	if r.has("riv"):
		r["ri"] = 1; r["rgo"] = false; r["rdone"] = false
		var p: Array = r["pts"][0]; r["riv"].global_position = Vector3(float(p[0]) + 2.5, Shops.ground_y(p[0], p[1]), p[1])
	_paint()

# ---- chase (STEP.chase) ----
func _chase_start(st: Dictionary) -> void:
	var path: Array = st["path"]
	var g: Node3D
	if st.get("mk") == "imp" and ResourceLoader.exists("res://assets/imp/imp.glb"):
		g = Node3D.new(); var m: Node3D = load("res://assets/imp/imp.glb").instantiate(); Tint.apply(m); g.add_child(m); world.add_child(g)
	else:
		var n := Npc.new(); world.add_child(n); n.setup("male", "res://assets/npc/male_4.png", 1.0, torii); n.mode = "puppet"; g = n
	var s := Shops.sign3d(st.get("tag", "💰 HIRSIZ"), Color("ff3b3b"), 46); s.position.y = 2.9; g.add_child(s)
	g.global_position = Vector3(path[0][0], Shops.ground_y(path[0][0], path[0][1]), path[0][1])
	r = {"i": 1, "lost": 0.0, "runner": g, "path": path, "t": 0.0}
	hud.banner("🏃 %s\n[font_size=18]%s[/font_size]" % [st.get("bn", "KOVALAMACA · CHASE"), _bb(st["lab"])])
	Shops.teach("hırsız"); Shops.tip("chase", TIPS["chase"][0], TIPS["chase"][1]); Shops.sfx("honk")

func _chase(st: Dictionary, dt: float) -> void:
	var g: Node3D = r.get("runner")
	if not is_instance_valid(g): return
	r["t"] += dt
	var q: Array = r["path"][r["i"]]
	var to := Vector3(q[0], 0, q[1]) - Vector3(g.global_position.x, 0, g.global_position.z)
	var pd := Vector2(torii.global_position.x - g.global_position.x, torii.global_position.z - g.global_position.z).length()
	var sp := float(st.get("sp", 9.4)) * (1.12 if pd < 9 else (.65 if pd > 40 else 1.0))
	if to.length() < 1.6: r["i"] = (r["i"] + 1) % r["path"].size()
	else: g.global_position += to.normalized() * sp * dt; g.rotation.y = atan2(to.x, to.z)
	if g is Npc: (g as Npc).puppet_speed = sp
	g.global_position.y = Shops.ground_y(g.global_position.x, g.global_position.z) + absf(sin(r["t"] * 11)) * .08
	if pd < 2.3:
		Shops.sfx("thud")
		if Fx.me: Fx.me.shake(.3); Fx.me.puff(g.global_position + Vector3(0, 1.2, 0), [Color("ffd66b"), Color("ff5fa2")], 16, 2, 2, .8)
		hud.banner("🤚 YAKALADIN! · GOT THEM!\n[font_size=18]%s[/font_size]" % st.get("caught", "")); Shops.sfx("fanfare")
		next_step(); return
	if pd > float(st.get("lose", 75)):
		r["lost"] += dt
		if r["lost"] > 3.5:
			r["lost"] = 0.0; r["i"] = 1
			g.global_position = Vector3(r["path"][0][0], 0, r["path"][0][1])
			hud.toast("💨 [b]Kaçtı![/b] [i](They got away!)[/i] They've doubled back to where it started — go again.", 6.0, true); Shops.sfx("no")
	else: r["lost"] = 0.0

# ---- escort (STEP.escort) ----
func _escort_start(st: Dictionary) -> void:
	var g := Npc.critter("cat") if st.get("mk") == "cat" else Node3D.new()
	world.add_child(g); g.global_position = Vector3(st["from"][0], Shops.ground_y(st["from"][0], st["from"][1]), st["from"][1])
	r = {"i": 0, "hp": float(st.get("hp", 100)), "max": float(st.get("hp", 100)), "wave": 0, "wt": 5.0, "who": g, "path": st.get("path", [st.get("to")]), "t": 0.0, "say": 0.0}
	hud.banner("🛡 %s\n[font_size=18]%s[/font_size]" % [st.get("bn", "KORUMA · ESCORT"), _bb(st["lab"])])
	Shops.tip("escort", TIPS["escort"][0], TIPS["escort"][1])

func _escort(st: Dictionary, dt: float) -> void:
	var g: Node3D = r.get("who")
	if not is_instance_valid(g): return
	r["t"] += dt
	var q: Array = r["path"][r["i"]]
	var to := Vector3(q[0], 0, q[1]) - Vector3(g.global_position.x, 0, g.global_position.z)
	var pd := Vector2(torii.global_position.x - g.global_position.x, torii.global_position.z - g.global_position.z).length()
	var moving := pd < 14 and to.length() > .8
	if moving:
		g.global_position += to.normalized() * float(st.get("sp", 3.4)) * dt; g.rotation.y = atan2(to.x, to.z)
	Npc.critter_anim(g, r["t"], moving)
	g.global_position.y = Shops.ground_y(g.global_position.x, g.global_position.z) + (absf(sin(r["t"] * 8)) * .05 if moving else 0.0)
	r["say"] -= dt
	if not moving and pd >= 14 and r["say"] <= 0 and Fx.me:
		r["say"] = 4.0; Fx.me.label(g.global_position + Vector3(0, 1.4, 0), st.get("wait", "⏳ …"), Color("ffe9fb"), 1.6, true)
	if to.length() < 1.3:
		if r["i"] < r["path"].size() - 1: r["i"] += 1
		else:
			hud.banner("🛡 GÜVENDE! · SAFE!\n[font_size=18]%s[/font_size]" % st.get("safe", "")); Shops.sfx("fanfare"); next_step(); return
	r["wt"] -= dt
	if r["wave"] < int(st.get("waves", 3)) and r["wt"] <= 0:
		r["wt"] = float(st.get("every", 10)); r["wave"] += 1
		for k in int(st.get("per", 2)):
			var a := randf() * TAU
			Enemy.spawn(world, st.get("mob", ["imp", "zombie"].pick_random()), g.global_position + Vector3(cos(a) * 16, 0, sin(a) * 16), torii)
		hud.toast("⚠️ [b]Here they come![/b] Protect them!", 2.6, true); Shops.sfx("groan")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_squared_to(g.global_position) < 4:
			r["hp"] -= float(e.get("dmg") if e.get("dmg") != null else 6) * dt * .55
			if Fx.me and randf() < dt * 3: Fx.me.puff(g.global_position + Vector3(0, .5, 0), Color("ff3b3b"), 2, .5, .8, .3)
	if r["hp"] <= 0:
		r["hp"] = r["max"]; r["i"] = 0; r["wave"] = 0; r["wt"] = 5.0
		g.global_position = Vector3(st["from"][0], 0, st["from"][1])
		hud.toast("💔 [b]They didn't make it.[/b] They've run back to the start — stay closer this time.", 6.5, true); Shops.sfx("no")

# ---- deliver (STEP.deliver) ----
func _deliver_start(st: Dictionary) -> void:
	r = {"ph": "pick" if st.has("from") else "run", "t": 0.0, "i": 0, "time": float(st.get("time", 60)), "stops": st.get("stops", [st.get("to")])}
	if r["ph"] == "run": _deliver_go()
	hud.banner("📦 %s\n[font_size=18]%s[/font_size]" % [st.get("bn", "KURYE · DELIVERY"), _bb(st["lab"])])
	Shops.teach("kurye"); Shops.tip("deliver", TIPS["deliver"][0], TIPS["deliver"][1])

func _deliver_go() -> void:
	r["ph"] = "run"; r["t"] = 0.0; r["i"] = 0
	hud.toast("⏱ [b]%d seconds.[/b] [i]Acele et![/i] (hurry!)" % int(r["time"]), 4.2); Shops.teach("acele et!")

func _deliver(st: Dictionary, dt: float) -> void:
	if r["ph"] == "pick":
		if Shops.flat2(torii, st["from"][0], st["from"][1]) < 12: Shops.sfx("ding"); _deliver_go()
		return
	r["t"] += dt
	var s: Array = r["stops"][r["i"]]
	if Shops.flat2(torii, s[0], s[1]) < 14:
		r["i"] += 1; Shops.sfx("ding")
		if s.size() > 2: hud.toast("✅ " + _bb(s[2]), 3.0)
		if r["i"] >= r["stops"].size():
			hud.banner("📦 TESLİM! · DELIVERED!\n[font_size=18]%.1fs[/font_size]" % r["t"]); Shops.sfx("fanfare"); next_step(); return
	if r["t"] > r["time"]:
		hud.toast("⏱ [b]Olmadı![/b] [i](That didn't work!)[/i] " + ("Go back to the start and pick it up again." if st.has("from") else "The clock starts again."), 6.5, true)
		Shops.sfx("no")
		if st.has("from"): r["ph"] = "pick"; r["t"] = 0.0; r["i"] = 0
		else: _deliver_go()

# ---- photo (STEP.photo): Pamuk's hiding spots, or the harbour ghosts ----
func _photo_start(st: Dictionary) -> void:
	r = {"n": 0, "shot": [], "tg": [], "nodes": [], "t": 0.0}
	for c in st.get("cats", []):
		var g := Npc.critter("cat"); world.add_child(g)
		g.global_position = Vector3(c[0], Shops.ground_y(c[0], c[1]), c[1]); g.rotation.y = randf() * TAU
		g.set_meta("name", "🐱 Pamuk"); r["tg"].append(g); r["nodes"].append(g)
		var ic := Shops.sign3d("📸", Color("ffd66b"), 70); ic.position.y = 1.4; g.add_child(ic)
	hud.banner("📸 %s\n[font_size=18]%s · press T[/font_size]" % [st.get("bn", "FOTOĞRAF AVI · PHOTO HUNT"), _bb(st["lab"])])
	Shops.teach("fotoğraf çekmek"); Shops.tip("photo", TIPS["photo"][0], TIPS["photo"][1])

func _photo(st: Dictionary, dt: float) -> void:
	r["t"] += dt
	if not st.has("mob"): return
	# mob photo hunts: keep enough of them around (and they don't bite while she's photographing)
	r["tg"] = (r["tg"] as Array).filter(func(o): return is_instance_valid(o))
	var alive: Array = r["tg"].filter(func(o): return not r["shot"].has(o))
	if alive.size() < int(st["n"]) - int(r["n"]) and randf() < dt * .6:
		var a := randf() * TAU
		var e := Enemy.spawn(world, st["mob"], Vector3(float(st.get("x", torii.global_position.x)) + cos(a) * 18, 0, float(st.get("z", torii.global_position.z)) + sin(a) * 18), torii)
		e.set_meta("name", "👻"); r["tg"].append(e)

func _snap() -> void:
	var st := cur_step()
	Shops.sfx("clack")
	if Fx.me: Fx.me.flash("heal")
	var cam: Camera3D = torii.get("cam")
	var got := 0
	for o in r["tg"]:
		if not is_instance_valid(o) or r["shot"].has(o): continue
		var p: Vector3 = o.global_position + Vector3(0, .5, 0)
		if cam == null or cam.global_position.distance_to(p) > float(st.get("range", 45)) or cam.is_position_behind(p): continue
		var sz := cam.get_viewport().get_visible_rect().size
		var sp := cam.unproject_position(p)
		if absf(sp.x / sz.x - .5) > .425 or absf(sp.y / sz.y - .5) > .425: continue
		r["shot"].append(o); r["n"] += 1; got += 1
		hud.toast("📸 [b]Çek![/b] %s (%d/%d)" % [o.get_meta("name", "📸"), mini(r["n"], int(st["n"])), int(st["n"])], 3.2)
		for c in o.get_children(): if c is Label3D: c.visible = false
		if r["n"] >= int(st["n"]): break
	if got == 0: hud.toast("📸 Nothing in the shot — get it on screen and a bit closer, then press [b]T[/b].", 3.2)
	if r["n"] >= int(st["n"]):
		hud.banner("📸 TAMAM!"); Shops.sfx("fanfare")
		if st.has("mob"):
			for o in r["tg"]: if is_instance_valid(o) and r["shot"].has(o): o.queue_free()
		next_step()

# ---- choice (STEP.choice): answer in Turkish, wrong answers just get a reaction ----
func _choice(st: Dictionary, dt: float) -> void:
	r["cool"] -= dt
	if r["asked"] or Overlay.any() or r["cool"] > 0: return
	if st.has("x") and Shops.flat2(torii, st["x"], st["z"]) > 40: return
	r["asked"] = true
	var order := range(st["opts"].size()); order.shuffle()
	var labels := []
	for i in order:
		var o: Dictionary = st["opts"][i]
		labels.append(str(o["t"]) + ((" (%s)" % o["en"]) if o.has("en") else ""))
	hud.choose(st["who"], _bb(st["q"]) + (("\n[i][color=#bfb0e0]%s[/color][/i]" % st["hint"]) if st.has("hint") else ""), labels, _answered.bind(st, order))

func _answered(k: int, st: Dictionary, order: Array) -> void:
	if cur_step() != st: return
	if k < 0:
		r["asked"] = false; r["cool"] = 4.0; return
	var o: Dictionary = st["opts"][order[k]]
	if o.get("ok", false):
		Shops.sfx("yes")
		hud.say(st["who"], [_bb(o.get("r", "Aferin! 👏 [i](Well done!)[/i]"))], _choice_right.bind(st))
	else:
		Shops.sfx("no")
		hud.say(st["who"], [_bb(o.get("r", "Hmm... olmadı. [i](That's not it.)[/i]")) + " [i]— try again.[/i]"], _choice_wrong.bind(st))

func _choice_right(st: Dictionary) -> void:
	Shops.xp(20)
	if cur_step() == st: next_step()

func _choice_wrong(st: Dictionary) -> void:
	if cur_step() == st: r["asked"] = false

# Nermin Hanım, waiting outside Five Sips for a letter forty years late
func _spawn_nermin() -> void:
	if is_instance_valid(nermin): return
	var n := Npc.new(); world.add_child(n); n.setup("female", "res://assets/npc/female_3.png", 1.0, torii)
	n.global_position = Vector3(26, Shops.ground_y(26, 16), 16); n.rotation.y = PI; n.npc_name = "NERMİN HANIM 💌"
	var s := Shops.sign3d("NERMİN HANIM 💌", Color("ff9ecf"), 40); s.position.y = 2.9; n.add_child(s)
	nermin = n

func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0:
		_t = .8
		for g in givers:
			var a := avail(g["G"])
			g["mark"].visible = a == "ok"; g["low"].visible = a == "low"
			if a == "ok" and Shops.flat2(torii, g["G"]["x"], g["G"]["z"]) < 900: Shops.tip("quests", TIPS["quests"][0], TIPS["quests"][1])
	var tt := Time.get_ticks_msec() / 1000.0
	for g in givers: if g["mark"].visible: g["mark"].position.y = g["y"] + 3.3 + sin(tt * 3) * .18
	if qa.is_empty():
		marker.visible = false; nav.visible = false; return
	var st := cur_step()
	if not st.is_empty() and not Overlay.any(): _tick(st, dt)
	if qa.is_empty(): marker.visible = false; nav.visible = false; return
	var tg = target()
	if tg is Vector3:
		marker.visible = true; marker.global_position = Vector3(tg.x, Shops.ground_y(tg.x, tg.z, tg.y + 20), tg.z); marker.rotate_y(.03)
		marker.get_node("oct").position.y = 3 + sin(tt * 3) * .3
		nav.visible = true; nav.global_position = torii.global_position + Vector3(0, 4.1 + sin(tt * 4) * .12, 0)
		nav.rotation.y = atan2(tg.x - torii.global_position.x, tg.z - torii.global_position.z) + PI
	else: marker.visible = false; nav.visible = false
	_hud_t -= dt
	if _hud_t <= 0: _hud_t = .15; _hud_line()
