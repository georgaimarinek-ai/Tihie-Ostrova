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


func test_gathering_time_follows_rate_and_tool() -> void:
	var inv := Inventory.new(db)
	near(Gathering.unit_seconds(db, inv, "branch"), 60.0 / 20.0, 1e-6, "sticks by hand: 20 a minute")
	check(not Gathering.tool_ok(db, inv, "wood"), "wood needs an axe")
	inv.add("stone_axe", 1)
	near(Gathering.unit_seconds(db, inv, "wood"), 60.0 / 8.0, 1e-6, "stone axe: tier 1 speed")
	inv.add("iron_axe", 1)
	near(Gathering.unit_seconds(db, inv, "wood"), 60.0 / (8.0 * 1.75), 1e-6, "iron axe: 1.75x")
	check(not Gathering.tool_ok(db, Inventory.new(db), "larch"), "larch needs an iron axe")
	eq(Gathering.best_item(db, Inventory.new(db), ["wood", "resin"]), "", "no tools: nothing from a pine")
	var k := Inventory.new(db)
	k.add("knife", 1)
	eq(Gathering.best_item(db, k, ["wood", "resin"]), "resin", "a knife taps resin")


func test_fuel_says_how_it_is_made() -> void:
	var s := ItemInfo.how_made(db, ContentDB.bag(db.beacons["b01"]["fuel"]))
	check(s.contains(Loc.item(db, "resin")) and s.contains(Loc.item(db, "wood")), "the first beacon's fuel: from wood and resin")
	check(s.contains(Loc.name_of(db.pieces["workbench"]["name"])), "…at the workbench")
	eq(ItemInfo.how_made(db, {"resin": 1}), "", "resin is gathered as is")
