class_name Bot
extends RefCounted
## A headless player: the three rivals, and the reference profile used to tune
## run length. A bot sees only what a player sees: it keeps its own solver,
## limited to its tier, fed from the cells each move revealed. Every action
## thinks first (tick), then acts, so the signal drains while it thinks.

const DEFAULT_PATH := "res://data/bots.json"
## How close (squared cells) a planned cell must be to the last click to be a
## quick follow-up.
const FOLLOWUP_REACH := 8
const NB := Board.NB

var id: String
var profile: Dictionary
var tier: int
var solver: Solver
var rng := RandomNumberGenerator.new()
var last := Vector2i.ZERO
## Safe cells the bot had worked out at its last full think. Clicking one of
## these right next to the last click is a quick follow-up, not a new think.
var _planned := {}
var stats := {"actions": 0, "quick": 0, "guesses": 0, "searches": 0, "misclicks": 0, "chords": 0, "flags": 0, "think_ms": 0,
	"by_tier": [0, 0, 0, 0]}


static func load_profiles(path := DEFAULT_PATH) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(d is Dictionary, "bot profiles are not a JSON object: " + path)
	var out := {}
	for k in d:
		if not k.begins_with("_"):
			out[k] = d[k]
	return out


func _init(p_id: String, p_profile: Dictionary, rules: Rules, seed: int) -> void:
	id = p_id
	profile = p_profile
	tier = int(profile.tier)
	solver = Solver.new(tier, rules.window_radius, rules.node_cap)
	rng.seed = seed


## Plays a whole run from the first click until game over (or max_ms of run time).
func play(gs: GameState, start: Vector2i, max_ms: int) -> void:
	_think(gs, 0)
	if gs.over:
		return
	_observe(gs, gs.reveal(start))
	last = start
	while not gs.over and gs.elapsed_ms < max_ms:
		turn(gs)


## One action: pick a move, think, then click or chord.
func turn(gs: GameState) -> void:
	solver.solve()
	stats.actions += 1
	var extra := 0
	var target: Variant = null
	if not solver.safe.is_empty():
		var near := _nearest(solver.safe.keys())
		if _dist2(near, last) <= int(profile.attention) * int(profile.attention):
			target = near
		elif rng.randf() >= float(profile.local_guess):
			# Nothing safe in view: look around the board for it.
			target = near
			extra = int(profile.search_ms)
			stats.searches += 1
	if target != null:
		var used: int = solver.safe[target]
		var quick: bool = extra == 0 and _planned.has(target) and _dist2(target, last) <= FOLLOWUP_REACH
		if not quick:
			_planned = solver.safe.duplicate()
		stats.by_tier[used] += 1
		var chord: Variant = _chord_for(gs, target) if profile.chord else null
		if chord != null:
			_do_chord(gs, chord, used, extra, quick)
		else:
			_click(gs, target, used, false, extra, quick)
		return
	var guess: Variant = _best_guess(gs)
	if guess == null:
		# Nothing visible to work from (should not happen): click next to the last move.
		guess = last + NB[rng.randi_range(0, 7)]
	stats.guesses += 1
	_planned.clear()
	_click(gs, guess, 0, true, 0, false)


func _click(gs: GameState, target: Vector2i, used_tier: int, guessing: bool, extra: int, quick: bool) -> void:
	var c := target
	if rng.randf() < float(profile.misclick):
		var opts: Array[Vector2i] = []
		for d in NB:
			var q := target + d
			if not gs.board.is_revealed(q) and not gs.board.is_flagged(q):
				opts.append(q)
		if not opts.is_empty():
			c = opts[rng.randi_range(0, opts.size() - 1)]
			stats.misclicks += 1
	if quick:
		_quick(gs)
	else:
		_think(gs, extra + (int(profile.guess_extra_ms) if guessing else int(profile.tier_extra_ms[used_tier])))
	if gs.over:
		return
	if gs.board.is_flagged(c):
		gs.flag(c)
	_observe(gs, gs.reveal(c))
	last = c


