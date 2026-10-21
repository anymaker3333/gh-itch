extends ScreenBase
## Library screen: Home / All Games / Favorites / Recently played.
##
## One implementation drives all four routes (the route parameter picks the
## preset), which guarantees identical search, filtering and card behaviour
## everywhere and keeps the catalog the single source of truth.

const CARD_MIN_WIDTH: int = 300
const ROW_CARD_WIDTH: int = 268

enum Preset { HOME = 0, ALL = 1, FAVORITES = 2, RECENT = 3 }

var preset: Preset = Preset.HOME
var _grid: HFlowContainer
var _row_host: VBoxContainer
var _empty_state: VBoxContainer
var _filter_bar: HFlowContainer
var _count_label: Label
var _search: String = ""
var _category_filter: String = ""
var _players_filter: int = 0
var _sort_key: int = Catalog.SortKey.CATALOG_ORDER
var _sort_ascending: bool = true
var _playable_only: bool = false
var _cards: Array[GameCard] = []


func build() -> void:
	_determine_preset()
	match preset:
		Preset.ALL:
			title_key = "library.title_all"
			subtitle_key = "library.subtitle_all"
		Preset.FAVORITES:
			title_key = "library.title_favorites"
			subtitle_key = "library.subtitle_favorites"
		Preset.RECENT:
			title_key = "library.title_recent"
			subtitle_key = "library.subtitle_recent"
		_:
			title_key = "library.title_home"
			subtitle_key = "library.subtitle_home"

	var column := UI.column(16)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(column, 24, 20, 24, 24))

	# A flow bar wraps filter groups at narrow widths instead of clipping the
	# reset button off the right edge.
	_filter_bar = UI.flow(10, 8)
	column.add_child(_filter_bar)
	_build_filters()

	var scroll := UI.scroll(UI.column(22), false)
	column.add_child(scroll)
	var body: VBoxContainer = scroll.get_child(0) as VBoxContainer
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)

	_row_host = UI.column(18)
	body.add_child(_row_host)

	var grid_wrap := UI.column(10)
	body.add_child(grid_wrap)
	_count_label = UI.label("", "Small")
	grid_wrap.add_child(_count_label)
	_grid = UI.flow(16, 16)
	grid_wrap.add_child(_grid)
	_empty_state = _build_empty_state()
	grid_wrap.add_child(_empty_state)
	refresh_list()


func _determine_preset() -> void:
	match Nav.current_route():
		Nav.ROUTE_ALL_GAMES:
			preset = Preset.ALL
		Nav.ROUTE_FAVORITES:
			preset = Preset.FAVORITES
		Nav.ROUTE_RECENT:
			preset = Preset.RECENT
		_:
			preset = Preset.HOME


func _build_filters() -> void:
	var categories: Array = [{"label": Loc.t("library.category_all"), "value": ""}]
	for category: String in Catalog.categories():
		categories.append({"label": Loc.t("category.%s" % category), "value": category})
	_filter_bar.add_child(_filter_group("library.category_label", UI.dropdown(categories, _category_filter, func(value: String) -> void:
		_category_filter = value
		refresh_list()
	)))

	var player_options: Array = [{"label": Loc.t("library.players_any"), "value": "0"}]
	for count: int in range(2, 9):
		player_options.append({"label": Loc.tp("library.players_exact", count), "value": str(count)})
	_filter_bar.add_child(_filter_group("library.players_label", UI.dropdown(player_options, str(_players_filter), func(value: String) -> void:
		_players_filter = int(value)
		refresh_list()
	)))

	var sort_options: Array = [
		{"label": Loc.t("library.sort_catalog"), "value": str(Catalog.SortKey.CATALOG_ORDER)},
		{"label": Loc.t("library.sort_name"), "value": str(Catalog.SortKey.NAME)},
		{"label": Loc.t("library.sort_players"), "value": str(Catalog.SortKey.PLAYERS)},
		{"label": Loc.t("library.sort_recent"), "value": str(Catalog.SortKey.RECENT)},
		{"label": Loc.t("library.sort_complexity"), "value": str(Catalog.SortKey.COMPLEXITY)},
		{"label": Loc.t("library.sort_playtime"), "value": str(Catalog.SortKey.PLAYTIME)},
	]
	var sort_control := UI.dropdown(sort_options, str(_sort_key), func(value: String) -> void:
		_sort_key = int(value)
		refresh_list()
	)
	var sort_group := _filter_group("library.sort_label", sort_control)
	var direction := UI.button("↓" if _sort_ascending else "↑", "ChipButton", func() -> void:
		_sort_ascending = not _sort_ascending
		rebuild_filters()
		refresh_list()
	)
	direction.tooltip_text = Loc.t("library.sort_direction")
	sort_group.add_child(direction)
	_filter_bar.add_child(sort_group)

	var playable := UI.toggle(Loc.t("library.playable_only"), _playable_only, func(value: bool) -> void:
		_playable_only = value
		refresh_list()
	)
	_filter_bar.add_child(playable)

	var clear := UI.button(Loc.t("library.reset_filters"), "GhostButton", func() -> void:
		_category_filter = ""
		_players_filter = 0
		_sort_key = Catalog.SortKey.CATALOG_ORDER
		_playable_only = false
		_search = ""
		rebuild_filters()
		refresh_list()
	)
	_filter_bar.add_child(clear)


