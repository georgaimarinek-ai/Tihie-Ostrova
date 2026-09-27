extends "res://tests/lib/case.gd"


func _busy_world() -> WorldState:
	var c := new_world("saga", Vector3(3, 1, 4))
	var st := c.state
	st.inv("p1").add("wood", 17)
	st.inv("p1").add("stone_axe", 1)
	st.lit["b01"] = 2
	st.trials_done["b01"] = "defense"
	st.pieces["p9"] = {"id": "workbench", "pos": Vector3(1, 2, 3), "rot": 0.5, "owner": "p1"}
	st.boats["b1"] = {"type": "karbas", "pos": Vector3(0, 0, -30), "yaw": 1.5}
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


func test_migrates_v1() -> void:
	var v1 := {"version": 1, "world_seed": 5, "mode": "quiet", "lit": ["b01", "b02"], "players": {}}
	var st := WorldState.from_dict(db, v1)
	eq(st.lit, {"b01": 1, "b02": 1})
	eq(st.trials_done["b02"], "trial")
	eq(st.to_dict()["version"], WorldState.VERSION)


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
