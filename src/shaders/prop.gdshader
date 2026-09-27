shader_type spatial;
render_mode cull_disabled;

#include "res://src/shaders/fog_clear.gdshaderinc"

// Wooden props, stones, cloth, trees: a flat colour per material (or vertex / MultiMesh instance colours,
// or the artist's palette texture), optional glow (windows, fire bowls). Double-sided: open hulls and sails.
uniform vec3 albedo : source_color = vec3(0.42, 0.29, 0.2);
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float roughness = 0.95;
uniform bool fogged = true;  // false for glows that must read through the fog (beacon fire)
uniform bool flat_shading = true;  // faceted low-poly look for primitive meshes with smooth normals
uniform bool use_vertex_color = false;  // vertex colours × MultiMesh instance colours (authored in sRGB)
uniform bool use_palette = false;  // the artist's models: UVs into art/palette.png (docs/05_ART_AUDIO.md §4.4)
uniform sampler2D palette : source_color, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (flat_shading) {
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(n, -VERTEX) < 0.0) {
			n = -n;
		}
		NORMAL = n;
	} else if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 col = albedo;
	if (use_palette) {
		col = texture(palette, UV).rgb;
	}
	if (use_vertex_color) {
		col *= pow(COLOR.rgb, vec3(2.2));
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.15;  // specular light is not fogged: keep it faint
	EMISSION = emission * emission_energy;
	if (fogged) {
		FOG = fog_for(world_pos, length(VERTEX));
	}
}
