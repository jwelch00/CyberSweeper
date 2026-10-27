class_name Session
extends RefCounted
## Runs one GameState on a worker thread, so a slow reveal (generation repairs
## can take over a second in rare cases) never freezes a frame.
##
## The main thread calls send() and poll(); only the worker touches the
## GameState. Each result carries a MoveResult and a snapshot of the numbers the
## HUD shows, so the two threads never share mutable data. With threaded=false
## everything runs immediately on the caller's thread (tests, screenshots).

enum Op { REVEAL, FLAG, CHORD, TICK, BOT, DUMP, END }

var threaded: bool
var seed: int
var mode: GameState.Mode
## Commands sent and not yet returned by poll(). Main thread only.
var in_flight := 0

var _gs: GameState
var _rules: Rules
var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _inbox: Array = []
var _outbox: Array = []
var _stop := false
var _over_reported := false


## grace: the human-only signal grace (GameState.grace); bots run without it.
func _init(p_seed: int, rules: Rules, p_threaded := true, p_mode: GameState.Mode = GameState.Mode.ARCADE,
		p_grace := false) -> void:
	seed = p_seed & CsHash.MASK32
	_rules = rules
	threaded = p_threaded
	mode = p_mode
	_gs = GameState.new(seed, rules, false, p_mode, p_grace)
	if threaded:
		_thread = Thread.new()
		_thread.start(_worker)


func reveal(c: Vector2i) -> void:
	_send([Op.REVEAL, c, 0])


func flag(c: Vector2i) -> void:
	_send([Op.FLAG, c, 0])


func chord(c: Vector2i) -> void:
	_send([Op.CHORD, c, 0])


func tick(ms: int) -> void:
	_send([Op.TICK, Vector2i.ZERO, ms])


## Ghost mode's "End run": ends the run and banks the score.
func end_run() -> void:
	_send([Op.END, Vector2i.ZERO, 0])


## Lets a bot play `turns` actions (screenshots and demos).
func bot(profile_id: String, turns: int, first_click := Vector2i.ZERO) -> void:
	_send([Op.BOT, first_click, turns, profile_id])


## Asks for everything visible: revealed cells, flags and hits.
func dump() -> void:
	_send([Op.DUMP, Vector2i.ZERO, 0])


func busy() -> bool:
	return in_flight > 0


## Finished results, oldest first: {"op", "res": MoveResult, "state": {...}}.
func poll() -> Array:
	_mutex.lock()
	var out := _outbox
	_outbox = []
	_mutex.unlock()
	in_flight -= out.size()
	return out


func close() -> void:
	if not threaded or _thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_sem.post()
	_thread.wait_to_finish()
	_thread = null


func _send(cmd: Array) -> void:
	in_flight += 1
	if not threaded:
		_outbox.append(_apply(cmd))
		return
	_mutex.lock()
	_inbox.append(cmd)
	_mutex.unlock()
	_sem.post()


func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _inbox.is_empty():
			var stop := _stop
			_mutex.unlock()
			if stop:
				return
			continue
		var cmd: Array = _inbox.pop_front()
		_mutex.unlock()
		var out := _apply(cmd)
		_mutex.lock()
		_outbox.append(out)
		_mutex.unlock()


func _apply(cmd: Array) -> Dictionary:
	var op: int = cmd[0]
	var c: Vector2i = cmd[1]
	var res: MoveResult = null
	var extra := {}
	match op:
		Op.REVEAL:
			res = _gs.reveal(c)
		Op.FLAG:
			res = _gs.flag(c)
		Op.CHORD:
			res = _gs.chord(c)
		Op.TICK:
			res = _gs.tick(cmd[2])
		Op.END:
			res = _gs.end_run()
		Op.BOT:
			var profile: Dictionary = Bot.load_profiles()[cmd[3]]
			var b := Bot.new(cmd[3], profile, _rules, seed ^ 0x2545F491)
			if not _gs.started:
				_gs.reveal(c)
				b._observe(_gs, _snapshot_reveal())
				b.last = c
			else:
				b._observe(_gs, _snapshot_reveal())
			for i in int(cmd[2]):
				if _gs.over:
					break
				b.turn(_gs)
			res = MoveResult.new()
			extra = _visible()
			extra["last"] = b.last
		Op.DUMP:
			res = MoveResult.new()
			extra = _visible()
	var state := _state()
	if _gs.over and not _over_reported:
		_over_reported = true
		state["reveal"] = _post_mortem()
	for k in extra:
		state[k] = extra[k]
	return {"op": op, "res": res, "state": state}


func _state() -> Dictionary:
	return {
		"started": _gs.started, "over": _gs.over, "origin": _gs.board.origin, "seed": seed,
		"score": _gs.score, "links": _gs.links, "signal": _gs.signal_fraction(),
		"signal_shown": _rules.signal_display(_gs.signal_fraction()), "tiles": _gs.tiles,
		"elapsed_ms": _gs.elapsed_ms, "deepest": _gs.deepest, "tally": Array(_gs.tally),
		"stuck": _gs.stuck_count, "hits": _gs.hits, "mode": _gs.mode, "ended": _gs.ended,
	}


## Every revealed cell as one MoveResult-shaped list (for bots joining a run).
func _snapshot_reveal() -> MoveResult:
	var r := MoveResult.new()
	for k: Vector2i in _gs.board.chunks:
		var ch: Chunk = _gs.board.chunks[k]
		var corner := _gs.board.chunk_corner(k)
		for i in Chunk.CELLS:
			if ch.state[i] != Board.HIDDEN:
				r.revealed.append(corner + Vector2i(i & 15, i >> 4))
	return r


## Everything a player can see right now.
func _visible() -> Dictionary:
	var cells: Array[Vector2i] = []
	var numbers := PackedInt32Array()
	for c in _snapshot_reveal().revealed:
		cells.append(c)
		numbers.append(-1 if _gs.board.state_at(c) == Board.HIT else _gs.board.number(c))
	return {"cells": cells, "numbers": numbers, "flags": _gs.board.flags.keys()}


## At game over: hidden mines near the explored area, and flags on safe cells.
func _post_mortem() -> Dictionary:
	var mines: Array[Vector2i] = []
	var wrong: Array[Vector2i] = []
	for k: Vector2i in _gs.board.chunks:
		var ch: Chunk = _gs.board.chunks[k]
		if not ch.locked:
			continue
		var corner := _gs.board.chunk_corner(k)
		for i in Chunk.CELLS:
			var c := corner + Vector2i(i & 15, i >> 4)
			if ch.mines[i] == 1 and ch.state[i] == Board.HIDDEN and not _gs.board.is_flagged(c) \
					and _near_open(c, 2):
				mines.append(c)
	for c: Vector2i in _gs.board.flags:
		if not _gs.board.is_mine(c):
			wrong.append(c)
	return {"mines": mines, "wrong_flags": wrong, "flags_correct": _gs.flags_correct()}


func _near_open(c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _gs.board.is_open(c + Vector2i(dx, dy)):
				return true
	return false
