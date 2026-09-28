class_name Placeholders
extends RefCounted
## Stand-ins for the artist's models (docs/05_ART_AUDIO.md §4), built from primitives. Each has the size,
## pivot and forward direction (-Z) the real .glb must have, so a file dropped into art/models/ replaces it
## without moving anything. ModelLibrary.instance() falls back to build() when a model is missing.
## Sizes: human 1.85 m, izba 6.2 × 5 m, beacon brazier at 11 m, karbas 5.2 m (§1).

const PROP_SHADER := preload("res://src/shaders/prop.gdshader")
const FLAME_SHADER := preload("res://src/shaders/flame.gdshader")
const GLOW_SHADER := preload("res://src/shaders/glow.gdshader")

const WOOD := Color("6b4a33")
const DARK_WOOD := Color("3f2e22")
const PLANK := Color("8a6a4c")
const STONE := Color("7c7f82")
const RED := Color("a3372c")
const SKIN := Color("e0b89a")
const HAT := Color("2c2f36")
const PANTS := Color("3b3a3f")
const SAIL := Color("d9cbb0")
const WINDOW := Color("ffb24a")
const FIRE := Color("ff9a40")

## Hull sizes: length, beam, depth, masts (boats.json ids).
const HULLS := {
	"karbas": {"length": 5.2, "beam": 1.9, "depth": 0.8, "masts": 1, "sail": Vector2(2.6, 3.4)},
	"shnyaka": {"length": 7.4, "beam": 2.5, "depth": 1.0, "masts": 1, "sail": Vector2(3.4, 4.4)},
	"koch": {"length": 10.0, "beam": 3.6, "depth": 1.4, "masts": 2, "sail": Vector2(3.8, 5.0)},
}

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## A fogged flat-colour material (cached), optionally glowing or reading vertex/instance colours.
static func mat(color: Color, emission: Color = Color.BLACK, energy: float = 0.0, fogged: bool = true, vcol: bool = false) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%s|%s" % [color.to_html(), emission.to_html(), energy, fogged, vcol]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("fogged", fogged)
	m.set_shader_parameter("use_vertex_color", vcol)
	_mats[key] = m
	return m


static func build(category: String, id: String) -> Node3D:
	match category:
		"boats":
			return boat(id)
		"player":
			return pomor()
		"pieces":
			return piece(id)
		"creatures":
			return CreatureShapes.build(id)
		"props":
			match id:
				"izba":
					return izba()
				"pier":
					return pier(13)
				"pomor_cross":
					return pomor_cross()
				"beacon_tower":
					return beacon_tower()
	var n := Node3D.new()
	n.name = id
	_box(Vector3(1, 1, 1), mat(Color.MAGENTA), n, Vector3(0, 0.5, 0))
	return n


# ---------------------------------------------------------------- boats

static func boat(type: String) -> Node3D:
	var h: Dictionary = HULLS.get(type, HULLS["karbas"])
	var length: float = h["length"]
	var beam: float = h["beam"]
	var depth: float = h["depth"]
	var root := Node3D.new()
	root.name = type
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = hull_mesh(length, beam, depth)
	hull.material_override = mat(Color("5a3f2c"))
	root.add_child(hull)
	# floorboards just above the waterline hide the sea inside the open hull
	_box(Vector3(beam * 0.78, 0.08, length * 0.8), mat(PLANK), root, Vector3(0, 0.14, 0))
	for z: float in [-length * 0.22, length * 0.08, length * 0.3]:
		_box(Vector3(beam * 0.86, 0.07, 0.28), mat(WOOD), root, Vector3(0, depth * 0.42, z))
	var sail_size: Vector2 = h["sail"]
	for m in int(h["masts"]):
		var mz := -length * 0.12 if m == 0 else length * 0.22
		var mast_h := sail_size.y + 1.7
		var mast := MeshInstance3D.new()
		mast.mesh = _cyl(0.09 * depth / 0.8, 0.07, mast_h, 5)
		mast.material_override = mat(DARK_WOOD)
		mast.position = Vector3(0, mast_h * 0.5 + 0.1, mz)
		root.add_child(mast)
		var pivot := Node3D.new()
		pivot.name = "Sail" if m == 0 else "Sail%d" % (m + 1)
		pivot.position = Vector3(0, 0, mz)
		root.add_child(pivot)
		var sail := MeshInstance3D.new()
		sail.mesh = sail_mesh(sail_size * (1.0 if m == 0 else 0.8))
		sail.material_override = mat(SAIL)
		sail.position = Vector3(0, sail_size.y * 0.5 + 1.4, 0.12)
		pivot.add_child(sail)
		var stripe := MeshInstance3D.new()
		stripe.mesh = sail_mesh(Vector2(sail_size.x * (1.0 if m == 0 else 0.8) + 0.02, 0.36), 0.33)
		stripe.material_override = mat(RED)
		stripe.position = Vector3(0, 1.4 + sail_size.y * 0.22, 0.14)
		pivot.add_child(stripe)
	# the helmsman sits at the stern (hidden while the player walks ashore)
	var crew := pomor()
	crew.name = "Crew"
	crew.position = Vector3(0, 0.1, length * 0.3)
	crew.scale = Vector3.ONE * 0.95
	(crew.get_node("Hip_L") as Node3D).rotation.x = -1.3
	(crew.get_node("Hip_R") as Node3D).rotation.x = -1.3
	crew.position.y -= 0.35
	root.add_child(crew)
	var lamp := _box(Vector3(0.25, 0.35, 0.25), mat(Color("3a3226"), Color("ffc070"), 3.0, false), root, Vector3(beam * 0.14, depth * 0.55 + 0.75, length * 0.38))
	lamp.name = "Lantern"
	var post := _box(Vector3(0.06, 0.8, 0.06), mat(DARK_WOOD), root, Vector3(beam * 0.14, depth * 0.55 + 0.35, length * 0.38))
	post.name = "LanternPost"
	var marker := Marker3D.new()
	marker.name = "LanternLight"
	marker.position = lamp.position + Vector3(0, 0.2, 0)
	root.add_child(marker)
	return root


