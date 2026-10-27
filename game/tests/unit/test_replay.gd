extends TestCase
## Replay files: a run's actions and their times alone must reproduce it
## exactly (so replays double as score verification), however time is sliced.


func _bot_run(pid: String, seed: int, mode := GameState.Mode.ARCADE, minutes := 12, grace := false) -> GameState:
	var rules := Rules.load_default()
	var gs := GameState.new(seed, rules, false, mode, grace)
	var bot := Bot.new(pid, Bot.load_profiles()[pid], rules, seed)
	bot.play(gs, Vector2i(2, -3), minutes * 60000)
	return gs


func _same(a: GameState, b: GameState, what: String) -> void:
	eq(b.score, a.score, what + ": score")
	eq(b.links, a.links, what + ": links")
	eq(b.tiles, a.tiles, what + ": tiles")
	eq(b.over, a.over, what + ": over")
	eq(b.elapsed_ms, a.elapsed_ms, what + ": run time")
	eq(b.signal_u, a.signal_u, what + ": signal")
	eq(b.board.fingerprint(), a.board.fingerprint(), what + ": board")


func test_replay_reproduces_an_arcade_run() -> void:
	for seed in [3, 41]:
		var gs := _bot_run("runner", seed)
		check(gs.over, "the run ended")
		check(gs.links_lost - gs.hits > 0, "it lost links to the signal (exercises the drain)")
		var r := gs.move_log.to_replay()
		eq(r.score, gs.score, "the replay records the final score")
		eq(r.end_ms, gs.elapsed_ms, "and when the run ended")
		var again := MoveLog.play_replay(JSON.parse_string(JSON.stringify(r)), Rules.load_default())
		_same(gs, again, "seed %d" % seed)


func test_time_slicing_doesnt_matter() -> void:
	var gs := _bot_run("rookie", 9)
	var r := gs.move_log.to_replay()
	for step in [16, 250, 997]:
		_same(gs, MoveLog.play_replay(r, Rules.load_default(), step), "%d ms ticks" % step)


## A person's run, with signal grace: the freezes come from the actions and
## the signal, so a replay rebuilds them exactly, however time is sliced.
func test_grace_runs_replay_exactly() -> void:
	var plain := _bot_run("rookie", 9)
	var gs := _bot_run("rookie", 9, GameState.Mode.ARCADE, 12, true)
	check(gs.grace_until_ms > 0, "the run hit the grace line and froze the bar")
	check(gs.elapsed_ms != plain.elapsed_ms or gs.score != plain.score, "and grace changed how it went")
	var r: Dictionary = JSON.parse_string(JSON.stringify(gs.move_log.to_replay()))
	eq(r.grace, true, "the replay records grace")
	eq(MoveLog.replay_problem(r, Rules.load_default()), "")
	for step in [0, 16, 997]:
		_same(gs, MoveLog.play_replay(r, Rules.load_default(), step), "grace, %d ms ticks" % step)
	var no_grace := r.duplicate(true)
	no_grace.grace = false
	var off := MoveLog.play_replay(no_grace, Rules.load_default())
	check(off.elapsed_ms != gs.elapsed_ms or off.score != gs.score or off.signal_u != gs.signal_u,
		"the same actions without grace play out differently")
	check(MoveLog.replay_problem(r.merged({"grace": "yes"}, true), Rules.load_default()) != "", "a bad grace flag is refused")


func test_replay_reproduces_a_banked_ghost_run() -> void:
	var rules := Rules.load_default()
	var gs := GameState.new(77, rules, false, GameState.Mode.GHOST)
	var bot := Bot.new("netrunner", Bot.load_profiles().netrunner, rules, 1)
	gs.reveal(Vector2i.ZERO)
	bot._observe(gs, MoveResult.new())
	for i in 150:
		bot.turn(gs)
	gs.end_run()
	var r := gs.move_log.to_replay()
	eq(r.mode, GameState.Mode.GHOST)
	var again := MoveLog.play_replay(r, rules)
	_same(gs, again, "ghost")
	check(again.ended, "ended by the player")


func test_replays_from_another_build_are_refused() -> void:
	var rules := Rules.load_default()
	var r := _bot_run("rookie", 5, GameState.Mode.ARCADE, 3).move_log.to_replay()
	eq(MoveLog.replay_problem(r, rules), "", "this build can play its own replays")
	var other := r.duplicate(true)
	other.version = "0.0.1"
	check(MoveLog.replay_problem(other, rules).contains("0.0.1"), "a different version is named")
	var retuned := rules.with_overrides({"signal": {"drain_per_sec": 2.5}})
	check(MoveLog.replay_problem(r, retuned) != "", "different tuning is refused")
	check(rules.tuning_hash() == Rules.load_default().tuning_hash(), "the tuning hash is stable")
	check(rules.tuning_hash() != retuned.tuning_hash(), "and changes with the tuning")


func test_damaged_replays_are_refused_not_played() -> void:
	var rules := Rules.load_default()
	var r := _bot_run("rookie", 5, GameState.Mode.ARCADE, 3).move_log.to_replay()
	var damaged := {"format": {}, "seed": null, "mode": 7, "end_ms": "soon", "actions": "none"}
	for key in damaged:
		var bad := r.duplicate(true)
		bad[key] = damaged[key]
		check(MoveLog.replay_problem(bad, rules) != "", "a bad %s is refused" % key)
	var no_seed := r.duplicate(true)
	no_seed.erase("seed")
	check(MoveLog.replay_problem(no_seed, rules) != "", "a missing seed is refused")
	for a in [[0, 1, 2], ["0", 1, 2, 3], [9, 1, 2, 3], "reveal", [0, null, 2, 3]]:
		var bad := r.duplicate(true)
		bad.actions.append(a)
		check(MoveLog.replay_problem(bad, rules) != "", "a bad action is refused: %s" % str(a))
	# Through JSON, numbers come back as floats and still play.
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(r))
	eq(MoveLog.replay_problem(round_trip, rules), "", "a replay read back from JSON is fine")


func test_every_action_is_timed() -> void:
	var gs := _bot_run("runner", 12, GameState.Mode.ARCADE, 2)
	var last := -1
	var kinds := {}
	for i in gs.move_log.action_count():
		var at := gs.move_log.actions[i * 4 + 3]
		check(at >= last, "action times never go backwards")
		last = at
		kinds[gs.move_log.actions[i * 4]] = true
	check(kinds.has(MoveLog.REVEAL) and kinds.has(MoveLog.FLAG) and kinds.has(MoveLog.CHORD),
		"reveals, flags and chords are all recorded")
