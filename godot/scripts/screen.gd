# The real size of the UI canvas (widescreen, 8.2). Every screen was first laid out on a 960x720 (4:3) canvas.
# project.godot uses stretch aspect "expand": a wider window makes the canvas wider (16:10 → 1152x720,
# 16:9 → 1280x720, 21:9 → about 1680x720), and a taller one makes it taller. Nothing is cut off or squashed.
# Corner things anchor to the real edges, centred things to the real centre:
#   Screen.size() / w() / h()  the canvas right now
#   Screen.dx()                add to an x laid out on the 960 canvas to keep a block centred (0 at 4:3)
#   Screen.right(x)            an x measured on the 960 canvas, moved so it keeps its distance to the RIGHT edge
#   Screen.dy() / bottom(y)    the same for height (0 unless the window is taller than 4:3)
# When the window changes size, main emits Bus "screen" {size}; anything that places itself once listens to it.
class_name Screen
extends RefCounted

const BASE := Vector2(960, 720)

static func size() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return BASE
	return tree.root.get_visible_rect().size

static func w() -> float: return size().x
static func h() -> float: return size().y
static func dx() -> float: return (w() - BASE.x) / 2.0
static func dy() -> float: return (h() - BASE.y) / 2.0
static func right(x: float) -> float: return x + (w() - BASE.x)
static func bottom(y: float) -> float: return y + (h() - BASE.y)
