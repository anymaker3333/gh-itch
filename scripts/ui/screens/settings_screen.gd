extends ScreenBase
## Settings screen with sections: General, Display, Language, Audio, Accessibility,
## plus diagnostics entry points. The route selects the initial section, so
## `settings_display`, `settings_language`, ... all open the same screen.

enum Section { GENERAL = 0, DISPLAY = 1, LANGUAGE = 2, AUDIO = 3, ACCESSIBILITY = 4, APPEARANCE = 5 }

const SECTION_KEYS: Array[String] = [
	"settings.section_general",
	"settings.section_display",
	"settings.section_language",
	"settings.section_audio",
	"settings.section_accessibility",
	"settings.section_appearance",
]
const SECTION_ROUTES: Array[String] = [
	Nav.ROUTE_SETTINGS,
	Nav.ROUTE_DISPLAY_SETTINGS,
	Nav.ROUTE_LANGUAGE_SETTINGS,
	Nav.ROUTE_AUDIO_SETTINGS,
	Nav.ROUTE_ACCESSIBILITY,
]

var section: Section = Section.GENERAL
var _section_list: VBoxContainer
var _content: VBoxContainer
var _revert_banner: PanelContainer
var _revert_label: Label
var _countdown: SceneTreeTimer = null


func build() -> void:
	title_key = "settings.title"
	subtitle_key = "settings.subtitle"
	var layout := UI.row(18)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.max_width(UI.margin_xy(layout, 24, 20, 24, 24), 1200, true))

	var nav_panel := UI.panel("CardPanel")
	nav_panel.custom_minimum_size = Vector2(260, 0)
	var nav_box := UI.column(6)
	nav_box.add_theme_constant_override("separation", 6)
	nav_panel.add_child(UI.margin_container(nav_box, 12))
	_section_list = nav_box
	layout.add_child(nav_panel)

	var right := UI.column(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(right)

	_revert_banner = UI.panel("AccentPanel")
	var banner_box := UI.row(12)
	_revert_label = UI.label("", "Body")
	_revert_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_box.add_child(_revert_label)
	banner_box.add_child(UI.button(Loc.t("display.keep"), "PositiveButton", func() -> void:
		DisplayManager.confirm_pending()
		_hide_revert_banner()
	))
	banner_box.add_child(UI.button(Loc.t("display.revert"), "DangerButton", func() -> void:
		DisplayManager.revert_pending("user")
		_hide_revert_banner()
		_rebuild()
	))
	_revert_banner.add_child(UI.margin_container(banner_box, 12))
	_revert_banner.visible = false
	right.add_child(_revert_banner)

	_content = UI.column(14)
	var scroll := UI.scroll(_content)
	right.add_child(scroll)
	DisplayManager.add_listener(_on_display_event)


func on_enter() -> void:
	section = _section_from_route(Nav.current_route())
	if params.has("section"):
		section = clampi(int(params["section"]), 0, Section.size() - 1)
	_rebuild()


func _section_from_route(route: String) -> Section:
	match route:
		Nav.ROUTE_DISPLAY_SETTINGS:
			return Section.DISPLAY
		Nav.ROUTE_LANGUAGE_SETTINGS:
			return Section.LANGUAGE
		Nav.ROUTE_AUDIO_SETTINGS:
			return Section.AUDIO
		Nav.ROUTE_ACCESSIBILITY:
			return Section.ACCESSIBILITY
		_:
			return Section.GENERAL


func _rebuild() -> void:
	_build_section_list()
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match section:
		Section.DISPLAY:
			_build_display()
		Section.LANGUAGE:
			_build_language()
		Section.AUDIO:
			_build_audio()
		Section.ACCESSIBILITY:
			_build_accessibility()
		Section.APPEARANCE:
			_build_appearance()
		_:
			_build_general()
	_refresh_revert_banner()


func _build_section_list() -> void:
	for child: Node in _section_list.get_children():
		_section_list.remove_child(child)
		child.queue_free()
	for index: int in range(SECTION_KEYS.size()):
		var target := index
		var button := UI.button(Loc.t(SECTION_KEYS[index]), "SidebarButton", func() -> void:
			section = target as Section
			_rebuild()
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 38)
		if target == int(section):
			button.add_theme_stylebox_override("normal", ThemeBuilder.flat(Palette.tint(Palette.ACCENT, 0.18), Palette.tint(Palette.ACCENT, 0.4), 1, ThemeBuilder.RADIUS, 12))
			button.add_theme_color_override("font_color", Palette.TEXT)
		_section_list.add_child(button)
	_section_list.add_child(UI.divider())
	var diagnostics_button := UI.button(Loc.t("settings.open_diagnostics"), "GhostButton", func() -> void:
		Nav.go(Nav.ROUTE_DIAGNOSTICS)
	)
	diagnostics_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	diagnostics_button.custom_minimum_size = Vector2(0, 34)
	_section_list.add_child(diagnostics_button)
	var about_button := UI.button(Loc.t("settings.open_about"), "GhostButton", func() -> void:
		Nav.go(Nav.ROUTE_ABOUT)
	)
	about_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	about_button.custom_minimum_size = Vector2(0, 34)
	_section_list.add_child(about_button)


# ------------------------------------------------------------------- general

func _build_general() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("settings.profile_title"), Loc.t("settings.profile_hint")))
	var name_callback := func(value: String) -> void:
		var name_value := value if not value.strip_edges().is_empty() else Prefs.profile_name()
		Prefs.set_value("profile/display_name", name_value)
		Notify.success(Loc.t("settings.saved"))
		_rebuild()
	var rename := func() -> void:
		Notify.prompt(Loc.t("settings.display_name_prompt"), Loc.t("settings.display_name_placeholder"), Prefs.profile_name(), name_callback)
	var name_button := UI.button(Prefs.profile_name(), "Button", rename)
	name_button.custom_minimum_size = Vector2(240, 0)
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(UI.form_row(
		Loc.t("settings.display_name"),
		UI.row(10, [name_button]),
		Loc.t("settings.display_name_hint")
	))
	panel.add_child(UI.divider())
	panel.add_child(UI.toggle(Loc.t("settings.confirm_exit"), bool(Prefs.get_value("general/confirm_on_exit", true)), func(value: bool) -> void:
		Prefs.set_value("general/confirm_on_exit", value)
	))
	panel.add_child(UI.toggle(Loc.t("settings.show_development"), bool(Prefs.get_value("general/show_development_titles", true)), func(value: bool) -> void:
		Prefs.set_value("general/show_development_titles", value)
	))
	panel.add_child(UI.divider())
	panel.add_child(UI.section_header(Loc.t("settings.storage_title"), Loc.t("settings.storage_hint")))
	panel.add_child(UI.kv_row(Loc.t("settings.settings_file"), ProjectSettings.globalize_path(Prefs.SETTINGS_PATH)))
	panel.add_child(UI.kv_row(Loc.t("settings.catalog_games"), str(Catalog.count())))
	panel.add_child(UI.kv_row(Loc.t("settings.languages"), str(Loc.locale_codes().size())))
	panel.add_child(UI.kv_row(Loc.t("settings.version"), String(ProjectSettings.get_setting("application/config/version", ""))))
	var actions := UI.row(10)
	actions.add_child(UI.button(Loc.t("settings.reset_all"), "DangerButton", func() -> void:
		Notify.confirm(Loc.t("settings.reset_all"), Loc.t("settings.reset_all_confirm"), Loc.t("settings.reset_all"), func(accepted: bool) -> void:
			if accepted:
				Prefs.reset_to_defaults()
				Loc.set_locale(String(Prefs.get_value("general/locale", "en")))
				DisplayManager.apply_from_prefs()
				Audio.apply_volumes()
				Notify.success(Loc.t("settings.reset_done"))
				_rebuild()
		, Loc.t("common.cancel"), true)
	))
	actions.add_child(UI.button(Loc.t("settings.clear_recent"), "GhostButton", func() -> void:
		Prefs.clear_recent()
		Notify.success(Loc.t("settings.recent_cleared"))
	))
	panel.add_child(actions)
	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


