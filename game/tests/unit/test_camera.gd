extends TestCase


func test_screen_world_round_trip() -> void:
	var cam := BoardCamera.new()
	cam.center = Vector2(-123.4, 56.7)
	for z in [0.5, 1.0, 1.37, 2.0]:
		cam.zoom = z
		for s in [Vector2.ZERO, Vector2(960, 540), Vector2(1919, 1079), Vector2(13.5, 800.25)]:
			var back := cam.world_to_screen(cam.screen_to_world(s))
			check(back.distance_to(s) < 1e-3, "zoom %s: %s -> %s" % [z, s, back])


func test_zoom_keeps_the_point_under_the_cursor() -> void:
	var cam := BoardCamera.new()
	cam.center = Vector2(10, 10)
	var pt := Vector2(1500, 200)
	var w := cam.screen_to_world(pt)
	for f in [1.1, 1.1, 1.1, 0.8, 0.8, 1.25]:
		cam.zoom_at(pt, f)
		check(cam.screen_to_world(pt).distance_to(w) < 1e-4, "point drifted at zoom %s" % cam.zoom)


func test_zoom_is_clamped() -> void:
	var cam := BoardCamera.new()
	for i in 40:
		cam.zoom_at(Vector2(100, 100), 1.3)
	eq(cam.zoom, BoardCamera.ZOOM_MAX)
	for i in 80:
		cam.zoom_at(Vector2(100, 100), 0.7)
	eq(cam.zoom, BoardCamera.ZOOM_MIN)


func test_numbers_never_under_11px() -> void:
	var cam := BoardCamera.new()
	var z := BoardCamera.ZOOM_MIN
	while z <= BoardCamera.ZOOM_MAX:
		cam.zoom = z
		check(cam.number_px() >= 11.0, "zoom %s gives %s px" % [z, cam.number_px()])
		check(cam.number_px() >= 0.52 * cam.cell_px() - 1e-6, "and at least 52% of the cell")
		z += 0.01
	cam.zoom = 1.0
	check(absf(cam.number_px() - 20.8) < 1e-6, "52% of 40 px at default zoom")


func test_cell_at_matches_cell_rect() -> void:
	var cam := BoardCamera.new()
	cam.center = Vector2(-3.3, 7.9)
	cam.zoom = 0.75
	for c in [Vector2i(0, 0), Vector2i(-5, 9), Vector2i(-1, -1), Vector2i(3, 12)]:
		var r := cam.cell_rect(c)
		eq(cam.cell_at(r.position + r.size * 0.5), c)
		eq(cam.cell_at(r.position + Vector2(0.01, 0.01)), c)


func test_drag_follows_the_pointer() -> void:
	var cam := BoardCamera.new()
	var pt := Vector2(700, 400)
	var w := cam.screen_to_world(pt)
	cam.drag(Vector2(120, -45))
	check(cam.world_to_screen(w).distance_to(pt + Vector2(120, -45)) < 1e-4, "the board moves with the drag")
