extends Node3D
## The game world (docs/06_ROADMAP.md phase 1+): the sea, islands streamed around the viewer, beacons, the
## homestead, boats, the player on foot, the camera, the HUD and the sound. Everything that changes the
## world goes through Game.submit(); this node and its children only show WorldState and send commands.
##
## Command line (after "--"):
##   --smoke              run 60 frames, print "SMOKE OK", quit (tools/verify.sh, headless)
##   --screenshot=PATH    save a frame to PATH and quit (needs a renderer: xvfb-run + --rendering-driver opengl3)
##   --frames=N           frame for the screenshot (default 120)
##   --teleport=x,z,yaw   put the player's boat there (degrees)
##   --ashore             land at the nearest shore right away
##   --walk=x,z,yaw       put the player on foot there
##   --look=yaw,pitch     camera offset (degrees; boat: from the stern) and pitch (0..90)
##   --give=item:n,...    items in the bag (debug), --torch lights a torch
##   --locale=ru|en       interface language
##   --mode=quiet|tale|saga, --seed=N   a new world
##   --lit=b01,b02        light beacons at start (debug), --light-at=N lights the next beacon at frame N

const FOG_DIRECTOR := preload("res://src/world/fog_director.gd")
const GATHER_REACH := 3.2
const TOOL_VERB := {"axe": "act.chop", "knife": "act.cut", "pick": "act.mine", "shovel": "act.dig", "hand": "act.take", "rod": "act.fish"}

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
var player: Player
var my_boat: Boat  # the boat the local player is aboard (null on foot)
var last_boat: Boat  # the boat the player came ashore from

var _args := {}
var _frame := 0
var _move_timer := 0.0
var _scan_timer := 0.0
var _pid := ""
var _landing: Dictionary = {}
var _near_node: Dictionary = {}
var _choice := 0
var _channel: Dictionary = {}  # gathering in progress: {"node", "item", "per", "t", "done", "want"}
var _board_dist := 6.0


func _ready() -> void:
	_args = _parse_args()
	if _args.has("locale"):
		TranslationServer.set_locale(String(_args["locale"]))
	db = ContentDB.shared()
	if Game.state == null:
		for k in ["debug-cheats", "lit", "light-at", "give", "torch", "walk"]:
			if _args.has(k):
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
	player = Player.new()
	player.name = "Player"
	player.setup(db, map, cam)
	add_child(player)
	player.stepped.connect(func() -> void: audio.sfx("step"))
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


## Aboard a boat or on foot, from WorldState.
func _attach_player() -> void:
	var uid: String = state.players[_pid]["aboard"]
	my_boat = boats.get(uid)
	if my_boat != null:
		last_boat = my_boat
	var foot := my_boat == null
	player.visible = foot
	player.set_physics_process(foot)
	player.collision_layer = 4 if foot else 0
	if foot and player.global_position.length() < 0.01:
		var p: Vector3 = state.players[_pid]["pos"]
		player.place(Vector3(p.x, map.ground_at(p.x, p.z), p.z), 0.0)
	cam.boat = my_boat if my_boat != null else last_boat
	cam.player = player
	cam.mode = CameraRig.Mode.FOOT if foot else CameraRig.Mode.BOAT
	for b: Boat in boats.values():
		var crew := b.model.get_node_or_null("Crew") as Node3D
		if crew != null:
			crew.visible = b == my_boat
		if b == my_boat:
			b.weigh_anchor()
		elif not b.anchored:
			b.drop_anchor()
	_channel = {}
	player.busy = false


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
	return player.global_position


func on_foot() -> bool:
	return my_boat == null


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
	player.light_id = String((state.players[_pid].get("light", {}) as Dictionary).get("id", ""))
	var extra: Array[Vector4] = []
	if on_foot():
		extra.append(player.fog_light())
		if last_boat != null:
			extra.append(last_boat.fog_light(false))
		cam.occluders = _occluders()
	elif my_boat != null:
		extra.append(my_boat.fog_light(true))
	extra.append(home.hearth_light)
	director.extra_lights = extra
	director.boost_target = _fog_boost()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.15
		_scan()
	_update_channel(delta)
	_update_beacons()
	_update_audio(focus)
	_update_hud()
	_move_timer -= delta
	if _move_timer <= 0.0:
		_move_timer = 0.2
		_send_move()
	_debug_frame()


