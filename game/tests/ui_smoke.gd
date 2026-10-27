extends SceneTree
## Plays the real screens with real input events (pushed through the viewport,
## so routing, panels and buttons are exercised): the boot and its skip, the
## title, a run with checks that what the board shows always matches the game,
## mine hits and strain, LINK SEVERED, the game-over buttons, and Ghost mode.
## The screen-effects clock is stepped by hand so cards and transitions are
## deterministic. Runs headless in the test suites:
##   godot --headless --path game -s res://tests/ui_smoke.gd
## Under a display, `-- --shots DIR` also saves screenshots at key moments.

var _code := 3
var _fails: Array[String] = []
var _checks := 0
var _shots := ""
var flow: ScreenFlow
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
	# A scratch save folder: the smoke test never touches a real save.
	var save := ProjectSettings.globalize_path("res://").path_join("../test-output/save-smoke")
	DirAccess.make_dir_recursive_absolute(save)
	for f in DirAccess.get_files_at(save):
		DirAccess.remove_absolute(save.path_join(f))
	SaveStore.dir = save
	flow = ScreenFlow.new()
	flow.pause_on_focus_loss = false   # a stray focus event must not pause a check
	root.add_child(flow)
	flow.size = root.get_visible_rect().size
	gv = flow.game
	flow.fx.freeze = true
	if not gv.atlas.is_built:
		await gv.atlas.built
	await _frames(2)
	await _boot()
	await _reduced()
	await _title()
	await _arcade()
	await _game_over()
	await _menus()
	await _ghost()
	print("ui smoke: %d checks, %d failed" % [_checks, _fails.size()])
	flow.queue_free()
	await _frames(2)
	_code = 1 if not _fails.is_empty() else 0
	quit(_code)


## Steps the screen-effects clock (cards, datamosh, boot) by ms, a frame per step.
func _advance(ms: float, step := 20.0) -> void:
	var left := ms
	while left > 0.0:
		flow.fx.clock_ms += minf(step, left)
		left -= step
		await process_frame


func _boot() -> void:
	flow.start({"bootseed": "424242", "breach": "one"})
	await _frames(1)
	check(flow.current == flow.boot and flow.boot.visible, "launch shows the boot")
	var b := flow.boot
	check(b.plan.kind == "one" and b.plan.stalls.size() == 1, "a forced breach plays that variant")
	var d: Dictionary = b.plan.segs[1]
	await _advance(b.loader_at() + d.t0 + (d.t1 - d.t0) * 0.5 - b.elapsed())
	check(b.plan.at(b.elapsed() - b.loader_at()).seg.get("denied", false), "the breach hits ACCESS DENIED")
	await _shot("00-boot-denied")
	await _advance(b.card_at() - b.elapsed() + 1.0)
	await _frames(2)
	check(flow.fx.cards.current_text() == "JACKED IN", "the boot ends on the JACKED IN card")
	await _advance(TitleCards.duration(false, false) + 40.0)
	check(flow.current == flow.title, "after the card the title comes up")
	check(flow.fx.mosh.active, "by datamosh")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	check(not flow.fx.mosh.active, "the datamosh finishes in 380 ms")
	# Again, skipped: any key goes straight to the title.
	flow.start({"bootseed": "7", "jackedoff": "true"})
	await _frames(1)
	check(flow.boot.card_text() == "JACKED OFF", "the 1-in-10,000 card can be forced")
	await _key(KEY_SPACE)
	check(flow.current == flow.title, "any key skips the boot")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)


## Reduce motion: the boot shows everything at once, the card has no flash,
## and screens cut instead of datamoshing.
func _reduced() -> void:
	flow.settings.set_reduced_motion(true)
	flow.apply_settings()
	check(flow.fx.guard.reduce_flashing, "reduce motion turns on reduce flashing")
	flow.start({"bootseed": "9", "breach": "double"})
	await _frames(1)
	var b := flow.boot
	check(b.breach_ms() == 0.0, "reduce motion: the breach is at 100% at once")
	await _advance(b.card_at() - b.elapsed() + 1.0)
	await _frames(2)
	check(flow.fx.cards.current_text() == "JACKED IN" and not flow.fx.cards._flashed, "the card shows with no flash frame")
	await _advance(TitleCards.duration(false, true) + 40.0)
	await _frames(2)
	check(flow.current == flow.title and not flow.fx.mosh.active, "and the title cuts in, no datamosh")
	flow.settings.set_reduced_motion(false)
	flow.settings.reduce_flashing = false
	flow.apply_settings()


