# The Turkish course, ported from 7.2: all 16 units of Teach Yourself Turkish, 3 lesson parts each.
# Every 5 kills a lesson is ready; it starts as soon as it's safe (no monster close, not racing on the
# bike). K tests out of it with 3 questions (3/3 = skipped, +20 XP). After a unit's 3 parts, lessons
# become revision. Words she meets are taught (toast + spoken) and every 4 new words there's a vocab
# quiz; from level 4 a grammar question can join it. Right answers +15 XP, wrong ones -6 HP and go on
# the "missed" list (7.2's tavla replays it later). Progress lives in torii_save exactly like 7.2:
# lesson, lk, unit, ul, words, missed.
class_name Lessons
extends Node

static var me: Lessons
var data := {}
var course: Array = []          # flattened UNITS: {u, ut, part, t, v, lines, qs}
var torii: CharacterBody3D
var hud: Hud
var quiz: QuizUI
var pend := false               # a lesson is ready
var active := false
var cur_lesson := {}
var skipping := false
var quiz_pend := false
var new_words := 0

func setup(p: CharacterBody3D, h: Hud, q: QuizUI) -> void:
	me = self; torii = p; hud = h; quiz = q
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/lessons/turkish.json"))
	for u in data["UNITS"]:
		var part := 0
		for l in u["ls"]:
			part += 1
			var L: Dictionary = l.duplicate(); L["u"] = int(u["n"]); L["ut"] = u["tt"]; L["part"] = part
			course.append(L)
	quiz.answered.connect(_on_answer)

# ---- save fields (same names as 7.2) ----
func _gi(k: String, d := 0) -> int: return SaveBridge.get_i(k, d)
func _words() -> Array: return SaveBridge.data.get("words", [])
func unit() -> int: return max(1, _gi("unit", 1))
func unit_lessons(u: int) -> Array: return course.filter(func(L): return L["u"] == u)

func xp(n: int) -> void:
	var up := SaveBridge.gain_xp(n)
	if up:
		hud.banner("LEVEL %d ✨" % SaveBridge.get_i("lvl", 1))
		torii.max_hp = SaveBridge.get_i("mh", 100); torii.heal_full()

# ---- every 5 kills (lessonTick) ----
func lesson_tick() -> void:
	SaveBridge.data["lk"] = _gi("lk") + 1
	if _gi("lk") >= 5:
		SaveBridge.data["lk"] = 0; pend = true
		hud.toast("📖 New Turkish lesson ready — or press [K] to test out of it with 3 questions", 6.0)

func safe() -> bool:
	if QuizUI.open or hud.box.visible or torii.hp <= 0: return false
	if torii.on_bike and torii.bspeed > 4: return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_squared_to(torii.global_position) < 150: return false
	return true

func _process(_dt: float) -> void:
	if pend and not skipping and safe():
		pend = false; next_lesson()
	elif quiz_pend and safe():
		quiz_pend = false; new_words = 0; _vocab_quiz()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_K and (active or pend) and not skipping:
		try_skip()

# ---- a lesson (nextLesson / startLessonBody) ----
func next_lesson() -> void:
	var ls := unit_lessons(unit())
	if ls.is_empty(): return
	var ul := _gi("ul")
	if ul >= ls.size():
		var L2: Dictionary = ls.pick_random()
		hud.toast("📖 Unit %d pratiği — you've had all three lessons, so this is revision." % unit(), 6.0)
		quiz.run(build_session(L2).slice(0, 5), func(_s):
			xp(20); SaveBridge.write()
			hud.toast("✍️ Revision done — +20 XP. Finish Kaan's mission to reach Unit %d." % (unit() + 1), 7.0),
			"✍️ UNIT %d REVISION" % unit())
		return
	var L: Dictionary = ls[ul]
	SaveBridge.data["ul"] = ul + 1
	SaveBridge.data["lesson"] = max(_gi("lesson"), course.find(L) + 1)
	cur_lesson = L; active = true
	hud.banner("📖 UNIT %d · part %d/3" % [L["u"], L["part"]])
	_lesson_body(L)

func _lesson_body(L: Dictionary) -> void:
	var lines: Array = ["[b]%s %s[/b]" % [L["v"], L["t"]]]
	lines.append_array(L["lines"])
	quiz.show_lesson("📖 UNIT %d (%d/3) — %s" % [L["u"], L["part"], L["ut"]], lines, func():
		quiz.run(build_session(L), func(score):
			xp(25); var rw := _reward(); _summary(score); _finish_lesson()
			hud.toast("🎓 Unit %d, part %d complete! +25 XP · %s" % [L["u"], L["part"], rw], 7.5),
			"📖 UNIT %d · PART %d/3" % [L["u"], L["part"]]))

func _finish_lesson() -> void:
	active = false; cur_lesson = {}; SaveBridge.write()

func _reward() -> String:
	match randi() % 3:
		0: torii.hp = min(torii.max_hp, torii.hp + 30); torii.hp_changed.emit(torii.hp, torii.max_hp); return "+30 HP ❤"
		1: SaveBridge.data["lira"] = _gi("lira") + 45; return "+45₺ 💰"
		_: SaveBridge.data["ammo"] = _gi("ammo") + 2; return "+2 nazar beads 🧿"

