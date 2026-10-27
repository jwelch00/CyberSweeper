extends TestCase
## Command-line flags, and which ones a release build keeps.


func test_flags_parse_with_and_without_values() -> void:
	var a := CliArgs.parse(PackedStringArray(["--seed", "42", "--skip-boot", "--mode", "ghost", "stray"]))
	eq(a, {"seed": "42", "skip-boot": "true", "mode": "ghost"})


func test_release_builds_keep_only_accessibility_flags() -> void:
	var a := CliArgs.parse(PackedStringArray(["--seed", "42", "--mode", "ghost", "--shot", "x.png", "--gallery",
		"--save-dir", "/tmp/x", "--skip-boot", "--reduce-motion", "--reduce-flashing"]))
	eq(CliArgs.for_build(a, true), a, "a debug build (editor, tests, tools) keeps every flag")
	eq(CliArgs.for_build(a, false), {"reduce-motion": "true", "reduce-flashing": "true"},
		"a release build can't seed an Arcade run or write screenshots next to the install")
