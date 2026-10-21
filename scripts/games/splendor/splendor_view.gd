extends GameView
class_name SplendorView
## Splendor table: noble strip, one market row per tier, the gem supply and a
## panel per player with their tokens and bonuses.
##
## The view renders `engine.public_state()` plus the acting player's private
## reserve and submits action keys through the session; it never mutates the
## engine. Reserved cards are hidden information, so hotseat play confirms the
## handover before each turn and the reserved area only ever shows the cards of
## the player who is acting.

## Gem tint per token colour. "black" is the onyx gem: a violet tint keeps it
## readable on the dark table (Palette has no gem colours of its own).
const GEM_TINTS: Dictionary = {
	"white": Color("e9edf5"),
	"blue": Color("4ea1ff"),
	"green": Color("39d98a"),
	"red": Color("ff6b78"),
	"black": Color("9d8cf0"),
	"gold": Color("ffc24b"),
}
const CARD_WIDTH: int = 176
const CARD_HEIGHT: int = 84

var _content: VBoxContainer
var _status: Label
var _nobles_flow: HFlowContainer
var _nobles_count: Label
var _market_flows: Array[HFlowContainer] = []
var _deck_labels: Array[Label] = []
var _blind_buttons: Array[Button] = []
var _pile_box: HFlowContainer
var _pile_buttons: Dictionary = {}
var _pile_double_buttons: Dictionary = {}
var _players_flow: HFlowContainer
var _reserved_flow: HFlowContainer
var _reserved_hint: Label

## Action key for every board widget, keyed by "take:<gems>", "buy:<card>",
## "reserve:<card>" and "blind:<tier>".
var _keys: Dictionary = {}
var _selection: Array[String] = []
var _take_button: Button = null
var _selection_chip: PanelContainer = null


func requires_handover() -> bool:
	return true


# ------------------------------------------------------------------ structure

