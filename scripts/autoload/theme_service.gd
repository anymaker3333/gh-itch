extends Node
## Menu theme registry (autoload `ThemeSvc`).
##
## Themes are plain JSON files. Built-in packs live in `res://data/themes`;
## user packs are imported into `user://themes` and can be selected in
## Settings > Appearance. A theme may override any subset of [Palette] tokens,
## but must provide the four structural colours (`bg_base`, `bg_panel`, `text`
## and `accent`).

signal theme_changed(theme_id: String)

const FORMAT: String = "gamehub-theme/1"
const DEFAULT_ID: String = "default"
const CASINO_ID: String = "casino"
const BUILTIN_DIR: String = "res://data/themes"
const CUSTOM_DIR: String = "user://themes"
const MAX_NAME_LENGTH: int = 48

const REQUIRED_COLORS: Array[String] = ["bg_base", "bg_panel", "text", "accent"]

var _themes: Dictionary = {}
var _default_colors: Dictionary = {}
var _active_id: String = DEFAULT_ID


func _ready() -> void:
	_default_colors = Palette.snapshot()
	_themes[DEFAULT_ID] = {
		"id": DEFAULT_ID,
		"name": "Game Hub",
		"name_key": "theme.default",
		"colors": {},
		"builtin": true,
		"path": "",
	}
	_load_builtin(CASINO_ID, "theme.casino")
	_scan_custom()
	Prefs.setting_changed.connect(_on_setting_changed)
	var saved := String(Prefs.get_value("appearance/theme_id", DEFAULT_ID))
	if not _themes.has(saved):
		saved = DEFAULT_ID
	_activate(saved)
	Log.info("ThemeSvc: ready", {"theme": _active_id, "installed": _themes.size()})


# ------------------------------------------------------------------- queries

func active_id() -> String:
	return _active_id


func active_name() -> String:
	return display_name(_active_id)


func display_name(theme_id: String) -> String:
	var data: Dictionary = _themes.get(theme_id, {})
	if data.is_empty():
		return theme_id
	var name_key := String(data.get("name_key", ""))
	if not name_key.is_empty():
		return Loc.t(name_key)
	return String(data.get("name", theme_id))


func is_builtin(theme_id: String) -> bool:
	return bool((_themes.get(theme_id, {}) as Dictionary).get("builtin", false))


func theme_options() -> Array:
	var options: Array = []
	var custom_ids: Array[String] = []
	for theme_id: Variant in _themes:
		var id := String(theme_id)
		if id.begins_with("custom:"):
			custom_ids.append(id)
	custom_ids.sort_custom(func(a: String, b: String) -> bool:
		return display_name(a).naturalnocasecmp_to(display_name(b)) < 0
	)
	for theme_id: String in [DEFAULT_ID, CASINO_ID]:
		if _themes.has(theme_id):
			options.append({"label": display_name(theme_id), "value": theme_id})
	for theme_id: String in custom_ids:
		options.append({"label": display_name(theme_id), "value": theme_id})
	return options


## Full colour set used by a theme after merging with the built-in defaults.
func colors_for(theme_id: String) -> Dictionary:
	var data: Dictionary = _themes.get(theme_id, {})
	if data.is_empty():
		return _default_colors.duplicate()
	var merged := _default_colors.duplicate()
	var colors: Dictionary = data.get("colors", {})
	merged.merge(colors, true)
	return merged


func custom_dir() -> String:
	return CUSTOM_DIR


## Pretty-printed starter file, including every token at its default value.
func sample_json() -> String:
	return JSON.stringify({
		"format": FORMAT,
		"name": "My Theme",
		"colors": _default_colors,
	}, "\t")


# ------------------------------------------------------------------ mutation

func select(theme_id: String) -> bool:
	if not _themes.has(theme_id):
		return false
	_activate(theme_id)
	Prefs.set_value("appearance/theme_id", theme_id)
	theme_changed.emit(theme_id)
	return true


## Import a JSON file chosen by the user. The file is copied into the user data
## directory first, so later changes to the original file do not break the theme.
func import_theme(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "theme.invalid_file"}
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {"ok": false, "error": "theme.invalid_file"}
	var parsed := _parse_theme(raw, "")
	if not bool(parsed.get("ok", false)):
		return parsed
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var slug := _slug(String(parsed["name"]))
	var dest := "%s/%s.json" % [CUSTOM_DIR, slug]
	var suffix := 2
	while FileAccess.file_exists(dest):
		dest = "%s/%s-%d.json" % [CUSTOM_DIR, slug, suffix]
		suffix += 1
	var output := FileAccess.open(dest, FileAccess.WRITE)
	if output == null:
		return {"ok": false, "error": "theme.export_failed"}
	output.store_string(raw)
	output.close()
	_scan_custom()
	var theme_id := "custom:" + dest.get_file().get_basename()
	if not _themes.has(theme_id):
		return {"ok": false, "error": "theme.invalid_format"}
	select(theme_id)
	return {"ok": true, "id": theme_id, "name": display_name(theme_id)}


