class_name WorldMap
extends RefCounted
## Every island of the world, built from content only (never from the world seed): the home island, the
## twelve beacon islands and the islets between them (regions.json → islets). Host and co-op clients build
## the same map on their own, so node ids ("<island>:<n>") mean the same thing everywhere
## (docs/04_TECH_SPEC.md §7-8). Pure data and height queries: the scene streams IslandView nodes from it;
## the camera, walking, landing and WorldCommands (gather reach) ask it questions.

const HOME := "home"
const CELL := 250.0  # lookup grid for ground_at()
const PIER_LEN := 13.0
const REACH_M := 4.5  # how close the player must be to gather a node

var db: ContentDB
var islands: Array[IslandGen] = []
var by_id: Dictionary = {}  # island id -> IslandGen
var kind_of: Dictionary = {}  # island id -> "home" | "beacon" | "islet"
var region_of: Dictionary = {}  # island id -> region id
## Home island layout: izba, pier, starting boat, spawn point, pomor cross (all Vector3 world positions),
## "yaw" (facing the sea), "dir" (Vector2 towards the first beacon).
var home: Dictionary = {}
## Beacon island paths: beacon id -> {"shore": Vector2, "sea": Vector2, "dir": Vector2 (from the tower to the sea)}
var paths: Dictionary = {}

var _grid: Dictionary = {}  # Vector2i -> Array[IslandGen]
var _nodes: Dictionary = {}  # island id -> Array[Dictionary]
var _node_by_id: Dictionary = {}  # node id -> Dictionary

static var _shared: WorldMap


static func shared(p_db: ContentDB) -> WorldMap:
	if _shared == null or _shared.db != p_db:
		_shared = WorldMap.new(p_db)
	return _shared


func _init(p_db: ContentDB) -> void:
	db = p_db
	_add(IslandGen.from_content(db.home, HOME), "home", "r1")
	for bid in db.beacon_order:
		_add(IslandGen.from_content(db.beacons[bid], bid), "beacon", String(db.beacons[bid]["region"]))
	for rid in ContentDB.REGION_ORDER:
		_place_islets(rid)
	_layout_home()
	_layout_paths()


func _add(isl: IslandGen, kind: String, rid: String) -> void:
	islands.append(isl)
	by_id[isl.id] = isl
	kind_of[isl.id] = kind
	region_of[isl.id] = rid
	var half := isl.radius * IslandGen.MARGIN
	var a := Vector2i(floori((isl.center.x - half) / CELL), floori((isl.center.y - half) / CELL))
	var b := Vector2i(floori((isl.center.x + half) / CELL), floori((isl.center.y + half) / CELL))
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(isl)


