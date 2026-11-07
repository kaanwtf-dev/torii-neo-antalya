# TAVLA — a full, rules-correct backgammon game, ported from 7.2 (TV / d6 / tvNew / tvHome / tvBlocked /
# tvMovesFor / tvApply / tvMaxPlay / tvLegal / tvPip / tvWinner / tvEval / DIFF_SLIP / REPLY_ROLLS / tvOppBest /
# tvBestSeq / zarName, TRK-04) plus the seven tables round the city (TVNPC / buildTavlaTables / makeKaanSeated /
# tavlaInteract, TRK-09) and the match payouts (tvMatchOver, TRK-06). The board screen is tavla_ui.gd.
#   Torii = +1, moves 23 -> 0, bears off below 0, home = 0..5
#   Opponent = -1, moves 0 -> 23, bears off above 23, home = 18..23
#   state = {p: [24 ints], bar: [hers, theirs], off: [hers, theirs]}; a move = {d, from (-1 = bar), to (-99 = off)}
# Dice are fair (Godot's RNG, every face 1/6); nothing is weighted or aware of who's winning — except Kaan,
# who openly re-rolls weak throws three times a game (KAANCHEAT). Saved like 7.2: npc["tavla_<id>"] = "beat",
# npc.tavlaWeapon, lira, xp; a won match counts as one kill toward an open hunt gate.
class_name Tavla
extends Node

static var me: Tavla
var D := {}
var torii: Node3D
var hud: Hud
var world: Node3D
var ui: TavlaUI
var tables: Array = []          # {N, g, opp}

# ================================================================ the engine (pure, static)
static func d6() -> int: return randi_range(1, 6)

static func new_state() -> Dictionary:
	var p := []; p.resize(24); p.fill(0)
	p[23] = 2; p[12] = 5; p[7] = 3; p[5] = 5          # Torii
	p[0] = -2; p[11] = -5; p[16] = -3; p[18] = -5     # opponent
	return {"p": p, "bar": [0, 0], "off": [0, 0]}

static func clone(s: Dictionary) -> Dictionary:
	return {"p": (s["p"] as Array).duplicate(), "bar": (s["bar"] as Array).duplicate(), "off": (s["off"] as Array).duplicate()}

static func bi(pl: int) -> int: return 0 if pl > 0 else 1

static func is_home(s: Dictionary, pl: int) -> bool:
	if int(s["bar"][bi(pl)]) > 0: return false
	var p: Array = s["p"]
	for i in 24:
		var n: int = p[i]
		if pl > 0 and n > 0 and i > 5: return false
		if pl < 0 and n < 0 and i < 18: return false
	return true

static func blocked(s: Dictionary, pl: int, to: int) -> bool:
	var n: int = s["p"][to]
	return n <= -2 if pl > 0 else n >= 2

# every legal single move for player pl with die d
static func moves_for(s: Dictionary, pl: int, d: int) -> Array:
	var out := []
	var b := bi(pl); var p: Array = s["p"]
	if int(s["bar"][b]) > 0:
		var to := 24 - d if pl > 0 else d - 1
		if to >= 0 and to < 24 and not blocked(s, pl, to): out.append({"from": -1, "to": to})
		return out
	var home := is_home(s, pl)
	for i in 24:
		var n: int = p[i]
		if (n <= 0) if pl > 0 else (n >= 0): continue
		var to := i - d if pl > 0 else i + d
		if to >= 0 and to < 24:
			if not blocked(s, pl, to): out.append({"from": i, "to": to})
			continue
		if not home: continue
		var need := i + 1 if pl > 0 else 24 - i          # pips needed to bear this one off
		if need == d: out.append({"from": i, "to": -99}); continue
		if need < d:                                     # overshoot only from the furthest checker
			var furthest := true
			for j in 24:
				var m: int = p[j]
				if (pl > 0 and m > 0 and j > i) or (pl < 0 and m < 0 and j < i): furthest = false; break
			if furthest: out.append({"from": i, "to": -99})
	return out

