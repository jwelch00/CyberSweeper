class_name ScreenFlow
extends Control
## Which screen is up and how they change: boot -> title -> mode picker ->
## game (pause on Esc) -> LINK SEVERED card -> game over -> a new run or the
## title, plus palettes, rivals and settings from the title (settings from
## pause too). Every change of screen datamoshes (design/MOTION.md 7); pause
## opens and closes instantly. Owns the settings and the profile, and saves
## both whenever they change.

var settings: GameSettings
var profile: Profile
var rules := Rules.load_default()
var palette: Palette
var fx: ScreenFx
var boot: BootScreen
var title: TitleScreen
var modes: ModeScreen
var game: GameView
var pause: PauseScreen
var settings_screen: SettingsScreen
var palettes: PalettesScreen
var rivals: RivalsScreen
var over: GameOverScreen
var current: Control
var _screens: Array[Control] = []
var _last_mode: GameState.Mode = GameState.Mode.ARCADE
## Where Settings goes back to (the title or the pause screen).
var _settings_back: Control
## Where a run that's ending goes: the game over screen, or the title when
## Main menu was picked from pause.
var _after_run := "over"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings = GameSettings.load_saved()
	settings.set_reduced_motion(GameSettings.os_reduce_motion(), false)
	profile = SaveStore.load_profile()
	if not profile.is_unlocked(settings.palette_id):
		settings.palette_id = "signal"
	fx = ScreenFx.new()
	add_child(fx)
	game = GameView.new()
	game.fx = fx
	game.settings = settings
	game.rules = rules
	add_child(game)
	title = TitleScreen.new()
	title.fx = fx
	title.rules = rules
	add_child(title)
	modes = ModeScreen.new()
	modes.profile = profile
	add_child(modes)
	pause = PauseScreen.new()
	add_child(pause)
	settings_screen = SettingsScreen.new()
	settings_screen.settings = settings
	add_child(settings_screen)
	palettes = PalettesScreen.new()
	palettes.profile = profile
	palettes.settings = settings
	add_child(palettes)
	rivals = RivalsScreen.new()
	rivals.profile = profile
	add_child(rivals)
	over = GameOverScreen.new()
	add_child(over)
	boot = BootScreen.new()
	boot.fx = fx
	boot.sfx = game.sfx
	add_child(boot)
	_screens = [boot, title, modes, game, pause, settings_screen, palettes, rivals, over]
	apply_palette(Palette.by_id(settings.palette_id))
	apply_settings()
	game.run_over.connect(_on_run_over)
	game.pause_requested.connect(_on_pause)
	boot.finished.connect(func(): go(title))
	title.chosen.connect(_on_title)
	modes.chosen.connect(_on_mode)
	modes.back.connect(func(): go(title))
	pause.chosen.connect(_on_pause_item)
	pause.back.connect(func(): _on_pause_item("resume"))
	settings_screen.changed.connect(_on_settings_changed)
	settings_screen.back.connect(func(): go(_settings_back))
	palettes.chosen.connect(_on_equip)
	palettes.back.connect(_leave_palettes)
	rivals.back.connect(func(): go(title))
	over.chosen.connect(_on_over)
	fx.cards.finished.connect(_on_card_done)
	fx.mosh.done.connect(_on_mosh_done)
	for sc in _screens:
		_set_shown(sc, false)
	if not game.atlas.is_built:
		await game.atlas.built
	title.start_background(game.atlas)


## Starts from the boot (or the title with skip). Options mirror the motion
## lab: bootseed, breach (clean, one, 99, double), jackedoff.
func start(args := {}) -> void:
	if args.has("skip-boot"):
		_show(title)
		return
	boot.begin(int(args.get("bootseed", "-1")), args.get("breach", ""), 1 if args.has("jackedoff") else -1)
	_show(boot)


func apply_palette(p: Palette) -> void:
	palette = p
	settings.palette_id = p.id
	game.apply_palette(p)
	title.set_palette(p)
	boot.palette = p
	for sc in [modes, pause, settings_screen, palettes, rivals, over]:
		sc.palette = p
		sc.queue_redraw()
	fx.apply_palette(p)


