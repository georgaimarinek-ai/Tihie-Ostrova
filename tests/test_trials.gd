extends "res://tests/lib/case.gd"
## Trials through the real world scene (roadmap phase 5, an integration test like test_world_flow): every
## trial is played the way a player would, and counts only when "complete_trial" reaches the host; then the
## beacon moment: bars, the camera out to the side, the flame catching a moment later, the camera back.

var _events: Array[String] = []


func _world(tree: SceneTree, seed_value: int, lit: Array) -> Node3D:
	var game: Node = tree.root.get_node("Game")
	game.state = null
	game.debug_cheats = true
	game.new_world(seed_value, "quiet")
	_events.clear()
	game.world_event.connect(_on_event)
	var world: Node3D = add(tree, load("res://src/scenes/world.tscn").instantiate())
	await frames(tree, 3)
	for bid: String in lit:
		world._debug_light(bid, true)
	# ashore at home, like a player, before walking the beacon islands
	var m: WorldMap = game.map
	var sea: Vector2 = WorldMap.walk_out(m.by_id["home"], (m.by_id["home"] as IslandGen).center, Vector2(1, 0.3).normalized())["sea"]
	world.my_boat.global_position = Vector3(sea.x, 0.0, sea.y)
	await frames(tree, 3)
	world._scan()
	world._disembark()
	await frames(tree, 2)
	_events.clear()
	return world


