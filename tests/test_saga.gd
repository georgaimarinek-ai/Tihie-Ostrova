extends "res://tests/lib/case.gd"
## Saga (roadmap phase 7): fog creatures only where the fog is thicker than their fog_min (and never in Quiet
## or Tale); guardians and fire defences through begin_fight; a lost fight spends no fuel; weapons by tier;
## creatures never break walls or stations.


func _world(mode: String, pos: Vector3 = Vector3(20, 0, 20)) -> WorldCommands:
	var st := WorldState.new(db, 11, mode)
	st.add_player("p1", pos)
	return WorldCommands.new(db, st, WorldMap.shared(db))


func _at(c: WorldCommands, bid: String) -> void:
	var m := c.map
	var q := m.path_point(bid, 0.9, 0.0)
	c.state.players["p1"]["pos"] = q


func _open_all(c: WorldCommands) -> void:
	for bid in ["b03", "b06", "b09"]:
		c.state.lit[bid] = 1


func _night(c: WorldCommands) -> void:
	c.state.clock_min = float(db.balance["day"]["length_min"]) * 0.75  # midnight


func test_fog_creatures_spawn_only_in_thick_fog() -> void:
	# a dark spot at sea in the Summer Shore, at midnight
	var spot := [300.0, 0.0, -1100.0]
	var saga := _world("saga")
	_open_all(saga)
	_night(saga)
	var fog := FogField.factor(db, saga.state, Vector2(300, -1100))
	check(fog > float(db.creatures["mglyak"]["fog_min"]), "thick fog out there (%.2f)" % fog)
	check(saga.apply("p1", {"type": "spawn", "id": "mglyak", "pos": spot})["ok"], "a mistling comes out of the Mga")
	# in the clearing of a lit beacon the fog is thin
	saga.state.lit["b04"] = 1
	var b4 := db.beacon_pos("b04")
	eq(saga.apply("p1", {"type": "spawn", "id": "mglyak", "pos": [b4.x + 20.0, 0.0, b4.y]})["error"], "clear", "not in a beacon's clearing")
	# by day only on the island of a dark beacon
	saga.state.clock_min = float(db.balance["day"]["length_min"]) * 0.25  # noon
	eq(saga.apply("p1", {"type": "spawn", "id": "mglyak", "pos": spot})["error"], "daylight", "not in daylight at sea")
	var dark := saga.map.path_point("b05", 0.5, 0.0)
	check(saga.apply("p1", {"type": "spawn", "id": "mglyak", "pos": [dark.x, dark.y, dark.z]})["ok"], "the Mga clings to a dark beacon's island by day")
	eq(saga.apply("p1", {"type": "spawn", "id": "morok", "pos": spot})["error"], "not_in_this_region", "the glamour lives on the Ter Coast")
	eq(saga.apply("p1", {"type": "spawn", "id": "siverko", "pos": spot})["error"], "fight_only")
	# never in Quiet or Tale, anywhere, day or night
	for mode: String in ["quiet", "tale"]:
		var c := _world(mode)
		_open_all(c)
		_night(c)
		for id: String in db.creatures:
			if Creatures.group(db, id) in ["fog", "elite", "guardian"]:
				eq(c.apply("p1", {"type": "spawn", "id": id, "pos": spot})["error"], "not_in_this_mode", "%s in %s" % [id, mode])
				eq(c.apply("p1", {"type": "spawn", "id": id, "pos": spot, "fight": true})["error"], "no_fight")
		eq(c.apply("p1", {"type": "begin_fight", "beacon": "b03"})["error"], "not_in_this_mode", "no fights in " + mode)
	# predators: Tale and Saga, not Quiet
	var quiet := _world("quiet")
	var home_isl := quiet.map.path_point("b01", 0.5, 0.0)
	eq(quiet.apply("p1", {"type": "spawn", "id": "wolf", "pos": [home_isl.x, home_isl.y, home_isl.z]})["error"], "not_in_this_mode")
	var tale := _world("tale")
	check(tale.apply("p1", {"type": "spawn", "id": "wolf", "pos": [home_isl.x, home_isl.y, home_isl.z]})["ok"], "wolves in Tale")
	tale.state.tuning["predators"] = false
	eq(tale.apply("p1", {"type": "spawn", "id": "wolf", "pos": [home_isl.x, home_isl.y, home_isl.z]})["error"], "not_in_this_mode", "fine tuning can take them away")


