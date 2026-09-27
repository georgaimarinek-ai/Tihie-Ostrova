shader_type spatial;
render_mode cull_disabled;

#include "res://src/shaders/fog_clear.gdshaderinc"

// Island terrain: flat normals come from the mesh (IslandGen.build_mesh), colour from vertex colours.
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));  // vertex colours are authored in sRGB
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	FOG = fog_for(world_pos, length(VERTEX));
}
