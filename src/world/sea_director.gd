class_name SeaDirector
extends Node
## The living sea around the player (docs/08_NEXT.md 13.1). On every peer: the flotsam afloat
## (WorldState.flotsam) as bobbing things, and the tide's turn in a toast. On the host: what a storm leaves
## behind — logs, barrels and a bottle near the shores for balance.sea_events.flotsam.after_storm_min after
## a squall (the "flotsam" command; the player hauls them in with "pick_flotsam").

var world  # the world scene (untyped)
var db: ContentDB
var state: WorldState
var map: WorldMap
var nodes: Dictionary = {}  # flotsam uid -> Node3D

var _last_storm := 0
var _storm_ended_at := -INF  # clock minute the last squall blew out
var _spawn_t := 20.0
var _tide_low := false
var _first := true


func setup(p_world) -> void:
	world = p_world
	db = world.db
	state = world.state
	map = world.map
	name = "SeaLife"


func _process(delta: float) -> void:
	_sync()
	var low := SeaLife.tide_low(db, state.clock_min)
	if low != _tide_low and not _first:
		world.hud.toast(world.tr("toast.tide_low" if low else "toast.tide_high"), "≈")
	_tide_low = low
	_first = false
	if not Net.is_authority():
		return
	var f: Vector3 = world._focus()
	var rid := db.region_at(Vector2(f.x, f.z))
	var level := Weather.storm(db, state.world_seed, state.clock_min, rid)
	if level < _last_storm:
		_storm_ended_at = state.clock_min
	_last_storm = level
	var fl: Dictionary = db.balance["sea_events"]["flotsam"]
	if world.on_foot() or state.clock_min - _storm_ended_at > float(fl["after_storm_min"]) or state.flotsam.size() >= 4:
		return
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t = randf_range(40.0, 90.0)
	var at := _spot(f)
	if at == Vector3.INF:
		return
	var pick := randf()
	var kind := "log" if pick < 0.5 else ("barrel" if pick < 0.85 else "bottle")
	Game.submit({"type": "flotsam", "kind": kind, "pos": WorldState._v3(at)})


## Water 40–110 m from the boat, not deep (things drift in towards the shores).
func _spot(f: Vector3) -> Vector3:
	for k in 12:
		var a := randf() * TAU
		var p2 := Vector2(f.x, f.z) + Vector2.from_angle(a) * randf_range(40.0, 110.0)
		var g := map.ground_at(p2.x, p2.y)
		if g < -1.0 and g > -9.0:
			return Vector3(p2.x, 0.0, p2.y)
	return Vector3.INF


## Views follow the world: new flotsam gets a body, gone flotsam loses it; everything rides the waves.
func _sync() -> void:
	for uid: String in state.flotsam:
		if not nodes.has(uid):
			var f: Dictionary = state.flotsam[uid]
			var n := _make(String(f["kind"]))
			n.name = "Flotsam_" + uid
			world.add_child(n)
			n.global_position = f["pos"]
			n.rotation.y = randf() * TAU
			nodes[uid] = n
	for uid: String in nodes.keys():
		if not state.flotsam.has(uid):
			(nodes[uid] as Node).queue_free()
			nodes.erase(uid)
	var t := Sea.time
	for uid: String in nodes:
		var n: Node3D = nodes[uid]
		n.global_position.y = Sea.height(n.global_position.x, n.global_position.z, world.sea.storm) + 0.05
		n.rotation.x = sin(t * 0.9 + n.global_position.x) * 0.08
		n.rotation.z = cos(t * 0.7 + n.global_position.z) * 0.1


## E over a thing afloat (from the boat within reach_m, wading within 4 m): haul it in.
func action(p: Vector3, aboard: bool) -> Dictionary:
	var reach := float(db.balance["sea_events"]["flotsam"]["reach_m"]) if aboard else 4.0
	var best := ""
	var best_d := reach
	for uid: String in state.flotsam:
		var d := Vector2(p.x, p.z).distance_to(Vector2((state.flotsam[uid]["pos"] as Vector3).x, (state.flotsam[uid]["pos"] as Vector3).z))
		if d < best_d:
			best_d = d
			best = uid
	if best == "":
		return {}
	var kind := String(state.flotsam[best]["kind"])
	var label: String = world.tr("act.pick_bottle") if kind == "bottle" else world.tr("act.pick_flotsam") % world.tr("flotsam." + kind)
	var uid := best
	return {"label": label, "run": func() -> void:
		world._send_move()
		Game.submit({"type": "pick_flotsam", "uid": uid})}


## Placeholder bodies (art/models/props/flotsam_<kind>.glb when the artist makes them).
func _make(kind: String) -> Node3D:
	if ModelLibrary.has_model("props", "flotsam_" + kind):
		return ModelLibrary.instance("props", "flotsam_" + kind)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	match kind:
		"log":
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.26
			c.height = 3.2
			mi.mesh = c
			mi.rotation.z = PI * 0.5
			mi.material_override = Placeholders.mat(Color("5a4330"))
		"barrel":
			var c := CylinderMesh.new()
			c.top_radius = 0.34
			c.bottom_radius = 0.34
			c.height = 0.9
			mi.mesh = c
			mi.rotation.z = PI * 0.5
			mi.position.y = 0.1
			mi.material_override = Placeholders.mat(Color("6b5538"))
		_:
			var s := SphereMesh.new()
			s.radius = 0.14
			s.height = 0.4
			mi.mesh = s
			mi.position.y = 0.1
			mi.material_override = Placeholders.mat(Color("3f6a4a"), Color("70c080"), 0.6)
			root.add_child(Placeholders.glow(Color("90e0a0"), 1.2, 0.5))
	root.add_child(mi)
	return root
