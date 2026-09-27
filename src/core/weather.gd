class_name Weather
extends RefCounted
## Weather as pure functions of the world seed and the world clock (WorldState.clock_min): every peer
## computes the same wind, so the host never has to send it.


## Direction the wind blows TO (unit vector on the xz plane). Turns slowly and never jumps.
static func wind(db: ContentDB, world_seed: int, minutes: float) -> Vector2:
	var period := float(db.balance["sea"]["wind_period_min"])
	var base := float(posmod(world_seed, 628)) * 0.01
	var a := base + sin(minutes * TAU / period) * 1.1 + sin(minutes * TAU / (period * 2.7) + 1.7) * 1.6
	return Vector2(cos(a), sin(a))


## Sail speed factor for a heading: into the wind = balance.sea.headwind_speed, beam or downwind = 1.
static func sail_factor(db: ContentDB, heading: Vector2, wind_to: Vector2) -> float:
	var into := heading.normalized().dot(-wind_to.normalized())  # 1 = the wind comes from straight ahead
	var head := float(db.balance["sea"]["headwind_speed"])
	return lerpf(head, 1.0, clampf(1.0 - into, 0.0, 1.0))


## "head", "beam" or "tail": what the HUD says about the wind.
static func wind_side(heading: Vector2, wind_to: Vector2) -> String:
	var into := heading.normalized().dot(-wind_to.normalized())
	if into > 0.5:
		return "head"
	if into < -0.5:
		return "tail"
	return "beam"
