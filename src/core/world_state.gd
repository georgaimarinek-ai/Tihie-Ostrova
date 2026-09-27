class_name WorldState
extends RefCounted
## The whole shared world as plain data. Nodes are views of it; WorldCommands is the only writer.
## Serialised by SaveCodec; the host sends it to joining clients (docs/04_TECH_SPEC.md §7).

const VERSION := 3

var world_seed: int = 0
var mode: String = "tale"
var day: int = 1
var clock_min: float = 0.0  # world minutes since creation (debuffs, respawns, sheep)
var lit: Dictionary = {}  # beacon id -> day it was lit
var trials_done: Dictionary = {}  # beacon id -> "trial" | "guardian" | "defense"
var busy_beacon: String = ""  # guardian fight or fire defence in progress ("" = none)
## uid -> {"id", "pos": Vector3, "rot": float, "owner", optional "inv": Inventory (chests),
##   "queue": [{"recipe", "times" (units left), "left_s" (seconds left on the current unit)}], "out": {item: n}}
var pieces: Dictionary = {}
var graves: Dictionary = {}  # uid -> {"owner": String, "pos": Vector3, "inv": Dictionary}
var depleted: Dictionary = {}  # resource node id -> day it respawns
## player id -> {"inv": Inventory, "pos": Vector3, "spawn": Vector3, "weary_until": float, "aboard": boat uid or "",
##   "food": [{"id", "until"}], "rested_until": float, "steam_until": float, "light": {} or {"id", "until" (-1 = forever)}}.
## Times are clock_min.
var players: Dictionary = {}
var boats: Dictionary = {}  # uid -> {"type": String, "pos": Vector3, "yaw": float, "cargo": Inventory}
var journal: Dictionary = {}  # page id -> day it was found
var tuning: Dictionary = {}  # rule -> value: "fine tuning" overrides of the mode rules (modes.json)
var next_uid: int = 1

var db: ContentDB


func _init(p_db: ContentDB, p_seed: int = 0, p_mode: String = "") -> void:
	db = p_db
	world_seed = p_seed
	mode = p_mode if p_mode != "" else String(db.raw["modes"]["default"])


func new_uid(prefix: String) -> String:
	var uid := "%s%d" % [prefix, next_uid]
	next_uid += 1
	return uid


func add_player(pid: String, pos: Vector3 = Vector3.ZERO) -> Dictionary:
	if not players.has(pid):
		players[pid] = {"inv": Inventory.new(db, int(db.balance["player"]["carry_slots"])), "pos": pos, "spawn": pos,
			"weary_until": 0.0, "aboard": "", "food": [], "rested_until": 0.0, "steam_until": 0.0, "light": {}}
	return players[pid]


func inv(pid: String) -> Inventory:
	return players[pid]["inv"]


## A boat of a type from boats.json with an empty hold. Only WorldCommands calls this (and tests).
func add_boat(type: String, pos: Vector3, yaw: float) -> String:
	var uid := new_uid("b")
	boats[uid] = {"type": type, "pos": pos, "yaw": yaw, "cargo": Inventory.new(db, int(db.boats[type]["cargo_slots"]))}
	return uid


# ---------------------------------------------------------------- serialisation

static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(a: Variant) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func to_dict() -> Dictionary:
	var ps := {}
	for pid: String in players:
		var p: Dictionary = players[pid]
		ps[pid] = {"inv": (p["inv"] as Inventory).to_dict(), "pos": _v3(p["pos"]), "spawn": _v3(p["spawn"]), "weary_until": p["weary_until"],
			"aboard": p["aboard"], "food": (p["food"] as Array).duplicate(true), "rested_until": p["rested_until"], "steam_until": p["steam_until"],
			"light": (p["light"] as Dictionary).duplicate()}
	var pcs := {}
	for uid: String in pieces:
		var pc: Dictionary = pieces[uid]
		var row := {"id": pc["id"], "pos": _v3(pc["pos"]), "rot": pc["rot"], "owner": pc["owner"]}
		if pc.has("inv"):
			row["inv"] = (pc["inv"] as Inventory).to_dict()
		if pc.has("queue"):
			row["queue"] = (pc["queue"] as Array).duplicate(true)
		if pc.has("out"):
			row["out"] = (pc["out"] as Dictionary).duplicate()
		pcs[uid] = row
	var gr := {}
	for uid: String in graves:
		var g: Dictionary = graves[uid]
		gr[uid] = {"owner": g["owner"], "pos": _v3(g["pos"]), "inv": g["inv"]}
	var bs := {}
	for uid: String in boats:
		var b: Dictionary = boats[uid]
		bs[uid] = {"type": b["type"], "pos": _v3(b["pos"]), "yaw": b["yaw"], "cargo": (b["cargo"] as Inventory).to_dict()}
	return {
		"version": VERSION, "world_seed": world_seed, "mode": mode, "day": day, "clock_min": clock_min,
		"lit": lit.duplicate(), "trials_done": trials_done.duplicate(), "busy_beacon": busy_beacon,
		"pieces": pcs, "graves": gr, "depleted": depleted.duplicate(), "players": ps, "boats": bs, "next_uid": next_uid,
		"journal": journal.duplicate(), "tuning": tuning.duplicate(),
	}


