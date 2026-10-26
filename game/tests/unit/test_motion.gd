extends TestCase
## The motion pass (design/MOTION.md): strain, corruption, flashes and their
## limits, card and cascade timing, datamosh bands, the lattice's labels, and
## the fonts every effect draws with.

const JP_WORDS := ["鉄影", "監視中", "接続完了", "撃破", "記録更新", "切断", "接続"]


func test_strain_level_follows_motion_md() -> void:
	var A := GameState.Mode.ARCADE
	var G := GameState.Mode.GHOST
	eq(Strain.level(3, 0.5, A), 0, "plenty of everything")
	eq(Strain.level(2, 0.5, A), 0, "two links is fine")
	eq(Strain.level(1, 0.5, A), 1, "one link left")
	eq(Strain.level(3, 0.09, A), 1, "signal under 10%")
	eq(Strain.level(3, 0.10, A), 0, "10% exactly isn't under")
	eq(Strain.level(1, 0.05, A), 2, "both")
	eq(Strain.level(1, 0.0, G), 1, "Ghost mode has no signal, only links count")
	eq(Strain.level(3, 0.0, G), 0)
	eq(Strain.level(1, 0.05, A, false), 0, "nothing before the run starts or after it ends")


func test_corruption_swaps_about_65_percent_and_keeps_spaces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var text := "next rival position depth mine density"
	var swapped := 0
	var letters := 0
	for i in 400:
		var c := Strain.corrupt(text, rng)
		eq(c.length(), text.length())
		for k in text.length():
			if text[k] == " ":
				check(c[k] == " ", "spaces stay")
				continue
			letters += 1
			if c[k] != text[k]:
				swapped += 1
				check(Strain.GLYPHS.contains(c[k]), "only corruption glyphs: " + c[k])
	var share := float(swapped) / letters
	check(share > 0.6 and share < 0.68, "about 65%% replaced (%.3f)" % share)


func test_every_glyph_an_effect_draws_is_in_a_bundled_font() -> void:
	var fonts := ["MartianMono-300", "MartianMono-400", "MartianMono-600", "MartianMono-800", "ChakraPetch-500", "ChakraPetch-700"]
	for ch in Strain.GLYPHS:
		if HudText.SHAPES.contains(ch):
			continue   # drawn as shapes, never through a font
		for f in fonts:
			var font: FontFile = load("res://assets/fonts/%s.ttf" % f)
			check(font.has_char(ch.unicode_at(0)), "%s has %s" % [f, ch])
	var jp: FontFile = load("res://assets/fonts/NotoSansJP-Bold-subset.otf")
	for w in JP_WORDS:
		for ch in w:
			check(jp.has_char(ch.unicode_at(0)), "the Japanese subset has " + ch)
	for ln in Motion.BOOT_LINES:
		if String(ln[2]).begins_with("jp:"):
			check(JP_WORDS.has(String(ln[2]).substr(3)), "boot line words are checked: " + ln[2])


func test_flash_guard_caps_at_three_a_second() -> void:
	var g := FlashGuard.new()
	check(g.allow(0.0) and g.allow(100.0) and g.allow(200.0), "three in a second")
	check(not g.allow(300.0), "not a fourth")
	check(not g.allow(999.0), "still within the second")
	check(g.allow(1000.0), "once the first is a second old")
	var count := 0
	for t in range(0, 10000, 16):
		if g.allow(2000.0 + t):
			count += 1
	check(count <= 3 * 10 + 1, "never more than 3 per second over 10 s (%d)" % count)
	g.reduce_flashing = true
	check(not g.allow(50000.0), "none with reduce flashing")


func test_reduce_motion_turns_on_reduce_flashing() -> void:
	var s := GameSettings.new()
	s.set_reduced_motion(true)
	check(s.reduce_flashing, "on by default when reduce motion is on")


## WCAG counts a change of 0.1 relative luminance or more as a flash. The
## heartbeat and the low-signal pulse must stay under it over the board's void.
func test_pulses_stay_under_the_flash_threshold() -> void:
	for p in Palette.load_all():
		var v := p.c("void")
		var d := p.c("danger")
		var lum := func(a: float) -> float: return Palette._luminance(v.lerp(d, a))
		for peak in [0.42, 0.50]:
			var hi: float = lum.call(peak * 1.0)
			var lo: float = lum.call(peak * 0.5)
			check(hi - lo < 0.1, "%s strain edge %.2f changes %.3f" % [p.id, peak, hi - lo])
		var a_hi := 0.55 * Hud.alarm_level(0.0, 0.0, 0.3, 0.1, false)
		var a_lo := 0.55 * Hud.alarm_level(0.0, 250.0, 0.3, 0.1, false)
		check(absf(lum.call(a_hi) - lum.call(a_lo)) < 0.1, "%s low-signal pulse" % p.id)


func test_heartbeat_curve() -> void:
	check(is_equal_approx(Motion.beat(0.0), 1.0), "bright")
	check(is_equal_approx(Motion.beat(0.16), 0.55), "dip")
	check(is_equal_approx(Motion.beat(0.28), 0.9), "second bump")
	check(absf(Motion.beat(0.999) - 0.5) < 0.01, "fade")
	eq(Strain.pulse(0, 123.0, false), 0.0)
	eq(Strain.pulse(1, 0.0, true), Strain.pulse(1, 370.0, true), "steady with reduce motion")
	eq(Strain.jitter(1, 40.0, false), Vector2.ZERO, "only strain 2 jitters")
	eq(Strain.jitter(2, 40.0, true), Vector2.ZERO, "never with reduce motion")
	var moved := false
	for t in [0.0, 90.0, 170.0, 250.0]:
		var j := Strain.jitter(2, t, false)
		check(absf(j.x) <= 2.0 and absf(j.y) <= 2.0, "1-2 px")
		moved = moved or j != Vector2.ZERO
	check(moved, "it does jitter")


