extends "res://tests/lib/case.gd"
## The world map is built from content alone: every machine gets the same islands, islets and node ids.


func test_same_content_same_map() -> void:
	var a := WorldMap.new(db)
	var b := WorldMap.new(db)
	eq(a.islands.size(), b.islands.size())
	for i in a.islands.size():
		eq(a.islands[i].id, b.islands[i].id)
		eq(a.islands[i].center, b.islands[i].center)
	var islets := 0
	for rid in ContentDB.REGION_ORDER:
		islets += int(db.regions[rid]["islets"])
	eq(a.islands.size(), 1 + db.beacon_order.size() + islets, "home + beacons + every islet from regions.json")


func test_islets_sit_in_their_ring_apart() -> void:
	var m := WorldMap.shared(db)
	for isl in m.islands:
		if m.kind_of[isl.id] != "islet":
			continue
		var ring: Array = db.regions[m.region_of[isl.id]]["ring_m"]
		var d := isl.center.length()
		check(d > float(ring[0]) and d < float(ring[1]), "%s inside its ring (%.0f m)" % [isl.id, d])
		for other in m.islands:
			if other != isl:
				check(isl.center.distance_to(other.center) > (isl.radius + other.radius) * IslandGen.MARGIN, "%s clear of %s" % [isl.id, other.id])


func test_home_layout() -> void:
	var m := WorldMap.shared(db)
	var h := m.home
	var izba: Vector3 = h["izba"]
	check(izba.y > 0.9, "the izba stands on dry land (%.2f)" % izba.y)
	var boat: Vector3 = h["boat"]
	check(m.ground_at(boat.x, boat.z) < -1.3, "the boat floats in deep enough water")
	var spawn: Vector3 = h["spawn"]
	check(m.ground_at(spawn.x, spawn.z) > 0.3, "spawn point is on land")
	var toward := (db.beacon_pos("b01") - Vector2(izba.x, izba.z)).normalized()
	check((h["dir"] as Vector2).dot(toward) > 0.9, "the pier faces the first beacon")


func test_ground_and_island_queries() -> void:
	var m := WorldMap.shared(db)
	var isl: IslandGen = m.by_id["b02"]
	near(m.ground_at(isl.center.x, isl.center.y), isl.height_at(isl.center.x, isl.center.y), 1e-4)
	check(m.island_at(isl.center.x, isl.center.y) == isl, "island_at finds b02")
	eq(m.ground_at(2000, 1500), -5.0, "open sea")
	check(m.island_at(2000, 1500) == null, "no island in open sea")


func test_beacon_paths_reach_the_sea() -> void:
	var m := WorldMap.shared(db)
	for bid in db.beacon_order:
		var p: Dictionary = m.paths[bid]
		var sea: Vector2 = p["sea"]
		var shore: Vector2 = p["shore"]
		check(m.ground_at(sea.x, sea.y) < -1.0, bid + ": the path ends in the water")
		check(m.ground_at(shore.x, shore.y) > 0.3, bid + ": the path starts on dry land")


func test_nodes_are_stable_and_give_regional_items() -> void:
	var a := WorldMap.new(db).nodes("b02")
	var b := WorldMap.new(db).nodes("b02")
	eq(a.size(), b.size())
	var kinds := {}
	for i in a.size():
		eq(a[i]["id"], b[i]["id"])
		kinds[a[i]["kind"]] = true
		for it: String in a[i]["items"]:
			check(it in db.regions["r1"]["resources"], "%s gives %s, an r1 resource" % [a[i]["id"], it])
	for k in ["pine", "birch", "sticks", "nettle"]:
		check(kinds.has(k), "b02 has %s" % k)
	var r3 := WorldMap.shared(db).nodes("b08")
	var larch := r3.filter(func(n: Dictionary) -> bool: return n["kind"] == "larch")
	check(not larch.is_empty(), "r3 islands grow larch")


func test_node_lookup() -> void:
	var m := WorldMap.shared(db)
	var n: Dictionary = m.nodes("home")[3]
	eq(m.node(n["id"])["pos"], n["pos"])
	eq(m.node("nowhere:1"), {})
	var spot := m.fish_spot(Vector2(100, -300))
	eq(m.node(spot)["items"], ["raw_fish"])
