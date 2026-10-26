class_name GameView
extends Control
## The gameplay screen. Owns the Session (game on a worker thread), the board
## and its lattice, afterimages, HUD, popups and cursor, turns input into
## moves and results into visuals and motion (design/MOTION.md). Everything it
## shows comes from Session results; it never reads the GameState.

signal run_over(summary: Dictionary)

const DRAG_PX := 4.0
const PAN_PX_PER_SEC := 900.0

var settings := GameSettings.new()
var rules := Rules.load_default()
var palette: Palette
var mode: GameState.Mode = GameState.Mode.ARCADE
var session: Session
var state := {}
var origin := Vector2i.ZERO
var started := false
var over := false
## Stops run time (no ticks are sent). Milestone 4's pause screen uses it; tests
## use it so waiting on results is deterministic.
var clock_paused := false
## Screen effects (post, title cards, datamosh). ScreenFlow passes its own;
## standing alone, the view makes one.
var fx: ScreenFx
## Best score this session in this mode, for the NEW BEST card (0 = none yet).
## Milestone 4's save data makes it the real personal best.
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	var rv: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rivals.json"))
	_rivals = rv.rivals if rv is Dictionary else []
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
	session = Session.new(seed, rules, true, mode)
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
		_tick_acc += delta * 1000.0
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
	for c in pm.get("mines", []):
		board.set_cell(c, BoardView.MINE_SHOWN, 0, -1.0, false)
	for c in pm.get("wrong_flags", []):
		board.set_cell(c, BoardView.WRONG_FLAG, 0, -1.0, false)
	sfx.play("end")
	run_over.emit(summary())


func summary() -> Dictionary:
	return {"score": int(state.get("score", 0)), "depth": int(state.get("deepest", 0)),
		"elapsed_ms": int(state.get("elapsed_ms", 0)), "tiles": int(state.get("tiles", 0)),
		"ended": bool(state.get("ended", false)), "mode": mode, "seed": int(state.get("seed", 0)),
		"best_before": best_before}


# --- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
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
		KEY_F8:
			# Dev key until the mode picker (milestone 4): switch mode, new run.
			new_run(-1, GameState.Mode.GHOST if mode == GameState.Mode.ARCADE else GameState.Mode.ARCADE)
		KEY_E:
			# Ghost mode's End run (milestone 4 moves it into the pause menu).
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


# --- screenshots ----------------------------------------------------------------

## Plays a seeded bot run synchronously, frames it and saves a PNG, then quits.
## Options: shot (path), seed, bot, turns, zoom, palette, mode, center "x,y",
## hover "x,y" or "auto", pop, signal (shown fraction), links, hit (a fresh
## mine hit at ms into it), cascade (ms into a fresh cascade).
func screenshot(args: Dictionary) -> void:
	if not atlas.is_built:
		await atlas.built
	if args.has("palette"):
		apply_palette(Palette.by_id(args.palette))
	var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
	session = Session.new(int(args.get("seed", "7")), rules, false, m)
	mode = m
	hud.mode = m
	clock_paused = true
	board.clock_ms = 20000.0   # so "ms ago" timestamps below stay positive
	session.bot(args.get("bot", "netrunner"), int(args.get("turns", "400")), Vector2i.ZERO)
	for r in session.poll():
		_apply(r)
	board.cam.zoom = float(args.get("zoom", "1.0"))
	if args.has("center"):
		var xy: PackedStringArray = args.center.split(",")
		board.cam.center = Vector2(float(xy[0]), float(xy[1])) + Vector2(0.5, 0.5)
	else:
		board.cam.center = Vector2(state.get("last", origin)) + Vector2(0.5, 0.5)
	cursor.show = false
	if args.has("signal"):
		state["signal_shown"] = float(args.signal)
	if args.has("links"):
		state["links"] = int(args.links)
		_links = int(args.links)
		hud.lost_at = [-1e9, -1e9, -1e9]
	if args.has("score"):
		state["score"] = int(args.score)
	hud.state = state
	if args.get("hover", "auto") == "auto":
		_auto_hover()
	if args.has("pop"):
		var c := board.cam.cell_at(board.cam.view_size * 0.5)
		popups.add("+3", c, palette.number(3))
	board.freeze = true
	fx.freeze = true
	if args.has("hit"):
		var c := _frontier_cell()
		board.set_cell(c, BoardView.HIT, 0, board.clock_ms - float(args.hit))
	if args.has("cascade"):
		_fake_cascade(float(args.cascade))
	for i in int(args.get("frames", "6")):
		await RenderingServer.frame_post_draw
	set_process(false)
	_update_effects_frozen(args)
	board.hover_on = args.get("hover", "auto") != "none"
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.shot)
	print("saved ", args.shot, " ", img.get_size())
	session.close()
	get_tree().quit()


