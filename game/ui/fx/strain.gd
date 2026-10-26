class_name Strain
extends RefCounted
## Strain ("cyberpsychosis", design/MOTION.md 4): when you're in trouble the
## deck starts losing it. Level = (one link left) + (signal shown under 10%).
## Ghost mode has no signal, so only the links count there. Only the HUD and
## the screen edges are affected, never the board.

const SIGNAL_MARK := 0.10
## Corruption glyphs. ▓▒░█▚▞ΞΣ aren't in the bundled fonts, so
## HudText.draw_glitch_string draws those as shapes.
const GLYPHS := "▓▒░█▚▞#%&$@!?¥ΞΣ0123456789"
## Share of a label's characters that get replaced (fx.js keeps 35%).
const REPLACE := 0.65


static func level(links: int, signal_shown: float, mode: GameState.Mode, live := true) -> int:
	if not live:
		return 0
	var n := 1 if links == 1 else 0
	if mode != GameState.Mode.GHOST and signal_shown < SIGNAL_MARK:
		n += 1
	return n


## `text` with about 65% of its characters (never spaces) swapped for glyphs.
static func corrupt(text: String, rng: RandomNumberGenerator) -> String:
	var out := ""
	for ch in text:
		if ch == " " or rng.randf() >= REPLACE:
			out += ch
		else:
			out += GLYPHS[rng.randi_range(0, GLYPHS.length() - 1)]
	return out


## Vignette strength for this level at clock `ms`: the heartbeat (60 bpm at
## level 1, 120 at level 2). Steady with reduce motion.
static func pulse(lvl: int, ms: float, reduced: bool) -> float:
	if lvl <= 0:
		return 0.0
	if reduced:
		return 0.8
	var period := 1000.0 if lvl == 1 else 500.0
	return Motion.beat(ms / period)


## HUD jitter at level 2: 1-2 px, stepping at 12 Hz (cs.css @keyframes jitter).
static func jitter(lvl: int, ms: float, reduced: bool) -> Vector2:
	if lvl < 2 or reduced:
		return Vector2.ZERO
	var steps := [Vector2(0, 0), Vector2(1, -1), Vector2(-1, 1), Vector2(2, 0)]
	return steps[int(ms / 83.0) % 4]