static func apply(s: Dictionary, pl: int, mv: Dictionary) -> Dictionary:
	var n := clone(s); var b := bi(pl); var o := 1 - b
	var p: Array = n["p"]
	var fr: int = mv["from"]; var to: int = mv["to"]
	if fr == -1: n["bar"][b] = int(n["bar"][b]) - 1
	else: p[fr] = int(p[fr]) - pl
	if to == -99: n["off"][b] = int(n["off"][b]) + 1; return n
	if (pl > 0 and int(p[to]) == -1) or (pl < 0 and int(p[to]) == 1):     # hit a blot
		p[to] = 0; n["bar"][o] = int(n["bar"][o]) + 1; n["hit"] = true
	p[to] = int(p[to]) + pl
	return n

static func _key(s: Dictionary) -> String: return "%s%s%s" % [s["p"], s["bar"], s["off"]]

# how many of the remaining dice can actually be played (memoised)
static func max_play(s: Dictionary, pl: int, dice: Array, memo := {}) -> int:
	if dice.is_empty(): return 0
	var ds := dice.duplicate(); ds.sort()
	var k := _key(s) + str(ds)
	if memo.has(k): return memo[k]
	var best := 0; var seen := {}
	for i in dice.size():
		var d: int = dice[i]
		if seen.has(d): continue
		seen[d] = true
		for m in moves_for(s, pl, d):
			var rest := dice.duplicate(); rest.remove_at(i)
			best = maxi(best, 1 + max_play(apply(s, pl, m), pl, rest, memo))
			if best == dice.size(): memo[k] = best; return best
	memo[k] = best
	return best

# legal moves right now, honouring "use both dice" and "use the larger die" — each {d, from, to}
static func legal(s: Dictionary, pl: int, dice: Array) -> Array:
	var memo := {}
	var mx := max_play(s, pl, dice, memo)
	var out := []
	if mx == 0: return out
	var allowed := dice.duplicate()
	if mx == 1 and dice.size() == 2 and dice[0] != dice[1]:
		var hi := maxi(int(dice[0]), int(dice[1]))
		if not moves_for(s, pl, hi).is_empty(): allowed = [hi]     # the larger die is playable, so it must be used
	var seen := {}
	for d in allowed:
		if seen.has(d): continue
		seen[d] = true
		var i := dice.find(d)
		if i < 0: continue
		var rest := dice.duplicate(); rest.remove_at(i)
		for m in moves_for(s, pl, d):
			if 1 + max_play(apply(s, pl, m), pl, rest, memo) == mx: out.append({"d": d, "from": m["from"], "to": m["to"]})
	return out

static func pip(s: Dictionary, pl: int) -> int:
	var t: int = int(s["bar"][bi(pl)]) * 25
	var p: Array = s["p"]
	for i in 24:
		var n: int = p[i]
		if pl > 0 and n > 0: t += n * (i + 1)
		if pl < 0 and n < 0: t += -n * (24 - i)
	return t

static func winner(s: Dictionary) -> int:
	if int(s["off"][0]) >= 15: return 1
	if int(s["off"][1]) >= 15: return -1
	return 0

# ---- AI ----
static func eval_pos(s: Dictionary, pl: int) -> float:
	var mine_i := bi(pl); var op := 1 - mine_i
	var sc := float(pip(s, -pl) - pip(s, pl))
	sc += (int(s["off"][mine_i]) - int(s["off"][op])) * 12.0
	sc += (int(s["bar"][op]) - int(s["bar"][mine_i])) * 22.0
	var prime := 0; var best := 0
	var p: Array = s["p"]
	for i in 24:
		var n: int = p[i]
		var mine: bool = n > 0 if pl > 0 else n < 0
		var cnt := absi(n)
		if mine and cnt >= 2:
			sc += 4.0; prime += 1; best = maxi(best, prime)
			if (i <= 5) if pl > 0 else (i >= 18): sc += 7.0
		else: prime = 0
		if mine and cnt == 1:                        # blots are risky
			var dist := 24 - i if pl > 0 else i + 1
			sc -= 9.0 - minf(6.0, absf(12.0 - dist) * .4)
	sc += best * best * 1.5
	return sc

