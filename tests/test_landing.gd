extends "res://tests/lib/case.gd"
## Landing and boarding (docs/06_ROADMAP.md phase 2): from the water off three islands at three points each
## the landing search finds dry, walkable land within reach.


func test_landing_finds_land_around_three_islands() -> void:
	var m := WorldMap.shared(db)
	for id in ["home", "b01", "b02"]:
		var isl: IslandGen = m.by_id[id]
		for k in 3:
			var dir := Vector2.from_angle(0.4 + k * TAU / 3.0)
			var w := WorldMap.walk_out(isl, isl.center, dir)
			var sea: Vector2 = w["sea"]
			check(m.ground_at(sea.x, sea.y) < -1.0, "%s/%d: start in the water" % [id, k])
			var land := m.find_landing(sea)
			check(not land.is_empty(), "%s/%d: found a landing" % [id, k])
			if land.is_empty():
				continue
			var p: Vector3 = land["pos"]
			check(m.ground_at(p.x, p.z) > 0.25, "%s/%d: the landing is dry" % [id, k])
			check(isl.slope_at(p.x, p.z) < 1.3, "%s/%d: the landing is walkable" % [id, k])
			check(float(land["d"]) <= 14.0, "%s/%d: within reach of the boat" % [id, k])


func test_no_landing_in_open_sea() -> void:
	eq(WorldMap.shared(db).find_landing(Vector2(2500, 2500)), {})


func test_blocked_spots_are_skipped() -> void:
	var m := WorldMap.shared(db)
	var w := WorldMap.walk_out(m.by_id["b01"], (m.by_id["b01"] as IslandGen).center, Vector2(0, 1))
	var free := m.find_landing(w["sea"])
	var first: Vector3 = free["pos"]
	var blocked := func(p: Vector2) -> bool: return p.distance_to(Vector2(first.x, first.z)) < 1.0
	var other := m.find_landing(w["sea"], blocked)
	check(not other.is_empty(), "another spot is found")
	check(Vector2((other["pos"] as Vector3).x, (other["pos"] as Vector3).z).distance_to(Vector2(first.x, first.z)) >= 1.0, "not the blocked one")
