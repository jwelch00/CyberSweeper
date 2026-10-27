class_name GameOverScreen
extends Control
## The run end (design/png/game-over-signal.png).
## Left: the tag, one line of context, the score (and NEW BEST), how the score
## adds up (count x value per number, then the total), run stats, and Run it
## back (R) and Main menu (Esc), clickable or by key.
## Right: the rival ladder with this run and your previous best slotted in;
## below it the rival beaten for the first time (with their line), a palette
## unlocked this run (with Equip), or else the next rival's taunt. Ghost runs
## show the Ghost leaderboard instead: no rivals.

signal chosen(id: String)

const LEFT := Rect2(120, 95, 1000, 885)
const RIGHT_X := 1160.0
const RIGHT_W := 640.0

var palette: Palette
var summary := {}
var report := {}
var profile: Profile
var hovered := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_run(s: Dictionary, r := {}, p: Profile = null) -> void:
	summary = s
	report = r
	profile = p
	hovered = ""
	queue_redraw()


func ghost() -> bool:
	return summary.get("mode", GameState.Mode.ARCADE) == GameState.Mode.GHOST


func button_rect(id: String) -> Rect2:
	var y := LEFT.end.y - 52.0 - 56.0
	match id:
		"again":
			return Rect2(LEFT.position.x + 64, y, 206, 56)
		"menu":
			return Rect2(LEFT.position.x + 64 + 206 + 16, y, 218, 56)
		"equip":
			return _equip_rect()
	return Rect2()


func _cards() -> Array[String]:
	var out: Array[String] = []
	if ghost():
		return out
	if not report.get("beaten_now", []).is_empty():
		out.append("rival")
	if not report.get("unlocked_now", []).is_empty():
		out.append("unlock")
	if out.is_empty() and report.get("flavor", {}).get("kind", "") in ["taunt", "close", "again"]:
		out.append("taunt")
	return out


func _card_rect(k: int) -> Rect2:
	return Rect2(RIGHT_X, LEFT.position.y + 475 + k * 215, RIGHT_W, 195)


func _equip_rect() -> Rect2:
	var k := _cards().find("unlock")
	if k < 0:
		return Rect2()
	var c := _card_rect(k)
	return Rect2(c.position.x + 44, c.end.y - 40 - 46, 220, 46)


func _gui_input(event: InputEvent) -> void:
	var ids := ["again", "menu", "equip"]
	if event is InputEventMouseMotion:
		var h := ""
		for id in ids:
			if button_rect(id).has_point(event.position):
				h = id
		if h != hovered:
			hovered = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in ids:
			if button_rect(id).has_point(event.position):
				_choose(id)
		accept_event()


func _choose(id: String) -> void:
	if id == "equip":
		var u: Array = report.get("unlocked_now", [])
		if not u.is_empty():
			chosen.emit("equip:" + String(u.back()))
		return
	chosen.emit(id)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	match k.keycode:
		KEY_R, KEY_ENTER, KEY_KP_ENTER:
			_choose("again")
		KEY_ESCAPE:
			_choose("menu")
		KEY_E:
			_choose("equip")
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if palette == null:
		return
	var v := palette.c("void")
	draw_rect(Rect2(Vector2.ZERO, size), v)
	var c := Vector2(size.x * 0.3, size.y * 0.4)
	var tint := v.lerp(palette.c("danger"), 0.12)
	for i in range(24, 0, -1):
		var f := float(i) / 24
		draw_circle(c, size.length() * 0.52 * f, v.lerp(tint, 1.0 - f))
	_left()
	_ladder()
	var cards := _cards()
	for k in cards.size():
		_card(cards[k], _card_rect(k))