# difficulty 1-10 -> how often the AI takes a worse line. Above 10 it never slips AND looks a move ahead
const DIFF_SLIP := [.52, .46, .40, .33, .27, .20, .14, .09, .04, 0.0]
const REPLY_ROLLS := [[6, 5], [6, 6], [5, 3], [4, 2], [3, 1], [2, 1]]

static func _dice_of(a: int, b: int) -> Array: return [a, a, a, a] if a == b else [a, b]

# every complete play (the longest ones, larger-die rule): [{path, st}]; same position + same dice left = one branch
static func plays(s: Dictionary, pl: int, dice: Array) -> Array:
	var out := []
	_walk(s, pl, dice, [], out, {})
	var mx := 0
	for r in out: mx = maxi(mx, (r["path"] as Array).size())
	if mx == 0: return []
	var res := out.filter(func(r): return (r["path"] as Array).size() == mx)
	if mx == 1 and dice.size() == 2 and dice[0] != dice[1]:
		var hi := maxi(int(dice[0]), int(dice[1]))
		var wh := res.filter(func(r): return int(r["path"][0]["d"]) == hi)
		if wh.size(): res = wh
	return res

static func _walk(s: Dictionary, pl: int, dice: Array, path: Array, out: Array, seen: Dictionary) -> void:
	var any := false; var tried := {}
	for i in dice.size():
		var d: int = dice[i]
		if tried.has(d): continue
		tried[d] = true
		for m in moves_for(s, pl, d):
			any = true
			var ns := apply(s, pl, m)
			var rest := dice.duplicate(); rest.remove_at(i)
			var k := _key(ns) + str(rest)
			if seen.has(k): continue
			seen[k] = true
			_walk(ns, pl, rest, path + [{"d": d, "from": m["from"], "to": m["to"]}], out, seen)
	if not any: out.append({"path": path, "st": s})

# one move of lookahead: how good is the average best reply the other side could have?
static func opp_best(st: Dictionary, pl: int) -> float:
	var tot := 0.0; var n := 0
	for r in REPLY_ROLLS:
		var ps := plays(st, -pl, _dice_of(r[0], r[1]))
		n += 1
		if ps.is_empty(): continue
		var best := -1e9
		for q in ps: best = maxf(best, eval_pos(q["st"], -pl))
		tot += best
	return tot / n if n else 0.0

static func best_seq(s: Dictionary, pl: int, dice: Array, skill: float, deep: bool) -> Array:
	var res := plays(s, pl, dice)
	if res.is_empty(): return []
	for r in res: r["v"] = eval_pos(r["st"], pl)
	res.sort_custom(func(a, b): return a["v"] > b["v"])
	if deep and res.size() > 1:                          # beyond 10/10 he also weighs your best reply
		var top := res.slice(0, 3)
		for r in top: r["v2"] = float(r["v"]) - opp_best(r["st"], pl) * .55
		top.sort_custom(func(a, b): return a["v2"] > b["v2"])
		return top[0]["path"]
	var slip: float = DIFF_SLIP[clampi(roundi(skill), 1, 10) - 1]
	if slip > 0 and randf() < slip and res.size() > 1:
		return res[mini(res.size() - 1, 1 + randi() % 2)]["path"]
	return res[0]["path"]

# ---- Turkish tavla jargon (zarName) ----
static func zar_name(a: int, b: int) -> String:
	var Z: Array = me.D["ZAR"] if me else ["", "yek", "dü", "se", "cihar", "penç", "şeş"]
	if a == b: return "%s (double %d)" % [me.D["DBL"][str(a)] if me else str(a), a]
	var hi := maxi(a, b); var lo := mini(a, b)
	if hi == 6 and lo == 5: return "şeşbeş (6-5)"
	if hi == 6 and lo == 1: return "şeşyek (6-1)"
	if hi == 5 and lo == 3: return "pençüse (5-3)"
	return "%s-%s (%d-%d)" % [Z[hi], Z[lo], hi, lo]

