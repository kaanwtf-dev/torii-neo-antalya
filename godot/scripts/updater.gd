# 🆕 The in-game updater (8.2): after this version Torii never installs a zip again (unless the ENGINE changes).
#
# Kaan publishes a new version as a GitHub Release of kaanwtf-dev/torii-neo-antalya (tools/publish_update.sh):
#   version.json   {"ver": "8.3", "name": "ALPHA 8.3 · ...", "pck": "torii-8.3.pck", "size": bytes, "sha256": hex,
#                   "engine": "4.7.2", "notes": "one short line for Torii"}   — always at releases/latest/download/
#   torii-8.3.pck  the whole game as one Godot pack (godot --export-pack), at releases/download/v8.3/
# The app checks once while the title shows. Newer ver + same engine → a small panel: UPDATE / LATER. UPDATE
# downloads into user://updates/<pck>.part, checks size + sha256, renames it, writes user://updates/current.json,
# saves, and starts the app again (main._quit() → spawn). A different engine → one line: ask Kaan for a new app.
# Every start, boot.gd (the first scene) lays an installed update newer than the bundled game over it before any
# game script loads (ProjectSettings.load_resource_pack: Godot's release templates refuse `--main-pack`).
#
# Never a brick: a partial or bad download is never named in current.json; boot.gd checks the pack's size and
# sha256 every start; boot_try_<ver> counts starts on it and this node writes boot_ok_<ver>
# once the game is going (title up, 5 s of running, or an orderly quit). Two starts without that → boot.gd deletes the
# update (a ver that never got going is never offered again; one that did is offered again) and the bundled game starts. No internet, no release yet (404), a timeout, a
# broken version.json: nothing happens, silently.
#
# Only the exported app (OS.has_feature("template")) updates. Dev runs only with --updateurl=http://127.0.0.1:PORT/
# (base URL for version.json AND the pack). With --savedir=DIR the update files live in DIR/updates, so a test never
# touches the real user:// folder. Dev flags: --updatepress (press UPDATE when the panel shows), --updateshot=PATH
# (screenshot the panel, then quit), --updatequit=SEC (quit SEC s after the game got going). Log: <updates>/updater.log.
class_name Updater
extends CanvasLayer

const LATEST := "https://github.com/kaanwtf-dev/torii-neo-antalya/releases/latest/download/"
const RELEASE := "https://github.com/kaanwtf-dev/torii-neo-antalya/releases/download/v%s/%s"
const PINK := Color("ff5fa2")
const CYAN := Color("7bf7ff")
const GOLD := Color("ffd66b")
const PURP := Color("b06bff")

static var me: Updater
static var relaunch := PackedStringArray()    # set → main._quit() starts the app again with these args, last thing

var hud: CanvasLayer
var _info := {}              # the version.json on offer
var _http: HTTPRequest
var _dl: HTTPRequest
var _dl_last := 0
var _dl_still := 0.0
var _hash_th: Thread
var _checked := false
var _ok_marked := false
var _alive := 0.0
var _quit_after := -1.0
var _bg: Control             # the panel (dim backdrop + card)
var _body: VBoxContainer     # the card's changing part (buttons / progress / message)
var _bar: ProgressBar
var _bar_txt: Label
var _toast: PanelContainer
var _toast_t := 0.0

# ---------------------------------------------------------------- where / which version

static func _uargs() -> PackedStringArray: return OS.get_cmdline_user_args()

static func _arg(prefix: String) -> String:
	for a in _uargs():
		if a.begins_with(prefix): return a.substr(prefix.length())
	return ""

static func udir() -> String:
	var sd := _arg("--savedir=")
	return sd.path_join("updates") if sd != "" else "user://updates"

static func _base() -> String:
	var u := _arg("--updateurl=")
	if u != "" and not u.ends_with("/"): u += "/"
	return u

static func enabled() -> bool:
	if OS.has_feature("web"): return false
	return OS.has_feature("template") or _base() != ""

