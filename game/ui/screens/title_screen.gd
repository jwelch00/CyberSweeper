class_name TitleScreen
extends Control
## The title (design/png/title-signal.png): the wordmark and tagline over a
## real seeded board with the corp lattice, fading in from void on the left,
## and the menu. Jack in starts an Arcade run. Palettes, Rivals and Settings
## are shown but wait for milestone 4's screens. Quit isn't in the mockup;
## a desktop game needs one, so it sits last in the same dim style.

signal chosen(id: String)

const ITEMS := [["Jack in", "jack_in", true], ["Palettes", "palettes", false], ["Rivals", "rivals", false],
	["Settings", "settings", false], ["Quit", "quit", true]]
const LEFT := 140.0
const NAV_Y := 444.0
const ITEM_H := 60.0
const ITEM_GAP := 6.0
const NAV_W := 440.0
const BG_SEED := 4242

var fx: ScreenFx
var palette: Palette
var rules: Rules
var selected := 0
var board: BoardView
var lattice: LatticeLayer
var _front: Control
var _vignette: ColorRect
var _session: Session
var _word: FontVariation
var _tag: Font
var _item: Font
var _kbd: Font
var _micro: FontVariation


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_word = Hud.spaced(load("res://assets/fonts/ChakraPetch-700.ttf"), 6)
	_tag = load("res://assets/fonts/ChakraPetch-500.ttf")
	_item = load("res://assets/fonts/ChakraPetch-600.ttf")
	_kbd = load("res://assets/fonts/MartianMono-600.ttf")
	_micro = Hud.spaced(load("res://assets/fonts/MartianMono-300.ttf"), 1)
	board = BoardView.new()
	add_child(board)
	board.cam.zoom = 46.0 / BoardCamera.CELL
	lattice = LatticeLayer.new()
	lattice.view = board
	add_child(lattice)
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vm := ShaderMaterial.new()
	vm.shader = load("res://ui/vignette.gdshader")
	_vignette.material = vm
	add_child(_vignette)
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_front)
	_front.draw.connect(_draw_front)


## The background: a bot plays a fixed seed on the worker thread (during the
## boot), and the board shows where it got to.
func start_background(atlas: GlyphAtlas) -> void:
	board.set_atlas(atlas)
	if _session != null:
		return
	_session = Session.new(BG_SEED, rules if rules else Rules.load_default(), true)
	_session.bot("netrunner", 30, Vector2i.ZERO)


func set_palette(p: Palette) -> void:
	palette = p
	board.set_palette(p)
	lattice.palette = p
	(_vignette.material as ShaderMaterial).set_shader_parameter("c_void", p.c("void"))
	(_vignette.material as ShaderMaterial).set_shader_parameter("c_danger", p.c("danger"))
	_front.queue_redraw()


func _exit_tree() -> void:
	if _session != null:
		_session.close()


func _process(_delta: float) -> void:
	if _session != null:
		for r in _session.poll():
			if r.state.has("cells"):
				_show(r.state)
	_front.queue_redraw()


func _show(s: Dictionary) -> void:
	var cells: Array = s.cells
	var numbers: PackedInt32Array = s.numbers
	for i in cells.size():
		var n := numbers[i]
		board.set_cell(cells[i], BoardView.HIT if n < 0 else BoardView.OPEN, maxi(n, 0), -1.0, false)
	for c in s.flags:
		board.set_cell(c, BoardView.FLAG, 0, -1.0, false)
	var o: Vector2i = s.get("origin", Vector2i.ZERO)
	lattice.origin = o
	lattice.on = true
	# The mockup's composition: the explored area starts about 1330 px in and
	# runs off the right edge, behind the fade.
	var lo := Vector2(1e9, 1e9)
	var hi := -lo
	for c: Vector2i in cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	if cells.is_empty():
		lo = Vector2(o)
		hi = Vector2(o)
	var pitch := board.cam.pitch()
	board.cam.center = Vector2(lo.x - (1330.0 - size.x * 0.5) / pitch, (lo.y + hi.y) * 0.5 + 0.5 - (560.0 - size.y * 0.5) / pitch)


