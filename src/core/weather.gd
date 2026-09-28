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


## Time of day, 0..1: 0 = midnight, 0.25 = six in the morning, 0.5 = noon. A day lasts balance.day.length_min
## world minutes (30 real minutes) and a new world starts at dawn.
static func day_phase(db: ContentDB, minutes: float) -> float:
	return fposmod(minutes / float(db.balance["day"]["length_min"]) + 0.25, 1.0)


## How much of night it is in a region, 0..1 (docs/01_GDD.md §4.3): the night lasts balance.day.night_share
## of the day around midnight: none in r1 (white nights), 15 % in r2, 30 % in r3, 60 % in r4. Soft edges.
static func night(db: ContentDB, rid: String, minutes: float) -> float:
	var share := float((db.balance["day"]["night_share"] as Dictionary).get(rid, 0.0))
	if share <= 0.0:
		return 0.0
	var phase := day_phase(db, minutes)
	var from_midnight := minf(phase, 1.0 - phase)
	var half := share * 0.5
	return 1.0 - smoothstep(half - 0.03, half + 0.03, from_midnight)


## Dawn in a region: the end of its night (in the white nights of r1, early morning). Sirin sings then.
static func is_dawn(db: ContentDB, rid: String, minutes: float) -> bool:
	var share := float((db.balance["day"]["night_share"] as Dictionary).get(rid, 0.0))
	var start := share * 0.5 if share > 0.0 else 0.2
	var phase := day_phase(db, minutes)
	return phase >= start - 0.02 and phase <= start + 0.08


## "After midnight" (the bannik's hours: the third steam is his), until six in the morning.
static func after_midnight(db: ContentDB, minutes: float) -> bool:
	return day_phase(db, minutes) < 0.25


## The storm level at sea, 0..regions.json storm_max: calm most of the time, a squall now and then, the
## same for every peer (seed and clock).
static func storm(db: ContentDB, world_seed: int, minutes: float, rid: String) -> int:
	var top := int(db.regions[rid]["storm_max"])
	if top <= 0:
		return 0
	var t := minutes / 23.0 + float(posmod(world_seed, 97))
	var n := 0.5 + 0.5 * sin(t * 1.3) * cos(t * 0.71 + 2.0)
	var k := clampf((n - 0.6) / 0.4, 0.0, 1.0)
	return mini(top, int(floor(k * (top + 1))))


## A hull capsizes when the storm is above what it survives (boats.json storm) and the rules say storms
## capsize (Tale and Saga; in Quiet they are only waves and rain). The boat floats and can be righted.
static func capsizes(db: ContentDB, rules: Dictionary, boat_type: String, level: int) -> bool:
	return String(rules.get("storms", "cosmetic")) == "capsize" and level > int(db.boats[boat_type]["storm"])


## "head", "beam" or "tail": what the HUD says about the wind.
static func wind_side(heading: Vector2, wind_to: Vector2) -> String:
	var into := heading.normalized().dot(-wind_to.normalized())
	if into > 0.5:
		return "head"
	if into < -0.5:
		return "tail"
	return "beam"