static func diff_stars(d: int) -> String:
	return ("●".repeat(10) + " +%d" % (d - 10)) if d > 10 else ("●".repeat(d) + "○".repeat(10 - d))

# ================================================================ the tables in the city
func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	me = self; world = w; torii = p; hud = h
	randomize()
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/tavla.json"))
	ui = TavlaUI.new(); ui.name = "TavlaUI"; add_child(ui); ui.setup(self)
	for N in D["TVNPC"]: tables.append(_table(N))

static var _board_tex: ImageTexture
static func board_tex() -> ImageTexture:
	if _board_tex: return _board_tex
	var W := 128; var H := 64
	var im := Image.create(W, H, false, Image.FORMAT_RGBA8)
	im.fill(Color("8e5a32"))
	var f := 3; var b := 6; var hw := (W - 2 * f - b) / 2
	im.fill_rect(Rect2i(f, f, hw, H - 2 * f), Color("2f6b45")); im.fill_rect(Rect2i(f + hw + b, f, hw, H - 2 * f), Color("2f6b45"))
	var pw := hw / 6.0; var tl := int(H * .4)
	for half in 2:
		for i in 6:
			var x0 := f + half * (hw + b) + i * pw
			for top in [1, 0]:
				var c := Color("e8d7b0") if (i + top) % 2 else Color("9a3040")
				for yy in tl:
					var w2 := (pw - 1) * (1.0 - yy / float(tl)) / 2.0
					var cx := x0 + pw / 2.0
					var y: int = f + yy if top else H - f - 1 - yy
					for xx in range(int(cx - w2), int(cx + w2) + 1): im.set_pixel(clampi(xx, 0, W - 1), y, c)
	im.fill_rect(Rect2i(f + hw, f, b, H - 2 * f), Color("5a341c"))
	_board_tex = ImageTexture.create_from_image(im)
	return _board_tex

