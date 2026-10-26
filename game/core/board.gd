class_name Board
extends RefCounted
## The infinite minefield: chunk storage, mine drafts, numbers and cascades.
##
## Policy (when chunks lock, what may be re-rolled, proofs) lives in Generator.
## Coordinates are world cells. The first click becomes the origin and sits at
## local (8, 8) of chunk (0, 0), so the opening is never split across a corner.

const HIDDEN := 0
const REVEALED := 1
const HIT := 2   # a revealed mine: costs a link, then stays visible as a hazard

const NB: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var seed: int
var rules: Rules
var origin := Vector2i.ZERO
var started := false
var chunks := {}   # Vector2i chunk key -> Chunk
## Player flags, kept apart from chunk data so they can never touch generation.
var flags := {}    # Vector2i -> true

var _gx := -8   # chunk grid offset
var _gy := -8


func _init(p_seed: int, p_rules: Rules) -> void:
	seed = p_seed & CsHash.MASK32
	rules = p_rules


func start(at: Vector2i) -> void:
	assert(not started)
	origin = at
	started = true
	_gx = at.x - 8
	_gy = at.y - 8


# --- addressing ---------------------------------------------------------------

func chunk_key(c: Vector2i) -> Vector2i:
	return Vector2i((c.x - _gx) >> 4, (c.y - _gy) >> 4)


## Top-left cell of a chunk.
func chunk_corner(k: Vector2i) -> Vector2i:
	return Vector2i((k.x << 4) + _gx, (k.y << 4) + _gy)


func _idx(c: Vector2i) -> int:
	return ((c.x - _gx) & 15) | (((c.y - _gy) & 15) << 4)


## The chunk at key k, drafted from the seed if it doesn't exist yet.
func chunk(k: Vector2i) -> Chunk:
	var ch: Chunk = chunks.get(k)
	if ch == null:
		ch = _draft(k)
		chunks[k] = ch
	return ch


func chunk_at(c: Vector2i) -> Chunk:
	return chunk(chunk_key(c))


func has_chunk(k: Vector2i) -> bool:
	return chunks.has(k)


# --- drafting -----------------------------------------------------------------

func depth(c: Vector2i) -> int:
	var dx := c.x - origin.x
	var dy := c.y - origin.y
	return int(sqrt(float(dx * dx + dy * dy)))


func in_start_zone(c: Vector2i) -> bool:
	return started and absi(c.x - origin.x) <= 1 and absi(c.y - origin.y) <= 1


## Whether cell c is a mine in the draft keyed by salt. Salt 0 is the first
## draft; re-rolls use the chunk's attempt counter.
func draw_mine(c: Vector2i, salt: int) -> bool:
	if in_start_zone(c):
		return false
	return CsHash.hash4(seed, c.x, c.y, salt) < rules.mine_threshold(depth(c))


func _draft(k: Vector2i) -> Chunk:
	var ch := Chunk.new(k)
	var corner := chunk_corner(k)
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			if draw_mine(corner + Vector2i(lx, ly), 0):
				ch.mines[lx | (ly << 4)] = 1
	return ch


# --- cell queries -------------------------------------------------------------

func is_mine(c: Vector2i) -> bool:
	return chunk(chunk_key(c)).mines[_idx(c)] == 1


func set_mine(c: Vector2i, mine: bool) -> void:
	chunk(chunk_key(c)).mines[_idx(c)] = 1 if mine else 0


## Reveal state without drafting anything: missing chunks are all hidden.
func state_at(c: Vector2i) -> int:
	var ch: Chunk = chunks.get(chunk_key(c))
	if ch == null:
		return HIDDEN
	return ch.state[_idx(c)]


func is_revealed(c: Vector2i) -> bool:
	return state_at(c) != HIDDEN


## Revealed and safe (shows a number).
func is_open(c: Vector2i) -> bool:
	return state_at(c) == REVEALED


func is_flagged(c: Vector2i) -> bool:
	return flags.has(c)


