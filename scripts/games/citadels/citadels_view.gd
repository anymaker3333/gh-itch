extends GameView
## Citadels table: the character draft, the acting turn, the local hand and every
## player's city.
##
## The view renders [method GameEngine.public_state] plus the acting player's
## private state and turns clicks into action keys through [method submit]; it
## never mutates the engine, which keeps hotseat, solo and online play identical.

## District colours (game data, not theme colours: they match the card colours
## used by the physical game).
const COLOUR_TINT: Dictionary = {
	"noble": Color("#e3b23c"),
	"religious": Color("#5ac8fa"),
	"trade": Color("#39d98a"),
	"military": Color("#ff5f6d"),
	"unique": Color("#a98bff"),
}
const ROLE_GLYPHS: Dictionary = {
	"assassin": "🗡", "thief": "🖐", "magician": "✦", "king": "♛",
	"bishop": "✝", "merchant": "💰", "architect": "📐", "warlord": "⚔",
}

var _status: Label
var _picked_title: Label
var _picked_flow: HFlowContainer
var _pool_title: Label
var _pool_flow: HFlowContainer
var _hand_title: Label
var _hand_flow: HFlowContainer
var _choice_flow: HFlowContainer
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
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	_status = UI.label("", "Body")
	left.add_child(_status)
	_picked_title = UI.label("", "Subtitle")
	_picked_title.visible = false
	left.add_child(_picked_title)
	_picked_flow = UI.flow(8, 8)
	left.add_child(_picked_flow)
	_pool_title = UI.label("", "Subtitle")
	left.add_child(_pool_title)
	_pool_flow = UI.flow(10, 10)
	left.add_child(_pool_flow)
	_hand_title = UI.label("", "Subtitle")
	left.add_child(_hand_title)
	_hand_flow = UI.flow(10, 10)
	left.add_child(_hand_flow)
	_choice_flow = UI.flow(8, 8)
	left.add_child(_choice_flow)

	var side := UI.column(8)
	side.custom_minimum_size = Vector2(430, 0)
	layout.add_child(side)
	side.add_child(UI.heading(Loc.t("game.citadels.players_title"), "Subtitle"))
	var scroll := UI.scroll(UI.column(10), false)
	side.add_child(scroll)
	_players_box = scroll.get_child(0) as VBoxContainer


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var actor := acting_player()
	var mine: Dictionary = _private_of(actor)
	_status.text = _status_text(state, actor, mine)
	_render_picked(mine)
	_render_pool(state, actor)
	_render_hand(state, actor, mine)
	_render_choices(state, actor)
	_render_players(state, actor)


func _private_of(_player: int) -> Dictionary:
	# §6.3: private data reaches views only through the authorized helper.
	return private_info()


# ------------------------------------------------------------------- status

func _status_text(state: Dictionary, actor: int, mine: Dictionary) -> String:
	var lines := PackedStringArray()
	if engine.finished:
		lines.append(Loc.t("game.common.finished_status", {"winner": engine.winner_text()}))
		return "\n".join(lines)
	var step := VariantUtil.as_string(state.get("step", ""), "")
	lines.append(Loc.t("game.citadels.turn_line", {
		"player": engine.player_name(actor),
		"phase": Loc.t("game.citadels.phase.%s" % step),
	}))
	if step == "draft":
		lines.append(Loc.t("game.citadels.draft_prompt"))
	else:
		var role := VariantUtil.as_int(state.get("current_role", 0), 0)
		lines.append(Loc.t("game.citadels.call_line", {
			"player": engine.player_name(actor),
			"role": engine.role_name(role),
			"gold": engine.gold_of(actor),
		}))
		if VariantUtil.as_int(state.get("killed_role", 0), 0) > 0:
			lines.append(Loc.t("game.citadels.killed_line", {"role": engine.role_name(VariantUtil.as_int(state.get("killed_role", 0), 0))}))
		var roles: Array = mine.get("roles", [])
		lines.append(Loc.t("game.citadels.my_roles", {"roles": _roles_text(roles)}))
		if bool(state.get("power_used", false)):
			lines.append(Loc.t("game.citadels.power_used"))
	return "\n".join(lines)


func _roles_text(roles: Array) -> String:
	if roles.is_empty():
		return Loc.t("game.citadels.none")
	var names := PackedStringArray()
	for role: Variant in roles:
		names.append(engine.role_name(int(role)))
	return ", ".join(names)


