extends "res://tests/lib/case.gd"
## WorldCommands is the single writer of the world: every rule a remote peer could try to cheat is here.


func _at_beacon(c: WorldCommands, bid: String) -> void:
	var p := db.beacon_pos(bid)
	c.state.players["p1"]["pos"] = Vector3(p.x + 3.0, 0.0, p.y)


func _give_fuel(c: WorldCommands, bid: String) -> void:
	var fuel := ContentDB.bag(db.beacons[bid]["fuel"])
	for k: String in fuel:
		c.state.inv("p1").add(k, fuel[k])


func test_gather_needs_the_right_tool() -> void:
	var c := new_world()
	eq(c.apply("p1", {"type": "gather", "node": "home:1", "item": "wood", "qty": 3})["error"], "need_tool")
	c.state.inv("p1").add("stone_axe", 1)
	var r := c.apply("p1", {"type": "gather", "node": "home:1", "item": "wood", "qty": 3})
	check(r["ok"], "gather with an axe")
	eq(c.state.inv("p1").count("wood"), 3)
	eq(c.apply("p1", {"type": "gather", "node": "home:1", "item": "wood"})["error"], "depleted")


func test_gather_is_capped_and_region_checked() -> void:
	var c := new_world()
	c.apply("p1", {"type": "gather", "node": "home:2", "item": "stone", "qty": 999})
	eq(c.state.inv("p1").count("stone"), WorldCommands.GATHER_MAX)
	c.state.inv("p1").add("wooden_shovel", 1)
	eq(c.apply("p1", {"type": "gather", "node": "b04:1", "item": "bog_ore"})["error"], "region_locked")


func test_place_and_full_refund() -> void:
	var c := new_world()
	eq(c.apply("p1", {"type": "place", "piece": "workbench", "pos": [1, 0, 1]})["error"], "missing")
	c.state.inv("p1").add("wood", 10)
	var r := c.apply("p1", {"type": "place", "piece": "workbench", "pos": [1, 0, 1]})
	check(r["ok"], "placed")
	eq(c.state.inv("p1").count("wood"), 0)
	var uid: String = r["events"][0]["uid"]
	check(c.apply("p1", {"type": "remove", "uid": uid})["ok"], "removed")
	eq(c.state.inv("p1").count("wood"), 10, "full refund")
	eq(c.apply("p1", {"type": "place", "piece": "forge", "pos": [0, 0, 0]})["error"], "locked")


func test_bed_sets_spawn() -> void:
	var c := new_world()
	c.state.inv("p1").add("wood", 6)
	c.state.inv("p1").add("moss", 4)
	c.apply("p1", {"type": "place", "piece": "bed", "pos": [5, 1, 5]})
	eq(c.state.players["p1"]["spawn"], Vector3(5, 1, 5))


func test_light_beacon_rules_in_quiet() -> void:
	var c := new_world("quiet")
	eq(c.apply("p1", {"type": "light_beacon", "beacon": "b01"})["error"], "trial_not_done")
	check(c.apply("p1", {"type": "complete_trial", "beacon": "b01", "kind": "trial"})["ok"], "trial")
	eq(c.apply("p1", {"type": "light_beacon", "beacon": "b01"})["error"], "too_far")
	_at_beacon(c, "b01")
	eq(c.apply("p1", {"type": "light_beacon", "beacon": "b01"})["error"], "missing")
	_give_fuel(c, "b01")
	var r := c.apply("p1", {"type": "light_beacon", "beacon": "b01"})
	check(r["ok"], "lit")
	eq(r["events"][0]["type"], "beacon_lit")
	check("tar" in r["events"][0]["unlocks"]["recipes"], "b01 unlocks tar")
	eq(c.state.inv("p1").count("smolye"), 0, "fuel burnt")
	eq(c.apply("p1", {"type": "light_beacon", "beacon": "b01"})["error"], "already_lit")


func test_b03_opens_the_next_region() -> void:
	var c := new_world("tale")
	eq(c.apply("p1", {"type": "complete_trial", "beacon": "b04", "kind": "trial"})["error"], "region_locked")
	c.apply("p1", {"type": "complete_trial", "beacon": "b03", "kind": "trial"})
	_at_beacon(c, "b03")
	_give_fuel(c, "b03")
	var r := c.apply("p1", {"type": "light_beacon", "beacon": "b03"})
	eq(r["events"].size(), 2)
	eq(r["events"][1], {"type": "region_opened", "region": "r2"})
	check(c.apply("p1", {"type": "complete_trial", "beacon": "b04", "kind": "trial"})["ok"], "r2 open now")


