extends "res://tests/lib/case.gd"
## The life of the world (roadmap phase 6): spirits never hurt anyone in any mode, death by the mode's rules,
## day and night by region, storms by level, the cold of the Frozen Sea, gifts to spirits and the journal.

const MODES := ["quiet", "tale", "saga"]


func _world(mode: String, pos: Vector3 = Vector3(20, 0, 20)) -> WorldCommands:
	var st := WorldState.new(db, 7, mode)
	st.add_player("p1", pos)
	return WorldCommands.new(db, st, WorldMap.shared(db))


## A creature put straight into the world (what the host's spawn would do), next to the player.
func _creature(c: WorldCommands, id: String) -> String:
	var uid := c.state.new_uid("c")
	c.state.creatures[uid] = {"id": id, "pos": c.state.players["p1"]["pos"] + Vector3(1, 0, 0), "hp": float(db.creatures[id]["hp"]), "fight": ""}
	return uid


func test_spirits_are_always_friendly() -> void:
	for id: String in db.creatures:
		var g := Creatures.group(db, id)
		if g in ["spirit", "wonder", "legend"]:
			check(Creatures.is_friendly(db, id), id + " is friendly")
			eq(float(db.creatures[id]["damage"]), 0.0, id + " has no damage in content")
	for mode: String in MODES:
		var c := _world(mode)
		for id: String in db.creatures:
			if not Creatures.is_spirit(db, id):
				continue
			var uid := _creature(c, id)
			var hp := float(c.state.players["p1"]["hp"])
			for k in [1.0, 2.0]:
				eq(c.apply("p1", {"type": "hurt", "player": "p1", "source": uid, "k": k})["error"], "friendly", "%s can't hurt in %s" % [id, mode])
			eq(float(c.state.players["p1"]["hp"]), hp, "health untouched")
			eq(Creatures.damage_to_player(db, id, 2.0, "", false), 0.0)
			eq(c.apply("p1", {"type": "attack", "target": uid})["error"], "friendly", "and can't be struck")
		# fine tuning can't make them enemies either
		for rule: String in WorldCommands.TUNABLE:
			for v: Variant in WorldCommands.TUNABLE[rule]:
				c.state.tuning[rule] = v
				check(Creatures.is_friendly(db, "domovoy") and Creatures.is_friendly(db, "leshy"), "tuning %s=%s" % [rule, str(v)])


func test_hurting_follows_the_mode() -> void:
	var quiet := _world("quiet")
	eq(quiet.apply("p1", {"type": "hurt", "player": "p1", "source": _creature(quiet, "wolf")})["error"], "no_harm", "Quiet takes no health")
	var tale := _world("tale")
	var wolf := _creature(tale, "wolf")
	check(tale.apply("p1", {"type": "hurt", "player": "p1", "source": wolf})["ok"], "a wolf bites in Tale")
	near(float(tale.state.players["p1"]["hp"]), 90.0, 1e-6, "10 damage (creatures.json)")
	tale.state.players["p1"]["stance"] = "dodge"
	tale.apply("p1", {"type": "hurt", "player": "p1", "source": wolf})
	near(float(tale.state.players["p1"]["hp"]), 90.0, 1e-6, "a dodge takes nothing")
	tale.state.players["p1"]["stance"] = "block"
	tale.state.inv("p1").add("shield", 1)
	tale.apply("p1", {"type": "hurt", "player": "p1", "source": wolf})
	near(float(tale.state.players["p1"]["hp"]), 90.0, 1e-6, "a shield block takes 10 off a 10 bite")
	eq(tale.apply("p1", {"type": "hurt", "source": wolf})["ok"], true)
	check(WorldCommands.HOST_ONLY.has("hurt") and WorldCommands.HOST_ONLY.has("spawn"), "only the host deals creature damage")


