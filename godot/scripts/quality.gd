# The automatic quality governor (7.2 autoGfx). If the game really can't keep up while she plays (smoothed fps
# under ~34 for ~5 s), it steps graphics down ONE notch and says so in a toast: GRAFİK toward PS1 (the cheapest
# 3D pixels), and once that's PS1, the view distance (camera far + fog) a notch shorter. Never steps up by itself,
# waits 30 s of play between steps, takes at most 3 steps a session, and never touches anything again once she
# picked GRAFİK or VIEW herself in the pause menu (save gManual, like 7.2's GFX.manual).
# Measures only during real play: not on the title, the intro, menus, overlays, cutscenes, while she's down,
# with the window in the background, or in the first 8 s after load (2 s after any of those).
# Owns VIEW (save gView, new: 0 FAR 400 / 1 MID 300 / 2 NEAR 210 = 7.2's view distances) and cycle_view() for
# the pause menu. GRAFİK itself stays Menus' (gGfx); the fog floor that hides the far plane is SkyCycle.fog_min.
# Dev: --fakefps=N measures N fps instead of the real thing; --fakefps / --fps print QUALITY lines.
class_name Quality
extends Node

static var me: Quality
static var steps := 0                  # steps taken this session (a save-file reload keeps counting)
const LOW_FPS := 34.0
const LOW_FOR := 5.0
const WARMUP := 8.0
const REWARM := 2.0
const COOL := 30.0
const MAX_STEPS := 3
const WIN := .5                        # one reading per half second: the median frame (ignores single hitches)
const VIEW_FAR := [400.0, 300.0, 210.0]
const VIEW_NAME := ["FAR", "MID", "NEAR"]

var torii: Node3D
var hud: CanvasLayer
var fps := 60.0                        # the smoothed reading
var _fake := 0.0
var _log := false
var _warm := WARMUP
var _cool := 0.0
var _low_t := 0.0
var _win: Array[float] = []
var _win_t := 0.0
var _last_us := 0

func setup(p: Node3D, h: CanvasLayer) -> void:
	me = self; torii = p; hud = h; name = "Quality"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fakefps="): _fake = maxf(1.0, float(a.substr(10)))
		_log = _log or a == "--fps"
	_log = _log or _fake > 0.0
	apply_view()

# ---------------------------------------------------------------- VIEW (save gView)
func view() -> int: return clampi(SaveBridge.get_i("gView"), 0, 2)
func view_label() -> String: return "🔭 VIEW: " + VIEW_NAME[view()]

func cycle_view() -> void:
	SaveBridge.data["gView"] = (view() + 1) % 3
	mark_manual()
	apply_view()

# she chose her settings herself: the governor keeps its hands off from now on
func mark_manual() -> void: SaveBridge.data["gManual"] = true

func apply_view() -> void:
	var far: float = VIEW_FAR[view()]
	var cam = torii.get("cam") if torii else null
	if cam is Camera3D: (cam as Camera3D).far = far
	if SkyCycle.me:
		# FAR keeps the sky's own fog; shorter views fog over (~95%) before the far plane so nothing pops
		SkyCycle.me.fog_min = 0.0 if view() == 0 else 3.0 / (far * .86)
		SkyCycle.me._tick(true)

# ---------------------------------------------------------------- the governor
func _playing() -> bool:
	if SaveBridge.data.get("gManual", false) == true or steps >= MAX_STEPS: return false
	if get_tree().paused or Overlay.any() or Cutscene.busy() or is_instance_valid(Intro.me): return false
	if Menus.me and Menus.me.title_up: return false
	if torii == null or torii.get("dead"): return false
	var cam = torii.get("cam")
	if not (cam is Camera3D and (cam as Camera3D).current): return false
	if _fake <= 0.0:                   # a window in the background gets throttled by macOS: that's not her Mac being slow
		if not DisplayServer.window_is_focused() or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: return false
	return true

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var fdt := float(now - _last_us) / 1e6 if _last_us > 0 else 0.0
	_last_us = now
	if not _playing():
		_warm = maxf(_warm, REWARM); _low_t = 0.0; _win.clear(); _win_t = 0.0
		return
	if fdt <= 0.0 or fdt > .25: return                 # a load / shader hitch, or the first frame back
	if _warm > 0.0: _warm -= fdt; return
	if _cool > 0.0: _cool -= fdt; return
	_win.append(1.0 / _fake if _fake > 0.0 else fdt); _win_t += fdt
	if _win_t < WIN: return
	var s := _win.duplicate(); s.sort()
	var med: float = s[s.size() / 2]
	var span := _win_t
	_win.clear(); _win_t = 0.0
	fps = lerpf(fps, 1.0 / med, .4)
	_low_t = _low_t + span if fps < LOW_FPS else 0.0
	if _log: print("QUALITY fps %.1f low %.1fs gfx %d view %d steps %d" % [fps, _low_t, SaveBridge.get_i("gGfx"), view(), steps])
	if _low_t >= LOW_FOR: _step()

func _step() -> void:
	_low_t = 0.0; _cool = COOL
	var gfx := clampi(SaveBridge.get_i("gGfx"), 0, 2)
	var what := ""
	if gfx > 0:
		SaveBridge.data["gGfx"] = gfx - 1
		if Menus.me: Menus.me._apply_gfx()
		what = "GRAFİK is now [b]%s[/b]. Want it back? [b]P[/b] → GRAFİK." % ["PS1", "SHARP", "SMOOTH"][gfx - 1]
	elif view() < 2:
		SaveBridge.data["gView"] = view() + 1
		apply_view()
		what = "you see less far now ([b]VIEW: %s[/b]). Want it back? [b]P[/b] → VIEW." % VIEW_NAME[view()]
	else:
		steps = MAX_STEPS; return                       # already as low as it goes: stop watching
	steps += 1
	SaveBridge.write()
	if _log: print("QUALITY step ", steps, ": gfx ", SaveBridge.get_i("gGfx"), " view ", view())
	if hud and hud.has_method("toast"):
		hud.toast("⚙️ Ayarlar düşürüldü [i](settings lowered)[/i] — it was running slow (~%d fps), so %s" % [roundi(fps), what], 8.0)
