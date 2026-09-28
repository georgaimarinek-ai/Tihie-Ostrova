class_name Comfort
extends RefCounted
## Comfort at a bed (docs/01_GDD.md §7.3, balance.json → rested): every KIND of piece with a comfort value
## within rested.radius_m of the bed counts once (a stove +3, a sauna stove +2, a bench, a table, a ridge
## log… +1), up to rested.max_comfort. Sleeping there gives "Rested" for base_min + comfort × per_comfort_min.


## {"total": int, "parts": [{"id", "comfort"}], "max": int} for a point (usually a bed).
## A fed domovoy living at a bed within the radius adds balance.spirits.domovoy_comfort_bonus ("domovoy" part).
static func at(db: ContentDB, state: WorldState, pos: Vector3, with_spirits: bool = true) -> Dictionary:
	var r: Dictionary = db.balance["rested"]
	var radius := float(r["radius_m"])
	var best := {}
	for pc: Dictionary in state.pieces.values():
		var p: Dictionary = db.pieces.get(pc["id"], {})
		if not p.has("comfort") or (pc["pos"] as Vector3).distance_to(pos) > radius:
			continue
		best[pc["id"]] = int(p["comfort"])
	if with_spirits and Creatures.domovoy_fed(db, state):
		var home := Creatures.domovoy_home(db, state)
		if home != "" and (state.pieces[home]["pos"] as Vector3).distance_to(pos) <= radius:
			best["domovoy"] = int(db.balance["spirits"]["domovoy_comfort_bonus"])
	var parts: Array = []
	var total := 0
	var ids := best.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return best[a] > best[b] if best[a] != best[b] else a < b)
	for id: String in ids:
		parts.append({"id": id, "comfort": best[id]})
		total += int(best[id])
	return {"total": mini(total, int(r["max_comfort"])), "parts": parts, "max": int(r["max_comfort"])}


static func rested_minutes(db: ContentDB, comfort: int) -> float:
	var r: Dictionary = db.balance["rested"]
	return float(r["base_min"]) + comfort * float(r["per_comfort_min"])


## The nearest bed within `reach` metres ("" if none).
static func nearest_bed(db: ContentDB, state: WorldState, pos: Vector3, reach: float) -> String:
	var best := ""
	var best_d := reach
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if not db.pieces.get(pc["id"], {}).get("spawn", false):
			continue
		var d := (pc["pos"] as Vector3).distance_to(pos)
		if d <= best_d:
			best_d = d
			best = uid
	return best
