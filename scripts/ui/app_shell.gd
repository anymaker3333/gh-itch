class_name AppShell
extends Control
## Application shell: window chrome, sidebar, top bar, screen routing, modals.
##
## Owns the single instance of the running application (created by
## scenes/main.tscn). Screens are instantiated from a route table and cached when
## they declare themselves keep-alive, which is what makes "back" cheap and
## predictable.

const SIDEBAR_WIDTH: int = 272
const SIDEBAR_MIN_WIDTH: int = 200
const SIDEBAR_MAX_WIDTH: int = 520
const ROUTE_SCREENS: Dictionary = {
	Nav.ROUTE_LIBRARY: "res://scripts/ui/screens/library_screen.gd",
	Nav.ROUTE_ALL_GAMES: "res://scripts/ui/screens/library_screen.gd",
	Nav.ROUTE_FAVORITES: "res://scripts/ui/screens/library_screen.gd",
	Nav.ROUTE_RECENT: "res://scripts/ui/screens/library_screen.gd",
	Nav.ROUTE_SETTINGS: "res://scripts/ui/screens/settings_screen.gd",
	Nav.ROUTE_DISPLAY_SETTINGS: "res://scripts/ui/screens/settings_screen.gd",
	Nav.ROUTE_AUDIO_SETTINGS: "res://scripts/ui/screens/settings_screen.gd",
	Nav.ROUTE_LANGUAGE_SETTINGS: "res://scripts/ui/screens/settings_screen.gd",
	Nav.ROUTE_ACCESSIBILITY: "res://scripts/ui/screens/settings_screen.gd",
	Nav.ROUTE_DIAGNOSTICS: "res://scripts/ui/screens/diagnostics_screen.gd",
	Nav.ROUTE_ABOUT: "res://scripts/ui/screens/about_screen.gd",
	Nav.ROUTE_ONLINE: "res://scripts/ui/screens/online_screen.gd",
	Nav.ROUTE_LOBBY: "res://scripts/ui/screens/lobby_screen.gd",
	Nav.ROUTE_GAME_DETAILS: "res://scripts/ui/screens/details_screen.gd",
	Nav.ROUTE_GAME_SETUP: "res://scripts/ui/screens/setup_screen.gd",
	Nav.ROUTE_STAR_REALMS_SETS: "res://scripts/ui/screens/star_realms_sets_screen.gd",
	Nav.ROUTE_GAME: "res://scripts/ui/screens/game_screen.gd",
}

const NAV_ENTRIES: Array[Dictionary] = [
	{"route": Nav.ROUTE_LIBRARY, "key": "nav.library", "glyph": "◈"},
	{"route": Nav.ROUTE_ALL_GAMES, "key": "nav.all_games", "glyph": "▤"},
	{"route": Nav.ROUTE_FAVORITES, "key": "nav.favorites", "glyph": "★"},
	{"route": Nav.ROUTE_RECENT, "key": "nav.recent", "glyph": "◔"},
]

var content_host: MarginContainer
var top_bar: PanelContainer
var toasts: ToastLayer
var modals: ModalLayer
var _screen_layer: Control
var _title_label: Label
var _subtitle_label: Label
var _back_button: Button
var _search_field: LineEdit
var _sidebar_buttons: Dictionary = {}
var _sidebar_split: HSplitContainer
var _sidebar: Control
var _sidebar_toggle: Button
var _sidebar_visible: bool = true
var _sidebar_width: int = SIDEBAR_WIDTH
var _brand_label: Label
var _exit_button: Button
var _steam_chip: Button
var _error_chip: Button
var _version_label: Label
var _screens: Dictionary = {}
var _current: ScreenBase = null
var _current_route: String = ""
var _busy: bool = false
var _background: ColorRect


func _ready() -> void:
	theme = ThemeBuilder.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	Notify.set_modal_host(modals)
	Nav.route_changed.connect(_on_route_changed)
	Nav.stack_changed.connect(_on_stack_changed)
	Loc.locale_changed.connect(_on_locale_changed)
	Prefs.setting_changed.connect(_on_setting_changed)
	ThemeSvc.theme_changed.connect(_on_theme_changed)
	SteamSvc.state_changed.connect(_on_steam_state)
	SteamSvc.identity_ready.connect(_on_steam_identity)
	Log.message_logged.connect(_on_log_message)
	_apply_ui_scale()
	_refresh_sidebar()
	_refresh_steam_chip()
	_update_sidebar_toggle()
	_on_route_changed(Nav.current_route(), Nav.current_params(), "")


