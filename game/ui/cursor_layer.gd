class_name CursorLayer
extends Control
## The reticle cursor from the gameplay mockup (corner brackets and a cross,
## accent with a glow), drawn at the pointer in place of the system cursor. A
## small spinning tick shows while a move is still decrypting.

var palette: Palette
var busy_since := -1.0
var clock_ms := 0.0
var show := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	clock_ms += delta * 1000.0
	queue_redraw()


func _draw() -> void:
	if palette == null or not show:
		return
	var o := get_local_mouse_position() - Vector2(15, 15)
	var acc := palette.c("accent")
	var segs := [[Vector2(2, 9), Vector2(2, 2), Vector2(9, 2)], [Vector2(21, 2), Vector2(28, 2), Vector2(28, 9)],
		[Vector2(28, 21), Vector2(28, 28), Vector2(21, 28)], [Vector2(9, 28), Vector2(2, 28), Vector2(2, 21)]]
	for pass_i in 2:
		var w := 5.0 if pass_i == 0 else 2.0
		var c := Color(acc, 0.3) if pass_i == 0 else acc
		for s in segs:
			var pts := PackedVector2Array()
			for v in s:
				pts.append(o + v)
			draw_polyline(pts, c, w)
	draw_line(o + Vector2(15, 11), o + Vector2(15, 19), acc, 1.5)
	draw_line(o + Vector2(11, 15), o + Vector2(19, 15), acc, 1.5)
	if busy_since >= 0.0 and clock_ms - busy_since > 80.0:
		var a := (clock_ms - busy_since) / 1000.0 * TAU
		draw_arc(o + Vector2(36, 15), 5.0, a, a + PI * 1.2, 12, acc, 1.5)
