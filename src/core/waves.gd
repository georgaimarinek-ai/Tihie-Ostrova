class_name Waves
extends RefCounted
## Sea surface height, shared by boat buoyancy (GDScript) and the water shader (GLSL).
## The shader keeps the same numbers between WAVES-BEGIN / WAVES-END in src/shaders/water.gdshader;
## tests/test_waves.gd fails if they drift apart. Change both together.
##
## height = (1 + STORM_GAIN * storm) * Σ a · sin(kx·x + kz·z + ω·t + φ)

## [a, kx, kz, ω, φ] per component. Metres, radians per metre, radians per second.
const PARAMS: Array = [
	[0.34, 0.12, 0.0, 0.9, 0.0],
	[0.24, 0.0, 0.17, 1.3, 1.7],
	[0.12, 0.31, 0.31, 1.9, 0.0],
	[0.06, 0.53, -0.53, 2.7, 0.0],
]
const STORM_GAIN := 0.6


static func height(x: float, z: float, t: float, storm: float = 0.0) -> float:
	var h := 0.0
	for p: Array in PARAMS:
		h += p[0] * sin(p[1] * x + p[2] * z + p[3] * t + p[4])
	return h * (1.0 + STORM_GAIN * storm)


## Largest possible |height| for a storm level: used for camera and buoyancy limits.
static func max_height(storm: float = 0.0) -> float:
	var s := 0.0
	for p: Array in PARAMS:
		s += absf(p[0])
	return s * (1.0 + STORM_GAIN * storm)


## Surface normal by central differences (e = 0.5 m).
static func normal(x: float, z: float, t: float, storm: float = 0.0) -> Vector3:
	var e := 0.5
	var dx := height(x + e, z, t, storm) - height(x - e, z, t, storm)
	var dz := height(x, z + e, t, storm) - height(x, z - e, t, storm)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## The four numbers per line in the shader block, flattened in PARAMS order.
static func flat_params() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Array in PARAMS:
		for v: float in p:
			out.append(v)
	return out
