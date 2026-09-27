class_name ModelLibrary
extends RefCounted
## The artist's models, or placeholders when a file is missing (docs/05_ART_AUDIO.md §4):
##   ModelLibrary.instance("boats", "karbas")  ->  res://art/models/boats/karbas.glb  or  Placeholders.boat()
## Game code never depends on whether a model exists. Materials from Blender are replaced by the fog-aware
## prop shader (the palette texture or vertex colours carry the colour); "-glow" objects glow unfogged.

const ROOT := "res://art/models"
const CATEGORIES: Array[String] = ["pieces", "boats", "creatures", "props", "player"]
const PALETTE := "res://art/palette.png"

static var _scenes: Dictionary = {}


static func path_of(category: String, id: String) -> String:
	return "%s/%s/%s.glb" % [ROOT, category, id]


static func has_model(category: String, id: String) -> bool:
	return ResourceLoader.exists(path_of(category, id))


static func instance(category: String, id: String) -> Node3D:
	var path := path_of(category, id)
	if not ResourceLoader.exists(path):
		return Placeholders.build(category, id)
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene: PackedScene = _scenes[path]
	var node := scene.instantiate() as Node3D
	if node == null:
		push_warning("ModelLibrary: %s is not a 3D scene, using the placeholder" % path)
		return Placeholders.build(category, id)
	node.name = id
	apply_materials(node)
	return node


## Every mesh gets the prop shader: palette UVs if the Blender material had a texture, else vertex colours,
## else the material's flat colour. Objects named "*-glow" glow and read through the fog.
static func apply_materials(root: Node) -> void:
	for mi: MeshInstance3D in _meshes(root):
		var glow := mi.name.to_lower().contains("-glow") or mi.name.to_lower().ends_with("_glow")
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si)
			var col := Color(0.6, 0.6, 0.6)
			var tex: Texture2D = null
			if src is BaseMaterial3D:
				col = (src as BaseMaterial3D).albedo_color
				tex = (src as BaseMaterial3D).albedo_texture
			var has_vcol: bool = (mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var m := ShaderMaterial.new()
			m.shader = Placeholders.PROP_SHADER
			m.set_shader_parameter("albedo", col if tex == null and not has_vcol else Color.WHITE)
			m.set_shader_parameter("use_vertex_color", has_vcol and tex == null)
			if tex != null:
				m.set_shader_parameter("use_palette", true)
				m.set_shader_parameter("palette", tex)
			if glow:
				m.set_shader_parameter("emission", col)
				m.set_shader_parameter("emission_energy", 2.5)
				m.set_shader_parameter("fogged", false)
			mi.set_surface_override_material(si, m)


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out


## The AnimationPlayer inside an imported model (null for placeholders).
static func animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var ap := animation_player(c)
		if ap != null:
			return ap
	return null
