extends TestCase
## Save data: stats, unlocks, rivals, leaderboards, flavor lines, the save
## files themselves, and settings.

const A := GameState.Mode.ARCADE
const G := GameState.Mode.GHOST


func _run(score: int, tiles := 100, depth := 10, mode := A, cause := "mine") -> Dictionary:
	return {"score": score, "tiles": tiles, "depth": depth, "elapsed_ms": 60000, "mode": mode, "seed": score,
		"cause": cause, "date": "2026-10-26"}


func _scratch() -> String:
	var d := ProjectSettings.globalize_path("res://").path_join("../test-output/save-unit")
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	return d


func test_stats_add_up_for_arcade_runs() -> void:
	var p := Profile.new()
	p.record(_run(500, 300, 40, A, "mine"))
	p.record(_run(900, 700, 25, A, "signal"))
	eq(p.runs, 2)
	eq(p.total_tiles, 1000)
	eq(p.best_depth, 40)
	eq(p.best_score, 900)
	eq(p.time_ms, 120000)
	eq([p.deaths_mine, p.deaths_signal], [1, 1])


func test_ghost_runs_never_count_toward_anything() -> void:
	var p := Profile.new()
	var r := p.record(_run(99999, 99999, 999, G, "ended"))
	eq(p.runs, 0, "no stats")
	eq(p.total_tiles, 0)
	eq(p.best_depth, 0)
	eq(p.unlocked, [] as Array[String], "no unlocks")
	eq(p.beaten, [] as Array[String], "no rivals")
	eq(r.beaten_now, [])
	eq(r.unlocked_now, [])
	eq(p.ghost.size(), 1, "only the Ghost leaderboard")
	eq(p.arcade.size(), 0)
	eq(r.flavor.kind, "", "no rival lines")


func test_unlocks_fire_exactly_at_their_thresholds() -> void:
	var p := Profile.new()
	check(p.is_unlocked("signal") and p.is_unlocked("plaintext"), "always unlocked")
	check(not p.is_unlocked("hotwire"), "locked to start")
	eq(p.record(_run(3590)).unlocked_now, [], "level with mx_halcyon isn't beating her")
	eq(p.record(_run(3591)).unlocked_now, ["hotwire"], "beating mx_halcyon unlocks Hotwire")
	eq(p.record(_run(10, 24000 - 3800 - 200)).unlocked_now, [], "under 25,000 tiles")
	var tiles_left := 25000 - p.total_tiles
	eq(p.record(_run(10, tiles_left)).unlocked_now, ["root-access"], "25,000 tiles across runs")
	eq(p.record(_run(10, 1, 119)).unlocked_now, [], "depth 119")
	eq(p.record(_run(10, 1, 120)).unlocked_now, ["rustbelt"], "depth 120 in one run")
	eq(p.record(_run(7000)).unlocked_now, [], "level with NULL//SAINT")
	eq(p.record(_run(7001)).unlocked_now, ["icebreaker"], "beating NULL//SAINT")
	eq(p.unlocked_count(), 6)
	eq(p.unseen.size(), 4, "each new unlock is marked New")
	p.mark_seen("hotwire")
	check(not p.unseen.has("hotwire"))


func test_progress_toward_locked_palettes() -> void:
	var p := Profile.new()
	p.record(_run(2293, 7812, 87))
	eq(p.progress("root-access"), {"have": 7812, "need": 25000, "label": "tiles"})
	eq(p.progress("rustbelt"), {"have": 87, "need": 120, "label": "best depth"})
	eq(p.progress("icebreaker"), {"have": 2293, "need": 7000, "label": "best run"})
	eq(p.progress("signal"), {})


func test_rivals_beaten_for_the_first_time_only_once() -> void:
	var p := Profile.new()
	var r := p.record(_run(3600))
	eq(r.beaten_run, ["tourist", "rookie", "streamer", "runner"])
	eq(r.beaten_now, ["tourist", "rookie", "streamer", "runner"])
	eq(r.flavor.kind, "beaten")
	eq(r.flavor.rival, "runner", "the best rival beaten gets the line")
	eq(r.flavor.text, Profile.rival("runner").beaten)
	r = p.record(_run(3700))
	eq(r.beaten_run, ["tourist", "rookie", "streamer", "runner"], "still beats them")
	eq(r.beaten_now, [], "but not for the first time")
	eq(r.flavor.kind, "taunt")
	eq(r.flavor.rival, "veteran", "the next rival above taunts")
	r = p.record(_run(100))
	eq(r.flavor.rival, "tourist", "a low run hears from lil.byte")
	eq(p.record(_run(8000)).flavor.rival, "netrunner", "beating everyone for the first time: NULL//SAINT's line")
	var top: Dictionary = p.record(_run(9000)).flavor
	eq(top.kind, "again", "above everyone again")
	check(Profile.rival("netrunner").again.has(top.text), "one of NULL//SAINT's again lines")


func test_flavor_lines_follow_the_rules() -> void:
	var close := Profile.flavor_for(4200, [], 7)
	eq([close.kind, close.rival], ["close", "veteran"], "within 10% of OXIDE's 4,600")
	check(Profile.rival("veteran").close.has(close.text))
	var taunt := Profile.flavor_for(3000, [], 7)
	eq([taunt.kind, taunt.rival], ["taunt", "runner"], "more than 10% short of mx_halcyon")
	check(Profile.rival("runner").taunts.has(taunt.text))
	eq(Profile.flavor_for(3590, [], 7).rival, "runner", "level with a rival isn't past them")
	eq(Profile.flavor_for(3000, [], 11), Profile.flavor_for(3000, [], 11), "the same run always picks the same line")
	var seen := {}
	for seed in 64:
		seen[Profile.flavor_for(3000, [], seed).text] = true
	eq(seen.size(), 4, "different runs pick all four taunts")


