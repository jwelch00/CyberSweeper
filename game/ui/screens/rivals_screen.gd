class_name RivalsScreen
extends MenuScreen
## Rivals and the local leaderboards. Arcade: the three rivals (name, label,
## score, bio; beaten ones struck through and marked "beaten", NULL//SAINT's
## bio changing for good once she's beaten) and a ladder of your best runs
## with the rivals slotted in. Ghost: your best Ghost runs, no rivals.

var profile: Profile
var tab := 0


func _ready() -> void:
	super()
	horizontal = true


func items() -> Array[String]:
	return ["arcade", "ghost"]


func item_rect(i: int) -> Rect2:
	var x := 120.0 + i * 170.0
	return Rect2(x, 250, 156, 44)


func activate(i: int) -> void:
	tab = i
	selected = i
	queue_redraw()


func move(d: int) -> void:
	super(d)
	tab = selected


func _click_other(p: Vector2) -> void:
	if p.y < 220 and p.x > size.x - 420:
		back.emit()


func _draw() -> void:
	if palette == null or profile == null:
		return
	backdrop()
	Deck.heading(self, Vector2(120, 60), "Rivals", "Your local leaderboard. Each rival's score is that bot's typical run.", palette)
	Deck.back_hint(self, Vector2(size.x - 120, 186), "Back to menu", palette)
	for i in 2:
		var r := item_rect(i)
		var on := i == tab
		var t: String = ["Arcade", "Ghost"][i]
		if on:
			draw_rect(r, palette.c("accent"))
		else:
			draw_rect(r, palette.c("tileEdge"), false, 1.0)
		Deck.text(self, "ui600", Vector2(r.get_center().x - Deck.width("ui600", t, 20) * 0.5, r.position.y + 30), t, 20,
			palette.c("void") if on else palette.c("inkDim"))
	if tab == 0:
		_arcade()
	else:
		_ghost()
	Deck.hints(self, Vector2(120, size.y - 64), [["←", "→", "switch board"], ["Esc", "back"]], palette)


func _arcade() -> void:
	# Left: the rivals with their bios.
	var y := 330.0
	var rv := Profile.rivals()
	for k in range(rv.size() - 1, -1, -1):
		var r: Dictionary = rv[k]
		var box := Rect2(120, y, 760, 150)
		Deck.panel(self, box, 211 + k * 5, palette, 0.8)
		var beaten := profile.beaten.has(r.id)
		var nx := box.position.x + 40
		var name_w := Deck.text(self, "ui700", Vector2(nx, box.position.y + 56), r.name, 32,
			palette.c("inkDim") if beaten else palette.c("ink"))
		if beaten:
			draw_line(Vector2(nx, box.position.y + 45), Vector2(nx + name_w, box.position.y + 45), palette.c("inkDim"), 2.0)
		Deck.text(self, "ui500", Vector2(nx + name_w + 14, box.position.y + 54), r.label, 16, palette.c("inkDim"))
		if beaten:
			Deck.tag(self, Vector2(nx + name_w + 24 + Deck.width("ui500", r.label, 16), box.position.y + 34), "beaten",
				palette.c("accent2"), palette.c("void"), 11)
		Deck.text(self, "mono800", Vector2(box.end.x - 40, box.position.y + 58), HudText.thousands(int(r.score)), 32,
			palette.c("ink"), true)
		_quote(Vector2(nx, box.position.y + 102), profile.bio(r), box.size.x - 80)
		y += 170
	# Right: the ladder.
	var lad := Rect2(940, 330, size.x - 940 - 120, 490)
	Deck.panel(self, lad, 233, palette, 0.8)
	Deck.text(self, "ui600", lad.position + Vector2(40, 52), "Ladder", 20, palette.c("ink"))
	Deck.text(self, "ui400", lad.position + Vector2(40 + Deck.width("ui600", "Ladder", 20) + 8, 52), "your best Arcade runs and the rivals",
		18, palette.c("inkDim"))
	var rows: Array = []
	for r in rv:
		rows.append({"name": r.name, "sub": r.label, "score": int(r.score), "rival": true, "beaten": profile.beaten.has(r.id)})
	for run in profile.arcade:
		rows.append({"name": "You", "sub": run.date, "score": int(run.score), "rival": false})
	rows.sort_custom(func(a, b): return a.score > b.score)
	var ry := lad.position.y + 80
	for i in mini(rows.size(), 8):
		_row(Rect2(lad.position.x + 40, ry, lad.size.x - 80, 46), i + 1, rows[i])
		ry += 50
	if profile.arcade.is_empty():
		Deck.text(self, "ui400", Vector2(lad.position.x + 40, ry + 30), "No Arcade runs yet. Jack in.", 18, palette.c("inkDim"))


