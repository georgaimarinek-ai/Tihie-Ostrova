class_name IslandView
extends Node3D
## One island near the viewer (docs/04_TECH_SPEC.md §8): flat-shaded terrain, a HeightMapShape3D built from
## the same heightfield as the mesh, resource nodes as MultiMeshes (one per shape and part), colliders for
## trunks and rocks. Nodes that WorldState.depleted marks as gathered hide (trees leave a stump) and come
## back when they respawn. Only a view: gathering goes through Game.submit({"type": "gather"}).

const TERRAIN_SHADER := preload("res://src/shaders/terrain.gdshader")
const STEP := 2.5
const FAR_STEP := 8.0
const TREE_SHAPES: Array[String] = ["pine", "birch", "larch"]

var isl: IslandGen
var map: WorldMap
var nodes: Array = []
## Solid circles for the camera and walking: [{"pos": Vector2, "r": float, "id": String}]
var solids: Array = []

var _slots: Dictionary = {}  # node id -> [[MultiMesh, index, Transform3D], ...]
var _stumps: MultiMesh
var _stump_index: Dictionary = {}  # node id -> index in _stumps
var _colliders: Dictionary = {}  # node id -> CollisionShape3D
var _hidden: Dictionary = {}  # node id -> true while depleted


## Heavy part, safe on a worker thread: heightfield and terrain arrays.
static func prepare(p_isl: IslandGen, step: float = STEP) -> Dictionary:
	var hf := p_isl.heightfield(step)
	return {"hf": hf, "arrays": p_isl.mesh_arrays(hf)}


func setup(p_map: WorldMap, p_isl: IslandGen, data: Dictionary) -> void:
	map = p_map
	isl = p_isl
	name = "Island_" + isl.id
	nodes = map.nodes(isl.id)
	var land := MeshInstance3D.new()
	land.name = "Terrain"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	land.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	land.material_override = m
	add_child(land)
	_build_collision(data["hf"])
	_build_nodes()


func _build_collision(hf: Dictionary) -> void:
	var n: int = hf["n"]
	var step: float = hf["step"]
	var origin: Vector2 = hf["origin"]
	var heights: PackedFloat32Array = hf["heights"]
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / step
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = scaled
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * step
	var half := (n - 1) * step * 0.5
	cs.position = Vector3(origin.x + half, 0.0, origin.y + half)
	body.add_child(cs)
	add_child(body)


func _build_nodes() -> void:
	var by_shape := {}
	for nd: Dictionary in nodes:
		var shape: String = nd["shape"]
		if not by_shape.has(shape):
			by_shape[shape] = []
		(by_shape[shape] as Array).append(nd)
	var solids_body := StaticBody3D.new()
	solids_body.name = "Solids"
	solids_body.collision_layer = 1
	solids_body.collision_mask = 0
	add_child(solids_body)
	var rng := RandomNumberGenerator.new()
	rng.seed = isl.island_seed + 99
	var trees: Array = []
	for shape: String in by_shape:
		var list: Array = by_shape[shape]
		var parts := Placeholders.node_parts(shape)
		var xforms: Array[Transform3D] = []
		var tints: Array[Color] = []
		for nd: Dictionary in list:
			var sc: float = nd["scale"]
			var basis := Basis(Vector3.UP, float(nd["yaw"])).scaled(Vector3.ONE * sc)
			var sink := 0.2 if shape in TREE_SHAPES else 0.05
			xforms.append(Transform3D(basis, (nd["pos"] as Vector3) + Vector3(0, -sink, 0)))
			tints.append(_tint(shape, rng))
			if float(nd["solid"]) > 0.0:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = float(nd["solid"])
				cyl.height = 4.0
				cs.shape = cyl
				cs.position = (nd["pos"] as Vector3) + Vector3(0, 1.6, 0)
				solids_body.add_child(cs)
				_colliders[nd["id"]] = cs
				var p: Vector3 = nd["pos"]
				solids.append({"pos": Vector2(p.x, p.z), "r": float(nd["solid"]), "id": nd["id"], "crown": sc * (3.2 if shape in TREE_SHAPES else 1.0)})
			if shape in TREE_SHAPES:
				trees.append(nd)
		for part: Array in parts:
			var mm := _multimesh(part[0], xforms, tints if part[1] else [])
			for i in list.size():
				var id: String = list[i]["id"]
				if not _slots.has(id):
					_slots[id] = []
				(_slots[id] as Array).append([mm, i, xforms[i]])
	# stumps wait (invisible) under every tree
	if not trees.is_empty():
		var sx: Array[Transform3D] = []
		for i in trees.size():
			var nd: Dictionary = trees[i]
			_stump_index[nd["id"]] = i
			sx.append(Transform3D(Basis().scaled(Vector3.ZERO), nd["pos"]))
		_stumps = _multimesh(Placeholders.node_parts("stump")[0][0], sx, [])


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], tints: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	add_child(mmi)
	return mm


## Colour variety like the sketch: golden and green birch crowns, dark pines, larches turning gold.
func _tint(shape: String, rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	var c := Color.WHITE
	match shape:
		"pine":
			c = Color("2f4a3a")
		"birch":
			c = Color("c9a24a") if r < 0.25 else (Color("9fb35a") if r < 0.62 else Color("88a24c"))
		"larch":
			c = Color("c8a050") if r < 0.5 else Color("7a8f4a")
		"rock":
			c = Color(0.95, 0.96, 0.97)
	var v := (rng.randf() - 0.5) * 0.08
	return c.lightened(v) if v > 0.0 else c.darkened(-v)


## Hide gathered nodes and bring back respawned ones, from WorldState.depleted.
func refresh(state: WorldState) -> void:
	for id: String in _slots:
		var gone := int(state.depleted.get(id, 0)) > state.day
		if gone == _hidden.has(id):
			continue
		if gone:
			_hidden[id] = true
		else:
			_hidden.erase(id)
		for slot: Array in _slots[id]:
			var mm: MultiMesh = slot[0]
			var xf: Transform3D = slot[2]
			mm.set_instance_transform(int(slot[1]), Transform3D(Basis().scaled(Vector3.ZERO), xf.origin) if gone else xf)
		if _stump_index.has(id):
			var nd: Dictionary = map.node(id)
			var sc := float(nd.get("scale", 1.0))
			var xf := Transform3D(Basis(Vector3.UP, float(nd.get("yaw", 0.0))).scaled(Vector3.ONE * sc), nd["pos"]) if gone else Transform3D(Basis().scaled(Vector3.ZERO), nd["pos"])
			_stumps.set_instance_transform(int(_stump_index[id]), xf)
		elif _colliders.has(id):
			(_colliders[id] as CollisionShape3D).disabled = gone


func is_hidden(id: String) -> bool:
	return _hidden.has(id)


## Far silhouette: a coarse mesh and every third tree, no collision (worker-thread data from prepare()).
static func silhouette(p_map: WorldMap, p_isl: IslandGen, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Far_" + p_isl.id
	var land := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	land.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	land.material_override = m
	root.add_child(land)
	var xforms: Array[Transform3D] = []
	var i := 0
	for nd: Dictionary in p_map.nodes(p_isl.id):
		if nd["shape"] in TREE_SHAPES:
			i += 1
			if i % 3 == 0:
				xforms.append(Transform3D(Basis().scaled(Vector3.ONE * float(nd["scale"]) * 1.15), (nd["pos"] as Vector3) - Vector3(0, 0.2, 0)))
	if not xforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Placeholders.node_parts("pine")[1][0]
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k])
			mm.set_instance_color(k, Color("2f4a3a"))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
		root.add_child(mmi)
	return root
