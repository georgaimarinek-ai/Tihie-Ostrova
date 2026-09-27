class_name IslandGen
extends RefCounted
## Deterministic island: the same seed gives the same island on every machine. Co-op clients build
## islands locally from content seeds instead of downloading meshes; resource node ids are
## "<island>:<index>" so saves and network messages can refer to them.
## The shape follows the atmosphere sketch (reference/sketch/src/main.js, makeIsland).

const SEA_FLOOR := -4.5
const MARGIN := 1.35  # heightfield covers radius * MARGIN around the centre

var id: String
var center: Vector2
var radius: float
var peak: float
var island_seed: int
var plateau: Dictionary = {}  # {"pos": Vector2, "radius": float, "height": float}
var avoid: Array = []  # [{"pos": Vector2, "radius": float, "soft": bool}]: no trees there (izba, pier, beacon; soft = paths)

var _edge := FastNoiseLite.new()
var _hills := FastNoiseLite.new()


func _init(p_id: String, p_center: Vector2, p_radius: float, p_peak: float, p_seed: int) -> void:
	id = p_id
	center = p_center
	radius = p_radius
	peak = p_peak
	island_seed = p_seed
	for n: FastNoiseLite in [_edge, _hills]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_gain = 0.5
		n.fractal_lacunarity = 2.03
	_edge.seed = p_seed
	_edge.fractal_octaves = 4
	_edge.frequency = 1.4 / p_radius
	_hills.seed = p_seed + 101
	_hills.fractal_octaves = 3
	_hills.frequency = 2.8 / p_radius


## An island described in content (beacons.json row or regions.home).
static func from_content(row: Dictionary, p_id: String) -> IslandGen:
	var pos: Array = row["pos"]
	var r := float(row.get("island_radius", row.get("radius", 100)))
	var isl := IslandGen.new(p_id, Vector2(float(pos[0]), float(pos[1])), r, float(row.get("peak", 8)), int(row["seed"]))
	if row.has("island_radius"):  # beacon islands get a flat top for the tower
		isl.plateau = {"pos": isl.center, "radius": r * 0.12, "height": float(row.get("peak", 8)) * 0.75}
		isl.avoid.append({"pos": isl.center, "radius": r * 0.08})
	return isl


func height_at(x: float, z: float) -> float:
	var dx := (x - center.x) / radius
	var dz := (z - center.y) / radius
	var d := sqrt(dx * dx + dz * dz)
	if d > MARGIN:
		return -5.0
	var edge := d + _edge.get_noise_2d(x, z) * 0.35
	var mask := 1.0 - smoothstep(0.55, 1.0, edge)
	var hills := 0.45 + 0.55 * (0.5 + 0.5 * _hills.get_noise_2d(x, z))
	var h := mask * peak * hills * (1.0 - 0.3 * d) - (1.0 - mask) * 4.0 + mask * 0.5 - 0.9
	if not plateau.is_empty():
		var pd := Vector2(x, z).distance_to(plateau["pos"])
		var k := 1.0 - smoothstep(plateau["radius"] * 0.6, plateau["radius"], pd)
		h = lerpf(h, plateau["height"], k)
	return h


func slope_at(x: float, z: float) -> float:
	var e := 0.8
	var gx := height_at(x + e, z) - height_at(x - e, z)
	var gz := height_at(x, z + e) - height_at(x, z - e)
	return Vector2(gx, gz).length() / (2.0 * e)


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > -0.9


## Square grid of heights covering the island, row-major (z rows, x columns).
func heightfield(step: float) -> Dictionary:
	var half := radius * MARGIN
	var n := int(ceil(2.0 * half / step)) + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			var x := center.x - half + i * step
			var z := center.y - half + j * step
			h[j * n + i] = maxf(SEA_FLOOR, height_at(x, z))
	return {"n": n, "step": step, "origin": Vector2(center.x - half, center.y - half), "heights": h}


