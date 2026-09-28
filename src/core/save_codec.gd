class_name SaveCodec
extends RefCounted
## World saves: user://worlds/<name>/world.json plus rotating backups world.1.json .. world.3.json.
## Writes go to a temp file first and are renamed, so a crash never leaves a half-written save.

const BACKUPS := 3

## Which file the last load_world() came from: 0 = world.json, 1..BACKUPS = a backup (the UI says so), -1 = none.
static var last_restored := -1


static func encode(state: WorldState) -> String:
	return JSON.stringify(state.to_dict(), "\t", false, true)  # full precision: co-op copies must match exactly


## The world for a joining co-op client: binary, so every double arrives bit for bit (JSON text doesn't
## round-trip the last digit, and the copies must stay identical).
static func snapshot(state: WorldState) -> PackedByteArray:
	return var_to_bytes(state.to_dict())


static func from_snapshot(db: ContentDB, bytes: PackedByteArray) -> WorldState:
	var d: Variant = bytes_to_var(bytes)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	return WorldState.from_dict(db, d)


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
	last_restored = -1
	var candidates: Array[String] = [dir.path_join("world.json")]
	for i in range(1, BACKUPS + 1):
		candidates.append(dir.path_join("world.%d.json" % i))
	for i in candidates.size():
		var path := candidates[i]
		if not FileAccess.file_exists(path):
			continue
		var s := decode(db, FileAccess.get_file_as_string(path))
		if s != null:
			last_restored = i
			return s
		push_warning("SaveCodec: %s is unreadable, trying a backup" % path)
	return null


## How many backups a world has on disk (the evening screen says "saved · 3 backups").
static func backups(dir: String) -> int:
	var n := 0
	for i in range(1, BACKUPS + 1):
		if FileAccess.file_exists(dir.path_join("world.%d.json" % i)):
			n += 1
	return n


## Every saved world under `root` (a slot per folder), newest first:
## [{"dir", "name", "day", "mode", "lit", "time": unix seconds}].
static func list_worlds(db: ContentDB, root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for sub in d.get_directories():
		var dir := root.path_join(sub)
		var f := dir.path_join("world.json")
		var t := FileAccess.get_modified_time(f) if FileAccess.file_exists(f) else 0
		var s := load_world(db, dir)
		if s == null:
			continue
		out.append({"dir": dir, "name": s.name if s.name != "" else sub, "day": s.day, "mode": s.mode, "lit": s.lit.size(), "time": t})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["time"]) > int(b["time"]))
	last_restored = -1
	return out


## Deletes a world slot (its folder and every backup).
static func delete_world(dir: String) -> Error:
	var d := DirAccess.open(dir)
	if d == null:
		return ERR_FILE_NOT_FOUND
	for f in d.get_files():
		d.remove(f)
	return DirAccess.remove_absolute(dir)
