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
##   --give=item:n,...    items in the bag (debug), --torch lights a torch, --eat=a,b eats dishes
##   --place=piece,...    set up pieces in front of the player, --craft[=recipe] opens the crafting window
##   --house              build a small cabin in front of the player (snapped "place" commands)
##   --build=piece        enter the build mode with that piece, its ghost 5 m ahead
##   --locale=ru|en       interface language
##   --mode=quiet|tale|saga, --seed=N   a new world
##   --lit=b01,b02        light beacons at start (debug), --light-at=N lights the next beacon at frame N

const FOG_DIRECTOR := preload("res://src/world/fog_director.gd")
const GATHER_REACH := 3.2
## The beacon moment (docs/01_GDD.md §5.4): the flame catches, the banner comes, the camera returns.
const MOMENT_S := 8.0
const KINDLE_AT := 1.0
const BANNER_AT := 2.0
const TRAIL_STEP_M := 25.0
const LIGHT_BUDGET := 8  # docs/04_TECH_SPEC.md §11: no more OmniLight3D than this near the camera
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
var pieces: PiecesView
var craft: CraftWindow
var storage: StorageWindow
var build: BuildMode
var chart: MapWindow
var creatures: CreatureDirector
var sites: SitesView
var weather: WeatherView
var combat: Combat
var journal: JournalWindow
var pause_menu: PauseMenu
var menu: MainMenu
var evening: EveningWindow
var settings_win: SettingsWindow
var others: Dictionary = {}  # co-op: player id -> Node3D (the other players, drawn from WorldState)
var trials: Dictionary = {}  # beacon id -> Trial, built while its island is near
var trail := PackedVector2Array()  # where the player has been (the chart's dotted path)
var mark := Vector2.INF  # the chart's mark: the compass follows it until you get there
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
var _near_station := ""  # uid of the nearest station within reach
var _fishing: Dictionary = {}  # {"spot", "t", "next", "bite", "caught", "want"}
var _bobber: Node3D
var _hot := 0  # chosen hotbar place
var _near_use := ""  # a bed, a sauna stove or a chest within reach
var _fade: ColorRect
var _moment := ""  # the beacon in its lighting moment
var _budget_t := 0.0
var _bench: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	if _args.has("locale"):
		TranslationServer.set_locale(String(_args["locale"]))
	db = ContentDB.shared()
	if not _args.is_empty() and not _args.has("menu"):
		Game.show_menu = false  # debug and automation runs start straight in the world
	if Game.state == null:
		for k in ["debug-cheats", "lit", "light-at", "give", "torch", "walk", "place", "eat", "craft", "house", "build", "at-beacon"]:
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
	director.volumetric = FogDirector.wants_volumetric()
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
	pieces = PiecesView.new()
	pieces.setup(db, state)
	add_child(pieces)
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
	craft = CraftWindow.new()
	layer.add_child(craft)
	craft.closed.connect(func() -> void: player.busy = not _channel.is_empty())
	craft.place_requested.connect(_place_station)
	storage = StorageWindow.new()
	layer.add_child(storage)
	storage.closed.connect(func() -> void: player.busy = false)
	build = BuildMode.new()
	add_child(build)
	build.setup(db, state, map, player, cam, _pid, layer)
	weather = WeatherView.new()
	add_child(weather)
	weather.setup(self)
	creatures = CreatureDirector.new()
	add_child(creatures)
	creatures.setup(self)
	sites = SitesView.new()
	add_child(sites)
	sites.setup(self)
	combat = Combat.new()
	add_child(combat)
	combat.setup(self)
	journal = JournalWindow.new()
	journal.db = db
	journal.state = state
	layer.add_child(journal)
	journal.closed.connect(func() -> void: player.busy = false)
	pause_menu = PauseMenu.new()
	layer.add_child(pause_menu)
	pause_menu.closed.connect(func() -> void: player.busy = false)
	pause_menu.journal_requested.connect(_open_journal)
	pause_menu.settings_requested.connect(func() -> void:
		settings_win.open()
		player.busy = true)
	pause_menu.evening_requested.connect(_open_evening)
	evening = EveningWindow.new()
	layer.add_child(evening)
	evening.closed.connect(func() -> void: player.busy = false)
	settings_win = SettingsWindow.new()
	layer.add_child(settings_win)
	settings_win.closed.connect(func() -> void: player.busy = false)
	Game.quit_requested.connect(_on_quit_requested)
	Game.achieved.connect(func(id: String) -> void:
		hud.toast(tr("toast.achievement") % Loc.name_of(db.achievements[id]["name"]), "★"))
	Game.left_world.connect(func() -> void:
		Game.show_menu = true  # the host is gone: back to the menu
		get_tree().reload_current_scene())
	Game.saved.connect(func(ok: bool) -> void:
		if not evening.visible:
			hud.toast(tr("toast.saved") if ok else tr("toast.save_failed")))
	Game.settings.apply()  # the audio buses exist now
	chart = MapWindow.new()
	layer.add_child(chart)
	chart.closed.connect(func() -> void: player.busy = false)
	chart.mark_set.connect(func(at: Vector2) -> void: mark = at)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.05, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_bobber = _make_bobber()
	add_child(_bobber)
	_debug_setup()
	_attach_player()
	if Game.show_menu:
		menu = MainMenu.new()
		layer.add_child(menu)
		player.busy = true
	if Game.restored_from > 0:
		hud.toast(tr("toast.restored") % Game.restored_from, "!")  # the save was broken: a backup came back
		Game.restored_from = 0
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
	b.world_state = state  # the sea wall: closed regions turn the boat home
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
	extra.append_array(pieces.fog_lights(Vector2(focus.x, focus.z), 2))
	for t: Trial in trials.values():
		extra.append_array(t.fog_lights())
	director.extra_lights = extra
	director.boost_target = _fog_boost()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.15
		_scan()
	_update_channel(delta)
	_update_fishing(delta)
	_update_vitals()
	_update_beacons()
	_update_trials(delta)
	_update_others(delta)
	_budget_t -= delta
	if _budget_t <= 0.0:
		_budget_t = 0.5
		light_budget()
	_update_trail(focus)
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
		Game.submit({"type": "move", "pos": [p.x, p.y, p.z], "stance": player.stance()})


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
	_near_use = ""
	for uid in Crafting.stations_near(state, p, WorldCommands.USE_REACH_M - 0.5):
		var info: Dictionary = db.pieces[state.pieces[uid]["id"]]
		if info.get("spawn", false) or info.has("buff") or info.has("storage"):
			_near_use = uid
			break
	_near_station = ""
	for uid in Crafting.stations_near(state, p, Crafting.REACH_M - 1.0):
		if db.pieces[state.pieces[uid]["id"]].get("station", false):
			_near_station = uid
			break
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
		if my_boat.capsized:
			return {"label": tr("act.right_boat"), "run": func() -> void: Game.submit({"type": "right_boat", "boat": my_boat.uid})}
		if not _fishing.is_empty():
			if float(_fishing["bite"]) > 0.0:
				return {"label": tr("act.hook"), "run": _hook}
			return {"label": tr("act.reel") % [int(_fishing["caught"]), int(_fishing["want"])], "run": _stop_fishing}
		var whale := creatures.action(my_boat.global_position, true)
		if not whale.is_empty():
			return whale
		if not _landing.is_empty():
			return {"label": tr("act.land"), "run": _disembark}
		if _can_fish():
			return {"label": tr("act.fish") % Loc.item(db, "raw_fish"), "run": _start_fishing}
		return {}
	if not _channel.is_empty():
		var c := _channel
		return {"label": tr("act.working") % [Loc.item(db, c["item"]), int(c["done"]), int(c["want"])], "run": _finish_channel}
	if not _fishing.is_empty():
		if float(_fishing["bite"]) > 0.0:
			return {"label": tr("act.hook"), "run": _hook}
		return {"label": tr("act.reel") % [int(_fishing["caught"]), int(_fishing["want"])], "run": _stop_fishing}
	var beacon_act := _beacon_action()
	if not beacon_act.is_empty():
		return beacon_act
	var life := sites.action(player.global_position)
	if life.is_empty():
		life = creatures.action(player.global_position, false)
	if not life.is_empty():
		return life
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
	if _near_use != "":
		var use: Dictionary = state.pieces[_near_use]
		var info: Dictionary = db.pieces[use["id"]]
		if info.get("spawn", false):
			var cf := int(Comfort.at(db, state, use["pos"])["total"])
			return {"label": tr("act.sleep") % roundi(Comfort.rested_minutes(db, cf)), "run": _sleep.bind(_near_use)}
		if info.has("buff"):
			return {"label": tr("act.steam"), "run": func() -> void:
				_send_move()
				Game.submit({"type": "steam", "uid": _near_use})}
		if info.has("storage"):
			return {"label": tr("act.station") % Loc.name_of(info["name"]), "run": _open_storage.bind(_near_use)}
	if _near_station != "" and String(state.pieces[_near_station]["id"]) == "boatyard":
		var yard := _boatyard_action(_near_station)
		if not yard.is_empty():
			return yard
	if _near_station != "":
		var pc: Dictionary = state.pieces[_near_station]
		var out: Dictionary = pc.get("out", {})
		if not out.is_empty():
			return {"label": tr("act.collect") % ItemInfo.bag_text(db, out), "run": func() -> void:
				_send_move()
				Game.submit({"type": "collect", "uid": _near_station})}
		return {"label": tr("act.station") % Loc.name_of(db.pieces[pc["id"]]["name"]), "run": _open_craft}
	if _can_fish():
		return {"label": tr("act.fish") % Loc.item(db, "raw_fish"), "run": _start_fishing}
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


