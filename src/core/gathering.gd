class_name Gathering
extends RefCounted
## How gathering feels in time (docs/03_BALANCE.md §3): one unit takes 60 / (rate × tool speed) seconds,
## rate from items.json → gather.rate, speed from items.json → tool_speed by the best tool tier carried.
## The player works a node unit by unit and the whole haul (≤ WorldCommands.GATHER_MAX) goes to the host as
## one "gather" command, so a node is one line in co-op.


## Tool type needed ("hand", "axe", "knife", ...) and whether this bag has it at the needed tier.
## `wear_on` = the world's durability rule (Tools): then a broken tool is no tool.
static func tool_ok(db: ContentDB, inv: Inventory, item: String, wear_on: bool = false) -> bool:
	var g: Dictionary = db.items[item]["gather"]
	return g["tool"] == "hand" or inv.best_tool_tier(g["tool"], wear_on) >= int(g.get("tool_tier", 1))


static func speed(db: ContentDB, inv: Inventory, item: String, wear_on: bool = false) -> float:
	var g: Dictionary = db.items[item]["gather"]
	var ts: Dictionary = db.raw["items"]["tool_speed"]
	if g["tool"] == "hand":
		return float(ts["hand"])
	return float(ts.get(str(inv.best_tool_tier(g["tool"], wear_on)), 1.0)) * Tools.speed_factor(db, inv, g["tool"], wear_on)


static func unit_seconds(db: ContentDB, inv: Inventory, item: String, wear_on: bool = false) -> float:
	var rate := float(db.items[item]["gather"]["rate"])
	return 60.0 / (rate * speed(db, inv, item, wear_on))


## The first item of a node this bag can gather, or "" (the E key's default choice).
static func best_item(db: ContentDB, inv: Inventory, items: Array, wear_on: bool = false) -> String:
	for it: String in items:
		if tool_ok(db, inv, it, wear_on):
			return it
	return ""
