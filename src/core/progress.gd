class_name Progress
extends RefCounted
## Where the story stands: pure queries for the compass, the hint light over the next beacon, the map
## and the music (docs/01_GDD.md §5.1: beacons go in order, the compass always shows the next one).


## The next beacon to light: the first dark one in content order whose region is open ("" = all lit).
static func next_beacon(db: ContentDB, state: WorldState) -> String:
	for bid in db.beacon_order:
		if not state.lit.has(bid) and db.region_open(String(db.beacons[bid]["region"]), state.lit):
			return bid
	return ""


static func lit_count(state: WorldState) -> int:
	return state.lit.size()


## Music layer names that play for a number of lit beacons (docs/05_ART_AUDIO.md §7.1).
static func music_layers(lit: int) -> Array[String]:
	var out: Array[String] = ["base"]
	var steps := {"chords": 1, "gusli": 3, "zhaleyka": 4, "gudok": 7, "bells": 8, "frost": 10, "choir": 11}
	for layer: String in steps:
		if lit >= int(steps[layer]):
			out.append(layer)
	return out