func test_null_saint_bio_changes_once_beaten() -> void:
	var p := Profile.new()
	var saint := Profile.rival("netrunner")
	eq(p.bio(saint), saint.bio)
	p.record(_run(7001))
	eq(p.bio(saint), saint.bio_after_beaten)
	eq(p.bio(Profile.rival("rookie")), Profile.rival("rookie").bio, "the others don't change")


func test_leaderboards_keep_the_top_ten() -> void:
	var p := Profile.new()
	var ranks := []
	for s in [50, 400, 300, 900, 10, 700, 600, 200, 800, 100, 500, 5]:
		ranks.append(p.record(_run(s)).rank)
	eq(p.arcade.size(), 10)
	var scores := p.arcade.map(func(e): return e.score)
	eq(scores, [900, 800, 700, 600, 500, 400, 300, 200, 100, 50])
	eq(ranks[0], 0, "the first run is first")
	eq(ranks.back(), -1, "a run that doesn't make the top ten")
	var r := p.record(_run(850))
	eq(r.rank, 1)
	eq(r.previous_best, 900)
	check(not r.new_best)
	check(p.record(_run(901)).new_best)


func test_profile_round_trips_and_tolerates_junk() -> void:
	var p := Profile.new()
	p.record(_run(3600, 500, 30))
	p.record(_run(200, 50, 5, G, "ended"))
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	eq(q.to_dict(), p.to_dict(), "JSON round trip")
	var junk := Profile.from_dict({"runs": "3", "unlocked": ["hotwire", 7, "hotwire"], "arcade": [{"no": 1}, {"score": 5}],
		"ghost": "nope"})
	eq(junk.runs, 3)
	eq(junk.unlocked, ["hotwire"] as Array[String], "bad and duplicate entries dropped")
	eq(junk.arcade.size(), 1)
	eq(junk.ghost.size(), 0)


func test_save_store_writes_atomically_and_survives_corruption() -> void:
	var old := SaveStore.dir
	SaveStore.dir = _scratch()
	var p := Profile.new()
	p.record(_run(1234))
	check(SaveStore.save_profile(p), "saves")
	check(not FileAccess.file_exists(SaveStore.path("profile.json.tmp")), "no temp file left behind")
	eq(SaveStore.load_profile().to_dict(), p.to_dict(), "loads back the same")
	# A replace interrupted after the old file went: the .tmp is used.
	DirAccess.rename_absolute(SaveStore.path("profile.json"), SaveStore.path("profile.json.tmp"))
	eq(SaveStore.load_profile().best_score, 1234, "recovers from the temp file")
	SaveStore.save_profile(p)
	var f := FileAccess.open(SaveStore.path("profile.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	eq(SaveStore.load_profile().runs, 0, "a corrupt file starts fresh")
	check(FileAccess.file_exists(SaveStore.path("profile.json.bad")), "and is kept as .bad")
	eq(SaveStore.load_json("missing.json"), {}, "a missing file is empty")
	SaveStore.dir = old


func test_settings_round_trip_and_os_default() -> void:
	var old := SaveStore.dir
	SaveStore.dir = _scratch()
	var s := GameSettings.new()
	s.palette_id = "rustbelt"
	s.volume = 0.6
	s.scanlines = false
	s.fullscreen = true
	s.mode = "ghost"
	check(s.save())
	var t := GameSettings.load_saved()
	eq(t.to_dict(), s.to_dict())
	t.set_reduced_motion(true, false)
	check(t.reduced_motion, "the OS default applies until the player sets it")
	t.set_reduced_motion(false)
	t.set_reduced_motion(true, false)
	check(not t.reduced_motion, "the player's own choice wins over the OS")
	check(GameSettings.from_dict(t.to_dict()).reduced_motion_set, "and is remembered")
	eq(GameSettings.from_dict({"volume": 9, "mode": "x"}).volume, 1.0, "odd values are clamped")
	eq(GameSettings.from_dict({"mode": "x"}).mode, "arcade")
	SaveStore.dir = old


func test_tally_adds_up_to_the_score() -> void:
	var rules := Rules.load_default()
	for seed in [3, 11, 42]:
		var s := Session.new(seed, rules, false)
		s.bot("netrunner", 150, Vector2i.ZERO)
		for r in s.poll():
			var tally: Array = r.state.tally
			var sum := 0
			for n in range(1, tally.size()):
				sum += n * int(tally[n])
			eq(sum, int(r.state.score), "seed %d: count x value per number sums to the score" % seed)
		s.close()


func test_game_over_minutes_in_words() -> void:
	eq(Deck.minutes_words(30000), "under a minute in")
	eq(Deck.minutes_words(61000), "one minute in")
	eq(Deck.minutes_words(11 * 60000 + 42000), "eleven minutes in", "like the mockup")
	eq(Deck.minutes_words(42 * 60000), "42 minutes in")
	eq(Deck.clock(702000), "11:42")
