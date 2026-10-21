extends GameView
## Chess table: 8×8 board with click-to-move, promotion picker and side panel.
##
## The view never mutates the engine: it renders `engine.public_state()` and turns
## clicks into action keys submitted through the session, which is what makes the
## same screen work for hotseat, solo and (host-validated) online play.

const LIGHT_SQUARE: Color = Color("eed9b5")
const DARK_SQUARE: Color = Color("4f735f")
const SELECTED: Color = Color("6c8ef5")
const HINT_MOVE: Color = Color("4f9a67")
const HINT_CAPTURE: Color = Color("c84a42")
const LAST_MOVE: Color = Color("e7c455")
const WHITE_PIECE: Color = Color("f7f0df")
const BLACK_PIECE: Color = Color("151820")

const GLYPHS: Dictionary = {
	"K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘", "P": "♙",
	"k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟",
}

var _board_grid: GridContainer
var _squares: Array[Button] = []
var _status: Label
var _captured_row: HBoxContainer
var _promotion_row: HFlowContainer
var _promotion_label: Label
var _coords: GridContainer
var _top_files: Array[Label] = []
var _bottom_files: Array[Label] = []
var _left_ranks: Array[Label] = []
var _right_ranks: Array[Label] = []
const SQUARE_SIZE: int = 66
const COORD_SIZE: int = 16
var _selected: int = -1
var _targets: Dictionary = {}  # square -> action key
var _pending_promotion: int = -1
var _hint: String = ""
var _flipped: bool = false
var _rotate_toggle: CheckButton
var _updating_rotate: bool = false


func requires_handover() -> bool:
	return false


