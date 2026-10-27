extends Control
## Entry scene. Runs the screen flow from the boot, or with `-- --shot out.png
## ...` renders a screenshot and quits (tools/shots.py). Dev flags (debug
## builds only; a release build keeps just CliArgs.RELEASE):
## --skip-boot, --bootseed N, --breach clean|one|99|double, --jackedoff,
## --reduce-motion, --reduce-flashing, --seed N and --mode ghost (straight
## into a run), --save-dir DIR (use another save folder).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := CliArgs.for_build(CliArgs.parse(OS.get_cmdline_user_args()), OS.is_debug_build())
	# Screenshots and tests never touch a real save.
	if args.has("save-dir"):
		SaveStore.dir = args["save-dir"]
	elif args.has("shot") or args.has("gallery"):
		SaveStore.dir = ProjectSettings.globalize_path("res://").path_join("../test-output/save-shots")
	var flow := ScreenFlow.new()
	add_child(flow)
	if args.has("reduce-motion"):
		flow.settings.set_reduced_motion(true)
	if args.has("reduce-flashing"):
		flow.settings.reduce_flashing = true
	flow.apply_settings()
	if args.has("shot"):
		flow.screenshot(args)
		return
	if args.has("gallery"):
		flow.pause_on_focus_loss = false
		flow._show(flow.game)
		flow.game.gallery(args)
		return
	if args.has("seed") or args.has("mode"):
		var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
		flow._show(flow.game)
		flow.game.new_run(int(args.get("seed", "-1")), m)
		return
	flow.start(args)
