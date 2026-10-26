class_name Generator
extends RefCounted
## Decides where the mines are, so the player never faces a 50/50.
##
## Chunks start as drafts from the seed. A chunk locks the moment the player can
## see anything that depends on it (a revealed cell inside it or touching it);
## locked chunks never change, except through the logged backstop.
##
## Before a chunk locks, the solver plays forward in simulation from exactly
## what the player can see and must decrypt every safe cell in that chunk. If it
## can't, unlocked cells near the stuck spot are re-rolled and the move is tried
## again. Because the solver is monotone and the player can only ever learn more,
## a proof made at lock time stays true for the rest of the run. That gives:
##   * no dead pockets: every safe cell in a proven chunk stays solvable, and
##   * the spec invariant: while a proven chunk still has an unrevealed safe
##     cell, some frontier cell is provably safe right now.
##
## A proof relies on specific cells (each simulated reveal and its neighbours).
## Chunk-wide rerolls never touch those pinned cells. Local repairs may, but
## then every proof that relied on a changed cell is re-run and must still
## reach every cell it reached before, or the attempt is rejected; a
## transaction that runs out of attempts puts back everything it changed.
## Cells an earlier proof reached are part of what the player can eventually
## see, so later proofs start from them too (proofs only build on earlier
## proofs, never on later ones). Flags are never read here.

const NB := Board.NB

var board: Board
var rules: Rules
var proofs := {}       # chunk key -> Dictionary(cell -> true) of cells the proof relies on
var proof_order := {}  # chunk key -> order the proof was committed in
var proof_sims := {}   # chunk key -> Array of cells the proof revealed in simulation
var proven_at := {}    # cell -> order of the first proof that reached it
var pinned := {}       # union of every proof's cells
var events: Array[Dictionary] = []
var move_index := 0
var profile := false
var proof_usec := PackedInt64Array()
var txn_usec := PackedInt64Array()
var stats := {
	"transactions": 0, "locks": 0, "proofs": 0, "proof_fails": 0, "attempts": 0,
	"repair_local": 0, "repair_chunk": 0, "repair_neighbour": 0,
	"pockets": 0, "pockets_near_island": 0, "islands": 0, "rescues": 0, "rescue_fails": 0,
	"unsound": 0, "contradictions": 0, "cap_hits": 0, "rechecks": 0, "recheck_fails": 0,
	"reverts": 0,
}

var _any_locked := false
var _next_order := 0
const _REPAIR_STAT := ["repair_local", "repair_chunk", "repair_neighbour"]


func _init(p_board: Board, p_rules: Rules) -> void:
	board = p_board
	rules = p_rules


