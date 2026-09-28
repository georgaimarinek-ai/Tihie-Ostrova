extends "res://tests/lib/case.gd"
## Beacons and trials on the host (docs/01_GDD.md §5, roadmap phase 5): with a map, "complete_trial"
## checks what the host can see (on the island; fire in hand at the tower for "carry"; up on the deck for
## "climb"); the sea wall; the chart's coastlines.


func _world() -> WorldCommands:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 3, "quiet")
	st.add_player("p1", m.home["spawn"])
	return WorldCommands.new(db, st, m)


func _stand(c: WorldCommands, p: Vector3) -> void:
	c.state.players["p1"]["pos"] = p


func _trial(c: WorldCommands, bid: String) -> Dictionary:
	return c.apply("p1", {"type": "complete_trial", "beacon": bid, "kind": "trial"})


func test_trials_are_checked_on_the_island() -> void:
	var c := _world()
	eq(_trial(c, "b03")["error"], "too_far", "the bells can't be rung from home")
	var q := c.map.path_point("b03", 0.9, 0.0)
	_stand(c, q)
	check(_trial(c, "b03")["ok"], "on the island the bells count")
	check(c.state.trials_done.has("b03"), "and stay counted")


func test_carry_needs_fire_at_the_tower() -> void:
	var c := _world()
	var isl: IslandGen = c.map.by_id["b01"]
	var mid := c.map.path_point("b01", 0.3, 0.0)
	_stand(c, mid)
	eq(_trial(c, "b01")["error"], "no_fire", "no fire in hand")
	c.state.inv("p1").add("torch", 1)
	check(c.apply("p1", {"type": "light", "item": "torch"})["ok"], "the torch is lit")
	if Vector2(mid.x, mid.z).distance_to(isl.center) > WorldCommands.BEACON_REACH_M:
		eq(_trial(c, "b01")["error"], "too_far", "the fire has to reach the tower")
	var top := c.map.path_point("b01", 0.97, 0.0)
	_stand(c, top)
	check(_trial(c, "b01")["ok"], "fire carried to the tower")


func test_climb_ends_on_the_deck() -> void:
	var c := _world()
	var isl: IslandGen = c.map.by_id["b02"]
	var ground := isl.height_at(isl.center.x, isl.center.y)
	_stand(c, Vector3(isl.center.x + 1.0, ground, isl.center.y))
	eq(_trial(c, "b02")["error"], "not_at_top", "standing at the foot of the tower")
	_stand(c, Vector3(isl.center.x + 0.5, ground + 9.95, isl.center.y))
	check(_trial(c, "b02")["ok"], "up on the deck")


func test_the_sea_wall() -> void:
	var st := WorldState.new(db, 3, "quiet")
	var r2 := Vector2(0, -1000)
	var r3 := Vector2(0, -2000)
	eq(SeaWall.blocked(db, st, Vector2(0, -300), "karbas"), "", "the Quiet Bay is open")
	eq(SeaWall.blocked(db, st, r2, "karbas"), "locked", "the Summer Coast is closed until b03")
	for bid in ["b01", "b02", "b03", "b04", "b05", "b06"]:
		st.lit[bid] = 1
	eq(SeaWall.blocked(db, st, r2, "karbas"), "", "b03 opened it")
	eq(SeaWall.blocked(db, st, r3, "karbas"), "boat", "the Ter Coast wants a stronger boat")
	eq(SeaWall.boat_needed(db, r3), "shnyaka")
	eq(SeaWall.blocked(db, st, r3, "shnyaka"), "", "a shnyaka goes")
	near(SeaWall.pull(Vector2(0, -1000)).dot(Vector2(0, 1)), 1.0, 1e-6, "the current pulls home")
	near(SeaWall.push_after_s(db), 6.0, 1e-6, "after 6 s (roadmap)")


func test_every_beacon_stands_where_the_content_says() -> void:
	var m := WorldMap.shared(db)
	eq(db.beacon_order.size(), 12, "twelve beacons")
	for bid: String in db.beacon_order:
		var isl: IslandGen = m.by_id[bid]
		near(isl.center.distance_to(db.beacon_pos(bid)), 0.0, 0.01, bid + " island centre = beacons.json pos")
		check(isl.height_at(isl.center.x, isl.center.y) > 1.0, bid + " tower stands on land")
		check(m.paths.has(bid), bid + " has a path from the shore")


func test_coastlines_for_the_chart() -> void:
	var m := WorldMap.shared(db)
	for id: String in ["home", "b01", "b07"]:
		var isl: IslandGen = m.by_id[id]
		var o := m.outline(id)
		eq(o.size(), 48, id + " outline points")
		var land := 0
		for q in o:
			if isl.height_at(q.x, q.y) > 0.0:
				land += 1
			var out := q + (q - isl.center).normalized() * 6.0
			check(isl.height_at(out.x, out.y) <= 0.5 or out.distance_to(isl.center) > isl.radius * IslandGen.MARGIN, id + " outline sits at the shore")
		eq(land, 48, id + " outline is on land")
		check(m.outline(id) == o, "cached and stable")
