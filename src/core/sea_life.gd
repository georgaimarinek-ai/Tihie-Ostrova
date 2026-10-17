class_name SeaLife
extends RefCounted
## The living sea (docs/08_NEXT.md stage 13, balance.json → sea_events): pure functions of the world seed and
## clock, like Weather, so every peer sees the same shoal, tide and squall warning without a message.
## - a shoal: a fishing spot's bites × bite_bonus for lasts_min out of every every_min, on the spot's own clock;
## - the tide: low for low_share of the day from low_from (day phase), the sea drop_m lower; some nodes
##   (pearl shoals) are reachable only then, and a boat in the shallows sits on the bottom;
## - a squall warning: the storm will be worse within squall_warning_min;
## - the vodyanoy's mood: days without his first fish make the bites worse in his waters;
## - a tailwind after a beacon (WorldState.tailwind_until);
## - the aurora over the Frozen Sea on clear nights.


static func _se(db: ContentDB) -> Dictionary:
	return db.balance["sea_events"]


## Whether a shoal is at a fishing spot now (WorldMap.fish_spot id, "sea:x:z").
static func shoal_active(db: ContentDB, world_seed: int, minutes: float, spot: String) -> bool:
	var s: Dictionary = _se(db)["shoal"]
	var every := float(s["every_min"])
	var phase := float(posmod(hash(spot) ^ world_seed, 1000)) / 1000.0 * every
	return fposmod(minutes + phase, every) < float(s["lasts_min"])


## Bite factor at a spot: bite_bonus under a shoal, else 1.
static func shoal_factor(db: ContentDB, world_seed: int, minutes: float, spot: String) -> float:
	return float(_se(db)["shoal"]["bite_bonus"]) if shoal_active(db, world_seed, minutes, spot) else 1.0


## Low tide now: the sea is down and the shoals are bare.
static func tide_low(db: ContentDB, minutes: float) -> bool:
	return tide_offset(db, minutes) < -0.5 * float(_se(db)["tide"]["drop_m"])


## How far the sea stands from its mean level, 0 at high water down to -drop_m at low water, eased over the
## turn of the tide (2 % of the day each way, about 36 s).
static func tide_offset(db: ContentDB, minutes: float) -> float:
	var t: Dictionary = _se(db)["tide"]
	var phase := Weather.day_phase(db, minutes)
	var from := float(t["low_from"])
	var to := from + float(t["low_share"])
	var edge := 0.02
	var k := smoothstep(from - edge, from + edge, phase) * (1.0 - smoothstep(to - edge, to + edge, phase))
	return -float(t["drop_m"]) * k


## Minutes until the water comes back (0 when it isn't low).
static func tide_turns_in(db: ContentDB, minutes: float) -> float:
	var t: Dictionary = _se(db)["tide"]
	var phase := Weather.day_phase(db, minutes)
	var to := float(t["low_from"]) + float(t["low_share"])
	if phase < float(t["low_from"]) or phase >= to:
		return 0.0
	return (to - phase) * float(db.balance["day"]["length_min"])


## A node the tide hides: reachable only at low water.
static func tide_only(db: ContentDB, node_kind: String) -> bool:
	return (_se(db)["tide"]["only_nodes"] as Array).has(node_kind)


## The storm will be worse within squall_warning_min: gulls make for the shore, the HUD says so.
static func squall_coming(db: ContentDB, world_seed: int, minutes: float, rid: String) -> bool:
	var ahead := float(_se(db)["squall_warning_min"])
	return Weather.storm(db, world_seed, minutes + ahead, rid) > Weather.storm(db, world_seed, minutes, rid)


## The vodyanoy sulks: he was given a fish once, then forgotten for vodyanoy_angry_days.
static func vodyanoy_angry(db: ContentDB, state: WorldState) -> bool:
	var last := int((state.spirits.get("vodyanoy", {}) as Dictionary).get("day", -1))
	return last >= 0 and state.day - last >= int(_se(db)["vodyanoy_angry_days"])


## Bite time factor from the vodyanoy: faster with his boon, slower while he sulks, else 1 (fishing in his
## regions only; elsewhere 1).
static func vodyanoy_bite_factor(db: ContentDB, state: WorldState, rid: String) -> float:
	if not (db.regions[rid]["creatures"] as Array).has("vodyanoy"):
		return 1.0
	if Creatures.vodyanoy_boon(state):
		return 1.0 + float(db.balance["spirits"]["vodyanoy_bite_bonus"])
	if vodyanoy_angry(db, state):
		return 1.0 - float(_se(db)["vodyanoy_angry_penalty"])
	return 1.0


## The tailwind after a beacon: sail speed factor (1 when none).
static func tailwind(db: ContentDB, state: WorldState) -> float:
	return float(_se(db)["tailwind"]["factor"]) if state.tailwind_until > state.clock_min else 1.0


## The aurora's strength multiplier on a clear night over the Frozen Sea (night ≥ 0.5, storm 0, cold region).
static func aurora_boost(db: ContentDB, rid: String, night: float, storm: int) -> float:
	if night >= 0.5 and storm == 0 and bool(db.regions[rid]["cold"]):
		return float(_se(db)["aurora_boost"])
	return 1.0


## Flotsam kinds (balance.sea_events.flotsam.kinds).
static func flotsam_kinds(db: ContentDB) -> Dictionary:
	return _se(db)["flotsam"]["kinds"]
