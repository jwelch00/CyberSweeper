extends TestCase
## Every property-suite game and every bot run must be reproducible from its
## seed alone: no randomness from Godot's global RNG anywhere.


func test_property_drivers_repeat_exactly() -> void:
	var suite := PropertySuite.new()
	suite.rules = Rules.load_default()
	suite.out_dir = OS.get_cache_dir()
	for driver in ["perfect", "sloppy", "wanderer"]:
		var a := suite._play(driver, 3, 80, 1000, 1000)
		var b := suite._play(driver, 3, 80, 1000, 1000)
		for key in ["tiles", "hits", "flags", "chords", "far_clicks", "chunks_locked"]:
			eq(a[key], b[key], "%s %s" % [driver, key])
		eq(a.gen, b.gen, driver + " generator stats")


func test_global_rng_does_not_leak_in() -> void:
	# Disturb the global RNG between two identical runs; nothing may change.
	var suite := PropertySuite.new()
	suite.rules = Rules.load_default()
	suite.out_dir = OS.get_cache_dir()
	seed(1)
	var a := suite._play("wanderer", 7, 80, 1000, 1000)
	seed(99999)
	randi()
	var b := suite._play("wanderer", 7, 80, 1000, 1000)
	eq(a.tiles, b.tiles)
	eq(a.gen, b.gen)
