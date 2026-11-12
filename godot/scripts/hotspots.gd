# Kaan's monster service and the ways around it, ported from 7.2:
#  · the front door of Midtown Ev (DOORXZ / DOORUP / updateDoor, STY-30): walk into it and she's up on the
#    balcony with Kaan; walk into it up there and she's back on the street (teaches kapı / merdiven).
#  · KAAN'S CONTRACTS (HOTSPOTS / CONTRACTS / HIRE / KAANLINES / offerContracts / pickSpecies / pickCount /
#    startBounty / updateBounty / finishBounty, PRG-21): E on Kaan up there while a hunt gate is open. Pick a
#    species (the gate's own one pinned on top, paged 5 at a time), then how many (never more than the hunt
#    still wants), pay the finder's fee, and they wait at one of 18 city spots. They appear when she's within
#    48 m and each kill counts toward the gate. Saved like 7.2 in `bounty` {place,x,z,left,total,cost,type,tag}.
#  · the airport GATE AGENT (openTravel / travelTo / ZAIR, STY-17/18): E at (-10, 94) flies her to Cameroon /
#    Arizona / Livermore once those missions have started (or in free play); E at the airstrip abroad flies her
#    home. Dark fade + woosh, she's put down at the zone's spawn and Bandit comes along.
class_name Hotspots
extends Node

static var me: Hotspots
var D := {}
var torii: Node3D
var hud: Hud
var world: Node3D
var bounty := {}                # 7.2's S.bounty (+ spawned / mobs, not saved)
var _mobs: Array = []
var _line: RichTextLabel
var _door_cd := 0.0
var _t := 0.0

const DOORXZ := Vector2(-24, -18.2)
const DOORUP := Vector2(-24, -16.4)
const KD := {"x0": -26.0, "x1": -20.0, "z0": -19.0, "z1": -14.8, "y": 5.85}
const AIRPORT := Vector2(-10, 94)
const ZAIR := {"cam": Vector2(628, 8), "az": Vector2(628, 308), "liv": Vector2(628, -292)}
const ZSPAWN := {"city": Vector2(-10, 92), "cam": Vector2(622, 0), "az": Vector2(622, 300), "liv": Vector2(622, -300)}
const ZNAME := {"cam": "CAMEROON 🇨🇲 — Dede's homeland", "az": "ARIZONA 🌵 — Grandma's desert", "liv": "LIVERMORE 🍇 — the hometown"}

func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	me = self; world = w; torii = p; hud = h
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/side/hotspots.json"))
	var layer := CanvasLayer.new(); layer.layer = 3; add_child(layer)
	_line = Shops.rich("", 15, Color("ff9ecf"), 450); Shops.pin_right(_line, Vector2(500, 140), 450)
	_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); _line.add_theme_constant_override("outline_size", 6)
	layer.add_child(_line)
	var ds := Shops.sign3d("MİDTOWN EV · KAPI 🚪", Color("ffd66b"), 48); ds.position = Vector3(DOORXZ.x, 3.6, DOORXZ.y + .4); world.add_child(ds)
	var ga := Shops.sign3d("✈️ GATE AGENT", Color("8ff2ff"), 56); ga.position = Vector3(AIRPORT.x, Shops.ground_y(AIRPORT.x, AIRPORT.y) + 3.0, AIRPORT.y); world.add_child(ga)
	for z in ZAIR:
		var a: Vector2 = ZAIR[z]
		var hs := Shops.sign3d("✈️ HOME · EVE DÖN", Color("8ff2ff"), 56); hs.position = Vector3(a.x, Shops.ground_y(a.x, a.y) + 3.0, a.y); world.add_child(hs)
	_deck()
	var b = SaveBridge.data.get("bounty")
	if b is Dictionary and int(b.get("left", 0)) > 0: bounty = b.duplicate(); bounty["spawned"] = false
	_hud_line()

