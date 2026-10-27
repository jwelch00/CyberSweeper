extends SceneTree
## Development only: writes Godot's license and its third-party notices to one
## text file, for LICENSES/Godot.txt in each download (tools/build.py):
##   godot --headless --path game -s res://dev/licenses.gd -- --out FILE


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var info := Engine.get_version_info()
	var t := PackedStringArray()
	t.append("CyberSweeper is built with the Godot Engine %s (https://godotengine.org)." % info.string)
	t.append("Godot's license, then the third-party components Godot includes and their licenses.")
	t.append("")
	t.append("=== Godot Engine ===")
	t.append("")
	t.append(Engine.get_license_text().strip_edges())
	t.append("")
	t.append("=== Third-party components ===")
	for c in Engine.get_copyright_info():
		t.append("")
		t.append(c.name)
		for part in c.parts:
			for line in part.copyright:
				t.append("  Copyright " + line)
			t.append("  License: " + part.license)
	var texts := Engine.get_license_info()
	var names := texts.keys()
	names.sort()
	for n in names:
		t.append("")
		t.append("=== License: %s ===" % n)
		t.append("")
		t.append(String(texts[n]).strip_edges())
	var f := FileAccess.open(args.get("out", "user://Godot.txt"), FileAccess.WRITE)
	if f == null:
		printerr("can't write ", args.get("out", ""))
		quit(1)
		return
	f.store_string("\n".join(t) + "\n")
	f.close()
	quit()