# this run plays an installed update (boot.gd laid it over the bundled game)
static func from_pack() -> bool: return Engine.has_meta("torii_update")

# the number in a version: "ALPHA 8.1 · SERİ" → "8.1"
static func ver_num(s: String) -> String:
	var re := RegEx.new(); re.compile("\\d+(?:\\.\\d+)*")
	var m := re.search(s)
	return m.get_string() if m else ""

# numeric, part by part: 8.2 < 8.10, 8.2 == 8.2.0
static func cmp(a: String, b: String) -> int:
	var x := ver_num(a).split("."); var y := ver_num(b).split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() and x[i] != "" else 0
		var q := int(y[i]) if i < y.size() and y[i] != "" else 0
		if p != q: return -1 if p < q else 1
	return 0

static var _game_name := ""
static func game_name() -> String:
	if _game_name == "":
		var g = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/godot.json"))
		_game_name = str(g.get("ver", "")) if g is Dictionary else ""
	return _game_name

static func game_ver() -> String: return ver_num(game_name())

static func engine_ver() -> String:
	var e := Engine.get_version_info()
	return "%d.%d.%d" % [e.major, e.minor, e.patch]

static func _same_engine(s: String) -> bool:
	return ver_num(s) != "" and cmp(s, engine_ver()) == 0

static func _log(t: String) -> void:
	print("UPDATER ", t)
	var d := udir()
	if not DirAccess.dir_exists_absolute(d): return
	var p := d.path_join("updater.log")
	var old := FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	if old.length() > 20000: old = old.substr(old.length() - 10000)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f: f.store_string(old + "%s  %s\n" % [Time.get_datetime_string_from_system(), t])

static func _write(p: String, t: String) -> bool:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return false
	f.store_string(t); f.close()
	return true

static func _safe_name(pck: String) -> bool:
	return pck.ends_with(".pck") and not pck.contains("/") and not pck.contains("\\") and not pck.contains("..")

static func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else -1

# the args for starting the app again: the same user args (so --savedir & co carry over in tests)
static func _args_for() -> PackedStringArray:
	var a := PackedStringArray()
	if DisplayServer.get_name() == "headless": a.append("--headless")
	var user := PackedStringArray()
	for u in _uargs():
		if not (u == "--updatepress" or u.begins_with("--updateshot=")): user.append(u)
	if user.size(): a.append("--"); a.append_array(user)
	return a

static func spawn(args: PackedStringArray) -> int:
	var pid := OS.create_process(OS.get_executable_path(), args)
	_log("restart %s %s → pid %d" % [OS.get_executable_path(), " ".join(args), pid])
	return pid

# ---------------------------------------------------------------- the node (made in main after Menus)

func setup(h: CanvasLayer) -> void:
	me = self; hud = h
	name = "Updater"; layer = 46; process_mode = Node.PROCESS_MODE_ALWAYS
	if from_pack() or _base() != "": _log("running %s (engine %s)%s" % [game_name(), engine_ver(), " from the update pack" if from_pack() else ""])
	var q := _arg("--updatequit=")
	if q != "": _quit_after = float(q)
	if enabled() and DirAccess.dir_exists_absolute(udir()):    # a download cut off by quitting leaves a .part behind
		for f in DirAccess.get_files_at(udir()):
			if f.ends_with(".part"): DirAccess.remove_absolute(udir().path_join(f))

func _process(dt: float) -> void:
	_alive += dt
	var title := Menus.me != null and Menus.me.title_up
	if not _ok_marked and (title or _alive > 5.0): _mark_ok("the title" if title else "5 s")
	if not _checked and title and enabled():
		_checked = true; _check()
	if _quit_after >= 0.0 and _ok_marked:
		_quit_after -= dt
		if _quit_after < 0.0 and relaunch.is_empty() and _dl == null and _hash_th == null:
			_log("--updatequit: quitting"); get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	if _dl: _dl_tick(dt)
	if _hash_th and not _hash_th.is_alive(): _hashed(_hash_th.wait_to_finish()); _hash_th = null
	if _toast:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0: _toast.queue_free(); _toast = null

