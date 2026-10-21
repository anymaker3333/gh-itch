class_name ChessEngine
extends GameEngine
## Chess rules engine (standard international chess).
##
## Complete rules: piece movement, castling, en passant, promotion, check,
## checkmate, stalemate, threefold repetition, the fifty-move rule and
## insufficient-material draws. Positions can be imported and exported as FEN,
## which is what the rules tests use to reach endgame situations quickly.
##
## The engine is deterministic: no randomness is used, and the same action
## sequence always produces the same state. Chess has no hidden information, so
## [method private_state] stays empty.
##
## Representation: `board[square]` holds `""` or a piece letter where uppercase is
## White (`PNBRQK`) and lowercase is Black (`pnbrqk`).
## `square = rank * 8 + file`, so `a1 = 0` and `h8 = 63`. Action keys are built
## from `from`, `to` and `promo` only; everything else is `_`-prefixed metadata.

const SQUARES: int = 64
const PIECE_LETTERS: String = "PNBRQK"
const MATERIAL: Dictionary = {"P": 1, "N": 3, "B": 3, "R": 5, "Q": 9, "K": 0}
const FILES: String = "abcdefgh"
const START_FEN: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

var allow_castling: bool = true
var allow_en_passant: bool = true
var fifty_move_rule: bool = true

var board: Array[String] = []
var castling: Dictionary = {"K": true, "Q": true, "k": true, "q": true}
var ep_target: int = -1
var halfmove_clock: int = 0
var fullmove_number: int = 1
var position_counts: Dictionary = {}
var last_move: Dictionary = {}
var captured: Array[String] = []


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "chess"


func setup(options: Dictionary) -> void:
	super.setup(options)
	allow_castling = bool(options.get("castling", true))
	allow_en_passant = bool(options.get("en_passant", true))
	fifty_move_rule = bool(options.get("fifty_move_rule", true))
	var fen := VariantUtil.as_string(options.get("fen", START_FEN), START_FEN)
	if not set_fen(fen):
		Log.warn("Chess: unusable starting position, falling back to the standard setup", {"fen": fen})
		set_fen(START_FEN)
	log_event("game.chess.log_start", {"white": player_name(0), "black": player_name(1)})


func phases() -> PackedStringArray:
	return PackedStringArray(["opening", "middlegame", "endgame", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	if _piece_count() <= 12:
		return "endgame"
	return "opening" if turn < 12 else "middlegame"


func decision_player() -> int:
	return turn % 2


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "castling", "label_key": "game.chess.option.castling", "type": "bool", "default": true,
			"hint_key": "game.chess.option.castling_hint"},
		{"key": "en_passant", "label_key": "game.chess.option.en_passant", "type": "bool", "default": true,
			"hint_key": "game.chess.option.en_passant_hint"},
		{"key": "fifty_move_rule", "label_key": "game.chess.option.fifty_move", "type": "bool", "default": true,
			"hint_key": "game.chess.option.fifty_move_hint"},
	]


# ------------------------------------------------------------------- FEN bridge

func set_fen(fen: String) -> bool:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 2:
		return false
	var rows := parts[0].split("/")
	if rows.size() != 8:
		return false
	var new_board: Array[String] = []
	new_board.resize(SQUARES)
	new_board.fill("")
	for row: int in range(8):
		# FEN lists rank 8 first; index 0 of our board is rank 1.
		var rank := 7 - row
		var file := 0
		for character: String in rows[row].split(""):
			if character.is_valid_int():
				file += character.to_int()
				continue
			var lowercase := character.to_lower()
			if not PIECE_LETTERS.to_lower().contains(lowercase) or file > 7:
				return false
			new_board[rank * 8 + file] = character
			file += 1
		if file != 8:
			return false
	board = new_board
	var rights_text := parts[2] if parts.size() > 2 else "-"
	castling = {"K": false, "Q": false, "k": false, "q": false}
	if allow_castling:
		for right: String in ["K", "Q", "k", "q"]:
			castling[right] = rights_text.contains(right)
	ep_target = -1
	if parts.size() > 3 and parts[3] != "-" and parts[3].length() >= 2:
		var ep_file := FILES.find(parts[3].substr(0, 1))
		var ep_rank := int(parts[3].substr(1, 1)) - 1
		if ep_file >= 0 and ep_rank >= 0 and ep_rank < 8:
			ep_target = ep_rank * 8 + ep_file
	halfmove_clock = int(parts[4]) if parts.size() > 4 else 0
	fullmove_number = maxi(1, int(parts[5])) if parts.size() > 5 else 1
	turn = (fullmove_number - 1) * 2 + (1 if (parts.size() > 1 and parts[1] == "b") else 0)
	last_move = {}
	captured.clear()
	position_counts.clear()
	position_counts[position_key()] = 1
	finished = false
	result = {}
	round_index = fullmove_number
	return true


