# The one place systems talk to each other without editing each other's files.
#   Bus.emit_ev("enemy_died", {"enemy": e, "pos": p, "kind": k, "elite": b, "xp": n})
#   Bus.on("enemy_died", func(d): ...)
# Event names in use are listed in AI_HANDOFF.md ("Bus events"). Add new names freely; never rename one.
class_name Bus
extends RefCounted

static var _subs := {}       # name -> Array[Callable]

static func on(name: String, cb: Callable) -> void:
	if not _subs.has(name): _subs[name] = []
	_subs[name].append(cb)

static func off(name: String, cb: Callable) -> void:
	if _subs.has(name): _subs[name].erase(cb)

static func emit_ev(name: String, data := {}) -> void:
	if not _subs.has(name): return
	for cb in _subs[name].duplicate():
		if cb.is_valid(): cb.call(data)
		else: _subs[name].erase(cb)

static func reset() -> void: _subs.clear()
