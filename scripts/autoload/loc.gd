extends Node
## Localization service (autoload `Loc`).
##
## Translation catalogues live in `res://data/i18n/<locale>.json` as flat
## `key -> text` maps. At boot the catalogues are converted into Godot
## [Translation] resources, registered with [TranslationServer] and selected with
## [method TranslationServer.set_locale]. UI code always uses [method Loc.t], so
## a missing string degrades to English, then to a humanised key - raw keys are
## never shown to players, and [method Loc.missing_keys] powers automated checks.

signal locale_changed(code: String)
signal translations_reloaded()

const I18N_DIR: String = "res://data/i18n/"
const FALLBACK_LOCALE: String = "en"
## The ten supported languages. `native` is shown in the UI exactly as the
## language writes its own name.
const LOCALES: Array[Dictionary] = [
	{"code": "en", "native": "English", "english": "English", "cjk": false},
	{"code": "uk", "native": "Українська", "english": "Ukrainian", "cjk": false},
	{"code": "ru", "native": "Русский", "english": "Russian", "cjk": false},
	{"code": "de", "native": "Deutsch", "english": "German", "cjk": false},
	{"code": "zh_CN", "native": "中文", "english": "Simplified Chinese", "cjk": true},
	{"code": "az", "native": "Azərbaycanca", "english": "Azerbaijani", "cjk": false},
	{"code": "be", "native": "Беларуская", "english": "Belarusian", "cjk": false},
	{"code": "cs", "native": "Čeština", "english": "Czech", "cjk": false},
	{"code": "pl", "native": "Polski", "english": "Polish", "cjk": false},
	{"code": "fr", "native": "Français", "english": "French", "cjk": false},
]

var current_locale: String = FALLBACK_LOCALE

var _translations: Dictionary = {}  # locale code -> Translation
var _raw: Dictionary = {}  # locale code -> Dictionary[String, String]
var _missing_keys: Dictionary = {}  # key -> count


func _ready() -> void:
	translations_reloaded.connect(_on_translations_reloaded)
	load_catalogues()
	var requested := Prefs.locale()
	if not set_locale(requested):
		Log.warn("Loc: requested locale unavailable, keeping fallback", {"requested": requested})
		set_locale(FALLBACK_LOCALE)


func _on_translations_reloaded() -> void:
	set_locale(current_locale)


# ------------------------------------------------------------------ catalogues

func load_catalogues() -> void:
	_translations.clear()
	_raw.clear()
	for entry: Dictionary in LOCALES:
		var code := String(entry.code)
		var path := "%s%s.json" % [I18N_DIR, code]
		var data := _read_json(path)
		if data.is_empty():
			Log.warn("Loc: catalogue missing or empty", {"locale": code, "path": path})
			continue
		# Game string packs: `data/i18n/<locale>/<namespace>.json` are merged over
		# the shell catalogue. Keeping per-game strings in their own pack means a
		# game can be added, translated and removed without touching the shell
		# catalogue or racing other games' translations.
		var packs := _load_packs(code)
		var strings: Dictionary = {}
		for key: Variant in data:
			strings[String(key)] = String(data[key])
		for key: Variant in packs:
			strings[String(key)] = String(packs[key])
		_raw[code] = strings
		var translation := Translation.new()
		translation.locale = code
		for key: String in strings:
			translation.add_message(key, strings[key])
		_translations[code] = translation
		TranslationServer.add_translation(translation)
	translation_count_check()


## Merges every JSON file inside `data/i18n/<locale>/` (game string packs).
func _load_packs(code: String) -> Dictionary:
	var merged: Dictionary = {}
	var dir := "%s%s" % [I18N_DIR, code]
	if not DirAccess.dir_exists_absolute(dir):
		return merged
	var files := DirAccess.get_files_at(dir)
	var names: Array = []
	for file: String in files:
		if file.ends_with(".json"):
			names.append(file)
	names.sort()
	for file: Variant in names:
		var data := _read_json("%s/%s" % [dir, String(file)])
		for key: Variant in data:
			merged[String(key)] = String(data[key])
	if not names.is_empty():
		Log.info("Loc: string packs merged", {"locale": code, "packs": names.size(), "keys": merged.size()})
	return merged


## Names of the string packs a locale provides (used by diagnostics and tests).
func pack_names(code: String) -> PackedStringArray:
	var dir := "%s%s" % [I18N_DIR, code]
	var out: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names: Array = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			names.append(file)
	names.sort()
	for name: Variant in names:
		out.append(String(name))
	return out


func translation_count_check() -> void:
	var missing_locales: PackedStringArray = []
	for entry: Dictionary in LOCALES:
		if not _translations.has(String(entry.code)):
			missing_locales.append(String(entry.code))
	if not missing_locales.is_empty():
		Log.error("Loc: some catalogues failed to load", {"locales": missing_locales})


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		Log.error("Loc: JSON parse error", {"path": path, "line": parser.get_error_line(), "msg": parser.get_error_message()})
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


# ------------------------------------------------------------------- locale API

func locale_codes() -> PackedStringArray:
	var out: PackedStringArray = []
	for entry: Dictionary in LOCALES:
		out.append(String(entry.code))
	return out


func is_supported(code: String) -> bool:
	return locale_codes().has(code)


func native_name(code: String) -> String:
	for entry: Dictionary in LOCALES:
		if String(entry.code) == code:
			return String(entry.native)
	return code


