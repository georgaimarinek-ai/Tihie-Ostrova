extends "res://tests/lib/case.gd"


func test_loads_and_validates() -> void:
	var fresh := ContentDB.new()
	eq(fresh.load_dir(), OK)
	var problems := fresh.validate()
	check(problems.is_empty(), "validate(): " + ", ".join(problems))


func test_expected_shape() -> void:
	eq(db.beacon_order.size(), 12, "beacons")
	eq(db.regions.size(), 4, "regions")
	eq(db.modes.size(), 3, "modes")
	check(db.beacon_order == ["b01", "b02", "b03", "b04", "b05", "b06", "b07", "b08", "b09", "b10", "b11", "b12"], "beacon order")
	for bid in db.beacon_order:
		check(float(db.beacons[bid]["clear_radius"]) > 0.0, bid + " clear_radius")


func test_beacons_sit_in_their_region_ring() -> void:
	for bid in db.beacon_order:
		eq(db.region_at(db.beacon_pos(bid)), String(db.beacons[bid]["region"]), bid)


func test_regions_open_in_order() -> void:
	var lit := {}
	check(db.region_open("r1", lit), "r1 open at start")
	check(not db.region_open("r2", lit), "r2 locked at start")
	lit["b03"] = 1
	check(db.region_open("r2", lit), "b03 opens r2")


func test_unlocks_of_b06_include_the_boatyard() -> void:
	var u := db.unlocks_of("b06")
	check("boatyard" in u["pieces"], "boatyard")
	check("shnyaka" in u["boats"], "shnyaka")
	eq(u["region"], "r3")


func test_numbers_become_ints() -> void:
	var fuel := ContentDB.bag(db.beacons["b01"]["fuel"])
	eq(typeof(fuel["smolye"]), TYPE_INT)


## Design rule (GDD §11): spirits, wonders and legends are in every mode and never hurt anyone.
func test_spirits_are_always_friendly() -> void:
	var count := 0
	for c: Dictionary in db.creatures.values():
		if c["group"] in ["spirit", "wonder", "legend"]:
			count += 1
			eq(int(c["damage"]), 0, c["id"] + " damage")
			eq(c["modes"].size(), 3, c["id"] + " modes")
	check(count >= 7, "spirits present: %d" % count)
	for c: Dictionary in db.creatures.values():
		if c["group"] in ["fog", "elite", "guardian"]:
			eq(c["modes"], ["saga"], c["id"] + " only in Saga")
