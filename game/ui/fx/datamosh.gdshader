// Datamosh screen transition (design/MOTION.md 7). 0-180 ms: the old frame
// (captured once) breaks into 7 bands that slide sideways, some stretching
// vertically, all hue-shifting, saturating and gaining contrast. 180-380 ms:
// the live new screen (read through the screen texture) snaps in band by band
// from offset positions, bleeding color for a moment, while the old bands fade
// over 70 ms.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D old_tex : filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform bool has_old = false;
uniform float t_ms = 0.0;
uniform float break_ms = 180.0;
uniform float total_ms = 380.0;
uniform float fade_ms = 70.0;
uniform float cuts[8];      // band edges, fractions of the height (cuts[0] = 0, cuts[7] = 1)
uniform vec4 old_band[7];   // dx (px at 1080p), vertical stretch, hue (deg), unused
uniform vec4 new_band[7];   // dx (px at 1080p), delay (ms), hue (deg), unused
uniform vec4 c_void;

float bez(float x1, float y1, float x2, float y2, float t) {
	float lo = 0.0, hi = 1.0, u = t;
	for (int i = 0; i < 14; i++) {
		u = (lo + hi) * 0.5;
		float v = 1.0 - u;
		float x = 3.0 * v * v * u * x1 + 3.0 * v * u * u * x2 + u * u * u;
		if (x < t) lo = u; else hi = u;
	}
	float v = 1.0 - u;
	return 3.0 * v * v * u * y1 + 3.0 * v * u * u * y2 + u * u * u;
}

vec3 hue_rotate(vec3 c, float deg) {
	float a = cos(radians(deg));
	float b = sin(radians(deg));
	mat3 m = mat3(
		vec3(0.213 + a * 0.787 - b * 0.213, 0.213 - a * 0.213 + b * 0.143, 0.213 - a * 0.213 - b * 0.787),
		vec3(0.715 - a * 0.715 - b * 0.715, 0.715 + a * 0.285 + b * 0.140, 0.715 - a * 0.715 + b * 0.715),
		vec3(0.072 - a * 0.072 + b * 0.928, 0.072 - a * 0.072 - b * 0.283, 0.072 + a * 0.928 + b * 0.072));
	return clamp(m * c, 0.0, 1.0);
}

vec3 saturate_css(vec3 c, float s) {
	mat3 m = mat3(
		vec3(0.213 + 0.787 * s, 0.213 - 0.213 * s, 0.213 - 0.213 * s),
		vec3(0.715 - 0.715 * s, 0.715 + 0.285 * s, 0.715 - 0.715 * s),
		vec3(0.072 - 0.072 * s, 0.072 - 0.072 * s, 0.072 + 0.928 * s));
	return clamp(m * c, 0.0, 1.0);
}

vec3 graded(vec3 c, float hue, float sat, float con) {
	c = saturate_css(hue_rotate(c, hue), sat);
	return clamp((c - 0.5) * con + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	int b = 0;
	for (int i = 1; i < 7; i++) {
		if (uv.y >= cuts[i]) b = i;
	}
	float top = cuts[b];
	vec3 col = c_void.rgb;
	float aspect = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;   // = height / width
	if (t_ms >= break_ms) {
		vec4 nb = new_band[b];
		float lt = clamp((t_ms - break_ms - nb.y) / (total_ms - break_ms), 0.0, 1.0);
		float e = bez(0.1, 0.9, 0.2, 1.0, lt);
		vec2 suv = uv - vec2(nb.x * (1.0 - e) / 1080.0 * aspect, 0.0);
		vec3 n = (suv.x >= 0.0 && suv.x <= 1.0) ? texture(screen_tex, suv).rgb : c_void.rgb;
		n = graded(n, nb.z * (1.0 - e), mix(2.0, 1.0, e), 1.0);
		col = mix(c_void.rgb, n, mix(0.6, 1.0, e));
	}
	float old_a = t_ms < break_ms ? 1.0 : 1.0 - clamp((t_ms - break_ms) / fade_ms, 0.0, 1.0);
	if (has_old && old_a > 0.0) {
		vec4 ob = old_band[b];
		float e = bez(0.6, 0.0, 0.9, 0.5, clamp(t_ms / break_ms, 0.0, 1.0));
		float stretch = mix(1.0, ob.y, e);
		vec2 suv = vec2(uv.x - ob.x * e / 1080.0 * aspect, top + (uv.y - top) / stretch);
		vec3 o = (suv.x >= 0.0 && suv.x <= 1.0) ? texture(old_tex, suv).rgb : c_void.rgb;
		o = graded(o, ob.z * e, 1.0 + 1.2 * e, 1.0 + 0.3 * e);
		col = mix(col, o, old_a);
	}
	COLOR = vec4(col, 1.0);
}
