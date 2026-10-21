extends GameView
## Star Realms table: trade row, player seats, the local hand and the pending
## optional effects.
##
## The view never mutates the engine. It renders `engine.public_state()`, reads the
## local hand from the engine (hotseat/solo) or from the session snapshot (online
## clients) and turns clicks into action keys submitted through the session, which
## is what makes hotseat, solo and host-validated online play share one board.
##
## Interaction model: click a card or a seat to select it, then press the action in
## the context row under the hand ("Play", "Buy", "Scrap", "Attack"). The only
## always-visible button the game screen adds on top is "End turn", because the
## engine marks that action as direct.

const CARD_WIDTH: int = 132

var _status: Label
var _seats_flow: HFlowContainer
var _row_flow: HFlowContainer
var _table_flow: HFlowContainer
var _hand_flow: HFlowContainer
var _context_row: HFlowContainer
var _fleet_heading: Label
var _hand_heading: Label
## Nothing selected / { "zone": hand|row|table|enemy_base|enemy, ... }.
var _selection: Dictionary = {}


func requires_handover() -> bool:
	return true


func build_board() -> void:
	_status = UI.label("", "Body")
	add_child(_status)

	add_child(UI.heading(Loc.t("game.star_realms.section_trade_row"), "Subtitle"))
	_row_flow = UI.flow(8, 8)
	add_child(_row_flow)

	# In-play cards are the fleet; the hand is a separate zone with its own
	# heading. At game start the fleet is empty, so its heading is hidden
	# instead of making the hand look like part of the fleet.
	_fleet_heading = UI.heading(Loc.t("game.star_realms.section_your_area"), "Subtitle")
	add_child(_fleet_heading)
	_table_flow = UI.flow(8, 8)
	add_child(_table_flow)

	_hand_heading = UI.heading(Loc.t("game.star_realms.section_hand"), "Subtitle")
	add_child(_hand_heading)
	_hand_flow = UI.flow(8, 8)
	add_child(_hand_flow)
	_context_row = UI.flow(8, 8)
	add_child(_context_row)

	add_child(UI.heading(Loc.t("game.star_realms.section_opponents"), "Subtitle"))
	_seats_flow = UI.flow(12, 12)
	add_child(_seats_flow)


func refresh_board() -> void:
	if engine == null:
		return
	for flow: HFlowContainer in [_seats_flow, _row_flow, _table_flow, _hand_flow, _context_row]:
		_clear(flow)
	_context_row.visible = false
	var state := engine.public_state()
	var seats: Array = state.get("seats", [])
	var me := acting_player()
	_status.text = _status_text(seats, me)
	_build_seats(seats, me)
	_build_row(state)
	_build_own_area(me)
	_build_context(me)


# ------------------------------------------------------------------ top status

func _status_text(seats: Array, me: int) -> String:
	var parts := PackedStringArray()
	if engine.finished:
		parts.append(Loc.t("game.common.finished_status", {"winner": engine.winner_text()}))
	elif is_my_turn():
		parts.append(Loc.t("game.star_realms.status_your_turn"))
	else:
		parts.append(Loc.t("game.star_realms.status_waiting", {
			"player": engine.player_name(engine.decision_player()),
		}))
	var seat := _seat_at(seats, me)
	if not seat.is_empty():
		parts.append(Loc.t("game.star_realms.status_pools", {
			"trade": int(seat.get("trade", 0)),
			"combat": int(seat.get("combat", 0)),
		}))
	parts.append(Loc.t("game.star_realms.status_counts", {
		"hand": int(seat.get("hand_count", 0)) if not seat.is_empty() else 0,
		"deck": int(seat.get("deck_count", 0)) if not seat.is_empty() else 0,
		"discard": int(seat.get("discard_count", 0)) if not seat.is_empty() else 0,
	}))
	return "   ·   ".join(parts)


func _seat_at(seats: Array, index: int) -> Dictionary:
	for seat: Variant in seats:
		if seat is Dictionary and int((seat as Dictionary).get("index", -1)) == index:
			return seat
	return {}


# -------------------------------------------------------------- opponent seats

func _build_seats(seats: Array, me: int) -> void:
	for seat: Variant in seats:
		if not (seat is Dictionary):
			continue
		var entry: Dictionary = seat
		var index := int(entry.get("index", -1))
		if index == me:
			continue
		_seats_flow.add_child(_seat_panel(entry))