## Applies strain and the alarm as they look at the pinned clock.
func _update_effects_frozen(args: Dictionary) -> void:
	var now := float(args.get("at-ms", "0"))
	board.clock_ms = maxf(board.clock_ms, 0.0)
	var shown := float(state.get("signal_shown", 1.0))
	strain = Strain.level(int(state.get("links", 3)), shown, mode, true)
	hud.strain = strain
	hud.low_signal = shown < rules.low_fraction
	fx.strain_level = strain
	fx.strain_a = Strain.pulse(strain, now, false)
	fx.scan_boost = 1.0 if strain >= 2 else (0.6 if hud.low_signal else 0.0)
	var alarm := 0.0
	if hud.low_signal and strain == 0:
		alarm = Hud.alarm_level(shown, now, rules.low_fraction, rules.critical_fraction, false)
	(vignette.material as ShaderMaterial).set_shader_parameter("alarm", alarm)
	if not args.has("tear"):
		fx._tears.clear()
	if strain > 0:
		# Show a label mid-corruption, like the mockup.
		hud._process(0.0)
		for id in ["drain", "rival", "position", "depth", "density", "time"]:
			if hud._seen.has(id):
				hud._corrupt[id] = [Strain.corrupt(hud._seen[id], _rng), 1e12]
	hud.refresh()


## A hidden cell next to the open area, near the middle of the view.
func _frontier_cell() -> Vector2i:
	_auto_hover()
	return board.hover


## A fresh cascade, frozen ms into its ring wave: a disc of zeros around the
## view centre, revealed ring by ring with afterimages.
func _fake_cascade(ms: float) -> void:
	var mid := board.cam.cell_at(board.cam.view_size * 0.5) + Vector2i(8, -2)
	var now := board.clock_ms - ms
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := mid + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > 6.2:
				continue
			var at := now + ring_delay(c, mid, false)
			board.set_cell(c, BoardView.OPEN, 1 if Vector2(dx, dy).length() > 5.4 else 0, at)
			afterimages.spawn(c, at, mid)


## Hovers the hidden frontier cell nearest the centre of the view.
func _auto_hover() -> void:
	var mid := board.cam.cell_at(board.cam.view_size * 0.5)
	var best := mid
	var best_d := 1 << 30
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := mid + Vector2i(dx, dy)
			if board.cell(c)[0] != BoardView.HIDDEN:
				continue
			var near := false
			for d in Board.NB:
				if board.is_open(c + d):
					near = true
					break
			if near and dx * dx + dy * dy < best_d:
				best = c
				best_d = dx * dx + dy * dy
	board.hover = best


## Every cell state in a row (like design/png/components.png), for each
## palette, composited into one image per zoom: <shot>-1x.png and <shot>-0.5x.png.
func gallery(args: Dictionary) -> void:
	if not atlas.is_built:
		await atlas.built
	cursor.show = false
	hud.visible = false
	vignette.visible = false
	board.freeze = true
	board.clock_ms = 20000.0
	set_process(false)
	for z in [1.0, 0.5]:
		var strips: Array[Image] = []
		for pal in Palette.load_all():
			apply_palette(pal)
			board.clear()
			board.cam.zoom = z
			board.cam.center = Vector2(15.5, 1.5)
			_gallery_cells()
			for i in 3:
				await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var a := board.cam.world_to_screen(Vector2(-1, -1))
			var b := board.cam.world_to_screen(Vector2(33, 4.5))
			strips.append(img.get_region(Rect2i(Vector2i(a), Vector2i(b - a))))
		var w := strips[0].get_width()
		var h := strips[0].get_height()
		var out := Image.create(w, h * strips.size(), false, strips[0].get_format())
		for i in strips.size():
			out.blit_rect(strips[i], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(0, h * i))
		var path: String = args.gallery.get_basename() + "-%sx.png" % ("1" if z == 1.0 else "0.5")
		out.save_png(path)
		print("saved ", path, " ", out.get_size())
	get_tree().quit()


func _gallery_cells() -> void:
	var y := 0
	board.hover = Vector2i(2, y)
	board.hover_on = true
	board.set_cell(Vector2i(4, y), BoardView.OPEN, 0, -1.0, false)
	for n in range(1, 9):
		board.set_cell(Vector2i(4 + n * 2, y), BoardView.OPEN, n, -1.0, false)
	board.set_cell(Vector2i(22, y), BoardView.OPEN, 2, board.clock_ms - 160.0, true)   # fresh reveal
	board.set_cell(Vector2i(24, y), BoardView.FLAG, 0, -1.0, false)
	board.set_cell(Vector2i(26, y), BoardView.HIT, 0, -1.0, false)
	board.set_cell(Vector2i(28, y), BoardView.MINE_SHOWN, 0, -1.0, false)
	board.set_cell(Vector2i(30, y), BoardView.WRONG_FLAG, 0, -1.0, false)
	# Second row: a chord preview (a 2 being held) and a little revealed patch.
	board.set_cell(Vector2i(3, 3), BoardView.OPEN, 2, -1.0, false)
	board.chord_center = Vector2i(3, 3)
	board.chord_on = true
	for x in range(8, 14):
		board.set_cell(Vector2i(x, 3), BoardView.OPEN, [1, 2, 3, 0, 1, 1][x - 8], -1.0, false)
	board.set_cell(Vector2i(10, 2), BoardView.OPEN, 1, -1.0, false)
	board.set_cell(Vector2i(14, 3), BoardView.FLAG, 0, -1.0, false)
