class_name Datamosh
extends ColorRect
## Every screen change breaks the old screen into 7 horizontal bands and snaps
## the new one in band by band (design/MOTION.md 7). One full-screen shader:
## the old frame is grabbed once when the transition starts, the new screen
## is read live underneath. Input is blocked until it's over. Reduce motion
## makes it an instant cut.

signal done

var fx: ScreenFx
var active := false
var _start := 0.0
var _rng := RandomNumberGenerator.new()
var _old: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/fx/datamosh.gdshader")
	material = m
	m.set_shader_parameter("break_ms", Motion.MOSH_BREAK_MS)
	m.set_shader_parameter("total_ms", Motion.MOSH_TOTAL_MS)
	m.set_shader_parameter("fade_ms", Motion.MOSH_OLD_FADE_MS)
	visible = false
	_rng.randomize()


func apply_palette(p: Palette) -> void:
	(material as ShaderMaterial).set_shader_parameter("c_void", p.c("void"))


## Band edges as fractions of the height: 7 bands of slightly random height.
static func cuts_for(rng: RandomNumberGenerator, bands := Motion.MOSH_BANDS) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, bands):
		out.append(float(i) / bands + rng.randf_range(-1.0, 1.0) / bands / 3.0)
	out.append(1.0)
	return out


## Starts a transition from whatever is on screen now. Call it, then switch
## screens straight away: the old frame covers the switch.
func begin() -> void:
	if fx.reduced_motion:
		done.emit.call_deferred()
		return
	_old = null
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			_old = ImageTexture.create_from_image(img)
	var m := material as ShaderMaterial
	m.set_shader_parameter("old_tex", _old)
	m.set_shader_parameter("has_old", _old != null)
	m.set_shader_parameter("cuts", cuts_for(_rng))
	var hues := [0.0, 90.0, 160.0, 220.0, 300.0]
	var ob: Array[Vector4] = []
	var nb: Array[Vector4] = []
	for i in Motion.MOSH_BANDS:
		var dx := _rng.randf_range(-140.0, 140.0) * (1.0 if _rng.randf() < 0.5 else 0.3)
		var stretch := _rng.randf_range(1.6, 3.0) if _rng.randf() < 0.3 else 1.0
		ob.append(Vector4(dx, stretch, hues[i % 5], 0.0))
		nb.append(Vector4(_rng.randf_range(-120.0, 120.0), _rng.randf_range(0.0, 60.0), hues[(i + 2) % 5], 0.0))
	m.set_shader_parameter("old_band", ob)
	m.set_shader_parameter("new_band", nb)
	_start = fx.clock_ms
	active = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	m.set_shader_parameter("t_ms", 0.0)


func elapsed() -> float:
	return fx.clock_ms - _start if active else -1.0


func _process(_delta: float) -> void:
	if not active:
		return
	var t := fx.clock_ms - _start
	(material as ShaderMaterial).set_shader_parameter("t_ms", t)
	if t >= Motion.MOSH_TOTAL_MS:
		active = false
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_old = null
		done.emit()


func _gui_input(event: InputEvent) -> void:
	if active:
		accept_event()
