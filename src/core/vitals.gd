class_name Vitals
extends RefCounted
## Health and stamina limits from food and rest (docs/01_GDD.md §7): no hunger, only bonuses. Every dish in
## the three slots adds its food.hp and food.stamina while it lasts; "Rested" makes stamina come back faster.


static func bonus(db: ContentDB, state: WorldState, pid: String) -> Dictionary:
	var hp := 0.0
	var st := 0.0
	for f: Dictionary in state.players[pid]["food"]:
		var food: Dictionary = db.items[f["id"]]["food"]
		hp += float(food["hp"])
		st += float(food["stamina"])
	return {"hp": hp, "stamina": st}


static func max_hp(db: ContentDB, state: WorldState, pid: String) -> float:
	return float(db.balance["player"]["hp"]) + float(bonus(db, state, pid)["hp"])


static func max_stamina(db: ContentDB, state: WorldState, pid: String) -> float:
	return float(db.balance["player"]["stamina"]) + float(bonus(db, state, pid)["stamina"])


static func is_rested(state: WorldState, pid: String) -> bool:
	return float(state.players[pid]["rested_until"]) > state.clock_min


## "Weary" after a death (modes.json death_debuff_min): stamina comes back slower.
static func is_weary(state: WorldState, pid: String) -> bool:
	return float(state.players[pid]["weary_until"]) > state.clock_min


## Stamina per second: the base, +50 % rested (balance.rested.stamina_regen_bonus), more in the steam of a bath,
## half while weary, none at all in the cold without warmth (Tale and Saga, docs/01_GDD.md §6).
static func stamina_regen(db: ContentDB, state: WorldState, pid: String) -> float:
	if Creatures.is_cold(db, state, pid):
		return 0.0
	var k := 1.0
	if is_rested(state, pid):
		k += float(db.balance["rested"]["stamina_regen_bonus"])
	if float(state.players[pid]["steam_until"]) > state.clock_min:
		k += float(db.balance["steam"]["stamina_regen_bonus"])
	if is_weary(state, pid):
		k *= float(db.balance["weary"]["stamina_regen_factor"])
	return float(db.balance["player"]["stamina_regen_per_s"]) * k
