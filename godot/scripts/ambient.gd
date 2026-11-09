# The scenery moving on its own (FX-06, 7.2 loop()): the beach clubs' neon signs pulse (clubGlow), the ferry
# sails the river channel and puffs smoke, the river and the sea bob and drift, the Livermore windmill turns
# and the three gods' coins spin over their shrines.
# city.glb froze all of these where they stood at export time, merged into its 60 m chunks. setup() runs
# BEFORE main._solidify: it lifts the frozen ferry, windmill blades and coins out of their chunks (only the
# triangles that lie inside each one's own small box) into nodes of their own that move, and leaves the
# moving bits out of the colliders. The neon and the water are their own materials, so those just animate.
# A copy of each touched chunk mesh is edited, never the imported one (a reload instances the city again).
class_name Ambient
extends Node

static var me: Ambient

# where the export froze them (7.2 positions: buildGods, the windmill at Livermore, the ferry at z 80)
const COIN_Y := 2.3
const COIN_HALF := Vector3(.9, .9, .2)           # the coin is a .8 m disk facing z; the shrine pillars sit at 1.5 m
const BLADES_BOX := AABB(Vector3(614, 5, -315.8), Vector3(8, 8, .2))      # 4 blades round the hub (618, 9, -315.7)
const FERRY_BOX := AABB(Vector3(-216.2, -.2, 73.8), Vector3(4.4, 5.5, 12.4))   # hull 4x12, cabin, funnel
const FERRY_X := -214.0
const CLUBS := [Vector3(97.2, 6, -16), Vector3(97.2, 6, 12)]              # CLUB HOLO, BAR LUNA (7.2 clubGlow order)
const SMOKE := [Color("9a9aa8"), Color("c8c8d0")]

var _world: Node3D
var _chunks: Array[MeshInstance3D] = []
var _signs: Array[BaseMaterial3D] = []
var _coins: Array[Node3D] = []
var _coin_y: PackedFloat32Array = []
var _blades: Node3D
var _ferry: Node3D
var _river: Node3D
var _sea: Node3D
var _river_m: BaseMaterial3D
var _sea_m: BaseMaterial3D
var _river_y := 0.0
var _sea_y := 0.0
var _t := 0.0
var _info := ""

func _init() -> void: me = self

func setup(w: Node3D, city: Node3D) -> void:
	_world = w
	var stack: Array = [city]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for c in x.get_children(): stack.append(c)
		if x is MeshInstance3D and (x as MeshInstance3D).mesh is ArrayMesh: _chunks.append(x)
	# the club signs: their own see-through unlit sign material each
	for at in CLUBS:
		var m := _material_in(AABB(at - Vector3(1.2, 2, 5), Vector3(2.4, 4, 10)), func(b: BaseMaterial3D): return b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.albedo_texture != null)
		if m: _signs.append(m)
	# the gods' coins (unlit, 7.2 MeshBasicMaterial in the god's colour)
	var S = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/story72.json"))
	var gods: Array = S.get("gods", []) if S is Dictionary else []
	for G in gods:
		var c := Vector3(float(G["x"]), COIN_Y, float(G["z"]))
		var n := _take(AABB(c - COIN_HALF, COIN_HALF * 2), func(b: BaseMaterial3D): return b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, true)
		if n: w.add_child(n); _coins.append(n); _coin_y.append(n.position.y)
	_blades = _take(BLADES_BOX, _opaque, true)
	if _blades: w.add_child(_blades)
	_ferry = _take(FERRY_BOX, _opaque, false)
	if _ferry: w.add_child(_ferry)
	# the river and the sea: one big flat see-through blue quad each. The sea is a chunk of its own; the
	# river shares one, so it moves into a child of that chunk (still under the city: main finds it as water)
	for mi in _chunks.duplicate():
		for s in mi.mesh.get_surface_count():
			var b := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if b == null or not _is_water(b, mi, s): continue
			var node: Node3D = mi if mi.mesh.get_surface_count() == 1 else _split_surface(mi, s)
			if (mi.global_transform * mi.get_aabb()).get_center().x < 0.0:
				_river = node; _river_m = b; _river_y = node.position.y
			else:
				_sea = node; _sea_m = b; _sea_y = node.position.y
			break
	_info = "AMBIENT signs=%d coins=%d blades=%s ferry=%s river=%s sea=%s" % [_signs.size(), _coins.size(), _blades != null, _ferry != null, _river != null, _sea != null]
	for a in OS.get_cmdline_user_args():          # dev: --ambient_t=SEC starts the clock later (ferry at z = SEC*7 - 180)
		if a.begins_with("--ambient_t="): _t = float(a.substr(12))
	if "--ambientinfo" in OS.get_cmdline_user_args():      # dev: what it found in city.glb
		print(_info)
		var share := {}          # how many chunk surfaces use each animated material (only these should move)
		for mi in _chunks:
			for s in mi.mesh.get_surface_count():
				var b := mi.mesh.surface_get_material(s)
				if b in _signs or b == _river_m or b == _sea_m: share[b] = share.get(b, 0) + 1
		for b in share: print("AMBIENT mat ", b.resource_name, " used=", share[b], " tex=", (b as BaseMaterial3D).albedo_texture != null)
		print("AMBIENT river_m==sea_m ", _river_m == _sea_m)
		for n in _coins + [_blades, _ferry]:
			if n: print("AMBIENT ", n.position, " ", (n as MeshInstance3D).mesh.get_aabb(), " surfaces=", (n as MeshInstance3D).mesh.get_surface_count())
	elif _signs.size() < 2 or _coins.size() < 3 or not (_blades and _ferry and _river and _sea): print(_info)

