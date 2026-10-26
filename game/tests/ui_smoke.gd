extends SceneTree
## Plays the real gameplay screen with real input events (pushed through the
## viewport, so HUD panels and routing are exercised) and checks that what the
## board shows always matches the game. Runs headless in the test suites:
##   godot --headless --path game -s res://tests/ui_smoke.gd
## Under a display, `-- --shots DIR` also saves screenshots at key moments.

var _code := 3
var _fails: Array[String] = []
var _checks := 0
var _shots := ""
var gv: GameView


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		_shots = args[i + 1]
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return _code != 3 and _code != 4


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("FAIL ", msg)


func _run() -> void:
	_code = 4   # running
	gv = GameView.new()
	root.add_child(gv)
	gv.size = root.get_visible_rect().size
	if not gv.atlas.is_built:
		await gv.atlas.built
	await _frames(2)
	await _arcade()
	await _ghost()
	print("ui smoke: %d checks, %d failed" % [_checks, _fails.size()])
	gv.queue_free()
	await _frames(2)
	_code = 1 if not _fails.is_empty() else 0
	quit(_code)


func _gs() -> GameState:
	return gv.session._gs


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits until the worker has answered everything and the view applied it.
func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	while (gv.session.busy() or gv.session.in_flight > 0) and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await _frames(2)


func _mouse(button: MouseButton, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)


func _move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)


func _click(c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	var p := gv.board.cam.cell_center(c)
	_mouse(button, p, true)
	_mouse(button, p, false)
	await _settle()


func _key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	root.push_input(e, true)
	var u := e.duplicate()
	u.pressed = false
	root.push_input(u, true)
	await _settle()


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := _shots.path_join("ui-" + name + ".png")
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)


## Every revealed cell, flag and hit the game knows about is what the view shows.
func _mirror_matches(where: String) -> void:
	var gs := _gs()
	var bad := 0
	for k: Vector2i in gs.board.chunks:
		var ch: Chunk = gs.board.chunks[k]
		var corner := gs.board.chunk_corner(k)
		for i in Chunk.CELLS:
			var c := corner + Vector2i(i & 15, i >> 4)
			var v: Array = gv.board.cell(c)
			var want: int = BoardView.HIDDEN
			var n := 0
			if ch.state[i] == Board.REVEALED:
				want = BoardView.OPEN
				n = gs.board.number(c)
			elif ch.state[i] == Board.HIT:
				want = BoardView.HIT
			elif gs.board.is_flagged(c):
				want = BoardView.FLAG
			if gs.over and v[0] in [BoardView.MINE_SHOWN, BoardView.WRONG_FLAG]:
				continue
			if v[0] != want or (want == BoardView.OPEN and v[1] != n):
				bad += 1
	check(bad == 0, "%s: %d cells shown differently from the game" % [where, bad])


