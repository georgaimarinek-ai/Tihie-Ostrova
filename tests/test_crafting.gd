extends "res://tests/lib/case.gd"


func test_hand_recipe() -> void:
	var c := new_world()
	var inv := c.state.inv("p1")
	eq(Crafting.check(db, c.state, "p1", "stone_axe"), "missing")
	inv.add("stone", 2)
	inv.add("branch", 3)
	inv.add("fiber", 2)
	eq(Crafting.apply(db, c.state, "p1", "stone_axe"), "")
	eq(inv.count("stone_axe"), 1)
	eq(inv.count("stone"), 0)


func test_station_must_be_near() -> void:
	var c := new_world()
	var inv := c.state.inv("p1")
	inv.add("wood", 20)
	inv.add("resin", 2)
	eq(Crafting.check(db, c.state, "p1", "smolye"), "no_station")
	c.state.pieces["far"] = {"id": "workbench", "pos": Vector3(30, 0, 0), "rot": 0.0, "owner": "p1"}
	eq(Crafting.check(db, c.state, "p1", "smolye"), "no_station", "a workbench 30 m away does not count")
	c.state.pieces["near"] = {"id": "workbench", "pos": Vector3(2, 0, 1), "rot": 0.0, "owner": "p1"}
	eq(Crafting.apply(db, c.state, "p1", "smolye"), "")
	eq(inv.count("smolye"), 1)


func test_locked_until_beacon() -> void:
	var c := new_world()
	c.state.inv("p1").add("birch_bark", 8)
	c.state.pieces["pit"] = {"id": "tar_pit", "pos": Vector3.ZERO, "rot": 0.0, "owner": "p1"}
	eq(Crafting.check(db, c.state, "p1", "tar"), "locked")
	c.state.lit["b01"] = 1
	eq(Crafting.check(db, c.state, "p1", "tar"), "")


func test_times_multiplies() -> void:
	var c := new_world()
	c.state.inv("p1").add("fiber", 12)
	c.state.pieces["wb"] = {"id": "workbench", "pos": Vector3.ZERO, "rot": 0.0, "owner": "p1"}
	eq(Crafting.apply(db, c.state, "p1", "rope", 3), "")
	eq(c.state.inv("p1").count("rope"), 3)
	eq(c.state.inv("p1").count("fiber"), 0)
