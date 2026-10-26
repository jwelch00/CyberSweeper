extends TestCase


func test_all_five_palettes_load_with_every_role() -> void:
	var all := Palette.load_all()
	eq(all.map(func(p): return p.id), ["signal", "hotwire", "root-access", "rustbelt", "icebreaker"])
	for p in all:
		for role in Palette.ROLES:
			check(p.colors.has(role), "%s has %s" % [p.id, role])
		eq(p.numbers.size(), 8, p.id)


func test_every_number_clears_contrast_on_its_floor() -> void:
	for p in Palette.load_all():
		for n in range(1, 9):
			var ratio := Palette.contrast(p.number(n), p.c("floor"))
			check(ratio >= 5.7, "%s number %d is %.2f:1 on its floor" % [p.id, n, ratio])


func test_project_copy_matches_design() -> void:
	var design := ProjectSettings.globalize_path("res://").path_join("../design/tokens/palettes.json")
	if not FileAccess.file_exists(design):
		return   # exported builds have no design/ folder
	var a := FileAccess.get_file_as_bytes(design)
	var b := FileAccess.get_file_as_bytes(Palette.PATH)
	check(a == b, "game/assets/tokens/palettes.json differs from design/ (run tools/sync_design.py)")


func test_contrast_math() -> void:
	check(absf(Palette.contrast(Color.BLACK, Color.WHITE) - 21.0) < 0.01, "black on white is 21:1")
	check(absf(Palette.contrast(Color.WHITE, Color.WHITE) - 1.0) < 0.001)
