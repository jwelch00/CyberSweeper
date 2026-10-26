class_name ScreenFx
extends Node
## Effects shared by every screen: the post pass (scanlines, flash frames,
## tear lines), smash-cut title cards, datamosh transitions, the flash guard
## and the FPS overlay. One motion clock drives them; screenshots pin it.

var clock_ms := 0.0
var freeze := false
var guard := FlashGuard.new()
var reduced_motion := false
var palette: Palette
var post: ColorRect
var cards: TitleCards
var mosh: Datamosh
var fps_label: Label
## Extra scanline strength: 0.6 while the signal is low, 1 (double) at strain 2.
var scan_boost := 0.0
## Strain edge: level (0 = none) and opacity this frame (the heartbeat).
var strain_level := 0
var strain_a := 0.0

var _flash_col := Color()
var _flash_a := 0.0
var _flash_until := -1e9
var _tears: Array = []   # [y0, y1 (fractions of the screen height), until_ms]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	post = ColorRect.new()
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pm := ShaderMaterial.new()
	pm.shader = load("res://ui/post_fx.gdshader")
	post.material = pm
	post_layer.add_child(post)
	fps_label = Label.new()
	fps_label.position = Vector2(12, 1040)
	fps_label.visible = false
	post_layer.add_child(fps_label)
	var card_layer := CanvasLayer.new()
	card_layer.layer = 20
	add_child(card_layer)
	cards = TitleCards.new()
	cards.fx = self
	card_layer.add_child(cards)
	var mosh_layer := CanvasLayer.new()
	mosh_layer.layer = 100
	add_child(mosh_layer)
	mosh = Datamosh.new()
	mosh.fx = self
	mosh_layer.add_child(mosh)


func apply_palette(p: Palette) -> void:
	palette = p
	var pm := post.material as ShaderMaterial
	pm.set_shader_parameter("c_ink", p.c("ink"))
	pm.set_shader_parameter("c_danger", p.c("danger"))
	fps_label.add_theme_color_override("font_color", p.c("inkDim"))
	cards.queue_redraw()
	mosh.apply_palette(p)


func set_scanlines(on: bool) -> void:
	(post.material as ShaderMaterial).set_shader_parameter("scanlines", 1.0 if on else 0.0)


## No strain, no extra scanlines, no tears: for screens other than the game.
func calm() -> void:
	strain_level = 0
	strain_a = 0.0
	scan_boost = 0.0
	_tears.clear()


## A full-screen flash frame (if the guard allows it). Returns whether it
## showed. guarded=false when the caller already asked the guard (one hit's
## flash and tears are one flash).
func flash(color: Color, alpha: float, ms: float, guarded := true) -> bool:
	if guarded and not guard.allow(clock_ms):
		return false
	_flash_col = color
	_flash_a = alpha
	_flash_until = clock_ms + ms
	return true


## n tear lines across the screen for ms (counts as one flash).
func tear(n: int, ms: float, min_h := 6.0, max_h := 40.0, guarded := true) -> bool:
	if guarded and not guard.allow(clock_ms):
		return false
	for i in n:
		var y := _rng.randf_range(0.05, 0.9)
		_tears.append([y, y + _rng.randf_range(min_h, max_h) / 1080.0, clock_ms + ms])
	while _tears.size() > 4:
		_tears.pop_front()
	return true


func flash_on() -> bool:
	return clock_ms < _flash_until


func tears_on() -> int:
	return _tears.filter(func(t): return clock_ms < t[2]).size()


func _process(delta: float) -> void:
	if not freeze:
		clock_ms += delta * 1000.0
	var pm := post.material as ShaderMaterial
	pm.set_shader_parameter("scan_boost", scan_boost)
	pm.set_shader_parameter("strain_a", strain_a if strain_level > 0 else 0.0)
	pm.set_shader_parameter("strain_level", float(maxi(strain_level, 1)))
	pm.set_shader_parameter("flash_col", Color(_flash_col, _flash_a if clock_ms < _flash_until else 0.0))
	_tears = _tears.filter(func(t): return clock_ms < t[2])
	var tv: Array[Vector4] = []
	for i in 4:
		if i < _tears.size():
			tv.append(Vector4(_tears[i][0], _tears[i][1], 1.0, 0.0))
		else:
			tv.append(Vector4.ZERO)
	pm.set_shader_parameter("tears", tv)
	if fps_label.visible:
		fps_label.text = "%d fps  %.1f ms" % [Engine.get_frames_per_second(), delta * 1000.0]
