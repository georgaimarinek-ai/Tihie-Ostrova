extends "res://tests/lib/case.gd"


func _busy_world() -> WorldState:
	var c := new_world("saga", Vector3(3, 1, 4))
	var st := c.state
	st.inv("p1").add("wood", 17)
	st.inv("p1").add("stone_axe", 1)
	st.lit["b01"] = 2
	st.trials_done["b01"] = "defense"
	st.pieces["p9"] = {"id": "workbench", "pos": Vector3(1, 2, 3), "rot": 0.5, "owner": "p1"}
	var boat := st.add_boat("karbas", Vector3(0, 0, -30), 1.5)
	(st.boats[boat]["cargo"] as Inventory).add("stone", 7)
	st.players["p1"]["aboard"] = boat
	st.players["p1"]["food"] = [{"id": "cloudberry", "until": 130.0}]
	st.pieces["p10"] = {"id": "chest", "pos": Vector3(4, 1, 4), "rot": 0.0, "owner": "p1", "inv": Inventory.new(db, 16)}
	(st.pieces["p10"]["inv"] as Inventory).add("resin", 3)
	st.pieces["p11"] = {"id": "tar_pit", "pos": Vector3(6, 1, 4), "rot": 0.0, "owner": "p1", "queue": [{"recipe": "tar", "times": 2, "left_s": 30.0}]}
	st.journal["first_fire"] = 2
	st.tuning["storms"] = "cosmetic"
	st.depleted["home:4"] = 5
	st.day = 4
	st.clock_min = 123.5
	return st


func test_round_trip_is_exact() -> void:
	var st := _busy_world()
	var text := SaveCodec.encode(st)
	var back := SaveCodec.decode(db, text)
	check(back != null, "decoded")
	eq(SaveCodec.encode(back), text)
	eq(back.inv("p1").count("wood"), 17)
	eq(back.pieces["p9"]["pos"], Vector3(1, 2, 3))
	eq(back.day, 4)
	var boat: String = back.players["p1"]["aboard"]
	eq((back.boats[boat]["cargo"] as Inventory).count("stone"), 7, "the hold survives a save")
	eq((back.boats[boat]["cargo"] as Inventory).size, int(db.boats["karbas"]["cargo_slots"]))
	eq((back.pieces["p10"]["inv"] as Inventory).count("resin"), 3, "chest contents")
	eq(back.pieces["p11"]["queue"][0]["times"], 2, "station queue")
	eq(back.players["p1"]["food"][0]["id"], "cloudberry")
	eq(back.journal, {"first_fire": 2})


func test_migrates_v1() -> void:
	var v1 := {"version": 1, "world_seed": 5, "mode": "quiet", "lit": ["b01", "b02"], "players": {}}
	var st := WorldState.from_dict(db, v1)
	eq(st.lit, {"b01": 1, "b02": 1})
	eq(st.trials_done["b02"], "trial")
	eq(st.to_dict()["version"], WorldState.VERSION)


func test_migrates_v2() -> void:
	var v2 := {"version": 2, "world_seed": 5, "mode": "saga", "day": 3, "clock_min": 70.0, "lit": {"b01": 2}, "trials_done": {"b01": "defense"},
		"busy_beacon": "", "pieces": {}, "graves": {}, "depleted": {}, "next_uid": 4,
		"players": {"p1": {"inv": {"size": 24, "slots": []}, "pos": [1, 2, 3], "spawn": [0, 0, 0], "weary_until": 0.0}},
		"boats": {"b1": {"type": "shnyaka", "pos": [0, 0, -20], "yaw": 0.5}}}
	var st := WorldState.from_dict(db, v2)
	eq(st.players["p1"]["aboard"], "")
	eq(st.players["p1"]["food"], [])
	eq((st.boats["b1"]["cargo"] as Inventory).size, int(db.boats["shnyaka"]["cargo_slots"]), "hold sized by the boat type")
	eq(st.to_dict()["version"], WorldState.VERSION)
	eq(SaveCodec.encode(WorldState.from_dict(db, st.to_dict())), SaveCodec.encode(st), "migrated world round-trips")


