extends TestCase
## The builds (milestone 5): three export presets that ship only the game, the
## icon wired into the project and every preset, the startup color, and one
## version everywhere. tools/build.py checks the built archives themselves.

const BUNDLE_ID := "io.github.jwelch00.cybersweeper"


## {preset name: {platform, include, exclude, options}} from export_presets.cfg.
func _presets() -> Dictionary:
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg loads")
	var out := {}
	for sec in cfg.get_sections():
		if sec.ends_with(".options"):
			continue
		var opts := {}
		for k in cfg.get_section_keys(sec + ".options"):
			opts[k] = cfg.get_value(sec + ".options", k)
		out[cfg.get_value(sec, "name")] = {"platform": cfg.get_value(sec, "platform"),
			"include": cfg.get_value(sec, "include_filter"), "exclude": cfg.get_value(sec, "exclude_filter"), "options": opts}
	return out


func _scripts(dir: String, out: Array[String]) -> Array[String]:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	return out


func test_three_presets_ship_only_the_game() -> void:
	var p := _presets()
	eq(p.keys(), ["Windows", "macOS", "Linux"])
	eq([p.Windows.platform, p.macOS.platform, p.Linux.platform], ["Windows Desktop", "macOS", "Linux"])
	for name in p:
		var ex := Array(String(p[name].exclude).split(",")).map(func(s): return s.strip_edges())
		for d in ["tests/*", "sim/*", "dev/*"]:
			check(ex.has(d), "%s leaves out %s" % [name, d])
	for name in ["Windows", "Linux"]:
		var o: Dictionary = p[name].options
		eq(o["binary_format/architecture"], "x86_64", name)
		check(o["binary_format/embed_pck"], "%s carries the game data inside the program" % name)
	var mac: Dictionary = p.macOS.options
	eq(mac["binary_format/architecture"], "universal", "one Mac build for Intel and Apple silicon")
	eq(mac["codesign/codesign"], 1, "Godot's built-in ad-hoc signing, so Apple silicon will run it")
	eq(mac["notarization/notarization"], 0)
	eq(mac["application/bundle_identifier"], BUNDLE_ID)
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc"),
		"universal Mac builds need ETC2/ASTC textures")


func test_one_version_everywhere() -> void:
	eq(ProjectSettings.get_setting("application/config/version"), CsVersion.GAME, "project.godot and core/version.gd")
	var p := _presets()
	for k in ["application/file_version", "application/product_version"]:
		eq(p.Windows.options[k], "", "Windows %s is left empty, so it comes from the project version" % k)
	for k in ["application/short_version", "application/version"]:
		eq(p.macOS.options[k], "", "Mac %s is left empty, so it comes from the project version" % k)


## The presets leave tests/, sim/ and dev/ out, so the game must never need them.
func test_the_game_never_loads_what_the_builds_leave_out() -> void:
	check(FileAccess.file_exists("res://dev/shots.gd"), "the screenshot code lives in dev/")
	for path in _scripts("res://core", _scripts("res://ui", [] as Array[String])):
		var src := FileAccess.get_file_as_string(path)
		for d in ["res://tests", "res://sim"]:
			check(not src.contains(d), "%s doesn't load from %s" % [path, d])
		if path != "res://ui/main.gd":
			check(not src.contains("res://dev"), "%s doesn't load from res://dev" % path)
	for cls in ["TestCase", "Brute", "Fixture", "MiniBoard"]:
		for path in _scripts("res://core", _scripts("res://ui", [] as Array[String])):
			check(not FileAccess.get_file_as_string(path).contains(cls + "."), "%s doesn't use the test class %s" % [path, cls])


func test_the_icon_is_wired_everywhere() -> void:
	var p := _presets()
	var want := {
		"application/config/icon": "res://assets/icon/icon-256.png",
		"application/config/windows_native_icon": "res://assets/icon/icon.ico",
		"application/config/macos_native_icon": "res://assets/icon/icon.icns",
	}
	for k in want:
		eq(ProjectSettings.get_setting(k), want[k], k)
	eq(p.Windows.options["application/icon"], "res://assets/icon/icon.ico", "the icon inside the exe")
	check(p.Windows.options["application/modify_resources"], "the exe gets its icon and version info")
	eq(p.macOS.options["application/icon"], "res://assets/icon/icon.icns", "the Mac app's icon")
	check(String(p.Windows.include).contains("assets/icon/icon.ico"), "the window icon ships in the Windows game data")
	check(String(p.macOS.include).contains("assets/icon/icon.icns"), "the Dock icon ships in the Mac game data")
	for f in ["icon.ico", "icon.icns", "icon-256.png"]:
		check(FileAccess.file_exists("res://assets/icon/" + f), f + " is in the game")
	var design := ProjectSettings.globalize_path("res://").path_join("../design/icon/")
	if not DirAccess.dir_exists_absolute(design):
		return   # exported builds have no design/ folder
	for pair in [["icon.ico", "icon.ico"], ["icon.icns", "icon.icns"], ["png/icon-256.png", "icon-256.png"]]:
		var a := FileAccess.get_file_as_bytes(design + pair[0])
		var b := FileAccess.get_file_as_bytes("res://assets/icon/" + pair[1])
		check(a.size() > 0 and a == b, "game/assets/icon/%s differs from design/ (run tools/sync_design.py)" % pair[1])


func test_startup_shows_the_void_not_the_godot_logo() -> void:
	eq(ProjectSettings.get_setting("application/boot_splash/show_image"), false, "no Godot logo before the boot breach")
	var c: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	var v := Palette.by_id("signal").c("void")
	check(c.is_equal_approx(v), "the startup color %s is Signal's void %s" % [c.to_html(false), v.to_html(false)])
