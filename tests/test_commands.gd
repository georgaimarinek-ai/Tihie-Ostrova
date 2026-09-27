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
