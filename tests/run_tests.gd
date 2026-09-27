extends SceneTree
## Headless test runner, no add-ons needed:
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=inventory]
## Runs every method test_* in every tests/test_*.gd. Exit code 1 if anything fails.
## Run `godot --headless --path . --import` once on a fresh checkout so class_name scripts are registered.

func _initialize() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not compile" % f)
			failed += 1
			continue
		for m: Dictionary in script.get_script_method_list():
			var name := String(m["name"])
			if not name.begins_with("test_"):
				continue
			var full := "%s.%s" % [f.get_basename(), name]
			if filter != "" and not full.contains(filter):
				continue
			var t: Variant = script.new()
			t.current = full
			t.before_each()
			t.call(name)
			total += 1
			if t.failures.is_empty():
				print("ok   ", full)
			else:
				failed += 1
				for msg in t.failures:
					print("FAIL ", msg)
	print("\ntests: %d, failed: %d" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
