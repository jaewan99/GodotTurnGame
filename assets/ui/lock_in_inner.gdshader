shader_type canvas_item;

uniform bool active = false;
uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform float edge_strength = 3.0;
uniform float edge_scale = 2.0;

float luma(vec4 c) {
	return dot(c.rgb * c.a, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (active) {
		float pulse = 0.55 + 0.45 * sin(TIME * 3.0);

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

		COLOR = tex + vec4(glow_color.rgb * edge * pulse, edge * 0.5 * pulse);
	} else {
		COLOR = tex;
	}
}