# 7.2 made the balcony deck walkable with balconyY(); if the exported city has no floor up there, add one
func _deck() -> void:
	var cx: float = (KD["x0"] + KD["x1"]) / 2.0; var cz: float = (KD["z0"] + KD["z1"]) / 2.0
	var top := Shops.ground_y(cx, cz, KD["y"] + 1.5)
	if top > KD["y"] - .6: return
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(KD["x1"] - KD["x0"], .3, KD["z1"] - KD["z0"]); cs.shape = bx; sb.add_child(cs)
	sb.position = Vector3(cx, KD["y"] - .15, cz); world.add_child(sb)

static func _flat(p: Node3D, v: Vector2) -> float: return Shops.flat2(p, v.x, v.y)

func _zone() -> String:
	if torii.global_position.x < 400: return "city"
	var best := "cam"; var bd := INF
	for z in ZAIR:
		var d := _flat(torii, ZAIR[z])
		if d < bd: bd = d; best = z
	return best

func _kaan() -> Npc:
	for n in Npc.all:
		if is_instance_valid(n) and n.mode == "kaan": return n
	return null

# ---------------------------------------------------------------- E
func prompt(p: Node3D) -> String:
	if _near_kaan(p): return "E: 📞 KAAN ❤ — " + ("find monsters for your hunt" if Shops.gate_needs() > 0 or not bounty.is_empty() else "sit a while")
	if _zone() == "city" and _flat(p, AIRPORT) < 9: return "E: ✈️ GATE AGENT — fly somewhere"
	if _zone() != "city" and _flat(p, ZAIR[_zone()]) < 12: return "E: ✈️ fly home"
	return ""

# 7.2's interact(): Kaan's contracts right after the bike; the airport near the end (after the props)
func try_interact(p: Node3D) -> bool: return try_kaan(p) or try_travel(p)

func _near_kaan(p: Node3D) -> bool:
	if _zone() != "city" or p.global_position.y < 4.5: return false
	var k := _kaan()
	return k != null and k.global_position.distance_squared_to(p.global_position) < 20.0 + 9.0

func try_kaan(p: Node3D) -> bool:
	if not _near_kaan(p): return false
	offer(); return true

func try_travel(p: Node3D) -> bool:
	if _zone() == "city":
		if _flat(p, AIRPORT) >= 9: return false
		open_travel(); return true
	if _flat(p, ZAIR[_zone()]) < 12:
		travel("city"); return true
	return false

# ---------------------------------------------------------------- the door (updateDoor)
func _door(dt: float) -> void:
	if _door_cd > 0: _door_cd -= dt; return
	if Overlay.any() or _zone() != "city" or torii.get("on_bike") or torii.get("dead"): return
	if _flat(torii, DOORXZ) > 2.9: return
	var up := torii.global_position.y > 4.0
	_door_cd = 1.1
	if Fx.me: Fx.me.puff(torii.global_position + Vector3(0, 1.2, 0), [Color("ffd66b"), Color("ff5fa2")], 12, 1.1, 1.6, .7)
	Shops.sfx("drop")
	if up:
		_put(Vector3(DOORUP.x, Shops.ground_y(DOORUP.x, DOORUP.y, 3.0) + .1, DOORUP.y))
		hud.toast("🚪 [b]Aşağı indin.[/b] Back down to the street.", 3.0)
	else:
		_put(Vector3(DOORUP.x, KD["y"] + .1, DOORUP.y))
		hud.toast("🚪 [b]Yukarı çıktın[/b] — Kaan is on the balcony. [i]merdiven[/i] = stairs · [i]kapı[/i] = door.", 4.5)
		Shops.teach("kapı"); Shops.teach("merdiven")
	if Fx.me: Fx.me.puff(torii.global_position + Vector3(0, 1.2, 0), [Color("ffd66b"), Color("ff5fa2")], 12, 1.1, 1.6, .7); Fx.me.shake(.12)

func _put(at: Vector3) -> void:
	torii.global_position = at
	if torii is CharacterBody3D: (torii as CharacterBody3D).velocity = Vector3.ZERO
	if torii.has_method("snap_camera"): torii.call("snap_camera")

# ---------------------------------------------------------------- Kaan's contracts
func _gate() -> Dictionary:
	if Missions.me == null: return {}
	return Missions.me.gate

