extends RefCounted
## Splendor AI: a deterministic greedy gem merchant.
##
## The bot reads public state plus its own reserve only, uses no randomness and
## always answers with the key of an action the engine offered (an empty string
## makes [BotDirector] fall back to the first legal action, which only happens
## for a genuinely empty list). Policy, in order:
##   1. buy the most valuable affordable card: points first, then progress towards
##      a noble, then cheapness;
##   2. otherwise reserve the most valuable visible card (a blind reserve from the
##      top of a deck is the last resort, because it is an uninformed choice);
##   3. otherwise take gems that close the gap to the cheapest card still worth
##      buying, taking two identical gems when the pile allows it and the target
##      really needs two of that colour;
##   4. otherwise take whatever the supply offers.

const POINT_VALUE: int = 600
const NOBLE_PULL: int = 400
const RESERVED_BONUS: int = 40
const TAKE_NEEDED: int = 30
const TAKE_FRESH: int = 6
const TAKE_EXTRA: int = 1
const DOUBLE_TAKE: int = 40
const OVER_LIMIT_PENALTY: int = 60


func choose_action(engine: GameEngine, player: int) -> String:
	var table := engine as SplendorEngine
	if table == null:
		return ""
	var actions: Array[Dictionary] = table.legal_actions(player)
	if actions.is_empty():
		return ""
	var state := table.public_state()
	var tokens := _counts_of(state, "tokens", player)
	var bonuses := _counts_of(state, "bonuses", player)
	var purchases: Array[Dictionary] = []
	var reserves: Array[Dictionary] = []
	var takes: Array[Dictionary] = []
	for action: Dictionary in actions:
		match VariantUtil.as_string(action.get("type", ""), ""):
			"buy":
				purchases.append(action)
			"reserve":
				reserves.append(action)
			"take":
				takes.append(action)
	if not purchases.is_empty():
		return _best_buy(table, purchases, state, bonuses)
	if not reserves.is_empty():
		return _best_reserve(reserves)
	if not takes.is_empty():
		return _best_take(table, player, takes, state, tokens, bonuses)
	return VariantUtil.as_string(actions[0].get("key", ""), "")


# -------------------------------------------------------------------- buying

func _best_buy(table: SplendorEngine, purchases: Array[Dictionary], state: Dictionary, bonuses: Dictionary) -> String:
	var best_key := ""
	var best_score := -999999
	for action: Dictionary in purchases:
		var score := _buy_score(action, state, bonuses, table)
		if score > best_score:
			best_score = score
			best_key = VariantUtil.as_string(action.get("key", ""), "")
	return best_key


func _buy_score(action: Dictionary, state: Dictionary, bonuses: Dictionary, table: SplendorEngine) -> int:
	var cost: Array = VariantUtil.as_array(action.get("_cost", []))
	var total := 0
	for value: Variant in cost:
		total += VariantUtil.as_int(value, 0)
	var score := VariantUtil.as_int(action.get("_points", 0), 0) * POINT_VALUE + (16 - total) * 20
	var bonus := VariantUtil.as_string(action.get("_bonus", ""), "")
	score += _noble_pull(table, state, bonuses, bonus)
	if bool(action.get("_reserve", false)):
		# Cards from the reserve are already half paid for (they cost a gold token).
		score += RESERVED_BONUS
	return score


## How much buying a card of `bonus` colour advances the nearest noble.
func _noble_pull(table: SplendorEngine, state: Dictionary, bonuses: Dictionary, bonus: String) -> int:
	var index := SplendorEngine.GEM_COLOURS.find(bonus)
	if index < 0:
		return 0
	var owners: Array = VariantUtil.as_array(state.get("noble_owner", []))
	var pull := 0
	for entry: Variant in VariantUtil.as_array(state.get("nobles", [])):
		var noble_id := VariantUtil.as_int(entry, -1)
		if noble_id < 0 or noble_id >= owners.size() or VariantUtil.as_int(owners[noble_id], -1) >= 0:
			continue
		var cost: Array = VariantUtil.as_array(table.noble_data(noble_id).get("cost", []))
		if index >= cost.size() or VariantUtil.as_int(cost[index], 0) <= 0:
			continue
		var missing := VariantUtil.as_int(cost[index], 0) - VariantUtil.as_int(bonuses.get(bonus, 0), 0)
		if missing == 1:
			pull = maxi(pull, NOBLE_PULL)
		elif missing > 1:
			pull = maxi(pull, 60 - missing * 15)
	return pull


# ----------------------------------------------------------------- reserving

