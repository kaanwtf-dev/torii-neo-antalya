# The people who teach her Turkish outside the course, ported from 7.2:
#  · 11 NPC grammar tutors (LESSONS / addNPC / buildNPCs / buildSuburbNPCs / npcTalk / runLesson / assignTask /
#    sideItem / sideHUD, STY-19): 💬 over their heads → greeting → a grammar lesson → its GQ quiz (+20 XP) →
#    a side job (kill n / bring n things) → reward → chit-chat. The Five Sips owner's job opens the café shop.
#    Bandit's friend (the gold dog) and Dinozor Efendi get PS1 box bodies (Npc.critter, CRT-03).
#  · Old Soul's 16 unit tutors (SOULNPC / buildSoul / soulPaint / soulTalk / soulFinal, TRK-01/02): a UNIT tag
#    over each (dim + 🔒 = not reached, cyan = open, green = mastered), review the unit (+10 XP), practice
#    (5 questions, +25 XP, skippable), the FİNAL SINAVI (8 questions, 7 to pass, no skipping, her missed
#    questions mixed in) → mastered[u] = 1, +120 XP, +120₺, +5 max mana; all 16 = tavlaw + 1000₺ + 500 XP.
#  · advanceUnit's toast naming the tutor who can test her now, and Kaan's "Aferin bebeğim!" when a mission
#    is done (TRK-22).
# Save like 7.2: npc[id] = 0/1/2 (met / job given / done), mastered, mm, int, lira, ammo. The job itself is
# `side` (7.2 never saved S.side: after a reload it asked "Hazır mısın?" again; now the job carries on).
class_name Tutors
extends Node

static var me: Tutors
var D := {}
var torii: Node3D
var hud: Hud
var world: Node3D
var tutors: Array = []          # {T, body (critter or null), mark, y}
var soul: Array = []            # {N, body, tag, lock, ring, y}
var side := {}                  # 7.2's S.side: npcId, npcName, kind, item, mob, n, left, ready
var _line: RichTextLabel
var _mobs: Array = []
var _t := 0.0
var _spawn_t := 0.0
var _last_unit := -1
var _last_next := -1
var _aferin_i := -1
var _cb := Callable()           # the collect job's pickup callback (so its drops can be cleared)

const CRITTERS := ["golddog", "dino", "banditman", "fatcat", "cleo", "kusum"]

func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	me = self; world = w; torii = p; hud = h
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/tutors.json"))
	var layer := CanvasLayer.new(); layer.layer = 3; add_child(layer)
	_line = Shops.rich("", 15, Color("8ff2ff"), 450); _line.position = Vector2(500, 118)
	_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); _line.add_theme_constant_override("outline_size", 6)
	layer.add_child(_line)
	for T in D["NPCS"]:
		var y := Shops.ground_y(T["x"], T["z"])
		var body: Node3D = null
		if str(T["body"]) in CRITTERS:
			body = Npc.critter(T["body"]); world.add_child(body); body.position = Vector3(T["x"], y, T["z"])
		var mk := Shops.sign3d("💬", Color("ffd66b"), 90, 6.0); mk.position = Vector3(T["x"], y + 3.1, T["z"]); world.add_child(mk)
		tutors.append({"T": T, "body": body, "mark": mk, "y": y})
	for N in D["SOUL"]:
		var y := Shops.ground_y(N["x"], N["z"], 8.0)
		var body: Node3D = null
		if str(N["body"]) in CRITTERS:
			body = Npc.critter(N["body"]); world.add_child(body); body.position = Vector3(N["x"], y, N["z"])
		var tag := Shops.sign3d("UNIT %d" % int(N["u"]), Color("8ff2ff"), 44, 6.0); tag.position = Vector3(N["x"], y + 2.35, N["z"]); world.add_child(tag)
		var lk := Shops.sign3d("🔒", Color("9a88c0"), 36, 6.0); lk.position = Vector3(N["x"], y + 2.0, N["z"]); world.add_child(lk)
		var ring := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = .9; cm.bottom_radius = .9; cm.height = .03; cm.radial_segments = 10
		ring.mesh = cm; ring.material_override = MobModels.mat(Color("3dff9e"), true, .55); ring.position = Vector3(N["x"], y + .05, N["z"])
		world.add_child(ring)
		soul.append({"N": N, "body": body, "tag": tag, "lock": lk, "ring": ring, "y": y})
	Shops.on_kill(_on_kill)
	Bus.on("pickup", _on_pickup)
	Bus.on("mission_done", func(d): _aferin(int(d.get("i", -2))))
	_last_unit = SaveBridge.get_i("unit", 1); _last_next = SaveBridge.get_i("next")
	# a job from before the reload carries on (its pick-ups come back)
	var sv = SaveBridge.data.get("side")
	if sv is Dictionary and int(Shops.npcs().get(str(sv.get("npcId", "")), 0)) == 1 and not _tutor(str(sv["npcId"])).is_empty():
		side = sv.duplicate()
		if side.get("kind") == "collect" and not side.get("ready", false): _drop_items(_tutor(side["npcId"]))
	elif SaveBridge.data.has("side"): SaveBridge.data["side"] = null    # never ADD the key on load (7.2 saves stay 7.2-shaped)
	paint_soul()
	_side_hud()

