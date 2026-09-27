shader_type spatial;

#include "res://src/shaders/fog_clear.gdshaderinc"

// Wooden props, stones, cloth: one flat colour per material, optional glow (windows, fire bowls).
uniform vec3 albedo : source_color = vec3(0.42, 0.29, 0.2);
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float roughness = 0.95;
uniform bool fogged = true;  // false for glows that must read through the fog (beacon fire)
uniform bool flat_shading = true;  // faceted low-poly look for primitive meshes with smooth normals

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
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	EMISSION = emission * emission_energy;
	if (fogged) {
		FOG = fog_for(world_pos, length(VERTEX));
	}
}
