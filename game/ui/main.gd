extends Control
## Entry scene. Runs the screen flow from the boot, or with `-- --shot out.png
## ...` renders a screenshot and quits (tools/shots.py). Dev flags:
## --skip-boot, --bootseed N, --breach clean|one|99|double, --jackedoff,
## --reduce-motion, --reduce-flashing, --seed N and --mode ghost (straight
## into a run).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := _parse_args(OS.get_cmdline_user_args())
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
		flow._show(flow.game)
		flow.game.gallery(args)
		return
	if args.has("seed") or args.has("mode"):
		var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
		flow._show(flow.game)
		flow.game.new_run(int(args.get("seed", "-1")), m)
		return
	flow.start(args)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var a := raw[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				out[key] = raw[i + 1]
				i += 1
			else:
				out[key] = "true"
		i += 1
	return out
