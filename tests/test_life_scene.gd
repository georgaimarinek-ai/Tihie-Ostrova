extends "res://tests/lib/case.gd"
## Phases 6–7 through the real world scene (integration, like test_world_flow): the host's creature director
## only brings what the mode allows; a strike lands through "attack"; a Saga defence started at the tower and
## lost to death spends no fuel; the menu's fine tuning; the journal opens its pages.

var _events: Array[Dictionary] = []


func _world(tree: SceneTree, seed_value: int, mode: String) -> Node3D:
	var game: Node = tree.root.get_node("Game")
	game.state = null
	game.debug_cheats = true
	game.new_world(seed_value, mode)
	_events.clear()
	game.world_event.connect(_on_event)
	var world: Node3D = add(tree, load("res://src/scenes/world.tscn").instantiate())
	await frames(tree, 3)
	var m: WorldMap = game.map
	var sea: Vector2 = WorldMap.walk_out(m.by_id["home"], (m.by_id["home"] as IslandGen).center, Vector2(1, 0.3).normalized())["sea"]
	world.my_boat.global_position = Vector3(sea.x, 0.0, sea.y)
	await frames(tree, 3)
	world._scan()
	world._disembark()
	await frames(tree, 2)
	return world


func _on_event(e: Dictionary) -> void:
	_events.append(e)