## The draft pool disappears as soon as a character is taken. Keep the chosen
## characters visible as their own small cards so a pick never vanishes into a
## line of status text.
func _render_picked(mine: Dictionary) -> void:
	_clear(_picked_flow)
	var roles: Array = mine.get("roles", [])
	_picked_title.text = Loc.t("game.citadels.picked_roles")
	_picked_title.visible = not roles.is_empty()
	_picked_flow.visible = not roles.is_empty()
	for role: Variant in roles:
		var role_id := int(role)
		var face := CardFace.new()
		var data := CardFace.data(
			"picked_role_%d" % role_id,
			engine.role_name(role_id),
			Loc.t("game.citadels.role_card_subtitle"),
			"", "", "", Palette.ACCENT,
			VariantUtil.as_string(ROLE_GLYPHS.get(engine.role_key(role_id), ""), "★")
		)
		data["tooltip"] = Loc.t("game.citadels.role.%s_power" % engine.role_key(role_id))
		face.configure(data, CardFace.WIDTH_MEDIUM)
		face.mouse_filter = Control.MOUSE_FILTER_PASS
		_picked_flow.add_child(face)


# --------------------------------------------------------------- board parts

func _render_pool(state: Dictionary, actor: int) -> void:
	_clear(_pool_flow)
	var step := VariantUtil.as_string(state.get("step", ""), "")
	var pool: Array = state.get("role_pool", [])
	_pool_title.visible = step == "draft"
	_pool_flow.visible = step == "draft"
	if step != "draft":
		return
	for role: Variant in pool:
		var role_id := int(role)
		var card := CardFace.new()
		var power := Loc.t("game.citadels.role.%s_power" % engine.role_key(role_id))
		# District cards are compact references; role cards carry a sentence of
		# rules text, so they get the medium width and the same text in the
		# tooltip when the card itself clips at a narrow window.
		card.configure(CardFace.data(
			"role_%d" % role_id,
			engine.role_name(role_id),
			Loc.t("game.citadels.role_card_subtitle"),
			"", power, "",
			Palette.ACCENT, VariantUtil.as_string(ROLE_GLYPHS.get(engine.role_key(role_id), ""), "★")
		), CardFace.WIDTH_MEDIUM)
		card.tooltip_text = power
		card.clicked.connect(func(_id: String) -> void: _submit_type("take_role", role_id))
		_pool_flow.add_child(card)


func _render_hand(state: Dictionary, actor: int, mine: Dictionary) -> void:
	_clear(_hand_flow)
	var hand: Array = mine.get("hand", [])
	_hand_title.text = Loc.t("game.citadels.hand_title") + " · " + Loc.tp("game.citadels.hand_count", hand.size())
	_hand_title.visible = not hand.is_empty()
	var builds: Dictionary = {}
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "build":
			builds[VariantUtil.as_int(action.get("slot", -1), -1)] = action
	for slot: int in range(hand.size()):
		var card_id := String(hand[slot])
		var action: Dictionary = builds.get(slot, {})
		var face := CardFace.new()
		# Only affordable districts carry a build action: a card without one is
		# presented dimmed and inert instead of submitting a guaranteed reject.
		var afford := not action.is_empty()
		var data := CardFace.data(
			card_id, engine.district_name(card_id), _colour_name(card_id),
			str(CitadelsEngine.district_cost(card_id)), "", _card_footer(state, actor, card_id),
			_colour_colour(card_id), "◆"
		)
		data["dimmed"] = not afford
		data["highlight"] = afford
		face.configure(data, CardFace.WIDTH_SMALL)
		face.tooltip_text = Loc.t("game.citadels.build_hint")
		if afford:
			face.clicked.connect(func(_id: String) -> void: _submit_action(action))
		_hand_flow.add_child(face)


func _card_footer(state: Dictionary, actor: int, card_id: String) -> String:
	if engine.finished or VariantUtil.as_int(state.get("current_player", -1), -1) != actor:
		return ""
	if VariantUtil.as_int(state.get("builds_done", 0), 0) >= VariantUtil.as_int(state.get("build_limit", 1), 1):
		return Loc.t("game.citadels.build_limit_reached")
	return "" if engine.gold_of(actor) >= CitadelsEngine.district_cost(card_id) else Loc.t("game.citadels.need_gold")


