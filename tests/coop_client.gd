extends SceneTree
## The second instance for test_coop (a separate Godot process): joins the host on localhost, gets the world,
## sends a few commands of its own (one the host must refuse) and keeps writing the MD5 of its copy of the
## world (SaveCodec.encode) to --out so the host can compare. Quits after --life seconds.

var _port := 0
var _out := ""
var _life := 60.0
var _t := 0.0
var _write := 0.0
var _sent := false
var _refused := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			_port = int(a.trim_prefix("--port="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--life="):
			_life = float(a.trim_prefix("--life="))
	var game: Node = root.get_node("Game")
	game.command_failed.connect(func(cmd: Dictionary, error: String) -> void: _refused = "%s:%s" % [cmd.get("type", ""), error])


func _process(delta: float) -> bool:
	if _t == 0.0:
		root.get_node("Net").join("127.0.0.1", _port)  # once the autoloads are in the tree
	_t += delta
	var game: Node = root.get_node("Game")
	if game.state != null:
		if not _sent and _t > 0.5:
			_sent = true
			var me: String = root.get_node("Net").local_player_id()
			var p: Vector3 = game.state.players[me]["pos"]
			game.submit({"type": "move", "pos": [p.x + 1.5, p.y, p.z + 0.5], "stance": "block"})
			game.submit({"type": "set_tuning", "rule": "storms", "value": "cosmetic"})
			game.submit({"type": "debug", "give": {"wood": 99}})  # host-only: refused
		_write -= delta
		if _write <= 0.0:
			_write = 0.2
			var f := FileAccess.open(_out, FileAccess.WRITE)
			if f != null:
				f.store_string("%s\n%s\n%s" % [SaveCodec.encode(game.state).md5_text(), root.get_node("Net").local_player_id(), _refused])
				f.close()
	return _t > _life
