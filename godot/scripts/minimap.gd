# The minimap, top right: 7.2's drawMinimap() as a round PS1 radar. North is up, a 120 m window centred on
# her (MMR), her white arrow in the middle, the camera's view as a faint cone. Draws the city blocks
# (city_data.json colliders), the sea and the river (player.water), the world's edge (ZB.city), 7.2's
# MMDOT places, the checkpoints, Bandit, people, red monster dots (bigger for epics and bosses), chests
# and nazar beads once she's been near them (all of them close by after 20 beads, 7.2's nazar radar),
# quest givers with work ("!"), and the objective in gold — pinned to the rim with an arrow when it's
# out of the window. Abroad it just names the island, like 7.2. Redraws ~15 times a second.
# Groups it reads (all optional): enemies, chests (skips opened/open), nazar (skips found/taken),
# npcs, quest_giver (skips avail == false), minimap (any node: meta mm_color / mm_size). Also Items.me.nazars /
# .chests and Quests.me.marker when those systems exist.
class_name Minimap
extends Control

const MMR := 120.0                  # 7.2: world metres from the centre to the edge
const R := 66.0                     # radius on screen
const CITY := [-520.0, 152.0, -424.0, 332.0]
const ABROAD := [[562.0, 638.0, -38.0, 38.0, "CAMEROON"], [562.0, 638.0, 262.0, 338.0, "ARIZONA"], [562.0, 638.0, -338.0, -262.0, "LIVERMORE"]]
# 7.2's MMDOT: home, the market, the mosque, Jayna, the castle... (same coordinates, the city is 7.2's)
const MMDOT := [[-24, -24, "ff9ecf"], [60, -64, "ff4d4d"], [-100, 16, "ff8a5c"], [60, 64, "ffd66b"],
	[-100, -104, "ff2d2d"], [20, 66, "b06bff"], [92, -2, "ff2d78"], [-60, 60, "e8e8f2"],
	[-10, 100, "8ff2ff"], [20, 20, "d8b36a"], [-46, -170, "5fff9e"], [20, -60, "3dff9e"], [-126, 0, "d8a53e"],
	[-140, 60, "ffd66b"], [-180, 100, "8ff2ff"], [-180, -20, "ffe9a0"], [60, -16, "b06bff"], [-60, -64, "2fd0a0"],
	[-20, -58, "3dff9e"], [-214, 0, "ffd66b"], [-232, 60, "8ff2ff"], [-256, -20, "e8e8f2"], [-236, -150, "fff2b0"]]

var player: Node3D
var hud: Node
var _blds: Array = []               # [x, z, hw, hd]
var _seen := {}                     # instance id -> true: chests / beads she's been close to
var _t := 0.0
var _acc := 0.0
var _clip: Control
var _map: Control
var _top: Control
var _font: Font
var C := Vector2(R + 4, R + 4)

func setup(p: Node3D, h: Node) -> void:
	player = p; hud = h
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# top right, pinned to the REAL corner by anchors (widescreen, 8.2): at 4:3 = x 818, y 8 as before
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(R * 2 + 8) - 8; offset_right = -8; offset_top = 8; offset_bottom = 8 + R * 2 + 8
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/city_data.json"))
	if data is Dictionary:
		for c in data.get("colliders", []): _blds.append([float(c["x"]), float(c["z"]), float(c["hw"]), float(c["hd"])])
	# the disc is a mask: everything on the map is clipped to it
	_clip = Control.new(); _clip.size = size; _clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW; add_child(_clip)
	_clip.draw.connect(func(): _clip.draw_circle(C, R, Color("0a0714")))
	_map = Control.new(); _map.size = size; _map.mouse_filter = Control.MOUSE_FILTER_IGNORE; _clip.add_child(_map)
	_map.draw.connect(_draw_map)
	_top = Control.new(); _top.size = size; _top.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_top)
	_top.draw.connect(_draw_top)

func _process(dt: float) -> void:
	_t += dt; _acc -= dt
	if _acc <= 0:
		_acc = 1.0 / 15.0; _map.queue_redraw(); _top.queue_redraw()

func _zone() -> String:
	if not player: return ""
	var p := player.global_position
	for a in ABROAD:
		if p.x > a[0] and p.x < a[1] and p.z > a[2] and p.z < a[3]: return a[4]
	return ""

func _w2m(x: float, z: float) -> Vector2:
	var p := player.global_position
	return C + Vector2(x - p.x, z - p.z) * (R / MMR)

func _vis(x: float, z: float, pad := 0.0) -> bool:
	var p := player.global_position
	return absf(x - p.x) < MMR + pad and absf(z - p.z) < MMR + pad

func _dot(at: Vector2, col: Color, s: float) -> void:
	_map.draw_rect(Rect2(at - Vector2(s, s) * .5, Vector2(s, s)), col)

