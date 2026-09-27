class_name Inventory
extends RefCounted
## Slot inventory with stack sizes from content. Removal of a bag is all-or-nothing.

var size: int
var slots: Array[Dictionary] = []  # {} = empty, or {"id": String, "n": int}
var _db: ContentDB


func _init(db: ContentDB, p_size: int = 24) -> void:
	_db = db
	size = p_size
	slots.resize(size)
	for i in size:
		slots[i] = {}


func count(id: String) -> int:
	var n := 0
	for s: Dictionary in slots:
		if s.get("id", "") == id:
			n += int(s["n"])
	return n


func has_bag(bag: Dictionary) -> bool:
	for k: String in bag:
		if count(k) < int(bag[k]):
			return false
	return true


func missing(bag: Dictionary) -> Dictionary:
	var out := {}
	for k: String in bag:
		var lack := int(bag[k]) - count(k)
		if lack > 0:
			out[k] = lack
	return out


## Adds as many as fit; returns how many did not fit.
func add(id: String, n: int) -> int:
	var stack := _db.stack_size(id)
	var left := n
	for s: Dictionary in slots:
		if left == 0:
			break
		if s.get("id", "") == id and int(s["n"]) < stack:
			var put := mini(stack - int(s["n"]), left)
			s["n"] = int(s["n"]) + put
			left -= put
	for i in size:
		if left == 0:
			break
		if slots[i].is_empty():
			var put := mini(stack, left)
			slots[i] = {"id": id, "n": put}
			left -= put
	return left


func can_fit(bag: Dictionary) -> bool:
	var probe := Inventory.new(_db, size)
	probe.from_dict(to_dict())
	for k: String in bag:
		if probe.add(k, int(bag[k])) > 0:
			return false
	return true


func remove(id: String, n: int) -> bool:
	if count(id) < n:
		return false
	var left := n
	for i in range(size - 1, -1, -1):
		if left == 0:
			break
		var s: Dictionary = slots[i]
		if s.get("id", "") == id:
			var take := mini(int(s["n"]), left)
			s["n"] = int(s["n"]) - take
			left -= take
			if int(s["n"]) == 0:
				slots[i] = {}
	return true


func remove_bag(bag: Dictionary) -> bool:
	if not has_bag(bag):
		return false
	for k: String in bag:
		remove(k, int(bag[k]))
	return true


func best_tool_tier(tool_type: String) -> int:
	var best := 0
	for s: Dictionary in slots:
		if s.is_empty():
			continue
		var it: Dictionary = _db.items.get(s["id"], {})
		if it.has("tool") and it["tool"]["type"] == tool_type:
			best = maxi(best, int(it["tool"]["tier"]))
	return best


func is_empty() -> bool:
	for s: Dictionary in slots:
		if not s.is_empty():
			return false
	return true


func to_dict() -> Dictionary:
	var out: Array = []
	for s: Dictionary in slots:
		out.append(s.duplicate())
	return {"size": size, "slots": out}


func from_dict(d: Dictionary) -> void:
	size = int(d.get("size", size))
	slots.resize(size)
	var src: Array = d.get("slots", [])
	for i in size:
		var s: Dictionary = src[i] if i < src.size() else {}
		slots[i] = {} if s.is_empty() else {"id": String(s["id"]), "n": int(s["n"])}
