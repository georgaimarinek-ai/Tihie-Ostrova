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


static func scaled(bag: Dictionary, times: int) -> Dictionary:
	var out := {}
	for k: String in bag:
		out[k] = int(bag[k]) * times
	return out
