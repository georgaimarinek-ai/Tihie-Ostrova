class_name FogDirector
extends Node
## Feeds the fog and sky every frame (docs/04_TECH_SPEC.md §5):
## - palette of the region under the camera, blended across ring borders (regions.json chapters);
## - fog_clear_0..3 shader globals: extra lights (lantern, hearth) + nearest lit beacons (FogField);
## - newly lit beacons grow their clearing over GROW_S seconds (the "fog rolls back" moment).

const GROW_S := 3.5
const BLEND_M := 150.0  # palette blend width across a region border

var db: ContentDB
var state: WorldState
var environment: Environment
var sun: DirectionalLight3D
var extra_lights: Array[Vector4] = []  # player lantern, home hearth: Vector4(x, z, radius, strength)

var _lit_at: Dictionary = {}  # beacon id -> time it was lit (for the growth animation)
var _time := 0.0
var palette: Dictionary = {}


## Start the clearing's growth animation now (or at `at`, on this node's clock: a time far in the past = fully grown).
func mark_lit(beacon_id: String, at: float = NAN) -> void:
	_lit_at[beacon_id] = _time if is_nan(at) else at


func _process(delta: float) -> void:
	_time += delta
	if db == null or state == null:
		return
	var cam := get_viewport().get_camera_3d()
	var p := Vector2.ZERO if cam == null else Vector2(cam.global_position.x, cam.global_position.z)
	palette = palette_at(p)
	var fog_col: Color = palette["fog"]
	var lin := fog_col.srgb_to_linear()
	RenderingServer.global_shader_parameter_set("fog_color", Vector4(lin.r, lin.g, lin.b, 1.0))
	var dens := float(palette["density"])
	var rid := db.region_at(p)
	if not db.region_open(rid, state.lit):
		dens = float(db.regions[rid]["fog"]["locked"])
	RenderingServer.global_shader_parameter_set("fog_density", dens)
	var slots := FogField.shader_slots(db, state, p, extra_lights, _beacon_lights())
	for i in FogField.SLOTS:
		RenderingServer.global_shader_parameter_set("fog_clear_%d" % i, slots[i])
	_apply_sky()


## Lit beacons with the growth animation applied to the radius.
func _beacon_lights() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for bid: String in state.lit:
		var b: Dictionary = db.beacons[bid]
		var pos := db.beacon_pos(bid)
		var grow := 1.0
		if _lit_at.has(bid):
			grow = smoothstep(0.0, GROW_S, _time - float(_lit_at[bid]))
		out.append(Vector4(pos.x, pos.y, float(b["clear_radius"]) * grow, 0.95 * grow))
	return out


## Region chapter colours at a point, blended over BLEND_M metres around each ring border.
func palette_at(p: Vector2) -> Dictionary:
	var d := p.length()
	var order := ContentDB.REGION_ORDER
	var idx := 0
	for i in order.size():
		if d >= float(db.regions[order[i]]["ring_m"][0]):
			idx = i
	var a := _chapter(order[idx])
	if idx + 1 < order.size():
		var border := float(db.regions[order[idx + 1]]["ring_m"][0])
		var k := smoothstep(border - BLEND_M, border + BLEND_M, d)
		if k > 0.0:
			return _mix(a, _chapter(order[idx + 1]), k)
	if idx > 0:
		var border := float(db.regions[order[idx]]["ring_m"][0])
		var k := smoothstep(border - BLEND_M, border + BLEND_M, d)
		if k < 1.0:
			return _mix(_chapter(order[idx - 1]), a, k)
	return a


func _chapter(rid: String) -> Dictionary:
	var r: Dictionary = db.regions[rid]
	var c: Dictionary = r["chapter"]
	return {
		"fog": Color(c["fog"]), "zenith": Color(c["zenith"]), "sun": Color(c["sun"]),
		"sun_energy": float(c["sun_energy"]), "sun_elevation": float(c["sun_elevation"]),
		"sea_deep": Color(c["sea_deep"]), "sea_shallow": Color(c["sea_shallow"]),
		"night": float(c["night"]), "aurora": float(c["aurora"]), "density": float(r["fog"]["density"]),
	}


func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key: String in a:
		if a[key] is Color:
			out[key] = (a[key] as Color).lerp(b[key], k)
		else:
			out[key] = lerpf(a[key], b[key], k)
	return out


func _apply_sky() -> void:
	if environment != null and environment.sky != null and environment.sky.sky_material is ShaderMaterial:
		var sm := environment.sky.sky_material as ShaderMaterial
		sm.set_shader_parameter("horizon", palette["fog"])
		sm.set_shader_parameter("zenith", palette["zenith"])
		sm.set_shader_parameter("sun_color", palette["sun"])
		sm.set_shader_parameter("night", palette["night"])
		sm.set_shader_parameter("aurora", palette["aurora"])
		sm.set_shader_parameter("time", _time)
	elif environment != null and environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
		var m := environment.sky.sky_material as ProceduralSkyMaterial
		m.sky_top_color = palette["zenith"]
		m.sky_horizon_color = palette["fog"]
		m.ground_horizon_color = palette["fog"]
		m.ground_bottom_color = (palette["fog"] as Color).darkened(0.35)
	if sun != null:
		sun.light_color = palette["sun"]
		sun.light_energy = palette["sun_energy"]
		sun.rotation = Vector3(-asin(clampf(palette["sun_elevation"], 0.02, 1.0)) - 0.25, deg_to_rad(147.0), 0.0)
		var to_sun := sun.global_transform.basis.z.normalized()
		RenderingServer.global_shader_parameter_set("sun_dir", to_sun)
		var sc := (palette["sun"] as Color).srgb_to_linear()
		var k := 0.55 * float(palette["sun_energy"]) * (1.0 - 0.6 * float(palette["night"]))
		RenderingServer.global_shader_parameter_set("sun_glint", Vector4(sc.r * k, sc.g * k, sc.b * k, 1.0))
