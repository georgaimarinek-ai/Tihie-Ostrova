extends "res://tests/lib/case.gd"
## Interface text only through translation keys that exist in both languages (CLAUDE.md, code style).


func _keys(path: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile('^msgid "(.+)"$')
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var m := re.search(line)
		if m != null:
			out[m.get_string(1)] = true
	return out


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


func test_both_languages_have_the_same_keys() -> void:
	var ru := _keys("res://i18n/ru.po")
	var en := _keys("res://i18n/en.po")
	check(ru.size() > 20, "ru.po loaded")
	eq(ru.keys(), en.keys())


func test_every_key_used_in_code_exists() -> void:
	var ru := _keys("res://i18n/ru.po")
	var re := RegEx.new()
	re.compile('(?:\\btr|Loc\\.t)\\("([a-z0-9_]+\\.[a-z0-9_.]+)"\\)')
	var used := 0
	for path in _scripts("res://src"):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used += 1
			check(ru.has(m.get_string(1)), "%s: missing key %s" % [path.get_file(), m.get_string(1)])
	check(used > 10, "found tr() calls (%d)" % used)


func test_every_command_error_has_a_message() -> void:
	var ru := _keys("res://i18n/ru.po")
	var re := RegEx.new()
	re.compile('_fail\\("([a-z_]+)"\\)|return "([a-z_]+)"')
	for path in ["res://src/core/world_commands.gd", "res://src/core/crafting.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var code := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
			check(ru.has("cmd." + code), "cmd.%s has no message" % code)
	for side in ["head", "beam", "tail"]:
		check(ru.has("wind." + side), "wind." + side)


func test_english_is_complete() -> void:
	var f := FileAccess.open("res://i18n/strings.tsv", FileAccess.READ)
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "" or line.begins_with("#") or line.begins_with("key\t"):
			continue
		var cols := line.split("\t")
		check(cols.size() >= 3 and cols[2].strip_edges() != "", "an English text for " + cols[0])
		n += 1
	check(n > 400, "all the strings (%d)" % n)
	for table: Dictionary in [db.items, db.pieces, db.boats, db.creatures, db.beacons, db.regions, db.modes]:
		for id: String in table:
			var name: Dictionary = table[id]["name"]
			check(String(name.get("en", "")) != "" and String(name.get("ru", "")) != "", "names in both languages: " + id)


func test_no_russian_text_hidden_in_code() -> void:
	var re := RegEx.create_from_string("\"[^\"]*[\\x{0400}-\\x{04FF}][^\"]*\"")
	for path in _scripts("res://src"):
		var f := FileAccess.open(path, FileAccess.READ)
		var i := 0
		while not f.eof_reached():
			var line := f.get_line()
			i += 1
			if line.strip_edges().begins_with("#"):
				continue
			check(re.search(line) == null, "%s:%d says it in Russian outside tr()" % [path, i])
