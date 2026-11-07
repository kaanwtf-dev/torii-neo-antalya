# Says Turkish words out loud like 7.2's speak(): goes through Audio.speak when Audio is up, else the
# system's Turkish voice if it has one.
class_name Tts
extends RefCounted

static var _voice := ""

static func say(text: String) -> void:
	if Audio.me: Audio.speak(text); return           # audio.gd's speak(): 7.2's any-voice fallback + retries
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH): return
	if _voice == "":
		var v := DisplayServer.tts_get_voices_for_language("tr")
		_voice = v[0] if v.size() else "-"
	if _voice == "-": return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _voice, 50, 1.0, .9)
