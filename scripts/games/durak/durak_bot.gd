extends RefCounted
## Durak bot: a deterministic greedy policy.
##
## The bot never cheats - it only reads the public state plus its own hand - and
## it only ever returns a key taken from [method GameEngine.legal_actions], so
## every choice is legal by construction. [BotDirector] re-validates it anyway.
##
## Defence: beat the attack with the cheapest card that works, preferring a
## plain card over a trump; pick the table up when beating it would only waste a
## high trump on a growing pile.
## Attack: shed the cheapest card, and only extend an open attack with small
## cards of a rank that is already on the table.

func choose_action(engine: GameEngine, player: int) -> String:
	var game := engine as DurakEngine
	if game == null:
		return ""
	var actions: Array = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var defends: Array = []
	var attacks: Array = []
	var take: Dictionary = {}
	var done: Dictionary = {}
	for entry: Variant in actions:
		var action: Dictionary = entry
		match String(action.get("type", "")):
			"defend":
				defends.append(action)
			"attack":
				attacks.append(action)
			"take":
				take = action
			"pass":
				done = action
	if not defends.is_empty():
		var cheapest := _cheapest(defends, game)
		if not take.is_empty() and _prefer_take(game, player, defends, cheapest):
			return String(take.get("key", ""))
		return String(cheapest.get("key", ""))
	if not take.is_empty():
		return String(take.get("key", ""))
	if not attacks.is_empty():
		var choice := _cheapest(attacks, game)
		if _worth_extending(game, choice):
			return String(choice.get("key", ""))
	if not done.is_empty():
		return String(done.get("key", ""))
	if not attacks.is_empty():
		return String(_cheapest(attacks, game).get("key", ""))
	return ""


## Cheapest working defence among the legal ones: a plain card first, then the
## lowest trump.
func _cheapest(defends: Array, game: DurakEngine) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in defends:
		var action: Dictionary = entry
		if best.is_empty() or _less(String(action.get("card", "")), String(best.get("card", "")), game):
			best = action
	return best


func _less(a: String, b: String, game: DurakEngine) -> bool:
	var value_a := _value(a, game)
	var value_b := _value(b, game)
	if value_a == value_b:
		return a < b
	return value_a < value_b


func _value(card: String, game: DurakEngine) -> int:
	return DurakEngine.rank_index(card) + (100 if game.is_trump(card) else 0)


## When every defence costs a trump and the table already holds two or more
## cards, picking the cards up is the cheaper option. A plain-card defence is
## always worth playing.
func _prefer_take(game: DurakEngine, player: int, defends: Array, cheapest: Dictionary) -> bool:
	var cheapest_card := String(cheapest.get("card", ""))
	if not game.is_trump(cheapest_card):
		return false
	var table_size := 0
	if not game.table.is_empty():
		table_size = game.table.size()
	if table_size >= 2:
		return true
	# Only one attack on the table: keep low trumps for defence, hand over the
	# cards when nothing but a picture trump could beat it.
	return DurakEngine.rank_index(cheapest_card) >= DurakEngine.RANKS.find("Q")


## Attacking: the first card may be anything; an extension should only use small
## plain cards so that high cards and trumps stay in hand.
func _worth_extending(game: DurakEngine, choice: Dictionary) -> bool:
	if game.table.is_empty():
		return true
	var card := String(choice.get("card", ""))
	if game.is_trump(card):
		return false
	return DurakEngine.rank_index(card) < DurakEngine.RANKS.find("10")