func _summary(score: Array) -> void:
	if score.size() <= 2: return
	var right := score.count(true)
	hud.toast("📊 Quiz done: %d/%d correct%s" % [right, score.size(),
		" — MÜKEMMEL! Perfect! 🌟" if right == score.size() else (" — Aferin! 👏" if right >= score.size() * .7 else " — keep going, you'll get it 💪")], 7.0)
	if right == score.size(): xp(40)

# ---- K: prove you already know it with 3 questions (trySkipLesson) ----
func try_skip() -> void:
	var started := active
	var L: Dictionary = cur_lesson
	if not started:
		var ls := unit_lessons(unit())
		if _gi("ul") >= ls.size(): return
		L = ls[_gi("ul")]
	skipping = true; pend = false
	var qs: Array = build_session(L); qs.shuffle()
	quiz.run(qs.slice(0, 3), func(score):
		skipping = false
		if score.count(true) >= 3:
			if not started:
				SaveBridge.data["ul"] = _gi("ul") + 1; SaveBridge.data["lesson"] = _gi("lesson") + 1
			xp(20); hud.banner("⏭ LESSON SKIPPED")
			hud.toast("⏭ Skipped Unit %d part %d — 3/3 correct. +20 XP. Aferin! 👏" % [L["u"], L["part"]], 7.5)
			_finish_lesson()
		else:
			hud.toast("📖 Got %d/3 — close, but let's go through this one properly." % score.count(true), 6.5)
			if started: _lesson_body(L)
			else: pend = true,
		"⏭ SKIP TEST · 3 QUESTIONS")

# ---- buildSession: the lesson's own questions, then the unit pool; 10, shuffled, no repeats ----
func build_session(L: Dictionary) -> Array:
	var out := []; var seen := {}
	var push := func(q: Dictionary):
		var key: String = str(q.get("q", q.get("f", " ".join(q.get("w", [])))))
		if key == "" or seen.has(key): return
		seen[key] = true
		if q.has("o"): out.append({"kind": "mc", "vis": L["v"], "text": q["q"], "opts": q["o"], "a": int(q.get("a", 0)), "expl": q.get("x", "")})
		elif q.has("f"): out.append({"kind": "fill", "vis": "✍️", "text": q["f"].replace("___", "[b][color=#7bf7ff]___[/color][/b]"), "answer": q["a"], "expl": q.get("x", "")})
		elif q.has("w"): out.append({"kind": "order", "vis": "🔤", "text": "Put the sentence in the correct Turkish order:", "words": q["w"], "expl": q.get("x", "")})
	for q in L.get("qs", []): push.call(q)
	var pool: Array = data["POOLS"].get(str(L["u"]), []).duplicate(); pool.shuffle()
	for q in pool: push.call(q)
	out.shuffle()
	return out.slice(0, 10)

# ---- every answer (finishQ) ----
func _on_answer(ok: bool, q: Dictionary) -> void:
	var key: String = str(q.get("text", "")) + "|" + " ".join(q.get("words", []))
	var missed: Array = SaveBridge.data.get("missed", [])
	if ok:
		xp(15)
		missed = missed.filter(func(m): return m.get("k", "") != key)
	else:
		torii.hp = max(5, torii.hp - 6); torii.hp_changed.emit(torii.hp, torii.max_hp)
		if not missed.any(func(m): return m.get("k", "") == key):
			missed.append({"k": key, "q": q})
			if missed.size() > 30: missed.pop_front()
	SaveBridge.data["missed"] = missed

# ---- words (teach) and the vocab quiz every 4 new ones (maybeQuiz) ----
func teach(tr: String) -> void:
	var words := _words()
	if words.has(tr): return
	var w = null
	for x in data["WORDS"]:
		if x["tr"] == tr: w = x; break
	if w == null: return
	words.append(tr); SaveBridge.data["words"] = words
	hud.toast("%s  %s = %s 🇹🇷" % [w["e"], String(w["en"]).to_upper(), w["tr"]], 7.5)
	Tts.say(w["tr"]); xp(3)
	new_words += 1
	if new_words >= 4: quiz_pend = true

func _vocab_q(pool: Array) -> Dictionary:
	var target: Dictionary = pool.pick_random()
	var same: Array = data["WORDS"].filter(func(w): return w["t"] == target["t"] and w != target)
	var dis := []
	while dis.size() < 3 and same.size() >= 3:
		var c = same.pick_random()
		if not dis.has(c): dis.append(c)
	var en := randf() < .5
	var o := [target] + dis
	return {"kind": "mc", "vis": target["e"], "say": target["tr"], "a": 0,
		"text": ("How do you say \"[b]%s[/b]\" in Turkish?" % target["en"]) if en else ("What does \"[b]%s[/b]\" mean?" % target["tr"]),
		"opts": o.map(func(x): return x["tr"] if en else x["en"])}

func _vocab_quiz() -> void:
	var learned: Array = data["WORDS"].filter(func(w): return _words().has(w["tr"]))
	var pool: Array = learned if learned.size() >= 5 else data["WORDS"].filter(func(w): return w["t"] == 1)
	var qs := [_vocab_q(pool)]
	if _gi("lvl", 1) >= 4 and randf() < .45:
		var g: Dictionary = data["GQ"].pick_random()
		qs.append({"kind": "mc", "vis": "✍️", "text": g["q"], "opts": g["opts"], "a": int(g["a"]), "expl": g.get("expl", "")})
	quiz.run(qs, func(_s): SaveBridge.write())