func build_board() -> void:
	var scroll := UI.scroll(null)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A four-card tier only needs so much width; centering the scroll viewport
	# keeps the board from hugging the left edge on 1920px displays while still
	# filling the narrower layout at 1280x720. The cap must sit outside the
	# ScrollContainer: inside, the scroll sizes its child to the content width
	# and there is no leftover space left to center.
	add_child(UI.max_width(scroll, 1280, true))
	_content = UI.column(8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_status = UI.label("", "Small")
	_content.add_child(_status)

	# Nobles and the token bank share one compact top row so all three card
	# tiers and the bank fit above the fold at 1600x900.
	# Noble rewards and the gem bank share a row while there is room. Below
	# roughly 1400px the gem buttons wrap onto their own line instead of
	# pushing the last gem (gold) past the right edge of the page.
	var top := UI.flow(12, 12)
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(top)
	var nobles_box := UI.column(3)
	nobles_box.custom_minimum_size = Vector2(446, 0)
	top.add_child(nobles_box)
	var nobles_head := UI.row(8)
	nobles_head.add_child(UI.heading(Loc.t("game.splendor.nobles_title"), "Subtitle"))
	var nobles_count := UI.label("", "Caption")
	nobles_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	nobles_head.add_child(nobles_count)
	_nobles_count = nobles_count
	nobles_box.add_child(nobles_head)
	_nobles_flow = UI.flow(6, 6)
	_nobles_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nobles_box.add_child(_nobles_flow)

	var supply_box := UI.column(3)
	supply_box.custom_minimum_size = Vector2(430, 0)
	top.add_child(supply_box)
	var supply_head := UI.row(8)
	supply_head.add_child(UI.heading(Loc.t("game.splendor.supply_title"), "Subtitle"))
	supply_box.add_child(supply_head)
	_pile_box = UI.flow(6, 6)
	supply_box.add_child(_pile_box)
	for colour: String in SplendorEngine.ALL_COLOURS:
		var cell := UI.row(2)
		var button := UI.button("", "Button", _on_pile_pressed.bind(colour))
		button.custom_minimum_size = Vector2(58, 32)
		button.add_theme_font_size_override("font_size", ThemeBuilder.SIZE_CAPTION)
		button.add_theme_color_override("font_color", GEM_TINTS.get(colour, Palette.TEXT))
		cell.add_child(button)
		_pile_buttons[colour] = button
		var double := UI.button("×2", "GhostButton", _on_double_pressed.bind(colour))
		double.custom_minimum_size = Vector2(26, 32)
		double.add_theme_font_size_override("font_size", ThemeBuilder.SIZE_CAPTION)
		double.tooltip_text = Loc.t("game.splendor.take_two_hint", {"gem": Loc.t(_gem_key(colour))})
		double.visible = false
		cell.add_child(double)
		_pile_double_buttons[colour] = double
		_pile_box.add_child(cell)

	# Tier three on top, like the physical board. The tier caption sits beside
	# the cards instead of in a separate header row, saving three rows of height.
	for tier: int in [3, 2, 1]:
		var tier_row := UI.row(10)
		tier_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var side := UI.column(3)
		side.custom_minimum_size = Vector2(112, 0)
		side.add_child(UI.heading(_tier_text(tier), "Subtitle"))
		var deck := UI.label("", "Caption")
		deck.autowrap_mode = TextServer.AUTOWRAP_OFF
		side.add_child(deck)
		_deck_labels.append(deck)
		var blind := UI.button(Loc.t("game.splendor.reserve_blind"), "GhostButton", _on_blind_pressed.bind(tier))
		blind.custom_minimum_size = Vector2(106, 28)
		blind.add_theme_font_size_override("font_size", ThemeBuilder.SIZE_CAPTION)
		blind.tooltip_text = Loc.t("game.splendor.reserve_blind_hint", {"tier": _tier_text(tier)})
		_blind_buttons.append(blind)
		side.add_child(blind)
		tier_row.add_child(side)
		var flow := UI.flow(6, 6)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_market_flows.append(flow)
		tier_row.add_child(flow)
		_content.add_child(tier_row)

	_content.add_child(UI.divider())
	_content.add_child(UI.section_header(Loc.t("game.splendor.players_title"), ""))
	_players_flow = UI.flow(10, 10)
	_content.add_child(_players_flow)
	var reserved_head := UI.row(8)
	reserved_head.add_child(UI.heading(Loc.t("game.splendor.reserved_title"), "Subtitle"))
	_reserved_hint = UI.label("", "Small")
	_reserved_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reserved_head.add_child(_reserved_hint)
	_content.add_child(reserved_head)
	_reserved_flow = UI.flow(10, 10)
	_content.add_child(_reserved_flow)


# -------------------------------------------------------------------- refresh

func refresh_board() -> void:
	if engine == null:
		return
	var table := engine as SplendorEngine
	if table == null:
		return
	var state := table.public_state()
	_collect_keys()
	_prune_selection(table)
	_status.text = _status_text(table)
	_refresh_nobles(table, state)
	_refresh_market(table, state)
	_refresh_piles(table, state)
	_refresh_players(table, state)
	_refresh_reserved(table)
	_refresh_extras()


## Indexes the legal action keys the board widgets may submit.
func _collect_keys() -> void:
	_keys.clear()
	if engine == null or engine.finished:
		return
	for action: Variant in legal_actions():
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		var key := VariantUtil.as_string(entry.get("key", ""), "")
		match VariantUtil.as_string(entry.get("type", ""), ""):
			"take":
				_keys["take:" + VariantUtil.as_string(entry.get("take", ""), "")] = key
			"buy":
				_keys["buy:%d" % VariantUtil.as_int(entry.get("_card", -1), -1)] = key
			"reserve":
				if bool(entry.get("_blind", false)):
					_keys["blind:%d" % VariantUtil.as_int(entry.get("_tier", 0), 0)] = key
				else:
					_keys["reserve:%d" % VariantUtil.as_int(entry.get("_card", -1), -1)] = key


## Drops selected colours that are no longer part of a legal take.
func _prune_selection(table: SplendorEngine) -> void:
	if table.finished:
		_selection.clear()
		return
	if _take_key().is_empty() and _selection.size() >= 3:
		_selection.clear()


func _status_text(table: SplendorEngine) -> String:
	var lines := PackedStringArray()
	if table.finished:
		lines.append(Loc.t("game.common.finished_status", {"winner": table.winner_text()}))
	else:
		if table.phase() == "final_round":
			lines.append(Loc.t("game.splendor.final_round_notice", {"points": table.target_points}))
		if _selection.is_empty():
			lines.append(Loc.t("game.splendor.hint"))
		else:
			lines.append(Loc.t("game.splendor.selection", {"gems": _selection_text()}))
	return "\n".join(lines)


func _refresh_nobles(table: SplendorEngine, state: Dictionary) -> void:
	_clear(_nobles_flow)
	var owners: Array = VariantUtil.as_array(state.get("noble_owner", []))
	var waiting := 0
	for entry: Variant in VariantUtil.as_array(state.get("nobles", [])):
		var noble_id := VariantUtil.as_int(entry, -1)
		var noble := table.noble_data(noble_id)
		if noble.is_empty():
			continue
		var owner := VariantUtil.as_int(owners[noble_id], -1) if noble_id < owners.size() else -1
		var cost_text := _cost_text(noble.get("cost", []))
		var tint: Color = Palette.TEXT_MUTED
		if owner < 0:
			waiting += 1
			tint = Palette.WARNING
		var panel := UI.panel("TransparentPanel")
		panel.add_theme_stylebox_override("panel", ThemeBuilder.flat(
			Palette.tint(tint, 0.08), Palette.tint(tint, 0.45), 1, 7, 4))
		panel.tooltip_text = "%s · %s" % [
			Loc.tp("game.splendor.points", VariantUtil.as_int(noble.get("points", 0), 0)), cost_text]
		var row := UI.row(5)
		var points_label := UI.label(Loc.tp("game.splendor.points", VariantUtil.as_int(noble.get("points", 0), 0)), "Caption")
		points_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		points_label.add_theme_color_override("font_color", tint)
		row.add_child(points_label)
		row.add_child(_cost_chips(noble.get("cost", [])))
		if owner >= 0:
			var owner_label := UI.label("→ " + table.player_name(owner), "Caption")
			owner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			owner_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			row.add_child(owner_label)
		panel.add_child(row)
		_nobles_flow.add_child(panel)
	_nobles_count.text = Loc.tp("game.splendor.nobles_left", waiting) if bool(state.get("nobles_enabled", true)) else ""


func _refresh_market(table: SplendorEngine, state: Dictionary) -> void:
	var market: Array = state.get("market", [])
	var decks: Array = state.get("_decks", [])
	# Rows are built top down (tier three first), so the market index is
	# mirrored: row 0 shows tier 3.
	for row_index: int in range(3):
		var tier := 3 - row_index
		var flow := _market_flows[row_index]
		_clear(flow)
		var row: Array = VariantUtil.as_array(market[tier - 1]) if tier - 1 < market.size() else []
		for slot: Variant in row:
			var card_id := VariantUtil.as_int(slot, -1)
			if card_id < 0:
				flow.add_child(_empty_slot())
				continue
			flow.add_child(_card_widget(table, card_id, true, true))
		if row_index < _deck_labels.size():
			var deck_size: int = VariantUtil.as_array(decks[tier - 1]).size() if tier - 1 < decks.size() else 0
			_deck_labels[row_index].text = Loc.tp("game.splendor.deck_count", deck_size)
			var blind := _blind_buttons[row_index]
			blind.disabled = not _keys.has("blind:%d" % tier)


func _empty_slot() -> Control:
	var panel := UI.panel("TransparentPanel")
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.add_child(UI.centered(Loc.t("game.splendor.empty_slot"), "Caption"))
	return panel


func _refresh_piles(table: SplendorEngine, state: Dictionary) -> void:
	var piles: Dictionary = VariantUtil.as_dict(state.get("piles", {}))
	for colour: String in _pile_buttons:
		var button: Button = _pile_buttons[colour]
		var count := VariantUtil.as_int(piles.get(colour, 0), 0)
		var label := "%s %d" % [Loc.t(_gem_key(colour)), count]
		if _selection.has(colour):
			label = "▸ " + label
		button.text = label
		button.disabled = table.finished or count <= 0 or not is_my_turn()
		var tint: Color = GEM_TINTS.get(colour, Palette.TEXT)
		button.add_theme_stylebox_override("normal", ThemeBuilder.flat(Palette.tint(tint, 0.16 if _selection.has(colour) else 0.08), tint, 2 if _selection.has(colour) else 1, 7, 0))
		var double: Button = _pile_double_buttons[colour]
		double.visible = _keys.has("take:%s,%s" % [colour, colour])
		double.disabled = table.finished or not is_my_turn()


func _refresh_players(table: SplendorEngine, state: Dictionary) -> void:
	_clear(_players_flow)
	var tokens: Array = state.get("tokens", [])
	var bonuses: Array = state.get("bonuses", [])
	var points: Array = state.get("points", [])
	var reserved_counts: Array = state.get("reserved_counts", [])
	for index: int in range(table.player_count()):
		var box := UI.column(4)
		box.custom_minimum_size = Vector2(280, 0)
		var head := UI.row(6)
		var name_label := UI.label(table.player_name(index), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if table.decision_player() == index and not table.finished:
			name_label.add_theme_color_override("font_color", Palette.POSITIVE)
		head.add_child(name_label)
		if table.is_bot(index):
			head.add_child(UI.chip(Loc.t("game.common.bot"), Palette.TEXT_MUTED))
		head.add_child(UI.chip(Loc.tp("game.splendor.points", VariantUtil.as_int(points[index], 0) if index < points.size() else 0), Palette.WARNING))
		head.add_child(UI.chip(Loc.tp("game.splendor.reserved_chip", VariantUtil.as_int(reserved_counts[index], 0) if index < reserved_counts.size() else 0), Palette.TEXT_MUTED))
		box.add_child(head)
		box.add_child(UI.kv_row(Loc.t("game.splendor.gems_label"),
			_counts_text(tokens[index] if index < tokens.size() else {})))
		box.add_child(UI.kv_row(Loc.t("game.splendor.bonuses_label"),
			_counts_text(bonuses[index] if index < bonuses.size() else {})))
		var card := UI.panel_with(box, "CardPanel", 10)
		card.custom_minimum_size = Vector2(300, 0)
		_players_flow.add_child(card)


func _refresh_reserved(table: SplendorEngine) -> void:
	_clear(_reserved_flow)
	_reserved_hint.text = ""
	if engine.finished:
		return
	var actor := acting_player()
	if actor < 0 or actor >= table.player_count():
		return
	var reserved: Array = table.private_state(actor).get("reserved", [])
	if reserved.is_empty():
		_reserved_hint.text = Loc.t("game.splendor.no_reserved")
		return
	_reserved_hint.text = Loc.t("game.splendor.reserved_hint", {"player": table.player_name(actor)})
	for card_id: Variant in VariantUtil.as_array(reserved):
		_reserved_flow.add_child(_card_widget(table, VariantUtil.as_int(card_id, -1), true, false))


func _refresh_extras() -> void:
	if _take_button != null and is_instance_valid(_take_button):
		_take_button.disabled = _take_key().is_empty()
	if _selection_chip != null and is_instance_valid(_selection_chip):
		var label := _selection_chip.get_child(0) as Label
		if label != null:
			label.text = Loc.t("game.splendor.selection", {"gems": _selection_text()})


# -------------------------------------------------------------------- widgets

## Compact colour/count pills for a card or noble cost. The full localised names
## live in the parent tooltip; the pills keep rows short enough for 1280x720.
func _cost_chips(cost: Variant) -> HBoxContainer:
	var costs := UI.row(4)
	var values: Array = VariantUtil.as_array(cost)
	for i: int in range(values.size()):
		var count := VariantUtil.as_int(values[i], 0)
		if count <= 0:
			continue
		var colour := String(SplendorEngine.GEM_COLOURS[i]) if i < SplendorEngine.GEM_COLOURS.size() else "gold"
		var tint: Color = GEM_TINTS.get(colour, Palette.TEXT)
		var chip := UI.panel("TransparentPanel")
		chip.custom_minimum_size = Vector2(18, 18)
		chip.add_theme_stylebox_override("panel", ThemeBuilder.flat(
			Palette.tint(tint, 0.14), Palette.tint(tint, 0.55), 1, 6, 2))
		chip.tooltip_text = "%s %d" % [Loc.t(_gem_key(colour)), count]
		var count_label := UI.label(str(count), "Caption", HORIZONTAL_ALIGNMENT_CENTER)
		count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", tint)
		chip.add_child(count_label)
		costs.add_child(chip)
	return costs


func _card_widget(table: SplendorEngine, card_id: int, show_buy: bool, show_reserve: bool) -> Control:
	var card := table.card_data(card_id)
	var points := VariantUtil.as_int(card.get("points", 0), 0)
	var bonus := VariantUtil.as_string(card.get("bonus", ""), "")
	var accent: Color = GEM_TINTS.get(bonus, Palette.ACCENT)
	var cost_text := _cost_text(card.get("cost", []))
	var panel := UI.panel("TransparentPanel")
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_ELEVATED, accent, 1, ThemeBuilder.RADIUS, 0))
	panel.tooltip_text = "%s · %s" % [Loc.t(_gem_key(bonus)), cost_text]
	var box := UI.column(3)
	panel.add_child(UI.margin_xy(box, 8, 5, 8, 5))

	var head := UI.row(5)
	var glyph := UI.label("◆", "Small")
	glyph.autowrap_mode = TextServer.AUTOWRAP_OFF
	glyph.add_theme_font_size_override("font_size", 12)
	glyph.add_theme_color_override("font_color", accent)
	head.add_child(glyph)
	var title := UI.label(Loc.t(_gem_key(bonus)), "Small")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Palette.TEXT)
	head.add_child(title)
	var points_label := UI.label(("★ %d" % points) if points > 0 else "", "Small")
	points_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	points_label.add_theme_font_size_override("font_size", 12)
	points_label.add_theme_color_override("font_color", Palette.WARNING)
	head.add_child(points_label)
	box.add_child(head)

	# Colour chips keep the complete price glanceable in a compact card. The
	# full localised names remain in the card tooltip.
	box.add_child(_cost_chips(card.get("cost", [])))
	box.add_child(UI.spacer(0, true))

	var actions := UI.row(3)
	if show_buy:
		var buy_key := VariantUtil.as_string(_keys.get("buy:%d" % card_id, ""), "")
		var buy := UI.button(Loc.t("game.splendor.buy"), "CompactButton", func() -> void: _submit_key(buy_key))
		buy.disabled = buy_key.is_empty() or not is_my_turn()
		buy.custom_minimum_size = Vector2(0, 26)
		buy.add_theme_font_size_override("font_size", 11)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(buy)
	if show_reserve:
		var reserve_key := VariantUtil.as_string(_keys.get("reserve:%d" % card_id, ""), "")
		var reserve := UI.button("↧", "CompactButton", func() -> void: _submit_key(reserve_key), Loc.t("game.splendor.reserve"))
		reserve.disabled = reserve_key.is_empty() or not is_my_turn()
		reserve.custom_minimum_size = Vector2(28, 26)
		reserve.add_theme_font_size_override("font_size", 12)
		actions.add_child(reserve)
	if actions.get_child_count() > 0:
		box.add_child(actions)
	return panel