## Anything that takes the keys and the mouse from the world.
func ui_open() -> bool:
	return craft.visible or storage.visible or chart.visible or journal.visible or pause_menu.visible or build.active \
			or evening.visible or settings_win.visible or (menu != null and menu.visible)


func _unhandled_input(event: InputEvent) -> void:
	if craft.visible or storage.visible or chart.visible or journal.visible or pause_menu.visible or cam.in_shot() \
			or evening.visible or settings_win.visible:
		return
	if menu != null and menu.visible:
		return
	if event.is_action_pressed("pause") and not build.active:
		_send_move()
		pause_menu.open(self)
		player.busy = true
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("journal") and not build.active:
		_open_journal()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") and not build.active:
		_open_chart()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_menu") and on_foot() and not build.active:
		build.enter()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and my_boat != null:
		_open_storage(my_boat.uid)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		_do_action()
	elif event.is_action_pressed("cycle"):
		_choice += 1
	elif event.is_action_pressed("inventory"):
		_open_craft()
		get_viewport().set_input_as_handled()
	else:
		for i in 8:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				_use_hotbar(i)


## The bag and crafting at the stations within reach.
func _open_craft() -> void:
	_send_move()
	var near: Array = []
	var p := player.global_position if on_foot() else my_boat.global_position
	for uid in Crafting.stations_near(state, p):
		near.append({"uid": uid, "id": state.pieces[uid]["id"]})
	craft.open(db, state, _pid, near)
	player.busy = true


## A chest, or the boat's hold (with "all into the storehouse" when a chest stands near the boat).
func _open_storage(uid: String) -> void:
	_send_move()
	var unload := ""
	if state.boats.has(uid):
		var bp: Vector3 = state.boats[uid]["pos"]
		for pu: String in state.pieces:
			var pc: Dictionary = state.pieces[pu]
			if pc.has("inv") and (pc["pos"] as Vector3).distance_to(bp) <= 30.0:
				unload = pu
				break
	storage.open(db, state, _pid, uid, unload)
	player.busy = true


func _sleep(uid: String) -> void:
	_send_move()
	var res := Game.submit({"type": "sleep", "uid": uid})
	if res.get("ok", false):
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 0.95, 0.8)
		tw.tween_interval(0.6)
		tw.tween_property(_fade, "color:a", 0.0, 1.2)


## Keys 1–8: a light is lit, food is eaten, anything else becomes the chosen tool.
func _use_hotbar(i: int) -> void:
	_hot = i
	var s: Dictionary = state.inv(_pid).slots[i]
	if s.is_empty():
		return
	var it: Dictionary = db.items[s["id"]]
	if it.has("food"):
		Game.submit({"type": "eat", "item": s["id"]})
	elif it.has("light"):
		Game.submit({"type": "light", "item": s["id"]})


## A station goes down 2.5 m in front of the player, facing them.
func _place_station(piece: String) -> void:
	if not on_foot():
		return
	var yaw := player.model.rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var at := player.global_position + fwd * 2.5
	at.y = map.ground_at(at.x, at.z)
	_send_move()
	Game.submit({"type": "place", "piece": piece, "pos": [at.x, at.y, at.z], "rot": yaw + PI})


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


## Board the nearest boat within reach (the last one, or a new shnyaka or koch from the boatyard).
func _board() -> void:
	_send_move()
	var best: Boat = last_boat
	var best_d := INF
	for b: Boat in boats.values():
		var d := b.global_position.distance_to(player.global_position)
		if d < best_d and d < WorldCommands.BOARD_REACH_M and not b.capsized:
			best = b
			best_d = d
	last_boat = best
	var res := Game.submit({"type": "board", "boat": best.uid})
	if res.get("ok", false):
		_attach_player()
		cam.look_yaw = 0.0
		audio.sfx("board")