func _tutor(id: String) -> Dictionary:
	for T in D["NPCS"]: if T["id"] == id: return T
	return {}

func _st(id: String) -> int: return int(Shops.npcs().get(id, 0))
func _bb(s) -> String: return Rich.to_bb(str(s))
func _bbs(a: Array) -> Array: return a.map(func(x): return Rich.to_bb(str(x)))

# ---------------------------------------------------------------- E
func _near_tutor(p: Node3D) -> Dictionary:
	for t in tutors:
		if Shops.flat2(p, t["T"]["x"], t["T"]["z"]) < 9: return t
	return {}

func _near_soul(p: Node3D) -> Dictionary:
	for s in soul:
		if Shops.flat2(p, s["N"]["x"], s["N"]["z"]) < 9: return s
	return {}

func prompt(p: Node3D) -> String:
	var s := _near_soul(p)
	if not s.is_empty():
		var N: Dictionary = s["N"]
		if int(N["u"]) > SaveBridge.get_i("unit", 1): return "E: %s — 🔒 Unit %d" % [N["n"], int(N["u"])]
		return "E: %s — 📖 Unit %d%s" % [N["n"], int(N["u"]), " ✅" if _mastered(int(N["u"])) else ""]
	var t := _near_tutor(p)
	if t.is_empty(): return ""
	var T: Dictionary = t["T"]
	match _st(T["id"]):
		0: return "E: 💬 talk to %s" % T["name"]
		1: return "E: %s — %s" % [T["name"], "✅ hand it in" if side.get("npcId") == T["id"] and side.get("ready", false) else "🤝 side job"]
	return "E: ☕ FIVE SIPS — buy something" if T["id"] == "fivesips" else "E: talk to %s" % T["name"]

# 7.2's interact(): soulInteract comes before tavlaInteract, the NPC tutors after josh. try_interact does both.
func try_interact(p: Node3D) -> bool:
	return try_soul(p) or try_npc(p)

func try_soul(p: Node3D) -> bool:
	var s := _near_soul(p)
	if s.is_empty(): return false
	_face(s, p); soul_talk(s); return true

func try_npc(p: Node3D) -> bool:
	var t := _near_tutor(p)
	if t.is_empty(): return false
	_face(t, p); npc_talk(t["T"]); return true

func _face(e: Dictionary, p: Node3D) -> void:
	var b: Node3D = e.get("body")
	var d: Dictionary = e["T"] if e.has("T") else e["N"]
	if is_instance_valid(b): b.rotation.y = atan2(p.global_position.x - b.global_position.x, p.global_position.z - b.global_position.z)
	else:
		var n := Npc.find_near(Vector3(d["x"], 0, d["z"]), 2.6)
		if n and n.mode != "sit": n.face(p.global_position)

