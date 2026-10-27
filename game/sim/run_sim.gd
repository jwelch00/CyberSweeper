extends SceneTree
## Headless bot simulations. tools/simulate.py wraps this and runs shards in
## parallel. Direct use, from the repo root:
##   godot --headless --path game -s res://sim/run_sim.gd -- --profile runner \
##       --first 0 --games 20 --json ../test-output/sim/runner-0.json
## Options:
##   --override '{"signal": {"drain_per_sec": 2.5}}'   tuning.json overrides
##   --bot-override '{"think_median_ms": 900}'          bot profile overrides
##   --max-minutes 120                                  safety cap on run length
##   --grace                                            play with the human-only signal grace

const SEED_BASE := 0x5100000

## Stays 3 if a script error aborts _init (same pattern as run_tests.gd).
var _code := 3


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	_code = _run(args)


func _process(_delta: float) -> bool:
	if _code == 3:
		printerr("simulation aborted (script error?)")
	quit(_code)
	return true


## Board seed for game i. Every profile plays the same boards.
static func game_seed(i: int) -> int:
	return CsHash.mix32(SEED_BASE + i)


func _run(args: Dictionary) -> int:
	var pid: String = args.get("profile", "runner")
	var profiles := Bot.load_profiles()
	if not profiles.has(pid):
		printerr("unknown profile: ", pid)
		return 2
	var profile: Dictionary = profiles[pid].duplicate(true)
	if args.has("bot-override"):
		var bo: Dictionary = JSON.parse_string(args["bot-override"])
		for k in bo:
			profile[k] = bo[k]
	var rules := Rules.load_default()
	if args.has("override"):
		rules = rules.with_overrides(JSON.parse_string(args.override))
	var first := int(args.get("first", "0"))
	var games := int(args.get("games", "10"))
	var max_ms := int(float(args.get("max-minutes", "120")) * 60000.0)

	var t0 := Time.get_ticks_msec()
	var runs: Array[Dictionary] = []
	for i in range(first, first + games):
		var seed := game_seed(i)
		var gs := GameState.new(seed, rules, false, GameState.Mode.ARCADE, args.has("grace"))
		var bot := Bot.new(pid, profile, rules, seed ^ 0x2545F491)
		bot.play(gs, Vector2i.ZERO, max_ms)
		runs.append({
			"index": i, "seed": seed, "score": gs.score, "tally": Array(gs.tally),
			"minutes": gs.elapsed_ms / 60000.0, "tiles": gs.tiles, "depth": gs.deepest,
			"hits": gs.hits, "signal_outs": gs.links_lost - gs.hits, "capped": not gs.over,
			"actions": bot.stats.actions, "quick": bot.stats.quick, "guesses": bot.stats.guesses, "searches": bot.stats.searches,
			"misclicks": bot.stats.misclicks, "chords": bot.stats.chords,
			"by_tier": bot.stats.by_tier, "think_ms": bot.stats.think_ms,
			"stuck": gs.stuck_count, "rescues": gs.gen.stats.rescues,
			"pockets": gs.gen.stats.pockets,
		})
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	print("sim %s games %d-%d: %.1f s" % [pid, first, first + games - 1, elapsed])
	if args.has("json"):
		var fa := FileAccess.open(args.json, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"profile": pid, "grace": args.has("grace"), "bot": profile, "tuning": rules.data,
			"runs": runs, "elapsed_s": elapsed}))
	return 0
