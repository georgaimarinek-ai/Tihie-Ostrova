class_name BeaconView
extends Node3D
## A beacon tower on its island (beacons.json): dark until lit, then the fire kindles over
## FogDirector.GROW_S seconds while the clearing grows. The next beacon to light carries the hint light,
## a pale will-o'-wisp that flickers over the brazier and reads through the fog (docs/01_GDD.md §5.1).

var bid := ""
var db: ContentDB
var tower: Node3D
var fire: Node3D
var halo: MeshInstance3D
var hint: MeshInstance3D
var fire_pos := Vector3.ZERO
var lit := 0.0  # 0 = dark, 0..1 kindling, 1 = burning
var night := 0.0

var _time := 0.0
var _light: OmniLight3D


func setup(p_db: ContentDB, map: WorldMap, p_bid: String) -> void:
	db = p_db
	bid = p_bid
	name = "Beacon_" + bid
	var p := db.beacon_pos(bid)
	var isl: IslandGen = map.by_id[bid]
	position = Vector3(p.x, isl.height_at(p.x, p.y) - 0.3, p.y)
	var towards: Dictionary = map.paths.get(bid, {})
	if not towards.is_empty():
		rotation.y = WorldMap.yaw_of(-(towards["dir"] as Vector2))  # ladder side faces the path
	tower = ModelLibrary.instance("props", "beacon_tower")
	add_child(tower)
	var anchor := tower.get_node_or_null("Fire") as Node3D
	var local_fire := anchor.position if anchor != null else Vector3(0, 11.2, 0)
	fire = Placeholders.fire(1.0, true)
	fire.position = local_fire
	fire.visible = false
	add_child(fire)
	_light = fire.get_node("Light")
	_light.omni_range = 90.0
	_light.light_energy = 0.0
	halo = Placeholders.glow(Color("ff9a40"), 24.0, 0.0)
	halo.position = local_fire + Vector3(0, 0.6, 0)
	add_child(halo)
	hint = Placeholders.glow(Color("bfe6ff"), 9.0, 0.6)
	hint.position = local_fire + Vector3(0, 1.2, 0)
	hint.visible = false
	add_child(hint)
	fire_pos = to_global(local_fire) if is_inside_tree() else position + local_fire


func _ready() -> void:
	fire_pos = fire.global_position


## Start kindling (instant = already burning, e.g. on load).
func kindle(instant: bool = false) -> void:
	if instant:
		lit = 1.0
	elif lit <= 0.0:
		lit = 0.001
	fire.visible = true


func set_hint(on: bool) -> void:
	hint.visible = on and lit == 0.0


func _process(delta: float) -> void:
	_time += delta
	if hint.visible:
		hint.position.y = fire.position.y + 1.2 + sin(_time * 1.5) * 0.6
		(hint.material_override as ShaderMaterial).set_shader_parameter("strength", 0.45 + 0.25 * sin(_time * 2.2))
	if lit <= 0.0:
		return
	lit = minf(1.0, lit + delta / FogDirector.GROW_S)
	var flick := 1.0 + 0.25 * sin(_time * 17.0) + 0.15 * randf()
	_light.light_energy = 9.0 * lit * flick * (1.0 - 0.45 * night)
	fire.scale = Vector3.ONE * (0.4 + 0.6 * lit)
	(halo.material_override as ShaderMaterial).set_shader_parameter("strength", lit * (0.25 + 0.45 * night) * (0.9 + 0.1 * sin(_time * 9.0)))