# ---------------------------------------------------------------- the grammar tutors (npcTalk)
func npc_talk(T: Dictionary) -> void:
	var id: String = T["id"]; var nm: String = T["name"]
	var st := _st(id)
	if st == 0:
		Shops.npcs()[id] = 1
		hud.say(nm, _bbs(T["greet"]), func(): _run_lesson(T))
	elif st == 1:
		if side.get("npcId") == id:
			if side.get("ready", false):
				Shops.npcs()[id] = 2; side = {}; SaveBridge.data["side"] = null; _side_hud(); hud.unpin("side")
				hud.say(nm, ["Aferin! 🎉 [i](Well done!)[/i] A deal is a deal..."], func(): _reward(T); SaveBridge.write())
			else: hud.say(nm, ["Görev bitmedi! [i](The task isn't done!)[/i] " + _bb(T["task"]["desc"])])
		elif side.is_empty(): hud.say(nm, ["Hazır mısın? [i](Are you ready?)[/i]"], func(): _assign(T))
		else: hud.say(nm, ["You're busy with another quest. Finish it, then come back! 😉"])
	else:
		if id == "fivesips" and Shops.me: Shops.me.open("cafe")
		elif (T.get("chat", []) as Array).size(): hud.say(nm, [_bb((T["chat"] as Array).pick_random())])
		else: hud.say(nm, ["Merhaba güzelim! ☀️ [i](Hello beautiful!)[/i]"])

func _run_lesson(T: Dictionary) -> void:
	var L: Dictionary = D["LESSONS"].get(T["lesson"], {})
	if L.is_empty() or Lessons.me == null: _assign(T); return
	hud.say("%s — 📖 %s" % [T["name"], _bb(L["title"])], _bbs(L["lines"]), func():
		var qs := []
		for ix in L.get("qs", []): qs.append(Lessons.me.gq(int(ix)))
		Lessons.me.quiz.run(qs, func(_s):
			Shops.xp(20)
			if not side.is_empty(): hud.toast("📖 Lesson learned! Finish your current side quest first, then come back for this one.", 7.0)
			else: _assign(T),
			"LESSON QUIZ 📖"))

func _assign(T: Dictionary) -> void:
	var tk: Dictionary = T["task"]
	side = {"npcId": T["id"], "npcName": T["name"], "kind": tk["kind"], "item": tk.get("item"), "mob": tk.get("mob"),
		"n": int(tk["n"]), "left": int(tk["n"]), "ready": false}
	SaveBridge.data["side"] = side
	if tk["kind"] == "collect": _drop_items(T)
	_side_hud()
	hud.toast("🤝 [b]SIDE QUEST:[/b] " + _bb(tk["desc"]), 8.0)
	Shops.tip("sidejob", "🤝 SIDE JOBS", ["People with a [color=#ffd66b]💬[/color] teach you a bit of grammar, then ask a favour.",
		"Your job shows under the mission text. One job at a time — come back to them when it says [b]RETURN ✅[/b]."])
	SaveBridge.write()

# their collect jobs leave the things lying where 7.2 had them (cocktails, shells, the bone, simit)
func _drop_items(T: Dictionary) -> void:
	if Shops.me == null: return
	if _cb.is_valid(): Shops.me.clear_items(_cb)
	_cb = func(k: String): _got(k)
	for sp in T["task"].get("spots", []): Shops.me.drop_item(str(T["task"]["item"]), Vector3(sp[0], 0, sp[1]), _cb)

func _on_pickup(d: Dictionary) -> void:
	if d.get("side", false): return           # our own drops come in through _got
	_got(Quests.pickup_kind(d))

# sideItem()
func _got(k: String) -> void:
	if side.is_empty() or side.get("kind") != "collect" or side.get("ready", false) or side.get("item") != k: return
	side["left"] = int(side["left"]) - 1; _side_hud()
	if int(side["left"]) <= 0: _job_ready()

func _on_kill(e) -> void:
	if side.is_empty() or side.get("kind") != "kill" or side.get("ready", false): return
	if side.get("mob") != null and str(side["mob"]) != Shops.kind_of(e): return
	side["left"] = int(side["left"]) - 1; _side_hud()
	if int(side["left"]) <= 0: _job_ready()

func _ready_msg() -> String: return "✅ Task done! Return to [b]%s[/b] for your Turkish lesson reward" % side["npcName"]

func _job_ready() -> void:
	side["ready"] = true; SaveBridge.data["side"] = side; _side_hud()
	hud.toast(_ready_msg(), 6.0); Shops.sfx("yes")
	var T := _tutor(side["npcId"])
	if not T.is_empty(): hud.pin("side", Vector3(T["x"], 1.6, T["z"]), Color("ffd66b"))
	if _cb.is_valid() and Shops.me: Shops.me.clear_items(_cb)
	for m in _mobs: if is_instance_valid(m): m.queue_free()
	_mobs = []
	SaveBridge.write()

