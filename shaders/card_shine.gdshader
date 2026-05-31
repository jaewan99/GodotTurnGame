shader_type canvas_item;
render_mode blend_add;

// Normalized UV position of the shine highlight (0–1). Set to vec2(0.5,-1) to hide.
uniform vec2 shine_pos = vec2(0.5, -1.0);

void fragment() {
	float dist = distance(UV, shine_pos);
	float shine = pow(max(0.0, 1.0 - dist * 2.6), 3.0);
	COLOR = vec4(0.88, 0.94, 1.0, shine * 0.55);
}
