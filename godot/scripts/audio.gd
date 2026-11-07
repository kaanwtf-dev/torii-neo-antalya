# Every sound in the game, synthesised from scratch at startup like 7.2 did it live in WebAudio
# (audioBoot / tone / nz / fx, 7.2 lines 4873-4943): no sound files. A background thread renders each
# recipe into a crunchy 22 kHz AudioStreamWAV, then:
#   Audio.me.play(name, pos := null, vol := 1.0)   2D when pos is null, 3D (panned, fades with distance) at a Vector3
#   Audio.sfx(name, pos, vol)                      the same, safe to call before/without Audio existing
#   Bus "sfx" {name, pos?, vol?, pitch?, surface?} the way other systems should ask for a sound
# It also listens to the standard Bus events (enemy_hit, enemy_died, player_hit, player_attack, pickup,
# level_up, faint, respawn, mission_start, mission_done, skill_used, lira, night) so the game makes noise
# without anyone calling it.
# Music: 7.2's in-game synth loop (CHORDS / musicStart / schedBar 4944-4981, Am F C G, 2.4 s bars) as the
# "day" stem, plus new night and combat stems in the same key and tempo (combat is built from the intro
# track IM / imBar 18459-18501: kick, snare, filter bass, arps through a delay, IMLEAD). All stems play in
# sync and crossfade: night when Bus "night" says so, combat when a live monster is close. The DJ layer
# (7.2's djUntil) sits on top. The intro track itself renders on demand: set_music_mode("intro").
# M toggles music, V monster voices (7.2's keys). Volumes like 7.2's options: musVol (16) / sfxVol (90) / voiceOn, kept in
# torii_save (7.2 kept them in torii_opts) + musicOn. Monster voices: 7.2's MOBTALK / VOICE / FORMANT
# babble / mobSpeak 8846-8927 — a speech bubble, a vowel-tracking synth voice and the system TTS voice.
class_name Audio
extends Node

static var me: Audio
const SR := 22050
const MUS_GAIN := 3.0      # stems render 3x hot so 16 bits keep their detail; the Music bus takes it back
const MUS_TRIM := 1.6      # 7.2's music sat very low; a touch louder here since it carries the mood

# 7.2's monster lines (MOBTALK) — [turkish, english, 1 = it's English already]. lory/vergi/kapici/aga are new.
const MOBTALK := {
	"imp": [["Yakala!", "Catch her!"], ["Küçük!", "Little one!"], ["Hızlı!", "Fast!"], ["Gel buraya!", "Come here!"], ["Seni buldum!", "I found you!"]],
	"okuz": [["Çekil önümden!", "Get out of my way!"], ["Ben geçerim!", "I go first!"], ["Sıra mı var?", "Is there a queue?"],
		["Kaba mıyım? Kabayım!", "Am I rude? I am rude!"], ["Bana ne!", "What do I care!"], ["Öff!", "Ugh!"], ["Sen kimsin?", "Who even are you?"],
		["Bastım gaza!", "I hit the gas!"], ["Özür dilemem!", "I will not apologise!"], ["Hoşça kal demem!", "I do not say goodbye!"]],
	"zombie": [["Açım!", "I am hungry!"], ["Beyin...", "Brain..."], ["Mesai!", "Overtime!"], ["Toplantı!", "Meeting!"], ["Yorgunum", "I am tired"], ["Work... work...", "", 1]],
	"thot": [["Kim bu?", "Who is this?"], ["Çirkin!", "Ugly!"], ["Bana bak!", "Look at me!"], ["Whatever!", "", 1], ["Benim!", "Mine!"]],
	"ghost": [["Soğuk...", "Cold..."], ["Gel bana", "Come to me"], ["Buradayım", "I am here"], ["Korkuyor musun?", "Are you scared?"]],
	"witch": [["Lanet olsun!", "Curse you!"], ["Büyü!", "Magic!"], ["Kızım!", "My girl!"], ["Nazar değsin!", "May the evil eye strike!"]],
	"skeleton": [["Kemik!", "Bone!"], ["Ok!", "Arrow!"], ["Ölüm...", "Death..."], ["Nişan al", "Take aim"]],
	"mummy": [["Bin yıl...", "A thousand years..."], ["Uyandım", "I woke up"], ["Yavaş...", "Slow..."], ["Çok eski", "Very old"]],
	"driver": [["Korna!", "Horn!"], ["Sinyal versene!", "Use your signal!"], ["Dikkat et!", "Watch out!"], ["Öğrenci sürücü!", "Student driver!"]],
	"cruze": [["Yıkanmadım", "I was not washed"], ["İki bin on yedi!", "Two thousand seventeen!"], ["Koku!", "Smell!"]],
	"karen": [["Müdürü çağır!", "Call the manager!"], ["Son e-postama göre", "Per my last email"], ["Kovuldun!", "You are fired!"], ["Fazla mesai!", "Overtime!"]],
	"spirit": [["Ata...", "Ancestor..."], ["Hatırla", "Remember"], ["Maske", "Mask"]],
	"scorpion": [["Sok!", "Sting!"], ["Kum!", "Sand!"], ["Zehir", "Venom"]],
	"wisp": [["Geçmiş...", "The past..."], ["Anı", "Memory"], ["Kal benimle", "Stay with me"]],
	"lory": [["Ben daha güzelim!", "I am prettier!"], ["Ayna ayna...", "Mirror mirror..."], ["Kopya değilim!", "I am not a copy!"]],
	"vergi": [["Vergi!", "Tax!"], ["Fiş var mı?", "Got a receipt?"], ["Öde!", "Pay!"]],
	"kapici": [["Kapı kapalı!", "The door is closed!"], ["Aidat!", "Dues!"], ["Çöp!", "Rubbish!"]],
	"aga": [["Ağa benim!", "I am the Agha!"], ["Toprak benim!", "The land is mine!"], ["Diz çök!", "Kneel!"]],
}
# 7.2's VOICE: rate / pitch / volume per creature (+ the four new ones)
const VOICE := {
	"imp": [1.65, 1.95, .55], "zombie": [.55, .32, .7], "thot": [1.2, 1.6, .6], "ghost": [.6, .75, .45],
	"witch": [1.35, 1.75, .6], "skeleton": [1.05, .45, .6], "mummy": [.45, .28, .65], "driver": [1.45, 1.05, .75],
	"cruze": [.7, .25, .75], "karen": [1.3, 1.45, .85], "spirit": [.7, .85, .5], "scorpion": [1.55, 1.7, .5],
	"wisp": [.65, 1.25, .4], "alien": [1.5, 1.85, .6], "drone": [1.7, .6, .55], "kaan": [1.02, .86, .9], "okuz": [.42, .24, .85],
	"lory": [1.15, 1.5, .6], "vergi": [1.3, 1.3, .75], "kapici": [.8, .5, .7], "aga": [.75, .4, .8],
}
# each monster's own 7.2 sound (ENEMY[k].snd) and how high its grunts sit
const ARCH := {
	"imp": ["chitter", 1.6], "witch": ["cackle", 1.3], "skeleton": ["rattle", .9], "mummy": ["moan", .6], "driver": ["honk", 1.0],
	"lory": ["sass", 1.35], "vergi": ["karen", 1.2], "kapici": ["groan", .7], "zombie": ["groan", .65], "thot": ["sass", 1.3],
	"ghost": ["boo", .8], "cruze": ["rev", .55], "karen": ["karen", 1.2], "spirit": ["boo", .85], "scorpion": ["sting", 1.5],
	"wisp": ["woosh2", 1.1], "okuz": ["groan", .5], "aga": ["karen", .6],
}
# everything in the bank. 7.2's fx names first (exact), then the Godot build's
const NAMES := ["chuckle", "bark", "ding", "whoosh", "stab", "bassHit", "groan", "chitter", "fanfare", "yes", "no", "hurt",
	"boost", "cough", "dizzy", "heal", "drop", "dance", "sass", "boo", "rev", "clack", "cash", "karen", "blah", "drum", "thud",
	"coin", "sting", "woosh2", "cackle", "rattle", "moan", "honk", "arrow", "coinflip", "divine", "stink", "firework", "zap", "levelup",
	"step", "step_sand", "step_grass", "step_wood", "step_water", "jump", "land", "land_hard", "roll", "swing_light", "swing_heavy",
	"hit", "hit_heavy", "crit", "parry", "block", "faint", "respawn", "enemy_hurt", "enemy_die", "boss_die", "growl", "tell",
	"charge", "shoot", "magic", "explosion", "pickup", "nazar", "level_up", "quest_start", "quest_done", "mission_start",
	"mission_done", "menu_move", "menu_select", "menu_back", "ui_open", "ui_close", "ui_toast", "eat", "drink", "chest_open",
	"pedal", "crash", "empty_click", "winded", "lock_on", "lock_off", "door", "splash", "heartbeat", "cast", "cast_fire",
	"cast_ice", "cast_shock", "cast_heal", "cast_buff", "cast_dash", "cast_nova", "photo", "gear_drop", "break", "climb", "grab",
	"dodge", "drift", "guard_break", "shield", "charge_full", "dash", "slam", "enemy_notice", "enemy_swing", "meow", "combo_end"]
