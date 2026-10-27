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
## See _notification.
var pause_on_focus_loss := true


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


## Pauses a run when the game loses focus (alt-tab, a laptop going to sleep),
## so the signal never drains while nobody's looking. Screenshots and the
## smoke test turn it off: a stray focus event there would pause them.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and game != null and game.started:
		_on_pause()


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
