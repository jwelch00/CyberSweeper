class_name CliArgs
extends RefCounted
## Command-line flags after `--`: `--key value` or a bare `--key` ("true").
## Shared by the game, the test runner and the simulator.

## Flags a release build still honors: accessibility before the first frame
## (the boot breach flashes before the settings can be reached). Every other
## flag is for development: --seed and --mode would let a known board count
## toward unlocks, and --shot and --gallery write next to the install.
const RELEASE := ["reduce-motion", "reduce-flashing"]


static func parse(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var a := raw[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				out[key] = raw[i + 1]
				i += 1
			else:
				out[key] = "true"
		i += 1
	return out


## The flags this build honors: all of them in a debug build (the editor, the
## tests, the tools), only RELEASE in an exported release build.
static func for_build(args: Dictionary, debug: bool) -> Dictionary:
	if debug:
		return args
	var out := {}
	for k in RELEASE:
		if args.has(k):
			out[k] = args[k]
	return out
