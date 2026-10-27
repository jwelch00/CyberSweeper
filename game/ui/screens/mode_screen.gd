class_name ModeScreen
extends MenuScreen
## The mode picker after Jack in: Arcade (the main mode) or Ghost (no timer,
## its own leaderboard, no unlocks). Remembers the last pick.

const CARD := Vector2(640, 420)

var profile: Profile


func _ready() -> void:
	super()
	horizontal = true


func items() -> Array[String]:
	return ["arcade", "ghost"]


func item_rect(i: int) -> Rect2:
	var gap := 40.0
	var x := (size.x - CARD.x * 2 - gap) * 0.5 + i * (CARD.x + gap)
	return Rect2(x, 300, CARD.x, CARD.y)


func _draw() -> void:
	if palette == null:
		return
	backdrop()
	Deck.heading(self, Vector2(item_rect(0).position.x, 120), "Jack in", "Pick a mode. You can switch every run.", palette)
	Deck.back_hint(self, Vector2(item_rect(1).end.x, 180), "Back to menu", palette)
	var texts := [
		["Arcade", "accent", ["The signal drains; decrypting refills it.", "Three links. Beat the rivals, unlock palettes."],
			GameState.Mode.ARCADE],
		["Ghost", "accent2", ["No signal, no timer. End the run when you like.", "Its own leaderboard. No rivals, no unlocks."],
			GameState.Mode.GHOST],
	]
	for i in 2:
		var r := item_rect(i)
		var t: Array = texts[i]
		var col := palette.c(t[1])
		var lit := i == selected
		Deck.panel(self, r, 101 + i * 7, palette, 0.9 if lit else 0.7)
		if lit:
			draw_rect(Rect2(r.position + Vector2(-10, 30), Vector2(5, r.size.y - 60)), col)
		var x := r.position.x + 48
		Deck.tag(self, Vector2(x, r.position.y + 48), t[0], col, palette.c("void"))
		draw_string(Deck.font("ui700"), Vector2(x, r.position.y + 150), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 56,
			palette.c("ink") if lit else palette.c("inkDim"))
		var y := r.position.y + 210
		for line in t[2]:
			Deck.text(self, "ui400", Vector2(x, y), line, 20, palette.c("inkDim"))
			y += 32
		var best := profile.best(t[3]) if profile else 0
		Deck.text(self, "ui500", Vector2(x, r.end.y - 60), "your best", 15, palette.c("inkDim"))
		Deck.text(self, "mono800", Vector2(x, r.end.y - 28), HudText.thousands(best) if best > 0 else "none yet", 28,
			palette.c("ink"))
		if lit:
			Deck.key(self, Vector2(r.end.x - 48 - 60, r.end.y - 52), "Enter", palette.c("ink"))
	Deck.hints(self, Vector2(item_rect(0).position.x, size.y - 70), [["←", "→", "choose"], ["Enter", "jack in"]], palette)


func _click_other(p: Vector2) -> void:
	if p.y < 220 and p.x > item_rect(1).end.x - 260:
		back.emit()
