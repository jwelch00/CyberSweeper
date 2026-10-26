class_name BootScreen
extends Control
## The jack-in boot (design/MOTION.md 1): a terminal log types itself out on
## void, then the breach takes centre stage. A 9x5 board solves itself in a
## diagonal sweep, a session key cracks character by character, hex dumps pop
## open, and depending on the boot seed it may hit ACCESS DENIED on the way
## (BreachPlan). KEY ACCEPTED, the JACKED IN card, then the flow datamoshes to
## the title. Any key or click skips. 1 boot in 10,000 the card reads
## JACKED OFF. Same timing, same subtitle, never explained.

signal finished

const W := 9
const H := 5
const MINES := [11, 24, 30, 42]
const TILE := 30.0
const GAP := 3.0
const LOADER_SCALE := 1.35
const DUMP_TITLES := ["proc/ice_daemon", "net/handshake", "mem/0x", "lattice/chunk_map"]
const DUMP_AT := [Vector2(-560, -150), Vector2(330, -190), Vector2(-500, 120), Vector2(360, 110)]

var fx: ScreenFx
var palette: Palette
var sfx: Sfx
var plan: BreachPlan
var jacked_off := false
var reduced := false

var _start := 0.0
var _running := false
var _card_played := false
var _accept_played := false
var _denials_seen := {}
var _kick_until := -1e9
var _accept_flash := false
var _max_p := 0.0
var _dumps: Array = [[], [], [], []]
var _rng := RandomNumberGenerator.new()
var _mono: Font
var _mono_b: Font
var _mono_6: Font
var _cap: FontVariation
var _key_font: FontVariation
var _ui: FontVariation
var _jp: Font
var _title_font: FontVariation


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mono = load("res://assets/fonts/MartianMono-400.ttf")
	_mono_6 = load("res://assets/fonts/MartianMono-600.ttf")
	_mono_b = load("res://assets/fonts/MartianMono-800.ttf")
	_cap = Hud.spaced(_mono, 2)
	_key_font = Hud.spaced(_mono_6, 1)
	_ui = Hud.spaced(load("res://assets/fonts/ChakraPetch-700.ttf"), 5)
	_jp = load("res://assets/fonts/NotoSansJP-Bold-subset.otf")
	_title_font = Hud.spaced(_mono_6, 1)
	_rng.randomize()


## Starts the boot. seed < 0 picks a fresh one; force is a breach kind.
func begin(seed := -1, force := "", off := -1) -> void:
	if seed < 0:
		seed = _rng.randi() & 0x7FFFFFFF
	plan = BreachPlan.make(seed, force)
	jacked_off = _rng.randf() < Motion.JACKED_OFF_CHANCE if off < 0 else off == 1
	_start = fx.clock_ms
	_running = true
	_card_played = false
	_accept_played = false
	_denials_seen = {}
	_max_p = 0.0
	_dumps = [[], [], [], []]
	reduced = fx.reduced_motion


func card_text() -> String:
	return "JACKED OFF" if jacked_off else "JACKED IN"


# Beats, in ms from the start.
func lines_end() -> float:
	return 0.0 if reduced else Motion.BOOT_LINES.size() * Motion.BOOT_LINE_MS


func loader_at() -> float:
	return lines_end() + Motion.BOOT_HOLD_END_MS


func breach_ms() -> float:
	return 0.0 if reduced else plan.total_ms


func accept_at() -> float:
	return loader_at() + breach_ms()


func card_at() -> float:
	return accept_at() + Motion.BOOT_LOADER_HOLD_MS


## Time until the title screen is interactive (card, then the datamosh).
func total_ms() -> float:
	return card_at() + TitleCards.duration(false, reduced) + (0.0 if reduced else Motion.MOSH_TOTAL_MS)


func elapsed() -> float:
	return fx.clock_ms - _start