## Open lofted hull: U-shaped sections from stern (+Z) to bow (-Z), sheer rising towards the ends.
## Origin on the waterline, bow towards -Z.
static func hull_mesh(length: float, beam: float, depth: float) -> ArrayMesh:
	var key := "hull%.2f/%.2f/%.2f" % [length, beam, depth]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var sections: Array = []
	for i in n + 1:
		var z := lerpf(length * 0.5, -length * 0.5, float(i) / n)
		var t := absf(z) / (length * 0.5)
		var hw := beam * 0.5 * (1.0 - 0.86 * t * t)
		var top := depth * 0.55 + pow(t, 3.0) * 0.55
		var bot := -depth * 0.45 * (1.0 - 0.35 * t) + t * t * depth * 0.2
		sections.append([Vector3(-hw, top, z), Vector3(-hw * 0.95, 0.05, z), Vector3(-hw * 0.5, bot, z),
			Vector3(hw * 0.5, bot, z), Vector3(hw * 0.95, 0.05, z), Vector3(hw, top, z)])
	for i in n:
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		for k in 5:
			_quad(st, a[k], a[k + 1], b[k + 1], b[k])
	for end: Array in [sections[0], sections[n]]:  # transom and stem
		var c := Vector3.ZERO
		for v: Vector3 in end:
			c += v
		c /= end.size()
		for k in end.size() - 1:
			_tri(st, c, end[k], end[k + 1])
		_tri(st, c, end[end.size() - 1], end[0])
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## A square sail with a belly (wind fills it towards -Z... the pivot turns it to the wind).
static func sail_mesh(size: Vector2, belly: float = 0.35) -> ArrayMesh:
	var key := "sail%.2f/%.2f/%.2f" % [size.x, size.y, belly]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 6
	var ny := 6
	var pts: Array = []
	for j in ny + 1:
		var row: Array = []
		for i in nx + 1:
			var x := (float(i) / nx - 0.5) * size.x
			var y := (float(j) / ny - 0.5) * size.y
			var bz := -belly * (1.0 - pow(x / (size.x * 0.5), 2.0)) * (1.0 - pow(y / (size.y * 0.5), 2.0) * 0.3)
			row.append(Vector3(x, y, bz))
		pts.append(row)
	for j in ny:
		for i in nx:
			_quad(st, pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i])
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


# ---------------------------------------------------------------- people

## The pomor: red shirt, dark trousers, hat, beard. Pivot between the feet, facing -Z. Named parts for
## the simple procedural animation: Hip_L, Hip_R, Arm_R (holding Torch with a TorchTip marker).
static func pomor() -> Node3D:
	var root := Node3D.new()
	root.name = "Pomor"
	var body := MeshInstance3D.new()
	body.mesh = _cyl(0.29, 0.25, 0.62, 6)
	body.material_override = mat(RED)
	body.position = Vector3(0, 1.06, 0)
	root.add_child(body)
	var belt := MeshInstance3D.new()
	belt.mesh = _cyl(0.3, 0.3, 0.08, 6)
	belt.material_override = mat(HAT)
	belt.position = Vector3(0, 0.84, 0)
	root.add_child(belt)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.18
	hs.height = 0.36
	hs.radial_segments = 8
	hs.rings = 5
	head.mesh = hs
	head.material_override = mat(SKIN)
	head.position = Vector3(0, 1.53, 0)
	root.add_child(head)
	var hat := MeshInstance3D.new()
	hat.mesh = _cyl(0.22, 0.0, 0.26, 6)
	hat.material_override = mat(HAT)
	hat.position = Vector3(0, 1.72, 0)
	root.add_child(hat)
	var beard := MeshInstance3D.new()
	beard.mesh = _cyl(0.0, 0.12, 0.24, 5)
	beard.material_override = mat(Color("c9b38f"))
	beard.position = Vector3(0, 1.4, -0.14)
	root.add_child(beard)
	for s: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "Hip_L" if s < 0 else "Hip_R"
		hip.position = Vector3(0.12 * s, 0.76, 0)
		root.add_child(hip)
		_box(Vector3(0.15, 0.76, 0.18), mat(PANTS), hip, Vector3(0, -0.38, 0))
	var arm := Node3D.new()
	arm.name = "Arm_R"
	arm.position = Vector3(0.32, 1.3, 0)
	root.add_child(arm)
	var sleeve := _box(Vector3(0.12, 0.52, 0.12), mat(RED), arm, Vector3(0, -0.22, 0))
	sleeve.name = "Sleeve"
	var arm_l := Node3D.new()
	arm_l.name = "Arm_L"
	arm_l.position = Vector3(-0.32, 1.3, 0)
	root.add_child(arm_l)
	_box(Vector3(0.12, 0.52, 0.12), mat(RED), arm_l, Vector3(0, -0.22, 0))
	# the torch stands up out of the fist (arm raised forward ~0.5 rad keeps it upright and a little ahead)
	var torch := Node3D.new()
	torch.name = "Torch"
	torch.position = Vector3(0, -0.44, 0)
	torch.rotation.x = -0.35
	arm.add_child(torch)
	var stick := MeshInstance3D.new()
	stick.mesh = _cyl(0.035, 0.045, 0.75, 5)
	stick.material_override = mat(WOOD)
	stick.position = Vector3(0, 0.22, 0)
	torch.add_child(stick)
	var tip := Marker3D.new()
	tip.name = "TorchTip"
	tip.position = Vector3(0, 0.62, 0)
	torch.add_child(tip)
	torch.visible = false
	return root