# ---------------------------------------------------------------- appearance

func _build_appearance() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("theme.title"), Loc.t("theme.hint")))
	var options := ThemeSvc.theme_options()
	var choose_callback := func(value: String) -> void:
		if ThemeSvc.select(value):
			Notify.success(Loc.t("theme.applied", {"name": ThemeSvc.active_name()}))
			_rebuild()
		else:
			Notify.error(Loc.t("theme.invalid_format"))
	panel.add_child(UI.form_row(
		Loc.t("theme.choose"),
		UI.dropdown(options, ThemeSvc.active_id(), choose_callback),
		Loc.t("theme.choose_hint")
	))
	var current := UI.kv_row(Loc.t("theme.current"), ThemeSvc.active_name())
	current.add_child(UI.chip(
		Loc.t("theme.builtin") if ThemeSvc.is_builtin(ThemeSvc.active_id()) else Loc.t("theme.custom"),
		Palette.ACCENT
	))
	panel.add_child(current)

	# A compact live swatch strip makes the active palette obvious without
	# leaving the settings page.
	panel.add_child(UI.label(Loc.t("theme.preview"), "Caption"))
	var colors := ThemeSvc.colors_for(ThemeSvc.active_id())
	var swatches := UI.flow(6, 6)
	for key: String in ["bg_deepest", "bg_base", "bg_panel", "bg_elevated", "accent", "accent_hover", "text", "text_muted"]:
		var swatch := PanelContainer.new()
		swatch.add_theme_stylebox_override("panel", ThemeBuilder.flat(
			Color(String(colors.get(key, "#000000"))), Palette.BORDER_STRONG, 1, 6, 0))
		swatch.custom_minimum_size = Vector2(48, 22)
		swatch.tooltip_text = key
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatches.add_child(swatch)
	panel.add_child(swatches)
	panel.add_child(UI.divider())
	panel.add_child(UI.section_header(Loc.t("theme.custom_title"), Loc.t("theme.custom_hint")))

	var actions := UI.flow(10, 8)
	actions.add_child(UI.button(Loc.t("theme.upload"), "PrimaryButton", _open_theme_upload))
	if ThemeSvc.active_id().begins_with("custom:"):
		actions.add_child(UI.button(Loc.t("theme.delete"), "DangerOutline", _delete_active_theme))
	actions.add_child(UI.button(Loc.t("theme.export_example"), "Button", _export_sample_theme))
	panel.add_child(actions)
	panel.add_child(UI.kv_row(Loc.t("theme.folder"), ProjectSettings.globalize_path(ThemeSvc.custom_dir())))
	panel.add_child(UI.label(Loc.t("theme.format_hint"), "Small"))

	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


