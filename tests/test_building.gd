extends "res://tests/lib/case.gd"
## Building (docs/01_GDD.md §10, roadmap phase 4): the grid and sockets, "dry" checks change nothing,
## pieces need something to stand on, removal refunds everything; comfort within 10 m of the bed.


func _world() -> WorldCommands:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 3, "quiet")
	var c := WorldCommands.new(db, st, m)
	var at := Vector3(4.0, m.ground_at(4.0, 4.0), 4.0)
	st.add_player("p1", at)
	for k in ["wood", "stone", "moss", "birch_bark", "rope"]:
		st.inv("p1").add(k, 200)
	return c


func _place(c: WorldCommands, piece: String, aim: Vector3, turns: int = 0, dry: bool = false) -> Dictionary:
	var s := Building.snap(db, c.state, c.map, piece, aim, turns)
	var p: Vector3 = s["pos"]
	return c.apply("p1", {"type": "place", "piece": piece, "pos": [p.x, p.y, p.z], "rot": s["rot"], "dry": dry})


func test_dry_changes_nothing() -> void:
	var c := _world()
	var before := SaveCodec.encode(c.state)
	var r := _place(c, "log_foundation", c.state.players["p1"]["pos"], 0, true)
	check(r["ok"], "a foundation would stand: " + String(r["error"]))
	eq(r["events"], [], "no events")
	eq(SaveCodec.encode(c.state), before, "the world is exactly as it was")
	var at: Vector3 = c.state.players["p1"]["pos"]
	var bad := c.apply("p1", {"type": "place", "piece": "log_wall", "pos": [at.x, at.y + 6.0, at.z], "rot": 0.0, "dry": true})
	eq(bad["error"], "no_support", "dry also says why not")


func test_foundation_walls_floor_roof() -> void:
	var c := _world()
	var at: Vector3 = c.state.players["p1"]["pos"]
	check(_place(c, "log_foundation", at)["ok"], "foundation on the ground")
	var cell := Building.cell_center(at)
	var wall := Building.snap(db, c.state, c.map, "log_wall", Vector3(cell.x, at.y, cell.y + 0.9), 0)
	var f: Dictionary = c.state.pieces.values()[0]
	near((wall["pos"] as Vector3).y, (f["pos"] as Vector3).y + Building.TOP["foundation"], 1e-4, "the wall stands on the sill log")
	near((wall["pos"] as Vector3).z, cell.y + 1.0, 1e-4, "on the cell's edge")
	check(_place(c, "log_wall", Vector3(cell.x, at.y, cell.y + 0.9))["ok"], "wall")
	var wp: Vector3 = wall["pos"]
	eq(c.apply("p1", {"type": "place", "piece": "log_wall", "pos": [wp.x, wp.y, wp.z], "rot": wall["rot"]})["error"], "occupied", "one wall per socket")
	var upper := Building.snap(db, c.state, c.map, "log_wall", Vector3(cell.x, at.y, cell.y + 0.9), 0)
	near((upper["pos"] as Vector3).y, wp.y + Building.TOP["wall"], 1e-4, "the next wall on that edge stacks: a second storey")
	check(_place(c, "log_wall", Vector3(cell.x + 0.9, at.y, cell.y))["ok"], "a corner wall")
	check(_place(c, "plank_floor", Vector3(cell.x, at.y, cell.y))["ok"], "floor on the foundation")
	var roof := Building.snap(db, c.state, c.map, "gable_roof", Vector3(cell.x, at.y, cell.y), 0)
	near((roof["pos"] as Vector3).y, (wall["pos"] as Vector3).y + Building.TOP["wall"], 1e-4, "the roof sits on the wall tops")
	check(_place(c, "gable_roof", Vector3(cell.x, at.y, cell.y))["ok"], "roof")


