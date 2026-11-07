# 7.2's weapon wheel (openWheel / wheelHi / wheelAim / closeWheel, #wheel CSS): hold Q and every weapon she
# owns lies in a ring, plus bare hands. Move the mouse to aim the little cursor (dead zone in the hub), or
# 1-9 / A D / ← → / the mouse wheel; the middle shows the one she's on: name, rarity, damage, speed, DPS,
# reach or ammo, condition bar. Releasing Q (or a click / Enter) equips it; Esc puts it away.
# Ranged weapons with no ammo show red and can't be picked. Drawn at full window resolution in 7.2's neon.
# Arsenal owns the logic (what's equipped, the time slow-down); this is only the picture and the cursor.
class_name WeaponWheel
extends CanvasLayer

const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURPLE := Color("b06bff")
const RED := Color("ff3b3b")
const RARCOL := {"Unarmed": "e8e8f2", "Common": "b8b8c4", "Uncommon": "5fff9e", "Rare": "5fb0ff", "Epic": "c07bff",
	"LEGENDARY": "ffa53a", "CURSED": "ff3b3b", "TAVLA CHAMPION": "ffd66b", "Mission": "ff5fa2",
	"Mission · FEARED": "ff2d5e", "Mission · RIGGED": "ffd66b", "MISSION LEGENDARY": "ffe9a0"}

var is_open := false
var slots: Array = []            # [{k, a, info}]
var pick := 0
var cur := Vector2.ZERO          # the cursor, in pixels from the centre
var equipped := ""
var _c: Control
var _font: Font

static func rar_col(r: String) -> Color: return Color(RARCOL.get(r, "ff9ecf"))

func _ready() -> void:
	layer = 8                          # over the HUD, under the faint/travel fade
	_c = Control.new(); _c.set_anchors_preset(Control.PRESET_FULL_RECT); _c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_c); _c.draw.connect(_draw_wheel)
	_font = ThemeDB.fallback_font
	visible = false

func _radius() -> float:
	var s := _c.size
	return minf(320.0, minf(s.x, s.y) * .46)

func _k() -> float: return clampf(minf(_c.size.x / 960.0, _c.size.y / 720.0), .7, 1.6)

# list = weapon ids (bare hands included); infos = Arsenal.weapon_info for each
func show_wheel(list: Array, infos: Array, eq: String) -> void:
	slots.clear(); equipped = eq
	for i in list.size():
		slots.append({"k": list[i], "a": -PI / 2 + i * TAU / list.size(), "info": infos[i]})
	pick = maxi(0, list.find(eq))
	var sa: float = slots[pick]["a"] if slots.size() else -PI / 2
	cur = Vector2(cos(sa), sin(sa)) * _radius() * .62     # start on what she's holding
	is_open = true; visible = true; _c.queue_redraw()

func hide_wheel() -> void:
	is_open = false; visible = false

func refresh(infos: Array) -> void:
	for i in mini(infos.size(), slots.size()): slots[i]["info"] = infos[i]
	_c.queue_redraw()

func step(n: int) -> void:
	if slots.is_empty(): return
	pick = posmod(pick + n, slots.size()); _c.queue_redraw()

func set_pick(i: int) -> void:
	if i >= 0 and i < slots.size(): pick = i; _c.queue_redraw()

func picked() -> String: return slots[pick]["k"] if pick < slots.size() else ""

# mouse movement steers the cursor; it's clamped to the ring and picks the nearest slot by angle
# (returns true when the pick changed, so Arsenal can tick)
func aim(rel: Vector2) -> bool:
	var R := _radius()
	cur += rel * .85
	if cur.length() > R * .92: cur = cur.normalized() * R * .92
	_c.queue_redraw()
	if cur.length() < R * .17 or slots.is_empty(): return false
	var a := cur.angle()
	var best := pick
	var bd := 1e9
	for i in slots.size():
		var d := absf(angle_difference(a, float(slots[i]["a"])))
		if d < bd: bd = d; best = i
	if best != pick: pick = best; return true
	return false