## The boatyard: build the best boat that's open (koch, then shnyaka), or say what it still needs.
func _boatyard_action(uid: String) -> Dictionary:
	for type: String in ["koch", "shnyaka"]:
		var b: Dictionary = db.boats[type]
		if not db.is_unlocked(String(b["unlock"]), state.lit):
			continue
		var name := Loc.name_of(b["name"])
		var cost := ContentDB.bag(b["cost"])
		var inv := state.inv(_pid)
		if inv.has_bag(cost):
			return {"label": tr("act.build_boat") % name, "run": func() -> void:
				_send_move()
				Game.submit({"type": "build_boat", "boat": type, "uid": uid})}
		var need := tr("act.boat_needs") % [name, ItemInfo.bag_text(db, inv.missing(cost))]
		return {"label": need, "run": func() -> void: hud.toast(need)}
	return {}


## E by a trial's props, or at the tower once the trial is passed: "Light the beacon" (or what fuel is missing).
func _beacon_action() -> Dictionary:
	var p := player.global_position
	for t: Trial in trials.values():
		var a := t.action(p)
		if not a.is_empty():
			return a
	var bid := _beacon_at(p)
	if bid == "" or state.lit.has(bid):
		return {}
	if not state.trials_done.has(bid):
		return _saga_action(bid)
	var fuel := ContentDB.bag(db.beacons[bid]["fuel"])
	if state.inv(_pid).has_bag(fuel):
		return {"label": tr("act.light_beacon"), "run": _light_beacon.bind(bid)}
	var need := tr("act.need_fuel") % ItemInfo.bag_text(db, fuel)
	return {"label": need, "run": func() -> void: hud.toast(need)}


## The beacon whose tower is within lighting reach of a point on foot ("" if none).
func _beacon_at(p: Vector3) -> String:
	for bid: String in db.beacon_order:
		if Vector2(p.x, p.z).distance_to(db.beacon_pos(bid)) <= WorldCommands.BEACON_REACH_M - 1.5:
			return bid
	return ""


## Saga at the tower: start the guardian's fight, or the fire defence (with the fuel in the bag).
func _saga_action(bid: String) -> Dictionary:
	if String(state.rules()["beacon"]) == "trial" or state.busy_beacon != "" or not db.region_open(db.beacons[bid]["region"], state.lit):
		return {}
	var start := func() -> void:
		_send_move()
		Game.submit({"type": "begin_fight", "beacon": bid})
	if String(db.beacons[bid]["saga"]["type"]) == "guardian":
		var boss: String = Game.commands.guardian_of(bid)
		return {"label": tr("act.fight_guardian") % Loc.name_of(db.creatures[boss]["name"]), "run": start}
	var fuel := ContentDB.bag(db.beacons[bid]["fuel"])
	if not state.inv(_pid).has_bag(fuel):
		var need := tr("act.need_fuel") % ItemInfo.bag_text(db, fuel)
		return {"label": need, "run": func() -> void: hud.toast(need)}
	return {"label": tr("act.defend_fire") % int(db.beacons[bid]["saga"]["seconds"]), "run": start}


func _light_beacon(bid: String) -> void:
	_send_move()
	Game.submit({"type": "light_beacon", "beacon": bid})


## The window's close button or "Until tomorrow": the evening screen first; a second close quits.
func _on_quit_requested() -> void:
	if evening.visible or (menu != null and menu.visible):
		Game.quit_now()
	else:
		_open_evening()


func _open_evening() -> void:
	_send_move()
	evening.open(db, state, _focus())
	player.busy = true


func _open_journal() -> void:
	journal.open(db, state)
	player.busy = true


## The chart (M): what the fog has shown so far.
func _open_chart() -> void:
	_send_move()
	var me := _focus()
	var yaw := my_boat.rotation.y if my_boat != null else player.model.rotation.y
	chart.open(db, state, map, Vector2(me.x, me.z), yaw, trail, mark)
	player.busy = true


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


# ---------------------------------------------------------------- fishing

## A rod in the bag and open water in front: from a boat that has stopped or from the shore.
func _can_fish() -> bool:
	var inv := state.inv(_pid)
	if inv.best_tool_tier("rod") < 1:
		return false
	if my_boat != null:
		return absf(my_boat.speed) < 0.8
	return _cast_point().y < -0.5


func _cast_point() -> Vector3:
	if my_boat != null:
		var bp := my_boat.global_position
		var side := my_boat.global_transform.basis.x
		var p := bp + side * 5.0
		return Vector3(p.x, map.ground_at(p.x, p.z), p.z)
	var yaw := player.model.rotation.y
	var p := player.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 6.0
	return Vector3(p.x, map.ground_at(p.x, p.z), p.z)


## Fishing works like gathering: bites come at the fish's gather rate, each strike in time is one fish,
## and the catch of this spot goes to the host as one "gather" of the sea cell.
func _start_fishing() -> void:
	var cp := _cast_point()
	var per := Gathering.unit_seconds(db, state.inv(_pid), "raw_fish")
	if Creatures.vodyanoy_boon(state):
		per /= 1.0 + float(db.balance["spirits"]["vodyanoy_bite_bonus"])  # the first fish went to the vodyanoy
	_fishing = {"spot": map.fish_spot(Vector2(cp.x, cp.z)), "pos": cp, "t": 0.0, "next": per * randf_range(0.6, 1.3), "bite": 0.0, "caught": 0, "want": WorldCommands.GATHER_MAX, "per": per}
	_bobber.visible = true
	player.busy = true
	audio.sfx("board")


func _update_fishing(delta: float) -> void:
	if _fishing.is_empty():
		_bobber.visible = false
		return
	var f := _fishing
	var cp: Vector3 = f["pos"]
	var dip := 0.0
	f["t"] = float(f["t"]) + delta
	if float(f["bite"]) > 0.0:
		f["bite"] = float(f["bite"]) - delta
		dip = -0.25 - 0.1 * sin(float(f["t"]) * 30.0)
		if float(f["bite"]) <= 0.0:
			hud.toast(tr("toast.fish_lost"))
			f["t"] = 0.0
			f["next"] = float(f["per"]) * randf_range(0.6, 1.3)
	elif float(f["t"]) >= float(f["next"]):
		f["bite"] = 1.3
		audio.sfx("pickup", 2)
	_bobber.global_position = Vector3(cp.x, Sea.height(cp.x, cp.z) + 0.1 + dip, cp.z)
	var moved := (my_boat != null and absf(my_boat.throttle) > 0.1) or (on_foot() and player.velocity.length() > 0.5)
	if moved:
		_stop_fishing()


