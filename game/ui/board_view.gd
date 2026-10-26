class_name BoardView
extends ColorRect
## Draws the board with one shader (board.gdshader). This view keeps its own
## copy of everything visible (built from Session results, never by reading
## the GameState) and streams it into a 256x256 wrap-around texture: texel
## (x mod 256, y mod 256) holds world cell (x, y) while it is inside the
## window around the camera. Only changed cells and rows/columns that scroll
## into the window are rewritten.
##
## Texel bytes: state, number, event time (15 bits, ms mod 32768) + an
## "animating" bit, cleared once the animation is long over.

const TEX := 256
const HIDDEN := 0
const OPEN := 1
const HIT := 2
const FLAG := 3
const MINE_SHOWN := 4
const WRONG_FLAG := 5
const ANIM_MS := 2500.0

var cam := BoardCamera.new()
var palette: Palette
var atlas: GlyphAtlas
var reduced_motion := false
var hover := Vector2i(1 << 29, 1 << 29)
var hover_on := false
var chord_on := false
var chord_center := Vector2i.ZERO
## Animation clock (real time, ms). Cell events are stamped with it.
var clock_ms := 0.0
var drift_ms := 0.0

var _state := {}   # Vector2i -> PackedByteArray [state, number, t_lo, t_hi]
var _bytes := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _win := Vector2i.ZERO
var _win_valid := false
var _dirty := true
var _animating := {}   # Vector2i -> clock_ms when its animation is over


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bytes.resize(TEX * TEX * 4)
	_bytes.fill(0)
	_image = Image.create_from_data(TEX, TEX, false, Image.FORMAT_RGBA8, _bytes)
	_texture = ImageTexture.create_from_image(_image)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/board.gdshader")
	material = mat
	mat.set_shader_parameter("cells", _texture)


func set_palette(p: Palette) -> void:
	palette = p
	var m := material as ShaderMaterial
	for role in [["c_void", "void"], ["c_floor", "floor"], ["c_grid", "grid"], ["c_tile", "tile"],
			["c_edge", "tileEdge"], ["c_cipher", "cipher"], ["c_ink_dim", "inkDim"], ["c_accent", "accent"],
			["c_accent2", "accent2"], ["c_warn", "warn"], ["c_danger", "danger"]]:
		m.set_shader_parameter(role[0], p.c(role[1]))
	m.set_shader_parameter("nums", p.numbers)


func set_atlas(a: GlyphAtlas) -> void:
	atlas = a
	var m := material as ShaderMaterial
	m.set_shader_parameter("glyphs", a.sharp)
	m.set_shader_parameter("glow_s", a.glow_small)
	m.set_shader_parameter("glow_l", a.glow_large)
	m.set_shader_parameter("hex_advance", a.hex_advance)
	m.set_shader_parameter("digit_dy", a.digit_dy)
	m.set_shader_parameter("hex_dy", a.hex_dy)


## What this view believes about a cell: [state, number].
func cell(c: Vector2i) -> Array:
	var b: PackedByteArray = _state.get(c, PackedByteArray())
	if b.is_empty():
		return [HIDDEN, 0]
	return [b[0], b[1]]


func is_open(c: Vector2i) -> bool:
	return cell(c)[0] == OPEN


func is_hidden(c: Vector2i) -> bool:
	var s: int = cell(c)[0]
	return s == HIDDEN or s == FLAG


## Sets a cell. at_ms is when its animation starts (clock_ms by default; later
## for cascade rings); animate=false shows it settled.
func set_cell(c: Vector2i, state: int, number := 0, at_ms := -1.0, animate := true) -> void:
	if state == HIDDEN:
		_state.erase(c)
		_animating.erase(c)
	else:
		var t := int(clock_ms if at_ms < 0.0 else at_ms) & 32767
		var b := PackedByteArray([state, number, t & 255, ((t >> 8) & 127) | (128 if animate else 0)])
		_state[c] = b
		if animate:
			_animating[c] = (clock_ms if at_ms < 0.0 else at_ms) + ANIM_MS
		else:
			_animating.erase(c)
	_write(c)