func _left() -> void:
	Deck.panel(self, LEFT, Jag.SEED_OVER, palette, 0.85)
	var x := LEFT.position.x + 64.0
	var y := LEFT.position.y + 77.0
	var ended := bool(summary.get("ended", false))
	var title := "link severed"
	var col := palette.c("danger")
	if ended:
		title = "run banked" if ghost() else "run ended"
		col = palette.c("accent")
	Deck.tag(self, Vector2(x, y), title, col, palette.c("void"), 16)
	var ms := int(summary.get("elapsed_ms", 0))
	var depth := int(summary.get("depth", 0))
	var line := ""
	if ghost():
		line = "Ghost run banked at depth %d, %s." % [depth, Deck.minutes_words(ms)]
	elif ended:
		line = "Run ended at depth %d, %s." % [depth, Deck.minutes_words(ms)]
	else:
		line = "All three links lost at depth %d, %s." % [depth, Deck.minutes_words(ms)]
	Deck.text(self, "ui400", Vector2(x, y + 60), line, 20, palette.c("inkDim"))
	var score := int(summary.get("score", 0))
	var s := HudText.thousands(score)
	var sy := y + 220.0
	HudText.draw_glow_string(self, Deck.font("mono800"), Vector2(x - 6, sy), s, 132, palette.c("ink"), 22.0, 0.25)
	if report.get("new_best", false):
		var sw := Deck.width("mono800", s, 132)
		Deck.text(self, "ui600", Vector2(x + sw + 28, sy - 26), "New best", 20, palette.c("accent2"))
		var prev := int(report.get("previous_best", 0))
		Deck.text(self, "ui400", Vector2(x + sw + 28, sy - 4), "up from " + HudText.thousands(prev) if prev > 0 else "your first run",
			16, palette.c("inkDim"))
	# How the score adds up.
	var ty := sy + 90.0
	var hw := Deck.text(self, "ui600", Vector2(x, ty), "How your score adds up", 20, palette.c("ink"))
	Deck.text(self, "ui400", Vector2(x + hw + 8, ty), "every number you decrypted, summed", 20, palette.c("inkDim"))
	var tally: Array = summary.get("tally", [])
	var subs: Array[int] = []
	var top := 1
	for n in range(1, 9):
		var cnt := int(tally[n]) if n < tally.size() else 0
		subs.append(cnt * n)
		top = maxi(top, cnt * n)
	var base := ty + 228.0
	for n in range(1, 9):
		var cx := x + 42.0 + (n - 1) * 94.5
		var nc := palette.number(n)
		var cnt := int(tally[n]) if n < tally.size() else 0
		Deck.text(self, "mono800", Vector2(cx - Deck.width("mono800", str(n), 28) * 0.5, ty + 60), str(n), 28, nc)
		var h := maxf(2.0, float(subs[n - 1]) / top * 130.0)
		draw_rect(Rect2(cx - 26, base - h, 52, h), Color(nc, 0.78))
		draw_rect(Rect2(cx - 26, base - h, 52, 3), nc)
		var ct := "×%d" % cnt
		Deck.text(self, "mono400", Vector2(cx - Deck.width("mono400", ct, 15) * 0.5, base + 22), ct, 15, palette.c("inkDim"))
		var st := HudText.thousands(subs[n - 1])
		Deck.text(self, "mono600", Vector2(cx - Deck.width("mono600", st, 18) * 0.5, base + 48), st, 18, palette.c("ink"))
	var tx := x + 42.0 + 8 * 94.5 - 20.0
	draw_line(Vector2(tx, base - 40), Vector2(tx, base + 52), palette.c("tileEdge"), 1.0)
	Deck.text(self, "ui400", Vector2(tx + 18, base + 4), "total", 15, palette.c("inkDim"))
	Deck.text(self, "mono800", Vector2(tx + 18, base + 40), s, 32, palette.c("ink"))
	# Run stats.
	var stats := [["time survived", Deck.clock(ms)], ["tiles decrypted", HudText.thousands(int(summary.get("tiles", 0)))],
		["deepest point", str(depth)], ["flags correct", "%d%%" % roundi(float(summary.get("flags_correct", 1.0)) * 100.0)],
		["seed", CsHash.seed_text(int(summary.get("seed", 0)))]]
	var stx := x
	var sty := base + 110.0
	for st in stats:
		Deck.text(self, "ui400", Vector2(stx, sty), st[0], 15, palette.c("inkDim"))
		Deck.text(self, "mono600", Vector2(stx, sty + 30), st[1], 26, palette.c("ink"))
		stx += maxf(Deck.width("ui400", st[0], 15), Deck.width("mono600", st[1], 26)) + 52.0
	Deck.button(self, button_rect("again"), "Run it back", "R", palette, true, hovered == "again")
	Deck.button(self, button_rect("menu"), "Main menu", "Esc", palette, false, hovered == "menu")


