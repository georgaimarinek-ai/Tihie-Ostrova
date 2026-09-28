class_name WorldCommands
extends RefCounted
## The only writer of WorldState. Every change to the shared world is a command Dictionary:
##   {"type": "gather", "node": "home:12", "item": "wood", "qty": 3}
## Solo: Game calls apply() directly. Co-op: a client sends the same Dictionary to the host
## (Net.send_command), the host calls apply() and broadcasts the returned events to everyone.
## apply() validates everything itself: never trust the caller, it may be a remote peer.
## Result: {"ok": bool, "error": String, "events": Array[Dictionary]}. Errors are i18n keys: cmd.<error>.

const GATHER_MAX := 5
const BEACON_REACH_M := 12.0
const BOARD_REACH_M := 16.0  # landing looks up to 14 m from the boat
const LAND_REACH_M := 18.0
const PLACE_REACH_M := 10.0
const USE_REACH_M := 4.0  # beds, sauna stoves, chests
const CLIMB_TOP_M := 9.0  # the "climb" trial ends this high above the tower's foot
const WORLD_LIMIT_M := 5000.0
## Commands only the host itself may issue; Game drops them when they arrive from a remote peer.
const HIT_REACH_M := 4.5  # a creature's bite or swipe (guardians reach further)
## Only the host sends these: world time, debug, and what the host simulates (creatures, their hits, storms).
const HOST_ONLY: Array[String] = ["tick", "debug", "spawn", "despawn", "creatures", "hurt", "capsize", "douse", "steal", "join"]
const ARENA_LANTERNS := 4  # around the Lodestar: the Mga is weak while all of them burn

var db: ContentDB
var state: WorldState
## Optional: with a map, gather checks that the node exists, gives that item and is within reach, and
## disembark checks for dry land. Tests without a map keep the older, looser checks.
var map: WorldMap
## Debug commands (grant items, pass trials) for screenshots and automation. Off in normal play.
var allow_debug := false


func _init(p_db: ContentDB, p_state: WorldState, p_map: WorldMap = null) -> void:
	db = p_db
	state = p_state
	map = p_map


## A brand-new world: the starting karbas moored at the home pier with every player aboard. The host calls
## this once right after creating the state. Returns events like apply() does.
func init_world() -> Array:
	if map == null or not state.boats.is_empty():
		return []
	var h := map.home
	var uid := state.add_boat("karbas", h["boat"], float(h["yaw"]))
	for pid: String in state.players:
		var p: Dictionary = state.players[pid]
		p["spawn"] = h["spawn"]
		p["pos"] = h["boat"]
		p["aboard"] = uid
	return [{"type": "boat_added", "uid": uid, "boat": "karbas"}]


func apply(pid: String, cmd: Dictionary) -> Dictionary:
	if not state.players.has(pid):
		return _fail("unknown_player")
	match String(cmd.get("type", "")):
		"gather":
			return _gather(pid, cmd)
		"craft":
			return _craft(pid, cmd)
		"place":
			return _place(pid, cmd)
		"remove":
			return _remove(pid, cmd)
		"begin_fight":
			return _begin_fight(pid, cmd)
		"complete_trial":
			return _complete_trial(pid, cmd)
		"light_beacon":
			return _light_beacon(pid, cmd)
		"set_mode":
			return _set_mode(pid, cmd)
		"die":
			return _die(pid, cmd)
		"loot_grave":
			return _loot_grave(pid, cmd)
		"move":
			return _move(pid, cmd)
		"board":
			return _board(pid, cmd)
		"disembark":
			return _disembark(pid, cmd)
		"light":
			return _light(pid, cmd)
		"load_station":
			return _load_station(pid, cmd)
		"cancel_station":
			return _cancel_station(pid, cmd)
		"collect":
			return _collect(pid, cmd)
		"eat":
			return _eat(pid, cmd)
		"sleep":
			return _sleep(pid, cmd)
		"steam":
			return _steam(pid, cmd)
		"store":
			return _store(pid, cmd)
		"take":
			return _take(pid, cmd)
		"unload":
			return _unload(pid, cmd)
		"offer":
			return _offer(pid, cmd)
		"meet":
			return _meet(pid, cmd)
		"explore":
			return _explore(pid, cmd)
		"set_tuning":
			return _set_tuning(pid, cmd)
		"right_boat":
			return _right_boat(pid, cmd)
		"capsize":
			return _capsize(pid, cmd)
		"spawn":
			return _spawn(pid, cmd)
		"despawn":
			return _despawn(pid, cmd)
		"creatures":
			return _creatures(pid, cmd)
		"hurt":
			return _hurt(pid, cmd)
		"attack":
			return _attack(pid, cmd)
		"join":
			return _join(pid, cmd)
		"douse":
			return _douse(pid, cmd)
		"steal":
			return _steal(pid, cmd)
		"arena_lantern":
			return _arena_lantern(pid, cmd)
		"tick":
			return _tick(pid, cmd)
		"debug":
			return _debug(pid, cmd)
	return _fail("unknown_command")


## The mode's rules with the world's fine-tuning overrides on top.
func rules() -> Dictionary:
	return state.rules()


# ---------------------------------------------------------------- commands

func _gather(pid: String, cmd: Dictionary) -> Dictionary:
	var node := String(cmd.get("node", ""))
	var item := String(cmd.get("item", ""))
	var qty := clampi(int(cmd.get("qty", 1)), 1, GATHER_MAX)
	if node == "":
		return _fail("bad_node")
	if int(state.depleted.get(node, 0)) > state.day:
		return _fail("depleted")
	var it: Dictionary = db.items.get(item, {})
	if not it.has("gather"):
		return _fail("not_gatherable")
	if map != null:
		var n := map.node(node)
		if n.is_empty():
			return _fail("bad_node")
		if not item in (n["items"] as Array):
			return _fail("not_here")
		var p: Vector3 = state.players[pid]["pos"]
		var np: Vector3 = n["pos"]
		if Vector2(p.x, p.z).distance_to(Vector2(np.x, np.z)) > float(n.get("reach", WorldMap.REACH_M + float(n["solid"]))):
			return _fail("too_far")
	var g: Dictionary = it["gather"]
	if not db.region_open(g["region"], state.lit):
		return _fail("region_locked")
	var inv := state.inv(pid)
	if g["tool"] != "hand" and inv.best_tool_tier(g["tool"]) < int(g.get("tool_tier", 1)):
		return _fail("need_tool")
	var left := inv.add(item, qty)
	if left == qty:
		return _fail("no_space")
	var days := int(db.balance["respawn"]["berries_days"] if it["kind"] == "food" else db.balance["respawn"]["resource_nodes_days"])
	state.depleted[node] = state.day + days
	return _ok([{"type": "gathered", "player": pid, "node": node, "item": item, "n": qty - left}])


func _craft(pid: String, cmd: Dictionary) -> Dictionary:
	var rid := String(cmd.get("recipe", ""))
	var times := clampi(int(cmd.get("times", 1)), 1, 99)
	if Crafting.is_background(db, rid):
		return _fail("background")
	var reason := Crafting.apply(db, state, pid, rid, times)
	if reason != "":
		return _fail(reason)
	return _ok([{"type": "crafted", "player": pid, "recipe": rid, "times": times}])


