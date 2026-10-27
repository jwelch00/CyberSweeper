class_name PalettesScreen
extends MenuScreen
## The palette picker (design/png/palettes.png): six cards, each drawn in its
## own palette. Unlocked ones show a live preview and Equip; locked ones show
## an encrypted preview with a lock, the unlock condition and progress.
## Plaintext carries a "Colorblind-safe" tag; new unlocks a "New" tag.

const CARD := Vector2(262, 690)
const TOP := 250.0
## The preview board (design/png/palettes.png): numbers, F flag, H hit, . open, - hidden.
const PREVIEW := ["-2F32-", "2333F3", "FF213F", "F31.22", "31..1H", "1...12"]

var profile: Profile
var settings: GameSettings
var _pals: Array[Palette] = []


func _ready() -> void:
	super()
	horizontal = true
	_pals = Palette.load_all()


func items() -> Array[String]:
	var out: Array[String] = []
	for p in _pals:
		out.append(p.id)
	return out


func item_rect(i: int) -> Rect2:
	var gap := 22.0
	var x0 := (size.x - (CARD.x * 6 + gap * 5)) * 0.5
	return Rect2(x0 + i * (CARD.x + gap), TOP, CARD.x, CARD.y)


func activate(i: int) -> void:
	selected = i
	if profile.is_unlocked(_pals[i].id):
		chosen.emit(_pals[i].id)
	queue_redraw()


func open_at_equipped() -> void:
	selected = maxi(0, items().find(settings.palette_id))


func _click_other(p: Vector2) -> void:
	if p.y < 220 and p.x > item_rect(5).end.x - 300:
		back.emit()


func _draw() -> void:
	if palette == null or profile == null:
		return
	backdrop()
	var left := item_rect(0).position.x
	Deck.heading(self, Vector2(left, 60), "Palettes",
		"%d of %d unlocked. A palette recolors the board, the HUD and every menu." % [profile.unlocked_count(), _pals.size()], palette)
	Deck.back_hint(self, Vector2(item_rect(5).end.x, 186), "Back to menu", palette)
	for i in _pals.size():
		_card(i)
	Deck.hints(self, Vector2(left, size.y - 64), [["←", "→", "choose"], ["Enter", "equip"]], palette)


func _card(i: int) -> void:
	var p := _pals[i]
	var r := item_rect(i)
	var open := profile.is_unlocked(p.id)
	var lit := i == selected
	var equipped := settings.palette_id == p.id
	# The card in its own palette.
	draw_rect(r, p.c("void"))
	draw_rect(r, Color(p.c("tileEdge"), 1.0), false, 1.0)
	if lit:
		for g in [8.0, 4.0]:
			draw_rect(r.grow(g * 0.5), Color(p.c("accent"), 0.12), false, g)
		draw_rect(r, p.c("accent"), false, 2.0)
	var pr := Rect2(r.position + Vector2(22, 22), Vector2(r.size.x - 44, 250))
	if open:
		_preview(pr, p)
	else:
		_encrypted(pr, p)
	var x := r.position.x + 22
	var y := r.position.y + 326
	draw_string(Deck.font("ui700"), Vector2(x, y), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, p.c("ink") if open else p.c("accent"))
	# Tags sit between the preview and the name, on the right.
	var tag_x := r.end.x - 22
	if p.accessibility:
		Deck.tag(self, Vector2(tag_x, r.position.y + 282), "Colorblind-safe", p.c("ink"), p.c("void"), 10, true)
	elif profile.unseen.has(p.id):
		Deck.tag(self, Vector2(tag_x, r.position.y + 282), "New", p.c("accent"), p.c("void"), 10, true)
	_wrap(p.vibe, Vector2(x, y + 34), r.size.x - 44, 15, p.c("inkDim") if open else p.c("accent").lerp(p.c("inkDim"), 0.5), "ui400", 5)
	# Swatch strip: void, the eight numbers, ink. Locked cards show two then hatching.
	var sw := Rect2(x, r.position.y + 486, r.size.x - 44, 22)
	var chips: Array[Color] = [p.c("void")]
	chips.append_array(p.numbers)
	chips.append(p.c("ink"))
	var cw := sw.size.x / chips.size()
	for k in chips.size():
		var cr := Rect2(sw.position.x + k * cw, sw.position.y, cw, sw.size.y)
		if open or k < 2:
			draw_rect(cr, chips[k])
	if not open:
		_hatch(Rect2(sw.position.x + 2 * cw, sw.position.y, sw.size.x - 2 * cw, sw.size.y), p.c("accent"))
	var bottom := r.end.y - 22
	var rule: Variant = Profile.unlock_rules().get(p.id, null)
	if open:
		var note := "Always unlocked"
		if p.id == "signal":
			note = "Default palette"
		elif rule != null:
			note = "Unlocked: " + String(rule.text).substr(0, 1).to_lower() + String(rule.text).substr(1)
		_wrap(note, Vector2(x, bottom - 76), r.size.x - 44, 15, p.c("inkDim"))
		var b := Rect2(x, bottom - 52, r.size.x - 44, 52)
		if equipped:
			draw_rect(b, p.c("accent"), false, 1.5)
			Deck.text(self, "ui600", Vector2(b.get_center().x - Deck.width("ui600", "Equipped", 20) * 0.5, b.position.y + 33),
				"Equipped", 20, p.c("accent"))
		else:
			Deck.button(self, b, "Equip " + p.name, "", p, true, false)
	else:
		var pg := profile.progress(p.id)
		_wrap(String(rule.text), Vector2(x, bottom - 92), r.size.x - 44, 17, p.c("ink"), "ui600")
		var have := mini(int(pg.have), int(pg.need))
		var left_text := "%s %s" % [pg.label, HudText.thousands(have)] if pg.label != "tiles" else HudText.thousands(have)
		Deck.text(self, "mono400", Vector2(x, bottom - 22), left_text, 14, p.c("inkDim"))
		Deck.text(self, "mono400", Vector2(r.end.x - 22, bottom - 22), HudText.thousands(int(pg.need)), 14, p.c("inkDim"), true)
		Deck.progress_bar(self, Rect2(x, bottom - 8, r.size.x - 44, 6), float(have) / maxf(1.0, float(pg.need)), p.c("accent"))


