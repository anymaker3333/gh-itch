extends ScreenBase
## Game setup: players, opponents, game-specific options, then start.
##
## The screen builds itself from catalog metadata plus the option schema that the
## game's engine publishes, so a new game becomes configurable without touching
## this file.

var entry: GameEntry = null
var _body: VBoxContainer
var _seat_rows: Array[Dictionary] = []
var _option_rows: Dictionary = {}
var _player_count: int = 2
var _seed_locked: bool = false
var _seed_value: int = 0


func build() -> void:
	title_key = "setup.title"
	var column := UI.column(18)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(column)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.max_width(UI.margin_xy(scroll, 24, 20, 24, 24), 1200, true))
	_body = column


func on_enter() -> void:
	entry = Catalog.get_entry(String(params.get("game_id", "")))
	if entry == null:
		Nav.go(Nav.ROUTE_ALL_GAMES, {}, "replace")
		return
	title_key = entry.name_key
	subtitle_key = "setup.subtitle"
	_player_count = clampi(int(params.get("player_count", entry.min_players)), entry.min_players, entry.max_players)
	_seed_value = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	Session.configure(entry.id, _player_count)
	Session.set_option("ai_difficulty", Session.option("ai_difficulty", "normal"))
	_rebuild()


func _rebuild() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_seat_rows.clear()
	_option_rows.clear()

	_body.add_child(_build_summary())
	_body.add_child(_build_mode_panel())
	_body.add_child(_build_players_panel())
	var options_panel := _build_options_panel()
	if options_panel != null:
		_body.add_child(options_panel)
	var editions_panel := _build_editions_panel()
	if editions_panel != null:
		_body.add_child(editions_panel)
	_body.add_child(_build_actions())


func _build_summary() -> Control:
	var box := UI.column(8)
	box.add_child(UI.label(entry.description(), "Small"))
	var meta := UI.row(8)
	meta.add_child(UI.chip(entry.category_text(), entry.accent))
	meta.add_child(UI.chip(entry.players_text(), Palette.INFO))
	meta.add_child(UI.chip(entry.minutes_text(), Palette.TEXT_MUTED))
	meta.add_child(UI.chip(entry.status_text(), entry.status_color()))
	box.add_child(meta)
	if entry.status != GameEntry.Status.PLAYABLE:
		var warning := UI.panel("DangerPanel")
		var warning_text := UI.label(Loc.t("setup.status_warning_%s" % entry.status_key().get_slice(".", 1)), "Warning")
		warning.add_child(UI.margin_container(warning_text, 12))
		box.add_child(warning)
	return box


func _build_mode_panel() -> Control:
	var box := UI.column(8)
	box.add_child(UI.section_header(Loc.t("setup.mode_title"), Loc.t("setup.mode_hint")))
	var row := UI.row(10)
	box.add_child(row)
	row.add_child(UI.button(Loc.t("setup.mode_hotseat"), "PrimaryButton", func() -> void:
		_start(GameSession.Mode.LOCAL_HOTSEAT)
	))
	var solo := UI.button(Loc.t("setup.mode_solo"), "Button", func() -> void:
		_start(GameSession.Mode.SOLO_AI)
	)
	solo.disabled = not BotDirector.has_bot(entry.id) and entry.max_players < 2
	row.add_child(solo)
	row.add_child(UI.button(Loc.t("setup.mode_online"), "Button", func() -> void:
		Nav.go(Nav.ROUTE_ONLINE, {"game_id": entry.id})
	))
	row.add_child(UI.button(Loc.t("details.editions"), "GhostButton", func() -> void:
		Nav.go(Nav.ROUTE_STAR_REALMS_SETS, {"game_id": entry.id})
	) if entry.has_editions else UI.label("", "Caption"))
	return UI.panel_with(box, "CardPanel", 16)


