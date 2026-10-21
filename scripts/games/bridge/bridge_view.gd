extends GameView
## Bridge table.
##
## Shows the auction, the current trick, the dummy hand once it is exposed and
## the acting player's own cards. Bidding buttons are built from the legal
## actions, so the view can never offer an illegal contract. The view only
## submits action keys; the engine owns every rule.

const SUIT_SYMBOLS: Dictionary = {"C": "♣", "D": "♦", "H": "♥", "S": "♠"}
const RED_SUITS: Array[String] = ["H", "D"]
const CARD_ACCENT_RED: Color = Color("e2574c")
const CARD_ACCENT_DARK: Color = Color("c9d4e6")

var _rail: HBoxContainer
var _auction_label: Label
var _auction_row: HFlowContainer
var _table_label: Label
var _table_row: HFlowContainer
var _dummy_label: Label
var _dummy_row: HFlowContainer
var _bid_panel: VBoxContainer
var _bid_grid: GridContainer
var _pass_row: HBoxContainer
var _hand_label: Label
var _hand_row: HFlowContainer
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
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(left)

	_rail = UI.hsep(8)
	left.add_child(UI.panel_with(_rail, "ElevatedPanel", 8))

	_auction_label = UI.label(Loc.t("game.bridge.auction_label"), "Subtitle")
	left.add_child(_auction_label)
	_auction_row = UI.flow(8, 8)
	left.add_child(_auction_row)

	_table_label = UI.label(Loc.t("game.bridge.trick_label"), "Subtitle")
	left.add_child(_table_label)
	_table_row = UI.flow(14, 14)
	left.add_child(_table_row)

	_dummy_label = UI.label(Loc.t("game.bridge.dummy_hand_label"), "Subtitle")
	left.add_child(_dummy_label)
	_dummy_row = UI.flow(8, 8)
	left.add_child(_dummy_row)

	_bid_panel = UI.column(8)
	_bid_grid = GridContainer.new()
	_bid_grid.columns = 5
	_bid_grid.add_theme_constant_override("h_separation", 6)
	_bid_grid.add_theme_constant_override("v_separation", 6)
	_bid_panel.add_child(_bid_grid)
	_pass_row = UI.hsep(8)
	_bid_panel.add_child(_pass_row)
	left.add_child(_bid_panel)

	left.add_child(UI.spacer(4, true))
	_hand_label = UI.label(Loc.t("game.bridge.hand_label"), "Subtitle")
	left.add_child(_hand_label)
	_hand_row = UI.flow(10, 10)
	left.add_child(_hand_row)

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(340, 0)
	layout.add_child(side)
	_status = UI.label("", "Body")
	side.add_child(_status)
	side.add_child(UI.divider())
	side.add_child(UI.label(Loc.t("game.bridge.players_label"), "Subtitle"))
	_players_box = UI.column(8)
	side.add_child(_players_box)
	side.add_child(UI.divider())
	_hint = UI.label(Loc.t("game.bridge.hint_auction"), "Caption")
	side.add_child(_hint)


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	_refresh_rail(state)
	_refresh_auction(state)
	_refresh_trick(state)
	_refresh_dummy(state)
	_refresh_bids(state)
	_refresh_hand(state)
	_refresh_players(state)
	_refresh_status(state)


func _refresh_rail(state: Dictionary) -> void:
	_clear(_rail)
	var phase := VariantUtil.as_string(state.get("phase_id", "auction"), "auction")
	_rail.add_child(UI.chip(_phase_label(phase), Palette.ACCENT))
	if phase == "auction":
		_rail.add_child(UI.chip(Loc.t("game.bridge.dealer_chip", {
			"player": engine.player_name(VariantUtil.as_int(state.get("dealer", 0), 0)),
		}), Palette.TEXT_MUTED))
	else:
		_rail.add_child(UI.chip(Loc.t("game.bridge.trick_no", {
			"count": VariantUtil.as_int(state.get("trick_no", 1), 1),
		}), Palette.INFO))
	var bid := VariantUtil.as_string(state.get("contract_bid", ""), "")
	if bid.is_empty():
		_rail.add_child(UI.chip(Loc.t("game.bridge.contract_none"), Palette.TEXT_MUTED))
	else:
		_rail.add_child(UI.chip(Loc.t("game.bridge.contract_chip", {"bid": _pretty_bid_text(bid)}), Palette.WARNING))


func _refresh_auction(state: Dictionary) -> void:
	_clear(_auction_row)
	var entries: Array = VariantUtil.as_array(state.get("auction", []))
	if entries.is_empty():
		_auction_row.add_child(_empty_label(Loc.t("game.bridge.auction_empty")))
		return
	for entry: Variant in entries:
		var slot: Dictionary = entry
		var player := VariantUtil.as_int(slot.get("player", 0), 0)
		var text := engine.player_name(player) + ": " + _auction_text(slot)
		_auction_row.add_child(UI.chip(text, Palette.TEXT_MUTED))


