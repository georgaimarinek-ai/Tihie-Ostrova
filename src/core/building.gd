class_name Building
extends RefCounted
## The building grid (docs/01_GDD.md §10, docs/04_TECH_SPEC.md §8): 2 m cells aligned with the world axes,
## turns in 90° steps (free pieces in 45°), socket families from buildables.json → snap. No loads and no
## collapse: a piece only needs something to stand on — the ground or a neighbouring piece.
## Pure: WorldCommands checks placements with check(), the build mode snaps its ghost with snap().

const GRID := 2.0
const TOUCH := 0.35  # how close levels must be to count as resting on each other
## Height of each family's top above its pivot: walls stack on walls, floors lie on foundations.
const TOP := {"foundation": 0.6, "floor": 0.1, "wall": 2.4, "roof": 1.4, "pier": 0.0, "free": 0.0}
const DECK_Y := 0.9  # pier deck height over the water


static func family(db: ContentDB, piece_id: String) -> String:
	return String(db.pieces.get(piece_id, {}).get("snap", "free"))


static func top_of(db: ContentDB, pc: Dictionary) -> float:
	return (pc["pos"] as Vector3).y + float(TOP.get(family(db, pc["id"]), 0.0))


static func cell_center(p: Vector3) -> Vector2:
	return Vector2((floorf(p.x / GRID) + 0.5) * GRID, (floorf(p.z / GRID) + 0.5) * GRID)


static func _ground(map: WorldMap, x: float, z: float, fallback: float) -> float:
	return map.ground_at(x, z) if map != null else fallback


## Pieces (as [uid, piece]) whose pivot is within `r` metres of a point on the ground plane.
static func near(state: WorldState, p: Vector2, r: float) -> Array:
	var out: Array = []
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		var q: Vector3 = pc["pos"]
		if Vector2(q.x, q.z).distance_to(p) <= r:
			out.append([uid, pc])
	return out


## Where a piece would go for an aim point on the ground and a number of quarter turns (R):
## {"pos": Vector3, "rot": float, "hint": "ground" | "joins"}.
static func snap(db: ContentDB, state: WorldState, map: WorldMap, piece_id: String, aim: Vector3, turns: int) -> Dictionary:
	var fam := family(db, piece_id)
	var c := cell_center(aim)
	var rot := wrapf(turns * PI * 0.5, -PI, PI)
	var y := _ground(map, c.x, c.y, aim.y)
	var hint := "ground"
	match fam:
		"foundation":
			for k: Vector2 in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(-0.9, 0.9), Vector2(0.9, 0.9)]:
				y = maxf(y, _ground(map, c.x + k.x, c.y + k.y, aim.y) - 0.3)
			return {"pos": Vector3(c.x, y, c.y), "rot": 0.0, "hint": hint}
		"floor":
			var level := _level_in_cell(db, state, c, ["foundation"], -INF)
			level = maxf(level, _level_on_edges(db, state, c, ["wall"]))
			if level > -INF:
				return {"pos": Vector3(c.x, level, c.y), "rot": 0.0, "hint": "joins"}
			return {"pos": Vector3(c.x, y, c.y), "rot": 0.0, "hint": hint}
		"wall":
			var d := Vector2(aim.x, aim.z) - c
			var pos2 := c
			var along := 0.0  # 0: the wall runs along x; PI/2: along z
			if absf(d.x) > absf(d.y):
				pos2 = Vector2(c.x + signf(d.x) * GRID * 0.5, c.y)
				along = PI * 0.5
			else:
				pos2 = Vector2(c.x, c.y + signf(d.y) * GRID * 0.5)
			var base := -INF
			for pr: Array in near(state, pos2, GRID * 0.75):
				var pc: Dictionary = pr[1]
				var f := family(db, pc["id"])
				if f in ["foundation", "floor"] or (f == "wall" and (pc["pos"] as Vector3).distance_to(Vector3(pos2.x, (pc["pos"] as Vector3).y, pos2.y)) < 0.2):
					base = maxf(base, top_of(db, pc))
			if base > -INF:
				return {"pos": Vector3(pos2.x, base, pos2.y), "rot": wrapf(along + (turns % 2) * PI, -PI, PI), "hint": "joins"}
			return {"pos": Vector3(pos2.x, _ground(map, pos2.x, pos2.y, aim.y), pos2.y), "rot": wrapf(along + (turns % 2) * PI, -PI, PI), "hint": hint}
		"roof":
			var top := _level_on_edges(db, state, c, ["wall"])
			if top > -INF:
				var lift := 1.4 if piece_id in ["roof_ridge", "carved_horse"] else 0.0
				return {"pos": Vector3(c.x, top + lift, c.y), "rot": rot, "hint": "joins"}
			return {"pos": Vector3(c.x, y, c.y), "rot": rot, "hint": hint}
		"pier":
			return {"pos": Vector3(c.x, DECK_Y, c.y), "rot": rot, "hint": "joins" if not near(state, c, GRID * 1.2).is_empty() else hint}
	# free pieces (stations, furniture, marks): no grid, stand on a floor under them or on the ground
	var level := y
	for pr: Array in near(state, Vector2(aim.x, aim.z), GRID * 0.75):
		var pc: Dictionary = pr[1]
		if family(db, pc["id"]) in ["foundation", "floor"]:
			level = maxf(level, top_of(db, pc))
			hint = "joins"
	return {"pos": Vector3(aim.x, level, aim.z), "rot": wrapf(turns * PI * 0.25, -PI, PI), "hint": hint}


