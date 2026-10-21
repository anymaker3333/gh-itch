extends GameView
## Codenames table: the 5×5 word grid, the cue picker and the team readout.
##
## The view never mutates the engine: clicks are turned into action keys of the
## acting player's legal action list and submitted through the session. A
## spymaster sees the key card painted on the unrevealed words, an operative sees
## them blank, which is exactly the game's hidden information.

const RED_CARD: Color = Color("c0392b")
const BLUE_CARD: Color = Color("2f6fbf")
const NEUTRAL_CARD: Color = Color("5d666f")
const ASSASSIN_CARD: Color = Color("14141a")
const UNKNOWN_CARD: Color = Color("263041")

const CELL_SIZE: Vector2 = Vector2(142, 86)
## Narrow windows need a little more room for the cue column; without this the
## fifth word row and the cue picker fall outside the board viewport.
const COMPACT_CELL_SIZE: Vector2 = Vector2(123, 65)

var _cells: Array[Button] = []
var _status: Label
var _role: Label
var _key_note: Label
var _agents: Label
var _cue_section: VBoxContainer
var _cue_flow: HFlowContainer
var _number_row: HBoxContainer
var _number_slider: HSlider
var _number_value: Label
var _selected_number: int = 2


func requires_handover() -> bool:
	return true


