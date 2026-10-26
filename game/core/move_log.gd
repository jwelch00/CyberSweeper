class_name MoveLog
extends RefCounted
## Every GameState call in order. Seed + log reproduces a run exactly.
##
## It also keeps what a replay file needs (IDEAS.md): the game version, the
## tuning hash, the mode, every player action with the run time it happened
## at, and how the run ended. Because the signal drain is an exact integral
## (Rules.drained_u), actions and their times alone reproduce the run.

const REVEAL := 0
const FLAG := 1
const CHORD := 2
const TICK := 3
const END := 4

var seed := 0
var mode: int = 0   # GameState.Mode
var ops := PackedInt32Array()   # triples: op, a, b (cell x, y; or ms, 0)

## Replay data: player actions as quads (op, x, y, run ms when it happened).
var actions := PackedInt64Array()
var version := CsVersion.GAME
var tuning_hash := ""
## Set when the run ends: run time and final score.
var end_ms := -1
var final_score := -1


func add(op: int, a: int, b := 0) -> void:
	ops.append(op)
	ops.append(a)
	ops.append(b)


## Records a player action (not ticks) with the run time it happened at.
func action(op: int, c: Vector2i, at_ms: int) -> void:
	actions.append(op)
	actions.append(c.x)
	actions.append(c.y)
	actions.append(at_ms)


func count() -> int:
	return ops.size() / 3


func action_count() -> int:
	return actions.size() / 4


## A replay file's contents: everything needed to reproduce (and verify) the run.
func to_replay() -> Dictionary:
	var list := []
	for i in action_count():
		list.append([actions[i * 4], actions[i * 4 + 1], actions[i * 4 + 2], actions[i * 4 + 3]])
	return {"format": 1, "version": version, "tuning_hash": tuning_hash, "mode": mode, "seed": seed,
		"actions": list, "end_ms": end_ms, "score": final_score}


## Why a replay can't be played on this build, or "" if it can.
static func replay_problem(r: Dictionary, rules: Rules) -> String:
	if int(r.get("format", 0)) != 1:
		return "This replay uses a format this build doesn't know."
	if str(r.get("version", "")) != CsVersion.GAME:
		return "This replay was recorded on CyberSweeper %s; this is %s, so it might play differently." % [
			r.get("version", "?"), CsVersion.GAME]
	if str(r.get("tuning_hash", "")) != rules.tuning_hash():
		return "This replay was recorded with different game tuning, so it can't be played back faithfully."
	return ""


## Plays a replay's actions at their recorded times into a fresh GameState.
## step_ms > 0 slices the time between actions into ticks of that size (a
## real frame rate); the result is the same either way.
static func play_replay(r: Dictionary, rules: Rules, step_ms := 0) -> GameState:
	var gs := GameState.new(int(r.seed), rules, false, int(r.get("mode", 0)) as GameState.Mode)
	var t := 0
	for a in r.actions:
		_advance(gs, t, int(a[3]), step_ms)
		t = maxi(t, int(a[3]))
		var c := Vector2i(int(a[1]), int(a[2]))
		match int(a[0]):
			REVEAL:
				gs.reveal(c)
			FLAG:
				gs.flag(c)
			CHORD:
				gs.chord(c)
			END:
				gs.end_run()
	if int(r.get("end_ms", -1)) > t:
		_advance(gs, t, int(r.end_ms), step_ms)
	return gs


static func _advance(gs: GameState, from: int, to: int, step_ms: int) -> void:
	if to <= from:
		return
	if step_ms <= 0:
		gs.tick(to - from)
		return
	var t := from
	while t < to:
		var dt := mini(step_ms, to - t)
		gs.tick(dt)
		t += dt


func to_dict() -> Dictionary:
	return {"seed": seed, "mode": mode, "ops": Array(ops), "replay": to_replay()}


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