func test_saga_needs_the_guardian() -> void:
	var c := new_world("saga")
	eq(c.apply("p1", {"type": "complete_trial", "beacon": "b03", "kind": "trial"})["error"], "wrong_trial")
	eq(c.apply("p1", {"type": "complete_trial", "beacon": "b03", "kind": "guardian"})["error"], "no_fight")
	check(c.apply("p1", {"type": "begin_fight", "beacon": "b03"})["ok"], "fight starts")
	eq(c.apply("p1", {"type": "set_mode", "mode": "quiet"})["error"], "busy", "no mode switch mid-fight")
	check(c.apply("p1", {"type": "complete_trial", "beacon": "b03", "kind": "guardian"})["ok"], "guardian beaten")
	eq(c.state.busy_beacon, "")
	eq(c.apply("p1", {"type": "complete_trial", "beacon": "b01", "kind": "guardian"})["error"], "wrong_trial", "b01 is a defence in Saga")


func test_mode_switch_keeps_progress() -> void:
	var c := new_world("saga")
	c.apply("p1", {"type": "begin_fight", "beacon": "b03"})
	c.apply("p1", {"type": "complete_trial", "beacon": "b03", "kind": "guardian"})
	check(c.apply("p1", {"type": "set_mode", "mode": "quiet"})["ok"], "switch")
	eq(c.state.mode, "quiet")
	check(c.state.trials_done.has("b03"), "a won fight stays won")


func test_death_by_mode() -> void:
	var quiet := new_world("quiet", Vector3(50, 0, 50))
	quiet.state.inv("p1").add("stone", 5)
	quiet.apply("p1", {"type": "die"})
	eq(quiet.state.inv("p1").count("stone"), 5, "quiet keeps everything")
	eq(quiet.state.players["p1"]["weary_until"], 0.0)
	var saga := new_world("saga", Vector3(50, 0, 50))
	saga.state.players["p1"]["spawn"] = Vector3.ZERO  # the bed at home
	saga.state.inv("p1").add("stone", 5)
	var r := saga.apply("p1", {"type": "die"})
	eq(saga.state.inv("p1").count("stone"), 0, "items go to the grave")
	var grave: String = r["events"][0]["grave"]
	check(saga.state.graves.has(grave), "grave exists")
	check(float(saga.state.players["p1"]["weary_until"]) > 0.0, "weary debuff")
	eq(saga.apply("p1", {"type": "loot_grave", "uid": grave})["error"], "too_far", "respawned at home")
	saga.state.players["p1"]["pos"] = Vector3(50, 0, 50)
	check(saga.apply("p1", {"type": "loot_grave", "uid": grave})["ok"], "loot")
	eq(saga.state.inv("p1").count("stone"), 5)
	check(not saga.state.graves.has(grave), "empty grave disappears")


func test_rejects_garbage() -> void:
	var c := new_world()
	eq(c.apply("p1", {"type": "fly"})["error"], "unknown_command")
	eq(c.apply("nobody", {"type": "gather"})["error"], "unknown_player")
	eq(c.apply("p1", {"type": "set_mode", "mode": "hardcore"})["error"], "unknown_mode")


func test_world_starts_with_a_boat_at_the_pier() -> void:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 3, "quiet")
	st.add_player("p1", m.home["spawn"])
	var c := WorldCommands.new(db, st, m)
	var ev := c.init_world()
	eq(ev.size(), 1)
	eq(st.boats.size(), 1)
	var uid: String = st.players["p1"]["aboard"]
	eq(st.boats[uid]["type"], "karbas")
	eq(c.init_world(), [], "only once")


func test_move_board_and_disembark() -> void:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 3, "quiet")
	st.add_player("p1", m.home["spawn"])
	var c := WorldCommands.new(db, st, m)
	c.init_world()
	var uid: String = st.players["p1"]["aboard"]
	eq(c.apply("p1", {"type": "board", "boat": uid})["error"], "already_aboard")
	var boat: Vector3 = m.home["boat"]
	check(c.apply("p1", {"type": "move", "pos": [boat.x, 0, boat.z], "boat_pos": [boat.x + 1, 0, boat.z], "boat_yaw": 0.5})["ok"], "move")
	near((st.boats[uid]["pos"] as Vector3).x, boat.x + 1, 1e-4, "the helmsman moves the boat")
	eq(c.apply("p1", {"type": "move", "pos": [INF, 0, 0]})["error"], "bad_pos")
	eq(c.apply("p1", {"type": "disembark", "pos": [boat.x, 0, boat.z]})["error"], "no_land", "can't step onto water")
	var landing := m.find_landing(Vector2(boat.x, boat.z))
	check(not landing.is_empty(), "there is a landing near the pier")
	var lp: Vector3 = landing["pos"]
	var r := c.apply("p1", {"type": "disembark", "pos": [lp.x, lp.y, lp.z]})
	check(r["ok"], "disembark: " + String(r["error"]))
	eq(st.players["p1"]["aboard"], "")
	check(c.apply("p1", {"type": "board", "boat": uid})["ok"], "board again from the shore")


