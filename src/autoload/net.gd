extends Node
## Autoload "Net": co-op transport. Phase 0: solo only, the API is fixed so gameplay code never changes
## when co-op arrives (docs/04_TECH_SPEC.md §7, roadmap phase 9).
##
## Rules that keep the game co-op-ready from day one:
## - gameplay code asks is_authority() and never mutates WorldState except through Game.submit();
## - clients send commands with send_command(); the host applies them and broadcasts events;
## - peer id 1 is the host; player ids are "p<peer_id>".

signal command_received(pid: String, cmd: Dictionary)
signal events_received(events: Array)

const PORT := 24650
const MAX_PLAYERS := 4


func is_online() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func is_authority() -> bool:
	return not is_online() or multiplayer.is_server()


func local_player_id() -> String:
	return "p%d" % (multiplayer.get_unique_id() if is_online() else 1)


func host(port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func join(address: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func send_command(cmd: Dictionary) -> void:
	_rpc_command.rpc_id(1, cmd)


func broadcast_events(events: Array) -> void:
	if is_online():
		_rpc_events.rpc(events)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	command_received.emit("p%d" % multiplayer.get_remote_sender_id(), cmd)


@rpc("authority", "call_remote", "reliable")
func _rpc_events(events: Array) -> void:
	events_received.emit(events)
