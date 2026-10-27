class_name Profile
extends RefCounted
## The player's saved progress: Arcade stats, unlocked palettes, rivals ever
## beaten, and the top runs per mode. Pure logic (no files, no nodes), so it
## runs headless in tests; SaveStore reads and writes it as JSON.
##
## Only Arcade runs count toward stats, unlocks and rivals (SPEC.md, Ghost
## mode). A Ghost run only goes on the Ghost leaderboard.

const VERSION := 1
const TOP := 10

var runs := 0
var total_tiles := 0
var best_depth := 0
var best_score := 0
var time_ms := 0
var deaths_mine := 0
var deaths_signal := 0
## Palette ids unlocked by play (Signal and Plaintext are always unlocked).
var unlocked: Array[String] = []
## Unlocked but not yet looked at on the palettes screen (the "New" tag).
var unseen: Array[String] = []
## Rival ids ever beaten in an Arcade run.
var beaten: Array[String] = []
## Best runs, highest score first: {score, tiles, depth, ms, date, seed}.
var arcade: Array[Dictionary] = []
var ghost: Array[Dictionary] = []

static var _rules := {}
static var _rivals: Array = []


static func unlock_rules() -> Dictionary:
	if _rules.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/unlocks.json"))
		_rules = d.palettes if d is Dictionary else {}
	return _rules


static func rivals() -> Array:
	if _rivals.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rivals.json"))
		_rivals = d.rivals if d is Dictionary else []
	return _rivals


static func rival(id: String) -> Dictionary:
	for r in rivals():
		if r.id == id:
			return r
	return {}


func is_unlocked(palette_id: String) -> bool:
	var rule: Variant = unlock_rules().get(palette_id, null)
	return rule == null or unlocked.has(palette_id)


func unlocked_count() -> int:
	var n := 0
	for pid in unlock_rules():
		if is_unlocked(pid):
			n += 1
	return n


## How far along a locked palette is: {have, need, label} (label names what
## `have` counts: "best run", "best depth", tiles).
func progress(palette_id: String) -> Dictionary:
	var rule: Variant = unlock_rules().get(palette_id, null)
	if rule == null:
		return {}
	match rule.type:
		"beat_rival":
			return {"have": best_score, "need": int(rival(rule.rival).get("score", 0)), "label": "best run"}
		"total_tiles":
			return {"have": total_tiles, "need": int(rule.value), "label": "tiles"}
		"depth":
			return {"have": best_depth, "need": int(rule.value), "label": "best depth"}
	return {}


static func _met(rule: Dictionary, p: Profile) -> bool:
	match rule.type:
		"beat_rival":
			return p.beaten.has(rule.rival)
		"total_tiles":
			return p.total_tiles >= int(rule.value)
		"depth":
			return p.best_depth >= int(rule.value)
	return false


func best(mode: GameState.Mode) -> int:
	var list := ghost if mode == GameState.Mode.GHOST else arcade
	return int(list[0].score) if not list.is_empty() else 0


## Records a finished run and says what it changed. run: {score, tiles, depth,
## elapsed_ms, mode, seed, cause ("mine", "signal", "ended"), date}. Returns
## {previous_best, new_best, rank (0-based on its leaderboard, -1 if off it),
## beaten_run (rival ids this run beat), beaten_now (beaten for the first
## time), unlocked_now (palette ids), flavor {kind ("beaten" | "taunt" | ""),
## rival, text}}.
func record(run: Dictionary) -> Dictionary:
	var mode: GameState.Mode = run.get("mode", GameState.Mode.ARCADE)
	var score := int(run.get("score", 0))
	var entry := {"score": score, "tiles": int(run.get("tiles", 0)), "depth": int(run.get("depth", 0)),
		"ms": int(run.get("elapsed_ms", 0)), "date": String(run.get("date", "")), "seed": int(run.get("seed", 0))}
	var out := {"previous_best": best(mode), "new_best": false, "rank": -1, "beaten_run": [], "beaten_now": [],
		"unlocked_now": [], "flavor": {"kind": "", "rival": "", "text": ""}}
	out.new_best = score > int(out.previous_best) and score > 0
	if mode == GameState.Mode.GHOST:
		out.rank = _insert(ghost, entry)
		return out
	runs += 1
	total_tiles += entry.tiles
	best_depth = maxi(best_depth, entry.depth)
	best_score = maxi(best_score, score)
	time_ms += entry.ms
	match run.get("cause", ""):
		"mine":
			deaths_mine += 1
		"signal":
			deaths_signal += 1
	out.rank = _insert(arcade, entry)
	for r in rivals():
		if score > int(r.score):
			out.beaten_run.append(r.id)
			if not beaten.has(r.id):
				beaten.append(r.id)
				out.beaten_now.append(r.id)
	for pid in unlock_rules():
		var rule: Variant = unlock_rules()[pid]
		if rule != null and not unlocked.has(pid) and _met(rule, self):
			unlocked.append(pid)
			unseen.append(pid)
			out.unlocked_now.append(pid)
	out.flavor = flavor_for(score, out.beaten_now)
	return out


