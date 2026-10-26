class_name TitleCards
extends Control
## Smash-cut title cards (design/MOTION.md 2): a 2-frame flash in the band
## color, then a thick band rotated -6 degrees slams across the middle with
## huge skewed text, an outline copy offset (14, 8), a Japanese word and a
## subtitle, and speed lines streaking through; it exits by slicing into
## offset strips. Cards queue so none is dropped. They never take input, so
## the board stays clickable under mid-run cards.

signal finished(spec: Dictionary)

const BAND_FRAC := 0.40
const BAND_ROT := -6.0
const TEXT_SKEW := -10.0
const TEXT_PX := 210
const SPEED_LINES := 14

var fx: ScreenFx
var _queue: Array[Dictionary] = []
var _card := {}
var _start := 0.0
var _flashed := false
var _speed: Array = []   # [top frac, left frac, width px, opacity]
var _ui: Font
var _sub: FontVariation
var _jp: Font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui = load("res://assets/fonts/ChakraPetch-700.ttf")
	_sub = Hud.spaced(load("res://assets/fonts/MartianMono-600.ttf"), 3)
	_jp = load("res://assets/fonts/NotoSansJP-Bold-subset.otf")
	_rng.randomize()


## spec: {text, jp, sub, role ("accent" | "accent2" | "danger"), full (long hold)}
func play(spec: Dictionary) -> void:
	_queue.append(spec)
	if _card.is_empty():
		_next()


func busy() -> bool:
	return not _card.is_empty() or not _queue.is_empty()


## What's on screen now ("" when nothing).
func current_text() -> String:
	return _card.get("text", "")


func clear() -> void:
	_queue.clear()
	_card = {}
	queue_redraw()


## Length of a card in ms.
static func duration(full: bool, reduced: bool) -> float:
	var hold := Motion.CARD_FULL_HOLD_MS if full else Motion.CARD_HOLD_MS
	if reduced:
		return Motion.CARD_SLAM_MS + hold
	return Motion.CARD_FLASH_MS + Motion.CARD_SLAM_MS + hold + Motion.CARD_SLICE_MS


## Which beat a card is in at t ms: flash, slam, hold, slice or gone.
static func phase(t: float, full: bool, reduced: bool) -> String:
	if t >= duration(full, reduced):
		return "gone"
	if reduced:
		return "hold"
	if t < Motion.CARD_FLASH_MS:
		return "flash"
	t -= Motion.CARD_FLASH_MS
	if t < Motion.CARD_SLAM_MS:
		return "slam"
	t -= Motion.CARD_SLAM_MS
	var hold := Motion.CARD_FULL_HOLD_MS if full else Motion.CARD_HOLD_MS
	return "hold" if t < hold else "slice"


func _next() -> void:
	_card = {} if _queue.is_empty() else _queue.pop_front()
	if _card.is_empty():
		return
	_start = fx.clock_ms
	_flashed = not fx.reduced_motion and fx.guard.allow(fx.clock_ms)
	_speed.clear()
	for i in SPEED_LINES:
		_speed.append([_rng.randf_range(0.04, 0.96), _rng.randf_range(-0.2, 0.8), _rng.randf_range(80, 420),
			_rng.randf_range(0.3, 0.9)])


func _process(_delta: float) -> void:
	if _card.is_empty():
		return
	var t := fx.clock_ms - _start
	if t >= duration(bool(_card.get("full", false)), fx.reduced_motion):
		var done := _card
		_next()
		finished.emit(done)
	queue_redraw()


