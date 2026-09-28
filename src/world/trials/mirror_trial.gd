class_name MirrorTrial
extends Trial
## "Turn the copper reflectors to aim the beam at the brazier" (b05, b09): a sun-stone shines along the path;
## three copper mirrors each turn in 45° steps (E). A mirror aimed at the next one (or, the last, at the
## brazier) passes the beam on. When the beam reaches the brazier the trial is passed.

const STEPS := 8

## [t along the path, side] for the sun-stone and the three mirrors.
var spots: Array = [[0.3, -3.0], [0.48, 3.0], [0.68, -3.0], [0.86, 2.5]]
var source := Vector3.ZERO
var mirrors: Array = []  # [{"pos": Vector3, "turn": int, "disc": Node3D}]
var beams: Array[MeshInstance3D] = []
var _beam_mat: ShaderMaterial


func build() -> void:
	_beam_mat = Placeholders.mat(Color("ffe2a8"), Color("ffd27a"), 3.0, false)
	source = map.path_point(bid, float(spots[0][0]), float(spots[0][1])) + Vector3(0, 1.2, 0)
	var stone := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	stone.mesh = sm
	stone.material_override = Placeholders.mat(Color("d9cbb0"), Color("ffd27a"), 2.2, false)
	stone.position = source
	add_child(stone)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(db.beacons[bid]["seed"]) * 17 + 3
	for i in range(1, spots.size()):
		var p := map.path_point(bid, float(spots[i][0]), float(spots[i][1]))
		var root := Node3D.new()
		root.position = p - Vector3(0, 0.1, 0)
		add_child(root)
		post(root, Vector3.ZERO, 1.2)
		var disc_root := Node3D.new()
		disc_root.position = Vector3(0, 1.5, 0)
		root.add_child(disc_root)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 0.06
		cm.radial_segments = 12
		disc.mesh = cm
		disc.rotation.x = PI * 0.5
		disc.material_override = Placeholders.mat(Color("c07a3a"))
		disc_root.add_child(disc)
		mirrors.append({"pos": p + Vector3(0, 1.4, 0), "turn": 0, "disc": disc_root})
	# start everything a few steps off from the answer
	for i in mirrors.size():
		mirrors[i]["turn"] = posmod(_answer(i) + 2 + rng.randi() % 5, STEPS)
	for i in mirrors.size() + 1:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 1.0)
		b.mesh = bm
		b.material_override = _beam_mat
		b.visible = false
		add_child(b)
		beams.append(b)
	_update_beams()


## The step at which mirror i points straight at its target (the next mirror, the last one at the brazier).
func _answer(i: int) -> int:
	var from: Vector3 = mirrors[i]["pos"]
	var to: Vector3 = fire_pos() if i == mirrors.size() - 1 else mirrors[i + 1]["pos"]
	var a := atan2(to.x - from.x, to.z - from.z)
	return posmod(roundi(a / (TAU / STEPS)), STEPS)


func aligned(i: int) -> bool:
	return int(mirrors[i]["turn"]) == _answer(i)


func aligned_count() -> int:
	var n := 0
	for i in mirrors.size():
		if aligned(i):
			n += 1
		else:
			break
	return n


func action(p: Vector3) -> Dictionary:
	if finished:
		return {}
	for i in mirrors.size():
		var m: Vector3 = mirrors[i]["pos"]
		if Vector2(p.x - m.x, p.z - m.z).length() < 2.6:
			return {"label": tr("act.mirror"), "run": turn.bind(i)}
	return {}


func turn(i: int) -> void:
	mirrors[i]["turn"] = (int(mirrors[i]["turn"]) + 1) % STEPS
	sfx("pickup", i)
	_update_beams()
	if aligned_count() == mirrors.size():
		sfx("lantern", 2)
		complete()


func _update_beams() -> void:
	for i in mirrors.size():
		var d := mirrors[i]["disc"] as Node3D
		d.rotation.y = int(mirrors[i]["turn"]) * TAU / STEPS
	# the beam: sun-stone → mirror 1 always; each aligned mirror passes it on
	_segment(0, source, mirrors[0]["pos"])
	var n := aligned_count()
	for i in mirrors.size():
		var from: Vector3 = mirrors[i]["pos"]
		if i < n:
			var to: Vector3 = fire_pos() if i == mirrors.size() - 1 else mirrors[i + 1]["pos"]
			_segment(i + 1, from, to)
		elif i == n:
			var a := int(mirrors[i]["turn"]) * TAU / STEPS
			_segment(i + 1, from, from + Vector3(sin(a), 0, cos(a)) * 6.0)
		else:
			beams[i + 1].visible = false


func _segment(i: int, a: Vector3, b: Vector3) -> void:
	var beam := beams[i]
	beam.visible = true
	var mid := (a + b) * 0.5
	beam.position = mid
	beam.scale = Vector3(1, 1, a.distance_to(b))
	if not a.is_equal_approx(b):
		beam.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)


func debug_solve(n: int) -> void:
	for i in mini(n, mirrors.size()):
		while not aligned(i):
			turn(i)


func goal() -> String:
	return tr("goal.mirror") % [aligned_count(), mirrors.size()]


func target() -> Dictionary:
	var n := aligned_count()
	if n < mirrors.size():
		return {"target": mirrors[n]["pos"], "label": tr("target.mirror")}
	return {}
