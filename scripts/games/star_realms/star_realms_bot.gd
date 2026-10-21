extends RefCounted
## Star Realms AI: deterministic greedy policy.
##
## The bot only reads the public table plus its own hand (the engine's
## [method StarRealmsEngine.legal_actions] only answers for the acting player, so
## there is nothing else to read anyway). It plays every card it can, groups cards
## by faction so ally abilities fire, scraps its weak machine-cult ships, kills
## blockers before hitting authority and spends all trade on the best affordable
## card. Every choice is a total order over the legal actions, so the same seed and
## the same state always produce the same move - [BotDirector] verifies that the
## returned key is legal.

## Scoring weights, kept as small integers so the comparison is exact.
const WEIGHT_TRADE: int = 3
const WEIGHT_COMBAT: int = 3
const WEIGHT_AUTHORITY: int = 2
const WEIGHT_DRAW: int = 4

var engine: StarRealmsEngine = null


func choose_action(active_engine: GameEngine, player: int) -> String:
	engine = active_engine as StarRealmsEngine
	if engine == null:
		return ""
	var actions: Array = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var chosen := _choose_pending(player, actions)
	if chosen.is_empty():
		chosen = _choose_play(player, actions)
	if chosen.is_empty():
		chosen = _choose_scrap(player, actions)
	if chosen.is_empty():
		chosen = _choose_attack(player, actions)
	if chosen.is_empty():
		chosen = _choose_buy(player, actions)
	if chosen.is_empty():
		chosen = _choose_of_type(actions, "end_turn")
	if chosen.is_empty():
		return String((actions[0] as Dictionary).get("key", ""))
	return String(chosen.get("key", ""))


# ------------------------------------------------------- optional effects first

## Mandatory-looking choices first: they were already paid for by an ability.
func _choose_pending(player: int, actions: Array) -> Dictionary:
	var row: Array = engine.public_state().get("trade_row", [])
	var scrap_row_action := _best_of(actions, "scrap_row", func(action: Dictionary) -> int:
		var slot := int(action.get("slot", -1))
		if slot < 0 or slot >= row.size():
			return -1
		return StarRealmsCards.cost_of(String((row[slot] as Dictionary).get("id", "")))
	)
	if not scrap_row_action.is_empty():
		return scrap_row_action

	var destroy := _best_of(actions, "destroy_base", func(action: Dictionary) -> int:
		var owner := int(action.get("player", -1))
		var index := int(action.get("base", -1))
		var bases := engine.bases_of(owner)
		if index < 0 or index >= bases.size():
			return -1
		var card_id := String((bases[index] as Dictionary).get("id", ""))
		var score := StarRealmsCards.cost_of(card_id) * 2
		if StarRealmsCards.is_outpost(card_id):
			score += 8
		return score
	)
	if not destroy.is_empty():
		return destroy

	var hand: Array = engine.hand_of(player)
	return _best_of(actions, "scrap_hand", func(action: Dictionary) -> int:
		## Lowest value first: the bot scraps a Scout before a bought card.
		var uid := int(action.get("card", -1))
		for card: Dictionary in hand:
			if int(card.get("uid", -1)) == uid:
				return 1000 - _card_value(String(card.get("id", "")))
		return -1
	)


# ---------------------------------------------------------------- play a card

## Plays the card that grows the faction the bot already has on the table the
## most, so ally abilities chain; cost breaks ties inside a faction.
func _choose_play(player: int, actions: Array) -> Dictionary:
	var hand: Array = engine.hand_of(player)
	var counts := _faction_counts(player)
	return _best_of(actions, "play_card", func(action: Dictionary) -> int:
		var card_id := _hand_card_id(hand, int(action.get("card", -1)))
		if card_id.is_empty():
			return -1
		var faction := StarRealmsCards.faction_of(card_id)
		var allies := int(counts.get(faction, 0)) if faction != StarRealmsCards.FACTION_UNALIGNED else 0
		return allies * 1000 + StarRealmsCards.cost_of(card_id) * 3 + _card_value(card_id)
	)


# ------------------------------------------------------- scrap a card in play

## Scrapping the cheap machine-cult ships is what buys the bot deck quality: the
## scrap ability is worth more than keeping a one- or two-cost card, and the
## removed card makes every future hand better. Persisting bases are kept for
## their defence.
func _choose_scrap(player: int, actions: Array) -> Dictionary:
	return _best_of(actions, "scrap_play", func(action: Dictionary) -> int:
		var card_id := _in_play_card_id(player, int(action.get("card", -1)))
		if card_id.is_empty() or StarRealmsCards.is_base(card_id):
			return -1
		var gain := _ability_value(StarRealmsCards.by_id(card_id).get("scrap", {}))
		if gain <= 0:
			return -1
		if StarRealmsCards.cost_of(card_id) <= 2:
			return gain + 10
		return gain if gain >= 8 else -1
	)


# -------------------------------------------------------------------- attacks

