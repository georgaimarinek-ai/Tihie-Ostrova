extends "res://tests/lib/case.gd"
## The living sea (docs/08_NEXT.md stage 13): shoals, the tide, squall warnings and the vodyanoy's mood are pure
## in seed and clock (SeaLife); flotsam, a tailwind after a beacon, boat fittings and the Puchinnik's grip are
## commands on the host. The Puchinnik is a Saga creature of deep, foggy night water, never of the shallows.


func _world(mode: String, pos: Vector3 = Vector3(20, 0, 20)) -> WorldCommands:
	var st := WorldState.new(db, 7, mode)
	st.add_player("p1", pos)
	return WorldCommands.new(db, st, WorldMap.shared(db))


func test_shoals_and_tide_are_the_same_for_everyone() -> void:
	var on := 0
	for m in 180:
		if SeaLife.shoal_active(db, 7, float(m), "sea:12:-40"):
			on += 1
	var s: Dictionary = db.balance["sea_events"]["shoal"]
	near(float(on) / 180.0, float(s["lasts_min"]) / float(s["every_min"]), 0.03, "a shoal lasts its share of the time")
	check(SeaLife.shoal_active(db, 7, 10.0, "sea:12:-40") == SeaLife.shoal_active(db, 7, 10.0, "sea:12:-40"), "deterministic")
	var differs := false
	for m in 60:
		if SeaLife.shoal_active(db, 7, float(m), "sea:12:-40") != SeaLife.shoal_active(db, 7, float(m), "sea:200:8"):
			differs = true
	check(differs, "spots have their own clocks")
	eq(SeaLife.shoal_factor(db, 7, 0.0, "x"), float(s["bite_bonus"]) if SeaLife.shoal_active(db, 7, 0.0, "x") else 1.0)
	# the tide: low for a third of the day, the sea a metre lower, eased at the turn
	var day := float(db.balance["day"]["length_min"])
	var low := 0
	for m in 300:
		if SeaLife.tide_low(db, m * day / 300.0):
			low += 1
	near(float(low) / 300.0, float(db.balance["sea_events"]["tide"]["low_share"]), 0.03, "low water a third of the day")
	var mid := (float(db.balance["sea_events"]["tide"]["low_from"]) + 0.1 - 0.25) * day  # day_phase starts at 0.25
	near(SeaLife.tide_offset(db, mid), -float(db.balance["sea_events"]["tide"]["drop_m"]), 1e-6, "a metre down at low water")
	eq(SeaLife.tide_offset(db, 0.0), 0.0, "high water at dawn")
	check(SeaLife.tide_turns_in(db, mid) > 0.0 and SeaLife.tide_turns_in(db, 0.0) == 0.0, "minutes until the flood")
	check(SeaLife.tide_only(db, "pearl_shoal") and not SeaLife.tide_only(db, "pine"), "pearl shoals wait for the ebb")


func test_the_ebb_bares_the_pearl_shoals() -> void:
	var c := _world("quiet")
	var shoal: Dictionary = {}
	for isl: IslandGen in c.map.islands:
		for n: Dictionary in c.map.nodes(isl.id):
			if String(n["kind"]) == "pearl_shoal":
				shoal = n
				break
		if not shoal.is_empty():
			break
	check(not shoal.is_empty(), "a pearl shoal somewhere on the Ter Coast")
	for b in ["b01", "b02", "b03", "b04", "b05", "b06"]:
		c.state.lit[b] = 1
	c.state.players["p1"]["pos"] = shoal["pos"]
	var day := float(db.balance["day"]["length_min"])
	c.state.clock_min = 0.0
	eq(c.apply("p1", {"type": "gather", "node": shoal["id"], "item": "pearl", "qty": 1})["error"], "tide", "high water: no")
	c.state.clock_min = (float(db.balance["sea_events"]["tide"]["low_from"]) + 0.1 - 0.25) * day
	check(c.apply("p1", {"type": "gather", "node": shoal["id"], "item": "pearl", "qty": 1})["ok"], "low water: a pearl")