## Reveals the clicked cells as one transaction: apply, prove every chunk that
## would lock, and on failure undo, repair and retry. Voluntary clicks (not next
## to anything revealed) lock their chunks as islands without a proof.
func reveal(clicks: Array[Vector2i], voluntary: bool) -> Dictionary:
	var t0 := Time.get_ticks_usec() if profile else 0
	stats.transactions += 1
	var first := not _any_locked
	var hold := {}
	for c in clicks:
		hold[c] = true
	var stage_len: Array[int] = [rules.attempts_local, rules.attempts_chunk, rules.attempts_neighbour]
	var stage := 0
	var in_stage := 0
	var orig := {}       # cell -> its mine value before this transaction changed it
	var affected := {}   # earlier proofs that relied on a changed cell
	var rec: Dictionary
	while true:
		rec = board.apply_reveals(clicks)
		var new_locks := _touched_unlocked(rec.cells)
		if voluntary and not first:
			_commit(new_locks, {}, true, {})
			break
		var results := {}
		var failed: Array[Vector2i] = []
		for k in new_locks:
			var p := prove_chunk(k)
			results[k] = p
			if not p.ok:
				failed.append(k)
		var recheck := _recheck(affected)
		var short_opening := first and _safe_count(rec) < rules.min_opening
		if failed.is_empty() and recheck.ok and not short_opening:
			_commit(new_locks, results, false, recheck.updates)
			break
		stats.proof_fails += failed.size()
		for k: Vector2i in recheck.failed:
			failed.append(k)
			results[k] = recheck.results[k]
		board.undo_reveals(rec)
		var targets: Array[Vector2i] = failed
		if targets.is_empty():
			targets = [board.chunk_key(board.origin)]
		var changed := {}
		while changed.is_empty() and stage < 3:
			if in_stage >= stage_len[stage]:
				stage += 1
				in_stage = 0
				continue
			in_stage += 1
			changed = _repair(stage, targets, results, hold)
			if changed.is_empty():
				stage += 1
				in_stage = 0
		if changed.is_empty():
			# Out of attempts. Put back everything this transaction changed, so
			# every earlier proof holds exactly as it did, and lock as-is: chunks
			# that fail become pockets (logged; the spec invariant is still
			# checked after the move).
			if not orig.is_empty():
				stats.reverts += 1
				for c: Vector2i in orig:
					board.set_mine(c, orig[c])
			rec = board.apply_reveals(clicks)
			var locks := _touched_unlocked(rec.cells)
			var final := {}
			for k in locks:
				final[k] = prove_chunk(k)
			_commit(locks, final, false, {})
			break
		for c: Vector2i in changed:
			if not orig.has(c):
				orig[c] = changed[c]
			for k in _dependents(c):
				affected[k] = true
		stats.attempts += 1
	if profile:
		txn_usec.append(Time.get_ticks_usec() - t0)
	return rec


## Plays the solver forward from what the player can see, revealing (in
## simulation only) every cell it proves safe inside chunk k plus a margin.
## ok = every safe cell of k was reached. It also starts from cells earlier
## proofs reached; with before >= 0 only from proofs committed before that
## order (used to re-check the whole chain without circular support).
func prove_chunk(k: Vector2i, before := -1) -> Dictionary:
	var t0 := Time.get_ticks_usec() if profile else 0
	var margin := rules.proof_margin
	var corner := board.chunk_corner(k)
	var q0 := corner - Vector2i(margin, margin)
	var q1 := corner + Vector2i(Chunk.SIZE - 1 + margin, Chunk.SIZE - 1 + margin)
	var pad := rules.window_radius + 1
	var s := Solver.from_rules(rules)
	var unsound := false
	for y in range(q0.y - pad, q1.y + pad + 1):
		for x in range(q0.x - pad, q1.x + pad + 1):
			var c := Vector2i(x, y)
			var st := board.state_at(c)
			if st == Board.REVEALED:
				s.add_number(c, board.number(c))
			elif st == Board.HIT:
				s.add_mine(c)
			elif proven_at.has(c) and (before < 0 or proven_at[c] < before):
				if board.is_mine(c):
					unsound = true
				else:
					s.add_number(c, board.number(c))
	var sim: Array[Vector2i] = []
	s.solve()
	while not s.contradiction:
		var any := false
		for c in s.take_new_safe():
			if c.x < q0.x or c.y < q0.y or c.x > q1.x or c.y > q1.y:
				continue
			if board.is_mine(c):
				unsound = true
				break
			s.add_number(c, board.number(c))
			sim.append(c)
			any = true
		if unsound or not any:
			break
		s.solve()
	if unsound:
		stats.unsound += 1
		push_error("solver proved a mine safe (seed %d, move %d)" % [board.seed, move_index])
	if s.contradiction:
		stats.contradictions += 1
		push_error("solver contradiction while proving chunk %s (seed %d, move %d)" % [k, board.seed, move_index])
	stats.cap_hits += s.stats.cap_hits

	var edge: Array[Vector2i] = []
	var other: Array[Vector2i] = []
	var uncovered := 0
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var c := corner + Vector2i(lx, ly)
			if board.is_mine(c) or board.is_revealed(c) or s.num.has(c):
				continue
			uncovered += 1
			var touches := false
			for d in NB:
				if board.is_open(c + d) or s.num.has(c + d):
					touches = true
					break
			if touches:
				edge.append(c)
			else:
				other.append(c)
	var stuck: Array[Vector2i] = edge if not edge.is_empty() else other
	var cells := {}
	for c in sim:
		cells[c] = true
		for d in NB:
			cells[c + d] = true
	if profile:
		proof_usec.append(Time.get_ticks_usec() - t0)
	return {
		"ok": uncovered == 0 and not unsound and not s.contradiction,
		"cells": cells,
		"stuck": stuck,
		"uncovered": uncovered,
		"sim": sim,
	}