func _arcade() -> void:
	gv.new_run(11, GameState.Mode.ARCADE)
	gv.clock_paused = true   # run time only moves where a check needs it
	await _frames(2)
	var cam := gv.board.cam
	var mid := cam.cell_at(cam.view_size * 0.5)
	await _click(mid)
	check(gv.started, "first click starts the run")
	check(_gs().started and _gs().tiles >= 9, "first click opened a region")
	await _frames(int(BoardView.ANIM_MS / 16.0) + 10)
	await _shot("01-opening")
	_mirror_matches("after the first click")

	# A few provably safe clicks.
	for i in 12:
		_gs().solver.solve()
		var safe: Array = _gs().solver.safe.keys()
		if safe.is_empty():
			break
		var c: Vector2i = safe[0]
		cam.center = Vector2(c) + Vector2(0.5, 0.5)
		await _frames(1)
		var before := _gs().tiles
		await _click(c)
		check(_gs().tiles > before, "clicking a safe cell reveals it")
	_mirror_matches("after safe clicks")
	check(int(gv.state.score) == _gs().score, "HUD score matches the game")

	# Flag a proven mine, then chord a number whose mines are all flagged.
	_gs().solver.solve()
	var chorded := false
	for p: Vector2i in _gs().solver.num:
		var hidden_safe := 0
		var mines: Array[Vector2i] = []
		var unknown := false
		for d in Board.NB:
			var q := p + d
			if _gs().board.state_at(q) != Board.HIDDEN:
				continue
			if _gs().solver.mine.has(q):
				mines.append(q)
			elif _gs().solver.safe.has(q):
				hidden_safe += 1
			else:
				unknown = true
		if unknown or mines.is_empty() or hidden_safe == 0:
			continue
		cam.center = Vector2(p) + Vector2(0.5, 0.5)
		await _frames(1)
		for m in mines:
			await _click(m, MOUSE_BUTTON_RIGHT)
			check(_gs().board.is_flagged(m), "right click flags")
			check(gv.board.cell(m)[0] == BoardView.FLAG, "the view shows the flag")
		# Hold on the number: chord preview on; release: chord.
		var pp := cam.cell_center(p)
		_mouse(MOUSE_BUTTON_LEFT, pp, true)
		await _frames(1)
		check(gv.board.chord_on and gv.board.chord_center == p, "holding a number shows the chord preview")
		await _shot("02-chord-preview")
		var before := _gs().tiles
		_mouse(MOUSE_BUTTON_LEFT, pp, false)
		await _settle()
		check(not gv.board.chord_on, "releasing ends the preview")
		check(_gs().tiles >= before + hidden_safe, "the chord opened the safe neighbours")
		chorded = true
		break
	check(chorded, "found a number to chord")
	_mirror_matches("after flag and chord")

	# Dragging pans without revealing anything.
	var start := cam.center
	var tiles := _gs().tiles
	var a := Vector2(900, 500)
	_mouse(MOUSE_BUTTON_LEFT, a, true)
	for k in 10:
		_move(a + Vector2(20 * (k + 1), 0), Vector2(20, 0))
	_mouse(MOUSE_BUTTON_LEFT, a + Vector2(200, 0), false)
	await _settle()
	check(_gs().tiles == tiles, "a drag never reveals")
	check(absf((start.x - cam.center.x) * cam.pitch() - 200.0) < 1.0, "the board follows the drag")

	# Wheel zoom keeps the point under the cursor.
	var pt := Vector2(1300, 300)
	var w := cam.screen_to_world(pt)
	var z := cam.zoom
	_mouse(MOUSE_BUTTON_WHEEL_UP, pt, true)
	_mouse(MOUSE_BUTTON_WHEEL_UP, pt, false)
	await _frames(1)
	check(cam.zoom > z, "wheel up zooms in")
	check(cam.screen_to_world(pt).distance_to(w) < 1e-3, "zoom keeps the point under the cursor")
	cam.zoom = 1.0

	# Clicking HUD panels doesn't reveal the board underneath.
	tiles = _gs().tiles
	_mouse(MOUSE_BUTTON_LEFT, Vector2(1750, 100), true)
	_mouse(MOUSE_BUTTON_LEFT, Vector2(1750, 100), false)
	await _settle()
	check(_gs().tiles == tiles, "the score panel eats clicks")

	# Run time drains the signal in Arcade mode.
	gv.clock_paused = false
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1500:
		await process_frame
	gv.clock_paused = true
	await _settle()
	check(float(gv.state.signal) < 1.0, "the signal drains while the clock runs")

	# A mine hit costs a link and shows the hit.
	var mine := _hidden_mine()
	cam.center = Vector2(mine) + Vector2(0.5, 0.5)
	await _frames(1)
	await _click(mine)
	check(_gs().links == 2, "a mine hit costs a link")
	check(gv.board.cell(mine)[0] == BoardView.HIT, "the view shows the hit")
	check(int(gv.state.links) == 2, "the HUD shows two links")
	await _frames(4)
	await _shot("03-mine-hit")

	# Two more hits end the run: overlay, mines shown, R restarts.
	for k in 2:
		var m := _hidden_mine()
		cam.center = Vector2(m) + Vector2(0.5, 0.5)
		await _frames(1)
		await _click(m)
	check(gv.over and _gs().over, "three hits end the run")
	check(gv.overlay.visible, "the run-end overlay shows")
	var shown := 0
	for k in gv.board._state:
		if gv.board._state[k][0] == BoardView.MINE_SHOWN:
			shown += 1
	check(shown > 0, "hidden mines near the explored area are shown")
	await _frames(30)
	await _shot("04-link-severed")
	_mirror_matches("at game over")
	await _key(KEY_R)
	check(not gv.over and not gv.started, "R starts a new run")


func _ghost() -> void:
	await _key(KEY_F8)
	check(gv.mode == GameState.Mode.GHOST, "F8 switches to Ghost mode")
	var cam := gv.board.cam
	await _click(cam.cell_at(cam.view_size * 0.5))
	check(gv.started, "ghost run started")
	gv.clock_paused = false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
	gv.clock_paused = true
	await _settle()
	check(int(gv.state.elapsed_ms) > 1000, "run time passes in Ghost mode")
	check(float(gv.state.signal) == 1.0, "Ghost mode has no draining signal")
	check(not gv.hud._sig.visible, "the HUD hides the signal meter in Ghost mode")
	await _shot("05-ghost")
	await _key(KEY_E, true)
	check(gv.over and _gs().ended, "Ctrl+E ends a Ghost run")
	check(gv.overlay.visible and gv.overlay.title == "Run banked", "the banked overlay shows")
	await _frames(30)
	await _shot("06-ghost-banked")


func _hidden_mine() -> Vector2i:
	var gs := _gs()
	for p: Vector2i in gs.solver.num:
		for d in Board.NB:
			var q := p + d
			if gs.board.state_at(q) == Board.HIDDEN and gs.board.is_mine(q) and not gs.board.is_flagged(q):
				return q
	return Vector2i.ZERO

