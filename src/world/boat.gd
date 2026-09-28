class_name Boat
extends RigidBody3D
## A boat from boats.json on the shared waves (docs/04_TECH_SPEC.md §6, feel from reference/sketch):
## - four buoyancy points: force = k·(Waves.height − y) with damping; at rest the origin sits on the waterline;
## - the sail sets itself: full speed with a beam or following wind, balance.sea.headwind_speed into it;
##   S rows astern at the boat's row_speed;
## - the rudder turns 0.35–0.85 rad/s depending on speed (the sketch's numbers);
## - anchored: holds its spot, still rides the waves.
## Only the helmsman's machine (the host in co-op) simulates the boat; its position goes to the world with
## the "move" command.

const DRAFT := 0.25  # how deep the buoyancy points sit at rest
const ACCEL := 0.7  # 1/s towards the target speed with the sail set (sketch: 0.7)
const COAST := 0.45  # 1/s when drifting
const KEEL := 2.5  # 1/s: sideways drift dies quickly
const MASS := {"karbas": 600.0, "shnyaka": 1300.0, "koch": 2400.0}

var db: ContentDB
var type := "karbas"
var uid := ""
var data: Dictionary = {}
## Helm input: throttle -0.5..1 (W sails, S rows astern), steer -1..1 (A = +1 = turn left).
var throttle := 0.0
var steer := 0.0
var anchored := false
var anchor_at := Vector3.ZERO
var wind := Vector2(1, 0)  # where the wind blows to (Weather.wind)
var storm := 0.0
var wave_gain := 1.0  # 0 = flat water (tests)
var model: Node3D
var speed := 0.0  # signed forward speed, m/s (HUD, audio)
var submerged := 0  # buoyancy points under water this step
## The sea wall (SeaWall): with a world attached, a closed region (or one that needs a stronger boat) turns
## the boat home after balance.fog.lock_push_s seconds inside.
var world_state: WorldState
var wall := ""  # "" | "locked" | "boat": what the sea says here
var wall_time := 0.0  # seconds spent inside the wall
var pushed := false  # the current has taken over the helm
var capsized := false  # WorldState boats[uid].capsized: keel up, no sail, no helm until righted

var _points: Array[Vector3] = []
var _turn := 0.0
var _sails: Array[Node3D] = []


func setup(p_db: ContentDB, p_type: String, p_uid: String = "") -> void:
	db = p_db
	type = p_type
	uid = p_uid
	data = db.boats[type]


