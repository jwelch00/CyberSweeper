class_name Brute
extends RefCounted
## Exact answer by exhaustive search over every constraint at once (no windows,
## no rules). Only for small test positions.
## Returns {"safe": {cell: true}, "mine": {cell: true}} over the unknown cells
## that touch a revealed number.

static func solve(s: Solver) -> Dictionary:
	var vars: Array[Vector2i] = []
	var var_of := {}
	var need := PackedInt32Array()
	var con_vars: Array[PackedInt32Array] = []
	for p: Vector2i in s.num:
		var idxs := PackedInt32Array()
		var n: int = s.num[p]
		for d in Board.NB:
			var q := p + d
			if s.mine.has(q) and s.mine[q] == 0:
				n -= 1
			elif not (s.num.has(q) or s.wall.has(q) or s.mine.has(q) or s.safe.has(q)):
				if not var_of.has(q):
					var_of[q] = vars.size()
					vars.append(q)
				idxs.append(var_of[q])
			elif s.mine.has(q):
				# a deduced mine: treat as a variable too, so brute force is independent
				if not var_of.has(q):
					var_of[q] = vars.size()
					vars.append(q)
				idxs.append(var_of[q])
			elif s.safe.has(q):
				if not var_of.has(q):
					var_of[q] = vars.size()
					vars.append(q)
				idxs.append(var_of[q])
		if idxs.size() > 0:
			need.append(n)
			con_vars.append(idxs)
	var nv := vars.size()
	var var_cons: Array[PackedInt32Array] = []
	for v in nv:
		var_cons.append(PackedInt32Array())
	for ci in need.size():
		for v in con_vars[ci]:
			var_cons[v].append(ci)
	var st := {
		"assign": PackedInt32Array(), "mines": PackedInt32Array(), "left": PackedInt32Array(),
		"can_mine": PackedByteArray(), "can_safe": PackedByteArray(), "solutions": 0,
	}
	st.assign.resize(nv)
	st.mines.resize(need.size())
	st.mines.fill(0)
	for ci in need.size():
		st.left.append(con_vars[ci].size())
	st.can_mine.resize(nv)
	st.can_mine.fill(0)
	st.can_safe.resize(nv)
	st.can_safe.fill(0)
	_bt(0, nv, var_cons, need, st)
	var out := {"safe": {}, "mine": {}, "solutions": st.solutions}
	for v in nv:
		if st.can_mine[v] == 0:
			out.safe[vars[v]] = true
		elif st.can_safe[v] == 0:
			out.mine[vars[v]] = true
	return out


static func _bt(i: int, nv: int, var_cons: Array[PackedInt32Array], need: PackedInt32Array, st: Dictionary) -> void:
	if i == nv:
		st.solutions += 1
		for v in nv:
			if st.assign[v] == 1:
				st.can_mine[v] = 1
			else:
				st.can_safe[v] = 1
		return
	for val in 2:
		var ok := true
		for ci in var_cons[i]:
			st.mines[ci] += val
			st.left[ci] -= 1
			var rem: int = need[ci] - st.mines[ci]
			if rem < 0 or rem > st.left[ci]:
				ok = false
		if ok:
			st.assign[i] = val
			_bt(i + 1, nv, var_cons, need, st)
		for ci in var_cons[i]:
			st.mines[ci] -= val
			st.left[ci] += 1
