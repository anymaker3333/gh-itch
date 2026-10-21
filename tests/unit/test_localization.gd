extends RefCounted
## Localisation invariants: ten catalogues, no missing keys, no raw keys shown.
##
## The suite is the gate for "the UI never shows a raw key": it compares every
## literal key referenced in GDScript against the English catalogue, checks that
## each locale covers the complete key set (game string packs included) and that
## every game in the catalog provides a name, a description and its phase keys.


func suite_name() -> String:
	return "localisation"


func run(h: TestHarness) -> void:
	_check_locale_set(h)
	_check_english_catalogue(h)
	_check_runtime_keys(h)
	_check_coverage(h)
	_check_game_families(h)
	_check_no_raw_keys(h)


func _check_locale_set(h: TestHarness) -> void:
	var codes := Loc.locale_codes()
	h.equal(codes.size(), 10, "exactly ten locales must be supported")
	for code: String in ["en", "uk", "ru", "de", "zh_CN", "az", "be", "cs", "pl", "fr"]:
		h.check(codes.has(code), "locale %s is registered" % code)
		h.check(not Loc.native_name(code).is_empty(), "locale %s has a native name" % code)
		h.equal(Loc.native_name(code), _expected_native(code), "native name of %s" % code)


func _expected_native(code: String) -> String:
	match code:
		"en":
			return "English"
		"uk":
			return "Українська"
		"ru":
			return "Русский"
		"de":
			return "Deutsch"
		"zh_CN":
			return "中文"
		"az":
			return "Azərbaycanca"
		"be":
			return "Беларуская"
		"cs":
			return "Čeština"
		"pl":
			return "Polski"
		"fr":
			return "Français"
	return "?"


func _check_english_catalogue(h: TestHarness) -> void:
	var keys := Loc.catalogue_keys("en")
	h.greater(float(keys.size()), 300.0, "English catalogue must be substantial")
	h.check(Loc.has_key("app.name", "en"), "app.name exists")
	h.check(Loc.has_key("game.common.log", "en"), "game.common.log exists")


## Every key written as a literal in the sources must exist in English. Keys that
## exist only as plural forms (`.one` / `.other`) count as translated.
func _check_runtime_keys(h: TestHarness) -> void:
	var static_keys := I18nScanner.scan_static_keys()
	var missing: Array[String] = []
	for key: Variant in static_keys:
		if not _has_translation(String(key)):
			missing.append("%s (%s)" % [String(key), String(static_keys[key])])
	missing.sort()
	for entry: String in missing:
		h.check(false, "missing English string: %s" % entry)
	h.greater(float(static_keys.size()), 200.0, "scanner must find the UI keys")


func _has_translation(key: String) -> bool:
	return Loc.has_key(key, "en") or Loc.has_key(key + ".one", "en") or Loc.has_key(key + ".other", "en")


func _check_coverage(h: TestHarness) -> void:
	var report := Loc.coverage_report()
	for code: String in Loc.locale_codes():
		var entry: Dictionary = report.get(code, {})
		if entry.is_empty():
			h.check(false, "no coverage data for %s" % code)
			continue
		var missing: int = int(entry.get("missing", 9999))
		var percent: float = float(entry.get("percent", 0.0))
		h.greater(percent, 99.9, "locale %s must be fully translated (%.1f%%), %d keys missing" % [code, percent, missing])


## Names, descriptions and phase keys for every catalog entry.
func _check_game_families(h: TestHarness) -> void:
	for entry: GameEntry in Catalog.games():
		h.check(Loc.has_key(entry.name_key, "en"), "%s has a name" % entry.id)
		h.check(Loc.has_key(entry.desc_key, "en"), "%s has a description" % entry.id)
		h.no_raw_key(Loc.t(entry.name_key), "%s name" % entry.id)
		h.greater(float(Loc.t(entry.desc_key).length()), 20.0, "%s description is substantial" % entry.id)
		if not Session.engine_available(entry.id):
			continue
		var engine := Session.create_engine(entry.id)
		if engine == null:
			h.check(false, "%s engine cannot be instantiated" % entry.id)
			continue
		for phase: String in engine.phases():
			h.check(Loc.has_key("game.%s.phase.%s" % [entry.id, phase], "en"),
				"%s declares phase '%s' without a translation" % [entry.id, phase])


func _check_no_raw_keys(h: TestHarness) -> void:
	Loc.reset_missing_tracking()
	for key: Variant in I18nScanner.scan_static_keys():
		var text := Loc.t(String(key))
		h.no_raw_key(text, "static key must render as text")
		if text.is_empty():
			h.check(false, "key %s renders as empty text" % String(key))
	h.equal(Loc.missing_keys().size(), 0, "no key may fall back to English while playing in English")
