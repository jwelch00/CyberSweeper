class_name LatticeLayer
extends Control
## The corp's own markings on its secure lattice (design/MOTION.md 5, cs.css
## .lattice): at every 16x16 generator chunk corner a registration crosshair,
## the chunk ID (LAT 03F0:01A0) and faint seams along the chunk edges, plus
## edge rulers with a tick per cell and the coordinate (from the start, y up)
## at each chunk boundary. Drawn only for what's on screen; it scrolls with
## the board. Chunks only exist once the first click fixes the origin, so
## nothing shows before that.

const CHUNK := 16
const RULER_TOP := 22.0
const RULER_LEFT := 26.0

var view: BoardView
var palette: Palette
## The run's first click (GameState.origin); the chunk grid sits 8 cells up-left.
var origin := Vector2i.ZERO
var on := false
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load("res://assets/fonts/MartianMono-300.ttf")


func _process(_delta: float) -> void:
	queue_redraw()


## Chunk corner cell (the chunk's top-left) for chunk key k.
func corner(k: Vector2i) -> Vector2i:
	return origin - Vector2i(8, 8) + k * CHUNK


static func chunk_id(k: Vector2i) -> String:
	return "LAT %04X:%04X" % [(0x3F0 + k.x) & 0xFFFF, (0x1A0 + k.y) & 0xFFFF]


## Is world column/row v a chunk boundary (its first cell)?
func on_boundary(v: int, axis: int) -> bool:
	return posmod(v - (origin[axis] - 8), CHUNK) == 0


func _draw() -> void:
	if not on or view == null or palette == null:
		return
	var cam := view.cam
	var gap := cam.gap_px()
	var pitch := cam.pitch()
	var vis := cam.visible_cells()
	var mark := palette.c("tileEdge").lerp(palette.c("ink"), 0.3)
	var idc := palette.c("cipher").lerp(palette.c("ink"), 0.2)
	var seam := palette.c("tileEdge")
	seam.a = 0.45
	var base := origin - Vector2i(8, 8)
	var k0 := Vector2i(floori(float(vis.position.x - base.x) / CHUNK), floori(float(vis.position.y - base.y) / CHUNK))
	var k1 := Vector2i(floori(float(vis.end.x - base.x) / CHUNK), floori(float(vis.end.y - base.y) / CHUNK))
	for ky in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var k := Vector2i(kx, ky)
			var p := cam.world_to_screen(Vector2(corner(k))) - Vector2(gap, gap) * 0.5
			draw_line(p + Vector2(-6.5, 0), p + Vector2(6.5, 0), mark, 1.0)
			draw_line(p + Vector2(0, -6.5), p + Vector2(0, 6.5), mark, 1.0)
			draw_string(_font, p + Vector2(8, 3 + 9), chunk_id(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, idc)
			var len := CHUNK * pitch - 24.0
			draw_rect(Rect2(p + Vector2(12, 0), Vector2(len, 1)), seam)
			draw_rect(Rect2(p + Vector2(0, 12), Vector2(1, len)), seam)
	_draw_rulers(vis)


func _draw_rulers(vis: Rect2i) -> void:
	var cam := view.cam
	var w := size.x
	var h := size.y
	var shade := palette.c("void")
	# Strips fade from void at 85% to clear.
	var top := PackedColorArray([Color(shade, 0.85), Color(shade, 0.85), Color(shade, 0.0), Color(shade, 0.0)])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, RULER_TOP), Vector2(0, RULER_TOP)]), top)
	var left := PackedColorArray([Color(shade, 0.85), Color(shade, 0.0), Color(shade, 0.0), Color(shade, 0.85)])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(RULER_LEFT, 0), Vector2(RULER_LEFT, h), Vector2(0, h)]), left)
	var tick := palette.c("tileEdge").lerp(palette.c("ink"), 0.4)
	var num := palette.c("inkDim")
	num.a = 0.85
	var half := cam.cell_px() * 0.5
	for x in range(vis.position.x, vis.end.x + 1):
		var px := cam.world_to_screen(Vector2(x, 0)).x + half
		var ch := on_boundary(x, 0)
		draw_rect(Rect2(px, 0, 1, 9 if ch else 3), tick)
		if ch:
			draw_string(_font, Vector2(px + 4, 2 + 8), str(x - origin.x), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, num)
	for y in range(vis.position.y, vis.end.y + 1):
		var py := cam.world_to_screen(Vector2(0, y)).y + half
		var ch := on_boundary(y, 1)
		draw_rect(Rect2(0, py, 9 if ch else 3, 1), tick)
		if ch:
			draw_string(_font, Vector2(3, py + 3 + 8), str(origin.y - y), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, num)