const VARIANTS := {"step": 3, "step_sand": 2, "step_grass": 2, "hit": 3, "swing_light": 3, "enemy_hurt": 2, "chitter": 2, "blah": 2, "bark": 2}
const ALIAS := {"woosh": "whoosh", "levelUp": "level_up", "select": "menu_select", "move": "menu_move", "back": "menu_back",
	"toast": "ui_toast", "chest": "chest_open", "travel": "woosh2", "bell": "ding", "skill": "cast", "fireball": "cast_fire",
	"lock": "lock_on", "unlock": "lock_off", "heavy": "swing_heavy", "enemy_hit": "enemy_hurt", "enemy_hit_heavy": "enemy_hurt",
	"enemy_windup": "tell", "parry_stun": "dizzy", "weapon": "gear_drop", "bass_hit": "bassHit", "right": "yes", "wrong": "no"}
# jingles and UI keep their exact pitch; everything else wobbles a little so repeats don't drone
const NOJIT := ["fanfare", "levelup", "level_up", "quest_start", "quest_done", "mission_start", "mission_done", "menu_move",
	"menu_select", "menu_back", "ui_open", "ui_close", "ui_toast", "ding", "yes", "no", "divine", "dance", "respawn", "lock_on", "lock_off"]
const UI_NAMES := ["menu_move", "menu_select", "menu_back", "ui_open", "ui_close", "ui_toast", "yes", "no", "ding", "chuckle",
	"fanfare", "level_up", "levelup", "quest_start", "quest_done", "mission_start", "mission_done", "coin", "cash"]

var world: Node3D
var cam: Camera3D
var sfx_ready := false
var music_on := true
var mus_vol := 16
var sfx_vol := 90
var voice_on := true
var night := false
var mode := "world"                 # "world" (day / night / combat) | "intro" | "none"
var _bank := {}                     # name -> Array of AudioStreamWAV (variants)
var _babble := {}                   # "kind:i" -> AudioStreamWAV
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _r2 := 0
var _r3 := 0
var _last := {}                     # name -> msec (the same sound twice in 35 ms plays once)
var _stems := {}                    # day / night / combat / dj -> AudioStreamPlayer
var _amp := {"day": 0.0, "night": 0.0, "combat": 0.0, "dj": 0.0, "intro": 0.0}
var _intro: AudioStreamPlayer
var _intro_wav: AudioStreamWAV
var _intro_task := -1
var _combat := 0.0
var _combat_hold := 0.0
var _scan_t := 0.0
var _dj_until := 0.0
var _duck := 1.0
var _duck_to := 1.0
var _duck_t := 0.0
var _voice_busy := 0.0
var _tts_voice := {}                # lang -> voice id
var _tts_look := {}                 # lang -> last look-up time
var _thr: Thread
var _abort := false
var _applied := false

static func sfx(name: String, pos: Variant = null, vol := 1.0, pitch := 1.0) -> void:
	if is_instance_valid(me): me.play(name, pos, vol, pitch)

# 7.2's speak(): a Turkish word read out (rate .85, pitch 1.15, volume .9). Falls back to any voice (TRK-14)
static func speak(text: String, lang := "tr") -> void:
	if is_instance_valid(me): me.say(text, lang)

func setup(w: Node3D, camera: Camera3D) -> void:
	me = self; world = w; cam = camera
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buses()
	for i in 14:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"; p.process_mode = Node.PROCESS_MODE_ALWAYS; add_child(p); _p2.append(p)
	for i in 4:                                              # the last 4 2D players are dry, for menus and jingles
		_p2[i].bus = "UI"
	for i in 18:
		var p := AudioStreamPlayer3D.new(); p.bus = "SFX"; p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.unit_size = 7.0; p.max_distance = 60.0; p.panning_strength = .7
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		w.add_child(p); _p3.append(p)
	if camera and camera.get_viewport(): camera.get_viewport().audio_listener_enable_3d = true    # the 3D lives in a SubViewport
	for k in ["day", "night", "combat", "dj"]:
		var p := AudioStreamPlayer.new(); p.bus = "Music"; p.process_mode = Node.PROCESS_MODE_ALWAYS; p.volume_db = -80
		add_child(p); _stems[k] = p
	_intro = AudioStreamPlayer.new(); _intro.bus = "Music"; _intro.process_mode = Node.PROCESS_MODE_ALWAYS; _intro.volume_db = -80
	add_child(_intro)
	for ev in ["sfx", "enemy_hit", "enemy_died", "player_hit", "player_attack", "pickup", "level_up", "faint", "respawn",
			"mission_start", "mission_done", "quest_done", "skill_used", "lira", "night", "dj", "enemy_notice", "enemy_attack", "enemy_tell", "mob_talk",
			"quiz_answer", "weapon_broke", "weapon_new", "weapon_gained"]:
		Bus.on(ev, _on_ev.bind(ev))
	apply_settings.call_deferred()
	_thr = Thread.new(); _thr.start(_render_all)

func _buses() -> void:
	for b in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus(); var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b); AudioServer.set_bus_send(i, "Master")
			if b == "SFX":                                    # a little PS1 SPU room on the world sounds
				var rv := AudioEffectReverb.new(); rv.room_size = .35; rv.damping = .6; rv.wet = .1; rv.dry = 1.0
				AudioServer.add_bus_effect(i, rv)

# her settings live in torii_save: musVol / sfxVol / voiceOn (7.2's torii_opts names) and musicOn
func apply_settings() -> void:
	var d := SaveBridge.data
	mus_vol = clampi(int(d.get("musVol", 16)), 0, 100)
	sfx_vol = clampi(int(d.get("sfxVol", 90)), 0, 100)
	voice_on = bool(d.get("voiceOn", true))
	music_on = bool(d.get("musicOn", true))
	_applied = true
	_sync_voice()
	_bus_vols()

func _bus_vols() -> void:
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_mute(mi, mus_vol <= 0)
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(.0001, mus_vol / 100.0 * .32 / MUS_GAIN * MUS_TRIM)))
	for b in ["SFX", "UI"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, sfx_vol <= 0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(.0001, sfx_vol / 100.0)))

func _store(k: String, v: Variant) -> void:
	SaveBridge.data[k] = v; SaveBridge.write()

func set_music_volume(pct: int) -> void:
	mus_vol = clampi(pct, 0, 100); _bus_vols(); _store("musVol", mus_vol)

func set_sfx_volume(pct: int) -> void:
	sfx_vol = clampi(pct, 0, 100); _bus_vols(); _store("sfxVol", sfx_vol); play("ding")     # 7.2 dings as you slide

func set_voice(on: bool) -> void:
	voice_on = on; _store("voiceOn", on); _sync_voice()
	if not on: DisplayServer.tts_stop()
	_toast("🔊 MONSTER VOICES: ON" if on else "🔇 MONSTER VOICES: OFF")

# enemy.gd has its own static voice_on for its speech bubbles' TTS; keep it in step (no hard class
# reference so a broken enemy.gd can't take the sound down with it). Others can listen to Bus "voice".
func _sync_voice() -> void:
	if ResourceLoader.has_cached("res://scripts/enemy.gd"):     # main.gd uses Enemy, so it's loaded by now
		var sc := load("res://scripts/enemy.gd") as Script
		if sc: sc.set("voice_on", voice_on)                       # sets its static var (no-op if it has none)
	Bus.emit_ev("voice", {"on": voice_on})

func toggle_music() -> void:
	music_on = not music_on; _store("musicOn", music_on)
	_toast("🎵 Music on" if music_on else "🔇 Music off")

# 7.2 toast(…, 3000) through the HUD, like the other systems reach it
func _toast(t: String) -> void:
	if Lessons.me and Lessons.me.hud: Lessons.me.hud.toast(t, 3.0)

func set_music_mode(m: String) -> void:
	mode = m
	if m == "intro" and _intro_wav == null and _intro_task == -1:
		_intro_task = WorkerThreadPool.add_task(_render_intro)

func set_night(on: bool) -> void: night = on

# 7.2's DJ decks: extra hats and a lead on top of the music for `sec` seconds
func dj(sec: float) -> void: _dj_until = Time.get_ticks_msec() / 1000.0 + sec

