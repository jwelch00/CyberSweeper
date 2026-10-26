extends TestCase
## Generator: locking, proofs, islands, and the backstop.


func _clear_box(b: Board, c0: Vector2i, c1: Vector2i) -> void:
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			b.set_mine(Vector2i(x, y), false)


func test_first_move_locks_only_proven_chunks() -> void:
	for seed in 10:
		var gs := GameState.new(seed, Rules.load_default())
		var res := gs.reveal(Vector2i(seed, seed))
		for c in res.revealed:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var ch := gs.board.chunk_at(c + Vector2i(dx, dy))
					check(ch.locked, "touched chunk locked (seed %d)" % seed)
					check(ch.proven, "and proven (seed %d)" % seed)


func test_locked_chunks_never_change() -> void:
	var gs := GameState.new(99, Rules.load_default())
	gs.reveal(Vector2i.ZERO)
	var snaps := {}
	for i in 150:
		for k in gs.board.chunks:
			var ch: Chunk = gs.board.chunks[k]
			if ch.locked and not snaps.has(k):
				snaps[k] = ch.mines.duplicate()
		gs.solver.solve(true)
		gs.reveal(gs.solver.safe.keys()[0])
	for k in snaps:
		eq(gs.board.chunk(k).mines, snaps[k], "chunk %s changed after locking" % k)
	check(snaps.size() > 4, "the run crossed several chunks")


func test_every_proof_still_holds_later() -> void:
	for seed in [1234, 77, 4040]:
		var gs := GameState.new(seed, Rules.load_default())
		gs.reveal(Vector2i.ZERO)
		for i in 200:
			gs.solver.solve(true)
			gs.reveal(gs.solver.safe.keys()[0])
		var keys := gs.gen.proofs.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return gs.gen.proof_order[a] < gs.gen.proof_order[b])
		check(keys.size() > 4, "several proofs")
		for k: Vector2i in keys:
			var p := gs.gen.prove_chunk(k, gs.gen.proof_order[k])
			check(p.ok, "seed %d: proof of %s no longer holds" % [seed, k])


func test_locked_cells_never_change_even_with_repairs() -> void:
	var repaired_runs := 0
	for seed in [31337, 2, 3, 4, 5, 6]:
		var gs := GameState.new(seed, Rules.load_default())
		gs.reveal(Vector2i.ZERO)
		var locked_mines := {}
		for i in 200:
			for k in gs.board.chunks:
				var ch: Chunk = gs.board.chunks[k]
				if ch.locked and not locked_mines.has(k):
					locked_mines[k] = ch.mines.duplicate()
			gs.solver.solve(true)
			gs.reveal(gs.solver.safe.keys()[0])
		for k in locked_mines:
			eq(gs.board.chunk(k).mines, locked_mines[k], "seed %d chunk %s" % [seed, k])
		if gs.gen.stats.attempts > 0:
			repaired_runs += 1
	check(repaired_runs >= 2, "repairs happened in at least two runs (%d)" % repaired_runs)


func test_far_click_locks_an_island_without_a_proof() -> void:
	var gs := GameState.new(55, Rules.load_default())
	gs.reveal(Vector2i.ZERO)
	var far := Vector2i(300, -200)
	var res := gs.reveal(far)
	var ch := gs.board.chunk_at(far)
	check(ch.locked and ch.island and not ch.proven, "far click makes an island")
	check(gs.gen.stats.islands > 0)
	check(res.revealed.size() > 0)
	gs.solver.solve(true)
	check(gs.solver.has_safe(), "the main area still offers a provably safe cell")


func test_rescue_moves_the_mine_and_keeps_numbers() -> void:
	var b := Board.new(1, Rules.load_default())
	b.start(Vector2i.ZERO)
	var gen := Generator.new(b, Rules.load_default())
	_clear_box(b, Vector2i(90, 90), Vector2i(110, 110))
	var a := Vector2i(100, 100)
	var p := Vector2i(100, 101)
	b.set_mine(a, true)
	b._set_state(p, Board.REVEALED)
	eq(b.number(p), 1)
	check(gen.rescue(a), "a lone 1 has seven other places for its mine")
	check(not b.is_mine(a), "the clicked cell is now safe")
	eq(b.number(p), 1, "the revealed number still matches")
	eq(gen.stats.rescues, 1)
	eq(gen.events.back().type, "rescue")


func test_rescue_refuses_a_provable_mine() -> void:
	var b := Board.new(1, Rules.load_default())
	b.start(Vector2i.ZERO)
	var gen := Generator.new(b, Rules.load_default())
	_clear_box(b, Vector2i(90, 90), Vector2i(110, 110))
	var a := Vector2i(100, 100)
	var p := Vector2i(100, 101)
	b.set_mine(a, true)
	for d in Board.NB:
		if p + d != a:
			b._set_state(p + d, Board.REVEALED)
	b._set_state(p, Board.REVEALED)
	check(not gen.rescue(a), "a 1 whose only hidden neighbour is this cell can't move it")
	check(b.is_mine(a))


func test_backstop_makes_the_next_frontier_click_safe() -> void:
	for seed in 30:
		var gs := GameState.new(seed, Rules.load_default())
		gs.reveal(Vector2i.ZERO)
		for i in 30:
			gs.solver.solve(true)
			gs.reveal(gs.solver.safe.keys()[0])
		gs.solver.solve()
		var target: Variant = null
		for p: Vector2i in gs.solver.num:
			for d in Board.NB:
				var q := p + d
				if not gs.board.is_revealed(q) and gs.board.is_mine(q) and not gs.solver.mine.has(q):
					target = q
					break
			if target != null:
				break
		if target == null:
			continue
		var before := {}
		for c: Vector2i in gs.solver.num:
			before[c] = gs.board.number(c)
		gs.backstop_armed = true
		var res := gs.reveal(target)
		check(res.backstop, "backstop fired")
		eq(res.hits.size(), 0, "the click was made safe")
		check(gs.board.is_open(target))
		for c: Vector2i in before:
			eq(gs.board.number(c), before[c], "revealed number %s changed" % c)
		check(not gs.backstop_armed, "disarmed after use")
		return
	check(false, "no seed had an unproven frontier mine")
