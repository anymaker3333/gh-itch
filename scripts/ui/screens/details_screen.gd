extends ScreenBase
## Game details screen: artwork, metadata, implementation status, actions.

var entry: GameEntry = null
var _content: VBoxContainer


func build() -> void:
	title_key = "details.title"
	_content = UI.column(20)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(_content)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.max_width(UI.margin_xy(scroll, 24, 20, 24, 24), 1200, true))


func on_enter() -> void:
	entry = Catalog.get_entry(String(params.get("game_id", "")))
	if entry == null:
		Log.warn("Details: unknown game", {"game_id": params.get("game_id", "")})
		Nav.go(Nav.ROUTE_ALL_GAMES, {}, "replace")
		return
	title_key = entry.name_key
	_rebuild()


func _rebuild() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if entry == null:
		return

	# --- hero ---------------------------------------------------------------
	var hero := UI.panel("CardPanel")
	hero.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_PANEL, Palette.tint(entry.accent, 0.5), 1, ThemeBuilder.RADIUS_LARGE, 0))
	_content.add_child(hero)
	var hero_box := UI.column(0)
	hero.add_child(hero_box)
	var art_wrap := Control.new()
	art_wrap.custom_minimum_size = Vector2(0, 240)
	hero_box.add_child(art_wrap)
	if ResourceLoader.exists(entry.art_path):
		var texture := load(entry.art_path) as Texture2D
		if texture != null:
			var art := TextureRect.new()
			art.texture = texture
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.set_anchors_preset(Control.PRESET_FULL_RECT)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art_wrap.add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.05, 0.07, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(shade)
	var hero_text := UI.column(8)
	var hero_margin := UI.margin_xy(null, 20, 16, 20, 18)
	hero_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hero_margin.offset_top = -170
	hero_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the description on the dark left side of the artwork instead of
	# running over the board illustration and the full 1920 px page.
	var hero_text_limit := UI.max_width(hero_text, 760)
	hero_text_limit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_margin.add_child(hero_text_limit)
	art_wrap.add_child(hero_margin)
	var title := UI.heading(entry.display_name(), "Display")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_text.add_child(title)
	var meta := UI.row(8)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(UI.chip(entry.category_text(), entry.accent, Palette.BG_ELEVATED))
	meta.add_child(UI.chip(entry.players_text(), Palette.INFO, Palette.BG_ELEVATED))
	meta.add_child(UI.chip(entry.minutes_text(), Palette.TEXT_MUTED, Palette.BG_ELEVATED))
	meta.add_child(UI.chip(entry.status_text(), entry.status_color(), Palette.BG_ELEVATED))
	hero_text.add_child(meta)
	var description := UI.label(entry.description(), "Small")
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_text.add_child(description)

	# --- actions ------------------------------------------------------------
	var actions := UI.row(10)
	_content.add_child(actions)
	var play := UI.button(Loc.t("details.play"), "PrimaryButton", _on_play)
	play.custom_minimum_size = Vector2(160, 44)
	play.disabled = not entry.is_playable() or not Session.engine_available(entry.id)
	if play.disabled:
		play.tooltip_text = Loc.t("details.play_unavailable")
	actions.add_child(play)
	if entry.has_editions:
		actions.add_child(UI.button(Loc.t("details.editions"), "Button", func() -> void:
			Nav.go(Nav.ROUTE_STAR_REALMS_SETS, {"game_id": entry.id})
		))
	actions.add_child(UI.button(Loc.t("details.online"), "Button", func() -> void:
		Nav.go(Nav.ROUTE_ONLINE, {"game_id": entry.id})
	))
	var favorite := UI.button(
		Loc.t("details.favorite_remove") if Prefs.is_favorite(entry.id) else Loc.t("details.favorite_add"),
		"Button",
		func() -> void:
			var now := Prefs.toggle_favorite(entry.id)
			Notify.info(Loc.t("library.favorite_added" if now else "library.favorite_removed", {"game": entry.display_name()}))
			_rebuild()
	)
	actions.add_child(favorite)
	actions.add_child(UI.spacer())

	# --- info panels --------------------------------------------------------
	_content.add_child(_info_panel(Loc.t("details.panel_about"), _about_lines()))
	_content.add_child(_info_panel(Loc.t("details.panel_rules"), _rule_lines()))
	_content.add_child(_info_panel(Loc.t("details.panel_controls"), _control_lines()))

	# --- library statistics -------------------------------------------------
	if Catalog.play_count(entry.id) > 0:
		_content.add_child(UI.label(Loc.tp("details.play_count", Catalog.play_count(entry.id)), "Caption"))