func test_nothing_hangs_in_the_air() -> void:
	var c := _world()
	var at: Vector3 = c.state.players["p1"]["pos"]
	eq(c.apply("p1", {"type": "place", "piece": "log_wall", "pos": [at.x, at.y + 6.0, at.z], "rot": 0.0})["error"], "no_support")
	eq(c.apply("p1", {"type": "place", "piece": "bench", "pos": [at.x, at.y + 3.0, at.z], "rot": 0.0})["error"], "no_support")
	check(c.apply("p1", {"type": "place", "piece": "bench", "pos": [at.x, at.y, at.z], "rot": 0.0})["ok"], "a bench on the ground")


func test_piers_start_at_the_shore() -> void:
	var c := _world()
	var m: WorldMap = c.map
	var shore: Vector2 = m.home["shore"]
	var dir: Vector2 = m.home["dir"]
	var first := shore + dir * 4.0
	c.state.players["p1"]["pos"] = Vector3(first.x, 0.9, first.y)
	var r := _place(c, "pier", Vector3(first.x, 0, first.y))
	check(r["ok"], "the first plank at the shore: " + String(r["error"]))
	var far := shore + dir * 40.0
	c.state.players["p1"]["pos"] = Vector3(far.x, 0.9, far.y)
	eq(_place(c, "pier", Vector3(far.x, 0, far.y))["error"], "no_support", "not out in the open sea")
	var inland := Vector3(4, m.ground_at(4, 4), 4)
	c.state.players["p1"]["pos"] = inland
	eq(_place(c, "pier", inland)["error"], "no_water")


func test_remove_refunds_everything_and_keeps_chests() -> void:
	var c := _world()
	var at: Vector3 = c.state.players["p1"]["pos"]
	var wood := c.state.inv("p1").count("wood")
	var r := _place(c, "chest", at)
	check(r["ok"], "chest")
	var uid: String = r["events"][0]["uid"]
	check(c.state.pieces[uid].has("inv"), "a chest has its own inventory")
	c.state.inv("p1").add("flint", 3)
	var slot := -1
	for i in c.state.inv("p1").size:
		if c.state.inv("p1").slots[i].get("id", "") == "flint":
			slot = i
	check(c.apply("p1", {"type": "store", "uid": uid, "slot": slot})["ok"], "store")
	eq((c.state.pieces[uid]["inv"] as Inventory).count("flint"), 3)
	eq(c.apply("p1", {"type": "remove", "uid": uid})["error"], "not_empty", "a full chest stays")
	check(c.apply("p1", {"type": "take", "uid": uid, "slot": 0})["ok"], "take")
	eq(c.state.inv("p1").count("flint"), 3)
	check(c.apply("p1", {"type": "remove", "uid": uid})["ok"], "remove the empty chest")
	eq(c.state.inv("p1").count("wood"), wood, "100% back")


func test_comfort_counts_kinds_within_ten_metres() -> void:
	var c := _world()
	var st := c.state
	var bed := Vector3(0, 0, 0)
	st.pieces["b"] = {"id": "bed", "pos": bed, "rot": 0.0, "owner": "p1"}
	st.pieces["h"] = {"id": "hearth", "pos": Vector3(3, 0, 0), "rot": 0.0, "owner": "p1"}
	st.pieces["s1"] = {"id": "bench", "pos": Vector3(0, 0, 4), "rot": 0.0, "owner": "p1"}
	st.pieces["s2"] = {"id": "bench", "pos": Vector3(0, 0, -4), "rot": 0.0, "owner": "p1"}
	st.pieces["far"] = {"id": "table", "pos": Vector3(10.5, 0, 0), "rot": 0.0, "owner": "p1"}
	var cf := Comfort.at(db, st, bed)
	eq(cf["total"], 3, "bed 1 + hearth 1 + bench 1 (two benches count once), the table is 10.5 m away")
	st.pieces["far"]["pos"] = Vector3(9.5, 0, 0)
	eq(Comfort.at(db, st, bed)["total"], 4, "within 10 m it counts")
	for id: String in db.pieces:
		st.pieces["x_" + id] = {"id": id, "pos": Vector3(1, 0, 1), "rot": 0.0, "owner": "p1"}
	check(int(Comfort.at(db, st, bed)["total"]) <= int(db.balance["rested"]["max_comfort"]), "capped")