func test_title_card_timeline() -> void:
	eq(TitleCards.duration(false, false), 33.0 + 90.0 + 300.0 + 60.0)
	eq(TitleCards.duration(true, false), 33.0 + 90.0 + 900.0 + 60.0, "LINK SEVERED holds 900 ms")
	eq(TitleCards.phase(10.0, false, false), "flash")
	eq(TitleCards.phase(60.0, false, false), "slam")
	eq(TitleCards.phase(200.0, false, false), "hold")
	eq(TitleCards.phase(430.0, false, false), "slice")
	eq(TitleCards.phase(490.0, false, false), "gone")
	eq(TitleCards.phase(900.0, true, false), "hold")
	eq(TitleCards.phase(10.0, false, true), "hold", "reduce motion: no flash, no slam, no slice")
	eq(TitleCards.duration(false, true), 390.0)


func test_cascade_rings_are_round() -> void:
	eq(GameView.ring_delay(Vector2i(0, 0), Vector2i(0, 0), false), 0.0)
	eq(GameView.ring_delay(Vector2i(3, 4), Vector2i(0, 0), false), 5.0 * Motion.RING_MS, "straight-line distance")
	eq(GameView.ring_delay(Vector2i(1, 1), Vector2i(0, 0), false), Motion.RING_MS, "a diagonal neighbour is ring 1")
	eq(GameView.ring_delay(Vector2i(4, 4), Vector2i(0, 0), false), 6.0 * Motion.RING_MS, "round, not square")
	eq(GameView.ring_delay(Vector2i(9, 9), Vector2i(0, 0), true), 0.0, "instant with reduce motion")


func test_afterimages_are_three_echoes_per_cell() -> void:
	var e := AfterimageLayer.echoes(Vector2i(5, 0), 1000.0, Vector2i(0, 0))
	eq(e.size(), 3)
	for k in 3:
		var d: Color = e[k].data
		eq(d.r, 1000.0 + Motion.ECHO_DELAYS[k], "echo %d starts at its delay" % k)
		eq(int(d.g), k)
		check(Vector2(d.b, d.a).is_equal_approx(Vector2(1, 0)), "drifts away from the click")


func test_cards_for_rivals_and_best() -> void:
	var gv := GameView.new()
	gv._rivals = [{"name": "script.kitty", "score": 1890}, {"name": "mx_halcyon", "score": 3590}, {"name": "NULL//SAINT", "score": 7000}]
	gv.mode = GameState.Mode.ARCADE
	eq(gv.cards_between(0, 1500), [], "nothing passed yet")
	var c := gv.cards_between(1500, 3600)
	eq(c.size(), 1, "passing two rivals at once shows one card")
	eq(c[0].text, "RIVAL DOWN")
	eq(c[0].sub, "mx_halcyon 3,590", "the highest one passed")
	eq(gv.cards_between(1000, 3700), [], "each rival only once per run")
	eq(gv.cards_between(6990, 7000), [], "level with a rival isn't past it")
	eq(gv.cards_between(7000, 7001)[0].sub, "NULL//SAINT 7,000")
	gv.best_before = 8000
	eq(gv.cards_between(7990, 8010)[0].text, "NEW BEST")
	eq(gv.cards_between(8010, 9000), [], "NEW BEST once per run")
	var ghost := GameView.new()
	ghost._rivals = gv._rivals
	ghost.mode = GameState.Mode.GHOST
	eq(ghost.cards_between(0, 9000), [], "Ghost runs never beat rivals")
	gv.free()
	ghost.free()


func test_datamosh_bands_cover_the_screen() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 200:
		rng.seed = s
		var cuts := Datamosh.cuts_for(rng)
		eq(cuts.size(), Motion.MOSH_BANDS + 1)
		eq(cuts[0], 0.0)
		eq(cuts[cuts.size() - 1], 1.0)
		for i in range(1, cuts.size()):
			check(cuts[i] > cuts[i - 1], "bands in order")
			check(absf(cuts[i] - cuts[i - 1] - 1.0 / 7.0) <= 2.0 / 21.0 + 1e-6, "slightly random heights")


func test_lattice_labels_come_from_chunk_keys() -> void:
	eq(LatticeLayer.chunk_id(Vector2i(0, 0)), "LAT 03F0:01A0")
	eq(LatticeLayer.chunk_id(Vector2i(-1, 2)), "LAT 03EF:01A2")
	var l := LatticeLayer.new()
	l.origin = Vector2i(5, 5)
	eq(l.corner(Vector2i(0, 0)), Vector2i(-3, -3), "the first click sits at (8, 8) of chunk 0")
	check(l.on_boundary(-3, 0) and l.on_boundary(13, 0) and l.on_boundary(-19, 1), "every 16 cells")
	check(not l.on_boundary(5, 0), "the start is mid-chunk")
	l.free()
