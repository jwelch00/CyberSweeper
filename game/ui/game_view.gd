class_name GameView
extends Control
## The gameplay screen. Owns the Session (game on a worker thread), the board,
## HUD, popups, cursor and effects, turns input into moves and results into
## visuals. Everything it shows comes from Session results; it never reads
## the GameState.

const RING_MS := 18.0
const DRAG_PX := 4.0
const PAN_PX_PER_SEC := 900.0
const SHAKE_MS := 250.0
const SHAKE_PX := 8.0
const ABERRATION_MS := 400.0

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

var world: Control
var board: BoardView
var atlas: GlyphAtlas
var popups: PopupLayer
var hud: Hud
var cursor: CursorLayer
var overlay: GameOverOverlay
var sfx: Sfx
var post: ColorRect
var vignette: ColorRect
var fps_label: Label

var _rivals: Array = []
var _press := Vector2.ZERO
var _left_down := false
var _dragging := false
var _tick_acc := 0.0
var _shake_start := -1e9
var _shake_scale := 1.0
var _aberration_start := -1e9
var _rng := RandomNumberGenerator.new()
var _links := 3


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	var rv: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rivals.json"))
	_rivals = rv.rivals if rv is Dictionary else []

	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(world)
	board = BoardView.new()
	world.add_child(board)
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
	world.add_child(hud)
	hud.minimap.view = board
	overlay = GameOverOverlay.new()
	world.add_child(overlay)
	cursor = CursorLayer.new()
	add_child(cursor)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	post = ColorRect.new()
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pm := ShaderMaterial.new()
	pm.shader = load("res://ui/post_fx.gdshader")
	post.material = pm
	layer.add_child(post)
	fps_label = Label.new()
	fps_label.position = Vector2(12, 1040)
	fps_label.visible = false
	layer.add_child(fps_label)

	sfx = Sfx.new()
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
	popups.palette = p
	hud.set_palette(p)
	cursor.palette = p
	overlay.palette = p
	(vignette.material as ShaderMaterial).set_shader_parameter("c_void", p.c("void"))
	var pm := post.material as ShaderMaterial
	pm.set_shader_parameter("c_void", p.c("void"))
	pm.set_shader_parameter("c_ink", p.c("ink"))
	RenderingServer.set_default_clear_color(p.c("void"))
	fps_label.add_theme_color_override("font_color", p.c("inkDim"))