## A little revealed board in this palette.
func _preview(pr: Rect2, p: Palette) -> void:
	draw_rect(pr, p.c("floor"))
	var cs := 39.0
	var pitch := 41.0
	for y in PREVIEW.size():
		var row: String = PREVIEW[y]
		for x in row.length():
			var c := Rect2(pr.position + Vector2(x * pitch, y * pitch + 2), Vector2(cs, cs)).intersection(pr)
			if c.size.x <= 0:
				continue
			var ch := row[x]
			match ch:
				"-":
					draw_rect(c, p.c("tile"))
				"F":
					draw_rect(c, p.c("tile"))
					_flag(c.position + Vector2(cs, cs) * 0.5, p.c("warn"))
				"H":
					_hazard(c, p)
				".":
					pass
				_:
					var n := int(ch)
					var col := p.number(n)
					var w := Deck.width("mono800", ch, 22)
					if c.size.x >= w:
						var at := c.position + Vector2((cs - w) * 0.5, cs * 0.5 + 8)
						draw_string_outline(Deck.font("mono800"), at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 7, Color(col, 0.25))
						draw_string(Deck.font("mono800"), at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)


## Locked: hidden chips with cipher bytes, and a lock.
func _encrypted(pr: Rect2, p: Palette) -> void:
	draw_rect(pr, p.c("void"))
	var pitch := 41.0
	var bytes := ["A4", "EC", "8E", "AF", "5D", "96", "9F", "84", "D0", "7A", "32", "C1"]
	for y in 6:
		for x in 6:
			var c := Rect2(pr.position + Vector2(x * pitch, y * pitch + 2), Vector2(39, 39)).intersection(pr)
			if c.size.x <= 0:
				continue
			draw_rect(c, p.c("tile"))
			if x < 2 and c.size.x > 30:
				Deck.text(self, "mono400", c.position + Vector2(5, 13), bytes[(x + y * 2) % bytes.size()], 9, p.c("cipher"))
	var m := pr.get_center()
	var acc := p.c("accent")
	draw_arc(m + Vector2(0, -8), 12, PI, TAU, 16, acc, 4.0)
	draw_line(m + Vector2(-12, -8), m + Vector2(-12, 2), acc, 4.0)
	draw_line(m + Vector2(12, -8), m + Vector2(12, 2), acc, 4.0)
	var body := Rect2(m + Vector2(-18, 2), Vector2(36, 28))
	draw_rect(body, acc, false, 3.0)
	draw_rect(Rect2(m + Vector2(-2, 10), Vector2(4, 10)), acc)


func _flag(c: Vector2, col: Color) -> void:
	var s := 22.0 / 24.0
	var o := c - Vector2(12, 12) * s
	draw_line(o + Vector2(6.5, 2.5) * s, o + Vector2(6.5, 21.5) * s, col, 2.2 * s)
	draw_colored_polygon(PackedVector2Array([o + Vector2(8, 3.5) * s, o + Vector2(19, 3.5) * s, o + Vector2(15.8, 8.1) * s,
		o + Vector2(19, 12.7) * s, o + Vector2(8, 12.7) * s]), col)
	draw_line(o + Vector2(3.5, 21.5) * s, o + Vector2(10.5, 21.5) * s, col, 2.2 * s)


## The hazard tile: warn/void stripes with a danger mark in the middle.
func _hazard(c: Rect2, p: Palette) -> void:
	draw_rect(c, p.c("warn"))
	var poly := PackedVector2Array([c.position, c.position + Vector2(c.size.x, 0), c.end, c.position + Vector2(0, c.size.y)])
	var x := c.position.x - c.size.y
	while x < c.end.x:
		var line := PackedVector2Array([Vector2(x, c.end.y), Vector2(x + c.size.y, c.position.y)])
		for seg in Geometry2D.clip_polyline_with_polygon(line, poly):
			draw_polyline(seg, p.c("void"), 3.5)
		x += 10.0
	draw_rect(c, p.c("danger"), false, 1.0)
	draw_rect(Rect2(c.get_center() - Vector2(6, 6), Vector2(12, 12)), p.c("void"))
	draw_circle(c.get_center(), 4.0, p.c("danger"))


func _hatch(r: Rect2, col: Color) -> void:
	var poly := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var line := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y)])
		for seg in Geometry2D.clip_polyline_with_polygon(line, poly):
			draw_polyline(seg, Color(col, 0.35), 1.5)
		x += 6.0


## Word-wrapped text in a column, at most max_lines (the last one ends in …).
func _wrap(s: String, at: Vector2, w: float, size: int, col: Color, f := "ui400", max_lines := 99) -> void:
	var lines := Deck.wrap(f, s, size, w)
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		var last := lines[max_lines - 1]
		while last.length() > 1 and Deck.width(f, last + "…", size) > w:
			last = last.substr(0, last.length() - 1)
		lines[max_lines - 1] = last.strip_edges() + "…"
	var y := at.y
	for l in lines:
		Deck.text(self, f, Vector2(at.x, y), l, size, col)
		y += size * 1.4
