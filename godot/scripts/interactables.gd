# The bits of the city she uses with E that aren't people with a quest, ported from 7.2:
#  · fountains (+25 HP, +15 mana, 40 s) and simit carts (15₺, +10 HP, 12 s) — PROPS / buildProps / propInteract
#    (the fountain and cart models are baked into city.glb; this is just their triggers and what they do)
#  · Club Holo's DJ booth (DJB, djUntil / djCd: a 12 s set, confetti, she dances, +30 XP, 55 s cooldown)
#  · Josh in Stockton (joshBody / updateJosh / joshTalk / JOSH_LINES): within 9 m he rants (−HP, never below 3,
#    slows her), E gets Josh's Device (joshdev), then a 5-minute recharge
# Kaan's door, his monster service and the airport travel menu live in hotspots.gd (Hotspots) — not here.
# main's E dispatcher calls try_interact(p) (true = E was used here), or the three steps one by one in 7.2's
# order: try_josh (step 7), try_props (step 10), try_dj (step 12). prompt(p) gives the hint line.
class_name Interactables
extends Node

static var me: Interactables

const FOUNTAINS := [[-60, 20], [20, -20], [-140, 60]]
const SIMIT := [[-16, 22], [64, 10], [-96, -18]]          # 7.2 put the trigger 2 m in front of the cart
const DJB := Vector2(101, -24)
const JOSH_AT := Vector3(-40, 0, -164)
const JOSH_CD := 300.0
const JOSH_LINES := ["\"The moon landing was FAKE, sis!\" 🌙", "\"Time travelers walk among us!\" ⏳", "\"I'm hiding an alien in the garage!\" 👽",
	"\"Birds are actually drones!\" 🐦", "\"Aliens built the pyramids!\" 👽", "\"5G is reading my thoughts!\" 📡"]

var world: Node3D
var player                        # player.gd (untyped, so its own methods can be called)
var hud: Hud
var _prop_cd := {}                # "f0" / "s1" -> time it's ready again
var _dj_until := 0.0
var _dj_cd := 0.0
var _josh_t := 0.0
var _josh_dev := 0.0
var _josh_hp := 0.0
var _josh: Node3D
var _josh_pose: ToriiPose
var _josh_anim := 0.0

func _init() -> void: me = self

func setup(w: Node3D, p: Node3D, h: Hud) -> void:
	world = w; player = p; hud = h
	# Josh stands outside his mum's house in Stockton (7.2 joshBody at -40, -164) unless people.json has him
	_josh = Npc.find_near(JOSH_AT, 6.0)
	if _josh == null:
		_josh = MobModels.josh(); _josh.name = "Josh"; w.add_child(_josh)
		_josh.global_position = JOSH_AT
		if _josh.has_meta("pose"): _josh_pose = _josh.get_meta("pose")
		_snap_josh()

# stand him on whatever the city has there once physics is up
func _snap_josh() -> void:
	await get_tree().physics_frame; await get_tree().physics_frame
	if is_instance_valid(_josh) and Shops.me: _josh.global_position.y = Shops.ground_y(JOSH_AT.x, JOSH_AT.z, 20.0)

static func now() -> float: return Time.get_ticks_msec() / 1000.0
static func d2(p: Node3D, x: float, z: float) -> float:
	var dx := p.global_position.x - x; var dz := p.global_position.z - z
	return dx * dx + dz * dz

func _toast(t: String, secs := 4.0, bad := false) -> void:
	if hud: hud.toast(t, secs, bad)
func _sfx(n: String, at: Variant = null) -> void:
	var d := {"name": n}
	if at is Vector3: d["pos"] = at
	Bus.emit_ev("sfx", d)
func _city() -> bool: return float(player.global_position.x) < 400.0
func _josh_pos() -> Vector3: return _josh.global_position if is_instance_valid(_josh) else JOSH_AT
func _near_josh(p: Node3D) -> bool:
	var at := _josh_pos()
	return d2(p, at.x, at.z) < 20.0 and absf(p.global_position.y - at.y) < 4.0

