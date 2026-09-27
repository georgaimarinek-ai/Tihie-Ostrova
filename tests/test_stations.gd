extends "res://tests/lib/case.gd"
## Background stations (docs/01_GDD.md §9.3, roadmap phase 3) and food (§7.2).


func _world_with(piece: String) -> WorldCommands:
	var c := new_world("quiet", Vector3(1, 0, 1))
	c.state.lit["b01"] = 1  # the tar pit opens with b01
	c.state.pieces["s1"] = {"id": piece, "pos": Vector3(2, 0, 2), "rot": 0.0, "owner": "p1"}
	return c


func test_long_recipes_go_into_the_station() -> void:
	var c := _world_with("tar_pit")
	c.state.inv("p1").add("birch_bark", 24)
	eq(c.apply("p1", {"type": "craft", "recipe": "tar"})["error"], "background", "tar takes 60 s: load it")
	var r := c.apply("p1", {"type": "load_station", "uid": "s1", "recipe": "tar", "times": 2})
	check(r["ok"], "loaded: " + String(r["error"]))
	eq(c.state.inv("p1").count("birch_bark"), 8, "inputs taken at once")
	# the player walks away: the pit keeps working while time passes
	c.state.players["p1"]["pos"] = Vector3(300, 0, 300)
	var done := 0
	for i in 150:  # 150 s
		for e: Dictionary in c.apply("p1", {"type": "tick", "dt_min": 1.0 / 60.0})["events"]:
			if e["type"] == "station_done":
				done += 1
	eq(done, 2, "two units of tar in 120 s")
	eq(c.state.pieces["s1"]["out"], {"tar": 2})
	eq(c.state.pieces["s1"]["queue"], [], "queue empty")
	eq(c.apply("p1", {"type": "collect", "uid": "s1"})["error"], "too_far")
	c.state.players["p1"]["pos"] = Vector3(1, 0, 1)
	check(c.apply("p1", {"type": "collect", "uid": "s1"})["ok"], "collect")
	eq(c.state.inv("p1").count("tar"), 2)
	eq(c.apply("p1", {"type": "collect", "uid": "s1"})["error"], "empty")


func test_queue_limit_and_cancel_refunds() -> void:
	var c := _world_with("tar_pit")
	c.state.inv("p1").add("birch_bark", 50)
	c.state.inv("p1").add("birch_bark", 50)
	var cap := int(db.balance["stations"]["queue_max"])
	for i in cap:
		check(c.apply("p1", {"type": "load_station", "uid": "s1", "recipe": "tar"})["ok"], "load %d" % i)
	eq(c.apply("p1", {"type": "load_station", "uid": "s1", "recipe": "tar"})["error"], "queue_full")
	c.apply("p1", {"type": "tick", "dt_min": 0.5})  # half of the first unit is done
	var before := c.state.inv("p1").count("birch_bark")
	check(c.apply("p1", {"type": "cancel_station", "uid": "s1", "index": 0})["ok"], "cancel")
	eq(c.state.inv("p1").count("birch_bark"), before + 8, "a unit in progress comes back in full")
	eq((c.state.pieces["s1"]["queue"] as Array).size(), cap - 1)


func test_station_rules() -> void:
	var c := _world_with("workbench")
	c.state.inv("p1").add("birch_bark", 8)
	eq(c.apply("p1", {"type": "load_station", "uid": "s1", "recipe": "tar"})["error"], "wrong_station")
	eq(c.apply("p1", {"type": "load_station", "uid": "nope", "recipe": "tar"})["error"], "unknown_uid")
	c.state.pieces["s2"] = {"id": "hearth", "pos": Vector3(1, 0, 2), "rot": 0.0, "owner": "p1"}
	c.state.inv("p1").add("raw_fish", 2)
	eq(c.apply("p1", {"type": "load_station", "uid": "s2", "recipe": "cooked_fish"})["error"], "not_background", "20 s: made at once")
	check(c.apply("p1", {"type": "craft", "recipe": "cooked_fish"})["ok"], "short recipes still craft")
	c.state.pieces["s3"] = {"id": "kiln", "pos": Vector3(1, 0, 3), "rot": 0.0, "owner": "p1"}
	c.state.inv("p1").add("wood", 4)
	eq(c.apply("p1", {"type": "load_station", "uid": "s3", "recipe": "charcoal"})["error"], "locked", "charcoal opens with b04")


func test_stations_survive_a_save() -> void:
	var c := _world_with("tar_pit")
	c.state.inv("p1").add("birch_bark", 16)
	c.apply("p1", {"type": "load_station", "uid": "s1", "recipe": "tar", "times": 2})
	c.apply("p1", {"type": "tick", "dt_min": 1.0})
	c.apply("p1", {"type": "tick", "dt_min": 0.25})
	var back := SaveCodec.decode(db, SaveCodec.encode(c.state))
	eq(back.pieces["s1"]["out"], {"tar": 1})
	near(float(back.pieces["s1"]["queue"][0]["left_s"]), 45.0, 1e-3)
	eq(SaveCodec.encode(back), SaveCodec.encode(c.state))


func test_food_stacks_and_expires() -> void:
	var c := new_world()
	var st := c.state
	st.inv("p1").add("cloudberry", 3)
	st.inv("p1").add("cooked_fish", 1)
	st.inv("p1").add("mushroom", 1)
	st.inv("p1").add("lingonberry", 1)
	var base_hp := Vitals.max_hp(db, st, "p1")
	check(c.apply("p1", {"type": "eat", "item": "cloudberry"})["ok"], "eat")
	eq(c.apply("p1", {"type": "eat", "item": "cloudberry"})["error"], "already_eaten", "one of each dish")
	check(c.apply("p1", {"type": "eat", "item": "cooked_fish"})["ok"], "second slot")
	check(c.apply("p1", {"type": "eat", "item": "mushroom"})["ok"], "third slot")
	eq(c.apply("p1", {"type": "eat", "item": "lingonberry"})["error"], "food_full")
	var hp := float(db.items["cloudberry"]["food"]["hp"]) + float(db.items["cooked_fish"]["food"]["hp"]) + float(db.items["mushroom"]["food"]["hp"])
	near(Vitals.max_hp(db, st, "p1"), base_hp + hp, 1e-6, "bonuses stack")
	eq(c.apply("p1", {"type": "eat", "item": "stone"})["error"], "not_food")
	# cloudberry and mushroom last 10 minutes, the fish 15
	for i in 11:
		c.apply("p1", {"type": "tick", "dt_min": 1.0})
	eq((st.players["p1"]["food"] as Array).size(), 1, "short dishes wore off")
	eq(st.players["p1"]["food"][0]["id"], "cooked_fish")
	check(c.apply("p1", {"type": "eat", "item": "lingonberry"})["ok"], "room again")
	for i in 10:
		c.apply("p1", {"type": "tick", "dt_min": 1.0})
	eq(st.players["p1"]["food"], [])
	near(Vitals.max_hp(db, st, "p1"), base_hp, 1e-6, "back to the base, no hunger penalty")


func test_rested_speeds_stamina() -> void:
	var st := WorldState.new(db)
	st.add_player("p1")
	var base := Vitals.stamina_regen(db, st, "p1")
	st.players["p1"]["rested_until"] = 20.0
	near(Vitals.stamina_regen(db, st, "p1"), base * 1.5, 1e-6)
