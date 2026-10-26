class_name Hud
extends Control
## The gameplay HUD from design/png/gameplay-signal.png, laid out at the
## 1920x1080 base size: wordmark + seed + links (top left), signal meter (top
## centre), score + next rival (top right), position / depth / density / time
## (bottom left), controls hints (bottom centre), minimap (bottom right).

const MARGIN := 28.0
const SEGMENTS := 40

var palette: Palette
var view: BoardView
var rivals: Array = []
var state := {}
var origin := Vector2i.ZERO
var started := false
var density_for := func(_depth: int) -> float: return 0.0
var lost_at := []   # clock_ms when each link was lost (index 0..2), for the shatter
var low_signal := false
## Ghost mode has no signal meter and doesn't race the rivals.
var mode: GameState.Mode = GameState.Mode.ARCADE

var _ui: Array[Font] = []     # Chakra Petch 400, 500, 600, 700
var _data: Array[Font] = []   # Martian Mono 300, 400, 600, 800
var _tl: CutPanel
var _sig: CutPanel
var _score: CutPanel
var _bl: CutPanel
var _hints: CutPanel
var _mm: CutPanel
var minimap: Minimap


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for w in [400, 500, 600, 700]:
		_ui.append(load("res://assets/fonts/ChakraPetch-%d.ttf" % w))
	for w in [300, 400, 600, 800]:
		_data.append(load("res://assets/fonts/MartianMono-%d.ttf" % w))
	_tl = _panel(Vector2(362, 106), _draw_tl)
	_sig = _panel(Vector2(620, 76), _draw_sig)
	_score = _panel(Vector2(300, 144), _draw_score)
	_bl = _panel(Vector2(232, 122), _draw_bl)
	_hints = _panel(Vector2(748, 46), _draw_hints)
	_mm = _panel(Vector2(284, 226), _draw_mm)
	minimap = Minimap.new()
	minimap.position = Vector2(12, 38)
	minimap.size = Vector2(260, 176)
	_mm.add_child(minimap)
	resized.connect(_layout)
	_layout()


func set_palette(p: Palette) -> void:
	palette = p
	for panel in [_tl, _sig, _score, _bl, _hints, _mm]:
		panel.palette = p
		panel.queue_redraw()
	minimap.palette = p
	minimap.repaint()


func _panel(sz: Vector2, drawer: Callable) -> CutPanel:
	var p := CutPanel.new()
	p.size = sz
	add_child(p)
	p.paint.connect(drawer.bind(p))
	return p


func _layout() -> void:
	var w := size.x
	var h := size.y
	_tl.position = Vector2(MARGIN, MARGIN)
	_sig.position = Vector2((w - _sig.size.x) * 0.5, MARGIN)
	_score.position = Vector2(w - MARGIN - _score.size.x, MARGIN)
	_bl.position = Vector2(MARGIN, h - MARGIN - _bl.size.y)
	_hints.position = Vector2((w - _hints.size.x) * 0.5, h - MARGIN - _hints.size.y)
	_mm.position = Vector2(w - MARGIN - _mm.size.x, h - MARGIN - _mm.size.y)


func refresh() -> void:
	for panel in [_tl, _sig, _score, _bl, _mm]:
		panel.queue_redraw()


func _process(_delta: float) -> void:
	if palette == null:
		return
	_sig.visible = mode != GameState.Mode.GHOST
	if mode == GameState.Mode.GHOST:
		low_signal = false
	# Signal pulses and link shatters animate every frame; the rest follows the view.
	refresh()
	_hints.queue_redraw()


# --- panels -------------------------------------------------------------------

func _lbl(ci: CanvasItem, pos: Vector2, text: String, color_role := "inkDim", size := 14, font := 1) -> void:
	ci.draw_string(_ui[font], pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, palette.c(color_role))


func _draw_tl(p: CutPanel) -> void:
	if palette == null:
		return
	HudText.draw_split_string(p, _ui[3], Vector2(22, 40), "CYBERSWEEPER", 22, palette.c("ink"),
		palette.c("accent"), palette.c("accent2"))
	var seed_text := "seed " + CsHash.seed_text(int(state.get("seed", 0)))
	p.draw_string(_data[1], Vector2(222, 39), seed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, palette.c("inkDim"))
	_lbl(p, Vector2(22, 81), "links")
	var links := int(state.get("links", 3))
	for i in 3:
		_draw_link(p, Vector2(91 + i * 36.5, 75), i < links, i)