## Islets: `islets` per region, scattered in the region's ring on the side where its beacons are.
## A fixed integer RNG per region keeps them identical on every machine.
func _place_islets(rid: String) -> void:
	var reg: Dictionary = db.regions[rid]
	var ring: Array = reg["ring_m"]
	var want := int(reg.get("islets", 0))
	var ridx := ContentDB.REGION_ORDER.find(rid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (ridx + 1)
	var spread := deg_to_rad(115.0 if ridx == 0 else 70.0)
	var placed := 0
	for _attempt in want * 120:
		if placed >= want:
			break
		var a := rng.randf_range(-spread, spread)
		var d := rng.randf_range(float(ring[0]) + 90.0, float(ring[1]) - 70.0)
		var r := rng.randf_range(12.0, 30.0)
		var peak := rng.randf_range(4.0, 9.0)
		var p := Vector2(sin(a), -cos(a)) * d
		if _too_close(p, r):
			continue
		placed += 1
		_add(IslandGen.new("%si%d" % [rid, placed], p, r, peak, 500 + ridx * 50 + placed), "islet", rid)


func _too_close(p: Vector2, r: float) -> bool:
	for isl in islands:
		if p.distance_to(isl.center) < (isl.radius + r) * IslandGen.MARGIN + 40.0:
			return true
	return false


# ---------------------------------------------------------------- layouts

## Walks from `from` along `dir` until deep water. "shore" = last dry point, "sea" = a few metres into deep water.
static func walk_out(isl: IslandGen, from: Vector2, dir: Vector2) -> Dictionary:
	var shore := from
	for s in 600:
		var p := from + dir * float(s)
		var h := isl.height_at(p.x, p.y)
		if h > 0.4:
			shore = p
		if h < -1.2:
			return {"shore": shore, "sea": p + dir * 3.0}
	return {"shore": shore, "sea": from + dir * isl.radius * IslandGen.MARGIN}


static func yaw_of(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)  # a node with rotation.y = yaw looks along -Z = dir


func _layout_home() -> void:
	var isl: IslandGen = by_id[HOME]
	var dir := (db.beacon_pos(db.beacon_order[0]) - isl.center).normalized()
	var side := Vector2(-dir.y, dir.x)
	var w := walk_out(isl, isl.center, dir)
	var shore: Vector2 = w["shore"]
	var izba := shore - dir * 24.0
	for _i in 12:  # step inland until the ground is dry and gentle enough for a house
		if isl.height_at(izba.x, izba.y) > 1.0 and isl.slope_at(izba.x, izba.y) < 0.35:
			break
		izba -= dir * 2.0
	var pier_start := shore - dir * 2.0
	var berth := pier_start + dir * (PIER_LEN - 2.0) + side * 2.8
	for _i in 20:  # the boat needs water under the keel
		if isl.height_at(berth.x, berth.y) < -1.4:
			break
		berth += dir * 1.5
	var spawn := izba + dir * 5.0
	var cross := shore - dir * 5.0 + side * 11.0
	var yaw := yaw_of(dir)
	home = {
		"dir": dir, "yaw": yaw, "shore": shore,
		"izba": Vector3(izba.x, isl.height_at(izba.x, izba.y), izba.y),
		"pier": Vector3(pier_start.x, 0.9, pier_start.y), "pier_len": PIER_LEN,
		"boat": Vector3(berth.x, 0.0, berth.y),
		"spawn": Vector3(spawn.x, isl.height_at(spawn.x, spawn.y), spawn.y),
		"cross": Vector3(cross.x, isl.height_at(cross.x, cross.y), cross.y),
	}
	isl.avoid.append({"pos": izba, "radius": 8.0})
	isl.avoid.append({"pos": cross, "radius": 2.0})
	for s in range(0, int(PIER_LEN) + 30, 3):  # the yard between the izba and the pier stays open
		isl.avoid.append({"pos": izba.lerp(pier_start + dir * float(PIER_LEN), float(s) / (PIER_LEN + 30.0)), "radius": 4.0, "soft": true})


## A path from the shore facing the previous beacon (home for b01) up to each tower: trees keep off it,
## pickups and trial props line it (the sketch's landingPoint()).
func _layout_paths() -> void:
	var prev := Vector2.ZERO
	for bid in db.beacon_order:
		var isl: IslandGen = by_id[bid]
		var dir := (prev - isl.center).normalized()
		var w := walk_out(isl, isl.center, dir)
		var shore: Vector2 = w["shore"]
		paths[bid] = {"shore": shore, "sea": w["sea"], "dir": dir}
		var length := isl.center.distance_to(shore)
		var s := 0.0
		while s <= length:
			isl.avoid.append({"pos": shore.lerp(isl.center, s / maxf(length, 1.0)), "radius": 5.5, "soft": true})
			s += 4.0
		prev = isl.center


# ---------------------------------------------------------------- height queries

func near(x: float, z: float) -> Array:
	return _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])


## Terrain height at a point (the highest island there), -5 in open sea.
func ground_at(x: float, z: float) -> float:
	var h := -5.0
	for isl: IslandGen in near(x, z):
		var half := isl.radius * IslandGen.MARGIN
		if absf(x - isl.center.x) < half and absf(z - isl.center.y) < half:
			h = maxf(h, isl.height_at(x, z))
	return h