func _hook() -> void:
	var f := _fishing
	f["caught"] = int(f["caught"]) + 1
	f["bite"] = 0.0
	f["t"] = 0.0
	f["next"] = float(f["per"]) * randf_range(0.6, 1.3)
	audio.sfx("pickup", int(f["caught"]))
	if int(f["caught"]) >= int(f["want"]):
		_stop_fishing()


func _stop_fishing() -> void:
	var f := _fishing
	_fishing = {}
	_bobber.visible = false
	player.busy = false
	if f.is_empty() or int(f["caught"]) <= 0:
		return
	_send_move()
	Game.submit({"type": "gather", "node": f["spot"], "item": "raw_fish", "qty": int(f["caught"])})


func _make_bobber() -> Node3D:
	var root := Node3D.new()
	root.name = "Bobber"
	var top := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 6
	s.rings = 3
	top.mesh = s
	top.material_override = Placeholders.mat(Color("d9cbb0"), Color("ff9a40"), 0.8, false)
	root.add_child(top)
	root.visible = false
	return root


## Food and rest set the limits: the player node carries them for movement and the HUD.
func _update_vitals() -> void:
	player.hp_max = Vitals.max_hp(db, state, _pid)
	player.hp = float(state.players[_pid]["hp"])
	player.stamina_max = Vitals.max_stamina(db, state, _pid)
	player.stamina = minf(player.stamina, player.stamina_max)
	player.stamina_regen = Vitals.stamina_regen(db, state, _pid)


func _update_beacons() -> void:
	var next := Progress.next_beacon(db, state)
	var night := float(director.palette.get("night", 0.0))
	for bid: String in beacons:
		(beacons[bid] as BeaconView).set_hint(bid == next)
		(beacons[bid] as BeaconView).night = night
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


## Trials are props on their islands: built when the island comes near (Quiet and Tale; the Saga lights
## beacons by fights), dropped when it is far again or its beacon burns and the player has sailed off.
func _update_trials(delta: float) -> void:
	var by_trial := Game.commands != null and String(Game.commands.rules()["beacon"]) == "trial"
	var f := _focus()
	for bid: String in db.beacon_order:
		var d := Vector2(f.x, f.z).distance_to(db.beacon_pos(bid))
		var t: Trial = trials.get(bid)
		if t == null:
			if by_trial and d < 420.0 and not state.trials_done.has(bid) and not state.lit.has(bid) \
					and db.region_open(db.beacons[bid]["region"], state.lit):
				t = Trial.create(String(db.beacons[bid]["trial"]))
				add_child(t)
				t.setup(self, bid)
				trials[bid] = t
		elif d > 650.0 or (state.lit.has(bid) and d > 160.0) or not by_trial:
			trials.erase(bid)
			t.queue_free()
	for t: Trial in trials.values():
		t.tick(delta)  # finished trials keep animating (lit lanterns flicker, bells settle)


## The light budget (docs/04_TECH_SPEC.md §11): only the LIGHT_BUDGET real lights nearest the camera shine; the
## rest are left to their emissive flames and glows, which read the same through the fog at a distance.
## Returns how many are on.
func light_budget() -> int:
	var c := cam.global_position
	var lights: Array = []
	for n in get_tree().get_nodes_in_group("budget_light"):
		var l := n as OmniLight3D
		if l != null and l.is_inside_tree():
			lights.append([l.global_position.distance_squared_to(c), l])
	lights.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var on := 0
	for i in lights.size():
		var l: OmniLight3D = lights[i][1]
		l.visible = i < LIGHT_BUDGET
		if l.visible:
			on += 1
	return on


## --bench: frame time, draw calls and objects at a few places (home, at sea, a beacon island) — the numbers
## docs/04_TECH_SPEC.md §11 is checked against.
func _bench_frame() -> void:
	if _bench.is_empty():
		_bench = {"stage": 0, "frames": 0, "t": 0.0, "draws": 0.0, "objects": 0.0, "rows": []}
	var places := [["home", Vector3.ZERO], ["sea", Vector3(150, 0, -420)], ["b01", Vector3.INF]]
	var b := _bench
	b["frames"] = int(b["frames"]) + 1
	var now := Time.get_ticks_usec()
	if int(b["frames"]) > 60:  # settle, then measure 120 frames
		b["t"] = float(b["t"]) + (Time.get_ticks_usec() - int(b.get("last", Time.get_ticks_usec()))) / 1000000.0
		b["draws"] = float(b["draws"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		b["objects"] = float(b["objects"]) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	b["last"] = now
	if int(b["frames"]) < 180:
		return
	var n := 120.0
	(b["rows"] as Array).append("%s: %.1f ms/frame, %d draw calls, %d objects, %d lights on" % [places[int(b["stage"])][0], float(b["t"]) / n * 1000.0, roundi(float(b["draws"]) / n), roundi(float(b["objects"]) / n), light_budget()])
	b["stage"] = int(b["stage"]) + 1
	b["frames"] = 0
	b["t"] = 0.0
	b["draws"] = 0.0
	b["objects"] = 0.0
	if int(b["stage"]) >= places.size():
		for r: String in b["rows"]:
			print("BENCH ", r)
		get_tree().quit(0)
		return
	var to: Vector3 = places[int(b["stage"])][1]
	if my_boat != null and to != Vector3.INF:
		my_boat.global_position = Vector3(to.x, 0.0, to.z)
		streamer.build_around(my_boat.global_position)
	elif to == Vector3.INF:
		_args["at-beacon"] = "b01"
		_debug_place()


## Co-op: the other players and the boats they sail, from WorldState (their "move" commands, replayed on every
## copy of the world), eased so they don't jump. A boat someone else steers is kinematic here.
func _update_others(delta: float) -> void:
	if not Net.is_online() and others.is_empty():
		return
	var k := 1.0 - exp(-delta * 8.0)
	for pid: String in state.players:
		if pid == _pid:
			continue
		var p: Dictionary = state.players[pid]
		var here := Net.peers.has(pid)
		var n: Node3D = others.get(pid)
		if n == null and here:
			n = ModelLibrary.instance("player", "pomor")
			var tag := Label3D.new()
			tag.text = pid
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.position = Vector3(0, 2.3, 0)
			tag.font_size = 48
			tag.outline_size = 8
			n.add_child(tag)
			add_child(n)
			n.global_position = p["pos"]
			others[pid] = n
		if n == null:
			continue
		n.visible = here and String(p["aboard"]) == ""
		var to: Vector3 = p["pos"]
		var move := to - n.global_position
		n.global_position = n.global_position.lerp(to, k)
		if Vector2(move.x, move.z).length() > 0.05:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-move.x, -move.z), k)
	for uid: String in boats:
		var b: Boat = boats[uid]
		if b == my_boat or not state.boats.has(uid):
			continue
		var steered := false
		for pid: String in state.players:
			if pid != _pid and String(state.players[pid]["aboard"]) == uid:
				steered = true
		b.freeze = steered
		if steered:
			var row: Dictionary = state.boats[uid]
			var bp: Vector3 = row["pos"]
			b.global_position = b.global_position.lerp(Vector3(bp.x, b.global_position.y, bp.z), k)
			b.rotation.y = lerp_angle(b.rotation.y, float(row["yaw"]), k)