func _draw_wheel() -> void:
	if not is_open: return
	var S := _c.size
	var C := S / 2.0
	var k := _k()
	var R := _radius()
	var RP := R * (.78 if slots.size() > 10 else .72)
	# the dark veil + the ring
	_c.draw_rect(Rect2(Vector2.ZERO, S), Color(4 / 255.0, 2 / 255.0, 10 / 255.0, .72))
	_c.draw_circle(C, R * .98, Color(.08, .03, .16, .55))
	_c.draw_arc(C, R * .98, 0, TAU, 64, Color(PURPLE, .55), 2.0)
	var pulse := .5 + .5 * sin(Time.get_ticks_msec() / 160.0)
	for i in slots.size():
		var s: Dictionary = slots[i]
		var info: Dictionary = s["info"]
		var on := i == pick
		var dry: bool = info.get("dry", false)
		var w := (104.0 if not on else 126.0) * k
		var h := (66.0 if not on else 80.0) * k
		var at := C + Vector2(cos(s["a"]), sin(s["a"])) * RP
		var box := Rect2(at - Vector2(w, h) / 2.0, Vector2(w, h))
		var sb := StyleBoxFlat.new(); sb.set_corner_radius_all(int(10 * k)); sb.set_border_width_all(2 if not on else 3)
		sb.bg_color = Color(52 / 255.0, 8 / 255.0, 14 / 255.0, .92) if dry else (Color(30 / 255.0, 14 / 255.0, 54 / 255.0, .98) if on else Color(16 / 255.0, 8 / 255.0, 30 / 255.0, .88))
		sb.border_color = (Color("ff5a5a") if dry else CYAN) if on else (RED if dry else (GOLD if s["k"] == equipped else Color(PURPLE, .7)))
		if on: sb.shadow_color = Color(sb.border_color, .35 + .25 * pulse); sb.shadow_size = int(12 * k)
		_c.draw_style_box(sb, box)
		var icon: String = info.get("icon", "?")
		var nm: String = info.get("name", s["k"])
		var fs := int(26 * k * (1.15 if on else 1.0))
		_c.draw_string(_font, Vector2(box.position.x, box.position.y + fs * 1.05), icon, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
			Color(1, 1, 1, .4 if dry else 1.0))
		var ns := int(10 * k * (1.1 if on else 1.0))
		var label := ("%d " % (i + 1) if i < 9 else "") + nm
		_c.draw_string_outline(_font, Vector2(box.position.x + 3, box.position.y + h * .74), label, HORIZONTAL_ALIGNMENT_CENTER, w - 6, ns, 3, Color(0, 0, 0, .8))
		_c.draw_string(_font, Vector2(box.position.x + 3, box.position.y + h * .74), label, HORIZONTAL_ALIGNMENT_CENTER, w - 6, ns,
			Color("ff8a8a") if dry else Color("cfc0e8"))
		if dry:
			_c.draw_string(_font, Vector2(box.position.x, box.position.y + h - 5 * k), "NO AMMO", HORIZONTAL_ALIGNMENT_CENTER, w, int(8 * k), Color("ff6b6b"))
		elif info.get("dur_max", -1) > 0:                  # a thin condition bar along the bottom
			var bw := w - 20 * k
			var fr := clampf(float(info["dur"]) / float(info["dur_max"]), 0.0, 1.0)
			var bp := Vector2(box.position.x + 10 * k, box.position.y + h - 8 * k)
			_c.draw_rect(Rect2(bp, Vector2(bw, 3 * k)), Color("241238"))
			_c.draw_rect(Rect2(bp, Vector2(bw * fr, 3 * k)), PINK.lerp(GOLD, fr))
	_draw_hub(C, k)
	# the cursor dot
	_c.draw_circle(C + cur, 7 * k, Color(CYAN, .25))
	_c.draw_circle(C + cur, 4 * k, CYAN)
	var hint := "move the mouse · 1-9 · A/D  —  let go of Q to equip  ·  Esc = cancel"
	_c.draw_string_outline(_font, Vector2(0, S.y * .94), hint, HORIZONTAL_ALIGNMENT_CENTER, S.x, int(12 * k), 4, Color(0, 0, 0, .8))
	_c.draw_string(_font, Vector2(0, S.y * .94), hint, HORIZONTAL_ALIGNMENT_CENTER, S.x, int(12 * k), Color("cfc0e8"))

