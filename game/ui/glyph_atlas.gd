class_name GlyphAtlas
extends Node
## Draws the board's glyphs once, at startup, into textures the board shader
## samples: digits 1-8 (Martian Mono 800), hex digits 0-F (Martian Mono 400),
## the flag and the mine (shapes from design/shared/board.js; the mine's void
## centre is its own cell). Each glyph sits
## centred in a 256 px atlas cell with room around it for its glow. Two blurred
## copies give the two-layer glow (6 px at 70% + 18 px at 35%) at any zoom.

signal built

const CELL := 256
const COLS := 8
const ROWS := 4
## Font size of digits and hex inside an atlas cell.
const FONT_PX := 96.0
## Size of the flag and mine's 24-unit viewBox inside an atlas cell.
const SHAPE_PX := 160.0

var sharp: Texture2D
var glow_small: Texture2D
var glow_large: Texture2D
## Advance of one hex digit as a fraction of its font size.
var hex_advance := 0.6
## How far the visual centre of a digit / hex glyph sits from its atlas cell's
## centre, as a fraction of the cell (the shader shifts by this).
var digit_dy := 0.0
var hex_dy := 0.0
var is_built := false


func build() -> void:
	if DisplayServer.get_name() == "headless":
		# Nothing renders headless (tests): plain 1 px textures keep the board working.
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		sharp = ImageTexture.create_from_image(img)
		glow_small = sharp
		glow_large = sharp
		is_built = true
		built.emit.call_deferred()
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * COLS, CELL * ROWS)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := _Painter.new()
	painter.size = Vector2(vp.size)
	vp.add_child(painter)
	add_child(vp)
	var mono := load("res://assets/fonts/MartianMono-400.ttf") as Font
	hex_advance = mono.get_char_size("0".unicode_at(0), int(FONT_PX)).x / FONT_PX
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	digit_dy = _centre_offset(img, 7, 0)   # the 8
	hex_dy = _centre_offset(img, 0, 1)     # the 0
	glow_small = ImageTexture.create_from_image(_blurred(img, 32))
	glow_large = ImageTexture.create_from_image(_blurred(img, 64))
	img.generate_mipmaps()
	sharp = ImageTexture.create_from_image(img)
	is_built = true
	built.emit()


## A blurred copy: halve down to 1/factor, then scale back up smoothly.
func _blurred(src: Image, factor: int) -> Image:
	var b := src.duplicate() as Image
	var w := b.get_width()
	var h := b.get_height()
	while w > src.get_width() / factor:
		w /= 2
		h /= 2
		b.resize(w, h, Image.INTERPOLATE_BILINEAR)
	b.resize(src.get_width() / 8, src.get_height() / 8, Image.INTERPOLATE_CUBIC)
	b.generate_mipmaps()
	return b


## Vertical offset of a glyph's ink from its atlas cell centre (fraction of cell).
func _centre_offset(img: Image, col: int, row: int) -> float:
	var top := -1
	var bottom := -1
	for y in CELL:
		for x in range(CELL / 4, CELL * 3 / 4, 2):
			if img.get_pixel(col * CELL + x, row * CELL + y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	if top < 0:
		return 0.0
	return ((top + bottom) * 0.5 - CELL * 0.5) / CELL


class _Painter extends Control:
	const HEX := "0123456789ABCDEF"

	func _draw() -> void:
		var bold := load("res://assets/fonts/MartianMono-800.ttf") as Font
		var mono := load("res://assets/fonts/MartianMono-400.ttf") as Font
		for n in range(1, 9):
			_glyph(bold, str(n), n - 1, 0)
		for h in 16:
			_glyph(mono, HEX[h], h % 8, 1 + h / 8)
		_flag(_cell_origin(0, 3))
		_mine(_cell_origin(1, 3))

	func _cell_origin(col: int, row: int) -> Vector2:
		return Vector2(col * GlyphAtlas.CELL, row * GlyphAtlas.CELL)

	func _glyph(font: Font, ch: String, col: int, row: int) -> void:
		var size := int(GlyphAtlas.FONT_PX)
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var o := _cell_origin(col, row)
		# Baseline so the cap height sits roughly centred; the exact offset is
		# measured afterwards and corrected in the shader.
		var baseline := o.y + GlyphAtlas.CELL * 0.5 + font.get_ascent(size) * 0.36
		draw_string(font, Vector2(o.x + (GlyphAtlas.CELL - w) * 0.5, baseline), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)

	## Maps the 24-unit viewBox into an atlas cell.
	func _s(o: Vector2, x: float, y: float) -> Vector2:
		var k := GlyphAtlas.SHAPE_PX / 24.0
		var pad := (GlyphAtlas.CELL - GlyphAtlas.SHAPE_PX) * 0.5
		return o + Vector2(pad + x * k, pad + y * k)

	## A stroke with square caps (the SVG's stroke-linecap: square).
	func _stroke(o: Vector2, a: Vector2, b: Vector2, width: float) -> void:
		var k := GlyphAtlas.SHAPE_PX / 24.0
		var d := (b - a).normalized() * width * 0.5
		var n := Vector2(-d.y, d.x)
		var pa := _s(o, a.x, a.y) - d * k
		var pb := _s(o, b.x, b.y) + d * k
		draw_colored_polygon(PackedVector2Array([pa + n * k, pb + n * k, pb - n * k, pa - n * k]), Color.WHITE)

	func _flag(o: Vector2) -> void:
		_stroke(o, Vector2(6.5, 2.5), Vector2(6.5, 21.5), 2.2)
		var p := PackedVector2Array()
		for v in [Vector2(8, 3.5), Vector2(19, 3.5), Vector2(15.8, 8.1), Vector2(19, 12.7), Vector2(8, 12.7)]:
			p.append(_s(o, v.x, v.y))
		draw_colored_polygon(p, Color.WHITE)
		_stroke(o, Vector2(3.5, 21.5), Vector2(10.5, 21.5), 2.2)

	func _mine(o: Vector2) -> void:
		_stroke(o, Vector2(12, 1.8), Vector2(12, 22.2), 2.2)
		_stroke(o, Vector2(1.8, 12), Vector2(22.2, 12), 2.2)
		_stroke(o, Vector2(4.8, 4.8), Vector2(19.2, 19.2), 2.2)
		_stroke(o, Vector2(19.2, 4.8), Vector2(4.8, 19.2), 2.2)
		var oct := PackedVector2Array()
		for v in [Vector2(9.3, 5.5), Vector2(14.7, 5.5), Vector2(18.5, 9.3), Vector2(18.5, 14.7),
				Vector2(14.7, 18.5), Vector2(9.3, 18.5), Vector2(5.5, 14.7), Vector2(5.5, 9.3)]:
			oct.append(_s(o, v.x, v.y))
		draw_colored_polygon(oct, Color.WHITE)
		# The small square in the middle is filled with void in the design, so
		# it gets its own atlas cell (next one over) that the shader paints void.
		var hole := PackedVector2Array()
		var r := 3.6 * 0.7071
		var ho := o + Vector2(GlyphAtlas.CELL, 0)
		for v in [Vector2(12, 12 - r), Vector2(12 + r, 12), Vector2(12, 12 + r), Vector2(12 - r, 12)]:
			hole.append(_s(ho, v.x, v.y))
		draw_colored_polygon(hole, Color.WHITE)
