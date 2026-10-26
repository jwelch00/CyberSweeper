class_name Jag
extends RefCounted
## The street deck's jagged panel silhouettes (design/MOTION.md, "HUD frames"):
## uneven cut corners, a notch bitten out of the top edge, sawtooth teeth near
## the top right, a 45-degree jog in the right edge and a step in the bottom.
## An exact port of CS.jagPoints in design/shared/screens.js, so each seed
## gives the mockup's shape.

## Mockup seeds as CS.jagAll computes them (data-seed + index * 7 + 3).
const SEED_TL := 14
const SEED_SIG := 33
const SEED_SCORE := 22
const SEED_BL := 55
const SEED_MM := 48
const SEED_HINTS := 79
const SEED_OVER := 6
const SEED_OVER_SIDE := 19


static func _r(seed: int, k: int) -> float:
	return JsPort.hash2(seed, k, 11)


## {pts: PackedVector2Array (the outline, clockwise from the top-left cut),
##  hot: [PackedVector2Array, PackedVector2Array] (the thick accent strokes)}
static func points(w: float, h: float, seed: int) -> Dictionary:
	var ctl := 14 + JsPort.round_js(_r(seed, 1) * 12.0)
	var cbr := 16 + JsPort.round_js(_r(seed, 2) * 14.0)
	var cbl := 6
	var jog := 6
	var step := 6
	var jog_y := JsPort.round_js(h * (0.38 + _r(seed, 3) * 0.25))
	var nx := JsPort.round_js(w * (0.30 + _r(seed, 4) * 0.25))
	var nw := 34 + JsPort.round_js(_r(seed, 5) * 40.0)
	var nd := 5
	var step_x := JsPort.round_js(w * (0.28 + _r(seed, 6) * 0.3))
	var pts := PackedVector2Array([Vector2(ctl, 0)])
	if _r(seed, 8) > 0.3 and nx + nw < w - 60:
		pts.append_array([Vector2(nx, 0), Vector2(nx + nd, nd), Vector2(nx + nw - nd, nd), Vector2(nx + nw, 0)])
	if _r(seed, 7) > 0.35:
		var x := w - 46
		while x < w - 10:
			pts.append_array([Vector2(x, 0), Vector2(x + 5, 5)])
			x += 10
		pts.append_array([Vector2(w - 10, 0), Vector2(w - 6, 0), Vector2(w, 6)])
	else:
		pts.append_array([Vector2(w - 6, 0), Vector2(w, 6)])
	pts.append_array([Vector2(w, jog_y), Vector2(w - jog, jog_y + jog), Vector2(w - jog, h - cbr),
		Vector2(w - jog - cbr, h), Vector2(step_x + step, h), Vector2(step_x, h - step), Vector2(cbl, h - step),
		Vector2(0, h - step - cbl), Vector2(0, ctl)])
	var hot := [
		PackedVector2Array([Vector2(0, ctl + 18), Vector2(0, ctl), Vector2(ctl, 0), Vector2(ctl + 44, 0)]),
		PackedVector2Array([Vector2(w - jog, h - cbr - 22), Vector2(w - jog, h - cbr), Vector2(w - jog - cbr, h),
			Vector2(w - jog - cbr - 34, h)]),
	]
	return {"pts": pts, "hot": hot}
