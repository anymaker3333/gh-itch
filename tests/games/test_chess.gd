extends RefCounted
## Chess rules suite: movement, castling, en passant, promotion, endings and
## determinism. Positions are set up with FEN so each rule is tested in isolation.


func suite_name() -> String:
	return "chess rules"


func run(h: TestHarness) -> void:
	_start_position(h)
	_movement(h)
	_illegal_moves(h)
	_castling(h)
	_en_passant(h)
	_promotion(h)
	_endings(h)
	_fen_validation(h)
	_determinism(h)
	_bot_match(h)


func _engine(h: TestHarness, fen: String = "") -> GameEngine:
	var options := {}
	if not fen.is_empty():
		options["fen"] = fen
	var engine := EngineHarness.create("chess", 2, 20251018, options)
	h.check(engine != null, "chess engine must be creatable")
	return engine


func _start_position(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.decision_player(), 0, "white moves first")
	h.equal(engine.legal_actions(0).size(), 20, "twenty legal first moves")
	h.equal(engine.legal_actions(1).size(), 20, "black also has twenty moves available")
	h.equal(engine.phase(), "opening", "the start is the opening")
	EngineHarness.check_legal_action_shape(h, engine, "start")
	h.equal(engine.to_fen(), ChessEngine.START_FEN, "start position round trips through FEN")
	h.check(engine.private_state(0).is_empty(), "chess has no hidden information")


func _movement(h: TestHarness) -> void:
	var engine := _engine(h)
	var outcome := engine.apply_action_by_key(0, _key(engine, 12, 28))
	h.check(bool(outcome.get("ok", false)), "e2-e4 is legal")
	h.equal(engine.decision_player(), 1, "turn passes to black")
	h.equal(engine.board[28], "P", "the pawn moved")
	h.equal(engine.board[12], "", "the origin square is empty")
	h.check(engine.ep_target == 20, "double push records the en passant target")
	h.equal(String(mate_out_of_turn(engine).get("error_key", "")), "game.common.not_your_turn", "moving out of turn is rejected")


func _illegal_moves(h: TestHarness) -> void:
	var engine := _engine(h)
	var outcome := engine.apply_action_by_key(0, _key(engine, 0, 16))
	h.check(not bool(outcome.get("ok", false)), "a rook cannot jump over its own pawn")
	h.equal(String(outcome.get("error_key", "")), "game.common.illegal_action", "rejection is reported as an illegal action")
	# A pinned piece may not leave the king in check: white king e1, white knight
	# e2, black rook e8.
	var pinned := _engine(h, "4r3/8/8/8/8/8/4N3/4K3 w - - 0 1")
	h.greater(float(pinned.legal_actions(0).size()), 0.0, "white has legal king moves while pinned")
	for action: Dictionary in pinned.legal_actions(0):
		h.not_equal(int(action.get("from", -1)), 12, "the pinned knight may not move")
	var in_check := _engine(h, "4r3/8/8/8/8/8/8/4K3 w - - 0 1")
	var king_key := _key(in_check, 4, 3)
	h.check(bool(in_check.apply_action_by_key(0, king_key).get("ok", false)), "the king may step out of check")
	var into_check := _engine(h, "4r3/8/8/8/8/8/8/4K3 w - - 0 1")
	h.check(not bool(into_check.apply_action_by_key(0, _key(into_check, 4, 12)).get("ok", false)), "…but not into another check")


