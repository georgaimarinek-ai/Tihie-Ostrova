extends "res://tests/lib/case.gd"
## The boat floats on the shared waves (docs/06_ROADMAP.md phase 1): on calm water it holds the waterline
## within ±0.1 m for 10 s; on real waves it rides them; the sail pulls harder with a beam wind.


func _boat(tree: SceneTree, calm: bool) -> Boat:
	var sea := Sea.new()
	add(tree, sea)
	var b := Boat.new()
	b.setup(db, "karbas")
	b.wave_gain = 0.0 if calm else 1.0
	add(tree, b)
	b.global_position = Vector3(3000, 0.4, 3000)  # open sea, far from any island
	return b


func test_calm_water_holds_the_waterline(tree: SceneTree) -> void:
	var b := _boat(tree, true)
	await frames(tree, 90)  # settle after the drop
	var worst := 0.0
	for i in 600:
		await tree.physics_frame
		worst = maxf(worst, absf(b.global_position.y))
	check(worst < 0.1, "waterline held within 0.1 m (worst %.3f m)" % worst)


func test_rides_the_waves(tree: SceneTree) -> void:
	var b := _boat(tree, false)
	await frames(tree, 120)
	var err := 0.0
	for i in 300:
		await tree.physics_frame
		var p := b.global_position
		err += absf(p.y - Waves.height(p.x, p.z, Sea.time))
	check(err / 300.0 < 0.25, "follows the wave height (mean error %.3f m)" % (err / 300.0))
	check(absf(b.rotation.x) < 0.4 and absf(b.rotation.z) < 0.4, "stays upright")


func test_sails_and_turns(tree: SceneTree) -> void:
	var b := _boat(tree, true)
	await frames(tree, 30)
	var start := b.global_position
	b.wind = Vector2(1, 0)  # blowing east; the boat heads north: a beam wind
	b.throttle = 1.0
	await frames(tree, 600)
	var beam := b.speed
	check(beam > float(db.boats["karbas"]["speed"]) * 0.85, "near full speed with a beam wind (%.1f m/s)" % beam)
	check(b.global_position.z < start.z - 40.0, "moved forward (-z)")
	b.steer = 1.0
	var yaw0 := b.yaw()
	await frames(tree, 120)
	check(wrapf(b.yaw() - yaw0, -PI, PI) > 0.5, "A turns to port (yaw grows)")


func test_headwind_is_slower() -> void:
	var into := Weather.sail_factor(db, Vector2(0, -1), Vector2(0, 1))
	var beam := Weather.sail_factor(db, Vector2(0, -1), Vector2(1, 0))
	var tail := Weather.sail_factor(db, Vector2(0, -1), Vector2(0, -1))
	near(into, float(db.balance["sea"]["headwind_speed"]), 1e-6, "straight into the wind")
	near(beam, 1.0, 1e-6, "beam wind")
	near(tail, 1.0, 1e-6, "following wind")
	eq(Weather.wind_side(Vector2(0, -1), Vector2(0, 1)), "head")


func test_anchor_holds(tree: SceneTree) -> void:
	var b := _boat(tree, false)
	await frames(tree, 30)
	b.drop_anchor()
	var at := b.global_position
	b.throttle = 1.0
	await frames(tree, 300)
	var p := b.global_position
	check(Vector2(p.x - at.x, p.z - at.z).length() < 1.5, "anchored boat stays put (%.2f m)" % Vector2(p.x - at.x, p.z - at.z).length())


## The sea wall (roadmap phase 5): sailing into a closed region, after lock_push_s the current takes the helm
## and turns the bow home; no damage, no stop.
func test_sea_wall_turns_the_boat_home(tree: SceneTree) -> void:
	var b := _boat(tree, true)
	b.world_state = WorldState.new(db, 3, "quiet")
	b.global_position = Vector3(0, 0.4, -760)  # just inside the Summer Coast, still closed
	await frames(tree, 30)
	b.wind = Vector2(1, 0)
	b.throttle = 1.0  # full sail northwards, away from home
	await frames(tree, 60)
	eq(b.wall, "locked", "the sea says: not yet")
	check(not b.pushed, "the helm is still the player's")
	await frames(tree, int(SeaWall.push_after_s(db) * 60.0))
	check(b.pushed, "after %d s the current takes the helm" % int(SeaWall.push_after_s(db)))
	await frames(tree, 600)
	var home := SeaWall.pull(Vector2(b.global_position.x, b.global_position.z))
	check(b.heading().dot(home) > 0.7, "the bow points home (%.2f)" % b.heading().dot(home))
