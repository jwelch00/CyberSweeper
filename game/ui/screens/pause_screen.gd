class_name PauseScreen
extends MenuScreen
## Pause (Esc during a run). Run time stops and the board hides behind the
## cipher, so a pause can't be used to plan. End run banks a Ghost run or
## abandons an Arcade one; either way it's recorded like any run end.

const PANEL := Vector2(560, 470)

var mode: GameState.Mode = GameState.Mode.ARCADE
var info := ""


func items() -> Array[String]:
	return ["resume", "settings", "end", "menu"]


func label(i: int) -> String:
	return ["Resume", "Settings", "End run" if mode == GameState.Mode.GHOST else "Abandon run", "Main menu"][i]


func panel_rect() -> Rect2:
	return Rect2((size - PANEL) * 0.5, PANEL)


func item_rect(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position.x + 56, p.position.y + 150 + i * 68, PANEL.x - 112, 56)


func _draw() -> void:
	if palette == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(palette.c("void"), 0.45))
	var p := panel_rect()
	Deck.panel(self, p, 63, palette, 0.92)
	Deck.tag(self, p.position + Vector2(56, 52), "paused", palette.c("accent"), palette.c("void"))
	Deck.text(self, "ui400", p.position + Vector2(56, 118), info, 18, palette.c("inkDim"))
	for i in 4:
		Deck.button(self, item_rect(i), label(i), "Esc" if i == 0 else "", palette, i == 0, i == selected)