## The dotted path on the chart: a point every TRAIL_STEP_M metres.
func _update_trail(focus: Vector3) -> void:
	var p := Vector2(focus.x, focus.z)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(p) >= TRAIL_STEP_M:
		trail.append(p)
	if mark != Vector2.INF and p.distance_to(mark) < 25.0:
		mark = Vector2.INF
		hud.toast(tr("toast.mark_reached"))


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
	hud.visible = not craft.visible and not storage.visible and not build.active and not chart.visible \
			and not journal.visible and not pause_menu.visible and (menu == null or not menu.visible) \
			and not evening.visible and not settings_win.visible
	if hud.in_cinema:
		return  # the beacon moment: only the banner and the black bars
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	var rid := db.region_at(p)
	hud.set_region("%s · %s" % [Loc.chapter(db, rid), Loc.region(db, rid)])
	if not director.palette.is_empty():
		hud.set_backdrop((director.palette["fog"] as Color).get_luminance() > 0.45)
	var goal := _goal()
	hud.set_goal(goal["text"])
	if mark != Vector2.INF:
		goal["target"] = Vector3(mark.x, 0.0, mark.y)
		goal["label"] = tr("target.mark")
	if Creatures.leshy_guiding(state) and creatures.leshy_goal != Vector3.INF and on_foot():
		goal["target"] = creatures.leshy_goal
		goal["label"] = tr("target.wisp")
	var fwd := -cam.global_transform.basis.z
	var cam_bearing := atan2(fwd.x, -fwd.z)
	if goal.has("target") and not cam.in_shot():
		var t: Vector3 = goal["target"]
		var me := _focus()
		var rel := Vector2(t.x - me.x, t.z - me.z)
		hud.set_compass(cam_bearing, atan2(rel.x, -rel.y), "%s: %s" % [goal["label"], Loc.meters(rel.length())])
	else:
		hud.set_compass(cam_bearing, NAN, "")
	hud.set_action("" if craft.visible else String(_action().get("label", "")))
	hud.set_bars(player.hp, player.hp_max, float(Vitals.bonus(db, state, _pid)["hp"]), player.stamina, player.stamina_max)
	var food: Array = []
	for f: Dictionary in state.players[_pid]["food"]:
		food.append({"id": f["id"], "left_min": float(f["until"]) - state.clock_min})
	hud.set_buffs(food, _states())
	_update_fight_bar()
	hud.set_hotbar(state.inv(_pid).slots.slice(0, 8), _hot, on_foot() and not craft.visible)
	var light: Dictionary = state.players[_pid].get("light", {})
	if on_foot() and not light.is_empty():
		var lt: Dictionary = db.items[light["id"]]["light"]
		var total := float(lt.get("minutes", lt.get("minutes_per_fuel", 0.0)))
		hud.set_light(String(light["id"]), -1.0 if float(light["until"]) < 0.0 else float(light["until"]) - state.clock_min, total)
	else:
		hud.set_light("", 0.0, 0.0)
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
		var hint := tr("hint.foot")
		if not _fishing.is_empty():
			hint = tr("hint.fishing")
		elif creatures.hostile_near(player.global_position, 25.0):
			hint = tr("hint.combat")
		hud.set_hint(hint)


## The states in the top-right corner besides food: Rested, Bath steam, Weary, Cold, the leshy's wisp.
func _states() -> Array:
	var p: Dictionary = state.players[_pid]
	var out: Array = []
	var left := func(until: float) -> String: return "%d %s" % [ceili(until - state.clock_min), tr("unit.min").to_upper()]
	if float(p["rested_until"]) > state.clock_min:
		out.append({"label": tr("ui.rested"), "text": left.call(float(p["rested_until"]))})
	if float(p["steam_until"]) > state.clock_min:
		out.append({"label": tr("ui.steam"), "text": left.call(float(p["steam_until"]))})
	if Vitals.is_weary(state, _pid):
		out.append({"label": tr("ui.weary"), "text": left.call(float(p["weary_until"])), "warn": true})
	if Creatures.is_cold(db, state, _pid):
		out.append({"label": tr("ui.cold"), "text": tr("ui.cold_hint"), "warn": true})
	if Creatures.leshy_guiding(state):
		out.append({"label": tr("ui.wisp"), "text": ""})
	return out


## Saga fights: the guardian's health and phase, or the kindling fire and the time left.
func _update_fight_bar() -> void:
	if state.fight.is_empty():
		hud.set_boss("")
		return
	if String(state.fight["kind"]) == "defense":
		var left := maxf(0.0, (float(state.fight["until"]) - state.clock_min) * 60.0)
		hud.set_boss(tr("fight.fire"), float(state.fight["fire"]), 100.0, tr("fight.hold") % ItemInfo.clock(left / 60.0))
		return
	var boss: Dictionary = state.creatures.get(String(state.fight.get("boss", "")), {})
	if boss.is_empty():
		hud.set_boss("")
		return
	var info: Dictionary = db.creatures[boss["id"]]
	var sub := tr("fight.phase") % [int(state.fight.get("phase", 1)), int(info.get("phases", 1))]
	if String(boss["id"]) == "mga":
		sub += " · " + tr("fight.lanterns") % [(state.fight.get("lanterns", []) as Array).size(), WorldCommands.ARENA_LANTERNS]
	hud.set_boss(Loc.name_of(info["name"]), float(boss["hp"]), float(info["hp"]), sub)


## Death by the mode's rules (docs/01_GDD.md §6): a fade, then wake where the host says.
func _respawn(e: Dictionary) -> void:
	var at := WorldState._to_v3(e["at"])
	if not _fishing.is_empty():
		_stop_fishing()
	_channel = {}
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		if my_boat != null:
			my_boat = null
		_attach_player()
		player.place(Vector3(at.x, map.ground_at(at.x, at.z) + 0.2, at.z), player.model.rotation.y)
		player.stamina = player.stamina_max
		streamer.build_around(player.global_position)
		cam.snap())
	tw.tween_interval(0.6)
	tw.tween_property(_fade, "color:a", 0.0, 1.2)
	var key := "toast.respawn_" + String(e["death"])
	hud.toast(tr(key), "✦")


