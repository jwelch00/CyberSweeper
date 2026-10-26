class_name MoveLog
extends RefCounted
## Every GameState call in order. Seed + log reproduces a run exactly.

const REVEAL := 0
const FLAG := 1
const CHORD := 2
const TICK := 3
const END := 4

var seed := 0
var mode: int = 0   # GameState.Mode
var ops := PackedInt32Array()   # triples: op, a, b (cell x, y; or ms, 0)


func add(op: int, a: int, b := 0) -> void:
	ops.append(op)
	ops.append(a)
	ops.append(b)


func count() -> int:
	return ops.size() / 3


func to_dict() -> Dictionary:
	return {"seed": seed, "mode": mode, "ops": Array(ops)}


static func from_dict(d: Dictionary) -> MoveLog:
	var log := MoveLog.new()
	log.seed = int(d.seed)
	log.mode = int(d.get("mode", 0))
	for v in d.ops:
		log.ops.append(int(v))
	return log


## Plays the log into a fresh GameState.
static func replay(log: MoveLog, rules: Rules, immortal := false) -> GameState:
	var gs := GameState.new(log.seed, rules, immortal, log.mode as GameState.Mode)
	apply_ops(gs, log, 0, log.count())
	return gs


static func apply_ops(gs: GameState, log: MoveLog, from: int, to: int) -> void:
	for i in range(from, to):
		var op := log.ops[i * 3]
		var c := Vector2i(log.ops[i * 3 + 1], log.ops[i * 3 + 2])
		match op:
			REVEAL:
				gs.reveal(c)
			FLAG:
				gs.flag(c)
			CHORD:
				gs.chord(c)
			TICK:
				gs.tick(c.x)
			END:
				gs.end_run()