func _ready() -> void:
	if data.is_empty():
		setup(ContentDB.shared(), type, uid)
	var hull: Dictionary = Placeholders.HULLS.get(type, Placeholders.HULLS["karbas"])
	var length: float = hull["length"]
	var beam: float = hull["beam"]
	var depth: float = hull["depth"]
	mass = float(MASS.get(type, 600.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	# drag and keel are modelled in _integrate_forces; don't add the project's default damping on top
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 1.2
	can_sleep = false
	custom_integrator = false
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(beam * 0.85, depth + 0.2, length * 0.92)
	shape.shape = box
	shape.position = Vector3(0, 0.05, 0)
	add_child(shape)
	var hx := beam * 0.36
	var hz := length * 0.36
	_points = [Vector3(-hx, -DRAFT, -hz), Vector3(hx, -DRAFT, -hz), Vector3(-hx, -DRAFT, hz), Vector3(hx, -DRAFT, hz)]
	model = ModelLibrary.instance("boats", type)
	add_child(model)
	for n: String in ["Sail", "Sail2"]:
		if model.has_node(n):
			_sails.append(model.get_node(n))


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var t := Sea.time
	var g := st.total_gravity.length()
	var k := mass * g / (4.0 * DRAFT)
	var c := 0.7 * 2.0 * mass * sqrt(g / DRAFT) / 4.0
	var xf := st.transform
	submerged = 0
	for lp in _points:
		var wp := xf * lp
		var depth := Waves.height(wp.x, wp.z, t, storm) * wave_gain - wp.y
		if depth <= 0.0:
			continue
		submerged += 1
		var rel := wp - xf.origin
		var v := st.linear_velocity + st.angular_velocity.cross(rel)
		st.apply_force(Vector3(0, k * minf(depth, 1.5) - c * v.y, 0), rel)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var vel := st.linear_velocity
	var v_fwd := vel.dot(fwd)
	var v_side := vel.dot(right)
	speed = v_fwd
	var helm := 0.0 if capsized else steer
	var sail := 0.0 if capsized else throttle
	_update_wall(st.step, Vector2(xf.origin.x, xf.origin.z))
	if pushed:
		# the current turns the bow home and carries the boat out of the Mga, gently
		var home := SeaWall.pull(Vector2(xf.origin.x, xf.origin.z))
		var off := Vector2(fwd.x, fwd.z).angle_to(home)
		helm = clampf(-off * 2.0, -1.0, 1.0)
		sail = 0.5
		st.apply_central_force(Vector3(home.x, 0.0, home.y) * mass * 0.8)
	var target := 0.0
	if not anchored:
		if sail > 0.0:
			target = sail * float(data["speed"]) * Weather.sail_factor(db, Vector2(fwd.x, fwd.z), wind)
		elif sail < 0.0:
			target = sail * 2.0 * float(data["row_speed"])
	var wet := float(submerged) / 4.0
	if wet > 0.0:
		var rate := ACCEL if sail != 0.0 else COAST
		st.apply_central_force(fwd * mass * rate * (target - v_fwd) * wet)
		st.apply_central_force(-right * mass * KEEL * v_side * wet)
	if anchored:
		var off := anchor_at - xf.origin
		off.y = 0.0
		st.apply_central_force(off * mass * 0.6 - Vector3(vel.x, 0.0, vel.z) * mass * 1.5)
	# rudder: the sketch's yaw rate, smoothed like its turn input
	_turn = lerpf(_turn, 0.0 if anchored else helm, 1.0 - exp(-st.step * 3.0))
	var yaw_rate := _turn * (0.35 + 0.5 * minf(1.0, absf(v_fwd) / 5.0))
	var av := st.angular_velocity
	av.y = lerpf(av.y, yaw_rate, 1.0 - exp(-st.step * 6.0))
	st.angular_velocity = av


func _process(delta: float) -> void:
	# the sail sets itself across the wind and fills with speed; the hull leans into turns
	var local_wind := global_transform.basis.inverse() * Vector3(wind.x, 0, wind.y)
	var sail_yaw := clampf(atan2(-local_wind.x, -local_wind.z) * 0.5, -1.1, 1.1)
	for s in _sails:
		s.rotation.y = lerp_angle(s.rotation.y, sail_yaw, 1.0 - exp(-delta * 1.5))
		s.scale.z = 0.7 + 0.3 * sin(Sea.time * 1.3) + minf(1.0, absf(speed) / 9.0) * 0.4
	if model != null:
		var roll := 2.75 if capsized else -_turn * 0.06  # a capsized hull floats keel up
		model.rotation.z = lerpf(model.rotation.z, roll, 1.0 - exp(-delta * (1.5 if capsized else 3.0)))
		model.position.y = lerpf(model.position.y, 0.9 if capsized else 0.0, 1.0 - exp(-delta * 1.5))


## Time inside the wall grows while the sea says no and melts away outside; after lock_push_s the
## current takes the helm until the boat is back in open water.
func _update_wall(dt: float, pos: Vector2) -> void:
	if world_state == null or anchored:
		wall = ""
		wall_time = 0.0
		pushed = false
		return
	wall = SeaWall.blocked(db, world_state, pos, type)
	if wall != "":
		wall_time += dt
	else:
		wall_time = maxf(0.0, wall_time - dt * 2.0)
	if wall_time > SeaWall.push_after_s(db):
		pushed = true
	elif wall == "" and wall_time <= 0.0:
		pushed = false


func drop_anchor() -> void:
	anchored = true
	anchor_at = global_position
	throttle = 0.0
	steer = 0.0


func weigh_anchor() -> void:
	anchored = false


func yaw() -> float:
	var f := -global_transform.basis.z
	return atan2(-f.x, -f.z)


## Heading on the water plane.
func heading() -> Vector2:
	var f := -global_transform.basis.z
	return Vector2(f.x, f.z).normalized()


## The lantern clears the fog around the boat (sketch: 16 m, 0.55 aboard; 10 m, 0.4 when moored).
func fog_light(aboard: bool) -> Vector4:
	return Vector4(global_position.x, global_position.z, 16.0 if aboard else 10.0, 0.55 if aboard else 0.4)
