// Vignette over the board only (under the HUD, as in design/shared/cs.css):
// radial in void, 0% at 55% of the radius to 85% at the corners. When the
// signal runs low a danger-red glow creeps in from the edges and pulses
// (alarm, set by game_view.gd from Hud.alarm_level).
shader_type canvas_item;
render_mode unshaded;

uniform vec4 c_void;
uniform vec4 c_danger;
uniform float alarm = 0.0;

void fragment() {
	float r = length((UV - 0.5) / 0.75);
	float dark = 0.85 * clamp((r - 0.55) / 0.45, 0.0, 1.0);
	float red = 0.55 * alarm * smoothstep(0.30, 1.05, r);
	float a = dark + red * (1.0 - dark);
	vec3 col = mix(c_void.rgb, c_danger.rgb, a > 0.0 ? red / a : 0.0);
	COLOR = vec4(col, a);
}