func _place(pid: String, cmd: Dictionary) -> Dictionary:
	var piece_id := String(cmd.get("piece", ""))
	var p: Dictionary = db.pieces.get(piece_id, {})
	if p.is_empty():
		return _fail("unknown_piece")
	if not db.is_unlocked(p["unlock"], state.lit):
		return _fail("locked")
	var cost := ContentDB.bag(p["cost"])
	var inv := state.inv(pid)
	var pos := WorldState._to_v3(cmd.get("pos", []))
	var rot := wrapf(float(cmd.get("rot", 0.0)), -PI, PI)
	if map != null and (not _sane(pos) or not _near(pid, pos, PLACE_REACH_M)):
		return _fail("too_far")
	var why := Building.check(db, state, map, piece_id, pos, rot)
	if why != "":
		return _fail(why)
	if not inv.has_bag(cost):
		return _fail("missing")
	if cmd.get("dry", false):
		return _ok([])  # the build mode's ghost asks "would it stand?" without building anything
	inv.remove_bag(cost)
	var uid := state.new_uid("p")
	state.pieces[uid] = {"id": piece_id, "pos": pos, "rot": rot, "owner": pid}
	if p.has("storage"):
		state.pieces[uid]["inv"] = Inventory.new(db, int(p["storage"]))
	if p.get("spawn", false):
		state.players[pid]["spawn"] = pos
	return _ok([{"type": "piece_placed", "uid": uid, "piece": piece_id, "pos": WorldState._v3(pos), "rot": rot, "player": pid}])