func _draw_link(ci: CanvasItem, c: Vector2, alive: bool, index: int) -> void:
	var r := 13.0 * 1.4142   # half-diagonal of a 26 px square rotated 45 degrees
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var closed := pts.duplicate()
	closed.append(pts[0])
	var acc := palette.c("accent")
	if alive:
		for g in [10.0, 6.0, 3.0]:
			var gc := acc
			gc.a = 0.6 * 0.18
			ci.draw_polyline(closed, gc, g, true)
		var fill := acc
		fill.a = 0.35
		ci.draw_colored_polygon(pts, fill)
		ci.draw_polyline(closed, acc, 2.0, true)
		return
	var dan := palette.c("danger")
	var lost: float = lost_at[index] if index < lost_at.size() else -1e9
	var since: float = view.clock_ms - lost
	if since < 420.0:
		# shatter: the two halves fly apart and fade, then the lost state shows
		var t: float = since / 420.0
		var spread: float = 10.0 * t
		var halves := [[pts[0], pts[1], pts[2]], [pts[2], pts[3], pts[0]]]
		for k in 2:
			var dir: Vector2 = Vector2(1, -1).normalized() * spread * (1.0 if k == 0 else -1.0)
			var hp := PackedVector2Array()
			for v in halves[k]:
				hp.append(v + dir)
			var hc := acc.lerp(dan, t)
			hc.a = 1.0 - t
			ci.draw_colored_polygon(hp, Color(hc, hc.a * 0.4))
			hp.append(hp[0])
			ci.draw_polyline(hp, hc, 2.0, true)
		return
	var lc := dan
	lc.a = 0.8
	ci.draw_polyline(closed, lc, 2.0, true)
	# the design's slash: a 2 px danger line through the diamond, past its tips
	ci.draw_line(c + Vector2(-0.62, 0.62) * (r + 4.0), c + Vector2(0.62, -0.62) * (r + 4.0), lc, 2.0, true)


func _draw_sig(p: CutPanel) -> void:
	if palette == null:
		return
	var f := float(state.get("signal", 1.0))
	var role := "accent"
	if f < 0.10:
		role = "danger"
	elif f < 0.30:
		role = "warn"
	low_signal = f < 0.30 and bool(state.get("started", false)) and not bool(state.get("over", false))
	var mc := palette.c(role)
	var pulse := 1.0
	if low_signal:
		var hz := 2.0 if f < 0.10 else 1.0
		pulse = 0.65 + 0.35 * (0.5 + 0.5 * cos(view.clock_ms / 1000.0 * TAU * hz))
	_lbl(p, Vector2(20, 30), "signal")
	var pct := "%d%%" % roundi(f * 100.0)
	var pw := HudText.width(_data[2], pct, 15)
	p.draw_string(_data[2], Vector2(p.size.x - 20 - pw, 30), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, mc)
	var x0 := 20.0
	var y0 := 42.0
	var total := p.size.x - 40.0
	var seg := (total - 3.0 * (SEGMENTS - 1)) / SEGMENTS
	var on := roundi(f * SEGMENTS)
	for i in SEGMENTS:
		var x := x0 + i * (seg + 3.0)
		var poly := PackedVector2Array([Vector2(x + seg * 0.3, y0), Vector2(x + seg, y0),
			Vector2(x + seg * 0.7, y0 + 18), Vector2(x, y0 + 18)])
		if i < on:
			var g := mc
			g.a = 0.25 * pulse
			var gp := PackedVector2Array()
			for v in poly:
				gp.append(v + (v - Vector2(x + seg * 0.5, y0 + 9)) * 0.35)
			p.draw_colored_polygon(gp, g)
			var cc := mc
			cc.a = pulse
			p.draw_colored_polygon(poly, cc)
		else:
			var off := palette.c("accent")
			off.a = 0.14
			p.draw_colored_polygon(poly, off)


