class_name HudText
extends RefCounted
## Text drawing helpers for the HUD: neon glow and the chromatic split.

## Text with a soft glow: layered outlines of the text's own color, fading
## out to `radius` px (approximates CSS text-shadow: 0 0 radius color).
static func draw_glow_string(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int,
		color: Color, radius: float, strength := 0.35) -> void:
	var layers := 4
	for i in range(layers, 0, -1):
		var w := int(radius * float(i) / layers)
		var g := color
		g.a = color.a * strength * (1.0 - float(i - 1) / layers) * 0.5
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, w, g)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## The wordmark treatment: accent2 copy 2 px left, accent copy 2 px right
## (both 85%), then the ink on top.
static func draw_split_string(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int,
		ink: Color, a1: Color, a2: Color, offset := 2.0) -> void:
	var l := a2
	l.a *= 0.85
	var r := a1
	r.a *= 0.85
	ci.draw_string(font, pos + Vector2(-offset, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, l)
	ci.draw_string(font, pos + Vector2(offset, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, r)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


static func width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 2,293 style thousands separators.
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