func _mob_name(k) -> String:
	if k == null: return "monster"
	if Missions.me and Missions.me.D.get("enemies", {}).has(k): return str(Missions.me.D["enemies"][k].get("name", k))
	return str(k)

func _hire_of(k) -> Dictionary:
	for h in D["HIRE"]: if h["k"] == k: return h
	return D["HIRE"][0]

func _price(n: int, h: Dictionary) -> int: return int(round(n * int(D["FEE_PER"]) * float(h["m"]) / 10.0)) * 10

func offer() -> void:
	if not bounty.is_empty():
		var B := bounty
		hud.say("KAAN ❤ (balkon)", ["Hâlâ bekliyorlar, canım. [i](They are still waiting, my love.)[/i]",
			"Go to [b]%s[/b] — [b]%d × %s[/b] still there. It is [b]%dm[/b] away." % [B["place"], int(B["left"]), B.get("tag", "monster"), roundi(sqrt(Shops.flat2(torii, B["x"], B["z"])))],
			"[i]Acele etme, dikkatli ol.[/i] — Don't rush. Be careful."])
		return
	if Shops.gate_needs() <= 0:
		hud.say("KAAN ❤ (balkon)", ["Gel, otur biraz. 😌 [i](Come, sit a while.)[/i]",
			"You are not waiting on a hunt right now, so there is nothing for me to arrange. Go and do your mission, canım — and when Bandit's people ask you to clear something out, come back and I will find them for you.",
			"[i]Ben buradayım.[/i] — I am right here."])
		return
	_species(0)

# step 1: WHAT should turn up (the hunt's own species pinned on top)
func _species(page: int) -> void:
	var need = _gate().get("type")
	var rest: Array = (D["HIRE"] as Array).filter(func(h): return h["k"] != need)
	if need != null: rest.push_front(_hire_of(need))
	var per := 5; var pages := ceili(rest.size() / float(per))
	page = ((page % pages) + pages) % pages
	var sl: Array = rest.slice(page * per, page * per + per)
	var opts := []
	for h in sl: opts.append(("⚑ " if need != null and h["k"] == need else "") + "%s %s  ·  %d₺ each" % [h["e"], h["n"], _price(1, h)])
	opts.append("▶ Başka türler · Other species  (%d/%d)" % [page + 1, pages])
	var gl := ("[b][color=#ffd66b]⚑ Your hunt wants %d more %s[/color][/b] — marked below. Anything else I send you won't count toward it." % [Shops.gate_needs(), _mob_name(need)]) if need != null \
		else "Your hunt takes [b]any[/b] monster, so [b]Karışık[/b] is the cheap choice."
	hud.say("KAAN ❤ (balkon)", ["Gel buraya. 😘 [i](Come here.)[/i]",
		"Still hunting? I can't swing a rolling pin to save my life, but I [b]can[/b] make some calls and have them waiting somewhere instead of you combing the whole city.",
		gl, "It is a finder's fee, not a job — whatever you get off them is yours. You have [b]%d₺[/b]. [i]bulmak[/i] = to find." % Shops.lira()], func():
		hud.choose("KAAN ❤ (balkon)", "Who should turn up?", opts, func(i: int):
			if i < 0: return
			if i >= sl.size(): _species(page + 1); return
			_count(sl[i])))

# step 2: HOW MANY (never more than the hunt still wants)
func _count(h: Dictionary) -> void:
	var need := Shops.gate_needs()
	var list: Array = (D["CONTRACTS"] as Array).filter(func(c): return int(c["n"]) <= maxi(1, need))
	var opts := []
	for c in list:
		var pr := _price(int(c["n"]), h)
		opts.append(("" if Shops.lira() >= pr else "🔒 ") + "%d × %s  ·  %d₺" % [int(c["n"]), h["e"], pr])
	opts.append("◀ Geri · Back")
	var head := ("[b]%s[/b]. Tamam, onları bulurum. [i](Fine, I will find them.)[/i]" % h["n"]) if h["k"] != null else "Karışık it is — whoever owes me a favour that night."
	hud.choose("KAAN ❤ — %s %s" % [h["e"], h["n"]], "%s\nHow many? Your hunt still wants [b]%d[/b], so that is as many as I will send.\nYou have [b]%d₺[/b]." % [head, need, Shops.lira()], opts, func(i: int):
		if i < 0: return
		if i >= list.size(): _species(0); return
		var c: Dictionary = list[i]; var pr := _price(int(c["n"]), h)
		if Shops.lira() < pr:
			hud.say("KAAN ❤", ["Param yetmiyor bebeğim. [i](We don't have enough.)[/i]", "That one is [b]%d₺[/b] and you have [b]%d₺[/b]. Go and win some tavla. 🎲" % [pr, Shops.lira()]])
			return
		_start(c, h))