func _remove(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	if not state.pieces.has(uid):
		return _fail("unknown_uid")
	var pc: Dictionary = state.pieces[uid]
	if map != null and not _near(pid, pc["pos"], PLACE_REACH_M):
		return _fail("too_far")
	if pc.has("inv") and not (pc["inv"] as Inventory).is_empty():
		return _fail("not_empty")
	if not (pc.get("queue", []) as Array).is_empty() or not (pc.get("out", {}) as Dictionary).is_empty():
		return _fail("not_empty")
	var cost := ContentDB.bag(db.pieces[pc["id"]]["cost"])
	var inv := state.inv(pid)
	if not inv.can_fit(cost):
		return _fail("no_space")
	for k: String in cost:
		inv.add(k, cost[k])  # full refund: rebuilding should never feel like a loss
	state.pieces.erase(uid)
	return _ok([{"type": "piece_removed", "uid": uid, "player": pid}])


## Saga (docs/01_GDD.md §5.3): the beacons of b03, b06, b09 and b12 wait for their guardian to be beaten; the
## others want the fire defended while it kindles (beacons.json → saga.seconds). The fighter must be on the
## beacon's island. A defence needs the fuel in the bag (it burns only if the fire holds); a guardian fight
## brings the guardian (creatures.json → beacon). While a fight goes on the mode can't change.
func _begin_fight(pid: String, cmd: Dictionary) -> Dictionary:
	var bid := String(cmd.get("beacon", ""))
	if not db.beacons.has(bid):
		return _fail("unknown_beacon")
	if rules()["beacon"] != "guardian_or_defense":
		return _fail("not_in_this_mode")
	if state.busy_beacon != "":
		return _fail("busy")
	var b: Dictionary = db.beacons[bid]
	if not db.region_open(b["region"], state.lit):
		return _fail("region_locked")
	if state.lit.has(bid) or state.trials_done.has(bid):
		return _fail("already_done")
	var pos: Vector3 = state.players[pid]["pos"]
	if map != null:
		var isl: IslandGen = map.by_id[bid]
		if Vector2(pos.x, pos.z).distance_to(isl.center) > isl.radius * IslandGen.MARGIN:
			return _fail("too_far")
	var kind := String(b["saga"]["type"])
	var events: Array[Dictionary] = []
	state.busy_beacon = bid
	state.fight = {"beacon": bid, "kind": kind, "player": pid}
	if kind == "defense":
		if not state.inv(pid).has_bag(ContentDB.bag(b["fuel"])):
			state.busy_beacon = ""
			state.fight = {}
			return _fail("missing")
		state.fight["until"] = state.clock_min + float(b["saga"]["seconds"]) / 60.0
		state.fight["fire"] = 100.0
	else:
		var boss := guardian_of(bid)
		var at := db.beacon_pos(bid)
		var bp := Vector3(at.x, map.ground_at(at.x, at.y) if map != null else 0.0, at.y)
		var uid := state.new_uid("c")
		state.creatures[uid] = {"id": boss, "pos": bp, "hp": float(Creatures.info(db, boss)["hp"]), "fight": bid}
		state.fight["boss"] = uid
		state.fight["phase"] = 1
		state.fight["lanterns"] = []
		events.append({"type": "creature_spawned", "uid": uid, "id": boss, "pos": WorldState._v3(bp), "fight": true})
	events.push_front({"type": "fight_started", "beacon": bid, "kind": kind, "player": pid, "until": float(state.fight.get("until", -1.0))})
	return _ok(events)


## The guardian of a beacon (creatures.json → beacon), "" if it has none.
func guardian_of(bid: String) -> String:
	for id: String in db.creatures:
		if String(db.creatures[id].get("beacon", "")) == bid:
			return id
	return ""


## The fight ends: its creatures go back into the fog. Lost = nothing spent, try again any time.
func _end_fight(won: bool) -> Array[Dictionary]:
	var bid := state.busy_beacon
	var events: Array[Dictionary] = []
	for uid: String in state.creatures.keys():
		if String(state.creatures[uid]["fight"]) == bid:
			state.creatures.erase(uid)
			events.append({"type": "creature_gone", "uid": uid})
	state.busy_beacon = ""
	state.fight = {}
	events.append({"type": "fight_ended", "beacon": bid, "won": won})
	return events


## A hit on a creature (Tale and Saga): the best weapon in the bag (or the one named), heavy = balance.combat
## heavy_k; the aurora spear and fire in hand hurt fog creatures more; a bow needs an arrow and reaches far.
## Friendly creatures can't be struck at all (no hunting seals, no harming spirits). A beaten guardian passes
## the beacon's trial; a creature's drops go into the bag.
func _attack(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("target", ""))
	var c: Dictionary = state.creatures.get(uid, {})
	if c.is_empty():
		return _fail("unknown_uid")
	var id := String(c["id"])
	if Creatures.is_friendly(db, id):
		return _fail("friendly")
	var p: Dictionary = state.players[pid]
	var inv: Inventory = p["inv"]
	var weapon := String(cmd.get("weapon", ""))
	if weapon == "":
		weapon = best_weapon(inv)
	var cb: Dictionary = db.balance["combat"]
	var damage := float(cb["fist_damage"])
	var reach := float(cb["reach_bare"])
	if weapon != "":
		if inv.count(weapon) < 1 or not db.items[weapon].has("weapon"):
			return _fail("missing")
		var w: Dictionary = db.items[weapon]["weapon"]
		damage = float(w["damage"])
		reach = float(w.get("reach", 30.0))
		if w.has("ammo") and not inv.remove(String(w["ammo"]), 1):
			return _fail("no_ammo")
		if Creatures.group(db, id) in ["fog", "elite"]:
			damage *= float(w.get("vs_fog", 1.0))
	if Creatures.group(db, id) in ["fog", "elite"] and not (p["light"] as Dictionary).is_empty():
		damage *= float(cb["light_vs_fog"])  # fire in hand is a weapon against the fog
	if bool(cmd.get("heavy", false)):
		damage *= float(cb["heavy_k"])
	if id == "bolotnitsa" and not (p["light"] as Dictionary).is_empty():
		damage *= float(cb["light_vs_fog"])  # the Bog Maiden burns away with torches
	if id == "mga" and (state.fight.get("lanterns", []) as Array).size() >= ARENA_LANTERNS:
		damage *= 2.0  # weak while every lantern around the arena burns
	var slack := 3.0 if Creatures.group(db, id) == "guardian" else 1.2  # big bodies
	if (c["pos"] as Vector3).distance_to(p["pos"]) > reach + slack:
		return _fail("too_far")
	var info := Creatures.info(db, id)
	var before := float(c["hp"])
	c["hp"] = maxf(0.0, before - damage)
	var events: Array[Dictionary] = [{"type": "creature_hit", "uid": uid, "id": id, "player": pid, "amount": damage, "hp": c["hp"], "weapon": weapon}]
	var phases := int(info.get("phases", 1))
	if phases > 1:
		var full := float(info["hp"])
		var was := 1 + int(floor((1.0 - before / full) * phases))
		var now := 1 + int(floor((1.0 - float(c["hp"]) / full) * phases))
		if now > was and float(c["hp"]) > 0.0:
			state.fight["phase"] = mini(now, phases)
			events.append({"type": "guardian_phase", "uid": uid, "id": id, "phase": mini(now, phases)})
	if float(c["hp"]) <= 0.0:
		state.creatures.erase(uid)
		var drops := ContentDB.bag(info.get("drops", {}))
		for k: String in drops:
			inv.add(k, drops[k])
		events.append({"type": "creature_died", "uid": uid, "id": id, "player": pid, "drops": drops})
		if String(info["group"]) == "elite":
			state.spirits[id] = {"beaten_day": state.day}  # Likho stays beaten; Karachun comes back another night
		events.append_array(_journal(pid, id))
		if String(info["group"]) == "guardian" and String(c["fight"]) != "":
			var bid := String(c["fight"])
			state.trials_done[bid] = "guardian"
			events.append({"type": "trial_done", "beacon": bid, "kind": "guardian", "player": pid})
			events.append_array(_end_fight(true))
	return _ok(events)


## Host-only: a creature of a fire defence reaches the kindling fire and beats at it. At zero the fire goes
## out: the defence is lost, and nothing is spent (the fuel only burns when the fire holds).
func _douse(_pid: String, cmd: Dictionary) -> Dictionary:
	var src := String(cmd.get("source", ""))
	var c: Dictionary = state.creatures.get(src, {})
	if c.is_empty() or state.fight.is_empty() or String(state.fight["kind"]) != "defense" or String(c["fight"]) != state.busy_beacon:
		return _fail("no_fight")
	var at := db.beacon_pos(state.busy_beacon)
	if Vector2((c["pos"] as Vector3).x, (c["pos"] as Vector3).z).distance_to(at) > 6.0:
		return _fail("too_far")
	var fire := maxf(0.0, float(state.fight["fire"]) - float(Creatures.info(db, String(c["id"]))["damage"]))
	state.fight["fire"] = fire
	var events: Array[Dictionary] = [{"type": "fire_doused", "beacon": state.busy_beacon, "fire": fire}]
	if fire <= 0.0:
		events.append_array(_end_fight(false))
	return _ok(events)


## Host-only: a gull snatches one thing from a drying rack's finished output.
func _steal(_pid: String, cmd: Dictionary) -> Dictionary:
	var src := String(cmd.get("source", ""))
	var c: Dictionary = state.creatures.get(src, {})
	var rack := String(cmd.get("uid", ""))
	var pc: Dictionary = state.pieces.get(rack, {})
	if c.is_empty() or String(Creatures.info(db, String(c["id"])).get("behaviour", "")) != "thief" or pc.is_empty():
		return _fail("unknown_uid")
	var out: Dictionary = pc.get("out", {})
	if out.is_empty():
		return _fail("nothing")
	var k: String = out.keys()[0]
	out[k] = int(out[k]) - 1
	if int(out[k]) <= 0:
		out.erase(k)
	return _ok([{"type": "stolen", "uid": rack, "item": k, "by": src}])


## The Mga's arena: light a lantern with fire in hand (0..ARENA_LANTERNS-1) during the fight on the Lodestar.
func _arena_lantern(pid: String, cmd: Dictionary) -> Dictionary:
	var i := int(cmd.get("i", -1))
	if state.fight.is_empty() or guardian_of(String(state.fight["beacon"])) != "mga":
		return _fail("no_fight")
	if i < 0 or i >= ARENA_LANTERNS:
		return _fail("bad_value")
	if (state.players[pid]["light"] as Dictionary).is_empty():
		return _fail("no_fire")
	var lit: Array = state.fight["lanterns"]
	if not lit.has(i):
		lit.append(i)
	return _ok([{"type": "arena_lantern", "i": i, "lit": lit.size(), "player": pid}])


## The strongest weapon in a bag ("" = bare hands). A bow counts only with arrows.
func best_weapon(inv: Inventory) -> String:
	var best := ""
	var best_dmg := 0.0
	for s: Dictionary in inv.slots:
		if s.is_empty() or not db.items[s["id"]].has("weapon"):
			continue
		var w: Dictionary = db.items[s["id"]]["weapon"]
		if w.has("ammo") and inv.count(String(w["ammo"])) < 1:
			continue
		if float(w["damage"]) > best_dmg:
			best_dmg = float(w["damage"])
			best = s["id"]
	return best


## A fire defence holds until its time runs out: the trial is passed and the beacon lights with the fighter's
## fuel. (Losing is handled by _die: the fire goes out and nothing is spent.)
func _tick_fight() -> Array[Dictionary]:
	if state.fight.is_empty() or String(state.fight["kind"]) != "defense" or state.clock_min < float(state.fight["until"]):
		return []
	var bid := String(state.fight["beacon"])
	var pid := String(state.fight["player"])
	state.trials_done[bid] = "defense"
	var events: Array[Dictionary] = [{"type": "trial_done", "beacon": bid, "kind": "defense", "player": pid}]
	events.append_array(_end_fight(true))
	if state.players.has(pid) and state.inv(pid).remove_bag(ContentDB.bag(db.beacons[bid]["fuel"])):
		state.lit[bid] = state.day
		events.append({"type": "beacon_lit", "beacon": bid, "player": pid, "unlocks": db.unlocks_of(bid)})
		if db.beacons[bid].get("opens") != null:
			events.append({"type": "region_opened", "region": db.beacons[bid]["opens"]})
	return events


func _complete_trial(pid: String, cmd: Dictionary) -> Dictionary:
	var bid := String(cmd.get("beacon", ""))
	var kind := String(cmd.get("kind", "trial"))
	if not db.beacons.has(bid):
		return _fail("unknown_beacon")
	var b: Dictionary = db.beacons[bid]
	if not db.region_open(b["region"], state.lit):
		return _fail("region_locked")
	var expected := "trial"
	if rules()["beacon"] == "guardian_or_defense":
		expected = String(b["saga"]["type"])
	if kind != expected:
		return _fail("wrong_trial")
	if expected != "trial" and state.busy_beacon != bid:
		return _fail("no_fight")
	if map != null and expected == "trial":
		var why := _trial_check(pid, bid)
		if why != "":
			return _fail(why)
	state.trials_done[bid] = kind
	var events: Array[Dictionary] = [{"type": "trial_done", "beacon": bid, "kind": kind, "player": pid}]
	if state.busy_beacon == bid:
		events.append_array(_end_fight(true))
	return _ok(events)


## What the host can see of a trial (docs/01_GDD.md §5.2): the player is on the beacon's island; "carry"
## ends at the tower with fire in hand; "climb" ends up on the tower's deck. The puzzles themselves (bells,
## lanterns, mirrors) run on the player's machine; their end is this command.
func _trial_check(pid: String, bid: String) -> String:
	var p: Dictionary = state.players[pid]
	var pos: Vector3 = p["pos"]
	var isl: IslandGen = map.by_id[bid]
	if Vector2(pos.x, pos.z).distance_to(isl.center) > isl.radius * IslandGen.MARGIN:
		return "too_far"
	var trial := String(db.beacons[bid]["trial"])
	var base := isl.height_at(isl.center.x, isl.center.y)
	if trial == "carry":
		if (p.get("light", {}) as Dictionary).is_empty():
			return "no_fire"
		if Vector2(pos.x, pos.z).distance_to(isl.center) > BEACON_REACH_M:
			return "too_far"
	elif trial == "climb" and pos.y < base + CLIMB_TOP_M:
		return "not_at_top"
	return ""


func _light_beacon(pid: String, cmd: Dictionary) -> Dictionary:
	var bid := String(cmd.get("beacon", ""))
	if not db.beacons.has(bid):
		return _fail("unknown_beacon")
	if state.lit.has(bid):
		return _fail("already_lit")
	var b: Dictionary = db.beacons[bid]
	if not db.region_open(b["region"], state.lit):
		return _fail("region_locked")
	if not state.trials_done.has(bid):
		return _fail("trial_not_done")
	var p: Dictionary = state.players[pid]
	var pos: Vector3 = p["pos"]
	if Vector2(pos.x, pos.z).distance_to(db.beacon_pos(bid)) > BEACON_REACH_M:
		return _fail("too_far")
	if not (p["inv"] as Inventory).remove_bag(ContentDB.bag(b["fuel"])):
		return _fail("missing")
	state.lit[bid] = state.day
	var events: Array[Dictionary] = [{"type": "beacon_lit", "beacon": bid, "player": pid, "unlocks": db.unlocks_of(bid)}]
	if b.get("opens") != null:
		events.append({"type": "region_opened", "region": b["opens"]})
	return _ok(events)


func _set_mode(pid: String, cmd: Dictionary) -> Dictionary:
	var m := String(cmd.get("mode", ""))
	if not db.modes.has(m):
		return _fail("unknown_mode")
	if state.busy_beacon != "":
		return _fail("busy")
	var old := state.mode
	state.mode = m
	return _ok([{"type": "mode_changed", "from": old, "to": m, "player": pid}])


## Host-generated when a player's health reaches zero (or they fall/drown in Quiet).
func _die(pid: String, _cmd: Dictionary) -> Dictionary:
	var r := rules()
	var p: Dictionary = state.players[pid]
	var death := String(r["death"])
	var at: Vector3 = p["landed"] if death == "none" else p["spawn"]  # Quiet: back to the last landing
	var ev := {"type": "respawn", "player": pid, "at": WorldState._v3(at), "death": death, "cause": String(_cmd.get("cause", ""))}
	p["aboard"] = ""
	if death == "grave":
		var inv: Inventory = p["inv"]
		if not inv.is_empty():
			var uid := state.new_uid("g")
			state.graves[uid] = {"owner": pid, "pos": p["pos"], "inv": inv.to_dict()}
			p["inv"] = Inventory.new(db, inv.size)
			ev["grave"] = uid
	var debuff := float(r["death_debuff_min"])
	if debuff > 0.0:
		p["weary_until"] = state.clock_min + debuff
	p["pos"] = at
	p["hp"] = Vitals.max_hp(db, state, pid)
	p["stance"] = ""
	var events: Array[Dictionary] = [ev]
	if state.busy_beacon != "":
		events.append_array(_end_fight(false))  # a lost fight can simply be retried; no fuel was spent
	return _ok(events)


func _loot_grave(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	if not state.graves.has(uid):
		return _fail("unknown_uid")
	var g: Dictionary = state.graves[uid]
	var p: Dictionary = state.players[pid]
	if (p["pos"] as Vector3).distance_to(g["pos"]) > Crafting.REACH_M:
		return _fail("too_far")
	var stash := Inventory.new(db)
	stash.from_dict(g["inv"])
	var inv: Inventory = p["inv"]
	for s: Dictionary in stash.slots:
		if s.is_empty():
			continue
		var left := inv.add(s["id"], s["n"])
		s["n"] = left
		if left == 0:
			s.clear()
	if stash.is_empty():
		state.graves.erase(uid)
	else:
		g["inv"] = stash.to_dict()
	return _ok([{"type": "grave_looted", "uid": uid, "player": pid, "emptied": not state.graves.has(uid)}])


## Where the player is (and the boat they steer). Sent by the local player a few times a second; the host
## needs it to check reach for every other command. No events: positions travel by the synchroniser.
func _move(pid: String, cmd: Dictionary) -> Dictionary:
	var pos := WorldState._to_v3(cmd.get("pos", []))
	if not _sane(pos):
		return _fail("bad_pos")
	var p: Dictionary = state.players[pid]
	p["pos"] = pos
	var stance := String(cmd.get("stance", ""))
	p["stance"] = stance if stance in ["block", "dodge"] else ""
	var uid: String = p["aboard"]
	if uid != "" and state.boats.has(uid) and cmd.has("boat_pos"):
		var bp := WorldState._to_v3(cmd["boat_pos"])
		if _sane(bp):
			state.boats[uid]["pos"] = bp
			state.boats[uid]["yaw"] = wrapf(float(cmd.get("boat_yaw", 0.0)), -PI, PI)
	return _ok([])


func _board(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("boat", ""))
	if not state.boats.has(uid):
		return _fail("unknown_boat")
	var p: Dictionary = state.players[pid]
	if p["aboard"] != "":
		return _fail("already_aboard")
	var bp: Vector3 = state.boats[uid]["pos"]
	var pp: Vector3 = p["pos"]
	if Vector2(pp.x, pp.z).distance_to(Vector2(bp.x, bp.z)) > BOARD_REACH_M:
		return _fail("too_far")
	p["aboard"] = uid
	p["pos"] = bp
	return _ok([{"type": "boarded", "player": pid, "boat": uid}])


func _disembark(pid: String, cmd: Dictionary) -> Dictionary:
	var p: Dictionary = state.players[pid]
	var uid: String = p["aboard"]
	if uid == "":
		return _fail("not_aboard")
	var pos := WorldState._to_v3(cmd.get("pos", []))
	var bp: Vector3 = state.boats[uid]["pos"]
	if not _sane(pos) or Vector2(pos.x, pos.z).distance_to(Vector2(bp.x, bp.z)) > LAND_REACH_M:
		return _fail("too_far")
	if map != null and map.ground_at(pos.x, pos.z) < 0.2:
		return _fail("no_land")
	p["aboard"] = ""
	p["pos"] = pos
	p["landed"] = pos
	return _ok([{"type": "disembarked", "player": pid, "boat": uid, "pos": WorldState._v3(pos)}])


## Light in hand (items.json → light): a torch burns one torch item for `minutes`; a lantern burns one
## `fuel` per `minutes_per_fuel`; the aurora lantern never goes out. {"item": ""} puts the light out.
func _light(pid: String, cmd: Dictionary) -> Dictionary:
	var item := String(cmd.get("item", ""))
	var p: Dictionary = state.players[pid]
	if item == "":
		p["light"] = {}
		return _ok([{"type": "light_changed", "player": pid, "item": ""}])
	var it: Dictionary = db.items.get(item, {})
	if not it.has("light"):
		return _fail("not_a_light")
	var inv: Inventory = p["inv"]
	if inv.count(item) < 1:
		return _fail("missing")
	var l: Dictionary = it["light"]
	var until := -1.0  # forever
	if l.has("fuel"):
		if not inv.remove(String(l["fuel"]), 1):
			return _fail("no_fuel")
		until = state.clock_min + float(l["minutes_per_fuel"])
	elif float(l.get("minutes", 0.0)) > 0.0:
		inv.remove(item, 1)
		until = state.clock_min + float(l["minutes"])
	p["light"] = {"id": item, "until": until}
	return _ok([{"type": "light_changed", "player": pid, "item": item, "until": until}])


## Put a long recipe into a station: the inputs leave the bag now, the output waits in the station.
func _load_station(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	var rid := String(cmd.get("recipe", ""))
	var times := clampi(int(cmd.get("times", 1)), 1, 99)
	var pc: Dictionary = state.pieces.get(uid, {})
	if pc.is_empty():
		return _fail("unknown_uid")
	var r: Dictionary = db.recipes.get(rid, {})
	if r.is_empty():
		return _fail("unknown_recipe")
	if r["station"] != pc["id"]:
		return _fail("wrong_station")
	if not Crafting.is_background(db, rid):
		return _fail("not_background")
	if not db.is_unlocked(r["unlock"], state.lit):
		return _fail("locked")
	if not _near(pid, pc["pos"], Crafting.REACH_M):
		return _fail("too_far")
	var queue: Array = pc.get("queue", [])
	if queue.size() >= int(db.balance["stations"]["queue_max"]):
		return _fail("queue_full")
	if not state.inv(pid).remove_bag(Crafting.scaled(r["inputs"], times)):
		return _fail("missing")
	queue.append({"recipe": rid, "times": times, "left_s": float(r["time_s"])})
	pc["queue"] = queue
	return _ok([{"type": "station_loaded", "uid": uid, "recipe": rid, "times": times, "player": pid}])


## Take a load back out: every unit not finished yet returns its inputs in full.
func _cancel_station(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	var idx := int(cmd.get("index", 0))
	var pc: Dictionary = state.pieces.get(uid, {})
	if pc.is_empty():
		return _fail("unknown_uid")
	if not _near(pid, pc["pos"], Crafting.REACH_M):
		return _fail("too_far")
	var queue: Array = pc.get("queue", [])
	if idx < 0 or idx >= queue.size():
		return _fail("unknown_uid")
	var q: Dictionary = queue[idx]
	var back := Crafting.scaled(db.recipes[q["recipe"]]["inputs"], int(q["times"]))
	var inv := state.inv(pid)
	if not inv.can_fit(back):
		return _fail("no_space")
	for k: String in back:
		inv.add(k, back[k])
	queue.remove_at(idx)
	return _ok([{"type": "station_canceled", "uid": uid, "recipe": q["recipe"], "player": pid}])


## Take what the station made (as much as fits in the bag; the rest waits).
func _collect(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	var pc: Dictionary = state.pieces.get(uid, {})
	if pc.is_empty():
		return _fail("unknown_uid")
	if not _near(pid, pc["pos"], Crafting.REACH_M):
		return _fail("too_far")
	var out: Dictionary = pc.get("out", {})
	if out.is_empty():
		return _fail("empty")
	var inv := state.inv(pid)
	var got := {}
	for k: String in out.keys():
		var left := inv.add(k, int(out[k]))
		if int(out[k]) - left > 0:
			got[k] = int(out[k]) - left
		if left == 0:
			out.erase(k)
		else:
			out[k] = left
	if got.is_empty():
		return _fail("no_space")
	return _ok([{"type": "station_collected", "uid": uid, "items": got, "player": pid}])


## Food: three slots (balance.player.food_slots), no two of the same dish; the bonus lasts food.minutes.
func _eat(pid: String, cmd: Dictionary) -> Dictionary:
	var item := String(cmd.get("item", ""))
	var it: Dictionary = db.items.get(item, {})
	if not it.has("food"):
		return _fail("not_food")
	var p: Dictionary = state.players[pid]
	var food: Array = p["food"]
	for f: Dictionary in food:
		if f["id"] == item:
			return _fail("already_eaten")
	if food.size() >= int(db.balance["player"]["food_slots"]):
		return _fail("food_full")
	if not (p["inv"] as Inventory).remove(item, 1):
		return _fail("missing")
	var until := state.clock_min + float(it["food"]["minutes"])
	food.append({"id": item, "until": until})
	return _ok([{"type": "ate", "player": pid, "item": item, "until": until}])


## Sleep in a bed: "Rested" for base_min + comfort × per_comfort_min (+ a pearl necklace's minutes).
func _sleep(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	var pc: Dictionary = state.pieces.get(uid, {})
	if pc.is_empty() or not db.pieces[pc["id"]].get("spawn", false):
		return _fail("unknown_uid")
	if not _near(pid, pc["pos"], USE_REACH_M):
		return _fail("too_far")
	var comfort := int(Comfort.at(db, state, pc["pos"])["total"])
	var minutes := Comfort.rested_minutes(db, comfort)
	var p: Dictionary = state.players[pid]
	for s: Dictionary in (p["inv"] as Inventory).slots:
		if not s.is_empty() and db.items[s["id"]].has("trinket"):
			minutes += float(db.items[s["id"]]["trinket"].get("rested_minutes", 0.0))
			break
	p["rested_until"] = state.clock_min + minutes
	p["spawn"] = pc["pos"]
	return _ok([{"type": "slept", "player": pid, "uid": uid, "comfort": comfort, "minutes": minutes}])


## Steam in the bathhouse: warmth and faster stamina for balance.steam.minutes.
func _steam(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	var pc: Dictionary = state.pieces.get(uid, {})
	if pc.is_empty() or String(db.pieces[pc["id"]].get("buff", "")) != "steam":
		return _fail("unknown_uid")
	if not _near(pid, pc["pos"], USE_REACH_M):
		return _fail("too_far")
	# the bannik: after midnight the steam is his (no bonus that day); keep the rule and it lasts longer
	var minutes := float(db.balance["steam"]["minutes"])
	var bannik := "pleased"
	if Weather.after_midnight(db, state.clock_min):
		state.spirits["bannik"] = {"angry_day": state.day}
		bannik = "angry"
	elif int((state.spirits.get("bannik", {}) as Dictionary).get("angry_day", -1)) == state.day:
		bannik = "angry"
	else:
		minutes *= 1.0 + float(db.balance["spirits"]["bannik_steam_bonus"])
	state.players[pid]["steam_until"] = state.clock_min + minutes
	var events: Array[Dictionary] = [{"type": "steamed", "player": pid, "uid": uid, "minutes": minutes, "bannik": bannik}]
	events.append_array(_journal(pid, "bannik"))
	return _ok(events)


## A container the player can reach: a chest (within USE_REACH_M) or a boat's hold (aboard or beside it).
func _container(pid: String, uid: String) -> Inventory:
	if state.pieces.has(uid):
		var pc: Dictionary = state.pieces[uid]
		if pc.has("inv") and _near(pid, pc["pos"], USE_REACH_M):
			return pc["inv"]
		return null
	if state.boats.has(uid):
		var b: Dictionary = state.boats[uid]
		if state.players[pid]["aboard"] == uid or _near(pid, b["pos"], BOARD_REACH_M):
			return b["cargo"]
	return null


static func _move_stack(from: Inventory, slot: int, to: Inventory) -> int:
	if slot < 0 or slot >= from.size or from.slots[slot].is_empty():
		return 0
	var s: Dictionary = from.slots[slot]
	var n := int(s["n"])
	var left := to.add(String(s["id"]), n)
	var moved := n - left
	if left == 0:
		from.slots[slot] = {}
	else:
		s["n"] = left
	return moved


## Bag slot → chest or hold.
func _store(pid: String, cmd: Dictionary) -> Dictionary:
	var box := _container(pid, String(cmd.get("uid", "")))
	if box == null:
		return _fail("too_far")
	var inv := state.inv(pid)
	var slot := int(cmd.get("slot", -1))
	var id := String(inv.slots[slot].get("id", "")) if slot >= 0 and slot < inv.size else ""
	var moved := _move_stack(inv, slot, box)
	if moved == 0:
		return _fail("no_space" if id != "" else "empty")
	return _ok([{"type": "stored", "player": pid, "uid": cmd["uid"], "item": id, "n": moved}])


## Chest or hold slot → bag.
func _take(pid: String, cmd: Dictionary) -> Dictionary:
	var box := _container(pid, String(cmd.get("uid", "")))
	if box == null:
		return _fail("too_far")
	var slot := int(cmd.get("slot", -1))
	var id := String(box.slots[slot].get("id", "")) if slot >= 0 and slot < box.size else ""
	var moved := _move_stack(box, slot, state.inv(pid))
	if moved == 0:
		return _fail("no_space" if id != "" else "empty")
	return _ok([{"type": "taken", "player": pid, "uid": cmd["uid"], "item": id, "n": moved}])


## "All into the storehouse": the boat's hold into a chest near the pier (within 30 m of the boat).
func _unload(pid: String, cmd: Dictionary) -> Dictionary:
	var boat_uid := String(cmd.get("boat", ""))
	var chest_uid := String(cmd.get("chest", ""))
	var hold := _container(pid, boat_uid)
	var pc: Dictionary = state.pieces.get(chest_uid, {})
	if hold == null or pc.is_empty() or not pc.has("inv"):
		return _fail("unknown_uid")
	if (pc["pos"] as Vector3).distance_to(state.boats[boat_uid]["pos"]) > 30.0:
		return _fail("too_far")
	var moved := 0
	for i in hold.size:
		moved += _move_stack(hold, i, pc["inv"])
	if moved == 0:
		return _fail("no_space" if not hold.is_empty() else "empty")
	return _ok([{"type": "unloaded", "player": pid, "boat": boat_uid, "chest": chest_uid, "n": moved}])


func _near(pid: String, pos: Vector3, reach: float) -> bool:
	return (state.players[pid]["pos"] as Vector3).distance_to(pos) <= reach


## Host-only: world time passes (Game sends it once a second while someone plays; no one playing = no time).
func _tick(_pid: String, cmd: Dictionary) -> Dictionary:
	var dt := clampf(float(cmd.get("dt_min", 0.0)), 0.0, 1.0)
	var events: Array[Dictionary] = []
	var day_len := float(db.balance["day"]["length_min"])
	state.clock_min += dt
	var day := 1 + int(floor(state.clock_min / day_len))
	if day != state.day:
		state.day = day
		events.append({"type": "day_changed", "day": day})
		events.append_array(_tick_domovoy())
	for pid: String in state.players:
		events.append_array(_tick_light(pid))
		events.append_array(_tick_food(pid))
		events.append_array(_tick_body(pid, dt))
	events.append_array(_tick_fight())
	events.append_array(_tick_stations(dt * 60.0))
	return _ok(events)


## Food runs out: the slot frees up.
func _tick_food(pid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var food: Array = state.players[pid]["food"]
	for i in range(food.size() - 1, -1, -1):
		if float(food[i]["until"]) <= state.clock_min:
			out.append({"type": "food_gone", "player": pid, "item": food[i]["id"]})
			food.remove_at(i)
	return out


## Stations cook their queues: each finished unit goes into the station's output ("out").
func _tick_stations(seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		var queue: Array = pc.get("queue", [])
		var t := seconds
		while t > 0.0 and not queue.is_empty():
			var q: Dictionary = queue[0]
			var step := minf(t, float(q["left_s"]))
			q["left_s"] = float(q["left_s"]) - step
			t -= step
			if float(q["left_s"]) > 0.0:
				break
			var r: Dictionary = db.recipes[q["recipe"]]
			if not pc.has("out"):
				pc["out"] = {}
			for k: String in r["output"]:
				pc["out"][k] = int(pc["out"].get(k, 0)) + int(r["output"][k])
			q["times"] = int(q["times"]) - 1
			events.append({"type": "station_done", "uid": uid, "recipe": q["recipe"]})
			if int(q["times"]) <= 0:
				queue.pop_front()
			else:
				q["left_s"] = float(r["time_s"])
	return events


## Lights burn down; a lantern takes its next fuel from the bag by itself.
func _tick_light(pid: String) -> Array[Dictionary]:
	var p: Dictionary = state.players[pid]
	var l: Dictionary = p.get("light", {})
	if l.is_empty() or float(l["until"]) < 0.0 or float(l["until"]) > state.clock_min:
		return []
	var it: Dictionary = db.items[l["id"]]["light"]
	var inv: Inventory = p["inv"]
	if it.has("fuel") and inv.count(String(l["id"])) > 0 and inv.remove(String(it["fuel"]), 1):
		l["until"] = state.clock_min + float(it["minutes_per_fuel"])
		return []
	p["light"] = {}
	return [{"type": "light_changed", "player": pid, "item": "", "burnt_out": true}]


## Debug-only (allow_debug): {"give": {item: n}, "trial": beacon, "pos": [x, y, z], "clock_min": t, "journal": page,
## "hp": value, "spawn": creature id + "pos" (still only what the mode allows)}.
func _debug(pid: String, cmd: Dictionary) -> Dictionary:
	if not allow_debug:
		return _fail("unknown_command")
	var p: Dictionary = state.players[pid]
	var events: Array[Dictionary] = []
	var give: Dictionary = cmd.get("give", {})
	for k: String in give:
		if db.items.has(k):
			(p["inv"] as Inventory).add(k, int(give[k]))
			events.append({"type": "gathered", "player": pid, "node": "", "item": k, "n": int(give[k])})
	if cmd.has("trial") and db.beacons.has(String(cmd["trial"])):
		var bid := String(cmd["trial"])
		var kind := "trial" if rules()["beacon"] == "trial" else String(db.beacons[bid]["saga"]["type"])
		state.trials_done[bid] = kind
		events.append({"type": "trial_done", "beacon": bid, "kind": kind, "player": pid})
	if cmd.has("pos"):
		p["pos"] = WorldState._to_v3(cmd["pos"])
	if cmd.has("clock_min"):
		state.clock_min = float(cmd["clock_min"])
	if cmd.has("journal"):
		state.journal[String(cmd["journal"])] = state.day
	if cmd.has("hp"):
		p["hp"] = clampf(float(cmd["hp"]), 1.0, Vitals.max_hp(db, state, pid))
		p["hurt_at"] = state.clock_min
	if cmd.has("spawn") and Creatures.allowed(db, state.mode, rules(), String(cmd["spawn"])):
		var uid := state.new_uid("c")
		var at := WorldState._to_v3(cmd.get("pos", []))
		var cid := String(cmd["spawn"])
		state.creatures[uid] = {"id": cid, "pos": at, "hp": float(Creatures.info(db, cid)["hp"]), "fight": state.busy_beacon}
		events.append({"type": "creature_spawned", "uid": uid, "id": cid, "pos": WorldState._v3(at), "fight": state.busy_beacon != ""})
	return _ok(events)


# ---------------------------------------------------------------- life of the world (phase 6)

## Host-only: a co-op friend joins (docs/04_TECH_SPEC.md §7). New players start on foot at the home pier;
## someone who played here before comes back as they were.
func _join(_pid: String, cmd: Dictionary) -> Dictionary:
	var who := String(cmd.get("player", ""))
	if not who.begins_with("p") or not who.trim_prefix("p").is_valid_int():
		return _fail("unknown_player")
	var fresh := not state.players.has(who)
	var at: Vector3 = map.home["spawn"] if map != null else Vector3.ZERO
	state.add_player(who, at)
	return _ok([{"type": "player_joined", "player": who, "fresh": fresh}])


## A gift to a spirit (docs/01_GDD.md §11, creatures.json → gift): kalitki by the domovoy's bed (every
## balance.spirits.domovoy_gift_days), cloudberries on a stump of a big forested island for the leshy (his
## wisp leads the way), the first fish of the day for the vodyanoy on the Summer Shore or the Ter Coast.
func _offer(pid: String, cmd: Dictionary) -> Dictionary:
	var sp := String(cmd.get("spirit", ""))
	if not Creatures.is_spirit(db, sp):
		return _fail("unknown_creature")
	var gift := String(Creatures.info(db, sp).get("gift", ""))
	if gift == "":
		return _fail("no_gift")
	var p: Dictionary = state.players[pid]
	var inv: Inventory = p["inv"]
	if inv.count(gift) < 1:
		return _fail("missing")
	var sb: Dictionary = db.balance["spirits"]
	var pos: Vector3 = p["pos"]
	var mem: Dictionary = (state.spirits.get(sp, {}) as Dictionary).duplicate()
	var ev := {"type": "offered", "player": pid, "spirit": sp, "item": gift}
	match sp:
		"domovoy":
			var home := Creatures.domovoy_home(db, state)
			if home == "":
				return _fail("no_domovoy")
			if not _near(pid, state.pieces[home]["pos"], Creatures.HOME_REACH_M):
				return _fail("too_far")
			if Creatures.domovoy_fed(db, state):
				return _fail("not_hungry")
			mem["fed_until"] = state.clock_min + float(sb["domovoy_gift_days"]) * float(db.balance["day"]["length_min"])
		"leshy":
			if map != null:
				var isl := map.island_at(pos.x, pos.z)
				if isl == null or not map.forested(isl.id):
					return _fail("not_here")
			mem["guide_until"] = state.clock_min + float(sb["leshy_guide_s"]) / 60.0
			ev["until"] = mem["guide_until"]
		"vodyanoy":
			if not (db.regions[db.region_at(Vector2(pos.x, pos.z))]["creatures"] as Array).has("vodyanoy"):
				return _fail("not_here")
			if map != null and p["aboard"] == "" and map.ground_at(pos.x, pos.z) > 1.2:
				return _fail("not_here")  # at the water's edge or from a boat
			if Creatures.vodyanoy_boon(state):
				return _fail("not_hungry")
			mem["day"] = state.day
		_:
			return _fail("no_gift")
	inv.remove(gift, 1)
	state.spirits[sp] = mem
	var events: Array[Dictionary] = [ev]
	events.append_array(_journal(pid, sp))
	return _ok(events)


## Meeting a creature for the first time opens its page in the journal of tales. The host checks what it can:
## the creature lives in this mode and region; the wonders are where and when they come (the whale on calm
## nights of the Frozen Sea gives rest by its chapel; Sirin sings at dawn).
func _meet(pid: String, cmd: Dictionary) -> Dictionary:
	var id := String(cmd.get("creature", ""))
	if not Creatures.allowed(db, state.mode, rules(), id):
		return _fail("unknown_creature")
	var pos: Vector3 = state.players[pid]["pos"]
	var rid := db.region_at(Vector2(pos.x, pos.z))
	if not (db.regions[rid]["creatures"] as Array).has(id) and not Creatures.info(db, id).has("beacon"):
		return _fail("not_here")
	var events: Array[Dictionary] = [{"type": "met", "player": pid, "creature": id}]
	match id:
		"ryba_kit":
			if Weather.night(db, rid, state.clock_min) < 0.5 or Weather.storm(db, state.world_seed, state.clock_min, rid) > 0:
				return _fail("not_now")
			var whale: Dictionary = state.spirits.get("whale", {})
			if int(whale.get("day", 0)) != state.day:
				state.spirits["whale"] = {"day": state.day}
				var p: Dictionary = state.players[pid]
				p["rested_until"] = maxf(float(p["rested_until"]), state.clock_min) + float(db.balance["spirits"]["whale_rested_min"])
				events[0]["rested"] = true
		"sirin":
			if not Weather.is_dawn(db, rid, state.clock_min):
				return _fail("not_now")
	events.append_array(_journal(pid, id))
	return _ok(events)


## A ruin of the Chud (WorldMap.chud_sites): once, its finds and its story.
func _explore(pid: String, cmd: Dictionary) -> Dictionary:
	if map == null:
		return _fail("not_here")
	var site := String(cmd.get("site", ""))
	var found: Dictionary = {}
	for s: Dictionary in map.chud_sites():
		if s["id"] == site:
			found = s
	if found.is_empty():
		return _fail("unknown_site")
	if not _near(pid, found["pos"], Crafting.REACH_M):
		return _fail("too_far")
	if state.journal.has(site):
		return _fail("explored")
	var finds := ContentDB.bag(db.balance["spirits"]["chud_finds"])
	var inv := state.inv(pid)
	for k: String in finds:
		inv.add(k, finds[k])
	var events: Array[Dictionary] = [{"type": "explored", "player": pid, "site": site, "items": finds}]
	events.append_array(_journal(pid, site))
	return _ok(events)


## A page for the journal of tales, once.
func _journal(pid: String, page: String) -> Array[Dictionary]:
	if state.journal.has(page):
		return []
	state.journal[page] = state.day
	return [{"type": "journal_page", "page": page, "player": pid}]


## Fine tuning (modes.json → rules): storms, cold, tool wear, night raids. Not during a fight.
const TUNABLE := {"storms": ["cosmetic", "capsize"], "cold": ["cosmetic", "mild", "full"], "durability": [true, false], "night_raids": [true, false]}


func _set_tuning(pid: String, cmd: Dictionary) -> Dictionary:
	var rule := String(cmd.get("rule", ""))
	if not TUNABLE.has(rule):
		return _fail("unknown_rule")
	var value: Variant = cmd.get("value")
	if not (TUNABLE[rule] as Array).has(value):
		return _fail("bad_value")
	if state.busy_beacon != "":
		return _fail("busy")
	if db.mode_rules(state.mode).get(rule) == value:
		state.tuning.erase(rule)
	else:
		state.tuning[rule] = value
	return _ok([{"type": "tuning_changed", "player": pid, "rule": rule, "value": value}])


## Host-only: a storm above the hull's class capsizes the boat (Tale and Saga). It floats; right it with E.
func _capsize(_pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("boat", ""))
	if not state.boats.has(uid):
		return _fail("unknown_uid")
	var b: Dictionary = state.boats[uid]
	var bp: Vector3 = b["pos"]
	var level := Weather.storm(db, state.world_seed, state.clock_min, db.region_at(Vector2(bp.x, bp.z)))
	if bool(b["capsized"]) or not Weather.capsizes(db, rules(), String(b["type"]), level):
		return _fail("no_storm")
	b["capsized"] = true
	return _ok([{"type": "boat_capsized", "boat": uid, "level": level}])


func _right_boat(pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("boat", ""))
	if not state.boats.has(uid) or not bool(state.boats[uid]["capsized"]):
		return _fail("unknown_uid")
	if state.players[pid]["aboard"] != uid and not _near(pid, state.boats[uid]["pos"], BOARD_REACH_M):
		return _fail("too_far")
	state.boats[uid]["capsized"] = false
	return _ok([{"type": "boat_righted", "boat": uid, "player": pid}])


## Host-only: a creature appears (the host's CreatureDirector). Ambient spawns obey Creatures.spawn_block
## (mode, region, fog thicker than fog_min, night or a dark island); fight spawns need a fight going on.
func _spawn(_pid: String, cmd: Dictionary) -> Dictionary:
	var id := String(cmd.get("id", ""))
	var pos := WorldState._to_v3(cmd.get("pos", []))
	if not _sane(pos):
		return _fail("bad_pos")
	var r := rules()
	var fight := bool(cmd.get("fight", false))
	if fight:
		if state.busy_beacon == "":
			return _fail("no_fight")
		if not Creatures.allowed(db, state.mode, r, id):
			return _fail("not_in_this_mode")
	else:
		var p2 := Vector2(pos.x, pos.z)
		var rid := db.region_at(p2)
		var dark := false
		if map != null:
			var isl := map.island_at(pos.x, pos.z)
			dark = isl != null and map.kind_of[isl.id] == "beacon" and not state.lit.has(isl.id)
		var why := Creatures.spawn_block(db, state.mode, r, id, rid, FogField.factor(db, state, p2), Weather.night(db, rid, state.clock_min), dark)
		if why != "":
			return _fail(why)
	var uid := state.new_uid("c")
	state.creatures[uid] = {"id": id, "pos": pos, "hp": float(Creatures.info(db, id)["hp"]), "fight": state.busy_beacon if fight else ""}
	return _ok([{"type": "creature_spawned", "uid": uid, "id": id, "pos": WorldState._v3(pos), "fight": fight}])


func _despawn(_pid: String, cmd: Dictionary) -> Dictionary:
	var uid := String(cmd.get("uid", ""))
	if not state.creatures.has(uid):
		return _fail("unknown_uid")
	state.creatures.erase(uid)
	return _ok([{"type": "creature_gone", "uid": uid}])


## Host-only: where the host's creatures are now ({"pos": {uid: [x, y, z]}}); no events, the synchroniser
## carries positions. The host needs them to check reach for hits both ways.
func _creatures(_pid: String, cmd: Dictionary) -> Dictionary:
	var moved: Dictionary = cmd.get("pos", {})
	for uid: String in moved:
		var v := WorldState._to_v3(moved[uid])
		if state.creatures.has(uid) and _sane(v):
			state.creatures[uid]["pos"] = v
	return _ok([])


## Host-only: a creature's hit lands on a player. Friendly creatures (animals, spirits, wonders, legends)
## can never hurt anyone, in any mode; in Quiet nothing takes health. A dodge takes nothing, a block takes off
## the shield's worth. At zero health the player dies by the mode's rules.
func _hurt(pid: String, cmd: Dictionary) -> Dictionary:
	var target := String(cmd.get("player", pid))
	if not state.players.has(target):
		return _fail("unknown_player")
	var src := String(cmd.get("source", ""))
	var c: Dictionary = state.creatures.get(src, {})
	if c.is_empty():
		return _fail("unknown_uid")
	var id := String(c["id"])
	if Creatures.is_friendly(db, id):
		return _fail("friendly")
	if String(rules()["death"]) == "none":
		return _fail("no_harm")
	var p: Dictionary = state.players[target]
	var reach := 16.0 if Creatures.group(db, id) == "guardian" else HIT_REACH_M  # needles, gusts, waves
	if (c["pos"] as Vector3).distance_to(p["pos"]) > reach:
		return _fail("too_far")
	var stance := String(p.get("stance", ""))
	var dmg := Creatures.damage_to_player(db, id, float(cmd.get("k", 1.0)), stance, (p["inv"] as Inventory).count("shield") > 0)
	p["hp"] = maxf(0.0, float(p["hp"]) - dmg)
	p["hurt_at"] = state.clock_min
	var events: Array[Dictionary] = [{"type": "hurt", "player": target, "source": src, "id": id, "amount": dmg, "hp": p["hp"], "stance": stance}]
	if id in ["mglyak", "karachun", "mga"] and dmg > 0.0 and not (p["light"] as Dictionary).is_empty():
		p["light"] = {}  # the mistling's touch and Karachun's breath put the light out
		events.append({"type": "light_changed", "player": target, "item": "", "drained": true})
	if float(p["hp"]) <= 0.0:
		events.append_array(_die(target, {})["events"])
	return _ok(events)


## Health comes back after a few quiet seconds; in the cold without warmth Saga takes it slowly (Tale only
## stops stamina, see Vitals). Health never exceeds the food-raised maximum.
func _tick_body(pid: String, dt_min: float) -> Array[Dictionary]:
	var p: Dictionary = state.players[pid]
	var pb: Dictionary = db.balance["player"]
	var hp := float(p["hp"])
	var top := Vitals.max_hp(db, state, pid)
	if String(rules()["cold"]) == "full" and Creatures.is_cold(db, state, pid):
		hp -= float(db.balance["cold"]["hp_per_s"]) * dt_min * 60.0
		p["hurt_at"] = state.clock_min
	elif (state.clock_min - float(p["hurt_at"])) * 60.0 >= float(pb["hp_regen_after_hurt_s"]):
		hp += float(pb["hp_regen_per_s"]) * dt_min * 60.0
	p["hp"] = clampf(hp, 0.0, top)
	if hp <= 0.0:
		return _die(pid, {"cause": "cold"})["events"]
	return []


## Now and then a fed domovoy tidies the chest nearest his bed: stacks merged and sorted.
func _tick_domovoy() -> Array[Dictionary]:
	if state.day % 2 != 0 or not Creatures.domovoy_fed(db, state):
		return []
	var home := Creatures.domovoy_home(db, state)
	if home == "":
		return []
	var bed: Vector3 = state.pieces[home]["pos"]
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		if pc.has("inv") and (pc["pos"] as Vector3).distance_to(bed) <= float(db.balance["rested"]["radius_m"]):
			var inv: Inventory = pc["inv"]
			var bag := {}
			for s: Dictionary in inv.slots:
				if not s.is_empty():
					bag[s["id"]] = int(bag.get(s["id"], 0)) + int(s["n"])
					s.clear()
			var ids := bag.keys()
			ids.sort()
			for k: String in ids:
				inv.add(k, bag[k])
			return [{"type": "domovoy_tidied", "uid": uid}]
	return []


# ---------------------------------------------------------------- helpers

static func _sane(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < WORLD_LIMIT_M and absf(v.z) < WORLD_LIMIT_M and absf(v.y) < 500.0


static func _ok(events: Array) -> Dictionary:
	return {"ok": true, "error": "", "events": events}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
