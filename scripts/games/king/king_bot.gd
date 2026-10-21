extends RefCounted
## King bot: a deterministic greedy policy.
##
## The bot never cheats - it only reads the public state plus its own legal
## actions - and it only ever returns a key taken from
## [method GameEngine.legal_actions], so every choice is legal by construction
## ([BotDirector] re-validates it anyway).
##
## Passing: every card is offered, so the bot simply hands over the three most
## dangerous cards it holds (king of hearts, queen of spades, the highest
## hearts, then the highest of the rest).
## Playing: when it leads it puts down its least dangerous card; when it can
## follow suit it ducks with the lowest card of the led suit; when it cannot
## follow it dumps the most dangerous card in hand.

func choose_action(engine: GameEngine, player: int) -> String:
	var game := engine as KingEngine
	if game == null:
		return ""
	var actions := engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var mode := _mode(game, actions)
	var best: Dictionary = {}
	var best_cost := 0
	for entry: Variant in actions:
		var action: Dictionary = entry
		var card := VariantUtil.as_string(action.get("card", ""), "")
		var cost := _cost(game, card, mode)
		if best.is_empty() or cost < best_cost or (cost == best_cost and card < VariantUtil.as_string(best.get("card", ""), "")):
			best = action
			best_cost = cost
	return VariantUtil.as_string(best.get("key", ""), "")


## Decides how the cards are chosen: what to pass, what to lead, ducking or
## dumping. The mode is derived from the legal actions alone, so the bot stays
## inside its own information even though every card is an option.
func _mode(game: KingEngine, actions: Array) -> String:
	if game.phase() != "playing":
		return "pass"
	var led := game.led_suit()
	if led.is_empty():
		return "lead"
	var follows := true
	for entry: Variant in actions:
		if KingEngine.card_suit(VariantUtil.as_string(VariantUtil.as_dict(entry).get("card", ""), "")) != led:
			follows = false
			break
	return "follow" if follows else "dump"


## Lower cost is always the better card.
func _cost(game: KingEngine, card: String, mode: String) -> int:
	match mode:
		"pass", "dump":
			return -_weight(game, card)
		"lead":
			return _weight(game, card)
		"follow":
			return KingEngine.rank_index(card)
	return _weight(game, card)


func _weight(game: KingEngine, card: String) -> int:
	return game.pass_danger(card) * 100 + KingEngine.rank_index(card)
