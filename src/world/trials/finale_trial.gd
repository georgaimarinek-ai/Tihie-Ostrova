class_name FinaleTrial
extends Trial
## "All trials in a row under the aurora" (b12, the Lodestar): lanterns up the path, then the bells, the
## mirrors and the climb to the brazier, one after another. Each part is a trial of its own that reports
## back here instead of to the host; the last one sends the command.

var parts: Array[Trial] = []
var current := 0


func build() -> void:
	var lanterns := LanternsTrial.new()
	lanterns.spots = [[0.15, 2.6], [0.28, -2.6], [0.4, 2.6]]
	var mirror := MirrorTrial.new()
	mirror.spots = [[0.5, -3.0], [0.62, 3.0], [0.74, -3.0], [0.86, 3.0]]
	for t: Trial in [lanterns, BellsTrial.new(), mirror, ClimbTrial.new()]:
		t.world = world
		t.db = db
		t.map = map
		t.bid = bid
		t.kind = kind
		add_child(t)
		t.build()
		t.set_meta("finale", true)
		t.done.connect(_part_done)
		parts.append(t)


## Parts don't talk to the host: they call this instead (Trial.complete checks the "finale" meta).
func part_complete(t: Trial) -> void:
	t.finished = true
	t.done.emit()


func _part_done() -> void:
	current += 1
	sfx("swell")
	if current >= parts.size():
		complete()


func _active() -> Trial:
	return parts[current] if current < parts.size() else null


func action(p: Vector3) -> Dictionary:
	var t := _active()
	return t.action(p) if t != null else {}


func goal() -> String:
	var t := _active()
	if t == null:
		return tr("goal.climb")
	return tr("goal.finale") % [current + 1, parts.size(), t.goal()]


func target() -> Dictionary:
	var t := _active()
	return t.target() if t != null else {}


func fog_lights() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for t in parts:
		out.append_array(t.fog_lights())
	return out


func tick(delta: float) -> void:
	var t := _active()
	if t != null:
		t.tick(delta)
	for other in parts:
		if other != t and other is LanternsTrial:
			other.tick(delta)  # lit lanterns keep burning
