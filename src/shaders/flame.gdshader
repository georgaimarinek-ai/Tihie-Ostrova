shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Flame "tongues" for CPUParticles3D (torches, beacon fires, hearths). Normal blending, not additive:
// additive flames vanish against the white fog (docs/05_ART_AUDIO.md §5). Colour and fade come from the
// particle colour ramp (COLOR). Billboarded like the sketch's sprites.
uniform float night = 0.0;  // at night a little additive-looking brightness is added

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;  // up
	float w = 0.62 * (1.0 - smoothstep(-0.6, 1.0, p.y));  // a teardrop narrowing upwards
	float body = 1.0 - smoothstep(w * 0.55, w, abs(p.x));
	body *= 1.0 - smoothstep(0.55, 1.0, p.y) * 0.8;
	body *= smoothstep(-1.0, -0.55, p.y);
	float core = (1.0 - smoothstep(0.0, w * 0.6, abs(p.x))) * (1.0 - smoothstep(-0.6, 0.3, p.y));
	vec3 col = mix(COLOR.rgb, vec3(1.0, 0.93, 0.7), core * 0.7);
	ALBEDO = col * (1.0 + night * 0.6);
	ALPHA = clamp(body * COLOR.a, 0.0, 1.0);
}
