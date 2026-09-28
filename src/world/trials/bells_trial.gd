class_name BellsTrial
extends Trial
## "Ring the bells in the order they sound from the fog" (b03, b07): four bells hang around the tower, each
## a note of the mode (A4, C5, D5, F5). Near the tower the melody plays from the fog; strike the bells in the
## same order. A slip is no failure: listen again and start over.

const NOTES: Array[int] = [69, 72, 74, 77]

var bells: Array = []  # [{"pos": Vector3, "bell": Node3D, "glow": float}]
var melody: Array[int] = []
var heard := false
var step := 0
var _playing: Array = []  # [[time, bell index]]
var _time := 0.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(db.beacons[bid]["seed"]) * 31 + 7
	var length := 3 + mini(2, ContentDB.REGION_ORDER.find(String(db.beacons[bid]["region"])))
	for i in length:
		var n := rng.randi() % NOTES.size()
		if i > 0 and n == melody[i - 1]:
			n = (n + 1) % NOTES.size()
		melody.append(n)
	var center := tower_base()
	var dir: Vector2 = map.paths[bid]["dir"]
	var face := dir.angle()
	for i in NOTES.size():
		var a := face + (i - 1.5) * 0.55
		var p2 := Vector2(center.x, center.z) + Vector2.from_angle(a) * 7.0
		var isl: IslandGen = map.by_id[bid]
		var p := Vector3(p2.x, isl.height_at(p2.x, p2.y), p2.y)
		var root := Node3D.new()
		root.position = p - Vector3(0, 0.1, 0)
		root.rotation.y = -a
		add_child(root)
		post(root, Vector3(-0.8, 0, 0), 2.4)
		post(root, Vector3(0.8, 0, 0), 2.4)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.9, 0.16, 0.16)
		beam.mesh = bm
		beam.material_override = Placeholders.mat(Placeholders.DARK_WOOD)
		beam.position = Vector3(0, 2.4, 0)
		root.add_child(beam)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 2.3, 0)
		root.add_child(pivot)
		var bell := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18 + i * 0.02
		cyl.bottom_radius = 0.34 + i * 0.04
		cyl.height = 0.5 + i * 0.05
		cyl.radial_segments = 8
		bell.mesh = cyl
		bell.position = Vector3(0, -0.35, 0)
		var m := Placeholders.mat(Color("a97a3a"), Color("ffc070"), 0.0).duplicate() as ShaderMaterial
		bell.material_override = m
		pivot.add_child(bell)
		bells.append({"pos": p, "pivot": pivot, "bell": bell, "glow": 0.0})


func action(p: Vector3) -> Dictionary:
	if finished or not _playing.is_empty():
		return {}
	var t := tower_base()
	for i in bells.size():
		var b: Dictionary = bells[i]
		if Vector2(p.x - (b["pos"] as Vector3).x, p.z - (b["pos"] as Vector3).z).length() < 2.6:
			if not heard:
				return {"label": tr("act.listen"), "run": listen}
			return {"label": tr("act.strike") % [step, melody.size()], "run": strike.bind(i)}
	if Vector2(p.x - t.x, p.z - t.z).length() < 5.0:
		return {"label": tr("act.listen"), "run": listen}
	return {}


## The melody sounds from the fog, each bell swinging with its note.
func listen() -> void:
	_playing.clear()
	for i in melody.size():
		_playing.append([_time + 0.4 + i * 0.9, melody[i]])
	heard = true
	step = 0


func strike(i: int) -> void:
	_ring(i)
	if i == melody[step]:
		step += 1
		if step >= melody.size():
			complete()
	else:
		world.hud.toast(tr("toast.bells_wrong"))
		step = 0
		heard = false


func _ring(i: int) -> void:
	bells[i]["glow"] = 1.0
	sfx("bell", NOTES[i])


func debug_solve(n: int) -> void:
	listen()
	for i in mini(n, melody.size()):
		strike(melody[i])


func goal() -> String:
	if not heard:
		return tr("goal.bells_listen")
	return tr("goal.bells") % [step, melody.size()]


func tick(delta: float) -> void:
	_time += delta
	# the first time the player comes up to the tower the bells play by themselves
	if not heard and _playing.is_empty() and not finished:
		var p := player_pos()
		var t := tower_base()
		if Vector2(p.x - t.x, p.z - t.z).length() < 14.0:
			listen()
	while not _playing.is_empty() and float(_playing[0][0]) <= _time:
		_ring(int(_playing[0][1]))
		_playing.pop_front()
	for b: Dictionary in bells:
		var g := float(b["glow"])
		if g > 0.0:
			g = maxf(0.0, g - delta * 0.8)
			b["glow"] = g
			(b["pivot"] as Node3D).rotation.z = sin(_time * 9.0) * 0.35 * g
			var m := (b["bell"] as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("emission_energy", 2.0 * g)
			m.set_shader_parameter("fogged", g < 0.05)