func _build_players_panel() -> Control:
	var box := UI.column(12)
	box.add_child(UI.section_header(Loc.t("setup.players_title"), Loc.t("setup.players_hint")))
	var count_control := HSlider.new()
	count_control.min_value = entry.min_players
	count_control.max_value = entry.max_players
	count_control.step = 1
	count_control.value = _player_count
	count_control.custom_minimum_size = Vector2(240, 24)
	count_control.editable = entry.min_players != entry.max_players
	count_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count_label := UI.value_label(str(_player_count), 32)
	var count_row := UI.row(8)
	count_row.add_child(count_control)
	count_row.add_child(count_label)
	box.add_child(UI.form_row(Loc.t("setup.player_count"), count_row))
	count_control.value_changed.connect(func(value: float) -> void:
		_player_count = int(value)
		count_label.text = str(_player_count)
		Session.configure(entry.id, _player_count)
		_rebuild_players()
	)

	var seats := VBoxContainer.new()
	seats.name = "Seats"
	seats.add_theme_constant_override("separation", 8)
	box.add_child(seats)
	_populate_seats(seats)
	return UI.panel_with(box, "CardPanel", 16)


func _rebuild_players() -> void:
	var seats := _body.find_child("Seats", true, false) as VBoxContainer
	if seats == null:
		return
	for child: Node in seats.get_children():
		seats.remove_child(child)
		child.queue_free()
	_populate_seats(seats)


func _populate_seats(seats: VBoxContainer) -> void:
	var names := Session.pending_names()
	var kinds := Session.pending_kinds()
	for index: int in range(_player_count):
		var row := UI.row(10)
		var number := UI.label(str(index + 1), "Small")
		number.custom_minimum_size = Vector2(24, 0)
		row.add_child(number)
		var name_field := UI.line_edit(Loc.t("setup.player_name_placeholder"), String(names[index]))
		name_field.size_flags_horizontal = Control.SIZE_FILL
		name_field.custom_minimum_size = Vector2(320, 0)
		name_field.editable = true
		name_field.text_changed.connect(func(text: String) -> void: Session.set_player_name(index, text))
		row.add_child(name_field)
		var kind_entries: Array = [
			{"label": Loc.t("setup.kind_local"), "value": "local"},
			{"label": Loc.t("setup.kind_bot"), "value": "bot"},
		]
		var kind_select := UI.dropdown(kind_entries, String(kinds[index]), func(value: String) -> void:
			Session.set_player_kind(index, value)
		)
		kind_select.custom_minimum_size = Vector2(150, 0)
		if index == 0:
			kind_select.disabled = true
			name_field.text = Prefs.profile_name()
		row.add_child(kind_select)
		if index == 0:
			row.add_child(UI.chip(Loc.t("setup.seat_you"), Palette.ACCENT))
		row.add_child(UI.spacer())
		seats.add_child(row)


func _build_options_panel() -> Control:
	var engine := Session.create_engine(entry.id)
	if engine == null:
		return null
	var schema: Array = engine.options_schema()
	var box := UI.column(12)
	box.add_child(UI.section_header(Loc.t("setup.options_title"), Loc.t("setup.options_hint")))
	# Common option: deterministic seed for reproducible matches (and tests).
	var seed_row := UI.row(10)
	box.add_child(seed_row)
	var seed_toggle := UI.toggle(Loc.t("setup.fixed_seed"), _seed_locked, func(value: bool) -> void:
		_seed_locked = value
		Session.set_option("seed", _seed_value if value else 0)
	)
	seed_row.add_child(seed_toggle)
	var seed_field := UI.line_edit(Loc.t("setup.seed_placeholder"), str(_seed_value))
	# `line_edit` expands by default so it can carry a search field. The seed
	# is a short number: keep it at a readable field width instead of letting
	# it take over the options row.
	seed_field.size_flags_horizontal = Control.SIZE_FILL
	seed_field.custom_minimum_size = Vector2(220, 0)
	seed_field.editable = _seed_locked
	seed_field.text_changed.connect(func(text: String) -> void:
		_seed_value = maxi(0, int(text))
		if _seed_locked:
			Session.set_option("seed", _seed_value)
	)
	seed_row.add_child(seed_field)
	for option: Variant in schema:
		if not (option is Dictionary):
			continue
		var spec: Dictionary = option
		box.add_child(_build_option_row(spec))
	return UI.panel_with(box, "CardPanel", 16)


