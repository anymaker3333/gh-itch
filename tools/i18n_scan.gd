extends SceneTree
## Development tool: lists localisation keys referenced from GDScript sources.
##
##     godot --headless --path . --script tools/i18n_scan.gd
##
## Prints static keys and the patterns that are completed at runtime, one per line
## as `key<TAB>file:line`. Read-only: never writes files.

func _initialize() -> void:
	var static_keys := I18nScanner.scan_static_keys()
	var patterns := I18nScanner.scan_dynamic_patterns()
	var keys: Array = static_keys.keys()
	keys.sort()
	var pattern_keys: Array = patterns.keys()
	pattern_keys.sort()
	print("# static keys: %d" % keys.size())
	for key: Variant in keys:
		print("%s\t%s" % [String(key), String(static_keys[key])])
	print("# dynamic key patterns: %d" % pattern_keys.size())
	for key: Variant in pattern_keys:
		print("%s\t%s" % [String(key), String(patterns[key])])
	quit(0)
