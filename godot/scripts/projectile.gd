# Her ranged shots (7.2's projs / updateProjs: Bill Box stacks, the Nazar Sling bead, and the mission
# guns that 7.2 fired as plain green boxes). Each kind has its own little PS1 mesh and a trick:
#   bills  — bill stacks, a fat knockback        bead  — nazar bead, pierces 3 and slows
#   pick   — guitar picks fired in a fan          ball  — tennis ball, falls, bounces off walls and mobs
#   staple — fast staples that pin (slow)          die   — loaded die, damage by the face it rolled
#   disc   — vinyl discus that flies out and comes back, cutting through everything
# A short fading trail behind it, sparks where it lands. Monsters' shots are shot.gd.
class_name Projectile
extends Node3D

const TRAIL := 5
var vel := Vector3.ZERO
var cfg := {}
var life := 1.3
var age := 0.0
var pierce := 0
var bounce := 0
var owner_p = null                 # the player (untyped: player.gd has no class_name)
var _hit := {}                     # enemy instance ids already hit (pierce / the way back)
var _body: Node3D
var _trail: Array = []             # [{m, mat}]
var _hist: Array = []              # last positions, newest first
var _back := false                 # boomerang on its way home
static var _mats := {}
static var _glow: GradientTexture2D

# cfg: kind, col, spd, dmg, life, grav, bounce, pierce, kb, status, sec, stagger, boomer, mult, snd_hit
static func shoot(parent: Node, from: Vector3, dir: Vector3, c: Dictionary, p) -> Projectile:
	var pr := Projectile.new()
	pr.cfg = c; pr.owner_p = p
	pr.vel = dir.normalized() * float(c.get("spd", 23.0))
	pr.life = float(c.get("life", 1.3)); pr.pierce = int(c.get("pierce", 0)); pr.bounce = int(c.get("bounce", 0))
	parent.add_child(pr)
	pr.global_position = from
	pr._build()
	return pr

static func _mat(col: Color, alpha := false) -> StandardMaterial3D:
	var key := "%s%s" % [col.to_html(), alpha]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if alpha: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

func _box(sz: Vector3, col: Color, at := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = sz; b.material = _mat(col)
	var m := MeshInstance3D.new(); m.mesh = b; m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _body.add_child(m)
	return m

func _ball(r: float, col: Color, at := Vector3.ZERO, sq := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 8; s.rings = 4; s.material = _mat(col)
	var m := MeshInstance3D.new(); m.mesh = s; m.position = at; m.scale = sq
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _body.add_child(m)
	return m

func _build() -> void:
	_body = Node3D.new(); add_child(_body)
	var col := Color(str(cfg.get("col", "4fbf72")))
	match str(cfg.get("kind", "bills")):
		"bead":                                   # the evil eye: dark blue, white, light blue, black pupil
			_ball(.2, Color("1f5fd0"), Vector3.ZERO, Vector3(1, 1, .45))
			_ball(.13, Color("f4f8ff"), Vector3(0, 0, -.05), Vector3(1, 1, .45))
			_ball(.085, Color("7bd0ff"), Vector3(0, 0, -.08), Vector3(1, 1, .45))
			_ball(.04, Color("10142a"), Vector3(0, 0, -.11), Vector3(1, 1, .45))
		"pick":
			var pm := PrismMesh.new(); pm.size = Vector3(.3, .34, .04); pm.material = _mat(col)
			var m := MeshInstance3D.new(); m.mesh = pm; m.rotation.x = -PI / 2; _body.add_child(m)
		"ball":
			_ball(.18, Color("d8ff4a"))
			_box(Vector3(.37, .025, .03), Color("f4f8ff"))
		"staple":
			_box(Vector3(.06, .05, .34), Color("cfd8ff"))
			_box(Vector3(.06, .14, .05), Color("cfd8ff"), Vector3(0, -.07, .15))
			_box(Vector3(.06, .14, .05), Color("cfd8ff"), Vector3(0, -.07, -.15))
		"die":
			_box(Vector3(.32, .32, .32), Color("fff8ec"))
			for f in [Vector3(0, 0, .165), Vector3(.165, 0, 0), Vector3(0, .165, 0)]:
				_box(Vector3(.07, .07, .07) - f.abs() * .4, Color("ff2d78"), f)
		"disc":
			var cy := CylinderMesh.new(); cy.top_radius = .42; cy.bottom_radius = .42; cy.height = .05
			cy.radial_segments = 12; cy.material = _mat(Color("1a1626"))
			var d := MeshInstance3D.new(); d.mesh = cy; _body.add_child(d)
			var lab := CylinderMesh.new(); lab.top_radius = .15; lab.bottom_radius = .15; lab.height = .07
			lab.radial_segments = 8; lab.material = _mat(col)
			var l := MeshInstance3D.new(); l.mesh = lab; _body.add_child(l)
		_:                                        # bill stack: green with a pale paper band (7.2's box)
			_box(Vector3(.34, .22, .34), Color("4fbf72"))
			_box(Vector3(.36, .07, .2), Color("e8ffe0"))
	# the trail: soft billboard dots trailing behind, fading out (shared glow texture)
	if not _glow:
		_glow = GradientTexture2D.new(); _glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(.5, .5); _glow.fill_to = Vector2(1, .5); _glow.width = 16; _glow.height = 16
		var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0)); _glow.gradient = g
	var q := QuadMesh.new(); q.size = Vector2(.34, .34)
	for i in TRAIL:
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = _glow; mat.albedo_color = Color(col, .55 * (1.0 - float(i) / TRAIL))
		var m := MeshInstance3D.new(); m.mesh = q; m.material_override = mat; m.top_level = true
		m.scale = Vector3.ONE * (1.0 - float(i) / (TRAIL + 1)); m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(m)
		_trail.append(m)
	if vel.length() > .01: look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < .98 else Vector3.RIGHT)

