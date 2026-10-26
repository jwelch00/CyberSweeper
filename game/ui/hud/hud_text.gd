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


## Text that may contain strain corruption glyphs. ▓▒░█▚▞ΞΣ aren't in the
## bundled fonts (and the OS fallback differs per platform), so those are
## drawn as shapes in a digit-wide box; everything else is the font's own.
## Returns the advance.
static func draw_glitch_string(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int,
		color: Color) -> float:
	var adv := font.get_char_size("0".unicode_at(0), size).x
	var cap := size * 0.72
	var x := pos.x
	for ch in text:
		if SHAPES.contains(ch):
			_shape(ci, ch, Rect2(x + adv * 0.08, pos.y - cap, adv * 0.84, cap), color)
			x += adv
		else:
			ci.draw_char(font, Vector2(x, pos.y), ch, size, color)
			x += font.get_char_size(ch.unicode_at(0), size).x
	return x - pos.x


const SHAPES := "▓▒░█▚▞ΞΣ"


static func _shape(ci: CanvasItem, ch: String, r: Rect2, color: Color) -> void:
	var hw := r.size * 0.5
	match ch:
		"█":
			ci.draw_rect(r, color)
		"▓":
			ci.draw_rect(r, Color(color, color.a * 0.75))
		"▒":
			ci.draw_rect(r, Color(color, color.a * 0.5))
		"░":
			ci.draw_rect(r, Color(color, color.a * 0.25))
		"▚":
			ci.draw_rect(Rect2(r.position, hw), color)
			ci.draw_rect(Rect2(r.position + hw, hw), color)
		"▞":
			ci.draw_rect(Rect2(r.position + Vector2(hw.x, 0), hw), color)
			ci.draw_rect(Rect2(r.position + Vector2(0, hw.y), hw), color)
		"Ξ":
			var t := maxf(1.0, r.size.y * 0.14)
			for f in [0.0, 0.5, 1.0]:
				ci.draw_rect(Rect2(r.position.x, r.position.y + (r.size.y - t) * f, r.size.x, t), color)
		"Σ":
			var t := maxf(1.0, r.size.y * 0.14)
			ci.draw_polyline(PackedVector2Array([r.position + Vector2(r.size.x, t * 0.5), r.position + Vector2(0, t * 0.5),
				r.position + Vector2(r.size.x * 0.55, r.size.y * 0.5), r.position + Vector2(0, r.size.y - t * 0.5),
				r.position + Vector2(r.size.x, r.size.y - t * 0.5)]), color, t)


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