# the update got going (the title is up, or 5 s of running: the world is built and drawing): stop counting tries
func _mark_ok(how: String) -> void:
	if _ok_marked: return
	_ok_marked = true
	if not from_pack(): return
	var ver := str((Engine.get_meta("torii_update") as Dictionary).get("ver", game_ver())); var d := udir()
	_write(d.path_join("boot_ok_" + ver), Time.get_datetime_string_from_system())
	DirAccess.remove_absolute(d.path_join("boot_try_" + ver))
	_log("boot ok: GAME_VER %s reached %s · save level %d, %d words" % [Menus.me.GAME_VER if Menus.me else game_name(), how, SaveBridge.get_i("lvl", 1), (SaveBridge.data.get("words", []) as Array).size() if SaveBridge.data.get("words") is Array else 0])

# main._quit(): an orderly quit (close button, Cmd+Q, even on the VHS intro) means this pack runs fine
func mark_ok_on_quit() -> void: _mark_ok("an orderly quit")

# ---------------------------------------------------------------- the check (once, while the title shows)

func _check() -> void:
	_http = HTTPRequest.new(); _http.timeout = 12.0; _http.max_redirects = 8
	add_child(_http)
	_http.request_completed.connect(_checked_in)
	var url := (_base() if _base() != "" else LATEST) + "version.json"
	if _http.request(url, ["Cache-Control: no-cache"]) != OK: _log("couldn't start the check"); _http.queue_free(); _http = null

func _checked_in(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free(); _http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_log("check: nothing (result %d, http %d)" % [result, code]); return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if not (j is Dictionary and ver_num(str(j.get("ver", ""))) != "" and _safe_name(str(j.get("pck", ""))) and int(j.get("size", 0)) > 0 and str(j.get("sha256", "")).length() == 64):
		_log("check: version.json doesn't look right"); return
	var ver := ver_num(str(j["ver"]))
	if cmp(ver, game_ver()) <= 0: _log("check: up to date (%s, online %s)" % [game_ver(), ver]); return
	if FileAccess.file_exists(udir().path_join("bad_" + ver)): _log("check: %s failed to start before, not offered again" % ver); return
	var nm := str(j.get("name", "ALPHA " + ver))
	if not _same_engine(str(j.get("engine", ""))):
		_log("check: %s needs engine %s (this app %s)" % [ver, j.get("engine", "?"), engine_ver()])
		_show_toast("🆕 [b]%s[/b] is out, but it needs a new app — ask Kaan 💌" % nm)
		return
	if not (Menus.me and Menus.me.title_up): _log("check: %s found, but she already left the title" % ver); return
	_info = j; _info["ver"] = ver; _info["name"] = nm
	_log("check: offering %s" % ver)
	_open_panel()

# ---------------------------------------------------------------- the panel

func _open_panel() -> void:
	Overlay.open("update")
	_bg = ColorRect.new(); (_bg as ColorRect).color = Color(.02, .01, .05, .55)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT); _bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(cc)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, .97); sb.border_color = PINK
	sb.set_border_width_all(2); sb.set_corner_radius_all(14); sb.set_content_margin_all(20)
	sb.shadow_color = Color(PINK, .25); sb.shadow_size = 14
	card.add_theme_stylebox_override("panel", sb); cc.add_child(card)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); card.add_child(v)
	_rich(v, "[center][b]🆕 %s is here![/b][/center]" % _info["name"], 22, PINK)
	var notes := str(_info.get("notes", "")).strip_edges()
	if notes != "": _rich(v, "[center]%s[/center]" % notes, 16, Color("e8e4f8"))
	_rich(v, "[center][color=#9a94a8]%.1f MB · your save stays safe 💾 · the game restarts by itself[/color][/center]" % (float(_info["size"]) / 1048576.0), 13, Color.WHITE)
	_body = VBoxContainer.new(); _body.add_theme_constant_override("separation", 10); v.add_child(_body)
	UiScale.apply(card, 1.5)
	_choice()
	Audio.sfx("menu_select")
	var shot := _arg("--updateshot=")
	if shot != "": _shot(shot, true)
	elif "--updatepress" in _uargs(): get_tree().create_timer(.6, true).timeout.connect(_update)

