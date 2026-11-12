# 💾 SAVE & LOAD, ported from 7.2's #saveBox: save to a file, load one (button, or drag it onto the window),
# and the transfer code. The first time the Mac game starts with no save it opens as BRING YOUR SAVE, so
# Torii can carry over her browser-game progress (7.2: SAVE & LOAD → SAVE TO A FILE, then drag it in).
# A loaded save goes through SaveBridge (the one it replaces becomes the backup), then the game restarts on it.
class_name SaveUI
extends CanvasLayer

signal closed(fresh: bool)

var panel: PanelContainer
var title: Label
var info: RichTextLabel
var msg: RichTextLabel
var code_box: VBoxContainer
var code: TextEdit
var down_btn: Button
var up_btn: Button
var fresh_btn: Button
var close_btn: Button
var dlg: FileDialog
var welcome := false
var _busy := false

func _ready() -> void:
	layer = 8
	panel = PanelContainer.new(); panel.position = Vector2(170, 70); panel.size = Vector2(620, 0); panel.visible = false
	Bus.on("screen", func(_d): _place())      # widescreen (8.2): the panel stays on the real centre
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.07, .04, .13, .97); sb.border_color = Color("7bf7ff")
	sb.set_border_width_all(2); sb.set_corner_radius_all(14); sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb); add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); panel.add_child(v)
	title = Label.new(); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26); title.add_theme_color_override("font_color", Color("ffd66b")); v.add_child(title)
	info = _rich(v, 16)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 12); v.add_child(row)
	down_btn = _btn(row, "⬇ SAVE TO A FILE", _save_file)
	up_btn = _btn(row, "⬆ LOAD FROM A FILE", func(): dlg.popup_centered_ratio(.7))
	var drop := Label.new(); drop.text = "…or just drag a save file onto this window."; drop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop.add_theme_font_size_override("font_size", 13); drop.modulate = Color(1, 1, 1, .65); v.add_child(drop)
	_btn(v, "Transfer code (from another computer or browser) ▾", func(): code_box.visible = not code_box.visible)
	code_box = VBoxContainer.new(); code_box.visible = false; v.add_child(code_box)
	code = TextEdit.new(); code.custom_minimum_size = Vector2(560, 90); code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code.add_theme_font_size_override("font_size", 11); code_box.add_child(code)
	var crow := HBoxContainer.new(); crow.add_theme_constant_override("separation", 10); code_box.add_child(crow)
	_btn(crow, "COPY CODE", func(): DisplayServer.clipboard_set(code.text); msg.text = "📋 Copied!")
	_btn(crow, "RESTORE FROM CODE", func(): _apply(code.text, "the code"))
	fresh_btn = _btn(v, "▶ START A NEW GAME", func(): _close(true))
	close_btn = _btn(v, "CLOSE", func(): _close(false))
	msg = _rich(v, 15); msg.add_theme_color_override("default_color", Color("ffd66b"))
	dlg = FileDialog.new(); dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.json, *.torii ; Torii save"]); dlg.use_native_dialog = true
	dlg.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS); dlg.title = "Load a Torii save"
	dlg.file_selected.connect(func(path: String): _apply(FileAccess.get_file_as_string(path), path.get_file()))
	add_child(dlg)
	get_window().files_dropped.connect(_dropped)

func _rich(parent: Node, size: int) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.custom_minimum_size = Vector2(576, 0)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]: r.add_theme_font_size_override(k, size)
	parent.add_child(r); return r

func _btn(parent: Node, t: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = t; b.add_theme_font_size_override("font_size", 15); b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb); parent.add_child(b); return b

func open_panel(first := false) -> void:
	welcome = first
	title.text = "💾 BRING YOUR SAVE" if first else "💾 SAVE & LOAD"
	if first:
		info.text = ("Playing [b]TORİİ: NEO ANTALYA[/b] in the browser already? Bring your progress with you:\n" +
			"[b]1.[/b] In the browser game press [b]💾 SAVE & LOAD → ⬇ SAVE TO A FILE[/b].\n" +
			"[b]2.[/b] Drag that file onto this window, or press [b]⬆ LOAD FROM A FILE[/b] and pick it.\n" +
			"New here? Press [b]▶ START A NEW GAME[/b].")
	else:
		info.text = ("Your progress saves automatically on this computer. [b]Keep a real file too[/b]: it's the " +
			"easiest way to move your save to another computer, and a file never disappears.")
	down_btn.visible = not first; fresh_btn.visible = first; close_btn.visible = not first
	up_btn.visible = not OS.has_feature("web")          # the website has no file picker: drag a file in or use the code
	code.text = "" if first else SaveBridge.code(); code_box.visible = false; msg.text = ""
	panel.visible = true; Overlay.open("save"); _place()

# 4:3 size, on the real centre of a wider (or taller) window: at 960x720 = x 170, y 70 as before
func _place() -> void:
	panel.position = Vector2(170.0 + Screen.dx(), 70.0 + Screen.dy())

func _close(fresh: bool) -> void:
	if _busy: return
	panel.visible = false; Overlay.close("save")
	closed.emit(fresh)

func _unhandled_input(e: InputEvent) -> void:
	if panel.visible and not welcome and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close(false); get_viewport().set_input_as_handled()

# 7.2's downloadSave(): straight into Downloads, named after her level and the date
func _save_file() -> void:
	if _busy: return
	var raw := SaveBridge.export_text()
	if raw == "": msg.text = "Play a little first — there is nothing to save yet."; return
	var fname := _download(SaveBridge.file_name(), raw)
	if fname == "": msg.text = "❌ Could not write the file (%s)." % error_string(FileAccess.get_open_error()); return
	msg.text = "✅ Saved to your [b]Downloads[/b] folder as [i]%s[/i]. Keep that file — drag it back onto the game any time to restore." % fname

# a real file in Downloads (on the website: a browser download, like 7.2's Blob); returns its name, "" on failure
func _download(fname: String, raw: String) -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(raw.to_utf8_buffer(), fname, "application/json"); return fname
	var f := FileAccess.open(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(fname), FileAccess.WRITE)
	if not f: return ""
	f.store_string(raw); f.close(); return fname

# drop a save file anywhere on the window, any time (7.2 did the same)
func _dropped(files: PackedStringArray) -> void:
	if files.is_empty() or _busy: return
	if not panel.visible: open_panel(false)
	_apply(FileAccess.get_file_as_string(files[0]), files[0].get_file())

func _apply(raw: String, how: String) -> void:
	if _busy: return
	# check it first, then file the save it's about to replace in Downloads (a file never rolls away like
	# the backups do) so a wrong file can't cost her anything
	if SaveBridge.save_text(raw) == "":
		msg.text = "[color=#ff6b6b]❌ That does not look like a Torii save file.[/color]"; return
	var kept := ""
	if not SaveBridge.data.is_empty():
		var cur := SaveBridge.export_text()
		if cur != "": kept = _download(SaveBridge.file_name().replace(".json", "-before-loading.json"), cur)
	var lvl := SaveBridge.import_text(raw)
	if lvl <= 0:
		msg.text = "[color=#ff6b6b]❌ That does not look like a Torii save file.[/color]"; return
	_busy = true
	for b in panel.find_children("*", "Button", true, false): b.disabled = true
	msg.text = "✅ Loaded a level [b]%d[/b] save from %s.%s Starting it now…" % [lvl, how,
		(" The save it replaced is in Downloads as [i]%s[/i]." % kept) if kept != "" else ""]
	await get_tree().create_timer(1.8).timeout
	Overlay.reset()
	get_tree().reload_current_scene()
