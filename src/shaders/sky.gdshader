shader_type sky;

// The sky of the sketch: the horizon IS the fog colour (so fully fogged islands vanish into it), a zenith
// colour per weather chapter, a soft sun, stars and the aurora at night (docs/05_ART_AUDIO.md §5).
// FogDirector sets the uniforms from the region palette every frame.
uniform vec3 horizon : source_color = vec3(0.682, 0.722, 0.733);
uniform vec3 zenith : source_color = vec3(0.486, 0.557, 0.608);
uniform vec3 sun_color : source_color = vec3(1.0, 0.84, 0.69);
uniform float night = 0.0;
uniform float aurora = 0.0;
uniform float time = 0.0;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float t = smoothstep(-0.02, 0.55, d.y);
	vec3 col = mix(horizon, zenith, t);
	float s = max(dot(d, normalize(LIGHT0_DIRECTION)), 0.0);
	col += sun_color * (pow(s, 600.0) * 3.0 + pow(s, 12.0) * 0.35) * (1.0 - night * 0.6);
	if (night > 0.01 && d.y > 0.02) {
		vec3 c = floor(d * 260.0);
		float h = hash(c);
		float st = step(0.9975, h) * (0.6 + 0.4 * sin(time * 2.0 + h * 50.0));
		col += vec3(st) * night * smoothstep(0.02, 0.3, d.y);
	}
	if (aurora > 0.01 && d.y > 0.05 && d.z < 0.2) {
		// ribbons over the northern half of the sky, green to violet, shimmering on sines
		float az = atan(d.x, -d.z);
		float band = sin(az * 3.0 + sin(az * 7.0 + time * 0.3) * 0.6 + time * 0.1);
		float height = smoothstep(0.08, 0.25, d.y) * (1.0 - smoothstep(0.35, 0.7, d.y));
		float curtain = pow(max(0.0, 1.0 - abs(d.y - 0.22 - band * 0.08) * 6.0), 2.0);
		float w = 0.5 + 0.5 * sin(az * 40.0 + time * 0.7 + sin(az * 13.0 - time * 0.4) * 2.0);
		vec3 ac = mix(vec3(0.15, 1.0, 0.55), vec3(0.6, 0.35, 1.0), smoothstep(0.2, 0.5, d.y));
		col += ac * curtain * height * (0.35 + 0.65 * w) * aurora * 0.55 * smoothstep(0.2, -0.3, d.z);
	}
	COLOR = col;
}