func test_sleep_gives_rested_by_comfort() -> void:
	var c := _world()
	var st := c.state
	var at: Vector3 = st.players["p1"]["pos"]
	st.pieces["b"] = {"id": "bed", "pos": at, "rot": 0.0, "owner": "p1"}
	st.pieces["h"] = {"id": "stove", "pos": at + Vector3(3, 0, 0), "rot": 0.0, "owner": "p1"}
	var r := c.apply("p1", {"type": "sleep", "uid": "b"})
	check(r["ok"], "sleep")
	var want := Comfort.rested_minutes(db, 1 + 3)
	near(float(st.players["p1"]["rested_until"]), st.clock_min + want, 1e-4, "base + comfort minutes")
	check(Vitals.is_rested(st, "p1"), "rested")
	st.inv("p1").add("pearl_necklace", 1)
	c.apply("p1", {"type": "sleep", "uid": "b"})
	near(float(st.players["p1"]["rested_until"]), st.clock_min + want + 10.0, 1e-4, "the necklace adds its minutes")
	st.players["p1"]["pos"] = at + Vector3(30, 0, 0)
	eq(c.apply("p1", {"type": "sleep", "uid": "b"})["error"], "too_far")


func test_steam_in_the_bathhouse() -> void:
	var c := _world()
	var st := c.state
	var at: Vector3 = st.players["p1"]["pos"]
	st.pieces["k"] = {"id": "bathhouse_stove", "pos": at, "rot": 0.0, "owner": "p1"}
	var base := Vitals.stamina_regen(db, st, "p1")
	check(c.apply("p1", {"type": "steam", "uid": "k"})["ok"], "steam")
	near(Vitals.stamina_regen(db, st, "p1"), base * (1.0 + float(db.balance["steam"]["stamina_regen_bonus"])), 1e-5)
	st.pieces["w"] = {"id": "workbench", "pos": at, "rot": 0.0, "owner": "p1"}
	eq(c.apply("p1", {"type": "steam", "uid": "w"})["error"], "unknown_uid", "only a sauna stove steams")


func test_unload_the_hold_into_a_chest() -> void:
	var c := _world()
	var st := c.state
	var at: Vector3 = st.players["p1"]["pos"]
	var boat := st.add_boat("karbas", at + Vector3(5, 0, 0), 0.0)
	st.players["p1"]["aboard"] = boat
	(st.boats[boat]["cargo"] as Inventory).add("wood", 40)
	(st.boats[boat]["cargo"] as Inventory).add("raw_fish", 6)
	st.pieces["c"] = {"id": "chest", "pos": at, "rot": 0.0, "owner": "p1", "inv": Inventory.new(db, 16)}
	check(c.apply("p1", {"type": "unload", "boat": boat, "chest": "c"})["ok"], "all into the chest")
	eq((st.pieces["c"]["inv"] as Inventory).count("wood"), 40)
	check((st.boats[boat]["cargo"] as Inventory).is_empty(), "the hold is empty")
	eq(c.apply("p1", {"type": "unload", "boat": boat, "chest": "c"})["error"], "empty")


func test_build_menu_lists_every_piece_once() -> void:
	var seen: Array[String] = []
	for cat: Array in BuildMode.CATEGORIES:
		check(String(cat[0]).begins_with("build.cat."), "category key " + String(cat[0]))
		for id: String in cat[1]:
			check(db.pieces.has(id), "known piece " + id)
			check(not seen.has(id), "listed once " + id)
			seen.append(id)
	eq(seen.size(), db.pieces.size(), "every buildable piece is in the build menu")