func build_board() -> void:
	var layout := UI.row(16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var left := UI.column(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	var board_panel := UI.panel("ElevatedPanel")
	board_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(board_panel)
	var board_margin := UI.margin_container(null, 8)
	board_panel.add_child(board_margin)
	_board_grid = UI.grid(10, 2, 2)
	_board_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board_margin.add_child(_board_grid)
	# File/rank coordinates are part of the grid, so the board reads like a real
	# diagram and the labels rotate with the board.
	_board_grid.add_child(_coord_spacer())
	for col: int in range(8):
		var top_file := _coord_label("")
		_top_files.append(top_file)
		_board_grid.add_child(top_file)
	_board_grid.add_child(_coord_spacer())
	for row: int in range(8):
		var left_rank := _coord_label("")
		_left_ranks.append(left_rank)
		_board_grid.add_child(left_rank)
		for col: int in range(8):
			var display := row * 8 + col
			var button := Button.new()
			button.custom_minimum_size = Vector2(SQUARE_SIZE, SQUARE_SIZE)
			button.focus_mode = Control.FOCUS_ALL
			button.add_theme_font_size_override("font_size", 40)
			button.set_meta("square", _square_at(display))
			button.pressed.connect(_on_square_pressed.bind(display))
			_squares.append(button)
			_board_grid.add_child(button)
		var right_rank := _coord_label("")
		_right_ranks.append(right_rank)
		_board_grid.add_child(right_rank)
	_board_grid.add_child(_coord_spacer())
	for col: int in range(8):
		var bottom_file := _coord_label("")
		_bottom_files.append(bottom_file)
		_board_grid.add_child(bottom_file)
	_board_grid.add_child(_coord_spacer())
	_refresh_coords()
	_captured_row = UI.hsep(6)
	left.add_child(_captured_row)

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(300, 0)
	layout.add_child(side)
	_status = UI.label("", "Body")
	side.add_child(_status)
	side.add_child(UI.divider())
	_rotate_toggle = UI.toggle(Loc.t("game.chess.rotate_board"), _flipped, _on_rotate_toggled)
	side.add_child(_rotate_toggle)
	side.add_child(UI.divider())
	_promotion_label = UI.label(Loc.t("game.chess.promotion"), "Small")
	_promotion_label.visible = false
	side.add_child(_promotion_label)
	_promotion_row = UI.flow(8, 8)
	side.add_child(_promotion_row)
	side.add_child(UI.divider())
	side.add_child(UI.label(Loc.t("game.chess.notation_hint"), "Caption"))


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	var board: Array = VariantUtil.as_array(state.get("board", []))
	var last: Dictionary = VariantUtil.as_dict(state.get("last_move", {}))
	var actives := _legal_moves_by_from()
	_pending_promotion = -1
	_promotion_label.visible = false
	_clear(_promotion_row)
	_refresh_coords()
	if _rotate_toggle != null:
		_updating_rotate = true
		_rotate_toggle.text = Loc.t("game.chess.rotate_board")
		_rotate_toggle.button_pressed = _flipped
		_updating_rotate = false
	for display: int in range(64):
		var square := _square_at(display)
		var piece := VariantUtil.as_string(board[square], "") if square < board.size() else ""
		var button := _squares[display]
		var light := ((square % 8) + (square / 8)) % 2 == 1
		var background := LIGHT_SQUARE if light else DARK_SQUARE
		if _selected == square:
			background = background.lerp(SELECTED, 0.55)
		elif _targets.has(square):
			var is_capture := not VariantUtil.as_string(VariantUtil.as_dict(_targets[square]).get("_capture", ""), "").is_empty()
			background = background.lerp(HINT_CAPTURE if is_capture else HINT_MOVE, 0.55)
		elif VariantUtil.as_int(last.get("from", -1), -1) == square or VariantUtil.as_int(last.get("to", -1), -1) == square:
			background = background.lerp(LAST_MOVE, 0.45)
		button.add_theme_stylebox_override("normal", _square_style(background, display))
		button.add_theme_stylebox_override("hover", _square_style(background.lightened(0.08), display))
		button.add_theme_stylebox_override("pressed", _square_style(background.darkened(0.1), display))
		button.add_theme_stylebox_override("focus", _square_style(background, display))
		button.add_theme_stylebox_override("disabled", _square_style(background, display))
		button.text = VariantUtil.as_string(GLYPHS.get(piece, ""), "")
		var white_piece := not piece.is_empty() and piece == piece.to_upper()
		button.add_theme_color_override("font_color", WHITE_PIECE if white_piece else BLACK_PIECE)
		button.add_theme_color_override("font_disabled_color", WHITE_PIECE if white_piece else BLACK_PIECE)
		button.add_theme_color_override("font_outline_color", Color("251d16") if white_piece else Color("f0e3c7"))
		button.add_theme_constant_override("outline_size", 5 if white_piece else 4)
		button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		button.add_theme_constant_override("shadow_offset_y", 2)
		button.tooltip_text = _square_name(square) + (" · " + piece.to_upper() if not piece.is_empty() else "")
		button.disabled = engine.finished or not (actives.has(square) or _targets.has(square))
	_status.text = _status_text()
	_refresh_captured(VariantUtil.as_array(state.get("_captured", [])))
	if not _targets.is_empty():
		_promotion_label.visible = false


func _legal_moves_by_from() -> Dictionary:
	var out: Dictionary = {}
	if engine == null or engine.finished:
		return out
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") != "move":
			continue
		var from := VariantUtil.as_int(action.get("from", -1), -1)
		if not out.has(from):
			out[from] = []
		VariantUtil.as_array(out[from]).append(action)
	return out


func _status_text() -> String:
	var state := engine.public_state()
	var check: Dictionary = VariantUtil.as_dict(state.get("_check", {}))
	var lines := PackedStringArray()
	lines.append(Loc.t("game.chess.turn_line", {
		"player": engine.player_name(engine.decision_player()),
		"colour": Loc.t("game.chess.colour_white" if engine.decision_player() == 0 else "game.chess.colour_black"),
	}))
	if bool(check.get("white", false)):
		lines.append(Loc.t("game.chess.check_white"))
	if bool(check.get("black", false)):
		lines.append(Loc.t("game.chess.check_black"))
	if engine.finished:
		lines.append(Loc.t("game.common.finished_status", {"winner": engine.winner_text()}))
	lines.append(Loc.t("game.chess.move_number", {"number": engine.round_index}))
	if not _hint.is_empty():
		lines.append(Loc.t("game.chess.hint_top", {"move": _hint}))
	return "\n".join(lines)


## Runs the chess engine's search once, on demand (it is too slow to run on
## every board refresh, so the board stays responsive).
func _top_move() -> String:
	var best := BotDirector.choose_action(engine, engine.decision_player())
	if best.is_empty():
		return "-"
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("key", ""), "") == best:
			return engine.notation_for({
				"from": VariantUtil.as_int(action.get("from", 0), 0),
				"to": VariantUtil.as_int(action.get("to", 0), 0),
				"piece": VariantUtil.as_string(action.get("_piece", ""), "P"),
				"capture": VariantUtil.as_string(action.get("_capture", ""), ""),
				"flags": VariantUtil.as_string(action.get("_flags", ""), ""),
				"promo": VariantUtil.as_string(action.get("promo", ""), ""),
			})
	return "-"


func _refresh_captured(items: Array) -> void:
	_clear(_captured_row)
	if items.is_empty():
		return
	_captured_row.add_child(UI.label(Loc.t("game.chess.captured"), "Caption"))
	var counts: Dictionary = {}
	for piece: Variant in items:
		var letter := VariantUtil.as_string(piece, "").to_upper()
		counts[letter] = VariantUtil.as_int(counts.get(letter, 0), 0) + 1
	for letter: String in ["Q", "R", "B", "N", "P"]:
		if not counts.has(letter):
			continue
		var label := UI.label("%s×%d" % [VariantUtil.as_string(GLYPHS.get(letter, letter), letter), int(counts[letter])], "Body")
		label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		_captured_row.add_child(label)


func _on_square_pressed(display: int) -> void:
	if engine == null or engine.finished:
		return
	var square := _square_at(display)
	if _targets.has(square):
		var action: Dictionary = _targets[square]
		if VariantUtil.as_string(action.get("promo", ""), "").is_empty() and _promotion_options_for(square).size() > 1:
			_show_promotion(square)
			return
		_submit(action)
		return
	var move_list: Array = _legal_moves_by_from().get(square, [])
	if move_list.is_empty():
		_selected = -1
		_targets.clear()
		refresh_board()
		return
	_selected = square
	_targets.clear()
	for action: Dictionary in move_list:
		_targets[VariantUtil.as_int(action.get("to", -1), -1)] = action
	Audio.play(Audio.Sfx.CLICK)
	refresh_board()


func _promotion_options_for(square: int) -> Array:
	var from := VariantUtil.as_int(VariantUtil.as_dict(_targets[square]).get("from", -1), -1)
	var out: Array = []
	for action: Dictionary in _legal_moves_by_from().get(from, []):
		if VariantUtil.as_int(action.get("to", -1), -1) == square and not VariantUtil.as_string(action.get("promo", ""), "").is_empty():
			out.append(action)
	return out


func _show_promotion(square: int) -> void:
	var options := _promotion_options_for(square)
	_pending_promotion = square
	_promotion_label.visible = true
	_clear(_promotion_row)
	for action: Dictionary in options:
		var promo := VariantUtil.as_string(action.get("promo", ""), "q").to_upper()
		var button := UI.button(VariantUtil.as_string(GLYPHS.get(promo, promo), promo), "Button", func() -> void:
			_submit(action)
		)
		button.custom_minimum_size = Vector2(48, 48)
		button.add_theme_font_size_override("font_size", 26)
		_promotion_row.add_child(button)


func _submit(action: Dictionary) -> void:
	_selected = -1
	_targets.clear()
	_pending_promotion = -1
	for child: Node in _promotion_row.get_children():
		(child as Node).queue_free()
	_promotion_label.visible = false
	submit(VariantUtil.as_string(action.get("key", ""), ""))


func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if _selected >= 0:
		var name := _square_name(_selected)
		var piece: String = engine.piece_at(_selected)
		out.append(UI.chip(Loc.t("game.chess.selected", {"square": name, "piece": piece.to_upper()}), Palette.ACCENT))
		var cancel := UI.button(Loc.t("common.cancel"), "GhostButton", func() -> void:
			_selected = -1
			_targets.clear()
			refresh_board()
		)
		out.append(cancel)
	var hint := UI.button(Loc.t("game.chess.suggest"), "Button", func() -> void:
		_hint = _top_move()
		refresh_board()
	)
	hint.disabled = engine.finished
	out.append(hint)
	return out


func _square_at(display: int) -> int:
	var row := display / 8
	var column := display % 8
	if _flipped:
		return row * 8 + (7 - column)
	return (7 - row) * 8 + column


func _on_rotate_toggled(pressed: bool) -> void:
	if _updating_rotate:
		return
	_flipped = pressed
	_selected = -1
	_targets.clear()
	refresh_board()


func _square_name(square: int) -> String:
	return "%s%d" % ["abcdefgh"[square % 8], (square / 8) + 1]


func _coord_label(text: String) -> Label:
	var label := UI.label(text, "Caption", HORIZONTAL_ALIGNMENT_CENTER)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(COORD_SIZE, COORD_SIZE)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _coord_spacer() -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(COORD_SIZE, COORD_SIZE)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _refresh_coords() -> void:
	for col: int in range(mini(8, _top_files.size())):
		var file := _square_name(_square_at(col)).substr(0, 1)
		_top_files[col].text = file
		if col < _bottom_files.size():
			_bottom_files[col].text = file
	for row: int in range(mini(8, _left_ranks.size())):
		var rank := _square_name(_square_at(row * 8)).substr(1)
		_left_ranks[row].text = rank
		if row < _right_ranks.size():
			_right_ranks[row].text = rank


func _square_style(background: Color, display: int) -> StyleBoxFlat:
	var style := ThemeBuilder.flat(background, background.darkened(0.35), 1, 2, 0)
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 2
	style.shadow_offset = Vector2(1 if (display / 8) % 2 == 0 else -1, 2)
	return style


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
