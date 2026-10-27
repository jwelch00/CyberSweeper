class_name GameView
extends Control
## The gameplay screen. Owns the Session (game on a worker thread), the board
## and its lattice, afterimages, HUD, popups and cursor, turns input into
## moves and results into visuals and motion (design/MOTION.md). Everything it
## shows comes from Session results; it never reads the GameState.

signal run_over(summary: Dictionary)
## Esc during a run (ScreenFlow shows the pause screen).
signal pause_requested

const DRAG_PX := 4.0
const PAN_PX_PER_SEC := 900.0
## The most run time one frame may add (see _process).
const MAX_FRAME_MS := 250.0

var settings := GameSettings.new()
var rules := Rules.load_default()
var palette: Palette
var mode: GameState.Mode = GameState.Mode.ARCADE
var session: Session
var state := {}
var origin := Vector2i.ZERO
var started := false
var over := false
## Stops run time (no ticks are sent). The pause screen uses it; tests use it
## so waiting on results is deterministic.
var clock_paused := false
## Screen effects (post, title cards, datamosh). ScreenFlow passes its own;
## standing alone, the view makes one.
var fx: ScreenFx
## The saved best score in this mode, for the NEW BEST card (0 = none yet).
var best_before := 0
## Current strain level (0..2), see Strain.
var strain := 0

var world: Control
var board: BoardView
var lattice: LatticeLayer
var afterimages: AfterimageLayer
var atlas: GlyphAtlas
var popups: PopupLayer
var hud: Hud
var cursor: CursorLayer
var sfx: Sfx
var vignette: ColorRect

var _rivals: Array = []
var _press := Vector2.ZERO
var _left_down := false
var _dragging := false
var _tick_acc := 0.0
var _shake_start := -1e9
var _shake_scale := 1.0
var _rng := RandomNumberGenerator.new()
var _links := 3
var _beaten := {}
var _best_shown := false
var _next_tear := 0.0
var _next_thump := 0.0
var _cause := ""
var _post_mortem := {}
var paused := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_rivals = Profile.rivals()
	if fx == null:
		fx = ScreenFx.new()
		add_child(fx)

	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(world)
	board = BoardView.new()
	world.add_child(board)
	lattice = LatticeLayer.new()
	lattice.view = board
	world.add_child(lattice)
	afterimages = AfterimageLayer.new()
	afterimages.view = board
	world.add_child(afterimages)
	vignette = ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vm := ShaderMaterial.new()
	vm.shader = load("res://ui/vignette.gdshader")
	vignette.material = vm
	popups = PopupLayer.new()
	popups.view = board
	world.add_child(popups)
	hud = Hud.new()
	hud.view = board
	hud.rivals = _rivals
	hud.density_for = func(depth: int) -> float: return rules.density(depth)
	hud.drain_for = _drain_shown
	hud.low_fraction = rules.low_fraction
	hud.critical_fraction = rules.critical_fraction
	world.add_child(hud)
	hud.minimap.view = board
	cursor = CursorLayer.new()
	add_child(cursor)

	sfx = Sfx.new()
	# Shared with the other screens (the boot's sounds), so it keeps playing
	# while this screen is hidden and paused.
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sfx)
	atlas = GlyphAtlas.new()
	add_child(atlas)
	apply_palette(Palette.by_id(settings.palette_id))
	apply_settings()
	await atlas.build()
	board.set_atlas(atlas)


func apply_palette(p: Palette) -> void:
	palette = p
	board.set_palette(p)
	lattice.palette = p
	afterimages.set_palette(p)
	popups.palette = p
	hud.set_palette(p)
	cursor.palette = p
	fx.apply_palette(p)
	(vignette.material as ShaderMaterial).set_shader_parameter("c_void", p.c("void"))
	(vignette.material as ShaderMaterial).set_shader_parameter("c_danger", p.c("danger"))
	RenderingServer.set_default_clear_color(p.c("void"))


func apply_settings() -> void:
	board.reduced_motion = settings.reduced_motion
	hud.reduced_motion = settings.reduced_motion
	fx.reduced_motion = settings.reduced_motion
	fx.guard.reduce_flashing = settings.reduce_flashing
	sfx.enabled = settings.sfx
	sfx.volume_db = settings.sfx_volume_db
	fx.fps_label.visible = settings.show_fps
	fx.set_scanlines(settings.scanlines)