func _done(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node("Game")
	if game.world_event.is_connected(_on_event):
		game.world_event.disconnect(_on_event)
	game.state = null


func _put(tree: SceneTree, world: Node3D, p: Vector3, yaw: float = 0.0) -> void:
	var q := Vector3(p.x, Game.map.ground_at(p.x, p.z), p.z)
	Game.submit({"type": "debug", "pos": [q.x, q.y, q.z]})
	world.player.place(q + Vector3(0, 0.2, 0), yaw)
	world.streamer.build_around(q)
	await frames(tree, 3)
	world._send_move()


func test_the_director_brings_only_what_the_mode_allows(tree: SceneTree) -> void:
	for mode: String in ["quiet", "tale"]:
		var world: Node3D = await _world(tree, 21, mode)
		Game.submit({"type": "debug", "clock_min": float(db.balance["day"]["length_min"]) * 0.75})  # midnight
		await _put(tree, world, Game.map.path_point("b01", 0.4, 0.0))
		await frames(tree, 60 * 14)
		var ids: Array = []
		for e: Dictionary in _events:
			if e["type"] == "creature_spawned":
				ids.append(e["id"])
		check(not ids.is_empty(), "%s: something lives on Gull Skerry" % mode)
		for id: String in ids:
			check((db.regions["r1"]["creatures"] as Array).has(id), id + " belongs to the Quiet Bay")
			check(Creatures.allowed(db, mode, Game.state.rules(), id), "%s allowed in %s" % [id, mode])
			check(not Creatures.group(db, id) in ["fog", "elite", "guardian"], "no fog creature in " + mode)
			if mode == "quiet":
				check(Creatures.is_friendly(db, id), "only friendly ones in Quiet: " + id)
		eq(float(Game.state.players[Net.local_player_id()]["hp"]), 100.0, mode + ": nobody hurt the player")
		_done(tree)
		world.queue_free()
		await frames(tree, 2)


func test_a_strike_lands_on_the_wolf(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 22, "tale")
	var st: WorldState = Game.state
	var pid := Net.local_player_id()
	await _put(tree, world, Game.map.path_point("b01", 0.4, 0.0), 0.0)
	st.inv(pid).add("spear", 1)
	var p: Vector3 = world.player.global_position
	Game.submit({"type": "debug", "spawn": "wolf", "pos": [p.x, p.y, p.z - 2.0]})
	await frames(tree, 2)
	var uid := ""
	for u: String in st.creatures:
		if st.creatures[u]["id"] == "wolf":
			uid = u
	check(uid != "", "a wolf in front")
	var view: CreatureView = world.creatures.views.get(uid)
	check(view != null, "and its view")
	world.player.model.rotation.y = 0.0  # facing -Z, the wolf
	var stamina: float = world.player.stamina
	world.combat.strike(false)
	check(float(st.creatures.get(uid, {"hp": 0.0})["hp"]) <= 60.0 - 14.0, "a spear strike: 14")
	check(world.player.stamina < stamina, "a strike costs stamina")
	world.combat.strike(true)
	await frames(tree, 2)
	check(not st.creatures.has(uid) or float(st.creatures[uid]["hp"]) <= 60.0 - 14.0 - 28.0, "a heavy strike: twice as much")
	_done(tree)


func test_a_lost_saga_defence_from_the_tower(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 23, "saga")
	var st: WorldState = Game.state
	var pid := Net.local_player_id()
	await _put(tree, world, Game.map.path_point("b01", 0.95, 0.0))
	var fuel := ContentDB.bag(db.beacons["b01"]["fuel"])
	check(String(world._beacon_action().get("label", "")).begins_with(tr("act.need_fuel").split("%")[0]), "the tower asks for fuel first")
	Game.submit({"type": "debug", "give": fuel})
	var a: Dictionary = world._beacon_action()
	eq(a.get("label", ""), tr("act.defend_fire") % int(db.beacons["b01"]["saga"]["seconds"]))
	(a["run"] as Callable).call()
	eq(st.busy_beacon, "b01", "the defence is on")
	await frames(tree, 60 * 5)
	var waves := 0
	for e: Dictionary in _events:
		if e["type"] == "creature_spawned" and e.get("fight", false):
			waves += 1
	check(waves >= 2, "the first wave comes out of the fog (%d)" % waves)
	check(world.hud.boss_panel.visible, "the fire's bar is up")
	# the player falls
	Game.submit({"type": "debug", "hp": 1.0})
	var wolfish := ""
	for u: String in st.creatures:
		if String(st.creatures[u]["fight"]) != "":
			wolfish = u  # a creature of the defence, not a passing hare
	st.creatures[wolfish]["pos"] = st.players[pid]["pos"]
	var hr: Dictionary = Game.submit({"type": "hurt", "player": pid, "source": wolfish})
	check(hr["ok"], "the hit lands: %s (%s, %d creatures)" % [hr["error"], wolfish, st.creatures.size()])
	await frames(tree, 150)
	eq(st.busy_beacon, "", "the fire went out")
	check(not st.lit.has("b01"), "not lit")
	var fuel_left := st.inv(pid).has_bag(fuel)
	var in_grave := false
	for g: String in st.graves:
		in_grave = true
	check(fuel_left or in_grave, "the fuel is not spent: in the bag or at the grave marker")
	check(Vector2(world.player.global_position.x, world.player.global_position.z).length() < 150.0, "woke up at home")
	_done(tree)


func test_menu_tuning_and_journal(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 24, "tale")
	var menu := MainMenu.new()
	add(tree, menu)
	await frames(tree, 2)
	menu._pick("saga")
	eq(menu.tuning(), {}, "Saga as it is: no fine tuning")
	(menu._checks["storms"] as CheckBox).button_pressed = false
	(menu._checks["night_raids"] as CheckBox).button_pressed = false
	eq(menu.tuning(), {"storms": "cosmetic", "night_raids": false}, "only what differs from the mode")
	menu._pick("quiet")
	check((menu._checks["night_raids"] as CheckBox).disabled, "night raids are Saga-only")
	(menu._checks["cold"] as CheckBox).button_pressed = true
	eq(menu.tuning(), {"cold": "mild"}, "cold in a Quiet world: the mild kind")
	# the journal
	Game.submit({"type": "debug", "journal": "domovoy"})
	world._open_journal()
	await frames(tree, 2)
	check(world.journal.visible, "J opens the journal")
	eq(world.journal._title.text, Loc.name_of(db.creatures["domovoy"]["name"]))
	check(world.journal._text.text.find("TODO") >= 0, "the tales are drafts marked TODO for the author")
	check(world.ui_open(), "the journal takes the keys")
	world.journal.close_window()
	# the pause menu changes the mode
	world.pause_menu.open(world)
	check(Game.paused, "time stands still in a solo pause")
	world.pause_menu._set_mode("saga")
	eq(Game.state.mode, "saga")
	world.pause_menu.close_window()
	check(not Game.paused, "and runs again")
	_done(tree)


func test_the_evening_by_the_stove(tree: SceneTree) -> void:
	var world: Node3D = await _world(tree, 25, "quiet")
	var pid := Net.local_player_id()
	Game.reset_session()
	Game._count({"type": "gathered", "player": pid, "node": "home:1", "item": "wood", "n": 5})
	Game._count({"type": "gathered", "player": pid, "node": "home:2", "item": "wood", "n": 3})
	Game._count({"type": "piece_placed", "player": pid, "piece": "bed", "uid": "p1"})
	Game._count({"type": "beacon_lit", "player": pid, "beacon": "b01", "unlocks": db.unlocks_of("b01")})
	Game.autosave = false
	Game.quit_requested.emit()  # the window's close button
	await frames(tree, 2)
	check(world.evening.visible, "closing the window shows the evening first")
	check(Game.paused, "time stands still meanwhile")
	var rows: Array = world.evening.rows()
	var text := str(rows)
	check(text.find(Loc.beacon(db, "b01")) >= 0, "the beacon lit tonight")
	check(text.find("8") >= 0, "wood 8 gathered")
	check(text.find(Loc.name_of(db.pieces["bed"]["name"]).to_lower()) >= 0, "the bed built")
	var next := Progress.next_beacon(db, Game.state)
	check(String(world.evening.next_time(Vector3.ZERO)).find(Loc.beacon(db, next)) >= 0, "next time: the next beacon")
	world.evening.close_window()
	check(not Game.paused, "\"a little more\" goes back to the game")
	Game.autosave = true
	_done(tree)
