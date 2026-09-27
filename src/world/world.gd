extends Node3D
## The game world (docs/06_ROADMAP.md phase 1+): the sea, islands streamed around the viewer, beacons, the
## homestead, boats, the camera, the HUD and the sound. Everything that changes the world goes through
## Game.submit(); this node and its children only show WorldState and send commands.
##
## Command line (after "--"):
##   --smoke              run 60 frames, print "SMOKE OK", quit (tools/verify.sh, headless)
##   --screenshot=PATH    save a frame to PATH and quit (needs a renderer: xvfb-run + --rendering-driver opengl3)
##   --frames=N           frame for the screenshot (default 120)
##   --teleport=x,z,yaw   put the player's boat there (degrees)
##   --look=yaw,pitch     camera offset (degrees; boat: from the stern)
##   --locale=ru|en       interface language
##   --mode=quiet|tale|saga, --seed=N   a new world
##   --lit=b01,b02        light beacons at start (debug), --light-at=N lights the next beacon at frame N

const FOG_DIRECTOR := preload("res://src/world/fog_director.gd")

var db: ContentDB
var map: WorldMap
var state: WorldState
var director: FogDirector
var sea: Sea
var streamer: IslandStreamer
var home: HomeView
var cam: CameraRig
var hud: Hud
var audio: AudioDirector
var sun: DirectionalLight3D
var env: Environment
var boats: Dictionary = {}  # uid -> Boat
var beacons: Dictionary = {}  # beacon id -> BeaconView
var my_boat: Boat

var _args := {}
var _frame := 0
var _move_timer := 0.0
var _pid := ""


func _ready() -> void:
	_args = _parse_args()
	if _args.has("locale"):
		TranslationServer.set_locale(String(_args["locale"]))
	db = ContentDB.shared()
	if Game.state == null:
		if _args.has("debug-cheats") or _args.has("lit") or _args.has("light-at"):
			Game.debug_cheats = true
		Game.new_world(int(_args.get("seed", 4127)), String(_args.get("mode", "")))
	state = Game.state
	map = Game.map
	_pid = Net.local_player_id()
	Game.world_event.connect(_on_world_event)
	Game.command_failed.connect(_on_command_failed)
	_build_environment()
	director = FOG_DIRECTOR.new()
	director.db = db
	director.state = state
	director.environment = env
	director.sun = sun
	add_child(director)
	sea = Sea.new()
	sea.director = director
	add_child(sea)
	streamer = IslandStreamer.new()
	streamer.map = map
	streamer.state = state
	add_child(streamer)
	home = HomeView.new()
	home.setup(map)
	add_child(home)
	for bid in db.beacon_order:
		var bv := BeaconView.new()
		bv.setup(db, map, bid)
		add_child(bv)
		beacons[bid] = bv
		if state.lit.has(bid):
			bv.kindle(true)
	for uid: String in state.boats:
		_spawn_boat(uid)
	cam = CameraRig.new()
	cam.map = map
	add_child(cam)
	audio = AudioDirector.new()
	add_child(audio)
	hud = Hud.new()
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	layer.add_child(hud)
	hud.action_pressed.connect(_do_action)
	_debug_setup()
	_attach_player()
	streamer.build_around(_focus())
	cam.snap()


func _attach_player() -> void:
	var uid: String = state.players[_pid]["aboard"]
	my_boat = boats.get(uid)
	cam.boat = my_boat
	cam.mode = CameraRig.Mode.BOAT
	for b: Boat in boats.values():
		var crew := b.model.get_node_or_null("Crew") as Node3D
		if crew != null:
			crew.visible = b == my_boat
		if b == my_boat:
			b.weigh_anchor()
		else:
			b.drop_anchor()


func _spawn_boat(uid: String) -> Boat:
	var row: Dictionary = state.boats[uid]
	var b := Boat.new()
	b.setup(db, String(row["type"]), uid)
	b.name = "Boat_" + uid
	add_child(b)
	b.global_position = row["pos"]
	b.rotation.y = float(row["yaw"])
	boats[uid] = b
	return b


func _focus() -> Vector3:
	if my_boat != null:
		return my_boat.global_position
	return state.players[_pid]["pos"]


# ---------------------------------------------------------------- frame