func _best_reserve(reserves: Array[Dictionary]) -> String:
	var best_key := ""
	var best_score := -999999
	for action: Dictionary in reserves:
		var score := -999999
		if not bool(action.get("_blind", false)):
			var cost: Array = VariantUtil.as_array(action.get("_cost", []))
			var total := 0
			for value: Variant in cost:
				total += VariantUtil.as_int(value, 0)
			score = VariantUtil.as_int(action.get("_points", 0), 0) * 300 + VariantUtil.as_int(action.get("_tier", 1), 1) * 30 - total * 10
		else:
			# Reserving the unknown top card keeps the choice only as a fallback.
			score = VariantUtil.as_int(action.get("_tier", 1), 1) * 5 - 300
		if score > best_score:
			best_score = score
			best_key = VariantUtil.as_string(action.get("key", ""), "")
	return best_key


# ------------------------------------------------------------------- taking

func _best_take(table: SplendorEngine, player: int, takes: Array[Dictionary], state: Dictionary, tokens: Dictionary, bonuses: Dictionary) -> String:
	var needs := _target_needs(table, player, state, tokens, bonuses)
	var held := 0
	for colour: Variant in tokens:
		held += VariantUtil.as_int(tokens[colour], 0)
	var best_key := ""
	var best_score := -999999
	for action: Dictionary in takes:
		var gems: Array = VariantUtil.as_array(action.get("_gems", []))
		var score := 0
		var same := gems.size() == 2 and str(gems[0]) == str(gems[1])
		for gem: Variant in gems:
			var colour := VariantUtil.as_string(gem, "")
			if VariantUtil.as_int(needs.get(colour, 0), 0) > 0:
				score += TAKE_NEEDED
			elif VariantUtil.as_int(tokens.get(colour, 0), 0) == 0:
				score += TAKE_FRESH
			else:
				score += TAKE_EXTRA
		if same and VariantUtil.as_int(needs.get(str(gems[0]), 0), 0) >= 2:
			score += DOUBLE_TAKE
		if held + gems.size() > SplendorEngine.TOKEN_LIMIT:
			# The engine would hand the surplus straight back: a wasted turn.
			score -= OVER_LIMIT_PENALTY
		if score > best_score:
			best_score = score
			best_key = VariantUtil.as_string(action.get("key", ""), "")
	return best_key


## Missing gems per colour for the cheapest card still worth buying. Preference
## order: fewest missing gems, then most points, then lowest card id.
func _target_needs(table: SplendorEngine, player: int, state: Dictionary, tokens: Dictionary, bonuses: Dictionary) -> Dictionary:
	var best_missing := 1 << 30
	var best_points := -1
	var best_cost: Array = []
	for card_id: int in _candidate_cards(table, player, state):
		var card := table.card_data(card_id)
		if card.is_empty():
			continue
		var cost: Array = VariantUtil.as_array(card.get("cost", []))
		var missing := 0
		for i: int in range(SplendorEngine.GEM_COLOURS.size()):
			var colour: String = SplendorEngine.GEM_COLOURS[i]
			missing += maxi(0, VariantUtil.as_int(cost[i], 0) - VariantUtil.as_int(bonuses.get(colour, 0), 0) - VariantUtil.as_int(tokens.get(colour, 0), 0))
		if missing <= VariantUtil.as_int(tokens.get("gold", 0), 0):
			continue  # already affordable: the buy branch would have taken it
		var points := VariantUtil.as_int(card.get("points", 0), 0)
		if missing < best_missing or (missing == best_missing and points > best_points):
			best_missing = missing
			best_points = points
			best_cost = cost
	var needs: Dictionary = {}
	if best_cost.is_empty():
		return needs
	for i: int in range(SplendorEngine.GEM_COLOURS.size()):
		var colour: String = SplendorEngine.GEM_COLOURS[i]
		var need := maxi(0, VariantUtil.as_int(best_cost[i], 0) - VariantUtil.as_int(bonuses.get(colour, 0), 0) - VariantUtil.as_int(tokens.get(colour, 0), 0))
		if need > 0:
			needs[colour] = need
	return needs


## Cards the player could still buy: the market plus their own reserve.
func _candidate_cards(table: SplendorEngine, player: int, state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for row: Variant in VariantUtil.as_array(state.get("market", [])):
		for slot: Variant in VariantUtil.as_array(row):
			var card_id := VariantUtil.as_int(slot, -1)
			if card_id >= 0:
				out.append(card_id)
	for card_id: Variant in VariantUtil.as_array(table.private_state(player).get("reserved", [])):
		out.append(VariantUtil.as_int(card_id, -1))
	return out


func _counts_of(state: Dictionary, field: String, player: int) -> Dictionary:
	var rows: Array = VariantUtil.as_array(state.get(field, []))
	if player < 0 or player >= rows.size() or not (rows[player] is Dictionary):
		return {}
	return VariantUtil.dict_copy(rows[player])
