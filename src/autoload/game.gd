extends Node
## Autoload "Game": owns the WorldState and routes commands (docs/04_TECH_SPEC.md §3).
## Views listen to world_event and update themselves; they never change the state directly.

signal world_event(event: Dictionary)
signal command_failed(cmd: Dictionary, error: String)

const INPUT_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "build_menu": [KEY_B],
	"inventory": [KEY_TAB], "map": [KEY_M], "pause": [KEY_ESCAPE], "cycle": [KEY_Q], "rotate": [KEY_R],
	"eat": [KEY_F], "journal": [KEY_J], "block": [KEY_C], "dodge": [KEY_CTRL, KEY_ALT],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4],
	"slot_5": [KEY_5], "slot_6": [KEY_6], "slot_7": [KEY_7], "slot_8": [KEY_8],
}
const MOUSE_ACTIONS := {"attack": MOUSE_BUTTON_LEFT}
const TICK_S := 1.0  # how often the host advances the world clock
const WORLDS_DIR := "user://worlds"

var state: WorldState
var commands: WorldCommands
var map: WorldMap
## Time stands still while this is true (pause menu, the evening screen). Solo only: in co-op the world goes on.
var paused := false
## Debug commands allowed (screenshots, automation: --debug-cheats or a debug build run from the editor).
var debug_cheats := false
## Show the main menu when the world scene starts (first launch; off for debug runs and after "Set sail").
var show_menu := true

var _tick_acc := 0.0


func _ready() -> void:
	_register_input()
	Net.command_received.connect(_on_remote_command)
	Net.events_received.connect(_emit_events)
	debug_cheats = OS.has_feature("editor") or "--debug-cheats" in OS.get_cmdline_user_args()
	show_menu = DisplayServer.get_name() != "headless"  # tests and servers never see the menu


func _process(delta: float) -> void:
	if state == null or not Net.is_authority() or (paused and not Net.is_online()):
		return
	_tick_acc += delta
	if _tick_acc >= TICK_S:
		_apply(Net.local_player_id(), {"type": "tick", "dt_min": _tick_acc / 60.0})
		_tick_acc = 0.0


func new_world(seed_value: int, mode: String = "", world_name: String = "", tuning: Dictionary = {}) -> void:
	state = WorldState.new(Content.db, seed_value, mode)
	state.name = world_name
	state.tuning = tuning.duplicate()
	_attach()
	state.add_player(Net.local_player_id(), map.home["spawn"])
	_emit_events(commands.init_world())


func load_world(dir: String) -> bool:
	var s := SaveCodec.load_world(Content.db, dir)
	if s == null:
		return false
	state = s
	_attach()
	state.add_player(Net.local_player_id(), map.home["spawn"])
	return true


func _attach() -> void:
	map = WorldMap.shared(Content.db)
	commands = WorldCommands.new(Content.db, state, map)
	commands.allow_debug = debug_cheats


## The one entry point for gameplay changes.
func submit(cmd: Dictionary) -> Dictionary:
	if not Net.is_authority():
		Net.send_command(cmd)
		return {"ok": true, "pending": true, "events": []}
	return _apply(Net.local_player_id(), cmd)


## "Would this pass?" against the local copy of the world, changing nothing and telling no one (the build
## mode's ghost). Co-op clients hold a replica, so they can ask too. For commands that accept "dry".
func check(cmd: Dictionary) -> Dictionary:
	if commands == null:
		return {"ok": false, "error": "unknown_command", "events": []}
	var c := cmd.duplicate()
	c["dry"] = true
	return commands.apply(Net.local_player_id(), c)


func _apply(pid: String, cmd: Dictionary) -> Dictionary:
	var res := commands.apply(pid, cmd)
	if res["ok"]:
		_emit_events(res["events"])
		Net.broadcast_events(res["events"])
	elif pid == Net.local_player_id():
		command_failed.emit(cmd, res["error"])
	return res


func _on_remote_command(pid: String, cmd: Dictionary) -> void:
	if String(cmd.get("type", "")) in WorldCommands.HOST_ONLY:
		return
	state.add_player(pid, map.home["spawn"])
	_apply(pid, cmd)


func _emit_events(events: Array) -> void:
	for e: Dictionary in events:
		world_event.emit(e)


## Where a world is saved: user://worlds/<name or seed>.
func world_dir(s: WorldState = null) -> String:
	var st := s if s != null else state
	var n := st.name.strip_edges().validate_filename() if st.name.strip_edges() != "" else "world_%d" % st.world_seed
	return "%s/%s" % [WORLDS_DIR, n]


func save() -> Error:
	if state == null:
		return ERR_UNCONFIGURED
	return SaveCodec.save_world(state, world_dir())


## The most recently saved world ({"dir", "name", "day", "mode"}), {} if there is none.
func last_world() -> Dictionary:
	var best := {}
	var best_t := -1
	var d := DirAccess.open(WORLDS_DIR)
	if d == null:
		return {}
	for sub in d.get_directories():
		var f := "%s/%s/world.json" % [WORLDS_DIR, sub]
		if not FileAccess.file_exists(f):
			continue
		var t := FileAccess.get_modified_time(f)
		if t > best_t:
			var s := SaveCodec.load_world(Content.db, "%s/%s" % [WORLDS_DIR, sub])
			if s != null:
				best_t = t
				best = {"dir": "%s/%s" % [WORLDS_DIR, sub], "name": s.name if s.name != "" else sub, "day": s.day, "mode": s.mode}
	return best


func _register_input() -> void:
	for action: String in MOUSE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_ACTIONS[action]
			InputMap.action_add_event(action, mb)
	for action: String in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in INPUT_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
