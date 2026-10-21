extends GameView
## Spyfall table: the secret identity card, the public question/answer history
## and the acting seat's controls (ask, accuse, answer, name the location).
##
## Everything is rebuilt from `engine.public_state()` plus the authorized
## private slice ([method GameView.private_info]), so the same screen serves
## hotseat and online play; the view never mutates the engine.

var _identity: VBoxContainer
var _status: Label
var _history: VBoxContainer
var _controls: VBoxContainer
var _selected_question: int = 0


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
	var identity_panel := UI.panel("CardPanel")
	left.add_child(identity_panel)
	_identity = UI.column(6)
	identity_panel.add_child(UI.margin_container(_identity, 12))
	_status = UI.label("", "Caption")
	left.add_child(_status)
	left.add_child(UI.separator_label(Loc.t("game.spyfall.history_title")))
	_history = UI.column(6)
	left.add_child(UI.scroll(_history, false))

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(360, 0)
	layout.add_child(side)
	var controls_panel := UI.panel("CardPanel")
	controls_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(controls_panel)
	_controls = UI.column(8)
	controls_panel.add_child(UI.margin_container(_controls, 12))
	side.add_child(UI.label(Loc.t("game.spyfall.identity_hint"), "Caption"))


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var player := acting_player()
	var private := private_info()
	_refresh_identity(private)
	_refresh_history(state)
	var phase := VariantUtil.as_string(state.get("phase", "ask"), "ask")
	if engine.finished:
		_status.text = Loc.t("game.spyfall.finished", {"winner": engine.winner_text()})
	else:
		_status.text = Loc.t("game.spyfall.status_answer" if phase == "answer" else "game.spyfall.status_ask", {
			"player": engine.player_name(engine.decision_player()),
			"asks": Loc.t("game.spyfall.asks_line", {
				"count": VariantUtil.as_int(state.get("asks", 0), 0),
				"limit": VariantUtil.as_int(state.get("asks_limit", 1), 1),
			}),
		})
	_refresh_controls(state, private, player, phase)


func _refresh_identity(private: Dictionary) -> void:
	_clear(_identity)
	if private.is_empty():
		_identity.add_child(UI.label(Loc.t("game.spyfall.identity_unknown"), "Body"))
		return
	if bool(private.get("is_spy", false)):
		_identity.add_child(UI.chip(Loc.t("game.spyfall.spy_label"), Palette.DANGER))
		_identity.add_child(UI.label(Loc.t("game.spyfall.identity_spy"), "Small"))
		var names := PackedStringArray()
		for candidate: Variant in VariantUtil.as_array(private.get("candidates", [])):
			names.append(Loc.t("game.spyfall.location.%s" % VariantUtil.as_string(candidate, "")))
		_identity.add_child(UI.label(Loc.t("game.spyfall.candidates", {"list": ", ".join(names)}), "Body"))
		return
	_identity.add_child(UI.chip(Loc.t("game.spyfall.agent_label"), Palette.POSITIVE))
	_identity.add_child(UI.label(Loc.t("game.spyfall.identity_agent", {
		"location": Loc.t("game.spyfall.location.%s" % VariantUtil.as_string(private.get("location", ""), "")),
		"role": Loc.t("game.spyfall.role.%s" % VariantUtil.as_string(private.get("role", ""), "")),
	}), "Subtitle"))
	_identity.add_child(UI.label(Loc.t("game.spyfall.agents_goal"), "Small"))


func _refresh_history(state: Dictionary) -> void:
	_clear(_history)
	var entries: Array = VariantUtil.as_array(state.get("history", []))
	if entries.is_empty():
		_history.add_child(UI.label(Loc.t("game.spyfall.history_empty"), "Caption"))
		return
	for entry: Variant in entries:
		var record: Dictionary = entry
		_history.add_child(UI.label(Loc.t("game.spyfall.history_entry", {
			"asker": engine.player_name(VariantUtil.as_int(record.get("asker", -1), -1)),
			"target": engine.player_name(VariantUtil.as_int(record.get("target", -1), -1)),
			"question": Loc.t(SpyfallEngine.QUESTIONS[clampi(VariantUtil.as_int(record.get("question", 0), 0), 0, SpyfallEngine.QUESTIONS.size() - 1)]),
			"answer": Loc.t(SpyfallEngine.ANSWERS[clampi(VariantUtil.as_int(record.get("answer", 0), 0), 0, SpyfallEngine.ANSWERS.size() - 1)]),
		}), "Small"))
	var cleared: Array = VariantUtil.as_array(state.get("cleared", []))
	if not cleared.is_empty():
		var names := PackedStringArray()
		for player: Variant in cleared:
			names.append(engine.player_name(VariantUtil.as_int(player, -1)))
		_history.add_child(UI.chip(Loc.t("game.spyfall.cleared", {"list": ", ".join(names)}), Palette.INFO))


