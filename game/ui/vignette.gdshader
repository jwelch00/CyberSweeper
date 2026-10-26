// Vignette over the board only (under the HUD, as in design/shared/cs.css):
// radial in void, 0% at 55% of the radius to 85% at the corners.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 c_void;

void fragment() {
	float r = length((UV - 0.5) / 0.75);
	COLOR = vec4(c_void.rgb, 0.85 * clamp((r - 0.55) / 0.45, 0.0, 1.0));
}
