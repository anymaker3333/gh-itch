extends RefCounted
## Citadels AI: a deterministic greedy policy.
##
## The bot only uses information a human player could see: the public state plus
## its own private characters and hand (never [code]role_owner[/code]). It drafts
## by a fixed preference order, takes gold unless it has nothing to build with,
## builds its most valuable affordable district and then uses its power.

## Draft preference: money engine first, then the powers that build.
const DRAFT_PRIORITY: Array[int] = [6, 4, 7, 5, 8, 3, 2, 1]
## Assassination targets: the characters that hurt the most to lose.
const KILL_PRIORITY: Array[int] = [4, 6, 7, 5, 8, 2, 3]
## Theft targets: the characters most likely to be holding gold.
const STEAL_PRIORITY: Array[int] = [6, 4, 7, 5, 8, 3]

var seat: int = -1


func choose_action(engine: GameEngine, player: int) -> String:
	seat = player
	var actions: Array = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var state: Dictionary = engine.public_state()
	var secret: Dictionary = engine.private_state(player)
	match VariantUtil.as_string(state.get("step", ""), ""):
		"draft":
			return _draft(actions, secret)
		"income":
			return _income(actions, state, secret)
		"action":
			return _action(actions, state, secret)
	return VariantUtil.as_string(actions[0].get("key", ""), "")


func _draft(actions: Array, secret: Dictionary) -> String:
	var mine: Array = secret.get("roles", [])
	var hand: Array = secret.get("hand", [])
	var priority := DRAFT_PRIORITY
	if hand.is_empty():
		priority = [7, 6, 4, 5, 8, 3, 2, 1]
	for role: int in priority:
		if mine.has(role):
			continue
		for action: Dictionary in actions:
			if VariantUtil.as_string(action.get("type", ""), "") == "take_role" and VariantUtil.as_int(action.get("role", 0), 0) == role:
				return VariantUtil.as_string(action.get("key", ""), "")
	return _first_of(actions, "take_role")


func _income(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	var hand: Array = secret.get("hand", [])
	if hand.is_empty() and _has(actions, "draw_cards"):
		return _first_of(actions, "draw_cards")
	if _gold(state) >= 6 and hand.size() < 4 and _has(actions, "draw_cards"):
		return _first_of(actions, "draw_cards")
	return _first_of(actions, "income")


func _action(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	var build := _best_build(actions)
	if not build.is_empty():
		return build
	var power := _use_power(actions, state, secret)
	if not power.is_empty():
		return power
	return _first_of(actions, "end_turn")


## Most expensive affordable district in hand; ties go to the first slot.
## The engine only lists affordable builds, so every entry is playable.
func _best_build(actions: Array) -> String:
	var best := ""
	var best_cost := -1
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") != "build":
			continue
		var cost := CitadelsEngine.district_cost(VariantUtil.as_string(action.get("card", ""), ""))
		if cost > best_cost:
			best_cost = cost
			best = VariantUtil.as_string(action.get("key", ""), "")
	return best


func _use_power(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	match VariantUtil.as_int(state.get("current_role", 0), 0):
		1:
			return _pick_role(actions, "assassinate", secret, VariantUtil.as_int(state.get("killed_role", 0), 0), state)
		2:
			return _pick_role(actions, "steal", secret, 0, state)
		3:
			var swap := _magician(actions, state, secret)
			if not swap.is_empty():
				return swap
			return _first_of(actions, "magician_discard")
		8:
			return _warlord(actions, state)
	return ""


## Assassin/thief: name the highest-value character that is in play, not mine and
## not already dead. The draft pool is public, so unclaimed characters are
## avoided (they would make the power fizzle).
func _pick_role(actions: Array, type: String, secret: Dictionary, killed: int, state: Dictionary) -> String:
	var priority := KILL_PRIORITY if type == "assassinate" else STEAL_PRIORITY
	var mine: Array = secret.get("roles", [])
	var pool: Array = state.get("role_pool", [])
	for role: int in priority:
		if role == killed or mine.has(role) or pool.has(role):
			continue
		for action: Dictionary in actions:
			if VariantUtil.as_string(action.get("type", ""), "") == type and VariantUtil.as_int(action.get("role", 0), 0) == role:
				return VariantUtil.as_string(action.get("key", ""), "")
	return _first_of(actions, type)


## Magician: swap with the largest hand when ours is smaller, else discard.
func _magician(actions: Array, state: Dictionary, secret: Dictionary) -> String:
	var hand: Array = VariantUtil.as_array(secret.get("hand", []))
	var counts: Array = VariantUtil.as_array(state.get("hand_counts", []))
	var target := -1
	var biggest := hand.size()
	for other: int in range(counts.size()):
		if other == seat:
			continue
		if VariantUtil.as_int(counts[other], 0) > biggest:
			biggest = VariantUtil.as_int(counts[other], 0)
			target = other
	if target < 0:
		return ""
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == "magician_swap" and VariantUtil.as_int(action.get("target", -1), -1) == target:
			return VariantUtil.as_string(action.get("key", ""), "")
	return ""


## Warlord: raze the most expensive district of the richest opponent.
func _warlord(actions: Array, state: Dictionary) -> String:
	var best := ""
	var best_rank := Vector2i(-1, -1)
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") != "destroy":
			continue
		var target := VariantUtil.as_int(action.get("target", -1), -1)
		var rank := Vector2i(VariantUtil.as_int(action.get("_price", 0), 0), _threat(state, target))
		if rank.x > best_rank.x or (rank.x == best_rank.x and rank.y > best_rank.y):
			best_rank = rank
			best = VariantUtil.as_string(action.get("key", ""), "")
	return best


## Public threat proxy: districts already built.
func _threat(state: Dictionary, target: int) -> int:
	if target < 0 or target == seat:
		return -1
	var cities: Array = VariantUtil.as_array(state.get("cities", []))
	if target >= cities.size():
		return 0
	return VariantUtil.as_array(cities[target]).size()


func _gold(state: Dictionary) -> int:
	var gold: Array = VariantUtil.as_array(state.get("gold", []))
	return VariantUtil.as_int(gold[seat], 0) if seat >= 0 and seat < gold.size() else 0


func _has(actions: Array, type: String) -> bool:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == type:
			return true
	return false


func _first_of(actions: Array, type: String) -> String:
	for action: Dictionary in actions:
		if VariantUtil.as_string(action.get("type", ""), "") == type:
			return VariantUtil.as_string(action.get("key", ""), "")
	return VariantUtil.as_string(VariantUtil.as_dict(actions[0]).get("key", ""), "")