func test_death_rules_by_mode() -> void:
	# Quiet: no death at all; if something drops you, you're back where you last came ashore, with everything
	var quiet := _world("quiet")
	quiet.state.players["p1"]["landed"] = Vector3(7, 1, 7)
	quiet.state.inv("p1").add("stone", 3)
	var r := quiet.apply("p1", {"type": "die"})
	eq(r["events"][0]["at"], [7.0, 1.0, 7.0], "back at the last landing")
	eq(quiet.state.inv("p1").count("stone"), 3)
	# Tale: wake at home (the bed) with everything, Weary for 3 minutes
	var tale := _world("tale")
	tale.state.players["p1"]["spawn"] = Vector3(1, 2, 3)
	tale.state.inv("p1").add("stone", 3)
	var wolf := _creature(tale, "wolf")
	for i in 12:
		tale.apply("p1", {"type": "hurt", "player": "p1", "source": wolf})
	eq(tale.state.inv("p1").count("stone"), 3, "Tale keeps everything")
	eq(tale.state.players["p1"]["pos"], Vector3(1, 2, 3), "woke up in bed")
	near(float(tale.state.players["p1"]["weary_until"]) - tale.state.clock_min, 3.0, 1e-6, "Weary 3 min")
	near(float(tale.state.players["p1"]["hp"]), 100.0, 1e-6, "health back")
	check(Vitals.stamina_regen(db, tale.state, "p1") < float(db.balance["player"]["stamina_regen_per_s"]), "Weary: slower stamina")
	# Saga: things wait in a grave marker, Weary 10 min (the grave itself: test_commands.test_death_by_mode)
	var saga := _world("saga")
	saga.state.inv("p1").add("stone", 3)
	var bear := _creature(saga, "bear")
	var dead := false
	for i in 10:
		if dead:
			break
		for e: Dictionary in saga.apply("p1", {"type": "hurt", "player": "p1", "source": bear})["events"]:
			if e["type"] == "respawn":
				dead = true
				check(e.has("grave"), "a grave marker")
	check(dead, "a bear kills in Saga")
	near(float(saga.state.players["p1"]["weary_until"]) - saga.state.clock_min, 10.0, 1e-6, "Weary 10 min")


func test_day_and_night_by_region() -> void:
	var len := float(db.balance["day"]["length_min"])
	near(Weather.day_phase(db, 0.0), 0.25, 1e-6, "a world starts at dawn")
	var midnight := len * 0.75
	eq(Weather.night(db, "r1", midnight), 0.0, "white nights in the Quiet Bay")
	near(Weather.night(db, "r4", midnight), 1.0, 1e-6, "the polar night")
	near(Weather.night(db, "r2", midnight), 1.0, 1e-6, "a short night on the Summer Shore")
	eq(Weather.night(db, "r2", 0.0), 0.0, "…over by six")
	near(Weather.night(db, "r4", 0.0), 1.0, 1e-6, "the Frozen Sea is still dark at six")
	eq(Weather.night(db, "r4", len * 0.25), 0.0, "but it has its noon")
	# the share of night over a whole day matches balance.day.night_share
	for rid: String in ["r1", "r2", "r3", "r4"]:
		var n := 0.0
		for i in 1000:
			n += Weather.night(db, rid, len * i / 1000.0)
		near(n / 1000.0, float(db.balance["day"]["night_share"][rid]), 0.02, rid + " night share")
	check(Weather.after_midnight(db, midnight + 1.0) and not Weather.after_midnight(db, len * 0.5), "the bannik's hours")


func test_storms_by_level() -> void:
	for rid: String in ["r1", "r2", "r3", "r4"]:
		var top := 0
		for i in 3000:
			var l := Weather.storm(db, 5, i * 0.5, rid)
			check(l >= 0 and l <= int(db.regions[rid]["storm_max"]), "level within the region's max")
			top = maxi(top, l)
		eq(top, int(db.regions[rid]["storm_max"]), rid + " reaches its worst storm now and then")
	var tale := WorldState.new(db, 1, "tale")
	var quiet := WorldState.new(db, 1, "quiet")
	check(Weather.capsizes(db, tale.rules(), "karbas", 2), "a karbas capsizes in a level-2 storm in Tale")
	check(not Weather.capsizes(db, tale.rules(), "koch", 3), "a koch rides out anything")
	check(not Weather.capsizes(db, quiet.rules(), "karbas", 3), "Quiet storms are only waves and rain")
	tale.tuning["storms"] = "cosmetic"
	check(not Weather.capsizes(db, tale.rules(), "karbas", 3), "fine tuning: storms don't capsize")


