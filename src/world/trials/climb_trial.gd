class_name ClimbTrial
extends Trial
## "Climb the ledges to the brazier" (b02, b06, b10): stone ledges spiral up around the tower, a jump apart
## (Space); a plank bridges the last one to the tower's deck. A slip only drops you onto a lower ledge
## (docs/01_GDD.md §5.2). Standing on the deck passes the trial — the host sees the height.

const LEDGES := 24
const RISE := 0.42
const RADIUS := 3.9

var _top := 0.0


func build() -> void:
	var base := tower_base()
	var dir: Vector2 = map.paths[bid]["dir"]
	var start := dir.angle()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var parts: Array = []
	for i in LEDGES:
		var a := start - i * 0.37
		var p := Vector3(base.x + cos(a) * RADIUS, base.y + (i + 1) * RISE, base.z + sin(a) * RADIUS)
		var size := Vector3(1.35, 0.3, 1.1)
		var xf := Transform3D(Basis(Vector3.UP, -a), p - Vector3(0, 0.15, 0))
		var bm := BoxMesh.new()
		bm.size = size
		parts.append([bm, xf, Placeholders.STONE.darkened(0.05 * (i % 3))])
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.transform = xf
		body.add_child(cs)
		if i == LEDGES - 1:
			# a plank from the last ledge onto the deck
			var plank_pos := Vector3(base.x + cos(a) * RADIUS * 0.62, base.y + 9.95, base.z + sin(a) * RADIUS * 0.62)
			var pm := BoxMesh.new()
			pm.size = Vector3(2.4, 0.12, 0.8)
			var pxf := Transform3D(Basis(Vector3.UP, -a), plank_pos - Vector3(0, 0.06, 0))
			parts.append([pm, pxf, Placeholders.PLANK])
			var pcs := CollisionShape3D.new()
			var pb := BoxShape3D.new()
			pb.size = pm.size
			pcs.shape = pb
			pcs.transform = pxf
			body.add_child(pcs)
	var mi := MeshInstance3D.new()
	mi.mesh = Placeholders.merge_colored(parts)
	mi.material_override = Placeholders.mat(Color.WHITE, Color.BLACK, 0.0, true, true)
	add_child(mi)
	var isl: IslandGen = map.by_id[bid]
	_top = isl.height_at(isl.center.x, isl.center.y) + WorldCommands.CLIMB_TOP_M


func tick(_delta: float) -> void:
	if finished:
		return
	var p := player_pos()
	var t := tower_base()
	if p.y >= _top and Vector2(p.x - t.x, p.z - t.z).length() < 2.2 and world.player.is_on_floor():
		complete()


func goal() -> String:
	return tr("goal.climb_ledges")
