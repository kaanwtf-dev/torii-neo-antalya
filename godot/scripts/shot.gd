# Monster ranged attacks and ground telegraphs (7.2's enemyShoot / updateEProjs, made readable like a PS1
# action game):
#   "arrow" skeleton arrows (20 m/s), "hex" the witch's spinning purple hex (13 m/s, slows her 50% for 3 s),
#   "orb" the jinn's cyan orbs, "lob" a thug's bottle that arcs to where she stood with a red marker
#   on the ground where it'll land, "ring" a circle on the ground that fills up and then goes off
#   (witch curses, boss slams). Shots stop at walls with a puff, like 7.2. Roll through them / out of them.
class_name Shot
extends MeshInstance3D

var mode := "arrow"
var vel := Vector3.ZERO
var dmg := 8
var life := 2.5
var torii: Node3D
var owner_e: Node = null          # who fired it (a ring dies with its caster)
# lob / ring
var t := 0.0
var flight := 1.0
var radius := 2.0
var from_p := Vector3.ZERO
var to_p := Vector3.ZERO
var hit_kind := "ranged"
var marker: MeshInstance3D
var disc: MeshInstance3D
var status := ""

static var _m := {}
static func _mat(c: Color, a := 1.0) -> StandardMaterial3D:
	var k := "%s%s" % [c.to_html(), a]
	if _m.has(k): return _m[k]
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, a); m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m[k] = m
	return m

# the old call (missions / anything that just wants a shot): arrow or hex
static func fire(parent: Node, from: Vector3, target: Node3D, damage: int, arrow: bool) -> void:
	shoot(parent, from, target, damage, "arrow" if arrow else "hex")

# a straight shot at her chest. spread: radians off-centre (the jinn fires three)
static func shoot(parent: Node, from: Vector3, target: Node3D, damage: int, kind := "arrow", spread := 0.0, by: Node = null) -> Shot:
	var s := Shot.new(); s.mode = kind; parent.add_child(s)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"arrow":
			var b := BoxMesh.new(); b.size = Vector3(.06, .06, .9); b.material = _mat(Color("c8a46a")); s.mesh = b
		"orb":
			var o := SphereMesh.new(); o.radius = .2; o.height = .4; o.radial_segments = 6; o.rings = 3
			o.material = _mat(Color("7bf7ff")); s.mesh = o
		_:
			var p := PrismMesh.new(); p.size = Vector3(.42, .42, .42); p.material = _mat(Color("b06bff")); s.mesh = p
	s.global_position = from; s.torii = target; s.dmg = damage; s.owner_e = by
	s.hit_kind = "ranged"; s.status = "slow" if kind == "hex" else ("burn" if kind == "orb" else "")
	var aim := target.global_position + Vector3(0, 1.1, 0)
	var dir := (aim - from).normalized().rotated(Vector3.UP, spread)
	s.vel = dir * (20.0 if kind == "arrow" else (11.0 if kind == "orb" else 13.0))
	s.life = 2.6 if kind == "arrow" else 3.0
	if dir.length_squared() > .01 and absf(dir.y) < .99: s.look_at(from + dir, Vector3.UP)
	Enemy.sfx("arrow" if kind == "arrow" else ("orb" if kind == "orb" else "hex"), from)
	return s

# a lobbed bottle: arcs over flight seconds to `at`, a red marker shows where; bursts in `rad` metres
static func lob(parent: Node, from: Vector3, at: Vector3, damage: int, fl := 1.1, rad := 1.9, by: Node = null) -> Shot:
	var s := Shot.new(); s.mode = "lob"; parent.add_child(s)
	var b := CylinderMesh.new(); b.top_radius = .05; b.bottom_radius = .08; b.height = .32; b.radial_segments = 5; b.rings = 1
	b.material = _mat(Color("5fff9e")); s.mesh = b
	s.global_position = from; s.from_p = from; s.to_p = at; s.flight = fl; s.radius = rad; s.dmg = damage; s.owner_e = by
	s.hit_kind = "aoe"
	s.marker = _ring_mesh(parent, at, rad, Color("ff3b3b"))
	Enemy.sfx("lob", from)
	return s

# a ground circle that fills over `delay` seconds and then goes off: anyone inside gets hit
# (unblockable ones = roll out; a boss slam is centred on the boss)
static func ring(parent: Node, at: Vector3, rad: float, delay: float, damage: int, target: Node3D, kind := "aoe", col := Color("ff3b3b"), by: Node = null) -> Shot:
	var s := Shot.new(); s.mode = "ring"; parent.add_child(s)
	s.global_position = at; s.to_p = at; s.radius = rad; s.flight = delay; s.dmg = damage; s.torii = target
	s.hit_kind = kind; s.owner_e = by
	s.marker = _ring_mesh(parent, at, rad, col)
	var d := CylinderMesh.new(); d.top_radius = rad; d.bottom_radius = rad; d.height = .02; d.radial_segments = 14; d.rings = 1
	d.material = _mat(col, .28)
	s.disc = MeshInstance3D.new(); s.disc.mesh = d; parent.add_child(s.disc)
	s.disc.global_position = at + Vector3(0, .06, 0); s.disc.scale = Vector3(.05, 1, .05)
	s.disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Enemy.sfx("telegraph", at)
	return s