func delete_theme(theme_id: String) -> bool:
	if is_builtin(theme_id) or not theme_id.begins_with("custom:"):
		return false
	var path := String((_themes.get(theme_id, {}) as Dictionary).get("path", ""))
	if not path.is_empty():
		DirAccess.remove_absolute(path)
	_scan_custom()
	if _active_id == theme_id:
		select(DEFAULT_ID)
	return true


# ---------------------------------------------------------------- internals

func _on_setting_changed(path: String, value: Variant) -> void:
	if path != "appearance/theme_id":
		return
	var theme_id := String(value)
	if theme_id == _active_id or not _themes.has(theme_id):
		return
	_activate(theme_id)
	theme_changed.emit(theme_id)


func _activate(theme_id: String) -> void:
	_active_id = theme_id
	Palette.apply(colors_for(theme_id))
	ThemeBuilder.invalidate()


func _load_builtin(theme_id: String, name_key: String) -> void:
	var path := "%s/%s.json" % [BUILTIN_DIR, theme_id]
	var raw := FileAccess.get_file_as_string(path)
	var parsed := _parse_theme(raw, theme_id, true)
	if not bool(parsed.get("ok", false)):
		Log.warn("ThemeSvc: built-in theme unavailable", {"theme": theme_id, "error": parsed.get("error", "")})
		return
	parsed["name_key"] = name_key
	parsed["id"] = theme_id
	parsed["builtin"] = true
	parsed["path"] = path
	_themes[theme_id] = parsed


func _scan_custom() -> void:
	var stale: Array[String] = []
	for theme_id: Variant in _themes:
		if String(theme_id).begins_with("custom:"):
			stale.append(String(theme_id))
	for theme_id: String in stale:
		_themes.erase(theme_id)
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var dir := DirAccess.open(CUSTOM_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file: String in files:
		if file.get_extension().to_lower() != "json":
			continue
		var path := "%s/%s" % [CUSTOM_DIR, file]
		var raw := FileAccess.get_file_as_string(path)
		var parsed := _parse_theme(raw, "custom:" + file.get_basename())
		if not bool(parsed.get("ok", false)):
			Log.warn("ThemeSvc: skipped invalid custom theme", {"file": file, "error": parsed.get("error", "")})
			continue
		parsed["id"] = "custom:" + file.get_basename()
		parsed["builtin"] = false
		parsed["path"] = path
		_themes[String(parsed["id"])] = parsed


func _parse_theme(raw: String, theme_id: String, builtin: bool = false) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "theme.invalid_format"}
	var data: Dictionary = parsed
	if String(data.get("format", "")) != FORMAT:
		return {"ok": false, "error": "theme.invalid_format"}
	var name := String(data.get("name", "")).strip_edges()
	if name.is_empty() or name.length() > MAX_NAME_LENGTH:
		return {"ok": false, "error": "theme.invalid_format"}
	if not (data.get("colors", null) is Dictionary):
		return {"ok": false, "error": "theme.invalid_colors"}
	var source: Dictionary = data.get("colors", {})
	var colors: Dictionary = {}
	for key: String in Palette.THEME_KEYS:
		if not source.has(key):
			continue
		var text := String(source[key]).strip_edges()
		if not Color.html_is_valid(text):
			return {"ok": false, "error": "theme.invalid_colors", "key": key}
		colors[key] = text.to_lower()
	for key: String in REQUIRED_COLORS:
		if not colors.has(key):
			return {"ok": false, "error": "theme.invalid_colors", "key": key}
	return {"ok": true, "id": theme_id, "name": name, "colors": colors, "builtin": builtin}


func _slug(name: String) -> String:
	var lower := name.to_lower()
	var out := ""
	for index: int in range(lower.length()):
		var ch := lower.substr(index, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789-_".contains(ch):
			out += ch
		elif ch == " ":
			out += "-"
	out = out.strip_edges().trim_prefix("-").trim_suffix("-")
	if out.is_empty():
		out = "theme"
	return out.substr(0, 40)