func _physics_process(_delta: float) -> void:
	var wind := Weather.wind(db, state.world_seed, state.clock_min)
	for b: Boat in boats.values():
		b.wind = wind
		b.storm = sea.storm
	if my_boat != null:
		var fwd := Input.get_action_strength("move_forward") - 0.5 * Input.get_action_strength("move_back")
		var steer := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if joy.length() > 0.2:
			fwd += clampf(-joy.y, -0.5, 1.0)
			steer -= joy.x
		if cam.in_shot():
			fwd = 0.0
			steer = 0.0
		my_boat.throttle = clampf(fwd, -0.5, 1.0)
		my_boat.steer = clampf(steer, -1.0, 1.0)


func _process(delta: float) -> void:
	_frame += 1
	var focus := _focus()
	streamer.focus = focus
	var extra: Array[Vector4] = []
	if my_boat != null:
		extra.append(my_boat.fog_light(true))
	extra.append(home.hearth_light)
	director.extra_lights = extra
	_update_beacons()
	_update_audio(focus)
	_update_hud()
	_move_timer -= delta
	if _move_timer <= 0.0:
		_move_timer = 0.2
		_send_move()
	_debug_frame()


func _send_move() -> void:
	if my_boat == null:
		return
	var bp := my_boat.global_position
	Game.submit({"type": "move", "pos": [bp.x, bp.y, bp.z], "boat_pos": [bp.x, 0.0, bp.z], "boat_yaw": my_boat.rotation.y})


func _update_beacons() -> void:
	var next := Progress.next_beacon(db, state)
	for bid: String in beacons:
		(beacons[bid] as BeaconView).set_hint(bid == next)
	# the warm reflection of the nearest burning beacon on the water
	var best := Vector4.ZERO
	var best_d := INF
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	for bid: String in state.lit:
		var bv: BeaconView = beacons[bid]
		var d := p.distance_to(Vector2(bv.fire_pos.x, bv.fire_pos.z))
		if d < best_d:
			best_d = d
			best = Vector4(bv.fire_pos.x, bv.fire_pos.z, 0.0, bv.lit * 0.18)
	sea.glow = best


func _update_audio(focus: Vector3) -> void:
	audio.lit = state.lit.size()
	audio.fog = FogField.factor(db, state, Vector2(focus.x, focus.z), director.extra_lights)
	audio.on_foot = my_boat == null
	if my_boat != null:
		audio.boat_speed = my_boat.speed
		audio.boat_roll = my_boat.rotation.z + my_boat.rotation.x
	var near_fire := 0.0
	for bid: String in state.lit:
		var bv: BeaconView = beacons[bid]
		near_fire = maxf(near_fire, bv.lit * clampf(1.0 - focus.distance_to(bv.fire_pos) / 70.0, 0.0, 1.0))
	audio.fire_near = near_fire


# ---------------------------------------------------------------- HUD

func _update_hud() -> void:
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	var rid := db.region_at(p)
	hud.set_region("%s · %s" % [Loc.chapter(db, rid), Loc.region(db, rid)])
	if not director.palette.is_empty():
		hud.set_backdrop((director.palette["fog"] as Color).get_luminance() > 0.45)
	var goal := _goal()
	hud.set_goal(goal["text"])
	var fwd := -cam.global_transform.basis.z
	var cam_bearing := atan2(fwd.x, -fwd.z)
	if goal.has("target") and not cam.in_shot():
		var t: Vector3 = goal["target"]
		var me := _focus()
		var rel := Vector2(t.x - me.x, t.z - me.z)
		hud.set_compass(cam_bearing, atan2(rel.x, -rel.y), "%s: %s" % [goal["label"], Loc.meters(rel.length())])
	else:
		hud.set_compass(cam_bearing, NAN, "")
	hud.set_action(_action_label())
	hud.set_bars(100.0, 100.0, 0.0, 100.0, 100.0)
	if my_boat != null:
		var wind := Weather.wind(db, state.world_seed, state.clock_min)
		var side := Weather.wind_side(my_boat.heading(), wind)
		var full := Weather.sail_factor(db, my_boat.heading(), wind) > 0.95
		var cargo: Inventory = state.boats[my_boat.uid]["cargo"]
		var used := 0
		for s: Dictionary in cargo.slots:
			if not s.is_empty():
				used += 1
		var h := my_boat.heading()
		hud.set_boat({
			"name": Loc.name_of(db.boats[my_boat.type]["name"]),
			"wind_text": "%s · %s" % [tr("wind." + side), tr("sail.full") if full else tr("sail.slow")],
			"speed": "%.1f %s" % [absf(my_boat.speed), tr("unit.mps")],
			"hold": "%s %d/%d" % [tr("hud.hold"), used, cargo.size],
			"heading": atan2(h.x, -h.y), "wind_angle": atan2(wind.x, -wind.y),
		})
		hud.set_hint(tr("hint.boat"))
	else:
		hud.set_boat({})


