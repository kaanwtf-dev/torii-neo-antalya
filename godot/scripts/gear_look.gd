# Gear you can see (7.2 applyGearLook / buildShadesInto): what she wears in the eye, jewellery, bag and shoe
# slots shows on Torii.
#  - eye: the G sunglasses (Menus owns the toggle and the save field `shades`) take the style and the
#    frame / lens colours of the eye item she wears (aviator, cat-eye, visor, round); nothing worn = 7.2's
#    gold aviators
#  - jewellery: hoop earrings, the evil-eye necklace, the gold chain, the beaded bracelet
#  - bags in the item's colour: tote, crossbody, bum bag, backpack
#  - shoes: only add-ons over her own sneakers (platform = a thick sole, roller skates = plate, wheels and
#    toe stop). Combat boots (postal) are left out: they would mean repainting her sneakers, and her model
#    stays exactly the turnaround sheet.
# Everything is small low-poly code meshes with flat colours on BoneAttachment3Ds of her skeleton. The
# numbers are her rest pose in model space (+z = her front, feet at y 0, top of her head 2.2), measured from
# torii.glb. Rebuilt on Bus "gear_eq" (Items equip / unequip) and "gear_gained"; a loaded save reloads the
# scene, so setup() covers that.
class_name GearLook
extends Node

static var me: GearLook
var torii
var sk: Skeleton3D
var dev_look := {}                 # dev only (--gearshots): slot -> base id, shown instead of what she wears
var _roots := {}                   # bone -> Node3D in her model space, following that bone
var _gear := {}                    # bone -> the node holding the current pieces (cleared on a change)
var _shades: Node3D
var _shades_key := ""
var _key := "?"

func setup(p) -> void:
	me = self; torii = p
	if p == null or p.get("pose") == null: return
	sk = p.pose.sk
	Bus.on("gear_eq", func(_d): if is_instance_valid(self): refresh())
	Bus.on("gear_gained", func(_d): if is_instance_valid(self): refresh())
	refresh()
	for a in OS.get_cmdline_user_args(): if a.begins_with("--gearshots="): _dev_shots(a.substr(12))

# the base (GEARBASE row) of what she wears in a slot, or {}
func _base(sl: String) -> Dictionary:
	if dev_look.has(sl):
		for g in Stats.data()["GEARBASE"]: if g["id"] == dev_look[sl]: return g
		return {}
	if Items.me == null or not SaveBridge.data.get("eq") is Dictionary: return {}
	var it: Dictionary = Items.me.eq_item(sl)
	return {} if it.is_empty() else Items.me.base_of(it)

func _col(b: Dictionary, k: String, fallback: String) -> Color:
	return Color(str(b[k])) if b.get(k) is String else Color(fallback)

func refresh() -> void:
	if sk == null: return
	_fill_shades()
	var parts := []
	for sl in ["jew", "shoe", "bag"]:
		var b := _base(sl); parts.append("%s:%s" % [b.get("id", ""), b.get("col", "")])
	var key := ",".join(parts)
	if key == _key: return
	_key = key
	for g in _gear.values():
		for c in g.get_children(): c.queue_free()
	var jb := _base("jew"); var jc := _col(jb, "col", "#ffd66b")
	match str(jb.get("id", "")):
		"hoops": _hoops(jc)
		"nazark": _necklace(false)
		"zincir": _necklace(true)
		"bileklik": _bracelet()
	var sid := str(_base("shoe").get("id", ""))
	if sid == "platform" or sid == "paten":
		for s in [-1, 1]: _shoe(sid, s, _col(_base("shoe"), "col", "#ff5fa2"))
	var bb := _base("bag"); var bc := _col(bb, "col", "#2fa08f")
	match str(bb.get("id", "")):
		"bez": _tote(bc)
		"capraz": _crossbody(bc)
		"bel": _bumbag(bc)
		"sirt": _backpack(bc)

# a node in her model space that follows `bone` (her rest pose has unrotated bones, so this is just the
# bone's rest transform undone)
func _root(bone: String) -> Node3D:
	if _roots.has(bone): return _roots[bone]
	var ba := BoneAttachment3D.new(); ba.name = "Gear_" + bone; ba.bone_name = bone; sk.add_child(ba)
	var r := Node3D.new(); r.transform = sk.get_bone_global_rest(sk.find_bone(bone)).affine_inverse(); ba.add_child(r)
	var g := Node3D.new(); g.name = "Pieces"; r.add_child(g)
	_roots[bone] = r; _gear[bone] = g
	return r