func _draw_score(p: CutPanel) -> void:
	if palette == null:
		return
	var right := p.size.x - 24.0
	var lw := HudText.width(_ui[1], "score", 14)
	_lbl(p, Vector2(right - lw, 30), "score")
	var score := int(state.get("score", 0))
	var s := HudText.thousands(score)
	var sw := HudText.width(_data[3], s, 56)
	HudText.draw_glow_string(p, _data[3], Vector2(right - sw, 92), s, 56, palette.c("ink"), 18.0, 0.0)
	_glow_behind(p, _data[3], Vector2(right - sw, 92), s, 56, palette.c("accent"))
	if mode == GameState.Mode.GHOST:
		var g := "ghost run, no rivals"
		_lbl(p, Vector2(right - HudText.width(_ui[1], g, 14), 116), g)
		return
	var next := _next_rival(score)
	var name: String = next[0]
	var target: int = next[1]
	var num := HudText.thousands(target)
	var nw := HudText.width(_data[1], num, 14)
	var bw := HudText.width(_ui[2], name, 14)
	var tail := right - nw
	p.draw_string(_data[1], Vector2(tail, 116), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, palette.c("inkDim"))
	p.draw_string(_ui[2], Vector2(tail - 6 - bw, 116), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, palette.c("ink"))
	var lead := "next rival" if score < target else "top rival"
	var ldw := HudText.width(_ui[1], lead, 14)
	_lbl(p, Vector2(tail - 6 - bw - 6 - ldw, 116), lead)
	var bar := Rect2(Vector2(24, 126), Vector2(p.size.x - 48, 4))
	var a2 := palette.c("accent2")
	p.draw_rect(bar, Color(a2, 0.18))
	var frac := clampf(float(score) / maxf(1.0, float(target)), 0.0, 1.0)
	var fill := Rect2(bar.position, Vector2(bar.size.x * frac, 4))
	p.draw_rect(fill.grow(2.0), Color(a2, 0.25))
	p.draw_rect(fill, a2)


## The score's 18 px accent glow at 35%, drawn under the ink.
func _glow_behind(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	for i in range(4, 0, -1):
		var g := color
		g.a = 0.35 * 0.22 * (1.0 - float(i - 1) / 4.0)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(18.0 * i / 4.0), g)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, palette.c("ink"))


func _next_rival(score: int) -> Array:
	for r in rivals:
		if int(r.score) > score:
			return [r.name, int(r.score)]
	var top: Dictionary = rivals.back() if not rivals.is_empty() else {"name": "", "score": 0}
	return [top.name, int(top.score)]


func _draw_bl(p: CutPanel) -> void:
	if palette == null:
		return
	var rel := view.cam.center - (Vector2(origin) + Vector2(0.5, 0.5))
	var x := roundi(rel.x)
	var y := -roundi(rel.y)
	var depth := int(rel.length())
	_lbl(p, Vector2(22, 32), "position")
	_lbl(p, Vector2(150, 32), "depth")
	var v := palette.c("ink")
	p.draw_string(_data[2], Vector2(22, 56), "x %d  y %d" % [x, y], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, v)
	p.draw_string(_data[2], Vector2(150, 56), str(depth), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, v)
	_lbl(p, Vector2(22, 84), "mine density")
	_lbl(p, Vector2(150, 84), "time")
	p.draw_string(_data[2], Vector2(22, 108), "%.1f%%" % (density_for.call(depth) * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, v)
	var secs := int(state.get("elapsed_ms", 0)) / 1000
	p.draw_string(_data[2], Vector2(150, 108), "%02d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, v)


func _draw_hints(p: CutPanel) -> void:
	if palette == null:
		return
	var items := [["LMB", "reveal"], ["RMB", "flag"], ["LMB", "on a number to chord"], ["WASD", "or drag to pan"],
		["wheel", "zoom"]]
	if mode == GameState.Mode.GHOST:
		items.append(["Ctrl+E", "end run"])
	var x := 22.0
	var dim := palette.c("inkDim")
	for it in items:
		var kw := HudText.width(_data[2], it[0], 12)
		var box := Rect2(Vector2(x, 13), Vector2(kw + 14, 20))
		var kc := dim
		kc.a = 0.75
		p.draw_rect(box, kc, false, 1.0)
		p.draw_string(_data[2], Vector2(x + 7, 28), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, kc)
		x += box.size.x + 8
		p.draw_string(_ui[1], Vector2(x, 29), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, dim)
		x += HudText.width(_ui[1], it[1], 15) + 26
	if absf(x - 26 + 22 - p.size.x) > 1.0:
		p.size.x = x - 26 + 22
		_layout()


func _draw_mm(p: CutPanel) -> void:
	if palette == null:
		return
	_lbl(p, Vector2(12, 24), "explored")
	var t := HudText.thousands(int(state.get("tiles", 0)))
	var tw := HudText.width(_data[1], t, 14)
	p.draw_string(_data[1], Vector2(p.size.x - 12 - tw, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, palette.c("inkDim"))
