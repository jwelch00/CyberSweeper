class_name ScreenFlow
extends Control
## Which screen is up and how they change: boot -> title -> game -> LINK
## SEVERED card -> game over -> a new run (R) or the title (Esc). Every change
## datamoshes (design/MOTION.md 7). Owns the settings, the palette, the shared
## screen effects and the session's best scores.

var settings := GameSettings.new()
var rules := Rules.load_default()
var palette: Palette
var fx: ScreenFx
var boot: BootScreen
var title: TitleScreen
var game: GameView
var over: GameOverScreen
var current: Control
## Best score this session per mode, for NEW BEST (saved for real in milestone 4).
var best := {GameState.Mode.ARCADE: 0, GameState.Mode.GHOST: 0}
var _last_mode: GameState.Mode = GameState.Mode.ARCADE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings.set_reduced_motion(GameSettings.os_reduce_motion())
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
	over = GameOverScreen.new()
	add_child(over)
	boot = BootScreen.new()
	boot.fx = fx
	boot.sfx = game.sfx
	add_child(boot)
	apply_palette(Palette.by_id(settings.palette_id))
	apply_settings()
	game.run_over.connect(_on_run_over)
	boot.finished.connect(func(): go(title))
	title.chosen.connect(_on_title)
	over.chosen.connect(_on_over)
	fx.cards.finished.connect(_on_card_done)
	fx.mosh.done.connect(_on_mosh_done)
	for s in [boot, title, game, over]:
		_set_shown(s, false)
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
	over.palette = p
	over.queue_redraw()
	boot.palette = p
	fx.apply_palette(p)


func apply_settings() -> void:
	game.settings = settings
	game.apply_settings()
	title.board.reduced_motion = settings.reduced_motion


func _set_shown(s: Control, on: bool) -> void:
	s.visible = on
	s.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# The worker keeps going in the background; only the view pauses.


func _show(s: Control) -> void:
	for other in [boot, title, game, over]:
		if other != s:
			_set_shown(other, false)
	_set_shown(s, true)
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
			go(game, func(): _new_run(GameState.Mode.ARCADE))
		"quit":
			get_tree().quit()


func _on_over(id: String) -> void:
	match id:
		"again":
			go(game, func(): _new_run(_last_mode))
		"menu":
			go(title)


func _new_run(m: GameState.Mode) -> void:
	game.new_run(-1, m)
	game.best_before = best[m]


func _on_run_over(s: Dictionary) -> void:
	_last_mode = s.mode
	best[s.mode] = maxi(best[s.mode], int(s.score))
	over.show_run(s)
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
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_F3:
			settings.show_fps = not settings.show_fps
			apply_settings()
		KEY_F2:
			# Dev key until the palettes screen (milestone 4): cycle palettes.
			var all := Palette.load_all()
			apply_palette(all[(all.find(palette) + 1) % all.size()])
		KEY_F6:
			settings.scanlines = not settings.scanlines
			apply_settings()
		KEY_F7:
			settings.set_reduced_motion(not settings.reduced_motion)
			apply_settings()
		KEY_F9:
			settings.reduce_flashing = not settings.reduce_flashing
			apply_settings()
		KEY_M:
			settings.sfx = not settings.sfx
			apply_settings()
		_:
			return
	get_viewport().set_input_as_handled()


# --- screenshots ----------------------------------------------------------------

## Renders one screen and quits (tools/shots.py). --screen game (default, see
## GameView.screenshot), boot (--bootseed, --breach, --at-ms or --at denial |
## accept | card, --card-ms, --jackedoff), title, over, or mosh (--mosh-ms
## into a title -> game over datamosh).
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
			for i in 900:
				if title.lattice.on:
					break
				await get_tree().process_frame
		"over":
			over.show_run({"score": 2293, "depth": 212, "elapsed_ms": 702000, "tiles": 1866, "ended": false, "seed": 7,
				"best_before": 1734, "mode": GameState.Mode.ARCADE})
			_show(over)
		"mosh":
			over.show_run({"score": 2293, "depth": 212, "elapsed_ms": 702000, "tiles": 1866, "ended": false, "seed": 7,
				"best_before": 1734, "mode": GameState.Mode.ARCADE})
			_show(title)
			for i in 900:
				if title.lattice.on:
					break
				await get_tree().process_frame
			await _frames(4)
			go(over)
			fx.clock_ms += float(args.get("mosh-ms", "120"))
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.shot)
	print("saved ", args.shot, " ", img.get_size())
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
