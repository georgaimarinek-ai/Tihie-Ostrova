extends Node
## Autoload "Game": owns the WorldState and routes commands (docs/04_TECH_SPEC.md §3).
## Views listen to world_event and update themselves; they never change the state directly.

signal world_event(event: Dictionary)
signal command_failed(cmd: Dictionary, error: String)

const INPUT_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "build_menu": [KEY_B],
	"inventory": [KEY_TAB], "map": [KEY_M], "pause": [KEY_ESCAPE],
}

var state: WorldState
var commands: WorldCommands


func _ready() -> void:
	_register_input()
	Net.command_received.connect(_on_remote_command)
	Net.events_received.connect(_emit_events)


func new_world(seed_value: int, mode: String = "") -> void:
	state = WorldState.new(Content.db, seed_value, mode)
	commands = WorldCommands.new(Content.db, state)
	state.add_player(Net.local_player_id())


func load_world(dir: String) -> bool:
	var s := SaveCodec.load_world(Content.db, dir)
	if s == null:
		return false
	state = s
	commands = WorldCommands.new(Content.db, state)
	state.add_player(Net.local_player_id())
	return true


## The one entry point for gameplay changes.
func submit(cmd: Dictionary) -> Dictionary:
	if not Net.is_authority():
		Net.send_command(cmd)
		return {"ok": true, "pending": true, "events": []}
	return _apply(Net.local_player_id(), cmd)


func _apply(pid: String, cmd: Dictionary) -> Dictionary:
	var res := commands.apply(pid, cmd)
	if res["ok"]:
		_emit_events(res["events"])
		Net.broadcast_events(res["events"])
	elif pid == Net.local_player_id():
		command_failed.emit(cmd, res["error"])
	return res


func _on_remote_command(pid: String, cmd: Dictionary) -> void:
	state.add_player(pid)
	_apply(pid, cmd)


func _emit_events(events: Array) -> void:
	for e: Dictionary in events:
		world_event.emit(e)


func _register_input() -> void:
	for action: String in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in INPUT_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