func set_flag(c: Vector2i, on: bool) -> void:
	if on:
		flags[c] = true
	else:
		flags.erase(c)


func is_locked(c: Vector2i) -> bool:
	return chunk(chunk_key(c)).locked


func number(c: Vector2i) -> int:
	var n := 0
	for d in NB:
		if is_mine(c + d):
			n += 1
	return n


## Hidden and next to a revealed safe cell.
func is_frontier(c: Vector2i) -> bool:
	if is_revealed(c):
		return false
	for d in NB:
		if is_open(c + d):
			return true
	return false


# --- reveals ------------------------------------------------------------------

## Reveals each start cell and cascades through zeros (breadth-first, so cells
## come out in ring order). Cascades also clear flags: a zero proves its
## neighbours safe, so a flag there was wrong, and flags must never change what
## gets revealed. Returns a record that undo_reveals() can roll back.
func apply_reveals(starts: Array[Vector2i]) -> Dictionary:
	var cells: Array[Vector2i] = []
	var rings := PackedInt32Array()
	var hits: Array[Vector2i] = []
	var cleared_flags: Array[Vector2i] = []
	var head := 0
	for s in starts:
		if is_revealed(s):
			continue
		if is_flagged(s):
			set_flag(s, false)
			cleared_flags.append(s)
		if is_mine(s):
			_set_state(s, HIT)
			hits.append(s)
		else:
			_set_state(s, REVEALED)
		cells.append(s)
		rings.append(0)
	while head < cells.size():
		var c := cells[head]
		var ring := rings[head]
		head += 1
		if state_at(c) != REVEALED or number(c) != 0:
			continue
		for d in NB:
			var n := c + d
			if is_revealed(n):
				continue
			if is_flagged(n):
				set_flag(n, false)
				cleared_flags.append(n)
			_set_state(n, REVEALED)
			cells.append(n)
			rings.append(ring + 1)
	return {"cells": cells, "rings": rings, "hits": hits, "cleared_flags": cleared_flags}


func undo_reveals(rec: Dictionary) -> void:
	for c in rec.cells:
		_set_state(c, HIDDEN)
	for c in rec.cleared_flags:
		set_flag(c, true)


func _set_state(c: Vector2i, s: int) -> void:
	chunk(chunk_key(c)).state[_idx(c)] = s


# --- debugging and fingerprints -----------------------------------------------

## Text map around a cell. '#' hidden, 'F' flag, '.' zero, digits, 'X' hit.
## With truth=true hidden mines show as '*'. The centre row/column is marked.
func ascii(centre: Vector2i, radius: int, truth := false) -> String:
	var lines := PackedStringArray()
	for y in range(centre.y - radius, centre.y + radius + 1):
		var row := ""
		for x in range(centre.x - radius, centre.x + radius + 1):
			var c := Vector2i(x, y)
			var s := state_at(c)
			var ch := "#"
			if s == HIT:
				ch = "X"
			elif s == REVEALED:
				var n := number(c)
				ch = "." if n == 0 else str(n)
			elif truth and has_chunk(chunk_key(c)) and is_mine(c):
				ch = "*"
			elif is_flagged(c):
				ch = "F"
			if c == centre:
				ch = "[" + ch + "]"
			else:
				ch = " " + ch + " "
			row += ch
		lines.append(row)
	return "\n".join(lines)


## Fingerprint of mines, reveal state and lock state (not player flags: those are
## player opinions and must never affect the board).
func fingerprint() -> int:
	var keys := chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var h := CsHash.mix32(seed)
	for k: Vector2i in keys:
		var ch: Chunk = chunks[k]
		h = CsHash.mix32(h ^ (k.x & CsHash.MASK32))
		h = CsHash.mix32(h ^ (k.y & CsHash.MASK32))
		h = CsHash.fold_bytes(h, ch.mines)
		h = CsHash.fold_bytes(h, ch.state)
		h = CsHash.mix32(h ^ (1 if ch.locked else 0) ^ (2 if ch.proven else 0) ^ (ch.attempt << 4))
	return h