func _draw() -> void:
	if _card.is_empty() or fx.palette == null:
		return
	var pal := fx.palette
	var full := bool(_card.get("full", false))
	var reduced := fx.reduced_motion
	var t := fx.clock_ms - _start
	var ph := phase(t, full, reduced)
	var band_col := pal.c(_card.get("role", "accent"))
	var w := size.x
	var h := size.y
	if ph == "flash":
		if _flashed:
			draw_rect(Rect2(Vector2.ZERO, size), Color(band_col, 0.5))
		return
	var since := t if reduced else t - Motion.CARD_FLASH_MS
	var slam := 1.0 if reduced else clampf(since / Motion.CARD_SLAM_MS, 0.0, 1.0)
	var band_e := Motion.bezier(0.2, 1.4, 0.4, 1.0, slam)
	var text_e := Motion.bezier(0.1, 0.9, 0.3, 1.0, slam)
	var slicing := ph == "slice"
	var mid := size * 0.5
	# Band: 120% wide, 40% tall, rotated -6 degrees, slamming from 1.18 x 0.6.
	var bw := w * 1.2
	var bh := h * BAND_FRAC
	var sx := lerpf(1.18, 1.0, band_e)
	var sy := lerpf(0.6, 1.0, band_e)
	var band_off := Vector2(18, 0) if slicing else Vector2.ZERO
	draw_set_transform(mid + band_off, deg_to_rad(BAND_ROT), Vector2(sx, sy))
	var r := Rect2(-bw * 0.5, -bh * 0.5, bw, bh)
	for strip in _strips(r, slicing):
		draw_rect(strip, band_col)
	# Faint horizontal lines through the band, every 10 px.
	var line := Color(pal.c("void"), 0.22)
	var y := r.position.y + 9.0
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, bw, 1), line)
		y += 10.0
	# Speed lines sweep right to left for the whole hold.
	var hold := Motion.CARD_FULL_HOLD_MS if full else Motion.CARD_HOLD_MS
	var sweep := 0.0 if reduced else clampf(since / (Motion.CARD_SLAM_MS + hold), 0.0, 1.0)
	for s in _speed:
		var sx0: float = r.position.x + s[1] * bw + lerpf(300.0, -300.0, sweep)
		draw_rect(Rect2(sx0, r.position.y + s[0] * bh, s[2], 2), Color(pal.c("void"), 0.7 * s[3]))
	draw_set_transform(Vector2.ZERO)
	# Text: void, skewed -10 degrees, sliding in from the right; the outline
	# copy (ink) sits 14, 8 behind and slides in from further out.
	var text: String = _card.text
	var tw := _ui.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX).x
	# translate(-50%, -54%) of a 0.9 line box puts the baseline about 0.31 em below the middle.
	var base := Vector2(mid.x - tw * 0.5, mid.y + TEXT_PX * 0.31)
	var text_off := Vector2(-26, 0) if slicing else Vector2.ZERO
	var a := text_e
	for i in 2:
		var slide := Vector2((120.0 + i * 40.0) * (1.0 - text_e), 0)
		var skew := Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(TEXT_SKEW)), 1), mid)
		draw_set_transform_matrix(skew)
		var p := base - mid + slide + text_off
		if i == 0:
			draw_string_outline(_ui, p + Vector2(14, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX, 3,
				Color(pal.c("ink"), 0.85 * a))
		else:
			draw_string(_ui, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX, Color(pal.c("void"), a))
	draw_set_transform(Vector2.ZERO)
	# Japanese word and subtitle, under the text, on the band's angle.
	var jp: String = _card.get("jp", "")
	var sub: String = _card.get("sub", "")
	if jp != "" or sub != "":
		var jw := _jp.get_string_size(jp, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x if jp != "" else 0.0
		var sw := _sub.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var total := jw + (18.0 if jp != "" and sub != "" else 0.0) + sw
		draw_set_transform(mid + Vector2(0, 118) + text_off, deg_to_rad(BAND_ROT), Vector2.ONE)
		var x := -total * 0.5
		var ink := Color(pal.c("void"), a)
		if jp != "":
			draw_string(_jp, Vector2(x, 18), jp, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
			x += jw + 18.0
		draw_string(_sub, Vector2(x, 17), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
		draw_set_transform(Vector2.ZERO)
	if slicing:
		_draw_slice_gaps(mid + band_off, r, bh, pal)


## The band as one rect, or as three strips while slicing.
func _strips(r: Rect2, slicing: bool) -> Array[Rect2]:
	if not slicing:
		return [r]
	var out: Array[Rect2] = []
	for s in [[0.0, 0.30], [0.34, 0.66], [0.72, 1.0]]:
		out.append(Rect2(r.position.x, r.position.y + r.size.y * s[0], r.size.x, r.size.y * (s[1] - s[0])))
	return out


## Cuts the text along the band's two gaps. The text is one draw call, so the
## gaps are painted over it in void at 85% rather than masked out.
func _draw_slice_gaps(at: Vector2, r: Rect2, bh: float, pal: Palette) -> void:
	draw_set_transform(at, deg_to_rad(BAND_ROT), Vector2.ONE)
	for g in [[0.30, 0.34], [0.66, 0.72]]:
		draw_rect(Rect2(r.position.x, r.position.y + bh * g[0], r.size.x, bh * (g[1] - g[0])), Color(pal.c("void"), 0.85))
	draw_set_transform(Vector2.ZERO)
