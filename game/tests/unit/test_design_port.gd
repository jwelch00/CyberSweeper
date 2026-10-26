extends TestCase
## The GDScript ports of design/shared/*.js match the JS exactly
## (tests/data/js_reference.json is what the JS itself produced; regenerate it
## with `node tools/js_reference.mjs` when design/shared changes).

const REF := "res://tests/data/js_reference.json"


func _ref() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(REF))


func test_hash2_matches_board_js() -> void:
	for h in _ref().hash2:
		var v := JsPort.hash2(int(h.x), int(h.y), int(h.s))
		check(is_equal_approx(v, float(h.v)), "hash2(%d, %d, %d) = %.12f, JS says %.12f" % [h.x, h.y, h.s, v, h.v])


func test_jag_points_match_screens_js() -> void:
	for j in _ref().jag:
		var got := Jag.points(float(j.w), float(j.h), int(j.seed))
		var pts: PackedVector2Array = got.pts
		eq(pts.size(), j.pts.size(), "seed %d point count" % j.seed)
		var same: bool = pts.size() == j.pts.size()
		for i in mini(pts.size(), j.pts.size()):
			if pts[i] != Vector2(j.pts[i][0], j.pts[i][1]):
				same = false
		check(same, "seed %d outline differs: %s vs %s" % [j.seed, str(pts), str(j.pts)])
		for k in 2:
			var hp: PackedVector2Array = got.hot[k]
			for i in hp.size():
				check(hp[i] == Vector2(j.hot[k][i][0], j.hot[k][i][1]), "seed %d hot stroke %d" % [j.seed, k])


func test_breach_plans_match_fx_js() -> void:
	for want in _ref().plans:
		var p := BreachPlan.make(int(want.seed), want.forced)
		eq(p.kind, want.kind, "seed %d kind" % want.seed)
		eq(p.key, want.key, "seed %d key" % want.seed)
		check(is_equal_approx(p.total_ms, float(want.total)), "seed %d total %f vs %f" % [want.seed, p.total_ms, want.total])
		eq(p.stalls.size(), want.stalls.size(), "seed %d stalls" % want.seed)
		for i in mini(p.stalls.size(), want.stalls.size()):
			eq([p.stalls[i].at, p.stalls[i].drop, p.stalls[i].proxy],
				[int(want.stalls[i].at), int(want.stalls[i].drop), int(want.stalls[i].proxy)], "seed %d stall %d" % [want.seed, i])
		eq(p.segs.size(), want.segs.size(), "seed %d segments" % want.seed)


func test_breach_odds_and_ranges_follow_motion_md() -> void:
	var counts := {"clean": 0, "one": 0, "99": 0, "double": 0}
	var n := 20000
	for s in n:
		var p := BreachPlan.make(s * 2654435761 & 0x7FFFFFFF)
		counts[p.kind] += 1
		match p.kind:
			"clean":
				eq(p.stalls.size(), 0)
				check(is_equal_approx(p.total_ms, 900.0), "a clean breach takes 900 ms")
			"one":
				check(p.stalls[0].at >= 25 and p.stalls[0].at <= 90, "one setback between 25% and 90%")
				check(p.stalls[0].drop >= 8 and p.stalls[0].drop <= 22, "drops 8-22 points")
			"99":
				eq(p.stalls[0].at, 99)
				check(p.stalls[0].drop >= 10 and p.stalls[0].drop <= 22, "99% drops 10-22 points")
			"double":
				var a: int = p.stalls[0].at
				check(a >= 20 and a <= 50, "first denial at 20-50%")
				var gap: int = p.stalls[1].at - a
				check(gap >= 25 and gap <= 50, "second denial 25-50 points later (%d)" % gap)
		for x in p.stalls:
			check(x.proxy >= 2 and x.proxy <= 9, "proxy 2-9")
		eq(p.at(p.total_ms + 1.0).p, 100.0, "done at 100%")
		eq(p.at(0.0).p, 0.0, "starts at 0%")
		eq(p.key.length(), 19)
	var share := func(k: String) -> float: return float(counts[k]) / n
	check(absf(share.call("clean") - 0.40) < 0.015, "clean ~40%: " + str(counts))
	check(absf(share.call("one") - 0.40) < 0.015, "one ~40%: " + str(counts))
	check(absf(share.call("99") - 0.15) < 0.01, "99 ~15%: " + str(counts))
	check(absf(share.call("double") - 0.05) < 0.006, "double ~5%: " + str(counts))


