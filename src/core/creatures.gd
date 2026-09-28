class_name Creatures
extends RefCounted
## Who lives where and who may hurt whom (docs/01_GDD.md §6, §11; creatures.json). Pure: the host's
## CreatureDirector asks here before it spawns anything, and WorldCommands asks before any harm is done.
## Spirits, wonders and legends are never enemies, in any mode and with any fine tuning.

const FRIENDLY_GROUPS: Array[String] = ["animal", "spirit", "wonder", "legend"]
const SPIRIT_GROUPS: Array[String] = ["spirit", "wonder", "legend"]
## The mode rule (modes.json → rules) that lets a hostile group exist at all.
const RULE_OF_GROUP := {"predator": "predators", "fog": "fog_creatures", "elite": "fog_creatures", "guardian": "guardians"}
const HOME_REACH_M := 6.0  # the domovoy's gifts are left by the bed


static func info(db: ContentDB, id: String) -> Dictionary:
	return db.creatures.get(id, {})


static func group(db: ContentDB, id: String) -> String:
	return String(info(db, id).get("group", ""))


## Never deals damage: animals, spirits, wonders, legends (and anything with no damage in the content).
static func is_friendly(db: ContentDB, id: String) -> bool:
	var c := info(db, id)
	if c.is_empty():
		return true
	return FRIENDLY_GROUPS.has(String(c["group"])) or float(c.get("damage", 0.0)) <= 0.0


static func is_spirit(db: ContentDB, id: String) -> bool:
	return SPIRIT_GROUPS.has(group(db, id))


## Whether the creature exists at all in a world of this mode with these (fine-tuned) rules.
static func allowed(db: ContentDB, mode: String, rules: Dictionary, id: String) -> bool:
	var c := info(db, id)
	if c.is_empty() or not (c["modes"] as Array).has(mode):
		return false
	var rule := String(RULE_OF_GROUP.get(String(c["group"]), ""))
	return rule == "" or bool(rules.get(rule, false))


## Ambient appearance at a place: "" if it may appear here now, else why not. `fog` is FogField.factor there,
## `night` 0..1, `dark_island` = on the island of a beacon that is still dark (the Mga clings to the land).
## Fog creatures come only where the fog is thicker than their fog_min, at night or on a dark island;
## guardians come only with their fight (begin_fight), never by themselves.
static func spawn_block(db: ContentDB, mode: String, rules: Dictionary, id: String, rid: String, fog: float, night: float, dark_island: bool) -> String:
	if not allowed(db, mode, rules, id):
		return "not_in_this_mode"
	var c := info(db, id)
	if String(c["group"]) == "guardian":
		return "fight_only"
	if rid != "" and not (db.regions[rid]["creatures"] as Array).has(id):
		return "not_in_this_region"
	if String(c["behaviour"]) == "fog":
		if fog <= float(c.get("fog_min", 0.0)):
			return "clear"
		if night < 0.5 and not dark_island:
			return "daylight"
	return ""


## Damage a hit from `id` does to a player (0 for anything friendly): a dodge takes none, a block takes off
## the shield's armor.block (bare hands balance.combat.block_bare).
static func damage_to_player(db: ContentDB, id: String, k: float, stance: String, has_shield: bool) -> float:
	if is_friendly(db, id):
		return 0.0
	var dmg := float(info(db, id)["damage"]) * clampf(k, 0.0, 2.0)
	match stance:
		"dodge":
			return 0.0
		"block":
			var cut := float(db.items["shield"]["armor"]["block"]) if has_shield else float(db.balance["combat"]["block_bare"])
			return maxf(0.0, dmg - cut)
	return dmg


# ---------------------------------------------------------------- spirits (docs/01_GDD.md §11)

## The domovoy moves into a home with a stove (or hearth) and a bed where comfort is 5 or more: the bed's uid.
static func domovoy_home(db: ContentDB, state: WorldState) -> String:
	var need := int(db.balance["spirits"]["domovoy_comfort"])
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if not db.pieces[pc["id"]].get("spawn", false):
			continue
		var bed: Vector3 = pc["pos"]
		var has_fire := false
		for other: String in state.pieces:
			var o: Dictionary = state.pieces[other]
			if String(o["id"]) in ["stove", "hearth"] and (o["pos"] as Vector3).distance_to(bed) <= float(db.balance["rested"]["radius_m"]):
				has_fire = true
				break
		if has_fire and int(Comfort.at(db, state, bed, false)["total"]) >= need:
			return uid
	return ""


## Fed within the last balance.spirits.domovoy_gift_days: +2 comfort at home.
static func domovoy_fed(db: ContentDB, state: WorldState) -> bool:
	return float((state.spirits.get("domovoy", {}) as Dictionary).get("fed_until", -1.0)) > state.clock_min


## The vodyanoy got the first fish today: bites +30 % until the day ends.
static func vodyanoy_boon(state: WorldState) -> bool:
	return int((state.spirits.get("vodyanoy", {}) as Dictionary).get("day", 0)) == state.day


## The leshy's green wisp: leading the way until this clock minute.
static func leshy_guiding(state: WorldState) -> bool:
	return float((state.spirits.get("leshy", {}) as Dictionary).get("guide_until", -1.0)) > state.clock_min


## Warm enough in the cold (r4): a coat in the bag, fire in hand, steam, or a fire piece within 6 m.
static func is_warm(db: ContentDB, state: WorldState, pid: String) -> bool:
	var p: Dictionary = state.players[pid]
	if (p["inv"] as Inventory).count("wool_coat") > 0 or not (p.get("light", {}) as Dictionary).is_empty():
		return true
	if float(p["steam_until"]) > state.clock_min:
		return true
	var pos: Vector3 = p["pos"]
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if float(db.pieces[pc["id"]].get("fog_radius", 0.0)) > 0.0 and (pc["pos"] as Vector3).distance_to(pos) <= float(db.balance["cold"]["fire_m"]):
			return true
	return false


## In the cold at all: a region with cold = true, and the rule isn't just the look of it.
static func is_cold(db: ContentDB, state: WorldState, pid: String) -> bool:
	var pos: Vector3 = state.players[pid]["pos"]
	var rid := db.region_at(Vector2(pos.x, pos.z))
	if not bool(db.regions[rid]["cold"]) or String(state.rules()["cold"]) == "cosmetic":
		return false
	return not is_warm(db, state, pid)
