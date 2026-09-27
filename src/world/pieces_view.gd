class_name PiecesView
extends Node3D
## Every placed building piece (WorldState.pieces) as a model from ModelLibrary("pieces", id). Stations
## with fire burn while their queue works (hearths and stoves always: they are the home); pieces with
## fog_radius clear the fog around them (FogDirector extra lights). Collision so the player walks around
## them. Only a view: pieces come and go with the piece_placed / piece_removed events.

const ALWAYS_BURNING: Array[String] = ["hearth", "stove"]

var db: ContentDB
var state: WorldState
var nodes: Dictionary = {}  # uid -> Node3D
var _fires: Dictionary = {}  # uid -> Node3D (fire effect)


func setup(p_db: ContentDB, p_state: WorldState) -> void:
	db = p_db
	state = p_state
	name = "Pieces"
	for uid: String in state.pieces:
		add_piece(uid)


func add_piece(uid: String) -> void:
	if nodes.has(uid) or not state.pieces.has(uid):
		return
	var pc: Dictionary = state.pieces[uid]
	var id := String(pc["id"])
	var n := ModelLibrary.instance("pieces", id)
	n.position = pc["pos"]
	n.rotation.y = float(pc["rot"])
	n.set_meta("uid", uid)
	add_child(n)
	nodes[uid] = n
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bounds := _bounds(n)
	box.size = Vector3(maxf(bounds.size.x, 0.3), maxf(bounds.size.y, 0.3), maxf(bounds.size.z, 0.3))
	cs.shape = box
	cs.position = bounds.get_center()
	body.add_child(cs)
	n.add_child(body)
	var anchor := n.get_node_or_null("Fire") as Node3D
	if anchor != null:
		var f := Placeholders.fire(0.45 if id != "bloomery" else 0.3, true)
		f.position = anchor.position
		f.visible = false
		n.add_child(f)
		_fires[uid] = f


func remove_piece(uid: String) -> void:
	if nodes.has(uid):
		(nodes[uid] as Node).queue_free()
		nodes.erase(uid)
		_fires.erase(uid)


func _process(_delta: float) -> void:
	for uid: String in _fires:
		if not state.pieces.has(uid):
			continue
		var pc: Dictionary = state.pieces[uid]
		var on: bool = String(pc["id"]) in ALWAYS_BURNING or not (pc.get("queue", []) as Array).is_empty()
		(_fires[uid] as Node3D).visible = on


## Fog clearings around burning hearths, stoves and lamps near a point: nearest first, at most `n`.
func fog_lights(near: Vector2, n: int) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var all: Array = []
	for uid: String in state.pieces:
		var pc: Dictionary = state.pieces[uid]
		var p: Dictionary = db.pieces.get(pc["id"], {})
		if not p.has("fog_radius"):
			continue
		var pos: Vector3 = pc["pos"]
		all.append([Vector2(pos.x, pos.z).distance_to(near), Vector4(pos.x, pos.z, float(p["fog_radius"]), 0.8)])
	all.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(n, all.size()):
		if float(all[i][0]) < 250.0:
			out.append(all[i][1])
	return out


static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in ModelLibrary._meshes(root):
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