## Starts a fresh run (a random seed unless one is given).
func new_run(seed := -1, p_mode: GameState.Mode = mode) -> void:
	if session != null:
		session.close()
	mode = p_mode
	if seed < 0:
		seed = _rng.randi()
	session = Session.new(seed, rules, true, mode, true)   # a person playing: signal grace on
	board.clear()
	popups.clear()
	afterimages.clear()
	hud.minimap.clear()
	lattice.on = false
	started = false
	over = false
	strain = 0
	_links = rules.start_links
	_beaten = {}
	_best_shown = false
	_cause = ""
	_post_mortem = {}
	set_paused(false)
	hud.lost_at = []
	state = {"seed": session.seed, "links": _links, "signal": 1.0, "signal_shown": 1.0, "score": 0, "tiles": 0,
		"elapsed_ms": 0,
		"mode": mode, "started": false, "over": false}
	hud.state = state
	hud.mode = mode
	_tick_acc = 0.0


func _exit_tree() -> void:
	if session != null:
		session.close()


func _process(delta: float) -> void:
	if session == null:
		return
	for r in session.poll():
		_apply(r)
	cursor.busy_since = (cursor.busy_since if cursor.busy_since >= 0.0 else cursor.clock_ms) if session.busy() else -1.0
	_pan_keys(delta)
	if started and not over and not clock_paused and not session.busy():
		# One long frame (a stall, a laptop waking up) can't drain the signal in one go.
		_tick_acc += minf(delta * 1000.0, MAX_FRAME_MS)
		if _tick_acc >= 1.0:
			var ms := int(_tick_acc)
			_tick_acc -= ms
			session.tick(ms)
	_update_hover()
	_update_effects()
	hud.state = state


## Shown signal (percent) drained per second right now: the real drain rate
## through the false scale's slope, so it matches what the bar does.
func _drain_shown(s: Dictionary) -> float:
	if not bool(s.get("started", false)) or mode == GameState.Mode.GHOST:
		return 0.0
	var f := float(s.get("signal", 1.0))
	var rate := rules.drain_rate(int(s.get("elapsed_ms", 0))) / rules.signal_max
	var c := rules.display_curve
	var slope := 1.0 if c <= 0.0 else c * exp(c * f) / (exp(c) - 1.0)
	return 100.0 * rate * slope


# --- results -> visuals ---------------------------------------------------------

func _apply(r: Dictionary) -> void:
	var res: MoveResult = r.res
	var before := int(state.get("score", 0))
	for k in r.state:
		state[k] = r.state[k]
	match res.kind:
		MoveResult.Kind.REVEAL, MoveResult.Kind.CHORD:
			_show_reveal(res)
		MoveResult.Kind.FLAG:
			if res.flag_on:
				board.set_cell(res.cell, BoardView.FLAG)
				hud.minimap.mark(res.cell, 2)
				sfx.play("flag")
			else:
				board.set_cell(res.cell, BoardView.HIDDEN)
				hud.minimap.unmark(res.cell)
	if r.state.has("cells"):
		_show_all(r.state)
	var links := int(state.get("links", _links))
	if links < _links:
		for i in range(links, _links):
			while hud.lost_at.size() <= i:
				hud.lost_at.append(-1e9)
			hud.lost_at[i] = board.clock_ms
		_shake(1.0)
		_cause = "mine" if not res.hits.is_empty() else "signal"
		if res.hits.is_empty():
			sfx.play("link")
	_links = links
	if not r.state.has("cells"):
		_cards_for(before, int(state.get("score", 0)))
	if bool(state.get("over", false)) and not over:
		over = true
		_game_over(r.state.get("reveal", {}))


func _show_reveal(res: MoveResult) -> void:
	if res.revealed.is_empty():
		return
	if not started:
		started = true
		origin = state.get("origin", Vector2i.ZERO)
		hud.origin = origin
		hud.minimap.origin = origin
		lattice.origin = origin
		lattice.on = true
	var now := board.clock_ms
	var safe := 0
	for n in res.numbers:
		if n >= 0:
			safe += 1
	var trails := safe >= Motion.TRAIL_MIN_CELLS and not settings.reduced_motion
	var budget := AfterimageLayer.CAPACITY / Motion.ECHO_DELAYS.size()
	var last := now
	for i in res.revealed.size():
		var c: Vector2i = res.revealed[i]
		var n: int = res.numbers[i]
		if n < 0:
			board.set_cell(c, BoardView.HIT, 0, now)
			hud.minimap.mark(c, 3)
			continue
		var at := now + ring_delay(c, res.cell, settings.reduced_motion)
		board.set_cell(c, BoardView.OPEN, n, at)
		hud.minimap.mark(c, 1 if n > 0 else 0)
		if trails and budget > 0:
			afterimages.spawn(c, at, res.cell)
			budget -= 1
		last = maxf(last, at)
	if res.hits.is_empty():
		# No popup text on a mine hit, even when a chord also opened numbers.
		var pop := PopupLayer.for_move(res.revealed, res.numbers, palette)
		if not pop.is_empty():
			popups.add(pop[0], res.cell if res.kind == MoveResult.Kind.REVEAL else res.revealed[0], pop[1], last)
		if res.revealed.size() > 1:
			sfx.play("cascade")
		else:
			sfx.play("reveal", 0.9 + 0.05 * res.numbers[0])
	else:
		_mine_hit()


