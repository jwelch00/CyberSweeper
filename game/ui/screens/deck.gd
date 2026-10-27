class_name Deck
extends RefCounted
## Drawing kit for the menu screens, in the street-deck language of the HUD
## (design/MOTION.md, "HUD frames"): jagged panels, cut-corner tags and
## buttons, headings in Chakra Petch, digits in Martian Mono, key hints.

static var _fonts := {}


static func font(key: String) -> Font:
	if _fonts.is_empty():
		for w in [400, 500, 600, 700]:
			_fonts["ui%d" % w] = load("res://assets/fonts/ChakraPetch-%d.ttf" % w)
		for w in [300, 400, 600, 800]:
			_fonts["mono%d" % w] = load("res://assets/fonts/MartianMono-%d.ttf" % w)
		_fonts["jp"] = load("res://assets/fonts/NotoSansJP-Bold-subset.otf")
		_fonts["tag"] = Hud.spaced(_fonts.ui700, 2)
		_fonts["micro"] = Hud.spaced(_fonts.mono300, 1)
	return _fonts[key]


static func width(f: String, text: String, size: int) -> float:
	return font(f).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func text(ci: CanvasItem, f: String, pos: Vector2, s: String, size: int, color: Color, right := false) -> float:
	var w := width(f, s, size)
	ci.draw_string(font(f), pos - Vector2(w if right else 0.0, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## A jagged panel: void fill and the HUD's line work, in the accent or
## another role (NULL//SAINT's card is danger), with the fill tinted toward it.
static func panel(ci: CanvasItem, r: Rect2, seed: int, pal: Palette, fill := 0.86, role := "accent", tint := 0.0) -> void:
	var sh := Jag.points(roundf(r.size.x), roundf(r.size.y), seed)
	var pts := PackedVector2Array()
	for p in sh.pts:
		pts.append(p + r.position)
	ci.draw_colored_polygon(pts, Color(pal.c("void").lerp(pal.c(role), tint), fill))
	ci.draw_set_transform(r.position)
	JagPanel.draw_frame(ci, sh, r.size, pal, 0.0, role)
	ci.draw_set_transform(Vector2.ZERO)


## Word-wraps s into lines no wider than w.
static func wrap(f: String, s: String, size: int, w: float) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in s.split(" "):
		var next := word if line == "" else line + " " + word
		if width(f, next, size) > w and line != "":
			lines.append(line)
			line = word
		else:
			line = next
	if line != "":
		lines.append(line)
	return lines


## A filled tag with the lower-right corner cut (cs.css .tagl). Returns its width.
static func tag(ci: CanvasItem, pos: Vector2, s: String, color: Color, ink: Color, size := 12, right := false) -> float:
	var up := s.to_upper()
	var w := width("tag", up, size) + 25.0
	var h := size * 1.25 + 6.0
	var x := pos.x - (w if right else 0.0)
	var cut := 7.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x, pos.y), Vector2(x + w, pos.y), Vector2(x + w, pos.y + h - cut),
		Vector2(x + w - cut, pos.y + h), Vector2(x, pos.y + h)]), color)
	ci.draw_string(font("tag"), Vector2(x + 11.0, pos.y + size + 3.5), up, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	return w


## A key cap like the HUD hints (Martian Mono 600 in a 1 px box).
## Martian Mono has no left/right arrows, so those are drawn as shapes.
static func key(ci: CanvasItem, pos: Vector2, k: String, color: Color, size := 12) -> float:
	var c := Color(color, 0.75)
	var arrow := k == "←" or k == "→"
	var w := (size + 6.0 if arrow else width("mono600", k, size)) + 14.0
	var r := Rect2(pos, Vector2(w, size + 10.0))
	ci.draw_rect(r, c, false, 1.0)
	if arrow:
		var m := r.get_center()
		var dx := size * 0.42 * (1.0 if k == "→" else -1.0)
		ci.draw_line(m - Vector2(dx, 0), m + Vector2(dx, 0), c, 1.5)
		ci.draw_polyline(PackedVector2Array([m + Vector2(dx * 0.2, -size * 0.32), m + Vector2(dx, 0), m + Vector2(dx * 0.2, size * 0.32)]), c, 1.5)
	else:
		ci.draw_string(font("mono600"), pos + Vector2(7, size + 4.0), k, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	return w


## A cut-corner button. primary = accent fill; otherwise a tile with an edge.
## The hovered/selected one gets an accent bar on its left edge as well as a
## lighter fill, so it never relies on color alone.
static func button(ci: CanvasItem, r: Rect2, label: String, k: String, pal: Palette, primary: bool, lit: bool,
		fill_role := "accent") -> void:
	var cut := 10.0
	var poly := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end - Vector2(0, cut),
		r.end - Vector2(cut, 0), r.position + Vector2(0, r.size.y)])
	var fill := pal.c(fill_role) if primary else pal.c("tile")
	if lit:
		fill = fill.lerp(pal.c("ink"), 0.15)
	ci.draw_colored_polygon(poly, fill)
	var ink := pal.c("void") if primary else pal.c("ink")
	if not primary:
		var o := poly.duplicate()
		o.append(poly[0])
		ci.draw_polyline(o, pal.c("tileEdge"), 1.0)
	if lit:
		ci.draw_rect(Rect2(r.position + Vector2(-8, 0), Vector2(4, r.size.y)), pal.c("accent"))
	var size := 20
	var lw := width("ui600", label, size)
	var kw := (width("mono600", k, 12) + 14.0 + 14.0) if k != "" else 0.0
	var x := r.position.x + (r.size.x - lw - kw) * 0.5
	ci.draw_string(font("ui600"), Vector2(x, r.position.y + r.size.y * 0.5 + 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	if k != "":
		key(ci, Vector2(x + lw + 14.0, r.position.y + r.size.y * 0.5 - 11), k, ink)


## Screen heading (Chakra Petch 700) and a dim line under it.
static func heading(ci: CanvasItem, pos: Vector2, title: String, sub: String, pal: Palette) -> void:
	ci.draw_string(font("ui700"), pos + Vector2(0, 64), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, pal.c("ink"))
	if sub != "":
		ci.draw_string(font("ui400"), pos + Vector2(0, 116), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, pal.c("inkDim"))


## "Esc  Back to menu" at the top right.
static func back_hint(ci: CanvasItem, right: Vector2, label: String, pal: Palette) -> Rect2:
	var dim := pal.c("inkDim")
	var lw := width("ui500", label, 18)
	var kw := width("mono600", "Esc", 12) + 14.0
	var x := right.x - lw - 10.0 - kw
	key(ci, Vector2(x, right.y - 16), "Esc", dim)
	ci.draw_string(font("ui500"), Vector2(right.x - lw, right.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, dim)
	return Rect2(x - 6, right.y - 24, right.x - x + 12, 34)


## Key hints along the bottom: [["←", "→", "choose"], ["Enter", "equip"]].
static func hints(ci: CanvasItem, pos: Vector2, items: Array, pal: Palette) -> void:
	var dim := pal.c("inkDim")
	var x := pos.x
	for it in items:
		for i in it.size() - 1:
			x += key(ci, Vector2(x, pos.y - 16), it[i], dim) + 6.0
		x += 4.0
		x += text(ci, "ui500", Vector2(x, pos.y), it.back(), 16, dim) + 32.0


## A dashed, hatched progress bar (the locked-palette cards).
static func progress_bar(ci: CanvasItem, r: Rect2, frac: float, color: Color) -> void:
	ci.draw_rect(r, Color(color, 0.18))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), color)


## "eleven minutes in", the way the game-over line says it.
static func minutes_words(ms: int) -> String:
	var m := ms / 60000
	if m < 1:
		return "under a minute in"
	var words := ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
		"thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
	var n: String = str(m) if m >= words.size() else words[m]
	return "%s minute%s in" % [n, "" if m == 1 else "s"]


static func clock(ms: int) -> String:
	var s := ms / 1000
	return "%d:%02d" % [s / 60, s % 60] if s < 3600 else "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