func test_squall_warning_and_the_vodyanoy_mood() -> void:
	var warned := false
	var stormy := false
	for i in 4000:
		var m := i * 0.25
		if SeaLife.squall_coming(db, 7, m, "r3"):
			warned = true
			check(Weather.storm(db, 7, m + float(db.balance["sea_events"]["squall_warning_min"]), "r3") > Weather.storm(db, 7, m, "r3"), "it says so only before a worse storm")
		if Weather.storm(db, 7, m, "r3") > 0:
			stormy = true
	check(warned and stormy, "storms come, and the warning comes first")
	var c := _world("tale")
	eq(SeaLife.vodyanoy_bite_factor(db, c.state, "r2"), 1.0, "never met: nothing")
	c.state.spirits["vodyanoy"] = {"day": 1}
	c.state.day = 1
	near(SeaLife.vodyanoy_bite_factor(db, c.state, "r2"), 1.3, 1e-6, "his fish today: +30 %")
	c.state.day = 4
	check(SeaLife.vodyanoy_angry(db, c.state), "three days forgotten")
	near(SeaLife.vodyanoy_bite_factor(db, c.state, "r2"), 0.7, 1e-6, "he sulks: -30 %")
	eq(SeaLife.vodyanoy_bite_factor(db, c.state, "r1"), 1.0, "not his waters")
	eq(SeaLife.aurora_boost(db, "r4", 1.0, 0), float(db.balance["sea_events"]["aurora_boost"]), "clear night over the Frozen Sea")
	eq(SeaLife.aurora_boost(db, "r4", 1.0, 1), 1.0, "not in a storm")
	eq(SeaLife.aurora_boost(db, "r1", 1.0, 0), 1.0, "not in the south")


func test_flotsam_and_the_tailwind() -> void:
	var c := _world("quiet")
	var st := c.state
	var uid := st.add_boat("karbas", Vector3(0, 0, -600), 0.0)
	st.players["p1"]["aboard"] = uid
	st.players["p1"]["pos"] = Vector3(0, 0, -600)
	eq(c.apply("p1", {"type": "flotsam", "kind": "crate", "pos": [0, 0, -605]})["error"], "bad_value")
	eq(c.apply("p1", {"type": "flotsam", "kind": "log", "pos": [0, 5, 0]})["error"], "bad_pos", "not on land")
	var r := c.apply("p1", {"type": "flotsam", "kind": "log", "pos": [0, 0, -605]})
	check(r["ok"], "a log afloat")
	var fid := String(r["events"][0]["uid"])
	st.players["p1"]["pos"] = Vector3(0, 0, -630)
	eq(c.apply("p1", {"type": "pick_flotsam", "uid": fid})["error"], "too_far")
	st.players["p1"]["pos"] = Vector3(0, 0, -600)
	check(c.apply("p1", {"type": "pick_flotsam", "uid": fid})["ok"], "hauled in from the boat")
	eq(st.inv("p1").count("wood"), 4, "four logs' worth")
	check(not st.flotsam.has(fid), "gone from the water")
	var bottle := String(c.apply("p1", {"type": "flotsam", "kind": "bottle", "pos": [2, 0, -600]})["events"][0]["uid"])
	var pr := c.apply("p1", {"type": "pick_flotsam", "uid": bottle})
	check(pr["ok"] and pr["events"].size() == 2 and pr["events"][1]["page"] == "sea_bottle", "a note for the journal")
	var old := String(c.apply("p1", {"type": "flotsam", "kind": "barrel", "pos": [4, 0, -600]})["events"][0]["uid"])
	var tick := c.apply("p1", {"type": "tick", "dt_min": 1.0})
	check(st.flotsam.has(old), "still there a minute later")
	st.clock_min += float(db.balance["sea_events"]["flotsam"]["lasts_min"])
	tick = c.apply("p1", {"type": "tick", "dt_min": 0.1})
	check(not st.flotsam.has(old) and tick["events"].any(func(e: Dictionary) -> bool: return e["type"] == "flotsam_gone"), "drifts away")
	check(WorldCommands.HOST_ONLY.has("flotsam") and WorldCommands.HOST_ONLY.has("grapple") and WorldCommands.HOST_ONLY.has("release"), "the sea is the host's")
	# a tailwind after a beacon
	eq(SeaLife.tailwind(db, st), 1.0)
	st.players["p1"]["aboard"] = ""
	st.players["p1"]["pos"] = Vector3(db.beacon_pos("b01").x, 0, db.beacon_pos("b01").y)
	st.trials_done["b01"] = "trial"
	st.inv("p1").add("smolye", 3)
	check(c.apply("p1", {"type": "light_beacon", "beacon": "b01"})["ok"], "lit")
	near(SeaLife.tailwind(db, st), float(db.balance["sea_events"]["tailwind"]["factor"]), 1e-6, "the wind favours the boat")
	st.clock_min += float(db.balance["sea_events"]["tailwind"]["minutes"]) + 0.1
	eq(SeaLife.tailwind(db, st), 1.0, "and drops after two minutes")


