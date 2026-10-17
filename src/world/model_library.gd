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


## The model's bounds in its own space: every mesh's AABB merged (an empty AABB when there is no mesh).
## Hitboxes are fitted from this, so the artist's model gets a body of its own size (docs/05_ART_AUDIO.md §4.6).
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(root):
		if mi.mesh == null:
			continue
		var b := (root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() and mi.is_inside_tree() else _local_to(root, mi)) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## A footprint radius and a height for a standing thing (a creature, a prop): half the wider side of the
## bounds, and its top. Placeholders may say so themselves with "radius"/"height" metadata.
static func fit(root: Node3D) -> Dictionary:
	if root.has_meta("radius") and root.has_meta("height"):
		return {"radius": float(root.get_meta("radius")), "height": float(root.get_meta("height"))}
	var b := bounds(root)
	if b.size == Vector3.ZERO:
		return {"radius": 0.5, "height": 1.5}
	return {"radius": maxf(0.2, maxf(b.size.x, b.size.z) * 0.5), "height": maxf(0.3, b.end.y)}


## Whether the imported scene brought its own collision (Blender objects named "*-col", "*-convcol",
## "*-colonly", "*-convcolonly": Godot's importer turns them into bodies). Then code adds none of its own.
static func has_collision(root: Node) -> bool:
	if root is CollisionShape3D or root is CollisionPolygon3D:
		return true
	for c in root.get_children():
		if has_collision(c):
			return true
	return false


## The transform of `node` relative to `root` without needing the tree.
static func _local_to(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The AnimationPlayer inside an imported model (null for placeholders).
static func animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var ap := animation_player(c)
		if ap != null:
			return ap
	return null
