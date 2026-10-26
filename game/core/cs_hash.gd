class_name CsHash
extends RefCounted
## Deterministic 32-bit hashing for board generation.
##
## Every multiply is split into 16-bit halves so no intermediate value gets near
## 2^63. GDScript ints are 64-bit everywhere, so this gives the same bytes on
## Windows, macOS and Linux. tests/unit/test_hash.gd pins golden values.

const MASK32 := 0xFFFFFFFF


## (a * b) mod 2^32 for a, b in [0, 2^32), without overflowing int64.
static func mul32(a: int, b: int) -> int:
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) & 0xFFFF) * b
	return (lo + ((hi & 0xFFFF) << 16)) & MASK32


## 32-bit avalanche mix ("lowbias32").
static func mix32(h: int) -> int:
	h &= MASK32
	h ^= h >> 16
	h = mul32(h, 0x7FEB352D)
	h ^= h >> 15
	h = mul32(h, 0x846CA68B)
	h ^= h >> 16
	return h


## Hash of (seed, x, y, salt) to a uniform value in [0, 2^32).
static func hash4(seed: int, x: int, y: int, salt: int) -> int:
	var h := mix32(seed ^ 0x9E3779B9)
	h = mix32(h ^ (x & MASK32))
	h = mix32(h ^ (y & MASK32) ^ 0x85EBCA6B)
	h = mix32(h ^ (salt & MASK32) ^ 0xC2B2AE35)
	return h


## Folds a byte array into a running hash (used for board fingerprints in tests).
static func fold_bytes(h: int, bytes: PackedByteArray) -> int:
	for b in bytes:
		h = mix32(h ^ b ^ 0x27D4EB2F)
	return h


## Seed as shown in the HUD, e.g. "7F3A-91C2".
static func seed_text(seed: int) -> String:
	var s := "%08X" % (seed & MASK32)
	return s.substr(0, 4) + "-" + s.substr(4, 4)
