// Fog with local clearings around lights (beacons, hearths, the player's lantern).
// Works in every renderer (Forward+, Mobile, Compatibility). Environment fog stays OFF: every world
// material includes this file and writes FOG = fog_for(world_pos, depth).
// The globals are declared in project.godot [shader_globals] and set by src/world/fog_director.gd
// from FogField.shader_slots(). Maths = FogField (src/core/fog_field.gd); keep them identical.
// Forward+ "high" quality adds volumetric fog on top (docs/04_TECH_SPEC.md §5).

global uniform vec4 fog_color;     // rgb in linear space
global uniform float fog_density;  // exp2 density, from the region chapter (regions.json)
global uniform vec4 fog_clear_0;   // x, z, radius, strength (FogField.SLOTS = 8)
global uniform vec4 fog_clear_1;
global uniform vec4 fog_clear_2;
global uniform vec4 fog_clear_3;
global uniform vec4 fog_clear_4;
global uniform vec4 fog_clear_5;
global uniform vec4 fog_clear_6;
global uniform vec4 fog_clear_7;

const float FOG_CLEAR_FACTOR = 0.22;  // balance.json fog.clear_factor
const float FOG_CLEAR_EDGE = 0.3;     // balance.json fog.clear_edge

float fog_clear_term(vec2 p, vec4 c) {
	float d = distance(p, c.xy);
	return mix(1.0, smoothstep(c.z * FOG_CLEAR_EDGE, max(c.z, 0.001), d), c.w);
}

vec4 fog_for(vec3 world_pos, float view_depth) {
	vec2 p = world_pos.xz;
	float k = min(min(min(fog_clear_term(p, fog_clear_0), fog_clear_term(p, fog_clear_1)),
			min(fog_clear_term(p, fog_clear_2), fog_clear_term(p, fog_clear_3))),
			min(min(fog_clear_term(p, fog_clear_4), fog_clear_term(p, fog_clear_5)),
			min(fog_clear_term(p, fog_clear_6), fog_clear_term(p, fog_clear_7))));
	float dens = fog_density * mix(FOG_CLEAR_FACTOR, 1.0, k);
	float f = 1.0 - exp(-dens * dens * view_depth * view_depth);
	return vec4(fog_color.rgb, clamp(f, 0.0, 1.0));
}