## The island whose land (above -0.9 m) is at the point, or null.
func island_at(x: float, z: float) -> IslandGen:
	for isl: IslandGen in near(x, z):
		if Vector2(x, z).distance_to(isl.center) < isl.radius * IslandGen.MARGIN and isl.height_at(x, z) > -0.9:
			return isl
	return null


## The island nearest to a point (by distance to its shore ring), or null if nothing is within `max_m`.
func nearest_island(p: Vector2, max_m: float = INF) -> IslandGen:
	var best: IslandGen = null
	var best_d := max_m
	for isl in islands:
		var d := p.distance_to(isl.center) - isl.radius
		if d < best_d:
			best_d = d
			best = isl
	return best


## Nearest walkable land within reach of a boat (the sketch's findLanding): 16 directions, 2–14 m out,
## dry (> 0.25 m) and not steeper than 1.3. `blocked` (optional Callable(Vector2) -> bool) rejects spots
## taken by trees or buildings. Returns {} or {"pos": Vector3, "d": float, "island": String}.
func find_landing(from: Vector2, blocked: Callable = Callable()) -> Dictionary:
	var best := {}
	for a in 16:
		var ang := float(a) / 16.0 * TAU
		var d := 2.0
		while d <= 14.0:
			var p := from + Vector2(cos(ang), sin(ang)) * d
			var h := ground_at(p.x, p.y)
			if h > 0.25:
				var isl := island_at(p.x, p.y)
				var steep := isl.slope_at(p.x, p.y) if isl != null else 0.0
				if steep < 1.3 and (not blocked.is_valid() or not bool(blocked.call(p))):
					var score := d + steep * 5.0
					if best.is_empty() or score < float(best["score"]):
						best = {"pos": Vector3(p.x, h, p.y), "d": d, "score": score, "island": isl.id if isl != null else ""}
					break
			d += 1.5
	return best


# ---------------------------------------------------------------- resource nodes

