class_name PopupLayer
extends Control
## Score popups: "+n" in the number's color for a single reveal, one summed
## popup in accent for a cascade. Cut-corner chip, Martian Mono 800 20 px,
## rises and fades.

const LIFE_MS := 900.0

var view: BoardView
var palette: Palette
var _font: Font
var _pops: Array[Dictionary] = []   # {text, cell, color, born}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load("res://assets/fonts/MartianMono-800.ttf")


func add(text: String, cell: Vector2i, color: Color) -> void:
	_pops.append({"text": text, "cell": cell, "color": color, "born": view.clock_ms})


## Popup for one move: a single reveal shows its number, a cascade one sum.
static func for_move(revealed: Array[Vector2i], numbers: PackedInt32Array, palette: Palette) -> Array:
	var total := 0
	var safe := 0
	var last := 0
	for n in numbers:
		if n > 0:
			total += n
			last = n
		if n >= 0:
			safe += 1
	if total == 0:
		return []
	if safe == 1:
		return ["+%d" % total, palette.number(last)]
	return ["+%d" % total, palette.c("accent")]


func clear() -> void:
	_pops.clear()


func _process(_delta: float) -> void:
	if not _pops.is_empty():
		_pops = _pops.filter(func(p): return view.clock_ms - p.born < LIFE_MS)
		queue_redraw()


func _draw() -> void:
	for p in _pops:
		var t: float = (view.clock_ms - p.born) / LIFE_MS
		var alpha := 1.0 - smoothstep(0.55, 1.0, t)
		var base := view.cam.world_to_screen(Vector2(p.cell)) + Vector2(view.cam.cell_px() * 0.75, -26.0)
		var pos := base + Vector2(0, -28.0 * t)
		var size := 20
		var tw := _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var r := Rect2(pos, Vector2(tw + 14.0, 26.0))
		var cut := 6.0
		var poly := PackedVector2Array([r.position + Vector2(cut, 0), r.position + Vector2(r.size.x, 0),
			r.end, r.position + Vector2(0, r.size.y), r.position + Vector2(0, cut)])
		var bg: Color = palette.c("void")
		bg.a = 0.88 * alpha
		draw_colored_polygon(poly, bg)
		var edge: Color = p.color
		edge.a = 0.6 * alpha
		poly.append(poly[0])
		draw_polyline(poly, edge, 1.0)
		var col: Color = p.color
		col.a = alpha
		HudText.draw_glow_string(self, _font, pos + Vector2(7, 20), p.text, size, col, 10.0)
