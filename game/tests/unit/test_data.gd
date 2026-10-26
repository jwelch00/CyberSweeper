extends TestCase
## The data files milestone 4 will read: rivals and palette unlocks.


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(d is Dictionary, path + " is a JSON object")
	return d if d is Dictionary else {}


func test_rivals_match_the_bots_and_climb() -> void:
	var rivals: Array = _json("res://data/rivals.json").rivals
	var bots := Bot.load_profiles()
	eq(rivals.size(), 3)
	var last := 0
	for r in rivals:
		check(bots.has(r.id), "rival %s has a bot profile" % r.id)
		eq(r.name, bots[r.id].name, "rival name matches its bot")
		check(float(r.score) == floorf(r.score) and int(r.score) % 10 == 0, "score is a whole multiple of 10")
		check(int(r.score) > last, "rivals climb: rookie < runner < netrunner")
		last = int(r.score)
	eq([rivals[0].id, rivals[1].id, rivals[2].id], ["rookie", "runner", "netrunner"])


func test_unlocks_cover_every_palette() -> void:
	var u: Dictionary = _json("res://data/unlocks.json").palettes
	var rivals := {}
	for r in _json("res://data/rivals.json").rivals:
		rivals[r.id] = true
	eq(u.keys(), ["signal", "hotwire", "root-access", "rustbelt", "icebreaker", "plaintext"])
	check(u.signal == null, "signal is the default")
	check(u.plaintext == null, "Plaintext, the colorblind-safe palette, is always unlocked")
	var ids := Palette.load_all().map(func(p): return p.id)
	eq(u.keys(), ids, "every palette in the tokens has an unlock entry")
	for id in u:
		var c: Variant = u[id]
		if c == null:
			continue
		check(c.has("text") and c.text != "", id + " has text")
		match c.type:
			"beat_rival":
				check(rivals.has(c.rival), id + " names a real rival")
			"total_tiles", "depth":
				check(c.value > 0, id + " has a positive threshold")
			_:
				check(false, id + " has an unknown unlock type " + str(c.type))


func test_rivals_have_their_flavor_text() -> void:
	for r in _json("res://data/rivals.json").rivals:
		for key in ["bio", "taunt", "beaten"]:
			check(r.has(key) and String(r[key]).strip_edges() != "", "%s has %s" % [r.id, key])
		if r.id == "netrunner":
			check(r.has("bio_after_beaten") and r.bio_after_beaten != r.bio, "NULL//SAINT has a bio for after she's beaten")
