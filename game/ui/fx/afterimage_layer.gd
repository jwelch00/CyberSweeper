class_name AfterimageLayer
extends MultiMeshInstance2D
## Cascade afterimages: one MultiMesh (no node per cell) used as a ring
## buffer of echoes. The shader animates each echo from its start time, so
## spawning is the only CPU work.

const CAPACITY := 4096
const QUAD := 1.8   # instance size in world units (room for the glow)

var view: BoardView
var _next := 0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = CAPACITY
	for i in CAPACITY:
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(QUAD, QUAD), 0.0, Vector2(-1e6, -1e6)))
		mm.set_instance_custom_data(i, Color(-1e7, 0, 0, 0))
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/fx/afterimage.gdshader")
	material = mat
	mat.set_shader_parameter("life_ms", Motion.GHOST_LIFE_MS)
	mat.set_shader_parameter("drift_px", Motion.DRIFT_PX)
	mat.set_shader_parameter("pitch_1x", BoardCamera.CELL + BoardCamera.GAP)
	mat.set_shader_parameter("quad", QUAD)
	mat.set_shader_parameter("chip", BoardCamera.CELL / (BoardCamera.CELL + BoardCamera.GAP))


func set_palette(p: Palette) -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("c0", p.c("accent2"))
	m.set_shader_parameter("c1", p.c("accent"))
	m.set_shader_parameter("c2", p.c("warn"))


## Three echoes for cell c, revealed at at_ms, drifting away from `from`.
func spawn(c: Vector2i, at_ms: float, from: Vector2i) -> void:
	for e in echoes(c, at_ms, from):
		multimesh.set_instance_transform_2d(_next, Transform2D(0.0, Vector2(QUAD, QUAD), 0.0, e.mid))
		multimesh.set_instance_custom_data(_next, e.data)
		_next = (_next + 1) % CAPACITY


## Instance data for the echoes: chip centre (world units) and custom data
## (start ms, echo index, direction away from the click).
static func echoes(c: Vector2i, at_ms: float, from: Vector2i) -> Array[Dictionary]:
	var dir := Vector2(c - from)
	dir = dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
	var mid := Vector2(c) + Vector2.ONE * (BoardCamera.CELL * 0.5 / (BoardCamera.CELL + BoardCamera.GAP))
	var out: Array[Dictionary] = []
	for k in Motion.ECHO_DELAYS.size():
		out.append({"mid": mid, "data": Color(at_ms + Motion.ECHO_DELAYS[k], float(k), dir.x, dir.y)})
	return out


func clear() -> void:
	for i in CAPACITY:
		multimesh.set_instance_custom_data(i, Color(-1e7, 0, 0, 0))


func _process(_delta: float) -> void:
	if view == null:
		return
	var cam := view.cam
	position = cam.world_to_screen(Vector2.ZERO)
	scale = Vector2(cam.pitch(), cam.pitch())
	var m := material as ShaderMaterial
	m.set_shader_parameter("now_ms", view.clock_ms)
	m.set_shader_parameter("px", 1.0 / cam.pitch())
