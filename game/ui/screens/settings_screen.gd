class_name SettingsScreen
extends MenuScreen
## Settings, applied live and saved as they change. Every toggle says On or
## Off in words; the volume shows its number as well as a bar.

signal changed

const ROW := Vector2(820, 64)
const TOP := 250.0

var settings: GameSettings


func items() -> Array[String]:
	return ["sfx", "volume", "scanlines", "reduce_motion", "reduce_flashing", "fullscreen", "show_fps"]


func label(id: String) -> Array:
	match id:
		"sfx": return ["Sound", "M"]
		"volume": return ["Volume", ""]
		"scanlines": return ["Scanlines", ""]
		"reduce_motion": return ["Reduce motion", "no shake, jitter, trails or transitions; follows your system until you set it"]
		"reduce_flashing": return ["Reduce flashing", "no full-screen flashes (on with reduce motion)"]
		"fullscreen": return ["Fullscreen", "F11"]
		"show_fps": return ["FPS overlay", "F3"]
	return [id, ""]


func item_rect(i: int) -> Rect2:
	return Rect2((size.x - ROW.x) * 0.5, TOP + i * (ROW.y + 10), ROW.x, ROW.y)


func value(id: String) -> Variant:
	match id:
		"sfx": return settings.sfx
		"volume": return settings.volume
		"scanlines": return settings.scanlines
		"reduce_motion": return settings.reduced_motion
		"reduce_flashing": return settings.reduce_flashing
		"fullscreen": return settings.fullscreen
		"show_fps": return settings.show_fps
	return null


func activate(i: int) -> void:
	selected = i
	var id := items()[i]
	if id == "volume":
		adjust(i, 1 if settings.volume < 1.0 else -20)
		return
	set_value(id, not bool(value(id)))


func adjust(i: int, d: int) -> void:
	var id := items()[i]
	if id == "volume":
		set_value(id, clampf(snappedf(settings.volume + 0.05 * d, 0.05), 0.0, 1.0))
	else:
		set_value(id, d > 0)


func set_value(id: String, v: Variant) -> void:
	match id:
		"sfx": settings.sfx = v
		"volume": settings.volume = v
		"scanlines": settings.scanlines = v
		"reduce_motion": settings.set_reduced_motion(v)
		"reduce_flashing": settings.reduce_flashing = v
		"fullscreen": settings.fullscreen = v
		"show_fps": settings.show_fps = v
	changed.emit()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Clicking the volume bar sets it there.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := item_at(event.position)
		if i >= 0 and items()[i] == "volume":
			var bar := _bar_rect(item_rect(i))
			if bar.grow(8).has_point(event.position):
				selected = i
				set_value("volume", clampf(snappedf((event.position.x - bar.position.x) / bar.size.x, 0.05), 0.0, 1.0))
				accept_event()
				return
	super(event)


func _bar_rect(r: Rect2) -> Rect2:
	return Rect2(r.end.x - 28 - 260, r.position.y + r.size.y * 0.5 - 4, 260, 8)


func _click_other(p: Vector2) -> void:
	if p.y < 220:
		back.emit()


func _draw() -> void:
	if palette == null or settings == null:
		return
	backdrop()
	var left := item_rect(0).position.x
	Deck.heading(self, Vector2(left, 100), "Settings", "Saved as you change them.", palette)
	Deck.back_hint(self, Vector2(item_rect(0).end.x, 160), "Back", palette)
	for i in items().size():
		var id := items()[i]
		var r := item_rect(i)
		var lit := i == selected
		draw_rect(r, palette.c("tile") if lit else Color(palette.c("tile"), 0.45))
		if lit:
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), palette.c("accent"))
		var l := label(id)
		var note := String(l[1]).length() > 4
		var ly := 30.0 if note else 40.0
		draw_string(Deck.font("ui600"), r.position + Vector2(28, ly), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			palette.c("ink") if lit else palette.c("inkDim"))
		if note:
			Deck.text(self, "ui400", r.position + Vector2(28, 52), l[1], 14, palette.c("inkDim"))
		elif l[1] != "":
			Deck.key(self, r.position + Vector2(28 + Deck.width("ui600", l[0], 22) + 14, ly - 18), l[1], palette.c("inkDim"))
		if id == "volume":
			var bar := _bar_rect(r)
			Deck.progress_bar(self, bar, settings.volume, palette.c("accent"))
			Deck.text(self, "mono600", Vector2(bar.position.x - 16, r.position.y + 40), "%d%%" % roundi(settings.volume * 100.0), 18,
				palette.c("ink"), true)
		else:
			var on := bool(value(id))
			var t := "On" if on else "Off"
			var tw := Deck.width("ui700", t, 18) + 28.0
			var box := Rect2(r.end.x - 28 - tw, r.position.y + 16, tw, 32)
			if on:
				draw_rect(box, palette.c("accent"))
			else:
				draw_rect(box, palette.c("tileEdge"), false, 1.0)
			Deck.text(self, "ui700", box.position + Vector2(14, 23), t, 18, palette.c("void") if on else palette.c("inkDim"))
	Deck.hints(self, Vector2(left, size.y - 70), [["↑", "↓", "choose"], ["←", "→", "change"], ["Enter", "toggle"]], palette)
