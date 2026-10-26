class_name Solver
extends RefCounted
## The reference solver: which hidden cells are provably safe or provably mines,
## given only revealed numbers and revealed mines. Flags are not an input.
##
## Tiers (max_tier limits which run, for the M2 bot skill levels):
##   1. single-cell rules: a number's remaining mines are 0, or equal its hidden count
##   2. subset/difference: constraint A's cells inside B's => B minus A holds b - a mines
##   3. exact enumeration in a fixed window: every mine layout that fits the numbers
##      within window_radius of a revealed number cell
##
## Every rule only proves things that are definitely true, and every rule is
## monotone: learning more never un-proves a cell. That is what makes the
## generator's proofs hold for the rest of a run. Tier 3 windows are centred on
## revealed number cells (which never go away) rather than on frontier cells or
## whole components, because either of those would let a proof disappear as the
## frontier changes.

const NB := Board.NB

var max_tier := 3
var window_radius := 2
var node_cap := 100000

var num := {}      # Vector2i -> int: revealed safe cells (real or simulated) and their number
var mine := {}     # Vector2i -> int tier: 0 = revealed mine, 1..3 = deduced
var safe := {}     # Vector2i -> int tier: deduced safe, not revealed yet
var wall := {}     # Vector2i -> true: known safe, no number (test fixtures only)
var active := {}   # number cells that still have an unknown neighbour

var contradiction := false
var stats := {"t1": 0, "t2": 0, "t3": 0, "windows": 0, "cap_hits": 0, "nodes": 0}

var _q1: Array[Vector2i] = []
var _in_q1 := {}
var _changed2 := {}
var _changed3 := {}
var _new_safe: Array[Vector2i] = []
var _win_offsets: Array[Vector2i] = []

# Tier-3 search state (members so the recursion stays allocation-free).
var _w_nv := 0
var _w_assign := PackedInt32Array()
var _w_var_cons: Array[PackedInt32Array] = []
var _w_need := PackedInt32Array()
var _w_mines := PackedInt32Array()
var _w_left := PackedInt32Array()
var _w_can_mine := PackedByteArray()
var _w_can_safe := PackedByteArray()
var _w_open := 0
var _w_nodes := 0
var _w_solutions := 0
var _w_stop := false
var _w_capped := false


func _init(p_max_tier := 3, p_window_radius := 2, p_node_cap := 100000) -> void:
	max_tier = p_max_tier
	window_radius = p_window_radius
	node_cap = p_node_cap
	for ring in window_radius + 1:
		for dy in range(-window_radius, window_radius + 1):
			for dx in range(-window_radius, window_radius + 1):
				if maxi(absi(dx), absi(dy)) == ring:
					_win_offsets.append(Vector2i(dx, dy))


static func from_rules(rules: Rules, tier := 3) -> Solver:
	return Solver.new(tier, rules.window_radius, rules.node_cap)


# --- input --------------------------------------------------------------------

func add_number(c: Vector2i, n: int) -> void:
	if num.has(c):
		return
	if mine.has(c):
		contradiction = true
		return
	num[c] = n
	safe.erase(c)
	_touch(c)


func add_mine(c: Vector2i) -> void:
	if mine.has(c):
		mine[c] = 0
		return
	if num.has(c) or safe.has(c) or wall.has(c):
		contradiction = true
		return
	mine[c] = 0
	_touch(c)


func add_wall(c: Vector2i) -> void:
	wall[c] = true
	_touch(c)


# --- queries ------------------------------------------------------------------

func is_unknown(c: Vector2i) -> bool:
	return not (num.has(c) or mine.has(c) or safe.has(c) or wall.has(c))


func has_safe() -> bool:
	return not safe.is_empty()


func is_proven_mine(c: Vector2i) -> bool:
	return mine.has(c)


## Deduced-safe cells learned since the last call (still unrevealed).
func take_new_safe() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _new_safe:
		if safe.has(c):
			out.append(c)
	_new_safe.clear()
	return out


# --- solving ------------------------------------------------------------------

