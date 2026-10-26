extends Control
## Entry scene. Starts a run, or with `-- --shot out.png ...` renders a
## screenshot of a seeded bot run and quits (tools/shots.py).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := _parse_args(OS.get_cmdline_user_args())
	var gv := GameView.new()
	add_child(gv)
	if args.has("shot"):
		gv.screenshot(args)
		return
	if args.has("gallery"):
		gv.gallery(args)
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var m := GameState.Mode.GHOST if args.get("mode", "arcade") == "ghost" else GameState.Mode.ARCADE
	gv.new_run(int(args.get("seed", "-1")), m)


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
