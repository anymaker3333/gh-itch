extends GameView
## Coup table: hidden influence, the claim under challenge, blocks, the reveal
## step and the exchange.
##
## The view renders [method GameEngine.public_state] plus the acting player's
## private hand and turns clicks into action keys through [method submit]; it
## never mutates the engine, which keeps hotseat, solo and online play identical.

const ROLE_TINTS: Dictionary = {
	"duke": Color("#c9a227"),
	"assassin": Color("#b8455f"),
	"captain": Color("#2f7bd8"),
	"ambassador": Color("#3fae6a"),
	"contessa": Color("#8f6bd6"),
}
const ROLE_GLYPHS: Dictionary = {
	"duke": "♔", "assassin": "🗡", "captain": "⚓", "ambassador": "🕊", "contessa": "🌹",
}
## The role reference and the hand cards reuse the already translated action
## names instead of duplicating five ability descriptions per locale.
const ROLE_ORDER: Array[String] = ["duke", "assassin", "captain", "ambassador", "contessa"]
const ROLE_ABILITY_KEYS: Dictionary = {
	"duke": "game.coup.action.tax",
	"assassin": "game.coup.action.assassinate",
	"captain": "game.coup.action.steal",
	"ambassador": "game.coup.action.exchange",
	"contessa": "game.coup.action.block_contessa",
}

var _status: Label
var _claim: Label
var _hand_title: Label
var _hand_flow: HFlowContainer
var _choice_title: Label
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
	_claim = UI.label("", "Subtitle")
	left.add_child(_claim)
	# With only two players the turn area is short. Let the influence cards and
	# target choices take the middle of the table instead of leaving all empty
	# space underneath them.
	left.add_child(UI.spacer(4, true))
	_hand_title = UI.label("", "Subtitle")
	left.add_child(_hand_title)
	_hand_flow = UI.flow(10, 10)
	left.add_child(_hand_flow)
	_choice_title = UI.label("", "Subtitle")
	left.add_child(_choice_title)
	_choice_flow = UI.flow(8, 8)
	left.add_child(_choice_flow)
	left.add_child(UI.spacer(4, true))

	var side := UI.column(8)
	side.custom_minimum_size = Vector2(430, 0)
	layout.add_child(side)
	side.add_child(UI.heading(Loc.t("game.coup.players_title"), "Subtitle"))
	var scroll := UI.scroll(UI.column(10), false)
	side.add_child(scroll)
	_players_box = scroll.get_child(0) as VBoxContainer

	# The role reference is compact reference text, not part of the turn area.
	# Keeping it in the right rail under the players uses the column that would
	# otherwise stay empty and leaves the left column focused on the current
	# claim, hand and target choice.
	var guide := UI.column(4)
	guide.add_child(UI.heading(Loc.t("game.coup.roles_title"), "Subtitle"))
	for role: String in ROLE_ORDER:
		var line := UI.label("%s — %s" % [Loc.t("game.coup.role.%s" % role), _role_ability(role)], "Small")
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		guide.add_child(line)
	side.add_child(UI.panel_with(guide, "CardPanel", 10))


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var actor := acting_player()
	var mine: Dictionary = _private_of(actor)
	_status.text = _status_text(state, actor)
	_claim.text = _claim_text(state)
	_claim.visible = not _claim.text.is_empty()
	_render_hand(state, actor, mine)
	_render_choices(state, actor)
	_render_players(state, actor)


func _private_of(_player: int) -> Dictionary:
	# §6.3: private data reaches views only through the authorized helper.
	return private_info()


# ------------------------------------------------------------------- status

