class_name MiniBoard
extends RefCounted
## A small finite board with walls around it, for checking the solver against
## brute force and against the real mine layout.

var w: int
var h: int
var mines := {}      # Vector2i -> true
var revealed := {}   # Vector2i -> true (safe cells only)
var hit := {}        # Vector2i -> true (revealed mines)


func _init(p_w: int, p_h: int, density: float, rng: RandomNumberGenerator) -> void:
	w = p_w
	h = p_h
	for y in h:
		for x in w:
			if rng.randf() < density:
				mines[Vector2i(x, y)] = true


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func number(c: Vector2i) -> int:
	var n := 0
	for d in Board.NB:
		if mines.has(c + d):
			n += 1
	return n


## Reveals c and cascades through zeros.
func open(c: Vector2i) -> void:
	if not inside(c) or revealed.has(c):
		return
	if mines.has(c):
		hit[c] = true
		return
	var stack: Array[Vector2i] = [c]
	revealed[c] = true
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if number(p) != 0:
			continue
		for d in Board.NB:
			var q := p + d
			if inside(q) and not revealed.has(q) and not mines.has(q):
				revealed[q] = true
				stack.append(q)


## A random safe hidden cell next to the revealed area, or null.
func random_safe_frontier(rng: RandomNumberGenerator) -> Variant:
	var cands: Array[Vector2i] = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if revealed.has(c) or mines.has(c):
				continue
			for d in Board.NB:
				if revealed.has(c + d):
					cands.append(c)
					break
	if cands.is_empty():
		return null
	return cands[rng.randi_range(0, cands.size() - 1)]


func random_safe(rng: RandomNumberGenerator) -> Variant:
	var cands: Array[Vector2i] = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if not mines.has(c) and not revealed.has(c):
				cands.append(c)
	if cands.is_empty():
		return null
	return cands[rng.randi_range(0, cands.size() - 1)]


## Solver loaded with what's visible. Outside the board is a wall.
func solver(tier := 3, radius := 2) -> Solver:
	var s := Solver.new(tier, radius, 1000000)
	for y in range(-1, h + 1):
		for x in range(-1, w + 1):
			var c := Vector2i(x, y)
			if not inside(c):
				s.add_wall(c)
			elif revealed.has(c):
				s.add_number(c, number(c))
			elif hit.has(c):
				s.add_mine(c)
	return s


func copy() -> MiniBoard:
	var b := MiniBoard.new(w, h, 0.0, RandomNumberGenerator.new())
	b.mines = mines.duplicate()
	b.revealed = revealed.duplicate()
	b.hit = hit.duplicate()
	return b
