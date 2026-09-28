class_name LanternsTrial
extends Trial
## "Light three path lanterns through the fog" (b04, b08, b11; the sketch's second island): lanterns stand
## along the path; touching each with the torch lights it, rings a note (A4, C5, D5) and clears the fog
## around it. Three lit — the trial is passed.

## Where the lanterns stand on the path: [t along the path, metres to the side].
var spots: Array = [[0.3, 2.6], [0.56, -2.6], [0.8, 2.6]]
var lamps: Array = []  # [{"pos": Vector3, "lit": float (0 = dark, 0..1 kindling), "glass": MeshInstance3D, "light": OmniLight3D, "fire": Node3D}]
var _time := 0.0


func build() -> void:
	var dir: Vector2 = map.paths[bid]["dir"]
	for i in spots.size():
		var p := map.path_point(bid, float(spots[i][0]), float(spots[i][1]))
		var root := Node3D.new()
		root.position = p - Vector3(0, 0.1, 0)
		root.rotation.y = WorldMap.yaw_of(-dir) + (PI if i % 2 else 0.0)
		add_child(root)
		post(root, Vector3.ZERO, 2.2)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.9, 0.14, 0.14)
		arm.mesh = am
		arm.material_override = Placeholders.mat(Placeholders.DARK_WOOD)
		arm.position = Vector3(0.3, 2.1, 0)
		root.add_child(arm)
		var glass := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.32, 0.42, 0.32)
		glass.mesh = gm
		glass.material_override = Placeholders.mat(Color("3a3226"))
		glass.position = Vector3(0.62, 1.8, 0)
		root.add_child(glass)
		var light := OmniLight3D.new()
		light.light_color = Color("ffa84a")
		light.omni_range = 18.0
		light.light_energy = 0.0
		light.position = glass.position
		root.add_child(light)
		var fire := Placeholders.fire(0.12, false)
		fire.position = glass.position + Vector3(0, 0.1, 0)
		fire.visible = false
		root.add_child(fire)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 2.2
		cs.shape = shape
		cs.position = Vector3(0, 1.1, 0)
		body.add_child(cs)
		root.add_child(body)
		lamps.append({"pos": root.position + Vector3(0, 0.1, 0), "lit": 0.0, "glass": glass, "light": light, "fire": fire})


func lit_count() -> int:
	var n := 0
	for l: Dictionary in lamps:
		if float(l["lit"]) > 0.0:
			n += 1
	return n


func action(p: Vector3) -> Dictionary:
	if finished:
		return {}
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		if float(l["lit"]) > 0.0 or Vector2(p.x - (l["pos"] as Vector3).x, p.z - (l["pos"] as Vector3).z).length() > 3.0:
			continue
		if not has_light():
			return {"label": tr("act.need_fire"), "run": func() -> void: world.hud.toast(tr("goal.need_fire"))}
		return {"label": tr("act.lantern"), "run": light_lantern.bind(i)}
	return {}


func light_lantern(i: int) -> void:
	var l: Dictionary = lamps[i]
	if float(l["lit"]) > 0.0:
		return
	l["lit"] = 0.001
	(l["fire"] as Node3D).visible = true
	(l["glass"] as MeshInstance3D).material_override = Placeholders.mat(Color("3a2a1a"), Color("ffa84a"), 2.5, false)
	sfx("lantern", lit_count() - 1)
	if lit_count() >= lamps.size():
		complete()


func debug_solve(n: int) -> void:
	for i in mini(n, lamps.size()):
		light_lantern(i)


func goal() -> String:
	if lit_count() < lamps.size():
		return tr("goal.lanterns") % [lit_count(), lamps.size()]
	return tr("goal.climb")


func target() -> Dictionary:
	var p := player_pos()
	var best := {}
	var best_d := INF
	for l: Dictionary in lamps:
		if float(l["lit"]) > 0.0:
			continue
		var d := (l["pos"] as Vector3).distance_to(p)
		if d < best_d:
			best_d = d
			best = {"target": l["pos"], "label": tr("target.lantern")}
	return best


func fog_lights() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for l: Dictionary in lamps:
		var k := float(l["lit"])
		if k > 0.0:
			var p: Vector3 = l["pos"]
			out.append(Vector4(p.x, p.z, 24.0 * smoothstep(0.0, 1.0, k), 0.9 * k))
	return out


func tick(delta: float) -> void:
	_time += delta
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		if float(l["lit"]) > 0.0:
			l["lit"] = minf(1.0, float(l["lit"]) + delta / 1.2)
			(l["light"] as OmniLight3D).light_energy = (2.4 + 0.5 * sin(_time * 11.0 + i)) * float(l["lit"])