static func _level_in_cell(db: ContentDB, state: WorldState, c: Vector2, families: Array, fallback: float) -> float:
	var level := fallback
	for pr: Array in near(state, c, 0.3):
		var pc: Dictionary = pr[1]
		if family(db, pc["id"]) in families:
			level = maxf(level, top_of(db, pc))
	return level


static func _level_on_edges(db: ContentDB, state: WorldState, c: Vector2, families: Array) -> float:
	var level := -INF
	for pr: Array in near(state, c, GRID * 0.55):
		var pc: Dictionary = pr[1]
		if family(db, pc["id"]) in families:
			level = maxf(level, top_of(db, pc))
	return level


## Dry land within a plank's reach (its 2 m edge) of a point.
static func _touches_land(map: WorldMap, pos: Vector3) -> bool:
	if map.ground_at(pos.x, pos.z) > -0.6:
		return true
	for a in 8:
		var d := Vector2.from_angle(a * TAU / 8.0) * (GRID * 1.1)
		if map.ground_at(pos.x + d.x, pos.z + d.y) > 0.0:
			return true
	return false


## Why a piece cannot stand there, or "": "no_support" (nothing under it: neither the ground nor a
## neighbouring piece), "occupied" (the same kind of piece is already in that socket), "no_land" (over
## water; only piers go there), "no_water" (a pier must reach the water).
static func check(db: ContentDB, state: WorldState, map: WorldMap, piece_id: String, pos: Vector3, rot: float) -> String:
	var fam := family(db, piece_id)
	var ground := _ground(map, pos.x, pos.z, pos.y)
	if fam != "free":
		for pc: Dictionary in state.pieces.values():
			if family(db, pc["id"]) != fam:
				continue
			var q: Vector3 = pc["pos"]
			var same_axis := absf(wrapf(float(pc["rot"]) - rot, -PI * 0.5, PI * 0.5)) < 0.2
			if q.distance_to(pos) < 0.4 and (fam != "wall" or same_axis):
				return "occupied"
	if fam == "pier":
		if ground > 0.8:
			return "no_water"
		if map != null and _touches_land(map, pos):
			return ""  # the first plank rests on the shore
		for pr: Array in near(state, Vector2(pos.x, pos.z), GRID * 1.2):
			if family(db, (pr[1] as Dictionary)["id"]) in ["pier"] or String((pr[1] as Dictionary)["id"]) == "boatyard":
				return ""
		return "no_support"
	var on_ground := absf(pos.y - ground) < 0.9 and ground > -0.6
	if on_ground:
		return ""
	for pr: Array in near(state, Vector2(pos.x, pos.z), GRID * 1.2):
		var pc: Dictionary = pr[1]
		var f := family(db, pc["id"])
		if f == "free":
			continue
		var q: Vector3 = pc["pos"]
		if absf(top_of(db, pc) - pos.y) < TOUCH or (absf(q.y - pos.y) < TOUCH and f == fam):
			return ""
		if fam == "roof" and absf(top_of(db, pc) - pos.y) < 1.6:
			return ""  # ridges and roof decor sit up on the roof
	if ground < -0.6:
		return "no_land"
	return "no_support"
