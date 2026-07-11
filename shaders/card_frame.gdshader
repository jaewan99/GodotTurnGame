shader_type canvas_item;

// Procedural card "cover": a rounded-rect body with a vertical gradient, a subtle
// grain texture, and a gold border ring — all drawn in-shader, no PNG needed.
// Applied to a full-rect ColorRect behind the card's content.

uniform vec2 card_size = vec2(200.0, 300.0);
uniform float corner_radius = 16.0;
uniform float border_width = 3.0;
uniform vec4 top_color : source_color = vec4(0.13, 0.15, 0.23, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.03, 0.04, 0.07, 1.0);
uniform vec4 border_color : source_color = vec4(0.82, 0.66, 0.32, 1.0);
uniform float grain = 0.05;   // strength of the procedural grain texture

// Signed distance to a rounded box (negative inside).
float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = UV * card_size;
	vec2 p = px - card_size * 0.5;
	float d = sd_round_box(p, card_size * 0.5, corner_radius);

	// Screen-space anti-alias width: how much the SDF changes per screen pixel.
	// Using fwidth (instead of a fixed value) keeps the edge ~1px smooth even
	// when the card is rotated in the hand arc or drawn at a different scale.
	float aa = fwidth(d);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	if (inside <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec4 col = mix(top_color, bottom_color, clamp(UV.y, 0.0, 1.0));
		// Fine grain so the fill reads as textured, not flat.
		float n = hash(floor(px));
		col.rgb += (n - 0.5) * grain;
		// Gold border ring hugging the rounded edge.
		float ring = smoothstep(-border_width - aa, -border_width + aa, d);
		col.rgb = mix(col.rgb, border_color.rgb, ring * inside);
		col.a = inside;
		COLOR = col;
	}
}
