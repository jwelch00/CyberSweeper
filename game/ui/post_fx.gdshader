// Whole-screen effects over every screen (design/MOTION.md): scanlines (twice
// as strong at strain 2), full-screen flash frames (mine hit, boot) and the
// tear lines of mine hits and strain: a band of the screen hue-rotated 160
// degrees and saturated 2x (cs.css .tear). The vignette sits under the HUD
// instead (vignette.gdshader). The strain edge is drawn here, over the HUD,
// because the deck is what's falling apart.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 c_ink;
uniform float scanlines = 1.0;     // 0 when turned off in settings
uniform float scan_boost = 0.0;    // > 0 while the signal is low; 1 doubles them (strain 2)
uniform vec4 flash_col;            // rgb + strength (0 = none)
uniform vec4 c_danger;
uniform float strain_a = 0.0;      // strain edge opacity (the heartbeat), 0 = off
uniform float strain_level = 1.0;  // 1 or 2: the shape of the red edge
uniform vec4 tears[4];             // y0, y1 (fractions of the height), on (0/1), unused

vec3 hue_rotate(vec3 c, float deg) {
	float a = cos(radians(deg));
	float b = sin(radians(deg));
	mat3 m = mat3(
		vec3(0.213 + a * 0.787 - b * 0.213, 0.213 - a * 0.213 + b * 0.143, 0.213 - a * 0.213 - b * 0.787),
		vec3(0.715 - a * 0.715 - b * 0.715, 0.715 + a * 0.285 + b * 0.140, 0.715 - a * 0.715 + b * 0.715),
		vec3(0.072 - a * 0.072 + b * 0.928, 0.072 - a * 0.072 - b * 0.283, 0.072 + a * 0.928 + b * 0.072));
	return m * c;
}

vec3 saturate_css(vec3 c, float s) {
	mat3 m = mat3(
		vec3(0.213 + 0.787 * s, 0.213 - 0.213 * s, 0.213 - 0.213 * s),
		vec3(0.715 - 0.715 * s, 0.715 + 0.285 * s, 0.715 - 0.715 * s),
		vec3(0.072 - 0.072 * s, 0.072 - 0.072 * s, 0.072 + 0.928 * s));
	return clamp(m * c, 0.0, 1.0);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	for (int i = 0; i < 4; i++) {
		if (tears[i].z > 0.5 && SCREEN_UV.y >= tears[i].x && SCREEN_UV.y < tears[i].y) {
			col = saturate_css(hue_rotate(col, 160.0), 2.0);
		}
	}
	if (strain_a > 0.0) {
		// cs.css .strainfx: radial-gradient(ellipse 72% 68%, transparent 60%,
		// danger 42% at the edge); level 2: 70% 64%, from 54%, danger 50%.
		bool two = strain_level > 1.5;
		vec2 rad = two ? vec2(0.70, 0.64) : vec2(0.72, 0.68);
		float r = length((SCREEN_UV - 0.5) / rad);
		float from = two ? 0.54 : 0.60;
		float peak = two ? 0.50 : 0.42;
		col = mix(col, c_danger.rgb, strain_a * peak * clamp((r - from) / (1.0 - from), 0.0, 1.0));
	}
	if (flash_col.a > 0.0) {
		col = mix(col, flash_col.rgb, flash_col.a);
	}
	// Scanlines: 1 px of ink at 3.5% every 3 screen pixels.
	if (scanlines > 0.0 && mod(floor(FRAGCOORD.y), 3.0) < 1.0) {
		col = mix(col, c_ink.rgb, 0.035 * (1.0 + scan_boost));
	}
	COLOR = vec4(col, 1.0);
}