func test_tick_is_host_only_time() -> void:
	var c := new_world()
	check(c.apply("p1", {"type": "tick", "dt_min": 0.5})["ok"], "tick")
	near(c.state.clock_min, 0.5, 1e-6)
	c.apply("p1", {"type": "tick", "dt_min": 99.0})
	near(c.state.clock_min, 1.5, 1e-6, "one tick advances at most a minute")
	c.state.clock_min = float(db.balance["day"]["length_min"]) - 0.1
	var r := c.apply("p1", {"type": "tick", "dt_min": 0.2})
	eq(r["events"][0], {"type": "day_changed", "day": 2})
	check("tick" in WorldCommands.HOST_ONLY, "remote peers can't send ticks")


func test_debug_commands_are_off_by_default() -> void:
	var c := new_world()
	eq(c.apply("p1", {"type": "debug", "give": {"wood": 5}})["error"], "unknown_command")
	c.allow_debug = true
	check(c.apply("p1", {"type": "debug", "give": {"wood": 5}})["ok"], "allowed when switched on")
	eq(c.state.inv("p1").count("wood"), 5)


func test_gather_with_a_map_checks_the_node() -> void:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 3, "quiet")
	st.add_player("p1")
	var c := WorldCommands.new(db, st, m)
	var pine: Dictionary = {}
	for n: Dictionary in m.nodes("home"):
		if n["kind"] == "pine":
			pine = n
			break
	st.inv("p1").add("stone_axe", 1)
	st.inv("p1").add("knife", 1)
	eq(c.apply("p1", {"type": "gather", "node": pine["id"], "item": "wood"})["error"], "too_far")
	st.players["p1"]["pos"] = pine["pos"]
	eq(c.apply("p1", {"type": "gather", "node": pine["id"], "item": "stone"})["error"], "not_here", "pines give no stone")
	eq(c.apply("p1", {"type": "gather", "node": "home:99999", "item": "wood"})["error"], "bad_node")
	check(c.apply("p1", {"type": "gather", "node": pine["id"], "item": "resin", "qty": 2})["ok"], "resin from a pine")


func test_torch_burns_and_lantern_refuels() -> void:
	var c := new_world()
	eq(c.apply("p1", {"type": "light", "item": "torch"})["error"], "missing")
	c.state.inv("p1").add("torch", 2)
	check(c.apply("p1", {"type": "light", "item": "torch"})["ok"], "light a torch")
	eq(c.state.inv("p1").count("torch"), 1, "a torch burns up")
	var mins := float(db.items["torch"]["light"]["minutes"])
	c.apply("p1", {"type": "tick", "dt_min": 1.0})
	eq(c.state.players["p1"]["light"]["id"], "torch")
	c.state.clock_min = mins + 0.5
	var r := c.apply("p1", {"type": "tick", "dt_min": 0.1})
	eq(c.state.players["p1"]["light"], {}, "burnt out")
	check(r["events"].any(func(e: Dictionary) -> bool: return e["type"] == "light_changed"), "the view hears about it")
	c.state.inv("p1").add("iron_lantern", 1)
	eq(c.apply("p1", {"type": "light", "item": "iron_lantern"})["error"], "no_fuel")
	c.state.inv("p1").add("fish_oil", 2)
	check(c.apply("p1", {"type": "light", "item": "iron_lantern"})["ok"], "lantern lit")
	c.state.clock_min += float(db.items["iron_lantern"]["light"]["minutes_per_fuel"]) + 0.1
	c.apply("p1", {"type": "tick", "dt_min": 0.1})
	eq(c.state.players["p1"]["light"]["id"], "iron_lantern", "takes the next fuel by itself")
	eq(c.state.inv("p1").count("fish_oil"), 0)
	eq(c.apply("p1", {"type": "light", "item": "stone"})["error"], "not_a_light")