func test_a_lost_defence_spends_no_fuel() -> void:
	var c := _world("saga")
	var fuel := ContentDB.bag(db.beacons["b01"]["fuel"])
	eq(c.apply("p1", {"type": "begin_fight", "beacon": "b01"})["error"], "too_far", "on the beacon's island")
	_at(c, "b01")
	eq(c.apply("p1", {"type": "begin_fight", "beacon": "b01"})["error"], "missing", "a defence needs the fuel in the bag")
	for k: String in fuel:
		c.state.inv("p1").add(k, fuel[k])
	check(c.apply("p1", {"type": "begin_fight", "beacon": "b01"})["ok"], "the fire kindles")
	eq(c.state.fight["kind"], "defense")
	eq(c.apply("p1", {"type": "set_mode", "mode": "quiet"})["error"], "busy", "no mode switch mid-fight")
	# the player falls: the fire goes out, the fuel stays
	c.apply("p1", {"type": "die"})
	eq(c.state.busy_beacon, "", "the fight is over")
	check(c.state.inv("p1").has_bag(fuel) or c.state.graves.size() == 1, "fuel not spent (in the bag or the grave)")
	check(not c.state.lit.has("b01") and not c.state.trials_done.has("b01"), "nothing gained, nothing lost")
	# creatures beat the fire out: lost again, fuel still there
	c = _world("saga")
	for k: String in fuel:
		c.state.inv("p1").add(k, fuel[k])
	_at(c, "b01")
	c.apply("p1", {"type": "begin_fight", "beacon": "b01"})
	var at := db.beacon_pos("b01")
	var uid: String = c.apply("p1", {"type": "spawn", "id": "mglyak", "pos": [at.x + 2.0, 0.0, at.y], "fight": true})["events"][0]["uid"]
	var lost := false
	for i in 30:
		for e: Dictionary in c.apply("p1", {"type": "douse", "source": uid})["events"]:
			if e["type"] == "fight_ended":
				lost = not e["won"]
		if lost:
			break
	check(lost, "the fire was beaten out")
	check(c.state.inv("p1").has_bag(fuel), "fuel still in the bag")
	eq(c.state.creatures.size(), 0, "the fight's creatures went back into the fog")
	# held to the end: the trial is passed and the beacon lights with that fuel
	check(c.apply("p1", {"type": "begin_fight", "beacon": "b01"})["ok"], "try again")
	var r := c.apply("p1", {"type": "tick", "dt_min": 1.0})
	var types: Array = r["events"].map(func(e: Dictionary) -> String: return e["type"])
	check(types.has("trial_done") and types.has("beacon_lit"), "held for %d s: lit" % int(db.beacons["b01"]["saga"]["seconds"]))
	check(not c.state.inv("p1").has_bag(fuel), "now the fuel burns")


func test_the_guardian_fight() -> void:
	var c := _world("saga")
	_at(c, "b03")
	var r := c.apply("p1", {"type": "begin_fight", "beacon": "b03"})
	check(r["ok"], "Siverko comes")
	var boss: String = c.state.fight["boss"]
	eq(c.state.creatures[boss]["id"], "siverko")
	c.state.players["p1"]["pos"] = c.state.creatures[boss]["pos"] + Vector3(1.5, 0, 0)
	eq(c.apply("p1", {"type": "attack", "target": boss})["events"][0]["amount"], 4.0, "bare hands: 4")
	c.state.inv("p1").add("spear", 1)
	var hits := 1
	var phases: Array = []
	var won := false
	while hits < 200 and not won:
		for e: Dictionary in c.apply("p1", {"type": "attack", "target": boss})["events"]:
			if e["type"] == "guardian_phase":
				phases.append(e["phase"])
			if e["type"] == "trial_done":
				won = true
		hits += 1
	check(won, "Siverko beaten")
	check(hits >= 28 and hits <= 34, "about 30 spear strikes (docs/03_BALANCE.md §6): %d" % hits)
	eq(phases, [2], "phase 2 at half health")
	eq(c.state.trials_done["b03"], "guardian")
	eq(c.state.busy_beacon, "", "the fight is over")
	eq(c.state.inv("p1").count("smolye"), 4, "his drops (4 smolye)")
	check(c.state.journal.has("siverko"), "his page in the journal")