func _seat_panel(seat: Dictionary) -> PanelContainer:
	var index := int(seat.get("index", -1))
	var box := UI.column(4)
	var title := UI.flow(6, 6)
	var name_label := UI.label(engine.player_name(index), "Body")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if index == engine.decision_player() and not engine.finished:
		name_label.add_theme_color_override("font_color", Palette.POSITIVE)
	title.add_child(name_label)
	title.add_child(UI.chip(Loc.t("game.star_realms.authority_short", {"n": int(seat.get("authority", 0))}), Palette.DANGER))
	title.add_child(UI.chip(Loc.t("game.star_realms.seat_counts", {
		"hand": int(seat.get("hand_count", 0)),
		"deck": int(seat.get("deck_count", 0)),
		"discard": int(seat.get("discard_count", 0)),
	}), Palette.TEXT_MUTED))
	box.add_child(title)

	if int(seat.get("authority", 0)) <= 0:
		box.add_child(UI.label(Loc.t("game.star_realms.seat_eliminated"), "Caption"))
		return UI.panel_with(box, "ElevatedPanel", 10)

	# Authority attack button (only offered while the engine lists the action).
	var attack := _find_action("attack_authority", {"player": index})
	if not attack.is_empty():
		box.add_child(UI.button(Loc.t("game.star_realms.attack_authority", {
			"n": engine.combat_of(engine.decision_player()),
		}), "DangerButton", func() -> void:
			_submit_action(attack)
		))

	var bases: Array = seat.get("bases", [])
	var table: Array = seat.get("in_play", [])
	for card: Variant in table:
		if card is Dictionary:
			box.add_child(_card(card, "enemy", {"player": index}))
	for base_index: int in range(bases.size()):
		if bases[base_index] is Dictionary:
			box.add_child(_card(bases[base_index], "enemy_base", {"player": index, "base": base_index}))
	var panel := UI.panel_with(box, "ElevatedPanel", 8)
	# Keep the seat summary on one line instead of wrapping the count chips into
	# a second row; it saves vertical space for the trade row and hand.
	panel.custom_minimum_size = Vector2(310, 0)
	return panel


# ------------------------------------------------------------------ trade row

func _build_row(state: Dictionary) -> void:
	var row: Array = state.get("trade_row", [])
	if row.is_empty():
		_row_flow.add_child(_empty_label("game.star_realms.row_empty"))
	for slot: int in range(row.size()):
		_row_flow.add_child(_card(row[slot], "row", {"slot": slot}))
	var explorer := _find_action("buy_explorer", {})
	if not explorer.is_empty():
		_row_flow.add_child(_explorer_button(explorer))
	if int(state.get("trade_deck_count", 0)) > 0:
		var deck_chip := UI.chip(Loc.t("game.star_realms.row_deck", {
			"n": int(state.get("trade_deck_count", 0)),
		}), Palette.TEXT_MUTED)
		# HFlowContainer stretches the cross axis; keep the deck marker at chip
		# height instead of inflating it to the card row height.
		deck_chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_row_flow.add_child(deck_chip)


func _explorer_button(action: Dictionary) -> Button:
	var label := "%s · %s" % [
		Loc.t("game.star_realms.explorer"),
		Loc.t("game.star_realms.cost_short", {"n": StarRealmsEngine.EXPLORER_COST}),
	]
	var button := UI.button(label, "Button", func() -> void:
		_submit_action(action)
	)
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return button


# ----------------------------------------------------------------- own table

func _build_own_area(me: int) -> void:
	var state := engine.public_state()
	var seat := _seat_at(state.get("seats", []), me)
	for card: Variant in seat.get("in_play", []):
		if card is Dictionary:
			_table_flow.add_child(_card(card, "table", {}))
	for base_index: int in range((seat.get("bases", []) as Array).size()):
		var bases: Array = seat.get("bases", [])
		if bases[base_index] is Dictionary:
			_table_flow.add_child(_card(bases[base_index], "table_base", {"base": base_index}))
	var has_fleet := _table_flow.get_child_count() > 0
	_table_flow.visible = has_fleet
	_fleet_heading.visible = has_fleet
	for card: Variant in _hand(me):
		if card is Dictionary:
			_hand_flow.add_child(_card(card, "hand", {}))
	_hand_heading.visible = not engine.finished


## The local hand through the authorized helper (§6.3): the engine in local
## modes, the session snapshot on online clients.
func _hand(me: int) -> Array:
	if me != acting_player():
		return []
	return private_info().get("hand", [])


# --------------------------------------------------------------------- cards

func _card(card: Dictionary, zone: String, extra: Dictionary) -> CardFace:
	var card_id := String(card.get("id", ""))
	var uid := str(card.get("uid", ""))
	var selected := _is_selected(zone, card, extra)
	var face := CardFace.new()
	face.configure(StarRealmsCards.face_data(card_id, uid, selected, false), CARD_WIDTH, true)
	face.clicked.connect(func(_card_key: String) -> void:
		_on_card_clicked(zone, card, extra)
	)
	return face