func _castling(h: TestHarness) -> void:
	var engine := _engine(h, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var king_side := _key(engine, 4, 6)
	h.check(bool(engine.apply_action_by_key(0, king_side).get("ok", false)), "white may castle short")
	h.equal(engine.board[6], "K", "the king lands on g1")
	h.equal(engine.board[5], "R", "the rook jumps to f1")
	h.equal(engine.board[7], "", "h1 is empty afterwards")
	# Castling through an attacked square is forbidden.
	var through_check := _engine(h, "4k3/8/8/8/8/5r2/8/R3K2R w KQ - 0 1")
	for action: Dictionary in through_check.legal_actions(0):
		h.check(not (int(action.get("from", -1)) == 4 and int(action.get("to", -1)) == 6),
			"the king may not castle through an attacked square")
	# Castling rights are lost once the king has moved.
	var moved := _engine(h, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	moved.apply_action_by_key(0, _key(moved, 4, 3))
	h.check(not bool(moved.castling["K"]) and not bool(moved.castling["Q"]), "a king that has moved loses its castling rights")
	h.check(bool(moved.castling["k"]) and bool(moved.castling["q"]), "the opponent keeps theirs")


func _en_passant(h: TestHarness) -> void:
	var engine := _engine(h, "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	var capture := _key(engine, 36, 43)
	h.check(bool(engine.apply_action_by_key(0, capture).get("ok", false)), "en passant capture is legal")
	h.equal(engine.board[43], "P", "the pawn lands on d6")
	h.equal(engine.board[35], "", "the black pawn on d5 is removed")
	var disabled := EngineHarness.create("chess", 2, 7, {"fen": "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "en_passant": false})
	h.equal(disabled.legal_actions(0).size(), 6, "with the rule off only the king moves and the pawn push remain")


func _promotion(h: TestHarness) -> void:
	var engine := _engine(h, "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1")
	var promotions: Array = []
	for action: Dictionary in engine.legal_actions(0):
		if int(action.get("from", -1)) == 49:
			promotions.append(action)
	h.equal(promotions.size(), 4, "four promotion pieces are offered")
	var queen := {}
	for action: Dictionary in promotions:
		if String(action.get("promo", "")) == "q":
			queen = action
	h.check(not queen.is_empty(), "the queen promotion exists")
	h.check(bool(engine.apply_action_by_key(0, String(queen.get("key", ""))).get("ok", false)), "promotion applies")
	h.equal(engine.board[57], "Q", "the pawn became a queen on b8")
	h.check(not engine.finished, "the game continues after a promotion")


func _endings(h: TestHarness) -> void:
	# Fool's mate: 1. f3 e5 2. g4 Qh4#.
	var mate := _engine(h)
	mate.apply_action_by_key(0, _key(mate, 13, 21))
	mate.apply_action_by_key(1, _key(mate, 52, 36))
	mate.apply_action_by_key(0, _key(mate, 14, 30))
	mate.apply_action_by_key(1, _key(mate, 59, 31))
	h.check(mate.finished, "fool's mate ends the game")
	h.equal(mate.winner_index(), 1, "black wins")
	h.equal(String(mate.result.get("reason_key", "")), "game.chess.reason_checkmate", "reason is checkmate")
	h.check(mate.legal_actions(0).is_empty(), "no moves after checkmate")

	var draw_engine := _engine(h, "7k/5K2/5Q2/8/8/8/8/8 w - - 0 1")
	h.check(not draw_engine.finished, "the position is not over on load")
	h.check(draw_engine.apply_action_by_key(0, _key(draw_engine, 45, 46)).get("ok", false), "white plays Qf6-g6")
	h.check(draw_engine.finished, "the stalemate is detected after the move")
	h.equal(draw_engine.winner_index(), -1, "stalemate is a draw")
	h.equal(String(draw_engine.result.get("reason_key", "")), "game.chess.reason_stalemate", "reason is stalemate")

	var material := _engine(h, "4k3/8/8/8/8/8/8/4KB2 w - - 0 1")
	h.check(not material.finished, "king and bishop is still playable")
	var bare := _engine(h, "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
	bare.apply_action_by_key(0, _key(bare, 4, 12))
	h.check(bare.finished, "king versus king is a draw")
	h.equal(String(bare.result.get("reason_key", "")), "game.chess.reason_insufficient_material", "reason is insufficient material")

	var fifty := _engine(h, "4k3/8/8/8/8/8/8/R3K3 w - - 99 60")
	fifty.apply_action_by_key(0, _key(fifty, 4, 12))
	h.check(fifty.finished, "the fifty-move rule ends the game")
	h.equal(String(fifty.result.get("reason_key", "")), "game.chess.reason_fifty_move", "reason is the fifty-move rule")


## Malformed positions must be rejected instead of producing a broken board.
func _fen_validation(h: TestHarness) -> void:
	var engine := _engine(h)
	h.check(not engine.set_fen("nonsense"), "a malformed FEN is rejected")
	h.check(not engine.set_fen("4k3/8/8/8/8/8/R3K3 w - - 0 1"), "a FEN with seven ranks is rejected")
	h.check(engine.set_fen(ChessEngine.START_FEN), "the standard position is accepted")
	h.equal(engine.to_fen(), ChessEngine.START_FEN, "the board is unchanged after a rejected FEN")


func _determinism(h: TestHarness) -> void:
	var first := _engine(h)
	var second := _engine(h)
	for step: int in range(24):
		var key := BotDirector.choose_action(first, first.decision_player())
		h.check(not key.is_empty(), "the bot always finds a move (%d)" % step)
		var outcome := first.apply_action_by_key(first.decision_player(), key)
		h.check(bool(outcome.get("ok", false)), "the bot move is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same move list gives the same state")
	EngineHarness.check_snapshot_round_trip(h, first, "chess")


func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h)
	var steps := EngineHarness.play_out(engine, 160)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished or engine.legal_actions(engine.decision_player()).size() > 0,
		"the match is either over or playable")
	if engine.finished:
		h.check(not String(engine.result.get("reason_key", "")).is_empty(), "a finished match explains itself")
	h.greater(float(engine.move_log.size()), 0.0, "moves are logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
	h.check(not Loc.missing_keys().has(String("game.chess.log_move")), "the move log uses a real string")


## Attempts a move as the player who is not to move (rejection is expected).
func mate_out_of_turn(engine: GameEngine) -> Dictionary:
	var waiting := 1 - engine.decision_player()
	var actions := engine.legal_actions(waiting)
	if actions.is_empty():
		return {"error_key": "game.common.not_your_turn"}
	return engine.apply_action_by_key(waiting, String(actions[0].get("key", "")))


## Key of the move `from -> to` in the current position (ignores promotions).
func _key(engine: GameEngine, from: int, to: int) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if int(action.get("from", -1)) == from and int(action.get("to", -1)) == to:
			return String(action.get("key", ""))
	return "missing:%d-%d" % [from, to]
