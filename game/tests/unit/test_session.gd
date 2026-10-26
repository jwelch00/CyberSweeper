extends TestCase
## The worker-thread Session must give exactly what calling GameState directly gives.


func _wait(s: Session) -> Array:
	var out := []
	var t0 := Time.get_ticks_msec()
	while s.busy() and Time.get_ticks_msec() - t0 < 60000:
		out += s.poll()
		OS.delay_msec(1)
	out += s.poll()
	return out


func _play_log(seed: int) -> GameState:
	var gs := GameState.new(seed, Rules.load_default())
	var bot := Bot.new("runner", Bot.load_profiles().runner, Rules.load_default(), 5)
	bot.play(gs, Vector2i(4, -2), 3 * 60000)
	return gs


func test_threaded_session_matches_direct_play() -> void:
	var direct := _play_log(808)
	var s := Session.new(808, Rules.load_default(), true)
	var log := direct.move_log
	for i in log.count():
		var op := log.ops[i * 3]
		var c := Vector2i(log.ops[i * 3 + 1], log.ops[i * 3 + 2])
		match op:
			MoveLog.REVEAL:
				s.reveal(c)
			MoveLog.FLAG:
				s.flag(c)
			MoveLog.CHORD:
				s.chord(c)
			MoveLog.TICK:
				s.tick(c.x)
	var results := _wait(s)
	s.close()
	eq(results.size(), log.count(), "one result per command, none lost")
	var last: Dictionary = results.back().state
	eq(last.score, direct.score)
	eq(last.links, direct.links)
	eq(last.tiles, direct.tiles)
	eq(last.elapsed_ms, direct.elapsed_ms)
	eq(s._gs.board.fingerprint(), direct.board.fingerprint())
	var revealed := 0
	for r in results:
		var res: MoveResult = r.res
		eq(res.numbers.size(), res.revealed.size(), "a number for every revealed cell")
		revealed += res.revealed.size()
	eq(revealed, direct.tiles + direct.hits, "results carry every revealed cell exactly once")


func test_unthreaded_session_answers_immediately() -> void:
	var s := Session.new(1, Rules.load_default(), false)
	s.reveal(Vector2i.ZERO)
	check(s.busy())
	var r := s.poll()
	eq(r.size(), 1)
	check(not s.busy())
	check(r[0].state.started)
	check(r[0].res.revealed.size() >= 9)
	for i in r[0].res.revealed.size():
		check(r[0].res.numbers[i] >= 0, "the opening has no mines")


func test_bot_and_dump_report_what_is_visible() -> void:
	var s := Session.new(77, Rules.load_default(), false)
	s.bot("netrunner", 60, Vector2i(2, 2))
	var r: Dictionary = s.poll()[0].state
	check(r.cells.size() > 50, "the bot revealed cells")
	eq(r.cells.size(), r.numbers.size())
	for i in r.cells.size():
		var c: Vector2i = r.cells[i]
		eq(r.numbers[i], -1 if s._gs.board.state_at(c) == Board.HIT else s._gs.board.number(c))


func test_game_over_reports_hidden_mines_and_wrong_flags() -> void:
	var s := Session.new(3, Rules.load_default(), false)
	s.reveal(Vector2i.ZERO)
	s.poll()
	# Flag a safe frontier cell, then run the signal dry three times.
	var safe := Vector2i.ZERO
	for c in s._gs.solver.safe:
		safe = c
		break
	s.flag(safe)
	for i in 3:
		s.tick(400000)
	var results := s.poll()
	check(results.back().state.over, "running the signal dry ends the run")
	var with_pm := results.filter(func(r): return r.state.has("reveal"))
	eq(with_pm.size(), 1, "the post-mortem comes exactly once, with the move that ended the run")
	if with_pm.is_empty():
		return
	var pm: Dictionary = with_pm[0].state.reveal
	check(pm.wrong_flags.has(safe), "the wrong flag is reported")
	check(pm.mines.size() > 0, "hidden mines near the explored area are reported")
	for m: Vector2i in pm.mines:
		check(s._gs.board.is_mine(m))
