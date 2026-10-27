extends Node
## Development only: renders one screenshot (or the cell gallery) and quits,
## for tools/shots.py. main.gd loads this by path for --shot or --gallery,
## which only debug builds honor, and release exports leave dev/ out, so the
## game never ships it. It reaches into the screens' internals on purpose
## (the HUD's corrupted labels, screen tears, the boot clock), so the game
## classes don't grow screenshot-only methods.
##
## --shot takes --screen game (the default), boot (--bootseed, --breach,
## --at-ms or --at denial | accept | card, --card-ms, --jackedoff), title,
## modes, pause, settings, palettes, rivals (--tab ghost, --beaten id,id), over
## (--sample rival | unlock | rematch | ghost), or mosh (--mosh-ms into a
## title -> game over datamosh). Menus show a sample profile; main.gd points
## saves at a scratch folder in this mode.
##
## A game shot plays a seeded bot run synchronously and frames it: seed, bot,
## turns, zoom, palette, mode, center "x,y", hover "auto" | "none", pop,
## signal (shown fraction), links, score, hit (a fresh mine hit at ms into
## it), cascade (ms into a fresh cascade), at-ms, tear, frames.

var flow: ScreenFlow
var gv: GameView


func run(args: Dictionary) -> void:
	gv = flow.game
	flow.pause_on_focus_loss = false
	if not gv.atlas.is_built:
		await gv.atlas.built
	if args.has("gallery"):
		flow._show(gv)
		await _gallery(args)
		return
	if args.has("palette"):
		flow.apply_palette(Palette.by_id(args.palette))
	var screen: String = args.get("screen", "game")
	if screen == "game":
		flow._show(gv)
		await _game_shot(args)
		return
	_sample_profile()
	flow.fx.freeze = true
	match screen:
		"boot":
			var boot := flow.boot
			boot.begin(int(args.get("bootseed", "7")), args.get("breach", ""), 1 if args.has("jackedoff") else 0)
			flow._show(boot)
			var at := float(args.get("at-ms", "0"))
			match args.get("at", ""):
				"denial":
					var d: Dictionary = boot.plan.segs[1] if boot.plan.segs.size() > 1 else boot.plan.segs[0]
					at = boot.loader_at() + d.t0 + (d.t1 - d.t0) * 0.55
				"accept":
					at = boot.accept_at() + 60.0
				"card":
					at = boot.card_at()
			flow.fx.clock_ms = boot._start + at
			await _frames(8)
			if args.get("at", "") == "card":
				flow.fx.clock_ms += float(args.get("card-ms", "260"))
				await _frames(3)
		"title":
			flow._show(flow.title)
			await _title_ready()
		"modes":
			flow._show(flow.modes)
		"pause":
			_prepare(args)
			flow._show(gv)
			await _frames(6)
			flow._on_pause()
		"settings":
			flow._show(flow.settings_screen)
			flow.settings_screen.selected = 3
		"palettes":
			flow.palettes.selected = 1
			flow._show(flow.palettes)
		"rivals":
			flow.rivals.tab = 1 if args.get("tab", "") == "ghost" else 0
			if args.has("beaten"):
				flow.profile.beaten.assign(String(args.beaten).split(","))
			flow._show(flow.rivals)
		"over":
			_show_sample_over(args)
			flow._show(flow.over)
		"mosh":
			_show_sample_over(args)
			flow._show(flow.title)
			await _title_ready()
			await _frames(4)
			flow.go(flow.over)
			flow.fx.clock_ms += float(args.get("mosh-ms", "120"))
	await _frames(4)
	_save(get_viewport().get_texture().get_image(), args.shot)
	get_tree().quit()


func _save(img: Image, path: String) -> void:
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _title_ready() -> void:
	for i in 900:
		if flow.title.lattice.on:
			break
		await get_tree().process_frame


# --- menus ----------------------------------------------------------------------

