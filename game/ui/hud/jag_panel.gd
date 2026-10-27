class_name JagPanel
extends Control
## A street-deck HUD panel (design/MOTION.md, "HUD frames"): the jagged
## silhouette from Jag.points filled with the blurred board under void, a 1 px
## hairline at 40% accent, thick hot accent strokes on two corners ending in
## square terminals, ruler ticks near the bottom right, and a misregistered
## dashed ghost outline that only shows under strain. Content is drawn by
## whoever connects to `paint`, which fires after the frame.

signal paint

var seed := 0
var palette: Palette
## Ghost outline opacity: 0 normally, 0.6 at strain 1, 1 at strain 2.
var ghost := 0.0
var bg_top := 0.82
var bg_bottom := 0.66
var shape := {}
var _backdrop: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = ColorRect.new()
	_backdrop.show_behind_parent = true
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/hud/panel_backdrop.gdshader")
	_backdrop.material = mat
	add_child(_backdrop)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	shape = Jag.points(roundf(size.x), roundf(size.y), seed)
	if _backdrop == null:
		return
	_backdrop.position = Vector2.ZERO
	_backdrop.size = size
	var m := _backdrop.material as ShaderMaterial
	m.set_shader_parameter("rect_size", size)
	m.set_shader_parameter("pts", shape.pts)
	m.set_shader_parameter("npts", shape.pts.size())


func _draw() -> void:
	if palette == null or shape.is_empty():
		return
	var m := _backdrop.material as ShaderMaterial
	m.set_shader_parameter("c_void", palette.c("void"))
	m.set_shader_parameter("alpha_top", bg_top)
	m.set_shader_parameter("alpha_bottom", bg_bottom)
	draw_frame(self, shape, size, palette, ghost)
	paint.emit()


static func _closed(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + off)
	out.append(pts[0] + off)
	return out


## The line work for a jag shape, on any CanvasItem (the game-over screen
## draws its panels with this too).
static func draw_frame(ci: CanvasItem, sh: Dictionary, sz: Vector2, pal: Palette, ghost_alpha: float, role := "accent") -> void:
	var acc := pal.c(role)
	var half := Vector2(0.5, 0.5)
	if ghost_alpha > 0.0:
		var g := pal.c("accent2")
		g.a = 0.55 * ghost_alpha
		_dashed(ci, _closed(sh.pts, Vector2(4, 4) + half), [64.0, 10.0, 6.0, 10.0], g)
	ci.draw_polyline(_closed(sh.pts, half), Color(acc, 0.4), 1.0)
	for h: PackedVector2Array in sh.hot:
		var hp := PackedVector2Array()
		for p in h:
			hp.append(p + half)
		ci.draw_polyline(hp, Color(acc, 0.12), 9.0)
		ci.draw_polyline(hp, Color(acc, 0.22), 6.0)
		ci.draw_polyline(hp, acc, 3.0)
		for t in [h[0], h[h.size() - 1]]:
			ci.draw_rect(Rect2(t - Vector2(2, 2), Vector2(4, 4)), acc)
	if sz.x > 200:
		var tc := Color(acc, 0.7)
		for i in 7:
			var x := sz.x - 70 + i * 6 + 0.5
			ci.draw_line(Vector2(x, sz.y - 4), Vector2(x, sz.y - (8 if i % 3 else 12)), tc, 1.0)


## A dashed polyline (SVG stroke-dasharray).
static func _dashed(ci: CanvasItem, pts: PackedVector2Array, pattern: Array, color: Color) -> void:
	var k := 0
	var left: float = pattern[0]
	var on := true
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 1e-6)
		var pos := 0.0
		while pos < seg:
			var step := minf(left, seg - pos)
			if on:
				ci.draw_line(a + dir * pos, a + dir * (pos + step), color, 1.0)
			pos += step
			left -= step
			if left <= 1e-6:
				k = (k + 1) % pattern.size()
				left = pattern[k]
				on = k % 2 == 0
