class_name SeaWall
extends RefCounted
## The edge of the open sea (docs/01_GDD.md §3, §4.2): a region that is still closed is a wall of Mga, and a
## region whose ice or storms need a stronger boat (regions.json → boat_required: the Ter Coast wants a
## shnyaka, the Frozen Sea a koch) turns a weaker hull back too. After balance.fog.lock_push_s seconds inside,
## a gentle current turns the boat towards home. No damage and no death — just the sea saying "not yet".

const BOAT_ORDER: Array[String] = ["karbas", "shnyaka", "koch"]
## The Steam Next Fest demo (export feature "demo"): only the Quiet Bay and its three beacons; the rest of the
## sea is a wall like a closed region.
static var demo := false


## "" (free to sail), "locked" (the region is closed), "boat" (it needs a stronger boat) or "demo" (the demo ends).
static func blocked(db: ContentDB, state: WorldState, pos: Vector2, boat_type: String) -> String:
	var rid := db.region_at(pos)
	if demo and rid != "r1":
		return "demo"
	if not db.region_open(rid, state.lit):
		return "locked"
	var need := String(db.regions[rid]["boat_required"])
	if BOAT_ORDER.find(boat_type) < BOAT_ORDER.find(need):
		return "boat"
	return ""


## The boat that region needs (for the message "a karbas can't go here: you need a shnyaka").
static func boat_needed(db: ContentDB, pos: Vector2) -> String:
	return String(db.regions[db.region_at(pos)]["boat_required"])


## Where the current pulls: back towards the home island.
static func pull(pos: Vector2) -> Vector2:
	return -pos.normalized() if pos.length() > 0.001 else Vector2.ZERO


static func push_after_s(db: ContentDB) -> float:
	return float(db.balance["fog"]["lock_push_s"])
