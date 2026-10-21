extends ScreenBase
## Star Realms edition picker: choose the sets that are dealt into the trade deck.
##
## The screen is a thin editor over the edition registry
## (`data/catalog/star_realms_sets.json`): every row comes from
## [method Catalog.edition_sets], so adding a set to the JSON is enough for it to
## appear here. A change is persisted immediately through
## [method Prefs.set_star_realms_sets] after [method Catalog.validate_selection],
## which forces the required base set in and rejects sets whose card data is not
## implemented yet - the registry, not this screen, decides what is playable.

var entry: GameEntry = null

var _content: VBoxContainer
var _summary: Label


func build() -> void:
	title_key = "sr.picker.title"
	subtitle_key = "sr.selection_hint_short"
	_content = UI.column(16)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(_content)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(scroll, 24, 20, 24, 24))


func on_enter() -> void:
	entry = Catalog.get_entry(String(params.get("game_id", "")))
	if entry == null or not entry.has_editions:
		Log.warn("StarRealmsSets: game has no edition registry", {"game_id": params.get("game_id", "")})
		Nav.go(Nav.ROUTE_LIBRARY, {}, "replace")
		return
	_rebuild()


func _rebuild() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if entry == null:
		return
	_content.add_child(UI.section_header(Loc.t("sr.selection_title"), Loc.t("sr.picker.intro")))
	_summary = UI.label("", "Small")
	_content.add_child(_summary)

	var sets := Catalog.edition_sets(entry.edition_registry)
	if sets.is_empty():
		_content.add_child(UI.label(Loc.t("sr.picker.empty"), "Small"))
		return
	var selected: Array = Prefs.selected_star_realms_sets()
	for set: ExpansionSet in sets:
		_content.add_child(_set_panel(set, selected.has(set.id)))
	_content.add_child(_actions_row())
	_refresh_summary(sets)


func _refresh_summary(sets: Array[ExpansionSet]) -> void:
	var selected: Array = Prefs.selected_star_realms_sets()
	var enabled := 0
	for set: ExpansionSet in sets:
		if selected.has(set.id):
			enabled += 1
	_summary.text = Loc.t("sr.picker.summary", {"count": enabled, "total": sets.size()})


func _set_panel(set: ExpansionSet, active: bool) -> PanelContainer:
	var row := UI.row(12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var toggle := UI.toggle(set.display_name(), active, func(pressed: bool) -> void:
		_apply(set.id, pressed)
	)
	toggle.disabled = set.required or not set.content_ready
	toggle.custom_minimum_size = Vector2(300, 0)
	row.add_child(toggle)

	var info := UI.column(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label(set.description(), "Small"))
	# Four status chips can exceed the row at 1280 px; let them wrap instead of
	# widening the whole page past the right edge.
	var meta := UI.flow(8, 8)
	meta.add_child(UI.chip(set.status_text(), set.status_color()))
	meta.add_child(UI.chip(set.players_text(), Palette.INFO))
	if set.card_count > 0:
		meta.add_child(UI.chip(Loc.t("sr.picker.cards", {
			"implemented": set.implemented_card_count,
			"total": set.card_count,
		}), Palette.ACCENT if set.content_ready else Palette.TEXT_MUTED))
	else:
		meta.add_child(UI.chip(Loc.t("sr.picker.cards_pending"), Palette.TEXT_MUTED))
	if not set.content_ready:
		meta.add_child(UI.chip(Loc.t("sr.picker.unavailable"), Palette.WARNING))
	info.add_child(meta)
	if set.required:
		info.add_child(UI.label(Loc.t("sr.picker.required_note"), "Caption"))
	elif set.depends_on.has(StarRealmsCards.SET_CORE):
		info.add_child(UI.label(Loc.t("sr.picker.depends"), "Caption"))
	row.add_child(info)
	return UI.panel_with(row, "CardPanel", 14)


func _actions_row() -> HBoxContainer:
	var row := UI.row(10)
	row.add_child(UI.button(Loc.t("sr.picker.reset"), "GhostButton", func() -> void:
		_apply_selection([StarRealmsCards.SET_CORE])
	))
	row.add_child(UI.spacer())
	row.add_child(UI.button(Loc.t("common.back"), "PrimaryButton", func() -> void:
		Nav.back()
	))
	return row


## Writes one toggle through the registry validation, so the stored selection can
## never contain an unknown, conflicting or unimplemented set.
func _apply(set_id: String, enabled: bool) -> void:
	var selection: Array = Prefs.selected_star_realms_sets()
	if enabled and not selection.has(set_id):
		selection.append(set_id)
	elif not enabled:
		selection.erase(set_id)
	_apply_selection(selection)


func _apply_selection(selection: Array) -> void:
	var outcome := Catalog.validate_selection(entry.edition_registry, selection)
	var cleaned: Array = outcome.get("selected", [])
	Prefs.set_star_realms_sets(cleaned)
	Log.info("StarRealmsSets: selection saved", {"sets": cleaned, "rejected": outcome.get("rejected", [])})
	Notify.info(Loc.t("sr.picker.saved"))
	_rebuild()


func refresh_texts() -> void:
	if entry != null:
		_rebuild()