func test_capsize_and_right_the_boat() -> void:
	var c := _world("tale")
	var uid := c.state.add_boat("karbas", Vector3(0, 0, -2000), 0.0)
	c.state.players["p1"]["aboard"] = uid
	var at := -1.0
	for i in 20000:
		if Weather.storm(db, c.state.world_seed, i * 0.25, "r3") >= 2:
			at = i * 0.25
			break
	check(at >= 0.0, "a storm comes")
	c.state.clock_min = at
	check(c.apply("p1", {"type": "capsize", "boat": uid})["ok"], "the karbas capsizes on the Ter Coast")
	check(c.apply("p1", {"type": "right_boat", "boat": uid})["ok"], "and is righted")
	eq(c.state.boats[uid]["capsized"], false)
	var q := _world("quiet")
	var qb := q.state.add_boat("karbas", Vector3(0, 0, -2000), 0.0)
	q.state.clock_min = at
	eq(q.apply("p1", {"type": "capsize", "boat": qb})["error"], "no_storm", "never in Quiet")


func test_cold_of_the_frozen_sea() -> void:
	var cold := Vector3(0, 0, -3000)
	var tale := _world("tale", cold)
	check(Creatures.is_cold(db, tale.state, "p1"), "cold without a coat")
	eq(Vitals.stamina_regen(db, tale.state, "p1"), 0.0, "Tale: no stamina back in the cold")
	tale.apply("p1", {"type": "tick", "dt_min": 1.0})
	near(float(tale.state.players["p1"]["hp"]), 100.0, 1e-6, "Tale: the cold doesn't take health")
	tale.state.inv("p1").add("wool_coat", 1)
	check(not Creatures.is_cold(db, tale.state, "p1"), "the coat keeps you warm")
	var saga := _world("saga", cold)
	saga.apply("p1", {"type": "tick", "dt_min": 1.0})
	near(float(saga.state.players["p1"]["hp"]), 100.0 - 30.0, 1e-4, "Saga: the cold drains 0.5 hp/s")
	var quiet := _world("quiet", cold)
	check(not Creatures.is_cold(db, quiet.state, "p1"), "Quiet: the cold is only frost on the screen")
	saga.state.players["p1"]["light"] = {"id": "torch", "until": 99.0}
	check(not Creatures.is_cold(db, saga.state, "p1"), "fire in hand warms")


func test_health_comes_back() -> void:
	var c := _world("tale")
	c.state.players["p1"]["hp"] = 50.0
	c.state.players["p1"]["hurt_at"] = c.state.clock_min
	c.apply("p1", {"type": "tick", "dt_min": 0.05})
	near(float(c.state.players["p1"]["hp"]), 50.0, 1e-6, "not right after a hit")
	c.apply("p1", {"type": "tick", "dt_min": 0.5})
	near(float(c.state.players["p1"]["hp"]), 80.0, 1e-4, "then 1 hp/s")
	c.apply("p1", {"type": "tick", "dt_min": 1.0})
	near(float(c.state.players["p1"]["hp"]), 100.0, 1e-6, "up to the maximum")


## A home around a bed: hearth, table and bench (comfort 4), and a bathhouse stove (+2) if asked.
func _home(c: WorldCommands, with_bath: bool) -> String:
	var inv := c.state.inv("p1")
	for k in ["wood", "stone", "moss", "birch_bark", "rope"]:
		inv.add(k, 100)
	c.state.lit["b01"] = 1  # the bathhouse stove opens with b02
	c.state.lit["b02"] = 1
	var at: Vector3 = c.state.players["p1"]["pos"]
	var bed: String = c.apply("p1", {"type": "place", "piece": "bed", "pos": [at.x, at.y, at.z]})["events"][0]["uid"]
	var around := {"hearth": Vector3(2.5, 0, 0), "table": Vector3(0, 0, 2.5), "bench": Vector3(-2.5, 0, 0)}
	if with_bath:
		around["bathhouse_stove"] = Vector3(0, 0, -2.5)
	for piece: String in around:
		var q: Vector3 = at + around[piece]
		check(c.apply("p1", {"type": "place", "piece": piece, "pos": [q.x, q.y, q.z]})["ok"], "placed " + piece)
	return bed


