class_name Hud
extends Control
## The player's street cyberdeck over the corp's board (design/png/
## gameplay-signal.png, design/MOTION.md "HUD frames"), laid out at the
## 1920x1080 base size. Jagged panels:
## - wordmark and links as memory blocks (top left);
## - the signal as a health bar (top centre);
## - score and next rival (top right);
## - position, depth, density and time (bottom left);
## - controls (bottom centre) and the lattice map (bottom right);
## plus micro-text, slash hatching and a ribbon cable down the left edge.
## Under strain it corrupts its own labels, jitters and splits (strain 2),
## and shows the ghost outlines of its frames.

const MARGIN := 30.0
const SEGMENTS := 40
const SLANT := 9.0
const SHATTER_SHARDS := 5

var palette: Palette
var view: BoardView
var rivals: Array = []
var state := {}
var origin := Vector2i.ZERO
var started := false
var density_for := func(_depth: int) -> float: return 0.0
## Shown signal (percent) drained per second right now, for the DRAIN readout.
var drain_for := func(_state: Dictionary) -> float: return 0.0
var lost_at := []   # clock_ms when each link was lost (index 0..2), for the shatter
var low_signal := false
var low_fraction := 0.30
var critical_fraction := 0.10
## Ghost mode has no signal meter and doesn't race the rivals.
var mode: GameState.Mode = GameState.Mode.ARCADE
## 0..2, from Strain.level (set by GameView).
var strain := 0
var reduced_motion := false

var _ui: Array[Font] = []     # Chakra Petch 400, 500, 600, 700
var _data: Array[Font] = []   # Martian Mono 300, 400, 600, 800
var _jp: Font
var _tag_font: FontVariation
var _micro_font: FontVariation
var _lbl_wide: FontVariation
var _word_font: FontVariation
var _tl: JagPanel
var _sig: JagPanel
var _score: JagPanel
var _bl: JagPanel
var _hints: JagPanel
var _mm: JagPanel
var _deco: Control
var minimap: Minimap

## Strain corruption: label id -> [corrupted text, until clock_ms].
var _corrupt := {}
var _seen := {}          # label id -> its text, as last drawn
var _next_corrupt := 0.0
var _strain_was := 0
var _pkt := 10728
var _next_pkt := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 7
	for w in [400, 500, 600, 700]:
		_ui.append(load("res://assets/fonts/ChakraPetch-%d.ttf" % w))
	for w in [300, 400, 600, 800]:
		_data.append(load("res://assets/fonts/MartianMono-%d.ttf" % w))
	_jp = load("res://assets/fonts/NotoSansJP-Bold-subset.otf")
	_tag_font = spaced(_ui[3], 2)
	_micro_font = spaced(_data[0], 1)
	_lbl_wide = spaced(_ui[1], 1)
	_word_font = spaced(_ui[3], 1)
	_deco = Control.new()
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_deco)
	_deco.draw.connect(_draw_deco)
	_tl = _panel(Vector2(230, 116), Jag.SEED_TL, _draw_tl)
	_sig = _panel(Vector2(620, 116), Jag.SEED_SIG, _draw_sig)
	_score = _panel(Vector2(330, 170), Jag.SEED_SCORE, _draw_score)
	_bl = _panel(Vector2(226, 132), Jag.SEED_BL, _draw_bl)
	_hints = _panel(Vector2(800, 50), Jag.SEED_HINTS, _draw_hints)
	_mm = _panel(Vector2(284, 220), Jag.SEED_MM, _draw_mm)
	minimap = Minimap.new()
	minimap.position = Vector2(12, 30)
	minimap.size = Vector2(260, 176)
	_mm.add_child(minimap)
	resized.connect(_layout)
	_layout()


