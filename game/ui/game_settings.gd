class_name GameSettings
extends RefCounted
## Player settings, saved to settings.json in the user data folder (SaveStore)
## whenever they change.

const VERSION := 1

var palette_id := "signal"
var scanlines := true
## Reduce motion: no shake, jitter, slide-ins, cipher drift, afterimages or
## datamosh; effects become instant changes. Follows the OS setting until the
## player sets it.
var reduced_motion := false
var reduced_motion_set := false
## Reduce flashing: no full-screen flash frames. On whenever reduce motion is.
var reduce_flashing := false
var sfx := true
## Sound volume, 0..1 (25% is about -12 dB).
var volume := 0.25
var fullscreen := false
var show_fps := false
## The mode picker's last choice.
var mode := "arcade"

var sfx_volume_db: float:
	get:
		return linear_to_db(maxf(volume, 0.0001))


## Reads the OS accessibility preference (Godot 4.5+): 1 = reduce, 0 = don't,
## -1 = the OS doesn't say.
static func os_reduce_motion() -> bool:
	if DisplayServer.has_method("accessibility_should_reduce_animation"):
		return int(DisplayServer.call("accessibility_should_reduce_animation")) == 1
	return false


## by_user=false for the OS default, which the player's own choice overrides.
func set_reduced_motion(on: bool, by_user := true) -> void:
	if not by_user and reduced_motion_set:
		return
	reduced_motion = on
	reduced_motion_set = reduced_motion_set or by_user
	if on:
		reduce_flashing = true


func to_dict() -> Dictionary:
	var d := {"version": VERSION, "palette": palette_id, "scanlines": scanlines, "reduce_flashing": reduce_flashing,
		"sfx": sfx, "volume": volume, "fullscreen": fullscreen, "show_fps": show_fps, "mode": mode}
	if reduced_motion_set:
		d["reduce_motion"] = reduced_motion
	return d


## Missing or wrong-typed values fall back to the defaults.
static func from_dict(d: Dictionary) -> GameSettings:
	var s := GameSettings.new()
	s.palette_id = SaveStore.str_of(d, "palette", s.palette_id)
	s.scanlines = SaveStore.bool_of(d, "scanlines", s.scanlines)
	s.reduce_flashing = SaveStore.bool_of(d, "reduce_flashing", s.reduce_flashing)
	s.sfx = SaveStore.bool_of(d, "sfx", s.sfx)
	s.volume = clampf(SaveStore.float_of(d, "volume", s.volume), 0.0, 1.0)
	s.fullscreen = SaveStore.bool_of(d, "fullscreen", s.fullscreen)
	s.show_fps = SaveStore.bool_of(d, "show_fps", s.show_fps)
	s.mode = "ghost" if SaveStore.str_of(d, "mode") == "ghost" else "arcade"
	if d.get("reduce_motion") is bool:
		s.reduced_motion = d.reduce_motion
		s.reduced_motion_set = true
	return s


func save() -> bool:
	return SaveStore.save_json(SaveStore.SETTINGS, to_dict())


static func load_saved() -> GameSettings:
	return from_dict(SaveStore.load_json(SaveStore.SETTINGS))
