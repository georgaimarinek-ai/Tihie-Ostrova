class_name Tools
extends RefCounted
## Tool wear (docs/01_GDD.md §6, docs/08_NEXT.md stage 14): a tool has items.json → tool.uses; every unit
## gathered with it spends one. Past balance.wear.dull_at of its uses it is DULL (works at dull_speed), at the
## end it is BROKEN: it stays in the bag but no longer counts as a tool. Nothing ever vanishes. A repair at the
## recipe's station costs a share of the recipe's inputs (repair_broken, repair_dull). The rule is the mode's
## "durability" (off in Quiet, so there every tool is whole whatever its wear says).

const OK := "ok"
const DULL := "dull"
const BROKEN := "broken"


static func uses(db: ContentDB, id: String) -> int:
	var it: Dictionary = db.items.get(id, {})
	return int(it["tool"].get("uses", 0)) if it.has("tool") else 0


## "" for anything that doesn't wear (not a tool, or a tool without uses), else ok | dull | broken.
static func condition(db: ContentDB, slot: Dictionary) -> String:
	if slot.is_empty():
		return ""
	var total := uses(db, String(slot["id"]))
	if total <= 0:
		return ""
	var w := int(slot.get("wear", 0))
	if w >= total:
		return BROKEN
	if float(w) >= float(total) * float(db.balance["wear"]["dull_at"]):
		return DULL
	return OK


## The slot of the best working tool of a type (highest tier, then the least worn): -1 if none. With the wear
## rule off a broken tool still counts (Quiet: everything is whole).
static func best_slot(db: ContentDB, inv: Inventory, tool_type: String, wear_on: bool) -> int:
	var best := -1
	var best_tier := 0
	var best_wear := 0
	for i in inv.size:
		var s: Dictionary = inv.slots[i]
		if s.is_empty():
			continue
		var it: Dictionary = db.items.get(s["id"], {})
		if not it.has("tool") or it["tool"]["type"] != tool_type:
			continue
		if wear_on and condition(db, s) == BROKEN:
			continue
		var tier := int(it["tool"]["tier"])
		var w := int(s.get("wear", 0))
		if tier > best_tier or (tier == best_tier and w < best_wear):
			best = i
			best_tier = tier
			best_wear = w
	return best


## Work speed factor of the tool that will be used: dull_speed when it is dull, else 1.
static func speed_factor(db: ContentDB, inv: Inventory, tool_type: String, wear_on: bool) -> float:
	if not wear_on:
		return 1.0
	var i := best_slot(db, inv, tool_type, true)
	if i >= 0 and condition(db, inv.slots[i]) == DULL:
		return float(db.balance["wear"]["dull_speed"])
	return 1.0


## Spend `n` uses of the best working tool of a type. Returns {} when nothing wore, else
## {"slot", "item", "from", "to"} with the condition before and after (the HUD tells when it changes).
static func use(db: ContentDB, inv: Inventory, tool_type: String, n: int) -> Dictionary:
	var i := best_slot(db, inv, tool_type, true)
	if i < 0:
		return {}
	var s: Dictionary = inv.slots[i]
	var total := uses(db, String(s["id"]))
	if total <= 0:
		return {}
	var before := condition(db, s)
	s["wear"] = mini(total, int(s.get("wear", 0)) + maxi(0, n))
	return {"slot": i, "item": String(s["id"]), "from": before, "to": condition(db, s)}


## Where a tool is mended: the forge for what the forge made, the workbench for everything else.
static func repair_station(db: ContentDB, id: String) -> String:
	var made := db.recipes_producing(id)
	if not made.is_empty() and String(made[0]["station"]) == "forge":
		return "forge"
	return "workbench"


## What a repair costs: broken = repair_broken of every input of the recipe (rounded up); dull = repair_dull
## of the largest input only. A tool nobody crafts (found, debug) is mended for nothing.
static func repair_cost(db: ContentDB, id: String, cond: String) -> Dictionary:
	var made := db.recipes_producing(id)
	if made.is_empty() or cond == OK or cond == "":
		return {}
	var inputs := ContentDB.bag(made[0]["inputs"])
	var w: Dictionary = db.balance["wear"]
	var out := {}
	if cond == BROKEN:
		for k: String in inputs:
			out[k] = int(ceil(float(inputs[k]) * float(w["repair_broken"])))
	else:
		var top := ""
		for k: String in inputs:
			if top == "" or int(inputs[k]) > int(inputs[top]):
				top = k
		out[top] = int(ceil(float(inputs[top]) * float(w["repair_dull"])))
	return out


## Tools in a bag that are dull or broken: [{"slot", "item", "condition"}] (the evening screen's reminder).
static func worn(db: ContentDB, inv: Inventory) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in inv.size:
		var c := condition(db, inv.slots[i])
		if c == DULL or c == BROKEN:
			out.append({"slot": i, "item": String(inv.slots[i]["id"]), "condition": c})
	return out
