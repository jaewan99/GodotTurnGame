// Horizontal Diablo-style liquid bar.
// fill  = current value (0..1), the liquid surface with waves/bubbles.
// ghost = trailing value that lerps down after damage; the gap between
//         ghost and fill renders as a fading "recent damage" band.
// mirrored flips the drain direction for the right-side (enemy) HUD.
shader_type canvas_item;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float ghost : hint_range(0.0, 1.0) = 1.0;
uniform bool mirrored = false;
uniform vec4 liquid_color : source_color = vec4(0.18, 0.72, 0.30, 1.0);
uniform vec4 liquid_deep : source_color = vec4(0.04, 0.34, 0.12, 1.0);
uniform vec4 back_color : source_color = vec4(0.03, 0.04, 0.05, 0.88);
uniform vec4 ghost_color : source_color = vec4(0.85, 0.22, 0.18, 0.60);
uniform float wave_amp : hint_range(0.0, 0.1) = 0.022;
uniform float wave_speed = 2.4;
uniform float bubbles : hint_range(0.0, 1.0) = 1.0;

float wobble(float y, float t) {
	return sin(y * 9.0 + t * wave_speed) * 0.6
	     + sin(y * 17.0 - t * wave_speed * 1.7) * 0.4;
}

void fragment() {
	vec2 uv = UV;
	if (mirrored) { uv.x = 1.0 - uv.x; }
	float t = TIME;

	// Waves are strongest mid-bar, damped when nearly empty/full so the
	// liquid never leaks past the frame ends.
	float damp = clamp(fill * (1.0 - fill) * 10.0, 0.0, 1.0);
	float front = fill + wobble(uv.y, t) * wave_amp * damp;

	vec4 col = back_color;

	if (uv.x >= front && uv.x < ghost) {
		col = ghost_color;
	}

	if (uv.x < front) {
		// Depth: darker toward the bottom of the tube.
		vec3 liquid = mix(liquid_color.rgb, liquid_deep.rgb, uv.y * 0.8);
		// Slow slosh bands drifting through the liquid.
		float band = sin(uv.x * 34.0 - t * 1.3 + sin(uv.y * 5.0)) * 0.5 + 0.5;
		liquid += band * 0.045;
		// Bright meniscus at the liquid front.
		liquid += smoothstep(0.05, 0.0, front - uv.x) * 0.28;
		// Specular strip along the top of the tube.
		liquid += smoothstep(0.30, 0.0, uv.y) * 0.10;
		// A few procedural bubbles drifting toward the front.
		if (bubbles > 0.0) {
			for (int i = 0; i < 5; i++) {
				float fi = float(i);
				float bx = fract(fi * 0.173 + t * (0.045 + fi * 0.011)) * max(fill, 0.001);
				float by = fract(fi * 0.311 + 0.15 + sin(t * 0.6 + fi * 2.1) * 0.04);
				float d = distance(uv, vec2(bx, by));
				liquid += smoothstep(0.016, 0.005, d) * 0.16 * bubbles;
			}
		}
		col = vec4(liquid, 1.0);
	}

	COLOR = col;
}
