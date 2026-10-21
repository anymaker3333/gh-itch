extends RefCounted
## Coup AI: a deterministic greedy policy with certainty-based challenges.
##
## The bot only uses public information plus its own hidden hand. It taxes while
## it holds a Duke, robs the richest opponent while it holds a Captain, pays for
## a coup once it can afford one (or is forced to by the ten-coin rule) and uses
## Exchange otherwise. It never bluffs: a claim or a block is only made for a
## card it really holds, and it challenges only when all three copies of the
## claimed character are already accounted for between its own hand and the
## revealed influences.

## Cards the bot reveals or returns first when it has to give one up.
const GIVE_AWAY_ORDER: Array[String] = ["ambassador", "assassin", "contessa", "captain", "duke"]


func choose_action(engine: GameEngine, player: int) -> String:
	var actions: Array = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var state: Dictionary = engine.public_state()
	var secret: Dictionary = engine.private_state(player)
	match VariantUtil.as_string(state.get("step", ""), ""):
		"action":
			return _action(actions, state, secret, player)
		"challenge":
			return _challenge(actions, state, secret)
		"block":
			return _block(actions, state, secret)
		"lose":
			return _give_away(actions, "lose_card")
		"exchange":
			return _give_away(actions, "return_card")
	return _first(actions)


func _action(actions: Array, state: Dictionary, secret: Dictionary, player: int) -> String:
	var mine: Array = secret.get("hand", [])
	var coins := _coins(state, player)
	var targets := _targets(state, player)
	if coins >= 10 or (coins >= 7 and _weakest_influence(state, targets) <= 1):
		return _coup(actions, state, targets)
	if mine.has("duke"):
		return _or(_first_of(actions, "tax"), actions)
	if coins >= 3 and mine.has("assassin") and not targets.is_empty():
		return _or(_key_of(actions, "assassinate", {"target": _leader(state, targets)}), actions)
	if mine.has("captain"):
		var richest := _richest(state, targets)
		if richest >= 0 and _coins(state, richest) >= 1:
			return _or(_key_of(actions, "steal", {"target": richest}), actions)
	if coins >= 7:
		return _coup(actions, state, targets)
	if mine.has("ambassador"):
		return _or(_first_of(actions, "exchange"), actions)
	return _or(_first_of(actions, "foreign_aid"), actions)


## The rules force a coup at ten coins, so the action list is all coups then.
func _coup(actions: Array, state: Dictionary, targets: Array) -> String:
	if targets.is_empty():
		return _first(actions)
	return _or(_key_of(actions, "coup", {"target": _leader(state, targets)}), actions)


func _challenge(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	var claim: Dictionary = VariantUtil.as_dict(state.get("claim", {}))
	var role := VariantUtil.as_string(claim.get("role", ""), "")
	var known := _count_role(secret, role)
	for shown: Variant in VariantUtil.as_array(state.get("revealed", [])):
		if shown is Array:
			for card: Variant in shown:
				if VariantUtil.as_string(card, "") == role:
					known += 1
	# All three copies are visible: the claim cannot be true.
	if known >= 3:
		return _or(_first_of(actions, "challenge"), actions)
	return _or(_first_of(actions, "pass"), actions)


func _block(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	var type := VariantUtil.as_string(VariantUtil.as_dict(state.get("pending", {})).get("type", ""), "")
	var mine: Array = VariantUtil.as_array(secret.get("hand", []))
	for role: String in CoupEngine._block_roles(type):
		if mine.has(role):
			return _or(_key_of(actions, "block", {"role": role}), actions)
	return _or(_first_of(actions, "pass"), actions)


## Losing/returning: give up the least useful character first.
func _give_away(actions: Array, type: String) -> String:
	var best := ""
	var best_rank := 999
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") != type:
			continue
		var rank := GIVE_AWAY_ORDER.find(VariantUtil.as_string(action.get("_role", ""), ""))
		if rank < 0:
			rank = 999
		if rank < best_rank:
			best_rank = rank
			best = VariantUtil.as_string(action.get("key", ""), "")
	return best if not best.is_empty() else _first(actions)


# ------------------------------------------------------------------ helpers

func _coins(state: Dictionary, player: int) -> int:
	var coins: Array = VariantUtil.as_array(state.get("coins", []))
	return VariantUtil.as_int(coins[player], 0) if player >= 0 and player < coins.size() else 0


func _targets(state: Dictionary, player: int) -> Array:
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var out: Array = []
	for other: int in range(counts.size()):
		if other != player and VariantUtil.as_int(counts[other], 0) > 0:
			out.append(other)
	return out


func _leader(state: Dictionary, targets: Array) -> int:
	var best := -1
	var best_rank := Vector2i(-1, -1)
	for target: int in targets:
		var rank := Vector2i(_influence(state, target), _coins(state, target))
		if rank.x > best_rank.x or (rank.x == best_rank.x and rank.y > best_rank.y):
			best_rank = rank
			best = target
	return best


func _richest(state: Dictionary, targets: Array) -> int:
	var best := -1
	var best_coins := 0
	for target: int in targets:
		if _coins(state, target) > best_coins:
			best_coins = _coins(state, target)
			best = target
	return best


func _weakest_influence(state: Dictionary, targets: Array) -> int:
	var weakest := 99
	for target: int in targets:
		weakest = mini(weakest, _influence(state, target))
	return weakest


func _influence(state: Dictionary, player: int) -> int:
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	return VariantUtil.as_int(counts[player], 0) if player >= 0 and player < counts.size() else 0


func _count_role(secret: Dictionary, role: String) -> int:
	var count := 0
	for card: Variant in VariantUtil.as_array(secret.get("hand", [])):
		if VariantUtil.as_string(card, "") == role:
			count += 1
	return count


func _first(actions: Array) -> String:
	return VariantUtil.as_string(VariantUtil.as_dict(actions[0]).get("key", ""), "") if not actions.is_empty() else ""


func _or(key: String, actions: Array) -> String:
	return key if not key.is_empty() else _first(actions)


func _first_of(actions: Array, type: String) -> String:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == type:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""


func _key_of(actions: Array, type: String, params: Dictionary) -> String:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") != type:
			continue
		var matches := true
		for key: String in params:
			if action.get(key) != params[key]:
				matches = false
				break
		if matches:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""