# pull the music down for a moment (a jingle, fainting)
func duck(to := .3, sec := 1.5) -> void:
	_duck_to = minf(_duck_to, to) if _duck_t > 0 else to; _duck_t = maxf(_duck_t, sec)

func has_sound(name: String) -> bool: return _bank.has(ALIAS.get(name, name))

func play(name: String, pos: Variant = null, vol := 1.0, pitch := 1.0) -> void:
	name = ALIAS.get(name, name)
	var bank: Array = _bank.get(name, [])
	if bank.is_empty() or vol <= 0.0: return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 35: return
	_last[name] = now
	var st: AudioStreamWAV = bank[randi() % bank.size()]
	if not NOJIT.has(name): pitch *= randf_range(.95, 1.05)
	if pos is Vector3 and is_instance_valid(cam) and is_instance_valid(world):
		if cam.global_position.distance_to(pos) > 58.0: return
		var p := _free3()
		p.stream = st; p.global_position = pos; p.volume_db = linear_to_db(vol) + 4.0; p.pitch_scale = clampf(pitch, .3, 3.0); p.play()
	else:
		var p := _free2(UI_NAMES.has(name))
		p.stream = st; p.volume_db = linear_to_db(vol); p.pitch_scale = clampf(pitch, .3, 3.0); p.play()

func _free2(ui: bool) -> AudioStreamPlayer:
	var lo := 0 if ui else 4
	var hi := 4 if ui else _p2.size()
	for i in range(lo, hi):
		if not _p2[i].playing: return _p2[i]
	_r2 = lo + (_r2 + 1) % (hi - lo)
	return _p2[_r2]

func _free3() -> AudioStreamPlayer3D:
	for p in _p3:
		if not p.playing: return p
	_r3 = (_r3 + 1) % _p3.size()
	return _p3[_r3]

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	if e.physical_keycode == KEY_M:                               # 7.2: M music on/off
		toggle_music(); get_viewport().set_input_as_handled()
	elif e.physical_keycode == KEY_V:                             # 7.2: V monster voices on/off
		set_voice(not voice_on); get_viewport().set_input_as_handled()

# ---- the Bus: everyone gets sound without calling Audio ----
func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _pos(d: Dictionary) -> Variant:
	var p: Variant = d.get("pos")
	if p is Vector3: return p
	var e: Variant = d.get("enemy")
	if e is Node3D and is_instance_valid(e): return e.global_position
	return null

func _kind(d: Dictionary) -> String:
	var k := str(d.get("kind", ""))
	if k == "":
		var e: Variant = d.get("enemy")
		if e is Node and is_instance_valid(e) and "type" in e: k = str(e.type)
	return k

func _arch_pitch(d: Dictionary) -> float:
	var A: Array = ARCH.get(_kind(d), ["groan", 1.0])
	var p: float = A[1]
	if d.get("elite", false): p *= .85
	if d.get("boss", false): p *= .75
	var e: Variant = d.get("enemy")
	if e is Node and is_instance_valid(e):
		if "elite" in e and e.elite: p *= .85
		if "flags" in e and e.flags is Dictionary and e.flags.has("boss"): p *= .75
	return clampf(p, .4, 2.0)

func _on_ev(d: Dictionary, ev: String) -> void:
	match ev:
		"sfx":
			var n := str(d.get("name", ""))
			if d.has("surface") and _bank.has(n + "_" + str(d["surface"])): n = n + "_" + str(d["surface"])
			play(n, d.get("pos"), float(d.get("vol", 1.0)), float(d.get("pitch", 1.0)))
		"enemy_hit":
			var p: Variant = _pos(d)
			play("crit" if d.get("crit", false) else ("hit_heavy" if d.get("heavy", false) else "hit"), p)
			play("enemy_hurt", p, .7, _arch_pitch(d))
		"enemy_died":
			var p: Variant = _pos(d)
			if d.get("boss", false): play("boss_die"); duck(.25, 2.5)
			else: play("enemy_die", p, 1.0, _arch_pitch(d))
			play(str(ARCH.get(_kind(d), ["groan"])[0]), p, .7)               # 7.2: fx[e.snd]() on the kill
		"player_hit":
			if d.get("parried", false): play("parry")
			elif d.get("blocked", false): play("block")
			elif int(d.get("dmg", 1)) > 0: play("hurt")
		"player_attack":
			var k := str(d.get("kind", "light")); var c := int(d.get("combo", 0))
			var snd := str(d.get("snd", ""))
			if snd == "":
				var pl := _player()
				if pl and "weapon" in pl and pl.weapon is Dictionary: snd = str(pl.weapon.get("snd", ""))
			if k == "heavy": play("swing_heavy")
			elif k == "ranged": play("shoot")
			else: play("swing_light", null, 1.0, 1.0 + .07 * clampi(c, 0, 4))
			if c >= 3 and k != "ranged": play("combo_end")
			if snd != "": play(snd, null, .55)                                # the weapon's own 7.2 sound (w.snd)
		"pickup":
			var k := str(d.get("kind", ""))
			var n := str({"nazar": "nazar", "coin": "coin", "lira": "coin", "food": "pickup", "gear": "gear_drop",
				"weapon": "gear_drop", "chest": "chest_open", "ammo": "pickup", "heal": "heal"}.get(k, "pickup"))
			play(n, null)
		"lira":
			var dl := int(d.get("delta", 0))
			if dl > 0: play("coin")
			elif dl < 0: play("cash")
		"level_up": play("level_up"); duck(.2, 2.6)
		"faint": play("faint"); duck(0.0, 2.8)
		"respawn": play("respawn")
		"mission_start": play("mission_start"); duck(.35, 1.6)
		"mission_done": play("mission_done"); duck(.2, 3.0)
		"quest_done": play("quest_done"); duck(.35, 1.6)
		"skill_used": play(_skill_snd(str(d.get("id", ""))))
		"night": night = bool(d.get("on", false))
		"dj": dj(float(d.get("sec", 30.0)))
		"enemy_notice":                                                        # 7.2: first time it spots her
			var p: Variant = _pos(d)
			play(str(ARCH.get(_kind(d), ["growl"])[0]), p)
			if p is Vector3 and randf() < .7: mob_talk(_kind(d), p)
		"enemy_attack":                                                        # 7.2 mobAttack: fx[e.snd]() + 55% a line
			var p: Variant = _pos(d)
			play("growl", p, .8, _arch_pitch(d))
			if p is Vector3 and randf() < .55: mob_talk(_kind(d), p)
		"enemy_tell":                                                          # a wind-up: warn her by ear too
			var p: Variant = _pos(d)
			play("charge" if str(d.get("move", "")) == "charge" else "tell", p, 1.0, _arch_pitch(d))
		"mob_talk":
			var p: Variant = _pos(d)
			if p is Vector3: mob_talk(_kind(d), p, bool(d.get("slow", false)), d.get("line", []))
		"quiz_answer":                                                         # 7.2: right = yes, wrong = no (+ red flash in Fx)
			play("yes" if d.get("ok", false) else "no")
		"weapon_broke": play("break")
		"weapon_new", "weapon_gained": play("gear_drop")

func _skill_snd(id: String) -> String:
	if _bank.has("skill_" + id): return "skill_" + id
	if _bank.has("cast_" + id): return "cast_" + id
	for pair in [["fire", "cast_fire"], ["burn", "cast_fire"], ["ice", "cast_ice"], ["frost", "cast_ice"], ["shock", "cast_shock"],
			["zap", "cast_shock"], ["thunder", "cast_shock"], ["heal", "cast_heal"], ["shield", "cast_buff"], ["buff", "cast_buff"],
			["haste", "cast_buff"], ["dash", "cast_dash"], ["blink", "cast_dash"], ["nova", "cast_nova"], ["burst", "cast_nova"], ["nazar", "nazar"]]:
		if id.contains(pair[0]): return pair[1]
	return "cast"