func _build_layout() -> void:
	_background = ColorRect.new()
	_background.color = Palette.BG_BASE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	root.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	add_child(root)
	_sidebar_split = root
	_sidebar = _build_sidebar()
	root.add_child(_sidebar)
	root.add_child(_build_main_column())
	_sidebar_width = clampi(int(Prefs.get_value("general/sidebar_width", SIDEBAR_WIDTH)),
		SIDEBAR_MIN_WIDTH, SIDEBAR_MAX_WIDTH)
	_sidebar_visible = bool(Prefs.get_value("general/sidebar_visible", true))
	_sidebar.custom_minimum_size = Vector2(_sidebar_width, 0)
	_sidebar.visible = _sidebar_visible
	root.split_offset = _sidebar_width
	root.dragged.connect(_on_sidebar_dragged)

	# Overlays (order matters: modals above toasts).
	toasts = ToastLayer.new()
	add_child(toasts)
	modals = ModalLayer.new()
	add_child(modals)


func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.theme_type_variation = "FlatPanel"
	sidebar.custom_minimum_size = Vector2(SIDEBAR_MIN_WIDTH, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_DEEPEST, Palette.BORDER, 1, 0, 0))

	var column := UI.column(0)
	column.add_theme_constant_override("separation", 0)
	sidebar.add_child(column)

	# Brand block.
	var brand := MarginContainer.new()
	brand.add_theme_constant_override("margin_left", 22)
	brand.add_theme_constant_override("margin_right", 18)
	brand.add_theme_constant_override("margin_top", 22)
	brand.add_theme_constant_override("margin_bottom", 18)
	column.add_child(brand)
	var brand_row := UI.row(12)
	brand.add_child(brand_row)
	var mark := UI.panel("AccentPanel")
	mark.custom_minimum_size = Vector2(40, 40)
	var mark_label := UI.label("GH", "Body", HORIZONTAL_ALIGNMENT_CENTER)
	mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark_label.add_theme_color_override("font_color", Color.WHITE)
	mark_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mark.add_child(mark_label)
	brand_row.add_child(mark)
	var brand_text := UI.column(0)
	brand_row.add_child(brand_text)
	_brand_label = UI.heading(Loc.t("app.name"), "Subtitle")
	_brand_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand_text.add_child(_brand_label)
	_version_label = UI.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1.0"), "Caption")
	brand_text.add_child(_version_label)

	# Primary navigation.
	var nav_box := UI.column(4)
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 12)
	nav_margin.add_theme_constant_override("margin_right", 12)
	nav_margin.add_child(nav_box)
	column.add_child(nav_margin)
	for entry: Dictionary in NAV_ENTRIES:
		nav_box.add_child(_make_nav_button(entry))
	nav_box.add_child(UI.fixed_spacer(10))
	nav_box.add_child(_make_nav_button({"route": Nav.ROUTE_ONLINE, "key": "nav.online", "glyph": "⬡"}))
	nav_box.add_child(_make_nav_button({"route": Nav.ROUTE_SETTINGS, "key": "nav.settings", "glyph": "⚙"}))

	column.add_child(UI.spacer(0, true))

	# Status footer.
	var footer := UI.column(8)
	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 14)
	footer_margin.add_theme_constant_override("margin_right", 14)
	footer_margin.add_theme_constant_override("margin_bottom", 16)
	footer_margin.add_theme_constant_override("margin_top", 12)
	footer_margin.add_child(footer)
	column.add_child(footer_margin)
	footer.add_child(UI.divider())
	_steam_chip = UI.button("", "SidebarButton", _on_steam_chip_pressed)
	_steam_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_steam_chip.tooltip_text = Loc.t("steam.status_tooltip")
	footer.add_child(_steam_chip)
	_error_chip = UI.button("", "SidebarButton", func() -> void: Nav.go(Nav.ROUTE_DIAGNOSTICS))
	_error_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_error_chip.tooltip_text = Loc.t("diagnostics.tooltip")
	footer.add_child(_error_chip)
	var exit_row := UI.row(8)
	footer.add_child(exit_row)
	_exit_button = UI.button("⏻  " + Loc.t("nav.exit"), "SidebarButton", _request_exit)
	_exit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exit_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	exit_row.add_child(_exit_button)
	return sidebar


