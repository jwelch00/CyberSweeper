class_name GameOverScreen
extends Control
## The run end in the v2 frame (design/png/game-over-signal.png): the LINK
## SEVERED tag (RUN BANKED for a Ghost run), one line of context, the score,
## run stats, and two buttons, Run it back (R) and Main menu (Esc), which work
## by click or key. Milestone 4 adds the score tally, the rival ladder and the
## unlock card.

signal chosen(id: String)

const PANEL_POS := Vector2(120, 110)
const PANEL_SIZE := Vector2(1000, 520)

var palette: Palette
var summary := {}
var hovered := ""
var _shape := {}
var _tag: FontVariation
var _ui: Font
var _ui6: Font
var _data: Font
var _data6: Font
var _big: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tag = Hud.spaced(load("res://assets/fonts/ChakraPetch-700.ttf"), 3)
	_ui = load("res://assets/fonts/ChakraPetch-500.ttf")
	_ui6 = load("res://assets/fonts/ChakraPetch-600.ttf")
	_data = load("res://assets/fonts/MartianMono-400.ttf")
	_data6 = load("res://assets/fonts/MartianMono-600.ttf")
	_big = load("res://assets/fonts/MartianMono-800.ttf")
	_shape = Jag.points(PANEL_SIZE.x, PANEL_SIZE.y, Jag.SEED_OVER)


func show_run(s: Dictionary) -> void:
	summary = s
	hovered = ""
	queue_redraw()


func button_rect(id: String) -> Rect2:
	var y := PANEL_POS.y + PANEL_SIZE.y - 60.0 - 56.0
	if id == "again":
		return Rect2(PANEL_POS.x + 64, y, 206, 56)
	return Rect2(PANEL_POS.x + 64 + 206 + 16, y, 218, 56)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := ""
		for id in ["again", "menu"]:
			if button_rect(id).has_point(event.position):
				h = id
		if h != hovered:
			hovered = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in ["again", "menu"]:
			if button_rect(id).has_point(event.position):
				chosen.emit(id)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	match k.keycode:
		KEY_R, KEY_ENTER, KEY_KP_ENTER:
			chosen.emit("again")
		KEY_ESCAPE:
			chosen.emit("menu")
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if palette == null:
		return
	var v := palette.c("void")
	draw_rect(Rect2(Vector2.ZERO, size), v)
	# radial-gradient(at 30% 40%, danger 12% over void, void at 70%)
	var c := Vector2(size.x * 0.3, size.y * 0.4)
	var tint := v.lerp(palette.c("danger"), 0.12)
	var rings := 24
	for i in range(rings, 0, -1):
		var f := float(i) / rings
		draw_circle(c, size.length() * 0.7 * f * 0.75, v.lerp(tint, 1.0 - f))
	# Panel: jagged frame over a void fill.
	draw_set_transform(PANEL_POS)
	draw_colored_polygon(_shape.pts, Color(v, 0.85))
	JagPanel.draw_frame(self, _shape, PANEL_SIZE, palette, 0.0)
	draw_set_transform(Vector2.ZERO)
	var x := PANEL_POS.x + 64.0
	var y := PANEL_POS.y + 56.0
	var ended := bool(summary.get("ended", false))
	var title := "run banked" if ended else "link severed"
	var col := palette.c("accent") if ended else palette.c("danger")
	var tw := _tag.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28.0
	var cut := 7.0
	draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + tw, y), Vector2(x + tw, y + 24 - cut),
		Vector2(x + tw - cut, y + 24), Vector2(x, y + 24)]), col)
	draw_string(_tag, Vector2(x + 13, y + 18), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, v)
	var secs := int(summary.get("elapsed_ms", 0)) / 1000
	var t := "%d:%02d" % [secs / 60, secs % 60]
	var depth := int(summary.get("depth", 0))
	var line := ("Ghost run ended at depth %d after %s." % [depth, t]) if ended \
		else ("All three links lost at depth %d, %s in." % [depth, t])
	draw_string(_ui, Vector2(x, y + 24 + 14 + 20), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, palette.c("inkDim"))
	var score := int(summary.get("score", 0))
	var s := HudText.thousands(score)
	var sy := y + 24 + 14 + 26 + 26 + 132 * 0.78
	HudText.draw_glow_string(self, _big, Vector2(x - 4, sy), s, 132, palette.c("ink"), 22.0, 0.25)
	var best := int(summary.get("best_before", 0))
	if best > 0 and score > best:
		var sw := _big.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 132).x
		draw_string(_ui6, Vector2(x + sw + 28, sy - 24), "New best", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, palette.c("accent2"))
		draw_string(_ui, Vector2(x + sw + 28, sy - 2), "up from " + HudText.thousands(best), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			palette.c("inkDim"))
	# Run stats.
	var stats := [["time survived", "%02d:%02d" % [secs / 60, secs % 60]], ["tiles decrypted", HudText.thousands(int(summary.get("tiles", 0)))],
		["deepest point", str(depth)], ["seed", CsHash.seed_text(int(summary.get("seed", 0)))]]
	var stx := x
	var sty := sy + 70.0
	for st in stats:
		draw_string(_ui, Vector2(stx, sty), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, palette.c("inkDim"))
		draw_string(_data6, Vector2(stx, sty + 30), st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, palette.c("ink"))
		stx += maxf(_ui.get_string_size(st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x,
			_data6.get_string_size(st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x) + 56.0
	_button("again", "Run it back", "R", true)
	_button("menu", "Main menu", "Esc", false)


func _button(id: String, label: String, key: String, primary: bool) -> void:
	var r := button_rect(id)
	var cut := 10.0
	var poly := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end - Vector2(0, cut), r.end - Vector2(cut, 0),
		r.position + Vector2(0, r.size.y)])
	var fill := palette.c("accent") if primary else palette.c("tile")
	if hovered == id:
		fill = fill.lerp(palette.c("ink"), 0.15)
	draw_colored_polygon(poly, fill)
	var ink := palette.c("void") if primary else palette.c("ink")
	if not primary:
		var o := poly.duplicate()
		o.append(poly[0])
		draw_polyline(o, palette.c("tileEdge"), 1.0)
	draw_string(_ui6, r.position + Vector2(28, 35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	var lw := _ui6.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var kw := _data6.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
	var kr := Rect2(r.position + Vector2(28 + lw + 14, 17), Vector2(kw, 22))
	draw_rect(kr, Color(ink, 0.75), false, 1.0)
	draw_string(_data6, kr.position + Vector2(7, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ink, 0.75))
