extends GameView
## DANY table: the wandering hand binder, the claim banner and the inspect
## buttons.
##
## Everything is rebuilt from `engine.public_state()` plus the authorized
## private slice ([method GameView.private_info]); the view never mutates the
## engine. Hands are hidden, so hotseat play uses the handover gate
## ([method requires_handover] is true) and only the seat on the spot ever sees
## its own cards.

const SUIT_COLORS: Dictionary = {
	"ember": Color("c0392b"),
	"tide": Color("2f6fbf"),
	"grove": Color("3d8b5f"),
	"dusk": Color("6d5bd0"),
	"frost": Color("4aa3b8"),
}

var _status: Label
var _seats: VBoxContainer
var _table: VBoxContainer
var _log_box: VBoxContainer
var _controls: VBoxContainer
var _hand_box: HFlowContainer
var _hand_title: Label
var _claim_value: int = -1


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
	_status = UI.label("", "Body")
	left.add_child(_status)
	var seats_panel := UI.panel("CardPanel")
	left.add_child(seats_panel)
	_seats = UI.column(6)
	seats_panel.add_child(UI.margin_container(_seats, 12))
	left.add_child(UI.separator_label(Loc.t("game.dany.table_title")))
	_table = UI.column(6)
	left.add_child(_table)
	left.add_child(UI.separator_label(Loc.t("game.dany.history_title")))
	_log_box = UI.column(4)
	left.add_child(UI.scroll(_log_box, false))

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(360, 0)
	layout.add_child(side)
	var controls_panel := UI.panel("CardPanel")
	side.add_child(controls_panel)
	_controls = UI.column(8)
	controls_panel.add_child(UI.margin_container(_controls, 12))
	var hand_panel := UI.panel("CardPanel")
	side.add_child(hand_panel)
	var hand_column := UI.column(8)
	hand_panel.add_child(UI.margin_container(hand_column, 12))
	_hand_title = UI.heading(Loc.t("game.dany.hand_title"), "Subtitle")
	hand_column.add_child(_hand_title)
	_hand_box = UI.flow(8, 8)
	hand_column.add_child(_hand_box)


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var player := acting_player()
	var private := private_info()
	var phase := VariantUtil.as_string(state.get("phase", "select"), "select")
	_status.text = _status_text(state, player, phase)
	_refresh_seats(state, player)
	_refresh_table(state)
	_refresh_log()
	_refresh_controls(state, private, player, phase)
	_refresh_hand(state, private)


# -------------------------------------------------------------------- seats

func _refresh_seats(state: Dictionary, player: int) -> void:
	_clear(_seats)
	var counts: Array = state.get("hand_counts", [])
	var reputations: Array = state.get("reputations", [])
	var insights: Array = state.get("insights", [])
	var eliminated: Array = state.get("eliminated", [])
	var actor := engine.decision_player()
	for seat: int in range(engine.player_count()):
		var row := UI.row(8)
		var title := UI.label(engine.player_name(seat), "Small")
		title.custom_minimum_size = Vector2(90, 0)
		row.add_child(title)
		if seat == player:
			row.add_child(UI.chip(Loc.t("game.dany.you"), Palette.ACCENT))
		var is_out := seat < eliminated.size() and bool(eliminated[seat])
		if is_out:
			row.add_child(UI.chip(Loc.t("game.dany.out"), Palette.DANGER))
		else:
			if seat == actor and not engine.finished:
				row.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
			row.add_child(UI.chip(Loc.t("game.dany.chip_insight", {"value": int(insights[seat])}), Palette.INFO))
			row.add_child(UI.chip(Loc.t("game.dany.chip_reputation", {"value": int(reputations[seat])}), Palette.WARNING))
			row.add_child(UI.chip(Loc.t("game.dany.chip_cards", {"count": int(counts[seat])}), Palette.TEXT_MUTED))
		_seats.add_child(row)


# -------------------------------------------------------------------- table

func _refresh_table(state: Dictionary) -> void:
	_clear(_table)
	var phase := VariantUtil.as_string(state.get("phase", "select"), "select")
	_table.add_child(UI.label(Loc.t("game.dany.oracle_line", {
		"oracle": VariantUtil.as_int(state.get("oracle", 1), 1),
		"round": VariantUtil.as_int(state.get("round", 1), 1),
	}), "Caption"))
	if engine.finished:
		for entry: Variant in engine.result.get("scores", []):
			var record: Dictionary = entry
			_table.add_child(UI.label(Loc.t("game.dany.score_line", {
				"player": VariantUtil.as_string(record.get("name", ""), "?"),
				"insight": VariantUtil.as_int(record.get("insight", 0), 0),
				"reputation": VariantUtil.as_int(record.get("reputation", 0), 0),
			}), "Small"))
		return
	if phase == "inspect":
		var slots: Array = VariantUtil.as_array(state.get("pending_slots", []))
		_table.add_child(UI.label(Loc.t("game.dany.claim_banner", {
			"player": engine.player_name(VariantUtil.as_int(state.get("turn_pos", -1), -1)),
			"value": VariantUtil.as_int(state.get("claimed_value", 0), 0),
			"cards": slots.size(),
		}), "Body"))


# --------------------------------------------------------------------- log

func _refresh_log() -> void:
	_clear(_log_box)
	for entry: Dictionary in engine.recent_log(6):
		_log_box.add_child(UI.label(VariantUtil.as_string(entry.get("text", ""), ""), "Caption"))


# ---------------------------------------------------------------- controls

