class_name Trial
extends Node3D
## A beacon's trial on its island (docs/01_GDD.md §5.2, beacons.json → trial). Each kind builds its props
## along the path to the tower, answers "what can E do here?" and "what does the goal line say?", and when
## the player has done it sends the one command that counts: {"type": "complete_trial"}. The host checks
## what it can (the island, fire in hand, the height of the climb); the rest is the player's own play.

signal done

var world  # the world scene (player, audio, hud, beacons…): untyped, its members are read dynamically
var db: ContentDB
var map: WorldMap
var bid := ""
var kind := ""
var finished := false


static func create(p_kind: String) -> Trial:
	match p_kind:
		"carry":
			return CarryTrial.new()
		"lanterns":
			return LanternsTrial.new()
		"bells":
			return BellsTrial.new()
		"mirror":
			return MirrorTrial.new()
		"climb":
			return ClimbTrial.new()
		"finale":
			return FinaleTrial.new()
	return CarryTrial.new()


func setup(p_world, p_bid: String) -> void:
	world = p_world
	db = world.db
	map = world.map
	bid = p_bid
	kind = String(db.beacons[bid]["trial"])
	name = "Trial_%s_%s" % [bid, kind]
	build()


## Props go up here.
func build() -> void:
	pass


## E on foot at `p`: {"label", "run": Callable} or {}.
func action(_p: Vector3) -> Dictionary:
	return {}


## The goal line while the player is on this island.
func goal() -> String:
	return ""


## Where the compass points on the island ({} = the tower).
func target() -> Dictionary:
	return {}


## Extra fog clearings (lit lanterns).
func fog_lights() -> Array[Vector4]:
	return []


func tick(_delta: float) -> void:
	pass


## Tell the host the trial is passed (World sends the player's position first).
func complete() -> void:
	if finished:
		return
	if has_meta("finale"):
		(get_parent() as FinaleTrial).part_complete(self)
		return
	world._send_move()
	var res: Dictionary = Game.submit({"type": "complete_trial", "beacon": bid, "kind": "trial"})
	if res.get("ok", false):
		finished = true
		done.emit()


func player_pos() -> Vector3:
	return (world.player as Node3D).global_position


func has_light() -> bool:
	return String(world.player.light_id) != ""


func tower_base() -> Vector3:
	var bv: BeaconView = world.beacons[bid]
	return bv.global_position


func fire_pos() -> Vector3:
	var bv: BeaconView = world.beacons[bid]
	return bv.fire_pos


func sfx(k: String, arg: int = 0) -> void:
	(world.audio as AudioDirector).sfx(k, arg)


static func post(parent: Node3D, pos: Vector3, h: float, col: Color = Placeholders.DARK_WOOD) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, h, 0.18)
	mi.mesh = bm
	mi.material_override = Placeholders.mat(col)
	mi.position = pos + Vector3(0, h * 0.5, 0)
	parent.add_child(mi)
	return mi
