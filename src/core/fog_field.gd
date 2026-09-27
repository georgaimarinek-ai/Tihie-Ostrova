class_name FogField
extends RefCounted
## How thick the fog is at a point. 1.0 = the region's full fog, balance.fog.clear_factor (0.22) = the
## centre of a lit beacon's clearing. Locked regions return locked/density (> 1: the "wall").
## Used by gameplay (Saga creatures spawn only where factor > creature.fog_min), audio (wind level),
## and to feed the four fog_clear_* shader globals (see src/shaders/fog_clear.gdshaderinc).
## The maths matches the shader: smoothstep(radius * edge, radius, distance), strength-weighted.

## A light that clears fog: Vector4(x, z, radius, strength 0..1).
static func clear_term(p: Vector2, light: Vector4, edge: float) -> float:
	var d := p.distance_to(Vector2(light.x, light.y))
	return lerpf(1.0, smoothstep(light.z * edge, light.z, d), light.w)


## All clearing lights: lit beacons plus extra lights (lanterns, hearths) passed by the caller.
static func lights(db: ContentDB, state: WorldState, extra: Array[Vector4] = []) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for bid: String in state.lit:
		var b: Dictionary = db.beacons[bid]
		var p := db.beacon_pos(bid)
		out.append(Vector4(p.x, p.y, float(b["clear_radius"]), 0.95))
	out.append_array(extra)
	return out


static func factor(db: ContentDB, state: WorldState, p: Vector2, extra: Array[Vector4] = []) -> float:
	var rid := db.region_at(p)
	var reg: Dictionary = db.regions[rid]
	if not db.region_open(rid, state.lit):
		return float(reg["fog"]["locked"]) / float(reg["fog"]["density"])
	var fog: Dictionary = db.balance["fog"]
	var k := 1.0
	for l: Vector4 in lights(db, state, extra):
		k = minf(k, clear_term(p, l, float(fog["clear_edge"])))
	return lerpf(float(fog["clear_factor"]), 1.0, k)


## The four lights the shader gets: the extra lights first (player lantern, home hearth), then the
## lit beacons nearest to `near`. Unused slots are zero (strength 0 = no effect).
## `beacons` overrides the lit-beacon list (FogDirector passes radii with the growth animation applied).
static func shader_slots(db: ContentDB, state: WorldState, near: Vector2, extra: Array[Vector4] = [], beacons: Array[Vector4] = []) -> Array[Vector4]:
	var beacon_lights: Array[Vector4] = beacons.duplicate() if not beacons.is_empty() else lights(db, state)
	beacon_lights.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		return near.distance_squared_to(Vector2(a.x, a.y)) < near.distance_squared_to(Vector2(b.x, b.y)))
	var out: Array[Vector4] = []
	for l: Vector4 in extra:
		if out.size() < 4:
			out.append(l)
	for l: Vector4 in beacon_lights:
		if out.size() < 4:
			out.append(l)
	while out.size() < 4:
		out.append(Vector4.ZERO)
	return out
