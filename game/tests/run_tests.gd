extends SceneTree
## Headless test entry point. From the repo root:
##   godot --headless --path game -s res://tests/run_tests.gd -- --suite unit
##   godot --headless --path game -s res://tests/run_tests.gd -- --suite property \
##       --driver perfect --first 0 --games 50 --moves 300 --json ../test-output/p.json
##   godot --headless --path game -s res://tests/run_tests.gd -- --suite replay \
##       --file ../test-output/failures/sloppy-12.json
## tools/run_tests.py wraps this and runs property shards in parallel.

const UNIT_DIR := "res://tests/unit"

## Stays 3 if a script error aborts _init, so a broken run never looks green
## and never hangs.
var _code := 3


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	match args.get("suite", "unit"):
		"unit":
			_code = _run_unit(args)
		"property":
			_code = PropertySuite.new().run(args)
		"replay":
			_code = _replay(args)
		_:
			printerr("unknown suite: ", args.get("suite"))
			_code = 2


func _process(_delta: float) -> bool:
	if _code == 3:
		printerr("test run aborted (script error?)")
	quit(_code)
	return true


## --only takes one or more substrings separated by "|".
func _matches(full: String, only: String) -> bool:
	for part in only.split("|", false):
		if full.contains(part):
			return true
	return false


func _run_unit(args: Dictionary) -> int:
	var only: String = args.get("only", "")
	var files := DirAccess.get_files_at(UNIT_DIR)
	var total := 0
	var failed := 0
	var lines := PackedStringArray()
	var t_start := Time.get_ticks_msec()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR + "/" + f)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not _matches(f + ":" + name, only):
				continue
			var t: TestCase = script.new()
			t.current = name
			var t0 := Time.get_ticks_msec()
			t.call(name)
			var ms := Time.get_ticks_msec() - t0
			total += 1
			if t.failures.is_empty():
				lines.append("  ok    %s :: %s (%d ms)" % [f, name, ms])
			else:
				failed += 1
				lines.append("  FAIL  %s :: %s" % [f, name])
				for msg in t.failures.slice(0, 12):
					lines.append("          " + msg)
	print("\n".join(lines))
	print("unit: %d tests, %d failed (%.1f s)" % [total, failed, (Time.get_ticks_msec() - t_start) / 1000.0])
	if args.has("json"):
		var fa := FileAccess.open(args.json, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"suite": "unit", "total": total, "failed": failed, "lines": lines}))
	return 1 if failed > 0 else 0


## Replays a failure file written by the property suite and prints what the
## generator logged, plus the map around the last revealed cell.
func _replay(args: Dictionary) -> int:
	var text := FileAccess.get_file_as_string(args.get("file", ""))
	var d: Variant = JSON.parse_string(text)
	if not d is Dictionary:
		printerr("can't read failure file: ", args.get("file", ""))
		return 2
	var log := MoveLog.from_dict(d.log)
	var upto := int(args.get("upto", str(log.count())))
	var gs := GameState.new(log.seed, Rules.load_default(), true)
	MoveLog.apply_ops(gs, log, 0, mini(upto, log.count()))
	print("seed %d, %d ops replayed, failure was: %s" % [log.seed, upto, d.get("msg", "?")])
	print("stats: ", gs.gen.stats)
	for e in gs.gen.events:
		var line := str(e)
		print("event: ", line.substr(0, 300))
	var last := Vector2i.ZERO
	for i in range(mini(upto, log.count()) - 1, -1, -1):
		if log.ops[i * 3] != MoveLog.TICK:
			last = Vector2i(log.ops[i * 3 + 1], log.ops[i * 3 + 2])
			break
	print(gs.board.ascii(last, 12, true))
	return 0
