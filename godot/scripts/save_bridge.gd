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
static var frozen := false          # an imported save is waiting for the restart: nothing may write over it

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
	frozen = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--savedir="): file_dir = a.substr(10)
	for k in [KEY, KEY + "_bak", KEY + "_bak2"]:
		var raw := _read(k)
		if raw == "": continue
		var d = _parse(raw)
		if d is Dictionary:
			data = d; loaded_from = k
			migrate()
			return true
	data = {}; loaded_from = ""
	return false

static func _parse(raw: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(raw) == OK else null

static var _md := {}
static func _missions_data() -> Dictionary:
	if _md.is_empty(): _md = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missions/missions.json"))
	return _md

# 7.2's applySave() repairs, done once when a save loads. A pre-7.0 save gets its one-time conversion
# BEFORE anything stamps lvlv:2 (otherwise the perk cards and stat growth it was owed are lost for
# good); `need` follows the curve and xp stays under it; her weapons are 7.2 ids, each with a
# durability, never an empty list; a save with no unit gets it from how far she got in the story.
static func migrate() -> void:
	if not data.has("lvl"): return
	var L := maxi(1, get_i("lvl", 1))
	var need := xp_for(L)
	if not data.get("lvlv"):
		var old_need := get_i("need")
		if old_need <= 0: old_need = int(round(60.0 * pow(float(L), 1.35)))
		var frac := clampf(float(get_i("xp")) / float(maxi(1, old_need)), 0.0, .99)
		data["xp"] = int(floor(frac * need))
		data["mh"] = get_i("mh", 100) + 2 * (L - 1); data["mm"] = get_i("mm", 100) + 3 * (L - 1)
		data["ms"] = 100 + 2 * (L - 1); data["pp"] = L - 1
		var msd: Dictionary = data["msd"] if data.get("msd") is Dictionary else {}
		for v in range(5, L + 1, 5):
			msd[str(v)] = 1
			if v > 30: data["mh"] = get_i("mh", 100) + 50
		data["msd"] = msd; data["lvlv"] = 2
	else:
		data["xp"] = clampi(get_i("xp"), 0, need - 1)
	data["need"] = need
	var known: Dictionary = _missions_data()["weapons"]
	var raw: Array = data["weap"] if data.get("weap") is Array else ["katana"]
	var dur: Dictionary = data["dur"] if data.get("dur") is Dictionary else {}
	# weapons this build doesn't know (a newer update's, when the updater fell back to the bundled game) wait in
	# weap_later / dur_later instead of being dropped, and come back as soon as a build knows them again
	var later: Array = data["weap_later"] if data.get("weap_later") is Array else []
	var dur_later: Dictionary = data["dur_later"] if data.get("dur_later") is Dictionary else {}
	for w in raw:
		if not known.has(str(w)) and not later.has(w):
			later.append(w)
			if dur.has(w): dur_later[w] = dur[w]
	var weap: Array = raw.filter(func(w): return known.has(str(w)))
	for w in later.duplicate():
		if known.has(str(w)):
			later.erase(w)
			if not weap.has(w):
				weap.append(w)
				if dur_later.has(w) and not dur.has(w): dur[w] = dur_later[w]
			dur_later.erase(w)
	for w in dur_later.keys(): if not later.has(w): dur_later.erase(w)
	if later.is_empty(): data.erase("weap_later"); data.erase("dur_later")
	else: data["weap_later"] = later; data["dur_later"] = dur_later
	if weap.is_empty(): weap = ["katana"]
	var nd := {}
	for w in weap:
		var v = dur.get(w)
		if v is int or v is float: nd[w] = v
		else:
			var dv = known[w].get("dur", 40)
			nd[w] = 9999 if (dv == null or str(dv) == "inf" or float(dv) > 9999) else dv
	data["weap"] = weap; data["dur"] = nd
	data["wi"] = clampi(get_i("wi"), 0, weap.size() - 1)
	if not (data.get("unit") is int or data.get("unit") is float) or get_i("unit") < 1:
		var ms: Array = _missions_data()["missions"]
		data["unit"] = int(ms[clampi(get_i("next"), 0, ms.size() - 1)].get("unit", 1)); data["ul"] = 0

# ---- 7.2's SAVE & LOAD: a save file is the raw save JSON, a transfer code is the same JSON in base64 ----
static func file_name() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "torii-save-lvl%d-%04d%02d%02d-%02d%02d.json" % [maxi(1, get_i("lvl", 1)), t.year, t.month, t.day, t.hour, t.minute]

static func export_text() -> String:
	if data.is_empty(): return ""
	write()
	return _read(KEY)

# the transfer code is made from a fresh save, so it carries everything up to this moment
static func code() -> String:
	var raw := export_text()
	return Marshalls.utf8_to_base64(raw) if raw != "" else ""

# the save JSON inside a file or a transfer code, or "" if it isn't a Torii save (7.2: typeof lvl === 'number')
static func save_text(raw: String) -> String:
	var txt := raw.strip_edges()
	if not txt.begins_with("{"):
		var b64 := RegEx.new(); b64.compile("^[A-Za-z0-9+/=\\s]+$")
		if b64.search(txt): txt = Marshalls.base64_to_utf8(txt).strip_edges()
	var d = _parse(txt)
	return txt if d is Dictionary and (d.get("lvl") is int or d.get("lvl") is float) else ""

# applySaveText(): accepts the file or a pasted code. Returns the save's level, 0 if it isn't a Torii save.
# The save it replaces rolls into the backups; after that nothing writes until the game restarts on it
# (the old one still in memory must never land back on top). SaveUI also files a copy in Downloads first.
static func import_text(raw: String) -> int:
	var txt := save_text(raw)
	if txt == "": return 0
	var d: Dictionary = _parse(txt)
	var prev := _read(KEY)
	if prev != "":
		_store(KEY + "_bak2", _read(KEY + "_bak"))
		_store(KEY + "_bak", prev)
	_store(KEY, txt)
	frozen = true
	return maxi(1, int(d["lvl"]))

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
	if frozen: return
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
