class_name GameState
extends RefCounted
## One run of CyberSweeper. This is the API the bots (milestone 2) and the UI
## (milestone 3) call. It never reads the clock: time only comes in via tick().

const NB := Board.NB

## ARCADE is the main mode. GHOST has no signal timer; the player ends the run
## with end_run() and the score is banked (Profile keeps the records).
enum Mode { ARCADE, GHOST }

var rules: Rules
var seed: int
var board: Board
var gen: Generator
## The player's view: proves cells from revealed numbers and mines only.
var solver: Solver
var move_log := MoveLog.new()

## Tests only: link losses are counted but never end the run.
var immortal := false
var mode: Mode = Mode.ARCADE
## The player ended the run (Ghost mode's "End run").
var ended := false

var started := false
var over := false
var links := 3
## Signal in micro-units (exact integer drain, see Rules.drained_u).
var signal_u := 0
## Signal in points (0..signal_max), for display and tests.
var signal_level: float:
	get:
		return float(signal_u) / Rules.MICRO
var score := 0
## tally[n] = revealed cells showing n (n = 0..8). Score = sum of n * tally[n].
var tally := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var tiles := 0
var hits := 0
var links_lost := 0
var elapsed_ms := 0
var deepest := 0
var moves := 0
var backstop_armed := false
## Times the solver found no provably safe frontier cell. Must stay 0.
var stuck_count := 0


func _init(p_seed: int, p_rules: Rules = null, p_immortal := false, p_mode: Mode = Mode.ARCADE) -> void:
	rules = p_rules if p_rules != null else Rules.load_default()
	seed = p_seed & CsHash.MASK32
	immortal = p_immortal
	mode = p_mode
	move_log.mode = mode
	board = Board.new(seed, rules)
	gen = Generator.new(board, rules)
	solver = Solver.from_rules(rules)
	move_log.seed = seed
	links = rules.start_links
	signal_u = rules.signal_max_u
	move_log.tuning_hash = rules.tuning_hash()


# --- player actions -----------------------------------------------------------

## Left click on a hidden cell. The first click starts the run there.
func reveal(c: Vector2i) -> MoveResult:
	move_log.add(MoveLog.REVEAL, c.x, c.y)
	move_log.action(MoveLog.REVEAL, c, elapsed_ms)
	var res := MoveResult.new(MoveResult.Kind.REVEAL, c)
	if over or board.is_revealed(c) or board.is_flagged(c):
		res.kind = MoveResult.Kind.NOOP
		return res
	var voluntary := started and not board.is_frontier(c)
	if not started:
		board.start(c)
		started = true
	moves += 1
	gen.move_index = moves
	if backstop_armed and not voluntary and not solver.is_proven_mine(c):
		backstop_armed = false
		if board.is_mine(c):
			res.backstop = gen.rescue(c)
	var clicks: Array[Vector2i] = [c]
	_apply(gen.reveal(clicks, voluntary), res)
	_after_move()
	return res


## Left click on a revealed number whose flags (plus revealed mines) match it:
## reveals every other hidden neighbour. Wrong flags can make this hit a mine.
func chord(c: Vector2i) -> MoveResult:
	move_log.add(MoveLog.CHORD, c.x, c.y)
	move_log.action(MoveLog.CHORD, c, elapsed_ms)
	var res := MoveResult.new(MoveResult.Kind.CHORD, c)
	var targets := chord_targets(c)
	if targets.is_empty():
		res.kind = MoveResult.Kind.NOOP
		return res
	moves += 1
	gen.move_index = moves
	_apply(gen.reveal(targets, false), res)
	_after_move()
	return res


## Cells a chord on c would reveal (empty if the chord isn't allowed).
func chord_targets(c: Vector2i) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if over or not board.is_open(c):
		return targets
	var marked := 0
	for d in NB:
		var q := c + d
		var st := board.state_at(q)
		if st == Board.HIT or (st == Board.HIDDEN and board.is_flagged(q)):
			marked += 1
		elif st == Board.HIDDEN:
			targets.append(q)
	if marked != board.number(c):
		targets.clear()
	return targets


