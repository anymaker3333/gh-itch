extends RefCounted
## Codenames bot: spymasters pick the cue that covers their own agents with the
## least collateral, operatives rank the unrevealed cards by association with the
## announced clue. The policy is deterministic and only uses information the
## acting seat is allowed to know (public state plus its own private role).

const OWN_WEIGHT: int = 100
const RISK_WEIGHT: int = 130


func choose_action(engine: GameEngine, player: int) -> String:
	var actions: Array[Dictionary] = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	if not engine.has_method("unrevealed_cells"):
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var phase := VariantUtil.as_string(engine.public_state().get("phase", engine.phase()), engine.phase())
	if phase == "clue":
		return _choose_clue(engine, player, actions)
	if phase == "guess":
		return _choose_guess(engine, player, actions)
	return VariantUtil.as_string(actions[0].get("key", ""), "")


func _choose_clue(engine: GameEngine, _player: int, actions: Array[Dictionary]) -> String:
	var cards: Array = VariantUtil.as_array(engine.key_card)
	if cards.size() != CodenamesEngine.CELLS:
		# Client-side engine without the key card: play the first legal clue.
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var team := VariantUtil.as_int(engine.public_state().get("active_team", 0), 0)
	var own_label: String = CodenamesEngine.CARD_RED if team == CodenamesEngine.RED else CodenamesEngine.CARD_BLUE
	var vocab: Array = VariantUtil.as_array(engine.public_state().get("cue_vocab", []))
	var best_cue := ""
	var best_number := 1
	var best_score := -999999
	var unrevealed: Array = VariantUtil.as_array(engine.unrevealed_cells())
	for cue: Variant in vocab:
		var own := 0
		var bad := 0
		for cell: Variant in unrevealed:
			if not VariantUtil.as_array(engine.cues_for(VariantUtil.as_string(engine.grid[VariantUtil.as_int(cell, -1)], ""))).has(VariantUtil.as_string(cue, "")):
				continue
			if VariantUtil.as_string(engine.card_owner_label(VariantUtil.as_int(cell, -1)), "") == own_label:
				own += 1
			else:
				bad += 1
		if own == 0:
			continue
		var score := own * OWN_WEIGHT - bad * RISK_WEIGHT
		if score > best_score:
			best_score = score
			best_cue = VariantUtil.as_string(cue, "")
			best_number = clampi(own, 1, CodenamesEngine.MAX_CLUE_NUMBER)
	if best_cue.is_empty():
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("word", ""), "") == best_cue and VariantUtil.as_int(action.get("number", 0), 0) == best_number:
			return VariantUtil.as_string(action.get("key", ""), "")
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("word", ""), "") == best_cue:
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(actions[0].get("key", ""), "")


func _choose_guess(engine: GameEngine, player: int, actions: Array[Dictionary]) -> String:
	var clue := VariantUtil.as_string(VariantUtil.as_dict(engine.public_state().get("clue", {})).get("word", ""), "")
	var private := engine.private_state(player)
	var knows_key := VariantUtil.as_string(private.get("role", ""), "") == "spymaster"
	var team := VariantUtil.as_int(private.get("team", 0), 0)
	var own_label: String = CodenamesEngine.CARD_RED if team == CodenamesEngine.RED else CodenamesEngine.CARD_BLUE
	var best := -1
	var best_score := -1
	for cell: Variant in VariantUtil.as_array(engine.unrevealed_cells()):
		if knows_key and VariantUtil.as_string(engine.card_owner_label(VariantUtil.as_int(cell, -1)), "") != own_label:
			continue
		var score := 0
		for cue: Variant in engine.cues_for(VariantUtil.as_string(engine.grid[VariantUtil.as_int(cell, -1)], "")):
			if VariantUtil.as_string(cue, "") == clue:
				score += 2
		if score > best_score:
			best_score = score
			best = VariantUtil.as_int(cell, -1)
	if best >= 0 and (best_score > 0 or knows_key):
		for action: Dictionary in actions:
			if VariantUtil.as_string(action.get("type", ""), "") == "guess" and VariantUtil.as_int(action.get("card", -1), -1) == best:
				return VariantUtil.as_string(action.get("key", ""), "")
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "stop":
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(actions[0].get("key", ""), "")
