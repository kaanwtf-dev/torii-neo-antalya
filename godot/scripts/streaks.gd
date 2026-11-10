# 7.2's kill streaks (STREAK / streakTier / streakMult / bumpStreak / decayStreak): kills within 7 s of each
# other chain up. At 3 / 6 / 10 / 16 / 25 in a row a tier kicks in (ÜÇLÜ, ALTILI, ONLU, EFSANE,
# DURDURULAMAZ) with a banner, the fanfare and a little shake, and multiplies the kill's XP and lira
# (×1.25 / 1.5 / 1.9 / 2.4 / 3.0). Enemy._die() calls bump() first thing, like 7.2's killEnemy(), and puts
# the multiplier on the enemy_died event ("mult"); Items._on_kill pays the XP with it, the purse is already
# scaled. A streak of 3+ that runs out says "seri = streak". The ÖFKE perk reads Stats.streak_tier.
# The 7 s clock waits while a box is up (lesson, call, shop) and the streak drops to 0 when she faints
# or the scene reloads. Hud._draw_streak() shows the counter (from 2 in a row) above the weapon box.
class_name Streaks
extends Node

const TIERS := [
	{"n": 3, "m": 1.25, "t": "ÜÇLÜ! · TRIPLE", "c": "8ff2ff"},
	{"n": 6, "m": 1.5, "t": "ALTILI! · SIX STRONG", "c": "3dff9e"},
	{"n": 10, "m": 1.9, "t": "ONLU! · RAMPAGE", "c": "ffd66b"},
	{"n": 16, "m": 2.4, "t": "EFSANE! · LEGENDARY", "c": "ff5fa2"},
	{"n": 25, "m": 3.0, "t": "DURDURULAMAZ! · UNSTOPPABLE", "c": "b06bff"},
]
const KEEP := 7.0                   # seconds to the next kill before it ends

static var me: Streaks
var player
var hud: Hud
var count := 0                      # 7.2 S.streak
var left := 0.0                     # seconds until it ends (7.2 S.streakT - now())
var shown := 0                      # 7.2 S.streakShown: the tier already announced

func setup(p, h: Hud) -> void:
	me = self; player = p; hud = h
	_reset(false)                   # a reload starts at 0 (before Items pushes the stats into her)
	Bus.on("faint", func(_d): _reset(true))

# the tier she's on ({} below 3) and its 1-based index
func tier() -> Dictionary:
	var cur := {}
	for s in TIERS:
		if count >= int(s["n"]): cur = s
	return cur

func tier_index() -> int:
	var t := tier()
	return TIERS.find(t) + 1 if not t.is_empty() else 0

func mult() -> float:
	var t := tier()
	return float(t["m"]) if not t.is_empty() else 1.0

# one more kill: returns the multiplier for this kill
func bump() -> float:
	count += 1; left = KEEP
	var t := tier()
	if not t.is_empty() and shown != int(t["n"]):
		shown = int(t["n"])
		call_deferred("_announce", t, count)   # after the kill's own banners (epic / rare / boss / level up)
		Bus.emit_ev("sfx", {"name": "fanfare"})
		if Fx.me: Fx.me.shake(.2)
	_sync_tier()
	return mult()

# the tier banner, unless the same kill already put one up: then it comes as a toast so both get read
func _announce(t: Dictionary, n: int) -> void:
	if not is_instance_valid(hud): return
	if hud._ban_frame == Engine.get_process_frames():
		hud.toast("🔥 [b]%s[/b] · ×%.2f XP and lira · %d in a row" % [t["t"], t["m"], n], 4.0)
	else: hud.banner("🔥 %s\n[font_size=16]×%.2f XP and lira · %d in a row[/font_size]" % [t["t"], t["m"], n], 2.2)

func _process(dt: float) -> void:
	if count <= 0 or Overlay.any(): return
	left -= dt
	if left > 0: return
	if count >= 3 and hud: hud.toast("🔥 Streak ended at [b]%d[/b]. [i]seri[/i] = streak." % count, 3.0)
	_reset(true)

func _reset(push: bool) -> void:
	count = 0; left = 0.0; shown = 0
	if push: _sync_tier()
	else: Stats.streak_tier = 0

# ÖFKE: +6% damage per tier — her damage mods only change when the tier does
func _sync_tier() -> void:
	var ti := tier_index()
	if ti == Stats.streak_tier: return
	Stats.streak_tier = ti
	if Stats.pk("ofke") > 0 and is_instance_valid(player): Stats.apply(player)
