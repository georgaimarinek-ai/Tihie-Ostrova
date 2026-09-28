class_name SitesView
extends Node3D
## Places of the world that aren't pieces: grave markers where a Saga player fell (WorldState.graves: E takes
## the things back, "loot_grave"), the ruins of the White-Eyed Chud (WorldMap.chud_sites: stone circles and
## mines, E explores once, "explore") and Likho's cave on the Summer Shore. Built near the player only.

const NEAR_M := 260.0

var world
var db: ContentDB
var state: WorldState
var map: WorldMap
var _graves: Dictionary = {}  # uid -> Node3D
var _ruins: Dictionary = {}  # site id -> Node3D
var _cave: Node3D
var _t := 0.0


func setup(p_world) -> void:
	world = p_world
	db = world.db
	state = world.state
	map = world.map
	name = "Sites"
	Game.world_event.connect(_on_event)
	_refresh_graves()


func _on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) in ["respawn", "grave_looted"]:
		_refresh_graves()


func _refresh_graves() -> void:
	for uid: String in _graves.keys():
		if not state.graves.has(uid):
			(_graves[uid] as Node3D).queue_free()
			_graves.erase(uid)
	for uid: String in state.graves:
		if _graves.has(uid):
			continue
		var n := ModelLibrary.instance("props", "pomor_cross")
		n.scale = Vector3.ONE * 0.6
		var p: Vector3 = state.graves[uid]["pos"]
		n.position = Vector3(p.x, map.ground_at(p.x, p.z), p.z)
		var g := Placeholders.glow(Color("ffd9a0"), 3.0, 0.5)
		g.position = Vector3(0, 2.2, 0)
		n.add_child(g)
		add_child(n)
		_graves[uid] = n


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var f: Vector3 = world._focus()
	for s: Dictionary in map.chud_sites():
		var d := Vector2((s["pos"] as Vector3).x - f.x, (s["pos"] as Vector3).z - f.z).length()
		if d < NEAR_M and not _ruins.has(s["id"]):
			_ruins[s["id"]] = _build_ruin(s)
		elif d > NEAR_M * 1.5 and _ruins.has(s["id"]):
			(_ruins[s["id"]] as Node3D).queue_free()
			_ruins.erase(s["id"])
	var cave := map.likho_cave()
	if cave != Vector3.INF:
		var dc := Vector2(cave.x - f.x, cave.z - f.z).length()
		if dc < NEAR_M and _cave == null:
			_cave = _build_cave(cave)
		elif dc > NEAR_M * 1.5 and _cave != null:
			_cave.queue_free()
			_cave = null


## A ring of seven standing stones with a flat carved stone in the middle, or a timbered mine mouth.
func _build_ruin(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Chud_" + String(s["id"])
	var at: Vector3 = s["pos"]
	root.position = at
	var parts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = String(s["id"]).hash()
	if String(s["kind"]) == "circle":
		for i in 7:
			var a := i * TAU / 7.0
			var h := rng.randf_range(1.2, 2.2)
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, h, 0.35)
			var q := Vector3(cos(a) * 3.6, 0, sin(a) * 3.6)
			q.y = map.ground_at(at.x + q.x, at.z + q.z) - at.y + h * 0.45
			parts.append([bm, Transform3D(Basis(Vector3.UP, -a).rotated(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), q), Placeholders.STONE.darkened(rng.randf() * 0.2)])
		var slab := BoxMesh.new()
		slab.size = Vector3(1.6, 0.25, 1.1)
		parts.append([slab, Transform3D(Basis(), Vector3(0, 0.15, 0)), Placeholders.STONE.lightened(0.1)])
	else:
		var mound := SphereMesh.new()
		mound.radius = 3.2
		mound.height = 3.6
		mound.radial_segments = 8
		mound.rings = 4
		parts.append([mound, Transform3D(Basis(), Vector3(0, 0.2, 0)), Placeholders.STONE.darkened(0.15)])
		for x: float in [-0.9, 0.9]:
			var post := BoxMesh.new()
			post.size = Vector3(0.25, 2.0, 0.25)
			parts.append([post, Transform3D(Basis(), Vector3(x, 1.0, -2.9)), Placeholders.DARK_WOOD])
		var lintel := BoxMesh.new()
		lintel.size = Vector3(2.2, 0.25, 0.3)
		parts.append([lintel, Transform3D(Basis(), Vector3(0, 2.05, -2.9)), Placeholders.DARK_WOOD])
		var mouth := BoxMesh.new()
		mouth.size = Vector3(1.6, 1.8, 0.2)
		parts.append([mouth, Transform3D(Basis(), Vector3(0, 0.95, -2.95)), Color("0c0c0e")])
	var mi := MeshInstance3D.new()
	mi.mesh = Placeholders.merge_colored(parts)
	mi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	var sign := Placeholders.glow(Color("cfe6ff"), 1.6, 0.0 if state.journal.has(s["id"]) else 0.5)
	sign.name = "Sign"
	sign.position = Vector3(0, 0.6, 0) if String(s["kind"]) == "circle" else Vector3(0, 1.0, -3.1)
	root.add_child(sign)
	add_child(root)
	return root


## A dark rock arch where Likho sleeps.
func _build_cave(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "LikhoCave"
	root.position = at
	var parts: Array = []
	for i in 5:
		var a := PI * 0.1 + i * PI * 0.2
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 1.8, 2.4)
		parts.append([bm, Transform3D(Basis(Vector3.FORWARD, a), Vector3(cos(a) * 3.2, sin(a) * 3.2, 2.0)), Placeholders.STONE.darkened(0.25)])
	var back := BoxMesh.new()
	back.size = Vector3(7.0, 4.5, 1.0)
	parts.append([back, Transform3D(Basis(), Vector3(0, 2.0, 3.6)), Placeholders.STONE.darkened(0.35)])
	var mi := MeshInstance3D.new()
	mi.mesh = Placeholders.merge_colored(parts)
	mi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	root.add_child(mi)
	add_child(root)
	return root


## E near a grave (take your things back) or an unexplored ruin. {} if nothing.
func action(p: Vector3) -> Dictionary:
	var pid := Net.local_player_id()
	for uid: String in state.graves:
		if String(state.graves[uid]["owner"]) == pid and (state.graves[uid]["pos"] as Vector3).distance_to(p) < 3.5:
			return {"label": tr("act.loot_grave"), "run": func() -> void:
				world._send_move()
				Game.submit({"type": "loot_grave", "uid": uid})}
	for s: Dictionary in map.chud_sites():
		if not state.journal.has(s["id"]) and Vector2((s["pos"] as Vector3).x - p.x, (s["pos"] as Vector3).z - p.z).length() < 4.8:
			var site: String = s["id"]
			return {"label": tr("act.explore_" + String(s["kind"])), "run": func() -> void:
				world._send_move()
				if Game.submit({"type": "explore", "site": site}).get("ok", false) and _ruins.has(site):
					var sign := (_ruins[site] as Node3D).get_node("Sign") as MeshInstance3D
					(sign.material_override as ShaderMaterial).set_shader_parameter("strength", 0.0)}
	return {}