## Blockers first: an outpost must fall before its owner can be hit, and a base
## that is worth more than its defence is removed before authority is damaged.
func _choose_attack(player: int, actions: Array) -> Dictionary:
	var combat := engine.combat_of(player)
	var bases := _best_of(actions, "attack_base", func(action: Dictionary) -> int:
		var owner := int(action.get("player", -1))
		var index := int(action.get("base", -1))
		var owned := engine.bases_of(owner)
		if index < 0 or index >= owned.size():
			return -1
		var card_id := String((owned[index] as Dictionary).get("id", ""))
		var cost := StarRealmsCards.cost_of(card_id)
		var defense := StarRealmsCards.defense_of(card_id)
		if StarRealmsCards.is_outpost(card_id):
			return 2000 + cost
		if cost >= defense:
			return 1000 + cost
		return -1
	)
	if not bases.is_empty():
		return bases
	return _best_of(actions, "attack_authority", func(action: Dictionary) -> int:
		var target := int(action.get("player", -1))
		var authority := engine.authority_of(target)
		if authority <= combat:
			# Killing blow: eliminate the weakest opponent first.
			return 100000 - authority
		# Otherwise hit whoever is ahead.
		return authority
	)


# ---------------------------------------------------------------------- buys

## Spends all trade: the best affordable row card, or an Explorer when nothing in
## the row beats it.
func _choose_buy(player: int, actions: Array) -> Dictionary:
	var row: Array = engine.public_state().get("trade_row", [])
	var best_row := _best_of(actions, "buy", func(action: Dictionary) -> int:
		var slot := int(action.get("slot", -1))
		if slot < 0 or slot >= row.size():
			return -1
		return _card_value(String((row[slot] as Dictionary).get("id", "")))
	)
	var explorer := _choose_of_type(actions, "buy_explorer")
	if explorer.is_empty():
		return best_row
	if best_row.is_empty():
		return explorer
	var slot := int(best_row.get("slot", -1))
	var picked := 0
	if slot >= 0 and slot < row.size():
		picked = _card_value(String((row[slot] as Dictionary).get("id", "")))
	if picked < _card_value(StarRealmsCards.EXPLORER):
		return explorer
	return best_row


# ------------------------------------------------------------------- helpers

## Returns the highest scoring action of one type (strict `>` keeps the first
## action of a tie, which makes the policy deterministic).
func _best_of(actions: Array, action_type: String, score_of: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for action: Variant in actions:
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if String(entry.get("type", "")) != action_type:
			continue
		var score := int(score_of.call(entry))
		if score > best_score:
			best_score = score
			best = entry
	return best


func _choose_of_type(actions: Array, action_type: String) -> Dictionary:
	for action: Variant in actions:
		if action is Dictionary and String((action as Dictionary).get("type", "")) == action_type:
			return action
	return {}


func _hand_card_id(hand: Array, uid: int) -> String:
	for card: Dictionary in hand:
		if int(card.get("uid", -1)) == uid:
			return String(card.get("id", ""))
	return ""


func _in_play_card_id(player: int, uid: int) -> String:
	for card: Dictionary in engine.in_play_of(player):
		if int(card.get("uid", -1)) == uid:
			return String(card.get("id", ""))
	for card: Dictionary in engine.bases_of(player):
		if int(card.get("uid", -1)) == uid:
			return String(card.get("id", ""))
	return ""


## Cards of each faction the player has on the table, bases included.
func _faction_counts(player: int) -> Dictionary:
	var counts: Dictionary = {}
	for card: Dictionary in engine.in_play_of(player):
		_bump_faction(counts, String(card.get("id", "")))
	for card: Dictionary in engine.bases_of(player):
		_bump_faction(counts, String(card.get("id", "")))
	return counts


func _bump_faction(counts: Dictionary, card_id: String) -> void:
	var faction := StarRealmsCards.faction_of(card_id)
	if faction == StarRealmsCards.FACTION_UNALIGNED:
		return
	counts[faction] = int(counts.get(faction, 0)) + 1


## Rough value of a card in play or in the row; bases are worth their staying power.
func _card_value(card_id: String) -> int:
	var card := StarRealmsCards.by_id(card_id)
	if card.is_empty():
		return 0
	var value := StarRealmsCards.cost_of(card_id) + _ability_value(card)
	if StarRealmsCards.is_base(card_id):
		value += StarRealmsCards.defense_of(card_id) / 2 + 3
	if not (card.get("ally", {}) as Dictionary).is_empty():
		value += 2
	if not (card.get("scrap", {}) as Dictionary).is_empty():
		value += 1
	return value


func _ability_value(ability: Dictionary) -> int:
	return int(ability.get("trade", 0)) * WEIGHT_TRADE \
		+ int(ability.get("combat", 0)) * WEIGHT_COMBAT \
		+ int(ability.get("authority", 0)) * WEIGHT_AUTHORITY \
		+ int(ability.get("draw", 0)) * WEIGHT_DRAW \
		+ int(ability.get("scrap_hand", 0)) * 3 \
		+ int(ability.get("scrap_row", 0)) * 3 \
		+ int(ability.get("destroy_base", 0)) * 4