func _clear_body() -> void:
	for c in _body.get_children(): _body.remove_child(c); c.queue_free()
	_bar = null; _bar_txt = null

func _choice() -> void:
	_clear_body()
	var r := _row()
	var up := _btn(r, "⬇ GÜNCELLE · UPDATE", _update, PINK, false)
	_btn(r, "SONRA · LATER", _later, CYAN, true)
	_rich(_body, "[center][color=#8a7fb0]ENTER = update · ESC = later · ←/→ choose[/color][/center]", 12, Color.WHITE)
	up.grab_focus()

func _later() -> void:
	_log("later")
	_close_panel()

func _close_panel() -> void:
	if _bg: _bg.queue_free(); _bg = null; _body = null
	_bar = null; _bar_txt = null
	Overlay.close("update")

func _input(e: InputEvent) -> void:
	if _bg == null or not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if k == KEY_ESCAPE:
		if _dl: _cancel()
		elif _hash_th == null and relaunch.is_empty(): _later()
		get_viewport().set_input_as_handled()
	elif not (k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_UP, KEY_DOWN]):
		get_viewport().set_input_as_handled()       # the title under the panel gets nothing (the buttons take the rest)

# ---------------------------------------------------------------- download → check → install → restart

func _part() -> String: return udir().path_join(str(_info["pck"]) + ".part")

func _update() -> void:
	if _dl or _hash_th or not relaunch.is_empty() or _body == null: return
	_progress_ui()
	var d := udir()
	DirAccess.make_dir_recursive_absolute(d)
	if FileAccess.file_exists(_part()): DirAccess.remove_absolute(_part())
	# no thread: a threaded HTTPRequest blocks in recv() on a dead link, and cancel_request() then joins that thread
	# on the main thread (the whole game freezes). Polled once a frame, non-blocking, up to 1 MB a frame.
	_dl = HTTPRequest.new(); _dl.use_threads = false; _dl.download_chunk_size = 1 << 20
	_dl.max_redirects = 8; _dl.download_file = _part()
	_dl.body_size_limit = int(_info["size"]) + 1048576
	add_child(_dl)
	_dl.request_completed.connect(_downloaded)
	var url: String = (_base() + str(_info["pck"])) if _base() != "" else RELEASE % [_info["ver"], _info["pck"]]
	_dl_last = 0; _dl_still = 0.0
	_log("download " + url)
	if _dl.request(url) != OK: _dl.queue_free(); _dl = null; _failed("couldn't start the download")
	else: _progress(0)

func _progress_ui() -> void:
	_clear_body()
	_bar = ProgressBar.new(); _bar.custom_minimum_size = Vector2(460, 22); _bar.show_percentage = false
	_bar.min_value = 0; _bar.max_value = 1.0; _bar.step = 0.0
	var bgs := StyleBoxFlat.new(); bgs.bg_color = Color(.12, .07, .2, .95); bgs.border_color = PURP; bgs.set_border_width_all(2); bgs.set_corner_radius_all(9)
	var fgs := StyleBoxFlat.new(); fgs.bg_color = PINK; fgs.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("background", bgs); _bar.add_theme_stylebox_override("fill", fgs)
	var cc := CenterContainer.new(); cc.add_child(_bar); _body.add_child(cc)
	_bar_txt = Label.new(); _bar_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_txt.add_theme_font_size_override("font_size", UiScale.px(15, 1.5)); _bar_txt.add_theme_color_override("font_color", GOLD)
	_body.add_child(_bar_txt)
	_btn(_row(), "✕ İPTAL · CANCEL", _cancel, CYAN, true)

