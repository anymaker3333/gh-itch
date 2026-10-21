extends Node
## Central diagnostics/logging service (autoload `Log`).
##
## Collects structured log entries in memory for in-app diagnostics, mirrors them to
## the console and appends them to a rolling log file under `user://logs/`.
## Game code must log through this service instead of `print()` so that the QA
## tooling and the in-app diagnostics screen can see the same information.

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

signal message_logged(entry: Dictionary)
signal error_logged(entry: Dictionary)

const MAX_ENTRIES: int = 800
const LEVEL_NAMES: PackedStringArray = ["DEBUG", "INFO", "WARN", "ERROR"]

var min_level: Level = Level.INFO
var mirror_to_console: bool = true

var _entries: Array[Dictionary] = []
var _log_file: FileAccess = null
var _error_count: int = 0
var _warn_count: int = 0
var _session_start_ms: int = 0


func _ready() -> void:
	_session_start_ms = Time.get_ticks_msec()
	_open_log_file()
	info("Game Hub starting", {
		"engine": Engine.get_version_info().get("string", "?"),
		"platform": OS.get_name(),
		"locale": OS.get_locale(),
	})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close_log_file()


func debug(message: String, context: Dictionary = {}) -> void:
	_write(Level.DEBUG, message, context)


func info(message: String, context: Dictionary = {}) -> void:
	_write(Level.INFO, message, context)


func warn(message: String, context: Dictionary = {}) -> void:
	_write(Level.WARN, message, context)


func error(message: String, context: Dictionary = {}) -> void:
	_write(Level.ERROR, message, context)


func error_count() -> int:
	return _error_count


func warn_count() -> int:
	return _warn_count


func uptime_seconds() -> float:
	return float(Time.get_ticks_msec() - _session_start_ms) / 1000.0


## Returns log entries, newest first.
func get_entries(level_filter: int = -1, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		if level_filter >= 0 and int(entry.level) != level_filter:
			continue
		out.append(entry)
		if out.size() >= limit:
			break
	return out


func get_entries_ordered(level_filter: int = -1, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if level_filter >= 0 and int(entry.level) != level_filter:
			continue
		out.append(entry)
		if out.size() >= limit:
			break
	return out


func clear() -> void:
	_entries.clear()
	_error_count = 0
	_warn_count = 0


## Human readable diagnostics dump, used by the diagnostics screen and QA tools.
func build_report() -> String:
	var lines: PackedStringArray = []
	lines.append("Game Hub diagnostics report")
	lines.append("==========================")
	lines.append("engine: %s" % Engine.get_version_info().get("string", "?"))
	lines.append("platform: %s (%s)" % [OS.get_name(), OS.get_version()])
	lines.append("uptime: %.1fs" % uptime_seconds())
	lines.append("errors: %d  warnings: %d" % [_error_count, _warn_count])
	lines.append("log file: %s" % _log_path())
	lines.append("")
	lines.append("Recent messages:")
	for entry: Dictionary in get_entries():
		lines.append("  [%s] %s %s" % [LEVEL_NAMES[int(entry.level)], entry.message, entry.context])
	return "\n".join(lines)


func _write(level: Level, message: String, context: Dictionary) -> void:
	if level == Level.WARN:
		_warn_count += 1
	elif level == Level.ERROR:
		_error_count += 1
	var entry: Dictionary = {
		"level": int(level),
		"level_name": LEVEL_NAMES[int(level)],
		"message": message,
		"context": context.duplicate(true),
		"time_ms": Time.get_ticks_msec(),
		"uptime": uptime_seconds(),
	}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)

	var line := "[%8.3f][%s] %s %s" % [entry.uptime, entry.level_name, message, _context_to_string(context)]
	if level >= min_level and mirror_to_console:
		if level >= Level.WARN:
			printerr(line)
		else:
			print(line)
	if _log_file != null:
		_log_file.store_line(line)
		_log_file.flush()

	if level == Level.ERROR:
		error_logged.emit(entry)
	message_logged.emit(entry)


func _context_to_string(context: Dictionary) -> String:
	if context.is_empty():
		return ""
	return "| " + JSON.stringify(context)


func _log_path() -> String:
	return "user://logs/gamehub.log"


func _open_log_file() -> void:
	DirAccess.make_dir_recursive_absolute(_log_path().get_base_dir())
	# Rotate the previous session log so the file never grows unbounded.
	if FileAccess.file_exists(_log_path()):
		DirAccess.copy_absolute(_log_path(), _log_path() + ".prev")
	_log_file = FileAccess.open(_log_path(), FileAccess.WRITE)
	if _log_file == null:
		push_warning("Log: could not open log file at %s" % _log_path())


func _close_log_file() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file.close()
		_log_file = null