func _add(c: WorldCommands, piece: String, q: Vector3) -> String:
	return c.apply("p1", {"type": "place", "piece": piece, "pos": [q.x, q.y, q.z]})["events"][0]["uid"]


func test_the_domovoy() -> void:
	var c := new_world("quiet")
	c.state.inv("p1").add("kalitki", 3)
	eq(c.apply("p1", {"type": "offer", "spirit": "domovoy"})["error"], "no_domovoy", "no home yet")
	var bed := _home(c, false)
	eq(int(Comfort.at(db, c.state, c.state.pieces[bed]["pos"])["total"]), 4, "comfort 4")
	eq(Creatures.domovoy_home(db, c.state), "", "not enough comfort for him")
	_add(c, "bathhouse_stove", Vector3(0, 0, -2.5))
	var home := Creatures.domovoy_home(db, c.state)
	check(home != "", "a stove, a bed and comfort 5: the domovoy moves in")
	c.state.players["p1"]["pos"] = c.state.pieces[home]["pos"]
	var before := int(Comfort.at(db, c.state, c.state.pieces[home]["pos"])["total"])
	var r := c.apply("p1", {"type": "offer", "spirit": "domovoy"})
	check(r["ok"], "kalitki for the domovoy")
	eq(int(Comfort.at(db, c.state, c.state.pieces[home]["pos"])["total"]), before + 2, "+2 comfort while fed")
	eq(c.apply("p1", {"type": "offer", "spirit": "domovoy"})["error"], "not_hungry", "one gift in three days")
	check(c.state.journal.has("domovoy"), "a page in the journal")
	c.state.clock_min += 3.0 * float(db.balance["day"]["length_min"]) + 1.0
	check(not Creatures.domovoy_fed(db, c.state), "hungry again after three days")


func test_the_bannik_keeps_his_hours() -> void:
	var c := new_world("tale")
	var bed := _home(c, true)
	var stove := ""
	for uid: String in c.state.pieces:
		if c.state.pieces[uid]["id"] == "bathhouse_stove":
			stove = uid
	c.state.players["p1"]["pos"] = c.state.pieces[stove]["pos"]
	var r := c.apply("p1", {"type": "steam", "uid": stove})
	eq(r["events"][0]["bannik"], "pleased")
	near(float(r["events"][0]["minutes"]), 15.0, 1e-6, "the rule kept: steam lasts 50% longer")
	c.state.clock_min = float(db.balance["day"]["length_min"]) * 0.8  # an hour after midnight
	r = c.apply("p1", {"type": "steam", "uid": stove})
	eq(r["events"][0]["bannik"], "angry", "after midnight the steam is his")
	near(float(r["events"][0]["minutes"]), 10.0, 1e-6, "no bonus")
	check(bed != "", "")


func test_leshy_vodyanoy_and_the_journal() -> void:
	var m := WorldMap.shared(db)
	var forest := ""
	for isl: IslandGen in m.islands:
		if db.region_at(isl.center) == "r1" and m.forested(isl.id):
			forest = isl.id
			break
	check(forest != "", "a big forested island in the Quiet Bay")
	var c := _world("quiet")
	c.state.inv("p1").add("cloudberry", 2)
	c.state.inv("p1").add("raw_fish", 2)
	c.state.players["p1"]["pos"] = Vector3(0, 0, -300)  # at sea, no island
	eq(c.apply("p1", {"type": "offer", "spirit": "leshy"})["error"], "not_here")
	var fc: Vector2 = (m.by_id[forest] as IslandGen).center
	c.state.players["p1"]["pos"] = Vector3(fc.x, m.ground_at(fc.x, fc.y), fc.y)
	check(c.apply("p1", {"type": "offer", "spirit": "leshy"})["ok"], "cloudberries on a stump")
	check(Creatures.leshy_guiding(c.state), "the green wisp leads")
	eq(c.apply("p1", {"type": "offer", "spirit": "vodyanoy"})["error"], "not_here", "the vodyanoy isn't in the Quiet Bay")
	c.state.players["p1"]["pos"] = Vector3(0, 0, -1000)  # the Summer Shore, at sea
	c.state.players["p1"]["aboard"] = "b1"
	check(c.apply("p1", {"type": "offer", "spirit": "vodyanoy"})["ok"], "the first fish to the vodyanoy")
	check(Creatures.vodyanoy_boon(c.state), "better bites today")
	eq(c.apply("p1", {"type": "offer", "spirit": "vodyanoy"})["error"], "not_hungry", "once a day")
	check(c.state.journal.has("leshy") and c.state.journal.has("vodyanoy"), "journal pages")
	# meeting: the whale on a calm night of the Frozen Sea gives rest; Sirin sings only at dawn
	c.state.players["p1"]["pos"] = Vector3(0, 0, -3000)
	var len := float(db.balance["day"]["length_min"])
	c.state.clock_min = len * 0.75
	var calm := c.state.clock_min
	while Weather.storm(db, c.state.world_seed, calm, "r4") > 0:
		calm += len
	c.state.clock_min = calm
	var rested := float(c.state.players["p1"]["rested_until"])
	check(c.apply("p1", {"type": "meet", "creature": "ryba_kit"})["ok"], "the miracle whale surfaces")
	check(float(c.state.players["p1"]["rested_until"]) > rested, "rest by its chapel")
	eq(c.apply("p1", {"type": "meet", "creature": "sirin"})["error"], "not_now", "Sirin sings at dawn")
	eq(c.apply("p1", {"type": "meet", "creature": "siverko"})["error"], "unknown_creature", "no guardians in Quiet")


