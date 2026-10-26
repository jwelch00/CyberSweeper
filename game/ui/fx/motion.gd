class_name Motion
extends RefCounted
## Every motion timing from design/MOTION.md (mirrors FX.T in
## design/shared/fx.js; tests/unit/test_design_port.gd checks they agree),
## plus the easing curves the mockups use.

# 1. boot
const BOOT_LINE_MS := 42.0
const BOOT_HOLD_END_MS := 160.0
const BOOT_LOG_FADE_MS := 200.0
const BOOT_LOADER_HOLD_MS := 180.0
const BOOT_ACCEPT_FLASH_MS := 160.0
const BOOT_DENIED_KICK_MS := 160.0
const JACKED_OFF_CHANCE := 1.0 / 10000.0
const BOOT_LINES := [
	["00.000", "cs-deck // street build " + CsVersion.GAME, "hi"],
	["00.038", "cold boot ................................ ", "ok:ok"],
	["00.081", "mounting cipher toolkit .................. ", "ok:ok"],
	["00.119", "proxy chain: 7 hops ...................... ", "ok:ok"],
	["00.164", "spoofing corp handshake .................. ", "ok:ok"],
	["00.203", "target: TETSUKAGE DATAWORKS // SECURE LATTICE  ", "jp:鉄影"],
	["00.247", "lattice size ............................. ", "warn:unbounded"],
	["00.288", "ice signatures ........................... ", "warn:black, many"],
	["00.330", "scanning for 50/50 traps ................. ", "ok:none found"],
	["00.371", "links .................................... ", "ok:3/3"],
	["00.409", "signal ................................... ", "ok:100%"],
	["00.452", "jacking in  ", "jp:接続"],
]

# 2. title cards
const CARD_FLASH_MS := 33.0
const CARD_SLAM_MS := 90.0
const CARD_HOLD_MS := 300.0
const CARD_FULL_HOLD_MS := 900.0
const CARD_SLICE_MS := 60.0

# 3. sandevistan cascade
const RING_MS := 22.0
const GHOST_LIFE_MS := 360.0
const ECHO_DELAYS: Array[float] = [0.0, 40.0, 80.0]
const DRIFT_PX := 11.0
const TRAIL_MIN_CELLS := 12
const FLOOR_FLASH_MS := 260.0

# 4. strain
const CORRUPT_EVERY_MS: Array[float] = [3000.0, 800.0]
const CORRUPT_FOR_MS: Array[float] = [90.0, 140.0]
const TEAR_EVERY_MS := 1500.0
const STRAIN_TEAR_MS := 60.0
const PKT_EVERY_MS := 180.0

# 6. mine hit
const HIT_SLAM_MS := 120.0
const SHAKE_MS := 250.0
const SHAKE_PX := 8.0
const HIT_FLASH_MS := 60.0
const HIT_TEAR_MS := 66.0
const HIT_MARCH_MS := 1200.0
const SHATTER_MS := 320.0
const SHATTER_PX := 22.0

# 7. datamosh
const MOSH_BREAK_MS := 180.0
const MOSH_TOTAL_MS := 380.0
const MOSH_BANDS := 7
const MOSH_OLD_FADE_MS := 70.0


## CSS cubic-bezier(x1, y1, x2, y2) at progress t in [0, 1].
static func bezier(x1: float, y1: float, x2: float, y2: float, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t == 0.0 or t == 1.0:
		return t
	# Solve x(s) = t by bisection (monotone for CSS curves), then return y(s).
	var lo := 0.0
	var hi := 1.0
	var s := t
	for i in 24:
		s = (lo + hi) * 0.5
		var x := _b(x1, x2, s)
		if x < t:
			lo = s
		else:
			hi = s
	return _b(y1, y2, s)


static func _b(p1: float, p2: float, s: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s


static func ease_out(t: float) -> float:
	return bezier(0.0, 0.0, 0.58, 1.0, t)


## The strain vignette's heartbeat (cs.css @keyframes beat, ease-out between
## keyframes): opacity at phase t in [0, 1) of one beat.
static func beat(t: float) -> float:
	t = fposmod(t, 1.0)
	var keys := [[0.0, 1.0], [0.16, 0.55], [0.28, 0.9], [1.0, 0.5]]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(a[1], b[1], ease_out((t - a[0]) / (b[0] - a[0])))
	return 0.5