func test_the_boat_lantern() -> void:
	var c := _world("quiet", Vector3(0, 0, 0))
	var st := c.state
	var yard := st.pieces
	yard["y"] = {"id": "boatyard", "pos": Vector3(2, 0, 0), "rot": 0.0, "owner": "p1"}
	var uid := st.add_boat("karbas", Vector3(20, 0, 0), 0.0)
	eq(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "sail_of_gold"})["error"], "unknown_part")
	eq(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "lantern"})["error"], "locked", "after b06")
	for b in ["b01", "b02", "b03", "b04", "b05", "b06"]:
		st.lit[b] = 1
	eq(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "lantern"})["error"], "missing")
	st.inv("p1").add("iron", 2)
	st.inv("p1").add("fish_oil", 4)
	st.boats[uid]["pos"] = Vector3(80, 0, 0)
	eq(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "lantern"})["error"], "too_far", "the boat must lie by the yard")
	st.boats[uid]["pos"] = Vector3(20, 0, 0)
	check(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "lantern"})["ok"], "fitted")
	eq(st.boats[uid]["parts"], ["lantern"])
	eq(st.inv("p1").count("iron"), 0)
	eq(c.apply("p1", {"type": "fit_boat", "uid": "y", "boat": uid, "part": "lantern"})["error"], "already_done")
	var back := SaveCodec.decode(db, SaveCodec.encode(st))
	eq(back.boats[uid]["parts"], ["lantern"], "saved with the boat")


func test_the_puchinnik_lives_in_deep_foggy_nights() -> void:
	var r := db.mode_rules("saga")
	eq(Creatures.group(db, "puchinnik"), "fog", "a creature of the Mga")
	check(not Creatures.is_friendly(db, "puchinnik") and not Creatures.allowed(db, "tale", db.mode_rules("tale"), "puchinnik"), "Saga only")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r3", 0.8, 1.0, false, -20.0, 500.0), "", "deep, foggy, dark, far from beacons: yes")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r3", 0.8, 1.0, false, -3.0, 500.0), "shallow")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r3", 0.8, 1.0, false, -20.0, 60.0), "near_beacon")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r3", 0.2, 1.0, false, -20.0, 500.0), "clear")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r3", 0.8, 0.0, false, -20.0, 500.0), "daylight")
	eq(Creatures.spawn_block(db, "saga", r, "puchinnik", "r1", 0.8, 1.0, false, -20.0, 500.0), "not_in_this_region")
	eq(Creatures.spawn_block(db, "saga", r, "mglyak", "r1", 0.8, 1.0, false, -3.0, 10.0), "", "depth and beacons mean nothing to a land creature")


