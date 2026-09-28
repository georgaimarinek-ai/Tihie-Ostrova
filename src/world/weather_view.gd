class_name WeatherView
extends Node3D
## Storms and precipitation (docs/01_GDD.md §4.3, §6): the storm level (Weather.storm, the same on every peer)
## drives the waves (Sea.storm) and rain — snow in cold regions. In Tale and Saga a storm above the hull's
## class capsizes the boat (the host sends "capsize"; E rights it). Siverko's squall adds to the storm.

var world
var db: ContentDB
var state: WorldState
var level := 0.0  # smoothed storm level the sea and the rain follow
var squall := 0.0  # extra storm from a guardian (Siverko's second phase)
var rain: CPUParticles3D
var _check := 5.0


func setup(p_world) -> void:
	world = p_world
	db = world.db
	state = world.state
	name = "Weather"
	rain = CPUParticles3D.new()
	rain.name = "Rain"
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.7)
	rain.mesh = q
	rain.material_override = Placeholders.mat(Color(0.8, 0.85, 0.9), Color(0.55, 0.6, 0.66), 0.4, true)
	rain.amount = 900
	rain.lifetime = 1.2
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22, 1, 22)
	rain.direction = Vector3(0.15, -1, 0)
	rain.spread = 4.0
	rain.gravity = Vector3(0, -20, 0)
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	rain.local_coords = false
	rain.emitting = false
	add_child(rain)


func _process(delta: float) -> void:
	var f: Vector3 = world._focus()
	var rid := db.region_at(Vector2(f.x, f.z))
	var want := float(Weather.storm(db, state.world_seed, state.clock_min, rid)) + squall
	level = move_toward(level, want, delta * 0.15)
	world.sea.storm = level
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		rain.global_position = cam.global_position + Vector3(0, 9, 0)
	var cold := bool(db.regions[rid]["cold"])
	rain.emitting = level > 0.6
	if cold:
		rain.gravity = Vector3(1.5, -2.5, 0)
		rain.initial_velocity_min = 1.0
		rain.initial_velocity_max = 2.5
		(rain.mesh as QuadMesh).size = Vector2(0.08, 0.08)
	else:
		rain.gravity = Vector3(0, -20, 0)
		rain.initial_velocity_min = 16.0
		rain.initial_velocity_max = 20.0
		(rain.mesh as QuadMesh).size = Vector2(0.03, 0.7)
	for uid: String in world.boats:
		if state.boats.has(uid):
			(world.boats[uid] as Boat).capsized = bool(state.boats[uid]["capsized"])
	# the host checks now and then whether the storm turns the player's boat over
	_check -= delta
	if _check <= 0.0 and Net.is_authority():
		_check = 5.0
		var b: Boat = world.my_boat
		if b != null and not b.capsized and Weather.capsizes(db, state.rules(), b.type, int(want)) and randf() < 0.3:
			Game.submit({"type": "capsize", "boat": b.uid})
