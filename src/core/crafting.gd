class_name Crafting
extends RefCounted
## Can this player craft this recipe here, and doing it. Used by WorldCommands (authority) and by
## the crafting UI (to grey out recipes and explain why). Reason codes are i18n keys: craft.<reason>.

const REACH_M := 6.0


static func station_near(state: WorldState, station_id: String, pos: Vector3, reach: float = REACH_M) -> bool:
	for pc: Dictionary in state.pieces.values():
		if pc["id"] == station_id and (pc["pos"] as Vector3).distance_to(pos) <= reach:
			return true
	return false


## "" when possible, otherwise: unknown_recipe, locked, no_station, missing, no_space.
static func check(db: ContentDB, state: WorldState, pid: String, recipe_id: String, times: int = 1) -> String:
	if not db.recipes.has(recipe_id):
		return "unknown_recipe"
	var r: Dictionary = db.recipes[recipe_id]
	if not db.is_unlocked(r["unlock"], state.lit):
		return "locked"
	var p: Dictionary = state.players[pid]
	if r["station"] != "hand" and not station_near(state, r["station"], p["pos"]):
		return "no_station"
	var inv: Inventory = p["inv"]
	if not inv.has_bag(scaled(r["inputs"], times)):
		return "missing"
	var probe := Inventory.new(db, inv.size)
	probe.from_dict(inv.to_dict())
	probe.remove_bag(scaled(r["inputs"], times))
	if not probe.can_fit(scaled(r["output"], times)):
		return "no_space"
	return ""


static func apply(db: ContentDB, state: WorldState, pid: String, recipe_id: String, times: int = 1) -> String:
	var reason := check(db, state, pid, recipe_id, times)
	if reason != "":
		return reason
	var r: Dictionary = db.recipes[recipe_id]
	var inv: Inventory = state.players[pid]["inv"]
	inv.remove_bag(scaled(r["inputs"], times))
	var out := scaled(r["output"], times)
	for k: String in out:
		inv.add(k, out[k])
	return ""


## Long recipes (balance.sim.background_craft_min_s and up) cook in the station in the background:
## load them with "load_station", collect later (docs/01_GDD.md §9.3).
static func is_background(db: ContentDB, recipe_id: String) -> bool:
	var r: Dictionary = db.recipes.get(recipe_id, {})
	return not r.is_empty() and r["station"] != "hand" and float(r["time_s"]) >= float(db.balance["sim"]["background_craft_min_s"])


## Stations of a kind within reach of a point, nearest first: [uid, ...].
static func stations_near(state: WorldState, pos: Vector3, reach: float = REACH_M) -> Array[String]:
	var out: Array[String] = []
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if (pc["pos"] as Vector3).distance_to(pos) <= reach:
			out.append(uid)
	out.sort_custom(func(a: String, b: String) -> bool:
		return (state.pieces[a]["pos"] as Vector3).distance_to(pos) < (state.pieces[b]["pos"] as Vector3).distance_to(pos))
	return out


## How many times the bag can afford a recipe right now (0 = not even once).
static func affordable(db: ContentDB, inv: Inventory, recipe_id: String) -> int:
	var inputs: Dictionary = db.recipes[recipe_id]["inputs"]
	var n := 999
	for k: String in inputs:
		n = mini(n, inv.count(k) / maxi(1, int(inputs[k])))
	return n


static func scaled(bag: Dictionary, times: int) -> Dictionary:
	var out := {}
	for k: String in bag:
		out[k] = int(bag[k]) * times
	return out