func build_board() -> void:
	var layout := UI.row(16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var compact := viewport_size().x < 1500.0
	var cell_size := COMPACT_CELL_SIZE if compact else CELL_SIZE
	var left := UI.column(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	var grid := UI.grid(5, 8, 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(grid)
	for cell: int in range(CodenamesEngine.CELLS):
		var button := Button.new()
		button.custom_minimum_size = cell_size
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 16 if compact else 18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_cell_pressed.bind(cell))
		_cells.append(button)
		grid.add_child(button)
	left.add_child(UI.label(Loc.t("game.codenames.board_hint"), "Caption"))

	var side := UI.column(6 if compact else 10)
	side.custom_minimum_size = Vector2(276 if compact else 320, 0)
	layout.add_child(side)
	_status = UI.label("", "Body")
	side.add_child(_status)
	_role = UI.label("", "Small")
	side.add_child(_role)
	side.add_child(UI.divider())
	_agents = UI.label("", "Small")
	side.add_child(_agents)
	side.add_child(UI.divider())
	_key_note = UI.label("", "Caption")
	side.add_child(_key_note)
	_cue_section = UI.column(6 if compact else 8)
	_cue_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_cue_section)
	_cue_section.add_child(UI.label(Loc.t("game.codenames.cue_prompt"), "Small"))
	_number_row = UI.hsep(8)
	_cue_section.add_child(_number_row)
	var number_caption := UI.label(Loc.t("game.codenames.cue_number"), "Small")
	number_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	number_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_number_row.add_child(number_caption)
	_number_slider = UI.slider(1.0, float(CodenamesEngine.MAX_CLUE_NUMBER), 1.0,
		float(_selected_number), _on_number_changed)
	_number_slider.custom_minimum_size = Vector2(120 if compact else 150, 24)
	_number_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_number_row.add_child(_number_slider)
	_number_value = UI.value_label(str(_selected_number), 28)
	_number_row.add_child(_number_value)
	_cue_flow = UI.flow(6, 6)
	var cue_scroll := UI.scroll(_cue_flow, false)
	cue_scroll.custom_minimum_size = Vector2(0, 120 if compact else 150)
	_cue_section.add_child(cue_scroll)


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var private := private_info()
	var grid_words: Array = VariantUtil.as_array(state.get("grid", []))
	var revealed: Array = VariantUtil.as_array(state.get("revealed", []))
	var key_card: Array = VariantUtil.as_array(private.get("key_card", []))
	var team := VariantUtil.as_int(private.get("team", 0), 0)
	var phase := VariantUtil.as_string(state.get("phase", "clue"), "clue")
	# Hotseat privacy: even a seat that happens to be a spymaster must not keep
	# the key painted while the device is in the guesser's hands. The colour
	# map returns as soon as the next clue phase starts.
	var offline_guess := session != null and not session.is_online() and phase == "guess"
	var perceiving_key := key_card.size() == CodenamesEngine.CELLS and not offline_guess
	var guess_keys := _guess_keys()
	var actor := engine.decision_player()
	for cell: int in range(_cells.size()):
		var word := VariantUtil.as_string(grid_words[cell], "?") if cell < grid_words.size() else "?"
		var face := _cell_color(cell, revealed, key_card, perceiving_key)
		var button := _cells[cell]
		button.text = word
		button.add_theme_stylebox_override("normal", _cell_style(face))
		button.add_theme_stylebox_override("hover", _cell_style(face.lightened(0.10)))
		button.add_theme_stylebox_override("pressed", _cell_style(face.darkened(0.12)))
		button.add_theme_stylebox_override("disabled", _cell_style(face.darkened(0.25)))
		button.add_theme_color_override("font_color", Palette.TEXT if face.get_luminance() < 0.6 else Palette.TEXT_ON_ACCENT)
		var owner := _owner_name(VariantUtil.as_string(key_card[cell], "") if cell < key_card.size() else "")
		button.tooltip_text = word if not perceiving_key else "%s · %s" % [word, owner]
		button.disabled = engine.finished or not guess_keys.has(cell)
	_role.text = Loc.t("game.codenames.your_role", {
		"role": Loc.t("game.codenames.role_spymaster" if VariantUtil.as_string(private.get("role", ""), "") == "spymaster" else "game.codenames.role_operative"),
		"team": Loc.t("game.codenames.team_red" if team == CodenamesEngine.RED else "game.codenames.team_blue"),
	})
	_key_note.text = Loc.t("game.codenames.key_visible" if perceiving_key else "game.codenames.key_hidden")
	_agents.text = Loc.t("game.codenames.agents_left", {
		"red": CodenamesEngine.team_remaining(state, CodenamesEngine.RED),
		"blue": CodenamesEngine.team_remaining(state, CodenamesEngine.BLUE),
	})
	_status.text = _status_text(state, actor, phase)
	var is_my_clue := phase == "clue" and VariantUtil.as_string(private.get("role", ""), "") == "spymaster" and not engine.finished
	_cue_section.visible = is_my_clue
	if is_my_clue:
		_refresh_cues(state)
		_number_row.visible = true


func _refresh_cues(state: Dictionary) -> void:
	_number_slider.set_value_no_signal(float(_selected_number))
	_number_value.text = str(_selected_number)
	_clear(_cue_flow)
	var vocab: Array = VariantUtil.as_array(state.get("cue_vocab", []))
	var keys := _clue_keys()
	for cue: Variant in vocab:
		var word := VariantUtil.as_string(cue, "")
		var key := VariantUtil.as_string(keys.get(word + "|%d" % _selected_number, ""), "")
		if key.is_empty():
			continue
		var button := UI.button(word, "Button", func() -> void: submit(key))
		_cue_flow.add_child(button)


func _status_text(state: Dictionary, actor: int, phase: String) -> String:
	if engine.finished:
		return Loc.t("game.codenames.finished", {"winner": engine.winner_text()})
	var team := VariantUtil.as_int(state.get("active_team", 0), 0)
	if phase == "clue":
		return Loc.t("game.codenames.turn_clue", {
			"player": engine.player_name(actor),
			"team": Loc.t("game.codenames.team_red" if team == CodenamesEngine.RED else "game.codenames.team_blue"),
		})
	var clue: Dictionary = VariantUtil.as_dict(state.get("clue", {}))
	return Loc.t("game.codenames.turn_guess", {
		"player": engine.player_name(actor),
		"team": Loc.t("game.codenames.team_red" if team == CodenamesEngine.RED else "game.codenames.team_blue"),
		"clue": Loc.t("game.codenames.cue_line", {"word": VariantUtil.as_string(clue.get("word", ""), ""), "number": VariantUtil.as_int(clue.get("number", 0), 0)}),
		"left": Loc.tp("game.codenames.guesses_left", VariantUtil.as_int(state.get("guesses_left", 0), 0)),
	})


func _cell_color(cell: int, revealed: Array, key_card: Array, perceiving_key: bool) -> Color:
	var shown := cell < revealed.size() and VariantUtil.as_int(revealed[cell], 0) == 1
	if not shown and not perceiving_key:
		return UNKNOWN_CARD
	var label := VariantUtil.as_string(key_card[cell], "") if cell < key_card.size() else ""
	var face := _owner_color(label)
	if not shown:
		return UNKNOWN_CARD.lerp(face, 0.32)
	return face


func _owner_color(label: String) -> Color:
	match label:
		CodenamesEngine.CARD_RED:
			return RED_CARD
		CodenamesEngine.CARD_BLUE:
			return BLUE_CARD
		CodenamesEngine.ASSASSIN:
			return ASSASSIN_CARD
	return NEUTRAL_CARD


func _owner_name(label: String) -> String:
	match label:
		CodenamesEngine.CARD_RED:
			return Loc.t("game.codenames.team_red")
		CodenamesEngine.CARD_BLUE:
			return Loc.t("game.codenames.team_blue")
		CodenamesEngine.ASSASSIN:
			return Loc.t("game.codenames.card_assassin")
	return Loc.t("game.codenames.card_neutral")


func _guess_keys() -> Dictionary:
	var out: Dictionary = {}
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "guess":
			out[VariantUtil.as_int(action.get("card", -1), -1)] = VariantUtil.as_string(action.get("key", ""), "")
	return out


func _clue_keys() -> Dictionary:
	var out: Dictionary = {}
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "clue":
			out["%s|%d" % [VariantUtil.as_string(action.get("word", ""), ""), VariantUtil.as_int(action.get("number", 0), 0)]] = VariantUtil.as_string(action.get("key", ""), "")
	return out


func _on_number_changed(value: float) -> void:
	_selected_number = int(value)
	if _number_value != null:
		_number_value.text = str(_selected_number)
	if engine != null and _cue_section.visible:
		_refresh_cues(engine.public_state())


func _on_cell_pressed(cell: int) -> void:
	var keys := _guess_keys()
	if not keys.has(cell):
		return
	Audio.play(Audio.Sfx.CARD)
	submit(VariantUtil.as_string(keys[cell], ""))


func _cell_style(background: Color) -> StyleBoxFlat:
	return ThemeBuilder.flat(background, background.lightened(0.18), 1, ThemeBuilder.RADIUS_SMALL, 6)


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