func _title() -> void:
	var t := flow.title
	check(t.selected == 0, "Jack in is selected")
	await _key(KEY_DOWN)
	check(TitleScreen.ITEMS[t.selected][1] == "palettes", "the menu moves down")
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	check(flow.current == flow.modes, "Jack in opens the mode picker")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	check(flow.modes.selected == 0, "Arcade first")
	await _key(KEY_ENTER)
	check(flow.current == gv and gv.visible, "picking a mode starts a run")
	check(gv.mode == GameState.Mode.ARCADE and not gv.started, "a fresh Arcade run")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)


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
	if gv.session != null:
		await _settle()
	else:
		await _frames(2)


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
	gv.best_before = 5   # a tiny session best, so passing it shows NEW BEST
	gv.clock_paused = true   # run time only moves where a check needs it
	await _frames(2)
	var cam := gv.board.cam
	var mid := cam.cell_at(cam.view_size * 0.5)
	await _click(mid)
	check(gv.started, "first click starts the run")
	check(_gs().started and _gs().tiles >= 9, "first click opened a region")
	check(gv.lattice.on and gv.lattice.origin == _gs().board.origin, "the lattice locks onto the real chunk grid")
	check(LatticeLayer.chunk_id(_gs().board.chunk_key(gv.lattice.corner(Vector2i(2, -1)))) == "LAT 03F2:019F",
		"chunk IDs come from the generator's chunk keys")
	if _gs().score > 5:
		await _frames(2)
		check(flow.fx.cards.busy() and flow.fx.cards.current_text() == "NEW BEST", "passing the best so far shows NEW BEST")
		check(flow.fx.cards.mouse_filter == Control.MOUSE_FILTER_IGNORE, "mid-run cards never take input")
		await _advance(TitleCards.duration(false, false) + 40.0)
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
	check(_gs().grace and _gs().move_log.grace, "a person's run plays with signal grace")
	# One huge frame (a laptop waking up) adds at most MAX_FRAME_MS of run time.
	var ms0 := _gs().elapsed_ms
	gv.clock_paused = false
	gv._process(600.0)
	gv.clock_paused = true
	await _settle()
	check(_gs().elapsed_ms - ms0 <= int(GameView.MAX_FRAME_MS) + 1, "a ten-minute frame adds at most a quarter second")

	# A mine hit costs a link and shows the hit: a hazard tile, no popup text.
	var mine := _hidden_mine()
	cam.center = Vector2(mine) + Vector2(0.5, 0.5)
	await _frames(1)
	var pops := gv.popups._pops.size()
	await _click(mine)
	check(_gs().links == 2, "a mine hit costs a link")
	check(gv.board.cell(mine)[0] == BoardView.HIT, "the view shows the hit")
	check(gv.popups._pops.size() == pops, "no popup text on a mine hit")
	check(int(gv.state.links) == 2, "the HUD shows two links")
	check(gv.strain == 0, "two links and plenty of signal: no strain")
	await _frames(4)
	await _shot("03-mine-hit")

	# The second hit leaves one link: strain 1.
	var m2 := _hidden_mine()
	cam.center = Vector2(m2) + Vector2(0.5, 0.5)
	await _frames(1)
	await _click(m2)
	await _frames(2)
	check(gv.strain == 1, "one link left is strain 1")
	check(gv.hud._tl.ghost > 0.0, "strain shows the HUD frames' ghost outlines")
	check(flow.fx.strain_level == 1, "and the red edge")
	await _shot("04-strain")


## Pause, then the last link: LINK SEVERED, the game over screen (with a
## palette unlocked), its buttons, and the save.
func _game_over() -> void:
	await _key(KEY_ESCAPE)
	check(flow.current == flow.pause, "Esc pauses")
	check(gv.paused and gv.clock_paused, "run time stops")
	check(gv.board.concealed and not gv.lattice.visible, "the board hides behind the cipher")
	check(gv.visible and flow.pause.visible, "the pause panel sits over the hidden board")
	await _key(KEY_ESCAPE)
	check(flow.current == gv and not gv.paused and not gv.board.concealed, "Esc again resumes")
	flow.pause_on_focus_loss = true
	flow.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(flow.current == flow.pause and gv.clock_paused, "losing focus mid-run pauses it")
	flow.pause_on_focus_loss = false
	await _key(KEY_ESCAPE)
	check(flow.current == gv and not gv.paused, "and Esc resumes")
	var cam := gv.board.cam
	# Put the save just short of 25,000 tiles, so this run unlocks Root access.
	flow.profile.total_tiles = 25000 - _gs().tiles
	var m := _hidden_mine()
	cam.center = Vector2(m) + Vector2(0.5, 0.5)
	await _frames(1)
	await _click(m)
	check(gv.over and _gs().over, "three hits end the run")
	var shown := 0
	for k in gv.board._state:
		if gv.board._state[k][0] == BoardView.MINE_SHOWN:
			shown += 1
	check(shown > 0, "hidden mines near the explored area are shown")
	_mirror_matches("at game over")
	await _frames(2)
	check(flow.fx.cards.current_text() == "LINK SEVERED" or flow.fx.cards._queue.any(func(c): return c.text == "LINK SEVERED"),
		"losing the last link shows LINK SEVERED")
	check(flow.current == gv, "the card holds over the board")
	await _advance(TitleCards.duration(true, false) * 2.0 + 80.0)
	check(flow.current == flow.over, "then the game over screen")
	check(int(flow.over.summary.score) == _gs().score, "with the run's score")
	check(flow.profile.runs == 1 and flow.profile.arcade.size() == 1, "the run is recorded")
	check(FileAccess.file_exists(SaveStore.path("profile.json")), "and saved")
	check(flow.over.report.unlocked_now == ["root-access"], "the run unlocked Root access")
	var tally: Array = flow.over.summary.tally
	var sum := 0
	for n in range(1, tally.size()):
		sum += n * int(tally[n])
	check(sum == _gs().score, "the tally adds up to the score")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	await _shot("05-game-over")
	var eq := flow.over.button_rect("equip")
	check(eq.size.x > 0, "the unlock card has an Equip button")
	_mouse(MOUSE_BUTTON_LEFT, eq.get_center(), true)
	_mouse(MOUSE_BUTTON_LEFT, eq.get_center(), false)
	await _frames(2)
	check(flow.settings.palette_id == "root-access" and flow.palette.id == "root-access", "Equip applies the new palette")
	check(GameSettings.load_saved().palette_id == "root-access", "and saves it")
	# Run it back by clicking the button.
	var r := flow.over.button_rect("again")
	_mouse(MOUSE_BUTTON_LEFT, r.get_center(), true)
	_mouse(MOUSE_BUTTON_LEFT, r.get_center(), false)
	await _frames(2)
	check(flow.current == gv and not gv.started and not gv.over, "clicking Run it back starts a new run")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)