func _make_nav_button(entry: Dictionary) -> Button:
	var button := UI.button("%s   %s" % [String(entry.glyph), Loc.t(String(entry.key))], "SidebarButton", func() -> void:
		Nav.go(String(entry.route))
	)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 40)
	button.set_meta("route", String(entry.route))
	button.set_meta("label_key", String(entry.key))
	button.set_meta("glyph", String(entry.glyph))
	_sidebar_buttons[String(entry.route)] = button
	return button


func _build_main_column() -> Control:
	var column := UI.column(0)
	column.custom_minimum_size = Vector2(520, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)

	top_bar = UI.panel("TransparentPanel")
	top_bar.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_BASE, Palette.BORDER, 0, 0, 0))
	top_bar.custom_minimum_size = Vector2(0, 68)
	column.add_child(top_bar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	var bar_margin := UI.margin_xy(bar, 20, 12, 24, 12)
	bar_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_bar.add_child(bar_margin)
	_sidebar_toggle = UI.icon_button("☰", Loc.t("shell.sidebar_hide"), _toggle_sidebar)
	bar.add_child(_sidebar_toggle)
	_back_button = UI.icon_button("←", Loc.t("common.back"), func() -> void: _handle_back())
	_back_button.visible = false
	bar.add_child(_back_button)
	var titles := UI.column(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(titles)
	_title_label = UI.heading("", "Title")
	titles.add_child(_title_label)
	_subtitle_label = UI.label("", "Caption")
	_subtitle_label.visible = false
	titles.add_child(_subtitle_label)
	_search_field = UI.line_edit(Loc.t("library.search_placeholder"))
	# Keep the query box a toolbar control. Letting it expand stole half of the
	# title bar at 1600-1920 px.
	_search_field.custom_minimum_size = Vector2(320, 36)
	_search_field.size_flags_horizontal = Control.SIZE_SHRINK_END
	_search_field.visible = false
	_search_field.text_changed.connect(_on_search_changed)
	bar.add_child(_search_field)

	_screen_layer = Control.new()
	_screen_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_screen_layer)
	return column


# ------------------------------------------------------------------ routing

func _on_route_changed(route: String, params: Dictionary, _previous: String) -> void:
	if _current != null:
		_current.on_exit()
	_current = null
	_current_route = route
	var screen := _obtain_screen(route, params)
	if screen == null:
		Log.error("AppShell: no screen for route", {"route": route})
		return
	if not screen.is_inside_tree():
		_screen_layer.add_child(screen)
	screen.setup(params)
	# A screen may redirect from on_enter (for example the game route without
	# an active session). That emits a nested route change which has already
	# installed the correct screen; do not make the redirected-away screen
	# visible on top of it.
	if _current_route != route:
		return
	_current = screen
	screen.visible = true
	for other: Variant in _screens:
		var other_screen: ScreenBase = _screens[other]
		if other_screen != screen and is_instance_valid(other_screen) and other_screen.is_inside_tree():
			other_screen.visible = false
	_update_top_bar()
	_refresh_sidebar()


func _obtain_screen(route: String, params: Dictionary) -> ScreenBase:
	var path := String(ROUTE_SCREENS.get(route, ""))
	if path.is_empty():
		return null
	if _screens.has(route):
		var cached: ScreenBase = _screens[route]
		if is_instance_valid(cached):
			return cached
		_screens.erase(route)
	var script := load(path) as GDScript
	if script == null:
		Log.error("AppShell: screen script missing", {"route": route, "path": path})
		return null
	var instance: Variant = script.new()
	if not (instance is ScreenBase):
		Log.error("AppShell: screen script is not a ScreenBase", {"path": path})
		return null
	var screen: ScreenBase = instance
	screen.name = "Screen_%s" % route
	_screens[route] = screen
	return screen


func _update_top_bar() -> void:
	if _current == null:
		return
	_title_label.text = _current.screen_title()
	var subtitle := _current.screen_subtitle()
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()
	_back_button.visible = Nav.can_go_back()
	var wants_search := _current.has_method("wants_search") and bool(_current.call("wants_search"))
	_search_field.visible = wants_search
	if wants_search:
		var current_query := String(_current.call("search_text")) if _current.has_method("search_text") else _search_field.text
		if _search_field.text != current_query:
			_search_field.text = current_query


func _on_stack_changed(_depth: int) -> void:
	_back_button.visible = Nav.can_go_back()


func _handle_back() -> void:
	if modals.is_open():
		modals.dismiss()
		return
	if _current != null and _current.on_back():
		return
	if _current != null and not _current.allows_back():
		Notify.warning(Loc.t("common.back_blocked"))
		return
	if not Nav.back():
		Nav.go(Nav.ROUTE_LIBRARY)


func _on_search_changed(text: String) -> void:
	if _current != null and _current.has_method("on_search"):
		_current.call("on_search", text)


# ------------------------------------------------------------------ sidebar

func _refresh_sidebar() -> void:
	var route := Nav.current_route()
	for key: Variant in _sidebar_buttons:
		var button: Button = _sidebar_buttons[key]
		var selected := String(key) == route
		var label_key := String(button.get_meta("label_key", ""))
		if not label_key.is_empty():
			button.text = "%s   %s" % [String(button.get_meta("glyph", "")), Loc.t(label_key)]
		button.disabled = false
		button.add_theme_color_override("font_color", Palette.TEXT if selected else Palette.TEXT_MUTED)
		var style := ThemeBuilder.flat(
			Palette.tint(Palette.ACCENT, 0.18) if selected else Color(0, 0, 0, 0),
			Palette.tint(Palette.ACCENT, 0.5) if selected else Color(0, 0, 0, 0),
			1,
			ThemeBuilder.RADIUS,
			12
		)
		button.add_theme_stylebox_override("normal", style)
		var hover := ThemeBuilder.flat(Palette.BG_HOVER, Palette.BORDER, 1, ThemeBuilder.RADIUS, 12)
		button.add_theme_stylebox_override("hover", hover)
		if selected:
			button.add_theme_stylebox_override("hover", style)


func _update_sidebar_toggle() -> void:
	if _sidebar_toggle == null:
		return
	_sidebar_toggle.tooltip_text = Loc.t("shell.sidebar_show" if not _sidebar_visible else "shell.sidebar_hide")


func _toggle_sidebar() -> void:
	_sidebar_visible = not _sidebar_visible
	if _sidebar != null:
		_sidebar.visible = _sidebar_visible
	if _sidebar_visible and _sidebar_split != null:
		_sidebar_split.split_offset = _sidebar_width
	Prefs.set_value("general/sidebar_visible", _sidebar_visible)
	_update_sidebar_toggle()


func _on_sidebar_dragged(offset: int) -> void:
	_sidebar_width = clampi(offset, SIDEBAR_MIN_WIDTH, SIDEBAR_MAX_WIDTH)
	if _sidebar != null:
		_sidebar.custom_minimum_size = Vector2(_sidebar_width, 0)


func _on_steam_chip_pressed() -> void:
	modals.alert(
		Loc.t("steam.status_title"),
		"%s\n\n%s\n\n%s" % [
			SteamSvc.status_text(),
			SteamSvc.state_detail if not SteamSvc.state_detail.is_empty() else Loc.t("steam.detail_none"),
			Loc.t("steam.detail_app_id", {"app_id": SteamSvc.app_id}),
		]
	)


func _refresh_steam_chip() -> void:
	if _steam_chip == null:
		return
	var color := Palette.TEXT_DIM
	match SteamSvc.state:
		SteamSvc.State.READY:
			color = Palette.POSITIVE
		SteamSvc.State.INITIALIZING:
			color = Palette.WARNING
		SteamSvc.State.FAILED:
			color = Palette.DANGER
		SteamSvc.State.DISABLED:
			color = Palette.TEXT_DIM
		_:
			color = Palette.TEXT_MUTED
	_steam_chip.text = "●  %s" % _short_steam_status()
	_steam_chip.tooltip_text = Loc.t("steam.status_tooltip")
	_steam_chip.add_theme_color_override("font_color", color)
	_error_chip.text = "%s  %d" % ["⚠", Log.error_count()]
	_error_chip.tooltip_text = Loc.t("diagnostics.tooltip")
	_error_chip.add_theme_color_override("font_color", Palette.DANGER if Log.error_count() > 0 else Palette.TEXT_DIM)


func _short_steam_status() -> String:
	match SteamSvc.state:
		SteamSvc.State.READY:
			return SteamSvc.persona_name if not SteamSvc.persona_name.is_empty() else Loc.t("steam.short_ready")
		SteamSvc.State.INITIALIZING:
			return Loc.t("steam.short_connecting")
		SteamSvc.State.FAILED:
			return Loc.t("steam.short_failed")
		SteamSvc.State.DISABLED:
			return Loc.t("steam.short_disabled")
		_:
			return Loc.t("steam.short_offline")


func _on_steam_state(_state: int, _detail: String) -> void:
	_refresh_steam_chip()


func _on_steam_identity(_id: int, name: String) -> void:
	_refresh_steam_chip()
	Notify.success(Loc.t("steam.signed_in", {"name": name}))


func _on_log_message(entry: Dictionary) -> void:
	if int(entry.level) >= Log.Level.ERROR:
		_refresh_steam_chip()


func _on_locale_changed(_code: String) -> void:
	# Screens are cached for their whole lifetime, so refreshing only the visible
	# one leaves every previously visited screen with the old language. Drop the
	# cached instances and let the next route build them with the new locale.
	_invalidate_cached_screens()
	_refresh_texts()


func _invalidate_cached_screens() -> void:
	var stale: Array[String] = []
	for route: Variant in _screens.keys():
		if _screens[route] == _current:
			continue
		stale.append(String(route))
	for route: String in stale:
		var screen: ScreenBase = _screens.get(route) as ScreenBase
		_screens.erase(route)
		if is_instance_valid(screen):
			screen.visible = false
			screen.queue_free()


func _on_theme_changed(_theme_id: String) -> void:
	theme = ThemeBuilder.build()
	if _background != null:
		_background.color = Palette.BG_BASE
	if _sidebar != null:
		_sidebar.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_DEEPEST, Palette.BORDER, 1, 0, 0))
	if top_bar != null:
		top_bar.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_BASE, Palette.BORDER, 0, 0, 0))
	_refresh_sidebar()
	_refresh_steam_chip()
	_invalidate_cached_screens()


