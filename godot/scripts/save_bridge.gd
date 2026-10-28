# Torii's save — the SAME `torii_save` the HTML game uses (+ `torii_save_bak`, `torii_save_bak2`).
# On the website it's the browser's localStorage (same site = same save as 7.2); on desktop a file.
#
# Never lose her progress: we keep the whole save dictionary we loaded and only change the fields the
# Godot build understands, so everything 7.2 stores (words, perks, gear, quests...) survives untouched.
# Writes roll the backups exactly like 7.2's saveGame(). A new save carries lvlv:2 so 7.2 never runs its
# pre-7.0 conversion on it.
class_name SaveBridge
extends RefCounted

const KEY := "torii_save"
static var data := {}               # the full save, as loaded
static var loaded_from := ""        # "", "torii_save", "torii_save_bak", "torii_save_bak2"
static var file_dir := "user://"    # desktop only; tests point it elsewhere with --savedir=

static func _web() -> bool:
	return OS.has_feature("web")

static func _read(k: String) -> String:
	if _web():
		var v = JavaScriptBridge.eval("localStorage.getItem(%s)" % JSON.stringify(k), true)
		return v if v is String else ""
	var p := file_dir.path_join(k + ".json")
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

static func _store(k: String, v: String) -> void:
	if _web():
		JavaScriptBridge.eval("localStorage.setItem(%s, %s)" % [JSON.stringify(k), JSON.stringify(v)], true)
		return
	var f := FileAccess.open(file_dir.path_join(k + ".json"), FileAccess.WRITE)
	if f: f.store_string(v)

# like 7.2's loadGame(): fall back through the backups rather than drop her at level 1
static func load_save() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--savedir="): file_dir = a.substr(10)
	for k in [KEY, KEY + "_bak", KEY + "_bak2"]:
		var raw := _read(k)
		if raw == "": continue
		var d = JSON.parse_string(raw)
		if d is Dictionary:
			data = d; loaded_from = k
			return true
	data = {}; loaded_from = ""
	return false

static func is_new() -> bool:
	return loaded_from == ""

# a brand-new save that 7.2 also loads as a fresh 7.0+ game
static func _defaults() -> void:
	for kv in [["v", 3], ["lvlv", 2], ["lvl", 1], ["xp", 0], ["need", 60], ["mh", 100], ["mm", 100], ["ms", 100],
			["lira", 0], ["kills", 0], ["weap", ["katana"]], ["wi", 0], ["dur", {"katana": 46}], ["next", 0], ["mid", null]]:
		if not data.has(kv[0]): data[kv[0]] = kv[1]

static func get_i(k: String, def := 0) -> int:
	var v = data.get(k, def)
	return int(v) if (v is int or v is float) else def

# write: same rolling backups as 7.2
static func write() -> void:
	_defaults()
	var js := JSON.stringify(data)
	var prev := _read(KEY)
	if prev != "" and prev != js:
		_store(KEY + "_bak2", _read(KEY + "_bak"))
		_store(KEY + "_bak", prev)
	_store(KEY, js)

# 7.2's gainXP(): XP grows with her level and INT, and every level-up pays +12 max HP, +3 mana,
# +2 stamina and one perk card. (Perk/gear XP bonuses and the focus buff aren't in the Godot build yet.)
static func xp_for(lvl: int) -> int:
	return int(round(35.0 * pow(float(maxi(1, lvl)), 2.03) + 40.0))

static func gain_xp(n: int) -> int:
	var lvl := maxi(1, get_i("lvl", 1))
	n = int(round(n * (1.0 + .1 * (lvl - 1)) * (1.0 + get_i("int") * .08)))
	var xp := get_i("xp") + n
	var need := xp_for(lvl)                 # 7.2 recomputes `need` from the curve when it loads
	var gained := 0
	while xp >= need:
		xp -= need; lvl += 1; need = xp_for(lvl); gained += 1
		data["mh"] = get_i("mh", 100) + 12; data["mm"] = get_i("mm", 100) + 3
		data["ms"] = get_i("ms", 100) + 2; data["pp"] = get_i("pp") + 1
	data["xp"] = xp; data["lvl"] = lvl; data["need"] = need
	return gained