## Runs the enabled tiers to a fixpoint. With stop_on_safe it returns as soon as
## any provably safe cell is known (the rest of the work stays queued).
func solve(stop_on_safe := false) -> void:
	while not contradiction:
		_run_tier1(stop_on_safe)
		if contradiction or (stop_on_safe and not safe.is_empty()):
			return
		if max_tier >= 2 and _run_tier2():
			continue
		if max_tier >= 3 and _run_tier3(stop_on_safe):
			continue
		return


func _touch(c: Vector2i) -> void:
	if num.has(c):
		_enqueue(c)
	for d in NB:
		var p := c + d
		if num.has(p):
			_enqueue(p)


func _enqueue(p: Vector2i) -> void:
	_changed2[p] = true
	_changed3[p] = true
	if not _in_q1.has(p):
		_in_q1[p] = true
		_q1.append(p)


## Returns true if c was not already known.
func _learn(c: Vector2i, is_mine: bool, tier: int) -> bool:
	if is_mine:
		if mine.has(c):
			return false
		if num.has(c) or safe.has(c) or wall.has(c):
			contradiction = true
			return false
		mine[c] = tier
	else:
		if safe.has(c) or num.has(c) or wall.has(c):
			return false
		if mine.has(c):
			contradiction = true
			return false
		safe[c] = tier
		_new_safe.append(c)
	stats["t%d" % tier] += 1
	_touch(c)
	return true


## [remaining mines, unknown neighbours] of number cell p.
func _constraint(p: Vector2i) -> Array:
	var unk: Array[Vector2i] = []
	var m := 0
	for d in NB:
		var q := p + d
		if mine.has(q):
			m += 1
		elif not (num.has(q) or safe.has(q) or wall.has(q)):
			unk.append(q)
	return [num[p] - m, unk]


func _run_tier1(stop_on_safe: bool) -> void:
	while not _q1.is_empty():
		var p: Vector2i = _q1.pop_back()
		_in_q1.erase(p)
		var con := _constraint(p)
		var need: int = con[0]
		var unk: Array[Vector2i] = con[1]
		if unk.is_empty():
			active.erase(p)
			if need != 0:
				contradiction = true
			continue
		active[p] = true
		if need == 0:
			for q in unk:
				_learn(q, false, 1)
		elif need == unk.size():
			for q in unk:
				_learn(q, true, 1)
		elif need < 0 or need > unk.size():
			contradiction = true
		if contradiction or (stop_on_safe and not safe.is_empty()):
			return


func _run_tier2() -> bool:
	if _changed2.is_empty():
		return false
	var cands := _changed2.keys()
	_changed2.clear()
	var progress := false
	for a: Vector2i in cands:
		if not active.has(a):
			continue
		var ca := _constraint(a)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx == 0 and dy == 0:
					continue
				var b := a + Vector2i(dx, dy)
				if not active.has(b):
					continue
				var cb := _constraint(b)
				if _subset_rule(ca, cb):
					progress = true
					ca = _constraint(a)
				elif _subset_rule(cb, ca):
					progress = true
					ca = _constraint(a)
	return progress


## If small's cells are a strict subset of big's, the difference holds exactly
## (big - small) mines. Returns true if anything new was learned.
func _subset_rule(small: Array, big: Array) -> bool:
	var us: Array[Vector2i] = small[1]
	var ub: Array[Vector2i] = big[1]
	if us.is_empty() or us.size() >= ub.size():
		return false
	for q in us:
		if not ub.has(q):
			return false
	var r: int = big[0] - small[0]
	var diff: Array[Vector2i] = []
	for q in ub:
		if not us.has(q):
			diff.append(q)
	var learned := false
	if r == 0:
		for q in diff:
			learned = _learn(q, false, 2) or learned
	elif r == diff.size():
		for q in diff:
			learned = _learn(q, true, 2) or learned
	elif r < 0 or r > diff.size():
		contradiction = true
	return learned


func _run_tier3(stop_on_safe: bool) -> bool:
	if _changed3.is_empty():
		return false
	var centres := {}
	for p: Vector2i in _changed3:
		for off in _win_offsets:
			var c := p + off
			if num.has(c):
				centres[c] = true
	_changed3.clear()
	var progress := false
	var keys := centres.keys()
	for i in keys.size():
		if _solve_window(keys[i]):
			progress = true
		if contradiction:
			return progress
		if stop_on_safe and not safe.is_empty():
			# Requeue the centres we skipped; each centre is itself a number cell.
			for j in range(i + 1, keys.size()):
				_changed3[keys[j]] = true
			return progress
	return progress