## Human readable cost, e.g. "white 4, blue 4".
func _cost_text(cost: Variant) -> String:
	if not (cost is Array) or VariantUtil.as_array(cost).is_empty():
		return ""
	var parts := PackedStringArray()
	var values: Array = VariantUtil.as_array(cost)
	for i: int in range(values.size()):
		var count := VariantUtil.as_int(values[i], 0)
		if count > 0:
			parts.append("%s %d" % [Loc.t(_gem_key(SplendorEngine.GEM_COLOURS[i])), count])
	if parts.is_empty():
		return Loc.t("game.splendor.no_cost")
	return ", ".join(parts)


func _counts_text(counts: Variant, include_gold: bool = true) -> String:
	if not (counts is Dictionary):
		return Loc.t("game.splendor.none")
	var parts := PackedStringArray()
	for colour: String in SplendorEngine.ALL_COLOURS:
		if colour == "gold" and not include_gold:
			continue
		var count := VariantUtil.as_int(VariantUtil.as_dict(counts).get(colour, 0), 0)
		if count > 0:
			parts.append("%s %d" % [Loc.t(_gem_key(colour)), count])
	if parts.is_empty():
		return Loc.t("game.splendor.none")
	return ", ".join(parts)


func _selection_text() -> String:
	if _selection.is_empty():
		return Loc.t("game.splendor.none")
	var names := PackedStringArray()
	for colour: String in _selection:
		names.append(Loc.t(_gem_key(colour)))
	return ", ".join(names)