static func _ring_mesh(parent: Node, at: Vector3, rad: float, col: Color) -> MeshInstance3D:
	var tm := TorusMesh.new(); tm.inner_radius = maxf(.05, rad - .14); tm.outer_radius = rad; tm.rings = 16; tm.ring_segments = 3
	tm.material = _mat(col, .85)
	var m := MeshInstance3D.new(); m.mesh = tm; parent.add_child(m)
	m.global_position = at + Vector3(0, .08, 0); m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func _physics_process(dt: float) -> void:
	if Overlay.any(): return
	match mode:
		"lob": _lob(dt)
		"ring": _ring(dt)
		_: _fly(dt)

func _fly(dt: float) -> void:
	var nxt := global_position + vel * dt
	life -= dt
	if mode == "hex": rotation.y += dt * 7.0
	if mode == "orb" and Fx.me and randf() < dt * 14: Fx.me.puff(global_position, Color("7bf7ff"), 1, .2, .2, .3)
	# stops at walls instead of flying through them (7.2 hitsWall)
	var q := PhysicsRayQueryParameters3D.create(global_position, nxt); q.collision_mask = 1
	var w := get_world_3d().direct_space_state.intersect_ray(q)
	if w:
		_burst(w["position"], 5); Enemy.sfx("thunk", w["position"]); _free(); return
	global_position = nxt
	if torii and is_instance_valid(torii) and global_position.distance_to(torii.global_position + Vector3(0, 1.1, 0)) < .85:
		var res := Enemy.strike_torii(torii, dmg, global_position - vel.normalized() * 2.0, hit_kind, null)
		if not res.is_empty() and not res.get("blocked", false) and status != "" and torii.has_method("set_status"):
			torii.set_status(status, 3.0 if status == "slow" else 2.0)
			if status == "slow" and Lessons.me: Lessons.me.hud.toast("🔮 [b]Hexed by the witch![/b] Slowed for 3 s", 3.0, true)
		_burst(global_position, 6); _free(); return
	if life <= 0: _free()

func _lob(dt: float) -> void:
	t += dt
	var u := clampf(t / flight, 0.0, 1.0)
	var p := from_p.lerp(to_p, u); p.y += sin(u * PI) * (2.5 + from_p.distance_to(to_p) * .18)
	global_position = p; rotation.x += dt * 12.0
	if marker: marker.scale = Vector3.ONE * (1.0 + sin(t * 18.0) * .06)
	if u < 1.0: return
	_burst(to_p + Vector3(0, .3, 0), 14, [Color("ff7a2d"), Color("ffd66b"), Color("5fff9e")])
	Enemy.sfx("boom", to_p)
	if Fx.me: Fx.me.shake(.12)
	if torii and is_instance_valid(torii) and _inside(torii.global_position):
		Enemy.strike_torii(torii, dmg, to_p, "aoe", null)
	_free()

func _ring(dt: float) -> void:
	t += dt
	if owner_e != null and (not is_instance_valid(owner_e) or not owner_e.is_alive()):
		_free(); return                                 # the caster's dead: the curse fizzles
	var u := clampf(t / flight, 0.0, 1.0)
	if disc: disc.scale = Vector3(maxf(.05, u), 1, maxf(.05, u))
	if marker and u > .65: marker.visible = fmod(t, .12) < .07     # blinks right before it goes
	if u < 1.0: return
	var n := int(8 + radius * 3)
	if Fx.me:
		for i in n:
			var a := TAU * i / n
			Fx.me.puff(to_p + Vector3(cos(a) * radius, .3, sin(a) * radius), [Color("ff5fa2"), Color("b06bff"), Color("ffd66b")], 1, .4, 1.6, .5)
		Fx.me.shake(.25 if radius > 3.0 else .1)
	Enemy.sfx("slam" if radius > 3.0 else "curse", to_p)
	if torii and is_instance_valid(torii) and _inside(torii.global_position):
		var res := Enemy.strike_torii(torii, dmg, to_p, hit_kind, null)
		if not res.is_empty() and torii.has_method("knockback"):
			var away := torii.global_position - to_p; away.y = 0
			if away.length() > .1: torii.knockback(away.normalized(), 8.0 if radius > 3.0 else 4.0)
	_free()

func _inside(p: Vector3) -> bool:
	var d := Vector2(p.x - to_p.x, p.z - to_p.z).length()
	return d < radius + .3 and absf(p.y - to_p.y) < 2.2

func _burst(at: Vector3, n: int, col = null) -> void:
	if not Fx.me: return
	var c = col if col != null else (Color("b06bff") if mode == "hex" else (Color("7bf7ff") if mode == "orb" else Color("c8a46a")))
	Fx.me.puff(at, c, n, 1.4, 1.3, .5)

func _free() -> void:
	if marker and is_instance_valid(marker): marker.queue_free()
	if disc and is_instance_valid(disc): disc.queue_free()
	queue_free()