func item_rect(i: int) -> Rect2:
	return Rect2(LEFT, NAV_Y + i * (ITEM_H + ITEM_GAP), NAV_W, ITEM_H)


func item_at(p: Vector2) -> int:
	for i in ITEMS.size():
		if item_rect(i).has_point(p):
			return i
	return -1


func _move(d: int) -> void:
	var i := selected
	for step in ITEMS.size():
		i = posmod(i + d, ITEMS.size())
		if ITEMS[i][2]:
			selected = i
			return


func activate(i: int) -> void:
	if i < 0 or not ITEMS[i][2]:
		return
	selected = i
	chosen.emit(ITEMS[i][1])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := item_at(event.position)
		if i >= 0 and ITEMS[i][2]:
			selected = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activate(item_at(event.position))
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	match k.keycode:
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			activate(selected)
		_:
			return
	get_viewport().set_input_as_handled()


func _draw_front() -> void:
	if palette == null:
		return
	var w := size.x
	var h := size.y
	var v := palette.c("void")
	# Fade from void on the left: 100% to 92% at 34%, 40% at 62%, clear at 85%.
	var stops := [[0.0, 1.0], [0.34, 0.92], [0.62, 0.40], [0.85, 0.0]]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		_front.draw_polygon(PackedVector2Array([Vector2(w * a[0], 0), Vector2(w * b[0], 0), Vector2(w * b[0], h), Vector2(w * a[0], h)]),
			PackedColorArray([Color(v, a[1]), Color(v, b[1]), Color(v, b[1]), Color(v, a[1])]))
	Hud.draw_slashes(_front, Vector2(LEFT, 140), 120, palette.c("accent"))
	HudText.draw_split_string(_front, _word, Vector2(LEFT, 170 + 148 * 0.78), "CYBERSWEEPER", 148, palette.c("ink"),
		palette.c("accent"), palette.c("accent2"))
	var tag_y := 170 + 148 * 0.9 + 30 + 28
	var lead := "Infinite Minesweeper. Three links. "
	_front.draw_string(_tag, Vector2(LEFT, tag_y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, palette.c("ink"))
	var lw := _tag.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	_front.draw_string(_tag, Vector2(LEFT + lw, tag_y), "Never a coin flip.", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, palette.c("inkDim"))
	for i in ITEMS.size():
		var r := item_rect(i)
		var label: String = ITEMS[i][0]
		var on: bool = ITEMS[i][2]
		if i == selected:
			# polygon(18px 0, 100%-30 0, 100%-25 5, 100%-10 5, 100% 15, 100% 100%-6, 100%-6 100%, 0 100%, 0 18px)
			var p := r.position
			var rw := r.size.x
			var rh := r.size.y
			_front.draw_colored_polygon(PackedVector2Array([p + Vector2(18, 0), p + Vector2(rw - 30, 0), p + Vector2(rw - 25, 5),
				p + Vector2(rw - 10, 5), p + Vector2(rw, 15), p + Vector2(rw, rh - 6), p + Vector2(rw - 6, rh), p + Vector2(0, rh),
				p + Vector2(0, 18)]), palette.c("accent"))
			_front.draw_string(_item, p + Vector2(26, 39), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, palette.c("void"))
			if i == 0:
				var kw := _kbd.get_string_size("Enter", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
				var kr := Rect2(p + Vector2(rw - 22 - kw, 19), Vector2(kw, 22))
				_front.draw_rect(kr, Color(palette.c("void"), 0.75), false, 1.0)
				_front.draw_string(_kbd, kr.position + Vector2(8, 16), "Enter", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(palette.c("void"), 0.75))
		else:
			var c := palette.c("inkDim")
			if not on:
				c.a = 0.55
			_front.draw_string(_item, r.position + Vector2(26, 39), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, c)
	var mc := Color(palette.c("inkDim"), 0.75)
	_front.draw_string(_micro, Vector2(LEFT, h - 60), "CS-DECK %s  STREET BUILD  NOT FOR CORPORATE USE" % CsVersion.GAME,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mc)
