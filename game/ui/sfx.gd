class_name Sfx
extends Node
## Short synthesized sounds (self-made by tools/make_sfx.py, see CREDITS.md).

const NAMES := ["reveal", "cascade", "flag", "hit", "link", "low", "end", "heartbeat", "denied", "accepted", "slam"]

var enabled := true
var volume_db := -12.0
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_low := -1e9


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch := 1.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## The low-signal beep, at most once a second.
func low(clock_ms: float) -> void:
	if clock_ms - _last_low >= 1000.0:
		_last_low = clock_ms
		play("low")
