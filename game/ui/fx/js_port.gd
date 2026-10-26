class_name JsPort
extends RefCounted
## Exact ports of the little random helpers in design/shared/*.js, so shapes
## and boot plans come out identical to the mockups and the motion lab.
## tests/unit/test_design_port.gd checks them against values the JS itself
## produced (tests/data/js_reference.json, from tools/js_reference.mjs).

const M32 := 0xFFFFFFFF
const TWO32 := 4294967296.0


## JS Math.round: halves round up.
static func round_js(v: float) -> int:
	return int(floor(v + 0.5))


## CS.hash2(x, y, s) from board.js, a float in [0, 1). The first sum is done
## in doubles like the JS, so large inputs round the same way.
static func hash2(x: int, y: int, s: int) -> float:
	var f := float(x) * 374761393.0 + float(y) * 668265263.0 + float(s) * 2147483647.0
	var h := _js_int32_bits(f)
	h = CsHash.mul32(h ^ (h >> 13), 1274126177)
	return float((h ^ (h >> 16)) & M32) / TWO32


## ToInt32 bits of a double (truncate toward zero, then mod 2^32).
static func _js_int32_bits(f: float) -> int:
	var t := f - fmod(f, 1.0)
	return int(fposmod(t, TWO32)) & M32


## mulberry32 from fx.js: a seeded generator of floats in [0, 1).
class Mulberry:
	var a := 0

	func _init(seed: int) -> void:
		a = seed & JsPort.M32

	func next() -> float:
		a = (a + 0x6D2B79F5) & JsPort.M32
		var t := CsHash.mul32(a ^ (a >> 15), 1 | a)
		t = ((t + CsHash.mul32(t ^ (t >> 7), 61 | t)) & JsPort.M32) ^ t
		return float((t ^ (t >> 14)) & JsPort.M32) / JsPort.TWO32