func _send_move() -> void:
	if my_boat != null:
		var bp := my_boat.global_position
		Game.submit({"type": "move", "pos": [bp.x, bp.y, bp.z], "boat_pos": [bp.x, 0.0, bp.z], "boat_yaw": my_boat.rotation.y})
	else:
		var p := player.global_position
		Game.submit({"type": "move", "pos": [p.x, p.y, p.z]})


## On foot on an island whose beacon is still dark the Mga is 2.3 times thicker; at home a little thicker.
func _fog_boost() -> float:
	if not on_foot():
		return 1.0
	var isl := map.island_at(player.global_position.x, player.global_position.z)
	if isl == null:
		return 1.0
	if map.kind_of[isl.id] == "beacon" and not state.lit.has(isl.id):
		return 2.3
	return 1.2 if isl.id == WorldMap.HOME else 1.0


func _occluders() -> Array:
	var out: Array = []
	var p := Vector2(player.global_position.x, player.global_position.z)
	for s: Dictionary in streamer.solids_near(p, 9.0):
		out.append({"pos": s["pos"], "r": maxf(0.8, float(s["r"]) * 3.2)})
	return out


## What is within reach: a landing for the boat, a resource node on foot.
func _scan() -> void:
	_landing = {}
	_near_node = {}
	if my_boat != null:
		var bp := my_boat.global_position
		_landing = map.find_landing(Vector2(bp.x, bp.z), _blocked)
		return
	var p := player.global_position
	var isl := map.island_at(p.x, p.z)
	if isl == null:
		return
	var best_d := INF
	for n: Dictionary in map.nodes(isl.id):
		if (n["items"] as Array).is_empty() or int(state.depleted.get(n["id"], 0)) > state.day:
			continue
		var np: Vector3 = n["pos"]
		var d := Vector2(p.x - np.x, p.z - np.z).length() - float(n["solid"])
		if d < GATHER_REACH and d < best_d:
			best_d = d
			_near_node = n


func _blocked(p: Vector2) -> bool:
	for s: Dictionary in streamer.solids_near(p, 3.0):
		if p.distance_to(s["pos"]) < float(s["r"]) + 0.5:
			return true
	return false


# ---------------------------------------------------------------- actions

## The action for E right now: {"label", "run": Callable} or {}.
func _action() -> Dictionary:
	if cam.in_shot():
		return {}
	if my_boat != null:
		if not _landing.is_empty():
			return {"label": tr("act.land"), "run": _disembark}
		return {}
	if not _channel.is_empty():
		var c := _channel
		return {"label": tr("act.working") % [Loc.item(db, c["item"]), int(c["done"]), int(c["want"])], "run": _finish_channel}
	var inv := state.inv(_pid)
	if not _near_node.is_empty():
		var items: Array = _near_node["items"]
		var item: String = items[_choice % items.size()]
		var tool := String(db.items[item]["gather"]["tool"])
		var label := ""
		if Gathering.tool_ok(db, inv, item):
			label = tr(TOOL_VERB.get(tool, "act.take")) % Loc.item(db, item)
		else:
			label = tr("act.need_tool") % tr("tool." + tool)
		if items.size() > 1:
			label += "   ·   " + tr("act.other")
		return {"label": label, "run": _start_channel.bind(_near_node, item)}
	var lit_now := not (state.players[_pid].get("light", {}) as Dictionary).is_empty()
	if not lit_now and inv.count("torch") > 0:
		return {"label": tr("act.light_torch"), "run": func() -> void: Game.submit({"type": "light", "item": "torch"})}
	if not lit_now and inv.count("branch") >= 1 and inv.count("resin") >= 1:
		return {"label": tr("act.make_torch"), "run": _make_torch}
	if last_boat != null and player.walked > 5.0:
		var bp := last_boat.global_position
		var d := Vector2(bp.x - player.global_position.x, bp.z - player.global_position.z).length()
		if d < minf(_board_dist, WorldCommands.BOARD_REACH_M):
			return {"label": tr("act.board"), "run": _board}
	return {}