## Exact enumeration over the active constraints within window_radius of centre.
func _solve_window(centre: Vector2i) -> bool:
	var var_of := {}
	var vars: Array[Vector2i] = []
	_w_need = PackedInt32Array()
	var con_vars: Array[PackedInt32Array] = []
	for off in _win_offsets:
		var p := centre + off
		if not active.has(p):
			continue
		var con := _constraint(p)
		var unk: Array[Vector2i] = con[1]
		if unk.is_empty():
			continue
		var idxs := PackedInt32Array()
		for q in unk:
			if not var_of.has(q):
				var_of[q] = vars.size()
				vars.append(q)
			idxs.append(var_of[q])
		_w_need.append(con[0])
		con_vars.append(idxs)
	var nc := _w_need.size()
	if nc == 0:
		return false
	stats.windows += 1
	_w_nv = vars.size()
	_w_var_cons.clear()
	for v in _w_nv:
		_w_var_cons.append(PackedInt32Array())
	for ci in nc:
		for v in con_vars[ci]:
			_w_var_cons[v].append(ci)
	_w_assign = PackedInt32Array()
	_w_assign.resize(_w_nv)
	_w_mines = PackedInt32Array()
	_w_mines.resize(nc)
	_w_mines.fill(0)
	_w_left = PackedInt32Array()
	_w_left.resize(nc)
	for ci in nc:
		_w_left[ci] = con_vars[ci].size()
	_w_can_mine = PackedByteArray()
	_w_can_mine.resize(_w_nv)
	_w_can_mine.fill(0)
	_w_can_safe = PackedByteArray()
	_w_can_safe.resize(_w_nv)
	_w_can_safe.fill(0)
	_w_open = _w_nv
	_w_nodes = 0
	_w_solutions = 0
	_w_stop = false
	_w_capped = false
	_bt(0)
	stats.nodes += _w_nodes
	if _w_capped:
		stats.cap_hits += 1
		return false
	if _w_solutions == 0:
		contradiction = true
		return false
	var learned := false
	for v in _w_nv:
		if _w_can_mine[v] == 0:
			learned = _learn(vars[v], false, 3) or learned
		elif _w_can_safe[v] == 0:
			learned = _learn(vars[v], true, 3) or learned
	return learned


func _bt(i: int) -> void:
	_w_nodes += 1
	if _w_nodes > node_cap:
		_w_stop = true
		_w_capped = true
		return
	if i == _w_nv:
		_w_solutions += 1
		for v in _w_nv:
			if _w_assign[v] == 1:
				if _w_can_mine[v] == 0:
					_w_can_mine[v] = 1
					if _w_can_safe[v] == 1:
						_w_open -= 1
			elif _w_can_safe[v] == 0:
				_w_can_safe[v] = 1
				if _w_can_mine[v] == 1:
					_w_open -= 1
		if _w_open == 0:
			_w_stop = true
		return
	# Try the value this variable hasn't been seen with yet first: once every
	# variable has been seen both ways nothing is provable and the search stops.
	var first := 1 if _w_can_mine[i] == 0 else 0
	for k in 2:
		var val := first if k == 0 else 1 - first
		if _try_assign(i, val):
			_bt(i + 1)
			_unassign(i, val)
		if _w_stop:
			return


func _try_assign(v: int, val: int) -> bool:
	var cons := _w_var_cons[v]
	var ok := true
	for ci in cons:
		_w_mines[ci] += val
		_w_left[ci] -= 1
		var rem := _w_need[ci] - _w_mines[ci]
		if rem < 0 or rem > _w_left[ci]:
			ok = false
	if not ok:
		for ci in cons:
			_w_mines[ci] -= val
			_w_left[ci] += 1
		return false
	_w_assign[v] = val
	return true


func _unassign(v: int, val: int) -> void:
	for ci in _w_var_cons[v]:
		_w_mines[ci] -= val
		_w_left[ci] += 1
	_w_assign[v] = -1