func test_backups_rescue_a_broken_save() -> void:
	var dir := "user://test_worlds/%d" % Time.get_ticks_usec()
	var st := _busy_world()
	eq(SaveCodec.save_world(st, dir), OK)
	st.day = 9
	eq(SaveCodec.save_world(st, dir), OK)
	eq(SaveCodec.load_world(db, dir).day, 9)
	var f := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var rescued := SaveCodec.load_world(db, dir)
	check(rescued != null, "fell back to a backup")
	eq(rescued.day, 4, "the previous save")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)


func _dir(tag: String) -> String:
	return "user://test_worlds/%s_%d" % [tag, randi()]


func _wipe(dir: String) -> void:
	SaveCodec.delete_world(dir)


func test_migrates_v1_all_the_way_to_v4() -> void:
	var v1 := {"world_seed": 9, "mode": "tale", "lit": ["b01"], "players": {"p1": {"inv": {"slots": []}, "pos": [1, 2, 3], "spawn": [0, 0, 0], "weary_until": 0.0}}}
	var s := WorldState.from_dict(db, v1)
	eq(s.lit.keys(), ["b01"])
	eq(s.trials_done["b01"], "trial", "v1→v2: lit beacons count as passed")
	eq(s.players["p1"]["aboard"], "", "v2→v3: aboard nothing")
	near(float(s.players["p1"]["hp"]), 100.0, 1e-6, "v3→v4: full health")
	eq(s.players["p1"]["landed"], Vector3.ZERO, "v3→v4: last landing = spawn")
	eq(s.creatures, {}, "v3→v4: no creatures")
	eq(WorldState.migrate(v1)["version"], WorldState.VERSION)


func test_a_broken_save_says_which_backup_came_back() -> void:
	var dir := _dir("restore")
	var st := _busy_world()
	st.name = "Проба"
	check(SaveCodec.save_world(st, dir) == OK, "saved")
	st.day = 5
	check(SaveCodec.save_world(st, dir) == OK, "saved again (a backup now)")
	var f := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	var back := SaveCodec.load_world(db, dir)
	check(back != null, "the world comes back")
	eq(SaveCodec.last_restored, 1, "from backup 1 (the UI says so)")
	eq(back.day, 4, "as it was one save ago")
	eq(SaveCodec.backups(dir), 1)
	for i in range(1, SaveCodec.BACKUPS + 1):
		if FileAccess.file_exists(dir.path_join("world.%d.json" % i)):
			var g := FileAccess.open(dir.path_join("world.%d.json" % i), FileAccess.WRITE)
			g.store_string("nope")
			g.close()
	check(SaveCodec.load_world(db, dir) == null, "all broken: nothing, never a half world")
	eq(SaveCodec.last_restored, -1)
	_wipe(dir)


func test_world_slots_list_and_delete() -> void:
	var root := "user://test_worlds/slots_%d" % randi()
	var a := _busy_world()
	a.name = "Первая"
	var b := _busy_world()
	b.name = "Вторая"
	b.day = 9
	SaveCodec.save_world(a, root.path_join("first"))
	SaveCodec.save_world(b, root.path_join("second"))
	var all := SaveCodec.list_worlds(db, root)
	eq(all.size(), 2, "two slots")
	var names: Array = all.map(func(w: Dictionary) -> String: return w["name"])
	check(names.has("Первая") and names.has("Вторая"), "named slots")
	check(SaveCodec.delete_world(root.path_join("first")) == OK, "deleted")
	eq(SaveCodec.list_worlds(db, root).size(), 1, "one left")
	_wipe(root.path_join("second"))
	DirAccess.remove_absolute(root)


func test_settings_round_trip() -> void:
	var s := GameSettings.new()
	s.path = "user://test_settings_%d.cfg" % randi()
	s.quality = "low"
	s.fullscreen = true
	s.volume["Music"] = 0.25
	s.keys["jump"] = KEY_J
	s.language = "en"
	check(s.save_file() == OK, "saved")
	var t := GameSettings.new()
	t.path = s.path
	t.load_file()
	eq(t.quality, "low")
	eq(t.rendering_method(), "gl_compatibility", "light = Compatibility")
	eq(t.fullscreen, true)
	near(float(t.volume["Music"]), 0.25, 1e-6)
	eq(int(t.keys["jump"]), KEY_J)
	eq(t.language, "en")
	DirAccess.remove_absolute(s.path)
