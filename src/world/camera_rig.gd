class_name CameraRig
extends Camera3D
## The camera from the sketch (reference/sketch/src/main.js, desiredCam/viewTarget):
## - boat: 15 m behind, height 3 + pitch·12, mouse drag looks around, swings back behind the stern after
##   2.5 s idle, climbs over land and tree crowns (+7.5 m) instead of diving into them;
## - foot: 7 m behind the player, A/D turn it (1.9 rad/s), pulls in before tree crowns, looks over the boat;
## - shots: play_shot() flies to a scripted view (beacon lighting) and back to the player.

enum Mode { BOAT, FOOT }

const LOOK_X := 0.006
const LOOK_Y := 0.004

var map: WorldMap
var boat: Boat
var player: Node3D  # Player (phase 2)
var mode := Mode.BOAT
var look_yaw := 0.0  # boat mode: offset from the stern
var foot_yaw := 0.0  # foot mode: the camera's own heading
var pitch := 0.32
var idle := 0.0
var dragging := false
## Solid circles near the player (trees): {"pos": Vector2, "r": float}. The camera pulls in before them.
var occluders: Array = []

var _target := Vector3.ZERO
var _cine: Dictionary = {}


func _ready() -> void:
	fov = 58.0
	near = 0.3
	far = 2600.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		look(mm.relative.x * LOOK_X, mm.relative.y * LOOK_Y)


## Turn the view: dx radians of yaw, dy of pitch (mouse, right stick).
func look(dx: float, dy: float) -> void:
	if mode == Mode.FOOT:
		foot_yaw -= dx
	else:
		look_yaw -= dx
	pitch = clampf(pitch + dy, 0.05, 0.9)
	idle = 0.0


func _process(delta: float) -> void:
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.2:
		look(stick.x * 2.2 * delta, stick.y * 1.4 * delta)
	if not _cine.is_empty():
		_run_cine(delta)
		return
	if mode == Mode.BOAT and not dragging:
		idle += delta
		if idle > 2.5:
			look_yaw = lerpf(look_yaw, 0.0, 1.0 - exp(-delta * 0.8))
	var want := desired()
	global_position = global_position.lerp(want, 1.0 - exp(-delta * (6.0 if mode == Mode.FOOT else 4.0)))
	_target = _target.lerp(view_target(), 1.0 - exp(-delta * 6.0))
	if not global_position.is_equal_approx(_target):
		look_at(_target)


## Jump straight to the resting position (after a teleport or on load).
func snap() -> void:
	global_position = desired()
	_target = view_target()
	look_at(_target)


func view_target() -> Vector3:
	if mode == Mode.FOOT and player != null:
		return player.global_position + Vector3(0, 1.6, 0)
	if boat != null:
		return boat.global_position + Vector3(0, 2.2, 0)
	return Vector3.ZERO


func desired() -> Vector3:
	if mode == Mode.FOOT and player != null:
		return _desired_foot()
	if boat == null:
		return global_position
	var yaw := boat.yaw() + look_yaw
	var dir := Vector2(sin(yaw), cos(yaw))
	var bp := boat.global_position
	var base := maxf(bp.y + 2.0, 3.0 + pitch * 12.0)
	var dist := 15.0
	var hgt := base
	var d := 3.0
	while d <= 15.0:
		var hh := _ground(bp.x + dir.x * d, bp.z + dir.y * d)
		if hh >= -0.3:
			var need := hh + 7.5  # trees stand on land: clear their crowns
			if need <= base + 7.0:
				hgt = maxf(hgt, need)
			else:
				dist = maxf(4.5, d - 2.0)
				break
		d += 1.5
	return Vector3(bp.x + dir.x * dist, hgt, bp.z + dir.y * dist)


func _desired_foot() -> Vector3:
	var pp := player.global_position
	var dir := Vector2(sin(foot_yaw), cos(foot_yaw))
	var base := pp.y + 1.7 + pitch * 7.0
	var dist := 7.0
	var hgt := base
	var d := 1.5
	while d <= 7.0:
		var hh := _ground(pp.x + dir.x * d, pp.z + dir.y * d)
		if hh + 1.2 > hgt:
			if hh + 1.2 <= base + 3.0:
				hgt = hh + 1.2
			else:
				dist = maxf(2.0, d - 0.8)
				break
		d += 0.75
	# pull in before a tree crown standing between the player and the camera
	for o: Dictionary in occluders:
		var op: Vector2 = o["pos"]
		var r: float = o["r"]
		var rel := op - Vector2(pp.x, pp.z)
		var along := rel.dot(dir)
		if along <= 0.5 or along > dist + r:
			continue
		var side := absf(rel.x * dir.y - rel.y * dir.x)
		if side < r:
			dist = maxf(1.8, minf(dist, along - sqrt(r * r - side * side) - 0.3))
	if dist < 4.0:
		hgt = maxf(hgt, pp.y + 2.4 + (4.0 - dist) * 0.35)
	# the moored boat: look over its sail rather than through it
	if boat != null:
		var bp := boat.global_position
		var rel := Vector2(bp.x - pp.x, bp.z - pp.z)
		var b_along := rel.dot(dir)
		var b_side := absf(rel.x * dir.y - rel.y * dir.x)
		var cam := Vector2(pp.x, pp.z) + dir * dist
		if (b_along > 0.0 and b_along < dist + 3.0 and b_side < 3.2) or cam.distance_to(Vector2(bp.x, bp.z)) < 3.5:
			hgt = maxf(hgt, bp.y + 6.2)
	return Vector3(pp.x + dir.x * dist, hgt, pp.z + dir.y * dist)


func _ground(x: float, z: float) -> float:
	return map.ground_at(x, z) if map != null else -5.0


# ---------------------------------------------------------------- cinematic shots

## A shot at `target` from `target + offset`: flies there over `fly_s`, holds, returns to the resting
## camera over the last 1.6 s. Calls `on_done` at the end.
func play_shot(target: Vector3, offset: Vector3, duration: float, on_done: Callable = Callable(), fly_s: float = 2.2) -> void:
	_cine = {"t": 0.0, "dur": duration, "from": global_position, "target": target, "offset": offset, "done": on_done, "fly": fly_s}


func in_shot() -> bool:
	return not _cine.is_empty()


func _run_cine(delta: float) -> void:
	var c := _cine
	c["t"] = float(c["t"]) + delta
	var t: float = c["t"]
	var dur: float = c["dur"]
	var k := smoothstep(0.0, 1.0, minf(1.0, t / float(c["fly"])))
	var back := smoothstep(dur - 1.6, dur, t)
	var shot: Vector3 = (c["target"] as Vector3) + (c["offset"] as Vector3)
	var from: Vector3 = c["from"]
	var rest := desired()
	global_position = from.lerp(shot, k * (1.0 - back)).lerp(rest, back)
	_target = (c["target"] as Vector3).lerp(view_target(), back)
	look_at(_target)
	if t >= dur:
		var done: Callable = c["done"]
		_cine = {}
		if done.is_valid():
			done.call()