# the middle: everything about the weapon under the cursor (7.2's #wheelHub)
func _draw_hub(C: Vector2, k: float) -> void:
	if slots.is_empty(): return
	var info: Dictionary = slots[pick]["info"]
	var dry: bool = info.get("dry", false)
	var W := 250.0 * k
	var x := C.x - W / 2.0
	var y := C.y - 92 * k
	var title: String = str(info.get("n", ""))
	_c.draw_string_outline(_font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_CENTER, W, int(19 * k), 4, Color(0, 0, 0, .8))
	_c.draw_string(_font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_CENTER, W, int(19 * k), RED if dry else Color.WHITE)
	y += 20 * k
	var rar := "✖ NO AMMO — CAN'T FIRE" if dry else "◆ " + str(info.get("rar", "")).to_upper()
	_c.draw_string(_font, Vector2(x, y), rar, HORIZONTAL_ALIGNMENT_CENTER, W, int(11 * k), Color("ff5a5a") if dry else rar_col(str(info.get("rar", ""))))
	y += 22 * k
	var lines := [["Damage", str(int(info.get("dmg", 0)))],
		["Speed", "%s (%.2fs)" % [info.get("speed", ""), float(info.get("cd", 0))]],
		["DPS", str(int(round(info.get("dps", 0))))]]
	if info.get("shock", false): lines.append(["Shock", "%.0fm all round · stuns" % float(info.get("rng", 8))])
	elif info.get("ranged", false): lines.append(["RANGED · ammo", str(info.get("ammo", 0))])
	else: lines.append(["Reach", "%.1fm" % float(info.get("rng", 0))])
	if float(info.get("arc", 0)) > 2: lines.append(["Wide sweep", ""])
	if str(info.get("desc", "")) != "": lines.append([str(info["desc"]), ""])
	var dm: int = info.get("dur_max", -1)
	lines.append(["Condition", "∞" if dm <= 0 else "%d / %d" % [int(info.get("dur", dm)), dm]])
	for L in lines:
		_c.draw_string(_font, Vector2(x + 18 * k, y), L[0], HORIZONTAL_ALIGNMENT_LEFT, W * .55, int(12 * k), Color("d9c8ff"))
		_c.draw_string(_font, Vector2(x + W * .5, y), L[1], HORIZONTAL_ALIGNMENT_RIGHT, W * .5 - 18 * k, int(12 * k),
			(Color("ff5a5a") if dry and L[0].begins_with("RANGED") else GOLD))
		y += 18 * k
	# the condition bar (7.2's #whBar: pink to gold)
	var bw := W - 36 * k
	var bp := Vector2(x + 18 * k, y - 4 * k)
	var fr := 1.0 if dm <= 0 else clampf(float(info.get("dur", dm)) / float(dm), 0.0, 1.0)
	_c.draw_rect(Rect2(bp, Vector2(bw, 7 * k)), Color("241238"))
	_c.draw_rect(Rect2(bp, Vector2(bw * fr, 7 * k)), Color(PINK.lerp(GOLD, fr), .25 if dm <= 0 else 1.0))
	_c.draw_rect(Rect2(bp, Vector2(bw, 7 * k)), Color("4a3b66"), false, 1.0)

func _process(_dt: float) -> void:
	if is_open: _c.queue_redraw()        # the selected slot pulses
