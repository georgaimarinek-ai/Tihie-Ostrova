extends "res://tests/lib/case.gd"
## End to end through the real world scene and the Game autoload (an integration test, unlike the rest):
## go ashore, gather a node unit by unit, the haul arrives through one "gather" command, the node hides,
## walk back and board.


func test_land_gather_and_board(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node("Game")
	game.state = null
	game.debug_cheats = true
	game.new_world(5, "quiet")
	var world: Node3D = add(tree, load("res://src/scenes/world.tscn").instantiate())
	await frames(tree, 3)
	var st: WorldState = game.state
	var m: WorldMap = game.map
	var pid: String = Net.local_player_id()
	var boat: Boat = world.my_boat
	check(boat != null, "starts aboard the karbas")
	# drift to a quiet shore of the home island and go ashore
	var sea: Vector2 = WorldMap.walk_out(m.by_id["home"], (m.by_id["home"] as IslandGen).center, Vector2(1, 0.3).normalized())["sea"]
	boat.global_position = Vector3(sea.x, 0.0, sea.y)
	boat.linear_velocity = Vector3.ZERO
	await frames(tree, 3)
	world._scan()
	check(not world._landing.is_empty(), "a landing is offered")
	world._disembark()
	await frames(tree, 2)
	check(world.on_foot(), "on foot")
	eq(st.players[pid]["aboard"], "", "the world knows we left the boat")
	# gather sticks: five units, one command
	var sticks: Dictionary = {}
	for n: Dictionary in m.nodes("home"):
		if n["kind"] == "sticks":
			sticks = n
			break
	var sp: Vector3 = sticks["pos"]
	world.player.place(sp + Vector3(1.0, 0.3, 0.0), 0.0)
	world._send_move()
	await frames(tree, 2)
	world._scan()
	check(not world._near_node.is_empty(), "a node is within reach")
	world._start_channel(sticks, "branch")
	var per := Gathering.unit_seconds(ContentDB.shared(), st.inv(pid), "branch")
	await frames(tree, int(ceil(per * WorldCommands.GATHER_MAX * 60.0)) + 20)
	eq(st.inv(pid).count("branch"), WorldCommands.GATHER_MAX, "the haul arrived")
	check(int(st.depleted.get(sticks["id"], 0)) > st.day, "the node is depleted in the world")
	var view: IslandView = world.streamer.views["home"]
	check(view.is_hidden(sticks["id"]), "and hidden in the view")
	# walk back to the boat and board it
	world.player.place(world.last_boat.global_position + Vector3(3.0, 0.0, 0.0), 0.0)
	world.player.walked = 10.0
	world._send_move()
	await frames(tree, 2)
	world._board()
	await frames(tree, 2)
	check(not world.on_foot(), "aboard again")
	eq(st.players[pid]["aboard"], world.my_boat.uid)
	game.state = null