func set_locale(code: String, persist: bool = true) -> bool:
	if not _translations.has(code):
		Log.warn("Loc: locale not loaded", {"locale": code})
		return false
	if current_locale == code:
		if persist:
			Prefs.set_value("general/locale", code)
		return true
	current_locale = code
	TranslationServer.set_locale(code)
	if persist:
		Prefs.set_value("general/locale", code)
	Log.info("Loc: locale applied", {"locale": code})
	locale_changed.emit(code)
	return true


# --------------------------------------------------------------- translations

## Translates `key`, substituting `{placeholders}` from `args`.
func t(key: String, args: Dictionary = {}) -> String:
	var text := _translate(key)
	if not args.is_empty():
		text = text.format(args, "{_}")
	return text


## Plural-aware lookup. Catalogues may provide `<key>.one`, `.few`, `.many`
## and `.other`; suffixes not present fall back to `.other`, then to the bare
## key. Slavic locales need the `few` category for counts 2-4.
func tp(key: String, count: int, args: Dictionary = {}) -> String:
	var suffix := _plural_suffix(count)
	var attempted: Array[String] = [suffix]
	for fallback: String in [".other", ".few", ".many", ".one"]:
		if not attempted.has(fallback):
			attempted.append(fallback)
	var text := ""
	for candidate: String in attempted:
		var plural_key := key + candidate
		if has_key(plural_key, current_locale):
			text = _translate(plural_key)
			break
		if has_key(plural_key, FALLBACK_LOCALE):
			text = _raw[FALLBACK_LOCALE][plural_key]
			break
	if text.is_empty():
		text = _translate(key)
	var merged: Dictionary = args.duplicate()
	merged["count"] = count
	return text.format(merged, "{_}")


func _plural_suffix(count: int) -> String:
	var n := absi(count)
	var mod10 := n % 10
	var mod100 := n % 100
	match current_locale:
		"uk", "ru", "be":
			if mod10 == 1 and mod100 != 11:
				return ".one"
			if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
				return ".few"
			return ".many"
		"pl":
			if n == 1:
				return ".one"
			if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
				return ".few"
			return ".many"
		"cs":
			if n == 1:
				return ".one"
			if n >= 2 and n <= 4:
				return ".few"
			return ".many"
		_:
			return ".one" if n == 1 else ".other"


func _translate(key: String) -> String:
	var value := String(TranslationServer.translate(key))
	if value != key and not value.is_empty():
		return value
	# Plural-only entries (`<key>.one` / `<key>.other`) are valid answers to a
	# request for the bare key (a header may show the same text a count does).
	for suffix: String in [".other", ".one"]:
		var plural := String(TranslationServer.translate(key + suffix))
		if plural != key + suffix and not plural.is_empty():
			return plural
	# Fallback chain: English catalogue, then a humanised key (never a raw key).
	if _raw.has(FALLBACK_LOCALE):
		var english: Dictionary = _raw[FALLBACK_LOCALE]
		if english.has(key):
			_note_missing(key)
			return String(english[key])
		for suffix: String in [".other", ".one"]:
			if english.has(key + suffix):
				return String(english[key + suffix])
	_note_missing(key)
	Log.warn("Loc: missing translation key", {"key": key, "locale": current_locale})
	return humanize_key(key)


## Turns `game.chess.name` into `Chess` so that untranslated data never shows a
## raw key to a player.
func humanize_key(key: String) -> String:
	var tail := key.get_slice(".", key.get_slice_count(".") - 1)
	tail = tail.replace("_", " ").strip_edges()
	if tail.is_empty():
		return key
	return tail.substr(0, 1).to_upper() + tail.substr(1)


func has_key(key: String, locale: String = "") -> bool:
	var code := locale if not locale.is_empty() else current_locale
	if not _raw.has(code):
		return false
	var table: Dictionary = _raw[code]
	return table.has(key)


func _note_missing(key: String) -> void:
	_missing_keys[key] = int(_missing_keys.get(key, 0)) + 1


func missing_keys() -> PackedStringArray:
	var keys: Array = _missing_keys.keys()
	keys.sort()
	var out: PackedStringArray = []
	for key: Variant in keys:
		out.append(String(key))
	return out


func reset_missing_tracking() -> void:
	_missing_keys.clear()


## Per-locale coverage statistics, used by Settings (informational) and tests.
func coverage_report() -> Dictionary:
	var reference: Dictionary = _raw.get(FALLBACK_LOCALE, {})
	var report: Dictionary = {}
	for entry: Dictionary in LOCALES:
		var code := String(entry.code)
		var table: Dictionary = _raw.get(code, {})
		var missing: PackedStringArray = []
		for key: Variant in reference:
			if not table.has(String(key)):
				missing.append(String(key))
		var translated := maxi(0, reference.size() - missing.size())
		report[code] = {
			"total_keys": reference.size(),
			"translated": translated,
			"missing": missing.size(),
			"missing_keys": missing,
			"percent": 100.0 if reference.is_empty() else (float(translated) / float(reference.size())) * 100.0,
		}
	return report


func catalogue_keys(locale: String = FALLBACK_LOCALE) -> PackedStringArray:
	var table: Dictionary = _raw.get(locale, {})
	var out: PackedStringArray = []
	for key: Variant in table:
		out.append(String(key))
	out.sort()
	return out
