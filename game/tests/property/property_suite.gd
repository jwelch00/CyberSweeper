class_name PropertySuite
extends RefCounted
## Seeded games driven by the solver, asserting after every move that a
## provably safe frontier cell exists (computed from scratch, flags ignored).
## Every check_every moves it also checks that revealed numbers never changed,
## locked chunks never changed, the score adds up, and the game's incremental
## solver matches a fresh one. Every reprove_every moves (and at the end) it
## re-runs every chunk proof against what the player can see now.
##
## Drivers:
##   perfect   only clicks provably safe cells
##   sloppy    also guesses frontier cells (mine hits), places random flags and
##             chords on them (bad chords hit mines too)
##   wanderer  sloppy plus voluntary far clicks

const DRIVER_BASE := {"perfect": 0x1000000, "sloppy": 0x2000000, "wanderer": 0x3000000}

var rules: Rules
var out_dir := ""


static func game_seed(driver: String, index: int) -> int:
	return CsHash.mix32(DRIVER_BASE[driver] + index)


func run(args: Dictionary) -> int:
	var driver: String = args.get("driver", "perfect")
	if not DRIVER_BASE.has(driver):
		printerr("unknown driver: ", driver)
		return 2
	var first := int(args.get("first", "0"))
	var games := int(args.get("games", "10"))
	var moves := int(args.get("moves", "300"))
	var check_every := int(args.get("check-every", "25"))
	var reprove_every := int(args.get("reprove-every", "100"))
	out_dir = args.get("out", ProjectSettings.globalize_path("res://").path_join("../test-output"))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("failures"))
	rules = Rules.load_default()

	var t_start := Time.get_ticks_msec()
	var total := {"games": 0, "moves": 0, "tiles": 0, "hits": 0, "flags": 0, "chords": 0,
		"far_clicks": 0, "chunks_locked": 0, "pocket_games": 0, "max_depth": 0}
	var gen_total := {}
	var hist := {"move": {}, "txn": {}, "proof": {}, "check": {}}
	var failures: Array[Dictionary] = []
	for i in range(first, first + games):
		var r := _play(driver, i, moves, check_every, reprove_every)
		total.games += 1
		for key in ["moves", "tiles", "hits", "flags", "chords", "far_clicks", "chunks_locked"]:
			total[key] += r[key]
		total.max_depth = maxi(total.max_depth, r.max_depth)
		if r.gen.pockets > 0:
			total.pocket_games += 1
		for key in r.gen:
			gen_total[key] = gen_total.get(key, 0) + r.gen[key]
		for name in hist:
			_hist_add(hist[name], r.samples[name])
		if r.fail != "":
			failures.append({"index": i, "seed": r.seed, "move": r.fail_move, "msg": r.fail, "file": r.fail_file})
			printerr("FAIL %s #%d (seed %d) move %d: %s" % [driver, i, r.seed, r.fail_move, r.fail])
	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("property %s games %d-%d: %d moves, %d failures, pockets in %d games, %.1f s" % [
		driver, first, first + games - 1, total.moves, failures.size(), total.pocket_games, elapsed])
	if args.has("json"):
		var fa := FileAccess.open(args.json, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"suite": "property", "driver": driver, "first": first,
			"total": total, "gen": gen_total, "hist": hist, "failures": failures, "elapsed_s": elapsed}))
	return 1 if failures.size() > 0 else 0


# --- one game -----------------------------------------------------------------

func _play(driver: String, index: int, moves: int, check_every: int, reprove_every: int) -> Dictionary:
	var seed := game_seed(driver, index)
	var gs := GameState.new(seed, rules, true)
	gs.gen.profile = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5BD1E995
	var ctx := {"seen": {}, "order": [] as Array[Vector2i], "snaps": {}, "flags": 0, "chords": 0,
		"far_clicks": 0, "last": Vector2i.ZERO}
	var samples := {"move": PackedInt64Array(), "check": PackedInt64Array()}
	var fail := ""
	var m := 0

	var start := Vector2i(rng.randi_range(-500, 500), rng.randi_range(-500, 500))
	_record(gs, gs.reveal(start), ctx)
	fail = _check(gs, ctx, true)
	while fail == "" and m < moves:
		var t0 := Time.get_ticks_usec()
		var res := _step(gs, driver, rng, ctx)
		samples.move.append(Time.get_ticks_usec() - t0)
		_record(gs, res, ctx)
		gs.tick(rng.randi_range(100, 1500))
		m += 1
		t0 = Time.get_ticks_usec()
		fail = _check(gs, ctx, m % check_every == 0)
		samples.check.append(Time.get_ticks_usec() - t0)
		if fail == "" and m % reprove_every == 0:
			fail = _reprove(gs)
	if fail == "":
		fail = _check(gs, ctx, true)
	if fail == "":
		fail = _reprove(gs)

	var fail_file := ""
	if fail != "":
		fail_file = out_dir.path_join("failures/%s-%d.json" % [driver, index])
		var fa := FileAccess.open(fail_file, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"driver": driver, "index": index, "seed": seed, "move": m,
			"msg": fail, "map": gs.board.ascii(ctx.last, 12, true), "events": _events_text(gs),
			"log": gs.move_log.to_dict()}, "  "))
	samples["txn"] = gs.gen.txn_usec
	samples["proof"] = gs.gen.proof_usec
	var locked := 0
	for k in gs.board.chunks:
		if gs.board.chunks[k].locked:
			locked += 1
	return {"seed": seed, "fail": fail, "fail_move": m, "fail_file": fail_file, "moves": m,
		"tiles": gs.tiles, "hits": gs.hits, "flags": ctx.flags, "chords": ctx.chords,
		"far_clicks": ctx.far_clicks, "chunks_locked": locked, "max_depth": gs.deepest,
		"gen": gs.gen.stats.duplicate(), "samples": samples}