func _tier_text(tier: int) -> String:
	match tier:
		2:
			return Loc.t("game.splendor.tier_two")
		3:
			return Loc.t("game.splendor.tier_three")
		_:
			return Loc.t("game.splendor.tier_one")


func _gem_key(colour: String) -> String:
	match colour:
		"white":
			return "game.splendor.gem.white"
		"blue":
			return "game.splendor.gem.blue"
		"green":
			return "game.splendor.gem.green"
		"red":
			return "game.splendor.gem.red"
		"black":
			return "game.splendor.gem.black"
		_:
			return "game.splendor.gem.gold"


func _on_pile_pressed(colour: String) -> void:
	if engine == null or engine.finished or not is_my_turn():
		return
	var index := _selection.find(colour)
	if index >= 0:
		_selection.remove_at(index)
	elif _selection.size() < 3:
		_selection.append(colour)
	Audio.play(Audio.Sfx.CLICK)
	refresh_board()


func _on_double_pressed(colour: String) -> void:
	var key := VariantUtil.as_string(_keys.get("take:%s,%s" % [colour, colour], ""), "")
	if key.is_empty():
		return
	_selection.clear()
	_submit_key(key)


func _on_blind_pressed(tier: int) -> void:
	var key := VariantUtil.as_string(_keys.get("blind:%d" % tier, ""), "")
	if key.is_empty():
		return
	# Audio feedback is owned by GameScreen._on_view_action() on the single
	# submission path; the view used to play the same CARD sound a second time.
	submit(key)