func _reward(T: Dictionary) -> void:
	var R: Dictionary = T["reward"]
	if R.has("lira"): Shops.add_lira(int(R["lira"])); Shops.sfx("coin")
	if R.has("xp"): Shops.xp(int(R["xp"]))
	if R.has("ammo"): SaveBridge.data["ammo"] = SaveBridge.get_i("ammo") + int(R["ammo"])
	if R.has("int"): SaveBridge.data["int"] = SaveBridge.get_i("int") + int(R["int"]); Shops.sfx("ding")
	if R.get("mana_full", false): Shops.mana_full(torii)
	if R.has("bandit_cd"):
		Shops.sfx("bark")
		if Skills.me: Skills.me.refresh()          # skills.gd reads npc.banditfriend >= 2 → 18 s
	if T["id"] == "fivesips": Shops.tip("fivesips", "☕ FIVE SIPS IS OPEN", ["Talk to the owner any time to buy cocktails, coffee, a tavla set and backpack food.", "Food waits in your backpack — eat it with [b]H[/b]."])
	if R.has("msg"): hud.toast(_bb(R["msg"]), 7.0)
	if torii.get("dance_t") != null: torii.dance_t = 1.6

# sideHUD(): the job line under the mission (and quest) text
func _side_hud() -> void:
	if side.is_empty(): _line.text = ""; return
	var what := "RETURN! ✅" if side.get("ready", false) else (("defeat %d more" % int(side["left"])) if side["kind"] == "kill" \
		else ("collect %d more %s" % [int(side["left"]), str(side["item"])]))
	_line.text = "[right]🤝 %s: %s[/right]" % [Rich.plain(str(side["npcName"])), what]

# jobs flagged "spawn" bring their own monsters round the tutor while she's there (the suburb is quiet)
func _job_mobs() -> void:
	if side.is_empty() or side.get("ready", false) or side.get("kind") != "kill": return
	var T := _tutor(side["npcId"])
	if T.is_empty() or not T["task"].get("spawn", false): return
	_mobs = _mobs.filter(func(m): return is_instance_valid(m) and m.is_alive())
	if Shops.flat2(torii, T["x"], T["z"]) > 70.0 * 70.0: return
	if _mobs.size() >= mini(3, int(side["left"])): return
	var pool: Array = T["task"].get("pool", ["imp", "zombie", "thot"])
	var kind: String = str(side["mob"]) if side.get("mob") != null else str(pool.pick_random())
	var a := randf() * TAU; var r := randf_range(10.0, 18.0)
	var at := Vector3(T["x"] + cos(a) * r, 0, T["z"] + sin(a) * r)
	at.y = Shops.ground_y(at.x, at.z)
	var e := Enemy.spawn(world, kind, at, torii as CharacterBody3D, randf() < .12)
	if e: _mobs.append(e)

# ---------------------------------------------------------------- Old Soul (soulTalk)
func _mastered(u: int) -> bool:
	var m = SaveBridge.data.get("mastered")
	return m is Dictionary and bool(m.get(str(u), m.get(u, 0)))

func mastered_count() -> int:
	var n := 0
	for s in soul: if _mastered(int(s["N"]["u"])): n += 1
	return n

# soulPaint(): dim purple = locked · cyan = open · green = mastered (and the tutor goes green)
func paint_soul() -> void:
	var U := SaveBridge.get_i("unit", 1)
	for s in soul:
		var u := int(s["N"]["u"])
		var locked := u > U; var done := _mastered(u)
		(s["tag"] as Label3D).modulate = Color("6a5f8a") if locked else (Color("3dff9e") if done else Color("8ff2ff"))
		(s["lock"] as Label3D).visible = locked
		(s["ring"] as MeshInstance3D).visible = done
		if done:
			var b: Node3D = s["body"]
			if not is_instance_valid(b): b = Npc.find_near(Vector3(s["N"]["x"], 0, s["N"]["z"]), 2.6)
			if b is Npc: (b as Npc).tint(Color("b4ffd2"))
			elif is_instance_valid(b):
				for m in b.find_children("*", "MeshInstance3D", true, false):
					var mat = (m as MeshInstance3D).material_override
					if mat is StandardMaterial3D: (mat as StandardMaterial3D).albedo_color = (mat as StandardMaterial3D).albedo_color.lerp(Color("3dff9e"), .55)