# ---------------------------------------------------------------- every frame (7.2 loop: plane2 .. waterM)
func _process(dt: float) -> void:
	# the club neon pulses always, like 7.2 (it ran outside the play check)
	var rt := Time.get_ticks_msec() * .001
	for i in _signs.size(): _signs[i].albedo_color.a = .7 + sin(rt * 3.0 + i * 2.1) * .3
	if Overlay.any(): return             # the rest holds still while a menu / lesson is up, like 7.2
	_t += dt
	var t := _t
	for i in _coins.size():
		var c := _coins[i]
		c.rotation.y += dt * 2.2
		c.position.y = _coin_y[i] + sin(t * 1.6) * .25
	if _blades: _blades.rotation.z += dt * 1.2
	if _ferry:
		var fz := fmod(t * 7.0, 320.0) - 180.0
		_ferry.position = Vector3(FERRY_X, sin(t * 1.2) * .12, fz)
		if Fx.me and randf() < dt * 1.4 and _near(_ferry.position, 140.0):
			Fx.me.puff(Vector3(FERRY_X, 5.2, fz), SMOKE, 1, .3, .9, 2.0, .5)
	# water: 7.2's gentle bob, plus a slow drift of the ripple texture (the river flows, the sea laps the beach)
	if _river:
		_river.position.y = _river_y + sin(t * .7) * .035
		_river_m.uv1_offset = Vector3(0, fmod(t * .05, 1.0), 0)
	if _sea:
		_sea.position.y = _sea_y + sin(t * .6) * .04
		_sea_m.uv1_offset = Vector3(fmod(t * .012, 1.0) + sin(t * .6) * .03, 0, 0)

func _near(at: Vector3, r: float) -> bool:
	var cam := _world.get_viewport().get_camera_3d() if _world and _world.get_viewport() else null
	return cam != null and cam.global_position.distance_squared_to(at) < r * r

# ---------------------------------------------------------------- finding them in the chunks
func _opaque(b: BaseMaterial3D) -> bool: return b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED

func _is_water(b: BaseMaterial3D, mi: MeshInstance3D, s: int) -> bool:
	if b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: return false
	var c := b.albedo_color
	if c.b < c.r + .3: return false
	var arr := mi.mesh.surface_get_arrays(s)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if v.is_empty() or v.size() > 64: return false
	var lo := Vector3.INF; var hi := -Vector3.INF
	for p in v: lo = lo.min(p); hi = hi.max(p)
	var size := hi - lo
	return size.y < .5 and size.x * size.z > 20000.0

# the first material whose surface has every triangle inside box (the sign quads)
func _material_in(box: AABB, ok: Callable) -> BaseMaterial3D:
	for mi in _chunks:
		if not (mi.global_transform * mi.get_aabb()).intersects(box): continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var b := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if b == null or not ok.call(b): continue
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty() or v.size() > 64: continue
			var inside := true
			for p in v:
				if not box.has_point(xf * p): inside = false; break
			if inside: return b
	return null

