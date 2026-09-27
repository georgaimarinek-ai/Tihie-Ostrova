extends Node3D
## Phase 0 scene: the atmosphere slice rebuilt from content (docs/06_ROADMAP.md, phase 0). The game itself
## runs src/scenes/world.tscn; this slice stays as a reference shot (docs/images/p0_*.png) and a smoke test.
## Home island, the first beacon island (b01), the sea, fog with clearings. Press L to light the beacon
## through the command path (debug: grant fuel and the trial, then light_beacon) and watch the fog roll back.
##
## Command-line (after "--"):
##   --smoke            run 30 frames, print "SMOKE OK", quit (tools/verify.sh, headless)
##   --screenshot=PATH  save a frame to PATH and quit (needs a real renderer, e.g. xvfb + opengl3)
##   --frames=N         frame to take the screenshot at (default 120)
##   --light-at=N       light the beacon at frame N (default: never)

const PROP_SHADER := preload("res://src/shaders/prop.gdshader")
const TERRAIN_SHADER := preload("res://src/shaders/terrain.gdshader")
const FIRST_BEACON := "b01"

var db: ContentDB
var director: FogDirector
var cam: Camera3D
var sea: Sea
var fire_light: OmniLight3D
var fire_core: MeshInstance3D
var _args := {}
var _frame := 0
var _time := 0.0
var _fire_on := 0.0
var _beacon_top := Vector3.ZERO


func _ready() -> void:
	db = ContentDB.shared()
	_args = _parse_args()
	if Game.state == null:
		Game.debug_cheats = true
		Game.new_world(1, "quiet")
	Game.world_event.connect(_on_world_event)
	var env := _build_environment()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	_build_sea()
	var home := IslandGen.from_content(db.home, "home")
	_build_island(home)
	var b: Dictionary = db.beacons[FIRST_BEACON]
	var isl := IslandGen.from_content(b, FIRST_BEACON)
	_build_island(isl)
	_build_beacon(isl, db.beacon_pos(FIRST_BEACON))
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 2500.0
	add_child(cam)
	cam.look_at_from_position(Vector3(-15, 10, -95), Vector3(-55, 8, -235))
	director = FogDirector.new()
	director.db = db
	director.state = Game.state
	director.environment = env
	director.sun = sun
	add_child(director)
	sea.director = director


func _process(delta: float) -> void:
	_frame += 1
	_time += delta
	# a slow look around, like the sketch's intro camera
	cam.look_at_from_position(Vector3(-15, 10, -95), Vector3(-55 + sin(_time * 0.1) * 25.0, 8, -235))
	if _fire_on > 0.0:
		_fire_on = minf(1.0, _fire_on + delta / FogDirector.GROW_S)
		fire_light.light_energy = (5.0 + sin(_time * 17.0) * 1.2 + randf() * 0.8) * _fire_on
		fire_core.scale = Vector3.ONE * (0.6 + 0.4 * _fire_on) * (1.0 + sin(_time * 11.0) * 0.08)
	if _args.has("light-at") and _frame == int(_args["light-at"]):
		light_first_beacon()
	if _args.has("smoke") and _frame >= 30:
		print("SMOKE OK: frames=%d lit=%s" % [_frame, str(Game.state.lit.keys())])
		get_tree().quit(0)
	if _args.has("screenshot") and _frame >= int(_args.get("frames", 120)):
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(String(_args["screenshot"]))
		print("screenshot %s: %s" % [_args["screenshot"], error_string(err)])
		get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_L:
		light_first_beacon()


## Demo shortcut: stand at the beacon with its fuel, pass the trial, light it. Real play does the same
## through the player's actions (roadmap phase 5).
func light_first_beacon() -> void:
	var bpos := db.beacon_pos(FIRST_BEACON)
	Game.submit({"type": "debug", "give": ContentDB.bag(db.beacons[FIRST_BEACON]["fuel"]), "pos": [bpos.x, 0.0, bpos.y]})
	Game.submit({"type": "complete_trial", "beacon": FIRST_BEACON, "kind": "trial"})
	var res := Game.submit({"type": "light_beacon", "beacon": FIRST_BEACON})
	if not res["ok"]:
		push_warning("light_beacon failed: " + String(res["error"]))


func _on_world_event(e: Dictionary) -> void:
	if e.get("type", "") == "beacon_lit":
		director.mark_lit(e["beacon"])
		if e["beacon"] == FIRST_BEACON:
			_fire_on = 0.01
			fire_core.visible = true


# ---------------------------------------------------------------- building the slice