func soul_talk(s: Dictionary) -> void:
	var N: Dictionary = s["N"]; var u := int(N["u"]); var U := SaveBridge.get_i("unit", 1)
	if u > U:
		hud.say(N["n"], ["[i]%s[/i]" % N["d"], "Unit %d henüz sıra değil, canım. [i](It is not time for Unit %d yet.)[/i]" % [u, u],
			"Şu an [b]Unit %d[/b]'desin. Kaan'ın görevini bitir, sokakları temizle — sonra buraya gel. [i](You are on Unit %d. Finish Kaan's mission, clear the streets, then come see me.)[/i]" % [U, U]])
		Shops.sfx("no"); return
	var done := _mastered(u)
	var ls: Array = Lessons.me.unit_lessons(u) if Lessons.me else []
	var lines: Array = ["[i]%s[/i]" % N["d"]]
	lines.append_array(_bbs(N["hi"]))
	if done: lines.append("[b][color=#3dff9e]✅ Bu üniteyi zaten ustalaştın. (You have already mastered this unit.)[/color][/b]")
	hud.say(N["n"], lines, func():
		hud.choose(N["n"], "[b]UNIT %d[/b] — %s\n%s" % [u, ls[0]["ut"] if ls.size() else "", "[color=#3dff9e]MASTERED ✅[/color]" if done else "[color=#ffd66b]not yet mastered[/color]"],
			["📖 Dersi tekrar et (review the lesson)", "✍️ Alıştırma (practice — 5 questions)", "🎓 FİNAL SINAVI (final test — 8 questions, need 7)", "Görüşürüz (leave)"],
			func(i: int): _soul_pick(i, s, ls)))

func _soul_pick(i: int, s: Dictionary, ls: Array) -> void:
	var N: Dictionary = s["N"]; var u := int(N["u"])
	if Lessons.me == null or ls.is_empty(): return
	match i:
		0:
			var lines := []
			for L in ls:
				lines.append("[b]%s %s[/b]" % [L["v"], L["t"]])
				for x in L["lines"]: lines.append(_bb(x))
			Lessons.me.quiz.show_lesson("%s — 📖 UNIT %d" % [N["n"], u], lines, func():
				Shops.xp(10); hud.toast("📖 Reviewed Unit %d with %s. +10 XP" % [u, N["n"]], 5.0))
		1:
			var pool: Array = Lessons.me.build_session(ls.pick_random()); pool.shuffle()
			Lessons.me.quiz.run(pool.slice(0, 5), func(_sc): Shops.xp(25); hud.toast("✍️ Practice done — +25 XP", 5.0),
				"✍️ UNIT %d PRACTICE · %s" % [u, N["n"]], true)
		2: _final(s, ls)

# soulFinal(): 8 questions across the whole unit plus anything she has missed; 7 right = mastered
func _final(s: Dictionary, ls: Array) -> void:
	var N: Dictionary = s["N"]; var u := int(N["u"])
	var bank := []
	for L in ls: bank.append_array(Lessons.me.build_session(L))
	var miss: Array = Lessons.me.missed_qs()
	bank.append_array(miss.slice(0, maxi(0, 40 - bank.size())))
	bank.shuffle()
	var seen := {}; var qs := []
	for q in bank:
		var k := Lessons.qkey(q)
		if k == "|" or seen.has(k) or qs.size() >= 8: continue
		seen[k] = true; qs.append(q)
	if qs.is_empty(): return
	var need := mini(7, maxi(1, qs.size() - 1))
	hud.toast("🎓 [b]FİNAL SINAVI · UNIT %d[/b] — %d questions, you need %d. No skipping. İyi şanslar!" % [u, qs.size(), need], 7.0)
	Lessons.me.quiz.run(qs, func(score):
		var right: int = (score as Array).count(true)
		if right >= need: _master(s, right, qs.size())
		else:
			hud.toast("📕 [b]%d/%d[/b] — need %d to master Unit %d. Review with %s and try again, canım." % [right, qs.size(), need, u, N["n"]], 8.0, true)
			Shops.sfx("no"),
		"🎓 FİNAL · UNIT %d · %s" % [u, N["n"]])