# ---------------------------------------------------------------- home and landmarks

## The izba "v oblo": log courses with overhanging ends, board roof, ridge log, warm windows. Pivot at the
## centre of the floor, door and windows towards -Z.
static func izba() -> Node3D:
	var root := Node3D.new()
	root.name = "Izba"
	var parts: Array = []
	var log_mesh := _cyl(0.21, 0.21, 1.0, 6)
	for i in 7:
		var y := 0.21 + i * 0.4
		var c1 := WOOD if i % 2 == 0 else PLANK
		var c2 := PLANK if i % 2 == 0 else WOOD
		for z: float in [-2.3, 2.3]:  # long logs along x with the ends sticking out ("v oblo")
			parts.append([log_mesh, Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(1, 6.8, 1)), Vector3(0, y, z)), c1])
		for x: float in [-3.0, 3.0]:
			parts.append([log_mesh, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, 5.4, 1)), Vector3(x, y + 0.2, 0)), c2])
	var walls := MeshInstance3D.new()
	walls.name = "Walls"
	walls.mesh = merge_colored(parts)
	walls.material_override = mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(walls)
	# gable roof from boards: two slopes and two gables
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = _roof_mesh(7.4, 6.2, 2.9, 5.3)
	roof.material_override = mat(Color("4a3526"))
	root.add_child(roof)
	var ridge := MeshInstance3D.new()
	ridge.mesh = _cyl(0.26, 0.26, 7.8, 6)
	ridge.material_override = mat(DARK_WOOD)
	ridge.position = Vector3(0, 5.35, 0)
	ridge.rotation = Vector3(PI * 0.5, 0, 0)  # along the ridge (z)
	root.add_child(ridge)
	var horse := _box(Vector3(0.22, 0.7, 0.9), mat(DARK_WOOD), root, Vector3(0, 5.6, -3.95))
	horse.rotation.x = 0.5
	_box(Vector3(0.7, 1.7, 0.7), mat(STONE), root, Vector3(1.6, 4.6, 0.6))  # chimney
	var win := mat(Color("3a2a1a"), WINDOW, 2.2, false)
	for x: float in [-1.5, 1.5]:
		var w := _box(Vector3(0.9, 0.62, 0.08), win, root, Vector3(x, 1.55, -2.52))
		w.name = "Window-glow"
	_box(Vector3(1.0, 1.9, 0.1), mat(DARK_WOOD), root, Vector3(0, 0.95, -2.52)).name = "Door"
	_box(Vector3(1.6, 0.25, 1.0), mat(PLANK), root, Vector3(0, 0.12, -3.1))  # porch step
	var light := OmniLight3D.new()
	light.name = "WindowLight"
	light.light_color = Color("ffa040")
	light.light_energy = 1.4
	light.omni_range = 14.0
	light.position = Vector3(0, 1.8, -3.6)
	root.add_child(light)
	var smoke := Marker3D.new()
	smoke.name = "Chimney"
	smoke.position = Vector3(1.6, 5.6, 0.6)
	root.add_child(smoke)
	return root