func _build_option_row(spec: Dictionary) -> Control:
	var key := String(spec.get("key", ""))
	var label_key := String(spec.get("label_key", key))
	var type := String(spec.get("type", "bool"))
	var current: Variant = Session.option(key, spec.get("default", null))
	var control: Control = null
	match type:
		"bool":
			control = UI.toggle("", bool(current) if current != null else false, func(value: bool) -> void:
				Session.set_option(key, value)
			)
		"int":
			var minimum := int(spec.get("min", 0))
			var maximum := int(spec.get("max", 10))
			var box := UI.row(8)
			var value_label := UI.label(str(int(current if current != null else spec.get("default", minimum))), "Body")
			var slider := UI.slider(minimum, maximum, 1, float(int(current if current != null else spec.get("default", minimum))), func(value: float) -> void:
				value_label.text = str(int(value))
				Session.set_option(key, int(value))
			)
			box.add_child(slider)
			box.add_child(value_label)
			control = box
		"enum":
			var values: Array = spec.get("values", [])
			var entries: Array = []
			var labels: Dictionary = spec.get("labels", {})
			for value: Variant in values:
				var value_key := String(value)
				entries.append({"label": Loc.t(String(labels.get(value_key, value_key))), "value": value_key})
			control = UI.dropdown(entries, String(current if current != null else spec.get("default", "")), func(value: String) -> void:
				Session.set_option(key, value)
			)
		_:
			control = UI.label(String(current), "Small")
	var hint := Loc.t(String(spec.get("hint_key", ""))) if spec.has("hint_key") else ""
	var row := UI.form_row(Loc.t(label_key), control, hint)
	_option_rows[key] = control
	return row


func _build_editions_panel() -> Control:
	if not entry.has_editions:
		return null
	var box := UI.column(8)
	box.add_child(UI.section_header(Loc.t("sr.selection_title"), Loc.t("sr.selection_hint_short")))
	var selected: Array = Prefs.selected_star_realms_sets()
	var sets := Catalog.edition_sets(entry.edition_registry)
	var chips := UI.flow(8, 8)
	for set: ExpansionSet in sets:
		var active := selected.has(set.id)
		if not active:
			continue
		chips.add_child(UI.chip(set.display_name(), Palette.ACCENT if set.required else Palette.INFO))
	if chips.get_child_count() == 0:
		chips.add_child(UI.label(Loc.t("sr.selection_none"), "Small"))
	box.add_child(chips)
	box.add_child(UI.button(Loc.t("sr.open_menu"), "GhostButton", func() -> void:
		Nav.go(Nav.ROUTE_STAR_REALMS_SETS, {"game_id": entry.id})
	))
	return UI.panel_with(box, "CardPanel", 16)


func _build_actions() -> Control:
	var row := UI.row(10)
	row.add_child(UI.button(Loc.t("details.play"), "PrimaryButton", func() -> void:
		_start(GameSession.Mode.LOCAL_HOTSEAT)
	))
	row.add_child(UI.button(Loc.t("common.cancel"), "GhostButton", func() -> void: Nav.back()))
	var issues := _validation_issues()
	if not issues.is_empty():
		var warning := UI.label("⚠ " + issues[0], "Warning")
		row.add_child(warning)
	return row


func _validation_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	if not Session.engine_available(entry.id):
		issues.append(Loc.t("setup.error_engine_unavailable"))
	if _player_count < entry.min_players or _player_count > entry.max_players:
		issues.append(Loc.t("setup.error_player_count"))
	return issues


func _start(mode: GameSession.Mode) -> void:
	var issues := _validation_issues()
	if not issues.is_empty():
		Notify.error(issues[0])
		return
	Session.configure(entry.id, _player_count)
	if _seed_locked:
		Session.set_option("seed", _seed_value)
	var session := Session.start_local_session(mode)
	if session == null:
		Notify.error(Loc.t("setup.error_start_failed"))
		return
	Nav.go(Nav.ROUTE_GAME, {"game_id": entry.id, "fresh": true}, "push", "none")


func refresh_texts() -> void:
	_rebuild()