func _filter_group(key: String, control: Control) -> HBoxContainer:
	var group := UI.row(7)
	group.add_child(_filter_caption(key))
	group.add_child(control)
	return group


func _filter_caption(key: String) -> Label:
	var label := UI.label(Loc.t(key), "Caption")
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func rebuild_filters() -> void:
	for child: Node in _filter_bar.get_children():
		_filter_bar.remove_child(child)
		child.queue_free()
	_build_filters()


func _build_empty_state() -> VBoxContainer:
	var box := UI.column(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UI.centered("◇", "Display"))
	box.add_child(UI.centered(Loc.t("library.empty_title"), "Subtitle"))
	box.add_child(UI.centered(Loc.t("library.empty_body"), "Small"))
	return box


# ------------------------------------------------------------------- content

func on_enter() -> void:
	_select_sidebar()
	refresh_list()


func _select_sidebar() -> void:
	# The documents/sidebar highlight already follows Nav; nothing else to do.
	pass


func refresh_list() -> void:
	if _grid == null:
		return
	for card: GameCard in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
	while _grid.get_child_count() > 0:
		var child := _grid.get_child(0)
		_grid.remove_child(child)
		child.queue_free()
	for child: Node in _row_host.get_children():
		_row_host.remove_child(child)
		child.queue_free()

	if preset == Preset.HOME:
		_build_home_rows()

	var filters: Dictionary = {
		"search": _search,
		"categories": [] if _category_filter.is_empty() else [_category_filter],
		"players": _players_filter,
		"playable_only": _playable_only,
		"favorites_only": preset == Preset.FAVORITES,
		"recent_only": preset == Preset.RECENT,
	}
	var entries := Catalog.query(filters, _sort_key as Catalog.SortKey, _sort_ascending)
	if not bool(Prefs.get_value("general/show_development_titles", true)):
		var filtered: Array[GameEntry] = []
		for entry: GameEntry in entries:
			if entry.status == GameEntry.Status.PLAYABLE:
				filtered.append(entry)
		entries = filtered

	var heading_key := "library.section_all"
	match preset:
		Preset.FAVORITES:
			heading_key = "library.section_favorites"
		Preset.RECENT:
			heading_key = "library.section_recent"
		Preset.ALL:
			heading_key = "library.section_all"
		_:
			heading_key = "library.section_all"
	if preset != Preset.HOME:
		_count_label.text = "%s  ·  %s" % [Loc.t(heading_key), Loc.tp("library.result_count", entries.size())]
	else:
		_count_label.text = Loc.tp("library.result_count", entries.size())
	for entry: GameEntry in entries:
		_grid.add_child(_make_card(entry, CARD_MIN_WIDTH))
	_empty_state.visible = entries.is_empty()
	if entries.is_empty():
		_build_empty_message()


func _build_empty_message() -> void:
	var title := _empty_state.get_child(1) as Label
	var body := _empty_state.get_child(2) as Label
	var message_key := "library.empty_body"
	if not _search.strip_edges().is_empty():
		message_key = "library.empty_search"
	elif preset == Preset.FAVORITES:
		message_key = "library.empty_favorites"
	elif preset == Preset.RECENT:
		message_key = "library.empty_recent"
	title.text = Loc.t("library.empty_title")
	body.text = Loc.t(message_key)


func _build_home_rows() -> void:
	var recent: Array[GameEntry] = []
	for entry: GameEntry in Catalog.recently_played():
		if Catalog.play_count(entry.id) > 0:
			recent.append(entry)
	if not recent.is_empty():
		_row_host.add_child(_build_row(Loc.t("library.row_continue"), recent.slice(0, mini(5, recent.size()))))
	var favorites := Catalog.favorites()
	if not favorites.is_empty():
		_row_host.add_child(_build_row(Loc.t("library.row_favorites"), favorites.slice(0, mini(5, favorites.size()))))


func _build_row(title: String, entries: Array[GameEntry]) -> Control:
	var box := UI.column(10)
	var header := UI.row(10)
	var label := UI.heading(title, "Subtitle")
	header.add_child(label)
	header.add_child(UI.spacer())
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, GameCard.CARD_HEIGHT + 12)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var row := UI.row(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	for entry: GameEntry in entries:
		row.add_child(_make_card(entry, ROW_CARD_WIDTH, GameCard.CARD_HEIGHT))
	return box


func _make_card(entry: GameEntry, min_width: int, height: int = -1) -> GameCard:
	var card := GameCard.new()
	card.custom_minimum_size = Vector2(min_width, height if height > 0 else GameCard.CARD_HEIGHT)
	card.configure(entry)
	card.activated.connect(_on_card_activated)
	card.favorite_toggled.connect(_on_favorite_toggled)
	_cards.append(card)
	return card


func _on_card_activated(game_id: String) -> void:
	Nav.go(Nav.ROUTE_GAME_DETAILS, {"game_id": game_id})


func _on_favorite_toggled(game_id: String, now_favorite: bool) -> void:
	Notify.info(Loc.t("library.favorite_added" if now_favorite else "library.favorite_removed", {
		"game": Catalog.get_entry(game_id).display_name() if Catalog.exists(game_id) else game_id,
	}))
	if preset == Preset.FAVORITES:
		refresh_list()


# ------------------------------------------------------------- search support

func wants_search() -> bool:
	return true


func search_text() -> String:
	return _search


func on_search(text: String) -> void:
	_search = text
	refresh_list()


func refresh_texts() -> void:
	rebuild_filters()
	refresh_list()