## What the player should do now and where the compass points: {"text", "target": Vector3, "label"}.
func _goal() -> Dictionary:
	var next := Progress.next_beacon(db, state)
	if next == "":
		return {"text": tr("goal.free")}
	var bv: BeaconView = beacons[next]
	var label := tr("target.beacon") % Loc.beacon(db, next)
	return {"text": tr("goal.sail"), "target": bv.fire_pos, "label": label}


func _action_label() -> String:
	return ""


func _do_action() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_do_action()


# ---------------------------------------------------------------- world events

func _on_world_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"beacon_lit":
			var bid: String = e["beacon"]
			director.mark_lit(bid)
			(beacons[bid] as BeaconView).kindle()
			audio.sfx("swell")
		"day_changed":
			streamer.refresh_all()


func _on_command_failed(_cmd: Dictionary, error: String) -> void:
	if error in ["bad_pos"]:
		return
	hud.toast(tr("cmd." + error))
	audio.sfx("deny")


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://src/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = false  # fog lives in the materials (fog_clear.gdshaderinc)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	sun.light_specular = 0.3  # a low white-night sun: keep its glint on the water gentle
	add_child(sun)


# ---------------------------------------------------------------- debug and automation

func _debug_setup() -> void:
	if _args.has("lit"):
		for bid: String in String(_args["lit"]).split(","):
			_debug_light(bid, true)
	if _args.has("teleport"):
		var v := String(_args["teleport"]).split(",")
		var b := boats.get(state.players[_pid]["aboard"]) as Boat
		if b != null and v.size() >= 2:
			b.global_position = Vector3(float(v[0]), 0.0, float(v[1]))
			if v.size() >= 3:
				b.rotation.y = deg_to_rad(float(v[2]))
	if _args.has("look"):
		var v := String(_args["look"]).split(",")
		cam.look_yaw = deg_to_rad(float(v[0]))
		cam.foot_yaw = deg_to_rad(float(v[0]))
		if v.size() > 1:
			cam.pitch = float(v[1]) / 100.0
		cam.idle = -1000.0


## Debug: pass the trial, stand at the beacon with its fuel, light it (the same commands real play uses).
func _debug_light(bid: String, instant: bool) -> void:
	var p := db.beacon_pos(bid)
	var back: Vector3 = state.players[_pid]["pos"]
	var fuel := ContentDB.bag(db.beacons[bid]["fuel"])
	Game.submit({"type": "debug", "trial": bid, "give": fuel, "pos": [p.x, 0.0, p.y]})
	var res := Game.submit({"type": "light_beacon", "beacon": bid})
	Game.submit({"type": "debug", "pos": [back.x, back.y, back.z]})
	if res.get("ok", false) and instant:
		(beacons[bid] as BeaconView).kindle(true)
		director.mark_lit(bid, -100.0)


func _debug_frame() -> void:
	if _args.has("light-at") and _frame == int(_args["light-at"]):
		var next := Progress.next_beacon(db, state)
		if next != "":
			_debug_light(next, false)
	if _args.has("smoke") and _frame >= 60:
		print("SMOKE OK: frames=%d islands=%d boats=%d lit=%s" % [_frame, streamer.views.size(), boats.size(), str(state.lit.keys())])
		get_tree().quit(0)
	if _args.has("screenshot") and _frame >= int(_args.get("frames", 120)):
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(String(_args["screenshot"]))
		print("screenshot %s: %s" % [_args["screenshot"], error_string(err)])
		get_tree().quit(0)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out
