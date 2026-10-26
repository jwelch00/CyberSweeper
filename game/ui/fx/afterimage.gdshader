// Sandevistan afterimages (design/MOTION.md 3): each instance is one echo of a
// cascade cell, an outlined glowing box that drifts away from the click,
// grows to 1.12x and fades over 360 ms. Instance custom data: r = start time
// (ms, board clock), g = echo index 0..2, b/a = unit direction from the click.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float now_ms = 0.0;
uniform float life_ms = 360.0;
uniform float drift_px = 11.0;   // per echo, at 1x zoom
uniform float pitch_1x = 43.0;   // world unit in px at 1x zoom
uniform float quad = 1.8;        // instance size in world units
uniform float chip = 0.930233;   // chip side in world units (40 / 43)
uniform float px = 0.0233;       // one screen pixel in world units at this zoom
uniform vec4 c0 : source_color;  // accent2
uniform vec4 c1 : source_color;  // accent
uniform vec4 c2 : source_color;  // warn

varying float v_alpha;
varying vec4 v_col;

float bez(float x1, float y1, float x2, float y2, float t) {
	float lo = 0.0, hi = 1.0, u = t;
	for (int i = 0; i < 12; i++) {
		u = (lo + hi) * 0.5;
		float v = 1.0 - u;
		float x = 3.0 * v * v * u * x1 + 3.0 * v * u * u * x2 + u * u * u;
		if (x < t) lo = u; else hi = u;
	}
	float v = 1.0 - u;
	return 3.0 * v * v * u * y1 + 3.0 * v * u * u * y2 + u * u * u;
}

void vertex() {
	float t = (now_ms - INSTANCE_CUSTOM.r) / life_ms;
	float k = INSTANCE_CUSTOM.g;
	if (t < 0.0 || t > 1.0) {
		VERTEX = vec2(0.0);
		v_alpha = 0.0;
	} else {
		float e = bez(0.2, 0.7, 0.3, 1.0, t);
		vec2 dir = INSTANCE_CUSTOM.ba;
		VERTEX *= 1.0 + 0.12 * e;
		VERTEX += dir * drift_px * (k + 1.0) * e / (pitch_1x * quad);
		v_alpha = (0.95 - k * 0.2) * (1.0 - e);
	}
	v_col = k < 0.5 ? c0 : (k < 1.5 ? c1 : c2);
}

void fragment() {
	// UV across the quad; the chip is the middle chip/quad of it
	vec2 p = (UV - 0.5) * quad;                 // world units from the centre
	vec2 d = abs(p) - vec2(chip * 0.5);
	float outside = length(max(d, vec2(0.0)));
	float inside = min(max(d.x, d.y), 0.0);
	float a = 0.0;
	if (outside > 0.0) {
		float d = outside / (6.0 * px);             // 0 0 12px glow: a Gaussian, sigma 6 px
		a = 0.55 * exp(-0.5 * d * d);
	} else if (inside > -2.0 * px) {
		a = 1.0;                                    // inset 2px outline
	} else {
		a = 0.08;                                   // 8% fill
	}
	COLOR = vec4(v_col.rgb * a * v_alpha, 1.0);
}