func _build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = false  # fog lives in the materials (fog_clear.gdshaderinc)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	return env


func _build_sea() -> void:
	sea = Sea.new()
	add_child(sea)


func _build_island(isl: IslandGen) -> void:
	var land := MeshInstance3D.new()
	land.mesh = isl.build_mesh(2.5)
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	land.material_override = m
	add_child(land)
	var pines: Array[Transform3D] = []
	var birches: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = isl.island_seed
	for n: Dictionary in isl.resource_nodes(1.2):
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.75, 1.35))
		var xf := Transform3D(basis, (n["pos"] as Vector3) + Vector3(0, -0.2, 0))
		match String(n["kind"]):
			"pine":
				pines.append(xf)
			"rock":
				rocks.append(xf)
			_:
				birches.append(xf)
	_multimesh(_pine_trunk(), _mat(Color("5b4331")), pines)
	_multimesh(_pine_crown(), _mat(Color("2f4a3a")), pines)
	_multimesh(_birch_trunk(), _mat(Color("e6e2d6")), birches)
	_multimesh(_birch_crown(), _mat(Color("93a851")), birches)
	var rock := SphereMesh.new()
	rock.radial_segments = 5
	rock.rings = 2
	_multimesh(rock, _mat(Color("7a7f84")), rocks)


func _build_beacon(isl: IslandGen, pos: Vector2) -> void:
	var y := isl.height_at(pos.x, pos.y) - 0.3
	var root := Node3D.new()
	root.position = Vector3(pos.x, y, pos.y)
	add_child(root)
	var dark := _mat(Color("3f2e22"))
	var wood := _mat(Color("6b4a33"))
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var leg := _box(Vector3(0.35, 10, 0.35), dark, root, Vector3(c.x * 1.04, 5, c.y * 1.04))
		leg.rotation = Vector3(c.y * 0.06, 0, c.x * -0.06)
	for i in range(1, 4):
		_box(Vector3(2.6 - i * 0.2, 0.2, 0.2), wood, root, Vector3(0, i * 2.4, 1.05 - i * 0.05))
		_box(Vector3(2.6 - i * 0.2, 0.2, 0.2), wood, root, Vector3(0, i * 2.4, -1.05 + i * 0.05))
	_box(Vector3(3.4, 0.3, 3.4), _mat(Color("8a6a4c")), root, Vector3(0, 10.1, 0))
	var bowl := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 0.6
	cyl.height = 0.8
	cyl.radial_segments = 6
	bowl.mesh = cyl
	bowl.material_override = _mat(Color("7c7f82"))
	bowl.position = Vector3(0, 10.7, 0)
	root.add_child(bowl)
	fire_core = MeshInstance3D.new()
	var flame := SphereMesh.new()
	flame.radius = 0.9
	flame.height = 2.4
	flame.radial_segments = 6
	flame.rings = 3
	fire_core.mesh = flame
	fire_core.material_override = _mat(Color("ffb050"), Color("ff8a30"), 4.0, false)
	fire_core.position = Vector3(0, 11.9, 0)
	fire_core.visible = false
	root.add_child(fire_core)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color("ff9a40")
	fire_light.omni_range = 70.0
	fire_light.light_energy = 0.0
	fire_light.position = Vector3(0, 12.4, 0)
	root.add_child(fire_light)
	_beacon_top = root.position + Vector3(0, 11.9, 0)


# ---------------------------------------------------------------- small helpers

func _mat(albedo: Color, emission: Color = Color.BLACK, energy: float = 0.0, fogged: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("fogged", fogged)
	return m


func _box(size: Vector3, mat: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


func _cone(r: float, h: float, top: float = 0.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c


func _pine_trunk() -> Mesh:
	return _merge([[_cone(0.22, 2.2, 0.16), Transform3D(Basis(), Vector3(0, 1.1, 0))]])


func _pine_crown() -> Mesh:
	return _merge([
		[_cone(1.7, 2.6), Transform3D(Basis(), Vector3(0, 1.9, 0))],
		[_cone(1.35, 2.3), Transform3D(Basis(), Vector3(0, 3.2, 0))],
		[_cone(0.95, 2.0), Transform3D(Basis(), Vector3(0, 4.4, 0))],
	])


func _birch_trunk() -> Mesh:
	return _merge([[_cone(0.17, 3.2, 0.12), Transform3D(Basis(), Vector3(0, 1.6, 0))]])


func _birch_crown() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.25
	s.height = 3.4
	s.radial_segments = 6
	s.rings = 3
	return _merge([[s, Transform3D(Basis(), Vector3(0, 3.6, 0))]])


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out
