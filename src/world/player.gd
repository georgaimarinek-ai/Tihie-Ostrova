class_name Player
extends CharacterBody3D
## The pomor on foot (docs/06_ROADMAP.md phase 2, feel from the sketch's updateFoot): W/S walk along the
## camera, A/D turn the camera (1.9 rad/s), the mouse looks around, Shift runs while stamina lasts, Space
## jumps. The shore is the edge: the player never walks into deep water (ground below -0.35 m).
## Only a view of the local player: where it stands goes to the world with the "move" command.

const WALK := 4.2
const RUN := 7.0
const TURN := 1.9
const JUMP := 4.6
const GRAVITY := 18.0
const WATER_EDGE := -0.35

var db: ContentDB
var map: WorldMap
var cam: CameraRig
var model: Node3D
var stamina := 100.0
var stamina_max := 100.0
var stamina_regen := 12.0
var sprint_cost := 10.0
var walked := 0.0  # metres since landing (you can board again after 5)
var busy := false  # gathering: stand still
var light_id := ""  # "", "torch", "iron_lantern", "spolokh_lantern"
var hp := 100.0
var hp_max := 100.0
## Combat (Tale and Saga): a block slows you, a dodge dashes you out of harm; gusts push, the mire slows.
var blocking := false
var dodge_s := 0.45
var push_v := Vector3.ZERO
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _slow_t := 0.0
var _slow_k := 1.0
var _swing_heavy := false

var _speed := 0.0
var _step := 0.0
var _time := 0.0
var _safe := Vector3.ZERO
var _anim: AnimationPlayer
var _hip_l: Node3D
var _hip_r: Node3D
var _arm: Node3D
var _torch: Node3D
var _fire: Node3D
var _light: OmniLight3D
var _work := 0.0  # > 0 while swinging a tool


signal stepped


func setup(p_db: ContentDB, p_map: WorldMap, p_cam: CameraRig) -> void:
	db = p_db
	map = p_map
	cam = p_cam
	var pl: Dictionary = db.balance["player"]
	stamina_max = float(pl["stamina"])
	stamina = stamina_max
	stamina_regen = float(pl["stamina_regen_per_s"])
	sprint_cost = float(pl["sprint_cost_per_s"])
	hp_max = float(pl["hp"])
	hp = hp_max


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.6
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	model = ModelLibrary.instance("player", "pomor")
	add_child(model)
	_anim = ModelLibrary.animation_player(model)
	_hip_l = model.get_node_or_null("Hip_L")
	_hip_r = model.get_node_or_null("Hip_R")
	_arm = model.get_node_or_null("Arm_R")
	_torch = model.find_child("Torch", true, false) as Node3D
	var tip := model.find_child("TorchTip", true, false) as Node3D
	_fire = Placeholders.fire(0.28, false)
	(_fire as Node3D).visible = false
	if tip != null:
		tip.add_child(_fire)
	else:
		model.add_child(_fire)
		_fire.position = Vector3(0.35, 1.4, -0.6)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffa04a")
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.position = Vector3(0.3, 1.9, -0.5)
	add_child(_light)
	_safe = global_position


## Put the player somewhere (landing, respawn) facing a direction.
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	_speed = 0.0
	walked = 0.0
	model.rotation.y = yaw
	_safe = global_position


