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
const HOST_ONLY: Array[String] = ["tick", "debug"]

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
		"tick":
			return _tick(pid, cmd)
		"debug":
			return _debug(pid, cmd)
	return _fail("unknown_command")


## The mode's rules with the world's fine-tuning overrides on top.
func rules() -> Dictionary:
	var r := db.mode_rules(state.mode).duplicate()
	for k: String in state.tuning:
		r[k] = state.tuning[k]
	return r


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


func _begin_fight(pid: String, cmd: Dictionary) -> Dictionary:
	var bid := String(cmd.get("beacon", ""))
	if not db.beacons.has(bid):
		return _fail("unknown_beacon")
	if rules()["beacon"] != "guardian_or_defense":
		return _fail("not_in_this_mode")
	if state.busy_beacon != "":
		return _fail("busy")
	state.busy_beacon = bid
	return _ok([{"type": "fight_started", "beacon": bid, "kind": db.beacons[bid]["saga"]["type"], "player": pid}])


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
	if state.busy_beacon == bid:
		state.busy_beacon = ""
	return _ok([{"type": "trial_done", "beacon": bid, "kind": kind, "player": pid}])


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
	var ev := {"type": "respawn", "player": pid, "at": WorldState._v3(p["spawn"]), "death": death}
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
	p["pos"] = p["spawn"]
	if state.busy_beacon != "":
		state.busy_beacon = ""  # a lost fight can simply be retried
	return _ok([ev])


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
	var minutes := float(db.balance["steam"]["minutes"])
	state.players[pid]["steam_until"] = state.clock_min + minutes
	return _ok([{"type": "steamed", "player": pid, "uid": uid, "minutes": minutes}])


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
	for pid: String in state.players:
		events.append_array(_tick_light(pid))
		events.append_array(_tick_food(pid))
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


## Debug-only (allow_debug): {"give": {item: n}, "trial": beacon, "pos": [x, y, z], "clock_min": t}.
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
	return _ok(events)


# ---------------------------------------------------------------- helpers

static func _sane(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < WORLD_LIMIT_M and absf(v.z) < WORLD_LIMIT_M and absf(v.y) < 500.0


static func _ok(events: Array) -> Dictionary:
	return {"ok": true, "error": "", "events": events}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
