extends TestCase
## GameState rules: links, signal, scoring, chord, flags, replay.


func _game(seed := 31, immortal := false) -> GameState:
	var gs := GameState.new(seed, Rules.load_default(), immortal)
	gs.reveal(Vector2i(3, -4))
	return gs


func _safe_move(gs: GameState) -> Vector2i:
	gs.solver.solve(true)
	return gs.solver.safe.keys()[0]


## Revealed numbers that still have a hidden neighbour.
func _edge_numbers(gs: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in gs.solver.num:
		for d in Board.NB:
			if not gs.board.is_revealed(p + d):
				out.append(p)
				break
	return out


## A hidden frontier mine, or null.
func _frontier_mine(gs: GameState) -> Variant:
	for p: Vector2i in _edge_numbers(gs):
		for d in Board.NB:
			var q := p + d
			if not gs.board.is_revealed(q) and gs.board.is_mine(q):
				return q
	return null


func test_first_click_opens_a_zero_region() -> void:
	for seed in 20:
		var gs := GameState.new(seed, Rules.load_default())
		var res := gs.reveal(Vector2i(seed * 7, -seed))
		eq(gs.board.number(Vector2i(seed * 7, -seed)), 0, "seed %d" % seed)
		check(res.revealed.size() >= Rules.load_default().min_opening, "seed %d opening %d" % [seed, res.revealed.size()])
		eq(res.hits.size(), 0)
		check(gs.solver.has_safe(), "seed %d: something provably safe after the first click" % seed)


func test_score_is_sum_of_revealed_numbers() -> void:
	var gs := _game()
	for i in 40:
		gs.reveal(_safe_move(gs))
	var total := 0
	var count := 0
	for n in 9:
		total += n * gs.tally[n]
		count += gs.tally[n]
	eq(gs.score, total)
	eq(gs.tiles, count)
	check(gs.score > 0)


func test_mine_hit_costs_a_link_and_stays_revealed() -> void:
	var gs := _game()
	var m: Variant = _frontier_mine(gs)
	check(m != null, "found a frontier mine")
	var score := gs.score
	var res := gs.reveal(m)
	eq(res.links_lost, 1)
	eq(gs.links, 2)
	eq(gs.board.state_at(m), Board.HIT)
	eq(gs.score, score, "a mine scores nothing")
	check(gs.solver.mine.has(m), "the solver knows the hazard")
	check(not gs.over)


func test_three_hits_end_the_run() -> void:
	var gs := _game()
	for i in 3:
		gs.reveal(_frontier_mine(gs))
	check(gs.over, "0 links is game over")
	eq(gs.links, 0)
	eq(gs.reveal(_safe_move(gs)).kind, MoveResult.Kind.NOOP, "no moves after game over")


func test_signal_drains_and_costs_a_link_at_zero() -> void:
	var gs := _game()
	var r := gs.rules
	gs.tick(1000)
	check(absf(gs.signal_level - (r.signal_max - r.drain_rate(1000))) < 1e-6, "one second of drain")
	var lost := 0
	for i in 200:
		lost += gs.tick(1000).links_lost
		if lost > 0:
			break
	eq(lost, 1, "running dry costs exactly one link")
	check(gs.signal_level > r.signal_max * 0.9, "and refills the bar")


func test_signal_refill_is_capped_per_move() -> void:
	var gs := _game()
	gs.tick(30000)
	var before := gs.signal_level
	var res := gs.reveal(_safe_move(gs))
	var safe := res.revealed.size() - res.hits.size()
	var expected := minf(gs.rules.signal_max, before + minf(gs.rules.refill_cap_per_move, gs.rules.refill_per_cell * safe))
	check(absf(gs.signal_level - expected) < 1e-6, "refill %f vs %f" % [gs.signal_level, expected])


func test_no_drain_before_first_click() -> void:
	var gs := GameState.new(5, Rules.load_default())
	gs.tick(60000)
	eq(gs.signal_level, gs.rules.signal_max)
	eq(gs.elapsed_ms, 0)


func test_flags_block_reveal_and_not_revealed_cells() -> void:
	var gs := _game()
	var c := _safe_move(gs)
	check(gs.flag(c).flag_on)
	eq(gs.reveal(c).kind, MoveResult.Kind.NOOP, "can't reveal a flagged cell")
	check(not gs.flag(c).flag_on, "toggle off")
	var open: Vector2i = gs.solver.num.keys()[0]
	eq(gs.flag(open).kind, MoveResult.Kind.NOOP, "can't flag a revealed cell")


func test_chord_with_right_flags() -> void:
	var gs := _game()
	var did := false
	for p: Vector2i in _edge_numbers(gs):
		var mines: Array[Vector2i] = []
		var hidden := 0
		for d in Board.NB:
			var q := p + d
			if not gs.board.is_revealed(q):
				hidden += 1
				if gs.board.is_mine(q):
					mines.append(q)
		if mines.is_empty() or mines.size() == hidden:
			continue
		for q in mines:
			gs.flag(q)
		var res := gs.chord(p)
		eq(res.kind, MoveResult.Kind.CHORD)
		eq(res.hits.size(), 0, "right flags never hit")
		check(res.revealed.size() >= hidden - mines.size())
		did = true
		break
	check(did, "found a number to chord")


func test_chord_needs_matching_flags_and_wrong_flags_hit() -> void:
	var gs := _game()
	var did := false
	for p: Vector2i in _edge_numbers(gs):
		var safe: Array[Vector2i] = []
		var mines: Array[Vector2i] = []
		for d in Board.NB:
			var q := p + d
			if not gs.board.is_revealed(q):
				if gs.board.is_mine(q):
					mines.append(q)
				else:
					safe.append(q)
		if mines.size() != 1 or safe.is_empty():
			continue
		eq(gs.chord(p).kind, MoveResult.Kind.NOOP, "no flags, no chord")
		gs.flag(safe[0])
		var res := gs.chord(p)
		eq(res.hits.size(), 1, "the wrong flag leaves the mine to be hit")
		eq(res.links_lost, 1)
		did = true
		break
	check(did, "found a number with one mine")


func test_hits_count_toward_chord() -> void:
	for seed in 40:
		var gs := _game(seed)
		var m: Variant = _frontier_mine(gs)
		if m == null:
			continue
		gs.reveal(m)
		for d in Board.NB:
			var p: Vector2i = m + d
			if not gs.board.is_open(p) or gs.board.number(p) != 1:
				continue
			var hidden := 0
			for d2 in Board.NB:
				if gs.board.state_at(p + d2) == Board.HIDDEN:
					hidden += 1
			if hidden == 0:
				continue
			var res := gs.chord(p)
			eq(res.kind, MoveResult.Kind.CHORD, "a revealed mine counts toward the chord (seed %d)" % seed)
			eq(res.hits.size(), 0)
			check(res.revealed.size() >= hidden)
			return
	check(false, "no seed had a hit next to a 1 with hidden neighbours")


func test_replay_reproduces_the_run() -> void:
	var gs := GameState.new(777, Rules.load_default())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	gs.reveal(Vector2i(-20, 40))
	for i in 120:
		if gs.over:
			break
		var r := rng.randf()
		if r < 0.1:
			var m: Variant = _frontier_mine(gs)
			if m != null:
				gs.flag(m)
		elif r < 0.15:
			var keys := _edge_numbers(gs)
			gs.chord(keys[rng.randi_range(0, keys.size() - 1)])
		else:
			gs.reveal(_safe_move(gs))
		gs.tick(rng.randi_range(100, 3000))
	var again := MoveLog.replay(MoveLog.from_dict(JSON.parse_string(JSON.stringify(gs.move_log.to_dict()))), Rules.load_default())
	eq(again.board.fingerprint(), gs.board.fingerprint(), "same board")
	eq(again.score, gs.score)
	eq(again.links, gs.links)
	eq(again.signal_level, gs.signal_level)
	eq(again.tally, gs.tally)
	eq(again.gen.stats, gs.gen.stats)


func test_flags_never_change_the_board() -> void:
	var gs := GameState.new(4242, Rules.load_default())
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	gs.reveal(Vector2i.ZERO)
	for i in 150:
		gs.reveal(_safe_move(gs))
		gs.tick(500)
	var log := gs.move_log
	var clicked := {}
	for i in log.count():
		if log.ops[i * 3] == MoveLog.REVEAL:
			clicked[Vector2i(log.ops[i * 3 + 1], log.ops[i * 3 + 2])] = true
	# Cells to flag: hidden ones near the play area that are never clicked
	# (many of them get revealed by cascades, which clears the flag).
	var cands: Array[Vector2i] = []
	for y in range(-40, 41):
		for x in range(-40, 41):
			var c := Vector2i(x, y)
			if not clicked.has(c):
				cands.append(c)
	var flagged := MoveLog.new()
	flagged.seed = log.seed
	for i in log.count():
		if i > 0 and rng.randf() < 0.5:
			for j in rng.randi_range(1, 3):
				var c := cands[rng.randi_range(0, cands.size() - 1)]
				flagged.add(MoveLog.FLAG, c.x, c.y)
		flagged.add(log.ops[i * 3], log.ops[i * 3 + 1], log.ops[i * 3 + 2])
	var with_flags := MoveLog.replay(flagged, Rules.load_default())
	check(with_flags.board.flags.size() > 0, "flags were placed")
	eq(with_flags.board.fingerprint(), gs.board.fingerprint(), "flags changed the board")
	eq(with_flags.gen.stats, gs.gen.stats, "flags changed generation")
	eq(with_flags.score, gs.score)


# --- game modes ---------------------------------------------------------------

func test_ghost_mode_has_no_signal_timer() -> void:
	var gs := GameState.new(31, Rules.load_default(), false, GameState.Mode.GHOST)
	gs.reveal(Vector2i(3, -4))
	var lost := 0
	for i in 200:
		lost += gs.tick(60000).links_lost
	eq(lost, 0, "no signal-outs in Ghost mode")
	eq(gs.links, 3)
	eq(gs.signal_fraction(), 1.0)
	eq(gs.elapsed_ms, 200 * 60000, "run time still counts")
	check(not gs.over)


func test_ghost_mode_still_costs_links_for_mines() -> void:
	var gs := GameState.new(31, Rules.load_default(), false, GameState.Mode.GHOST)
	gs.reveal(Vector2i(3, -4))
	for i in 3:
		gs.reveal(_frontier_mine(gs))
	check(gs.over, "three mine hits still end a Ghost run")


func test_end_run_banks_the_score() -> void:
	var gs := GameState.new(31, Rules.load_default(), false, GameState.Mode.GHOST)
	gs.reveal(Vector2i(3, -4))
	for i in 25:
		gs.reveal(_safe_move(gs))
	var score := gs.score
	var res := gs.end_run()
	eq(res.kind, MoveResult.Kind.END)
	check(gs.over and gs.ended, "the run is over, ended by the player")
	eq(gs.score, score, "score is banked as it was")
	eq(gs.reveal(Vector2i(500, 500)).kind, MoveResult.Kind.NOOP, "no moves after ending")
	eq(gs.end_run().kind, MoveResult.Kind.NOOP, "ending twice does nothing")


func test_ghost_runs_replay_exactly() -> void:
	var gs := GameState.new(902, Rules.load_default(), false, GameState.Mode.GHOST)
	gs.reveal(Vector2i.ZERO)
	for i in 60:
		gs.reveal(_safe_move(gs))
		gs.tick(4000)
	gs.end_run()
	var again := MoveLog.replay(MoveLog.from_dict(JSON.parse_string(JSON.stringify(gs.move_log.to_dict()))),
		Rules.load_default())
	eq(again.mode, GameState.Mode.GHOST)
	check(again.over and again.ended)
	eq(again.score, gs.score)
	eq(again.board.fingerprint(), gs.board.fingerprint())


func test_arcade_is_the_default_mode() -> void:
	var gs := GameState.new(1, Rules.load_default())
	eq(gs.mode, GameState.Mode.ARCADE)
	gs.reveal(Vector2i.ZERO)
	check(gs.tick(1000).links_lost == 0 and gs.signal_fraction() < 1.0, "arcade drains")