func _refresh_trick(state: Dictionary) -> void:
	_clear(_table_row)
	var trick: Array = VariantUtil.as_array(state.get("trick", []))
	if trick.is_empty():
		_table_row.add_child(_empty_label(Loc.t("game.bridge.trick_empty")))
		return
	for entry: Variant in trick:
		var slot: Dictionary = entry
		var column := UI.column(4)
		column.add_child(UI.label(engine.player_name(VariantUtil.as_int(slot.get("player", 0), 0)), "Caption"))
		column.add_child(_card_face(VariantUtil.as_string(slot.get("card", ""), ""), false))
		_table_row.add_child(column)


func _refresh_dummy(state: Dictionary) -> void:
	_clear(_dummy_row)
	var revealed := bool(state.get("dummy_revealed", false))
	_dummy_label.visible = revealed
	_dummy_row.visible = revealed
	if not revealed:
		return
	var cards: Array = VariantUtil.as_array(state.get("dummy_hand", []))
	if cards.is_empty():
		_dummy_row.add_child(_empty_label(Loc.t("game.bridge.hand_empty")))
		return
	for card: Variant in cards:
		var code := VariantUtil.as_string(card, "")
		var action := _action_for_card(code)
		var face := _card_face(code, not action.is_empty())
		if not action.is_empty():
			face.clicked.connect(_on_card_clicked)
		_dummy_row.add_child(face)


func _refresh_bids(state: Dictionary) -> void:
	_clear(_bid_grid)
	_clear(_pass_row)
	var auction_phase := VariantUtil.as_string(state.get("phase_id", ""), "") == "auction"
	_bid_panel.visible = auction_phase and not engine.finished
	if not _bid_panel.visible:
		return
	var bids: Array[Dictionary] = []
	var passes: Array[Dictionary] = []
	for action: Variant in legal_actions():
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if VariantUtil.as_string(entry.get("type", ""), "") == "bid":
			bids.append(entry)
		elif VariantUtil.as_string(entry.get("type", ""), "") == "pass":
			passes.append(entry)
	for action: Dictionary in bids:
		var button := UI.button(_pretty_bid(VariantUtil.as_int(action.get("level", 1), 1), VariantUtil.as_string(action.get("strain", ""), "C")), "Button", func() -> void:
			submit(VariantUtil.as_string(action.get("key", ""), ""))
		)
		button.custom_minimum_size = Vector2(58, 32)
		_bid_grid.add_child(button)
	for action: Dictionary in passes:
		var pass_button := UI.button(Loc.t("game.bridge.action.pass"), "Button", func() -> void:
			submit(VariantUtil.as_string(action.get("key", ""), ""))
		)
		_pass_row.add_child(pass_button)


func _refresh_hand(state: Dictionary) -> void:
	_clear(_hand_row)
	var cards := _local_cards()
	if cards.is_empty():
		_hand_row.add_child(_empty_label(Loc.t("game.bridge.hand_empty")))
		return
	for card: Variant in cards:
		var code := VariantUtil.as_string(card, "")
		var action := _action_for_card(code)
		var face := _card_face(code, not action.is_empty())
		if not action.is_empty():
			face.clicked.connect(_on_card_clicked)
		_hand_row.add_child(face)