func _table(N: Dictionary) -> Dictionary:
	var g := Node3D.new(); world.add_child(g)
	var y := Shops.ground_y(N["x"], N["z"])
	g.position = Vector3(N["x"], y, N["z"])
	var wood := Color("7a4a2b"); var leg := Color("5a3520")
	MobModels.box(g, Vector3(2.2, .16, 1.6), Vector3(0, .95, 0), wood)
	var brd := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.9, .04, 1.3); brd.mesh = bm
	var bmat := StandardMaterial3D.new(); bmat.albedo_texture = board_tex(); bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX; brd.material_override = bmat; brd.position.y = 1.045; g.add_child(brd)
	# the opening position, a few stacks of checkers + a pair of dice
	var START := [[1, 5, 1, 2, 0], [-1, 0, 1, 5, 1], [-1, 4, 1, 3, 0], [1, 0, 1, 5, 0], [1, 5, -1, 2, 1], [-1, 0, -1, 5, 0], [-1, 4, -1, 3, 1], [1, 0, -1, 5, 1]]
	for st in START:
		for i in int(st[3]):
			MobModels.cyl(g, .056, .056, .024, Vector3(st[0] * (.048 + .1417 * (st[1] + .5)), 1.077, st[2] * (.523 - i * .112)), Color("3a1418") if st[4] else Color("f2ead8"), Vector3.ZERO, 8)
	MobModels.box(g, Vector3(.055, .055, .055), Vector3(.42, 1.093, .05), Color("f6f2ea"), Vector3(0, .4, 0))
	MobModels.box(g, Vector3(.055, .055, .055), Vector3(.54, 1.093, -.06), Color("f6f2ea"), Vector3(0, 1.1, 0))
	for sx in [-1, 1]: for sz in [-1, 1]: MobModels.cyl(g, .06, .05, .95, Vector3(.9 * sx, .47, .6 * sz), leg)
	MobModels.cyl(g, .33, .3, .5, Vector3(0, .25, 1.5), Color("8a5a34"), Vector3.ZERO, 10)        # her stool
	MobModels.cyl(g, .33, .3, .5, Vector3(0, .25, -1.5), Color("8a5a34"), Vector3.ZERO, 10)       # theirs
	var opp: Node3D
	if N["id"] == "kaan":
		var n := Npc.new(); g.add_child(n); n.setup("male", "res://assets/npc/male_base.png", 1.0, torii)
		n.npc_name = "KAAN ❤"; n.position = Vector3(0, 0, -1.2); n.sit_at(0.0, 1.0)
		opp = n
		MobModels.cyl(g, .04, .03, .1, Vector3(1.0, 1.08, -.55), Color("d4552a"), Vector3.ZERO, 6, true)   # çay
		var heart := Shops.sign3d("❤", Color("ff2d5e"), 90); heart.position.y = 2.5; g.add_child(heart)
	else:
		var path := "res://assets/imp/imp.glb" if N["mob"] == "imp" else "res://assets/mobs/%s.glb" % N["mob"]
		opp = MobModels.build(N["mob"])
		if opp == null and ResourceLoader.exists(path):
			opp = (load(path) as PackedScene).instantiate(); Tint.apply(opp)
		if opp == null: opp = Npc.critter("golddog")
		opp.position = Vector3(0, .25, -1.5); g.add_child(opp)
	var s1 := Shops.sign3d("⚂ TAVLA", Color("ffd66b"), 80); s1.position.y = 2.9; g.add_child(s1)
	var s2 := Shops.sign3d(N["name"], Color("8ff2ff"), 48); s2.position.y = 2.25; g.add_child(s2)
	var beat := Shops.sign3d("🏆", Color("ffd66b"), 50); beat.position = Vector3(.9, 2.9, 0); g.add_child(beat); beat.name = "beat"
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(2.3, 1.1, 1.7)
	cs.shape = bx; cs.position.y = .55; sb.add_child(cs); g.add_child(sb)
	return {"N": N, "g": g, "opp": opp, "beat": beat}

func _near(p: Node3D) -> Dictionary:
	for t in tables:
		if Shops.flat2(p, t["N"]["x"], t["N"]["z"]) < 16: return t
	return {}

func prompt(p: Node3D) -> String:
	var t := _near(p)
	if t.is_empty(): return ""
	return "E: ⚂ TAVLA with %s%s" % [t["N"]["name"], " 🏆" if beaten(t["N"]["id"]) else ""]

static func beaten(id: String) -> bool: return str(Shops.npcs().get("tavla_" + id, "")) == "beat"

# tavlaInteract(): the intro, then the bet screen
func try_interact(p: Node3D) -> bool:
	var t := _near(p)
	if t.is_empty(): return false
	var N: Dictionary = t["N"]; var bt := beaten(N["id"])
	if N["id"] == "kaan":
		hud.say("⚂ KAAN ❤", ["[i]%s[/i]" % N["title"], "Otur bebeğim. ☕ [i](Sit down, baby.)[/i]",
			"Beni bir kere yendin. Bir kere. Hatırlatmayı bırak. [i](You beat me once. Once. Stop bringing it up.)[/i]" if bt else "Sana tavlayı ben öğrettim. Bunu unutma. [i](I taught you tavla. Don't forget that.)[/i]",
			"⚠️ Ve evet — zarı üç kere tekrar atacağım. Nişanlı ayrıcalığı. [i](And yes — I get three re-rolls. Fiancé privileges.)[/i]",
			"Kazanırsan... çok gurur duyarım. Ama kazanamayacaksın. 😘"], func(): ui.open_bet(N))
	else:
		hud.say("⚂ " + N["name"], ["[i]%s[/i]" % N["title"],
			"Yine mi sen? Bu sefer kaybetmem. [i](You again? I won't lose this time.)[/i]" if bt else "Tavla bilir misin? [i](Do you know backgammon?)[/i] Otur bakalım.",
			"Kurallar gerçek: kırık taş bara gider, kapı geçilmez, mars iki sayar. [i](Real rules: hit checkers go to the bar, made points block you, a gammon counts double.)[/i]"],
			func(): ui.open_bet(N))
	Shops.tip("tavla", "⚂ TAVLA · BACKGAMMON", ["Real rules, real dice. Click a checker, then where it goes (or drag it). Right-click / [b]Z[/b] / Backspace undoes a move.",
		"Before every game: 5 Turkish questions. Right answers earn [b]zar hakkı[/b] — re-rolls for that game. Your old mistakes come back here.",
		"Bet lira, win double. A won match counts as a kill for your hunt."])
	return true