func _ladder() -> void:
	var r := Rect2(RIGHT_X, LEFT.position.y, RIGHT_W, 435)
	Deck.panel(self, r, Jag.SEED_OVER_SIDE, palette, 0.85)
	var x := r.position.x + 44
	var score := int(summary.get("score", 0))
	var rows: Array = []
	if ghost():
		var hw := Deck.text(self, "ui600", Vector2(x, r.position.y + 64), "Ghost runs", 20, palette.c("ink"))
		Deck.text(self, "ui400", Vector2(x + hw + 8, r.position.y + 64), "your best, no rivals", 20, palette.c("inkDim"))
		var rank := int(report.get("rank", -1))
		var list: Array = profile.ghost if profile else []
		for i in mini(list.size(), 5):
			rows.append({"name": "You", "sub": "this run" if i == rank else String(list[i].date), "score": int(list[i].score),
				"you": i == rank})
		if rank < 0 or rank >= 5:
			rows.append({"name": "You", "sub": "this run", "score": score, "you": true})
	else:
		var hw := Deck.text(self, "ui600", Vector2(x, r.position.y + 64), "Rivals", 20, palette.c("ink"))
		Deck.text(self, "ui400", Vector2(x + hw + 8, r.position.y + 64), "local leaderboard", 20, palette.c("inkDim"))
		var beaten_run: Array = report.get("beaten_run", [])
		for rv in Profile.rivals():
			rows.append({"name": rv.name, "sub": rv.label + (", beaten this run" if beaten_run.has(rv.id) else ""),
				"score": int(rv.score), "rival": true, "beaten": beaten_run.has(rv.id)})
		rows.append({"name": "You", "sub": "this run", "score": score, "you": true})
		var prev := int(report.get("previous_best", 0))
		if prev > 0 and prev != score:
			rows.append({"name": "You", "sub": "previous best", "score": prev})
		rows.sort_custom(func(a, b): return a.score > b.score or (a.score == b.score and a.get("you", false)))
	# Seven rivals don't fit: show the top of the board and a window around
	# this run, with a gap marker where rows are skipped.
	var keep := ladder_window(rows.map(func(row): return row.get("you", false) and row.sub == "this run"), 6)
	var y := r.position.y + 92.0
	var prev := -1
	for i in keep:
		if prev >= 0 and i > prev + 1:
			Deck.text(self, "mono400", Vector2(x + 18, y + 12), "· · ·", 15, palette.c("inkDim"))
			y += 20
		_row(Rect2(x, y, RIGHT_W - 88, 46), i + 1, rows[i], score)
		y += 52
		prev = i


## Which ladder rows to show when there are more than `size`: the top row,
## then a window centred on this run (marked true in `is_you`).
static func ladder_window(is_you: Array, size: int) -> Array[int]:
	var n := is_you.size()
	var out: Array[int] = []
	if n <= size:
		for i in n:
			out.append(i)
		return out
	var you := maxi(0, is_you.find(true))
	var lo := clampi(you - (size - 1) / 2, 1, n - (size - 1))
	out.append(0)
	for i in range(lo, lo + size - 1):
		out.append(i)
	return out


