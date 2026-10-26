// Panel background (design/shared/screens.css .grp.jagged > .panel): the board
// behind, blurred about 6 px, under void fading from 82% at the top to 66% at
// the bottom, clipped to the jagged outline from Jag.points (even-odd test
// against up to 32 points).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 c_void;
uniform float alpha_top = 0.82;
uniform float alpha_bottom = 0.66;
uniform vec2 rect_size = vec2(100.0);
uniform vec2 pts[32];
uniform int npts = 0;

bool inside(vec2 p) {
	bool c = false;
	int j = npts - 1;
	for (int i = 0; i < 32; i++) {
		if (i >= npts) break;
		vec2 a = pts[i];
		vec2 b = pts[j];
		if (((a.y > p.y) != (b.y > p.y)) && (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)) c = !c;
		j = i;
	}
	return c;
}

void fragment() {
	vec2 p = UV * rect_size;
	if (npts > 2 && !inside(p)) discard;
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
	COLOR = vec4(mix(sum / n, c_void.rgb, mix(alpha_top, alpha_bottom, UV.y)), 1.0);
}
