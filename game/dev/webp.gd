extends SceneTree
## Development only: converts a screenshot to the download page's WebP
## (tools/shots.py --site):
##   godot --headless --path game -s res://dev/webp.gd -- --in A.png --out B.webp --width 1600 --quality 0.82


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var img := Image.load_from_file(args.get("in", ""))
	if img == null or img.is_empty():
		printerr("can't read ", args.get("in", ""))
		quit(1)
		return
	var w := int(args.get("width", "1600"))
	if img.get_width() > w:
		img.resize(w, roundi(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var err := img.save_webp(args.get("out", ""), true, float(args.get("quality", "0.82")))
	if err != OK:
		printerr("can't write ", args.get("out", ""), " (error ", err, ")")
		quit(1)
		return
	print("saved ", args.get("out", ""), " ", img.get_size())
	quit()
