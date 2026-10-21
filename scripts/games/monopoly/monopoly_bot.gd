extends RefCounted
## Monopoly AI: a deterministic greedy policy.
##
## The bot reads only public state plus its own private trade offer (it never
## looks at another player's secrets). It buys at a sensible reserve, raises in
## auctions up to a quarter above face value, pays its way out of jail when it
## can, builds houses out of spare cash and answers trade offers by comparing
## the values of the properties involved. It never proposes trades itself, so a
## bot-only match can always terminate through rolls alone.

const RESERVE: int = 120
const BUILD_RESERVE: int = 400
const AUCTION_MARGIN: float = 1.25


func choose_action(engine: GameEngine, player: int) -> String:
	var board := engine as MonopolyEngine
	if board == null:
		return ""
	var actions: Array = board.legal_actions(player)
	if actions.is_empty():
		return ""
	match board.phase():
		"trade":
			return _answer_trade(board, player, actions)
		"auction":
			return _auction(board, player, actions)
		"buy":
			return _buy(board, player, actions)
		"jail":
			return _jail(actions)
		_:
			return _turn(board, player, actions)


func _answer_trade(board: MonopolyEngine, player: int, actions: Array) -> String:
	var offer: Dictionary = board.trade
	if offer.is_empty():
		return ""
	var take := int(offer.get("take", -1))
	var give := int(offer.get("give", -1))
	var sweetener := int(offer.get("cash", 0))
	var received := sweetener + (_value(board, player, take) if take >= 0 else 0)
	var sent := _value(board, player, give) if give >= 0 else 0
	for action: Dictionary in actions:
		var accept := String(action.get("type", "")) == "accept_trade"
		if accept and received >= sent + 40:
			return String(action.get("key", ""))
		if not accept and received < sent + 40:
			return String(action.get("key", ""))
	return String((actions[0] as Dictionary).get("key", ""))


func _auction(board: MonopolyEngine, player: int, actions: Array) -> String:
	var space := int(board.auction.get("space", -1))
	var bid := int(board.auction.get("bid", 0))
	var face := int((MonopolyEngine.SPACES[space] as Dictionary).get("price", 0))
	var cap := mini(int(float(face) * AUCTION_MARGIN), board.cash[player] - RESERVE)
	var best := ""
	var best_amount := 0
	var pass_key := ""
	for action: Dictionary in actions:
		var action_type := String(action.get("type", ""))
		if action_type == "pass_bid":
			pass_key = String(action.get("key", ""))
			continue
		if action_type != "bid":
			continue
		var amount := int(action.get("amount", 0))
		if amount <= cap and (best.is_empty() or amount < best_amount):
			best = String(action.get("key", ""))
			best_amount = amount
	if not best.is_empty():
		return best
	if not pass_key.is_empty():
		return pass_key
	return String((actions[0] as Dictionary).get("key", ""))


func _buy(board: MonopolyEngine, player: int, actions: Array) -> String:
	var price := 0
	var pass_key := ""
	var buy_key := ""
	for action: Dictionary in actions:
		match String(action.get("type", "")):
			"buy":
				buy_key = String(action.get("key", ""))
				price = int((MonopolyEngine.SPACES[int(action.get("space", 0))] as Dictionary).get("price", 0))
			"pass_buy":
				pass_key = String(action.get("key", ""))
	if not buy_key.is_empty() and board.cash[player] >= price + RESERVE:
		return buy_key
	if not pass_key.is_empty():
		return pass_key
	return buy_key


func _jail(actions: Array) -> String:
	var fallback := ""
	for action: Dictionary in actions:
		match String(action.get("type", "")):
			"use_card":
				return String(action.get("key", ""))
			"pay_fine":
				fallback = String(action.get("key", ""))
			"roll":
				if fallback.is_empty():
					fallback = String(action.get("key", ""))
	return fallback if not fallback.is_empty() else String((actions[0] as Dictionary).get("key", ""))


func _turn(board: MonopolyEngine, player: int, actions: Array) -> String:
	var roll_key := ""
	var builds: Array = []
	for action: Dictionary in actions:
		var action_type := String(action.get("type", ""))
		if action_type == "roll":
			roll_key = String(action.get("key", ""))
		elif action_type == "build_house":
			builds.append(action)
	if not builds.is_empty() and board.cash[player] >= BUILD_RESERVE:
		builds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("_price", 0)) < int(b.get("_price", 0))
		)
		return String((builds[0] as Dictionary).get("key", ""))
	if not roll_key.is_empty():
		return roll_key
	return String((actions[0] as Dictionary).get("key", ""))


## Rough property value: face value plus a bonus for completing a colour group.
func _value(board: MonopolyEngine, player: int, space: int) -> int:
	if space < 0 or space >= MonopolyEngine.BOARD_SIZE:
		return 0
	var data: Dictionary = MonopolyEngine.SPACES[space]
	var value := int(data.get("price", 0))
	var group := String(data.get("group", ""))
	if not group.is_empty():
		var missing := 0
		for member: int in board.group_spaces(group):
			if board.owner[member] != player and member != space:
				missing += 1
		if missing == 0:
			value += int(data.get("price", 0))
		elif missing == 1:
			value += int(data.get("price", 0)) / 3
	return value