func _done(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node("Game")
	if game.world_event.is_connected(_on_event):
		game.world_event.disconnect(_on_event)
	game.state = null


func _on_event(e: Dictionary) -> void:
	_events.append(String(e["type"]))


## Stand somewhere on foot (a debug move on the host, the node follows).
func _put(tree: SceneTree, world: Node3D, p: Vector3) -> void:
	var m: WorldMap = Game.map
	var q := Vector3(p.x, maxf(m.ground_at(p.x, p.z), p.y), p.z)
	Game.submit({"type": "debug", "pos": [q.x, q.y, q.z]})
	world.player.place(q + Vector3(0, 0.2, 0), 0.0)
	world.streamer.build_around(q)
	await frames(tree, 3)
	world._send_move()


func test_carry_and_the_beacon_moment(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 11, [])
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b01", 0.5, 0.0))
	await frames(tree, 2)
	check(world.trials.get("b01") is CarryTrial, "the carry trial waits on Gull Skerry")
	await _put(tree, world, Game.map.path_point("b01", 0.97, 0.0))
	await frames(tree, 10)
	check(not st.trials_done.has("b01"), "at the tower without fire: not yet")
	Game.submit({"type": "debug", "give": {"torch": 1}})
	Game.submit({"type": "light", "item": "torch"})
	await frames(tree, 5)
	check(st.trials_done.has("b01"), "fire carried to the tower")
	check(_events.has("trial_done"), "passed through complete_trial")
	# the tower: first what fuel is missing, then "Light the beacon"
	check(String(world._beacon_action().get("label", "")).begins_with(tr("act.need_fuel").split("%")[0]), "says what fuel it needs")
	Game.submit({"type": "debug", "give": ContentDB.bag(db.beacons["b01"]["fuel"])})
	var a: Dictionary = world._beacon_action()
	eq(a.get("label", ""), tr("act.light_beacon"))
	(a["run"] as Callable).call()
	check(st.lit.has("b01"), "the beacon is lit in the world")
	eq(world._moment, "b01", "the moment plays")
	check(world.hud.in_cinema and world.cam.in_shot(), "black bars, the camera flies out")
	var bv: BeaconView = world.beacons["b01"]
	eq(bv.lit, 0.0, "the flame catches a moment later")
	var off: Vector3 = world.moment_offset(bv.fire_pos)
	var s3: Vector3 = world.sun.global_transform.basis.z
	var across := absf(Vector2(off.x, off.z).normalized().dot(Vector2(s3.x, s3.z).normalized()))
	check(across < 0.35, "the camera looks across the sun, not into it (%.2f)" % across)
	await frames(tree, int(world.KINDLE_AT * 60.0) + 10)
	check(bv.lit > 0.0, "kindling")
	await frames(tree, int((world.BANNER_AT - world.KINDLE_AT) * 60.0) + 5)
	check(world.hud.banner.visible, "the banner says what opened")
	await frames(tree, int((world.MOMENT_S - world.BANNER_AT) * 60.0) + 30)
	check(not world.hud.in_cinema and not world.cam.in_shot(), "the camera is back with the player")
	eq(world._moment, "")
	near(bv.lit, 1.0, 1e-6, "burning")
	_done(tree)


func test_lanterns(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 12, ["b01", "b02", "b03"])
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b04", 0.15, 0.0))
	Game.submit({"type": "debug", "give": {"torch": 1}})
	Game.submit({"type": "light", "item": "torch"})
	await frames(tree, 2)
	var t: LanternsTrial = world.trials.get("b04")
	check(t != null, "path lanterns stand on the Rusty Bog path")
	for i in t.lamps.size():
		var lp: Vector3 = t.lamps[i]["pos"]
		await _put(tree, world, lp + Vector3(1.0, 0.0, 0.6))
		var a: Dictionary = world._beacon_action()
		eq(a.get("label", ""), tr("act.lantern"), "lantern %d" % i)
		(a["run"] as Callable).call()
		await frames(tree, 2)
		if i < t.lamps.size() - 1:
			check(not st.trials_done.has("b04"), "%d of 3 is not the trial" % (i + 1))
	check(st.trials_done.has("b04"), "three lanterns lit")
	check(_events.has("trial_done"), "through complete_trial")
	eq(t.fog_lights().size(), 3, "each lit lantern clears the fog")
	_done(tree)


func test_bells(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 13, ["b01", "b02"])
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b03", 0.93, 0.0))
	var t: BellsTrial = world.trials.get("b03")
	check(t != null, "bells hang on Stone Watchman")
	await frames(tree, 4)
	check(t.heard, "near the tower the melody plays by itself")
	await frames(tree, int((0.4 + t.melody.size() * 0.9) * 60.0) + 10)
	var b0: Vector3 = t.bells[0]["pos"]
	await _put(tree, world, b0 + Vector3(0.8, 0.0, 0.8))
	eq(world._beacon_action().get("label", ""), tr("act.strike") % [0, t.melody.size()], "strike the bells")
	t.strike((t.melody[0] + 1) % BellsTrial.NOTES.size())
	check(not t.heard and t.step == 0, "a slip: listen again, no penalty")
	t.listen()
	for n: int in t.melody:
		check(not st.trials_done.has("b03"), "not before the last note")
		t.strike(n)
	await frames(tree, 2)
	check(st.trials_done.has("b03"), "the melody repeated")
	check(_events.has("trial_done"), "through complete_trial")
	_done(tree)


func test_mirrors(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 14, ["b01", "b02", "b03", "b04"])
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b05", 0.2, 0.0))
	var t: MirrorTrial = world.trials.get("b05")
	check(t != null, "copper reflectors on the path")
	var m0: Vector3 = t.mirrors[0]["pos"]
	await _put(tree, world, Vector3(m0.x + 1.0, 0.0, m0.z + 0.5))
	eq(world._beacon_action().get("label", ""), tr("act.mirror"), "turn a reflector")
	for i in t.mirrors.size():
		var guard := 0
		while not t.aligned(i) and guard < MirrorTrial.STEPS:
			if i == t.mirrors.size() - 1:
				check(not st.trials_done.has("b05"), "the beam isn't there yet")
			t.turn(i)
			guard += 1
		check(t.aligned(i), "reflector %d aligned within a full turn" % i)
	await frames(tree, 2)
	check(st.trials_done.has("b05"), "the beam reaches the brazier")
	check(_events.has("trial_done"), "through complete_trial")
	_done(tree)


func test_climb(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 15, ["b01"])
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b02", 0.9, 0.0))
	var t: ClimbTrial = world.trials.get("b02")
	check(t != null, "ledges around the tower")
	var bv: BeaconView = world.beacons["b02"]
	await _put(tree, world, bv.global_position + Vector3(2.5, 0.0, 0.0))
	await frames(tree, 20)
	check(not st.trials_done.has("b02"), "at the foot of the tower: not yet")
	eq(Game.submit({"type": "complete_trial", "beacon": "b02", "kind": "trial"})["error"], "not_at_top", "the host sees the height")
	# up on the deck (the ledges get you there; the test just stands you on it)
	var deck := bv.global_position + Vector3(1.3, 10.8, 0.0)
	Game.submit({"type": "debug", "pos": [deck.x, deck.y, deck.z]})
	world.player.place(deck, 0.0)
	await frames(tree, 40)
	check(world.player.global_position.y > bv.global_position.y + 9.5, "standing on the deck, not fallen through")
	check(st.trials_done.has("b02"), "climbed to the brazier")
	check(_events.has("trial_done"), "through complete_trial")
	_done(tree)


func test_finale_runs_every_trial_in_a_row(tree: SceneTree) -> void:
	var lit: Array = []
	for i in 11:
		lit.append("b%02d" % (i + 1))
	var world: Node3D = await _world(tree, 16, lit)
	var st: WorldState = Game.state
	await _put(tree, world, Game.map.path_point("b12", 0.1, 0.0))
	Game.submit({"type": "debug", "give": {"torch": 1}})
	Game.submit({"type": "light", "item": "torch"})
	await frames(tree, 2)
	var f: FinaleTrial = world.trials.get("b12")
	check(f != null, "the finale waits on the Lodestar")
	for part in 3:
		var t: Trial = f.parts[f.current]
		t.debug_solve(8)
		await frames(tree, 2)
		eq(f.current, part + 1, "part %d done, the next one begins" % (part + 1))
		check(not st.trials_done.has("b12"), "a part is not the trial")
		check(not _events.has("trial_done"), "parts don't talk to the host")
	var bv: BeaconView = world.beacons["b12"]
	var deck := bv.global_position + Vector3(1.3, 10.8, 0.0)
	Game.submit({"type": "debug", "pos": [deck.x, deck.y, deck.z]})
	world.player.place(deck, 0.0)
	await frames(tree, 40)
	check(st.trials_done.has("b12"), "all four in a row: the finale is passed")
	check(_events.has("trial_done"), "through complete_trial")
	_done(tree)


## At a pine the prompt names what Q switches to, and the tool it needs (the resin a player can't find).
func test_resource_prompt_names_the_other(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 11, [])
	var pine: Dictionary = {}
	for n: Dictionary in Game.map.nodes("home"):
		if String(n["kind"]) == "pine":
			pine = n
			break
	world._near_node = pine
	world._choice = 0
	var resin := Loc.item(db, "resin")
	var label := String(world._action().get("label", ""))
	check(label.contains(tr("act.other") % (tr("act.other_tool") % [resin, tr("tool.knife")])), "Q — resin, needs a knife: " + label)
	Game.submit({"type": "debug", "give": {"knife": 1}})
	label = String(world._action().get("label", ""))
	check(label.contains(tr("act.other") % resin), "with a knife: Q — resin: " + label)
	world._choice = 1
	label = String(world._action().get("label", ""))
	check(label.begins_with(tr("act.cut") % resin), "after Q: cut resin: " + label)
	_done(tree)