func _start(c: Dictionary, h: Dictionary) -> void:
	var cost := _price(int(c["n"]), h)
	Shops.add_lira(-cost); Shops.sfx("coin")
	var far: Array = (D["HOTSPOTS"] as Array).filter(func(s): return Shops.flat2(torii, s["x"], s["z"]) > 900)
	var H: Dictionary = far.pick_random() if far.size() else D["HOTSPOTS"][0]
	var tag := ("%s %s" % [h["e"], h["n"]]) if h["k"] != null else "monster"
	bounty = {"place": H["n"], "x": H["x"], "z": H["z"], "left": int(c["n"]), "total": int(c["n"]), "type": h["k"], "tag": tag, "cost": cost, "spawned": false}
	_save()
	hud.banner("📞 KAAN ARADI\n[font_size=18]%d × %s waiting at %s[/font_size]" % [int(c["n"]), tag, H["n"]])
	hud.toast("📞 [b]−%d₺ finder's fee.[/b] [b]%d × %s[/b] will be waiting at [b]%s[/b]. They count toward your hunt like any other kill — and whatever they drop is yours. [i]Onlar seni bekliyor.[/i]" % [cost, int(c["n"]), tag, H["n"]], 9.0)
	var kl: Array = (D["KAANLINES"] as Array).pick_random()
	hud.say("KAAN ❤", ["Tamam, ayarladım. [i](Done, I arranged it.)[/i]", "They will be at [b]%s[/b] — %d × %s. %s" % [H["n"], int(c["n"]), tag, c["d"]], "%s [i](%s)[/i]" % [kl[0], kl[1]]])
	_hud_line(); SaveBridge.write()

func _save() -> void:
	if bounty.is_empty(): SaveBridge.data["bounty"] = null; return
	var o := {}
	for k in ["place", "x", "z", "left", "total", "cost", "type", "tag"]: o[k] = bounty.get(k)
	o["xp"] = 0; o["lira"] = 0
	SaveBridge.data["bounty"] = o

# updateBounty(): they turn up once she's close, so they don't wander off before she arrives
func _bounty_tick() -> void:
	if bounty.is_empty() or torii.get("dead"): return
	var d2 := Shops.flat2(torii, bounty["x"], bounty["z"])
	if not bounty.get("spawned", false) and d2 < 48.0 * 48.0:
		bounty["spawned"] = true; _mobs = []
		var pool := ["imp", "zombie", "thot", "ghost", "skeleton", "witch", "mummy", "okuz", "scorpion"]
		var n := int(bounty["left"])
		for i in n:
			var a := i * (TAU / n); var r := 6.0 + i * 1.4
			var kind: String = str(bounty["type"]) if bounty.get("type") != null else str(pool.pick_random())
			var at := Vector3(float(bounty["x"]) + cos(a) * r, 0, float(bounty["z"]) + sin(a) * r)
			at.y = Shops.ground_y(at.x, at.z)
			var e := Enemy.spawn(world, kind, at, torii as CharacterBody3D, randf() < .3)
			if e == null: continue
			e.set_meta("bounty", true); _mobs.append(e)
			e.died.connect(_mob_died)
		hud.banner("🎯 %s\n[font_size=18]%d × %s — kill them all[/font_size]" % [str(bounty["place"]).to_upper(), int(bounty["total"]), bounty.get("tag", "monster")])
		Shops.sfx("rev")
		if Fx.me: Fx.me.shake(.35)
	if bounty.get("spawned", false):
		_mobs = _mobs.filter(func(e): return is_instance_valid(e) and e.is_alive())
		if _mobs.size() != int(bounty["left"]): bounty["left"] = _mobs.size(); _save(); _hud_line()
		if _mobs.is_empty(): _finish()

