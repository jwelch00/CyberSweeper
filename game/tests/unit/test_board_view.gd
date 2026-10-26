extends TestCase
## The board view's wrap-around cell texture and the popup rules.


func _view() -> BoardView:
	var v := BoardView.new()
	v._ready()
	v.size = Vector2(1920, 1080)
	return v


func test_texel_index_wraps_negative_cells() -> void:
	eq(BoardView.texel_index(Vector2i(0, 0)), 0)
	eq(BoardView.texel_index(Vector2i(-1, -1)), (255 * 256 + 255) * 4)
	eq(BoardView.texel_index(Vector2i(256, 3)), BoardView.texel_index(Vector2i(0, 3)))
	eq(BoardView.texel_index(Vector2i(-257, 0)), BoardView.texel_index(Vector2i(255, 0)))


func test_cells_are_written_with_state_number_and_time() -> void:
	var v := _view()
	v._process(0.0)
	v.clock_ms = 1234.0
	v.set_cell(Vector2i(-3, 5), BoardView.OPEN, 7)
	var t := v.texel(Vector2i(-3, 5))
	eq(t[0], BoardView.OPEN)
	eq(t[1], 7)
	eq(t[2] + ((t[3] & 127) << 8), 1234, "event time stored")
	check(t[3] & 128 != 0, "animating")
	v.set_cell(Vector2i(-3, 5), BoardView.OPEN, 7, -1.0, false)
	check(v.texel(Vector2i(-3, 5))[3] & 128 == 0, "settled cells are not animating")
	v.free()


func test_animation_bit_clears_after_the_animation() -> void:
	var v := _view()
	v._process(0.0)
	v.set_cell(Vector2i(1, 1), BoardView.OPEN, 2)
	v._process((BoardView.ANIM_MS + 50.0) / 1000.0)
	check(v.texel(Vector2i(1, 1))[3] & 128 == 0, "bit cleared")
	eq(v.texel(Vector2i(1, 1))[1], 2, "number kept")
	v.free()


func test_scrolling_rewrites_cells_that_come_into_the_window() -> void:
	var v := _view()
	v._process(0.0)
	var near := Vector2i(10, 10)
	var far := Vector2i(10 + 256, 10)     # same texel as `near`
	v.set_cell(near, BoardView.OPEN, 3, -1.0, false)
	v.set_cell(far, BoardView.FLAG, 0, -1.0, false)
	eq(v.texel(near)[0], BoardView.OPEN, "the near cell owns the texel while in the window")
	v.cam.center = Vector2(far) + Vector2(0.5, 0.5)
	v._process(0.0)
	eq(v.texel(far)[0], BoardView.FLAG, "after scrolling, the far cell owns it")
	v.cam.center = Vector2(near) + Vector2(0.5, 0.5)
	v._process(0.0)
	eq(v.texel(near)[0], BoardView.OPEN, "and back again")
	eq(v.texel(near)[1], 3)
	# One column at a time, as when panning.
	for x in range(0, 300, 7):
		v.cam.center = Vector2(near.x + x, near.y) + Vector2(0.5, 0.5)
		v._process(0.0)
	eq(v.texel(far)[0], BoardView.FLAG, "panning column by column also rewrites")
	v.free()


func test_view_never_mixes_up_cells_while_panning() -> void:
	var v := _view()
	v._process(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var cells := {}
	for i in 400:
		var c := Vector2i(rng.randi_range(-600, 600), rng.randi_range(-600, 600))
		var n := rng.randi_range(0, 8)
		cells[c] = n
		v.set_cell(c, BoardView.OPEN, n, -1.0, false)
	for step in 60:
		v.cam.center = Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		v._process(0.0)
		var win := v.window_for(v.cam.center)
		for c: Vector2i in cells:
			if c.x >= win.x and c.y >= win.y and c.x < win.x + 256 and c.y < win.y + 256:
				eq(v.texel(c)[1], cells[c], "cell %s at step %d" % [c, step])
	v.free()


func test_popup_rules() -> void:
	var p := Palette.by_id("signal")
	var one: Array[Vector2i] = [Vector2i(0, 0)]
	eq(PopupLayer.for_move(one, PackedInt32Array([3]), p), ["+3", p.number(3)], "a single number pops in its color")
	var many: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	eq(PopupLayer.for_move(many, PackedInt32Array([0, 1, 2, 3]), p), ["+6", p.c("accent")], "a cascade pops its sum in accent")
	eq(PopupLayer.for_move(one, PackedInt32Array([0]), p), [], "a zero pops nothing")
	eq(PopupLayer.for_move(one, PackedInt32Array([-1]), p), [], "a mine hit pops nothing")
