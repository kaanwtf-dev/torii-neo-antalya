# Anything that takes over the screen is an overlay: a lesson or quiz, Kaan's call, someone talking, a
# choice, the save screens. While one is up the fight stops, like 7.2's main loop and damagePlayer():
# monsters and their shots freeze, nothing can hurt her and her own controls wait. The mouse is freed for
# clicking and captured again when the last overlay closes.
class_name Overlay
extends RefCounted

static var _open := {}
static var _closed_at := -10

static func open(name: String) -> void:
	_open[name] = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func close(name: String) -> void:
	if not _open.has(name): return
	_open.erase(name)
	_closed_at = Engine.get_physics_frames()
	if _open.is_empty(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

static func any() -> bool: return not _open.is_empty()
static func count() -> int: return _open.size()
static func is_open(name: String) -> bool: return _open.has(name)

# the key that closed a box (E, Space) mustn't also get her on the bike or make her jump
static func just_closed() -> bool: return Engine.get_physics_frames() - _closed_at < 3

static func reset() -> void:
	_open = {}; _closed_at = -10