func _do_action() -> void:
	var a := _action()
	if not a.is_empty():
		(a["run"] as Callable).call()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_do_action()
	elif event.is_action_pressed("cycle"):
		_choice += 1


func _disembark() -> void:
	var lp: Vector3 = _landing["pos"]
	_send_move()  # the host checks distances against the last position it heard
	var res := Game.submit({"type": "disembark", "pos": [lp.x, lp.y, lp.z]})
	if not res.get("ok", false):
		return
	var bp := my_boat.global_position
	_board_dist = maxf(6.0, float(_landing["d"]) + 3.0)
	var yaw := atan2(-(lp.x - bp.x), -(lp.z - bp.z))
	my_boat.drop_anchor()
	player.place(lp, yaw)
	cam.foot_yaw = yaw
	_attach_player()
	audio.sfx("land")


func _board() -> void:
	_send_move()
	var res := Game.submit({"type": "board", "boat": last_boat.uid})
	if res.get("ok", false):
		_attach_player()
		cam.look_yaw = 0.0
		audio.sfx("board")


func _make_torch() -> void:
	var res := Game.submit({"type": "craft", "recipe": "torch"})
	if res.get("ok", false):
		Game.submit({"type": "light", "item": "torch"})
		audio.sfx("torch")


## Gathering works a node unit by unit (Gathering.unit_seconds); the haul goes to the host as one command.
func _start_channel(n: Dictionary, item: String) -> void:
	var inv := state.inv(_pid)
	if not Gathering.tool_ok(db, inv, item):
		hud.toast(tr("act.need_tool") % tr("tool." + String(db.items[item]["gather"]["tool"])))
		audio.sfx("deny")
		return
	_channel = {"node": n["id"], "item": item, "per": Gathering.unit_seconds(db, inv, item), "t": 0.0, "done": 0, "want": WorldCommands.GATHER_MAX}
	player.busy = true


func _update_channel(delta: float) -> void:
	if _channel.is_empty():
		return
	if not on_foot():
		_channel = {}
		player.busy = false
		return
	var c := _channel
	c["t"] = float(c["t"]) + delta
	player.work(0.2)
	if float(c["t"]) >= float(c["per"]):
		c["t"] = 0.0
		c["done"] = int(c["done"]) + 1
		audio.sfx("chop" if String(db.items[c["item"]]["gather"]["tool"]) in ["axe", "pick", "shovel"] else "pickup", int(c["done"]))
		if int(c["done"]) >= int(c["want"]):
			_finish_channel()


func _finish_channel() -> void:
	var c := _channel
	_channel = {}
	player.busy = false
	if c.is_empty() or int(c["done"]) <= 0:
		return
	_send_move()
	Game.submit({"type": "gather", "node": c["node"], "item": c["item"], "qty": int(c["done"])})


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
	audio.fog = FogField.factor(db, state, Vector2(focus.x, focus.z), director.extra_lights) * director.boost
	audio.on_foot = on_foot()
	if my_boat != null:
		audio.boat_speed = my_boat.speed
		audio.boat_roll = my_boat.rotation.z + my_boat.rotation.x
	var near_fire := 0.35 if on_foot() and player.light_id != "" else 0.0
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
	hud.set_action(String(_action().get("label", "")))
	hud.set_bars(player.hp, player.hp_max, 0.0, player.stamina, player.stamina_max)
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
		hud.set_hint(tr("hint.foot"))


## What the player should do now and where the compass points: {"text", "target": Vector3, "label"}.
func _goal() -> Dictionary:
	var next := Progress.next_beacon(db, state)
	if next == "":
		return {"text": tr("goal.free")}
	var bv: BeaconView = beacons[next]
	var beacon_goal := {"target": bv.fire_pos, "label": tr("target.beacon") % Loc.beacon(db, next)}
	if my_boat != null:
		var near_isl := map.nearest_island(Vector2(my_boat.global_position.x, my_boat.global_position.z), 40.0)
		var text := tr("goal.land") if not _landing.is_empty() and near_isl != null and near_isl.id == next else tr("goal.sail")
		beacon_goal["text"] = text
		return beacon_goal
	var isl := map.island_at(player.global_position.x, player.global_position.z)
	var boat_goal := {"target": last_boat.global_position if last_boat != null else Vector3.ZERO, "label": tr("target.boat")}
	if isl != null and isl.id == next:
		beacon_goal["text"] = tr("goal.climb") if player.light_id != "" else tr("goal.need_fire")
		return beacon_goal
	if isl != null and isl.id == WorldMap.HOME:
		boat_goal["text"] = tr("goal.home")
		return boat_goal
	boat_goal["text"] = tr("goal.back_to_boat")
	return boat_goal


