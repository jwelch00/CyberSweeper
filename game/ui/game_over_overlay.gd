class_name GameOverOverlay
extends Control
## The bare milestone-3 run end: title, one line of context, the score and how
## to run it back. Milestone 4 replaces this with the full game-over screen
## (tally, rival ladder, unlock card).

var palette: Palette
var title := "Link severed"
var detail := ""
var score := 0

var _ui: Font
var _ui_mid: Font
var _data: Font
var _panel: CutPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui = load("res://assets/fonts/ChakraPetch-700.ttf")
	_ui_mid = load("res://assets/fonts/ChakraPetch-500.ttf")
	_data = load("res://assets/fonts/MartianMono-800.ttf")
	_panel = CutPanel.new()
	_panel.size = Vector2(760, 330)
	_panel.bg_alpha = 0.9
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.paint.connect(_draw_panel)
	resized.connect(func(): _panel.position = (size - _panel.size) * 0.5)
	visible = false


func show_end(p_title: String, p_detail: String, p_score: int) -> void:
	title = p_title
	detail = p_detail
	score = p_score
	_panel.palette = palette
	_panel.position = (size - _panel.size) * 0.5
	visible = true
	_panel.queue_redraw()


func _draw_panel() -> void:
	if palette == null:
		return
	HudText.draw_split_string(_panel, _ui, Vector2(48, 86), title, 44, palette.c("danger"),
		palette.c("accent"), palette.c("accent2"))
	_panel.draw_string(_ui_mid, Vector2(48, 124), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, palette.c("inkDim"))
	var s := HudText.thousands(score)
	HudText.draw_glow_string(_panel, _data, Vector2(44, 224), s, 88, palette.c("ink"), 18.0, 0.25)
	var btn := Rect2(Vector2(48, 256), Vector2(206, 48))
	var cut := 10.0
	var poly := PackedVector2Array([btn.position + Vector2(cut, 0), btn.position + Vector2(btn.size.x, 0),
		btn.end - Vector2(0, cut), btn.end - Vector2(cut, 0), btn.position + Vector2(0, btn.size.y),
		btn.position + Vector2(0, cut)])
	_panel.draw_colored_polygon(poly, palette.c("accent"))
	_panel.draw_string(load("res://assets/fonts/ChakraPetch-600.ttf"), btn.position + Vector2(24, 32), "Run it back",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, palette.c("void"))
	var k := Rect2(btn.position + Vector2(150, 13), Vector2(22, 22))
	_panel.draw_rect(k, palette.c("void"), false, 1.0)
	_panel.draw_string(load("res://assets/fonts/MartianMono-600.ttf"), k.position + Vector2(6, 16), "R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, palette.c("void"))