# a bounty kill counts toward the open hunt (missions.gd only counts its own gate monsters) — if it's the
# species the hunt asked for, or the hunt takes anything
func _mob_died(e) -> void:
	if Missions.me and Missions.me.get("counts_all_kills"): return
	var need = _gate().get("type")
	if _gate().is_empty() or (need != null and str(need) != Shops.kind_of(e)): return
	var left := Shops.gate_credit(bool(e.get("elite")), "bounty")
	if left > 0: hud.toast("📞 One of Kaan's — [b]%d[/b] left for your hunt." % left, 3.0)

func _finish() -> void:
	var B := bounty; bounty = {}; _mobs = []; _save(); _hud_line()
	var left := Shops.gate_needs()
	hud.toast("📞 That is the %d Kaan sent. %s" % [int(B["total"]), ("Your hunt still wants [b]%d[/b] more — talk to him again if you want them found." % left) if left > 0 else "[b]That was the last of them.[/b]"], 6.5)
	Shops.sfx("ding"); SaveBridge.write()

func _hud_line() -> void:
	if bounty.is_empty():
		_line.text = ""; if hud: hud.unpin("bounty")
		return
	_line.text = "[right]📞 Kaan's monsters: %d × %s at %s[/right]" % [int(bounty["left"]), Rich.plain(str(bounty.get("tag", "monster"))), bounty["place"]]
	hud.pin("bounty", Vector3(float(bounty["x"]), 1.6, float(bounty["z"])), Color("ff9ecf"))

# ---------------------------------------------------------------- the airport (openTravel / travelTo)
func open_travel() -> void:
	var nx := SaveBridge.get_i("next"); var free := bool(SaveBridge.data.get("done", false))
	var opts := []; var map := []
	if nx >= 9 or free: opts.append("Cameroon 🇨🇲"); map.append("cam")
	if nx >= 10 or free: opts.append("Arizona 🌵"); map.append("az")
	if nx >= 11 or free: opts.append("Livermore 🍇"); map.append("liv")
	if map.is_empty():
		hud.say("GATE AGENT ✈️", ["No destinations unlocked yet, tatlım. Follow Kaan's missions — they'll take you abroad soon! 🌍"]); return
	opts.append("Never mind")
	hud.choose("GATE AGENT ✈️", "Where to, Torii? ✈️", opts, func(i: int):
		if i >= 0 and i < map.size(): travel(map[i]))

func travel(zone: String) -> void:
	if torii.get("on_bike") and torii.has_method("_get_off"): torii.call("_get_off")
	Shops.sfx("woosh2")
	if Fx.me: Fx.me.dark(.96, .45, true)
	if zone != "city": hud.toast("✈️ Boarding…", 2.0)
	await get_tree().create_timer(.9).timeout
	var sp: Vector2 = ZSPAWN[zone]
	_put(Vector3(sp.x, Shops.ground_y(sp.x, sp.y) + .3, sp.y))
	if torii.get("yaw") != null: torii.set("yaw", PI if zone == "city" else -PI / 2)
	if torii.has_method("snap_camera"): torii.call("snap_camera")
	var ban := get_tree().get_first_node_in_group("bandit")
	if ban is Node3D: (ban as Node3D).global_position = Vector3(sp.x + 1.5, torii.global_position.y, sp.y + 1)
	hud.banner("🛬 WELCOME HOME" if zone == "city" else "🛫 " + str(ZNAME.get(zone, zone)))
	if zone != "city": Shops.teach("uçak"); Shops.teach("havalimanı")
	if Fx.me: Fx.me.dark(0.0, .8)

func _process(dt: float) -> void:
	if torii == null: return
	_door(dt)
	_t -= dt
	if _t <= 0 and not Overlay.any():
		_t = .5; _bounty_tick()