func test_the_grip_and_the_harpoon() -> void:
	var c := _world("saga")
	var st := c.state
	var at := Vector3(0, 0, -2000)
	var uid := st.add_boat("shnyaka", at, 0.0)
	st.players["p1"]["aboard"] = uid
	st.players["p1"]["pos"] = at
	var p := st.new_uid("c")
	st.creatures[p] = {"id": "puchinnik", "pos": at + Vector3(14, 0, 0), "hp": 260.0, "fight": ""}
	var wolf := st.new_uid("c")
	st.creatures[wolf] = {"id": "fog_wolf", "pos": at + Vector3(3, 0, 0), "hp": 110.0, "fight": ""}
	eq(c.apply("p1", {"type": "grapple", "boat": uid, "source": wolf})["error"], "no_fight", "only a creature of the sea grips a hull")
	eq(c.apply("p1", {"type": "grapple", "boat": uid, "source": p})["error"], "too_far")
	st.creatures[p]["pos"] = at + Vector3(4, 0, 0)
	check(c.apply("p1", {"type": "grapple", "boat": uid, "source": p})["ok"], "gripped")
	eq(st.boats[uid]["held"], p)
	eq(c.apply("p1", {"type": "grapple", "boat": uid, "source": p})["error"], "busy")
	# a thrown harpoon reaches it from the deck; a spear does not
	st.creatures[p]["pos"] = at + Vector3(9, 0, 0)
	st.inv("p1").add("spear", 1)
	eq(c.apply("p1", {"type": "attack", "target": p, "weapon": "spear"})["error"], "too_far", "a spear reaches 2.4 m")
	st.inv("p1").add("harpoon", 1)
	eq(c.apply("p1", {"type": "attack", "target": p, "weapon": "harpoon"})["error"], "too_far", "a harpoon thrust: no")
	var hit := c.apply("p1", {"type": "attack", "target": p, "weapon": "harpoon", "thrown": true})
	check(hit["ok"], "thrown: 12 m")
	near(float(hit["events"][0]["amount"]), 38.0 * float(db.balance["combat"]["light_vs_fog"]) if not (st.players["p1"]["light"] as Dictionary).is_empty() else 38.0, 1e-6)
	eq(st.inv("p1").count("harpoon"), 1, "hauled back on its line")
	# its grip rolls the boat over whatever the weather; the roll lets go
	st.clock_min = 0.0
	var roll := c.apply("p1", {"type": "capsize", "boat": uid})
	check(roll["ok"] and roll["events"][0]["by"] == p, "rolled by the Deep One")
	eq(st.boats[uid]["held"], "", "and released")
	check(c.apply("p1", {"type": "right_boat", "boat": uid})["ok"], "righted")
	# a grip ends with the creature: death, despawn, or a world that turns Quiet
	st.creatures[p]["pos"] = at + Vector3(4, 0, 0)
	check(c.apply("p1", {"type": "grapple", "boat": uid, "source": p})["ok"], "gripped again")
	var ev: Array = c.apply("p1", {"type": "despawn", "uid": p})["events"]
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "boat_released"), "despawn lets go")
	eq(st.boats[uid]["held"], "")
	var q := st.new_uid("c")
	st.creatures[q] = {"id": "puchinnik", "pos": at + Vector3(4, 0, 0), "hp": 260.0, "fight": ""}
	check(c.apply("p1", {"type": "grapple", "boat": uid, "source": q})["ok"], "a second one grips")
	c.apply("p1", {"type": "set_mode", "mode": "quiet"})
	eq(st.boats[uid]["held"], "", "a Quiet sea has no grip")
	eq(c.apply("p1", {"type": "release", "boat": uid})["error"], "nothing")
	var back := SaveCodec.decode(db, SaveCodec.encode(st))
	eq(back.boats[uid]["held"], "", "held travels with the save")