func _draw_map() -> void:
	if not player or _zone() != "": return
	var s := R / MMR
	var pp := player.global_position
	# the city's ground, then water, then the blocks
	var a := _w2m(CITY[0], CITY[2]); var b := _w2m(CITY[1], CITY[3])
	_map.draw_rect(Rect2(a, b - a), Color("171030"))
	var water = player.get("water")
	if water is Array:
		for w in water:
			var wa := _w2m(float(w[0]), float(w[2])); var wb := _w2m(float(w[1]), float(w[3]))
			_map.draw_rect(Rect2(wa, wb - wa), Color("16485c"))
	for bl in _blds:
		if not _vis(bl[0], bl[1], bl[2] + 4): continue
		var c := _w2m(bl[0], bl[1]); var hs := Vector2(bl[2], bl[3]) * s
		_map.draw_rect(Rect2(c - hs, hs * 2), Color("3a2e5e"))
		_map.draw_rect(Rect2(c - hs, Vector2(hs.x * 2, maxf(1.0, hs.y * .35))), Color("4d3f7a"))   # lit top edge
	_map.draw_rect(Rect2(a, b - a), Color("4a3b66"), false, 1.5)
	for d in MMDOT:
		if _vis(d[0], d[1]): _dot(_w2m(d[0], d[1]), Color(d[2]), 4)
	# checkpoints: little cyan rings
	var main := hud.get_parent() if hud else null
	var cps = main.get("checkpoints") if main else null
	if cps is Array:
		for c in cps:
			if c is Dictionary and _vis(float(c["x"]), float(c["z"])): _map.draw_arc(_w2m(float(c["x"]), float(c["z"])), 3.2, 0, TAU, 10, Color("7bf7ff"), 1.4)
	var tree := get_tree()
	var nz = SaveBridge.data.get("nz")
	var radar: bool = nz is Array and (nz as Array).size() >= 20
	for n in tree.get_nodes_in_group("chests"):
		if not (n is Node3D) or n.get("opened") == true or n.get("open") == true: continue
		var q: Vector3 = n.global_position
		if q.distance_to(pp) < 30: _seen[n.get_instance_id()] = true
		if (_seen.has(n.get_instance_id()) or n.get("discovered") == true) and _vis(q.x, q.z): _dot(_w2m(q.x, q.z), Color("ffd24a"), 4)
	var pulse := .55 + sin(_t * 4.0) * .35
	for n in tree.get_nodes_in_group("nazar"):
		if not (n is Node3D) or n.get("found") == true or n.get("taken") == true or not n.is_visible_in_tree(): continue
		var q: Vector3 = n.global_position
		var dd := q.distance_to(pp)
		if dd < 25: _seen[n.get_instance_id()] = true
		if _seen.has(n.get_instance_id()) or n.get("discovered") == true or (radar and dd < 60):
			_map.draw_circle(_w2m(q.x, q.z), 2.6, Color(.31, .7, 1, pulse))
	# Items.me keeps its beads and chests in arrays, not groups (nazars {node,i,pos}, chests {x,z,open})
	var it: Object = hud.call("sys", "Items") if hud else null
	if it:
		var cl = it.get("chests")
		if cl is Array:
			for c in cl:
				if not (c is Dictionary) or c.get("open", false) == true: continue
				var cx := float(c.get("x", 0)); var cz := float(c.get("z", 0))
				var key := "c%d_%d" % [int(cx), int(cz)]
				if Vector2(cx - pp.x, cz - pp.z).length() < 30: _seen[key] = true
				if _seen.has(key) and _vis(cx, cz): _dot(_w2m(cx, cz), Color("ffd24a"), 4)
		var nl = it.get("nazars")
		if nl is Array:
			for o in nl:
				if not (o is Dictionary) or not (o.get("pos") is Vector3): continue
				if it.has_method("found") and it.call("found", int(o.get("i", -1))): continue
				var q: Vector3 = o["pos"]
				var key := "n%d" % int(o.get("i", -1))
				var dd := Vector2(q.x - pp.x, q.z - pp.z).length()
				if dd < 25: _seen[key] = true
				if (_seen.has(key) or (radar and dd < 60)) and _vis(q.x, q.z): _map.draw_circle(_w2m(q.x, q.z), 2.6, Color(.31, .7, 1, pulse))
	for n in tree.get_nodes_in_group("npcs"):
		if n is Node3D and _vis(n.global_position.x, n.global_position.z): _dot(_w2m(n.global_position.x, n.global_position.z), Color("7bf7ff"), 3)
	for n in tree.get_nodes_in_group("minimap"):
		if not (n is Node3D) or not n.is_visible_in_tree(): continue
		var q: Vector3 = n.global_position
		if _vis(q.x, q.z): _dot(_w2m(q.x, q.z), n.get_meta("mm_color", Color("e8dcff")), float(n.get_meta("mm_size", 3.0)))
	var ban := player.get_parent().get_node_or_null("Bandit") if player.get_parent() else null
	if ban is Node3D and _vis(ban.global_position.x, ban.global_position.z): _dot(_w2m(ban.global_position.x, ban.global_position.z), Color("c8a06b"), 3)
	for n in tree.get_nodes_in_group("quest_giver"):
		if not (n is Node3D) or n.get("avail") == false: continue
		var q: Vector3 = n.global_position
		if _vis(q.x, q.z):
			var m := _w2m(q.x, q.z)
			_map.draw_string_outline(_font, m + Vector2(-3, 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			_map.draw_string(_font, m + Vector2(-3, 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd66b"))
	for e in tree.get_nodes_in_group("enemies"):
		if not (e is Node3D) or not is_instance_valid(e): continue
		if e.has_method("is_alive") and not e.is_alive(): continue
		if not e.has_method("is_alive") and float(e.get("hp") if e.get("hp") != null else 1.0) <= 0: continue
		var q: Vector3 = e.global_position
		if not _vis(q.x, q.z): continue
		var fl = e.get("flags")
		var boss: bool = fl is Dictionary and (fl.has("boss") or fl.has("miniboss"))
		if boss: _map.draw_circle(_w2m(q.x, q.z), 3.5 + sin(_t * 6.0), Color("ff2d5e"))
		elif e.get("elite") == true: _dot(_w2m(q.x, q.z), Color("ffb03b"), 4)
		else: _dot(_w2m(q.x, q.z), Color("ff3b3b"), 3)
	# what the camera sees: a faint cone
	var cam = player.get("cam")
	if cam is Camera3D:
		var f: Vector3 = -cam.global_transform.basis.z
		var ang := atan2(f.x, -f.z)
		var pts := PackedVector2Array([C])
		for i in 7: pts.append(C + Vector2(0, -38).rotated(ang - .55 + .55 * 2.0 * i / 6.0))
		_map.draw_colored_polygon(pts, Color(.48, .97, 1, .09))

# objective + pins: inside the window a dot, outside an arrow on the rim
func _pin(x: float, z: float, col: Color, sz: float) -> void:
	var p := player.global_position
	var d := Vector2(x - p.x, z - p.z)
	if d.length() < MMR - 6:
		var m := _w2m(x, z)
		_top.draw_rect(Rect2(m - Vector2(sz, sz) * .5, Vector2(sz, sz)), col)
		_top.draw_rect(Rect2(m - Vector2(sz, sz) * .5, Vector2(sz, sz)), Color(0, 0, 0, .7), false, 1.0)
		return
	var dir := d.normalized()
	var at := C + dir * (R - 7)
	var a := atan2(dir.x, -dir.y)
	var tri := PackedVector2Array([at + Vector2(0, -6).rotated(a), at + Vector2(4.5, 4).rotated(a), at + Vector2(-4.5, 4).rotated(a)])
	_top.draw_colored_polygon(tri, col)

func _draw_top() -> void:
	# the rim, with a soft cyan glow like 7.2's #mmapWrap
	_top.draw_arc(C, R + 3, 0, TAU, 48, Color(.48, .97, 1, .18), 4.0)
	_top.draw_arc(C, R, 0, TAU, 48, Color("4a3b66"), 2.5)
	if not player: return
	var zn := _zone()
	if zn != "":
		for i in 2:
			var tx: String = ["✈️ " + zn, "airstrip = fly home"][i]
			_top.draw_string_outline(_font, Vector2(4, C.y - 4 + i * 16), tx, HORIZONTAL_ALIGNMENT_CENTER, R * 2, 11, 3, Color.BLACK)
			_top.draw_string(_font, Vector2(4, C.y - 4 + i * 16), tx, HORIZONTAL_ALIGNMENT_CENTER, R * 2, 11, Color("8ff2ff"))
		return
	if hud and hud.has_method("objective_point"):
		var o = hud.objective_point()
		if o is Vector3: _pin(o.x, o.z, Color("ffd66b"), 4.0 + sin(_t * 5.0))
	# the running side quest's target (quests.gd's floating marker), in green
	var qs: Object = hud.call("sys", "Quests") if hud else null
	if qs:
		var qm = qs.get("marker")
		if qm is Node3D and is_instance_valid(qm) and qm.visible: _pin(qm.global_position.x, qm.global_position.z, Color("3dff9e"), 4.0)
	if hud and hud.get("pins") is Dictionary:
		for k in hud.pins:
			var pn: Dictionary = hud.pins[k]
			var pos: Vector3 = pn["pos"]
			_pin(pos.x, pos.z, pn.get("col", Color("3dff9e")), 4.0)
	# her: a white arrow, always dead centre
	var f := Vector3(0, 0, -1)
	if player.has_method("facing"): f = player.facing()
	else:
		var y: float = player.get("heading") if player.get("on_bike") == true else player.get("yaw")
		f = Vector3(-sin(y), 0, -cos(y))
	var a := atan2(f.x, -f.z)
	var tri := PackedVector2Array([C + Vector2(0, -6).rotated(a), C + Vector2(4, 5).rotated(a), C + Vector2(0, 2.5).rotated(a), C + Vector2(-4, 5).rotated(a)])
	_top.draw_colored_polygon(tri, Color.WHITE)
	var ring := tri.duplicate(); ring.append(tri[0])
	_top.draw_polyline(ring, Color(0, 0, 0, .8), 1.0)
	_top.draw_string_outline(_font, Vector2(C.x - 4, 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
	_top.draw_string(_font, Vector2(C.x - 4, 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff5fa2"))
