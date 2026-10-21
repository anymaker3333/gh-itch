extends RefCounted
## Monopoly rules suite: board data, movement, purchase and auctions, rents,
## houses with the even-build rule, jail, cards, trading, bankruptcy, the turn
## cap, determinism, snapshots, privacy and a bot-only match.
##
## The suite reaches specific rules by placing pieces and invoking the landing
## resolver directly (test setup only; the engine itself is never patched).


func suite_name() -> String:
	return "monopoly rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_movement(h)
	_purchase(h)
	_auction(h)
	_rent(h)
	_houses(h)
	_jail(h)
	_cards(h)
	_trading(h)
	_bounded_trades(h)
	_bankruptcy(h)
	_endings(h)
	_illegal(h)
	_determinism(h)
	_snapshot(h)
	_privacy(h)
	_bot_match(h)


## §6.7 regression: the trade enumeration stays bounded, unique and
## deterministic. The earlier cross product (every give × take × cash variant)
## listed hundreds of near-identical offers in a developed match, pushing the
## action bar and every replicated state snapshot into truncation territory.
func _bounded_trades(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	engine.cash[0] = 4000
	# A rich hand on both sides drives the cross product above the cap:
	# eight counterparty houses, three own houses.
	for space: int in [16, 17, 18, 19, 20, 21, 22, 23]:
		engine.owner[space] = 1
	for space: int in [6, 7, 8]:
		engine.owner[space] = 0
	var trades: Array = []
	for action: Variant in engine.legal_actions(0):
		if String((action as Dictionary).get("type", "")) == "propose_trade":
			trades.append(action)
	h.greater(float(trades.size()), 0.0, "trade offers are listed")
	h.less_equal(float(trades.size()), float(MonopolyEngine.MAX_TRADE_OFFERS),
		"the trade enumeration is capped (%d listed)" % trades.size())
	var keys: Dictionary = {}
	for action: Variant in trades:
		keys[String((action as Dictionary).get("key", ""))] = true
	h.equal(float(keys.size()), float(trades.size()), "every trade offer keeps a unique action key")
	# Fairness-ranked: the responder's own value balance improves along the list.
	var last_rank := -1
	for action: Variant in trades:
		var give := int((action as Dictionary).get("give", -1))
		var take := int((action as Dictionary).get("take", -1))
		var cash := int((action as Dictionary).get("cash", 0))
		var give_value := int((MonopolyEngine.SPACES[give] as Dictionary).get("price", 0)) if give >= 0 else 0
		var take_value := int((MonopolyEngine.SPACES[take] as Dictionary).get("price", 0))
		var rank := absi(give_value + cash - take_value)
		h.check(rank >= last_rank, "value-balance ranks stay non-descending")
		last_rank = rank
	# A repeated call lists the same offers: pruning is deterministic.
	h.equal(engine.legal_actions(0), engine.legal_actions(0), "the offer list is deterministic")


func _engine(h: TestHarness, player_count: int = 2, options: Dictionary = {}) -> MonopolyEngine:
	var engine := EngineHarness.create("monopoly", player_count, 20260119, options) as MonopolyEngine
	h.check(engine != null, "monopoly engine must be creatable")
	return engine


## Reads (without consuming) the next dice pair of a fresh engine.
func _peek_roll(engine: MonopolyEngine) -> Array:
	var saved: int = engine.rng.state
	var d1 := engine.rng.randi_range(1, 6)
	var d2 := engine.rng.randi_range(1, 6)
	engine.rng.state = saved
	return [d1, d2]


func _seed_with(doubles: bool) -> int:
	for candidate: int in range(1, 200):
		var engine := EngineHarness.create("monopoly", 2, candidate) as MonopolyEngine
		if engine == null:
			continue
		var dice := _peek_roll(engine)
		if (dice[0] == dice[1]) == doubles:
			return candidate
	return 1


# --------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	h.equal(engine.cash, [1500, 1500, 1500], "every player starts with the standard cash")
	h.equal(engine.pos, [0, 0, 0], "everybody starts on GO")
	h.equal(engine.phase(), "turn", "the first phase is the turn")
	h.equal(engine.decision_player(), 0, "player one moves first")
	h.equal(engine.chance_deck.size(), 16, "the chance deck has sixteeen cards")
	h.equal(engine.chest_deck.size(), 16, "the community chest deck has sixteen cards")
	for phase: String in engine.phases():
		h.check(Loc.has_key("game.monopoly.phase.%s" % phase), "phase %s is translated" % phase)
	for card: String in MonopolyEngine.CHANCE_CARDS + MonopolyEngine.CHEST_CARDS:
		h.check(Loc.has_key("game.monopoly.card.%s" % card), "card %s is translated" % card)
	for space: String in ["go", "boardwalk", "luxury_tax", "free_parking"]:
		h.check(Loc.has_key("game.monopoly.space.%s" % space), "space %s is translated" % space)
	EngineHarness.check_legal_action_shape(h, engine, "monopoly opening")
	var twin := EngineHarness.create("monopoly", 3, 20260119) as MonopolyEngine
	h.equal(engine.public_state(), twin.public_state(), "the same seed builds the same opening")


# -------------------------------------------------------------------- movement

func _movement(h: TestHarness) -> void:
	var engine := _engine(h)
	var dice := _peek_roll(engine)
	var roll_key := String((engine.legal_actions(0)[0] as Dictionary).get("key", ""))
	h.check(bool(engine.apply_action_by_key(0, roll_key).get("ok", false)), "the first roll is legal")
	h.equal(engine.last_roll, dice, "the roll is recorded")
	h.equal(engine.pos[0], (dice[0] + dice[1]) % 40, "the token moved by the dice total")
	h.equal(engine.turn, 1, "the action counter advanced")

	var go_engine := _engine(h)
	go_engine.pos[0] = 33
	var wrap := _peek_roll(go_engine)
	var wrapped := go_engine.apply_action_by_key(0, String((go_engine.legal_actions(0)[0] as Dictionary).get("key", "")))
	h.check(bool(wrapped.get("ok", false)), "rolling from the last spaces is legal")
	if go_engine.pos[0] < 33:
		h.equal(go_engine.cash[0], 1500 + 200,
			"passing GO pays the salary (%d + %d)" % [wrap[0], wrap[1]])

	var doubles_seed := _seed_with(true)
	var doubles := EngineHarness.create("monopoly", 2, doubles_seed) as MonopolyEngine
	var doubles_key := String((doubles.legal_actions(0)[0] as Dictionary).get("key", ""))
	doubles.apply_action_by_key(0, doubles_key)
	h.equal(doubles.extra_roll, 1, "doubles keep the turn (seed %d)" % doubles_seed)
	h.equal(doubles.decision_player(), 0, "the same player rolls again after doubles")

	var triple := EngineHarness.create("monopoly", 2, doubles_seed) as MonopolyEngine
	triple.doubles_streak = 2
	triple.apply_action_by_key(0, String((triple.legal_actions(0)[0] as Dictionary).get("key", "")))
	h.equal(triple.jailed[0], 1, "a third doubles roll sends the player to jail")
	h.equal(triple.pos[0], 10, "the jailed player stands on the jail space")


# ---------------------------------------------------------- purchase & auction

func _purchase(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.pos[0] = 3
	engine._resolve_landing(0, 7, 0)
	h.equal(engine.phase(), "buy", "landing on an unowned property waits for a decision")
	h.equal(engine.pending_buy, 3, "the pending purchase is Baltic Avenue")
	var keys: Array = []
	for action: Dictionary in engine.legal_actions(0):
		keys.append(String(action.get("type", "")))
	h.check(keys.has("buy") and keys.has("pass_buy"), "buy and pass are offered")
	var buy_key := ""
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "buy":
			buy_key = String(action.get("key", ""))
	h.check(bool(engine.apply_action_by_key(0, buy_key).get("ok", false)), "the purchase applies")
	h.equal(engine.owner[3], 0, "the buyer owns the space")
	h.equal(engine.cash[0], 1500 - 60, "the price is deducted")
	h.equal(engine.decision_player(), 1, "the turn passes after the purchase")

	var poor := _engine(h)
	poor.cash[0] = 10
	poor.pos[0] = 39
	poor._resolve_landing(0, 7, 0)
	var types: Array = []
	for action: Dictionary in poor.legal_actions(0):
		types.append(String(action.get("type", "")))
	h.check(not types.has("buy"), "a player who cannot afford the space is only offered a pass")


func _auction(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.pos[0] = 3
	engine._resolve_landing(0, 7, 0)
	var pass_key := ""
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "pass_buy":
			pass_key = String(action.get("key", ""))
	engine.apply_action_by_key(0, pass_key)
	h.equal(engine.phase(), "auction", "a pass starts the auction")
	h.equal(engine.decision_player(), 0, "the passer bids first")
	var bid_key := ""
	var pass_bid := ""
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "bid" and int(action.get("amount", 0)) == 10:
			bid_key = String(action.get("key", ""))
		elif String(action.get("type", "")) == "pass_bid":
			pass_bid = String(action.get("key", ""))
	h.check(not bid_key.is_empty(), "the minimum bid is offered")
	h.check(not pass_bid.is_empty(), "passing the bid is offered")
	engine.apply_action_by_key(0, pass_bid)
	h.equal(engine.decision_player(), 1, "the other player keeps the auction alive")
	engine.apply_action_by_key(1, bid_key)
	h.equal(engine.phase(), "turn", "the auction closes after the last bid")
	h.equal(engine.owner[3], 1, "the only bidder wins the space")
	h.equal(engine.cash[1], 1490, "the winning bid is paid")

	var dead := _engine(h)
	dead.pos[0] = 3
	dead._resolve_landing(0, 7, 0)
	for action: Dictionary in dead.legal_actions(0):
		if String(action.get("type", "")) == "pass_buy":
			dead.apply_action_by_key(0, String(action.get("key", "")))
			break
	for action: Dictionary in dead.legal_actions(dead.decision_player()):
		if String(action.get("type", "")) == "pass_bid":
			dead.apply_action_by_key(dead.decision_player(), String(action.get("key", "")))
			break
	for action: Dictionary in dead.legal_actions(dead.decision_player()):
		if String(action.get("type", "")) == "pass_bid":
			dead.apply_action_by_key(dead.decision_player(), String(action.get("key", "")))
			break
	h.equal(dead.owner[3], -1, "an auction without bids leaves the space with the bank")

	var disabled := _engine(h, 2, {"auction": false})
	disabled.pos[0] = 3
	disabled._resolve_landing(0, 7, 0)
	for action: Dictionary in disabled.legal_actions(0):
		if String(action.get("type", "")) == "pass_buy":
			disabled.apply_action_by_key(0, String(action.get("key", "")))
			break
	h.equal(disabled.phase(), "turn", "with auctions off the pass ends the purchase step")
	h.equal(disabled.owner[3], -1, "nobody gets the space when auctions are off")


# ----------------------------------------------------------------------- rents

func _rent(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.owner[1] = 1
	engine.pos[0] = 1
	engine._resolve_landing(0, 5, 0)
	h.equal(engine.cash[0], 1500 - 2, "the base rent is paid")
	h.equal(engine.cash[1], 1500 + 2, "the owner receives the rent")

	var group := _engine(h)
	group.owner[1] = 1
	group.owner[3] = 1
	group.pos[0] = 1
	group._resolve_landing(0, 5, 0)
	h.equal(group.cash[0], 1500 - 4, "a full colour group doubles the base rent")

	var railroad := _engine(h)
	railroad.owner[5] = 1
	railroad.owner[15] = 1
	railroad.pos[0] = 5
	railroad._resolve_landing(0, 5, 0)
	h.equal(railroad.cash[0], 1500 - 50, "two railroads charge 50")
	railroad.owner[25] = 1
	railroad.owner[35] = 1
	railroad.pos[0] = 25
	railroad._resolve_landing(0, 5, 0)
	h.equal(railroad.cash[0], 1500 - 50 - 200, "four railroads charge 200")

	var utility := _engine(h)
	utility.owner[12] = 1
	utility.pos[0] = 12
	utility._resolve_landing(0, 8, 0)
	h.equal(utility.cash[0], 1500 - 32, "one utility charges four times the dice")
	utility.owner[28] = 1
	utility.pos[0] = 28
	utility._resolve_landing(0, 8, 0)
	h.equal(utility.cash[0], 1500 - 32 - 80, "both utilities charge ten times the dice")

	var built := _engine(h)
	built.owner[1] = 1
	built.houses[1] = 1
	built.pos[0] = 1
	built._resolve_landing(0, 5, 0)
	h.equal(built.cash[0], 1500 - 10, "a house raises the rent")
	built.houses[1] = 5
	built.cash[0] = 1500
	built._resolve_landing(0, 5, 0)
	h.equal(built.cash[0], 1500 - 250, "a hotel raises the rent further")

	var tax := _engine(h)
	tax.pos[0] = 4
	tax._resolve_landing(0, 7, 0)
	h.equal(tax.cash[0], 1500 - 200, "income tax costs 200")
	tax.pos[0] = 38
	tax._resolve_landing(0, 7, 0)
	h.equal(tax.cash[0], 1500 - 200 - 100, "luxury tax costs 100")


# ---------------------------------------------------------------------- houses

func _houses(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.owner[1] = 0
	h.equal(_build_keys(engine, 1).size(), 0, "no house may be built without the full colour group")
	engine.owner[3] = 0
	h.equal(_build_keys(engine, 1).size(), 1, "the full group unlocks building")
	var key: String = _build_keys(engine, 1)[0]
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "building a house applies")
	h.equal(engine.houses[1], 1, "the house is placed")
	h.equal(engine.cash[0], 1500 - 50, "the house cost is paid")
	h.equal(_build_keys(engine, 1).size(), 0, "the even-build rule forbids a second house next door")
	h.equal(_build_keys(engine, 3).size(), 1, "the partner may catch up")
	var second: String = _build_keys(engine, 3)[0]
	engine.apply_action_by_key(0, second)
	h.equal(engine.houses[3], 1, "both sides now have one house")
	h.equal(_build_keys(engine, 1).size(), 1, "the pair may now go up together")
	engine.houses[1] = 4
	engine.houses[3] = 4
	var hotel_key: String = _build_keys(engine, 1)[0]
	engine.apply_action_by_key(0, hotel_key)
	h.equal(engine.houses[1], 5, "the fifth house is a hotel")
	h.equal(_build_keys(engine, 1).size(), 0, "a hotel cannot be upgraded further")


func _build_keys(engine: MonopolyEngine, space: int) -> Array:
	var out: Array = []
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "build_house" and int(action.get("space", -1)) == space:
			out.append(String(action.get("key", "")))
	return out


# ------------------------------------------------------------------------ jail

func _jail(h: TestHarness) -> void:
	var engine := _engine(h)
	engine._send_to_jail(0)
	h.equal(engine.phase(), "jail", "being jailed shows the jail phase")
	var types: Array = []
	for action: Dictionary in engine.legal_actions(0):
		types.append(String(action.get("type", "")))
	h.check(types.has("pay_fine"), "the fine is offered")
	h.check(types.has("roll"), "trying for doubles is offered")
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "pay_fine":
			engine.apply_action_by_key(0, String(action.get("key", "")))
			break
	h.equal(engine.cash[0], 1450, "the fine leaves the wallet")
	h.equal(engine.jailed[0], 0, "paying the fine releases the player")
	h.equal(engine.phase(), "turn", "the player may now roll normally")

	var carded := _engine(h)
	carded._send_to_jail(0)
	carded.jail_cards[0] = 1
	for action: Dictionary in carded.legal_actions(0):
		if String(action.get("type", "")) == "use_card":
			carded.apply_action_by_key(0, String(action.get("key", "")))
			break
	h.equal(carded.jailed[0], 0, "the jail card releases the player")
	h.equal(carded.jail_cards[0], 0, "the card is consumed")

	var failed := _engine(h)
	failed._send_to_jail(0)
	failed.cash[0] = 10
	var failed_types: Array = []
	for action: Dictionary in failed.legal_actions(0):
		failed_types.append(String(action.get("type", "")))
	h.check(not failed_types.has("pay_fine"), "a player who cannot pay is not offered the fine")
	var peek := _peek_roll(failed)
	failed.apply_action_by_key(0, String((failed.legal_actions(0)[0] as Dictionary).get("key", "")))
	if peek[0] == peek[1]:
		h.equal(failed.jailed[0], 0, "doubles release the player from jail")
	else:
		h.equal(failed.jail_rolls[0], 1, "a failed attempt is counted")
		h.equal(failed.jailed[0], 1, "a failed attempt keeps the player in jail")


# ----------------------------------------------------------------------- cards

func _cards(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.cash[0] = 0
	engine._apply_card_effect(0, "dividend", 7, 0)
	h.equal(engine.cash[0], 50, "the dividend card pays out")
	engine.pos[0] = 30
	engine._apply_card_effect(0, "advance_go", 7, 0)
	h.equal(engine.pos[0], 0, "advance to GO moves the token")
	h.equal(engine.cash[0], 250, "advance to GO collects the salary")
	engine._apply_card_effect(0, "go_jail", 7, 0)
	h.equal(engine.jailed[0], 1, "the go-to-jail card works")

	var jail_free := _engine(h)
	var deck_size := jail_free.chance_deck.size()
	jail_free.chance_deck.push_front("jail_free")
	jail_free._draw_card(0, jail_free.chance_deck, 7, 0)
	h.equal(jail_free.jail_cards[0], 1, "a jail-free card is kept")
	h.equal(jail_free.chance_deck.size(), deck_size, "the kept card leaves the deck")

	var repairs := _engine(h)
	repairs.owner[1] = 0
	repairs.houses[1] = 2
	repairs.owner[3] = 0
	repairs.houses[3] = 5
	repairs._apply_card_effect(0, "street_repairs", 7, 0)
	h.equal(repairs.cash[0], 1500 - 2 * 40 - 115, "street repairs charge per house and hotel")

	var deck_a := _engine(h)
	var deck_b := _engine(h)
	h.equal(deck_a.chance_deck, deck_b.chance_deck, "the same seed shuffles the same chance deck")
	h.equal(deck_a.chest_deck, deck_b.chest_deck, "the same seed shuffles the same chest deck")


# --------------------------------------------------------------------- trading

func _trading(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.owner[1] = 0
	engine.owner[3] = 1
	var offer := _find_trade(engine, 1, 1, 3, 0)
	h.check(not offer.is_empty(), "a one-for-one trade is offered")
	h.check(bool(engine.apply_action_by_key(0, offer).get("ok", false)), "the offer applies")
	h.equal(engine.phase(), "trade", "the responder now decides")
	h.equal(engine.decision_player(), 1, "the responder is the second player")
	h.check(bool(engine.private_state(1).has("trade_offer")), "the responder sees the offer")
	h.check(bool(engine.private_state(0).has("trade_offer")), "the offerer sees their own offer")
	for action: Dictionary in engine.legal_actions(1):
		if String(action.get("type", "")) == "accept_trade":
			engine.apply_action_by_key(1, String(action.get("key", "")))
			break
	h.equal(engine.owner[1], 1, "the traded space changed hands")
	h.equal(engine.owner[3], 0, "the other space changed hands")
	h.equal(engine.phase(), "turn", "the offerer may continue the turn")

	var declined := _engine(h)
	declined.owner[1] = 0
	declined.owner[3] = 1
	declined.apply_action_by_key(0, _find_trade(declined, 1, 1, 3, 0))
	for action: Dictionary in declined.legal_actions(1):
		if String(action.get("type", "")) == "decline_trade":
			declined.apply_action_by_key(1, String(action.get("key", "")))
			break
	h.equal(declined.owner[1], 0, "a declined trade changes nothing")
	h.equal(declined.phase(), "turn", "a declined trade returns the turn to the offerer")

	var cash_offer := _engine(h)
	cash_offer.owner[3] = 1
	var cash_key := _find_trade(cash_offer, 1, -1, 3, 60)
	h.check(not cash_key.is_empty(), "a cash-only offer is offered")
	cash_offer.apply_action_by_key(0, cash_key)
	for action: Dictionary in cash_offer.legal_actions(1):
		if String(action.get("type", "")) == "accept_trade":
			cash_offer.apply_action_by_key(1, String(action.get("key", "")))
			break
	h.equal(cash_offer.owner[3], 0, "the buyer receives the space")
	h.equal(cash_offer.cash[1], 1560, "the seller receives the cash")


func _find_trade(engine: MonopolyEngine, to: int, give: int, take: int, cash: int) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) != "propose_trade":
			continue
		if int(action.get("to", -1)) == to and int(action.get("give", -2)) == give \
				and int(action.get("take", -2)) == take and int(action.get("cash", -1)) == cash:
			return String(action.get("key", ""))
	return ""


# ------------------------------------------------------------------ bankruptcy

func _bankruptcy(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.owner[39] = 0
	engine.houses[39] = 5
	engine.cash[1] = 10
	engine.pos[1] = 39
	engine._resolve_landing(1, 7, 0)
	h.check(engine.finished, "an unpaid hotel rent ends the match")
	h.equal(engine.winner_index(), 0, "the creditor wins")
	h.equal(String(engine.result.get("reason_key", "")), "game.monopoly.reason.last_standing",
		"the reason is the last player standing")
	h.equal(engine.bankrupt[1], 1, "the debtor is bankrupt")
	h.equal(engine.owner[39], 0, "the creditor keeps the space")

	var to_bank := _engine(h, 3)
	to_bank.cash[0] = 0
	to_bank.pos[0] = 4
	to_bank._resolve_landing(0, 7, 0)
	h.check(not to_bank.finished, "with three players the match continues")
	h.equal(to_bank.bankrupt[0], 1, "the player who cannot pay the tax is bankrupt")
	h.equal(to_bank.active, 1, "the turn moves to the next solvent player")

	var liquidate := _engine(h, 3)
	liquidate.owner[1] = 0
	liquidate.owner[3] = 0
	liquidate.houses[1] = 2
	liquidate.cash[0] = 0
	liquidate.pos[0] = 4
	liquidate._resolve_landing(0, 7, 0)
	h.equal(liquidate.cash[0], 0, "houses are sold at half price before the tax is paid")
	h.equal(liquidate.bankrupt[0], 1, "what remains unpaid bankrupts the player")


# --------------------------------------------------------------------- endings

func _endings(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.cash[0] = 5000
	engine.cash[1] = 0
	engine._finish_by_net_worth("game.monopoly.reason.turn_cap")
	h.check(engine.finished, "the turn cap ends the match")
	h.equal(String(engine.result.get("reason_key", "")), "game.monopoly.reason.turn_cap", "the cap is the reason")
	h.equal(engine.winner_index(), 0, "the richest player wins at the cap")
	h.check(engine.legal_actions(0).is_empty(), "a finished match offers no actions")


# --------------------------------------------------------------------- illegal

func _illegal(h: TestHarness) -> void:
	var engine := _engine(h)
	var roll := String((engine.legal_actions(0)[0] as Dictionary).get("key", ""))
	h.equal(String(engine.apply_action_by_key(1, roll).get("error_key", "")), "game.common.not_your_turn",
		"acting out of turn is rejected")
	h.equal(String(engine.apply_action_by_key(0, "type=bogus").get("error_key", "")), "game.common.illegal_action",
		"an unknown action key is rejected")
	var forged := {"type": "build_house", "space": 1, "key": "type=build_house|space=1"}
	h.equal(String(engine.apply_action(forged).get("error_key", "")), "game.monopoly.error.illegal_action",
		"a forged build is rejected by apply_action")


func _determinism(h: TestHarness) -> void:
	var first := _engine(h)
	var second := _engine(h)
	for step: int in range(20):
		var actor := first.decision_player()
		var key: String = BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same actions give the same state")


func _snapshot(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	for step: int in range(6):
		if engine.finished:
			break
		var actor := engine.decision_player()
		engine.apply_action_by_key(actor, BotDirector.choose_action(engine, actor))
	EngineHarness.check_snapshot_round_trip(h, engine, "monopoly")
	EngineHarness.check_legal_action_shape(h, engine, "monopoly mid-game")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	engine.owner[1] = 0
	engine.owner[3] = 1
	engine.apply_action_by_key(0, _find_trade(engine, 1, 1, 3, 0))
	var marker: Dictionary = engine.public_state().get("trade", {})
	var parties: Array = [int(marker.get("from", -1)), int(marker.get("to", -2))]
	h.equal(parties, [0, 1], "the pending trade is announced publicly")
	for player: int in range(engine.player_count()):
		var view := engine.private_state(player)
		if parties.has(player):
			h.check(view.has("trade_offer"), "player %d negotiates with the terms in hand" % player)
		else:
			h.check(view.is_empty(), "player %d cannot see the terms" % player)
	h.equal(engine.private_state(1).get("trade_offer", {}), engine.private_state(0).get("trade_offer", {}),
		"both sides of the table read the same offer")
	EngineHarness.check_privacy(h, engine, func(theirs: Dictionary, mine: Dictionary) -> Array:
		# Two private views may only overlap when both hold the very same shared
		# offer (the two negotiating players); anything else would be a leak.
		if not mine.is_empty() and not theirs.is_empty() and mine != theirs:
			return ["trade_offer"]
		return []
	, "monopoly trade")
	for action: Dictionary in engine.legal_actions(1):
		if String(action.get("type", "")) == "decline_trade":
			engine.apply_action_by_key(1, String(action.get("key", "")))
			break
	h.check(engine.private_state(0).is_empty() and engine.private_state(1).is_empty(),
		"declining the trade wipes the private terms")


# ------------------------------------------------------------------- bot match

func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 3, {"turn_cap": 60})
	var steps := EngineHarness.play_out(engine, 20000)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "a bot-only match reaches an end")
	h.check(not String(engine.result.get("reason_key", "")).is_empty(), "the finished match explains itself")
	h.check(engine.winner_index() >= -1, "the result names a winner or a draw")
	h.greater(float(engine.move_log.size()), 10.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
	var survivor := 0
	for i: int in range(engine.player_count()):
		if engine.bankrupt[i] == 0:
			survivor += 1
	var reason := String(engine.result.get("reason_key", ""))
	h.check(reason == "game.monopoly.reason.turn_cap" or reason == "game.monopoly.reason.last_standing"
		or reason == "game.monopoly.reason.all_bankrupt", "the end reason belongs to Monopoly")
	if reason == "game.monopoly.reason.last_standing":
		h.equal(survivor, 1, "the last-standing reason leaves exactly one solvent player")