## Actions that need a target/selection, rendered as explicit buttons.
func _render_choices(state: Dictionary, actor: int) -> void:
	_clear(_choice_flow)
	if engine.finished:
		return
	for action: Dictionary in legal_actions():
		var type := VariantUtil.as_string(action.get("type", ""), "")
		if type == "build" or bool(action.get("_direct", true)):
			continue
		var text := Loc.t(VariantUtil.as_string(action.get("label_key", ""), "game.citadels.action.build"))
		match type:
			"assassinate", "steal":
				text += " — " + engine.role_name(VariantUtil.as_int(action.get("role", 0), 0))
			"magician_swap":
				text += " — " + engine.player_name(VariantUtil.as_int(action.get("target", -1), -1))
			"destroy":
				var target := VariantUtil.as_int(action.get("target", -1), -1)
				var cities: Array = VariantUtil.as_array(state.get("cities", []))
				var city: Array = VariantUtil.as_array(cities[target]) if target >= 0 and target < cities.size() else []
				var slot := VariantUtil.as_int(action.get("slot", -1), -1)
				var card_id := String(city[slot]) if slot >= 0 and slot < city.size() else ""
				text += Loc.t("game.citadels.destroy_detail", {
					"player": engine.player_name(target),
					"district": engine.district_name(card_id),
					"gold": VariantUtil.as_int(action.get("_price", 0), 0),
				})
		var button := UI.button(text, "Button", func() -> void: _submit_action(action))
		_choice_flow.add_child(button)


func _render_players(state: Dictionary, actor: int) -> void:
	_clear(_players_box)
	for player: int in range(engine.player_count()):
		var box := UI.column(6)
		# Wrap chips under the name instead of squeezing the auto-wrapped name
		# into a vertical column and stretching the chips into tall bars.
		var title := UI.flow(6, 6)
		var name_label := UI.label(engine.player_name(player), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.add_child(name_label)
		if engine.is_bot(player):
			title.add_child(UI.chip(Loc.t("game.common.bot"), Palette.TEXT_MUTED))
		if player == actor and not engine.finished:
			title.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
		if player == VariantUtil.as_int(state.get("first_player", -1), -1):
			title.add_child(UI.chip("♛", Palette.WARNING))
		var score: Dictionary = state.get("_scores", {}).get(str(player), {})
		title.add_child(UI.chip(Loc.t("game.citadels.score_chip", {"total": VariantUtil.as_int(score.get("total", 0), 0)}), Palette.ACCENT))
		var gold_label := UI.label(Loc.t("game.citadels.gold_chip", {"gold": engine.gold_of(player)}), "Small")
		gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.add_child(gold_label)
		box.add_child(title)
		box.add_child(UI.label(Loc.tp("game.citadels.city_count", engine.city_of(player).size()), "Small"))
		var flow := UI.flow(6, 6)
		for card_id: String in engine.city_of(player):
			var chip := UI.chip("%s (%d)" % [engine.district_name(card_id), CitadelsEngine.district_cost(card_id)],
				_colour_colour(card_id))
			flow.add_child(chip)
		box.add_child(flow)
		_players_box.add_child(UI.panel_with(box, "CardPanel", 10))


# ------------------------------------------------------------------- helpers

func _colour_name(card_id: String) -> String:
	return Loc.t("game.citadels.colour.%s" % CitadelsEngine.district_colour(card_id))


func _colour_colour(card_id: String) -> Color:
	return COLOUR_TINT.get(CitadelsEngine.district_colour(card_id), Palette.ACCENT)


## Submits the first legal action of `type`, optionally with a role parameter.
func _submit_type(type: String, role: int = 0) -> void:
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") != type:
			continue
		if role > 0 and VariantUtil.as_int(action.get("role", 0), 0) != role:
			continue
		submit(VariantUtil.as_string(action.get("key", ""), ""))
		return


func _submit_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if engine == null or engine.finished:
		return out
	var state := engine.public_state()
	var actor := acting_player()
	out.append(UI.chip(Loc.t("game.citadels.extras_step", {
		"phase": Loc.t("game.citadels.phase.%s" % VariantUtil.as_string(state.get("step", ""), "")),
	}), Palette.INFO))
	out.append(UI.chip(Loc.t("game.citadels.extras_gold", {"gold": engine.gold_of(actor)}), Palette.WARNING))
	var role := VariantUtil.as_int(state.get("current_role", 0), 0)
	if role > 0:
		out.append(UI.chip(engine.role_name(role), Palette.ACCENT))
	return out


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
