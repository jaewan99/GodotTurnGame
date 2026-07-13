// Luminance-mask scene transition, adapted from
// https://godotshaders.com/shader/luminance-mask-transition/
// Drives a full-screen solid overlay: pixels of the mask brighter than
// `cutoff` are covered by `cover_color`; the rest stay transparent. Animating
// `cutoff` wipes the cover in/out following the mask's luminance pattern.
shader_type canvas_item;

uniform float cutoff : hint_range(0.0, 1.0) = 1.0;
uniform bool invert = false;
uniform vec4 cover_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D mask_texture : hint_default_black;
// Soft edge width so the wipe boundary isn't a hard pixel line.
uniform float feather : hint_range(0.0, 0.5) = 0.03;

void fragment() {
	vec4 sample_color = texture(mask_texture, UV);
	float luminance = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	if (invert) {
		luminance = 1.0 - luminance;
	}
	// 1.0 = fully covered, 0.0 = fully transparent, feathered across the edge.
	float covered = smoothstep(cutoff - feather, cutoff + feather, luminance);
	COLOR = vec4(cover_color.rgb, cover_color.a * covered);
}
