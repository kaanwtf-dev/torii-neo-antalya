# First-time "how it works" cards — 7.2's TIPS + tip(id). The card itself (and the save's `tips` list that
# remembers which ones she's seen) is LevelUp's; this adds the cards for the NEW moves (assets/story/
# godot.json "tips") and shows each one the first time it matters:
#   combo     a monster comes close for the first time        (F / click combo, RIGHT click heavy)
#   roll      the first time she gets hit                     (Left Ctrl dodge roll, i-frames)
#   block     the third hit she takes                         (hold Z, block just before = parry)
#   lockon    after a few hits on monsters                    (Tab lock-on / next target)
#   skills    first level up, or level 2+ after a minute      (1..N, R; mana)
#   wheel     a new weapon, or 3+ weapons owned               (tap Q / mouse wheel, HOLD Q wheel)
#   inventory the first pickup                                (I bag, J quests, H quick-eat)
# Tips.tip(id) works for any card LevelUp knows (7.2's ones too: deliver, photo, phases...).
class_name Tips
extends Node

static var me: Tips
var D := {}
var torii: Node3D
var _hits_taken := 0
var _hits_done := 0
var _t := 0.0
var _added := false

static func tip(id: String) -> void:
	if LevelUp.me: LevelUp.me.tip(id)

static func seen(id: String) -> bool:
	var t = SaveBridge.data.get("tips")
	return t is Dictionary and t.has(id)

func setup(p: Node3D) -> void:
	me = self; torii = p; name = "Tips"
	D = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/godot.json"))
	_register()
	Bus.on("player_hit", func(d: Dictionary):
		if d.get("blocked", false) or d.get("parried", false): return
		_hits_taken += 1
		if _hits_taken == 1: tip("roll")
		elif _hits_taken == 3: tip("block"))
	Bus.on("enemy_hit", func(_d):
		_hits_done += 1
		if _hits_done == 6: tip("lockon"))
	Bus.on("level_up", func(_d): tip("skills"))
	Bus.on("weapon_new", func(_d): tip("wheel"))
	Bus.on("pickup", func(_d): tip("inventory"))

func _register() -> void:
	if _added or LevelUp.me == null: return
	LevelUp.me.add_tips(D.get("tips", {}))
	_added = true

func _process(dt: float) -> void:
	if not _added: _register(); return
	_t += dt
	if fmod(_t, 1.0) > dt: return              # once a second is plenty
	if not is_instance_valid(torii) or Overlay.any(): return
	if not seen("combo"):
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Node3D and e.global_position.distance_squared_to(torii.global_position) < 16.0 * 16.0:
				tip("combo"); break
	if _t > 60.0 and not seen("skills") and SaveBridge.get_i("lvl", 1) >= 2: tip("skills")
	if not seen("wheel"):
		var w = SaveBridge.data.get("weap")
		if w is Array and w.size() >= 3: tip("wheel")