func _record(gs: GameState, res: MoveResult, ctx: Dictionary) -> void:
	for c in res.revealed:
		ctx.seen[c] = -1 if gs.board.state_at(c) == Board.HIT else gs.board.number(c)
		ctx.order.append(c)
		ctx.last = c


# --- drivers ------------------------------------------------------------------

func _step(gs: GameState, driver: String, rng: RandomNumberGenerator, ctx: Dictionary) -> MoveResult:
	if driver != "perfect":
		var r := rng.randf()
		if r < 0.06:
			var g: Variant = _random_frontier(gs, rng, ctx)
			if g != null:
				return gs.reveal(g)
		elif r < 0.12:
			var f: Variant = _random_frontier(gs, rng, ctx)
			if f != null:
				ctx.flags += 1
				return gs.flag(f)
		elif r < 0.18:
			var res: Variant = _flag_and_chord(gs, rng, ctx)
			if res != null:
				return res
		elif driver == "wanderer" and r < 0.21:
			var base: Vector2i = ctx.order[rng.randi_range(0, ctx.order.size() - 1)]
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(25.0, 60.0)
			var far := base + Vector2i(int(cos(ang) * dist), int(sin(ang) * dist))
			if not gs.board.is_revealed(far) and not gs.board.is_flagged(far):
				ctx.far_clicks += 1
				return gs.reveal(far)
	# Perfect play: any provably safe cell.
	gs.solver.solve(true)
	if gs.solver.has_safe():
		var keys := gs.solver.safe.keys()
		var c: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		if gs.board.is_flagged(c):
			gs.flag(c)
		return gs.reveal(c)
	var any: Variant = _random_frontier(gs, rng, ctx)
	return gs.reveal(any) if any != null else MoveResult.new()


## A revealed number with a hidden, unflagged neighbour, sampled from the
## revealed cells (recent ones are likelier to be on the edge).
func _edge_number(gs: GameState, rng: RandomNumberGenerator, ctx: Dictionary) -> Variant:
	var order: Array[Vector2i] = ctx.order
	for tries in 24:
		var i := order.size() - 1 - mini(order.size() - 1, absi(int(rng.randfn(0.0, 150.0))))
		if tries >= 12:
			i = rng.randi_range(0, order.size() - 1)
		var p := order[i]
		if not gs.board.is_open(p):
			continue
		for d in Board.NB:
			var q := p + d
			if not gs.board.is_revealed(q) and not gs.board.is_flagged(q):
				return p
	return null


func _random_frontier(gs: GameState, rng: RandomNumberGenerator, ctx: Dictionary) -> Variant:
	var p: Variant = _edge_number(gs, rng, ctx)
	if p == null:
		return null
	var opts: Array[Vector2i] = []
	for d in Board.NB:
		var q: Vector2i = p + d
		if not gs.board.is_revealed(q) and not gs.board.is_flagged(q):
			opts.append(q)
	return opts[rng.randi_range(0, opts.size() - 1)]


