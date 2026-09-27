class_name ContentDB
extends RefCounted
## All game data from res://content/*.json. Pure data: no nodes, no autoloads.
## Godot's JSON parser returns every number as float: read numbers through the typed getters
## (qty(), bag()) or cast with int().

const FILES: Array[String] = ["items", "recipes", "buildables", "boats", "regions", "beacons", "creatures", "modes", "balance"]
const REGION_ORDER: Array[String] = ["r1", "r2", "r3", "r4"]

static var _shared: ContentDB

var raw: Dictionary = {}
var items: Dictionary = {}
var recipes: Dictionary = {}
var pieces: Dictionary = {}
var boats: Dictionary = {}
var regions: Dictionary = {}
var beacons: Dictionary = {}
var beacon_order: Array[String] = []
var creatures: Dictionary = {}
var modes: Dictionary = {}
var balance: Dictionary = {}
var trial_types: Dictionary = {}
var home: Dictionary = {}


## One loaded instance for the whole game (the Content autoload and scenes use it; tests may build their own).
static func shared() -> ContentDB:
	if _shared == null:
		_shared = ContentDB.new()
		var err := _shared.load_dir()
		if err != OK:
			push_error("ContentDB: failed to load content (%s)" % error_string(err))
	return _shared


func load_dir(dir: String = "res://content") -> Error:
	for file_name in FILES:
		var path := dir.path_join(file_name + ".json")
		if not FileAccess.file_exists(path):
			push_error("ContentDB: missing %s" % path)
			return ERR_FILE_NOT_FOUND
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("ContentDB: bad JSON in %s" % path)
			return ERR_PARSE_ERROR
		raw[file_name] = parsed
	items = _index(raw["items"]["items"])
	recipes = _index(raw["recipes"]["recipes"])
	pieces = _index(raw["buildables"]["pieces"])
	boats = _index(raw["boats"]["boats"])
	regions = _index(raw["regions"]["regions"])
	home = raw["regions"]["home"]
	beacons = _index(raw["beacons"]["beacons"])
	beacon_order.clear()
	for b: Dictionary in raw["beacons"]["beacons"]:
		beacon_order.append(b["id"])
	trial_types = raw["beacons"]["trial_types"]
	creatures = _index(raw["creatures"]["creatures"])
	modes = _index(raw["modes"]["modes"])
	balance = raw["balance"]
	return OK


func _index(rows: Array) -> Dictionary:
	var out := {}
	for row: Dictionary in rows:
		out[row["id"]] = row
	return out


# ---------------------------------------------------------------- lookups

func item_name(id: String, lang: String = "ru") -> String:
	var it: Dictionary = items.get(id, {})
	return it.get("name", {}).get(lang, id)


func stack_size(id: String) -> int:
	return int(items.get(id, {}).get("stack", 1))