## Right click: toggles a flag on a hidden cell. Flags are the player's opinion
## only; nothing in generation or the solver reads them.
func flag(c: Vector2i) -> MoveResult:
	move_log.add(MoveLog.FLAG, c.x, c.y)
	move_log.action(MoveLog.FLAG, c, elapsed_ms)
	var res := MoveResult.new(MoveResult.Kind.FLAG, c)
	if over or not started or board.is_revealed(c):
		res.kind = MoveResult.Kind.NOOP
		return res
	res.flag_on = not board.is_flagged(c)
	board.set_flag(c, res.flag_on)
	return res


## Advances run time: drains signal; signal at 0 costs a link and refills.
## Ghost mode keeps time but has no signal.
func tick(ms: int) -> MoveResult:
	var res := MoveResult.new(MoveResult.Kind.TICK)
	if not started or over or ms <= 0:
		return res
	move_log.add(MoveLog.TICK, ms)
	var target := elapsed_ms + ms
	if mode == Mode.GHOST:
		elapsed_ms = target
		return res
	# Drain exactly, finding the exact millisecond the signal runs dry each
	# time, so neither the outcome nor when the run ends depends on how run
	# time was sliced into ticks.
	var t := elapsed_ms
	while not over:
		var drain := rules.drained_u(target) - rules.drained_u(t)
		if signal_u > drain:
			signal_u -= drain
			t = target
			break
		t = _runs_dry(t, target, signal_u)
		_lose_link(res)
		signal_u = 0 if over else rules.signal_max_u
	elapsed_ms = t if over else target
	if over:
		_finish()
	res.game_over = over
	return res


## First run time in (from, to] by which `amount` micro-units have drained.
func _runs_dry(from: int, to: int, amount: int) -> int:
	var base := rules.drained_u(from)
	var lo := from
	var hi := to
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if rules.drained_u(mid) - base >= amount:
			hi = mid
		else:
			lo = mid
	return hi


## Ends the run now and banks the score (Ghost mode's "End run"; Arcade runs
## end when the links run out).
func end_run() -> MoveResult:
	move_log.add(MoveLog.END, 0)
	move_log.action(MoveLog.END, Vector2i.ZERO, elapsed_ms)
	var res := MoveResult.new(MoveResult.Kind.END)
	if not started or over:
		res.kind = MoveResult.Kind.NOOP
		return res
	over = true
	ended = true
	_finish()
	res.game_over = true
	return res


# --- state for the UI and bots ------------------------------------------------

func signal_fraction() -> float:
	return 1.0 if mode == Mode.GHOST else signal_level / rules.signal_max


func depth_of(c: Vector2i) -> int:
	return board.depth(c)


func density_at(c: Vector2i) -> float:
	return rules.density(board.depth(c))


## Share of flags that sit on real mines (1.0 when no flags are placed).
func flags_correct() -> float:
	if board.flags.is_empty():
		return 1.0
	var right := 0
	for c: Vector2i in board.flags:
		if board.is_mine(c):
			right += 1
	return float(right) / float(board.flags.size())


# --- internals ----------------------------------------------------------------

func _apply(rec: Dictionary, res: MoveResult) -> void:
	res.revealed = rec.cells
	res.rings = rec.rings
	res.hits = rec.hits
	var safe_count := 0
	for cell: Vector2i in rec.cells:
		if board.state_at(cell) == Board.HIT:
			solver.add_mine(cell)
			res.numbers.append(-1)
			hits += 1
			_lose_link(res)
		else:
			var n := board.number(cell)
			res.numbers.append(n)
			solver.add_number(cell, n)
			score += n
			res.score_delta += n
			tally[n] += 1
			tiles += 1
			safe_count += 1
			deepest = maxi(deepest, board.depth(cell))
	if safe_count > 0:
		var refill := mini(rules.refill_cap_u, rules.refill_per_cell_u * safe_count)
		signal_u = mini(rules.signal_max_u, signal_u + refill)
	res.game_over = over


func _lose_link(res: MoveResult) -> void:
	links_lost += 1
	res.links_lost += 1
	if immortal:
		return
	links -= 1
	if links <= 0:
		links = 0
		over = true
		_finish()


## Records how the run ended, so a replay can check its score.
func _finish() -> void:
	move_log.end_ms = elapsed_ms
	move_log.final_score = score


func _after_move() -> void:
	solver.solve(true)
	if solver.contradiction:
		gen.events.append({"type": "solver_contradiction", "move": moves})
	if not solver.has_safe():
		backstop_armed = true
		stuck_count += 1
		gen.events.append({"type": "stuck", "move": moves})
