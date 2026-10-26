class_name GameSettings
extends RefCounted
## Player settings. Milestone 4 adds the settings screen and saves these to
## user://; until then they are set from dev keys (see README).

var palette_id := "signal"
var scanlines := true
var reduced_motion := false
var sfx := true
var sfx_volume_db := -12.0
var show_fps := false