func _open_theme_upload() -> void:
	var dialog := FileDialog.new()
	dialog.title = Loc.t("theme.upload")
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.current_dir = _dialog_start_dir()
	dialog.filters = PackedStringArray(["*.json ; " + Loc.t("theme.upload_hint")])
	dialog.min_size = Vector2i(860, 560)
	dialog.file_selected.connect(func(path: String) -> void:
		var result := ThemeSvc.import_theme(path)
		if bool(result.get("ok", false)):
			Notify.success(Loc.t("theme.imported", {"name": String(result.get("name", ""))}))
			_rebuild()
		else:
			var error_key := String(result.get("error", "theme.invalid_format"))
			Notify.error(Loc.t(error_key, {"key": String(result.get("key", ""))}))
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _dialog_start_dir() -> String:
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if not downloads.is_empty() and DirAccess.dir_exists_absolute(downloads):
		return downloads
	var home := OS.get_environment("HOME")
	return home if not home.is_empty() else ProjectSettings.globalize_path("user://")


func _delete_active_theme() -> void:
	var theme_id := ThemeSvc.active_id()
	if not theme_id.begins_with("custom:"):
		return
	var on_confirmed := func(accepted: bool) -> void:
		if not accepted:
			return
		ThemeSvc.delete_theme(theme_id)
		Notify.success(Loc.t("theme.deleted"))
		_rebuild()
	Notify.confirm(
		Loc.t("theme.delete"),
		Loc.t("theme.delete_confirm", {"name": ThemeSvc.display_name(theme_id)}),
		Loc.t("theme.delete"),
		on_confirmed,
		Loc.t("common.cancel"),
		true
	)


func _export_sample_theme() -> void:
	var dialog := FileDialog.new()
	dialog.title = Loc.t("theme.export_example")
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.current_dir = _dialog_start_dir()
	dialog.filters = PackedStringArray(["*.json ; " + Loc.t("theme.upload_hint")])
	dialog.current_file = "gamehub-theme.json"
	dialog.min_size = Vector2i(860, 560)
	dialog.file_selected.connect(func(path: String) -> void:
		var target := path if path.get_extension().to_lower() == "json" else path + ".json"
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			Notify.error(Loc.t("theme.export_failed"))
		else:
			file.store_string(ThemeSvc.sample_json())
			file.close()
			Notify.success(Loc.t("theme.exported", {"path": target}))
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


# ------------------------------------------------------------------- display

func _fps_text(value: int) -> String:
	if value <= 0:
		return Loc.t("display.max_fps_unlimited")
	return Loc.t("display.max_fps_value", {"value": value})


func _build_display() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("display.title"), Loc.t("display.hint")))
	panel.add_child(UI.kv_row(Loc.t("display.current"), DisplayManager.display_summary()))

	var mode_callback := func(value: String) -> void:
		_apply_display(int(value), Vector2i(Prefs.window_width(), Prefs.window_height()))
	panel.add_child(UI.form_row(
		Loc.t("display.mode"),
		UI.dropdown([
			{"label": Loc.t("display.mode_windowed"), "value": str(DisplayManager.MODE_WINDOWED)},
			{"label": Loc.t("display.mode_fullscreen"), "value": str(DisplayManager.MODE_FULLSCREEN)},
			{"label": Loc.t("display.mode_borderless"), "value": str(DisplayManager.MODE_BORDERLESS)},
		], str(Prefs.window_mode()), mode_callback),
		Loc.t("display.mode_hint")
	))

	var resolutions: Array[Vector2i] = DisplayManager.available_resolutions()
	var resolution_entries: Array = []
	for size: Vector2i in resolutions:
		resolution_entries.append({"label": "%d × %d" % [size.x, size.y], "value": "%dx%d" % [size.x, size.y]})
	var current := "%dx%d" % [Prefs.window_width(), Prefs.window_height()]
	var resolution_callback := func(value: String) -> void:
		var parts := value.split("x")
		_apply_display(Prefs.window_mode(), Vector2i(int(parts[0]), int(parts[1])))
	panel.add_child(UI.form_row(
		Loc.t("display.resolution"),
		UI.dropdown(resolution_entries, current, resolution_callback),
		Loc.t("display.resolution_hint")
	))

	if DisplayServer.get_screen_count() > 1:
		var screens: Array = []
		for index: int in range(DisplayServer.get_screen_count()):
			var size := DisplayServer.screen_get_size(index)
			screens.append({"label": "%d (%d×%d)" % [index + 1, size.x, size.y], "value": str(index)})
		var screen_callback := func(value: String) -> void:
			Prefs.set_value("display/screen", int(value))
			_apply_display(Prefs.window_mode(), Vector2i(Prefs.window_width(), Prefs.window_height()))
		panel.add_child(UI.form_row(
			Loc.t("display.screen"),
			UI.dropdown(screens, str(Prefs.screen_index()), screen_callback)
		))

	var vsync_callback := func(value: String) -> void:
		Prefs.set_value("display/vsync", int(value))
		DisplayServer.window_set_vsync_mode(int(value))
	panel.add_child(UI.form_row(
		Loc.t("display.vsync"),
		UI.dropdown([
			{"label": Loc.t("display.vsync_disabled"), "value": "0"},
			{"label": Loc.t("display.vsync_enabled"), "value": "1"},
			{"label": Loc.t("display.vsync_adaptive"), "value": "2"},
			{"label": Loc.t("display.vsync_mailbox"), "value": "3"},
		], str(Prefs.get_value("display/vsync", 1)), vsync_callback)
	))

	var fps_value := int(Prefs.get_value("display/max_fps", 0))
	var fps_label := UI.value_label(_fps_text(fps_value), 84)
	var fps_callback := func(value: float) -> void:
		Prefs.set_value("display/max_fps", int(value))
		Engine.max_fps = int(value)
		fps_label.text = _fps_text(int(value))
	var fps_slider := UI.slider(0, 240, 10, float(Prefs.get_value("display/max_fps", 0)), fps_callback)
	panel.add_child(UI.form_row(
		Loc.t("display.max_fps"),
		UI.row(10, [fps_slider, fps_label]),
		Loc.t("display.max_fps_hint")
	))

	var scale_label := UI.value_label("%d%%" % int(Prefs.ui_scale() * 100.0))
	var scale_callback := func(value: float) -> void:
		Prefs.set_value("general/ui_scale", value)
		scale_label.text = "%d%%" % int(value * 100.0)
	var scale_slider := UI.slider(0.75, 1.75, 0.05, Prefs.ui_scale(), scale_callback)
	panel.add_child(UI.form_row(
		Loc.t("display.ui_scale"),
		UI.row(10, [scale_slider, scale_label]),
		Loc.t("display.ui_scale_hint")
	))

	var actions := UI.flow(10, 8)
	actions.add_child(UI.button(Loc.t("display.restore_safe"), "Button", func() -> void:
		Notify.confirm(Loc.t("display.restore_safe"), Loc.t("display.restore_safe_confirm"), Loc.t("display.restore_safe"), func(accepted: bool) -> void:
			if not accepted:
				return
			Prefs.set_value("display/mode", DisplayManager.MODE_WINDOWED)
			Prefs.set_value("display/width", 1600)
			Prefs.set_value("display/height", 900)
			Prefs.set_value("display/screen", 0)
			DisplayManager.apply_from_prefs()
			Notify.success(Loc.t("display.restore_done"))
			_rebuild()
		, Loc.t("common.cancel"), true)
	))
	actions.add_child(UI.button(Loc.t("display.native_size"), "Button", func() -> void:
		var screen := clampi(Prefs.screen_index(), 0, DisplayServer.get_screen_count() - 1)
		var native := DisplayServer.screen_get_size(screen)
		_apply_display(DisplayManager.MODE_WINDOWED, native)
	))
	actions.add_child(UI.button(Loc.t("display.toggle_fullscreen"), "Button", func() -> void:
		DisplayManager.toggle_fullscreen()
		_rebuild()
	))
	panel.add_child(actions)
	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