func apply_settings() -> void:
	board.reduced_motion = settings.reduced_motion
	sfx.enabled = settings.sfx
	sfx.volume_db = settings.sfx_volume_db
	fps_label.visible = settings.show_fps
	(post.material as ShaderMaterial).set_shader_parameter("scanlines", 1.0 if settings.scanlines else 0.0)


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
	hud.minimap.clear()
	overlay.visible = false
	started = false
	over = false
	_links = rules.start_links
	hud.lost_at = []
	state = {"seed": session.seed, "links": _links, "signal": 1.0, "score": 0, "tiles": 0, "elapsed_ms": 0,
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
	if fps_label.visible:
		fps_label.text = "%d fps  %.1f ms" % [Engine.get_frames_per_second(), delta * 1000.0]


# --- results -> visuals ---------------------------------------------------------

func _apply(r: Dictionary) -> void:
	var res: MoveResult = r.res
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
	var now := board.clock_ms
	for i in res.revealed.size():
		var c: Vector2i = res.revealed[i]
		var n: int = res.numbers[i]
		if n < 0:
			board.set_cell(c, BoardView.HIT, 0, now)
			hud.minimap.mark(c, 3)
		else:
			board.set_cell(c, BoardView.OPEN, n, now + res.rings[i] * RING_MS)
			hud.minimap.mark(c, 1 if n > 0 else 0)
	var pop := PopupLayer.for_move(res.revealed, res.numbers, palette)
	if not pop.is_empty():
		popups.add(pop[0], res.cell if res.kind == MoveResult.Kind.REVEAL else res.revealed[0], pop[1])
	if not res.hits.is_empty():
		_aberration_start = board.clock_ms
		sfx.play("hit")
	elif res.revealed.size() > 1:
		sfx.play("cascade")
	else:
		sfx.play("reveal", 0.9 + 0.05 * res.numbers[0])


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


func _game_over(pm: Dictionary) -> void:
	for c in pm.get("mines", []):
		board.set_cell(c, BoardView.MINE_SHOWN, 0, -1.0, false)
	for c in pm.get("wrong_flags", []):
		board.set_cell(c, BoardView.WRONG_FLAG, 0, -1.0, false)
	var secs := int(state.get("elapsed_ms", 0)) / 1000
	var depth := int(state.get("deepest", 0))
	var t := "%d:%02d" % [secs / 60, secs % 60]
	if bool(state.get("ended", false)):
		overlay.show_end("Run banked", "Ghost run ended at depth %d after %s." % [depth, t], int(state.score))
	else:
		overlay.show_end("Link severed", "All three links lost at depth %d, %s in." % [depth, t], int(state.score))
	sfx.play("end")


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
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_R:
			if over:
				new_run(-1, mode)
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_F3:
			settings.show_fps = not settings.show_fps
			apply_settings()
		KEY_F2:
			# Dev key until the palettes screen (milestone 4): cycle palettes.
			var all := Palette.load_all()
			var i := all.find(palette)
			apply_palette(all[(i + 1) % all.size()])
		KEY_F6:
			settings.scanlines = not settings.scanlines
			apply_settings()
		KEY_F7:
			settings.reduced_motion = not settings.reduced_motion
			apply_settings()
		KEY_F8:
			# Dev key until the mode picker (milestone 4): switch mode, new run.
			new_run(-1, GameState.Mode.GHOST if mode == GameState.Mode.ARCADE else GameState.Mode.ARCADE)
		KEY_M:
			settings.sfx = not settings.sfx
			apply_settings()
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
	var t := board.clock_ms - _shake_start
	if t < SHAKE_MS:
		var amp := SHAKE_PX * _shake_scale * (1.0 - t / SHAKE_MS)
		world.position = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))
	else:
		world.position = Vector2.ZERO
	var pm := post.material as ShaderMaterial
	var at := board.clock_ms - _aberration_start
	var ab := 0.0
	if at < ABERRATION_MS:
		ab = 6.0 * (1.0 - at / ABERRATION_MS) * (0.5 if settings.reduced_motion else 1.0)
	pm.set_shader_parameter("aberration", ab)
	var low := hud.low_signal and mode == GameState.Mode.ARCADE
	pm.set_shader_parameter("scan_boost", 0.6 if low else 0.0)
	if low:
		sfx.low(board.clock_ms)


# --- screenshots ----------------------------------------------------------------

## Plays a seeded bot run synchronously, frames it and saves a PNG, then quits.
## Options: shot (path), seed, bot, turns, zoom, palette, mode, center "x,y",
## hover "x,y" or "auto", pop.
func screenshot(args: Dictionary) -> void:
	if not atlas.is_built:
		await atlas.built
	if args.has("palette"):
		apply_palette(Palette.by_id(args.palette))
	var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
	session = Session.new(int(args.get("seed", "7")), rules, false, m)
	mode = m
	hud.mode = m
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
	if args.get("hover", "auto") == "auto":
		_auto_hover()
	if args.has("pop"):
		var c := board.cam.cell_at(board.cam.view_size * 0.5)
		popups.add("+3", c, palette.number(3))
	for i in int(args.get("frames", "6")):
		await RenderingServer.frame_post_draw
	set_process(false)
	board.hover_on = args.get("hover", "auto") != "none"
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.shot)
	print("saved ", args.shot, " ", img.get_size())
	session.close()
	get_tree().quit()


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
