extends TestCase


func _board(seed := 7, at := Vector2i.ZERO) -> Board:
	var b := Board.new(seed, Rules.load_default())
	b.start(at)
	return b


func test_origin_sits_mid_chunk_even_negative() -> void:
	for at in [Vector2i.ZERO, Vector2i(-37, 1000), Vector2i(-1, -1), Vector2i(123456, -654321)]:
		var b := _board(1, at)
		eq(b.chunk_key(at), Vector2i.ZERO, "origin chunk for %s" % at)
		eq(b.chunk_corner(Vector2i.ZERO) + Vector2i(8, 8), at, "origin local cell for %s" % at)


func test_chunk_addressing_round_trip() -> void:
	var b := _board(1, Vector2i(-5, 3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 500:
		var c := Vector2i(rng.randi_range(-3000, 3000), rng.randi_range(-3000, 3000))
		var corner := b.chunk_corner(b.chunk_key(c))
		var off := c - corner
		check(off.x >= 0 and off.y >= 0 and off.x < 16 and off.y < 16, "cell %s corner %s" % [c, corner])


func test_start_zone_is_mine_free() -> void:
	for seed in 50:
		var b := _board(seed, Vector2i(seed * 3, -seed))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				check(not b.is_mine(b.origin + Vector2i(dx, dy)), "seed %d" % seed)
		eq(b.number(b.origin), 0, "origin is a zero")


func test_drafts_are_deterministic() -> void:
	var a := _board(424242)
	var b := _board(424242)
	var c := _board(424243)
	var same := true
	var differs := false
	for y in range(-40, 40):
		for x in range(-40, 40):
			var p := Vector2i(x, y)
			if a.is_mine(p) != b.is_mine(p):
				same = false
			if a.is_mine(p) != c.is_mine(p):
				differs = true
	check(same, "same seed, same draft")
	check(differs, "different seed, different draft")


func test_depth_matches_mockup() -> void:
	var b := _board(1, Vector2i(10, 10))
	eq(b.depth(Vector2i(73, 28)), 65, "x 63 y 18 is depth 65")
	eq(b.depth(Vector2i(10, 10)), 0)
	eq(b.depth(Vector2i(13, 14)), 5)


func test_cascade_ring_order_and_undo() -> void:
	var b := _board(5)
	var starts: Array[Vector2i] = [b.origin]
	var rec := b.apply_reveals(starts)
	check(rec.cells.size() >= 9, "zero opens its neighbours")
	eq(rec.rings[0], 0)
	for i in range(1, rec.rings.size()):
		check(rec.rings[i] >= rec.rings[i - 1], "rings never go down")
	for c: Vector2i in rec.cells:
		check(b.is_open(c), "revealed safe")
		check(not b.is_mine(c), "cascade never reveals a mine")
	b.undo_reveals(rec)
	for c: Vector2i in rec.cells:
		check(not b.is_revealed(c), "undo hides again")


func test_cascade_clears_wrong_flags() -> void:
	var b := _board(5)
	var n := b.origin + Vector2i(1, 0)
	b.set_flag(n, true)
	var starts: Array[Vector2i] = [b.origin]
	var rec := b.apply_reveals(starts)
	check(b.is_open(n), "flag next to a zero gets revealed")
	check(not b.is_flagged(n), "and cleared")
	b.undo_reveals(rec)
	check(b.is_flagged(n), "undo restores the flag")


func test_hit_reveals_only_the_mine() -> void:
	var b := _board(9)
	var mine := Vector2i.ZERO
	for y in range(-20, 20):
		for x in range(-20, 20):
			if b.is_mine(Vector2i(x, y)):
				mine = Vector2i(x, y)
	var starts: Array[Vector2i] = [mine]
	var rec := b.apply_reveals(starts)
	eq(rec.cells.size(), 1)
	eq(rec.hits.size(), 1)
	eq(b.state_at(mine), Board.HIT)


func test_flags_live_outside_chunks() -> void:
	var b := _board(3)
	var before := b.chunks.size()
	b.set_flag(Vector2i(5000, 5000), true)
	eq(b.chunks.size(), before, "flagging never drafts chunks")
	check(b.is_flagged(Vector2i(5000, 5000)))
