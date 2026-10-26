class_name TestCase
extends RefCounted
## Base for unit tests. The runner calls every method whose name starts with
## "test_" and collects failures.

var failures: Array[String] = []
var current := ""


func check(cond: bool, msg := "") -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg := "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s %s" % [current, str(expected), str(actual), msg])