func _physics_process(delta: float) -> void:
	_time += delta
	var fwd := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var turn := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.2:
		fwd -= joy.y
		turn -= joy.x
	if busy or (cam != null and cam.in_shot()):
		fwd = 0.0
		turn = 0.0
	fwd = clampf(fwd, -1.0, 1.0)
	if cam != null:
		cam.foot_yaw += turn * TURN * delta
	var sprint := Input.is_action_pressed("sprint") and fwd > 0.1 and stamina > 1.0
	if sprint:
		stamina = maxf(0.0, stamina - sprint_cost * delta)
	else:
		stamina = minf(stamina_max, stamina + stamina_regen * delta)
	var want := fwd * (RUN if sprint else WALK) * (0.6 if fwd < 0.0 else 1.0)
	if blocking:
		want *= 0.4
	if _slow_t > 0.0:
		_slow_t -= delta
		want *= _slow_k
	_speed = lerpf(_speed, want, 1.0 - exp(-delta * 8.0))
	var yaw := cam.foot_yaw if cam != null else 0.0
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw)) * signf(_speed)
	var hv := dir * absf(_speed)
	# the shore is the edge of the walkable world
	if absf(_speed) > 0.05:
		var ahead := global_position + hv.normalized() * 0.8
		if map.ground_at(ahead.x, ahead.z) < WATER_EDGE:
			var ax := global_position + Vector3(hv.x, 0, 0).normalized() * 0.8
			var az := global_position + Vector3(0, 0, hv.z).normalized() * 0.8
			if absf(hv.x) > 0.01 and map.ground_at(ax.x, ax.z) >= WATER_EDGE:
				hv = Vector3(hv.x, 0, 0)
			elif absf(hv.z) > 0.01 and map.ground_at(az.x, az.z) >= WATER_EDGE:
				hv = Vector3(0, 0, hv.z)
			else:
				hv = Vector3.ZERO
				_speed = 0.0
	if _dodge_t > 0.0:
		_dodge_t -= delta
		hv = _dodge_dir * 11.0
	hv += push_v
	push_v = push_v.lerp(Vector3.ZERO, 1.0 - exp(-delta * 3.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_action_just_pressed("jump") and not busy and stamina > 8.0:
			velocity.y = JUMP
			stamina -= 8.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	walked += moved
	if is_on_floor() and map.ground_at(global_position.x, global_position.z) > 0.0:
		_safe = global_position
	if global_position.y < -3.0:  # slipped off the world somehow: back to the last dry spot
		place(_safe, model.rotation.y)
	_animate(delta, hv, moved)


func _animate(delta: float, hv: Vector3, moved: float) -> void:
	if hv.length() > 0.1:
		var target := atan2(-hv.x, -hv.z)
		model.rotation.y = lerp_angle(model.rotation.y, target, 1.0 - exp(-delta * 10.0))
	var sp := absf(_speed)
	var prev := _step
	if sp > 0.05:
		_step += moved * 2.2
	else:
		_step = lerpf(_step, roundf(_step / PI) * PI, 1.0 - exp(-delta * 6.0))
	if floori(_step / PI) != floori(prev / PI) and sp > 0.5:
		stepped.emit()
	if _anim != null:
		var clip := "idle-loop"
		if _work > 0.0:
			clip = "chop"
		elif sp > 5.0:
			clip = "run-loop"
		elif sp > 0.3:
			clip = "walk-loop"
		elif light_id != "":
			clip = "carry_torch-loop"
		if _anim.has_animation(clip) and _anim.current_animation != clip:
			_anim.play(clip, 0.2)
		return
	var sw := sin(_step) * 0.55 * clampf(sp / 4.0, 0.0, 1.0)
	if _hip_l != null:
		_hip_l.rotation.x = sw
		_hip_r.rotation.x = -sw
	if _arm != null:
		# Godot: +x rotation swings the hanging arm forward
		if _work > 0.0:
			_work -= delta
			_arm.rotation.x = 0.4 + absf(sin(_time * 7.0)) * 1.9
		elif light_id != "":
			_arm.rotation.x = 0.55 + sin(_time * 2.0) * 0.03
		else:
			_arm.rotation.x = sw * 0.6
	model.position.y = absf(sin(_step)) * 0.05


func _process(_delta: float) -> void:
	var lit := light_id != ""
	if _torch != null:
		_torch.visible = lit
	_fire.visible = lit
	_light.light_energy = (3.4 + 0.6 * sin(_time * 13.0) + 0.4 * randf()) if lit else 0.0


## Swing the tool for a moment (gathering feedback).
func work(seconds: float = 0.6) -> void:
	_work = seconds


## "" | "block" | "dodge": sent to the host with "move" so its creatures' hits land right.
func stance() -> String:
	if _dodge_t > 0.0:
		return "dodge"
	return "block" if blocking else ""


## A quick dash (Ctrl) the way you face; costs stamina.
func dodge(cost: float) -> bool:
	if _dodge_t > 0.0 or stamina < cost or busy:
		return false
	stamina -= cost
	_dodge_t = dodge_s
	var yaw := model.rotation.y
	_dodge_dir = Vector3(-sin(yaw), 0, -cos(yaw))
	return true


## A strike: the arm swings (heavy = a slower, bigger one).
func swing(heavy: bool) -> void:
	_swing_heavy = heavy
	_work = 0.55 if heavy else 0.3


func push(v: Vector3) -> void:
	push_v += Vector3(v.x, 0.0, v.z)


func slow(k: float, seconds: float) -> void:
	_slow_k = k
	_slow_t = seconds


## The light in hand clears the fog (items.json → light.fog_radius); without one a little circle remains.
func fog_light() -> Vector4:
	var p := global_position
	if light_id == "":
		return Vector4(p.x, p.z, 4.0, 0.25)
	var r := float(db.items[light_id]["light"]["fog_radius"])
	return Vector4(p.x, p.z, r, 0.92)