func _on_setting_changed(path: String, _value: Variant) -> void:
	if path == "general/ui_scale":
		_apply_ui_scale()
	if path.begins_with("general/") or path.begins_with("library/"):
		_refresh_texts()


func _apply_ui_scale() -> void:
	get_window().content_scale_factor = clampf(Prefs.ui_scale(), 0.75, 1.75)


func _refresh_texts() -> void:
	if _brand_label != null:
		_brand_label.text = Loc.t("app.name")
	if _exit_button != null:
		_exit_button.text = "⏻  " + Loc.t("nav.exit")
	_refresh_sidebar()
	_refresh_steam_chip()
	_update_sidebar_toggle()
	if _current != null:
		_current.refresh_texts()
	_update_top_bar()
	_title_label.text = _current.screen_title() if _current != null else ""
	_search_field.placeholder_text = Loc.t("library.search_placeholder")


# ------------------------------------------------------------------ shortcuts

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_ESCAPE:
				_handle_back()
				get_viewport().set_input_as_handled()
			KEY_F11:
				DisplayManager.toggle_fullscreen()
				get_viewport().set_input_as_handled()
			KEY_F1:
				Nav.go(Nav.ROUTE_ABOUT)
				get_viewport().set_input_as_handled()
		if key_event.ctrl_pressed and key_event.keycode == KEY_F and _search_field.visible:
			_search_field.grab_focus()
			_search_field.select_all()
			get_viewport().set_input_as_handled()
		if key_event.ctrl_pressed and key_event.keycode == KEY_B:
			_toggle_sidebar()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_exit()


func _request_exit() -> void:
	if Session.current != null and Session.current.engine != null and not Session.current.engine.finished:
		modals.confirm(
			Loc.t("exit.title"),
			Loc.t("exit.active_match_body"),
			Loc.t("exit.title"),
			func(accepted: bool) -> void:
				if accepted:
					_quit_now()
		)
		return
	if bool(Prefs.get_value("general/confirm_on_exit", true)):
		modals.confirm(
			Loc.t("exit.title"),
			Loc.t("exit.body"),
			Loc.t("exit.confirm"),
			func(accepted: bool) -> void:
				if accepted:
					_quit_now()
		)
	else:
		_quit_now()


func _quit_now() -> void:
	Log.info("AppShell: exit requested")
	Prefs.set_value("general/sidebar_width", _sidebar_width)
	Prefs.set_value("general/sidebar_visible", _sidebar_visible)
	Session.end_session()
	SteamSvc.shutdown()
	Prefs.save_now()
	get_tree().quit()
