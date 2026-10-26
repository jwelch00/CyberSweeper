class_name BoardCamera
extends RefCounted
## Maps between screen pixels (the 1920x1080 base layout) and world cells.
## Cell (x, y) covers world [x, x+1) x [y, y+1); its chip is the first
## CELL / (CELL + GAP) of that span, the rest is the gap.

const CELL := 40.0
const GAP := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
## Cell numbers are 52% of the cell, never under this many pixels.
const MIN_NUMBER_PX := 11.0

var center := Vector2(0.5, 0.5)   # world position at the middle of the view
var zoom := 1.0
var view_size := Vector2(1920, 1080)


func pitch() -> float:
	return (CELL + GAP) * zoom


func cell_px() -> float:
	return CELL * zoom


func gap_px() -> float:
	return GAP * zoom


func number_px() -> float:
	return maxf(MIN_NUMBER_PX, 0.52 * cell_px())


func world_to_screen(w: Vector2) -> Vector2:
	return (w - center) * pitch() + view_size * 0.5


func screen_to_world(s: Vector2) -> Vector2:
	return (s - view_size * 0.5) / pitch() + center


func cell_at(s: Vector2) -> Vector2i:
	var w := screen_to_world(s)
	return Vector2i(floori(w.x), floori(w.y))


## Screen rectangle of a cell's chip.
func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(world_to_screen(Vector2(c)), Vector2(cell_px(), cell_px()))


func cell_center(c: Vector2i) -> Vector2:
	return world_to_screen(Vector2(c)) + Vector2(cell_px(), cell_px()) * 0.5


## Zooms by factor, keeping the world point under screen_pt fixed.
func zoom_at(screen_pt: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pt)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := screen_to_world(screen_pt)
	center += before - after


## Moves the view so the board follows a drag of delta pixels.
func drag(delta: Vector2) -> void:
	center -= delta / pitch()


## Cells at least partly on screen.
func visible_cells() -> Rect2i:
	var a := screen_to_world(Vector2.ZERO)
	var b := screen_to_world(view_size)
	var p := Vector2i(floori(a.x), floori(a.y))
	return Rect2i(p, Vector2i(floori(b.x), floori(b.y)) - p + Vector2i.ONE)
