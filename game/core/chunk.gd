class_name Chunk
extends RefCounted
## One 16x16 block of the infinite board, stored as flat packed arrays.
## Index of local cell (lx, ly) is lx + ly * 16.

const SIZE := 16
const CELLS := 256

var key: Vector2i
var mines := PackedByteArray()   # 1 = mine
var state := PackedByteArray()   # Board.HIDDEN / REVEALED / HIT
var attempt := 0                 # bumped every time cells in this chunk are re-rolled

## Locked once the player can see anything that depends on this chunk.
var locked := false
## Locked with a proof that every safe cell can be decrypted.
var proven := false
## Locked by a voluntary far click (a guess), so no proof was attempted.
var island := false
## Locked after the generator ran out of repair attempts.
var pocket := false


func _init(k: Vector2i) -> void:
	key = k
	mines.resize(CELLS)
	mines.fill(0)
	state.resize(CELLS)
	state.fill(0)