## Resource nodes of an island (computed once): trees, rocks and bushes from IslandGen.resource_nodes()
## plus small ground pickups, each {"id", "kind", "pos": Vector3, "items": Array, "shape", "scale", "yaw"}.
## What a kind gives comes from regions.json → nodes, filtered by the region's resources.
func nodes(island_id: String) -> Array:
	if _nodes.has(island_id):
		return _nodes[island_id]
	var isl: IslandGen = by_id.get(island_id)
	var out: Array = []
	if isl == null:
		return out
	var cfg: Dictionary = db.raw["regions"]["nodes"]
	var kinds: Dictionary = cfg["kinds"]
	var rid: String = region_of[island_id]
	var res: Array = db.regions[rid]["resources"]
	var swap: Dictionary = cfg.get("swap", {}).get(rid, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = isl.island_seed + 17
	var density := 1.2 if kind_of[island_id] == "home" else 1.0
	for n: Dictionary in isl.resource_nodes(density):
		var kind: String = n["kind"]
		var sc := rng.randf_range(0.75, 1.35)
		var yaw := rng.randf() * TAU
		var roll := rng.randf()
		if swap.has(kind) and roll < float(swap[kind][1]):
			kind = String(swap[kind][0])
		out.append(_node(n["id"], kind, n["pos"], sc, yaw, kinds, res))
	# ground pickups: count per 1000 m² of land, only kinds whose items occur in this region
	var prng := RandomNumberGenerator.new()
	prng.seed = isl.island_seed * 13 + 5
	var land := PI * isl.radius * isl.radius * 0.45
	var idx := 0
	var pick: Dictionary = cfg["pickups"]
	var names := pick.keys()
	names.sort()
	for kind: String in names:
		if _items_here(kinds[kind]["items"], res).is_empty():
			continue
		var want := int(round(land / 1000.0 * float(pick[kind])))
		var low := kind in ["pearl_shoal", "clay_bank", "bog"]
		for _t in want * 6:
			if want <= 0:
				break
			var a := prng.randf() * TAU
			var rr := sqrt(prng.randf()) * isl.radius * 0.95
			var p := isl.center + Vector2(cos(a), sin(a)) * rr
			var h := isl.height_at(p.x, p.y)
			var ok := h > 0.15 and h < 1.6 if low else h > 0.6
			if not ok or isl.slope_at(p.x, p.y) > 1.0 or isl.in_hard_avoid(p):
				continue
			out.append(_node("%s:p%d" % [island_id, idx], kind, Vector3(p.x, h, p.y), prng.randf_range(0.8, 1.2), prng.randf() * TAU, kinds, res))
			idx += 1
			want -= 1
	_nodes[island_id] = out
	for n: Dictionary in out:
		_node_by_id[n["id"]] = n
	return out


func _node(id: String, kind: String, pos: Vector3, sc: float, yaw: float, kinds: Dictionary, res: Array) -> Dictionary:
	var k: Dictionary = kinds.get(kind, {"items": [], "shape": "rock"})
	return {"id": id, "kind": kind, "pos": pos, "scale": sc, "yaw": yaw, "shape": String(k["shape"]),
		"solid": float(k.get("solid", 0.0)) * sc, "items": _items_here(k["items"], res)}


static func _items_here(items: Array, res: Array) -> Array:
	var out: Array = []
	for it: String in items:
		if it in res:
			out.append(it)
	return out


## A node by id ("b02:14", "home:p3"), or {} if there is none. Fishing spots "sea:<cx>:<cz>" are
## generated on the fly: every sea cell of balance.fishing.cell_m metres is a spot.
func node(id: String) -> Dictionary:
	if _node_by_id.has(id):
		return _node_by_id[id]
	var parts := id.split(":")
	if parts.size() == 3 and parts[0] == "sea":
		var cell := float(db.raw["regions"]["nodes"]["fish_cell_m"])
		var p := Vector2((int(parts[1]) + 0.5) * cell, (int(parts[2]) + 0.5) * cell)
		return {"id": id, "kind": "fish", "pos": Vector3(p.x, 0.0, p.y), "items": ["raw_fish"], "shape": "water", "solid": 0.0, "reach": cell}
	if parts.size() >= 2 and by_id.has(parts[0]):
		nodes(parts[0])
		return _node_by_id.get(id, {})
	return {}


## A point on a beacon's path from the shore (t = 0) to the tower (t = 1), `side` metres to the side of it
## but always on land (the sketch's pathPoint): where trial props stand.
func path_point(bid: String, t: float, side: float) -> Vector3:
	var isl: IslandGen = by_id[bid]
	var p: Dictionary = paths[bid]
	var shore: Vector2 = p["shore"]
	var dir: Vector2 = p["dir"]
	var base := shore.lerp(isl.center, t)
	var across := Vector2(-dir.y, dir.x)
	for k in 8:
		var q := base + across * side * (1.0 - k / 8.0)
		if isl.height_at(q.x, q.y) > 0.5:
			return Vector3(q.x, isl.height_at(q.x, q.y), q.y)
	return Vector3(base.x, isl.height_at(base.x, base.y), base.y)


## The coastline of an island as a closed polygon (48 points, where the land meets the water): the chart
## draws islands with it. Cached.
func outline(island_id: String) -> PackedVector2Array:
	var key := "outline:" + island_id
	if _nodes.has(key):
		return _nodes[key]
	var isl: IslandGen = by_id[island_id]
	var out := PackedVector2Array()
	for a in 48:
		var dir := Vector2.from_angle(a * TAU / 48.0)
		var last := isl.center
		var r := 0.0
		while r < isl.radius * IslandGen.MARGIN:
			var q := isl.center + dir * r
			if isl.height_at(q.x, q.y) > 0.0:
				last = q
			r += maxf(1.0, isl.radius / 60.0)
		out.append(last)
	_nodes[key] = out
	return out


## The fishing spot id for a point on the water.
func fish_spot(p: Vector2) -> String:
	var cell := float(db.raw["regions"]["nodes"]["fish_cell_m"])
	return "sea:%d:%d" % [floori(p.x / cell), floori(p.y / cell)]