func _physics_process(dt: float) -> void:
	if Overlay.any(): return                      # calls, quizzes, the wheel: everything waits
	age += dt; life -= dt
	if life <= 0: _pop(global_position, false); return
	vel.y -= float(cfg.get("grav", 0.0)) * dt
	# the discus: flies out, then curves back to her hand; catching it ends it
	if cfg.get("boomer", false) and owner_p and is_instance_valid(owner_p):
		var home: Vector3 = owner_p.global_position + Vector3(0, 1.4, 0)
		if not _back and age > .42: _back = true; _hit.clear()
		if _back:
			var want := (home - global_position).normalized() * float(cfg.get("spd", 22.0)) * 1.1
			vel = vel.lerp(want, minf(1.0, dt * 6.0))
			if global_position.distance_to(home) < 1.2: queue_free(); return
	var from := global_position
	var to := from + vel * dt
	# walls and the ground (the city has real collision); the ball bounces, everything else stops
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if owner_p and is_instance_valid(owner_p) and owner_p is CollisionObject3D: q.exclude = [owner_p.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		if bounce > 0:
			bounce -= 1
			var n: Vector3 = hit["normal"]
			vel = vel.bounce(n) * .72
			to = hit["position"] + n * .2
			Bus.emit_ev("sfx", {"name": "drop", "pos": to})
			if Fx.me: Fx.me.puff(to, Color("d8ff4a"), 3, .6, .6, .3)
		elif cfg.get("boomer", false) and not _back:
			_back = true; _hit.clear(); to = hit["position"] + Vector3(hit["normal"]) * .2   # the disc ricochets home
		else:
			_pop(hit["position"], false); return
	global_position = to
	_hist.push_front(from)
	if _hist.size() > TRAIL: _hist.resize(TRAIL)
	for i in _trail.size():
		var m: MeshInstance3D = _trail[i]
		m.visible = i < _hist.size()
		if m.visible: m.global_position = _hist[i]
	# spin (picks and discs flat, dice tumbling, bills wobbling)
	match str(cfg.get("kind", "")):
		"pick", "disc": _body.rotation.y += dt * 22.0
		"die", "bills", "ball": _body.rotation += Vector3(dt * 9.0, dt * 7.0, 0)
		"bead": _body.rotation.z += dt * 6.0
	# monsters (they have no collision bodies: distance from the path to their middle, like 7.2's d² < 2.2)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or _hit.has(e.get_instance_id()): continue
		if e.has_method("is_alive"):
			if not e.is_alive(): continue
		elif float(e.get("hp")) <= 0: continue
		var big: bool = e.get("flags") is Dictionary and e.flags.has("boss")
		var r := 2.0 if big else (1.5 if e.get("elite") else 1.2)
		var c: Vector3 = e.global_position + Vector3(0, 1.1 if not big else 1.6, 0)
		var seg := to - from
		var k := clampf((c - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var near := from + seg * k
		if Vector2(near.x - c.x, near.z - c.z).length() > r or absf(near.y - c.y) > (2.4 if big else 1.6): continue
		_hit[e.get_instance_id()] = true
		_strike(e, near)
		if pierce <= 0:
			if bounce > 0 and str(cfg.get("kind", "")) == "ball":
				bounce -= 1; vel = Vector3(vel.x * .55, 6.5, vel.z * .55)     # pops up off its head and carries on
				continue
			_pop(near, true); return
		pierce -= 1

func _strike(e, at: Vector3) -> void:
	var base := float(cfg.get("dmg", 45.0)) * float(cfg.get("mult", 1.0))
	var r: Array = Arsenal.me.roll_damage(owner_p, base) if Arsenal.me else [base, false]
	var flat := Vector3(vel.x, 0, vel.z).normalized()
	var opts := {"heavy": cfg.get("heavy", false), "crit": r[1], "kb": float(cfg.get("kb", 4.0)), "ranged": true}
	if cfg.get("status", "") != "":
		opts["status"] = cfg["status"]; opts["status_t"] = float(cfg.get("sec", 2.0))     # enemy.hit reads status_t
	if cfg.get("stagger", 0.0) > 0: opts["stagger"] = float(cfg["stagger"])
	e.hit(float(r[0]), flat, opts)
	Bus.emit_ev("sfx", {"name": str(cfg.get("snd_hit", "cash")), "pos": at})
	if Fx.me:
		Fx.me.puff(at, [Color(str(cfg.get("col", "5fdf8e"))), Color("ffe04d"), Color.WHITE], 8, 1.8, 2.0, .5)
		if r[1]: Fx.me.shake(.08)

# impact: sparks on a monster, a dusty pop on a wall; then it's gone
func _pop(at: Vector3, on_mob: bool) -> void:
	if Fx.me and not on_mob and life > 0:
		Fx.me.puff(at, [Color("cfd8ff"), Color(str(cfg.get("col", "cfd8ff")))], 5, 1.1, .9, .4)
		Bus.emit_ev("sfx", {"name": "drop", "pos": at})
	queue_free()
