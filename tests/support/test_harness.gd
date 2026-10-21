class_name TestHarness
extends RefCounted
## Minimal assertion + reporting harness for the headless test runner.
##
## Deliberately dependency-free: suites only need [method check]/[method equal]
## and the runner prints a machine-readable summary, which is what the automation
## around this project consumes.

signal suite_started(name: String)
signal suite_finished(name: String, failures: int)

var current_suite: String = "?"
var failures: Array[String] = []
var checks_run: int = 0
var suites_run: int = 0
var _case_failures: int = 0


func begin_suite(name: String) -> void:
	current_suite = name
	suites_run += 1
	_case_failures = 0
	suite_started.emit(name)
	print("── %s" % name)


func end_suite() -> void:
	suite_finished.emit(current_suite, _case_failures)


func check(condition: bool, message: String) -> bool:
	checks_run += 1
	if not condition:
		_fail(message)
	return condition


func equal(actual: Variant, expected: Variant, message: String = "") -> bool:
	var ok := _deep_equal(actual, expected)
	if not ok:
		_fail("%s expected %s, got %s" % [message, str(expected), str(actual)])
	else:
		checks_run += 1
	return ok


func not_equal(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	var ok := not _deep_equal(actual, unexpected)
	if not ok:
		_fail("%s value must not equal %s" % [message, str(unexpected)])
	else:
		checks_run += 1
	return ok


func greater(actual: float, minimum: float, message: String = "") -> bool:
	var ok := actual > minimum
	if not ok:
		_fail("%s expected > %s, got %s" % [message, str(minimum), str(actual)])
	else:
		checks_run += 1
	return ok

func less_equal(actual: float, maximum: float, message: String = "") -> bool:
	var ok := actual <= maximum
	if not ok:
		_fail("%s expected <= %s, got %s" % [message, str(maximum), str(actual)])
	else:
		checks_run += 1
	return ok


func less(actual: float, maximum: float, message: String = "") -> bool:
	var ok := actual < maximum
	if not ok:
		_fail("%s expected < %s, got %s" % [message, str(maximum), str(actual)])
	else:
		checks_run += 1
	return ok


func greater_equal(actual: float, minimum: float, message: String = "") -> bool:
	var ok := actual >= minimum
	if not ok:
		_fail("%s expected >= %s, got %s" % [message, str(minimum), str(actual)])
	else:
		checks_run += 1
	return ok


func has_key(dictionary: Dictionary, key: String, message: String = "") -> bool:
	var ok := dictionary.has(key)
	if not ok:
		_fail("%s missing key '%s'" % [message, key])
	else:
		checks_run += 1
	return ok


func is_true(value: bool, message: String = "") -> bool:
	return check(value, message)


## Fails when `text` looks like an untranslated machine key (e.g. "game.chess.name")
## reaching the player. Humanised fallbacks are allowed by design, raw keys are not.
func no_raw_key(text: String, message: String = "") -> bool:
	var looks_like_key := text.contains(".") and not text.contains(" ") and text == text.to_lower()
	var ok := not looks_like_key
	if not ok:
		_fail("%s text looks like an untranslated key: '%s'" % [message, text])
	else:
		checks_run += 1
	return ok


func _fail(message: String) -> void:
	_case_failures += 1
	failures.append("[%s] %s" % [current_suite, message])
	printerr("  ✗ %s" % message)


func _deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key: Variant in da:
			if not db.has(key) or not _deep_equal(da[key], db[key]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		for i: int in range(aa.size()):
			if not _deep_equal(aa[i], ba[i]):
				return false
		return true
	if a is float or b is float:
		if a is float and b is float:
			return absf(float(a) - float(b)) < 0.0001
	return a == b


func summary_line() -> String:
	return "%d suites, %d checks, %d failures" % [suites_run, checks_run, failures.size()]