func _refresh_controls(state: Dictionary, private: Dictionary, player: int, phase: String) -> void:
	_clear(_controls)
	if engine.finished:
		_controls.add_child(UI.label(Loc.t("game.dany.finished", {"winner": engine.winner_text()}), "Body"))
		return
	if phase == "inspect":
		_controls.add_child(UI.section_header(Loc.t("game.dany.inspect_prompt")))
		for action: Dictionary in legal_actions():
			var action_type := VariantUtil.as_string(action.get("type", ""), "")
			var inspect_key := VariantUtil.as_string(action.get("key", ""), "")
			if action_type == "inspect":
				_controls.add_child(UI.button(Loc.t("game.dany.inspect_button"), "DangerButton", func() -> void:
					submit(inspect_key)
				))
			elif action_type == "pass":
				_controls.add_child(UI.button(Loc.t("game.dany.hold_button"), "Button", func() -> void:
					submit(inspect_key)
				))
		return
	var hand: Array = VariantUtil.as_array(private.get("hand", []))
	if hand.is_empty():
		_controls.add_child(UI.section_header(Loc.t("game.dany.fold_prompt")))
		for action: Dictionary in legal_actions():
			if VariantUtil.as_string(action.get("type", ""), "") == "pass":
				var fold_key := VariantUtil.as_string(action.get("key", ""), "")
				_controls.add_child(UI.button(Loc.t("game.dany.fold_button"), "Button", func() -> void:
					submit(fold_key)
				))
		return
	var pending: Array = VariantUtil.as_array(state.get("pending_slots", []))
	_controls.add_child(UI.section_header(Loc.t("game.dany.claim_prompt"), Loc.t("game.dany.claim_hint")))
	_controls.add_child(UI.label(Loc.t("game.dany.laid_line", {"count": pending.size()}), "Caption"))
	var claims := _claim_keys()
	if claims.is_empty():
		_controls.add_child(UI.label(Loc.t("game.dany.select_first"), "Small"))
		return
	if not claims.has(_claim_value):
		var values: Array = claims.keys()
		values.sort()
		_claim_value = int(values[0])
	_controls.add_child(UI.dropdown(_claim_entries(claims), str(_claim_value), func(value: String) -> void:
		_claim_value = int(value)
		refresh_board()
	))
	_controls.add_child(UI.button(Loc.t("game.dany.claim_button", {"value": _claim_value}), "PrimaryButton", func() -> void:
		submit(VariantUtil.as_string(claims.get(_claim_value, ""), ""))
	))


## Maps hand slot -> the toggle action key, and claim value -> the claim key.
func _select_keys() -> Dictionary:
	var out: Dictionary = {}
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "select":
			out[VariantUtil.as_int(action.get("slot", -1), -1)] = VariantUtil.as_string(action.get("key", ""), "")
	return out


func _claim_keys() -> Dictionary:
	var out: Dictionary = {}
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "claim":
			out[VariantUtil.as_int(action.get("value", -1), -1)] = VariantUtil.as_string(action.get("key", ""), "")
	return out


func _claim_entries(claims: Dictionary) -> Array:
	var out: Array = []
	var values: Array = claims.keys()
	values.sort()
	for value: Variant in values:
		out.append({"label": str(int(value)), "value": str(int(value))})
	return out


# --------------------------------------------------------------------- hand

func _refresh_hand(state: Dictionary, private: Dictionary) -> void:
	_clear(_hand_box)
	if engine.finished:
		_hand_title.visible = false
		return
	_hand_title.visible = true
	if VariantUtil.as_string(state.get("phase", "select"), "select") != "select":
		return
	var hand: Array = VariantUtil.as_array(private.get("hand", []))
	var pending: Array = VariantUtil.as_array(state.get("pending_slots", []))
	var keys := _select_keys()
	for slot: int in range(hand.size()):
		var card: Dictionary = hand[slot]
		var key := VariantUtil.as_string(keys.get(slot, ""), "")
		if key.is_empty():
			continue
		_hand_box.add_child(_card_face(card, pending.has(slot), key))


func _card_face(card: Dictionary, selected: bool, key: String) -> CardFace:
	var face := CardFace.new()
	var suit := VariantUtil.as_string(card.get("suit", ""), "")
	face.configure({
		"id": VariantUtil.as_string(card.get("id", ""), ""),
		"title": str(VariantUtil.as_int(card.get("value", 0), 0)),
		"subtitle": Loc.t("game.dany.suit.%s" % suit),
		"accent": SUIT_COLORS.get(suit, Palette.ACCENT),
		"selected": selected,
	}, CardFace.WIDTH_SMALL)
	face.clicked.connect(func(_card_id: String) -> void:
		submit(key)
	)
	return face


# ------------------------------------------------------------------- status

func _status_text(state: Dictionary, player: int, phase: String) -> String:
	if engine.finished:
		return Loc.t("game.dany.finished", {"winner": engine.winner_text()})
	if phase == "inspect":
		return Loc.t("game.dany.status_inspect", {
			"player": engine.player_name(VariantUtil.as_int(state.get("turn_pos", -1), -1)),
			"value": VariantUtil.as_int(state.get("claimed_value", 0), 0),
			"cards": VariantUtil.as_array(state.get("pending_slots", [])).size(),
			"responder": engine.player_name(engine.decision_player()),
		})
	return Loc.t("game.dany.status_select", {
		"player": engine.player_name(engine.decision_player()),
		"oracle": VariantUtil.as_int(state.get("oracle", 1), 1),
		"round": VariantUtil.as_int(state.get("round", 1), 1),
	})


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
