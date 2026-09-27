shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Build preview: a see-through ghost, green when the place command would pass, red when not.
uniform vec3 color : source_color = vec3(0.56, 0.89, 0.63);
uniform float alpha = 0.38;

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(-VERTEX)));
	ALBEDO = color;
	ALPHA = alpha + rim * 0.35;
}
