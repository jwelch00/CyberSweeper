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


func test_signal_bar_runs_on_a_false_scale() -> void:
	var r := Rules.load_default()
	check(absf(r.signal_display(1.0) - 1.0) < 1e-9, "full is full")
	check(absf(r.signal_display(0.0)) < 1e-9, "empty is empty")
	check(absf(r.signal_display(0.8) - 0.5) < 0.005, "50%% shown is 80%% real (%f)" % r.signal_display(0.8))
	var prev := 0.0
	var prev_step := 1e9
	for i in range(1, 101):
		var a := i / 100.0
		var shown := r.signal_display(a)
		check(shown > prev, "rises steadily")
		check(shown <= a + 1e-9, "never shows more than is really left")
		prev = shown
	# The bar moves slower and slower toward empty.
	var near_full := r.signal_display(1.0) - r.signal_display(0.95)
	var middle := r.signal_display(0.55) - r.signal_display(0.5)
	var near_empty := r.signal_display(0.05) - r.signal_display(0.0)
	check(near_full > middle and middle > near_empty, "slows down toward empty")
	var linear := Rules.load_default().with_overrides({"signal": {"display_curve": 0.0}})
	check(absf(linear.signal_display(0.37) - 0.37) < 1e-9, "curve 0 is linear")


func test_low_signal_alarm() -> void:
	eq(Hud.alarm_level(0.5, 0.0, 0.3, 0.1, false), 0.0, "no alarm with plenty left")
	eq(Hud.alarm_level(0.3, 0.0, 0.3, 0.1, false), 0.0, "none right at the low mark")
	var a := Hud.alarm_level(0.25, 0.0, 0.3, 0.1, true)
	var b := Hud.alarm_level(0.05, 0.0, 0.3, 0.1, true)
	check(a > 0.0 and b > a, "grows as the signal drops")
	check(b <= 1.0, "never past full")
	var hi := 0.0
	var lo := 1.0
	for t in range(0, 1000, 10):
		var v := Hud.alarm_level(0.2, float(t), 0.3, 0.1, false)
		hi = maxf(hi, v)
		lo = minf(lo, v)
	check(hi - lo > 0.1, "pulses")
	eq(Hud.alarm_level(0.2, 0.0, 0.3, 0.1, true), Hud.alarm_level(0.2, 470.0, 0.3, 0.1, true), "steady with reduced motion")
