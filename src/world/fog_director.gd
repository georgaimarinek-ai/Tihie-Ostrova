class_name FogDirector
extends Node
## Feeds the fog and sky every frame (docs/04_TECH_SPEC.md §5):
## - palette of the region under the camera, blended across ring borders (regions.json chapters);
## - fog_clear_0..3 shader globals: extra lights (lantern, hearth) + nearest lit beacons (FogField);
## - newly lit beacons grow their clearing over GROW_S seconds (the "fog rolls back" moment).

const GROW_S := 3.5
const BLEND_M := 150.0  # palette blend width across a region border
const NIGHT_FOG := Color("1a2230")  # what the fog darkens to at night where the chapter itself isn't a night
const NIGHT_SKY := Color("070b14")

var db: ContentDB
var state: WorldState
var environment: Environment
var sun: DirectionalLight3D
var extra_lights: Array[Vector4] = []  # player lantern, home hearth: Vector4(x, z, radius, strength)
## The Mga clings to land: ×2.3 on foot on an island whose beacon is dark, ×1.2 at home (GDD §4.2, the
## sketch's fogBoost). World sets the target; the density eases towards it.
var boost_target := 1.0
var boost := 1.0

## Layer 2 (docs/04_TECH_SPEC.md §5): volumetric fog on high quality in Forward+ only, with a FogVolume of
## negative density carving each lit beacon's clearing out of it. The material fog (layer 1) stays the truth.
var volumetric := false
var volumes: Dictionary = {}  # beacon id -> FogVolume

var _lit_at: Dictionary = {}  # beacon id -> time it was lit (for the growth animation)
var _time := 0.0
var palette: Dictionary = {}


## Start the clearing's growth animation now (or at `at`, on this node's clock: a time far in the past = fully grown).
func mark_lit(beacon_id: String, at: float = NAN) -> void:
	_lit_at[beacon_id] = _time if is_nan(at) else at


## The clearing starts growing `delay` seconds from now (the beacon moment: when the flame catches).
func mark_lit_after(beacon_id: String, delay: float) -> void:
	_lit_at[beacon_id] = _time + delay


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
	boost = lerpf(boost, boost_target, 1.0 - exp(-delta * 0.8))
	if environment != null:
		environment.ambient_light_energy = 1.1 * (1.0 - 0.55 * float(palette["night"]))
	if volumetric:
		sync_volumes(fog_col)
	var dens := float(palette["density"]) * boost
	var rid := db.region_at(p)
	if not db.region_open(rid, state.lit):
		dens = float(db.regions[rid]["fog"]["locked"])
	RenderingServer.global_shader_parameter_set("fog_density", dens)
	var slots := FogField.shader_slots(db, state, p, extra_lights, _beacon_lights())
	for i in FogField.SLOTS:
		RenderingServer.global_shader_parameter_set("fog_clear_%d" % i, slots[i])
	_apply_sky()


## Whether this machine draws layer 2: Forward+ and the high quality setting.
static func wants_volumetric() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus" and Game.settings.quality == "high" \
			and DisplayServer.get_name() != "headless"


## Volumetric fog in the environment and a negative-density ellipsoid over every lit beacon, grown with it.
func sync_volumes(fog_col: Color) -> void:
	if environment != null:
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_albedo = fog_col
		environment.volumetric_fog_density = float(palette.get("density", 0.01)) * 0.6 * boost
		environment.volumetric_fog_length = 240.0
		environment.volumetric_fog_emission = fog_col * 0.15
	for bid: String in state.lit:
		var v: FogVolume = volumes.get(bid)
		if v == null:
			v = FogVolume.new()
			v.name = "Clearing_" + bid
			v.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
			var m := FogMaterial.new()
			m.density = -1.0  # subtracts: the clearing
			m.edge_fade = 0.35
			v.material = m
			add_child(v)
			volumes[bid] = v
		var p := db.beacon_pos(bid)
		var r := float(db.beacons[bid]["clear_radius"])
		var grow := 1.0
		if _lit_at.has(bid):
			grow = smoothstep(0.0, GROW_S, _time - float(_lit_at[bid]))
		v.position = Vector3(p.x, 20.0, p.y)
		v.size = Vector3(r * 2.0, 140.0, r * 2.0) * maxf(grow, 0.01)


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
	var out := {
		"fog": Color(c["fog"]), "zenith": Color(c["zenith"]), "sun": Color(c["sun"]),
		"sun_energy": float(c["sun_energy"]), "sun_elevation": float(c["sun_elevation"]),
		"sea_deep": Color(c["sea_deep"]), "sea_shallow": Color(c["sea_shallow"]),
		"night": float(c["night"]), "aurora": float(c["aurora"]), "density": float(r["fog"]["density"]),
	}
	# day and night (docs/01_GDD.md §4.3): the region's share of night darkens what its chapter doesn't already
	var cycle := Weather.night(db, rid, state.clock_min) if state != null else 0.0
	var extra := maxf(0.0, cycle - float(c["night"]))
	if extra > 0.0:
		out["fog"] = (out["fog"] as Color).lerp(NIGHT_FOG, extra * 0.8)
		out["zenith"] = (out["zenith"] as Color).lerp(NIGHT_SKY, extra * 0.9)
		out["sea_deep"] = (out["sea_deep"] as Color).darkened(extra * 0.5)
		out["sea_shallow"] = (out["sea_shallow"] as Color).darkened(extra * 0.5)
		out["sun_energy"] = float(out["sun_energy"]) * (1.0 - 0.8 * extra)
		out["night"] = maxf(float(c["night"]), cycle)
	return out


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
