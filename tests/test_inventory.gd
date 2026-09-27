extends "res://tests/lib/case.gd"


func test_stacks_and_spills() -> void:
	var inv := Inventory.new(db, 3)
	eq(inv.add("stone", 120), 0)  # stack 50: 50 + 50 + 20
	eq(inv.count("stone"), 120)
	eq(inv.add("wood", 10), 10, "no free slot left")
	eq(inv.add("stone", 40), 10, "last stack fills to 50")


func test_remove_bag_is_all_or_nothing() -> void:
	var inv := Inventory.new(db, 5)
	inv.add("stone", 3)
	inv.add("wood", 2)
	check(not inv.remove_bag({"stone": 2, "wood": 5}), "not enough wood")
	eq(inv.count("stone"), 3, "nothing removed")
	check(inv.remove_bag({"stone": 2, "wood": 2}), "enough")
	eq(inv.count("stone"), 1)
	eq(inv.count("wood"), 0)
	eq(inv.missing({"stone": 4}), {"stone": 3})


func test_best_tool_tier() -> void:
	var inv := Inventory.new(db)
	eq(inv.best_tool_tier("axe"), 0)
	inv.add("stone_axe", 1)
	eq(inv.best_tool_tier("axe"), 1)
	inv.add("iron_axe", 1)
	eq(inv.best_tool_tier("axe"), 2)


func test_round_trip() -> void:
	var inv := Inventory.new(db, 6)
	inv.add("cloudberry", 7)
	inv.add("stone_axe", 1)
	var copy := Inventory.new(db, 1)
	copy.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	eq(copy.size, 6)
	eq(copy.count("cloudberry"), 7)
	eq(copy.count("stone_axe"), 1)
