shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// Soft additive glow sprites (beacon fire halo, the hint light over the next beacon, sparks). Not fogged:
// lights must read through the Mga. Billboard quads facing the camera.
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.25);
uniform float strength = 1.0;
uniform float softness = 1.6;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	ALBEDO = color * a * strength;
}
