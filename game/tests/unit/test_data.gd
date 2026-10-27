extends TestCase
## The data files: rivals and palette unlocks.


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(d is Dictionary, path + " is a JSON object")
	return d if d is Dictionary else {}


func test_rivals_match_the_bots_and_climb() -> void:
	var rivals: Array = _json("res://data/rivals.json").rivals
	var bots := Bot.load_profiles()
	eq(rivals.map(func(r): return r.id), ["tourist", "rookie", "streamer", "runner", "veteran", "ace", "netrunner"])
	var last := 0
	var names := {}
	for r in rivals:
		check(bots.has(r.id), "rival %s has a bot profile" % r.id)
		eq(r.name, bots[r.id].name, "rival name matches its bot")
		check(not names.has(r.name), "rival names are unique")
		names[r.name] = true
		check(float(r.score) == floorf(r.score), "score is a whole number")
		check(int(r.score) > last, "rivals climb, lil.byte to NULL//SAINT")
		last = int(r.score)
	check(rivals[0].score < 1000, "a very low first rival anyone can beat")
	eq(rivals.back().name, "NULL//SAINT", "NULL//SAINT stays at the top")


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
		for key in ["bio", "beaten"]:
			check(r.has(key) and String(r[key]).strip_edges() != "", "%s has %s" % [r.id, key])
		for want in [["taunts", 4], ["close", 2], ["rematch", 0], ["again", 0]]:
			var lines: Array = r.get(want[0], [])
			check(lines.size() >= want[1], "%s has at least %d %s lines" % [r.id, want[1], want[0]])
			for l in lines:
				check(String(l).strip_edges() != "", "%s %s lines aren't empty" % [r.id, want[0]])
		if r.id in ["ace", "netrunner"]:
			check(r.has("bio_after_beaten") and r.bio_after_beaten != r.bio, "%s has a bio for after they're beaten" % r.name)
			check(r.get("rematch", []).size() >= 3, "%s has rematch lines" % r.name)
		if r.id == "netrunner":
			check(r.get("again", []).size() >= 3, "NULL//SAINT has again lines")
		else:
			check(not r.has("again"), "only NULL//SAINT can be passed by everyone")
	var vesper: Dictionary = Profile.rival("ace")
	check(vesper.taunts.size() >= 8 and vesper.close.size() >= 4, "VESPER has the most to say")


## Every bio fits its Rivals card and every game-over line fits its card,
## quotes included.
func test_rival_lines_fit_their_cards() -> void:
	for r in Profile.rivals():
		for key in ["bio", "bio_after_beaten"]:
			if r.has(key):
				var n := Deck.wrap("ui400", "\"%s\"" % r[key], 15, RivalsScreen.BIO_W).size()
				check(n <= RivalsScreen.BIO_LINES, "%s %s fits its card (%d lines)" % [r.id, key, n])
		var lines: Array = [r.beaten]
		for key in ["taunts", "close", "rematch", "again"]:
			lines.append_array(r.get(key, []))
		for l in lines:
			var n := Deck.wrap("ui400", "\"%s\"" % l, 16, GameOverScreen.QUOTE_W).size()
			check(n <= GameOverScreen.QUOTE_LINES, "%s fits the game-over card: %s" % [r.id, l])