func _refresh_players(state: Dictionary) -> void:
	_clear(_players_box)
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var declarer := VariantUtil.as_int(state.get("declarer", -1), -1)
	var dummy := VariantUtil.as_int(state.get("dummy", -1), -1)
	var leader := VariantUtil.as_int(state.get("leader", -1), -1)
	var tricks_ns := VariantUtil.as_int(state.get("tricks_ns", 0), 0)
	var tricks_ew := VariantUtil.as_int(state.get("tricks_ew", 0), 0)
	for seat: int in range(engine.player_count()):
		# A flow lets the name and chips wrap as whole units. The old HBox
		# squeezed the auto-wrapped name down to a one-character-wide column.
		var row := UI.flow(6, 6)
		var name_label := UI.label(engine.player_name(seat), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if seat == engine.decision_player() and not engine.finished:
			name_label.add_theme_color_override("font_color", Palette.POSITIVE)
		row.add_child(name_label)
		if seat == declarer:
			row.add_child(UI.chip(Loc.t("game.bridge.role_declarer"), Palette.POSITIVE))
		if seat == dummy:
			row.add_child(UI.chip(Loc.t("game.bridge.role_dummy"), Palette.INFO))
		if seat == leader and not engine.finished and VariantUtil.as_string(state.get("phase_id", ""), "") == "play":
			row.add_child(UI.chip(Loc.t("game.bridge.role_leader"), Palette.WARNING))
		var side_chip := UI.chip(Loc.t("game.bridge.side_ns") if seat % 2 == 0 else Loc.t("game.bridge.side_ew"), Palette.TEXT_MUTED)
		row.add_child(side_chip)
		if engine.finished:
			row.add_child(UI.chip(Loc.t("game.bridge.chip_score", {"score": _score_for(seat)}), Palette.ACCENT))
		else:
			var count := VariantUtil.as_int(counts[seat] if seat < counts.size() else 0, 0)
			row.add_child(UI.chip(Loc.tp("game.bridge.cards", count), Palette.TEXT_MUTED))
		if seat % 2 == 0:
			row.add_child(UI.chip(Loc.t("game.bridge.chip_tricks", {"count": tricks_ns}), Palette.INFO))
		else:
			row.add_child(UI.chip(Loc.t("game.bridge.chip_tricks", {"count": tricks_ew}), Palette.INFO))
		_players_box.add_child(row)


func _refresh_status(state: Dictionary) -> void:
	if engine.finished:
		_status.text = "%s\n%s" % [
			Loc.t("game.common.finished_status", {"winner": engine.winner_text()}),
			engine.scores_text(),
		]
		return
	var phase := VariantUtil.as_string(state.get("phase_id", "auction"), "auction")
	if phase == "auction":
		_hint.text = Loc.t("game.bridge.hint_auction")
		_status.text = Loc.t("game.bridge.status_auction", {
			"player": engine.player_name(engine.decision_player()),
		})
		return
	var turn_seat := VariantUtil.as_int(state.get("turn_seat", 0), 0)
	var dummy := VariantUtil.as_int(state.get("dummy", -1), -1)
	if turn_seat == dummy:
		_hint.text = Loc.t("game.bridge.hint_dummy")
		_status.text = Loc.t("game.bridge.status_dummy", {
			"player": engine.player_name(engine.decision_player()),
			"dummy": engine.player_name(dummy),
		})
		return
	_hint.text = Loc.t("game.bridge.hint_play")
	var trick: Array = VariantUtil.as_array(state.get("trick", []))
	if trick.is_empty():
		_status.text = Loc.t("game.bridge.status_lead", {
			"player": engine.player_name(engine.decision_player()),
		})
	else:
		_status.text = Loc.t("game.bridge.status_follow", {
			"player": engine.player_name(engine.decision_player()),
			"leader": engine.player_name(VariantUtil.as_int(state.get("leader", 0), 0)),
		})


# ------------------------------------------------------------------ helpers

func _empty_label(text: String) -> Label:
	var node := UI.label(text, "Caption")
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	return node


func _phase_label(phase: String) -> String:
	match phase:
		"auction":
			return Loc.t("game.bridge.phase.auction")
		"play":
			return Loc.t("game.bridge.phase.play")
		_:
			return Loc.t("game.bridge.phase.finished")


func _on_card_clicked(card_id: String) -> void:
	var action := _action_for_card(card_id)
	if action.is_empty():
		return
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func _action_for_card(card_id: String) -> Dictionary:
	for entry: Variant in legal_actions():
		var action: Dictionary = entry
		if VariantUtil.as_string(action.get("type", ""), "") == "play" and VariantUtil.as_string(action.get("card", ""), "") == card_id:
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
	return (engine as BridgeEngine).sorted_hand(actor)


func _score_for(seat: int) -> int:
	for entry: Variant in engine.result.get("scores", []):
		if entry is Dictionary and VariantUtil.as_int(VariantUtil.as_dict(entry).get("player", -1), -1) == seat:
			return VariantUtil.as_int(VariantUtil.as_dict(entry).get("score", 0), 0)
	return 0


func _auction_text(entry: Dictionary) -> String:
	if VariantUtil.as_string(entry.get("type", ""), "") == "pass":
		return Loc.t("game.bridge.action.pass")
	return _pretty_bid(VariantUtil.as_int(entry.get("level", 0), 0), VariantUtil.as_string(entry.get("strain", ""), ""))


func _pretty_bid(level: int, strain: String) -> String:
	if strain == "NT":
		return "%dNT" % level
	return "%d%s" % [level, VariantUtil.as_string(SUIT_SYMBOLS.get(strain, strain), strain)]


## Converts an engine bid such as "3NT" or "2H" into "3NT"/"2♥".
func _pretty_bid_text(bid: String) -> String:
	if bid.is_empty():
		return ""
	if bid.ends_with("NT"):
		return bid
	var strain := bid.substr(bid.length() - 1)
	return bid.substr(0, bid.length() - 1) + VariantUtil.as_string(SUIT_SYMBOLS.get(strain, strain), strain)


func _card_face(code: String, playable: bool) -> CardFace:
	var suit := code.substr(0, 1)
	var rank := code.substr(1)
	var red := RED_SUITS.has(suit)
	var accent := CARD_ACCENT_RED if red else CARD_ACCENT_DARK
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
	face.configure(data, CardFace.WIDTH_SMALL)
	return face


func _suit_symbol(card: String) -> String:
	return VariantUtil.as_string(SUIT_SYMBOLS.get(card.substr(0, 1), ""), "?")


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