func _status_text(state: Dictionary, actor: int) -> String:
	if engine.finished:
		return Loc.t("game.common.finished_status", {"winner": engine.winner_text()})
	match VariantUtil.as_string(state.get("step", ""), ""):
		"action":
			return Loc.t("game.coup.turn_line", {
				"player": engine.player_name(actor),
				"coins": VariantUtil.as_int(VariantUtil.as_array(state.get("coins", []))[actor], 0) if actor >= 0 and actor < VariantUtil.as_array(state.get("coins", [])).size() else 0,
			})
		"challenge":
			return Loc.t("game.coup.challenge_prompt", {"player": engine.player_name(actor)})
		"block":
			return Loc.t("game.coup.block_prompt", {"player": engine.player_name(actor)})
		"lose":
			return Loc.t("game.coup.lose_prompt", {"player": engine.player_name(actor)})
		"exchange":
			var hand: Array = VariantUtil.as_array(_private_of(actor).get("hand", []))
			var keep := VariantUtil.as_int(VariantUtil.as_dict(state.get("pending", {})).get("keep", 0), 0)
			return Loc.tp("game.coup.exchange_prompt", maxi(0, hand.size() - keep), {
				"player": engine.player_name(actor), "count": maxi(0, hand.size() - keep),
			})
	return engine.phase_hint()


## The public claim under challenge or block, for the second status line.
func _claim_text(state: Dictionary) -> String:
	var step := VariantUtil.as_string(state.get("step", ""), "")
	if step == "challenge":
		var claim: Dictionary = VariantUtil.as_dict(state.get("claim", {}))
		var claimant := VariantUtil.as_int(claim.get("player", -1), -1)
		var role := VariantUtil.as_string(claim.get("role", ""), "")
		if VariantUtil.as_string(claim.get("kind", ""), "action") == "block":
			return Loc.t("game.coup.claim_block_line", {
				"player": engine.player_name(claimant), "role": engine.role_name(role),
				"action": _action_name(VariantUtil.as_string(claim.get("type", ""), "")),
			})
		return Loc.t("game.coup.claim_action_line", {
			"player": engine.player_name(claimant), "role": engine.role_name(role),
			"action": _action_name(VariantUtil.as_string(claim.get("type", ""), "")),
		})
	if step == "block":
		var pending: Dictionary = VariantUtil.as_dict(state.get("pending", {}))
		return Loc.t("game.coup.block_line", {
			"player": engine.player_name(VariantUtil.as_int(pending.get("actor", -1), -1)),
			"action": _action_name(VariantUtil.as_string(pending.get("type", ""), "")),
		})
	return ""


func _action_name(type: String) -> String:
	match type:
		"income":
			return Loc.t("game.coup.action.income")
		"foreign_aid":
			return Loc.t("game.coup.action.foreign_aid")
		"tax":
			return Loc.t("game.coup.action.tax")
		"exchange":
			return Loc.t("game.coup.action.exchange")
		"coup":
			return Loc.t("game.coup.action.coup")
		"assassinate":
			return Loc.t("game.coup.action.assassinate")
		"steal":
			return Loc.t("game.coup.action.steal")
	return ""


# --------------------------------------------------------------- board parts

func _render_hand(state: Dictionary, actor: int, mine: Dictionary) -> void:
	_clear(_hand_flow)
	var step := VariantUtil.as_string(state.get("step", ""), "")
	var hand: Array = VariantUtil.as_array(mine.get("hand", []))
	var visible := step == "action" or step == "challenge" or step == "block" or step == "lose" or step == "exchange"
	_hand_title.visible = visible and not hand.is_empty()
	_hand_title.text = Loc.t("game.coup.hand_title", {"player": engine.player_name(actor)})
	if not visible:
		return
	var clickable := step == "lose" or step == "exchange"
	var clicks: Dictionary = {}
	if clickable:
		for action: Dictionary in legal_actions():
			var type := VariantUtil.as_string(action.get("type", ""), "")
			if type == "lose_card" or type == "return_card":
				clicks[VariantUtil.as_int(action.get("slot", -1), -1)] = action
	for slot: int in range(hand.size()):
		var role := VariantUtil.as_string(hand[slot], "")
		var face := CardFace.new()
		var footer := ""
		if step == "lose":
			footer = Loc.t("game.coup.lose_hint")
		elif step == "exchange":
			footer = Loc.t("game.coup.return_hint")
		else:
			footer = Loc.t("game.coup.secret_note")
		face.configure(CardFace.data(
			role, engine.role_name(role), Loc.t("game.coup.role_card_subtitle"), "",
			_role_ability(role), footer, _tint(role), VariantUtil.as_string(ROLE_GLYPHS.get(role, ""), "★")
		), CardFace.WIDTH_SMALL)
		var action: Dictionary = clicks.get(slot, {})
		face.tooltip_text = footer
		if not action.is_empty():
			face.clicked.connect(func(_id: String) -> void: _submit_action(action))
		_hand_flow.add_child(face)


