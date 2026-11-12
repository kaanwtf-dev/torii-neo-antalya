# 🆕 The first scene (8.2, project.godot run/main_scene): lays an installed update over the bundled game, THEN starts
# main.tscn. It has to happen here, before any game script loads: a script that's already loaded keeps its old code.
# (The plan was a restart with `--main-pack`, but Godot's official release templates refuse every path override:
# "this Godot binary was compiled without support for path overrides". ProjectSettings.load_resource_pack(pck, true)
# is the supported way: the pack's files win over the bundled ones, its class_name list and UIDs are re-read.)
#
# The update (written by updater.gd): <updates>/current.json {ver, pck, size, sha256, engine, name} + <updates>/<pck>,
# <updates> = user://updates, or <--savedir>/updates in test runs. It's used when its ver is newer than the bundled
# game's and it was made with this engine; the pack's size and sha256 are checked every start. boot_try_<ver>
# counts starts on it; the game writes boot_ok_<ver> (and clears the count) once it's running (Updater._mark_ok: the
# title, 5 s, or an orderly quit). A damaged pack (size / sha256) is deleted and simply offered again at the next check.
# Two starts that never got there → the update is deleted and the bundled game starts; bad_<ver> (never offered again)
# only if that ver never got going at all (no boot_ok_<ver>). A newer bundled game (a new zip from Kaan) also drops it.
# Whenever an update newer than the bundled game is dropped, the save is copied to torii_save_from_<ver>.json first
# (the older bundled code is about to run on a save the update wrote).
#
# This script must not use ANY game class (Updater, SaveBridge, Bus...): naming one would load it from the bundled
# pack before the update is laid over it. Its helpers are copied in updater.gd for the same reason.
# Limits: project.godot settings (window, rendering, new autoloads) and the engine itself come from the app, not the
# pack, so a change there needs a new app (tools/export_mac.sh), like an engine change. So does a change to THIS file
# or scenes/boot.tscn: the app's own copy always runs (it is what lays the pack over). tools/publish_update.sh refuses
# a pack when any of those differ from the app build (tools/app_base.sha256 / app_base.engine, from tools/export_mac.sh).
extends Node

func _ready() -> void:
	var picked := _pick()
	if picked.size():
		if ProjectSettings.load_resource_pack(picked["path"], true):
			Engine.set_meta("torii_update", picked)
			_log("boot: playing %s from %s (try %d)" % [picked["name"], picked["pck"], picked["try"]])
		else:
			_drop("Godot couldn't open the pack", str(picked["ver"]))
	_go.call_deferred()

func _go() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if err == OK: return
	if Engine.has_meta("torii_update"):              # the update's main scene doesn't load: forget it, start again without it
		var u: Dictionary = Engine.get_meta("torii_update")
		_drop("its main scene didn't load (error %d)" % err, str(u["ver"]))
		var args := PackedStringArray(["--headless"] if DisplayServer.get_name() == "headless" else [])
		if OS.get_cmdline_user_args().size(): args.append("--"); args.append_array(OS.get_cmdline_user_args())
		OS.create_process(OS.get_executable_path(), args)
		get_tree().quit()      # (the one direct quit: nothing is built yet, no save loaded, no sound — main._quit() isn't there)
	else:
		push_error("main.tscn didn't load: %d" % err)