func _on_take_pressed() -> void:
	var key := _take_key()
	if key.is_empty():
		view_message.emit("game.splendor.selection_incomplete", {})
		return
	_selection.clear()
	_submit_key(key)


func _on_clear_pressed() -> void:
	_selection.clear()
	Audio.play(Audio.Sfx.CLICK)
	refresh_board()
	_refresh_extras()
	view_message.emit("game.common.nothing_to_show", {})


## Key of the take action matching the current selection, or "".
func _take_key() -> String:
	if _selection.is_empty():
		return ""
	var sorted := _selection.duplicate()
	sorted.sort()
	var parts := PackedStringArray()
	for colour: Variant in sorted:
		parts.append(VariantUtil.as_string(colour, ""))
	return VariantUtil.as_string(_keys.get("take:" + ",".join(parts), ""), "")


func _submit_key(key: String) -> void:
	if key.is_empty() or not is_my_turn():
		return
	# The screen plays the card sound on the routed submission (GameScreen
	# _on_view_action); playing it here duplicated every take/purchase click.
	submit(key)


func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if engine == null or engine.finished:
		return out
	_selection_chip = UI.chip(Loc.t("game.splendor.selection", {"gems": _selection_text()}), Palette.ACCENT)
	_selection_chip.custom_minimum_size = Vector2(150, 0)
	out.append(_selection_chip)
	_take_button = UI.button(Loc.t("game.splendor.take"), "PrimaryButton", _on_take_pressed)
	_take_button.disabled = _take_key().is_empty()
	out.append(_take_button)
	if not _selection.is_empty():
		out.append(UI.button(Loc.t("common.cancel"), "GhostButton", _on_clear_pressed))
	return out


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