func opp_pos(id: String) -> Vector3:
	for t in tables: if t["N"]["id"] == id: return (t["g"] as Node3D).global_position
	return torii.global_position if torii else Vector3.ZERO

# tvMatchOver(): payouts
func match_over(M: Dictionary) -> void:
	var N: Dictionary = M["npc"]; var won: bool = int(M["my"]) > int(M["opp"])
	var stake := int(M["stake"])
	if won:
		var prize := stake * 2
		Shops.add_lira(prize); Shops.xp(70 + int(N["diff"]) * 30)
		Shops.npcs()["tavla_" + str(N["id"])] = "beat"
		if N["id"] == "kaan":
			hud.banner("🏆 SEN KAAN'I YENDİN\n[font_size=18]15/10, three cheats, and you still beat him ❤[/font_size]")
			hud.toast("❤ [b]You beat Kaan.[/b] He is quiet. He is proud. He will pretend the dice were against him for weeks. [i]+%d₺[/i]" % prize, 12.0)
			Shops.add_lira(500); Shops.xp(400)
		else: hud.banner("🏆 TAVLA GALİBİYETİ!\n[font_size=18]You beat %s %d–%d[/font_size]" % [N["short"], int(M["my"]), int(M["opp"])])
		hud.toast("🏆 [b]Match won %d–%d![/b]%s+XP · [i]tavla[/i] mastery 🎲" % [int(M["my"]), int(M["opp"]), (" +%d₺ " % prize) if stake else " "], 8.0)
		Shops.sfx("fanfare"); Shops.sfx("chuckle")
		if torii.get("dance_t") != null: torii.dance_t = 2.4
		# beating a monster at tavla is beating a monster: one kill toward the open hunt
		if Shops.gate_needs() > 0:
			var left := Shops.gate_credit(false, "tavla")
			hud.toast("⚂ [b]Tavla sayılır![/b] That match counted as a kill toward your hunt — %d left." % maxi(0, left), 6.0)
		var weap: Array = SaveBridge.data["weap"] if SaveBridge.data.get("weap") is Array else []
		if not weap.has("tavlaw") and not Shops.npcs().get("tavlaWeapon", false):
			Shops.npcs()["tavlaWeapon"] = 1; Shops.give_weapon("tavlaw")
			hud.banner("⚂ TAVLA BOARD UNLOCKED\n[font_size=18]A champion's weapon[/font_size]")
	else:
		Shops.add_lira(-stake)
		hud.banner("😤 MAÇI KAYBETTİN\n[font_size=18]Lost %d–%d[/font_size]" % [int(M["my"]), int(M["opp"])])
		hud.toast("😤 Match lost %d–%d%s — [i]rövanş?[/i] (rematch?) Come back any time." % [int(M["my"]), int(M["opp"]), (" · −%d₺" % stake) if stake else ""], 7.5)
		Shops.sfx("no")
	Shops.teach("tavla"); SaveBridge.write()

func _process(_dt: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for t in tables:
		(t["beat"] as Label3D).visible = beaten(t["N"]["id"])
		var o: Node3D = t["opp"]
		if is_instance_valid(o) and not (o is Npc) and torii and o.global_position.distance_squared_to(torii.global_position) < 900:
			o.position.y = .25 + absf(sin(tt * 1.7 + float(t["N"]["x"]))) * .03       # fidgeting on the stool
