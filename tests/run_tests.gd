extends SceneTree
## Headless test runner, no add-ons needed:
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=inventory]
## Runs every method test_* in every tests/test_*.gd. Exit code 1 if anything fails.
## A test that takes one argument is a scene test: it gets this SceneTree, may add nodes to `root` and
## `await tree.physics_frame`. Pass --fixed-fps 60 (tools/verify.sh does) so simulated seconds do not
## take real seconds.
## Run `godot --headless --path . --import` once on a fresh checkout so class_name scripts are registered.

func _initialize() -> void:
	await process_frame  # the root enters the tree on the first frame
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
			if (m["args"] as Array).size() == 1:
				await t.call(name, self)
			else:
				t.call(name)
			t.after_each()
			total += 1
			if t.failures.is_empty():
				print("ok   ", full)
			else:
				failed += 1
				for msg in t.failures:
					print("FAIL ", msg)
	print("\ntests: %d, failed: %d (%.1f s)" % [total, failed, Time.get_ticks_msec() / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)