## What the player should do now and where the compass points: {"text", "target": Vector3, "label"}.
func _goal() -> Dictionary:
	var next := Progress.next_beacon(db, state)
	var beacon_goal := {}
	if next != "":
		var bv: BeaconView = beacons[next]
		beacon_goal = {"target": bv.fire_pos, "label": tr("target.beacon") % Loc.beacon(db, next)}
	if my_boat != null:
		if my_boat.capsized:
			return {"text": tr("goal.capsized")}
		if my_boat.wall != "":
			var g := beacon_goal.duplicate()
			var bp := Vector2(my_boat.global_position.x, my_boat.global_position.z)
			var need := Loc.name_of(db.boats[SeaWall.boat_needed(db, bp)]["name"])
			g["text"] = tr("goal.wall_" + my_boat.wall) if my_boat.wall != "boat" else tr("goal.wall_boat") % need
			return g
		if next == "":
			return {"text": tr("goal.free")}
		var near_isl := map.nearest_island(Vector2(my_boat.global_position.x, my_boat.global_position.z), 40.0)
		var text := tr("goal.land") if not _landing.is_empty() and near_isl != null and near_isl.id == next else tr("goal.sail")
		beacon_goal["text"] = text
		return beacon_goal
	var isl := map.island_at(player.global_position.x, player.global_position.z)
	var boat_goal := {"target": last_boat.global_position if last_boat != null else Vector3.ZERO, "label": tr("target.boat")}
	if isl != null and map.kind_of[isl.id] == "beacon":
		var here := _beacon_goal(isl.id, boat_goal)
		if not here.is_empty():
			return here
	if next == "":
		return {"text": tr("goal.free")}
	if isl != null and isl.id == WorldMap.HOME:
		boat_goal["text"] = tr("goal.home")
		return boat_goal
	boat_goal["text"] = tr("goal.back_to_boat")
	return boat_goal


## On a beacon's island: the trial's own line and target, then the fuel, then "back to the boat".
func _beacon_goal(bid: String, boat_goal: Dictionary) -> Dictionary:
	var bv: BeaconView = beacons[bid]
	var tower := {"target": bv.fire_pos, "label": tr("target.beacon") % Loc.beacon(db, bid)}
	if state.lit.has(bid):
		if Progress.next_beacon(db, state) == "":
			return {}
		boat_goal["text"] = tr("goal.lit_here")
		return boat_goal
	if not db.region_open(db.beacons[bid]["region"], state.lit):
		return {}
	if state.trials_done.has(bid):
		var fuel := ContentDB.bag(db.beacons[bid]["fuel"])
		tower["text"] = tr("goal.light") if state.inv(_pid).has_bag(fuel) else tr("goal.fuel") % ItemInfo.bag_text(db, fuel)
		return tower
	if Game.commands != null and String(Game.commands.rules()["beacon"]) != "trial":
		if state.busy_beacon == bid:
			tower["text"] = tr("goal.fight_" + String(state.fight.get("kind", "guardian")))
		elif String(db.beacons[bid]["saga"]["type"]) == "guardian":
			tower["text"] = tr("goal.saga_guardian") % Loc.name_of(db.creatures[Game.commands.guardian_of(bid)]["name"])
		else:
			tower["text"] = tr("goal.saga_defense") % [int(db.beacons[bid]["saga"]["seconds"]), ItemInfo.bag_text(db, ContentDB.bag(db.beacons[bid]["fuel"]))]
		return tower
	var t: Trial = trials.get(bid)
	if t == null:
		tower["text"] = tr("goal.climb") if player.light_id != "" else tr("goal.need_fire")
		return tower
	tower["text"] = t.goal()
	var tg := t.target()
	if not tg.is_empty():
		tower["target"] = tg["target"]
		tower["label"] = tg["label"]
	return tower


# ---------------------------------------------------------------- the beacon moment

## docs/01_GDD.md §5.4: the fire is set, the camera flies out to the side (across the sun, so the flame
## isn't lost in the glare), the flame catches and the clearing grows over GROW_S, the music rises, the
## banner says what opened; then the camera comes back. A beacon lit far away (a co-op friend) just kindles.
func _on_beacon_lit(e: Dictionary) -> void:
	var bid: String = e["beacon"]
	var bv: BeaconView = beacons[bid]
	if _moment != "" or bv.fire_pos.distance_to(_focus()) > 150.0:
		bv.kindle()
		director.mark_lit(bid)
		audio.sfx("swell")
		hud.toast(tr("banner.lit") % [state.lit.size(), db.beacon_order.size()], Loc.beacon(db, bid))
		return
	_moment = bid
	director.mark_lit_after(bid, KINDLE_AT)
	player.busy = true
	hud.cinematic(true, _next_line(bid))
	cam.play_shot(bv.fire_pos, moment_offset(bv.fire_pos), MOMENT_S, _end_moment, 2.0)
	var unlocks: Dictionary = e.get("unlocks", {})
	get_tree().create_timer(KINDLE_AT).timeout.connect(func() -> void:
		bv.kindle()
		audio.sfx("swell"))
	get_tree().create_timer(BANNER_AT).timeout.connect(_moment_banner.bind(bid, unlocks))


## Where the camera stands for the moment, relative to the fire: out to the side across the sun's direction
## (on the player's side of the tower), a little towards the sun so the sun is behind, a bit below the fire.
func moment_offset(fire: Vector3) -> Vector3:
	var s3 := sun.global_transform.basis.z  # towards the sun
	var s := Vector2(s3.x, s3.z)
	s = s.normalized() if s.length() > 0.01 else Vector2(0, 1)
	var side := Vector2(-s.y, s.x)
	var me := _focus()
	if side.dot(Vector2(me.x - fire.x, me.z - fire.z)) < 0.0:
		side = -side
	var o2 := side * 21.0 + s * 6.0
	var off := Vector3(o2.x, -3.0, o2.y)
	var at := fire + off
	var ground := map.ground_at(at.x, at.z)
	if at.y < ground + 2.5:
		off.y += ground + 2.5 - at.y
	return off


## The line in the lower black bar: where the next light glimmers.
func _next_line(bid: String) -> String:
	var next := Progress.next_beacon(db, state)
	if next == "":
		return tr("banner.last")
	var v := db.beacon_pos(next) - db.beacon_pos(bid)
	return tr("banner.next") % [Loc.direction(v), Loc.beacon(db, next)]


func _moment_banner(bid: String, unlocks: Dictionary) -> void:
	var n := state.lit.size()
	var lines: Array = [tr("banner.cleared") % int(db.beacons[bid]["clear_radius"])]
	var opens: Variant = db.beacons[bid].get("opens")
	if opens != null:
		lines.append(tr("banner.region") % Loc.region(db, String(opens)))
	var layers: Array[String] = []
	var before := Progress.music_layers(n - 1)
	for l: String in Progress.music_layers(n):
		if not before.has(l):
			layers.append(tr("music." + l))
	var music := "" if layers.is_empty() else "♪ " + tr("banner.music") % ", ".join(layers)
	hud.show_banner(tr("banner.lit") % [n, db.beacon_order.size()], Loc.beacon(db, bid), lines, unlock_chips(unlocks), music, MOMENT_S - BANNER_AT + 1.5)