func test_chud_ruins() -> void:
	var m := WorldMap.shared(db)
	var sites := m.chud_sites()
	check(sites.size() >= 8, "stone circles and mines on the Summer Shore and the Ter Coast (%d)" % sites.size())
	for s: Dictionary in sites:
		check(db.region_at(Vector2((s["pos"] as Vector3).x, (s["pos"] as Vector3).z)) in ["r2", "r3"], "chud lives in r2 and r3")
	var c := _world("saga")
	var s0: Dictionary = sites[0]
	eq(c.apply("p1", {"type": "explore", "site": s0["id"]})["error"], "too_far")
	c.state.players["p1"]["pos"] = s0["pos"]
	check(c.apply("p1", {"type": "explore", "site": s0["id"]})["ok"], "a ruin explored")
	eq(c.state.inv("p1").count("mica"), 2, "finds")
	check(c.state.journal.has(s0["id"]), "a tale")
	eq(c.apply("p1", {"type": "explore", "site": s0["id"]})["error"], "explored", "once")


func test_fine_tuning() -> void:
	var c := _world("tale")
	check(c.apply("p1", {"type": "set_tuning", "rule": "storms", "value": "cosmetic"})["ok"], "storms off")
	eq(c.state.rules()["storms"], "cosmetic")
	check(c.apply("p1", {"type": "set_tuning", "rule": "storms", "value": "capsize"})["ok"], "back to the mode's own")
	check(not c.state.tuning.has("storms"), "the mode's value needs no override")
	eq(c.apply("p1", {"type": "set_tuning", "rule": "death", "value": "none"})["error"], "unknown_rule", "death isn't tunable")
	eq(c.apply("p1", {"type": "set_tuning", "rule": "cold", "value": "arctic"})["error"], "bad_value")


func test_save_v4_roundtrip_and_v3_migration() -> void:
	var c := _world("saga")
	c.state.name = "Родная губа"
	c.state.players["p1"]["hp"] = 42.0
	c.state.spirits["domovoy"] = {"fed_until": 99.0}
	_creature(c, "wolf")
	var back := WorldState.from_dict(db, c.state.to_dict())
	eq(back.name, "Родная губа")
	near(float(back.players["p1"]["hp"]), 42.0, 1e-6)
	eq(back.creatures.size(), 1)
	eq(SaveCodec.encode(back), SaveCodec.encode(c.state), "v4 round trip")
	var old := c.state.to_dict()
	old["version"] = 3
	for k in ["name", "spirits", "creatures", "fight"]:
		old.erase(k)
	for k in ["hp", "landed", "hurt_at"]:
		(old["players"]["p1"] as Dictionary).erase(k)
	var m := WorldState.from_dict(db, old)
	near(float(m.players["p1"]["hp"]), 100.0, 1e-6, "v3 players get full health")
	eq(m.name, "")