## Stable fingerprint for determinism tests: heights rounded to centimetres.
func fingerprint(step: float = 4.0) -> int:
	var hf := heightfield(step)
	var ints := PackedInt32Array()
	for v: float in hf["heights"]:
		ints.append(int(round(v * 100.0)))
	return hash(ints)


## Resource nodes (trees, rocks, bushes) on land. Integer RNG seeded from the island seed, so the list
## and the ids are identical for host and clients.
func resource_nodes(density: float = 1.0) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed * 7 + 3
	var out: Array[Dictionary] = []
	var want := int(round(radius * radius * 0.01 * density))
	var tries := want * 4
	var idx := 0
	for _t in tries:
		if out.size() >= want:
			break
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius * 0.95
		var p := center + Vector2(cos(a), sin(a)) * rr
		var roll := rng.randf()
		var h := height_at(p.x, p.y)
		if h < 1.1 or slope_at(p.x, p.y) > 0.9 or _avoided(p):
			continue
		var kind := "birch"
		if h > peak * 0.55 or roll < 0.35:
			kind = "pine"
		if roll > 0.9:
			kind = "rock"
		elif roll > 0.82:
			kind = "berry_bush"
		out.append({"id": "%s:%d" % [id, idx], "kind": kind, "pos": Vector3(p.x, h, p.y)})
		idx += 1
	return out


func _avoided(p: Vector2) -> bool:
	for a: Dictionary in avoid:
		if p.distance_to(a["pos"]) < float(a["radius"]):
			return true
	return false


## Avoid areas that even small ground pickups keep off (buildings, the tower); paths are "soft".
func in_hard_avoid(p: Vector2) -> bool:
	for a: Dictionary in avoid:
		if not a.get("soft", false) and p.distance_to(a["pos"]) < float(a["radius"]):
			return true
	return false


## Flat-shaded mesh with vertex colours (sand / rock / grass / moss / heath) as in the sketch.
func build_mesh(step: float = 3.0) -> ArrayMesh:
	return mesh_from_heightfield(heightfield(step))


## The same mesh from a heightfield computed once (IslandView shares it with the collision shape).
func mesh_from_heightfield(hf: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays(hf))
	return mesh


## Surface arrays of the terrain mesh (pure data: safe to compute on a worker thread).
func mesh_arrays(hf: Dictionary) -> Array:
	var step: float = hf["step"]
	var n: int = hf["n"]
	var origin: Vector2 = hf["origin"]
	var hs: PackedFloat32Array = hf["heights"]
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed + 7
	var sand := Color("8b8676")
	var rock := Color("6f7479")
	var grass := Color("6d8752")
	var moss := Color("56704a")
	var heath := Color("8a6f5a")
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in n - 1:
		for i in n - 1:
			var p00 := Vector3(origin.x + i * step, hs[j * n + i], origin.y + j * step)
			var p10 := Vector3(origin.x + (i + 1) * step, hs[j * n + i + 1], origin.y + j * step)
			var p01 := Vector3(origin.x + i * step, hs[(j + 1) * n + i], origin.y + (j + 1) * step)
			var p11 := Vector3(origin.x + (i + 1) * step, hs[(j + 1) * n + i + 1], origin.y + (j + 1) * step)
			for tri: Array in [[p00, p11, p10], [p00, p01, p11]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				if a.y <= SEA_FLOOR and b.y <= SEA_FLOOR and c.y <= SEA_FLOOR:
					continue
				var nrm := (b - a).cross(c - a).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var ya := (a.y + b.y + c.y) / 3.0
				var col := grass
				if ya < 0.5:
					col = sand
				elif nrm.y < 0.72:
					col = rock
				else:
					var r := rng.randf()
					col = heath if r < 0.18 else (grass if r < 0.6 else moss)
				col = col.lightened((rng.randf() - 0.5) * 0.06) if rng.randf() < 0.5 else col.darkened(rng.randf() * 0.04)
				for v: Vector3 in [a, b, c]:
					verts.append(v)
					normals.append(nrm)
					colors.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays
