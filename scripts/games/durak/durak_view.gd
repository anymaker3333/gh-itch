extends GameView
## Durak table.
##
## The view renders the public table (trump card, deck size, attack/defence
## pairs) plus the local hand, and turns a card click into the matching legal
## action key. It never mutates the engine: `Take` and `Done attacking` reach the
## action bar through the engine's own action list.

const SUIT_SYMBOLS: Dictionary = {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const RED_SUITS: Array[String] = ["H", "D"]
const CARD_ACCENT_RED: Color = Color("e2574c")
const CARD_ACCENT_DARK: Color = Color("c9d4e6")

var _rail: HBoxContainer
var _table_label: Label
var _table_row: HFlowContainer
var _hand_label: Label
var _hand_row: HFlowContainer
var _status: Label
var _players_box: VBoxContainer


func requires_handover() -> bool:
	return true


func build_board() -> void:
	var layout := UI.row(16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var left := UI.column(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	_rail = UI.hsep(8)
	left.add_child(UI.panel_with(_rail, "ElevatedPanel", 8))
	_table_label = UI.label(Loc.t("game.durak.table_label"), "Subtitle")
	left.add_child(_table_label)
	_table_row = UI.flow(14, 14)
	left.add_child(_table_row)
	left.add_child(UI.spacer(4, true))
	_hand_label = UI.label(Loc.t("game.durak.hand_label"), "Subtitle")
	left.add_child(_hand_label)
	_hand_row = UI.flow(10, 10)
	left.add_child(_hand_row)

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(330, 0)
	layout.add_child(side)
	_status = UI.label("", "Body")
	side.add_child(_status)
	side.add_child(UI.divider())
	side.add_child(UI.label(Loc.t("game.durak.players_label"), "Subtitle"))
	_players_box = UI.column(8)
	side.add_child(_players_box)
	side.add_child(UI.divider())
	side.add_child(UI.label(Loc.t("game.durak.hint"), "Caption"))


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	_refresh_rail(state)
	_refresh_table(state)
	_refresh_hand(state)
	_refresh_players(state)
	_refresh_status(state)


func _refresh_rail(state: Dictionary) -> void:
	_clear(_rail)
	var trump := VariantUtil.as_string(state.get("trump_card", ""), "")
	_rail.add_child(UI.chip(Loc.t("game.durak.trump", {"suit": _suit_symbol(trump)}), Palette.WARNING))
	_rail.add_child(UI.chip(Loc.t("game.durak.deck_count", {"count": VariantUtil.as_int(state.get("deck_count", 0), 0)}), Palette.ACCENT))
	_rail.add_child(UI.chip(Loc.t("game.durak.discard_count", {"count": VariantUtil.as_int(state.get("discard_count", 0), 0)}), Palette.TEXT_MUTED))


func _refresh_table(state: Dictionary) -> void:
	_clear(_table_row)
	var table: Array = VariantUtil.as_array(state.get("table", []))
	if table.is_empty():
		_table_row.add_child(_empty_label("game.durak.table_empty"))
		return
	for entry: Variant in table:
		var slot: Dictionary = entry
		var column := UI.column(4)
		column.add_child(_card_face(VariantUtil.as_string(slot.get("attack", ""), ""), false))
		var defense := VariantUtil.as_string(slot.get("defense", ""), "")
		if defense.is_empty():
			column.add_child(UI.label(Loc.t("game.durak.uncovered"), "Caption"))
		else:
			column.add_child(_card_face(defense, false))
		_table_row.add_child(column)


func _refresh_hand(state: Dictionary) -> void:
	_clear(_hand_row)
	var trump := VariantUtil.as_string(state.get("trump_suit", ""), "")
	var cards := _sorted_cards(_local_hand(), trump)
	if cards.is_empty():
		_hand_row.add_child(_empty_label("game.durak.hand_empty"))
		return
	for code: Variant in cards:
		var card := VariantUtil.as_string(code, "")
		var playable := _action_for_card(card) != {}
		var face := _card_face(card, playable)
		if playable:
			face.clicked.connect(_on_card_clicked)
		_hand_row.add_child(face)


func _refresh_players(state: Dictionary) -> void:
	_clear(_players_box)
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var out_list: Array = VariantUtil.as_array(state.get("out", []))
	var attacker := VariantUtil.as_int(state.get("attacker", -1), -1)
	var defender := VariantUtil.as_int(state.get("defender", -1), -1)
	for seat: int in range(engine.player_count()):
		var row := UI.flow(6, 6)
		var name_label := UI.label(engine.player_name(seat), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if seat == engine.decision_player() and not engine.finished:
			name_label.add_theme_color_override("font_color", Palette.POSITIVE)
		row.add_child(name_label)
		if seat == attacker:
			row.add_child(UI.chip(Loc.t("game.durak.role_attacker"), Palette.WARNING))
		if seat == defender:
			row.add_child(UI.chip(Loc.t("game.durak.role_defender"), Palette.INFO))
		if out_list.has(seat):
			row.add_child(UI.chip(Loc.t("game.durak.role_out"), Palette.TEXT_MUTED))
		if engine.finished and VariantUtil.as_int(counts[seat] if seat < counts.size() else 0, 0) > 0:
			row.add_child(UI.chip(Loc.t("game.durak.role_fool"), Palette.DANGER))
		var count := VariantUtil.as_int(counts[seat] if seat < counts.size() else 0, 0)
		row.add_child(UI.chip(Loc.tp("game.durak.cards", count), Palette.TEXT_MUTED))
		_players_box.add_child(row)


func _refresh_status(state: Dictionary) -> void:
	if engine.finished:
		_status.text = Loc.t("game.common.finished_status", {"winner": engine.winner_text()})
		return
	var lines := PackedStringArray()
	lines.append(Loc.t("game.durak.round_line", {"round": VariantUtil.as_int(state.get("round", 1), 1)}))
	if engine.phase() == "defense":
		lines.append(Loc.t("game.durak.status_defense", {
			"defender": engine.player_name(VariantUtil.as_int(state.get("defender", 0), 0)),
			"attacker": engine.player_name(VariantUtil.as_int(state.get("attacker", 0), 0)),
		}))
	else:
		lines.append(Loc.t("game.durak.status_attack", {
			"player": engine.player_name(engine.decision_player()),
		}))
	_status.text = "\n".join(lines)


# ------------------------------------------------------------------ helpers

func _on_card_clicked(card_id: String) -> void:
	var action := _action_for_card(card_id)
	if action.is_empty():
		return
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func _action_for_card(card_id: String) -> Dictionary:
	var pending: Array = []
	for entry: Variant in legal_actions():
		var action: Dictionary = entry
		var type := VariantUtil.as_string(action.get("type", ""), "")
		if (type == "attack" or type == "defend") and VariantUtil.as_string(action.get("card", ""), "") == card_id:
			pending.append(action)
	if pending.is_empty():
		return {}
	return pending[0]


func _local_hand() -> Array:
	# §6.3: the authorized private slice for the seat this device controls.
	return private_info().get("hand", [])


func _sorted_cards(cards: Array, trump: String) -> Array:
	var out: Array = cards.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var left := _value(VariantUtil.as_string(a, ""), trump)
		var right := _value(VariantUtil.as_string(b, ""), trump)
		if left == right:
			return VariantUtil.as_string(a, "") < VariantUtil.as_string(b, "")
		return left < right
	)
	return out


func _value(card: String, trump: String) -> int:
	var suit := card.substr(0, 1)
	var base := DurakEngine.rank_index(card)
	return base + (100 if suit == trump else 0)


func _card_face(code: String, playable: bool) -> CardFace:
	var suit := code.substr(0, 1)
	var rank := code.substr(1)
	var red := RED_SUITS.has(suit)
	var data := CardFace.data(
		code,
		rank,
		"",
		"",
		"",
		"",
		CARD_ACCENT_RED if red else CARD_ACCENT_DARK,
		_suit_symbol(code)
	)
	data["dimmed"] = not playable
	var face := CardFace.new()
	face.configure(data, CardFace.WIDTH_SMALL)
	return face


func _suit_symbol(card: String) -> String:
	return VariantUtil.as_string(SUIT_SYMBOLS.get(card.substr(0, 1), ""), "?")


## Reconstruct log lines from their localisation key so compact engine codes
## such as "10S" are rendered as real cards ("10♠") rather than raw data.
func log_text(entry: Dictionary) -> String:
	var text_key := VariantUtil.as_string(entry.get("text_key", ""), "")
	if text_key.is_empty():
		return VariantUtil.as_string(entry.get("text", ""), "")
	var args: Dictionary = VariantUtil.dict_copy(entry.get("args", {}))
	for field: String in ["card", "attack"]:
		if args.has(field):
			args[field] = _format_log_card(VariantUtil.as_string(args[field], ""))
	return Loc.t(text_key, args)


func _format_log_card(text: String) -> String:
	if text.length() < 2:
		return text
	var suit := text.substr(text.length() - 1, 1)
	if not SUIT_SYMBOLS.has(suit):
		return text
	return text.substr(0, text.length() - 1) + VariantUtil.as_string(SUIT_SYMBOLS[suit], "")


func _empty_label(key: String) -> Label:
	var label := UI.label(Loc.t(key), "Caption")
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
