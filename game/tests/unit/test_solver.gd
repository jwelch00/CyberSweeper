extends TestCase


func _cells(d: Dictionary, min_tier := 1) -> Array:
	var out := []
	for c in d:
		if d[c] >= min_tier:
			out.append(c)
	out.sort()
	return out


func _keys(d: Dictionary) -> Array:
	var out := d.keys()
	out.sort()
	return out


# --- hand-made patterns -------------------------------------------------------

func test_tier1_number_already_satisfied() -> void:
	var s := Fixture.solver("""
? ? ?
- 1 -
* - -
""", 1)
	s.solve()
	eq(_keys(s.safe), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	check(not s.contradiction)


func test_tier1_hidden_count_equals_number() -> void:
	var s := Fixture.solver("""
? ? -
- 2 -
- - -
""", 1)
	s.solve()
	eq(_cells(s.mine), [Vector2i(0, 0), Vector2i(1, 0)])


func test_one_one_against_wall_needs_subset_rule() -> void:
	var text := """
? ? ?
1 1 -
- - -
"""
	var s1 := Fixture.solver(text, 1)
	s1.solve()
	check(s1.safe.is_empty(), "tier 1 alone can't see it")
	var s2 := Fixture.solver(text, 2)
	s2.solve()
	eq(_keys(s2.safe), [Vector2i(2, 0)])
	eq(s2.safe[Vector2i(2, 0)], 2, "proved by tier 2")


func test_one_two_one() -> void:
	var text := """
? ? ?
1 2 1
- - -
"""
	var s1 := Fixture.solver(text, 1)
	s1.solve()
	check(s1.safe.is_empty() and _cells(s1.mine).is_empty(), "tier 1 finds nothing")
	var s2 := Fixture.solver(text, 2)
	s2.solve()
	eq(_keys(s2.safe), [Vector2i(1, 0)])
	eq(_cells(s2.mine), [Vector2i(0, 0), Vector2i(2, 0)])


func test_one_two_two_one() -> void:
	var s := Fixture.solver("""
? ? ? ?
1 2 2 1
- - - -
""", 2)
	s.solve()
	eq(_keys(s.safe), [Vector2i(0, 0), Vector2i(3, 0)])
	eq(_cells(s.mine), [Vector2i(1, 0), Vector2i(2, 0)])


func test_true_fifty_fifty_proves_nothing() -> void:
	for text in ["""
? ?
1 -
- -
""", """
? ? ? ?
- 1 1 -
- - - -
"""]:
		var s := Fixture.solver(text, 3)
		s.solve()
		check(s.safe.is_empty(), "no safe cell in a 50/50:\n" + text)
		check(_cells(s.mine).is_empty(), "no mine either")
		check(not s.contradiction)


func test_contradiction_is_reported() -> void:
	var s := Fixture.solver("""
1 -
- -
""", 3)
	s.solve()
	check(s.contradiction, "a 1 with no hidden neighbours is impossible")


# --- against brute force and the real layout ----------------------------------

## Random small position: a zero opening plus a few more safe reveals, and
## sometimes a revealed mine.
func _position(seed: int, w := 7, h := 7, density := 0.22) -> MiniBoard:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MiniBoard.new(w, h, density, rng)
	var first: Variant = b.random_safe(rng)
	if first == null:
		return b
	b.open(first)
	for i in rng.randi_range(0, 4):
		var c: Variant = b.random_safe_frontier(rng)
		if c != null:
			b.open(c)
	if rng.randf() < 0.3:
		for m: Vector2i in b.mines:
			for d in Board.NB:
				if b.revealed.has(m + d):
					b.hit[m] = true
					break
			if b.hit.has(m):
				break
	return b


func test_whole_board_window_equals_brute_force() -> void:
	var nontrivial := 0
	for seed in 300:
		var b := _position(seed)
		var brute := Brute.solve(b.solver())
		var s := b.solver(3, 12)
		s.solve()
		check(not s.contradiction, "seed %d contradiction" % seed)
		eq(_keys(s.safe), _keys(brute.safe), "safe, seed %d" % seed)
		eq(_cells(s.mine), _keys(brute.mine), "mines, seed %d" % seed)
		if brute.safe.size() + brute.mine.size() > 0 and brute.solutions > 1:
			nontrivial += 1
	check(nontrivial > 100, "only %d positions had something to prove" % nontrivial)


func test_every_tier_is_sound() -> void:
	for seed in 400:
		var b := _position(1000 + seed, 9, 9)
		var brute := Brute.solve(b.solver())
		for tier in [1, 2, 3]:
			var s := b.solver(tier, 2)
			s.solve()
			check(not s.contradiction, "seed %d tier %d contradiction" % [seed, tier])
			for c in s.safe:
				check(not b.mines.has(c), "seed %d tier %d: proved a mine safe at %s" % [seed, tier, c])
				check(brute.safe.has(c), "seed %d tier %d: %s not provably safe" % [seed, tier, c])
			for c in _cells(s.mine):
				check(b.mines.has(c), "seed %d tier %d: proved a safe cell is a mine at %s" % [seed, tier, c])
				check(brute.mine.has(c), "seed %d tier %d: %s not provably a mine" % [seed, tier, c])


## The property the generator's guarantee rests on: learning more never
## un-proves anything.
func test_monotone_when_learning_more() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var checked := 0
	for seed in 300:
		var b := _position(5000 + seed, 10, 10, 0.2)
		var more := b.copy()
		for i in rng.randi_range(1, 4):
			var c: Variant = more.random_safe_frontier(rng)
			if c != null:
				more.open(c)
		for tier in [1, 2, 3]:
			var before := b.solver(tier, 2)
			before.solve()
			var after := more.solver(tier, 2)
			after.solve()
			for c in before.safe:
				check(more.revealed.has(c) or after.safe.has(c), "seed %d tier %d lost safe %s" % [seed, tier, c])
			for c in _cells(before.mine):
				check(after.mine.has(c), "seed %d tier %d lost mine %s" % [seed, tier, c])
			checked += 1
	check(checked == 900)


func test_tiers_are_nested_and_tier3_adds_power() -> void:
	var t2_beats_t1 := 0
	var t3_beats_t2 := 0
	for seed in 400:
		var b := _position(9000 + seed, 9, 9)
		var found: Array[int] = []
		for tier in [1, 2, 3]:
			var s := b.solver(tier, 2)
			s.solve()
			found.append(s.safe.size() + _cells(s.mine).size())
		check(found[0] <= found[1] and found[1] <= found[2], "seed %d tiers not nested %s" % [seed, found])
		if found[1] > found[0]:
			t2_beats_t1 += 1
		if found[2] > found[1]:
			t3_beats_t2 += 1
	check(t2_beats_t1 > 0, "tier 2 never helped")
	check(t3_beats_t2 > 0, "tier 3 never helped")


func test_stop_early_then_resume_reaches_same_fixpoint() -> void:
	for seed in 100:
		var b := _position(20000 + seed, 10, 10, 0.2)
		var once := b.solver()
		once.solve()
		var steps := b.solver()
		steps.solve(true)
		steps.solve(true)
		steps.solve()
		eq(_keys(steps.safe), _keys(once.safe), "seed %d" % seed)
		eq(_cells(steps.mine), _cells(once.mine), "seed %d" % seed)