func to_fen() -> String:
	var rows := PackedStringArray()
	for rank: int in range(7, -1, -1):
		var row := ""
		var empty := 0
		for file: int in range(8):
			var piece := board[rank * 8 + file]
			if piece.is_empty():
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			row += piece
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var rights := ""
	for right: String in ["K", "Q", "k", "q"]:
		if bool(castling.get(right, false)):
			rights += right
	var ep := "-"
	if ep_target >= 0:
		ep = "%s%d" % [FILES[ep_target % 8], (ep_target / 8) + 1]
	return "%s %s %s %s %d %d" % [
		"/".join(rows),
		"w" if decision_player() == 0 else "b",
		rights if not rights.is_empty() else "-",
		ep,
		halfmove_clock,
		fullmove_number,
	]


## Position identity for repetition detection: board, side to move, castling and
## en-passant rights (not the move counters, as the rule requires).
func position_key() -> String:
	var rights := ""
	for right: String in ["K", "Q", "k", "q"]:
		if bool(castling.get(right, false)):
			rights += right
	return "%s|%d|%s|%d" % ["".join(board), decision_player(), rights, ep_target]


# -------------------------------------------------------------- move generation

func legal_actions(player: int) -> Array[Dictionary]:
	## Enumerates every move `player` may play in the current position. The bot's
	## search asks for both sides' moves without mutating the turn counter, so the
	## list is generated for the requested player rather than for
	## [method decision_player]; once the match is over the list is empty.
	var out: Array[Dictionary] = []
	if finished:
		return out
	for move: Dictionary in _legal_moves(player):
		out.append(_action_for(move))
	return out


func _action_for(move: Dictionary) -> Dictionary:
	# A move dictionary comes from the search, but the very same shape travels
	# through actions and snapshots, so every field is read defensively: a
	# wrong type must degrade into the documented default instead of raising
	# "Nonexistent 'String' constructor" and aborting the whole search.
	var action := make_action("move", {
		"from": VariantUtil.as_int(move.get("from", -1), -1),
		"to": VariantUtil.as_int(move.get("to", -1), -1),
		"promo": VariantUtil.as_string(move.get("promo", ""), ""),
	})
	action["label_key"] = ""
	action["_direct"] = false
	action["_piece"] = VariantUtil.as_string(move.get("piece", ""), "")
	action["_capture"] = VariantUtil.as_string(move.get("capture", ""), "")
	action["_flags"] = VariantUtil.as_string(move.get("flags", ""), "")
	return action


