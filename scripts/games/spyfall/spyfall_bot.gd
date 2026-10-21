extends RefCounted
## Spyfall bot. Agents answer on topic, keep a suspicion score from other
## players' off-topic answers and accuse once somebody looks impossible. The spy
## (which only the acting seat's private state identifies) answers with the reply
## that fits the most of its candidate locations and names a place when the table
## has clearly given the location away. Deterministic: no randomness at all.

const SUSPICION_TO_ACCUSE: int = 2
const SPY_CONFIDENCE: int = 3


func choose_action(engine: GameEngine, player: int) -> String:
	var actions: Array[Dictionary] = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	if not engine.has_method("is_on_topic"):
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var private := engine.private_state(player)
	var phase := String(engine.phase())
	if phase == "answer":
		return _choose_answer(engine, player, private, actions)
	if phase == "ask":
		return _choose_turn(engine, player, private, actions)
	return VariantUtil.as_string(actions[0].get("key", ""), "")


# -------------------------------------------------------------------- agents

func _choose_answer(engine: GameEngine, player: int, private: Dictionary, actions: Array[Dictionary]) -> String:
	var is_spy := bool(private.get("is_spy", false))
	var options: Array = []
	if is_spy:
		options = _top_candidate_answers(engine, private)
	else:
		options = engine.topics_of(VariantUtil.as_string(private.get("location", ""), ""))
	if options.is_empty():
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var history: Array = engine.public_state().get("history", [])
	var answer := VariantUtil.as_int(options[history.size() % options.size()], 0)
	for action: Dictionary in actions:
		if VariantUtil.as_int(action.get("answer", -1), -1) == answer:
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(actions[0].get("key", ""), "")


## Answers that look right for most of the spy's candidate locations.
func _top_candidate_answers(engine: GameEngine, private: Dictionary) -> Array:
	var candidates: Array = private.get("candidates", [])
	var best_answer := -1
	var best_score := -1
	for answer: int in range(SpyfallEngine.ANSWERS.size()):
		var score := 0
		for candidate: Variant in candidates:
			if engine.is_on_topic(VariantUtil.as_string(candidate, ""), answer):
				score += 1
		if score > best_score:
			best_score = score
			best_answer = answer
	return [best_answer] if best_answer >= 0 else []


func _choose_turn(engine: GameEngine, player: int, private: Dictionary, actions: Array[Dictionary]) -> String:
	if bool(private.get("is_spy", false)):
		var named := _spy_named_location(engine, player, private)
		if not named.is_empty():
			return named
		return _ask_key(engine, player, actions, _least_asked(engine, player))
	var suspicion := _suspicion_scores(engine, player)
	var suspect := _top_suspect(suspicion, engine, player)
	if suspect >= 0 and VariantUtil.as_int(suspicion.get(suspect, 0), 0) >= SUSPICION_TO_ACCUSE:
		for action: Dictionary in actions:
			if VariantUtil.as_string(action.get("type", ""), "") == "accuse" and VariantUtil.as_int(action.get("target", -1), -1) == suspect:
				return VariantUtil.as_string(action.get("key", ""), "")
	return _ask_key(engine, player, actions, suspect if suspect >= 0 else _least_asked(engine, player))


## Naming a location is the spy's gamble: only when the answers single out one
## candidate clearly.
func _spy_named_location(engine: GameEngine, player: int, private: Dictionary) -> String:
	var history: Array = engine.public_state().get("history", [])
	if history.size() < 2:
		return ""
	var candidates: Array = private.get("candidates", [])
	var best := ""
	var best_score := 0
	var second := 0
	for candidate: Variant in candidates:
		var score := 0
		for entry: Variant in history:
			var record: Dictionary = entry
			if VariantUtil.as_int(record.get("target", -1), -1) == player:
				continue
			if engine.is_on_topic(VariantUtil.as_string(candidate, ""), VariantUtil.as_int(record.get("answer", -1), -1)):
				score += 1
		if score > best_score:
			second = best_score
			best_score = score
			best = VariantUtil.as_string(candidate, "")
		elif score > second:
			second = score
	if best.is_empty() or best_score < SPY_CONFIDENCE or best_score <= second:
		return ""
	for action: Dictionary in engine.legal_actions(player):
		if VariantUtil.as_string(action.get("type", ""), "") == "name_location" and VariantUtil.as_string(action.get("location", ""), "") == best:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""


# ------------------------------------------------------------- suspicion map

## Off-topic answers cost the answerer a suspicion point in the eyes of every
## agent that knows the location. Cleared players are ignored.
func _suspicion_scores(engine: GameEngine, player: int) -> Dictionary:
	var my_location := VariantUtil.as_string(engine.private_state(player).get("location", ""), "")
	var history: Array = engine.public_state().get("history", [])
	var cleared: Array = engine.public_state().get("cleared", [])
	var scores: Dictionary = {}
	for entry: Variant in history:
		var record: Dictionary = entry
		var answerer := VariantUtil.as_int(record.get("target", -1), -1)
		if answerer == player or cleared.has(answerer):
			continue
		if not engine.is_on_topic(my_location, VariantUtil.as_int(record.get("answer", -1), -1)):
			scores[answerer] = VariantUtil.as_int(scores.get(answerer, 0), 0) + 1
	return scores


## Highest suspicion, ties broken by the lowest seat. -1 when nobody is suspect.
func _top_suspect(scores: Dictionary, engine: GameEngine, player: int) -> int:
	var best := -1
	var best_score := 0
	var cleared: Array = engine.public_state().get("cleared", [])
	for player_index: int in range(engine.player_count()):
		if player_index == player or cleared.has(player_index):
			continue
		var score := VariantUtil.as_int(scores.get(player_index, 0), 0)
		if score > best_score:
			best_score = score
			best = player_index
	return best


## Asks the least recently questioned player (deterministic round robin).
func _least_asked(engine: GameEngine, player: int) -> int:
	var counts: Dictionary = {}
	for entry: Variant in VariantUtil.as_array(engine.public_state().get("history", [])):
		var target := VariantUtil.as_int(VariantUtil.as_dict(entry).get("target", -1), -1)
		counts[target] = VariantUtil.as_int(counts.get(target, 0), 0) + 1
	var best := -1
	var best_count := 9999
	for player_index: int in range(engine.player_count()):
		if player_index == player:
			continue
		var count := VariantUtil.as_int(counts.get(player_index, 0), 0)
		if count < best_count:
			best_count = count
			best = player_index
	return best


func _ask_key(engine: GameEngine, _player: int, actions: Array[Dictionary], target: int) -> String:
	var question: int = VariantUtil.as_array(engine.public_state().get("history", [])).size() % SpyfallEngine.QUESTIONS.size()
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "ask" and VariantUtil.as_int(action.get("target", -1), -1) == target \
				and VariantUtil.as_int(action.get("question", -1), -1) == question:
			return VariantUtil.as_string(action.get("key", ""), "")
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "ask" and VariantUtil.as_int(action.get("target", -1), -1) == target:
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(actions[0].get("key", ""), "")