func _process(_delta: float) -> void:
	if not _running:
		return
	var t := elapsed()
	var tb := t - loader_at()
	if tb >= 0.0 and tb < breach_ms():
		var at := plan.at(tb)
		_max_p = maxf(_max_p, at.p)
		var seg: Dictionary = at.seg
		if seg.get("denied", false) and not _denials_seen.has(seg.t0):
			_denials_seen[seg.t0] = true
			if sfx:
				sfx.play("denied")
			if fx.guard.allow(fx.clock_ms):
				_kick_until = fx.clock_ms + Motion.BOOT_DENIED_KICK_MS
		for k in 4:
			if tb / breach_ms() > 0.06 + k * 0.1:
				_dumps[k].append(_dump_line())
				while _dumps[k].size() > 7:
					_dumps[k].pop_front()
	if t >= accept_at() and not _accept_played:
		_accept_played = true
		_max_p = 100.0
		_accept_flash = fx.guard.allow(fx.clock_ms)
		if sfx:
			sfx.play("accepted")
	if t >= card_at() and not _card_played:
		_card_played = true
		fx.cards.play({"text": card_text(), "jp": "接続完了", "sub": "TETSUKAGE // SECURE LATTICE", "role": "accent"})
		if sfx:
			sfx.play("slam")
		fx.cards.finished.connect(_on_card, CONNECT_ONE_SHOT)
	queue_redraw()


func _on_card(_spec: Dictionary) -> void:
	_running = false
	finished.emit()


func skip() -> void:
	if not _running:
		return
	_running = false
	fx.cards.clear()
	if fx.cards.finished.is_connected(_on_card):
		fx.cards.finished.disconnect(_on_card)
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		skip()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_pressed() and not event.is_echo():
		skip()
		get_viewport().set_input_as_handled()


func _hex() -> String:
	return "%02X" % _rng.randi_range(0, 255)


func _dump_line() -> String:
	var parts: Array[String] = []
	for i in 8:
		parts.append(_hex())
	return "%04X  %s" % [_rng.randi_range(0, 0xFFFF), " ".join(parts)]


static func number_at(i: int) -> int:
	var x := i % W
	var y := i / W
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var X := x + dx
			var Y := y + dy
			if (dx != 0 or dy != 0) and X >= 0 and Y >= 0 and X < W and Y < H and MINES.has(Y * W + X):
				n += 1
	return n


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if palette == null or plan == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), palette.c("void"))
	var t := elapsed()
	_draw_log(t)
	if t >= loader_at():
		_draw_loader(t)


