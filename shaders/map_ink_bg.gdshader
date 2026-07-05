// Procedural map backdrop: sumi-e ink-wash night. Near-black blue-charcoal
// base (#10131c) with soft cloud billows drifting like ink dispersing in
// dark water, faint washi-paper grain, and an edge vignette.
//
// Cloud shapes come from a FastNoiseLite simplex-fbm texture (fed in by
// map.gd) with domain warping — hand-rolled value noise looks blocky and
// square; simplex + warp gives organic, cloud-like billows.
shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 pan = vec2(0.0);
uniform float cloud_strength : hint_range(0.0, 0.5) = 0.17;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.02;
uniform float drift_speed : hint_range(0.0, 0.1) = 0.012;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 base = vec3(0.063, 0.075, 0.110);   // #10131c

	vec2 uv = UV * vec2(1.78, 1.0);
	vec2 p = uv * 0.85 - pan * 0.00025;
	float t = TIME * drift_speed;

	// Domain warp: push the cloud lookup around by another noise sample so
	// billows curl instead of sitting on a grid.
	vec2 warp = vec2(
			texture(noise_tex, p * 0.55 + vec2(t * 0.6, 0.0)).r,
			texture(noise_tex, p * 0.55 + vec2(0.37, t * 0.45)).r) - 0.5;

	float n1 = texture(noise_tex, p + warp * 0.30 + vec2(t, t * 0.55)).r;
	float n2 = texture(noise_tex, p * 2.2 + warp * 0.15 - vec2(t * 1.3, t * 0.25) + 0.61).r;
	float clouds = n1 * 0.65 + n2 * 0.35;

	// Bright mist billows hanging over the dark water…
	float mist = smoothstep(0.38, 0.78, clouds);
	vec3 col = base + mist * cloud_strength * vec3(0.50, 0.58, 0.85);
	// …and deeper ink pooling in the gaps between them.
	col -= (1.0 - smoothstep(0.22, 0.48, clouds)) * 0.022;

	// Static washi-paper grain.
	col += (hash(uv * 971.0) - 0.5) * grain_strength;

	// Vignette keeps the eye centred on the map.
	float d = distance(UV, vec2(0.5, 0.5));
	col *= 1.0 - smoothstep(0.42, 0.90, d) * 0.35;

	COLOR = vec4(col, 1.0);
}
