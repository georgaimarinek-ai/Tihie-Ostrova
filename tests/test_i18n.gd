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