func _draw_log(t: float) -> void:
	var dim := palette.c("inkDim")
	var fade := 1.0
	if t >= loader_at():
		fade = lerpf(1.0, 0.25, clampf((t - loader_at()) / Motion.BOOT_LOG_FADE_MS, 0.0, 1.0))
	var n := Motion.BOOT_LINES.size() if reduced else mini(Motion.BOOT_LINES.size(), int(t / Motion.BOOT_LINE_MS) + 1)
	var lh := 17.0 * 1.75
	var y := 80.0 + lh * 0.72
	var x0 := 110.0
	var ts_col := Color(dim, 0.6 * fade)
	for i in n:
		var ln: Array = Motion.BOOT_LINES[i]
		var x := x0
		draw_string(_mono, Vector2(x, y), "[%s]" % ln[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ts_col)
		x += _mono.get_string_size("[%s]" % ln[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 18.0
		var kind: String = ln[2].split(":")[0]
		var val: String = ln[2].split(":")[1] if ln[2].contains(":") else ""
		var body := Color(palette.c("ink") if kind == "hi" else dim, fade)
		draw_string(_mono, Vector2(x, y), ln[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, body)
		x += _mono.get_string_size(ln[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		match kind:
			"ok":
				draw_string(_mono, Vector2(x, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(palette.c("accent"), fade))
				x += _mono.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			"warn":
				draw_string(_mono, Vector2(x, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(palette.c("warn"), fade))
				x += _mono.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			"jp":
				draw_string(_jp, Vector2(x, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(palette.c("ink"), fade))
				x += _jp.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var established := t >= lines_end()
		if i == n - 1 and not established:
			draw_rect(Rect2(x + 4, y - 15, 10, 18), Color(palette.c("accent"), fade))
		y += lh
	if t >= lines_end():
		y += 14.0
		draw_string(_mono, Vector2(x0, y), "[00.611]", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ts_col)
		var x := x0 + _mono.get_string_size("[00.611]", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 18.0
		draw_string(_mono_b, Vector2(x, y), "LINK ESTABLISHED", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(palette.c("accent"), fade))
	# Progress bar along the bottom, one step per log line, and the skip hint.
	var bar := Rect2(110, size.y - 80 - 6, size.x - 220, 6)
	draw_rect(bar, Color(palette.c("accent"), 0.15))
	var frac := float(n) / Motion.BOOT_LINES.size()
	var fill := Rect2(bar.position, Vector2(bar.size.x * frac, 6))
	draw_rect(fill.grow(3.0), Color(palette.c("accent"), 0.18))
	draw_rect(fill, palette.c("accent"))
	var skip := "any key to skip"
	var sw := _mono.get_string_size(skip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_mono, Vector2(size.x - 110 - sw, size.y - 100 - 4), skip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(dim, 0.7))


func _draw_loader(t: float) -> void:
	var tb := t - loader_at()
	var done := t >= accept_at()
	var at := plan.at(tb) if not done else {"p": 100.0, "seg": {}}
	var p: float = at.p
	var seg: Dictionary = at.seg
	var denied: bool = seg.get("denied", false)
	var mid := size * 0.5
	# Hex dumps around it (unscaled), each popping open in 4 steps over 90 ms.
	for k in 4:
		var show_at := loader_at() + (0.06 + k * 0.1) * breach_ms()
		if t < show_at and not done:
			continue
		var grow := 1.0 if reduced else clampf(floorf((t - show_at) / Motion.CARD_SLAM_MS * 4.0) / 4.0, 0.05, 1.0)
		_draw_dump(mid + DUMP_AT[k], k, grow)
	draw_set_transform(mid, 0.0, Vector2(LOADER_SCALE, LOADER_SCALE))
	var gw := W * TILE + (W - 1) * GAP
	var gh := H * TILE + (H - 1) * GAP
	var top := -(16 + 16 + gh + 16 + 28 + 16 + 32) * 0.5
	# Header
	var hdr1 := "BREACHING ICE  "
	var hdr2 := "  SECURE LATTICE"
	var w1 := _cap.get_string_size(hdr1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var wj := _jp.get_string_size("鉄影", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var w2 := _cap.get_string_size(hdr2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var hx := -(w1 + wj + w2) * 0.5
	var acc := palette.c("accent")
	# .bootload .cap comes after .hdr in cs.css, so the header is ink-dim.
	var hc := palette.c("inkDim")
	draw_string(_cap, Vector2(hx, top + 13), hdr1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hc)
	draw_string(_jp, Vector2(hx + w1, top + 13), "鉄影", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hc)
	draw_string(_cap, Vector2(hx + w1 + wj, top + 13), hdr2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hc)
	# The mini board: decrypts along the diagonal as progress passes each tile.
	var gy := top + 32.0
	var kick := clampf((_kick_until - fx.clock_ms) / Motion.BOOT_DENIED_KICK_MS, 0.0, 1.0)
	var bright := 1.0
	if done and _accept_flash and not reduced:
		bright = lerpf(2.2, 1.0, clampf((t - accept_at()) / Motion.BOOT_ACCEPT_FLASH_MS, 0.0, 1.0))
	var max_d := float((W - 1) + (H - 1))
	for i in W * H:
		var x := i % W
		var y := i / W
		var r := Rect2(-gw * 0.5 + x * (TILE + GAP) + 6.0 * kick, gy + y * (TILE + GAP), TILE, TILE)
		var on := _max_p / 100.0 >= (x + y) / max_d * 0.9 + 0.08
		_draw_tile(r, i, on, kick, bright)
	# Session key: locked characters (accent, glowing) left to right with
	# progress; they un-lock if progress drops.
	var ky := gy + gh + 16.0 + 22.0
	var chars := plan.key
	var locked := int(floor(p / 100.0 * 16.0))
	var cw := _key_font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 2.0
	var kx := -cw * chars.length() * 0.5
	var idx := 0
	for c in chars:
		var col := Color(palette.c("inkDim"), 0.7)
		var shown := c
		if c == "-":
			col = palette.c("inkDim")
		else:
			if idx < locked:
				col = acc
				draw_string_outline(_key_font, Vector2(kx, ky), c, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(acc, 0.25))
			else:
				shown = "%X" % _rng.randi_range(0, 15)
			idx += 1
		draw_string(_key_font, Vector2(kx, ky), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		kx += cw
	# Status and percentage.
	var ry := ky + 16.0 + 26.0
	var status := "CRACKING SESSION KEY"
	var sc := palette.c("inkDim")
	if done:
		status = "KEY ACCEPTED"
		sc = acc
	elif denied:
		status = "RETRYING VIA PROXY %d" % int(seg.get("proxy", 2))
		sc = palette.c("danger")
	var pc := "%d%%" % JsPort.round_js(p)
	var sw := _cap.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var pw := maxf(_mono_b.get_string_size(pc, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x, _mono_b.get_string_size("100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x)
	var rx := -(sw + 18.0 + pw) * 0.5
	draw_string(_cap, Vector2(rx, ry), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, sc)
	var pcw := _mono_b.get_string_size(pc, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(_mono_b, Vector2(rx + sw + 18.0 + pw - pcw, ry + 2), pc, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, acc)
	# ACCESS DENIED stamp: scales 1.25 -> 1 in, holds, fades out over the beat.
	if denied and not done:
		var f := (tb - float(seg.t0)) / maxf(1.0, float(seg.t1) - float(seg.t0))
		var a := 1.0
		var s := 1.0
		if f < 0.25:
			a = f / 0.25
			s = lerpf(1.25, 1.0, f / 0.25)
		elif f > 0.8:
			a = 1.0 - (f - 0.8) / 0.2
		if reduced:
			a = 1.0
			s = 1.0
		_draw_denied(Vector2(0, top + (16 + 16 + gh + 16 + 28 + 16 + 32) * 0.38), s, a)
	draw_set_transform(Vector2.ZERO)


func _draw_tile(r: Rect2, i: int, on: bool, kick: float, bright: float) -> void:
	var tint := func(c: Color) -> Color:
		var o := css_filter(c, 140.0 * kick, 1.0 + 2.0 * kick) if kick > 0.0 else c
		return Color(minf(o.r * bright, 1.0), minf(o.g * bright, 1.0), minf(o.b * bright, 1.0), o.a)
	if on and MINES.has(i):
		draw_rect(r, tint.call(palette.c("tile")))
		_draw_flag(r, tint.call(palette.c("warn")))
		return
	if on:
		draw_rect(r, tint.call(palette.c("floor")))
		draw_rect(r, tint.call(palette.c("grid")), false, 1.0)
		var n := number_at(i)
		if n > 0:
			var s := str(n)
			var nc: Color = tint.call(palette.number(n))
			var w := _mono_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var pos := r.position + Vector2((TILE - w) * 0.5, TILE * 0.5 + 6)
			draw_string_outline(_mono_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(nc, 0.25))
			draw_string(_mono_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, nc)
		return
	var cut := TILE * 0.16
	var poly := PackedVector2Array([r.position + Vector2(cut, 0), r.position + Vector2(TILE, 0), r.end,
		r.position + Vector2(0, TILE), r.position + Vector2(0, cut)])
	draw_colored_polygon(poly, tint.call(palette.c("tile")))
	draw_line(r.position + Vector2(cut, 0.5), r.position + Vector2(TILE, 0.5), tint.call(palette.c("tileEdge")), 1.0)
	draw_line(r.position + Vector2(0.5, cut), r.position + Vector2(0.5, TILE), tint.call(palette.c("tileEdge")), 1.0)
	var hx := _hex() if _rng.randf() < 0.5 or reduced else "%02X" % ((i * 37 + 11) & 255)
	var w := _mono.get_string_size(hx, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(_mono, r.position + Vector2((TILE - w) * 0.5, TILE * 0.5 + 3), hx, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		tint.call(palette.c("cipher")))


## CSS filter: hue-rotate(deg) saturate(s), as the denial kick does to the board.
static func css_filter(c: Color, deg: float, sat: float) -> Color:
	var a := cos(deg_to_rad(deg))
	var b := sin(deg_to_rad(deg))
	var r := (0.213 + a * 0.787 - b * 0.213) * c.r + (0.715 - a * 0.715 - b * 0.715) * c.g + (0.072 - a * 0.072 + b * 0.928) * c.b
	var g := (0.213 - a * 0.213 + b * 0.143) * c.r + (0.715 + a * 0.285 + b * 0.140) * c.g + (0.072 - a * 0.072 - b * 0.283) * c.b
	var bl := (0.213 - a * 0.213 - b * 0.787) * c.r + (0.715 - a * 0.715 + b * 0.715) * c.g + (0.072 + a * 0.928 + b * 0.072) * c.b
	var r2 := (0.213 + 0.787 * sat) * r + (0.715 - 0.715 * sat) * g + (0.072 - 0.072 * sat) * bl
	var g2 := (0.213 - 0.213 * sat) * r + (0.715 + 0.285 * sat) * g + (0.072 - 0.072 * sat) * bl
	var b2 := (0.213 - 0.213 * sat) * r + (0.715 - 0.715 * sat) * g + (0.072 + 0.928 * sat) * bl
	return Color(clampf(r2, 0.0, 1.0), clampf(g2, 0.0, 1.0), clampf(b2, 0.0, 1.0), c.a)


## The flag from design/shared/board.js (24-unit viewBox) at 55% of the tile.
func _draw_flag(r: Rect2, col: Color) -> void:
	var s := TILE * 0.55 / 24.0
	var o := r.position + Vector2(TILE, TILE) * 0.225
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	draw_line(p.call(6.5, 2.5), p.call(6.5, 21.5), col, 2.2 * s)
	draw_colored_polygon(PackedVector2Array([p.call(8, 3.5), p.call(19, 3.5), p.call(15.8, 8.1), p.call(19, 12.7), p.call(8, 12.7)]), col)
	draw_line(p.call(3.5, 21.5), p.call(10.5, 21.5), col, 2.2 * s)


func _draw_denied(c: Vector2, s: float, a: float) -> void:
	var text := "ACCESS DENIED"
	var tw := _ui.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var w := (tw + 52.0) * s
	var h := (40.0 + 20.0) * s
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	var cut := 12.0 * s
	draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(w, 0), r.end - Vector2(0, cut), r.end - Vector2(cut, 0),
		r.position + Vector2(0, h)]), Color(palette.c("danger"), a))
	draw_set_transform(size * 0.5 + c * LOADER_SCALE, 0.0, Vector2(LOADER_SCALE, LOADER_SCALE) * s)
	draw_string(_ui, Vector2(-tw * 0.5, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(palette.c("void"), a))
	draw_set_transform(size * 0.5, 0.0, Vector2(LOADER_SCALE, LOADER_SCALE))


func _draw_dump(at: Vector2, k: int, grow: float) -> void:
	var w := 230.0
	var h := 8.0 + 16.0 + 108.0 + 10.0
	var r := Rect2(at.x, at.y + h * (1.0 - grow) * 0.5, w, h * grow)
	var cut := minf(10.0, r.size.y * 0.5)
	var poly := PackedVector2Array([r.position + Vector2(cut, 0), r.position + Vector2(w, 0), r.end - Vector2(0, cut),
		r.end - Vector2(cut, 0), r.position + Vector2(0, r.size.y), r.position + Vector2(0, cut)])
	draw_colored_polygon(poly, Color(palette.c("void"), 0.7))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(palette.c("accent"), 0.4), 1.0)
	if grow < 1.0:
		return
	var title: String = DUMP_TITLES[k] + (plan.key.substr(0, 4) if k == 2 else "")
	draw_rect(Rect2(r.position + Vector2(cut, 0), Vector2(w - cut, 16)), Color(palette.c("accent"), 0.8))
	draw_rect(Rect2(r.position + Vector2(0, cut), Vector2(cut, 16 - cut)), Color(palette.c("accent"), 0.8))
	draw_string(_title_font, r.position + Vector2(10, 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, palette.c("void"))
	var y := r.position.y + 16.0 + 6.0 + 10.0
	for line in _dumps[k]:
		draw_string(_mono, Vector2(r.position.x + 10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(palette.c("accent"), 0.65))
		y += 15.5
