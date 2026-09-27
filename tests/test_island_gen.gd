extends "res://tests/lib/case.gd"


func _isl(id: String) -> IslandGen:
	if id == "home":
		return IslandGen.from_content(db.home, "home")
	return IslandGen.from_content(db.beacons[id], id)


func test_same_seed_same_island() -> void:
	eq(_isl("b01").fingerprint(), _isl("b01").fingerprint())
	check(_isl("b01").fingerprint() != _isl("b02").fingerprint(), "different seeds differ")


func test_land_in_the_middle_sea_outside() -> void:
	for id in ["home", "b01", "b06", "b12"]:
		var isl := _isl(id)
		check(isl.is_land(isl.center.x, isl.center.y), id + ": centre is land")
		check(not isl.is_land(isl.center.x + isl.radius * 1.4, isl.center.y), id + ": beyond the margin is sea")


func test_beacon_plateau_is_flat() -> void:
	var isl := _isl("b03")
	var top: float = isl.plateau["height"]
	for a in 8:
		var p := isl.center + Vector2.from_angle(a * TAU / 8.0) * isl.radius * 0.05
		near(isl.height_at(p.x, p.y), top, 0.35, "plateau at angle %d" % a)


func test_resource_nodes_are_stable_and_on_land() -> void:
	var a := _isl("b02").resource_nodes()
	var b := _isl("b02").resource_nodes()
	eq(a.size(), b.size())
	check(a.size() > 10, "enough nodes: %d" % a.size())
	var isl := _isl("b02")
	for i in a.size():
		eq(a[i]["id"], b[i]["id"])
		var p: Vector3 = a[i]["pos"]
		check(isl.height_at(p.x, p.z) > 1.0, "node %s on land" % a[i]["id"])
		check(Vector2(p.x, p.z).distance_to(isl.center) > isl.radius * 0.08, "node %s outside the beacon clearing" % a[i]["id"])


func test_mesh_builds() -> void:
	var mesh := _isl("b01").build_mesh(4.0)
	check(mesh.get_surface_count() == 1, "one surface")
	check(mesh.surface_get_array_len(0) > 1000, "has triangles")