static func _roof_mesh(length: float, width: float, eave: float, top: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length * 0.5
	var hw := width * 0.5 + 0.5
	var a := Vector3(-hw, eave, -hl)
	var b := Vector3(-hw, eave, hl)
	var c := Vector3(0, top, hl)
	var d := Vector3(0, top, -hl)
	var e := Vector3(hw, eave, hl)
	var f := Vector3(hw, eave, -hl)
	_quad(st, a, b, c, d)
	_quad(st, d, c, e, f)
	# the gables close the log walls (z = ±2.45) under the overhang
	for gz: float in [-2.45, 2.45]:
		_tri(st, Vector3(-hw + 0.5, eave, gz), Vector3(0, top - 0.3, gz), Vector3(hw - 0.5, eave, gz))
	st.generate_normals()
	return st.commit()


## A pier `length` metres long from the pivot (on land, at deck height) out along -Z; posts reach into the water.
static func pier(length: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Pier"
	var parts: Array = []
	var board := BoxMesh.new()
	board.size = Vector3(2.4, 0.18, 0.92)
	var post := BoxMesh.new()
	post.size = Vector3(0.25, 3.2, 0.25)
	for i in length:
		parts.append([board, Transform3D(Basis(), Vector3(0, 0, -i * 1.0 - 0.5)), PLANK if i % 2 else WOOD])
	for i in range(0, length, 3):
		for x: float in [-1.1, 1.1]:
			parts.append([post, Transform3D(Basis(), Vector3(x, -1.5, -i * 1.0 - 0.5)), DARK_WOOD])
	var mi := MeshInstance3D.new()
	mi.mesh = merge_colored(parts)
	mi.material_override = mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	return root


## Pomor cross, a navigation mark 7.5 m tall: short top bar, main bar, slanted foot bar.
static func pomor_cross() -> Node3D:
	var root := Node3D.new()
	root.name = "PomorCross"
	var m := mat(DARK_WOOD)
	_box(Vector3(0.35, 7.5, 0.35), m, root, Vector3(0, 3.75, 0))
	_box(Vector3(2.8, 0.3, 0.3), m, root, Vector3(0, 5.6, 0))
	_box(Vector3(1.4, 0.25, 0.25), m, root, Vector3(0, 6.6, 0))
	var low := _box(Vector3(1.9, 0.25, 0.25), m, root, Vector3(0, 2.3, 0))
	low.rotation.z = -0.35
	return root


## The beacon tower: four raked legs, cross bars, a ladder, a platform and a stone brazier at 11 m;
## firewood stacked at the foot. Marker "Fire" is where the flame burns.
static func beacon_tower() -> Node3D:
	var root := Node3D.new()
	root.name = "BeaconTower"
	var parts: Array = []
	var leg := BoxMesh.new()
	leg.size = Vector3(0.35, 10.4, 0.35)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var b := Basis.from_euler(Vector3(c.y * 0.06, 0, c.x * -0.06))
		parts.append([leg, Transform3D(b, Vector3(c.x * 1.04, 5.0, c.y * 1.04)), DARK_WOOD])
	for i in range(1, 4):
		var w := 2.6 - i * 0.2
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.2, 0.2)
		parts.append([bm, Transform3D(Basis(), Vector3(0, i * 2.4, 1.05 - i * 0.05)), WOOD])
		parts.append([bm, Transform3D(Basis(), Vector3(0, i * 2.4, -1.05 + i * 0.05)), WOOD])
		var side := BoxMesh.new()
		side.size = Vector3(0.2, 0.2, w)
		parts.append([side, Transform3D(Basis(), Vector3(1.05 - i * 0.05, i * 2.4 + 1.2, 0)), WOOD])
	var rung := BoxMesh.new()
	rung.size = Vector3(0.8, 0.08, 0.1)
	for i in 24:
		parts.append([rung, Transform3D(Basis(), Vector3(0, 0.4 + i * 0.4, 1.3)), PLANK])
	var rail := BoxMesh.new()
	rail.size = Vector3(0.08, 10.0, 0.08)
	for x: float in [-0.4, 0.4]:
		parts.append([rail, Transform3D(Basis(), Vector3(x, 5.0, 1.3)), DARK_WOOD])
	var deck := BoxMesh.new()
	deck.size = Vector3(3.4, 0.3, 3.4)
	parts.append([deck, Transform3D(Basis(), Vector3(0, 10.1, 0)), PLANK])
	var logm := BoxMesh.new()
	logm.size = Vector3(0.22, 0.22, 1.6)
	for i in 5:
		parts.append([logm, Transform3D(Basis(Vector3.UP, 0.2), Vector3(1.9, 0.12 + (i % 2) * 0.22, -0.3 + i * 0.26)), PLANK])
	var mi := MeshInstance3D.new()
	mi.name = "Tower"
	mi.mesh = merge_colored(parts)
	mi.material_override = mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	var bowl := MeshInstance3D.new()
	bowl.name = "Brazier"
	bowl.mesh = _cyl(0.6, 1.0, 0.8, 6)
	bowl.material_override = mat(STONE)
	bowl.position = Vector3(0, 10.65, 0)
	root.add_child(bowl)
	var fire := Marker3D.new()
	fire.name = "Fire"
	fire.position = Vector3(0, 11.2, 0)
	root.add_child(fire)
	return root


# ---------------------------------------------------------------- building pieces (buildables.json)

## Pieces whose fire burns while they work (and clears the fog around them, if fog_radius).
const FIRE_PIECES := {"hearth": Vector3(0, 0.35, 0), "stove": Vector3(0, 0.7, -0.95), "kiln": Vector3(0, 0.5, -0.9),
	"bloomery": Vector3(0, 1.7, 0), "forge": Vector3(-0.5, 0.95, 0), "trypot": Vector3(0, 0.3, 0),
	"salt_pan": Vector3(0, 0.3, 0), "tar_pit": Vector3(0, 0.3, 0.9), "bathhouse_stove": Vector3(0, 0.4, 0)}


## A building piece: pivot at the centre of the bottom face, grid pieces 2 m (half walls 1 m), front -Z.
## Children: "Fire" marker where the flame burns (stations with fire), "*-glow" parts that light up.
static func piece(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var parts: Array = []
	var log_m := _cyl(0.2, 0.2, 1.0, 6)
	var along_x := func(len: float, y: float, z: float, c: Color) -> void:
		parts.append([log_m, Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(1, len, 1)), Vector3(0, y, z)), c])
	var box := func(size: Vector3, pos: Vector3, c: Color, rot: Vector3 = Vector3.ZERO) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		parts.append([bm, Transform3D(Basis.from_euler(rot), pos), c])
	var glow: Array = []  # [[Vector3 size, Vector3 pos, Color]]
	match id:
		"log_foundation":
			for z: float in [-0.9, 0.9]:
				along_x.call(2.0, 0.2, z, WOOD)
			for x: float in [-0.9, 0.9]:
				parts.append([log_m, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, 2.0, 1)), Vector3(x, 0.45, 0)), PLANK])
			box.call(Vector3(1.8, 0.1, 1.8), Vector3(0, 0.55, 0), PLANK)
		"log_wall", "log_wall_half", "door", "window_hatch", "mica_window":
			var len := 1.0 if id == "log_wall_half" else 2.0
			for i in 6:
				along_x.call(len + 0.2, 0.2 + i * 0.4, 0.0, WOOD if i % 2 == 0 else PLANK)
			if id == "door":
				box.call(Vector3(0.9, 1.8, 0.46), Vector3(0, 0.9, 0), DARK_WOOD)
			elif id == "window_hatch":
				box.call(Vector3(0.6, 0.35, 0.46), Vector3(0, 1.4, 0), DARK_WOOD)
			elif id == "mica_window":
				glow.append([Vector3(0.7, 0.5, 0.44), Vector3(0, 1.4, 0), Color("ffd89a")])
		"plank_floor":
			for i in 5:
				box.call(Vector3(2.0, 0.1, 0.38), Vector3(0, 0.05, -0.8 + i * 0.4), PLANK if i % 2 else WOOD)
		"gable_roof":
			box.call(Vector3(2.0, 0.12, 2.4), Vector3(0, 0.7, 0), Color("4a3526"), Vector3(0.6, 0, 0))
		"roof_ridge":
			along_x.call(2.0, 0.25, 0.0, DARK_WOOD)
		"carved_horse":
			box.call(Vector3(0.25, 0.9, 0.3), Vector3(0, 0.45, 0), DARK_WOOD)
			box.call(Vector3(0.25, 0.3, 0.7), Vector3(0, 0.95, -0.2), DARK_WOOD, Vector3(0.4, 0, 0))
		"pier":
			for i in 2:
				box.call(Vector3(2.0, 0.16, 0.95), Vector3(0, 0.0, -0.5 + i), PLANK if i else WOOD)
			for c: Vector2 in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(-0.9, 0.9), Vector2(0.9, 0.9)]:
				box.call(Vector3(0.22, 3.0, 0.22), Vector3(c.x, -1.5, c.y), DARK_WOOD)
		"workbench":
			box.call(Vector3(1.9, 0.14, 0.8), Vector3(0, 0.9, 0), PLANK)
			for c: Vector2 in [Vector2(-0.8, -0.3), Vector2(0.8, -0.3), Vector2(-0.8, 0.3), Vector2(0.8, 0.3)]:
				box.call(Vector3(0.12, 0.85, 0.12), Vector3(c.x, 0.42, c.y), DARK_WOOD)
			box.call(Vector3(0.3, 0.25, 0.3), Vector3(0.65, 1.1, 0), STONE)
			box.call(Vector3(0.5, 0.06, 0.1), Vector3(-0.3, 0.99, 0.1), Color("9aa0a4"))
		"hearth", "bathhouse_stove":
			for i in 8:
				var a := i * TAU / 8.0
				var r := SphereMesh.new()
				r.radius = 0.28
				r.height = 0.4
				r.radial_segments = 5
				r.rings = 2
				parts.append([r, Transform3D(Basis(), Vector3(cos(a) * 0.62, 0.18, sin(a) * 0.62)), STONE.darkened(0.1 * (i % 2))])
			if id == "bathhouse_stove":
				var heap := SphereMesh.new()
				heap.radius = 0.6
				heap.height = 0.9
				heap.radial_segments = 6
				heap.rings = 3
				parts.append([heap, Transform3D(Basis(), Vector3(0, 0.45, 0)), Color("6a6e72")])
			glow.append([Vector3(0.6, 0.12, 0.6), Vector3(0, 0.08, 0), Color("ff7a2a")])
		"stove":
			box.call(Vector3(2.0, 1.6, 1.8), Vector3(0, 0.8, 0), Color("e6e0d2"))
			box.call(Vector3(0.8, 1.4, 0.8), Vector3(0.4, 2.3, 0.4), Color("e6e0d2"))
			box.call(Vector3(0.8, 0.6, 0.1), Vector3(0, 0.7, -0.91), Color("2a2622"))
			glow.append([Vector3(0.6, 0.35, 0.08), Vector3(0, 0.62, -0.9), Color("ff7a2a")])
		"kiln":
			var dome := SphereMesh.new()
			dome.radius = 1.0
			dome.height = 1.4
			dome.radial_segments = 7
			dome.rings = 3
			parts.append([dome, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color("8a6a4a")])
			glow.append([Vector3(0.5, 0.4, 0.1), Vector3(0, 0.45, -0.95), Color("ff7a2a")])
		"bloomery":
			parts.append([_cyl(0.7, 0.45, 1.6, 7), Transform3D(Basis(), Vector3(0, 0.8, 0)), Color("9a6a4a")])
			glow.append([Vector3(0.3, 0.3, 0.1), Vector3(0, 0.3, -0.62), Color("ff7a2a")])
		"forge":
			box.call(Vector3(1.4, 0.9, 1.0), Vector3(-0.5, 0.45, 0), STONE)
			box.call(Vector3(0.5, 0.35, 0.3), Vector3(0.8, 0.75, 0), Color("4a4d52"))
			box.call(Vector3(0.25, 0.55, 0.25), Vector3(0.8, 0.3, 0), DARK_WOOD)
			glow.append([Vector3(0.8, 0.1, 0.6), Vector3(-0.5, 0.92, 0), Color("ff7a2a")])
		"loom":
			for x: float in [-0.8, 0.8]:
				box.call(Vector3(0.1, 1.8, 0.1), Vector3(x, 0.9, 0), WOOD)
			box.call(Vector3(1.7, 0.1, 0.1), Vector3(0, 1.75, 0), WOOD)
			box.call(Vector3(1.5, 1.2, 0.03), Vector3(0, 1.1, 0), Color("d9cbb0"))
		"quern":
			parts.append([_cyl(0.5, 0.5, 0.2, 10), Transform3D(Basis(), Vector3(0, 0.1, 0)), STONE])
			parts.append([_cyl(0.48, 0.48, 0.18, 10), Transform3D(Basis(), Vector3(0, 0.3, 0)), STONE.lightened(0.1)])
			box.call(Vector3(0.06, 0.35, 0.06), Vector3(0.35, 0.55, 0), WOOD)
		"garden_bed":
			box.call(Vector3(2.0, 0.3, 1.0), Vector3(0, 0.15, 0), Color("5a3f2c"))
			box.call(Vector3(1.8, 0.05, 0.8), Vector3(0, 0.3, 0), Color("3a2a1e"))
			for i in 6:
				parts.append([_cone(0.08, 0.4), Transform3D(Basis(), Vector3(-0.75 + i * 0.3, 0.5, 0)), Color("8aa050")])
		"boatyard":
			for i in 5:
				box.call(Vector3(0.2, 0.2, 8.0), Vector3(-1.6 + i * 0.8, 0.1, 0), DARK_WOOD)
			for i in 6:
				box.call(Vector3(3.6, 0.1, 0.15), Vector3(0, 0.25, -3.0 + i * 1.2), PLANK)
			for x: float in [-1.8, 1.8]:
				box.call(Vector3(0.2, 2.0, 0.2), Vector3(x, 1.0, 2.8), WOOD)
			box.call(Vector3(3.8, 0.2, 0.2), Vector3(0, 2.0, 2.8), WOOD)
		"trypot", "salt_pan":
			for i in 5:
				var a := i * TAU / 5.0
				box.call(Vector3(0.35, 0.3, 0.35), Vector3(cos(a) * 0.6, 0.15, sin(a) * 0.6), STONE)
			if id == "trypot":
				parts.append([_cyl(0.35, 0.55, 0.6, 8), Transform3D(Basis(), Vector3(0, 0.6, 0)), Color("3a3c40")])
			else:
				box.call(Vector3(1.8, 0.12, 1.2), Vector3(0, 0.4, 0), Color("5a5d62"))
			glow.append([Vector3(0.5, 0.08, 0.5), Vector3(0, 0.05, 0), Color("ff7a2a")])
		"tar_pit":
			var mound := SphereMesh.new()
			mound.radius = 1.0
			mound.height = 1.0
			mound.radial_segments = 7
			mound.rings = 3
			parts.append([mound, Transform3D(Basis(), Vector3(0, 0.1, 0)), Color("5a4a3a")])
			parts.append([_cyl(0.08, 0.08, 1.0, 5), Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, 0.4, 0.9)), DARK_WOOD])
			glow.append([Vector3(0.3, 0.1, 0.3), Vector3(0, 0.05, 0.9), Color("ff7a2a")])
		"bench":
			box.call(Vector3(1.8, 0.1, 0.4), Vector3(0, 0.45, 0), PLANK)
			for x: float in [-0.7, 0.7]:
				box.call(Vector3(0.1, 0.45, 0.35), Vector3(x, 0.22, 0), DARK_WOOD)
		"table":
			box.call(Vector3(1.6, 0.1, 0.9), Vector3(0, 0.8, 0), PLANK)
			for c: Vector2 in [Vector2(-0.7, -0.35), Vector2(0.7, -0.35), Vector2(-0.7, 0.35), Vector2(0.7, 0.35)]:
				box.call(Vector3(0.1, 0.78, 0.1), Vector3(c.x, 0.39, c.y), DARK_WOOD)
		"bed":
			box.call(Vector3(2.0, 0.12, 1.2), Vector3(0, 1.2, 0), PLANK)
			box.call(Vector3(1.8, 0.14, 1.0), Vector3(0, 1.32, 0), Color("7d9a4a"))
			for c: Vector2 in [Vector2(-0.9, -0.5), Vector2(0.9, -0.5), Vector2(-0.9, 0.5), Vector2(0.9, 0.5)]:
				box.call(Vector3(0.12, 1.2, 0.12), Vector3(c.x, 0.6, c.y), DARK_WOOD)
			box.call(Vector3(0.1, 0.1, 1.0), Vector3(-1.05, 0.6, 0), WOOD)
		"chest":
			box.call(Vector3(1.0, 0.55, 0.6), Vector3(0, 0.28, 0), Color("6b3f2a"))
			box.call(Vector3(1.04, 0.1, 0.64), Vector3(0, 0.6, 0), DARK_WOOD)
			box.call(Vector3(0.12, 0.14, 0.04), Vector3(0, 0.45, -0.31), Color("c9a24a"))
		"drying_rack":
			for x: float in [-0.9, 0.9]:
				box.call(Vector3(0.12, 1.9, 0.12), Vector3(x, 0.95, 0), WOOD)
			box.call(Vector3(2.0, 0.08, 0.08), Vector3(0, 1.8, 0), DARK_WOOD)
			for i in 5:
				box.call(Vector3(0.12, 0.5, 0.05), Vector3(-0.6 + i * 0.3, 1.5, 0), Color("b0a890"))
		"oil_lamp":
			box.call(Vector3(0.1, 0.4, 0.1), Vector3(0, 1.6, 0), DARK_WOOD)
			parts.append([_cyl(0.12, 0.08, 0.1, 6), Transform3D(Basis(), Vector3(0, 1.85, -0.1)), Color("4a4d52")])
			glow.append([Vector3(0.08, 0.14, 0.08), Vector3(0, 1.95, -0.1), Color("ffb24a")])
		"sheep_pen":
			for side in 4:
				var a := side * PI * 0.5
				for i in 3:
					var bm := BoxMesh.new()
					bm.size = Vector3(4.0, 0.08, 0.08)
					parts.append([bm, Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 2.0, 0.3 + i * 0.3, cos(a) * 2.0)), WOOD])
			for c: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
				box.call(Vector3(0.14, 1.1, 0.14), Vector3(c.x, 0.55, c.y), DARK_WOOD)
		"pomor_cross":
			return pomor_cross()
		_:
			box.call(Vector3(1, 1, 1), Vector3(0, 0.5, 0), Color.MAGENTA)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = merge_colored(parts)
	mi.material_override = mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	for g: Array in glow:
		var gm := _box(g[0], mat(Color("2a1a10"), g[2], 2.4, false), root, g[1])
		gm.name = "Ember-glow"
	if FIRE_PIECES.has(id):
		var f := Marker3D.new()
		f.name = "Fire"
		f.position = FIRE_PIECES[id]
		root.add_child(f)
	return root


