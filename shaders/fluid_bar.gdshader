// Clean glossy status bar (HP / energy).
// fill  = current value (0..1), the crisp filled portion.
// ghost = trailing value that lerps down after damage; the gap between
//         fill and ghost renders as a soft "recent damage" flash band.
// mirrored flips the drain direction for the right-side (enemy) HUD.
//
// Rounded-rect masked, vertical gloss gradient, thin top glass highlight,
// a slow diagonal shine sweep, and a bright leading edge. No procedural
// liquid — reads cleanly at small bar heights with no flicker/tearing.
shader_type canvas_item;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float ghost : hint_range(0.0, 1.0) = 1.0;
uniform bool mirrored = false;
uniform vec2 bar_size = vec2(420.0, 26.0);          // pixel size of the bar
uniform vec4 liquid_color : source_color = vec4(0.18, 0.72, 0.30, 1.0);
uniform vec4 liquid_deep  : source_color = vec4(0.04, 0.34, 0.12, 1.0);
uniform vec4 track_color  : source_color = vec4(0.03, 0.04, 0.05, 0.85);
uniform vec4 ghost_color  : source_color = vec4(0.95, 0.85, 0.55, 0.85);
uniform float shine_speed = 0.5;                    // shine sweeps per second

// Signed distance to a rounded box (half-size b, corner radius r).
float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 uv = UV;
	if (mirrored) { uv.x = 1.0 - uv.x; }

	// ── Rounded-rect mask (anti-aliased) ─────────────────────────────────────
	vec2 px = uv * bar_size;
	vec2 half_sz = bar_size * 0.5;
	float radius = min(half_sz.y, half_sz.x) - 1.0;
	float d = sd_round_box(px - half_sz, half_sz - vec2(1.0), radius);
	float aa = max(fwidth(d), 0.0001);
	float mask = 1.0 - smoothstep(-aa, aa, d);

	// ── Track background (dark, with a soft top-inner shadow) ────────────────
	vec3 col = track_color.rgb * mix(0.65, 1.15, uv.y);
	float alpha = track_color.a;

	// ── Damage ghost flash (between fill and ghost) ──────────────────────────
	if (uv.x >= fill && uv.x < ghost) {
		float pulse = 0.75 + 0.25 * sin(TIME * 9.0);
		col = mix(col, ghost_color.rgb, ghost_color.a * pulse);
	}

	// ── Filled portion ───────────────────────────────────────────────────────
	if (uv.x < fill) {
		// Vertical gloss gradient: bright near top, deep toward the bottom.
		vec3 fillc = mix(liquid_color.rgb, liquid_deep.rgb, smoothstep(0.0, 1.0, uv.y));
		// Glass highlight along the top.
		fillc += smoothstep(0.45, 0.0, uv.y) * 0.30;
		// Faint rim light along the bottom.
		fillc += smoothstep(0.85, 1.0, uv.y) * 0.10;
		// Slow diagonal shine sweep travelling across the fill.
		float sweep = fract(TIME * shine_speed);
		float band = 1.0 - abs((uv.x + (1.0 - uv.y) * 0.15) - sweep) * 6.0;
		fillc += clamp(band, 0.0, 1.0) * 0.16;
		// Bright crisp leading edge.
		fillc += smoothstep(0.018, 0.0, fill - uv.x) * 0.45;
		col = fillc;
		alpha = 1.0;
	}

	COLOR = vec4(col, alpha * mask);
}
