extends Node
## Autoload "Net": co-op transport (docs/04_TECH_SPEC.md §7, roadmap phase 9). No game logic lives here: it
## carries commands to the host and the host's applied commands back to everyone.
##
## - peer id 1 is the host; player ids are "p<peer_id>";
## - a client sends its commands with send_command(); the host applies them (WorldCommands) and, when they pass,
##   sends {pid, cmd} to every client (broadcast_applied), which replays it on its own copy of the world — the
##   same deterministic rules give the same world and the same events everywhere;
## - a joining client gets the whole world once (send_snapshot, SaveCodec.snapshot) and builds the islands itself;
## - a command the host refuses comes back to its sender (send_failed) so the UI can say why.

signal command_received(pid: String, cmd: Dictionary)
signal applied_received(pid: String, cmd: Dictionary)
signal snapshot_received(bytes: PackedByteArray)
signal failed_received(cmd: Dictionary, error: String)
signal peer_joined(pid: String)
signal peer_left(pid: String)
signal connected
signal connection_failed
signal server_lost

const PORT := 24650
const MAX_PLAYERS := 4

var peers: Array[String] = []  # connected players other than this one (host: clients; client: the host)


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void:
		var pid := "p%d" % id
		if not peers.has(pid):
			peers.append(pid)
		peer_joined.emit(pid))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		peers.erase("p%d" % id)
		peer_left.emit("p%d" % id))
	multiplayer.connected_to_server.connect(func() -> void: connected.emit())
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		server_lost.emit())


func is_online() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func is_authority() -> bool:
	return not is_online() or multiplayer.is_server()


func is_client() -> bool:
	return is_online() and not multiplayer.is_server()


func local_player_id() -> String:
	return "p%d" % (multiplayer.get_unique_id() if is_online() else 1)


func host(port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		peers.clear()
	return err


func join(address: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		peers.clear()
	return err


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers.clear()


## The addresses friends can join (for the lobby: IPv4, local network first).
func addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# ---------------------------------------------------------------- the three messages

func send_command(cmd: Dictionary) -> void:
	_rpc_command.rpc_id(1, cmd)


func broadcast_applied(pid: String, cmd: Dictionary) -> void:
	if is_online() and multiplayer.is_server():
		_rpc_applied.rpc(pid, cmd)


func send_snapshot(pid: String, bytes: PackedByteArray) -> void:
	_rpc_snapshot.rpc_id(int(pid.trim_prefix("p")), bytes)


func send_failed(pid: String, cmd: Dictionary, error: String) -> void:
	if is_online() and pid != local_player_id():
		_rpc_failed.rpc_id(int(pid.trim_prefix("p")), cmd, error)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	command_received.emit("p%d" % multiplayer.get_remote_sender_id(), cmd)


@rpc("authority", "call_remote", "reliable")
func _rpc_applied(pid: String, cmd: Dictionary) -> void:
	applied_received.emit(pid, cmd)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	snapshot_received.emit(bytes)


@rpc("authority", "call_remote", "reliable")
func _rpc_failed(cmd: Dictionary, error: String) -> void:
	failed_received.emit(cmd, error)
