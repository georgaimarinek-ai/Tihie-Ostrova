extends "res://tests/lib/case.gd"
## Tool wear (docs/08_NEXT.md stage 14, docs/01_GDD.md §6): a tool spends one use per unit gathered, dulls at
## balance.wear.dull_at (half speed), breaks at the end (stays in the bag, counts as no tool), is mended at
## its recipe's station for a share of the recipe. Off in Quiet. Wear travels through saves and chests.


func _world(mode: String) -> WorldCommands:
	var st := WorldState.new(db, 7, mode)
	st.add_player("p1", Vector3.ZERO)
	return WorldCommands.new(db, st)  # no map: gather skips the reach checks


func _slot(inv: Inventory, id: String) -> Dictionary:
	for s: Dictionary in inv.slots:
		if s.get("id", "") == id:
			return s
	return {}


func test_wear_spends_dulls_and_breaks() -> void:
	var c := _world("tale")
	var inv := c.state.inv("p1")
	inv.add("knife", 1)
	var total := Tools.uses(db, "knife")
	check(total > 0, "a knife has uses")
	var dull_at := int(ceil(total * float(db.balance["wear"]["dull_at"])))
	var worn := 0
	var events: Array[String] = []
	while worn < total:
		var r := c.apply("p1", {"type": "gather", "node": "home:%d" % worn, "item": "resin", "qty": 5})
		check(r["ok"], "cutting resin")
		for e: Dictionary in r["events"]:
			if e["type"] == "tool_worn":
				events.append(String(e["condition"]))
		worn += 5
		inv.remove("resin", inv.count("resin"))
	eq(int(_slot(inv, "knife")["wear"]), total, "worn to the end")
	eq(events, ["dull", "broken"], "the HUD hears it dull, then break")
	eq(Tools.condition(db, _slot(inv, "knife")), Tools.BROKEN)
	eq(inv.count("knife"), 1, "the knife is still in the bag")
	eq(c.apply("p1", {"type": "gather", "node": "home:99", "item": "resin", "qty": 1})["error"], "tool_broken", "but it cuts no more")
	check(not Gathering.tool_ok(db, inv, "resin", true) and Gathering.tool_ok(db, inv, "resin", false), "broken counts only with the rule on")
	# a dull knife works at half speed
	_slot(inv, "knife")["wear"] = dull_at
	eq(Tools.condition(db, _slot(inv, "knife")), Tools.DULL)
	near(Gathering.unit_seconds(db, inv, "resin", true), Gathering.unit_seconds(db, inv, "resin", false) / float(db.balance["wear"]["dull_speed"]), 1e-6, "dull: twice as long")
	# the best working tool is used: a second, whole knife takes over from the broken one
	_slot(inv, "knife")["wear"] = total
	inv.add("knife", 1)
	check(c.apply("p1", {"type": "gather", "node": "home:98", "item": "resin", "qty": 2})["ok"], "the fresh knife cuts")
	var wears: Array[int] = []
	for s: Dictionary in inv.slots:
		if s.get("id", "") == "knife":
			wears.append(int(s.get("wear", 0)))
	wears.sort()
	eq(wears, [2, total], "the fresh one wore, the broken one didn't")


func test_quiet_has_no_wear() -> void:
	var c := _world("quiet")
	var inv := c.state.inv("p1")
	inv.add("stone_axe", 1)
	_slot(inv, "stone_axe")["wear"] = Tools.uses(db, "stone_axe")  # brought over from a Tale world
	check(c.apply("p1", {"type": "gather", "node": "home:1", "item": "wood", "qty": 5})["ok"], "a broken axe still chops in Quiet")
	eq(int(_slot(inv, "stone_axe")["wear"]), Tools.uses(db, "stone_axe"), "and wears no further")
	check(c.apply("p1", {"type": "set_tuning", "rule": "durability", "value": true})["ok"], "fine tuning turns wear on")
	eq(c.apply("p1", {"type": "gather", "node": "home:2", "item": "wood", "qty": 5})["error"], "tool_broken")