## From the title: settings, palettes and rivals, each saving and going back with Esc.
func _menus() -> void:
	# Leave the fresh run through pause: nothing was played, so nothing is recorded.
	await _key(KEY_ESCAPE)
	flow.pause.selected = 3
	await _key(KEY_ENTER)
	check(flow.current == flow.title, "Main menu from pause goes to the title")
	check(flow.profile.runs == 1, "an unplayed run isn't recorded")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	# Settings: turn scanlines off.
	flow.title.selected = 3
	await _key(KEY_ENTER)
	check(flow.current == flow.settings_screen, "Settings opens")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	flow.settings_screen.selected = flow.settings_screen.items().find("scanlines")
	await _key(KEY_ENTER)
	check(not flow.settings.scanlines, "Enter toggles a setting")
	check(not GameSettings.load_saved().scanlines, "and it's saved straight away")
	await _key(KEY_ESCAPE)
	check(flow.current == flow.title, "Esc goes back")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	# Palettes: a locked one refuses, an unlocked one equips.
	flow.title.selected = 1
	await _key(KEY_ENTER)
	check(flow.current == flow.palettes, "Palettes opens")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	await _shot("09-palettes")
	flow.palettes.selected = flow.palettes.items().find("hotwire")
	await _key(KEY_ENTER)
	check(flow.settings.palette_id == "root-access", "a locked palette can't be equipped")
	flow.palettes.selected = flow.palettes.items().find("plaintext")
	await _key(KEY_ENTER)
	check(flow.settings.palette_id == "plaintext", "Plaintext is always unlocked")
	await _key(KEY_ESCAPE)
	check(flow.current == flow.title and flow.profile.unseen.is_empty(), "leaving marks new palettes as seen")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	# Rivals: both boards.
	flow.title.selected = 2
	await _key(KEY_ENTER)
	check(flow.current == flow.rivals, "Rivals opens")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	await _key(KEY_RIGHT)
	check(flow.rivals.tab == 1, "the Ghost board")
	await _shot("10-rivals-ghost")
	await _key(KEY_ESCAPE)
	check(flow.current == flow.title, "Esc goes back")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)


func _ghost() -> void:
	flow.title.selected = 0
	await _key(KEY_ENTER)
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	check(flow.current == gv and gv.mode == GameState.Mode.GHOST, "the mode picker starts a Ghost run")
	check(flow.settings.mode == "ghost", "and remembers it")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	gv.clock_paused = true
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
	await _shot("07-ghost")
	var tiles_before := flow.profile.total_tiles
	await _key(KEY_E, true)
	check(gv.over and _gs().ended, "Ctrl+E ends a Ghost run")
	await _frames(2)
	check(flow.current == flow.over and bool(flow.over.summary.ended), "a banked Ghost run goes straight to game over")
	check(flow.profile.ghost.size() == 1 and flow.profile.runs == 1, "it goes on the Ghost board only")
	check(flow.profile.total_tiles == tiles_before, "and adds nothing to the Arcade stats")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)
	await _shot("08-ghost-banked")
	await _key(KEY_ESCAPE)
	check(flow.current == flow.title, "Esc on game over goes to the title")
	await _advance(Motion.MOSH_TOTAL_MS + 40.0)


func _hidden_mine() -> Vector2i:
	var gs := _gs()
	for p: Vector2i in gs.solver.num:
		for d in Board.NB:
			var q := p + d
			if gs.board.state_at(q) == Board.HIDDEN and gs.board.is_mine(q) and not gs.board.is_flagged(q):
				return q
	return Vector2i.ZERO

