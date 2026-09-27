extends RefCounted
## Base class for tests: tiny assertion helpers. A test file is tests/test_*.gd, a test is a method test_*.
## Tests must not depend on autoloads. Scene tests (one SceneTree argument) may add nodes and await frames.

var failures: PackedStringArray = []
var current := ""
var db: ContentDB


func before_each() -> void:
	db = ContentDB.shared()


## Scene tests add nodes here; they are freed after the test.
var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()


func add(tree: SceneTree, n: Node) -> Node:
	tree.root.add_child(n)
	nodes.append(n)
	return n


func frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	var same_kind := typeof(actual) == typeof(expected) or (typeof(actual) in numeric and typeof(expected) in numeric)
	if not same_kind or actual != expected:
		failures.append("%s: expected %s, got %s %s" % [current, var_to_str(expected), var_to_str(actual), msg])


func near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: expected %.4f ± %.4f, got %.4f %s" % [current, expected, tol, actual, msg])


## A fresh world with one player standing at `pos`.
func new_world(mode: String = "quiet", pos: Vector3 = Vector3.ZERO) -> WorldCommands:
	var st := WorldState.new(db, 7, mode)
	st.add_player("p1", pos)
	return WorldCommands.new(db, st)
