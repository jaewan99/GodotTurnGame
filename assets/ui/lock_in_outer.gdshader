shader_type canvas_item;

uniform bool active = false;
uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform float glow_radius = 20.0;
uniform float outer_strength = 3.2;
uniform float inner_strength = 1.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (active) {
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
	} else {
		COLOR = tex;
	}
}