func clear() -> void:
	_state.clear()
	_animating.clear()
	_bytes.fill(0)
	_dirty = true


## Screenshots freeze the animation clock so animated states can be framed.
var freeze := false


func _process(delta: float) -> void:
	if freeze:
		delta = 0.0
	clock_ms += delta * 1000.0
	if not reduced_motion:
		drift_ms = fmod(drift_ms + delta * 1000.0, 4200.0 * 4096.0)
	cam.view_size = size
	_scroll_window()
	_settle_animations()
	if _dirty:
		_image.set_data(TEX, TEX, false, Image.FORMAT_RGBA8, _bytes)
		_texture.update(_image)
		_dirty = false
	var m := material as ShaderMaterial
	m.set_shader_parameter("view_size", size)
	m.set_shader_parameter("cam", cam.center)
	m.set_shader_parameter("zoom", cam.zoom)
	m.set_shader_parameter("number_px", cam.number_px())
	m.set_shader_parameter("now15", fmod(clock_ms, 32768.0))
	m.set_shader_parameter("drift_ms", drift_ms)
	m.set_shader_parameter("motion", 0.0 if reduced_motion else 1.0)
	m.set_shader_parameter("hover", Vector2(hover) if hover_on else Vector2(1e9, 1e9))
	m.set_shader_parameter("chord", Vector2(chord_center) if chord_on else Vector2(1e9, 1e9))


## The window of world cells the texture currently holds, kept centred on the
## camera. Cells that scroll in get written; whatever they replace is gone.
func window_for(center: Vector2) -> Vector2i:
	return Vector2i(floori(center.x) - TEX / 2, floori(center.y) - TEX / 2)


func _scroll_window() -> void:
	var nw := window_for(cam.center)
	if _win_valid and nw == _win:
		return
	var d := nw - _win
	if not _win_valid or absi(d.x) >= TEX or absi(d.y) >= TEX:
		_win = nw
		_win_valid = true
		_bytes.fill(0)
		for c: Vector2i in _state:
			if _in_window(c):
				_write(c)
		_dirty = true
		return
	var old := _win
	_win = nw
	# Columns that entered.
	var xs := range(old.x + TEX, nw.x + TEX) if d.x > 0 else range(nw.x, old.x)
	for x in xs:
		for y in range(nw.y, nw.y + TEX):
			_write(Vector2i(x, y))
	var ys := range(old.y + TEX, nw.y + TEX) if d.y > 0 else range(nw.y, old.y)
	for y in ys:
		for x in range(nw.x, nw.x + TEX):
			_write(Vector2i(x, y))


func _in_window(c: Vector2i) -> bool:
	return c.x >= _win.x and c.y >= _win.y and c.x < _win.x + TEX and c.y < _win.y + TEX


## Texel index for a world cell (wraps, works for negative coordinates).
static func texel_index(c: Vector2i) -> int:
	return (posmod(c.y, TEX) * TEX + posmod(c.x, TEX)) * 4


func _write(c: Vector2i) -> void:
	if _win_valid and not _in_window(c):
		return
	var i := texel_index(c)
	var b: PackedByteArray = _state.get(c, PackedByteArray())
	if b.is_empty():
		_bytes[i] = 0
		_bytes[i + 1] = 0
		_bytes[i + 2] = 0
		_bytes[i + 3] = 0
	else:
		_bytes[i] = b[0]
		_bytes[i + 1] = b[1]
		_bytes[i + 2] = b[2]
		_bytes[i + 3] = b[3]
	_dirty = true


func _settle_animations() -> void:
	if _animating.is_empty():
		return
	var done: Array[Vector2i] = []
	for c: Vector2i in _animating:
		if clock_ms >= _animating[c]:
			done.append(c)
	for c in done:
		_animating.erase(c)
		var b: PackedByteArray = _state.get(c)
		if b != null:
			b[3] = b[3] & 127
			_state[c] = b
			_write(c)


## Raw texel bytes, for tests.
func texel(c: Vector2i) -> PackedByteArray:
	var i := texel_index(c)
	return _bytes.slice(i, i + 4)
