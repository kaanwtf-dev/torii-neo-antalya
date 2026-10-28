# Models exported from 7.2 carry the game's vertex-colour tints (Bandit's black fur, imp red, the city's
# colours) and its PS1 pixels: switch both on for every material under a node.
class_name Tint
extends RefCounted

static func apply(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m = n.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				m.vertex_color_use_as_albedo = true
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for c in n.get_children(): apply(c)
