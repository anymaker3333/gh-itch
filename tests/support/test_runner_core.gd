extends RefCounted
## Test discovery, execution and reporting for `tests/run_tests.gd`.
##
## Loaded at runtime so that it can reference the autoload singletons (`Loc`,
## `Catalog`, `Session`, ...) directly - scripts compiled before the autoloads
## register cannot use those identifiers.

const SUITE_DIRS: Array[String] = ["res://tests/unit", "res://tests/games"]
const REQUIRED_SERVICES: Array[String] = ["Log", "Prefs", "ThemeSvc", "Loc", "Catalog", "Audio", "Notify", "SteamSvc", "Net", "Session", "Nav"]

var harness := TestHarness.new()
var filter: String = ""
var filter_terms: PackedStringArray = PackedStringArray()
var list_only: bool = false


func setup(args: PackedStringArray) -> void:
	for i: int in range(args.size()):
		if args[i] == "--filter" and i + 1 < args.size():
			filter = String(args[i + 1])
			filter_terms = _parse_filter(filter)
		elif args[i] == "--list":
			list_only = true


## `--filter` accepts several terms separated by commas or pipes; a suite runs
## when its path contains **any** of them. `--filter test_coup,test_dany` and
## `--filter 'test_coup|test_dany'` are equivalent.
static func _parse_filter(text: String) -> PackedStringArray:
	var terms: PackedStringArray = PackedStringArray()
	for chunk: String in text.split(","):
		for term: String in chunk.split("|"):
			var trimmed := term.strip_edges()
			if not trimmed.is_empty():
				terms.append(trimmed)
	return terms


static func _matches_filter(path: String, terms: PackedStringArray) -> bool:
	if terms.is_empty():
		return true
	for term: String in terms:
		if path.contains(term):
			return true
	return false


## Runs everything and returns the number of failed checks.
func run() -> int:
	_verify_services()
	print("════════════════════════════════════════════════════════════")
	print(" Game Hub test run  ·  Godot %s  ·  locale=%s" % [Engine.get_version_info().get("string", "?"), Loc.current_locale])
	print(" services: %d locales, %d games, steam=%s" % [Loc.locale_codes().size(), Catalog.count(), SteamSvc.state_name()])
	if not filter.is_empty():
		print(" filter: %s" % filter)
	print("════════════════════════════════════════════════════════════")
	var started := Time.get_ticks_msec()
	var suites := discover_suites()
	if list_only:
		for path: String in suites:
			print(path)
		print("%d suites" % suites.size())
		return 0
	for path: String in suites:
		_run_suite(path)
	var elapsed := Time.get_ticks_msec() - started
	_report(elapsed)
	return harness.failures.size()


func _verify_services() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for name: String in REQUIRED_SERVICES:
		if tree == null or tree.root.get_node_or_null(name) == null:
			harness.check(false, "autoload service '%s' is missing" % name)


func discover_suites() -> Array[String]:
	var paths: Array[String] = []
	for dir: String in SUITE_DIRS:
		var handle := DirAccess.open(dir)
		if handle == null:
			continue
		var files := handle.get_files()
		files.sort()
		for file: String in files:
			if not file.ends_with(".gd") or file.begins_with("_"):
				continue
			var suite_path := "%s/%s" % [dir, file]
			if not _matches_filter(suite_path, filter_terms):
				continue
			paths.append(suite_path)
	return paths


func _run_suite(path: String) -> void:
	var resource := load(path)
	if not (resource is GDScript):
		harness.check(false, "cannot load suite %s (parse error?)" % path)
		return
	var script: GDScript = resource
	if not script.can_instantiate():
		harness.check(false, "suite %s cannot be instantiated (parse error?)" % path)
		return
	var instance: Variant = script.new()
	if instance == null or not instance.has_method("run"):
		harness.check(false, "suite has no run(): %s" % path)
		return
	var name := path.get_file().get_basename()
	if instance.has_method("suite_name"):
		name = String(instance.call("suite_name"))
	harness.begin_suite(name)
	instance.call("run", harness)
	harness.end_suite()


func _report(elapsed_ms: int) -> void:
	print("════════════════════════════════════════════════════════════")
	if harness.failures.is_empty():
		print(" PASS  %s  (%.2fs)" % [harness.summary_line(), float(elapsed_ms) / 1000.0])
	else:
		print(" FAIL  %s  (%.2fs)" % [harness.summary_line(), float(elapsed_ms) / 1000.0])
		for failure: String in harness.failures:
			print("   • %s" % failure)
	print("════════════════════════════════════════════════════════════")