static func from_dict(p_db: ContentDB, src: Dictionary) -> WorldState:
	var d := migrate(src)
	var s := WorldState.new(p_db, int(d["world_seed"]), String(d["mode"]))
	s.day = int(d["day"])
	s.clock_min = float(d["clock_min"])
	for k: String in d["lit"]:
		s.lit[k] = int(d["lit"][k])
	for k: String in d["trials_done"]:
		s.trials_done[k] = String(d["trials_done"][k])
	s.busy_beacon = String(d.get("busy_beacon", ""))
	for uid: String in d["pieces"]:
		var pc: Dictionary = d["pieces"][uid]
		var piece := {"id": String(pc["id"]), "pos": _to_v3(pc["pos"]), "rot": float(pc["rot"]), "owner": String(pc["owner"])}
		if pc.has("inv"):
			var chest := Inventory.new(p_db)
			chest.from_dict(pc["inv"])
			piece["inv"] = chest
		if pc.has("queue"):
			piece["queue"] = _int_queue(pc["queue"])
		if pc.has("out"):
			piece["out"] = ContentDB.bag(pc["out"])
		s.pieces[uid] = piece
	for uid: String in d["graves"]:
		var g: Dictionary = d["graves"][uid]
		s.graves[uid] = {"owner": String(g["owner"]), "pos": _to_v3(g["pos"]), "inv": g["inv"]}
	for k: String in d["depleted"]:
		s.depleted[k] = int(d["depleted"][k])
	for pid: String in d["players"]:
		var p: Dictionary = d["players"][pid]
		var inv := Inventory.new(p_db)
		inv.from_dict(p["inv"])
		var food: Array = []
		for f: Dictionary in p["food"]:
			food.append({"id": String(f["id"]), "until": float(f["until"])})
		s.players[pid] = {"inv": inv, "pos": _to_v3(p["pos"]), "spawn": _to_v3(p["spawn"]), "weary_until": float(p["weary_until"]),
			"aboard": String(p["aboard"]), "food": food, "rested_until": float(p["rested_until"]), "steam_until": float(p["steam_until"]),
			"light": _light_from(p.get("light", {}))}
	for uid: String in d["boats"]:
		var b: Dictionary = d["boats"][uid]
		var cargo := Inventory.new(p_db, int(p_db.boats[String(b["type"])]["cargo_slots"]))
		cargo.from_dict(b["cargo"])
		s.boats[uid] = {"type": String(b["type"]), "pos": _to_v3(b["pos"]), "yaw": float(b["yaw"]), "cargo": cargo}
	s.next_uid = int(d["next_uid"])
	for k: String in d["journal"]:
		s.journal[k] = int(d["journal"][k])
	s.tuning = (d["tuning"] as Dictionary).duplicate()
	return s


static func _light_from(src: Dictionary) -> Dictionary:
	if src.is_empty():
		return {}
	return {"id": String(src["id"]), "until": float(src["until"])}


## Station queues from JSON: counts back to int (Godot parses JSON numbers as float).
static func _int_queue(src: Array) -> Array:
	var out: Array = []
	for q: Dictionary in src:
		out.append({"recipe": String(q["recipe"]), "times": int(q["times"]), "left_s": float(q["left_s"])})
	return out


## Upgrades an old save dictionary step by step. Add a step for every VERSION bump and a test for it.
static func migrate(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	var v := int(d.get("version", 1))
	if v < 2:
		# v1 kept lit beacons as a list and had no trials; lit ones count as done.
		var old_lit: Array = d.get("lit", [])
		var lit := {}
		var trials := {}
		for bid: String in old_lit:
			lit[bid] = 1
			trials[bid] = "trial"
		d["lit"] = lit
		d["trials_done"] = trials
		for key: String in ["graves", "boats", "depleted", "pieces", "players"]:
			if not d.has(key):
				d[key] = {}
		for key: String in ["day", "next_uid"]:
			if not d.has(key):
				d[key] = 1
		if not d.has("clock_min"):
			d["clock_min"] = 0.0
		v = 2
	if v < 3:
		# v3: players know which boat they are aboard, eat food and rest; boats have a hold; journal and fine tuning.
		for pid: String in d["players"]:
			var p: Dictionary = d["players"][pid]
			for key: String in ["aboard"]:
				if not p.has(key):
					p[key] = ""
			if not p.has("food"):
				p["food"] = []
			for key: String in ["rested_until", "steam_until"]:
				if not p.has(key):
					p[key] = 0.0
		for uid: String in d["boats"]:
			var b: Dictionary = d["boats"][uid]
			if not b.has("cargo"):
				b["cargo"] = {"slots": []}  # from_dict sizes it from boats.json
		if not d.has("journal"):
			d["journal"] = {}
		if not d.has("tuning"):
			d["tuning"] = {}
		v = 3
	d["version"] = v
	return d