func _on(bone: String) -> Node3D:
	_root(bone)
	return _gear[bone]

# ---------------------------------------------------------------- little mesh kit
func _mat(c: Color, shiny := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = .45 if shiny else 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m

func _put(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat
	mi.position = at; mi.rotation = rot; mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi); return mi

func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b

func _cyl(r: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = seg; c.rings = 1
	return c

func _ring(r: float, w: float, seg := 12) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = r - w; t.outer_radius = r + w; t.rings = seg; t.ring_segments = 4
	return t

func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 6; s.rings = 3
	return s

# a strap / chain: thin boxes from point to point (each a little longer so the joints close)
func _strap(parent: Node3D, pts: Array, w: float, mat: Material, t := -1.0) -> void:
	if t < 0: t = w
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]; var b: Vector3 = pts[i + 1]
		var d := b - a
		if d.length() < .001: continue
		var mi := MeshInstance3D.new(); mi.mesh = _box(w, t, d.length() + w * .8); mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up := Vector3.UP if absf(d.normalized().y) < .9 else Vector3.BACK
		mi.transform = Transform3D(Basis.looking_at(d, up), (a + b) * .5)
		parent.add_child(mi)

# a closed loop from half of it (back centre -> her left side -> front centre), mirrored to her right side
func _mirror(half: Array) -> Array:
	var out := half.duplicate()
	for i in range(half.size() - 2, -1, -1): out.append(Vector3(-half[i].x, half[i].y, half[i].z))
	return out

# ---------------------------------------------------------------- 🕶 sunglasses (7.2 buildShadesInto)
# Menus asks for the node the first time she presses G; it stays and is restyled when the eye item changes
func shades_node() -> Node3D:
	if _shades == null and sk != null:
		_shades = Node3D.new(); _shades.name = "Shades"; _root("head").add_child(_shades)
		_shades_key = ""; _fill_shades()
	return _shades

func _fill_shades() -> void:
	if _shades == null: return
	var eb := _base("eye")
	var id := str(eb.get("id", "aviator"))
	var style := id if id in ["cateye", "visor", "round"] else "aviator"
	var fc := _col(eb, "col", "#d8b04a"); var lc := _col(eb, "lens", "#1a2a44")
	var key := "%s|%s|%s" % [style, fc.to_html(), lc.to_html()]
	if key == _shades_key: return
	_shades_key = key
	for c in _shades.get_children(): c.queue_free()
	var fm := _mat(fc, true); var lm := _mat(lc, true)
	const EY := 1.995; const EZ := .127; const EX := .047; const R := .034
	if style == "visor":
		# one wrap-around lens in panels round the front of her head, a frame line along the top
		var c := Vector3(0, EY, -.031)
		var n := 5; var a0 := -1.1; var a1 := 1.1
		var step := (a1 - a0) / n
		for i in n:
			var a := a0 + step * (i + .5)
			var rr := .158
			_put(_shades, _box(2.0 * rr * sin(step / 2) + .004, .056, .006), lm, c + Vector3(sin(a) * rr, 0, cos(a) * rr), Vector3(0, a, 0))
			_put(_shades, _box(2.0 * (rr + .003) * sin(step / 2) + .004, .011, .009), fm, c + Vector3(sin(a) * (rr + .003), .031, cos(a) * (rr + .003)), Vector3(0, a, 0))
		return
	var sx := 1.25 if style == "cateye" else (1.0 if style == "round" else 1.12)
	var sy := .72 if style == "cateye" else (1.0 if style == "round" else .95)
	var r := .03 if style == "round" else R
	for s in [-1.0, 1.0]:
		var h := Node3D.new(); _shades.add_child(h)
		h.position = Vector3(s * EX, EY - (.004 if style == "aviator" else 0.0), EZ)
		h.scale = Vector3(sx, sy, 1)
		if style == "cateye": h.rotation.z = s * .22
		_put(h, _cyl(r, .005, 10), lm, Vector3.ZERO, Vector3(PI / 2, 0, 0))
		_put(h, _ring(r, .0045, 10), fm, Vector3(0, 0, .002), Vector3(PI / 2, 0, 0))
		# the arm back over her ear (into her hair)
		var o := Vector3(s * (EX + r * sx), EY + .006, EZ - .006)
		_strap(_shades, [o, Vector3(s * .118, EY + .009, .07), Vector3(s * .148, EY + .01, .0)], .007, fm)
	_strap(_shades, [Vector3(-(EX - r * sx) - .002, EY + .012, EZ + .004), Vector3(EX - r * sx + .002, EY + .012, EZ + .004)], .006, fm)

# ---------------------------------------------------------------- 💍 jewellery
func _hoops(c: Color) -> void:
	var g := _on("head"); var m := _mat(c, true)
	for s in [-1.0, 1.0]:
		_put(g, _ring(.032, .0055), m, Vector3(s * .192, 1.858, .004), Vector3(0, 0, PI / 2))

func _necklace(gold_chain: bool) -> void:
	var g := _on("body")
	var lo := .012 if gold_chain else 0.0       # the chain sits a little lower and thicker
	var half := [Vector3(0, 1.80, -.075), Vector3(.055, 1.795, -.05), Vector3(.068, 1.785, -.004),
		Vector3(.07, 1.748 - lo * .5, .066), Vector3(.045, 1.716 - lo, .099 + lo * .3), Vector3(0, 1.70 - lo, .114 + lo * .3)]
	var loop := _mirror(half)
	if gold_chain:
		_strap(g, loop, .013, _mat(Color("ffc83a"), true))
		return
	_strap(g, loop, .006, _mat(Color("d8c070"), true))
	# the nazar bead: dark blue, white, light blue, black — flat discs facing out of her chest
	var bead := Node3D.new(); bead.position = Vector3(0, 1.668, .131); bead.rotation.x = -.45; g.add_child(bead)
	var rings := [[.024, "1f4fb0"], [.016, "ffffff"], [.011, "6fc8ff"], [.005, "101018"]]
	for i in rings.size():
		_put(bead, _cyl(rings[i][0], .003, 10), _mat(Color(rings[i][1])), Vector3(0, 0, i * .0018), Vector3(PI / 2, 0, 0))
	_strap(g, [Vector3(0, 1.70, .116), Vector3(0, 1.69, .127)], .005, _mat(Color("d8c070"), true))

func _bracelet() -> void:
	# on her right wrist (-x arm), like 7.2: ten beads, pink and cyan
	var g := _on("elb_m"); var pink := _mat(Color("ff9ecf")); var cyan := _mat(Color("7bf7ff"))
	for i in 10:
		var a := TAU * i / 10.0
		_put(g, _ball(.013), pink if i % 2 else cyan, Vector3(-.712, 1.718 + cos(a) * .033, -.01 + sin(a) * .037))

# ---------------------------------------------------------------- 👟 shoe add-ons (her sneakers stay hers)
func _shoe(kind: String, s: int, c: Color) -> void:
	var g := _on("kn_p" if s > 0 else "kn_m")
	var x := s * .205
	if kind == "platform":
		_put(g, _box(.174, .062, .452), _mat(c), Vector3(x, .031, .013))
		return
	# roller skates: a plate, two axles, four yellow wheels, a toe stop
	var grey := _mat(Color("8a8a95"), true); var wheel := _mat(Color("ffd66b"))
	_put(g, _box(.13, .018, .37), grey, Vector3(x, .03, .012))
	for z in [-.14, .15]:
		_put(g, _box(.19, .014, .016), grey, Vector3(x, .036, z))
		for d in [-1.0, 1.0]:
			_put(g, _cyl(.036, .03, 8), wheel, Vector3(x + d * .089, .036, z), Vector3(0, 0, PI / 2))
	_put(g, _cyl(.022, .04, 8), _mat(Color("3a3a44")), Vector3(x, .03, .238), Vector3(PI / 2, 0, 0))

# ---------------------------------------------------------------- 👜 bags, in the item's colour
func _tote(c: Color) -> void:
	# hanging off her left shoulder (+x), flat against the back of her hip; the handles run behind her arm
	var g := _on("body"); var m := _mat(c)
	_put(g, _box(.05, .26, .22), m, Vector3(.226, 1.08, -.135), Vector3(0, PI / 4, 0))
	_strap(g, [Vector3(.292, 1.2, -.072), Vector3(.176, 1.48, -.076), Vector3(.13, 1.75, -.025)], .018, m, .008)
	_strap(g, [Vector3(.163, 1.2, -.202), Vector3(.152, 1.48, -.106), Vector3(.12, 1.75, -.04)], .018, m, .008)

func _crossbody(c: Color) -> void:
	# small bag on her right hip, strap from her left shoulder across her chest and round her back
	var g := _on("body"); var m := _mat(c)
	_put(g, _box(.16, .13, .055), m, Vector3(-.208, 1.19, .13), Vector3(0, -.45, 0))
	_put(g, _box(.162, .05, .058), _mat(c.darkened(.25)), Vector3(-.207, 1.235, .132), Vector3(0, -.45, 0))
	_strap(g, [Vector3(-.15, 1.25, .145), Vector3(-.06, 1.40, .126), Vector3(.02, 1.54, .152), Vector3(.075, 1.66, .124),
		Vector3(.11, 1.735, .045), Vector3(.12, 1.765, -.03), Vector3(.06, 1.6, -.105), Vector3(-.06, 1.4, -.12),
		Vector3(-.2, 1.25, -.075), Vector3(-.245, 1.2, .03), Vector3(-.27, 1.2, .085)], .018, m, .008)

func _bumbag(c: Color) -> void:
	# round pouch at the front of her belt line, the strap round her waist
	var g := _on("body"); var m := _mat(c)
	var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 8; sm.rings = 4
	_put(g, sm, m, Vector3(0, 1.235, .198), Vector3.ZERO, Vector3(.13, .068, .055))
	_put(g, _box(.15, .008, .01), _mat(c.darkened(.35)), Vector3(0, 1.262, .248))       # the zip
	var ring := []
	for i in 13:
		var a := TAU * i / 12.0
		ring.append(Vector3(sin(a) * .226, 1.256, cos(a) * .172))
	_strap(g, ring, .02, m, .01)

func _backpack(c: Color) -> void:
	# on her back, behind her braids; the straps go round the outside of them and over her shoulders
	var g := _on("body"); var m := _mat(c)
	_put(g, _box(.29, .34, .13), m, Vector3(0, 1.53, -.29))
	_put(g, _box(.21, .14, .04), _mat(c.darkened(.3)), Vector3(0, 1.44, -.37))
	for s in [-1.0, 1.0]:
		_strap(g, [Vector3(s * .11, 1.69, -.236), Vector3(s * .142, 1.77, -.09), Vector3(s * .132, 1.762, .025),
			Vector3(s * .118, 1.66, .106), Vector3(s * .128, 1.52, .1), Vector3(s * .16, 1.43, 0),
			Vector3(s * .152, 1.4, -.125), Vector3(s * .11, 1.39, -.226)], .03, m, .012)

# ---------------------------------------------------------------- dev: --gearshots=DIR
# four sets of gear, each as one picture of four views (front, her left side, back, a close-up), straight
# from the 3D view (no HUD), then an orderly quit. Shows the gear without touching what she wears.
func _dev_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(3.0).timeout
	if Spawner.me: Spawner.me.enabled = false
	var boxes := get_tree().root.find_children("*", "SubViewportContainer", true, false)
	if boxes.is_empty(): return
	var box: SubViewportContainer = boxes[0]
	var sharp := not ("--gearlow" in OS.get_cmdline_user_args())
	if sharp: box.stretch_shrink = 1
	var vp: SubViewport = box.get_child(0)
	var cam := Camera3D.new(); cam.fov = 38; cam.near = .05; torii.get_parent().add_child(cam); cam.current = true
	if Menus.me: Menus.me.set_shades(true, true)
	var sets := [{"eye": "aviator", "jew": "hoops", "shoe": "platform", "bag": "bez"},
		{"eye": "cateye", "jew": "nazark", "shoe": "paten", "bag": "capraz"},
		{"eye": "visor", "jew": "zincir", "shoe": "paten", "bag": "bel"},
		{"eye": "round", "jew": "bileklik", "shoe": "spor", "bag": "sirt"}]
	var views := [[0.0, 3.4, 1.1], [PI / 2, 3.4, 1.1], [PI, 3.4, 1.1], [.6, 1.25, 1.78]]
	for i in sets.size():
		dev_look = sets[i]; refresh()
		var sheet := Image.create(960, 720, false, Image.FORMAT_RGBA8)
		for k in views.size():
			var v: Array = views[k]
			var f: Vector3 = torii.facing(); var r := f.cross(Vector3.UP).normalized()
			var c: Vector3 = torii.global_position + Vector3(0, v[2], 0)
			cam.global_position = c + (f * cos(v[0]) + r * sin(v[0])) * v[1] + Vector3(0, .12, 0)
			cam.look_at(c, Vector3.UP)
			for n in 3: await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8); img.resize(480, 360)
			sheet.blit_rect(img, Rect2i(0, 0, 480, 360), Vector2i((k % 2) * 480, (k / 2) * 360))
		sheet.save_png(dir.path_join("gear_%d.png" % i))
	dev_look = {}
	print("GEARSHOTS ", dir)
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