## A font with extra px between glyphs (CSS letter-spacing).
static func spaced(f: Font, px: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = px
	return v


func set_palette(p: Palette) -> void:
	palette = p
	for panel in _panels():
		panel.palette = p
		panel.queue_redraw()
	minimap.palette = p
	minimap.repaint()


func _panels() -> Array[JagPanel]:
	return [_tl, _sig, _score, _bl, _hints, _mm]


func _panel(sz: Vector2, seed: int, drawer: Callable) -> JagPanel:
	var p := JagPanel.new()
	p.seed = seed
	p.size = sz
	add_child(p)
	p.paint.connect(drawer.bind(p))
	return p


func _layout() -> void:
	var w := size.x
	var h := size.y
	_tl.position = Vector2(MARGIN, MARGIN)
	_sig.position = Vector2(roundf((w - _sig.size.x) * 0.5), MARGIN)
	_score.position = Vector2(w - MARGIN - _score.size.x, MARGIN)
	_bl.position = Vector2(MARGIN, h - MARGIN - _bl.size.y)
	_hints.position = Vector2(roundf((w - _hints.size.x) * 0.5), h - MARGIN - _hints.size.y)
	_mm.position = Vector2(w - MARGIN - _mm.size.x, h - MARGIN - _mm.size.y)


func refresh() -> void:
	for panel in _panels():
		panel.queue_redraw()
	_deco.queue_redraw()


func _process(_delta: float) -> void:
	if palette == null or view == null:
		return
	_sig.visible = mode != GameState.Mode.GHOST
	if mode == GameState.Mode.GHOST:
		low_signal = false
	var now := view.clock_ms
	if now >= _next_pkt:
		_pkt += _rng.randi_range(1, 36)
		_next_pkt = now + Motion.PKT_EVERY_MS
	_corruption(now)
	var ghost := 0.0 if strain == 0 else (0.6 if strain == 1 else 1.0)
	for panel in _panels():
		panel.ghost = ghost
	refresh()


# --- strain corruption ----------------------------------------------------------

func _corruption(now: float) -> void:
	if strain != _strain_was:
		_strain_was = strain
		_next_corrupt = now + (Motion.CORRUPT_EVERY_MS[strain - 1] if strain > 0 else 0.0)
	for id in _corrupt.keys():
		if now >= _corrupt[id][1]:
			_corrupt.erase(id)
	if strain == 0 or reduced_motion or _seen.is_empty() or now < _next_corrupt:
		return
	var ids := _seen.keys().filter(func(k): return not _corrupt.has(k))
	if not ids.is_empty():
		var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
		_corrupt[id] = [Strain.corrupt(_seen[id], _rng), now + Motion.CORRUPT_FOR_MS[strain - 1]]
	_next_corrupt = now + Motion.CORRUPT_EVERY_MS[strain - 1]


## Labels the corruption may hit (never real numbers).
func corruptible() -> Array:
	return _seen.keys()


func is_corrupted(id: String) -> bool:
	return _corrupt.has(id)


## Draws a label, tag or micro-text; under strain it may come out corrupted
## (in danger). Returns its width.
func _txt(ci: CanvasItem, id: String, font: Font, pos: Vector2, text: String, size: int, color: Color,
		right := false) -> float:
	_seen[id] = text
	var shown := text
	if _corrupt.has(id):
		shown = _corrupt[id][0]
		color = palette.c("danger")
	var w := _glitch_width(font, shown, size)
	var p := pos - Vector2(w if right else 0.0, 0.0)
	HudText.draw_glitch_string(ci, font, p, shown, size, color)
	return w


func _glitch_width(font: Font, text: String, size: int) -> float:
	var adv := font.get_char_size("0".unicode_at(0), size).x
	var w := 0.0
	for ch in text:
		w += adv if HudText.SHAPES.contains(ch) else font.get_char_size(ch.unicode_at(0), size).x
	return w


## A real number. At strain 2 it gets the red/cyan split.
func _num(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	if strain >= 2 and not reduced_motion:
		ci.draw_string(font, pos + Vector2(-2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(palette.c("danger"), 0.8))
		ci.draw_string(font, pos + Vector2(2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(palette.c("accent"), 0.6))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A filled tag with the lower-right corner cut (cs.css .tagl). Returns its width.
func _tag(ci: CanvasItem, id: String, pos: Vector2, text: String, color: Color, right := false) -> float:
	var up := text.to_upper()
	var shown: String = _corrupt[id][0] if _corrupt.has(id) else up
	_seen[id] = up
	var tw := _glitch_width(_tag_font, shown, 12)
	var w := tw + 11.0 + 14.0
	var h := 21.0
	var x := pos.x - (w if right else 0.0)
	var cut := 7.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x, pos.y), Vector2(x + w, pos.y), Vector2(x + w, pos.y + h - cut),
		Vector2(x + w - cut, pos.y + h), Vector2(x, pos.y + h)]), color)
	var ink := palette.c("danger") if _corrupt.has(id) and color != palette.c("danger") else palette.c("void")
	HudText.draw_glitch_string(ci, _tag_font, Vector2(x + 11.0, pos.y + 15.5), shown, 12, ink)
	return w


