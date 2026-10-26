// Panel background: the board behind, blurred about 6 px (backdrop-filter:
// blur(6px) in design/shared/cs.css), under void at 78%. Corners cut 10 px
// top-left and bottom-right.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 c_void;
uniform float alpha = 0.78;
uniform vec2 rect_size = vec2(100.0);
uniform float cut = 10.0;

void fragment() {
	vec2 p = UV * rect_size;
	if (p.x + p.y < cut || (rect_size.x - p.x) + (rect_size.y - p.y) < cut) {
		discard;
	}
	vec3 sum = texture(screen_tex, SCREEN_UV).rgb;
	float n = 1.0;
	for (int ring = 1; ring <= 3; ring++) {
		float r = 2.2 * float(ring);
		float w = 1.0 / float(ring);
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398 + float(ring) * 0.39;
			vec2 o = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
			sum += texture(screen_tex, SCREEN_UV + o).rgb * w;
			n += w;
		}
	}
	COLOR = vec4(mix(sum / n, c_void.rgb, alpha), 1.0);
}