func test_denial_holds_then_drops() -> void:
	var p := BreachPlan.make(1, "one")
	var d: Dictionary = p.segs[1]
	check(d.denied, "the second segment is the denial")
	var len: float = d.t1 - d.t0
	eq(p.at(d.t0 + len * 0.2).p, d.p0, "holds at the stall for the first 40%")
	eq(p.at(d.t0 + len * 0.6).p, d.p1, "then shows the drop")
	eq(p.at(d.t0 + 1.0).seg.get("proxy"), p.stalls[0].proxy)


func test_motion_timings_match_fx_js() -> void:
	var t: Dictionary = _ref().T
	eq(float(t.boot.line), Motion.BOOT_LINE_MS)
	eq(float(t.boot.holdEnd), Motion.BOOT_HOLD_END_MS)
	eq(float(t.boot.denied), BreachPlan.DENIED_MS)
	eq(float(t.boot.msPerPct), BreachPlan.MS_PER_PCT)
	eq(float(t.boot.loaderHold), Motion.BOOT_LOADER_HOLD_MS)
	eq(float(t.boot.offChance), Motion.JACKED_OFF_CHANCE)
	eq(float(t.card.flash), Motion.CARD_FLASH_MS)
	eq(float(t.card.slam), Motion.CARD_SLAM_MS)
	eq(float(t.card.hold), Motion.CARD_HOLD_MS)
	eq(float(t.card.fullHold), Motion.CARD_FULL_HOLD_MS)
	eq(float(t.card.slice), Motion.CARD_SLICE_MS)
	eq(float(t.cascade.ring), Motion.RING_MS)
	eq(float(t.cascade.ghostLife), Motion.GHOST_LIFE_MS)
	eq(t.cascade.echoes.map(func(v): return float(v)), Array(Motion.ECHO_DELAYS))
	eq(float(t.cascade.drift), Motion.DRIFT_PX)
	eq(int(t.cascade.minCells), Motion.TRAIL_MIN_CELLS)
	eq(float(t.hit.slam), Motion.HIT_SLAM_MS)
	eq(float(t.hit.shake), Motion.SHAKE_MS)
	eq(float(t.hit.shakePx), Motion.SHAKE_PX)
	eq(float(t.hit.flash), Motion.HIT_FLASH_MS)
	eq(float(t.hit.march), Motion.HIT_MARCH_MS)
	eq(float(t.shatter.life), Motion.SHATTER_MS)
	eq(float(t.shatter.dist), Motion.SHATTER_PX)
	eq(t.strain.corruptEvery.map(func(v): return float(v)), Array(Motion.CORRUPT_EVERY_MS))
	eq(t.strain.corruptFor.map(func(v): return float(v)), Array(Motion.CORRUPT_FOR_MS))
	eq(float(t.strain.tearEvery), Motion.TEAR_EVERY_MS)
	eq(float(t.mosh.breakOut), Motion.MOSH_BREAK_MS)
	eq(float(t.mosh.total), Motion.MOSH_TOTAL_MS)
	eq(int(t.mosh.bands), Motion.MOSH_BANDS)


func test_boot_log_matches_fx_js() -> void:
	var lines: Array = _ref().boot_lines
	eq(lines.size(), Motion.BOOT_LINES.size())
	for i in lines.size():
		var want: Array = lines[i]
		var got: Array = Motion.BOOT_LINES[i]
		eq(got[0], want[0], "timestamp %d" % i)
		var text: String = want[1]
		if i == 0:
			text = text.replace("0.1.0", CsVersion.GAME)
		eq(got[1], text, "text %d" % i)
		eq(got[2], want[2], "tail %d" % i)
