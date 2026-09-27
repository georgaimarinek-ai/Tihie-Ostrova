extends "res://tests/lib/case.gd"


func test_clearing_around_a_lit_beacon() -> void:
	var st := WorldState.new(db)
	var p := db.beacon_pos("b01")
	near(FogField.factor(db, st, p), 1.0, 1e-6, "dark beacon: full fog")
	st.lit["b01"] = 1
	var clear := float(db.balance["fog"]["clear_factor"])
	near(FogField.factor(db, st, p), clear, 0.05, "centre of the clearing")
	var r := float(db.beacons["b01"]["clear_radius"])
	near(FogField.factor(db, st, p + Vector2(r * 1.01, 0)), 1.0, 1e-3, "outside the radius")


func test_locked_region_is_a_wall() -> void:
	var st := WorldState.new(db)
	check(FogField.factor(db, st, db.beacon_pos("b05")) > 2.0, "r2 is locked at start")
	st.lit["b03"] = 1
	near(FogField.factor(db, st, db.beacon_pos("b05")), 1.0, 1e-6, "r2 open after b03")


func test_shader_slots_pick_nearest() -> void:
	var st := WorldState.new(db)
	for bid in ["b01", "b02", "b03", "b04", "b05"]:
		st.lit[bid] = 1
	var lantern := Vector4(1, 2, 14, 0.9)
	var slots := FogField.shader_slots(db, st, db.beacon_pos("b02"), [lantern])
	eq(slots.size(), FogField.SLOTS)
	eq(slots[0], lantern, "extra lights first")
	var b02 := db.beacon_pos("b02")
	eq(Vector2(slots[1].x, slots[1].y), b02, "then the nearest beacon")
	var empty := FogField.shader_slots(db, WorldState.new(db), Vector2.ZERO)
	eq(empty[FogField.SLOTS - 1], Vector4.ZERO, "unused slots are zero")
	var many: Array[Vector4] = []
	for i in 12:
		many.append(Vector4(i, 0, 5, 1))
	var crowded := FogField.shader_slots(db, st, Vector2.ZERO, many)
	eq(crowded.size(), FogField.SLOTS)
	check(crowded[FogField.SLOTS - 1].z > 100.0, "extra lights never push out the nearest beacons")