# ---------------------------------------------------------------- world events

func _on_world_event(e: Dictionary) -> void:
	var mine := String(e.get("player", "")) == _pid
	match String(e.get("type", "")):
		"beacon_lit":
			var bid: String = e["beacon"]
			director.mark_lit(bid)
			(beacons[bid] as BeaconView).kindle()
			audio.sfx("swell")
		"gathered":
			streamer.refresh_node(String(e["node"]))
			if mine:
				hud.toast(Loc.item(db, e["item"]), "+%d" % int(e["n"]))
		"crafted":
			if mine:
				var r: Dictionary = db.recipes[e["recipe"]]
				for k: String in r["output"]:
					hud.toast(Loc.item(db, k), "+%d" % (int(r["output"][k]) * int(e["times"])))
		"light_changed":
			if mine and e.get("burnt_out", false):
				hud.toast(tr("toast.light_out"))
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
	if _args.has("give"):
		var give := {}
		for pair: String in String(_args["give"]).split(","):
			var kv := pair.split(":")
			give[kv[0]] = int(kv[1]) if kv.size() > 1 else 1
		Game.submit({"type": "debug", "give": give})
	if _args.has("teleport"):
		var v := String(_args["teleport"]).split(",")
		var b := boats.get(state.players[_pid]["aboard"]) as Boat
		if b != null and v.size() >= 2:
			b.global_position = Vector3(float(v[0]), 0.0, float(v[1]))
			if v.size() >= 3:
				b.rotation.y = deg_to_rad(float(v[2]))
			var bp := b.global_position
			Game.submit({"type": "move", "pos": [bp.x, 0.0, bp.z], "boat_pos": [bp.x, 0.0, bp.z], "boat_yaw": b.rotation.y})
	if _args.has("torch"):
		Game.submit({"type": "debug", "give": {"torch": 1}})
		Game.submit({"type": "light", "item": "torch"})
	if _args.has("look"):
		var v := String(_args["look"]).split(",")
		cam.look_yaw = deg_to_rad(float(v[0]))
		if v.size() > 1:
			cam.pitch = float(v[1]) / 100.0
		cam.idle = -1000.0


## After the first frames: landing and walking shortcuts for screenshots.
func _debug_place() -> void:
	if (_args.has("ashore") or _args.has("walk")) and my_boat != null:
		var bp := my_boat.global_position
		_landing = map.find_landing(Vector2(bp.x, bp.z), _blocked)
		if not _landing.is_empty():
			_disembark()
	if _args.has("walk") and on_foot():
		var v := String(_args["walk"]).split(",")
		var x := float(v[0])
		var z := float(v[1])
		var yaw := deg_to_rad(float(v[2])) if v.size() > 2 else 0.0
		Game.submit({"type": "debug", "pos": [x, map.ground_at(x, z), z]})
		player.place(Vector3(x, map.ground_at(x, z) + 0.2, z), yaw)
		cam.foot_yaw = yaw + (deg_to_rad(float(String(_args["look"]).split(",")[0])) if _args.has("look") else 0.0)
		streamer.build_around(player.global_position)
		cam.snap()


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
	if _frame == 2:
		_debug_place()
	if _args.has("light-at") and _frame == int(_args["light-at"]):
		var next := Progress.next_beacon(db, state)
		if next != "":
			_debug_light(next, false)
	if _args.has("smoke") and _frame >= 60:
		print("SMOKE OK: frames=%d islands=%d boats=%d on_foot=%s lit=%s" % [_frame, streamer.views.size(), boats.size(), on_foot(), str(state.lit.keys())])
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