## Backstop: makes frontier cell c safe by moving mines among hidden cells near
## it so that every revealed number still matches. Only ever called after the
## solver found no provably safe frontier cell (which should never happen).
func rescue(c: Vector2i) -> bool:
	for r in rules.rescue_radii:
		var changes: Variant = _rearrange(c, r)
		if changes == null:
			continue
		for cell: Vector2i in changes:
			board.set_mine(cell, changes[cell])
		stats.rescues += 1
		events.append({"type": "rescue", "move": move_index, "cell": c, "radius": r,
			"changed": changes.size(), "map": board.ascii(c, 8)})
		_reprove_after_change(changes.keys())
		return true
	stats.rescue_fails += 1
	events.append({"type": "rescue_failed", "move": move_index, "cell": c, "map": board.ascii(c, 8)})
	return false


# --- internals ----------------------------------------------------------------

func _touched_unlocked(cells: Array[Vector2i]) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := board.chunk_key(c + Vector2i(dx, dy))
				if seen.has(k):
					continue
				seen[k] = true
				if not board.chunk(k).locked:
					out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func _safe_count(rec: Dictionary) -> int:
	return rec.cells.size() - rec.hits.size()


func _commit(new_locks: Array[Vector2i], results: Dictionary, voluntary: bool, updates: Dictionary) -> void:
	# Earlier proofs re-run after a local repair (each still reaches all it did).
	for k: Vector2i in updates:
		var u: Dictionary = updates[k]
		proofs[k] = u.cells
		proof_sims[k] = u.sim
		for c in u.cells:
			pinned[c] = true
		for c: Vector2i in u.sim:
			if not proven_at.has(c):
				proven_at[c] = proof_order[k]
	for k in new_locks:
		var ch := board.chunk(k)
		ch.locked = true
		stats.locks += 1
		if voluntary:
			ch.island = true
			stats.islands += 1
			continue
		var p: Dictionary = results.get(k, {})
		if p.get("ok", false):
			ch.proven = true
			stats.proofs += 1
			proofs[k] = p.cells
			proof_sims[k] = p.sim
			proof_order[k] = _next_order
			for c in p.cells:
				pinned[c] = true
			for c: Vector2i in p.sim:
				if not proven_at.has(c):
					proven_at[c] = _next_order
			_next_order += 1
		else:
			ch.pocket = true
			# A pocket next to an island is fallout from the player's own far
			# click; count it apart from the ones that should never happen.
			var near_island := _near_island(k)
			stats["pockets_near_island" if near_island else "pockets"] += 1
			events.append({"type": "pocket", "move": move_index, "chunk": k,
				"uncovered": p.get("uncovered", -1), "near_island": near_island})
	_any_locked = true