# ---------------------------------------------------------------- vegetation and resource nodes

## Meshes for island MultiMeshes by node shape: [[mesh, tinted], ...]. Untinted parts (trunks) keep their
## baked colours; tinted parts are multiplied by the instance colour (golden or green birch crowns).
static func node_parts(shape: String) -> Array:
	if _meshes.has("node/" + shape):
		return _meshes["node/" + shape]
	var out: Array = []
	match shape:
		"pine":
			out = [[merge_colored([[_cyl(0.22, 0.16, 2.2, 5), Transform3D(Basis(), Vector3(0, 1.1, 0)), Color("5b4331")]]), false],
				[merge_colored([[_cone(1.7, 2.6), Transform3D(Basis(), Vector3(0, 1.9, 0)), Color.WHITE],
					[_cone(1.35, 2.3), Transform3D(Basis(), Vector3(0, 3.2, 0)), Color.WHITE],
					[_cone(0.95, 2.0), Transform3D(Basis(), Vector3(0, 4.4, 0)), Color.WHITE]]), true]]
		"larch":
			out = [[merge_colored([[_cyl(0.2, 0.12, 3.0, 5), Transform3D(Basis(), Vector3(0, 1.5, 0)), Color("6e5038")]]), false],
				[merge_colored([[_cone(1.4, 2.4), Transform3D(Basis(), Vector3(0, 2.6, 0)), Color.WHITE],
					[_cone(1.05, 2.2), Transform3D(Basis(), Vector3(0, 3.8, 0)), Color.WHITE],
					[_cone(0.7, 1.8), Transform3D(Basis(), Vector3(0, 4.9, 0)), Color.WHITE]]), true]]
		"birch":
			var crown := SphereMesh.new()
			crown.radius = 1.25
			crown.height = 3.4
			crown.radial_segments = 6
			crown.rings = 3
			out = [[merge_colored([[_cyl(0.17, 0.12, 3.2, 5), Transform3D(Basis(), Vector3(0, 1.6, 0)), Color("e6e2d6")]]), false],
				[merge_colored([[crown, Transform3D(Basis(), Vector3(0, 3.6, 0)), Color.WHITE]]), true]]
		"rock":
			var r := SphereMesh.new()
			r.radius = 0.9
			r.height = 1.3
			r.radial_segments = 5
			r.rings = 3
			out = [[merge_colored([[r, Transform3D(Basis(), Vector3(0, 0.25, 0)), Color("7a7f84")]]), true]]
		"stump":
			out = [[merge_colored([[_cyl(0.28, 0.24, 0.45, 6), Transform3D(Basis(), Vector3(0, 0.22, 0)), Color("5b4331")],
				[_cyl(0.23, 0.23, 0.02, 6), Transform3D(Basis(), Vector3(0, 0.46, 0)), Color("c9a27a")]]), false]]
		"bush":
			var s := SphereMesh.new()
			s.radius = 0.45
			s.height = 0.7
			s.radial_segments = 6
			s.rings = 3
			var berry := SphereMesh.new()
			berry.radius = 0.07
			berry.height = 0.14
			berry.radial_segments = 4
			berry.rings = 2
			var ps: Array = [[s, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color("4f6b3e")],
				[s, Transform3D(Basis.from_scale(Vector3.ONE * 0.8), Vector3(0.4, 0.25, 0.2)), Color("56704a")],
				[s, Transform3D(Basis.from_scale(Vector3.ONE * 0.75), Vector3(-0.35, 0.22, -0.2)), Color("4f6b3e")]]
			for i in 7:
				var a := i * 2.4
				ps.append([berry, Transform3D(Basis(), Vector3(cos(a) * 0.42, 0.35 + (i % 3) * 0.12, sin(a) * 0.42)), Color("f0a030")])
			out = [[merge_colored(ps), true]]
		"sticks":
			var st: Array = []
			for i in 4:
				st.append([_cyl(0.05, 0.04, 1.4, 4), Transform3D(Basis(Vector3.BACK, PI * 0.5).rotated(Vector3.UP, -0.4 + i * 0.25), Vector3(0, 0.1 + (i % 2) * 0.07, (i - 1.5) * 0.08)), WOOD])
			st.append([_cyl(0.17, 0.17, 0.07, 6), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.13, 0)), Color("c9a27a")])
			out = [[merge_colored(st), false]]
		"nettle":
			var nt: Array = []
			for i in 6:
				var a := i * 1.1
				nt.append([_cone(0.12, 0.9), Transform3D(Basis(), Vector3(cos(a) * 0.25, 0.45, sin(a) * 0.25)), Color("5d7f3e")])
			out = [[merge_colored(nt), false]]
		"moss":
			var ms := SphereMesh.new()
			ms.radius = 0.6
			ms.height = 0.35
			ms.radial_segments = 7
			ms.rings = 2
			out = [[merge_colored([[ms, Transform3D(Basis(), Vector3(0, 0.02, 0)), Color("7d9a4a")]]), false]]
		"mushrooms":
			var mu: Array = []
			for i in 3:
				var a := i * 2.1
				var off := Vector3(cos(a) * 0.2, 0, sin(a) * 0.2)
				mu.append([_cyl(0.04, 0.035, 0.18, 5), Transform3D(Basis(), off + Vector3(0, 0.09, 0)), Color("e8dfc8")])
				mu.append([_cyl(0.14, 0.02, 0.1, 6), Transform3D(Basis(), off + Vector3(0, 0.2, 0)), Color("8a4a2a")])
			out = [[merge_colored(mu), false]]
		"bog", "clay":
			var mound := SphereMesh.new()
			mound.radius = 0.8
			mound.height = 0.4
			mound.radial_segments = 7
			mound.rings = 2
			var col := Color("7a4a2a") if shape == "bog" else Color("b07850")
			out = [[merge_colored([[mound, Transform3D(Basis(), Vector3(0, 0.05, 0)), col],
				[mound, Transform3D(Basis.from_scale(Vector3.ONE * 0.5), Vector3(0.5, 0.08, 0.3)), col.darkened(0.2)]]), false]]
		"flax", "barley":
			var stalk: Array = []
			var sc := Color("6f8fcf") if shape == "flax" else Color("d8b860")
			for i in 9:
				var a := i * 0.7
				var off := Vector3(cos(a) * (0.1 + i * 0.03), 0, sin(a) * (0.1 + i * 0.03))
				stalk.append([_cyl(0.015, 0.015, 0.8, 3), Transform3D(Basis(), off + Vector3(0, 0.4, 0)), Color("8aa050")])
				stalk.append([_cone(0.05, 0.12), Transform3D(Basis(), off + Vector3(0, 0.84, 0)), sc])
			out = [[merge_colored(stalk), false]]
		"shoal":
			var pb: Array = []
			var peb := SphereMesh.new()
			peb.radius = 0.18
			peb.height = 0.2
			peb.radial_segments = 5
			peb.rings = 2
			for i in 6:
				var a := i * 1.3
				pb.append([peb, Transform3D(Basis(), Vector3(cos(a) * 0.4, 0.05, sin(a) * 0.4)), Color("9aa0a4")])
			pb.append([peb, Transform3D(Basis.from_scale(Vector3.ONE * 0.4), Vector3(0.1, 0.12, 0)), Color("f4efe6")])
			out = [[merge_colored(pb), false]]
		"spolokh":
			var cr: Array = []
			for i in 3:
				cr.append([_cyl(0.12, 0.0, 0.9 - i * 0.2, 5), Transform3D(Basis.from_euler(Vector3(0.3 * (i - 1), 0, 0.25 * (1 - i))), Vector3((i - 1) * 0.15, 0.4, 0)), Color("7cf0b8")])
			out = [[merge_colored(cr), false]]
		_:
			out = [[merge_colored([[BoxMesh.new(), Transform3D(Basis(), Vector3(0, 0.5, 0)), Color.MAGENTA]]), false]]
	_meshes["node/" + shape] = out
	return out


