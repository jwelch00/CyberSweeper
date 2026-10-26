class_name Palette
extends RefCounted
## One color palette from res://assets/tokens/palettes.json, a byte-for-byte
## copy of design/tokens/palettes.json (tools/sync_design.py). Every color the
## game draws comes from here; nothing is hand-copied.

const PATH := "res://assets/tokens/palettes.json"
const ROLES: Array[String] = ["void", "floor", "grid", "tile", "tileEdge", "cipher", "ink", "inkDim",
	"accent", "accent2", "warn", "danger"]

var id: String
var name: String
var vibe: String
## Built for color vision deficiency (Plaintext); the picker tags it.
var accessibility := false
var colors := {}                # role -> Color
var numbers: Array[Color] = []  # numbers[0] is the color of a 1

static var _cache: Array[Palette] = []


static func load_all() -> Array[Palette]:
	if not _cache.is_empty():
		return _cache
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(d is Dictionary, "palettes.json did not parse")
	for p in d.palettes:
		var pal := Palette.new()
		pal.id = p.id
		pal.name = p.name
		pal.vibe = p.get("vibe", "")
		pal.accessibility = bool(p.get("accessibility", false))
		for role in ROLES:
			pal.colors[role] = Color.html(p.colors[role])
		for hex in p.numbers:
			pal.numbers.append(Color.html(hex))
		_cache.append(pal)
	return _cache


static func by_id(pid: String) -> Palette:
	for p in load_all():
		if p.id == pid:
			return p
	return load_all()[0]


func c(role: String) -> Color:
	return colors[role]


## Color of number n (1..8).
func number(n: int) -> Color:
	return numbers[clampi(n, 1, 8) - 1]


## WCAG contrast ratio between two opaque colors.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(col: Color) -> float:
	var ch := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(col.r) + 0.7152 * ch.call(col.g) + 0.0722 * ch.call(col.b)
