class_name GameSettings
extends RefCounted
## Player settings. Milestone 4 adds the settings screen and saves these to
## user://; until then they are set from dev keys (see README).

var palette_id := "signal"
var scanlines := true
## Reduce motion: no shake, jitter, slide-ins, cipher drift, afterimages or
## datamosh; effects become instant changes. Defaults to the OS setting.
var reduced_motion := false
## Reduce flashing: no full-screen flash frames. On whenever reduce motion is.
var reduce_flashing := false
var sfx := true
var sfx_volume_db := -12.0
var show_fps := false


## Reads the OS accessibility preference (Godot 4.5+): 1 = reduce, 0 = don't,
## -1 = the OS doesn't say.
static func os_reduce_motion() -> bool:
	if DisplayServer.has_method("accessibility_should_reduce_animation"):
		return int(DisplayServer.call("accessibility_should_reduce_animation")) == 1
	return false


func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	if on:
		reduce_flashing = true