## A profile part way through, like design/png/palettes.png: Hotwire just
## unlocked, 7,812 tiles, best depth 87, best run 2,293.
func _sample_profile() -> void:
	var p := flow.profile
	p.runs = 14
	p.total_tiles = 7812
	p.best_depth = 87
	p.best_score = 2293
	p.unlocked.assign(["hotwire"])
	p.unseen.assign(["hotwire"])
	p.beaten.assign(["rookie", "runner"])
	p.arcade.clear()
	for sc in [2293, 1734, 1510, 1388, 960]:
		p.arcade.append({"score": sc, "tiles": sc * 4 / 5, "depth": sc / 20, "ms": sc * 300, "date": "2026-10-26", "seed": sc})
	p.ghost.clear()
	for sc in [5120, 3302, 2410]:
		p.ghost.append({"score": sc, "tiles": sc * 4 / 5, "depth": sc / 18, "ms": sc * 900, "date": "2026-10-26", "seed": sc})


## The game over from design/png/game-over-signal.png (--sample rival), one
## that also unlocks a palette (unlock), a run just under VESPER after beating
## her once (rematch), or a banked Ghost run (ghost).
func _show_sample_over(args: Dictionary) -> void:
	var kind: String = args.get("sample", "rival")
	var tally := [0, 617, 395, 173, 60, 18, 5, 1, 0]
	var s := {"score": 2293, "depth": 212, "elapsed_ms": 702000, "tiles": 1866, "ended": false, "seed": 7,
		"mode": GameState.Mode.ARCADE, "tally": tally, "flags_correct": 0.96, "cause": "mine"}
	var p := Profile.new()
	for sc in [1734, 1510]:
		p.arcade.append({"score": sc, "tiles": 1000, "depth": 80, "ms": 400000, "date": "2026-10-25", "seed": sc})
	p.best_score = 1734
	if kind == "rival":
		p.unlocked.append("rustbelt")   # the mockup's run unlocks nothing
	if kind == "unlock":
		s.score = 3712
		s.tally = [0, 912, 610, 280, 101, 24, 5, 1, 0]
	elif kind == "rematch":
		p.record({"score": 5911, "tiles": 4700, "depth": 330, "elapsed_ms": 1500000, "seed": 3, "cause": "signal",
			"date": "2026-10-25"})
		s.score = 5512
		s.tally = [0, 1290, 905, 412, 160, 38, 9, 2, 0]
	elif kind == "ghost":
		s.mode = GameState.Mode.GHOST
		s.ended = true
		s.cause = "ended"
		for sc in [5120, 3302]:
			p.ghost.append({"score": sc, "tiles": 4000, "depth": 280, "ms": 4000000, "date": "2026-10-25", "seed": sc})
	s["date"] = "2026-10-26"
	var report := p.record(s)
	flow.over.show_run(s, report, p)


# --- the board ------------------------------------------------------------------

func _game_shot(args: Dictionary) -> void:
	_prepare(args)
	for i in int(args.get("frames", "6")):
		await RenderingServer.frame_post_draw
	gv.set_process(false)
	_effects_frozen(args)
	gv.board.hover_on = args.get("hover", "auto") != "none"
	await _frames(2)
	_save(get_viewport().get_texture().get_image(), args.shot)
	gv.session.close()
	get_tree().quit()


## Sets up a seeded bot run, framed and frozen.
func _prepare(args: Dictionary) -> void:
	var board := gv.board
	var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
	gv.session = Session.new(int(args.get("seed", "7")), gv.rules, false, m)
	gv.mode = m
	gv.hud.mode = m
	gv.clock_paused = true
	board.clock_ms = 20000.0   # so "ms ago" timestamps below stay positive
	gv.session.bot(args.get("bot", "netrunner"), int(args.get("turns", "400")), Vector2i.ZERO)
	for r in gv.session.poll():
		gv._apply(r)
	board.cam.zoom = float(args.get("zoom", "1.0"))
	if args.has("center"):
		var xy: PackedStringArray = args.center.split(",")
		board.cam.center = Vector2(float(xy[0]), float(xy[1])) + Vector2(0.5, 0.5)
	else:
		board.cam.center = Vector2(gv.state.get("last", gv.origin)) + Vector2(0.5, 0.5)
	gv.cursor.show = false
	if args.has("signal"):
		gv.state["signal_shown"] = float(args.signal)
	if args.has("links"):
		gv.state["links"] = int(args.links)
		gv._links = int(args.links)
		gv.hud.lost_at = [-1e9, -1e9, -1e9]
	if args.has("score"):
		gv.state["score"] = int(args.score)
	gv.hud.state = gv.state
	if args.get("hover", "auto") == "auto":
		_auto_hover()
	if args.has("pop"):
		var c := board.cam.cell_at(board.cam.view_size * 0.5)
		gv.popups.add("+3", c, gv.palette.number(3))
	board.freeze = true
	gv.fx.freeze = true
	if args.has("hit"):
		var c := _frontier_cell()
		board.set_cell(c, BoardView.HIT, 0, board.clock_ms - float(args.hit))
	if args.has("cascade"):
		_fake_cascade(float(args.cascade))


