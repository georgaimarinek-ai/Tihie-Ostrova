extends "res://tests/lib/case.gd"
## Co-op (roadmap phase 9, docs/04_TECH_SPEC.md §7): no game logic in the transport — the host applies, every
## client replays the same commands on its copy of the world, and the copies stay identical. First the rule
## itself on two WorldCommands in one process (300 random commands), then two real Godot instances on this
## machine over ENet: 50 random commands, and SaveCodec.encode is the same at the host and the client.

const KINDS := ["tick", "move", "give", "gather", "craft", "place", "eat", "light", "tuning", "spawn", "hurt", "attack",
	"remove", "fight", "sleep", "store"]


## A random command for a player (many will be refused — only what passes travels).
func _random_cmd(rng: RandomNumberGenerator, st: WorldState, m: WorldMap, pid: String) -> Dictionary:
	var p: Vector3 = st.players[pid]["pos"]
	match KINDS[rng.randi() % KINDS.size()]:
		"tick":
			return {"type": "tick", "dt_min": rng.randf_range(0.05, 1.0)}
		"move":
			var q: Vector3 = m.home["spawn"] + Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))
			q.y = m.ground_at(q.x, q.z)
			return {"type": "move", "pos": [q.x, q.y, q.z], "stance": ["", "block", "dodge"][rng.randi() % 3]}
		"give":
			var items := ["wood", "stone", "moss", "resin", "branch", "torch", "cloudberry", "spear", "kalitki"]
			return {"type": "debug", "give": {items[rng.randi() % items.size()]: 1 + rng.randi() % 20}}
		"gather":
			var nodes := m.nodes("home")
			var n: Dictionary = nodes[rng.randi() % nodes.size()]
			return {"type": "gather", "node": n["id"], "item": (n["items"] as Array)[0] if not (n["items"] as Array).is_empty() else "stone", "qty": 1 + rng.randi() % 5}
		"craft":
			var ids := st.db.recipes.keys()
			return {"type": "craft", "recipe": ids[rng.randi() % ids.size()], "times": 1}
		"place":
			var pieces := ["hearth", "bench", "chest", "bed", "workbench", "log_foundation"]
			var piece: String = pieces[rng.randi() % pieces.size()]
			var aim := p + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
			var sn := Building.snap(st.db, st, m, piece, aim, rng.randi() % 4)
			var at: Vector3 = sn["pos"]
			return {"type": "place", "piece": piece, "pos": [at.x, at.y, at.z], "rot": sn["rot"]}
		"eat":
			return {"type": "eat", "item": ["cloudberry", "kalitki", "ukha"][rng.randi() % 3]}
		"light":
			return {"type": "light", "item": "torch"}
		"tuning":
			return {"type": "set_tuning", "rule": "durability", "value": rng.randf() < 0.5}
		"spawn":
			var a := rng.randf() * TAU
			var q := p + Vector3(cos(a), 0, sin(a)) * 6.0
			return {"type": "spawn", "id": ["wolf", "hare", "fox", "seal"][rng.randi() % 4], "pos": [q.x, m.ground_at(q.x, q.z), q.z]}
		"hurt":
			var uids := st.creatures.keys()
			return {"type": "hurt", "player": pid, "source": uids[rng.randi() % uids.size()] if not uids.is_empty() else ""}
		"attack":
			var uids := st.creatures.keys()
			return {"type": "attack", "target": uids[rng.randi() % uids.size()] if not uids.is_empty() else ""}
		"remove":
			var uids := st.pieces.keys()
			return {"type": "remove", "uid": uids[rng.randi() % uids.size()] if not uids.is_empty() else ""}
		"fight":
			return {"type": "begin_fight", "beacon": "b01"}
		"sleep":
			var uids := st.pieces.keys()
			return {"type": "sleep", "uid": uids[rng.randi() % uids.size()] if not uids.is_empty() else ""}
		"store":
			var uids := st.pieces.keys()
			return {"type": "store", "container": uids[rng.randi() % uids.size()] if not uids.is_empty() else "", "item": "wood", "qty": 3}
	return {"type": "tick", "dt_min": 0.1}


func test_replayed_commands_keep_the_copies_identical() -> void:
	var m := WorldMap.shared(db)
	var st := WorldState.new(db, 31, "tale")
	st.add_player("p1", m.home["spawn"])
	var host := WorldCommands.new(db, st, m)
	host.allow_debug = true
	host.init_world()
	check(host.apply("p1", {"type": "join", "player": "p7"})["ok"], "a friend joins")
	# the friend's copy starts from the host's world as Net.send_snapshot carries it
	var copy_state := SaveCodec.from_snapshot(db, SaveCodec.snapshot(st))
	eq(SaveCodec.encode(copy_state), SaveCodec.encode(st), "the snapshot is exact")
	var copy := WorldCommands.new(db, copy_state, m)
	copy.allow_debug = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4127
	var passed := 0
	for i in 300:
		var pid := "p1" if rng.randf() < 0.6 else "p7"
		var cmd := _random_cmd(rng, st, m, pid)
		var r := host.apply(pid, cmd)
		if r["ok"]:
			passed += 1
			var again := copy.apply(pid, cmd)  # the replay on the client
			check(again["ok"], "the copy accepts what the host accepted: %s" % cmd["type"])
			eq(again["events"].size(), r["events"].size(), "the same events: " + String(cmd["type"]))
	check(passed > 60, "enough of them passed (%d)" % passed)
	eq(SaveCodec.encode(copy_state), SaveCodec.encode(st), "the copies are identical")
	check(WorldCommands.HOST_ONLY.has("join"), "joining is the host's")


func test_two_instances_on_one_machine(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node("Game")
	game.state = null
	game.debug_cheats = true
	game.autosave = false
	game.new_world(77, "saga")
	var port := 25000 + randi() % 5000
	eq(Net.host(port), OK, "the host listens")
	var out := ProjectSettings.globalize_path("user://coop_test_%d.txt" % port)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/coop_client.gd",
		"--", "--port=%d" % port, "--out=%s" % out, "--life=40"]
	var proc := OS.create_process(OS.get_executable_path(), args)
	check(proc > 0, "the second instance starts")
	# the friend connects and gets the world
	var t0 := Time.get_ticks_msec()
	while (Net.peers.is_empty() or not FileAccess.file_exists(out)) and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	check(not Net.peers.is_empty(), "the client joined")
	var friend: String = Net.peers[0] if not Net.peers.is_empty() else ""
	check(game.state.players.has(friend), "the friend is a player in the host's world")
	# 50 random commands from the host (the friend sends its own from the other process)
	var st: WorldState = game.state
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 50:
		game.submit(_random_cmd(rng, st, game.map, Net.local_player_id()))
		await tree.process_frame
	# wait until the client's copy matches, byte for byte
	var want := ""
	var got := ""
	var lines := PackedStringArray()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
		want = SaveCodec.encode(game.state).md5_text()
		if FileAccess.file_exists(out):
			lines = FileAccess.get_file_as_string(out).split("\n")
			got = lines[0]
			if got == want and lines.size() > 2 and lines[2] != "":
				break
	eq(got, want, "SaveCodec.encode is the same at the host and the client")
	check(lines.size() > 2 and lines[2].begins_with("debug:"), "the host's refusal reached the client (%s)" % (lines[2] if lines.size() > 2 else ""))
	eq(String(game.state.tuning.get("storms", "")), "cosmetic", "the client's own command went through the host")
	OS.kill(proc)
	Net.leave()
	DirAccess.remove_absolute(out)
	game.autosave = true
	game.state = null
