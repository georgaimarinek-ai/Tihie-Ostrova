class_name SaveCodec
extends RefCounted
## World saves: user://worlds/<name>/world.json plus rotating backups world.1.json .. world.3.json.
## Writes go to a temp file first and are renamed, so a crash never leaves a half-written save.

const BACKUPS := 3


static func encode(state: WorldState) -> String:
	return JSON.stringify(state.to_dict(), "\t", false)


static func decode(db: ContentDB, text: String) -> WorldState:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return null
	return WorldState.from_dict(db, json.data)


static func save_world(state: WorldState, dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return err
	var main := dir.path_join("world.json")
	# rotate backups: world.2 -> world.3, world.1 -> world.2, world -> world.1
	for i in range(BACKUPS - 1, 0, -1):
		var from := dir.path_join("world.%d.json" % i)
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(from, dir.path_join("world.%d.json" % (i + 1)))
	if FileAccess.file_exists(main):
		DirAccess.copy_absolute(main, dir.path_join("world.1.json"))
	var tmp := dir.path_join("world.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(encode(state))
	f.close()
	return DirAccess.rename_absolute(tmp, main)


## Loads world.json, falling back to the newest readable backup.
static func load_world(db: ContentDB, dir: String) -> WorldState:
	var candidates: Array[String] = [dir.path_join("world.json")]
	for i in range(1, BACKUPS + 1):
		candidates.append(dir.path_join("world.%d.json" % i))
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var s := decode(db, FileAccess.get_file_as_string(path))
		if s != null:
			return s
		push_warning("SaveCodec: %s is unreadable, trying a backup" % path)
	return null
