# The skill bar, bottom centre: 7.2's #skills (buildSkillBar / updateSkillBar). One slot per skill from
# Skills.me.hotbar(): the key number (gold), the icon, the mana cost (cyan) or "LvN" while it's locked,
# greyed out when she's short on mana, and a clock-style cooldown sweep with the seconds left. A slot
# flashes when it comes off cooldown or gets used (Bus "skill_used"). Clicking a slot uses it, like 7.2.
# Slot dicts may carry: id, ic/icon, n/name, key, mana/cost, cd/cd_left, cd_max/cdmax, locked/lock, lv,
# nomana (Skills.me gives id, name, icon, key, cd_left, cd_total, mana, locked, lock_text, no_mana, new).
# Missing keys are fine. With no Skills system yet the bar just isn't there.
class_name Hotbar
extends Control

const W := 46.0
const H := 50.0
const GAP := 6.0

var hud: Node
var _slots: Array = []           # normalised slot dicts from the last poll
var _flash := {}                 # index -> seconds of white border left
var _was_cd := {}                # index -> was cooling down last poll
var _poll := 0.0
var _font: Font

func setup(h: Node) -> void:
	hud = h; _font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_PASS
	Bus.on("skill_used", _on_used)

func _on_used(d: Dictionary) -> void:
	for i in _slots.size():
		if str(_slots[i]["id"]) == str(d.get("id", "")): _flash[i] = .35

static func _pick(d: Dictionary, keys: Array, def: Variant) -> Variant:
	for k in keys:
		if d.has(k) and d[k] != null: return d[k]
	return def

func _process(dt: float) -> void:
	_poll -= dt
	if _poll <= 0:
		_poll = .05
		_slots.clear()
		var sk: Object = hud.call("sys", "Skills") if hud else null
		if sk and sk.has_method("hotbar"):
			var list = sk.call("hotbar")
			if list is Array:
				var mana := 0.0
				var p = hud.get("player")
				if p and p.get("mana") != null: mana = float(p.get("mana"))
				for i in (list as Array).size():
					var raw = list[i]
					if not (raw is Dictionary): continue
					var s := {
						"id": _pick(raw, ["id"], str(i)), "ic": str(_pick(raw, ["ic", "icon"], "✨")),
						"key": str(_pick(raw, ["key"], str(i + 1))), "mana": float(_pick(raw, ["mana", "cost"], 0)),
						"cd": float(_pick(raw, ["cd", "cd_left"], 0)), "cdmax": float(_pick(raw, ["cd_total", "cd_max", "cdmax", "max_cd"], 1)),
						"locked": bool(_pick(raw, ["locked", "lock"], false)), "lv": int(_pick(raw, ["lv", "level"], 0)),
						"lt": str(_pick(raw, ["lock_text"], "")), "new": bool(_pick(raw, ["new"], false))}
					s["nomana"] = bool(_pick(raw, ["no_mana", "nomana"], mana < s["mana"]))
					var cooling: bool = s["cd"] > 0.05
					if _was_cd.get(i, false) and not cooling: _flash[i] = .35          # ready again
					_was_cd[i] = cooling
					_slots.append(s)
		var n := _slots.size()
		size = Vector2(maxf(0.0, n * (W + GAP) - GAP), H)
		position = Vector2(480 - size.x * .5, 720 - H - 12)
	for k in _flash.keys():
		_flash[k] = _flash[k] - dt
		if _flash[k] <= 0: _flash.erase(k)
	visible = not _slots.is_empty() and not Overlay.any()
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT): return
	var i := int(e.position.x / (W + GAP))
	if i < 0 or i >= _slots.size(): return
	var sk: Object = hud.call("sys", "Skills") if hud else null
	if not sk: return
	for m in ["use_slot", "use_skill", "use"]:
		if sk.has_method(m): sk.call(m, i); accept_event(); return

# the dark part of a square cooldown sweep: from 12 o'clock round clockwise by `frac` of a turn
func _sweep(r: Rect2, frac: float) -> void:
	if frac <= 0.001: return
	var c := r.get_center(); var hw := r.size.x * .5; var hh := r.size.y * .5
	var pts := PackedVector2Array([c])
	var steps := maxi(2, int(ceil(frac * 32)))
	# the sweep covers what's still cooling: from where it's got to round to 12 o'clock
	for j in steps + 1:
		var a := TAU * (1.0 - frac) + TAU * frac * j / steps
		var d := Vector2(sin(a), -cos(a))
		var t := minf(hw / maxf(absf(d.x), .0001), hh / maxf(absf(d.y), .0001))
		pts.append(c + d * t)
	draw_colored_polygon(pts, Color(10 / 255.0, 5 / 255.0, 25 / 255.0, .82))

func _draw() -> void:
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var r := Rect2(Vector2(i * (W + GAP), 0), Vector2(W, H))
		var dim: bool = s["locked"] or s["nomana"]
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(16 / 255.0, 7 / 255.0, 30 / 255.0, .88)
		sb.border_color = Color("4a3b66") if dim else Color("7bf7ff") if s["cd"] <= .05 else Color("6b5a8e")
		if _flash.has(i): sb.border_color = Color.WHITE; sb.shadow_color = Color(1, 1, 1, .5); sb.shadow_size = 6
		sb.set_border_width_all(2); sb.set_corner_radius_all(8)
		draw_style_box(sb, r)
		var icol := Color(1, 1, 1, .35) if s["locked"] else Color(1, 1, 1, .5) if s["nomana"] else Color.WHITE
		draw_string(_font, Vector2(r.position.x, r.position.y + 30), s["ic"], HORIZONTAL_ALIGNMENT_CENTER, W, 22, icol)
		if s["cd"] > .05 and not s["locked"]:
			_sweep(r.grow(-2), clampf(s["cd"] / maxf(.01, s["cdmax"]), 0, 1))
			var tx := ("%.1f" % s["cd"]) if s["cd"] < 1.0 else str(int(ceil(s["cd"])))
			draw_string_outline(_font, Vector2(r.position.x, r.position.y + 31), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 15, 4, Color.BLACK)
			draw_string(_font, Vector2(r.position.x, r.position.y + 31), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color("7bf7ff"))
		draw_string_outline(_font, r.position + Vector2(4, 11), s["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
		draw_string(_font, r.position + Vector2(4, 11), s["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ffd66b"))
		if s["new"] and not s["locked"]:
			draw_string_outline(_font, Vector2(r.position.x, r.position.y + 11), "NEW", HORIZONTAL_ALIGNMENT_RIGHT, W - 3, 8, 3, Color.BLACK)
			draw_string(_font, Vector2(r.position.x, r.position.y + 11), "NEW", HORIZONTAL_ALIGNMENT_RIGHT, W - 3, 8, Color("ff5fa2"))
		var mc: String = (s["lt"] if s["lt"] != "" else "Lv%d" % s["lv"]) if s["locked"] else str(int(s["mana"]))
		draw_string_outline(_font, Vector2(r.position.x, r.end.y - 4), mc, HORIZONTAL_ALIGNMENT_CENTER, W, 10, 3, Color.BLACK)
		draw_string(_font, Vector2(r.position.x, r.end.y - 4), mc, HORIZONTAL_ALIGNMENT_CENTER, W, 10, Color("ff6b6b") if s["nomana"] and not s["locked"] else Color("8ff2ff"))