func apply_settings() -> void:
	game.settings = settings
	game.apply_settings()
	title.board.reduced_motion = settings.reduced_motion
	var w := get_window()
	if w != null and DisplayServer.get_name() != "headless":
		var want := Window.MODE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
		if (w.mode == Window.MODE_FULLSCREEN) != settings.fullscreen:
			w.mode = want


func _on_settings_changed() -> void:
	apply_settings()
	settings.save()


func _set_shown(s: Control, on: bool) -> void:
	s.visible = on
	s.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# The worker keeps going in the background; only the view pauses.


func _show(s: Control) -> void:
	for other in _screens:
		if other != s:
			_set_shown(other, false)
	_set_shown(s, true)
	if s == pause:
		# The game stays on screen under the pause panel, frozen and hidden.
		game.visible = true
	current = s
	if s != game:
		fx.calm()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if s == game else Input.MOUSE_MODE_VISIBLE


## Changes screen with a datamosh: grab the frame, switch, let the new screen
## snap in. Keys are held back until it's done.
func go(to: Control, setup := Callable()) -> void:
	fx.mosh.begin()
	if setup.is_valid():
		setup.call()
	_show(to)
	if fx.mosh.active:
		to.set_process_unhandled_key_input(false)


func _on_mosh_done() -> void:
	if current != null:
		current.set_process_unhandled_key_input(true)


func busy() -> bool:
	return fx.mosh.active


func _on_title(id: String) -> void:
	match id:
		"jack_in":
			go(modes, func(): modes.selected = 1 if settings.mode == "ghost" else 0)
		"palettes":
			go(palettes, func(): palettes.open_at_equipped())
		"rivals":
			go(rivals, _open_rivals)
		"settings":
			_settings_back = title
			go(settings_screen, func(): settings_screen.selected = 0)
		"quit":
			get_tree().quit()


func _open_rivals() -> void:
	rivals.tab = 0
	rivals.selected = 0


func _on_mode(id: String) -> void:
	settings.mode = id
	settings.save()
	var m := GameState.Mode.GHOST if id == "ghost" else GameState.Mode.ARCADE
	go(game, func(): _new_run(m))


func _on_pause() -> void:
	if current != game or game.over:
		return
	game.set_paused(true)
	var s := game.state
	pause.mode = game.mode
	pause.info = "score %s   depth %d   %s" % [HudText.thousands(int(s.get("score", 0))), int(s.get("deepest", 0)),
		Deck.clock(int(s.get("elapsed_ms", 0)))]
	pause.selected = 0
	_show(pause)


func _on_pause_item(id: String) -> void:
	match id:
		"resume":
			game.set_paused(false)
			_show(game)
		"settings":
			_settings_back = pause
			go(settings_screen, func(): settings_screen.selected = 0)
		"end":
			game.set_paused(false)
			_show(game)
			_after_run = "over"
			game.end_run()
		"menu":
			_after_run = "title"
			game.set_paused(false)
			if game.started:
				game.end_run()
			else:
				go(title)


func _on_equip(pid: String) -> void:
	if not profile.is_unlocked(pid):
		return
	apply_palette(Palette.by_id(pid))
	settings.save()


func _leave_palettes() -> void:
	for pid in profile.unseen.duplicate():
		profile.mark_seen(pid)
	SaveStore.save_profile(profile)
	go(title)


func _on_over(id: String) -> void:
	if id.begins_with("equip:"):
		_on_equip(id.substr(6))
		profile.mark_seen(id.substr(6))
		SaveStore.save_profile(profile)
		over.queue_redraw()
		return
	match id:
		"again":
			go(game, func(): _new_run(_last_mode))
		"menu":
			go(title)


func _new_run(m: GameState.Mode) -> void:
	_after_run = "over"
	game.new_run(-1, m)
	game.best_before = profile.best(m)


