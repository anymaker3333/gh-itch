extends RefCounted
## Chess AI: iterative-deepening negamax with alpha-beta pruning.
##
## The bot only ever reads public information (the position), is fully
## deterministic for a given position and never proposes an action the engine does
## not list as legal - [BotDirector] verifies that last point anyway.

const MAX_DEPTH: int = 3
const TIME_BUDGET_MS: int = 900

const PIECE_VALUE: Dictionary = {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 20000}
## Small positional bonus so that early moves develop instead of shuffling.
const CENTRE_BONUS: Array = [0, 1, 2, 3, 3, 2, 1, 0]
const OPENING_HINT: Dictionary = {
	"d2d4": 12, "e2e4": 12, "g1f3": 10, "b1c3": 10, "c2c4": 10, "e2e3": 4,
	"g8f6": 12, "b8c6": 10, "e7e5": 12, "d7d5": 12, "c7c5": 10,
}

var engine: GameEngine = null
var deadline_ms: int = 0
var nodes: int = 0


func choose_action(active_engine: GameEngine, player: int) -> String:
	engine = active_engine
	var moves: Array = engine.legal_actions(player)
	if moves.is_empty():
		return ""
	if moves.size() == 1:
		return String(moves[0].get("key", ""))
	deadline_ms = Time.get_ticks_msec() + TIME_BUDGET_MS
	nodes = 0
	var best: Dictionary = {}
	var best_score := -999999
	var depth := 1
	while depth <= MAX_DEPTH:
		var scored := _search_root(moves, player, depth)
		if not scored.is_empty():
			best = scored
			best_score = int(scored.score)
		if best_score > 50000 or Time.get_ticks_msec() > deadline_ms:
			break
		depth += 1
	if best.is_empty():
		return String(moves[0].get("key", ""))
	return String(best.action.get("key", ""))


## Returns `{ "action": Dictionary, "score": int }` for the best legal move.
func _search_root(moves: Array, player: int, depth: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -999999
	var alpha := -999999
	for action: Dictionary in moves:
		var move := _as_move(action)
		var undo: Dictionary = engine.make_for_search(move)
		var score := -_negamax(depth - 1, -999999, -alpha, 1 - player)
		engine.unmake_for_search(undo)
		score += _opening_bonus(move)
		if score > best_score:
			best_score = score
			best = {"action": action, "score": score}
		alpha = maxi(alpha, best_score)
		if Time.get_ticks_msec() > deadline_ms:
			break
	return best


func _negamax(depth: int, alpha: int, beta: int, player: int) -> int:
	nodes += 1
	if depth <= 0 or Time.get_ticks_msec() > deadline_ms:
		return _evaluate(player)
	var moves: Array = engine.legal_actions(player)
	if moves.is_empty():
		if engine.in_check(player):
			return -100000 - depth
		return 0
	var best := -999999
	for action: Dictionary in moves:
		var move := _as_move(action)
		var undo: Dictionary = engine.make_for_search(move)
		var score := -_negamax(depth - 1, -beta, -alpha, 1 - player)
		engine.unmake_for_search(undo)
		best = maxi(best, score)
		alpha = maxi(alpha, best)
		if alpha >= beta:
			break
	return best


## Static evaluation from `player`'s point of view (material, centre control,
## mobility proxy). Deterministic: no randomness anywhere.
func _evaluate(player: int) -> int:
	var score := 0
	for square: int in range(64):
		var piece: String = engine.piece_at(square)
		if piece.is_empty():
			continue
		var value := int(PIECE_VALUE.get(piece.to_upper(), 0))
		var file := square % 8
		var rank := square / 8
		var centred := int(CENTRE_BONUS[file]) + int(CENTRE_BONUS[rank])
		if piece.to_upper() == "N" or piece.to_upper() == "B":
			value += centred
		elif piece.to_upper() == "P":
			value += centred / 2
		if piece == piece.to_upper():
			score += value
		else:
			score -= value
	return score if player == 0 else -score


## Nudges the first moves towards the centre so that bots do not shuffle pieces.
func _opening_bonus(move: Dictionary) -> int:
	if engine.turn > 10:
		return 0
	var notation := "%s%d%s%d" % [
		"abcdefgh"[int(move["from"]) % 8], (int(move["from"]) / 8) + 1,
		"abcdefgh"[int(move["to"]) % 8], (int(move["to"]) / 8) + 1,
	]
	return int(OPENING_HINT.get(notation, 0))


func _as_move(action: Dictionary) -> Dictionary:
	return {
		"from": int(action.get("from", 0)),
		"to": int(action.get("to", 0)),
		"promo": String(action.get("promo", "")),
		"piece": String(action.get("_piece", "")),
		"capture": String(action.get("_capture", "")),
		"flags": String(action.get("_flags", "")),
	}