func _pseudo_moves(player: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var forward := 1 if player == 0 else -1
	for square: int in range(SQUARES):
		var piece := board[square]
		if piece.is_empty() or _owner_of(piece) != player:
			continue
		match piece.to_upper():
			"P":
				moves.append_array(_pawn_moves(square, piece, forward))
			"N", "K":
				for offset: Vector2i in _step_offsets(piece.to_upper()):
					var target := _shift(square, offset.x, offset.y)
					if target < 0:
						continue
					var occupant := board[target]
					if occupant.is_empty() or _owner_of(occupant) != player:
						moves.append(_move(piece, square, target, occupant))
			_:
				for direction: Vector2i in _slide_directions(piece.to_upper()):
					var target := square
					while true:
						target = _shift(target, direction.x, direction.y)
						if target < 0:
							break
						var occupant := board[target]
						if occupant.is_empty():
							moves.append(_move(piece, square, target, ""))
							continue
						if _owner_of(occupant) != player:
							moves.append(_move(piece, square, target, occupant))
						break
	if allow_castling:
		moves.append_array(_castle_moves(player))
	return moves


func _pawn_moves(square: int, piece: String, forward: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var start_rank := 1 if forward > 0 else 6
	var promotion_rank := 7 if forward > 0 else 0
	var file := square % 8
	var one := _shift(square, 0, forward)
	if one >= 0 and board[one].is_empty():
		moves.append_array(_pawn_pushes(piece, square, one, promotion_rank))
		if (square / 8) == start_rank:
			var two := _shift(square, 0, forward * 2)
			if two >= 0 and board[two].is_empty():
				moves.append(_move(piece, square, two, "", "double"))
	for delta_file: int in [-1, 1]:
		if file + delta_file < 0 or file + delta_file > 7:
			continue
		var diagonal := _shift(square, delta_file, forward)
		if diagonal < 0:
			continue
		var occupant := board[diagonal]
		if occupant.is_empty():
			# En passant: the captured pawn stands beside the destination square.
			var victim := _shift(diagonal, 0, -forward)
			if allow_en_passant and diagonal == ep_target and victim >= 0 \
					and not board[victim].is_empty() and _owner_of(board[victim]) != _owner_of(piece):
				moves.append(_move(piece, square, diagonal, board[victim], "en_passant"))
			continue
		if _owner_of(occupant) != _owner_of(piece):
			moves.append_array(_pawn_pushes(piece, square, diagonal, promotion_rank))
	return moves


func _pawn_pushes(piece: String, from: int, to: int, promotion_rank: int) -> Array[Dictionary]:
	if (to / 8) != promotion_rank:
		return [_move(piece, from, to, board[to])]
	var out: Array[Dictionary] = []
	for promo: String in ["q", "r", "b", "n"]:
		out.append(_move(piece, from, to, board[to], "", promo))
	return out


func _castle_moves(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rank := 0 if player == 0 else 7
	var king_square := rank * 8 + 4
	var piece := board[king_square]
	if piece.is_empty() or piece.to_upper() != "K" or _owner_of(piece) != player:
		return out
	if _is_attacked(king_square, 1 - player):
		return out
	var rook := "R" if player == 0 else "r"
	if bool(castling.get("K" if player == 0 else "k", false)) and board[rank * 8 + 7] == rook:
		if board[rank * 8 + 5].is_empty() and board[rank * 8 + 6].is_empty() \
				and not _is_attacked(rank * 8 + 5, 1 - player) and not _is_attacked(rank * 8 + 6, 1 - player):
			out.append(_move(piece, king_square, rank * 8 + 6, "", "castle_k"))
	if bool(castling.get("Q" if player == 0 else "q", false)) and board[rank * 8] == rook:
		if board[rank * 8 + 1].is_empty() and board[rank * 8 + 2].is_empty() and board[rank * 8 + 3].is_empty() \
				and not _is_attacked(rank * 8 + 3, 1 - player) and not _is_attacked(rank * 8 + 2, 1 - player):
			out.append(_move(piece, king_square, rank * 8 + 2, "", "castle_q"))
	return out


func _legal_moves(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for move: Dictionary in _pseudo_moves(player):
		var undo := make_for_search(move)
		var king := _find_king(player)
		var illegal := king < 0 or _is_attacked(king, 1 - player)
		unmake_for_search(undo)
		if not illegal:
			out.append(move)
	return out


func _move(piece: String, from: int, to: int, capture: String, flags: String = "", promo: String = "") -> Dictionary:
	return {"piece": piece, "from": from, "to": to, "capture": capture, "flags": flags, "promo": promo}


func _step_offsets(kind: String) -> Array:
	if kind == "N":
		return [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
			Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
	return [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _slide_directions(kind: String) -> Array:
	var orthogonals: Array = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var diagonals: Array = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	match kind:
		"B":
			return diagonals
		"R":
			return orthogonals
		_:
			return orthogonals + diagonals


## File/rank safe square arithmetic; returns -1 when the step would leave the board.
func _shift(square: int, delta_file: int, delta_rank: int) -> int:
	if square < 0:
		return -1
	var file := (square % 8) + delta_file
	var rank := (square / 8) + delta_rank
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 8 + file


func _owner_of(piece: String) -> int:
	return 0 if piece == piece.to_upper() else 1


func _find_king(player: int) -> int:
	var target := "K" if player == 0 else "k"
	for square: int in range(SQUARES):
		if board[square] == target:
			return square
	return -1


func _piece_count() -> int:
	var count := 0
	for piece: String in board:
		if not piece.is_empty():
			count += 1
	return count


func _is_attacked(square: int, by_player: int) -> bool:
	if square < 0:
		return false
	var pawn := "P" if by_player == 0 else "p"
	# Pawns capture forwards, so an attacking pawn sits one rank "behind" the target.
	var pawn_step := -1 if by_player == 0 else 1
	for delta_file: int in [-1, 1]:
		var source := _shift(square, delta_file, pawn_step)
		if source >= 0 and board[source] == pawn:
			return true
	var knight := "N" if by_player == 0 else "n"
	for offset: Vector2i in _step_offsets("N"):
		var source := _shift(square, offset.x, offset.y)
		if source >= 0 and board[source] == knight:
			return true
	var king := "K" if by_player == 0 else "k"
	for offset: Vector2i in _step_offsets("K"):
		var source := _shift(square, offset.x, offset.y)
		if source >= 0 and board[source] == king:
			return true
	for direction: Vector2i in _slide_directions("Q"):
		var diagonal := absi(direction.x) == 1
		var target := square
		while true:
			target = _shift(target, direction.x, direction.y)
			if target < 0:
				break
			var piece := board[target]
			if piece.is_empty():
				continue
			if _owner_of(piece) == by_player:
				var kind := piece.to_upper()
				if kind == "Q" or (diagonal and kind == "B") or (not diagonal and kind == "R"):
					return true
			break
	return false


func in_check(player: int) -> bool:
	var king := _find_king(player)
	return king >= 0 and _is_attacked(king, 1 - player)


func king_square(player: int) -> int:
	return _find_king(player)


# ----------------------------------------------------------------- make/unmake

## Applies `move` and returns undo information. Shared by [method apply_action]
## and by the bot's search, so it must not log, emit or check for game end.
func make_for_search(move: Dictionary) -> Dictionary:
	var from := VariantUtil.as_int(move["from"], -1)
	var to := VariantUtil.as_int(move["to"], -1)
	var piece := board[from]
	var flags := VariantUtil.as_string(move.get("flags", ""), "")
	var owner := _owner_of(piece)
	var undo := {
		"from": from,
		"to": to,
		"piece": piece,
		"captured": board[to],
		"captured_square": to,
		"castling": castling.duplicate(),
		"ep_target": ep_target,
		"halfmove_clock": halfmove_clock,
		"flags": flags,
	}
	if flags == "en_passant":
		var captured_square := to + (-8 if owner == 0 else 8)
		undo["captured"] = board[captured_square]
		undo["captured_square"] = captured_square
		board[captured_square] = ""
	board[to] = piece
	board[from] = ""
	var rank := 0 if owner == 0 else 7
	if flags == "castle_k":
		board[rank * 8 + 5] = board[rank * 8 + 7]
		board[rank * 8 + 7] = ""
	elif flags == "castle_q":
		board[rank * 8 + 3] = board[rank * 8]
		board[rank * 8] = ""
	var promo := VariantUtil.as_string(move.get("promo", ""), "")
	if not promo.is_empty():
		board[to] = promo.to_upper() if owner == 0 else promo.to_lower()
	var kind := piece.to_upper()
	if kind == "K":
		if owner == 0:
			castling["K"] = false
			castling["Q"] = false
		else:
			castling["k"] = false
			castling["q"] = false
	elif kind == "R":
		_update_rook_rights(from)
	if not VariantUtil.as_string(undo["captured"], "").is_empty():
		_update_rook_rights(VariantUtil.as_int(undo["captured_square"], -1))
	ep_target = -1
	if flags == "double":
		ep_target = (from + to) / 2
	if kind == "P" or not VariantUtil.as_string(undo["captured"], "").is_empty():
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	return undo


func unmake_for_search(undo: Dictionary) -> void:
	var from := VariantUtil.as_int(undo["from"], -1)
	var to := VariantUtil.as_int(undo["to"], -1)
	var piece := VariantUtil.as_string(undo["piece"], "")
	var flags := VariantUtil.as_string(undo.get("flags", ""), "")
	board[from] = piece
	board[to] = ""
	board[VariantUtil.as_int(undo["captured_square"], -1)] = VariantUtil.as_string(undo["captured"], "")
	var rank := 0 if _owner_of(piece) == 0 else 7
	if flags == "castle_k":
		board[rank * 8 + 7] = board[rank * 8 + 5]
		board[rank * 8 + 5] = ""
	elif flags == "castle_q":
		board[rank * 8] = board[rank * 8 + 3]
		board[rank * 8 + 3] = ""
	castling = VariantUtil.dict_copy(undo["castling"])
	ep_target = VariantUtil.as_int(undo["ep_target"], -1)
	halfmove_clock = VariantUtil.as_int(undo["halfmove_clock"], 0)


func _update_rook_rights(square: int) -> void:
	match square:
		0:
			castling["Q"] = false
		7:
			castling["K"] = false
		56:
			castling["q"] = false
		63:
			castling["k"] = false


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	if VariantUtil.as_string(action.get("type", ""), "") != "move":
		return _fail("game.chess.error.unknown_action")
	var wanted := VariantUtil.as_string(action.get("key", ""), "")
	var move: Dictionary = {}
	for candidate: Dictionary in _legal_moves(player):
		var candidate_action := make_action("move", {
			"from": VariantUtil.as_int(candidate.get("from", -1), -1),
			"to": VariantUtil.as_int(candidate.get("to", -1), -1),
			"promo": VariantUtil.as_string(candidate.get("promo", ""), ""),
		})
		if VariantUtil.as_string(candidate_action.get("key", ""), "") == wanted:
			move = candidate
			break
	if move.is_empty():
		return _fail("game.chess.error.illegal_move")
	_commit(move, player)
	return _ok(action)


func _commit(move: Dictionary, player: int) -> void:
	var from := VariantUtil.as_int(move["from"], -1)
	var to := VariantUtil.as_int(move["to"], -1)
	var piece := VariantUtil.as_string(move["piece"], "")
	var flags := VariantUtil.as_string(move.get("flags", ""), "")
	var captured_piece := VariantUtil.as_string(move.get("capture", ""), "")
	make_for_search(move)
	if flags == "en_passant":
		captured_piece = "p" if player == 0 else "P"
	if not captured_piece.is_empty():
		captured.append(captured_piece)
	last_move = {
		"from": from, "to": to, "piece": piece,
		"promo": VariantUtil.as_string(move.get("promo", ""), ""), "capture": captured_piece, "flags": flags,
	}
	turn += 1
	fullmove_number = (turn / 2) + 1
	round_index = fullmove_number
	var key := position_key()
	position_counts[key] = VariantUtil.as_int(position_counts.get(key, 0), 0) + 1
	log_event("game.chess.log_move", {
		"player": player_name(player),
		"move": notation_for(move),
	}, player)
	_check_end(player, key)


## Human-readable notation for the move log (SAN-like without disambiguation).
func notation_for(move: Dictionary) -> String:
	var from := VariantUtil.as_int(move["from"], -1)
	var to := VariantUtil.as_int(move["to"], -1)
	var piece := VariantUtil.as_string(move.get("piece", ""), "P")
	var flags := VariantUtil.as_string(move.get("flags", ""), "")
	var promo := VariantUtil.as_string(move.get("promo", ""), "")
	var capture := VariantUtil.as_string(move.get("capture", ""), "")
	var text := ""
	if flags == "castle_k":
		text = "O-O"
	elif flags == "castle_q":
		text = "O-O-O"
	else:
		if piece.to_upper() != "P":
			text = piece.to_upper()
		elif not capture.is_empty():
			text = FILES[from % 8]
		if not capture.is_empty():
			text += "x"
		text += "%s%d" % [FILES[to % 8], (to / 8) + 1]
	if not promo.is_empty():
		text += "=" + promo.to_upper()
	elif flags == "en_passant":
		text += " e.p."
	return text


func _check_end(player: int, key_after: String) -> void:
	var opponent := 1 - player
	var opponent_moves := _legal_moves(opponent)
	if opponent_moves.is_empty():
		if in_check(opponent):
			finish(player, "game.chess.reason_checkmate", _material_scores())
		else:
			finish(-1, "game.chess.reason_stalemate", _material_scores())
		return
	if _insufficient_material():
		finish(-1, "game.chess.reason_insufficient_material", _material_scores())
		return
	if fifty_move_rule and halfmove_clock >= 100:
		finish(-1, "game.chess.reason_fifty_move", _material_scores())
		return
	if VariantUtil.as_int(position_counts.get(key_after, 1), 1) >= 3:
		finish(-1, "game.chess.reason_repetition", _material_scores())


func _insufficient_material() -> bool:
	var bishops: Array[int] = []
	var others := 0
	for square: int in range(SQUARES):
		var piece := board[square]
		if piece.is_empty() or piece.to_upper() == "K":
			continue
		if piece.to_upper() == "B":
			bishops.append(square)
			continue
		if piece.to_upper() == "N":
			others += 1
			continue
		return false
	if others > 1:
		return false
	if bishops.is_empty():
		return others <= 1
	if not others == 0:
		return false
	if bishops.size() == 1:
		return true
	# Any number of bishops on the same colour complex cannot force mate.
	var first_colour := _square_colour(bishops[0])
	for square: int in bishops:
		if _square_colour(square) != first_colour:
			return false
	return true


func _square_colour(square: int) -> int:
	return ((square % 8) + (square / 8)) % 2


func _material_scores() -> Array:
	var totals := [0, 0]
	for piece: String in board:
		if piece.is_empty():
			continue
		totals[_owner_of(piece)] += int(MATERIAL.get(piece.to_upper(), 0))
	return [
		{"player": 0, "name": player_name(0), "score": totals[0]},
		{"player": 1, "name": player_name(1), "score": totals[1]},
	]


func material_balance(player: int) -> int:
	var total := 0
	for piece: String in board:
		if not piece.is_empty() and _owner_of(piece) == player:
			total += int(MATERIAL.get(piece.to_upper(), 0))
	return total


func piece_at(square: int) -> String:
	if square < 0 or square >= SQUARES:
		return ""
	return board[square]


# ------------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["board"] = board.duplicate()
	state["castling"] = castling.duplicate()
	state["ep_target"] = ep_target
	state["halfmove_clock"] = halfmove_clock
	state["fullmove"] = fullmove_number
	state["last_move"] = last_move.duplicate()
	state["_captured"] = captured.duplicate()
	# Which positions have been reached (for threefold repetition) is public
	# information - any observer can derive it from the move list - so it
	# belongs in the public snapshot instead of a private slice.
	state["_positions"] = position_counts.duplicate()
	state["fen"] = to_fen()
	state["_check"] = {"white": in_check(0), "black": in_check(1)}
	return state


func _restore_extra(state: Dictionary) -> void:
	copy_string_array(state.get("board", []), board)
	if board.size() != SQUARES:
		var fen := VariantUtil.as_string(state.get("fen", ""), START_FEN)
		if fen.is_empty():
			fen = START_FEN
		if not set_fen(fen):
			set_fen(START_FEN)
		return
	castling = VariantUtil.dict_copy(state.get("castling", {}))
	ep_target = VariantUtil.as_int(state.get("ep_target", -1), -1)
	halfmove_clock = VariantUtil.as_int(state.get("halfmove_clock", 0), 0)
	fullmove_number = maxi(1, VariantUtil.as_int(state.get("fullmove", 1), 1))
	last_move = VariantUtil.dict_copy(state.get("last_move", {}))
	copy_string_array(state.get("_captured", []), captured)
	position_counts.clear()
	if state.get("_positions", {}) is Dictionary:
		# The reached-position history is part of the public snapshot; an
		# untyped JSON-style dictionary needs an element-wise rebuild.
		var history: Dictionary = state.get("_positions", {})
		for key: Variant in history:
			position_counts[VariantUtil.as_string(key, "")] = VariantUtil.as_int(history.get(key, 0), 0)
	if position_counts.is_empty():
		# Without any history (corrupt or legacy snapshot) the current position
		# counts as reached once - threefold detection stays honest from here.
		position_counts[position_key()] = 1