# ---------------------------------------------------------------- the hint line (7.2's setPrompt picks)
func prompt(p: Node3D) -> String:
	if p == null or bool(p.get("dead")) or bool(p.get("on_bike")): return ""
	if _near_josh(p): return "E: JOSH 🛸 — ask about the device"
	for i in FOUNTAINS.size():
		if d2(p, FOUNTAINS[i][0], FOUNTAINS[i][1]) < 9.0: return "E: drink from the fountain ⛲"
	for i in SIMIT.size():
		if d2(p, SIMIT[i][0], SIMIT[i][1]) < 9.0: return "E: buy a simit — 15₺ 🥯"
	if d2(p, DJB.x, DJB.y) < 9.0: return "🎧 DJ cooling down..." if _dj_cd > now() else "E: hop on the decks 🎧"
	return ""

# ---------------------------------------------------------------- E
func _can(p: Node3D) -> bool:
	if p == null: return false
	player = p
	return not (Overlay.any() or bool(p.get("dead")) or bool(p.get("on_bike")))

func try_interact(p: Node3D) -> bool: return try_josh(p) or try_props(p) or try_dj(p)

func try_josh(p: Node3D) -> bool:
	if not _can(p) or not _near_josh(p): return false
	_josh_talk(); return true

func try_props(p: Node3D) -> bool:
	if not _can(p): return false
	for i in FOUNTAINS.size():
		if d2(p, FOUNTAINS[i][0], FOUNTAINS[i][1]) < 9.0: return _fountain("f%d" % i)
	for i in SIMIT.size():
		if d2(p, SIMIT[i][0], SIMIT[i][1]) < 9.0: return _simit("s%d" % i)
	return false

func try_dj(p: Node3D) -> bool:
	if not _can(p) or d2(p, DJB.x, DJB.y) >= 9.0: return false
	_dj(); return true

func _cooling(id: String) -> bool:
	var t := float(_prop_cd.get(id, 0.0))
	if t > now():
		_toast("⏳ Not yet — %ds" % ceili(t - now()), 2.5); return true
	return false

func _fountain(id: String) -> bool:
	if _cooling(id): return true
	_prop_cd[id] = now() + 40.0
	player.heal(25)
	if player.has_method("add_mana"): player.add_mana(15)
	if Fx.me: Fx.me.flash("heal"); Fx.me.heal(player.global_position)
	if Fx.me: Fx.me.splash(Vector3(FOUNTAINS[int(id.substr(1))][0], 1.0, FOUNTAINS[int(id.substr(1))][1]))
	_sfx("drink"); _sfx("heal")
	Shops.teach("çeşme"); Shops.teach("su")
	_toast("⛲ [b]+25 HP, +15 mana[/b] · Turkish: [i]çeşme[/i] = fountain, [i]su[/i] = water", 6.5)
	return true

func _simit(id: String) -> bool:
	if _cooling(id): return true
	if Shops.lira() < 15:
		_toast("Not enough lira! Simit costs 15₺ 🥯", 4.0, true); _sfx("no"); return true
	Shops.add_lira(-15); _prop_cd[id] = now() + 12.0
	player.heal(10)
	_sfx("coin"); _sfx("eat")
	if Fx.me: Fx.me.heal(player.global_position)
	if player.has_method("act"): player.act("eat", 1.2)
	Shops.teach("simit"); Shops.teach("ekmek")
	_toast("🥯 [b]Fresh simit![/b] +10 HP · The vendor says: [i]Afiyet olsun![/i]", 6.5)
	Audio.speak("Afiyet olsun")
	return true

# ---------------------------------------------------------------- the DJ booth
func _dj() -> void:
	if _dj_cd > now():
		_toast("🎧 DJ booth cooling down · %ds" % ceili(_dj_cd - now()), 3.5); return
	_dj_until = now() + 12.0; _dj_cd = now() + 55.0
	if player.has_method("act"): player.act("dance", 12.0)
	Bus.emit_ev("dj", {"sec": 12.0})                     # Audio adds its DJ layer on this
	if hud: hud.banner("🎧 DJ TORİİ IN THE MIX! · The floor is yours!")
	if Fx.me: Fx.me.burst(Vector3(DJB.x, 2.0, DJB.y), Fx.CONF, 24, 6.0, 6.0, .9)
	_sfx("dance"); Shops.xp(30); Shops.teach("müzik"); Shops.teach("dans")

# ---------------------------------------------------------------- Josh
func _josh_face(at: Vector3) -> void:
	if not is_instance_valid(_josh): return
	if _josh.has_method("face"): _josh.face(at); return
	var d := at - _josh.global_position
	_josh.rotation.y = atan2(d.x, d.z)

