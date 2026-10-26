class_name Rules
extends RefCounted
## Gameplay numbers, loaded from res://data/tuning.json so milestone 2 can tune
## them without code changes.

const DEFAULT_PATH := "res://data/tuning.json"

var data: Dictionary

var start_links: int
var signal_max: float
var drain_per_sec: float
var drain_growth_per_min: float
var refill_per_cell: float
var refill_cap_per_move: float
var low_fraction: float
var critical_fraction: float

var density_base: float
var density_per_cell: float
var density_max: float
var min_opening: int

var window_radius: int
var node_cap: int

var proof_margin: int
var local_repair_radius: int
var local_repair_cells: int
var attempts_local: int
var attempts_chunk: int
var attempts_neighbour: int
var rescue_radii: Array[int] = []

var _thresholds := PackedInt64Array()   # mine threshold per depth until the cap
var _threshold_cap := 0


static func load_default() -> Rules:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> Rules:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "tuning file is not a JSON object: " + path)
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> Rules:
	var r := Rules.new()
	r.data = d
	r.start_links = int(d.links.start)
	r.signal_max = float(d.signal.max)
	r.drain_per_sec = float(d.signal.drain_per_sec)
	r.drain_growth_per_min = float(d.signal.drain_growth_per_min)
	r.refill_per_cell = float(d.signal.refill_per_cell)
	r.refill_cap_per_move = float(d.signal.refill_cap_per_move)
	r.low_fraction = float(d.signal.low_fraction)
	r.critical_fraction = float(d.signal.critical_fraction)
	r.density_base = float(d.density.base)
	r.density_per_cell = float(d.density.per_cell)
	r.density_max = float(d.density.max)
	r.min_opening = int(d.start.min_opening)
	r.window_radius = int(d.solver.window_radius)
	r.node_cap = int(d.solver.node_cap)
	r.proof_margin = int(d.generator.proof_margin)
	r.local_repair_radius = int(d.generator.local_repair_radius)
	r.local_repair_cells = int(d.generator.local_repair_cells)
	r.attempts_local = int(d.generator.attempts_local)
	r.attempts_chunk = int(d.generator.attempts_chunk)
	r.attempts_neighbour = int(d.generator.attempts_neighbour)
	for v in d.generator.rescue_radii:
		r.rescue_radii.append(int(v))
	r._build_thresholds()
	return r


## A copy with some values overridden, e.g. {"density": {"base": 0.2}}.
func with_overrides(over: Dictionary) -> Rules:
	var d: Dictionary = data.duplicate(true)
	for section in over:
		for key in over[section]:
			d[section][key] = over[section][key]
	return Rules.from_dict(d)


## Mine probability for a cell at this depth.
func density(depth: int) -> float:
	return minf(density_max, density_base + density_per_cell * depth)


## A cell is a mine when its 32-bit hash is below this.
func mine_threshold(depth: int) -> int:
	if depth >= _threshold_cap:
		return _thresholds[_threshold_cap]
	return _thresholds[depth]


## Signal drained per second after this much run time.
func drain_rate(elapsed_ms: int) -> float:
	return drain_per_sec * (1.0 + drain_growth_per_min * float(elapsed_ms) / 60000.0)


func _build_thresholds() -> void:
	# Depth at which density reaches its cap; beyond it the threshold is constant.
	var cap_depth := 0
	if density_per_cell > 0.0:
		cap_depth = int(ceil((density_max - density_base) / density_per_cell))
	cap_depth = clampi(cap_depth, 0, 100000)
	_threshold_cap = cap_depth
	_thresholds.resize(cap_depth + 1)
	for depth in cap_depth + 1:
		_thresholds[depth] = int(density(depth) * 4294967296.0)