# lifts every triangle that lies fully inside box (on surfaces whose material passes ok) out of the city
# chunks into one new MeshInstance3D. centre = true: its origin is the middle of what it took (so it can
# spin in place); false: the middle at ground level (y 0)
func _take(box: AABB, ok: Callable, centre: bool) -> MeshInstance3D:
	var parts: Array = []            # [arrays, take indices, material, xf]
	var lo := Vector3.INF; var hi := -Vector3.INF
	for mi in _chunks:
		if not (mi.global_transform * mi.get_aabb()).intersects(box): continue
		var src := mi.mesh as ArrayMesh
		var xf := mi.global_transform
		var plan := {}
		for s in src.get_surface_count():
			var b := src.surface_get_material(s) as BaseMaterial3D
			if b == null or not ok.call(b): continue
			var arr := src.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if idx.is_empty(): continue
			var keep := PackedInt32Array(); var take := PackedInt32Array()
			for i in range(0, idx.size(), 3):
				var a := xf * v[idx[i]]; var bb := xf * v[idx[i + 1]]; var c := xf * v[idx[i + 2]]
				if box.has_point(a) and box.has_point(bb) and box.has_point(c):
					take.append(idx[i]); take.append(idx[i + 1]); take.append(idx[i + 2])
					lo = lo.min(a).min(bb).min(c); hi = hi.max(a).max(bb).max(c)
				else:
					keep.append(idx[i]); keep.append(idx[i + 1]); keep.append(idx[i + 2])
			if take.is_empty(): continue
			plan[s] = [arr, keep, take]
		if plan.is_empty(): continue
		# edit a copy (keeps every other surface's LODs); highest surface first so the lower indices hold
		var m2 := src.duplicate() as ArrayMesh
		m2.shadow_mesh = null
		var ss := plan.keys(); ss.sort(); ss.reverse()
		for s in ss:
			var arr: Array = plan[s][0]
			var keep: PackedInt32Array = plan[s][1]
			var mat := src.surface_get_material(s)
			m2.surface_remove(s)
			if not keep.is_empty():
				var ka := arr.duplicate(); ka[Mesh.ARRAY_INDEX] = keep
				m2.add_surface_from_arrays(src.surface_get_primitive_type(s), ka)
				m2.surface_set_material(m2.get_surface_count() - 1, mat)
			parts.append([arr, plan[s][2], mat, xf])
		mi.mesh = m2
	if parts.is_empty(): return null
	var mid := (lo + hi) * .5
	var pivot := mid if centre else Vector3(mid.x, 0, mid.z)
	var out := ArrayMesh.new()
	for p in parts:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(p[0], p[1], p[3], pivot))
		out.surface_set_material(out.get_surface_count() - 1, p[2])
	var n := MeshInstance3D.new(); n.mesh = out; n.position = pivot
	Tint.apply(n)
	return n

# the vertices `take` uses, renumbered, moved so `pivot` is the origin
static func _compact(arr: Array, take: PackedInt32Array, xf: Transform3D, pivot: Vector3) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	for i in take:
		if not remap.has(i): remap[i] = order.size(); order.append(i)
		idx.append(remap[i])
	var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := []; out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var a = arr[k]
		if a == null or k == Mesh.ARRAY_INDEX: continue
		var stride: int = a.size() / vc
		if stride <= 0: continue
		var b = a.slice(0, 0)
		for j in order:
			for q in stride: b.append(a[j * stride + q])
		out[k] = b
	var v: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	for j in v.size(): v[j] = xf * v[j] - pivot
	out[Mesh.ARRAY_VERTEX] = v
	if out[Mesh.ARRAY_NORMAL] != null:
		var nr: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
		for j in nr.size(): nr[j] = xf.basis * nr[j]
		out[Mesh.ARRAY_NORMAL] = nr
	out[Mesh.ARRAY_INDEX] = idx
	return out

# a whole surface into a child MeshInstance3D of its chunk (the river, so it can bob on its own)
func _split_surface(mi: MeshInstance3D, s: int) -> MeshInstance3D:
	var src := mi.mesh as ArrayMesh
	var mat := src.surface_get_material(s)
	var one := ArrayMesh.new()
	one.add_surface_from_arrays(src.surface_get_primitive_type(s), src.surface_get_arrays(s))
	one.surface_set_material(0, mat)
	var m2 := src.duplicate() as ArrayMesh
	m2.shadow_mesh = null
	m2.surface_remove(s)
	mi.mesh = m2
	var n := MeshInstance3D.new(); n.name = "River"; n.mesh = one
	mi.add_child(n)
	return n
