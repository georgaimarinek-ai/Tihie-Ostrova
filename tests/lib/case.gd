extends RefCounted
## Base class for tests: tiny assertion helpers. A test file is tests/test_*.gd, a test is a method test_*.
## Tests are synchronous and must not depend on autoloads (the runner is a bare SceneTree).

var failures: PackedStringArray = []
var current := ""
var db: ContentDB


func before_each() -> void:
	db = ContentDB.shared()


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
