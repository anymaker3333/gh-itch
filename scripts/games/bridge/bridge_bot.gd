extends RefCounted
## Bridge bot: a deterministic beginner policy.
##
## The bot only reads the public state and its own hand, and it always returns
## a key taken from [method GameEngine.legal_actions], so every choice is legal
## by construction ([BotDirector] re-validates it anyway).
##
## Auction: with no bid on the table the bot opens one club (the cheapest legal
## contract) so a solo match cannot pass out. Once somebody has bid it passes.
## Play: it always plays the lowest card that is legal.

func choose_action(engine: GameEngine, player: int) -> String:
	var game := engine as BridgeEngine
	if game == null:
		return ""
	var actions := engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var state := engine.public_state()
	if String(state.get("phase_id", "")) == "auction":
		if int(state.get("highest_bidder", -1)) < 0:
			var opening := _opening_bid(actions)
			if not opening.is_empty():
				return String(opening.get("key", ""))
	return String((actions[0] as Dictionary).get("key", ""))


## Picks the cheapest legal bid; 1C is always available when the auction is
## empty, so this simply returns the first non-pass action.
func _opening_bid(actions: Array[Dictionary]) -> Dictionary:
	for action: Dictionary in actions:
		if String(action.get("type", "")) == "bid":
			return action
	return {}
