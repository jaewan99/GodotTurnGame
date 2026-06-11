shader_type canvas_item;

uniform bool active = false;
uniform bool hovered = false;
uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform float glow_radius = 20.0;   // boundary halo thickness
uniform float outer_strength = 3.2; // brightness outside the icon edge
uniform float inner_strength = 1.5; // brightness inside the icon edge
uniform float edge_strength = 1.0;  // brightness on internal features (checkmark, etc.)
uniform float edge_scale = 10.1;     // pixel step for the internal edge detector — raise to widen lines

float luma(vec4 c) {
	return dot(c.rgb * c.a, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (active) {
		float pulse = hovered ? 1.0 : 0.55 + 0.45 * sin(TIME * 3.0);

		// ── boundary glow ────────────────────────────────────────────────
		float avg_alpha = 0.0;
		for (int i = 0; i < 12; i++) {
			float angle = float(i) * 6.28318 / 12.0;
			vec2 off = vec2(cos(angle), sin(angle)) * glow_radius * TEXTURE_PIXEL_SIZE;
			avg_alpha += texture(TEXTURE, UV + off).a;
		}
		avg_alpha = clamp(avg_alpha / 12.0, 0.0, 1.0);
		float outer = avg_alpha * (1.0 - tex.a) * outer_strength;
		float inner = (1.0 - avg_alpha) * tex.a * inner_strength;

		// ── internal edge detection (Sobel on luminance) ─────────────────
		vec2 p = TEXTURE_PIXEL_SIZE * edge_scale;
		float tl = luma(texture(TEXTURE, UV + vec2(-p.x, -p.y)));
		float tm = luma(texture(TEXTURE, UV + vec2( 0.0, -p.y)));
		float tr = luma(texture(TEXTURE, UV + vec2( p.x, -p.y)));
		float ml = luma(texture(TEXTURE, UV + vec2(-p.x,  0.0)));
		float mr = luma(texture(TEXTURE, UV + vec2( p.x,  0.0)));
		float bl = luma(texture(TEXTURE, UV + vec2(-p.x,  p.y)));
		float bm = luma(texture(TEXTURE, UV + vec2( 0.0,  p.y)));
		float br = luma(texture(TEXTURE, UV + vec2( p.x,  p.y)));
		float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
		float gy = -tl - 2.0*tm - tr + bl + 2.0*bm + br;
		float edge = clamp(sqrt(gx*gx + gy*gy) * edge_strength, 0.0, 1.0) * tex.a;

		// ── combine ───────────────────────────────────────────────────────
		float boundary = (outer + inner) * pulse;
		float internal = edge * pulse;
		float total    = boundary + internal;

		COLOR = tex + vec4(glow_color.rgb * total,
		                   (outer * 0.6 + inner * 0.3 + edge * 0.5) * pulse);
	} else {
		COLOR = vec4(tex.rgb * 0.35, tex.a);
	}
}