## The quiet one-line quote on game over: the beaten line of the best rival
## beaten for the first time, otherwise the taunt of the next rival above
## the score (none once every rival is below it).
static func flavor_for(score: int, beaten_now: Array) -> Dictionary:
	if not beaten_now.is_empty():
		var r := rival(beaten_now.back())
		return {"kind": "beaten", "rival": r.id, "text": r.beaten}
	for r in rivals():
		if int(r.score) >= score:
			return {"kind": "taunt", "rival": r.id, "text": r.taunt}
	return {"kind": "", "rival": "", "text": ""}


## A rival's bio for the Rivals screen; NULL//SAINT's changes for good once
## she's been beaten.
func bio(r: Dictionary) -> String:
	if r.has("bio_after_beaten") and beaten.has(r.id):
		return r.bio_after_beaten
	return r.get("bio", "")


func mark_seen(palette_id: String) -> void:
	unseen.erase(palette_id)


## Inserts into a leaderboard (highest first, ties keep the older run ahead),
## keeps the top 10, and returns the new run's place (-1 if it fell off).
static func _insert(list: Array[Dictionary], entry: Dictionary) -> int:
	var i := 0
	while i < list.size() and int(list[i].score) >= int(entry.score):
		i += 1
	list.insert(i, entry)
	while list.size() > TOP:
		list.pop_back()
	return i if i < TOP else -1


func to_dict() -> Dictionary:
	return {"version": VERSION, "runs": runs, "total_tiles": total_tiles, "best_depth": best_depth,
		"best_score": best_score, "time_ms": time_ms, "deaths_mine": deaths_mine, "deaths_signal": deaths_signal,
		"unlocked": unlocked, "unseen": unseen, "beaten": beaten, "arcade": arcade, "ghost": ghost}


## Reads a saved profile; missing or wrong-typed fields fall back to defaults,
## so older and hand-edited files still load.
static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.runs = int(d.get("runs", 0))
	p.total_tiles = int(d.get("total_tiles", 0))
	p.best_depth = int(d.get("best_depth", 0))
	p.best_score = int(d.get("best_score", 0))
	p.time_ms = int(d.get("time_ms", 0))
	p.deaths_mine = int(d.get("deaths_mine", 0))
	p.deaths_signal = int(d.get("deaths_signal", 0))
	for k in ["unlocked", "unseen", "beaten"]:
		var src: Variant = d.get(k, [])
		if src is Array:
			var dst: Array[String] = p.get(k)
			for v in src:
				if v is String and not dst.has(v):
					dst.append(v)
	for k in ["arcade", "ghost"]:
		var src: Variant = d.get(k, [])
		if src is Array:
			var dst: Array[Dictionary] = p.get(k)
			for v in src:
				if v is Dictionary and v.has("score"):
					dst.append({"score": int(v.score), "tiles": int(v.get("tiles", 0)), "depth": int(v.get("depth", 0)),
						"ms": int(v.get("ms", 0)), "date": String(v.get("date", "")), "seed": int(v.get("seed", 0))})
			dst.sort_custom(func(a, b): return int(a.score) > int(b.score))
			while dst.size() > TOP:
				dst.pop_back()
	return p
