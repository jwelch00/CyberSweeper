extends TestCase
## Golden values come from an independent Python implementation of the same
## hash, so a platform or port difference shows up here.


func test_mul32_matches_reference() -> void:
	eq(CsHash.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
	eq(CsHash.mul32(0x12345678, 0x846CA68B), 756859688)
	eq(CsHash.mul32(3, 5), 15)


func test_mix32_golden() -> void:
	eq(CsHash.mix32(0), 0)
	eq(CsHash.mix32(1), 1753845952)
	eq(CsHash.mix32(0xDEADBEEF), 3861431939)
	eq(CsHash.mix32(0xFFFFFFFF), 1734902346)


func test_hash4_golden() -> void:
	eq(CsHash.hash4(0, 0, 0, 0), 2567720537)
	eq(CsHash.hash4(1, 2, 3, 4), 2848380152)
	eq(CsHash.hash4(0x7F3A91C2, -63, 18, 0), 3214533750)
	eq(CsHash.hash4(0xFFFFFFFF, -1, -1, 7), 2203284549)
	eq(CsHash.hash4(12345, 100000, -100000, 3), 1078669447)


func test_hash4_range_and_spread() -> void:
	var below := 0
	var n := 20000
	var threshold := int(0.2 * 4294967296.0)
	for i in n:
		var h := CsHash.hash4(99, i % 141 - 70, i / 141 - 70, 0)
		check(h >= 0 and h <= CsHash.MASK32, "out of range: %d" % h)
		if h < threshold:
			below += 1
	var frac := float(below) / n
	check(absf(frac - 0.2) < 0.015, "mine fraction %f far from 0.2" % frac)


func test_seed_text() -> void:
	eq(CsHash.seed_text(0x7F3A91C2), "7F3A-91C2")
	eq(CsHash.seed_text(0x1), "0000-0001")