func _refresh_controls(state: Dictionary, private: Dictionary, player: int, phase: String) -> void:
	_clear(_controls)
	if engine.finished:
		_controls.add_child(UI.label(Loc.t("game.spyfall.reveal", {
			"spy": engine.player_name(VariantUtil.as_int(engine.result.get("_spy", -1), -1)),
			"location": Loc.t("game.spyfall.location.%s" % VariantUtil.as_string(engine.result.get("_location", ""), "")),
		}), "Body"))
		return
	if bool(private.get("is_spy", false)) and phase == "ask":
		_controls.add_child(UI.section_header(Loc.t("game.spyfall.name_prompt"), Loc.t("game.spyfall.name_hint")))
		var named := UI.flow(6, 6)
		_controls.add_child(named)
		for action: Dictionary in legal_actions():
			if VariantUtil.as_string(action.get("type", ""), "") != "name_location":
				continue
			var location := VariantUtil.as_string(action.get("location", ""), "")
			var key := VariantUtil.as_string(action.get("key", ""), "")
			if not VariantUtil.as_array(private.get("candidates", [])).has(location):
				continue
			named.add_child(UI.button(Loc.t("game.spyfall.location.%s" % location), "DangerButton", func() -> void:
				submit(key)
			))
	if phase == "answer":
		_controls.add_child(UI.section_header(Loc.t("game.spyfall.answer_prompt")))
		var answers := UI.flow(6, 6)
		_controls.add_child(answers)
		for action: Dictionary in legal_actions():
			if VariantUtil.as_string(action.get("type", ""), "") != "answer":
				continue
			var index := VariantUtil.as_int(action.get("answer", 0), 0)
			var key := VariantUtil.as_string(action.get("key", ""), "")
			answers.add_child(UI.button(Loc.t(SpyfallEngine.ANSWERS[index]), "Button", func() -> void:
				submit(key)
			))
		return
	_controls.add_child(UI.section_header(Loc.t("game.spyfall.question_prompt")))
	_controls.add_child(UI.dropdown(_question_entries(), str(_selected_question), func(value: String) -> void:
		_selected_question = int(value)
		refresh_board()
	))
	var suspects := UI.flow(6, 6)
	_controls.add_child(suspects)
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") != "ask":
			continue
		if VariantUtil.as_int(action.get("question", -1), -1) != _selected_question:
			continue
		var target := VariantUtil.as_int(action.get("target", -1), -1)
		var key := VariantUtil.as_string(action.get("key", ""), "")
		suspects.add_child(UI.button(Loc.t("game.spyfall.ask_button", {"player": engine.player_name(target)}), "Button", func() -> void:
			submit(key)
		))
	_controls.add_child(UI.divider())
	_controls.add_child(UI.section_header(Loc.t("game.spyfall.accuse_prompt"), Loc.t("game.spyfall.accuse_hint")))
	var accusers := UI.flow(6, 6)
	_controls.add_child(accusers)
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") != "accuse":
			continue
		var target := VariantUtil.as_int(action.get("target", -1), -1)
		var key := VariantUtil.as_string(action.get("key", ""), "")
		accusers.add_child(UI.button(Loc.t("game.spyfall.accuse_button", {"player": engine.player_name(target)}), "DangerButton", func() -> void:
			submit(key)
		))


func _question_entries() -> Array:
	var out: Array = []
	for index: int in range(SpyfallEngine.QUESTIONS.size()):
		out.append({"label": Loc.t(SpyfallEngine.QUESTIONS[index]), "value": str(index)})
	return out


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
