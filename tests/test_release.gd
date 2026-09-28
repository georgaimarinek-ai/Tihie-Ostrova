extends "res://tests/lib/case.gd"
## Release (roadmap phase 10): all the content is there, boats and guardians included; achievements without
## grind; the demo is the Quiet Bay and its three beacons; export presets; the volumetric fog layer carves the
## beacons' clearings; no more than 8 real lights near the camera.


func test_all_the_content() -> void:
	eq(db.regions.size(), 4, "4 regions")
	eq(db.beacon_order.size(), 12, "12 beacons")
	var guardians := 0
	for id: String in db.creatures:
		if Creatures.group(db, id) == "guardian":
			guardians += 1
			check(db.beacons.has(String(db.creatures[id]["beacon"])), id + " guards a beacon")
	eq(guardians, 4, "4 guardians")
	eq(db.pieces.size(), 33, "33 pieces, all in the build menu (test_building)")
	for b: String in db.boats:
		var unlock := String(db.boats[b]["unlock"])
		check(unlock == "start" or String(db.boats[b]["station"]) == "boatyard", b + " is built at the boatyard")
	# every region can be sailed with a boat the game can build by then
	for rid: String in db.regions:
		var need := String(db.regions[rid]["boat_required"])
		var opened := String(db.regions[rid]["opened_by"])
		var unlock := String(db.boats[need]["unlock"])
		check(unlock == "start" or db.beacon_order.find(unlock) <= db.beacon_order.find(opened) + 3, "%s: the %s opens in time" % [rid, need])


func test_achievements_are_moments_not_grind() -> void:
	check(db.achievements.size() >= 10, "achievements in content")
	for id: String in db.achievements:
		var a: Dictionary = db.achievements[id]
		check(String(a["name"].get("en", "")) != "" and String(a["name"].get("ru", "")) != "", id + " named in both languages")
		check(not (a["when"] as Dictionary).has("count"), id + ": no counters")
	eq(Achievements.earned_by(db, {"type": "beacon_lit", "beacon": "b01", "player": "p1"}), ["first_fire"])
	check(Achievements.earned_by(db, {"type": "beacon_lit", "beacon": "b03"}).has("quiet_bay"), "the Quiet Bay's last beacon")
	eq(Achievements.earned_by(db, {"type": "creature_died", "id": "wolf"}), [], "killing isn't an achievement")
	eq(Achievements.earned_by(db, {"type": "steamed", "bannik": "angry"}), [], "only when the bannik's rule is kept")


func test_the_demo_is_the_quiet_bay() -> void:
	var st := WorldState.new(db, 1, "tale")
	for bid in ["b01", "b02", "b03"]:
		st.lit[bid] = 1
	SeaWall.demo = true
	eq(SeaWall.blocked(db, st, Vector2(0, -300), "karbas"), "", "the Quiet Bay is open")
	eq(SeaWall.blocked(db, st, Vector2(0, -1000), "karbas"), "demo", "the Summer Shore ends the demo")
	SeaWall.demo = false
	eq(SeaWall.blocked(db, st, Vector2(0, -1000), "karbas"), "", "the full game goes on")


func test_export_presets() -> void:
	var cf := ConfigFile.new()
	eq(cf.load("res://export_presets.cfg"), OK, "export_presets.cfg reads")
	var found := {}
	for sec in cf.get_sections():
		if sec.ends_with(".options"):
			continue
		found[String(cf.get_value(sec, "name"))] = [String(cf.get_value(sec, "platform")), String(cf.get_value(sec, "custom_features"))]
		check(String(cf.get_value(sec, "include_filter")).contains("content/*.json"), "content travels with the build")
		check(String(cf.get_value(sec, "exclude_filter")).contains("tests/*"), "tests stay home")
	eq(found.get("Windows", []), ["Windows Desktop", ""])
	eq(found.get("Linux", []), ["Linux", ""])
	eq(found.get("Windows Demo", []), ["Windows Desktop", "demo"])
	eq(found.get("Linux Demo", []), ["Linux", "demo"])


func test_volumetric_fog_carves_the_clearings(tree: SceneTree) -> void:
	var st := WorldState.new(db, 1, "quiet")
	st.lit["b01"] = 1
	var d := FogDirector.new()
	d.db = db
	d.state = st
	d.environment = Environment.new()
	d.volumetric = true  # high quality in Forward+ (the test machine draws nothing)
	add(tree, d)
	await frames(tree, 3)
	check(d.environment.volumetric_fog_enabled, "the volumetric layer is on")
	check(d.volumes.has("b01"), "a clearing for the lit beacon")
	var v: FogVolume = d.volumes["b01"]
	check((v.material as FogMaterial).density < 0.0, "negative density: it takes the fog away")
	near(v.size.x, float(db.beacons["b01"]["clear_radius"]) * 2.0, 1.0, "as wide as the clearing")
	var off := FogDirector.new()
	off.db = db
	off.state = st
	off.environment = Environment.new()
	add(tree, off)
	await frames(tree, 2)
	check(not off.environment.volumetric_fog_enabled and off.volumes.is_empty(), "light quality: no volumetric layer")


func test_the_light_budget(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node("Game")
	game.state = null
	game.debug_cheats = true
	game.new_world(41, "quiet")
	var world: Node3D = add(tree, load("res://src/scenes/world.tscn").instantiate())
	await frames(tree, 3)
	for i in 14:
		var l := OmniLight3D.new()
		l.add_to_group("budget_light")
		world.add_child(l)
		l.global_position = world.cam.global_position + Vector3(i * 3.0, 0, 0)
	var on: int = world.light_budget()
	eq(on, world.LIGHT_BUDGET, "8 lights on at most (docs/04_TECH_SPEC.md §11)")
	game.state = null