func _ghost() -> void:
	var t := Rect2(120, 330, size.x - 240, 560)
	Deck.panel(self, t, 241, palette, 0.8)
	var x := t.position.x + 48
	Deck.text(self, "ui600", Vector2(x, t.position.y + 52), "Ghost runs", 20, palette.c("ink"))
	Deck.text(self, "ui400", Vector2(x + Deck.width("ui600", "Ghost runs", 20) + 8, t.position.y + 52),
		"no timer, no rivals; they don't count toward unlocks", 18, palette.c("inkDim"))
	var cols := [["#", 0.0], ["score", 80.0], ["tiles", 300.0], ["depth", 480.0], ["time", 640.0], ["date", 820.0]]
	for c in cols:
		Deck.text(self, "ui500", Vector2(x + c[1], t.position.y + 100), c[0], 15, palette.c("inkDim"))
	var y := t.position.y + 140
	for i in profile.ghost.size():
		var run: Dictionary = profile.ghost[i]
		if i % 2 == 0:
			draw_rect(Rect2(x - 16, y - 28, t.size.x - 64, 40), Color(palette.c("tile"), 0.5))
		var vals := [str(i + 1), HudText.thousands(int(run.score)), HudText.thousands(int(run.tiles)), str(run.depth),
			Deck.clock(int(run.ms)), run.date]
		for k in cols.size():
			Deck.text(self, "mono600" if k > 0 else "mono400", Vector2(x + cols[k][1], y), vals[k], 18,
				palette.c("ink") if k == 1 else palette.c("inkDim"))
		y += 40
	if profile.ghost.is_empty():
		Deck.text(self, "ui400", Vector2(x, y), "No Ghost runs yet. Pick Ghost after Jack in.", 18, palette.c("inkDim"))


func _row(r: Rect2, rank: int, row: Dictionary) -> void:
	var you: bool = not row.rival
	draw_rect(r, palette.c("accent").lerp(palette.c("tile"), 0.84) if you else Color(palette.c("tile"), 0.7))
	if you:
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), palette.c("accent"))
	Deck.text(self, "mono400", r.position + Vector2(18, 30), str(rank), 15, palette.c("inkDim"))
	var nc := palette.c("accent") if you else (palette.c("inkDim") if row.get("beaten", false) else palette.c("ink"))
	var nw := Deck.text(self, "ui600", r.position + Vector2(64, 30), row.name, 20, nc)
	if row.get("beaten", false):
		draw_line(r.position + Vector2(64, 22), r.position + Vector2(64 + nw, 22), palette.c("inkDim"), 2.0)
	var sub := String(row.sub) + (", beaten" if row.get("beaten", false) else "")
	Deck.text(self, "ui400", r.position + Vector2(64 + nw + 10, 30), sub, 14, palette.c("inkDim"))
	Deck.text(self, "mono600", Vector2(r.end.x - 18, r.position.y + 31), HudText.thousands(int(row.score)), 20,
		palette.c("accent") if you else palette.c("ink"), true)


func _quote(at: Vector2, s: String, w: float) -> void:
	var line := ""
	var y := at.y
	var f := Deck.font("ui400")
	for word in ("\"" + s + "\"").split(" "):
		var next := word if line == "" else line + " " + word
		if Deck.width("ui400", next, 17) > w and line != "":
			draw_string(f, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, palette.c("inkDim"))
			y += 24
			line = word
		else:
			line = next
	draw_string(f, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, palette.c("inkDim"))
