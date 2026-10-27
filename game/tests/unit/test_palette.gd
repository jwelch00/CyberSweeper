extends TestCase


func test_all_six_palettes_load_with_every_role() -> void:
	var all := Palette.load_all()
	eq(all.map(func(p): return p.id), ["signal", "hotwire", "root-access", "rustbelt", "icebreaker", "plaintext"])
	eq(all.filter(func(p): return p.accessibility).map(func(p): return p.id), ["plaintext"],
		"Plaintext is the colorblind-safe palette")
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


## Plaintext's numbers 1-4 stay clearly apart under protanopia, deuteranopia
## and tritanopia (Machado et al. 2009, full severity, in linear RGB), by at
## least 20 in CIE76 Lab distance.
func test_plaintext_numbers_survive_color_blindness() -> void:
	var sims := {
		"protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
		"deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
		"tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
	}
	var p := Palette.by_id("plaintext")
	for name in sims:
		var m: Array = sims[name]
		var labs: Array[Vector3] = []
		for n in range(1, 5):
			var c := p.number(n)
			var v := [_lin(c.r), _lin(c.g), _lin(c.b)]
			var s := Vector3()
			for row in 3:
				s[row] = clampf(m[row][0] * v[0] + m[row][1] * v[1] + m[row][2] * v[2], 0.0, 1.0)
			labs.append(_lab(s))
		for a in 4:
			for b in range(a + 1, 4):
				var d := labs[a].distance_to(labs[b])
				check(d >= 20.0, "%s: numbers %d and %d are %.1f apart" % [name, a + 1, b + 1, d])


static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _lab(rgb: Vector3) -> Vector3:
	var x := (0.4124 * rgb.x + 0.3576 * rgb.y + 0.1805 * rgb.z) / 0.95047
	var y := 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
	var z := (0.0193 * rgb.x + 0.1192 * rgb.y + 0.9505 * rgb.z) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
