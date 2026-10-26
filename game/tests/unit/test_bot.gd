extends TestCase
## Bots: tier limits, human pace, determinism, error rates, visibility.


func _run(pid: String, seed: int, overrides := {}) -> Array:
	var rules := Rules.load_default()
	var profile: Dictionary = Bot.load_profiles()[pid].duplicate(true)
	for k in overrides:
		profile[k] = overrides[k]
	var gs := GameState.new(seed, rules)
	var bot := Bot.new(pid, profile, rules, seed ^ 0x2545F491)
	bot.play(gs, Vector2i.ZERO, 120 * 60000)
	return [gs, bot]


func test_profiles_load_and_match_the_spec() -> void:
	var p := Bot.load_profiles()
	for id in ["rookie", "runner", "netrunner", "reference"]:
		check(p.has(id), "profile " + id)
	eq(p.rookie.name, "script.kitty")
	eq(p.runner.name, "mx_halcyon")
	eq(p.netrunner.name, "NULL//SAINT")
	eq(int(p.rookie.tier), 1)
	eq(int(p.runner.tier), 2)
	eq(int(p.netrunner.tier), 3)
	# Rookie thinks about as long as Runner per move but is slower in practice:
	# single clicks only, tier 1 only (tools/simulate.py checks the pace).
	check(p.rookie.think_median_ms >= p.runner.think_median_ms and p.runner.think_median_ms > p.netrunner.think_median_ms,
		"rookie slow, runner medium, netrunner fast")
	check(not p.rookie.chord and p.runner.chord and p.netrunner.chord, "only rookie never chords")
	check(p.rookie.misclick > p.netrunner.misclick and p.runner.misclick > p.netrunner.misclick, "netrunner errs least")


func test_bots_never_use_tiers_above_their_own() -> void:
	for pid in ["rookie", "runner"]:
		for seed in [3, 4]:
			var r := _run(pid, seed)
			var bot: Bot = r[1]
			var top := int(Bot.load_profiles()[pid].tier)
			for t in range(top + 1, 4):
				eq(bot.stats.by_tier[t], 0, "%s used tier %d" % [pid, t])
			eq(bot.solver.max_tier, top)


func test_netrunner_never_moves_faster_than_half_a_second() -> void:
	var rules := Rules.load_default()
	var profile: Dictionary = Bot.load_profiles().netrunner
	var bot := Bot.new("netrunner", profile, rules, 1)
	var gs := GameState.new(1, rules)   # not started: ticks cost nothing
	for i in 3000:
		var before: int = bot.stats.think_ms
		bot._think(gs, 0)
		check(bot.stats.think_ms - before >= 500, "think under 500 ms")
		before = bot.stats.think_ms
		bot._quick(gs)
		check(bot.stats.think_ms - before >= 500, "quick click under 500 ms")
	var r := _run("netrunner", 8)
	var nb: Bot = r[1]
	check(nb.stats.think_ms >= 500 * nb.stats.actions, "whole run averages at least 500 ms per action")


func test_same_seed_same_run() -> void:
	for pid in ["rookie", "netrunner"]:
		var a := _run(pid, 21)
		var b := _run(pid, 21)
		var ga: GameState = a[0]
		var gb: GameState = b[0]
		eq(ga.score, gb.score, pid)
		eq(ga.elapsed_ms, gb.elapsed_ms, pid)
		eq(ga.board.fingerprint(), gb.board.fingerprint(), pid)
		eq(a[1].stats, b[1].stats, pid)


func test_misclick_rate_is_roughly_what_the_profile_says() -> void:
	var r := _run("runner", 5, {"misclick": 0.2})
	var bot: Bot = r[1]
	var rate := float(bot.stats.misclicks) / float(bot.stats.actions - bot.stats.chords)
	check(rate > 0.12 and rate < 0.28, "misclick rate %.3f for a 0.2 profile" % rate)


func test_bots_only_see_what_a_player_sees() -> void:
	var r := _run("netrunner", 13)
	var gs: GameState = r[0]
	var bot: Bot = r[1]
	for c: Vector2i in bot.solver.num:
		check(gs.board.is_open(c), "bot knows a number that isn't revealed: %s" % c)
		eq(bot.solver.num[c], gs.board.number(c))
	for c: Vector2i in bot.solver.mine:
		if bot.solver.mine[c] == 0:
			eq(gs.board.state_at(c), Board.HIT, "given mines are revealed hits")
		else:
			check(gs.board.is_mine(c), "deduced mine %s is real" % c)


func test_every_profile_finishes_a_run() -> void:
	for pid in ["rookie", "runner", "netrunner", "reference"]:
		var r := _run(pid, 2)
		var gs: GameState = r[0]
		check(gs.over, "%s run ended" % pid)
		eq(gs.links, 0)
		check(gs.score > 0)
		eq(gs.stuck_count, 0, "never stuck")