func test_weapons_and_the_mga() -> void:
	var c := _world("saga")
	var uid := c.state.new_uid("c")
	c.state.creatures[uid] = {"id": "fog_wolf", "pos": Vector3(21, 0, 20), "hp": 110.0, "fight": ""}
	c.state.inv("p1").add("bow", 1)
	eq(c.apply("p1", {"type": "attack", "target": uid, "weapon": "bow"})["error"], "no_ammo", "a bow wants arrows")
	c.state.inv("p1").add("arrows", 2)
	check(c.apply("p1", {"type": "attack", "target": uid, "weapon": "bow"})["ok"], "an arrow")
	eq(c.state.inv("p1").count("arrows"), 1, "one arrow spent")
	c.state.inv("p1").add("spolokh_spear", 1)
	var r := c.apply("p1", {"type": "attack", "target": uid})
	near(float(r["events"][0]["amount"]), 55.0 * 1.5, 1e-4, "the aurora spear: x1.5 on fog creatures")
	c.state.players["p1"]["light"] = {"id": "torch", "until": 99.0}
	r = c.apply("p1", {"type": "attack", "target": uid, "heavy": true, "weapon": "spear"})
	eq(r["error"], "missing", "only weapons in the bag")
	# the Mga is weak while every lantern around the arena burns
	var m := _world("saga")
	for bid: String in db.beacon_order:
		if bid != "b12":
			m.state.lit[bid] = 1
	_at(m, "b12")
	check(m.apply("p1", {"type": "begin_fight", "beacon": "b12"})["ok"], "the Mga, heart of the fog")
	var boss: String = m.state.fight["boss"]
	m.state.players["p1"]["pos"] = m.state.creatures[boss]["pos"]
	m.state.inv("p1").add("spear", 1)
	var plain := float(m.apply("p1", {"type": "attack", "target": boss})["events"][0]["amount"])
	eq(m.apply("p1", {"type": "arena_lantern", "i": 0})["error"], "no_fire", "lanterns want fire in hand")
	m.state.players["p1"]["light"] = {"id": "torch", "until": 99.0}
	for i in WorldCommands.ARENA_LANTERNS:
		check(m.apply("p1", {"type": "arena_lantern", "i": i})["ok"], "lantern %d" % i)
	var lit := float(m.apply("p1", {"type": "attack", "target": boss})["events"][0]["amount"])
	near(lit, plain * 2.0, 1e-4, "twice the damage with every lantern burning")


func test_creatures_never_break_the_homestead() -> void:
	var c := _world("saga")
	for k in ["wood", "stone", "moss", "birch_bark", "rope"]:
		c.state.inv("p1").add(k, 100)
	var g := c.map.ground_at(20.0, 20.0)
	c.state.players["p1"]["pos"] = Vector3(20.0, g, 20.0)
	for q: Array in [["log_foundation", Vector3(20, g, 23)], ["hearth", Vector3(24, g, 20)], ["workbench", Vector3(17, g, 20)], ["chest", Vector3(20, g, 16)]]:
		var sn := Building.snap(db, c.state, c.map, q[0], q[1], 0)
		var at: Vector3 = sn["pos"]
		var r := c.apply("p1", {"type": "place", "piece": q[0], "pos": [at.x, at.y, at.z], "rot": sn["rot"]})
		check(r["ok"], "placed %s: %s" % [q[0], r["error"]])
	var before := SaveCodec.encode(c.state)
	var pieces_before := JSON.stringify(c.state.to_dict()["pieces"])
	_night(c)
	var uid := c.state.new_uid("c")
	c.state.creatures[uid] = {"id": "mglyak", "pos": Vector3(21, 0, 21), "hp": 30.0, "fight": ""}
	for i in 20:
		c.apply("p1", {"type": "hurt", "player": "p1", "source": uid})
		c.apply("p1", {"type": "tick", "dt_min": 0.5})
		c.apply("p1", {"type": "creatures", "pos": {uid: [22.0, 0.0, 22.0]}})
	eq(JSON.stringify(c.state.to_dict()["pieces"]), pieces_before, "walls and stations stand untouched")
	check(before != "", "")
	# night raids exist only in Saga
	check(bool(WorldState.new(db, 1, "saga").rules()["night_raids"]) and not bool(WorldState.new(db, 1, "tale").rules()["night_raids"]), "night raids: Saga only")


func test_seals_and_spirits_are_not_prey() -> void:
	for mode: String in ["tale", "saga"]:
		var c := _world(mode)
		for id: String in ["seal", "hare", "reindeer", "domovoy", "sirin", "chud"]:
			var uid := c.state.new_uid("c")
			c.state.creatures[uid] = {"id": id, "pos": Vector3(21, 0, 20), "hp": 10.0, "fight": ""}
			eq(c.apply("p1", {"type": "attack", "target": uid})["error"], "friendly", "%s in %s" % [id, mode])
