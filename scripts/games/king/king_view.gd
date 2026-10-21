extends GameView
## King table.
##
## Renders the current trick, the local hand and the public penalty counters,
## and turns a card click into the matching legal action key (a pass pick or a
## trick play). It never mutates the engine: everything reaches the engine
## through [method GameView.submit].

const SUIT_SYMBOLS: Dictionary = {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const RED_SUITS: Array[String] = ["H", "D"]
const CARD_ACCENT_RED: Color = Color("e2574c")
const CARD_ACCENT_DARK: Color = Color("c9d4e6")
const DANGER_ACCENT: Color = Color("e0a33c")
## Trick and pick cards are narrower so up to six fit on one row. The hand is
## a horizontal strip, so it can keep the readable small size.
const TABLE_CARD_WIDTH: int = 76

var _rail: HBoxContainer
var _table_label: Label
var _table_row: HFlowContainer
var _picks_label: Label
var _picks_row: HFlowContainer
var _hand_label: Label
var _hand_row: HBoxContainer
var _hand_scroll: ScrollContainer
var _status: Label
var _players_box: VBoxContainer
var _hint: Label


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
	_table_label = UI.label(Loc.t("game.king.table_label"), "Subtitle")
	left.add_child(_table_label)
	_table_row = UI.flow(14, 14)
	left.add_child(_table_row)
	_picks_label = UI.label(Loc.t("game.king.picks_label"), "Subtitle")
	left.add_child(_picks_label)
	_picks_row = UI.flow(10, 10)
	left.add_child(_picks_row)
	left.add_child(UI.spacer(4, true))
	_hand_label = UI.label(Loc.t("game.king.hand_label"), "Subtitle")
	left.add_child(_hand_label)
	_hand_row = UI.hsep(10)
	_hand_scroll = UI.scroll(_hand_row, true)
	_hand_scroll.custom_minimum_size = Vector2(0, int(float(CardFace.WIDTH_SMALL) * CardFace.RATIO) + 18)
	_hand_scroll.size_flags_vertical = Control.SIZE_SHRINK_END
	left.add_child(_hand_scroll)

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(340, 0)
	layout.add_child(side)
	_status = UI.label("", "Body")
	side.add_child(_status)
	side.add_child(UI.divider())
	side.add_child(UI.label(Loc.t("game.king.players_label"), "Subtitle"))
	_players_box = UI.column(8)
	var players_scroll := UI.scroll(_players_box, false)
	side.add_child(players_scroll)
	side.add_child(UI.divider())
	_hint = UI.label(Loc.t("game.king.hint"), "Caption")
	side.add_child(_hint)


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	_refresh_rail(state)
	_refresh_trick(state)
	_refresh_picks(state)
	_refresh_hand(state)
	_refresh_players(state)
	_refresh_status(state)


func _refresh_rail(state: Dictionary) -> void:
	_clear(_rail)
	_rail.add_child(UI.chip(Loc.t("game.king.trick_no", {"count": VariantUtil.as_int(state.get("trick_no", 1), 1)}), Palette.ACCENT))
	_rail.add_child(UI.chip(Loc.t("game.king.aside_count", {"count": VariantUtil.as_int(state.get("set_aside_count", 0), 0)}), Palette.TEXT_MUTED))
	var hearts := 0
	for count: Variant in VariantUtil.as_array(state.get("hearts_taken", [])):
		hearts += VariantUtil.as_int(count, 0)
	_rail.add_child(UI.chip(Loc.t("game.king.hearts_seen", {"count": hearts}), Palette.DANGER))


func _refresh_trick(state: Dictionary) -> void:
	_clear(_table_row)
	var trick: Array = VariantUtil.as_array(state.get("trick", []))
	if trick.is_empty():
		_table_row.add_child(_empty_label("game.king.table_empty"))
		return
	for entry: Variant in trick:
		var slot: Dictionary = entry
		var column := UI.column(4)
		var name_label := UI.label(engine.player_name(VariantUtil.as_int(slot.get("player", 0), 0)), "Caption")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		column.add_child(name_label)
		column.add_child(_card_face(VariantUtil.as_string(slot.get("card", ""), ""), false, TABLE_CARD_WIDTH))
		_table_row.add_child(column)


func _refresh_picks(state: Dictionary) -> void:
	var passing := VariantUtil.as_string(state.get("phase_id", ""), "") == "passing"
	_picks_label.visible = passing
	_picks_row.visible = passing
	_clear(_picks_row)
	if not passing:
		return
	var picks := _local_picks()
	if picks.is_empty():
		_picks_row.add_child(_empty_label("game.king.picks_none"))
		return
	for card: Variant in picks:
		_picks_row.add_child(_card_face(VariantUtil.as_string(card, ""), false, TABLE_CARD_WIDTH))


func _refresh_hand(state: Dictionary) -> void:
	var offset := _hand_scroll.scroll_horizontal if _hand_scroll != null else 0
	_clear(_hand_row)
	var cards := _local_cards()
	if cards.is_empty():
		_hand_row.add_child(_empty_label("game.king.hand_empty"))
		return
	for card: Variant in cards:
		var code := VariantUtil.as_string(card, "")
		var playable := _action_for_card(code) != {}
		var face := _card_face(code, playable)
		if playable:
			face.clicked.connect(_on_card_clicked)
		_hand_row.add_child(face)
	if _hand_scroll != null:
		_hand_scroll.set_deferred("scroll_horizontal", offset)


func _refresh_players(state: Dictionary) -> void:
	_clear(_players_box)
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var picks: Array = VariantUtil.as_array(state.get("picks_count", []))
	var hearts: Array = VariantUtil.as_array(state.get("hearts_taken", []))
	var queens: Array = VariantUtil.as_array(state.get("queens_taken", []))
	var kings: Array = VariantUtil.as_array(state.get("kings_taken", []))
	var leader := VariantUtil.as_int(state.get("leader", -1), -1)
	var passing := VariantUtil.as_string(state.get("phase_id", ""), "") == "passing"
	for seat: int in range(engine.player_count()):
		var row := UI.flow(6, 6)
		var name_label := UI.label(engine.player_name(seat), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if seat == engine.decision_player() and not engine.finished:
			name_label.add_theme_color_override("font_color", Palette.POSITIVE)
		row.add_child(name_label)
		if seat == leader and not passing:
			row.add_child(UI.chip(Loc.t("game.king.role_leader"), Palette.WARNING))
		if passing and seat < picks.size():
			row.add_child(UI.chip(Loc.t("game.king.picks_progress", {
				"picked": VariantUtil.as_int(picks[seat], 0),
				"total": KingEngine.PASS_COUNT,
			}), Palette.INFO))
		if seat < hearts.size() and VariantUtil.as_int(hearts[seat], 0) > 0:
			row.add_child(UI.chip(Loc.t("game.king.chip_hearts", {"count": VariantUtil.as_int(hearts[seat], 0)}), Palette.DANGER))
		if seat < queens.size() and VariantUtil.as_int(queens[seat], 0) > 0:
			row.add_child(UI.chip(Loc.t("game.king.chip_queen", {"count": VariantUtil.as_int(queens[seat], 0)}), Palette.DANGER))
		if seat < kings.size() and VariantUtil.as_int(kings[seat], 0) > 0:
			row.add_child(UI.chip(Loc.t("game.king.chip_king", {"count": VariantUtil.as_int(kings[seat], 0)}), Palette.POSITIVE))
		if engine.finished:
			row.add_child(UI.chip(Loc.t("game.king.chip_score", {"score": engine.score_for(seat)}), Palette.ACCENT))
		else:
			var count := VariantUtil.as_int(counts[seat] if seat < counts.size() else 0, 0)
			row.add_child(UI.chip(Loc.tp("game.king.cards", count), Palette.TEXT_MUTED))
		_players_box.add_child(row)


func _refresh_status(state: Dictionary) -> void:
	if engine.finished:
		_status.text = "%s\n%s" % [
			Loc.t("game.common.finished_status", {"winner": engine.winner_text()}),
			engine.scores_text(),
		]
		return
	if VariantUtil.as_string(state.get("phase_id", ""), "") == "passing":
		var picked := 0
		for count: Variant in VariantUtil.as_array(state.get("picks_count", [])):
			picked += VariantUtil.as_int(count, 0)
		var total := engine.player_count() * KingEngine.PASS_COUNT
		_hint.text = Loc.t("game.king.hint_passing")
		_status.text = Loc.t("game.king.status_passing", {
			"player": engine.player_name(engine.decision_player()),
			"picked": picked,
			"total": total,
		})
		return
	_hint.text = Loc.t("game.king.hint")
	var led: String = (engine as KingEngine).led_suit()
	if led.is_empty():
		_status.text = Loc.t("game.king.status_lead", {"player": engine.player_name(engine.decision_player())})
	else:
		_status.text = Loc.t("game.king.status_follow", {
			"player": engine.player_name(engine.decision_player()),
			"leader": engine.player_name(VariantUtil.as_int(state.get("leader", 0), 0)),
		})


# ------------------------------------------------------------------ helpers

func _on_card_clicked(card_id: String) -> void:
	var action := _action_for_card(card_id)
	if action.is_empty():
		return
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func _action_for_card(card_id: String) -> Dictionary:
	for entry: Variant in legal_actions():
		var action: Dictionary = entry
		var type := VariantUtil.as_string(action.get("type", ""), "")
		if (type == "pick" or type == "play") and VariantUtil.as_string(action.get("card", ""), "") == card_id:
			return action
	return {}


func _local_cards() -> Array[String]:
	var actor := acting_player()
	if engine == null or actor < 0 or actor >= engine.player_count():
		return []
	if session != null and session.is_online() and not session.last_private.is_empty():
		var online: Array[String] = []
		for card: Variant in VariantUtil.as_array(session.last_private.get("hand", [])):
			online.append(VariantUtil.as_string(card, ""))
		return online
	return (engine as KingEngine).sorted_hand(actor)


func _local_picks() -> Array:
	# §6.3: the authorized private slice for the seat this device controls.
	return private_info().get("picks", [])


func _card_face(code: String, playable: bool, width: int = CardFace.WIDTH_SMALL) -> CardFace:
	var suit := code.substr(0, 1)
	var rank := code.substr(1)
	var red := RED_SUITS.has(suit)
	var accent := CARD_ACCENT_RED if red else CARD_ACCENT_DARK
	if code == KingEngine.HEART_QUEEN or code == KingEngine.HEART_KING:
		accent = DANGER_ACCENT
	var data := CardFace.data(
		code,
		rank,
		"",
		"",
		"",
		"",
		accent,
		_suit_symbol(code)
	)
	data["dimmed"] = not playable
	var face := CardFace.new()
	face.configure(data, width)
	return face


func _suit_symbol(card: String) -> String:
	return VariantUtil.as_string(SUIT_SYMBOLS.get(card.substr(0, 1), ""), "?")


## An empty-state caption must keep its natural width. Wrapped labels have a
## one-pixel minimum width inside a flow container and grow into tall vertical
## columns, which used to push the whole hand off screen.
func _empty_label(key: String) -> Label:
	var label := UI.label(Loc.t(key), "Caption")
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