# ---- monster voices (7.2 mobSpeak) ----
# a bubble over its head, the synth babble, and the system TTS voice at that creature's pitch and pace.
# line = [tr, en, 1?]; leave it empty to pick one of the creature's own lines
func mob_talk(kind: String, pos: Vector3, slow := false, line: Array = []) -> void:
	var lines: Array = MOBTALK.get(kind, [["Hey!", "", 1]])
	var idx := -1
	if line.is_empty():
		idx = randi() % lines.size(); line = lines[idx]
	var en := str(line[1]) if line.size() > 1 else ""
	if Fx.me: Fx.me.label(pos + Vector3(0, 2.6, 0), "\"%s\"%s" % [line[0], (" (%s)" % en) if en != "" else ""], Color("ffd6e8"), 2.8, true)
	if not voice_on: return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _voice_busy: return
	var pl := _player()
	var dist := pl.global_position.distance_to(pos) if pl else 8.0
	if dist * dist > 420.0: return                                          # only mobs she can actually see
	var V: Array = VOICE.get(kind, [1.0, 1.0, .6])
	var near := 1.0 - minf(1.0, dist / 21.0)
	var vol: float = V[2] * (.35 + near * .65)
	var sf := .86 if kind == "kaan" else .62
	var rate: float = clampf(V[0] * sf, .82 if kind == "kaan" else .68, 1.05) if slow else clampf(V[0], .5, 2.0)
	_voice_busy = now + (2.6 if slow else 1.15)
	var has_tts := _voice_for("tr") != ""
	var solo := 1.0 if has_tts else 1.85                                     # louder when it's doing the job alone
	var key := "%s:%d" % [kind, idx]
	if idx >= 0 and not slow and _babble.has(key):
		_play_babble(_babble[key], vol * solo)
	else:
		WorkerThreadPool.add_task(func():
			var s := Syn.new(); s.begin(3.5); s.babble(str(line[0]), V[1], rate); s.trim()
			_play_babble.call_deferred(s.to_wav(), vol * solo))
	if has_tts and not DisplayServer.tts_is_speaking():                     # never talk over a Turkish lesson
		var en_line := line.size() > 2 and int(line[2]) == 1
		say(str(line[0]), "en" if en_line else "tr", rate, V[1], vol, false)

func _play_babble(w: AudioStreamWAV, vol: float) -> void:
	var p := _free2(false); p.stream = w; p.volume_db = linear_to_db(maxf(.001, vol)); p.pitch_scale = 1.0; p.play()

# TTS with 7.2's fallbacks: the language's voice, else any voice at all; looks again every 2 s while it
# has none (voices can turn up late) instead of giving up for good
func say(text: String, lang := "tr", rate := .85, pitch := 1.15, vol := .9, interrupt := true) -> bool:
	var v := _voice_for(lang)
	if v == "": return false
	if interrupt: DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, v, int(clampf(vol, 0.0, 1.0) * 100.0), clampf(pitch, 0.0, 2.0), clampf(rate, .1, 10.0))
	return true

func _voice_for(lang: String) -> String:
	if str(_tts_voice.get(lang, "")) != "": return _tts_voice[lang]
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH): return ""
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_tts_look.get(lang, -10.0)) < 2.0: return ""
	_tts_look[lang] = now
	var ids := DisplayServer.tts_get_voices_for_language(lang)
	var id := ids[0] if ids.size() else ""
	if id == "":
		var all := DisplayServer.tts_get_voices()
		if all.size(): id = str(all[0].get("id", ""))
	if id != "": _tts_voice[lang] = id
	return id

# ---- music mixing ----
func _process(dt: float) -> void:
	if not _applied and not SaveBridge.data.is_empty(): apply_settings()
	dt = minf(dt, .1)
	_scan_t -= dt
	if _scan_t <= 0:
		_scan_t = .3; _scan()
	_combat_hold -= dt
	_combat = move_toward(_combat, 1.0 if _combat_hold > 0 else 0.0, dt / (1.2 if _combat_hold > 0 else 3.0))
	if _duck_t > 0:
		_duck_t -= dt; _duck = move_toward(_duck, _duck_to, dt * 4.0)
	else:
		_duck = move_toward(_duck, 1.0, dt * .7); _duck_to = 1.0
	var on := 1.0 if music_on and mode == "world" else 0.0
	var n := 1.0 if night else 0.0
	var tgt := {"day": (1.0 - n) * (1.0 - _combat) * on, "night": n * (1.0 - _combat) * on, "combat": _combat * on,
		"dj": on if Time.get_ticks_msec() / 1000.0 < _dj_until else 0.0,
		"intro": 1.0 if music_on and mode == "intro" else 0.0}
	for k in tgt:
		_amp[k] = move_toward(_amp[k], tgt[k], dt * (.8 if k != "combat" else 1.0))
		var p: AudioStreamPlayer = _intro if k == "intro" else _stems[k]
		p.volume_db = linear_to_db(maxf(.0001, _amp[k] * _duck))
	if mode == "intro" and _intro_wav and not _intro.playing:
		_intro.stream = _intro_wav; _intro.play()
	elif mode != "intro" and _intro.playing and _amp["intro"] <= .001: _intro.stop()

func _scan() -> void:
	if Overlay.any(): return
	var pl := _player()
	if pl == null: return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not is_instance_valid(e): continue
		var alive: bool = e.is_alive() if e.has_method("is_alive") else ("hp" in e and float(e.hp) > 0.0)
		if not alive: continue
		var boss: bool = "flags" in e and e.flags is Dictionary and e.flags.has("boss")
		if e.global_position.distance_to(pl.global_position) < (40.0 if boss else 18.0):
			_combat_hold = 4.0; return

# a stem is ready: join the others in time (they're all whole multiples of the 9.6 s day loop)
func _got_stem(k: String, w: AudioStreamWAV) -> void:
	var p: AudioStreamPlayer = _stems[k]; p.stream = w
	var at := 0.0
	for o in _stems.values():
		if o != p and o.playing:
			at = fmod(o.get_playback_position() + AudioServer.get_time_since_last_mix(), w.get_length()); break
	p.play(at)

func _got(name: String, list: Array) -> void:
	_bank[name] = list
	if name == NAMES[NAMES.size() - 1]: sfx_ready = true

func _got_babble(key: String, w: AudioStreamWAV) -> void: _babble[key] = w

func _got_intro(w: AudioStreamWAV) -> void: _intro_wav = w

func _exit_tree() -> void:
	_abort = true
	if _thr and _thr.is_started(): _thr.wait_to_finish()
	if _intro_task != -1: WorkerThreadPool.wait_for_task_completion(_intro_task); _intro_task = -1
	if me == self: me = null

# ---- rendering (background thread) ----
func _render_all() -> void:
	for name in NAMES:
		if _abort: return
		var list := []
		for v in int(VARIANTS.get(name, 1)):
			var s := Syn.new(); s.begin(3.2)
			_recipe(s, name); s.trim(); list.append(s.to_wav())
		_got.call_deferred(name, list)
	for k in ["day", "combat", "night", "dj"]:
		if _abort: return
		_got_stem.call_deferred(k, _stem(k))
	for kind in MOBTALK:
		var V: Array = VOICE.get(kind, [1.0, 1.0, .6])
		var lines: Array = MOBTALK[kind]
		for i in lines.size():
			if _abort: return
			var s := Syn.new(); s.begin(3.5); s.babble(str(lines[i][0]), V[1], clampf(V[0], .5, 2.0)); s.trim()
			_got_babble.call_deferred("%s:%d" % [kind, i], s.to_wav())