func _apply_display(mode: int, size: Vector2i) -> void:
	Prefs.set_value("display/mode", mode)
	Prefs.set_value("display/width", size.x)
	Prefs.set_value("display/height", size.y)
	DisplayManager.request(mode, size, Prefs.screen_index())
	_refresh_revert_banner()
	_rebuild()


# ------------------------------------------------------------------ language

func _build_language() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("language.title"), Loc.t("language.hint")))
	panel.add_child(UI.kv_row(Loc.t("language.current"), Loc.native_name(Loc.current_locale)))
	var coverage := Loc.coverage_report()
	var list := UI.column(6)
	for code: String in Loc.locale_codes():
		var stats: Dictionary = coverage.get(code, {})
		var row := UI.row(10)
		var active := code == Loc.current_locale
		var button := UI.button(Loc.native_name(code), "SidebarButton" if not active else "PrimaryButton", func() -> void:
			if Loc.set_locale(code):
				Notify.success(Loc.t("language.changed", {"language": Loc.native_name(code)}))
				_rebuild()
		)
		button.custom_minimum_size = Vector2(220, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(button)
		var percent := float(stats.get("percent", 0.0))
		var info := UI.label(Loc.t("language.coverage", {"percent": int(percent)}), "Caption")
		# Take the spare width in the row instead of collapsing to a 1 px
		# column, which used to make each language row hundreds of pixels tall.
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_OFF
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.clip_text = true
		row.add_child(info)
		if not active and percent < 99.9:
			row.add_child(UI.chip(Loc.t("language.partial"), Palette.WARNING))
		if active:
			row.add_child(UI.chip(Loc.t("language.active"), Palette.POSITIVE))
		list.add_child(row)
	panel.add_child(list)
	panel.add_child(UI.label(Loc.t("language.fallback_note"), "Caption"))
	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


# --------------------------------------------------------------------- audio

func _build_audio() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("audio.title"), Loc.t("audio.hint")))
	panel.add_child(UI.toggle(Loc.t("audio.mute"), bool(Prefs.get_value("audio/mute", false)), func(value: bool) -> void:
		Prefs.set_value("audio/mute", value)
		Audio.apply_volumes()
	))
	panel.add_child(_volume_row(Loc.t("audio.master"), "audio/master_volume"))
	panel.add_child(_volume_row(Loc.t("audio.sfx"), "audio/sfx_volume"))
	panel.add_child(_volume_row(Loc.t("audio.music"), "audio/music_volume"))
	panel.add_child(UI.button(Loc.t("audio.test"), "Button", func() -> void:
		Audio.play(Audio.Sfx.CONFIRM)
	))
	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