## "Opened:" chips with icons: new pieces, the things new recipes make, new boats.
func unlock_chips(unlocks: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for id: String in unlocks.get("pieces", []):
		out.append({"text": Loc.name_of(db.pieces[id]["name"]), "icon": id})
		seen[id] = true
	for rid: String in unlocks.get("recipes", []):
		for item: String in db.recipes[rid]["output"]:
			if not seen.has(item) and not db.pieces.has(item):
				out.append({"text": Loc.item(db, item), "icon": item})
				seen[item] = true
	for id: String in unlocks.get("boats", []):
		out.append({"text": Loc.name_of(db.boats[id]["name"]), "icon": id})
	return out.slice(0, 8)


func _end_moment() -> void:
	hud.cinematic(false)
	player.busy = false
	_moment = ""


# ---------------------------------------------------------------- world events

func _on_world_event(e: Dictionary) -> void:
	var mine := String(e.get("player", "")) == _pid
	match String(e.get("type", "")):
		"beacon_lit":
			_on_beacon_lit(e)
		"region_opened":
			if _moment == "":  # during the moment the banner says it
				hud.toast(tr("toast.region_opened") % Loc.region(db, String(e["region"])))
		"respawn":
			if mine:
				_respawn(e)
		"boat_added":
			if not boats.has(String(e["uid"])):
				_spawn_boat(String(e["uid"]))
			if mine:
				hud.toast(tr("toast.boat_built") % Loc.name_of(db.boats[e["boat"]]["name"]), "⛵")
				audio.sfx("swell")
		"boarded", "disembarked":
			if mine and Net.is_client():
				_attach_player()  # a co-op client hears it when the host's answer comes back
		"player_joined":
			if String(e["player"]) != _pid:
				hud.toast(tr("coop.joined") % String(e["player"]), "✦")
		"journal_page":
			if mine:
				hud.toast(tr("toast.journal") % String(journal.page(String(e["page"]))["title"]), "J")
		"offered":
			if mine:
				hud.toast(tr("toast.offered_" + String(e["spirit"])), "✦")
				audio.sfx("lantern", 1)
		"met":
			if mine and e.get("rested", false):
				hud.toast(tr("toast.whale"), "✦")
				var tw := create_tween()
				tw.tween_property(_fade, "color:a", 0.9, 0.8)
				tw.tween_interval(0.8)
				tw.tween_property(_fade, "color:a", 0.0, 1.2)
			if mine and String(e["creature"]) == "sirin":
				audio.sfx("sirin")
		"explored":
			if mine:
				hud.toast(tr("toast.explored"), ItemInfo.bag_text(db, e["items"]))
		"boat_capsized":
			hud.toast(tr("toast.capsized"), "!")
			audio.sfx("thud")
		"boat_righted":
			audio.sfx("board")
		"fight_started":
			var kind := String(e["kind"])
			hud.toast(tr("fight.start_" + kind), "!")
			audio.sfx("growl")
		"fight_ended":
			hud.toast(tr("toast.fight_won") if e.get("won", false) else tr("toast.fight_lost"), "!")
		"fire_doused":
			audio.sfx("hurt")
		"creature_died":
			if mine and not (e["drops"] as Dictionary).is_empty():
				hud.toast(Loc.name_of(db.creatures[e["id"]]["name"]), ItemInfo.bag_text(db, e["drops"]))
		"mode_changed":
			hud.toast(tr("toast.mode") % Loc.name_of(db.modes[e["to"]]["name"]))
		"domovoy_tidied":
			hud.toast(tr("toast.tidied"), "✦")
		"stolen":
			hud.toast(tr("toast.stolen") % Loc.item(db, e["item"]))
		"steamed":
			if mine and String(e.get("bannik", "")) == "angry":
				hud.toast(tr("toast.bannik_angry"), "!")
		"trial_done":
			if mine:
				var kind := String(db.beacons[e["beacon"]]["trial"])
				if String(e["kind"]) != "trial":
					hud.toast(tr("toast.saga_done_" + String(e["kind"])), "✓")
				else:
					hud.toast(tr("toast.trial_done") % Loc.name_of(db.trial_types[kind]), "✓")
				audio.sfx("lantern", 2)
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
		"piece_placed":
			pieces.add_piece(String(e["uid"]))
			audio.sfx("chop")
		"piece_removed":
			pieces.remove_piece(String(e["uid"]))
		"station_done":
			var pc: Dictionary = state.pieces.get(String(e["uid"]), {})
			if not pc.is_empty() and (pc["pos"] as Vector3).distance_to(_focus()) < 60.0:
				hud.toast(tr("toast.station_done") % Loc.name_of(db.pieces[pc["id"]]["name"]), "✓")
		"station_collected":
			if mine:
				for k: String in e["items"]:
					hud.toast(Loc.item(db, k), "+%d" % int(e["items"][k]))
				audio.sfx("pickup", 1)
		"station_loaded":
			if mine:
				audio.sfx("craft")
		"ate":
			if mine:
				hud.toast(tr("toast.ate") % Loc.item(db, e["item"]))
		"slept":
			if mine:
				hud.toast(tr("toast.slept") % [roundi(float(e["minutes"])), int(e["comfort"])])
		"steamed":
			if mine:
				hud.toast(tr("toast.steamed") % roundi(float(e["minutes"])))
		"unloaded":
			if mine:
				hud.toast(tr("toast.unloaded") % int(e["n"]))
	craft.refresh()
	storage.refresh()
	build.refresh()
	journal.refresh()


func _on_command_failed(cmd: Dictionary, error: String) -> void:
	if error in ["bad_pos"]:
		return
	# what the host simulates (creatures, their hits, storms) and quiet background commands never toast
	if String(cmd.get("type", "")) in WorldCommands.HOST_ONLY or String(cmd.get("type", "")) in ["meet", "move"]:
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
	if _args.has("time"):
		# the time of day, 0..1 (0 = midnight): moves the world clock forward to it
		var len := float(db.balance["day"]["length_min"])
		var want := fposmod(float(_args["time"]) - 0.25, 1.0) * len
		Game.submit({"type": "debug", "clock_min": state.clock_min - fposmod(state.clock_min, len) + want})
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
	hud.clear_toasts()  # the setup's own toasts (debug gifts, instantly lit beacons) are not the shot
	if (_args.has("ashore") or _args.has("walk") or _args.has("at-beacon")) and my_boat != null:
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
	if _args.has("at-beacon") and on_foot():
		# on the path to a beacon's tower (t along the path: --path-t=0.82), facing the tower
		var bid := String(_args["at-beacon"])
		var q := map.path_point(bid, float(_args.get("path-t", 0.82)), float(_args.get("path-side", 0.0)))
		var bp := db.beacon_pos(bid)
		var yaw := atan2(-(bp.x - q.x), -(bp.y - q.z)) + deg_to_rad(float(_args.get("turn", 0.0)))
		Game.submit({"type": "debug", "pos": [q.x, q.y, q.z]})
		player.place(q + Vector3(0, 0.2, 0), yaw)
		cam.foot_yaw = yaw + (deg_to_rad(float(String(_args["look"]).split(",")[0])) if _args.has("look") else 0.0)
		streamer.build_around(player.global_position)
		cam.snap()
	if _args.has("trail"):
		# debug: a travelled path home → every lit beacon → here, for the chart
		var pts: Array[Vector2] = [Vector2(map.home["spawn"].x, map.home["spawn"].z)]
		for bid: String in db.beacon_order:
			if state.lit.has(bid):
				pts.append(db.beacon_pos(bid))
		var f := _focus()
		pts.append(Vector2(f.x, f.z))
		trail = PackedVector2Array()
		for i in range(1, pts.size()):
			var n := maxi(1, int(pts[i - 1].distance_to(pts[i]) / TRAIL_STEP_M))
			for k in n:
				trail.append(pts[i - 1].lerp(pts[i], float(k) / n))
	if _args.has("place") and on_foot():
		var n := 0
		for piece: String in String(_args["place"]).split(","):
			Game.submit({"type": "debug", "give": ContentDB.bag(db.pieces[piece]["cost"])})
			var yaw := player.model.rotation.y + (n - 0.5) * 0.9
			var at := player.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 3.2
			at.y = map.ground_at(at.x, at.z)
			Game.submit({"type": "place", "piece": piece, "pos": [at.x, at.y, at.z], "rot": yaw + PI})
			n += 1
	if _args.has("eat"):
		for dish: String in String(_args["eat"]).split(","):
			Game.submit({"type": "debug", "give": {dish: 1}})
			Game.submit({"type": "eat", "item": dish})
	if _args.has("house") and on_foot():
		_debug_house()
	if _args.has("build") and on_foot():
		build.enter()
		build.piece = String(_args["build"])
		var yaw := player.model.rotation.y
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		build.debug_aim = player.global_position + fwd * 5.0 + Vector3(fwd.z, 0, -fwd.x) * 2.0
	if _args.has("chart"):
		_open_chart()
	if _args.has("journal"):
		for id: String in String(_args["journal"]).split(","):
			if id != "true":
				Game.submit({"type": "debug", "journal": id})
		_open_journal()
	if _args.has("pause"):
		pause_menu.open(self)
	if _args.has("evening"):
		Game.submit({"type": "debug", "give": {"wood": 64, "stone": 40, "raw_fish": 11}})
		Game.session["gathered"] = {"wood": 64, "stone": 40, "raw_fish": 11}
		Game.session["built"] = {"bathhouse_stove": 1, "log_wall": 6, "gable_roof": 1}
		Game.session["started"] = Time.get_ticks_msec() - 72 * 60000
		_open_evening()
	if _args.has("settings"):
		settings_win.open()
	if _args.has("creature"):
		# debug: creatures in front of the player (through the same "spawn" the host sends, as a fight spawn
		# when a fight is on, else ambient: the host may still say no)
		var n := 0
		for id: String in String(_args["creature"]).split(","):
			var yaw := player.model.rotation.y + (n - 0.5) * 0.7
			var at := _focus() + Vector3(-sin(yaw), 0, -cos(yaw)) * (7.0 + n * 2.0)
			at.y = map.ground_at(at.x, at.z)
			Game.submit({"type": "debug", "spawn": id, "pos": [at.x, at.y, at.z]})
			n += 1
	if _args.has("fight") and on_foot():
		var bid := String(_args["fight"])
		Game.submit({"type": "debug", "give": ContentDB.bag(db.beacons[bid]["fuel"])})
		Game.submit({"type": "begin_fight", "beacon": bid})
	if _args.has("hurt"):
		Game.submit({"type": "debug", "hp": float(_args["hurt"])})
	if _args.has("craft") and on_foot():
		_open_craft()
		if String(_args["craft"]) != "true":
			craft.selected = String(_args["craft"])
			craft.refresh()


## Debug: a small cabin 8 m ahead through the same snapped "place" commands the build mode sends.
func _debug_house() -> void:
	Game.submit({"type": "debug", "give": {"wood": 200, "stone": 60, "moss": 30, "birch_bark": 10, "rope": 6}})
	var yaw := player.model.rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := Vector3(fwd.z, 0, -fwd.x)
	var base := player.global_position + fwd * 9.0
	var cells: Array[Vector3] = [base, base + side * 2.0]
	var put := func(piece: String, aim: Vector3, turns: int) -> void:
		var sn := Building.snap(db, state, map, piece, aim, turns)
		var q: Vector3 = sn["pos"]
		Game.submit({"type": "place", "piece": piece, "pos": [q.x, q.y, q.z], "rot": sn["rot"]})
	for c in cells:
		put.call("log_foundation", c, 0)
	for c in cells:
		put.call("plank_floor", c, 0)
	for c in cells:
		var cc := Building.cell_center(c)
		var y := map.ground_at(cc.x, cc.y)
		for d: Vector2 in [Vector2(0, -0.9), Vector2(0, 0.9)]:
			put.call("log_wall", Vector3(cc.x + d.x, y, cc.y + d.y), 0)
	var c0 := Building.cell_center(cells[0])
	var c1 := Building.cell_center(cells[1])
	var lo := c0 if c0.x < c1.x else c1
	var hi := c1 if c0.x < c1.x else c0
	put.call("log_wall", Vector3(lo.x - 0.9, 0, lo.y), 0)
	put.call("door", Vector3(hi.x + 0.9, 0, hi.y), 0)
	for c in cells:
		put.call("gable_roof", c, 0)
	put.call("bed", base + side * 1.0 + Vector3(0.3, 0, 0.3), 0)
	put.call("hearth", base - fwd * 3.5, 0)
	put.call("bench", base - fwd * 3.5 + side * 3.0, 1)
	put.call("bathhouse_stove", base - fwd * 2.0 - side * 4.5, 0)


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
	if _args.has("solve") and _frame == 6:
		for t: Trial in trials.values():
			t.debug_solve(int(_args["solve"]))
	if _args.has("light-at") and _frame == int(_args["light-at"]):
		var next := Progress.next_beacon(db, state)
		if next != "":
			_debug_light(next, false)
	if _args.has("bench"):
		_bench_frame()
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
