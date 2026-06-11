shader_type canvas_item;

uniform bool active    = false; // card dragged over this slot → glow
uniform bool droppable = false; // is this the next valid slot → full brightness
uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform float glow_radius    = 15.0;
uniform float outer_strength = 2.0;
uniform float inner_strength = 0.8;
uniform float dim_amount     = 0.25; // brightness multiplier when not droppable

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (active) {
		// ── outer boundary glow only ──────────────────────────────────
		float pulse = 0.55 + 0.45 * sin(TIME * 3.0);
		float avg_alpha = 0.0;
		for (int i = 0; i < 12; i++) {
			float angle = float(i) * 6.28318 / 12.0;
			vec2 off = vec2(cos(angle), sin(angle)) * glow_radius * TEXTURE_PIXEL_SIZE;
			avg_alpha += texture(TEXTURE, UV + off).a;
		}
		avg_alpha = clamp(avg_alpha / 12.0, 0.0, 1.0);
		float outer = avg_alpha * (1.0 - tex.a) * outer_strength;
		float inner = (1.0 - avg_alpha) * tex.a * inner_strength;
		float combined = (outer + inner) * pulse;
		COLOR = tex + vec4(glow_color.rgb * combined, (outer * 0.6 + inner * 0.3) * pulse);

	} else if (droppable) {
		// ── next valid slot — full brightness ─────────────────────────
		COLOR = tex;

	} else {
		// ── locked slot — dimmed ──────────────────────────────────────
		COLOR = vec4(tex.rgb * dim_amount, tex.a);
	}
}
