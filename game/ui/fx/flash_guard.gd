class_name FlashGuard
extends RefCounted
## Full-screen flashes (title-card flash frames, the mine-hit flash, the boot's
## KEY ACCEPTED flash and denial kick, tear lines) ask here first. Never more
## than 3 in any rolling second (design/MOTION.md, Accessibility), and none at
## all with reduce flashing on.

const MAX_PER_SECOND := 3

var reduce_flashing := false
var _times: Array[float] = []


func allow(now_ms: float) -> bool:
	if reduce_flashing:
		return false
	while not _times.is_empty() and now_ms - _times[0] >= 1000.0:
		_times.pop_front()
	if _times.size() >= MAX_PER_SECOND:
		return false
	_times.append(now_ms)
	return true
