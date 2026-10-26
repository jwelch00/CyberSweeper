extends TestCase


func test_density_curve() -> void:
	var r := Rules.load_default()
	check(absf(r.density(0) - 0.15) < 1e-9, "start density")
	check(absf(r.density(65) - 0.1825) < 1e-9, "depth 65 density %f" % r.density(65))
	check(absf(r.density(140) - 0.22) < 1e-9, "cap reached")
	check(absf(r.density(5000) - 0.22) < 1e-9, "cap holds")


func test_thresholds_match_density() -> void:
	var r := Rules.load_default()
	for depth in [0, 1, 65, 139, 140, 141, 10000]:
		eq(r.mine_threshold(depth), int(r.density(depth) * 4294967296.0), "depth %d" % depth)


func test_drain_grows_with_time() -> void:
	var r := Rules.load_default()
	check(absf(r.drain_rate(0) - r.drain_per_sec) < 1e-9, "base drain")
	var ten := r.drain_rate(600000)
	check(absf(ten - r.drain_per_sec * (1.0 + 10.0 * r.drain_growth_per_min)) < 1e-9, "10 min drain")


func test_overrides() -> void:
	var r := Rules.load_default().with_overrides({"density": {"base": 0.2, "per_cell": 0.0}})
	check(absf(r.density(500) - 0.2) < 1e-9, "flat override")
	eq(Rules.load_default().density_base, 0.15, "default untouched")
