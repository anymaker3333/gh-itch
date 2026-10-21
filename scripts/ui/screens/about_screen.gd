extends ScreenBase
## About screen: product information, credits, dependency versions, legal notes.

var _content: VBoxContainer


func build() -> void:
	title_key = "about.title"
	subtitle_key = "about.subtitle"
	_content = UI.column(18)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(_content)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(scroll, 24, 20, 24, 24))
	_rebuild()


func refresh_texts() -> void:
	_rebuild()


func _rebuild() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var column := _content
	var hero := UI.column(10)
	hero.add_child(UI.heading(Loc.t("app.name"), "Display"))
	hero.add_child(UI.label(Loc.t("about.tagline", {
		"version": str(Engine.get_version_info().get("string", "?")),
	}), "Subtitle"))
	hero.add_child(UI.label(Loc.t("about.version", {"version": str(ProjectSettings.get_setting("application/config/version", "0.1.0"))}), "Small"))
	column.add_child(UI.panel_with(hero, "CardPanel", 20))

	column.add_child(_panel(Loc.t("about.panel_what"), [
		Loc.t("about.what_body"),
	]))
	column.add_child(_panel(Loc.t("about.panel_scopes"), [
		Loc.t("about.scope_1"),
		Loc.t("about.scope_2"),
		Loc.t("about.scope_3"),
		Loc.t("about.scope_4"),
	]))
	column.add_child(_panel(Loc.t("about.panel_tech"), [
		Loc.t("about.tech_engine", {"version": str(Engine.get_version_info().get("string", "?"))}),
		Loc.t("about.tech_steam"),
		Loc.t("about.tech_fonts"),
		Loc.t("about.tech_art"),
	]))
	column.add_child(_panel(Loc.t("about.panel_legal"), [
		Loc.t("about.legal_1"),
		Loc.t("about.legal_2"),
		Loc.t("about.legal_3"),
	]))
	column.add_child(_panel(Loc.t("about.panel_keys"), [
		"Esc — " + Loc.t("accessibility.shortcut_back"),
		"Ctrl + F — " + Loc.t("accessibility.shortcut_search"),
		"F11 — " + Loc.t("accessibility.shortcut_fullscreen"),
		"F1 — " + Loc.t("accessibility.shortcut_help"),
	]))
	var actions := UI.row(10)
	actions.add_child(UI.button(Loc.t("about.open_diagnostics"), "Button", func() -> void: Nav.go(Nav.ROUTE_DIAGNOSTICS)))
	actions.add_child(UI.button(Loc.t("about.open_settings"), "GhostButton", func() -> void: Nav.go(Nav.ROUTE_SETTINGS)))
	column.add_child(actions)


func _panel(title: String, lines: Array) -> Control:
	var box := UI.column(8)
	box.add_child(UI.heading(title, "Subtitle"))
	box.add_child(UI.divider())
	for line: Variant in lines:
		box.add_child(UI.label(String(line), "Small"))
	return UI.panel_with(box, "CardPanel", 18)