func _volume_row(label_text: String, pref_key: String) -> Control:
	var value_label := UI.value_label("%d%%" % int(float(Prefs.get_value(pref_key, 0.8)) * 100.0))
	var volume_callback := func(value: float) -> void:
		Prefs.set_value(pref_key, value)
		value_label.text = "%d%%" % int(value * 100.0)
		Audio.apply_volumes()
	var slider := UI.slider(0.0, 1.0, 0.05, float(Prefs.get_value(pref_key, 0.8)), volume_callback)
	return UI.form_row(label_text, UI.row(10, [slider, value_label]))


# ------------------------------------------------------------- accessibility

func _build_accessibility() -> void:
	var panel := UI.column(16)
	panel.add_child(UI.section_header(Loc.t("accessibility.title"), Loc.t("accessibility.hint")))
	panel.add_child(UI.toggle(Loc.t("accessibility.reduced_motion"), bool(Prefs.get_value("general/reduced_motion", false)), func(value: bool) -> void:
		Prefs.set_value("general/reduced_motion", value)
		Notify.info(Loc.t("accessibility.reduced_motion_saved"))
	))
	panel.add_child(UI.toggle(Loc.t("accessibility.show_status"), bool(Prefs.get_value("general/show_development_titles", true)), func(value: bool) -> void:
		Prefs.set_value("general/show_development_titles", value)
	))
	var scale_label := UI.value_label("%d%%" % int(Prefs.ui_scale() * 100.0))
	var scale_callback := func(value: float) -> void:
		Prefs.set_value("general/ui_scale", value)
		scale_label.text = "%d%%" % int(value * 100.0)
	var scale_slider := UI.slider(0.75, 1.75, 0.05, Prefs.ui_scale(), scale_callback)
	panel.add_child(UI.form_row(
		Loc.t("accessibility.ui_scale"),
		UI.row(10, [scale_slider, scale_label]),
		Loc.t("accessibility.ui_scale_hint")
	))
	panel.add_child(UI.divider())
	panel.add_child(UI.label(Loc.t("accessibility.keyboard_hint"), "Small"))
	panel.add_child(UI.kv_row(Loc.t("accessibility.shortcut_back"), "Esc"))
	panel.add_child(UI.kv_row(Loc.t("accessibility.shortcut_search"), "Ctrl + F"))
	panel.add_child(UI.kv_row(Loc.t("accessibility.shortcut_fullscreen"), "F11"))
	panel.add_child(UI.kv_row(Loc.t("accessibility.shortcut_help"), "F1"))
	var card := UI.panel_with(panel, "CardPanel", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)


# ------------------------------------------------------------ revert banner

func _on_display_event(event: String, _data: Dictionary) -> void:
	if event == "reverted":
		_hide_revert_banner()
		Notify.warning(Loc.t("display.reverted"))
		if is_inside_tree() and visible:
			_rebuild()
	elif event == "confirmation_finished":
		_hide_revert_banner()
	_refresh_revert_banner()


func _refresh_revert_banner() -> void:
	if _revert_banner == null:
		return
	var pending := DisplayManager.has_pending()
	_revert_banner.visible = pending
	if pending:
		_revert_label.text = Loc.t("display.confirm_change", {"seconds": int(DisplayManager.REVERT_SECONDS)})


func _hide_revert_banner() -> void:
	if _revert_banner != null:
		_revert_banner.visible = false


func refresh_texts() -> void:
	_rebuild()
