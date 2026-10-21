class_name I18nScanner
extends RefCounted
## Static analysis of localisation key usage in GDScript sources.
##
## Shared by `tools/i18n_scan.gd` (developer report) and the localisation test
## suite (catalogue completeness gate). It finds the keys that appear as string
## literals in calls such as `Loc.t("...")`, action `label_key` fields and
## `log_event("...")`, plus the *patterns* that are completed at runtime with
## `%` formatting so the report can list what still needs a hand-written family.

const SCAN_DIRS: Array[String] = ["res://scripts", "res://tests"]

const LITERAL_PATTERNS: Array[String] = [
	"Loc\\.t\\(\"([A-Za-z0-9_./]+)\"",
	"UI\\.t\\(\"([A-Za-z0-9_./]+)\"",
	"Loc\\.tp\\(\"([A-Za-z0-9_./]+)\"",
	"label_key\": \"([A-Za-z0-9_.]+)\"",
	"label_key = \"([A-Za-z0-9_.]+)\"",
	"text_key\": \"([A-Za-z0-9_.]+)\"",
	"text_key = \"([A-Za-z0-9_.]+)\"",
	"key = \"([A-Za-z0-9_]+\\.[A-Za-z0-9_.]+)\"",
	"reason_key\": \"([A-Za-z0-9_.]+)\"",
	"has_key\\(\"([A-Za-z0-9_./]+)\"",
	"return \"([a-z][a-z0-9_]*\\.[a-z0-9_.]+)\"",
	# Keys collected in constant arrays and then looked up with Loc.t at runtime.
	"^\\s*\"([a-z][a-z0-9_]*\\.[a-z0-9_.]+)\",?\\s*$",
	"log_event\\(\"([A-Za-z0-9_.]+)\"",
	"_fail\\(\"([A-Za-z0-9_.]+)\"",
	"finish\\([^,]+, \"([A-Za-z0-9_.]+)\"",
	"warning\\(\"([A-Za-z0-9_.]+)\"",
	"success\\(\"([A-Za-z0-9_.]+)\"",
	"info\\(\"([A-Za-z0-9_.]+)\"",
	"_emit_rejection\\(\"([A-Za-z0-9_.]+)\"",
	"emit\\(\"([A-Za-z0-9_.]+)\"",
]

const DYNAMIC_PATTERNS: Array[String] = [
	"Loc\\.t\\(\"([A-Za-z0-9_.]*%[sd][A-Za-z0-9_.]*)\"",
	"Loc\\.tp\\(\"([A-Za-z0-9_.]*%[sd][A-Za-z0-9_.]*)\"",
	"has_key\\(\"([A-Za-z0-9_.]*%[sd][A-Za-z0-9_.]*)\"",
	"\"([A-Za-z0-9_]*%[sd][A-Za-z0-9_.]*)\"\\s*%",
	"\"([A-Za-z0-9_.]*%[sd][A-Za-z0-9_.]*)\" % \\[",
]

## Strings that look like keys but are developer-facing identifiers, not UI text.
const IGNORED_PREFIXES: Array[String] = [
	"res://", "user://", "127.0.0.1",
]


## Returns `{ key: "path:line" }` for every literal key referenced in code.
static func scan_static_keys() -> Dictionary:
	var literal := RegEx.create_from_string("|".join(LITERAL_PATTERNS))
	var found: Dictionary = {}
	for path: String in _gd_files():
		var text := _read(path)
		var line_number := 0
		for line: String in text.split("\n"):
			line_number += 1
			for match_result: RegExMatch in literal.search_all(line):
				var captured := _first_group(match_result)
				if captured.is_empty() or _is_ignored(captured):
					continue
				if not found.has(captured):
					found[captured] = "%s:%d" % [path, line_number]
	return found


## Returns `{ pattern: "path:line" }` for keys completed at runtime.
static func scan_dynamic_patterns() -> Dictionary:
	var dynamic := RegEx.create_from_string("|".join(DYNAMIC_PATTERNS))
	var found: Dictionary = {}
	for path: String in _gd_files():
		var text := _read(path)
		var line_number := 0
		for line: String in text.split("\n"):
			line_number += 1
			for match_result: RegExMatch in dynamic.search_all(line):
				var captured := _first_group(match_result)
				if captured.is_empty() or _is_ignored(captured):
					continue
				if not found.has(captured):
					found[captured] = "%s:%d" % [path, line_number]
	return found


static func _first_group(match_result: RegExMatch) -> String:
	for group_index: int in range(1, match_result.get_group_count()):
		var captured := match_result.get_string(group_index)
		if not captured.is_empty():
			return captured
	return ""


static func _is_ignored(value: String) -> bool:
	for prefix: String in IGNORED_PREFIXES:
		if value.begins_with(prefix):
			return true
	# Translation keys may contain a slash (`audio/master`); only URI-style or
	# path-like values are developer strings rather than keys.
	if value.contains(":"):
		return true
	return false


static func _gd_files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for dir: String in SCAN_DIRS:
		_collect(dir, files)
	return files


static func _collect(dir: String, files: PackedStringArray) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	handle.list_dir_begin()
	var entry := handle.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = handle.get_next()
			continue
		var path := "%s/%s" % [dir, entry]
		if handle.current_is_dir():
			_collect(path, files)
		elif entry.ends_with(".gd"):
			# The scanner's own pattern literals would show up as keys otherwise.
			if not path.ends_with("i18n_scanner.gd"):
				files.append(path)
		entry = handle.get_next()
	handle.list_dir_end()


static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
