class_name HomeView
extends Node3D
## The home island's homestead (WorldMap.home): the izba with its warm windows and chimney smoke, the
## pier, a pomor cross on the point. The hearth inside clears the fog around the house (FogDirector
## extra light, like the sketch's BEACONS[1]).

var map: WorldMap
var izba: Node3D
var hearth_light := Vector4.ZERO

var _time := 0.0
var _window: OmniLight3D


func setup(p_map: WorldMap) -> void:
	map = p_map
	name = "Home"
	var h := map.home
	izba = ModelLibrary.instance("props", "izba")
	izba.position = h["izba"] - Vector3(0, 0.1, 0)
	izba.rotation.y = float(h["yaw"])
	add_child(izba)
	_window = izba.get_node_or_null("WindowLight")
	var pier := ModelLibrary.instance("props", "pier")
	pier.position = h["pier"]
	pier.rotation.y = float(h["yaw"])
	add_child(pier)
	var cross := ModelLibrary.instance("props", "pomor_cross")
	cross.position = (h["cross"] as Vector3) - Vector3(0, 0.2, 0)
	cross.rotation.y = float(h["yaw"]) + 0.4
	add_child(cross)
	var chimney := izba.get_node_or_null("Chimney") as Node3D
	if chimney != null:
		chimney.add_child(_smoke())
	var ip: Vector3 = h["izba"]
	hearth_light = Vector4(ip.x, ip.z, 34.0, 0.8)
	var col := StaticBody3D.new()
	col.name = "IzbaBody"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.0, 3.2, 5.6)
	cs.shape = box
	cs.position = Vector3(0, 1.6, 0)
	col.add_child(cs)
	izba.add_child(col)


func _process(delta: float) -> void:
	_time += delta
	if _window != null:
		_window.light_energy = 1.3 + 0.2 * sin(_time * 7.0) + 0.1 * randf()


func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	p.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/shaders/smoke.gdshader")
	p.material_override = m
	p.amount = 14
	p.lifetime = 6.0
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 10.0
	p.gravity = Vector3(0.5, 0.4, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 4.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.6, 0.32))
	ramp.set_color(1, Color(0.7, 0.7, 0.68, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	return p