func _josh_talk() -> void:
	_josh_face(player.global_position)
	var left := _josh_dev - now()
	if _josh_dev > 0 and left > 0:
		var m := ceili(left / 60.0)
		hud.say("JOSH 🛸", ["*Josh pats his pockets frantically* Nah nah nah, I only got the one, sis.",
			"The... the [b]frequency[/b] has to recharge off the ionosphere. Or the wifi. I forget which one Dad said.",
			"Come back in about [b]%d minute%s[/b] and it'll be humming again. Probably." % [m, "s" if m > 1 else ""]])
		return
	_josh_dev = now() + JOSH_CD
	_sfx("blah"); _sfx("zap")
	hud.say("JOSH 🛸", ["*Josh sprints out of the garage holding something wrapped in a beach towel* TORİİ. TORİİ WAIT.",
		"*He unwraps it. It is a car alarm, a satellite dish, and a Nokia, all duct-taped together.*",
		"Okay so. You know how the government uses [b]frequencies[/b] to control the birds? I [i]reverse-engineered[/i] it. From the thing in the garage. You know the thing.",
		"Point it at anything that ain't human and it'll drop. Aliens hate it, ghosts hate it, my ex hated it.",
		"⚠️ Small thing though — it, uh, doesn't know YOU're not a target. So it's gonna zap you a little too. That's just physics, sis. That's just [b]physics[/b].",
		"Turkish word for it is [i]alet[/i]. Means \"device.\" Or \"tool.\" Kinda both. Kinda like me. 😎"], func():
			if Arsenal.me: Arsenal.me.give_weapon("joshdev", true)
			else: Shops.give_weapon("joshdev")
			Shops.teach("alet")
			if hud:
				hud.banner("📡 JOSH'S DEVICE ACQUIRED · Shocks everything nearby — including you")
				hud.toast("📡 [b]Josh's Device[/b] — hits ALL enemies within 8m, stuns them, costs you ~5 HP a zap. Josh has another in ~5 min.", 10.0)
			_sfx("divine")
			SaveBridge.write())

# within 9 m he won't stop talking: −2.6 HP/s (never below 3), slowed, a rant every 2.8 s
func _josh_tick(dt: float) -> void:
	var at := _josh_pos()
	# he fidgets and waves his arms about (7.2 joshBody was a statue; this one at least gestures)
	_josh_anim += dt
	if _josh_pose and d2(player, at.x, at.z) < 900.0:
		_josh_pose.arm(1, -1.0 + sin(_josh_anim * 3.1) * .5, 0, -.2); _josh_pose.elbow(1, -1.2 + sin(_josh_anim * 4.0) * .3)
		_josh_pose.head(sin(_josh_anim * 1.7) * .12, sin(_josh_anim * .9) * .3)
	if bool(player.get("dead")) or not _city() or d2(player, at.x, at.z) >= 81.0 or absf(player.global_position.y - at.y) > 4.0:
		_josh_t = 0.0; return
	_josh_face(player.global_position)
	if player.has_method("set_status"): player.set_status("slow", .25)
	_josh_hp += 2.6 * dt
	if _josh_hp >= 1.0:
		var n := int(_josh_hp); _josh_hp -= n
		var hp := int(player.get("hp"))
		if hp > 3:
			player.set("hp", maxi(3, hp - n))
			if player.has_signal("hp_changed"): player.hp_changed.emit(player.get("hp"), player.get("max_hp"))
	_josh_t -= dt
	if _josh_t <= 0.0:
		_josh_t = 2.8
		var L: String = JOSH_LINES.pick_random()
		_toast("🗣 [b]JOSH WON'T STOP TALKING![/b] -HP · " + L, 4.5, true)
		if Fx.me: Fx.me.label(at + Vector3(0, 2.7, 0), L, Color("d8ffd8"), 2.4, true); Fx.me.flash("hurt")
		_sfx("blah", at); Shops.teach("uzaylı")

# ---------------------------------------------------------------- every frame
func _process(dt: float) -> void:
	if player == null or world == null: return
	if Overlay.any(): return
	_josh_tick(dt)
	# the DJ set: confetti over the decks, and she can't help dancing while she's on the floor
	if _dj_until > now():
		if randf() < dt * 1.6 and Fx.me:
			Fx.me.puff(Vector3(DJB.x + randf_range(-2.5, 2.5), 1.6, DJB.y + randf_range(-2.5, 2.5)), Fx.CONF, 5, 1.6, 2.6, .9)
		if d2(player, DJB.x, DJB.y) < 20.0 and player.has_method("act"): player.act("dance", .4)