func _dl_tick(dt: float) -> void:
	var got := _dl.get_downloaded_bytes()
	if got != _dl_last: _dl_last = got; _dl_still = 0.0
	else: _dl_still += dt
	_progress(got)
	if _dl_still > 30.0:                         # nothing for 30 s: the connection died
		_dl.cancel_request(); _dl.queue_free(); _dl = null
		_failed("the download stopped (no internet?)")

func _progress(got: int) -> void:
	if _bar == null: return
	var total := float(_info["size"])
	var f := clampf(float(got) / maxf(total, 1.0), 0.0, 1.0)
	_bar.value = f
	_bar_txt.text = "İNDİRİLİYOR · DOWNLOADING   %.1f / %.1f MB · %d%%" % [got / 1048576.0, total / 1048576.0, roundi(f * 100.0)]

func _cancel() -> void:
	if _dl: _dl.cancel_request(); _dl.queue_free(); _dl = null
	if FileAccess.file_exists(_part()): DirAccess.remove_absolute(_part())
	_log("download cancelled")
	_close_panel()

func _downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _dl == null: return
	_dl.queue_free(); _dl = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failed("download failed (result %d, http %d)" % [result, code]); return
	_progress(int(_info["size"]))
	if _size(_part()) != int(_info["size"]):
		_failed("wrong size: %d, expected %d" % [_size(_part()), int(_info["size"])]); return
	_bar_txt.text = "KONTROL · CHECKING…"
	var part := _part()
	_hash_th = Thread.new()
	_hash_th.start(func(): return FileAccess.get_sha256(part))

func _hashed(sha) -> void:
	if str(sha) != str(_info["sha256"]).to_lower():
		_failed("sha256 doesn't match"); return
	var d := udir(); var pck := str(_info["pck"]); var ver := str(_info["ver"])
	var final := d.path_join(pck)
	if FileAccess.file_exists(final): DirAccess.remove_absolute(final)
	if DirAccess.rename_absolute(_part(), final) != OK: _failed("couldn't move the pack into place"); return
	# older packs, half downloads and their boot marks go — but never the pack this run is playing from (Godot reads
	# it again on every resource load): boot.gd deletes it at the next start, before anything mounts it
	var running := str((Engine.get_meta("torii_update") as Dictionary).get("pck", "")) if from_pack() else ""
	for f in DirAccess.get_files_at(d):
		if (f.ends_with(".pck") and f != pck and f != running) or f.ends_with(".part") or ((f.begins_with("boot_try_") or f.begins_with("boot_ok_")) and not f.ends_with("_" + ver)):
			DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d.path_join("boot_ok_" + ver))
	var cur := {"ver": ver, "pck": pck, "size": int(_info["size"]), "sha256": str(_info["sha256"]).to_lower(), "engine": str(_info.get("engine", engine_ver())), "name": str(_info["name"])}
	if not _write(d.path_join("current.json"), JSON.stringify(cur, "  ")): _failed("couldn't write current.json"); return
	_log("installed %s (%d bytes, sha256 ok)" % [pck, int(_info["size"])])
	DirAccess.remove_absolute(d.path_join("boot_try_" + ver))     # boot.gd counts the starts on it from 0
	if not SaveBridge.data.is_empty(): SaveBridge.write()
	_clear_body()
	_rich(_body, "[center][b]✅ HAZIR · READY![/b]\nRestarting into %s… see you in a second 💖[/center]" % _info["name"], 17, GOLD)
	Audio.sfx("menu_select")
	relaunch = _args_for()
	await get_tree().create_timer(1.4, true).timeout
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)   # main._quit(): saves, then starts us again