# the installed update to lay over the bundled game, or {} for none
static func _pick() -> Dictionary:
	if not enabled(): return {}
	var d := udir()
	var cp := d.path_join("current.json")
	if not FileAccess.file_exists(cp): return {}
	var cur = JSON.parse_string(FileAccess.get_file_as_string(cp))
	if not cur is Dictionary: _drop("current.json broken"); return {}
	var ver := ver_num(str(cur.get("ver", ""))); var pck := str(cur.get("pck", ""))
	if ver == "" or not safe_name(pck): _drop("current.json broken"); return {}
	var mine := ver_num(_bundled_name())
	if cmp(ver, mine) <= 0: _drop("this app (%s) is not older than the update (%s)" % [mine, ver]); return {}
	if cmp(str(cur.get("engine", "0")), engine_ver()) != 0: _drop("the update was made for engine %s, this app is %s" % [cur.get("engine", "?"), engine_ver()]); return {}
	var path := d.path_join(pck)
	if not FileAccess.file_exists(path): _drop("the pack is gone"); return {}
	if file_size(path) != int(cur.get("size", -1)): _drop("the pack has the wrong size"); return {}
	if FileAccess.get_sha256(path) != str(cur.get("sha256", "")).to_lower():     # ~25 MB: a blink
		_drop("the pack doesn't match its sha256 (it gets offered again)"); return {}
	var tp := d.path_join("boot_try_" + ver)
	var tries := int(FileAccess.get_file_as_string(tp)) if FileAccess.file_exists(tp) else 0
	if tries >= 2:
		var proven := FileAccess.file_exists(d.path_join("boot_ok_" + ver))    # it ran fine before: offer it again later
		_drop("it started %d times without getting going%s" % [tries, " (it did run before: offered again)" if proven else ""], "" if proven else ver)
		return {}
	write(tp, str(tries + 1))
	for f in DirAccess.get_files_at(d):           # packs of older updates (kept while that run was still playing from one)
		if f.ends_with(".pck") and f != pck: DirAccess.remove_absolute(d.path_join(f))
	return {"ver": ver, "pck": pck, "path": ProjectSettings.globalize_path(path), "name": str(cur.get("name", ver)), "try": tries + 1}

static func _bundled_name() -> String:
	var g = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/godot.json"))
	return str(g.get("ver", "")) if g is Dictionary else ""

# forget the installed update (bad_ver = it failed: never offer that version again)
static func _drop(why: String, bad_ver := "") -> void:
	var d := udir()
	_log("boot: not using the update: " + why)
	_keep_save(d)
	if bad_ver != "": write(d.path_join("bad_" + bad_ver), why)
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".pck") or f.ends_with(".part") or f == "current.json" or f.begins_with("boot_try_") or f.begins_with("boot_ok_"):
			DirAccess.remove_absolute(d.path_join(f))

# the older bundled game is about to run on a save written by a newer update: keep a copy of it as it is
# (torii_save_from_<ver>.json, next to the save; the torii_save keys themselves are untouched)
static func _keep_save(d: String) -> void:
	var cur = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("current.json"))) if FileAccess.file_exists(d.path_join("current.json")) else null
	if not cur is Dictionary: return
	var ver := ver_num(str(cur.get("ver", "")))
	if ver == "" or cmp(ver, ver_num(_bundled_name())) <= 0: return
	var sd := _arg("--savedir=")
	if sd == "": sd = "user://"
	var src := sd.path_join("torii_save.json")
	if not FileAccess.file_exists(src): return
	var txt := FileAccess.get_file_as_string(src)
	if txt != "" and write(sd.path_join("torii_save_from_%s.json" % ver), txt): _log("boot: kept the save as torii_save_from_%s.json" % ver)

# ---- helpers (the same ones are in updater.gd: see the top) ----
static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix): return a.substr(prefix.length())
	return ""

static func udir() -> String:
	var sd := _arg("--savedir=")
	return sd.path_join("updates") if sd != "" else "user://updates"

# the exported app only (dev runs: with --updateurl=, which also points the check at a local server)
static func enabled() -> bool:
	if OS.has_feature("web"): return false
	return OS.has_feature("template") or _arg("--updateurl=") != ""

static func ver_num(s: String) -> String:
	var re := RegEx.new(); re.compile("\\d+(?:\\.\\d+)*")
	var m := re.search(s)
	return m.get_string() if m else ""

static func cmp(a: String, b: String) -> int:
	var x := ver_num(a).split("."); var y := ver_num(b).split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() and x[i] != "" else 0
		var q := int(y[i]) if i < y.size() and y[i] != "" else 0
		if p != q: return -1 if p < q else 1
	return 0

static func engine_ver() -> String:
	var e := Engine.get_version_info()
	return "%d.%d.%d" % [e.major, e.minor, e.patch]

static func safe_name(pck: String) -> bool:
	return pck.ends_with(".pck") and not pck.contains("/") and not pck.contains("\\") and not pck.contains("..")

static func file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else -1

static func write(p: String, t: String) -> bool:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return false
	f.store_string(t); f.close()
	return true

static func _log(t: String) -> void:
	print("UPDATER ", t)
	var d := udir()
	if not DirAccess.dir_exists_absolute(d): return
	var p := d.path_join("updater.log")
	var old := FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	if old.length() > 20000: old = old.substr(old.length() - 10000)
	write(p, old + "%s  %s\n" % [Time.get_datetime_string_from_system(), t])
