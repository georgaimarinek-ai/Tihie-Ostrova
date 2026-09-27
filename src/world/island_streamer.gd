class_name IslandStreamer
extends Node3D
## Streams islands around the viewer (docs/04_TECH_SPEC.md §8): a full IslandView (mesh, collision,
## vegetation) closer than BUILD_M, dropped beyond DROP_M; a coarse silhouette out to FAR_M so distant
## islands still show through clearings. Heavy data is computed on the WorkerThreadPool; nodes are added
## to the tree on the main thread.

signal island_built(view: IslandView)

const BUILD_M := 600.0
const DROP_M := 900.0
const FAR_M := 2600.0
const MAX_TASKS := 2

var map: WorldMap
var state: WorldState
var focus := Vector3.ZERO
var views: Dictionary = {}  # island id -> IslandView
var far: Dictionary = {}  # island id -> Node3D

var _tasks: Dictionary = {}  # key ("full:id" / "far:id") -> {"task": int, "data": Dictionary}
var _timer := 0.0


## Builds everything near `pos` right now (start of the game, teleports) so nothing pops in.
func build_around(pos: Vector3) -> void:
	focus = pos
	for isl in map.islands:
		if _dist(isl) < BUILD_M and not views.has(isl.id):
			_add_full(isl, IslandView.prepare(isl))


func _process(delta: float) -> void:
	_finish_tasks()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	for isl in map.islands:
		var d := _dist(isl)
		var id := isl.id
		if d < BUILD_M:
			if not views.has(id):
				_start("full:" + id, isl, IslandView.STEP)
		elif d > DROP_M and views.has(id):
			(views[id] as Node).queue_free()
			views.erase(id)
		if d < FAR_M:
			if not far.has(id):
				_start("far:" + id, isl, IslandView.FAR_STEP)
		elif far.has(id):
			(far[id] as Node).queue_free()
			far.erase(id)
		if far.has(id):
			(far[id] as Node3D).visible = not views.has(id)


func _dist(isl: IslandGen) -> float:
	return Vector2(focus.x, focus.z).distance_to(isl.center) - isl.radius * IslandGen.MARGIN


func _start(key: String, isl: IslandGen, step: float) -> void:
	if _tasks.has(key) or _tasks.size() >= MAX_TASKS:
		return
	map.nodes(isl.id)  # resource nodes are cached on the main thread, never inside a worker
	var job := {"isl": isl, "step": step, "data": {}}
	job["task"] = WorkerThreadPool.add_task(_work.bind(job))
	_tasks[key] = job


func _work(job: Dictionary) -> void:
	job["data"] = IslandView.prepare(job["isl"], job["step"])


func _finish_tasks() -> void:
	for key: String in _tasks.keys():
		var job: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(int(job["task"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
		_tasks.erase(key)
		var isl: IslandGen = job["isl"]
		if key.begins_with("full:"):
			if not views.has(isl.id) and _dist(isl) < DROP_M:
				_add_full(isl, job["data"])
		elif not far.has(isl.id) and _dist(isl) < FAR_M:
			var f := IslandView.silhouette(map, isl, job["data"])
			add_child(f)
			far[isl.id] = f
			f.visible = not views.has(isl.id)


func _add_full(isl: IslandGen, data: Dictionary) -> void:
	var v := IslandView.new()
	v.setup(map, isl, data)
	add_child(v)
	views[isl.id] = v
	if state != null:
		v.refresh(state)
	if far.has(isl.id):
		(far[isl.id] as Node3D).visible = false
	island_built.emit(v)


func refresh_all() -> void:
	for v: IslandView in views.values():
		v.refresh(state)


## Solid circles (trees, rocks) of built islands near a point, for the camera.
func solids_near(p: Vector2, radius: float) -> Array:
	var out: Array = []
	for v: IslandView in views.values():
		if p.distance_to(v.isl.center) > v.isl.radius * IslandGen.MARGIN + radius:
			continue
		for s: Dictionary in v.solids:
			if p.distance_to(s["pos"]) < radius:
				out.append(s)
	return out


func _exit_tree() -> void:
	for job: Dictionary in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	_tasks.clear()