## A card is selected when its zone matches and its identity matches: the uid for
## hand/table cards, the slot for trade-row cards, the (player, base) pair for
## bases on the table.
func _is_selected(zone: String, card: Dictionary, extra: Dictionary) -> bool:
	if _selection.is_empty() or String(_selection.get("zone", "")) != zone:
		return false
	if extra.has("slot"):
		return int(_selection.get("slot", -1)) == int(extra["slot"])
	if extra.has("base"):
		return int(_selection.get("base", -1)) == int(extra["base"]) \
			and int(_selection.get("player", -1)) == int(extra.get("player", -1))
	return int(_selection.get("uid", -1)) == int(card.get("uid", -2))


func _on_card_clicked(zone: String, card: Dictionary, extra: Dictionary) -> void:
	var selection := {"zone": zone}
	for key: Variant in extra:
		selection[key] = extra[key]
	selection["uid"] = int(card.get("uid", -1))
	if _same_selection(selection):
		_selection = {}
	else:
		_selection = selection
	refresh_board()


func _same_selection(other: Dictionary) -> bool:
	if _selection.size() != other.size():
		return false
	for key: Variant in other:
		if _selection.get(key, null) != other[key]:
			return false
	return true


# ------------------------------------------------------------ context actions

func _build_context(_me: int) -> void:
	if not is_my_turn() or engine.finished:
		return
	var zone := String(_selection.get("zone", ""))
	_context_row.visible = true
	if zone.is_empty():
		_context_row.visible = false
		return
	var offered := 0
	match zone:
		"hand":
			var uid := int(_selection.get("uid", -1))
			var play := _find_action("play_card", {"card": uid})
			if not play.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_play"), "PrimaryButton", func() -> void:
					_submit_action(play)
				))
			var scrap := _find_action("scrap_hand", {"card": uid})
			if not scrap.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_scrap_hand"), "DangerButton", func() -> void:
					_submit_action(scrap)
				))
		"row":
			var slot := int(_selection.get("slot", -1))
			var buy := _find_action("buy", {"slot": slot})
			if not buy.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_buy"), "PositiveButton", func() -> void:
					_submit_action(buy)
				))
		"table", "table_base":
			var scrap_play := _find_action("scrap_play", {"card": int(_selection.get("uid", -1))})
			if not scrap_play.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_scrap"), "DangerButton", func() -> void:
					_submit_action(scrap_play)
				))
		"enemy_base":
			var attack_base := _find_action("attack_base", {
				"player": int(_selection.get("player", -1)),
				"base": int(_selection.get("base", -1)),
			})
			if not attack_base.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_attack_base"), "DangerButton", func() -> void:
					_submit_action(attack_base)
				))
		"enemy":
			var attack_authority := _find_action("attack_authority", {"player": int(_selection.get("player", -1))})
			if not attack_authority.is_empty():
				offered += 1
				_context_row.add_child(UI.button(Loc.t("game.star_realms.action_attack_authority"), "DangerButton", func() -> void:
					_submit_action(attack_authority)
				))
	if offered == 0:
		_context_row.add_child(_empty_label("game.star_realms.context_unavailable"))
	_context_row.add_child(UI.button(Loc.t("game.star_realms.action_clear"), "GhostButton", func() -> void:
		_selection = {}
		refresh_board()
	))


## First legal action of `action_type` whose parameters match; parameters the
## action does not carry are ignored (e.g. `enabled`).
func _find_action(action_type: String, params: Dictionary) -> Dictionary:
	for action: Variant in legal_actions():
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if String(entry.get("type", "")) != action_type:
			continue
		var matches := true
		for key: Variant in params:
			if int(entry.get(key, -1)) != int(params[key]):
				matches = false
				break
		if matches:
			return entry
	return {}


func _submit_action(action: Dictionary) -> void:
	_selection = {}
	submit(String(action.get("key", "")))


# ------------------------------------------------------------ action bar extras

## Pending optional effects are shown next to the action bar as a reminder of what
## the player still has to choose on the board.
func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if engine == null or engine.finished:
		return out
	var me := acting_player()
	var seat := _seat_at(engine.public_state().get("seats", []), me)
	for effect: Variant in seat.get("pending", []):
		if effect is Dictionary:
			var kind := String((effect as Dictionary).get("kind", ""))
			if kind.is_empty():
				continue
			out.append(UI.chip(Loc.t("game.star_realms.pending.%s" % kind), Palette.WARNING))
	return out


# --------------------------------------------------------------------- helpers


func _empty_label(key: String) -> Label:
	var label := UI.label(Loc.t(key), "Caption")
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