## Applies strain and the alarm as they look at the pinned clock.
func _effects_frozen(args: Dictionary) -> void:
	var hud := gv.hud
	var fx := gv.fx
	var rules := gv.rules
	var now := float(args.get("at-ms", "0"))
	gv.board.clock_ms = maxf(gv.board.clock_ms, 0.0)
	var shown := float(gv.state.get("signal_shown", 1.0))
	gv.strain = Strain.level(int(gv.state.get("links", 3)), shown, gv.mode, true)
	hud.strain = gv.strain
	hud.low_signal = shown < rules.low_fraction
	fx.strain_level = gv.strain
	fx.strain_a = Strain.pulse(gv.strain, now, false)
	fx.scan_boost = 1.0 if gv.strain >= 2 else (0.6 if hud.low_signal else 0.0)
	var alarm := 0.0
	if hud.low_signal and gv.strain == 0:
		alarm = Hud.alarm_level(shown, now, rules.low_fraction, rules.critical_fraction, false)
	(gv.vignette.material as ShaderMaterial).set_shader_parameter("alarm", alarm)
	if not args.has("tear"):
		fx._tears.clear()
	if gv.strain > 0:
		# Show a label mid-corruption, like the mockup.
		hud._process(0.0)
		for id in ["drain", "rival", "position", "depth", "density", "time"]:
			if hud._seen.has(id):
				hud._corrupt[id] = [Strain.corrupt(hud._seen[id], gv._rng), 1e12]
	hud.refresh()


## A hidden cell next to the open area, near the middle of the view.
func _frontier_cell() -> Vector2i:
	_auto_hover()
	return gv.board.hover


## A fresh cascade, frozen ms into its ring wave: a disc of zeros around the
## view centre, revealed ring by ring with afterimages.
func _fake_cascade(ms: float) -> void:
	var board := gv.board
	var mid := board.cam.cell_at(board.cam.view_size * 0.5) + Vector2i(8, -2)
	var now := board.clock_ms - ms
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := mid + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > 6.2:
				continue
			var at := now + gv.ring_delay(c, mid, false)
			board.set_cell(c, BoardView.OPEN, 1 if Vector2(dx, dy).length() > 5.4 else 0, at)
			gv.afterimages.spawn(c, at, mid)


## Hovers the hidden frontier cell nearest the centre of the view.
func _auto_hover() -> void:
	var board := gv.board
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


# --- the cell gallery -----------------------------------------------------------

## Every cell state in a row (like design/png/components.png), for each
## palette, composited into one image per zoom: <gallery>-1x.png and
## <gallery>-0.5x.png.
func _gallery(args: Dictionary) -> void:
	var board := gv.board
	gv.cursor.show = false
	gv.hud.visible = false
	gv.vignette.visible = false
	board.freeze = true
	board.clock_ms = 20000.0
	gv.set_process(false)
	for z in [1.0, 0.5]:
		var strips: Array[Image] = []
		for pal in Palette.load_all():
			gv.apply_palette(pal)
			board.clear()
			board.cam.zoom = z
			board.cam.center = Vector2(15.5, 1.5)
			_gallery_cells()
			await _frames(3)
			var img := get_viewport().get_texture().get_image()
			var a := board.cam.world_to_screen(Vector2(-1, -1))
			var b := board.cam.world_to_screen(Vector2(33, 4.5))
			strips.append(img.get_region(Rect2i(Vector2i(a), Vector2i(b - a))))
		var w := strips[0].get_width()
		var h := strips[0].get_height()
		var out := Image.create(w, h * strips.size(), false, strips[0].get_format())
		for i in strips.size():
			out.blit_rect(strips[i], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(0, h * i))
		_save(out, String(args.gallery).get_basename() + "-%sx.png" % ("1" if z == 1.0 else "0.5"))
	get_tree().quit()


func _gallery_cells() -> void:
	var board := gv.board
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