func _near_island(k: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := k + Vector2i(dx, dy)
			if board.has_chunk(n) and board.chunk(n).island:
				return true
	return false


## Cell c is in an unlocked chunk and may be re-rolled by a local repair.
## Pinned cells are allowed (their proofs get re-checked); cells a proof has
## already shown to be safe are not.
func _changeable(c: Vector2i, hold: Dictionary) -> bool:
	return not board.chunk_at(c).locked and not board.in_start_zone(c) and not hold.has(c) \
		and not proven_at.has(c)


## Cell c may be re-rolled by a chunk-wide reroll: changeable and not pinned.
func _free(c: Vector2i, hold: Dictionary) -> bool:
	return _changeable(c, hold) and not pinned.has(c)


## Proofs that rely on cell c. A proof only relies on cells within its chunk
## plus margin + 1, so only the 3x3 block of chunks around c can contain one.
func _dependents(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ck := board.chunk_key(c)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k := ck + Vector2i(dx, dy)
			if proofs.has(k) and proofs[k].has(c):
				out.append(k)
	return out


## Re-runs the given earlier proofs (in commit order). Each must still cover
## its chunk and still reach every cell it reached before, so later proofs
## that started from those cells stay valid.
func _recheck(affected: Dictionary) -> Dictionary:
	var out := {"ok": true, "updates": {}, "failed": [] as Array[Vector2i], "results": {}}
	if affected.is_empty():
		return out
	var keys := affected.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return proof_order[a] < proof_order[b])
	for k: Vector2i in keys:
		stats.rechecks += 1
		var order: int = proof_order[k]
		var p := prove_chunk(k, order)
		var ok: bool = p.ok
		if ok:
			var now := {}
			for c: Vector2i in p.sim:
				now[c] = true
			for c: Vector2i in proof_sims[k]:
				if not (now.has(c) or board.is_open(c) or proven_at.get(c, order) < order):
					ok = false
					break
		if ok:
			out.updates[k] = p
		else:
			stats.recheck_fails += 1
			out.ok = false
			out.failed.append(k)
			out.results[k] = p
	return out


## Re-rolls cells. Stage 0: changeable cells near the stuck spots. Stage 1:
## every free cell of the failed chunk. Stage 2: the failed chunk and its
## neighbours. Returns {cell: previous mine value} for the cells that actually
## changed; empty if there was nothing to re-roll.
func _repair(stage: int, targets: Array[Vector2i], results: Dictionary, hold: Dictionary) -> Dictionary:
	var cells := {}
	if stage == 0:
		var r := rules.local_repair_radius
		for k in targets:
			var stuck: Array[Vector2i] = results.get(k, {}).get("stuck", [] as Array[Vector2i])
			for i in mini(stuck.size(), rules.local_repair_cells):
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var c := stuck[i] + Vector2i(dx, dy)
						if _changeable(c, hold):
							cells[c] = true
	else:
		for k in targets:
			if stage == 1:
				_add_free_chunk_cells(k, cells, hold)
			else:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						_add_free_chunk_cells(k + Vector2i(dx, dy), cells, hold)
	var changed := {}
	if cells.is_empty():
		return changed
	var bumped := {}
	for c: Vector2i in cells:
		var k := board.chunk_key(c)
		if not bumped.has(k):
			board.chunk(k).attempt += 1
			bumped[k] = true
	for c: Vector2i in cells:
		var was := board.is_mine(c)
		var now := board.draw_mine(c, board.chunk_at(c).attempt)
		if now != was:
			board.set_mine(c, now)
			changed[c] = was
	stats[_REPAIR_STAT[stage]] += 1
	if changed.is_empty():
		# Same layout by chance: report one unchanged cell so the stage still
		# counts as an attempt (the next one draws with a new salt).
		var any: Vector2i = cells.keys()[0]
		changed[any] = board.is_mine(any)
	return changed


func _add_free_chunk_cells(k: Vector2i, cells: Dictionary, hold: Dictionary) -> void:
	if board.chunk(k).locked:
		return
	var corner := board.chunk_corner(k)
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var c := corner + Vector2i(lx, ly)
			if _free(c, hold):
				cells[c] = true


## Finds mine values for the hidden cells within r of c that touch a revealed
## number, with c safe, such that every revealed number still matches. Prefers
## each cell's current value. Returns {cell: is_mine} for the cells that change,
## or null if impossible.
func _rearrange(c: Vector2i, r: int) -> Variant:
	var vars: Array[Vector2i] = []
	var var_of := {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var v := c + Vector2i(dx, dy)
			if board.is_revealed(v):
				continue
			var touches := v == c
			for d in NB:
				if board.is_open(v + d):
					touches = true
					break
			if touches:
				var_of[v] = vars.size()
				vars.append(v)
	var need := PackedInt32Array()
	var con_vars: Array[PackedInt32Array] = []
	var seen := {}
	for v in vars:
		for d in NB:
			var p := v + d
			if seen.has(p) or not board.is_open(p):
				continue
			seen[p] = true
			var n := board.number(p)
			var idxs := PackedInt32Array()
			for d2 in NB:
				var q := p + d2
				if var_of.has(q):
					idxs.append(var_of[q])
				elif board.is_mine(q):
					n -= 1
			need.append(n)
			con_vars.append(idxs)
	var var_cons: Array[PackedInt32Array] = []
	for v in vars.size():
		var_cons.append(PackedInt32Array())
	for ci in need.size():
		for v in con_vars[ci]:
			var_cons[v].append(ci)
	var left := PackedInt32Array()
	for ci in need.size():
		left.append(con_vars[ci].size())
	var mines := PackedInt32Array()
	mines.resize(need.size())
	mines.fill(0)
	var assign := PackedInt32Array()
	assign.resize(vars.size())
	var prefer := PackedInt32Array()
	for v in vars:
		prefer.append(0 if v == c else (1 if board.is_mine(v) else 0))
	var ctx := {"nodes": 0}
	if not _rearrange_bt(0, vars, prefer, var_cons, need, mines, left, assign, var_of[c], ctx):
		return null
	var changes := {}
	for i in vars.size():
		var m := assign[i] == 1
		if m != board.is_mine(vars[i]):
			changes[vars[i]] = m
	return changes


func _rearrange_bt(i: int, vars: Array[Vector2i], prefer: PackedInt32Array,
		var_cons: Array[PackedInt32Array], need: PackedInt32Array, mines: PackedInt32Array,
		left: PackedInt32Array, assign: PackedInt32Array, forced: int, ctx: Dictionary) -> bool:
	ctx.nodes += 1
	if ctx.nodes > rules.node_cap:
		return false
	if i == vars.size():
		for ci in need.size():
			if mines[ci] != need[ci]:
				return false
		return true
	var order := [0] if i == forced else [prefer[i], 1 - prefer[i]]
	for val: int in order:
		var ok := true
		for ci in var_cons[i]:
			mines[ci] += val
			left[ci] -= 1
			var rem := need[ci] - mines[ci]
			if rem < 0 or rem > left[ci]:
				ok = false
		if ok:
			assign[i] = val
			if _rearrange_bt(i + 1, vars, prefer, var_cons, need, mines, left, assign, forced, ctx):
				return true
		for ci in var_cons[i]:
			mines[ci] -= val
			left[ci] += 1
	return false


## After the backstop moves mines, redo every proof that relied on a changed
## cell or covers a chunk that contains one.
func _reprove_after_change(changed: Array) -> void:
	var redo := {}
	for c: Vector2i in changed:
		redo[board.chunk_key(c)] = true
	for k in proofs:
		for c: Vector2i in changed:
			if proofs[k].has(c):
				redo[k] = true
				break
	# Cells reached by the redone proofs may no longer be reachable, so forget
	# them before re-proving (in commit order, each from the ones before it).
	var order := redo.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return proof_order.get(a, -1) < proof_order.get(b, -1))
	for k: Vector2i in order:
		if proof_order.has(k):
			var mine_order: int = proof_order[k]
			for c in proven_at.keys():
				if proven_at[c] == mine_order:
					proven_at.erase(c)
	for k: Vector2i in order:
		var ch := board.chunk(k)
		if not ch.proven:
			continue
		var p := prove_chunk(k, proof_order[k])
		if p.ok:
			proofs[k] = p.cells
			proof_sims[k] = p.sim
			for c: Vector2i in p.sim:
				if not proven_at.has(c) or proven_at[c] > proof_order[k]:
					proven_at[c] = proof_order[k]
		else:
			proofs.erase(k)
			proof_order.erase(k)
			proof_sims.erase(k)
			ch.proven = false
			ch.pocket = true
			stats.pockets += 1
			events.append({"type": "pocket", "move": move_index, "chunk": k, "uncovered": p.uncovered,
				"after": "rescue"})
	pinned.clear()
	for k in proofs:
		for c in proofs[k]:
			pinned[c] = true