## Records the run once (Arcade into stats, unlocks and rivals; Ghost only on
## its own leaderboard), saves, then LINK SEVERED and the game over screen.
func _on_run_over(s: Dictionary) -> void:
	_last_mode = s.mode
	var run := s.duplicate()
	run["date"] = Time.get_date_string_from_system()
	var report := profile.record(run)
	SaveStore.save_profile(profile)
	over.show_run(s, report, profile)
	if _after_run == "title":
		go(title)
		return
	if bool(s.ended):
		go(over)
		return
	fx.cards.play({"text": "LINK SEVERED", "jp": "切断", "sub": HudText.thousands(int(s.score)), "role": "danger", "full": true,
		"then": "over"})
	game.sfx.play("slam")


func _on_card_done(spec: Dictionary) -> void:
	if spec.get("then", "") == "over" and current == game:
		go(over)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F11:
			settings.fullscreen = not settings.fullscreen
			_on_settings_changed()
		KEY_F3:
			settings.show_fps = not settings.show_fps
			_on_settings_changed()
		KEY_M:
			settings.sfx = not settings.sfx
			_on_settings_changed()
		_:
			return
	get_viewport().set_input_as_handled()


# --- screenshots ----------------------------------------------------------------

## Renders one screen and quits (tools/shots.py). --screen game (default, see
## GameView.screenshot), boot (--bootseed, --breach, --at-ms or --at denial |
## accept | card, --card-ms, --jackedoff), title, modes, pause, settings,
## palettes, rivals (--tab ghost), over (--sample rival | unlock | ghost), or
## mosh (--mosh-ms into a title -> game over datamosh). Menus show a sample
## profile; main.gd points saves at a scratch folder in this mode.
func screenshot(args: Dictionary) -> void:
	if not game.atlas.is_built:
		await game.atlas.built
	if args.has("palette"):
		apply_palette(Palette.by_id(args.palette))
	var screen: String = args.get("screen", "game")
	if screen == "game":
		_show(game)
		game.screenshot(args)
		return
	_sample_profile()
	fx.freeze = true
	match screen:
		"boot":
			boot.begin(int(args.get("bootseed", "7")), args.get("breach", ""), 1 if args.has("jackedoff") else 0)
			_show(boot)
			var at := float(args.get("at-ms", "0"))
			match args.get("at", ""):
				"denial":
					var d: Dictionary = boot.plan.segs[1] if boot.plan.segs.size() > 1 else boot.plan.segs[0]
					at = boot.loader_at() + d.t0 + (d.t1 - d.t0) * 0.55
				"accept":
					at = boot.accept_at() + 60.0
				"card":
					at = boot.card_at()
			fx.clock_ms = boot._start + at
			await _frames(8)
			if args.get("at", "") == "card":
				fx.clock_ms += float(args.get("card-ms", "260"))
				await _frames(3)
		"title":
			_show(title)
			await _title_ready()
		"modes":
			_show(modes)
		"pause":
			game.prepare_shot(args)
			_show(game)
			await _frames(6)
			_on_pause()
		"settings":
			_show(settings_screen)
			settings_screen.selected = 3
		"palettes":
			palettes.selected = 1
			_show(palettes)
		"rivals":
			rivals.tab = 1 if args.get("tab", "") == "ghost" else 0
			_show(rivals)
		"over":
			_show_sample_over(args)
			_show(over)
		"mosh":
			_show_sample_over(args)
			_show(title)
			await _title_ready()
			await _frames(4)
			go(over)
			fx.clock_ms += float(args.get("mosh-ms", "120"))
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.shot)
	print("saved ", args.shot, " ", img.get_size())
	get_tree().quit()


func _title_ready() -> void:
	for i in 900:
		if title.lattice.on:
			break
		await get_tree().process_frame


## A profile part way through, like design/png/palettes.png: Hotwire just
## unlocked, 7,812 tiles, best depth 87, best run 2,293.
func _sample_profile() -> void:
	var p := profile
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
## that also unlocks a palette (unlock), or a banked Ghost run (ghost).
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
	elif kind == "ghost":
		s.mode = GameState.Mode.GHOST
		s.ended = true
		s.cause = "ended"
		for sc in [5120, 3302]:
			p.ghost.append({"score": sc, "tiles": 4000, "depth": 280, "ms": 4000000, "date": "2026-10-25", "seed": sc})
	s["date"] = "2026-10-26"
	var report := p.record(s)
	over.show_run(s, report, p)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