## A {item_id: float} dictionary from JSON as {item_id: int}.
static func bag(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out


func is_unlocked(unlock: String, lit: Dictionary) -> bool:
	return unlock == "start" or lit.has(unlock)


func mode_rules(mode_id: String) -> Dictionary:
	return modes.get(mode_id, modes[raw["modes"]["default"]])["rules"]


func recipes_producing(item_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in recipes.values():
		if r["output"].has(item_id):
			out.append(r)
	return out


## Region that contains a point (by distance ring from home). Beyond the last ring: the last region.
func region_at(pos: Vector2) -> String:
	var d := pos.length()
	for rid in REGION_ORDER:
		var ring: Array = regions[rid]["ring_m"]
		if d < float(ring[1]):
			return rid
	return REGION_ORDER[-1]


func region_open(rid: String, lit: Dictionary) -> bool:
	return is_unlocked(regions[rid]["opened_by"], lit)


func beacon_pos(id: String) -> Vector2:
	var p: Array = beacons[id]["pos"]
	return Vector2(float(p[0]), float(p[1]))


## Everything a beacon unlocks when lit, for the "new recipes" toast.
func unlocks_of(beacon_id: String) -> Dictionary:
	var out := {"recipes": [], "pieces": [], "boats": [], "region": beacons[beacon_id].get("opens")}
	for r: Dictionary in recipes.values():
		if r["unlock"] == beacon_id:
			out["recipes"].append(r["id"])
	for p: Dictionary in pieces.values():
		if p["unlock"] == beacon_id:
			out["pieces"].append(p["id"])
	for b: Dictionary in boats.values():
		if b["unlock"] == beacon_id:
			out["boats"].append(b["id"])
	return out


# ---------------------------------------------------------------- validation
## Reference checks. The full progression-reachability check lives in tools/validate_content.py.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var unlocks := {"start": true}
	for bid in beacon_order:
		unlocks[bid] = true
	var tool_types := {}
	for it: Dictionary in items.values():
		if it.has("tool"):
			tool_types[it["tool"]["type"]] = true
		for lang in ["ru", "en"]:
			if str(it.get("name", {}).get(lang, "")).is_empty():
				errors.append("item %s: missing name.%s" % [it["id"], lang])
	var produced := {}
	for r: Dictionary in recipes.values():
		var st: String = r["station"]
		if st != "hand" and not (pieces.has(st) and pieces[st].get("station", false)):
			errors.append("recipe %s: station %s is not a station piece" % [r["id"], st])
		if not unlocks.has(r["unlock"]):
			errors.append("recipe %s: unknown unlock %s" % [r["id"], r["unlock"]])
		for k: String in r["inputs"]:
			if not items.has(k):
				errors.append("recipe %s: unknown input %s" % [r["id"], k])
		for k: String in r["output"]:
			if not items.has(k):
				errors.append("recipe %s: unknown output %s" % [r["id"], k])
			produced[k] = true
	for it: Dictionary in items.values():
		if it.has("gather"):
			var g: Dictionary = it["gather"]
			if g["tool"] != "hand" and not tool_types.has(g["tool"]):
				errors.append("item %s: no tool of type %s" % [it["id"], g["tool"]])
			if not regions.has(g["region"]):
				errors.append("item %s: unknown region %s" % [it["id"], g["region"]])
		elif it.has("source"):
			if not pieces.has(it["source"]):
				errors.append("item %s: unknown source %s" % [it["id"], it["source"]])
		elif not produced.has(it["id"]):
			errors.append("item %s: nothing produces it" % it["id"])
	for p: Dictionary in pieces.values():
		if not unlocks.has(p["unlock"]):
			errors.append("piece %s: unknown unlock %s" % [p["id"], p["unlock"]])
		for k: String in p["cost"]:
			if not items.has(k):
				errors.append("piece %s: unknown cost item %s" % [p["id"], k])
	for b: Dictionary in boats.values():
		for k: String in b["cost"]:
			if not items.has(k):
				errors.append("boat %s: unknown cost item %s" % [b["id"], k])
	for g: Dictionary in regions.values():
		if not unlocks.has(g["opened_by"]):
			errors.append("region %s: unknown opened_by %s" % [g["id"], g["opened_by"]])
		if not boats.has(g["boat_required"]):
			errors.append("region %s: unknown boat %s" % [g["id"], g["boat_required"]])
		for k: String in g["resources"]:
			if not items.has(k):
				errors.append("region %s: unknown resource %s" % [g["id"], k])
		for k: String in g["creatures"]:
			if not creatures.has(k):
				errors.append("region %s: unknown creature %s" % [g["id"], k])
	for bid in beacon_order:
		var b: Dictionary = beacons[bid]
		if not regions.has(b["region"]):
			errors.append("beacon %s: unknown region %s" % [bid, b["region"]])
		if not trial_types.has(b["trial"]):
			errors.append("beacon %s: unknown trial %s" % [bid, b["trial"]])
		for k: String in b["fuel"]:
			if not items.has(k):
				errors.append("beacon %s: unknown fuel %s" % [bid, k])
		var saga: Dictionary = b["saga"]
		if saga["type"] == "guardian":
			var c: Dictionary = creatures.get(saga["id"], {})
			if c.is_empty() or c.get("beacon", "") != bid:
				errors.append("beacon %s: guardian %s missing or bound elsewhere" % [bid, saga["id"]])
	for c: Dictionary in creatures.values():
		if c.has("gift") and not items.has(c["gift"]):
			errors.append("creature %s: gift %s is not an item" % [c["id"], c["gift"]])
		for k: String in c.get("drops", {}):
			if not items.has(k):
				errors.append("creature %s: drop %s is not an item" % [c["id"], k])
		for m: String in c["modes"]:
			if not modes.has(m):
				errors.append("creature %s: unknown mode %s" % [c["id"], m])
	return errors