## Targeted actions (coup, assassinate, steal) become one button per victim.
func _render_choices(state: Dictionary, actor: int) -> void:
	_clear(_choice_flow)
	_choice_title.visible = false
	if engine.finished or VariantUtil.as_string(state.get("step", ""), "") != "action":
		return
	for action: Dictionary in legal_actions():
		var type := VariantUtil.as_string(action.get("type", ""), "")
		if type != "coup" and type != "assassinate" and type != "steal":
			continue
		var target := VariantUtil.as_int(action.get("target", -1), -1)
		var variation := "DangerButton" if type == "coup" or type == "assassinate" else "Button"
		var text := "%s — %s" % [Loc.t(VariantUtil.as_string(action.get("label_key", ""), "")), engine.player_name(target)]
		var button := UI.button(text, variation, func() -> void: _submit_action(action))
		button.disabled = not bool(action.get("_enabled", true))
		_choice_flow.add_child(button)
	_choice_title.visible = _choice_flow.get_child_count() > 0
	_choice_title.text = Loc.t("game.coup.targets_title")


func _render_players(state: Dictionary, actor: int) -> void:
	_clear(_players_box)
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var shown: Array = VariantUtil.as_array(state.get("revealed", []))
	var coins: Array = VariantUtil.as_array(state.get("coins", []))
	for player: int in range(engine.player_count()):
		var box := UI.column(6)
		var title := UI.row(8)
		var name_label := UI.label(engine.player_name(player), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.add_child(name_label)
		if engine.is_bot(player):
			title.add_child(UI.chip(Loc.t("game.common.bot"), Palette.TEXT_MUTED))
		if player == actor and not engine.finished:
			title.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
		if VariantUtil.as_int(counts[player], 0) <= 0:
			title.add_child(UI.chip(Loc.t("game.coup.out_chip"), Palette.DANGER))
		title.add_child(UI.spacer())
		title.add_child(UI.chip(Loc.t("game.coup.coins_chip", {"coins": VariantUtil.as_int(coins[player], 0)}), Palette.WARNING))
		box.add_child(title)
		box.add_child(UI.label(Loc.tp("game.coup.influence_count", VariantUtil.as_int(counts[player], 0)), "Small"))
		var flow := UI.flow(6, 6)
		for card: Variant in shown[player]:
			flow.add_child(UI.chip(engine.role_name(VariantUtil.as_string(card, "")), Palette.TEXT_MUTED))
		box.add_child(flow)
		_players_box.add_child(UI.panel_with(box, "CardPanel", 10))


# ------------------------------------------------------------------- helpers

func _tint(role: String) -> Color:
	return ROLE_TINTS.get(role, Palette.ACCENT)


func _role_ability(role: String) -> String:
	var key := VariantUtil.as_string(ROLE_ABILITY_KEYS.get(role, ""), "")
	return Loc.t(key) if not key.is_empty() else ""


func _submit_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if engine == null or engine.finished:
		return out
	var state := engine.public_state()
	out.append(UI.chip(Loc.t("game.coup.extras_phase", {
		"phase": Loc.t("game.coup.phase.%s" % VariantUtil.as_string(state.get("step", ""), "")),
	}), Palette.INFO))
	var actor := acting_player()
	out.append(UI.chip(Loc.t("game.coup.extras_coins", {
		"coins": engine.coins_of(actor),
	}), Palette.WARNING))
	out.append(UI.chip(Loc.t("game.coup.extras_deck", {
		"count": VariantUtil.as_int(state.get("deck_count", 0), 0),
	}), Palette.TEXT_MUTED))
	return out


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