const CHORDS := [[220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [130.8, 164.8, 196.0], [196.0, 246.9, 293.7]]
const IMCH := [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
const IMRT := [110.0, 87.31, 130.81, 98.0]
const IMLEAD := [[[0, 659.25, 4], [4, 783.99, 2], [6, 659.25, 2], [8, 587.33, 4], [12, 523.25, 4]], [[0, 523.25, 6], [6, 440.0, 2], [8, 523.25, 4], [12, 587.33, 4]],
	[[0, 659.25, 4], [4, 783.99, 4], [8, 659.25, 2], [10, 587.33, 2], [12, 523.25, 4]], [[0, 587.33, 8], [8, 493.88, 4], [12, 392.0, 4]]]

func _stem(k: String) -> AudioStreamWAV:
	var s := Syn.new()
	var bars := 8 if k == "combat" else 4
	s.begin(bars * 2.4, true)
	match k:
		"day":                                     # 7.2 schedBar, note for note
			for bar in bars:
				var t0 := bar * 2.4; var ch: Array = CHORDS[bar % 4]
				s.tgt = 1
				for f in ch: s.pad(t0, f, "sawtooth", .05, .3, 2.35)
				s.tgt = 0
				for i in 8:
					var t := t0 + i * .3
					s.tone(ch[0] / 2.0, .26, "square", .06, t)
					if i % 2 == 1: s.nz(.05, .05, 6000, t, 2, .7)
			s.flush_pad(900.0)
		"dj":                                      # 7.2's DJ layer: 16th hats + a square lead
			for bar in bars:
				var t0 := bar * 2.4; var ch: Array = CHORDS[bar % 4]
				for i in 16: s.nz(.04, .045, 7000, t0 + i * .15, 2, .7)
				s.tone(ch[2] * 2.0, 2.3, "square", .04, t0)
		"night":                                   # new: same chords, darker pad, slow arps through the delay
			s.use_send()
			for bar in bars:
				var t0 := bar * 2.4; var ch: Array = CHORDS[bar % 4]
				s.tgt = 1
				for f in ch:
					for dt in [-8.0, 8.0]: s.pad(t0, f, "sawtooth", .032, .9, 2.38, dt)
				s.tgt = 0
				s.tone(ch[0] / 2.0, 2.3, "sine", .07, t0)
				s.send = .9
				for i in 8: s.tone([ch[0], ch[1], ch[2], ch[1] * 2.0][i % 4] * 2.0, .22, "triangle", .022, t0 + i * .3)
				s.send = 0.0
				for i in 4: s.nz(.03, .025, 7500, t0 + i * .6 + .3, 2, .7)
			s.flush_pad(620.0)
			s.delay(.45, .38, .55)
		"combat":                                  # new, built from 7.2's intro track (imBar, bars >= 2)
			s.use_send()
			for bar in bars:
				if _abort: break
				var t0 := bar * 2.4; var i4 := bar % 4; var ch: Array = IMCH[i4]; var rt: float = IMRT[i4]
				s.tgt = 1
				for f in ch:
					for dt in [-8.0, 8.0]: s.pad(t0, f, "sawtooth", .028 * 1.5, .6, 2.38, dt)
				s.tgt = 0
				s.send = 1.0
				for i in 16: s.tone([ch[0], ch[1], ch[2], ch[1] * 2.0][i % 4] * 2.0, .13, "square", .022 * 1.5, t0 + i * .15)
				s.send = 0.0
				for i in 8: s.pluck(t0 + i * .3, rt * 2.0 if i % 2 else rt, "sawtooth", .09 * 1.5, .28, 1100.0, 240.0, 2.2)
				for b in 4:
					var t := t0 + b * .6
					if b % 2 == 0: s.tone(150, .32, "sine", .55 * 1.5, t, 42)
					else:
						s.nz(.3, .3 * 1.5, 1900, t, 0, .7); s.tone(190, .12, "triangle", .14 * 1.5, t, 120)
				for i in 8: s.nz(.05, (.07 if i % 2 else .04) * 1.5, 7500, t0 + i * .3 + (0.0 if i % 2 else .15), 2, .8)
				if bar >= 4:                       # the lead every other 4 bars, like the intro
					s.send = 1.0
					for L in IMLEAD[i4]: s.lead(t0 + L[0] * .15, L[1], L[2] * .15, 1.5)
					s.send = 0.0
			s.flush_pad(1500.0)
			s.delay(.45, .38, .55)
	return s.to_wav(MUS_GAIN, 0, s.n)

# 7.2's intro theme (imBar) for the title/intro, bars 0-11: plays once from the top, then loops bars 4-11
func _render_intro() -> void:
	var s := Syn.new(); s.begin(13 * 2.4); s.use_send()
	for bar in 12:
		if _abort: return
		var t0 := bar * 2.4; var i4 := bar % 4; var ch: Array = IMCH[i4]; var rt: float = IMRT[i4]
		s.tgt = 1
		for f in ch:
			for dt in [-8.0, 8.0]: s.pad(t0, f, "sawtooth", .028 * 1.5, .6, 2.38, dt)
		s.tgt = 0; s.send = 1.0
		for i in 16: s.tone([ch[0], ch[1], ch[2], ch[1] * 2.0][i % 4] * 2.0, .13, "square", .022 * 1.5, t0 + i * .15)
		s.send = 0.0
		if bar < 2: continue
		if bar == 3: s.nz(2.2, .16 * 1.5, 4500, t0, 2, .8); s.tone(55, 1.2, "sawtooth", .4 * 1.5, t0, 40)      # the crash under the logo
		for i in 8: s.pluck(t0 + i * .3, rt * 2.0 if i % 2 else rt, "sawtooth", .09 * 1.5, .28, 1100.0, 240.0, 2.2)
		for b in 4:
			var t := t0 + b * .6
			if b % 2 == 0: s.tone(150, .32, "sine", .55 * 1.5, t, 42)
			else:
				s.nz(.3, .3 * 1.5, 1900, t, 0, .7); s.tone(190, .12, "triangle", .14 * 1.5, t, 120)
		for i in 8: s.nz(.05, (.07 if i % 2 else .04) * 1.5, 7500, t0 + i * .3 + (0.0 if i % 2 else .15), 2, .8)
		if bar >= 4 and (bar - 4) % 8 < 4:
			s.send = 1.0
			for L in IMLEAD[i4]: s.lead(t0 + L[0] * .15, L[1], L[2] * .15, 1.5)
			s.send = 0.0
	s.flush_pad(1500.0)
	s.delay(.45, .38, .55)
	var lb := int(4 * 2.4 * SR); var le := int(12 * 2.4 * SR)
	s.fold(lb, le)
	_got_intro.call_deferred(s.to_wav(MUS_GAIN, lb, le))

# every sound, as tone()/nz() calls like 7.2's fx table. tone(freq, dur, wave, vol, delay, freq_end);
# nz(dur, vol, band_freq, delay, kind 0 band / 1 low / 2 high, q)
func _recipe(s: Syn, name: String) -> void:
	match name:
		# --- 7.2's fx, exactly ---
		"chuckle": s.tone(830, .09, "sine", .14, 0, 1150); s.tone(1100, .13, "sine", .11, .11, 720)
		"bark": s.nz(.07, .32, 850); s.tone(320, .08, "square", .22, 0, 140); s.nz(.07, .26, 900, .13); s.tone(300, .08, "square", .18, .13, 130)
		"ding": s.tone(1318, .09, "triangle", .16); s.tone(1760, .16, "triangle", .13, .07)
		"whoosh": s.nz(.16, .24, 520)
		"stab": s.tone(1900, .05, "square", .1, 0, 2600); s.nz(.05, .12, 2400)
		"bassHit": s.tone(65, .5, "sawtooth", .32, 0, 58); s.tone(98, .5, "sawtooth", .22); s.tone(131, .42, "sawtooth", .17); s.nz(.2, .15, 140)
		"groan": s.tone(110, .65, "sawtooth", .16, 0, 68)
		"chitter":
			for i in 3: s.tone(s.r(900, 1500), .05, "square", .09, i * .06, s.r(600, 1000))
		"fanfare":
			for i in 4: s.tone([523, 659, 784, 1047][i], .22, "triangle", .18, i * .11)
		"yes": s.tone(660, .11, "triangle", .16); s.tone(880, .2, "triangle", .14, .1)
		"no": s.tone(150, .32, "sawtooth", .22, 0, 105)
		"hurt": s.nz(.12, .3, 300); s.tone(210, .15, "square", .2, 0, 110)
		"boost": s.nz(.28, .24, 880); s.tone(140, .2, "sawtooth", .12, 0, 300)
		"cough": s.nz(.09, .34, 480); s.nz(.1, .3, 420, .13)
		"dizzy": s.tone(440, .5, "sine", .14, 0, 330); s.tone(452, .5, "sine", .12, .05, 320)
		"heal": s.tone(520, .12, "sine", .13, 0, 700); s.tone(760, .16, "sine", .11, .1)
		"drop": s.tone(500, .08, "square", .12, 0, 300)
		"dance":
			for i in 5: s.tone([392, 494, 587, 494, 659][i], .13, "square", .13, i * .09)
		"sass": s.tone(1300, .07, "square", .1, 0, 900); s.tone(900, .09, "square", .1, .09, 600)
		"boo": s.tone(320, .8, "sine", .16, 0, 85); s.tone(480, .7, "sine", .08, .1, 120)
		"rev": s.tone(62, .5, "sawtooth", .3, 0, 190); s.nz(.4, .2, 240)
		"clack":
			for i in 4: s.nz(.03, .22, 2600, i * .05)
		"cash": s.tone(1250, .08, "square", .15); s.tone(1650, .14, "square", .13, .08); s.nz(.1, .1, 3400, .05)
		"karen":
			for i in 3:
				var f: float = [660, 520, 392][i]; s.tone(f, .16, "sawtooth", .16, i * .12, f * .8)
		"blah":
			for i in 5: s.tone(s.r(200, 340), .05, "square", .09, i * .07)
		"drum": s.tone(95, .25, "sine", .35, 0, 60); s.tone(140, .2, "sine", .25, .12, 90); s.nz(.08, .15, 300)
		"thud": s.nz(.15, .4, 180); s.tone(70, .2, "sine", .3, 0, 45)
		"coin": s.tone(1400, .07, "square", .12); s.tone(1900, .12, "square", .1, .06)
		"sting": s.tone(2200, .06, "square", .1, 0, 2900); s.nz(.06, .14, 2600)
		"woosh2": s.nz(.35, .2, 700); s.tone(500, .3, "sine", .1, 0, 900)
		"cackle":
			for i in 4:
				var f: float = [880, 760, 980, 700][i]; s.tone(f, .09, "square", .11, i * .08, f * .75)
		"rattle":
			for i in 5: s.nz(.035, .22, 1700 + i * 260, i * .045)
		"moan": s.tone(88, .9, "sine", .2, 0, 58); s.tone(132, .7, "sawtooth", .08, .1, 90)
		"honk": s.tone(420, .28, "square", .26); s.tone(330, .3, "square", .22, .05)
		"arrow": s.nz(.14, .18, 1500); s.tone(900, .12, "sine", .08, 0, 400)
		"coinflip": s.tone(1500, .06, "sine", .12, 0, 2100); s.tone(1900, .07, "sine", .1, .09, 2600); s.tone(1200, .1, "sine", .1, .2, 1700)
		"divine":
			for i in 5: s.tone([523, 659, 784, 1047, 1319][i], .5, "sine", .09, i * .07)
		"stink": s.nz(.5, .12, 220); s.tone(70, .5, "sawtooth", .1, 0, 50)
		"firework":
			s.tone(300, .45, "sine", .07, 0, 1500); s.nz(.28, .3, 1600, .45); s.nz(.2, .18, 700, .5)
			for i in 5: s.tone(s.r(900, 2200), .1, "triangle", .05, .48 + i * .05, s.r(400, 900))
		"zap":
			for i in 7: s.nz(.035, .26, s.r(1800, 5200), i * .028)
			s.tone(90, .22, "sawtooth", .2, 0, 42); s.tone(1400, .14, "square", .09, 0, 300)
		"levelup":
			for i in 6: s.tone([523, 659, 784, 1047, 1319, 1568][i], .3, "triangle", .16, i * .08)
			s.tone(65, .7, "sawtooth", .24, .1, 50)
		# --- moving about ---
		"step": s.nz(.045, .17, s.r(1700, 2300)); s.tone(110, .035, "sine", .1, 0, 70)
		"step_sand": s.nz(.08, .15, s.r(800, 1000)); s.nz(.04, .06, 2600, .02)
		"step_grass": s.nz(.06, .12, s.r(3000, 3600)); s.nz(.04, .07, 1200, .015)
		"step_wood": s.tone(230, .05, "triangle", .13, 0, 140); s.nz(.03, .1, 1300)
		"step_water": s.nz(.09, .16, 700); s.nz(.06, .1, 2400, .03); s.tone(420, .06, "sine", .05, .02, 260)
		"jump": s.tone(260, .12, "square", .07, 0, 520); s.nz(.08, .1, 1800)
		"land": s.nz(.08, .22, 260); s.tone(80, .1, "sine", .18, 0, 50)
		"land_hard": s.nz(.15, .4, 180); s.tone(70, .2, "sine", .3, 0, 45); s.nz(.08, .12, 1400, .02)
		"roll": s.nz(.22, .2, 500); s.nz(.12, .1, 1200, .08); s.tone(120, .1, "sine", .1, .18, 70)
		"winded": s.nz(.25, .12, 600); s.nz(.3, .1, 520, .35)
		"heartbeat": s.tone(55, .12, "sine", .32, 0, 45); s.tone(55, .12, "sine", .24, .18, 45)
		# --- fighting ---
		"swing_light": s.nz(.11, .22, s.r(1600, 2000)); s.tone(700, .08, "sine", .04, 0, 300)
		"swing_heavy": s.nz(.26, .26, 650); s.tone(180, .24, "sawtooth", .08, 0, 85); s.nz(.1, .12, 1500, .1)
		"combo_end": s.nz(.18, .2, 1100); s.tone(1568, .12, "triangle", .07, .04); s.tone(2093, .16, "triangle", .05, .09)
		"hit": s.nz(.06, .32, s.r(1000, 1400)); s.tone(180, .08, "square", .18, 0, 80); s.tone(1200, .03, "square", .06)
		"hit_heavy": s.nz(.14, .42, 500); s.tone(110, .18, "sawtooth", .26, 0, 45); s.nz(.05, .25, 2500)
		"crit":
			s.nz(.14, .42, 500); s.tone(110, .18, "sawtooth", .26, 0, 45); s.nz(.05, .25, 2500)
			s.tone(1760, .18, "triangle", .12, .02); s.tone(2637, .24, "triangle", .08, .06)
		"parry":
			s.nz(.05, .3, 4000); s.tone(1568, .35, "triangle", .18); s.tone(2093, .42, "triangle", .12, .01); s.tone(3136, .3, "sine", .06, .02)
		"block": s.nz(.07, .3, 900); s.tone(330, .09, "square", .12, 0, 220); s.tone(90, .08, "sine", .12, 0, 60)
		"faint": s.tone(440, .9, "triangle", .14, 0, 110); s.tone(330, 1.1, "sine", .12, .2, 80); s.tone(452, .5, "sine", .08, .05, 320)
		"respawn":
			for i in 4: s.tone([392, 523, 659, 784][i], .3, "sine", .1, i * .09)
			s.tone(520, .12, "sine", .1, .4, 700); s.tone(760, .2, "sine", .09, .5)
		"enemy_hurt": s.tone(s.r(480, 560), .1, "square", .12, 0, 300); s.nz(.05, .15, 1500)
		"enemy_die": s.tone(400, .35, "sawtooth", .14, 0, 70); s.nz(.25, .22, 600); s.tone(1200, .08, "square", .06, 0, 400)
		"boss_die":
			s.nz(.8, .45, 160); s.nz(.4, .3, 900); s.tone(60, .9, "sine", .4, 0, 28); s.tone(300, 1.2, "sawtooth", .14, 0, 40)
			for i in 4: s.tone([523, 659, 784, 1047][i], .4, "triangle", .12, .9 + i * .12)
		"growl": s.tone(90, .45, "sawtooth", .16, 0, 70); s.tone(135, .4, "square", .06, .02, 95); s.nz(.4, .08, 400)
		"tell": s.tone(300, .42, "square", .07, 0, 900); s.tone(303, .42, "sawtooth", .05, 0, 906); s.nz(.1, .06, 3000, .32)
		"charge": s.tone(62, .6, "sawtooth", .26, 0, 160); s.nz(.5, .2, 300); s.tone(124, .5, "square", .06, .1, 260)
		"shoot": s.tone(900, .12, "square", .1, 0, 250); s.nz(.06, .2, 2200)
		"magic":
			s.tone(440, .3, "triangle", .08, 0, 880)
			for i in 3: s.tone([880, 1175, 1568][i], .25, "sine", .08, .05 + i * .06)
		"explosion": s.nz(.6, .5, 160); s.nz(.3, .35, 900); s.tone(60, .5, "sine", .4, 0, 30); s.tone(140, .3, "sawtooth", .15, 0, 40)
		"lock_on": s.tone(1760, .04, "square", .06); s.tone(2349, .06, "square", .05, .05)
		"lock_off": s.tone(1760, .05, "square", .05, 0, 1100)
		"empty_click": s.tone(2400, .02, "square", .08); s.tone(1200, .03, "square", .05, .04)
		# --- skills ---
		"cast":
			s.tone(440, .3, "triangle", .08, 0, 880)
			for i in 3: s.tone([880, 1175, 1568][i], .25, "sine", .08, .05 + i * .06)
		"cast_fire": s.nz(.45, .32, 700); s.tone(200, .4, "sawtooth", .12, 0, 90); s.nz(.2, .15, 2000, .05)
		"cast_ice":
			s.nz(.22, .14, 5000)
			for i in 3: s.tone([2093, 2637, 3136][i], .12, "triangle", .08, i * .05)
		"cast_shock":
			for i in 7: s.nz(.035, .26, s.r(1800, 5200), i * .028)
			s.tone(90, .22, "sawtooth", .2, 0, 42); s.tone(1400, .14, "square", .09, 0, 300)
		"cast_heal":
			s.tone(520, .12, "sine", .13, 0, 700); s.tone(760, .16, "sine", .11, .1)
			for i in 3: s.tone([784, 988, 1175][i], .3, "sine", .07, .18 + i * .07)
		"cast_buff":
			for i in 3: s.tone([523, 784, 1047][i], .12, "square", .08, i * .06)
		"cast_dash": s.nz(.18, .25, 1500); s.tone(400, .15, "sine", .08, 0, 1200)
		"cast_nova":
			s.nz(.4, .35, 400); s.tone(80, .4, "sine", .3, 0, 40)
			for i in 3: s.tone([880, 1175, 1568][i], .3, "sine", .07, .08 + i * .06)
		# --- pickups / world ---
		"pickup": s.tone(880, .06, "square", .1); s.tone(1320, .1, "square", .09, .05)
		"gear_drop": s.tone(500, .08, "square", .12, 0, 300); s.tone(1047, .2, "triangle", .1, .1); s.tone(1568, .25, "triangle", .08, .16)
		"nazar":                                   # glassy chime for the 50 beads
			s.tone(1568, .5, "sine", .12); s.tone(2349, .6, "sine", .08, .04); s.tone(3136, .4, "sine", .05, .08); s.tone(1047, .7, "triangle", .06)
		"eat":
			for i in 3: s.nz(.05, .2, s.r(1000, 1400), i * .11)
			s.tone(300, .06, "sine", .1, .34, 520)
		"drink": s.tone(400, .07, "sine", .1, 0, 650); s.tone(420, .07, "sine", .09, .12, 680); s.tone(380, .1, "sine", .08, .24, 700)
		"chest_open":
			s.tone(180, .3, "sawtooth", .07, 0, 260); s.nz(.08, .25, 900, .28)
			for i in 3: s.tone([1319, 1568, 2093][i], .3, "sine", .08, .34 + i * .07)
		"door": s.tone(140, .28, "sawtooth", .08, 0, 210); s.nz(.15, .35, 180, .26); s.tone(70, .2, "sine", .25, .26, 45)
		"splash": s.nz(.3, .3, 900); s.nz(.2, .2, 2500, .05); s.tone(300, .1, "sine", .08, 0, 120)
		"pedal": s.nz(.03, .08, 3000); s.tone(140, .03, "sine", .05)
		"crash": s.nz(.15, .4, 180); s.tone(70, .2, "sine", .3, 0, 45); s.nz(.3, .3, 1200, .02); s.nz(.04, .2, 2600, .1); s.nz(.04, .18, 2600, .16)
		"photo": s.nz(.03, .25, 3500); s.tone(2000, .03, "square", .06, .02); s.nz(.08, .12, 900, .06)
		"meow": s.tone(620, .14, "sawtooth", .07, 0, 1050); s.tone(1050, .22, "triangle", .09, .12, 560); s.tone(1240, .2, "sine", .03, .12, 700)
		"drift": s.nz(.55, .12, 2600, 0, 0, 4.0); s.tone(1750, .5, "square", .025, 0, 1500)
		# --- her body: ledges, guard, dodges ---
		"climb": s.nz(.12, .18, 700); s.tone(170, .1, "square", .06, .02, 240); s.nz(.06, .1, 2000, .14)
		"grab": s.nz(.05, .26, 420); s.tone(150, .06, "square", .1, 0, 95)
		"dodge": s.nz(.2, .2, 1300); s.tone(1568, .25, "sine", .06, .05, 2349); s.tone(2093, .2, "triangle", .04, .1)
		"shield": s.tone(523, .25, "triangle", .07, 0, 1047); s.tone(784, .3, "sine", .06, .05); s.nz(.15, .06, 5000, .05)
		"guard_break":
			s.nz(.07, .35, 3800); s.nz(.2, .25, 900, .02); s.tone(90, .25, "sawtooth", .2, 0, 45)
			for i in 4: s.tone(s.r(2400, 3600), .06, "triangle", .06, .03 + i * .04, s.r(1500, 2200))
		"break": s.nz(.05, .4, 2400); s.tone(600, .12, "square", .1, 0, 140); s.nz(.18, .2, 400, .03)
		"charge_full": s.tone(1568, .08, "square", .07); s.tone(2093, .14, "triangle", .1, .06); s.nz(.08, .05, 6000, .06)
		"dash": s.nz(.2, .26, 1100); s.tone(300, .16, "sawtooth", .06, 0, 700)
		"slam": s.nz(.5, .45, 150); s.tone(55, .5, "sine", .42, 0, 30); s.nz(.2, .25, 900, .02); s.tone(120, .25, "sawtooth", .12, 0, 40)
		# --- monsters ---
		"enemy_notice": s.tone(660, .07, "square", .09); s.tone(990, .16, "square", .08, .07, 1050)       # the "!" sting
		"enemy_swing": s.nz(.16, .2, 800); s.tone(240, .12, "sawtooth", .05, 0, 110)
		# --- story / UI ---
		"level_up":                                # 7.2 levelUp(): levelup + fanfare + chuckle together
			for i in 6: s.tone([523, 659, 784, 1047, 1319, 1568][i], .3, "triangle", .16, i * .08)
			s.tone(65, .7, "sawtooth", .24, .1, 50)
			for i in 4: s.tone([523, 659, 784, 1047][i], .22, "triangle", .14, .5 + i * .11)
			s.tone(830, .09, "sine", .12, .95, 1150); s.tone(1100, .13, "sine", .1, 1.06, 720)
		"quest_start":
			for i in 3: s.tone([523, 659, 784][i], .1, "square", .08, i * .08)
			s.tone(1318, .09, "triangle", .14, .26); s.tone(1760, .16, "triangle", .11, .33)
		"quest_done":
			for i in 4: s.tone([659, 784, 988, 1319][i], .2, "triangle", .15, i * .09)
		"mission_start":
			s.tone(110, .6, "sawtooth", .18, 0, 108); s.nz(.5, .15, 4500, 0, 2)
			for i in 3: s.tone([440, 523, 659][i], .35, "triangle", .12, .05 + i * .04)
		"mission_done":
			for i in 4: s.tone([523, 659, 784, 1047][i], .22, "triangle", .18, i * .11)
			for f in [1047, 1319, 1568]: s.tone(f, .9, "triangle", .1, .5)
			for i in 5: s.tone([523, 659, 784, 1047, 1319][i], .5, "sine", .06, .55 + i * .07)
			s.tone(65, .9, "sawtooth", .2, .5, 55)
		"menu_move": s.tone(1200, .035, "square", .06)
		"menu_select": s.tone(880, .05, "square", .08); s.tone(1320, .08, "square", .07, .05)
		"menu_back": s.tone(660, .07, "square", .07, 0, 440)
		"ui_open": s.tone(520, .09, "triangle", .09, 0, 1040)
		"ui_close": s.tone(1040, .09, "triangle", .08, 0, 520)
		"ui_toast": s.tone(1047, .06, "triangle", .08); s.tone(1568, .1, "triangle", .06, .06)

# the synth: 7.2's tone() (an oscillator with exponential pitch + volume ramps) and nz() (filtered noise
# burst), plus pads, filtered plucks, leads and a feedback delay for the music. Naive waveforms on purpose:
# the aliasing at 22 kHz is the PS1 crunch.
class Syn:
	const SR := 22050
	const FORMANT := {"a": [730, 1090], "e": [530, 1840], "ı": [300, 1390], "i": [270, 2290],
		"o": [570, 840], "ö": [440, 1690], "u": [300, 870], "ü": [300, 1650]}
	var b := PackedFloat32Array()          # the mix
	var p := PackedFloat32Array()          # pads, filtered once at the end (flush_pad)
	var s := PackedFloat32Array()          # delay send
	var n := 0
	var wrap := false                      # a loop: tails wrap round to the start
	var tgt := 0                           # 0 = mix, 1 = pad buffer
	var send := 0.0
	var rng := RandomNumberGenerator.new()

	func begin(sec: float, loop := false) -> void:
		n = maxi(1, int(sec * SR)); b = PackedFloat32Array(); b.resize(n); b.fill(0.0)
		p = PackedFloat32Array(); s = PackedFloat32Array(); wrap = loop; tgt = 0; send = 0.0; rng.randomize()

	func use_send() -> void:
		s.resize(n); s.fill(0.0)

	func r(a: float, c: float) -> float: return rng.randf_range(a, c)

	static func _code(type: String) -> int:
		match type:
			"sine": return 0
			"square": return 1
			"sawtooth": return 2
		return 3

	static func _bq(kind: int, f: float, q: float) -> PackedFloat32Array:
		f = clampf(f, 20.0, SR * .45)
		var w0 := TAU * f / SR; var cs := cos(w0); var al := sin(w0) / (2.0 * q)
		var b0 := 1.0; var b1 := 0.0; var b2 := 0.0
		if kind == 0: b0 = al; b1 = 0.0; b2 = -al
		elif kind == 1: b0 = (1.0 - cs) / 2.0; b1 = 1.0 - cs; b2 = b0
		elif kind == 2: b0 = (1.0 + cs) / 2.0; b1 = -(1.0 + cs); b2 = b0
		else: return PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])
		var a0 := 1.0 + al
		return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, -2.0 * cs / a0, (1.0 - al) / a0])

	func _put(i: int, x: float) -> void:
		if tgt == 1:
			if p.size() != n: p.resize(n); p.fill(0.0)
			p[i] += x
		else: b[i] += x
		if send > 0.0: s[i] += x * send

	# 7.2 tone(f, d, type, v, dl, f2)
	func tone(f: float, d: float, type := "square", v := .2, dl := 0.0, f2 := 0.0) -> void:
		var len := int(d * SR)
		if len <= 0 or f <= 0.0: return
		var i0 := int(dl * SR)
		v = maxf(v, .0012)
		var g := v; var gk := pow(.001 / v, 1.0 / len)
		var fr := f; var fk := 1.0
		if f2 > 0.0: fk = pow(maxf(20.0, f2) / f, 1.0 / len)
		var w := _code(type); var ph := 0.0
		var direct := tgt == 0 and send <= 0.0
		for k in len:
			var i := i0 + k
			if i >= n:
				if not wrap: break
				i = i % n
			var x: float
			if w == 0: x = sin(TAU * ph)
			elif w == 1: x = 1.0 if ph < .5 else -1.0
			elif w == 2: x = 2.0 * ph - 1.0
			else: x = 4.0 * absf(ph - .5) - 1.0
			x *= g
			if k < 30: x *= k / 30.0
			if direct: b[i] += x
			else: _put(i, x)
			g *= gk; ph += fr / SR; fr *= fk
			if ph >= 1.0: ph -= 1.0

	# 7.2 nz(d, v, fq, dl): white noise through a biquad (0 band / 1 low / 2 high)
	func nz(d: float, v := .2, fq := 1000.0, dl := 0.0, kind := 0, q := .9) -> void:
		var len := int(d * SR)
		if len <= 0: return
		var i0 := int(dl * SR)
		v = maxf(v, .0012)
		var g := v * .8; var gk := pow(.001 / v, 1.0 / len)
		var c := _bq(kind, fq, q)
		var b0 := c[0]; var b1 := c[1]; var b2 := c[2]; var a1 := c[3]; var a2 := c[4]
		var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
		var direct := tgt == 0 and send <= 0.0
		for k in len:
			var i := i0 + k
			if i >= n:
				if not wrap: break
				i = i % n
			var x := rng.randf() * 2.0 - 1.0
			var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
			x2 = x1; x1 = x; y2 = y1; y1 = y
			if direct: b[i] += y * g
			else: _put(i, y * g)
			g *= gk

	# a held chord note: linear in to v over att, linear out to nothing at rel (7.2's pads). cents = detune
	func pad(t0: float, f: float, type: String, v: float, att: float, rel: float, cents := 0.0) -> void:
		var len := int(rel * SR); var i0 := int(t0 * SR); var ai := maxi(1, int(att * SR))
		var fr := f * pow(2.0, cents / 1200.0) / SR; var w := _code(type); var ph := rng.randf()
		for k in len:
			var i := i0 + k
			if i >= n:
				if not wrap: break
				i = i % n
			var e := v * k / ai if k < ai else v * (1.0 - float(k - ai) / maxf(1.0, len - ai))
			var x: float
			if w == 0: x = sin(TAU * ph)
			elif w == 1: x = 1.0 if ph < .5 else -1.0
			elif w == 2: x = 2.0 * ph - 1.0
			else: x = 4.0 * absf(ph - .5) - 1.0
			_put(i, x * e)
			ph += fr
			if ph >= 1.0: ph -= 1.0

	# all the pads through one lowpass, into the mix
	func flush_pad(lp: float) -> void:
		if p.size() != n: return
		var c := _bq(1, lp, .707)
		var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
		for pass_i in (2 if wrap else 1):                       # a loop runs twice so the filter is settled at the seam
			for i in n:
				var x := p[i]
				var y := c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
				x2 = x1; x1 = x; y2 = y1; y1 = y
				if pass_i == (1 if wrap else 0): b[i] += y

	# the intro's bass: a saw through a resonant lowpass that snaps shut (lp0 -> lp1)
	func pluck(t0: float, f: float, type: String, v: float, d: float, lp0: float, lp1: float, q := .707) -> void:
		var len := int(d * SR); var i0 := int(t0 * SR)
		var g := v; var gk := pow(.0005 / v, 1.0 / len)
		var w := _code(type); var ph := 0.0; var fr := f / SR
		var cf := lp0; var ck := pow(lp1 / lp0, 1.0 / maxf(1.0, (d - .02) * SR))
		var c := _bq(1, cf, q)
		var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
		for k in len:
			var i := i0 + k
			if i >= n:
				if not wrap: break
				i = i % n
			if k % 16 == 0: c = _bq(1, cf, q)
			var x: float
			if w == 0: x = sin(TAU * ph)
			elif w == 1: x = 1.0 if ph < .5 else -1.0
			elif w == 2: x = 2.0 * ph - 1.0
			else: x = 4.0 * absf(ph - .5) - 1.0
			var y := c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
			x2 = x1; x1 = x; y2 = y1; y1 = y
			_put(i, y * g)
			g *= gk; cf = maxf(lp1, cf * ck); ph += fr
			if ph >= 1.0: ph -= 1.0

	# IMLEAD notes: saw + triangle, a slow upward detune, lowpass 2800, gated
	func lead(t0: float, f: float, d: float, gain := 1.0) -> void:
		for pair in [[2, .03], [3, .04]]:
			var w: int = pair[0]; var v: float = pair[1] * gain
			var len := int((d + .12) * SR); var i0 := int(t0 * SR)
			var c := _bq(1, 2800.0, .707)
			var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
			var ph := 0.0; var a_i := int(.03 * SR); var h_i := int(d * .8 * SR)
			var gk := pow(.0005 / v, 1.0 / maxf(1.0, len - h_i)); var g := v
			for k in len:
				var i := i0 + k
				if i >= n:
					if not wrap: break
					i = i % n
				var cents := 14.0 * minf(1.0, float(k) / maxf(1.0, d * SR))
				ph += f * pow(2.0, cents / 1200.0) / SR
				if ph >= 1.0: ph -= 1.0
				var x := 2.0 * ph - 1.0 if w == 2 else 4.0 * absf(ph - .5) - 1.0
				var e := v * k / a_i if k < a_i else (v if k < h_i else g)
				if k >= h_i: g *= gk
				var y := c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
				x2 = x1; x1 = x; y2 = y1; y1 = y
				_put(i, y * e)

	# 7.2's IM.dl: delay `time`, feedback fb, wet level — fed from the send buffer
	func delay(time: float, fb: float, wet: float) -> void:
		if s.size() != n: return
		var D := int(time * SR)
		var dl := PackedFloat32Array(); dl.resize(n); dl.fill(0.0)
		for pass_i in (3 if wrap else 1):
			for i in n:
				var j := i - D
				var into := 0.0; var prev := 0.0
				if j >= 0: into = s[j]; prev = dl[j]
				elif wrap: into = s[j + n]; prev = dl[j + n]
				dl[i] = into + fb * prev
		for i in n: b[i] += wet * dl[i]

	# 7.2 babble(): a vowel-tracking voice — buzz + two formants per syllable, a click between
	func babble(txt: String, pitch: float, rate: float, vol := 1.0) -> void:
		var vows := []
		for ch in txt.to_lower():
			if "aeıioöuü".contains(ch): vows.append(ch)
		if vows.is_empty(): vows = ["a", "a"]
		var syl := clampi(vows.size(), 2, 9)
		var base := 105.0 * pitch; var step := .125 / rate
		for i in syl:
			var F: Array = FORMANT.get(vows[i % vows.size()], FORMANT["a"])
			var t0 := i * step
			var f0 := base * r(.94, 1.08) * (.88 if i == syl - 1 else 1.0)
			tone(f0, .09 / rate, "sawtooth", .075 * vol, t0, f0 * .82)
			tone(F[0] * pitch * .5 + f0, .085 / rate, "triangle", .055 * vol, t0, F[0] * pitch * .42 + f0)
			tone(F[1] * pitch * .42, .06 / rate, "sine", .028 * vol, t0 + .012, F[1] * pitch * .36)
			if i < syl - 1: nz(.022, .05 * vol, 2200, t0 + step * .72)

	# a loop with an intro: everything past `le` folds back onto the start of the loop
	func fold(lb: int, le: int) -> void:
		for i in range(le, n):
			b[lb + (i - le) % (le - lb)] += b[i]
		n = le; b.resize(n)

	func trim() -> void:
		var last := n - 1
		while last > 0 and absf(b[last]) < .0004: last -= 1
		n = mini(n, last + 64); b.resize(n)

	# to 16-bit PCM with a soft knee instead of hard clipping
	func to_wav(gain := 1.0, lb := -1, le := -1) -> AudioStreamWAV:
		var bytes := PackedByteArray(); bytes.resize(n * 2)
		for i in n:
			var x := b[i] * gain
			var ax := absf(x)
			if ax > .7: x = signf(x) * (.7 + .3 * tanh((ax - .7) / .3))
			bytes.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = SR; w.stereo = false; w.data = bytes
		if lb >= 0:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_begin = lb; w.loop_end = le
		return w
