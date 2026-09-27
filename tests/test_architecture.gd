extends "res://tests/lib/case.gd"
## The rule that keeps co-op possible (CLAUDE.md, docs/04_TECH_SPEC.md §3): only WorldCommands writes the
## world. Views (src/world, src/ui, src/scenes) may read WorldState but never assign to it or mutate it; the
## gather, craft, move… all go through Game.submit(). src/core never touches nodes, Input or the tree.

const VIEW_DIRS: Array[String] = ["res://src/world", "res://src/ui", "res://src/scenes"]


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


func _code_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := line
		var hash := code.find("#")
		if hash >= 0:
			code = code.substr(0, hash)
		out.append(code)
	return out


func test_views_never_write_the_world() -> void:
	var writes := RegEx.new()
	# state.<field>[...] = / += / -=, and mutating calls on the state's containers or inventories
	writes.compile("\\bstate\\.[a-z_]+(\\[[^\\]]*\\])*\\s*(=[^=]|\\+=|-=)|\\bstate\\.(inv\\([^)]*\\)|[a-z_]+(\\[[^\\]]*\\])+)\\.(add|remove|remove_bag|erase|clear|append|from_dict|merge)\\(|\\bstate\\.(add_player|add_boat|new_uid)\\(|\\bstate\\.[a-z_]+\\.(erase|clear|merge)\\(")
	var files := 0
	for dir in VIEW_DIRS:
		for path in _scripts(dir):
			files += 1
			var n := 0
			for code in _code_lines(path):
				n += 1
				var m := writes.search(code)
				check(m == null, "%s:%d writes the world: %s" % [path.get_file(), n, code.strip_edges()])
	check(files > 10, "scanned the view scripts (%d)" % files)


func test_core_has_no_scene_dependencies() -> void:
	var bad := RegEx.new()
	bad.compile("\\b(get_tree|get_node|Input\\.|Engine\\.get_main_loop|Timer\\.new|add_child|Game\\.|Net\\.|Content\\.db)")
	for path in _scripts("res://src/core"):
		var n := 0
		for code in _code_lines(path):
			n += 1
			var m := bad.search(code)
			check(m == null, "%s:%d: core code must not use %s" % [path.get_file(), n, m.get_string() if m != null else ""])
