class_name CutPanel
extends Control
## The design's panel: the board behind it blurred under void at 78%, a 1 px
## tileEdge border, top-left and bottom-right corners cut 10 px, accent ticks
## across the cuts. Content is drawn by whoever connects to `paint`, which
## fires after the background and border (Godot's own `draw` signal fires
## before _draw, so content drawn there would end up underneath).

signal paint

const CUT := 10.0

var palette: Palette
var bg_alpha := 0.78
var accent_role := "accent"
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
	if _backdrop == null:
		return
	_backdrop.position = Vector2.ZERO
	_backdrop.size = size
	(_backdrop.material as ShaderMaterial).set_shader_parameter("rect_size", size)


func _draw() -> void:
	if palette == null:
		return
	var m := _backdrop.material as ShaderMaterial
	m.set_shader_parameter("c_void", palette.c("void"))
	m.set_shader_parameter("alpha", bg_alpha)
	var w := size.x
	var h := size.y
	var poly := PackedVector2Array([Vector2(CUT, 0), Vector2(w, 0), Vector2(w, h - CUT), Vector2(w - CUT, h),
		Vector2(0, h), Vector2(0, CUT), Vector2(CUT, 0)])
	draw_polyline(poly, palette.c("tileEdge"), 1.0)
	var acc := palette.c(accent_role)
	draw_line(Vector2(0, CUT), Vector2(CUT, 0), acc, 2.0, true)
	draw_line(Vector2(w - CUT, h), Vector2(w, h - CUT), acc, 2.0, true)
	paint.emit()