## Flags the known mines around number p (each flag costs time), then chords.
func _do_chord(gs: GameState, p: Vector2i, used_tier: int, extra: int, quick: bool) -> void:
	var to_flag: Array[Vector2i] = []
	for d in NB:
		var q := p + d
		if gs.board.state_at(q) == Board.HIDDEN and solver.mine.has(q) and not gs.board.is_flagged(q):
			to_flag.append(q)
	if quick:
		_quick(gs, to_flag.size() * int(profile.flag_ms))
	else:
		_think(gs, extra + int(profile.tier_extra_ms[used_tier]) + to_flag.size() * int(profile.flag_ms))
	if gs.over:
		return
	for q in to_flag:
		gs.flag(q)
		stats.flags += 1
	stats.chords += 1
	_observe(gs, gs.chord(p))
	last = p


## A revealed number next to target whose hidden neighbours are all known to
## this bot, with at least chord_min safe ones to open; or null.
func _chord_for(gs: GameState, target: Vector2i) -> Variant:
	for d in NB:
		var p := target + d
		if not solver.num.has(p):
			continue
		var safe_hidden := 0
		var ok := true
		for d2 in NB:
			var q := p + d2
			if gs.board.state_at(q) != Board.HIDDEN:
				continue
			if solver.safe.has(q):
				safe_hidden += 1
			elif not solver.mine.has(q):
				ok = false
				break
		if ok and safe_hidden >= int(profile.chord_min):
			return p
	return null


## The frontier cell that looks least likely to be a mine: for each unknown
## cell, the worst (remaining mines / unknown cells) over its numbers. Prefers
## cells within attention of the last click.
func _best_guess(gs: GameState) -> Variant:
	var est := {}
	for p: Vector2i in solver.active:
		var con := solver._constraint(p)
		var need: int = con[0]
		var unk: Array[Vector2i] = con[1]
		if unk.is_empty():
			continue
		var pr := float(need) / unk.size()
		for q in unk:
			if gs.board.is_flagged(q):
				continue
			est[q] = maxf(est.get(q, 0.0), pr)
	var best: Variant = null
	var best_p := 2.0
	var best_d := 1 << 30
	var reach := int(profile.attention) * int(profile.attention)
	var any_near := false
	for q: Vector2i in est:
		if _dist2(q, last) <= reach:
			any_near = true
			break
	for q: Vector2i in est:
		var d := _dist2(q, last)
		if any_near and d > reach:
			continue
		if est[q] < best_p - 1e-9 or (absf(est[q] - best_p) < 1e-9 and d < best_d):
			best = q
			best_p = est[q]
			best_d = d
	return best


func _nearest(cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d := _dist2(best, last)
	for c: Vector2i in cells:
		var d := _dist2(c, last)
		if d < best_d or (d == best_d and (c.y < best.y or (c.y == best.y and c.x < best.x))):
			best = c
			best_d = d
	return best


static func _dist2(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


## A quick follow-up click (plus any extra, e.g. placing flags), never under
## min_move_ms, so NULL//SAINT stays at human pace.
func _quick(gs: GameState, extra_ms := 0) -> void:
	var jitter := clampf(1.0 + 0.25 * rng.randfn(0.0, 1.0), 0.6, 1.8)
	var ms := maxi(int(profile.min_move_ms), int(float(profile.followup_ms) * jitter)) + extra_ms
	stats.think_ms += ms
	stats.quick += 1
	gs.tick(ms)


## Spends think time: log-normal around the median, never under the floor,
## plus extra for harder moves.
func _think(gs: GameState, extra_ms: int) -> void:
	var base := float(profile.think_median_ms) * exp(float(profile.think_sigma) * rng.randfn(0.0, 1.0))
	var ms := maxi(maxi(int(profile.think_min_ms), int(profile.min_move_ms)), int(base)) + extra_ms
	stats.think_ms += ms
	gs.tick(ms)


func _observe(gs: GameState, res: MoveResult) -> void:
	for c in res.revealed:
		if gs.board.state_at(c) == Board.HIT:
			solver.add_mine(c)
		else:
			solver.add_number(c, gs.board.number(c))