func _master(s: Dictionary, right: int, of: int) -> void:
	var N: Dictionary = s["N"]; var u := int(N["u"])
	if not (SaveBridge.data.get("mastered") is Dictionary): SaveBridge.data["mastered"] = {}
	SaveBridge.data["mastered"][str(u)] = 1
	paint_soul()
	Shops.xp(120); Shops.add_lira(120)
	SaveBridge.data["mm"] = SaveBridge.get_i("mm", 100) + 5
	if torii.get("max_mana") != null:
		torii.max_mana = float(torii.max_mana) + 5.0
		if torii.has_signal("stats_changed"): torii.stats_changed.emit()
	hud.banner("🎓 UNIT %d MASTERED\n[font_size=18]+120 XP · +120₺ · %s is proud[/font_size]" % [u, N["n"]])
	hud.toast("🎓 [b]%d/%d — Unit %d MASTERED![/b] %s turns green. Mastered: [b]%d/16[/b]" % [right, of, u, N["n"], mastered_count()], 9.0)
	Shops.sfx("fanfare"); Shops.sfx("chuckle")
	if Fx.me: Fx.me.puff(torii.global_position + Vector3(0, 2, 0), Fx.CONF, 30, 2.0, 4.0, 1.2)
	if torii.get("dance_t") != null: torii.dance_t = 2.2
	if mastered_count() >= 16 and not Shops.npcs().get("allmastered", false):
		Shops.npcs()["allmastered"] = 1
		await get_tree().create_timer(1.2).timeout
		hud.banner("🏆 TÜM KİTAP BİTTİ!\n[font_size=18]All 16 units mastered — you actually learned Turkish ❤[/font_size]")
		Shops.give_weapon("tavlaw"); Shops.add_lira(1000); Shops.xp(500)
		hud.toast("🏆 [b]ALL 16 UNITS MASTERED.[/b] Every NPC at Old Soul is green. +1000₺, +500 XP. Kaan is going to lose his mind.", 14.0)
		Shops.sfx("divine")
	SaveBridge.write()

# advanceUnit(): the toast naming the Old Soul tutor who can test her on the unit that just opened
func _unit_up(now_u: int) -> void:
	for s in soul:
		if int(s["N"]["u"]) == now_u:
			hud.toast("➡️ [b]UNIT %d of 16[/b] is open — and [b]%s[/b] at Old Soul ☕ can now test you on it." % [now_u, s["N"]["n"]], 9.0)
	Shops.sfx("divine")
	if Fx.me and torii: Fx.me.puff(torii.global_position + Vector3(0, 1.6, 0), Fx.CONF, 34, 3.4, 3.6, 1.3)
	paint_soul()

# missionComplete(): Kaan's "Aferin bebeğim!" over his balcony
func _aferin(i: int) -> void:
	if i == _aferin_i: return
	_aferin_i = i
	for n in Npc.all:
		if is_instance_valid(n) and n.mode == "kaan":
			if Fx.me: Fx.me.label(n.global_position + Vector3(0, 2.4, 0), "Aferin bebeğim! ❤ (Well done, baby!)", Color("ff9ecf"), 3.5, true)
			break
	Audio.speak("Aferin bebeğim")

func _process(dt: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for t in tutors:
		var st := _st(t["T"]["id"])
		var mk: Label3D = t["mark"]
		mk.visible = st < 2 or t["T"]["id"] == "fivesips"
		if t["T"]["id"] == "fivesips" and st >= 2: mk.text = "☕"
		elif side.get("npcId") == t["T"]["id"] and side.get("ready", false): mk.text = "✅"
		else: mk.text = "💬"
		mk.position.y = t["y"] + 3.1 + sin(tt * 2.6 + float(t["T"]["x"])) * .12
		if is_instance_valid(t["body"]) and torii and t["body"].global_position.distance_squared_to(torii.global_position) < 3600: Npc.critter_anim(t["body"], tt, false)
	for s in soul:
		if is_instance_valid(s["body"]) and torii and s["body"].global_position.distance_squared_to(torii.global_position) < 1600: Npc.critter_anim(s["body"], tt, false)
	_t -= dt
	if _t > 0: return
	_t = 1.0
	var U := SaveBridge.get_i("unit", 1)
	if U != _last_unit:
		var was := _last_unit; _last_unit = U
		if U > was and was > 0: _unit_up(U)
		else: paint_soul()
	var nx := SaveBridge.get_i("next")
	if nx > _last_next and _last_next >= 0: _aferin(nx - 1)
	_last_next = nx
	if not Overlay.any(): _job_mobs()
