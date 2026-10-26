extends TestCase
## Replay files: a run's actions and their times alone must reproduce it
## exactly (so replays double as score verification), however time is sliced.


func _bot_run(pid: String, seed: int, mode := GameState.Mode.ARCADE, minutes := 12) -> GameState:
	var rules := Rules.load_default()
	var gs := GameState.new(seed, rules, false, mode)
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
