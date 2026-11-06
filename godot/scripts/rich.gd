# 7.2's text is HTML (<b>, <i>, <br>); the Godot port shows BBCode ([b], [i]). Helpers to move between
# the two, and to compare texts with every tag stripped (keys built by 7.2 and by Godot must match).
class_name Rich
extends RefCounted

static var _bb: RegEx
static var _html: RegEx

static func _res() -> void:
	if _bb: return
	_bb = RegEx.new(); _bb.compile("\\[/?[a-z_]+(=[^\\]]*)?\\]")
	_html = RegEx.new(); _html.compile("<[^>]*>")

static func to_html(s: String) -> String:
	_res()
	# the blank in a fill-in question, exactly as 7.2's buildSession writes it (so the keys match)
	s = s.replace("[b][color=#7bf7ff]___[/color][/b]", "<b style=\"color:#7bf7ff\">___</b>")
	s = s.replace("[b]", "<b>").replace("[/b]", "</b>").replace("[i]", "<i>").replace("[/i]", "</i>").replace("\n", "<br>")
	return _bb.sub(s, "", true)

static func to_bb(s: String) -> String:
	_res()
	s = s.replace("<b>", "[b]").replace("</b>", "[/b]").replace("<i>", "[i]").replace("</i>", "[/i]")
	s = s.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	return _html.sub(s, "", true)

# no markup at all (button labels, key comparisons)
static func plain(s: String) -> String:
	_res()
	return " ".join(_html.sub(_bb.sub(s, "", true), "", true).split(" ", false)).strip_edges()
