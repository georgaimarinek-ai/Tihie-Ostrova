class_name Sea
extends MeshInstance3D
## The sea (docs/04_TECH_SPEC.md §6): one flat-shaded plane that follows the camera on its own 4 m vertex
## grid (waves are computed in world space, so moving it never shows a seam). It owns the wave clock
## shared by the water shader (global sea_time) and by boats (Waves.height(x, z, Sea.time)), and takes
## its colours from the fog director's palette.

const WATER_SHADER := preload("res://src/shaders/water.gdshader")
const SIZE := 900.0
const CELLS := 225  # 900 / 225 = 4 m grid

## The wave clock. Advanced in physics frames so boats and the shader agree.
static var time := 0.0
## The tide (SeaLife.tide_offset): the world sets it, every floating thing and the shader read it.
static var level := 0.0

var director: FogDirector
var storm := 0.0  # 0..3, from the weather (Waves.STORM_GAIN)
var glow := Vector4.ZERO  # warm reflection of the nearest lit beacon: x, z, 0, strength
var _mat: ShaderMaterial
var _far: MeshInstance3D
const FAR_SIZE := 7000.0


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = CELLS - 1
	plane.subdivide_depth = CELLS - 1
	mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = WATER_SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 8.0  # waves lift vertices above the flat plane's bounds
	# the horizon: a flat disc far beyond the wave mesh, so distant islands stand on water, not on sky
	_far = MeshInstance3D.new()
	_far.name = "FarSea"
	var fp := PlaneMesh.new()
	fp.size = Vector2(FAR_SIZE, FAR_SIZE)
	_far.mesh = fp
	_far.position = Vector3(0, -0.6, 0)
	_far.material_override = Placeholders.mat(Color(0.145, 0.235, 0.267))
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far)


func _physics_process(delta: float) -> void:
	time += delta


func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("sea_time", time)
	RenderingServer.global_shader_parameter_set("sea_storm", storm)
	RenderingServer.global_shader_parameter_set("sea_level", level)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var cell := SIZE / CELLS
		global_position = Vector3(snappedf(cam.global_position.x, cell), 0.0, snappedf(cam.global_position.z, cell))
	if director != null and not director.palette.is_empty():
		_mat.set_shader_parameter("deep_color", director.palette["sea_deep"])
		_mat.set_shader_parameter("shallow_color", director.palette["sea_shallow"])
		if _far != null:
			(_far.material_override as ShaderMaterial).set_shader_parameter("albedo", director.palette["sea_deep"])
	_mat.set_shader_parameter("glow", glow)


## Water height under a point right now (for floating things other than boats: flotsam, the camera).
static func height(x: float, z: float, storm_level: float = 0.0) -> float:
	return Waves.height(x, z, time, storm_level) + level
