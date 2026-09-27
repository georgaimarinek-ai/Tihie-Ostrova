extends "res://tests/lib/case.gd"
## The artist's models (docs/05_ART_AUDIO.md §4): every art/models/<category>/<id>.glb must have an id from
## content, a sensible size (people 1.6–2.0 m, building pieces on the 2 m grid, boats as long as their
## hull), animation clips named from the table, and "-glow" objects where light is needed.
## Placeholders follow the same rules, so swapping a model in moves nothing.

const PROPS: Array[String] = ["izba", "pier", "pomor_cross", "beacon_tower", "chapel", "stump", "path_lantern", "bell", "mirror", "chest_old"]
const CLIPS := {
	"player": ["idle-loop", "walk-loop", "run-loop", "jump", "chop", "mine", "gather", "carry_torch-loop", "row-loop", "sit-loop", "sleep-loop", "attack_light", "attack_heavy", "block", "dodge", "hit", "die"],
	"creatures": ["idle-loop", "walk-loop", "run-loop", "attack", "hit", "die", "appear", "vanish", "phase2", "special_1", "special_2"],
}
const GRID_SNAPS: Array[String] = ["foundation", "wall", "floor", "roof", "pier"]


func _known(category: String, id: String) -> bool:
	match category:
		"pieces":
			return db.pieces.has(id)
		"boats":
			return db.boats.has(id)
		"creatures":
			return db.creatures.has(id)
		"props":
			return id in PROPS
		"player":
			return id == "pomor"
	return false


## Bounds of every mesh under `root`, in root space.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in ModelLibrary._meshes(root):
		if mi.mesh == null:
			continue
		var xf := Transform3D()
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _check(category: String, id: String, node: Node3D) -> void:
	var box := bounds(node)
	var what := "%s/%s" % [category, id]
	match category:
		"player":
			check(box.size.y >= 1.6 and box.size.y <= 2.0, "%s: height %.2f m, want 1.6–2.0" % [what, box.size.y])
			check(absf(box.position.y) < 0.1, "%s: pivot between the feet (bottom at %.2f)" % [what, box.position.y])
		"boats":
			var want: float = Placeholders.HULLS[id]["length"]
			check(absf(box.size.z - want) / want < 0.15, "%s: length %.1f m, hull %.1f m" % [what, box.size.z, want])
			check(box.position.y < 0.0 and box.end.y > 0.0, "%s: pivot on the waterline" % what)
		"pieces":
			var p: Dictionary = db.pieces[id]
			if String(p.get("snap", "free")) in GRID_SNAPS:
				var ok := false
				for ext: float in [box.size.x, box.size.z]:
					var k := ext / 2.0
					if ext > 0.8 and absf(k - roundf(k)) * 2.0 / maxf(ext, 0.01) < 0.05:
						ok = true
				check(ok, "%s: a side on the 2 m grid (%.2f × %.2f)" % [what, box.size.x, box.size.z])
			if p.has("fog_radius") or String(p["category"]) == "light":
				check(_has_glow(node), "%s: gives light, needs a -glow object" % what)
	var ap := ModelLibrary.animation_player(node)
	if ap != null and CLIPS.has(category):
		for clip in ap.get_animation_list():
			check(String(clip) in CLIPS[category] or String(clip) == "RESET", "%s: clip '%s' is not in the table (§4.5)" % [what, clip])


func _has_glow(n: Node) -> bool:
	if n.name.to_lower().contains("glow"):
		return true
	for c in n.get_children():
		if _has_glow(c):
			return true
	return false


func test_models_on_disk() -> void:
	for category in ModelLibrary.CATEGORIES:
		var dir := ModelLibrary.ROOT.path_join(category)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var id := f.get_basename()
			check(_known(category, id), "%s/%s: no such id in content" % [category, f])
			if _known(category, id):
				var node := ModelLibrary.instance(category, id)
				_check(category, id, node)
				node.free()


func test_placeholders_follow_the_rules() -> void:
	var p := Placeholders.pomor()
	_check("player", "pomor", p)
	p.free()
	for id: String in db.boats:
		var b := Placeholders.boat(id)
		_check("boats", id, b)
		b.free()