## Flags as many hidden neighbours of a random number as it still needs (chosen
## at random, so often wrong), then chords it.
func _flag_and_chord(gs: GameState, rng: RandomNumberGenerator, ctx: Dictionary) -> Variant:
	var e: Variant = _edge_number(gs, rng, ctx)
	if e == null:
		return null
	var p: Vector2i = e
	var need := gs.board.number(p)
	var hidden: Array[Vector2i] = []
	for d in Board.NB:
		var q := p + d
		var st := gs.board.state_at(q)
		if st == Board.HIT or (st == Board.HIDDEN and gs.board.is_flagged(q)):
			need -= 1
		elif st == Board.HIDDEN:
			hidden.append(q)
	if need < 0 or need >= hidden.size():
		return null
	# Seeded shuffle (Array.shuffle() uses the global RNG, which would make
	# games unreproducible from their seed).
	for i in range(hidden.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := hidden[i]
		hidden[i] = hidden[j]
		hidden[j] = tmp
	for i in need:
		gs.flag(hidden[i])
		ctx.flags += 1
	ctx.chords += 1
	return gs.chord(p)


# --- checks -------------------------------------------------------------------

func _check(gs: GameState, ctx: Dictionary, full: bool) -> String:
	var g := gs.gen
	if g.stats.unsound > 0:
		return "solver proved a mine safe during generation"
	if g.stats.contradictions > 0:
		return "solver contradiction during generation"
	if gs.solver.contradiction:
		return "game solver contradiction"
	if gs.stuck_count > 0 or g.stats.rescues > 0:
		return "no provably safe frontier cell (backstop armed %d, rescues %d)" % [gs.stuck_count, g.stats.rescues]

	# The spec invariant, from scratch: only revealed numbers and mines, no flags.
	var s := Solver.from_rules(rules)
	_load(s, ctx)
	s.solve(true)
	if s.contradiction:
		return "fresh solver contradiction"
	if not s.has_safe():
		return "no provably safe frontier cell (fresh solver)"
	for c: Vector2i in s.safe:
		if gs.board.is_mine(c):
			return "fresh solver called mine %s safe" % c
		if gs.board.is_revealed(c):
			return "fresh solver offered revealed cell %s" % c
		break

	for k: Vector2i in gs.board.chunks:
		var ch: Chunk = gs.board.chunks[k]
		if ch.locked and not ctx.snaps.has(k):
			ctx.snaps[k] = ch.mines.duplicate()

	if not full:
		return ""
	var total := 0
	for c: Vector2i in ctx.order:
		var n: int = ctx.seen[c]
		if n < 0:
			if gs.board.state_at(c) != Board.HIT or not gs.board.is_mine(c):
				return "revealed mine changed at %s" % c
		else:
			total += n
			if not gs.board.is_open(c) or gs.board.number(c) != n:
				return "revealed number changed at %s" % c
	if total != gs.score:
		return "score %d but revealed numbers sum to %d" % [gs.score, total]
	var tally_score := 0
	var tally_tiles := 0
	for n in 9:
		tally_score += n * gs.tally[n]
		tally_tiles += gs.tally[n]
	if tally_score != gs.score or tally_tiles != gs.tiles:
		return "tally doesn't add up"
	for k: Vector2i in ctx.snaps:
		if gs.board.chunk(k).mines != ctx.snaps[k]:
			return "locked chunk %s changed" % k

	var fresh := Solver.from_rules(rules)
	_load(fresh, ctx)
	fresh.solve()
	gs.solver.solve()
	if _sorted(fresh.safe) != _sorted(gs.solver.safe):
		return "incremental solver safe set differs from fresh (%d vs %d)" % [gs.solver.safe.size(), fresh.safe.size()]
	if _sorted(fresh.mine) != _sorted(gs.solver.mine):
		return "incremental solver mine set differs from fresh"
	return ""


## Re-runs every proof against what the player can see now, in commit order,
## each one only starting from the proofs before it.
func _reprove(gs: GameState) -> String:
	gs.gen.profile = false
	var out := ""
	var keys := gs.gen.proofs.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return gs.gen.proof_order[a] < gs.gen.proof_order[b])
	for k: Vector2i in keys:
		var p := gs.gen.prove_chunk(k, gs.gen.proof_order[k])
		if not p.ok:
			out = "proof of chunk %s no longer holds (%d cells uncovered)" % [k, p.uncovered]
			break
	gs.gen.profile = true
	return out


func _load(s: Solver, ctx: Dictionary) -> void:
	for c: Vector2i in ctx.order:
		var n: int = ctx.seen[c]
		if n < 0:
			s.add_mine(c)
		else:
			s.add_number(c, n)


func _sorted(d: Dictionary) -> Array:
	var a := d.keys()
	a.sort()
	return a


func _events_text(gs: GameState) -> Array:
	var out := []
	for e in gs.gen.events:
		out.append(str(e))
	return out


## Histogram in 0.1 ms buckets.
func _hist_add(h: Dictionary, samples: PackedInt64Array) -> void:
	for us in samples:
		var b := mini(int(us / 100), 50000)
		h[b] = h.get(b, 0) + 1
