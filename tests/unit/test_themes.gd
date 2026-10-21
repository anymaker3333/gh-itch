extends RefCounted
## Theme registry invariants: built-in packs, validation, import and restore.
##
## These tests mutate the live palette, so the suite always restores the theme
## that was active before it ran.


func suite_name() -> String:
	return "themes"


func run(h: TestHarness) -> void:
	var original := ThemeSvc.active_id()
	_check_builtins(h)
	_check_switching(h)
	ThemeSvc.select(original)
	_check_validation(h, original)
	_check_import_round_trip(h, original)
	ThemeSvc.select(original)


func _check_builtins(h: TestHarness) -> void:
	var ids: Array[String] = []
	for entry: Dictionary in ThemeSvc.theme_options():
		ids.append(String(entry.get("value", "")))
	h.check(ids.has("default"), "default theme is listed")
	h.check(ids.has("casino"), "casino theme is listed")
	var casino := ThemeSvc.colors_for("casino")
	h.equal(String(casino.get("accent", "")).to_lower(), "#e8b84a", "casino accent")
	h.equal(String(casino.get("bg_base", "")).to_lower(), "#0b1a12", "casino felt background")


func _check_switching(h: TestHarness) -> void:
	h.check(ThemeSvc.select("casino"), "casino theme can be selected")
	h.equal(Palette.ACCENT, Color("#e8b84a"), "palette follows casino theme")
	h.check(ThemeSvc.select("default"), "default theme can be selected")
	h.equal(Palette.ACCENT, Color("#4ea1ff"), "palette returns to default")
	var sample: Variant = JSON.parse_string(ThemeSvc.sample_json())
	h.check(sample is Dictionary, "exported sample is valid JSON")
	if sample is Dictionary:
		h.equal(String(sample.get("format", "")), "gamehub-theme/1", "sample format tag")
		h.check(sample.get("colors", null) is Dictionary, "sample contains colours")


func _check_validation(h: TestHarness, original: String) -> void:
	var invalid_path := "user://invalid-theme-test.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	file.store_string("{\"format\":\"wrong\",\"name\":\"Bad\",\"colors\":{}}")
	file.close()
	var result := ThemeSvc.import_theme(invalid_path)
	h.check(not bool(result.get("ok", true)), "wrong format is rejected")
	h.equal(ThemeSvc.active_id(), original, "rejected theme does not become active")

	var incomplete := "{\"format\":\"gamehub-theme/1\",\"name\":\"No accent\",\"colors\":{\"bg_base\":\"#111111\",\"bg_panel\":\"#222222\",\"text\":\"#ffffff\"}}"
	file = FileAccess.open(invalid_path, FileAccess.WRITE)
	file.store_string(incomplete)
	file.close()
	result = ThemeSvc.import_theme(invalid_path)
	h.check(not bool(result.get("ok", true)), "missing required colour is rejected")
	h.equal(String(result.get("error", "")), "theme.invalid_colors", "missing colour error key")
	DirAccess.remove_absolute(invalid_path)


func _check_import_round_trip(h: TestHarness, original: String) -> void:
	var source := "user://imported-theme-test.json"
	var data := {
		"format": "gamehub-theme/1",
		"name": "Test Palette",
		"colors": {
			"bg_base": "#101010",
			"bg_panel": "#202020",
			"text": "#f0f0f0",
			"accent": "#ff8800",
			"positive": "#00ff88",
		},
	}
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var result := ThemeSvc.import_theme(source)
	h.check(bool(result.get("ok", false)), "valid custom theme imports")
	var theme_id := String(result.get("id", ""))
	h.check(theme_id.begins_with("custom:"), "custom theme gets a namespaced id")
	h.equal(ThemeSvc.active_id(), theme_id, "imported theme becomes active")
	h.equal(Palette.ACCENT, Color("#ff8800"), "custom accent is applied")
	h.equal(Palette.POSITIVE, Color("#00ff88"), "custom optional colour is applied")
	h.check(ThemeSvc.delete_theme(theme_id), "custom theme can be deleted")
	h.equal(ThemeSvc.active_id(), "default", "deleting the active theme falls back")
	h.check(ThemeSvc.select(original), "original theme can be restored")
	DirAccess.remove_absolute(source)
