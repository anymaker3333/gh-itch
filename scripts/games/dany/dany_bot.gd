extends RefCounted
## DANY bot: lays the smallest honest set of cards that satisfies the oracle and
## bluffs only when honesty is impossible. As a responder it inspects claims that
## cannot be true, claims that look bold for the number of cards laid, and
## claimants who are one reputation away from leaving the table. Every choice is
## a pure function of the visible state - no randomness at all.

## A claim above six times the number of laid cards looks like a bluff.
const BOLD_FACTOR: int = 6
## A claimant this close to elimination is worth doubting.
const DESPERATE_REPUTATION: int = 1


func choose_action(engine: GameEngine, player: int) -> String:
	var actions: Array[Dictionary] = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	match String(engine.phase()):
		"inspect":
			return _choose_response(engine, player, actions)
		"select":
			return _choose_turn(engine, player, actions)
	return VariantUtil.as_string(actions[0].get("key", ""), "")


# ----------------------------------------------------------------- responders

func _choose_response(engine: GameEngine, player: int, actions: Array[Dictionary]) -> String:
	var wanted := "inspect" if _wants_inspect(engine, player) else "pass"
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == wanted:
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(actions[0].get("key", ""), "")


func _wants_inspect(engine: GameEngine, player: int) -> bool:
	var state := engine.public_state()
	var slots: Array = VariantUtil.as_array(state.get("pending_slots", []))
	if slots.size() <= 0:
		return false
	var claimed := VariantUtil.as_int(state.get("claimed_value", 0), 0)
	# Each laid card is worth 1..9, so some claims are simply impossible.
	if claimed < slots.size() or claimed > slots.size() * 9:
		return true
	var reputations: Array = VariantUtil.as_array(state.get("reputations", []))
	var mine := VariantUtil.as_int(reputations[player], 0) if player >= 0 and player < reputations.size() else 0
	var claimant := VariantUtil.as_int(state.get("turn_pos", -1), -1)
	var theirs := VariantUtil.as_int(reputations[claimant], 0) if claimant >= 0 and claimant < reputations.size() else 0
	if claimed > BOLD_FACTOR * slots.size():
		# Bold is suspicious, but doubting an honest claim costs a reputation.
		return mine >= 2
	return theirs <= DESPERATE_REPUTATION


# ---------------------------------------------------------------------- turn

func _choose_turn(engine: GameEngine, player: int, actions: Array[Dictionary]) -> String:
	var hand: Array = VariantUtil.as_array(engine.private_state(player).get("hand", []))
	if hand.is_empty():
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var oracle := VariantUtil.as_int(engine.public_state().get("oracle", 1), 1)
	var plan := _plan(hand, oracle)
	var wanted: Array = VariantUtil.as_array(plan.get("slots", []))
	var pending: Array = VariantUtil.as_array(engine.public_state().get("pending_slots", []))
	# First take back anything the plan does not want...
	for slot: Variant in pending:
		if not wanted.has(VariantUtil.as_int(slot, -1)):
			var take_back := _select_key(actions, VariantUtil.as_int(slot, -1))
			if not take_back.is_empty():
				return take_back
	# ...then add the planned cards, never more than three.
	if pending.size() < 3:
		for slot: Variant in wanted:
			if not pending.has(VariantUtil.as_int(slot, -1)):
				var lay := _select_key(actions, VariantUtil.as_int(slot, -1))
				if not lay.is_empty():
					return lay
	if pending.size() == wanted.size():
		var claim := _claim_key(actions, VariantUtil.as_int(plan.get("value", 0), 0))
		if not claim.is_empty():
			return claim
	return VariantUtil.as_string(actions[0].get("key", ""), "")


## The smallest honest claim at or above the oracle and the fewest cards that
## reach it (single cards first, then pairs, then triples). When no honest claim
## exists the bot names the oracle and sheds its three cheapest cards.
func _plan(hand: Array, oracle: int) -> Dictionary:
	var size := hand.size()
	var subsets: Array = []
	for first: int in range(size):
		subsets.append([first])
	for first: int in range(size):
		for second: int in range(first + 1, size):
			subsets.append([first, second])
	for first: int in range(size):
		for second: int in range(first + 1, size):
			for third: int in range(second + 1, size):
				subsets.append([first, second, third])
	var best_sum := -1
	var best_slots: Array = []
	for subset: Variant in subsets:
		var slots: Array = subset
		var total := 0
		for slot: Variant in slots:
			total += VariantUtil.as_int(VariantUtil.as_dict(hand[VariantUtil.as_int(slot, -1)]).get("value", 0), 0)
		if total < oracle:
			continue
		if best_sum < 0 or total < best_sum or (total == best_sum and slots.size() < best_slots.size()):
			best_sum = total
			best_slots = slots
	if best_sum >= 0:
		return {"value": best_sum, "slots": best_slots}
	return {"value": oracle, "slots": _cheapest_slots(hand, 3)}


## Indices of the `count` lowest-valued cards, by value then hand order.
func _cheapest_slots(hand: Array, count: int) -> Array:
	var picked: Array = []
	var taken: Array = []
	for _round: int in range(count):
		var best := -1
		for index: int in range(hand.size()):
			if taken.has(index):
				continue
			if best < 0:
				best = index
				continue
			var best_value := VariantUtil.as_int(VariantUtil.as_dict(hand[best]).get("value", 0), 0)
			var index_value := VariantUtil.as_int(VariantUtil.as_dict(hand[index]).get("value", 0), 0)
			if index_value < best_value:
				best = index
		if best < 0:
			break
		picked.append(best)
		taken.append(best)
	picked.sort()
	return picked


func _select_key(actions: Array[Dictionary], slot: int) -> String:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "select" and VariantUtil.as_int(action.get("slot", -1), -1) == slot:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""


func _claim_key(actions: Array[Dictionary], value: int) -> String:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "claim" and VariantUtil.as_int(action.get("value", -1), -1) == value:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""
