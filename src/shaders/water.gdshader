shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

#include "res://src/shaders/fog_clear.gdshaderinc"

global uniform float sea_storm;
global uniform float sea_time;  // the wave clock shared with boats (Sea.time), not TIME: they must agree
global uniform vec3 sun_dir;  // towards the sun, world space (FogDirector)
global uniform vec4 sun_glint;  // rgb = sun colour × strength (FogDirector)
uniform vec3 deep_color : source_color = vec3(0.145, 0.235, 0.267);
uniform vec3 shallow_color : source_color = vec3(0.357, 0.478, 0.502);
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform vec4 glow = vec4(0.0);  // x, z, 0, strength: warm reflection of the nearest lit beacon

varying vec3 world_pos;

// WAVES-BEGIN: the same numbers as Waves.PARAMS (src/core/waves.gd); tests/test_waves.gd checks them.
float wave_h(vec2 p, float t) {
	return 0.34 * sin(0.12 * p.x + 0.0 * p.y + 0.9 * t + 0.0)
		+ 0.24 * sin(0.0 * p.x + 0.17 * p.y + 1.3 * t + 1.7)
		+ 0.12 * sin(0.31 * p.x + 0.31 * p.y + 1.9 * t + 0.0)
		+ 0.06 * sin(0.53 * p.x + -0.53 * p.y + 2.7 * t + 0.0);
}
// WAVES-END

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = wave_h(w.xz, sea_time) * (1.0 + 0.6 * sea_storm);
	VERTEX.y += h;
	world_pos = w + vec3(0.0, h, 0.0);
}

void fragment() {
	// flat, faceted water like the sketch: face normal from screen-space derivatives (view space)
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, -VERTEX) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fres = pow(1.0 - clamp(dot(n, normalize(-VERTEX)), 0.0, 1.0), 3.0);
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float tilt = 1.0 - clamp(dot(n, up_view), 0.0, 1.0);
	ALBEDO = mix(deep_color, shallow_color, clamp(fres * 0.9 + tilt * 2.5, 0.0, 1.0));
	float g = glow.w * exp(-distance(world_pos.xz, glow.xy) / 18.0);
	// the sun's glint lives in EMISSION so the fog swallows it with distance (specular light is not fogged)
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 vw = normalize(CAMERA_POSITION_WORLD - world_pos);
	float glint = pow(max(dot(nw, normalize(sun_dir + vw)), 0.0), 90.0);
	EMISSION = glow_color * g * (0.35 + fres) + sun_glint.rgb * glint;
	ROUGHNESS = 1.0;  // no mirror of the sky's sun disk: the glint is computed above, like the sketch
	SPECULAR = 0.0;
	FOG = fog_for(world_pos, length(VERTEX));
}

void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
}