## When a cascade cell reveals: rings by rounded straight-line distance from
## the click, 22 ms apart, so the wavefront is round (instant with reduce motion).
static func ring_delay(c: Vector2i, click: Vector2i, reduced: bool) -> float:
	if reduced:
		return 0.0
	return roundf(Vector2(c - click).length()) * Motion.RING_MS


## The hazard tile slams in on the board; the screen takes the hit: a danger
## flash, three tear lines and the shake (design/MOTION.md 6). The link block
## shatters in the HUD.
func _mine_hit() -> void:
	if fx.guard.allow(fx.clock_ms):
		fx.flash(palette.c("danger"), 0.22, Motion.HIT_FLASH_MS, false)
		fx.tear(3, Motion.HIT_TEAR_MS, 6.0, 40.0, false)
	sfx.play("hit")


## Everything visible at once, settled (screenshots, bots joining).
func _show_all(s: Dictionary) -> void:
	var cells: Array = s.cells
	var numbers: PackedInt32Array = s.numbers
	for i in cells.size():
		var n := numbers[i]
		board.set_cell(cells[i], BoardView.HIT if n < 0 else BoardView.OPEN, maxi(n, 0), -1.0, false)
		hud.minimap.mark(cells[i], 3 if n < 0 else (1 if n > 0 else 0))
	for c in s.flags:
		board.set_cell(c, BoardView.FLAG, 0, -1.0, false)
		hud.minimap.mark(c, 2)
	if bool(s.get("started", false)) and not started:
		started = true
		origin = s.get("origin", Vector2i.ZERO)
		hud.origin = origin
		hud.minimap.origin = origin
		lattice.origin = origin
		lattice.on = true


## RIVAL DOWN the moment the live score passes a rival's (Arcade only, once
## per rival; passing two at once shows one card), NEW BEST once per run when
## it passes the best so far. They queue and never take input.
func _cards_for(before: int, now: int) -> void:
	if now <= before or over:
		return
	for spec in cards_between(before, now):
		fx.cards.play(spec)


