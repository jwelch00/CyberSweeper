class_name MenuScreen
extends Control
## Base for the menu screens: a list of items picked by mouse or keyboard
## (arrows or WASD move, Enter or Space picks, Esc goes back). Subclasses
## say where each item is and draw themselves.

signal chosen(id: String)
signal back

var palette: Palette
var selected := 0
## Horizontal lists move with left/right; vertical ones with up/down.
var horizontal := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func items() -> Array[String]:
	return []


func item_rect(_i: int) -> Rect2:
	return Rect2()


func enabled(_i: int) -> bool:
	return true


## Left/right on a vertical list (settings use it to change a value).
func adjust(_i: int, _d: int) -> void:
	pass


func activate(i: int) -> void:
	if i >= 0 and i < items().size() and enabled(i):
		selected = i
		chosen.emit(items()[i])
		queue_redraw()


func item_at(p: Vector2) -> int:
	for i in items().size():
		if item_rect(i).has_point(p):
			return i
	return -1


func move(d: int) -> void:
	var n := items().size()
	var i := selected
	for step in n:
		i = posmod(i + d, n)
		if enabled(i):
			selected = i
			break
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := item_at(event.position)
		if i >= 0 and enabled(i) and i != selected:
			selected = i
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := item_at(event.position)
		if i >= 0:
			activate(i)
		else:
			_click_other(event.position)
		accept_event()


## Clicks that aren't on an item (back hints, tabs).
func _click_other(_p: Vector2) -> void:
	pass


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or not is_visible_in_tree():
		return
	var c := k.keycode
	var along_prev := [KEY_LEFT, KEY_A] if horizontal else [KEY_UP, KEY_W]
	var along_next := [KEY_RIGHT, KEY_D] if horizontal else [KEY_DOWN, KEY_S]
	if c in along_prev:
		move(-1)
	elif c in along_next:
		move(1)
	elif c in [KEY_LEFT, KEY_A]:
		adjust(selected, -1)
	elif c in [KEY_RIGHT, KEY_D]:
		adjust(selected, 1)
	elif c in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if not k.echo:
			activate(selected)
	elif c == KEY_ESCAPE:
		if not k.echo:
			back.emit()
	elif not _key(k):
		return
	get_viewport().set_input_as_handled()
	queue_redraw()


## Extra keys for a subclass; return true if handled.
func _key(_k: InputEventKey) -> bool:
	return false


func _process(_delta: float) -> void:
	queue_redraw()


func backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), palette.c("void"))
	var c := Vector2(size.x * 0.25, size.y * 0.2)
	var tint := palette.c("void").lerp(palette.c("accent"), 0.05)
	for i in range(16, 0, -1):
		var f := float(i) / 16
		draw_circle(c, size.length() * 0.6 * f, palette.c("void").lerp(tint, 1.0 - f))
