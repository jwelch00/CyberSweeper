class_name MoveResult
extends RefCounted
## What one GameState call did, for the UI (milestone 3) and the bots.

enum Kind { NOOP, REVEAL, CHORD, FLAG, TICK }

var kind: Kind
var cell: Vector2i
## Cells revealed this move, in cascade order; rings[i] is cell i's ring
## (0 = clicked, 1 = next ring out...) for the 18 ms-per-ring animation.
var revealed: Array[Vector2i] = []
var rings := PackedInt32Array()
var hits: Array[Vector2i] = []
var score_delta := 0
var links_lost := 0
var game_over := false
var flag_on := false
## The backstop made this click safe (should never happen; logged).
var backstop := false


func _init(p_kind: Kind = Kind.NOOP, p_cell := Vector2i.ZERO) -> void:
	kind = p_kind
	cell = p_cell
