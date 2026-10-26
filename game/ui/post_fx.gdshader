// Whole-screen effects over the board and HUD (design/tokens/palettes.json
// "effects"): scanlines, and the chromatic split on mine hits. The vignette
// sits under the HUD instead (vignette.gdshader).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 c_void;
uniform vec4 c_ink;
uniform float scanlines = 1.0;     // 0 when turned off in settings
uniform float scan_boost = 0.0;    // > 0 while the signal is low
uniform float aberration = 0.0;    // px of chromatic split (mine hit)

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col;
	if (aberration > 0.0) {
		vec2 o = vec2(aberration * SCREEN_PIXEL_SIZE.x, 0.0);
		col = vec3(texture(screen_tex, uv + o).r, texture(screen_tex, uv).g, texture(screen_tex, uv - o).b);
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	// Scanlines: 1 px of ink at 3.5% every 3 screen pixels.
	if (scanlines > 0.0 && mod(floor(FRAGCOORD.y), 3.0) < 1.0) {
		col = mix(col, c_ink.rgb, 0.035 * (1.0 + scan_boost));
	}
	COLOR = vec4(col, 1.0);
}