func _info_panel(title: String, lines: Array) -> PanelContainer:
	var box := UI.column(8)
	box.add_child(UI.heading(title, "Subtitle"))
	box.add_child(UI.divider())
	for line: Variant in lines:
		if line is Array:
			var pair: Array = line
			box.add_child(UI.kv_row(String(pair[0]), String(pair[1]), pair[2] if pair.size() > 2 else Palette.TEXT))
		else:
			box.add_child(UI.label(String(line), "Small"))
	var panel := UI.panel_with(box, "CardPanel", 16)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


func _about_lines() -> Array:
	var lines: Array = [
		[Loc.t("details.field_category"), entry.category_text()],
		[Loc.t("details.field_players"), entry.players_text()],
		[Loc.t("details.field_duration"), entry.minutes_text()],
		[Loc.t("details.field_complexity"), "%s / 5" % entry.complexity],
		[Loc.t("details.field_modes"), entry.modes_text()],
	]
	if entry.has_editions:
		var selected: Array = Prefs.selected_star_realms_sets()
		lines.append([Loc.t("details.field_editions"), Loc.t("details.editions_selected", {"count": selected.size()}), Palette.ACCENT])
	return lines


func _status_lines() -> Array:
	var lines: Array = [
		[Loc.t("details.field_status"), entry.status_text(), entry.status_color()],
		[Loc.t("details.field_online"), entry.online_status_text(), Palette.POSITIVE if entry.online_status == GameEntry.OnlineStatus.VERIFIED else Palette.TEXT_MUTED],
	]
	var engine_ready := Session.engine_available(entry.id)
	lines.append([Loc.t("details.field_engine"), Loc.t("details.engine_ready") if engine_ready else Loc.t("details.engine_missing"), Palette.POSITIVE if engine_ready else Palette.DANGER])
	var bot_ready := BotDirector.has_bot(entry.id)
	lines.append([Loc.t("details.field_ai"), Loc.t("details.ai_ready") if bot_ready else Loc.t("details.ai_basic"), Palette.POSITIVE if bot_ready else Palette.WARNING])
	if entry.has_editions:
		var selected: Array = Prefs.selected_star_realms_sets()
		lines.append([Loc.t("details.field_editions"), Loc.t("details.editions_selected", {"count": selected.size()}), Palette.ACCENT])
	return lines


func _rule_lines() -> Array:
	var lines: Array = []
	for index: int in range(1, 6):
		var key := "game.%s.rule.%d" % [entry.id, index]
		if Loc.has_key(key):
			lines.append("• " + Loc.t(key))
	if lines.is_empty():
		lines.append(Loc.t("details.rules_pending"))
	return lines


func _control_lines() -> Array:
	var lines: Array = [Loc.t("details.controls_common")]
	if entry.supports_mode("hotseat"):
		lines.append(Loc.t("details.controls_hotseat"))
	if entry.supports_mode("solo_ai"):
		lines.append(Loc.t("details.controls_solo"))
	if entry.supports_mode("online"):
		lines.append(Loc.t("details.controls_online"))
	return lines


func _on_play() -> void:
	if entry == null:
		return
	Nav.go(Nav.ROUTE_GAME_SETUP, {"game_id": entry.id})


func refresh_texts() -> void:
	if entry != null:
		_rebuild()
