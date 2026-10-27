class_name Minimap
extends Control
## Explored area at up to 2 px per cell (accent for numbers, dimmer for zeros,
## warn for flags, danger for hits), the view rectangle in ink and the start
## in accent2. New cells are drawn as they come in; the whole map is only
## rebuilt when the explored area outgrows the current scale.

var palette: Palette
var view: BoardView
var origin := Vector2i.ZERO

var _cells := {}      # Vector2i -> 0 zero, 1 number, 2 flag, 3 hit
var _hits: Array[Vector2i] = []
var _min := Vector2i.ZERO
var _max := Vector2i.ZERO
var _image: Image
var _texture: ImageTexture
var _dirty := false
var _last_build := -1e9
var _scale := 2.0
var _offset := Vector2.ZERO
var _pending: Array[Vector2i] = []
var _full := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)


func mark(c: Vector2i, kind: int) -> void:
	if _cells.is_empty():
		_min = c
		_max = c
	_cells[c] = kind
	if kind == 3 and not _hits.has(c):
		_hits.append(c)
	_min = Vector2i(mini(_min.x, c.x), mini(_min.y, c.y))
	_max = Vector2i(maxi(_max.x, c.x), maxi(_max.y, c.y))
	_pending.append(c)
	_dirty = true


func unmark(c: Vector2i) -> void:
	if _cells.has(c):
		_cells.erase(c)
		_full = true
		_dirty = true


## Redraw every cell (palette changed).
func repaint() -> void:
	_full = true
	_dirty = true


func clear() -> void:
	_cells.clear()
	_hits.clear()
	_pending.clear()
	_full = true
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and view != null and view.clock_ms - _last_build > 250.0:
		_build()
	queue_redraw()


func _build() -> void:
	_dirty = false
	_last_build = view.clock_ms
	if palette == null or _cells.is_empty():
		_image.fill(Color(0, 0, 0, 0))
		_texture.update(_image)
		_pending.clear()
		return
	var span := Vector2(_max - _min + Vector2i.ONE)
	var scale := minf(2.0, minf(size.x / span.x, size.y / span.y))
	# Rebuild everything only if the map has to shrink or recentre to fit.
	var lo := Vector2(_min) * _scale + _offset
	var hi := Vector2(_max + Vector2i.ONE) * _scale + _offset
	if _full or scale < _scale - 1e-6 or lo.x < 0 or lo.y < 0 or hi.x > size.x or hi.y > size.y:
		_scale = scale
		_offset = ((size - span * _scale) * 0.5 - Vector2(_min) * _scale).round()
		_image.fill(Color(0, 0, 0, 0))
		for c: Vector2i in _cells:
			_plot(c)
		_full = false
	else:
		for c in _pending:
			if _cells.has(c):
				_plot(c)
	_pending.clear()
	_texture.update(_image)


func _plot(c: Vector2i) -> void:
	var acc := palette.c("accent")
	var col: Color
	match int(_cells[c]):
		0: col = Color(acc, 0.33)
		1: col = Color(acc, 0.67)
		2: col = palette.c("warn")
		_: col = palette.c("danger")
	var px := maxi(1, int(_scale))
	var at := Vector2i(Vector2(c) * _scale + _offset)
	if int(_cells[c]) == 2 and px >= 2:
		# Flags are a diagonal checker, not a solid block, so they differ by
		# shape as well as color.
		_image.fill_rect(Rect2i(at, Vector2i(px, px)), palette.c("void"))
		var h := px / 2
		_image.fill_rect(Rect2i(at, Vector2i(h, h)), col)
		_image.fill_rect(Rect2i(at + Vector2i(h, h), Vector2i(px - h, px - h)), col)
		return
	_image.fill_rect(Rect2i(at, Vector2i(px, px)), col)


func _draw() -> void:
	if palette == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), palette.c("void"))
	draw_texture(_texture, Vector2.ZERO)
	if view == null or _cells.is_empty():
		return
	var vis := view.cam.visible_cells()
	var r := Rect2(Vector2(vis.position) * _scale + _offset, Vector2(vis.size) * _scale)
	r = r.intersection(Rect2(Vector2.ZERO, size))
	if r.size.x > 0 and r.size.y > 0:
		draw_rect(r, palette.c("ink"), false, 1.5)
	var s := Vector2(origin) * _scale + _offset
	draw_rect(Rect2(s - Vector2(2, 2), Vector2(5, 5)), palette.c("accent2"))
	# Hits: an X in a box, readable without color.
	var dan := palette.c("danger")
	for c in _hits:
		var m := Vector2(c) * _scale + _offset + Vector2.ONE * _scale * 0.5
		draw_rect(Rect2(m - Vector2(4, 4), Vector2(8, 8)), dan, false, 1.0)
		draw_line(m - Vector2(3, 3), m + Vector2(3, 3), dan, 1.0)
		draw_line(m + Vector2(-3, 3), m + Vector2(3, -3), dan, 1.0)