## Slash hatching (cs.css .slashes): -60 degree strokes, 1.5 px every 6 px, 55%.
static func draw_slashes(ci: CanvasItem, pos: Vector2, w: float, color: Color) -> void:
	var c := Color(color, color.a * 0.55)
	var h := 8.0
	var dx := h / tan(deg_to_rad(60.0))
	var x := 0.0
	while x < w:
		var a := Vector2(pos.x + x, pos.y + h)
		var b := Vector2(pos.x + minf(x + dx, w), pos.y + (0.0 if x + dx <= w else h - (w - x) / dx * h))
		ci.draw_line(a, b, c, 1.5)
		x += 6.0


func _micro(ci: CanvasItem, id: String, pos: Vector2, text: String, right := false) -> void:
	var c := palette.c("inkDim")
	c.a = 0.75
	_txt(ci, id, _micro_font, pos, text, 9, c, right)


# --- panels -------------------------------------------------------------------

func _draw_tl(p: JagPanel) -> void:
	if palette == null:
		return
	var wpos := Vector2(24, 42)
	if strain >= 2 and not reduced_motion:
		p.draw_string(_word_font, wpos + Vector2(-2, 0), "CYBERSWEEPER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(palette.c("danger"), 0.8))
		p.draw_string(_word_font, wpos + Vector2(2, 0), "CYBERSWEEPER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(palette.c("accent"), 0.6))
	HudText.draw_split_string(p, _word_font, wpos, "CYBERSWEEPER", 22, palette.c("ink"),
		palette.c("accent"), palette.c("accent2"))
	var tw := _tag(p, "links", Vector2(24, 66), "links", palette.c("accent"))
	var links := int(state.get("links", 3))
	var x := 24.0 + tw + 16.0
	for i in 3:
		_draw_link(p, Vector2(x + i * 21.0, 63), i < links, i)
	_num(p, _data[1], Vector2(x + 3 * 21.0 - 5.0 + 16.0, 81), "%d/3" % links, 13, palette.c("inkDim"))
	_micro(p, "sn", Vector2(24, 101), "SN %s  REV %s" % [CsHash.seed_text(int(state.get("seed", 0))), CsVersion.GAME])


## One link as a memory block (16 x 26, lower-right corner cut 6 px). A lost
## one shatters into 5 shards, then sits hatched in danger with an outline.
func _draw_link(ci: CanvasItem, at: Vector2, alive: bool, index: int) -> void:
	var w := 16.0
	var h := 26.0
	var cut := 6.0
	var poly := PackedVector2Array([at, at + Vector2(w, 0), at + Vector2(w, h - cut), at + Vector2(w - cut, h), at + Vector2(0, h)])
	var acc := palette.c("accent")
	if alive:
		for g in [6.0, 3.0]:
			var gp := PackedVector2Array()
			for v in poly:
				gp.append(at + Vector2(w, h) * 0.5 + (v - at - Vector2(w, h) * 0.5) * (1.0 + g / 13.0))
			ci.draw_colored_polygon(gp, Color(acc, 0.14))
		ci.draw_colored_polygon(poly, acc)
		return
	var dan := palette.c("danger")
	var lost: float = lost_at[index] if index < lost_at.size() else -1e9
	var since: float = view.clock_ms - lost
	if since >= 0.0 and since < Motion.SHATTER_MS and not reduced_motion:
		_draw_shards(ci, at + Vector2(w, h) * 0.5, since / Motion.SHATTER_MS, index, lost, acc)
	var hatch := Color(dan, 0.7 * 0.9)
	var y := -w
	while y < h:
		var line := PackedVector2Array([at + Vector2(0, y + w), at + Vector2(w, y)])
		for seg in Geometry2D.clip_polyline_with_polygon(line, poly):
			ci.draw_polyline(seg, hatch, 2.0)
		y += 5.0
	var outline := poly.duplicate()
	outline.append(poly[0])
	ci.draw_polyline(outline, Color(dan, 0.9), 1.0)


func _draw_shards(ci: CanvasItem, c: Vector2, t: float, index: int, seed_ms: float, color: Color) -> void:
	var e := Motion.bezier(0.2, 0.8, 0.3, 1.0, t)
	var r := RandomNumberGenerator.new()
	r.seed = hash([index, int(seed_ms)])
	for i in SHATTER_SHARDS:
		var a := float(i) / SHATTER_SHARDS * TAU + r.randf_range(-0.4, 0.4)
		var spin := deg_to_rad(r.randf_range(-200.0, 200.0)) * e
		var tri := [Vector2(r.randf_range(0, 0.4), 0), Vector2(1, r.randf_range(0.1, 0.6)), Vector2(r.randf_range(0.2, 0.8), 1)]
		var at := c + Vector2(cos(a), sin(a)) * Motion.SHATTER_PX * e
		var pts := PackedVector2Array()
		for v in tri:
			pts.append(at + ((v - Vector2(0.5, 0.5)) * 12.0).rotated(spin))
		ci.draw_colored_polygon(pts, Color(color, 1.0 - e))


func _signal_role(f: float) -> String:
	if f < critical_fraction:
		return "danger"
	if f < low_fraction:
		return "warn"
	return "accent"


func _draw_sig(p: JagPanel) -> void:
	if palette == null:
		return
	# What the player sees (the false scale), not the real fraction.
	var f := float(state.get("signal_shown", state.get("signal", 1.0)))
	var role := _signal_role(f)
	low_signal = f < low_fraction and bool(state.get("started", false)) and not bool(state.get("over", false))
	var mc := palette.c(role)
	# The tag says it in words too, so the state never relies on color alone.
	var tag := "signal critical" if role == "danger" else ("signal low" if role == "warn" else "signal")
	var tw := _tag(p, "signal", Vector2(20, 16), tag, mc)
	draw_slashes(p, Vector2(20 + tw + 14, 23), 140, palette.c("accent"))
	var drain := "DRAIN %.1f/s" % float(drain_for.call(state))
	_txt(p, "drain", _lbl_wide, Vector2(p.size.x - 26, 31), drain, 12, palette.c("inkDim"), true)
	var pct := str(roundi(f * 100.0))
	var big := _data[3]
	var glow := Color(mc, 0.5)
	for i in range(4, 0, -1):
		p.draw_string_outline(big, Vector2(20, 76), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, int(12.0 * i / 4.0),
			Color(glow, glow.a * 0.22 * (1.0 - float(i - 1) / 4.0)))
	_num(p, big, Vector2(20, 76), pct, 34, mc)
	var pw := HudText.width(big, pct, 34)
	p.draw_string(_data[2], Vector2(20 + pw + 2, 76), "%", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, mc)
	# Health bar: slanted, the empty part hatched, the fill solid.
	var bx := 141.0
	var bw := p.size.x - 20.0 - 6.0 - bx
	var by := 51.0
	var bh := 14.0
	var bar := PackedVector2Array([Vector2(bx + SLANT, by), Vector2(bx + bw, by), Vector2(bx + bw - SLANT, by + bh), Vector2(bx, by + bh)])
	var hatch := Color(mc, 0.3)
	var dx := bh / tan(deg_to_rad(55.0))
	var x := bx - dx
	while x < bx + bw:
		var line := PackedVector2Array([Vector2(x, by + bh), Vector2(x + dx, by)])
		for seg in Geometry2D.clip_polyline_with_polygon(line, bar):
			p.draw_polyline(seg, hatch, 1.5)
		x += 6.0
	var fw := bw * clampf(f, 0.0, 1.0)
	if fw > 0.5:
		var fill := Geometry2D.intersect_polygons(bar, PackedVector2Array([Vector2(bx, by), Vector2(bx + fw, by),
			Vector2(bx + fw - SLANT, by + bh), Vector2(bx - SLANT, by + bh)]))
		for poly in fill:
			p.draw_colored_polygon(poly, mc)
	# 40 fine ticks under it.
	var my := 72.0
	var seg := (bw - 2.0 * (SEGMENTS - 1)) / SEGMENTS
	var on := roundi(f * SEGMENTS)
	for i in SEGMENTS:
		var sx := bx + i * (seg + 2.0)
		var cell := PackedVector2Array([Vector2(sx + seg * 0.3, my), Vector2(sx + seg, my), Vector2(sx + seg * 0.7, my + 5), Vector2(sx, my + 5)])
		p.draw_colored_polygon(cell, mc if i < on else Color(palette.c("accent"), 0.14))
	_micro(p, "ch", Vector2(20, 101), "CH 07  PROXY 7/7  0 = LINK LOSS")
	_micro(p, "pkt", Vector2(p.size.x - 26, 101), "PKT %06X" % (_pkt & 0xFFFFFF), true)


func _draw_score(p: JagPanel) -> void:
	if palette == null:
		return
	var right := p.size.x - 24.0
	_tag(p, "score", Vector2(right, 18), "score", palette.c("accent2"), true)
	var score := int(state.get("score", 0))
	var s := HudText.thousands(score)
	var sw := HudText.width(_data[3], s, 56)
	_glow_behind(p, _data[3], Vector2(right - sw, 100), s, 56, palette.c("accent"))
	_num(p, _data[3], Vector2(right - sw, 100), s, 56, palette.c("ink"))
	_barcode(p, Vector2(30, p.size.y - 12 - 14))
	if mode == GameState.Mode.GHOST:
		_txt(p, "ghost", _ui[1], Vector2(right, 126), "ghost run, no rivals", 14, palette.c("inkDim"), true)
		return
	var next := _next_rival(score)
	var name: String = next[0]
	var target: int = next[1]
	var num := HudText.thousands(target)
	var nw := HudText.width(_data[1], num, 14)
	var bw := HudText.width(_ui[2], name, 14)
	var tail := right - nw
	_num(p, _data[1], Vector2(tail, 126), num, 14, palette.c("inkDim"))
	p.draw_string(_ui[2], Vector2(tail - 6 - bw, 126), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, palette.c("ink"))
	var lead := "next rival" if score < target else "top rival"
	_txt(p, "rival", _ui[1], Vector2(tail - 6 - bw - 6, 126), lead, 14, palette.c("inkDim"), true)
	var bar := Rect2(Vector2(24, 136), Vector2(right - 24, 4))
	var a2 := palette.c("accent2")
	p.draw_rect(bar, Color(a2, 0.18))
	var frac := clampf(float(score) / maxf(1.0, float(target)), 0.0, 1.0)
	var fill := Rect2(bar.position, Vector2(bar.size.x * frac, 4))
	p.draw_rect(fill.grow(2.0), Color(a2, 0.25))
	p.draw_rect(fill, a2)


func _barcode(ci: CanvasItem, at: Vector2) -> void:
	var c := Color(palette.c("inkDim"), 0.55)
	var x := at.x
	for i in 30:
		var w := 1 + int(JsPort.hash2(i, 7, 3) * 3.0)
		ci.draw_rect(Rect2(x, at.y, w, 14), c)
		x += w + 1


## The score's 18 px accent glow at 35%, drawn under the ink.
func _glow_behind(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	for i in range(4, 0, -1):
		var g := color
		g.a = 0.35 * 0.22 * (1.0 - float(i - 1) / 4.0)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(18.0 * i / 4.0), g)


func _next_rival(score: int) -> Array:
	for r in rivals:
		if int(r.score) > score:
			return [r.name, int(r.score)]
	var top: Dictionary = rivals.back() if not rivals.is_empty() else {"name": "", "score": 0}
	return [top.name, int(top.score)]


func _draw_bl(p: JagPanel) -> void:
	if palette == null:
		return
	var rel := view.cam.center - (Vector2(origin) + Vector2(0.5, 0.5))
	var x := roundi(rel.x)
	var y := -roundi(rel.y)
	var depth := int(rel.length())
	var dim := palette.c("inkDim")
	_txt(p, "position", _ui[1], Vector2(22, 29), "position", 14, dim)
	_txt(p, "depth", _ui[1], Vector2(150, 29), "depth", 14, dim)
	var v := palette.c("ink")
	_num(p, _data[2], Vector2(22, 54), "x %d  y %d" % [x, y], 16, v)
	_num(p, _data[2], Vector2(150, 54), str(depth), 16, v)
	_txt(p, "density", _ui[1], Vector2(22, 81), "mine density", 14, dim)
	_txt(p, "time", _ui[1], Vector2(150, 81), "time", 14, dim)
	_num(p, _data[2], Vector2(22, 106), "%.1f%%" % (density_for.call(depth) * 100.0), 16, v)
	var secs := int(state.get("elapsed_ms", 0)) / 1000
	_num(p, _data[2], Vector2(150, 106), "%02d:%02d" % [secs / 60, secs % 60], 16, v)
	_micro(p, "nav", Vector2(22, 120), "NAV // DEAD RECKONING")


func _draw_hints(p: JagPanel) -> void:
	if palette == null:
		return
	var items := [["LMB", "reveal"], ["RMB", "flag"], ["LMB", "on a number to chord"], ["WASD", "pan"], ["wheel", "zoom"]]
	if mode == GameState.Mode.GHOST:
		items.append(["Ctrl+E", "end run"])
	var widths := []
	var total := 0.0
	for it in items:
		var kw := HudText.width(_data[2], it[0], 12) + 14.0
		var lw := HudText.width(_ui[1], it[1], 15)
		widths.append([kw, lw])
		total += kw + 8.0 + lw
	total += 26.0 * (items.size() - 1)
	var x := roundf((p.size.x - total) * 0.5)
	var dim := palette.c("inkDim")
	for i in items.size():
		var it: Array = items[i]
		var box := Rect2(Vector2(x, 15), Vector2(widths[i][0], 20))
		var kc := Color(dim, 0.75)
		p.draw_rect(box, kc, false, 1.0)
		p.draw_string(_data[2], Vector2(x + 7, 30), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, kc)
		x += box.size.x + 8
		p.draw_string(_ui[1], Vector2(x, 31), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, dim)
		x += widths[i][1] + 26


func _draw_mm(p: JagPanel) -> void:
	if palette == null:
		return
	var dim := palette.c("inkDim")
	var jw := HudText.width(_jp, "鉄影", 10)
	p.draw_string(_jp, Vector2(12, 22), "鉄影", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	_micro_corp(p, "lattice", Vector2(12 + jw + 6, 21), "LATTICE MAP")
	var sw := HudText.width(_jp, "監視中", 10)
	p.draw_string(_jp, Vector2(p.size.x - 12 - 6 - sw, 22), "監視中", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	var frame := Rect2(minimap.position - Vector2(1, 1), minimap.size + Vector2(2, 2))
	p.draw_rect(frame, palette.c("tileEdge"), false, 1.0)


func _micro_corp(ci: CanvasItem, id: String, pos: Vector2, text: String) -> void:
	_txt(ci, id, _micro_font, pos, text, 9, palette.c("inkDim"))


# --- decoration outside the panels ---------------------------------------------------

func _draw_deco() -> void:
	if palette == null:
		return
	var acc := palette.c("accent")
	# Slash hatching beside the panels.
	draw_slashes(_deco, _tl.position + Vector2(_tl.size.x + 6, 22), 34, acc)
	draw_slashes(_deco, _score.position + Vector2(-42, _score.size.y - 30 - 8), 34, acc)
	draw_slashes(_deco, _mm.position + Vector2(-44, 40), 34, acc)
	# Ribbon cable down the left edge, between the top and bottom clusters.
	var top := _tl.position.y + _tl.size.y + 15.0
	var bottom := _bl.position.y - 19.0
	var cc := Color(acc, 0.35)
	if bottom - top > 200.0:
		# screens.js: M48 0 V60 L30 78 V660 L48 678 V740, then two more 4 px over.
		for k in 3:
			var x := -22.0 + 48.0 + 4.0 * k
			var d := 2.0 * k
			_deco.draw_polyline(PackedVector2Array([Vector2(x, top), Vector2(x, top + 60 - d), Vector2(x - 18, top + 78 - d),
				Vector2(x - 18, bottom - 80 - d), Vector2(x, bottom - 62 - d), Vector2(x, bottom)]), cc, 1.2)
	var tc := Color(acc, 0.8)
	_deco.draw_rect(Rect2(-22.0 + 46.0, top - 2.0, 12, 3), tc)
	_deco.draw_rect(Rect2(-22.0 + 46.0, bottom - 2.0, 12, 3), tc)
	if strain > 0 and reduced_motion:
		# Reduce motion: strain is a steady red edge plus this label.
		_tag(_deco, "strain-fixed", _tl.position + Vector2(0, _tl.size.y + 8), "strain", palette.c("danger"))


## Strength (0..1) of the red low-signal vignette for the signal shown: none
## above the low mark, growing to full at empty, pulsing at 1 Hz (steady with
## reduced motion). Strain takes over below the critical mark.
static func alarm_level(shown: float, clock_ms: float, low: float, critical: float, reduced: bool) -> float:
	if shown >= low:
		return 0.0
	var strength := clampf((low - shown) / low, 0.0, 1.0)
	var pulse := 0.5
	if not reduced:
		var hz := 2.0 if shown < critical else 1.0
		pulse = 0.5 + 0.5 * cos(clock_ms / 1000.0 * TAU * hz)
	return strength * (0.55 + 0.45 * pulse)