func test_repair_costs_a_share_of_the_recipe() -> void:
	eq(Tools.repair_cost(db, "knife", Tools.BROKEN), {"flint": 1, "branch": 1, "fiber": 1}, "half of 2/1/1, rounded up")
	eq(Tools.repair_cost(db, "knife", Tools.DULL), {"flint": 1}, "a quarter of the largest input")
	eq(Tools.repair_cost(db, "iron_axe", Tools.BROKEN), {"iron": 2, "wood": 1})
	eq(Tools.repair_cost(db, "iron_axe", Tools.DULL), {"iron": 1})
	eq(Tools.repair_cost(db, "knife", Tools.OK), {}, "a whole tool costs nothing")
	eq(Tools.repair_station(db, "knife"), "workbench", "hand recipes are mended at the workbench")
	eq(Tools.repair_station(db, "fishing_rod"), "workbench")
	eq(Tools.repair_station(db, "iron_axe"), "forge", "the forge mends what it made")
	var c := _world("tale")
	var inv := c.state.inv("p1")
	inv.add("knife", 1)
	_slot(inv, "knife")["wear"] = Tools.uses(db, "knife")
	var slot := Tools.best_slot(db, inv, "knife", false)
	c.state.pieces["wb"] = {"id": "workbench", "pos": Vector3(2, 0, 0), "rot": 0.0, "owner": "p1"}
	c.state.pieces["fg"] = {"id": "forge", "pos": Vector3(0, 0, 2), "rot": 0.0, "owner": "p1"}
	eq(c.apply("p1", {"type": "repair", "uid": "fg", "slot": slot})["error"], "wrong_station", "not at the forge")
	eq(c.apply("p1", {"type": "repair", "uid": "wb", "slot": slot})["error"], "missing", "no flint, no repair")
	inv.add("flint", 1)
	inv.add("branch", 1)
	inv.add("fiber", 1)
	var r := c.apply("p1", {"type": "repair", "uid": "wb", "slot": slot})
	check(r["ok"], "mended")
	eq(r["events"][0]["cost"], {"flint": 1, "branch": 1, "fiber": 1})
	eq(Tools.condition(db, inv.slots[slot]), Tools.OK, "as good as new")
	eq(inv.count("flint"), 0)
	eq(c.apply("p1", {"type": "repair", "uid": "wb", "slot": slot})["error"], "not_worn", "nothing to mend")
	c.state.players["p1"]["pos"] = Vector3(50, 0, 0)
	inv.slots[slot]["wear"] = 5
	eq(c.apply("p1", {"type": "repair", "uid": "wb", "slot": slot})["error"], "not_worn", "5 of 80 isn't dull yet")
	inv.slots[slot]["wear"] = Tools.uses(db, "knife") - 1
	eq(c.apply("p1", {"type": "repair", "uid": "wb", "slot": slot})["error"], "too_far", "far from the bench")


func test_wear_survives_saves_and_chests() -> void:
	var st := WorldState.new(db, 3, "tale")
	st.add_player("p1", Vector3.ZERO)
	var inv := st.inv("p1")
	inv.add("stone_axe", 1)
	inv.add("wood", 3)
	_slot(inv, "stone_axe")["wear"] = 42
	var back := SaveCodec.decode(db, SaveCodec.encode(st))
	eq(int(_slot(back.inv("p1"), "stone_axe")["wear"]), 42, "wear is saved")
	check(not _slot(back.inv("p1"), "wood").has("wear"), "plain items carry none")
	eq(WorldState.VERSION, 5, "save format v5")
	var old := st.to_dict()
	old["version"] = 4
	for s: Dictionary in old["players"]["p1"]["inv"]["slots"]:
		s.erase("wear")
	var migrated := WorldState.from_dict(db, old)
	eq(Tools.condition(db, _slot(migrated.inv("p1"), "stone_axe")), Tools.OK, "a v4 bag: every tool whole")
	# into a chest and back
	var c := WorldCommands.new(db, st)
	st.pieces["ch"] = {"id": "chest", "pos": Vector3.ZERO, "rot": 0.0, "owner": "p1", "inv": Inventory.new(db, 12)}
	var slot := Tools.best_slot(db, inv, "axe", false)
	check(c.apply("p1", {"type": "store", "uid": "ch", "slot": slot})["ok"], "axe into the chest")
	var box: Inventory = st.pieces["ch"]["inv"]
	eq(int(_slot(box, "stone_axe")["wear"]), 42, "the chest remembers the wear")
	check(c.apply("p1", {"type": "take", "uid": "ch", "slot": 0})["ok"], "and back")
	eq(int(_slot(inv, "stone_axe")["wear"]), 42)