func _row(r: Rect2, rank: int, row: Dictionary, score: int) -> void:
	var you: bool = row.get("you", false)
	draw_rect(r, palette.c("accent").lerp(palette.c("tile"), 0.75) if you else Color(palette.c("tile"), 0.7))
	if you:
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), palette.c("accent"))
	Deck.text(self, "mono400", r.position + Vector2(18, 35), str(rank), 15, palette.c("inkDim"))
	var beaten: bool = row.get("beaten", false)
	var nc := palette.c("accent") if you else (palette.c("inkDim") if beaten else palette.c("ink"))
	var nw := Deck.text(self, "ui600", r.position + Vector2(64, 36), row.name, 20, nc)
	if beaten:
		draw_line(r.position + Vector2(64, 28), r.position + Vector2(64 + nw, 28), palette.c("inkDim"), 2.0)
	Deck.text(self, "ui400", r.position + Vector2(64 + nw + 10, 36), row.sub, 14, palette.c("inkDim"))
	var st := HudText.thousands(int(row.score))
	if row.get("rival", false) and int(row.score) > score:
		Deck.text(self, "mono600", Vector2(r.end.x - 18, r.position.y + 28), st, 20, palette.c("ink"), true)
		Deck.text(self, "mono400", Vector2(r.end.x - 18, r.position.y + 47), "%s to go" % HudText.thousands(int(row.score) - score),
			12, palette.c("inkDim"), true)
	else:
		var sc := palette.c("accent") if you else (palette.c("inkDim") if beaten else palette.c("ink"))
		var sw := Deck.text(self, "mono600", Vector2(r.end.x - 18, r.position.y + 36), st, 20, sc, true)
		if beaten:
			draw_line(Vector2(r.end.x - 18 - sw, r.position.y + 29), Vector2(r.end.x - 18, r.position.y + 29), palette.c("inkDim"), 2.0)


func _card(kind: String, r: Rect2) -> void:
	Deck.panel(self, r, 251 + int(r.position.y) % 7, palette, 0.85)
	var x := r.position.x + 44
	match kind:
		"rival":
			var id: String = report.beaten_now.back()
			var rv := Profile.rival(id)
			Deck.text(self, "ui500", Vector2(x, r.position.y + 46), "Rival down", 16, palette.c("accent2"))
			Deck.text(self, "ui700", Vector2(x, r.position.y + 90), rv.name, 32, palette.c("ink"))
			_quote(Vector2(x, r.position.y + 130), rv.beaten, RIGHT_W - 88)
		"unlock":
			var pid: String = report.unlocked_now.back()
			var p := Palette.by_id(pid)
			Deck.text(self, "ui500", Vector2(x, r.position.y + 46), "Palette unlocked", 16, palette.c("accent2"))
			var nw := Deck.text(self, "ui700", Vector2(x, r.position.y + 90), p.name, 32, palette.c("ink"))
			var sw := Rect2(x + nw + 24, r.position.y + 68, 220, 22)
			var chips: Array[Color] = [p.c("void")]
			chips.append_array(p.numbers)
			chips.append(p.c("ink"))
			for k in chips.size():
				draw_rect(Rect2(sw.position.x + k * sw.size.x / chips.size(), sw.position.y, sw.size.x / chips.size(), sw.size.y), chips[k])
			Deck.button(self, _equip_rect(), "Equip " + p.name, "E", p, true, hovered == "equip")
		"taunt":
			var f: Dictionary = report.flavor
			var rv := Profile.rival(f.rival)
			var head: String = {"close": "So close", "again": "Top of the board"}.get(f.kind, "Next rival")
			Deck.text(self, "ui500", Vector2(x, r.position.y + 46), head, 16,
				palette.c("accent2") if f.kind == "close" else palette.c("inkDim"))
			var nw := Deck.text(self, "ui700", Vector2(x, r.position.y + 90), rv.name, 32, palette.c("ink"))
			Deck.text(self, "mono600", Vector2(x + nw + 16, r.position.y + 88), HudText.thousands(int(rv.score)), 20, palette.c("inkDim"))
			_quote(Vector2(x, r.position.y + 130), f.text, RIGHT_W - 88)


## A quiet one-line quote in ink-dim (wraps if it must).
func _quote(at: Vector2, s: String, w: float) -> void:
	var line := ""
	var y := at.y
	for word in ("\"" + s + "\"").split(" "):
		var next := word if line == "" else line + " " + word
		if Deck.width("ui400", next, 16) > w and line != "":
			Deck.text(self, "ui400", Vector2(at.x, y), line, 16, palette.c("inkDim"))
			y += 22
			line = word
		else:
			line = next
	Deck.text(self, "ui400", Vector2(at.x, y), line, 16, palette.c("inkDim"))