func _failed(why: String) -> void:
	_log("download: " + why)
	if FileAccess.file_exists(_part()): DirAccess.remove_absolute(_part())
	if _body == null: return
	_clear_body()
	_rich(_body, "[center]😿 The download didn't work — maybe the internet is away.\nYour game is fine. Try again in a bit![/center]", 16, Color("e8e4f8"))
	var r := _row()
	var again := _btn(r, "⟳ TEKRAR · RETRY", _update, PINK, false)
	_btn(r, "SONRA · LATER", _later, CYAN, true)
	again.grab_focus()

# ---------------------------------------------------------------- the engine-changed line

func _show_toast(t: String) -> void:
	_toast = PanelContainer.new(); _toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(20 / 255.0, 8 / 255.0, 38 / 255.0, .92); sb.border_color = PINK
	sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("panel", sb)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_TOP_WIDE); cc.offset_top = 24; cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc); cc.add_child(_toast)
	var r := _rich(_toast, "[center]%s[/center]" % t.replace("[b]", "[b][color=#7bf7ff]").replace("[/b]", "[/color][/b]"), 16, Color("e8e4f8"))
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiScale.apply(_toast, 1.5)
	_toast_t = 9.0
	_toast.tree_exited.connect(cc.queue_free)
	if _arg("--updateshot=") != "": _shot(_arg("--updateshot="), false)

# ---------------------------------------------------------------- little UI kit (Menus' neon cards)

func _rich(parent: Node, t: String, size: int, col: Color) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.custom_minimum_size = Vector2(560, 0)
	for k in UiScale.KEYS_RICH: r.add_theme_font_size_override(k, size)
	r.add_theme_color_override("default_color", col)
	r.text = UiScale.bb(t)
	parent.add_child(r)
	if parent == _body: UiScale.apply(r, 1.5)
	return r

func _row() -> HBoxContainer:
	var h := HBoxContainer.new(); h.alignment = BoxContainer.ALIGNMENT_CENTER; h.add_theme_constant_override("separation", 14)
	_body.add_child(h)
	return h

func _btn(parent: Node, t: String, cb: Callable, col: Color, alt: bool) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", UiScale.px(18, 1.5)); b.custom_minimum_size = Vector2(210, 0)
	var n := StyleBoxFlat.new(); n.bg_color = Color(.12, .07, .2, .95) if alt else Color(col, .9)
	n.border_color = col; n.set_border_width_all(2); n.set_corner_radius_all(9); n.set_content_margin_all(9)
	var hv := n.duplicate() as StyleBoxFlat; hv.bg_color = Color(col, .35) if alt else Color(col, 1)
	var fo := hv.duplicate() as StyleBoxFlat; fo.border_color = Color.WHITE; fo.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", hv); b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new()); b.add_theme_stylebox_override("hover_pressed", hv)
	b.focus_entered.connect(func(): b.add_theme_stylebox_override("normal", fo))
	b.focus_exited.connect(func(): b.add_theme_stylebox_override("normal", n))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.add_theme_color_override("font_color", col if alt else Color("12081e"))
	b.add_theme_color_override("font_focus_color", Color.WHITE if alt else Color("12081e"))
	b.add_theme_color_override("font_hover_color", Color.WHITE if alt else Color("12081e"))
	b.pressed.connect(func():
		Audio.sfx("menu_select")
		cb.call())
	parent.add_child(b)
	return b

# dev: --updateshot=PATH — the panel (PATH), the same panel downloading (PATH_dl.png); or the engine line (PATH)
func _shot(path: String, panel: bool) -> void:
	await _grab(path)
	if panel:
		_progress_ui(); _progress(int(float(_info["size"]) * .42))
		await _grab(path.get_basename() + "_dl.png")
		_close_panel()
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)

func _grab(path: String) -> void:
	for _i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path); print("UPDATESHOT ", path, " ", img.get_size())

func _exit_tree() -> void:
	if _hash_th: _hash_th.wait_to_finish(); _hash_th = null
	if me == self: me = null