func cards_between(before: int, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode == GameState.Mode.ARCADE:
		var passed: Dictionary = {}
		for r in _rivals:
			if before <= int(r.score) and now > int(r.score) and not _beaten.has(r.name):
				_beaten[r.name] = true
				passed = r
		if not passed.is_empty():
			out.append({"text": "RIVAL DOWN", "jp": "撃破", "sub": "%s %s" % [passed.name, HudText.thousands(int(passed.score))],
				"role": "accent"})
	if best_before > 0 and not _best_shown and before <= best_before and now > best_before:
		_best_shown = true
		out.append({"text": "NEW BEST", "jp": "記録更新", "sub": HudText.thousands(now), "role": "accent2"})
	return out


func _game_over(pm: Dictionary) -> void:
	_post_mortem = pm
	for c in pm.get("mines", []):
		board.set_cell(c, BoardView.MINE_SHOWN, 0, -1.0, false)
	for c in pm.get("wrong_flags", []):
		board.set_cell(c, BoardView.WRONG_FLAG, 0, -1.0, false)
	sfx.play("end")
	run_over.emit(summary())


## What the game over screen and the save need. cause: what took the last
## link ("mine", "signal"), or "ended" for an ended run.
func summary() -> Dictionary:
	var ended := bool(state.get("ended", false))
	return {"score": int(state.get("score", 0)), "depth": int(state.get("deepest", 0)),
		"elapsed_ms": int(state.get("elapsed_ms", 0)), "tiles": int(state.get("tiles", 0)),
		"ended": ended, "mode": mode, "seed": int(state.get("seed", 0)), "best_before": best_before,
		"tally": state.get("tally", []), "flags_correct": float(_post_mortem.get("flags_correct", 1.0)),
		"wrong_flags": _post_mortem.get("wrong_flags", []).size(), "cause": "ended" if ended else _cause}


## Pause: run time stops and the board hides behind the cipher, so a pause
## can't be used to plan.
func set_paused(on: bool) -> void:
	paused = on
	clock_paused = on
	board.set_conceal(on)
	lattice.visible = not on
	popups.visible = not on
	afterimages.visible = not on
	cursor.visible = not on
	board.hover_on = false
	board.chord_on = false
	_left_down = false


## Ends the run now (pause's End run / Abandon run); it's recorded like any end.
func end_run() -> void:
	if session != null and started and not over:
		session.end_run()


# --- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if paused:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_dragging = false
					_press = mb.position
					var c := board.cam.cell_at(mb.position)
					if board.is_open(c) and int(board.cell(c)[1]) > 0 and not over:
						board.chord_on = true
						board.chord_center = c
				else:
					if _left_down and not _dragging:
						_click(board.cam.cell_at(mb.position))
					_left_down = false
					_dragging = false
					board.chord_on = false
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_flag(board.cam.cell_at(mb.position))
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					board.cam.zoom_at(mb.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					board.cam.zoom_at(mb.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion and _left_down:
		var mm := event as InputEventMouseMotion
		if not _dragging and mm.position.distance_to(_press) > DRAG_PX:
			_dragging = true
			board.chord_on = false
			board.cam.drag(mm.position - _press)
		elif _dragging:
			board.cam.drag(mm.relative)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	match k.keycode:
		KEY_ESCAPE:
			if not over:
				pause_requested.emit()
				get_viewport().set_input_as_handled()
		KEY_E:
			# Ghost mode's End run, a shortcut for the pause menu's.
			if k.ctrl_pressed and mode == GameState.Mode.GHOST and started and not over:
				session.end_run()


## Left click: chord a revealed number, otherwise decrypt a hidden cell.
func _click(c: Vector2i) -> void:
	if over or session == null:
		return
	var s: Array = board.cell(c)
	if s[0] == BoardView.OPEN:
		if int(s[1]) > 0:
			session.chord(c)
	elif s[0] == BoardView.HIDDEN:
		session.reveal(c)


func _flag(c: Vector2i) -> void:
	if over or not started or session == null:
		return
	if board.is_hidden(c):
		session.flag(c)


func _pan_keys(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		board.cam.drag(-v.normalized() * PAN_PX_PER_SEC * delta)


func _update_hover() -> void:
	var p := get_local_mouse_position()
	var c := board.cam.cell_at(p)
	board.hover = c
	board.hover_on = not over and board.cell(c)[0] == BoardView.HIDDEN and Rect2(Vector2.ZERO, size).has_point(p)


# --- effects ------------------------------------------------------------------

func _shake(scale: float) -> void:
	if settings.reduced_motion:
		return
	_shake_start = board.clock_ms
	_shake_scale = scale


func _update_effects() -> void:
	if not is_visible_in_tree():
		return
	var now := board.clock_ms
	var t := now - _shake_start
	if t < Motion.SHAKE_MS:
		var amp := Motion.SHAKE_PX * _shake_scale * (1.0 - t / Motion.SHAKE_MS)
		world.position = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))
	else:
		world.position = Vector2.ZERO
	var reduced := settings.reduced_motion
	var shown := float(state.get("signal_shown", 1.0))
	strain = Strain.level(int(state.get("links", 3)), shown, mode, started and not over)
	hud.strain = strain
	# Strain 2 jitters the deck, never the board.
	hud.position = Strain.jitter(strain, now, reduced)
	fx.strain_level = strain
	fx.strain_a = Strain.pulse(strain, now, reduced)
	var low := hud.low_signal and mode == GameState.Mode.ARCADE
	fx.scan_boost = 1.0 if strain >= 2 else (0.6 if low else 0.0)
	# Below the low mark and before strain: the faint 1 Hz red edge.
	var alarm := 0.0
	if low and strain == 0:
		alarm = Hud.alarm_level(shown, now, rules.low_fraction, rules.critical_fraction, reduced)
	(vignette.material as ShaderMaterial).set_shader_parameter("alarm", alarm)
	if strain >= 2:
		if not reduced and now >= _next_tear:
			fx.tear(1, Motion.STRAIN_TEAR_MS, 4.0, 26.0)
			_next_tear = now + Motion.TEAR_EVERY_MS
		if now >= _next_thump:
			sfx.play("heartbeat")
			_next_thump = now + 500.0
	elif low:
		sfx.low(now)