# ---------------------------------------------------------------- fire

## A flame: CPUParticles3D tongues with normal blending plus a warm light. `size` 1 = a beacon fire,
## 0.3 = a torch.
static func fire(size: float = 1.0, with_light: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var p := CPUParticles3D.new()
	p.name = "Flames"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.3)
	p.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	p.material_override = m
	p.amount = int(clampf(22.0 * size, 6.0, 40.0))
	p.lifetime = 0.55 + 0.35 * size
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.55 * size
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.5 * size, 0)
	p.initial_velocity_min = 1.8 * size
	p.initial_velocity_max = 3.4 * size
	p.scale_amount_min = 1.6 * size
	p.scale_amount_max = 2.6 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.72, 0.32, 0.95))
	ramp.set_color(1, Color(0.85, 0.22, 0.06, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.5, 0.15, 0.8))
	p.color_ramp = ramp
	p.local_coords = false
	root.add_child(p)
	if with_light:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color("ff9a40")
		l.omni_range = 18.0 * maxf(size, 0.4) + 6.0
		l.light_energy = 2.0 * size
		l.position = Vector3(0, 0.6 * size, 0)
		root.add_child(l)
	return root


## A soft additive glow billboard (not fogged): halos over fires, the hint light, glimmers.
static func glow(color: Color, size: float, strength: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size
	return mi


# ---------------------------------------------------------------- mesh helpers

static func _box(size: Vector3, m: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(bottom: float, top: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _cone(r: float, h: float) -> CylinderMesh:
	return _cyl(r, 0.0, h, 6)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Several primitive meshes baked into one with vertex colours: [[Mesh, Transform3D, Color], ...].
## One draw call for a whole tree, izba wall set or tower.
static func merge_colored(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var basis := xf.basis
			if idx.is_empty():
				for i in v.size():
					verts.append(xf * v[i])
					normals.append((basis * nm[i]).normalized())
					colors.append(col)
			else:
				for i in idx:
					verts.append(xf * v[i])
					normals.append((basis * nm[i]).normalized())
					colors.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
