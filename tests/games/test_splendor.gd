extends RefCounted
## Splendor rules suite: the token economy, cards, nobles, the ending and the
## engine invariants (determinism, snapshots, hidden reserves, finite matches).
##
## The suite is white box on purpose: scenarios that the shuffled market only
## offers rarely (a specific card, a nearly full reserve, a dead board) are built
## by staging a card onto the market and moving tokens out of the supply with the
## helpers at the bottom. Every staged edit uses the engine's own fields, so the
## rest of the state stays exactly as a real match would have it.

const TABLE_CARDS: int = 90
const TIER_CARDS: Array[int] = [40, 30, 20]
const TIER_POINTS: Array[int] = [5, 55, 80]
const TIER_BONUSES: Array[int] = [8, 6, 4]


func suite_name() -> String:
	return "splendor rules"


func run(h: TestHarness) -> void:
	_dataset(h)
	_opening(h)
	_taking(h)
	_reserving(h)
	_buying(h)
	_token_limit(h)
	_nobles(h)
	_endings(h)
	_illegal_actions(h)
	_snapshots(h)
	_privacy(h)
	_bot_match(h)


# ------------------------------------------------------------------- datasets

## The card and noble tables are the rules: verify the standard distribution.
func _dataset(h: TestHarness) -> void:
	h.equal(SplendorEngine.CARDS.size(), TABLE_CARDS, "the standard game has ninety development cards")
	h.equal(SplendorEngine.GEM_COLOURS.size(), 5, "five gem colours")
	h.equal(SplendorEngine.NOBLES.size(), 10, "ten noble tiles")
	var tier_counts: Array[int] = [0, 0, 0]
	var tier_points: Array[int] = [0, 0, 0]
	var per_colour: Dictionary = {}
	var signatures: Dictionary = {}
	for card: Dictionary in SplendorEngine.CARDS:
		var tier := int(card.get("tier", 0))
		if tier < 1 or tier > 3:
			h.check(false, "card with tier %d" % tier)
			continue
		tier_counts[tier - 1] += 1
		tier_points[tier - 1] += int(card.get("points", 0))
		var bonus := str(card.get("bonus", ""))
		h.check(SplendorEngine.GEM_COLOURS.has(bonus), "every card awards one of the five bonuses")
		var key := "%d|%s" % [tier, bonus]
		per_colour[key] = int(per_colour.get(key, 0)) + 1
		var cost: Array = card.get("cost", [])
		h.equal(cost.size(), SplendorEngine.GEM_COLOURS.size(), "every cost has five entries")
		var signature := "%d/%s/%d/%s" % [tier, bonus, int(card.get("points", 0)), str(cost)]
		h.check(not signatures.has(signature), "card signature %s is unique" % signature)
		signatures[signature] = true
	for tier: int in range(3):
		h.equal(tier_counts[tier], TIER_CARDS[tier], "tier %d holds %d cards" % [tier + 1, TIER_CARDS[tier]])
		h.equal(tier_points[tier], TIER_POINTS[tier], "tier %d is worth %d points in total" % [tier + 1, TIER_POINTS[tier]])
		for colour: String in SplendorEngine.GEM_COLOURS:
			h.equal(int(per_colour.get("%d|%s" % [tier + 1, colour], 0)), TIER_BONUSES[tier],
				"tier %d holds %d %s cards" % [tier + 1, TIER_BONUSES[tier], colour])
	for noble: Dictionary in SplendorEngine.NOBLES:
		h.equal(int(noble.get("points", 0)), 3, "every noble is worth three points")
		var cost: Array = noble.get("cost", [])
		h.equal(cost.size(), SplendorEngine.GEM_COLOURS.size(), "noble requirements use the card order")
		for value: Variant in cost:
			h.check(int(value) >= 0 and int(value) <= 4, "a noble never demands more than four bonuses of one colour")


# -------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var first := _engine(h, 2)
	h.equal(first.player_count(), 2, "two players")
	h.equal(first.phase(), "playing", "the match starts in the playing phase")
	h.equal(first.decision_player(), 0, "player one moves first")
	var table := first as SplendorEngine
	h.equal(table.target_points, SplendorEngine.DEFAULT_TARGET_POINTS, "fifteen points win by default")
	h.equal(table.piles.size(), SplendorEngine.ALL_COLOURS.size(), "five gems plus the jokers")
	for colour: String in SplendorEngine.GEM_COLOURS:
		h.equal(table.pile(colour), SplendorEngine.PILE_SIZES[0], "two players share four %s" % colour)
	h.equal(table.pile(SplendorEngine.GOLD), SplendorEngine.GOLD_PILE, "five jokers")
	h.equal(table.market.size(), 3, "three market rows")
	h.equal((table.market[0] as Array).size(), SplendorEngine.MARKET_SIZE, "each row offers four cards")
	h.equal((table.decks[0] as Array).size(), TIER_CARDS[0] - SplendorEngine.MARKET_SIZE, "the rest of tier one stays in the deck")
	h.equal((table.decks[1] as Array).size(), TIER_CARDS[1] - SplendorEngine.MARKET_SIZE, "the rest of tier two stays in the deck")
	h.equal((table.decks[2] as Array).size(), TIER_CARDS[2] - SplendorEngine.MARKET_SIZE, "the rest of tier three stays in the deck")
	h.equal(table.nobles.size(), 3, "two players reveal three nobles")
	h.equal(table.private_state(0).get("reserved", []), [], "nobody has reserved a card yet")
	EngineHarness.check_legal_action_shape(h, first, "opening")
	h.equal(first.legal_actions(0).size(), 30, "fifteen gem takes and fifteen reservations are offered")
	h.equal(_count_type(first, 0, "take"), 15, "ten three-gem combinations plus five double takes")
	h.equal(_count_type(first, 0, "buy"), 0, "nothing is affordable before the first gems are taken")

	# The same seed must deal the same table and offer the same actions.
	var second := _engine(h, 2)
	h.equal(second.public_state(), first.public_state(), "the same seed deals the same table")
	h.equal(_keys(second, 0), _keys(first, 0), "and offers the same actions")
	var different := _engine(h, 2, {}, 987654)
	h.not_equal((different as SplendorEngine).decks[2], table.decks[2], "another seed shuffles the decks differently")

	# Player counts change the piles and the number of revealed nobles.
	var three := _engine(h, 3)
	h.equal((three as SplendorEngine).pile("white"), SplendorEngine.PILE_SIZES[1], "three players share five gems per colour")
	h.equal((three as SplendorEngine).nobles.size(), 4, "three players reveal four nobles")
	var four := _engine(h, 4)
	h.equal((four as SplendorEngine).pile("black"), SplendorEngine.PILE_SIZES[2], "four players share seven gems per colour")
	h.equal((four as SplendorEngine).nobles.size(), 5, "four players reveal five nobles")

	# A scripted opening keeps both engines in step.
	for step: int in range(4):
		_act(h, first)
		_act(h, second)
	h.equal(second.public_state(), first.public_state(), "the same actions keep two engines in step")
	EngineHarness.check_snapshot_round_trip(h, first, "after the opening")


# --------------------------------------------------------------------- taking

func _taking(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	var take := _find_key(engine, 0, "take", {"take": "black,blue,white"})
	h.check(not take.is_empty(), "three different gems are offered")
	h.check(bool(engine.apply_action_by_key(0, take).get("ok", false)), "the take applies")
	h.equal(int(table.tokens[0].get("white", 0)), 1, "one white gem arrives")
	h.equal(int(table.tokens[0].get("blue", 0)), 1, "one blue gem arrives")
	h.equal(int(table.tokens[0].get("black", 0)), 1, "one black gem arrives")
	h.equal(int(table.tokens[0].get("red", 0)), 0, "no ruby arrives")
	h.equal(table.pile("white"), SplendorEngine.PILE_SIZES[0] - 1, "the supply shrinks")
	h.equal(engine.decision_player(), 1, "the turn passes on")
	h.check(_log_has(engine, "game.splendor.log_take.other"), "a multi-gem take is logged")

	# Two of the same colour need a pile of at least four.
	var double := _find_key(engine, 1, "take", {"take": "green,green"})
	h.check(not double.is_empty(), "a pile of four still offers the double take")
	h.check(bool(engine.apply_action_by_key(1, double).get("ok", false)), "the double take applies")
	h.equal(int(table.tokens[1].get("green", 0)), 2, "two emeralds change hands")
	h.equal(table.pile("green"), SplendorEngine.PILE_SIZES[0] - 2, "the pile is down to two")
	h.check(_find_key(engine, 0, "take", {"take": "white,white"}).is_empty(), "a pile of three offers no double take")
	EngineHarness.check_legal_action_shape(h, engine, "mid taking")

	# Rejections: everything is validated again when the action is applied.
	var illegal := _engine(h, 2)
	var before := illegal.public_state()
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": "gold,gold"})).get("error_key", "")),
		"game.splendor.error.take_invalid", "gold is never taken from the supply")
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": "white,white,blue"})).get("error_key", "")),
		"game.splendor.error.take_invalid", "a colour may not repeat in a three-gem take")
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": "white,blue"})).get("error_key", "")),
		"game.splendor.error.take_size", "two different gems are only legal when the supply is thin")
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": "white,blue,green,red"})).get("error_key", "")),
		"game.splendor.error.take_invalid", "at most three gems may be taken")
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": ""})).get("error_key", "")),
		"game.splendor.error.take_invalid", "an empty take is refused")
	h.equal(str(illegal.apply_action(GameEngine.make_action("take", {"take": "purple"})).get("error_key", "")),
		"game.splendor.error.take_invalid", "an unknown colour is refused")
	h.equal(illegal.public_state(), before, "a rejected take leaves the table untouched")

	# Taking a colour whose pile is empty fails as a supply problem, and the
	# double take disappears with it.
	var drained := _engine(h, 2)
	var drained_table := drained as SplendorEngine
	drained.apply_action_by_key(0, _find_key(drained, 0, "take", {"take": "white,white"}))
	drained.apply_action_by_key(1, _find_key(drained, 1, "take", {"take": "blue,green,white"}))
	drained.apply_action_by_key(0, _find_key(drained, 0, "take", {"take": "blue,green,white"}))
	h.equal(drained_table.pile("white"), 0, "a double take and two single takes drain a pile of four")
	h.check(_find_key(drained, 1, "take", {"take": "white,white"}).is_empty(), "an empty pile offers no double take")
	h.equal(str(drained.apply_action(GameEngine.make_action("take", {"take": "black,blue,white"})).get("error_key", "")),
		"game.splendor.error.take_gems", "and no gem of that colour can be taken")

	# When the supply is down to one colour, the take shrinks and the log turns
	# singular.
	var thin := _engine(h, 2)
	var thin_table := thin as SplendorEngine
	for colour: String in SplendorEngine.GEM_COLOURS:
		if colour != "black":
			thin_table.piles[colour] = 0
	var last := _find_key(thin, 0, "take", {"take": "black"})
	h.check(not last.is_empty(), "the last colour in the supply can be taken alone")
	h.check(bool(thin.apply_action_by_key(0, last).get("ok", false)), "and the take applies")
	h.equal(int(thin_table.tokens[0].get("black", 0)), 1, "one onyx changes hands")
	h.check(_log_has(thin, "game.splendor.log_take.one"), "a single gem is logged in the singular")


# ------------------------------------------------------------------ reserving

func _reserving(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	var card_id := _first_market_card(table, 0)
	var deck_size := (table.decks[0] as Array).size()
	var reserve := _find_key(engine, 0, "reserve", {"card": card_id})
	h.check(not reserve.is_empty(), "the first tier one card can be reserved")
	h.check(bool(engine.apply_action_by_key(0, reserve).get("ok", false)), "the reservation applies")
	h.equal(table.reserved_count(0), 1, "the card lies in the reserve")
	h.equal(int((table.reserved[0] as Array)[0]), card_id, "and it is the chosen card")
	h.equal(int(table.tokens[0].get(SplendorEngine.GOLD, 0)), 1, "reserving pays a gold joker")
	h.equal(table.pile(SplendorEngine.GOLD), SplendorEngine.GOLD_PILE - 1, "the joker leaves the supply")
	h.equal((table.decks[0] as Array).size(), deck_size - 1, "a replacement is drawn for the empty slot")
	h.check(not (table.market[0] as Array).has(card_id), "the card left the market")
	h.check(_log_has(engine, "game.splendor.log_reserve_gold"), "the reserve with gold is logged")
	h.equal(table.private_state(0).get("reserved", []), [card_id], "the owner sees the reserve")
	h.equal(table.private_state(1).get("reserved", []), [], "the opponent does not")
	h.check(not engine.public_state().has("reserved"), "the public snapshot carries no reserve lists")

	# The blind reserve takes the top of a deck.
	var blind := _find_key(engine, 1, "reserve", {"tier": 2, "blind": true})
	h.check(not blind.is_empty(), "the top of the tier two deck can be reserved")
	var top := int((table.decks[1] as Array)[0])
	h.check(bool(engine.apply_action_by_key(1, blind).get("ok", false)), "the blind reservation applies")
	h.equal(int((table.reserved[1] as Array)[0]), top, "the drawn card is the top of the deck")
	h.equal(int(table.tokens[1].get(SplendorEngine.GOLD, 0)), 1, "a joker comes with it")

	# Fill both reserves; a fourth card is not offered and not accepted.
	for round_index: int in range(3):
		for player: int in range(2):
			if table.reserved_count(player) >= SplendorEngine.MAX_RESERVED:
				continue
			var id := _first_market_card(table, 2)
			var key := _find_key(engine, player, "reserve", {"card": id})
			h.check(not key.is_empty(), "player %d may reserve a card (%d)" % [player, round_index])
			h.check(bool(engine.apply_action_by_key(player, key).get("ok", false)), "the reservation applies")
	h.equal(table.reserved_count(0), SplendorEngine.MAX_RESERVED, "three cards are the maximum")
	h.equal(_count_type(engine, 0, "reserve"), 0, "a full reserve offers no reservation")
	var overfull := engine.apply_action(GameEngine.make_action("reserve", {"card": _first_market_card(table, 0)}))
	h.equal(str(overfull.get("error_key", "")), "game.splendor.error.reserve_full", "a fourth card is refused")

	# An exhausted deck leaves an empty market slot; it is not a card.
	var drained := _engine(h, 2)
	var drained_table := drained as SplendorEngine
	(drained_table.decks[0] as Array).clear()
	var last_card := _first_market_card(drained_table, 0)
	var last_key := _find_key(drained, 0, "reserve", {"card": last_card})
	h.check(bool(drained.apply_action_by_key(0, last_key).get("ok", false)), "the last market card can still be reserved")
	h.equal(int((drained_table.market[0] as Array)[0]), -1, "an exhausted deck leaves an empty slot")
	h.check(_find_key(drained, 1, "reserve", {"tier": 1, "blind": true}).is_empty(), "an empty deck offers no blind reserve")
	var untouched := drained.public_state()
	h.equal(str(drained.apply_action(GameEngine.make_action("reserve", {"card": -1})).get("error_key", "")),
		"game.splendor.error.no_card", "the empty slot is not a card")
	h.equal(drained.public_state(), untouched, "and a rejected reservation does not touch the board")


# --------------------------------------------------------------------- buying

func _buying(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine

	# --- exact payment for a specific card ---
	var red_card := _card_with(h, "red", [3, 0, 0, 0, 0])
	var tier := int(table.card_data(red_card).get("tier", 1)) - 1
	_stage(table, red_card)
	var refill := int((table.decks[tier] as Array)[0])
	var deck_size := (table.decks[tier] as Array).size()
	_give(h, engine, 0, {"white": 3})
	var key := _find_key(engine, 0, "buy", {"card": red_card})
	h.check(not key.is_empty(), "three white gems buy the red card")
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "the purchase applies")
	h.equal(int(table.tokens[0].get("white", 0)), 0, "the tokens are spent")
	h.equal(table.pile("white"), SplendorEngine.PILE_SIZES[0], "and return to the supply")
	h.equal(int(table.bonuses[0].get("red", 0)), 1, "the card grants a red bonus")
	h.equal(int(table.card_counts[0]), 1, "the card counts towards the tiebreak")
	h.equal(int(table.points[0]), 0, "a tier one card is worth no points")
	h.equal(int((table.market[tier] as Array)[0]), refill, "the market slot is refilled from the deck")
	h.equal((table.decks[tier] as Array).size(), deck_size - 1, "the deck shrinks")
	h.check(_log_has(engine, "game.splendor.log_buy"), "the purchase is logged")

	# --- the bonus discounts a later card of that colour ---
	_act(h, engine)
	var ruby_card := _card_with(h, "green", [0, 0, 0, 3, 0])
	_stage(table, ruby_card)
	h.check(_find_key(engine, 0, "buy", {"card": ruby_card}).is_empty(), "one red bonus alone does not pay three rubies")
	_give(h, engine, 0, {"red": 2})
	var discounted := _find_key(engine, 0, "buy", {"card": ruby_card})
	h.check(not discounted.is_empty(), "a red bonus and two rubies pay for three")
	h.check(bool(engine.apply_action_by_key(0, discounted).get("ok", false)), "the discounted purchase applies")
	h.equal(int(table.tokens[0].get("red", 0)), 0, "both rubies are spent")
	h.equal(table.pile("red"), SplendorEngine.PILE_SIZES[0], "…and return to the supply")
	h.equal(int(table.bonuses[0].get("green", 0)), 1, "the second bonus arrives")

	# --- gold substitutes for missing gems ---
	_act(h, engine)
	var onyx_card := _card_with(h, "blue", [0, 0, 0, 0, 3])
	_stage(table, onyx_card)
	_give(h, engine, 0, {"black": 1, "gold": 2})
	var joker := _find_key(engine, 0, "buy", {"card": onyx_card})
	h.check(not joker.is_empty(), "one onyx and two jokers pay for three onyx")
	h.check(bool(engine.apply_action_by_key(0, joker).get("ok", false)), "the purchase with jokers applies")
	h.equal(int(table.tokens[0].get("black", 0)), 0, "the onyx is spent")
	h.equal(int(table.tokens[0].get("gold", 0)), 0, "both jokers are spent")
	h.equal(table.pile(SplendorEngine.GOLD), SplendorEngine.GOLD_PILE, "the jokers return to the supply")
	h.equal(int(table.bonuses[0].get("blue", 0)), 1, "the blue bonus arrives")

	# --- a reserved card can be bought, but only by its owner ---
	var stolen := _first_market_card(table, 2)
	var steal_key := _find_key(engine, 1, "reserve", {"card": stolen})
	h.check(bool(engine.apply_action_by_key(1, steal_key).get("ok", false)), "player two reserves a card")
	h.check(_find_key(engine, 0, "buy", {"card": stolen}).is_empty(), "the opponent is not offered the reserved card")
	h.equal(str(engine.apply_action(GameEngine.make_action("buy", {"card": stolen})).get("error_key", "")),
		"game.splendor.error.not_your_card", "and buying it is refused")

	# --- player one buys their own reserve on a later turn ---
	var own := _card_with(h, "white", [0, 0, 0, 2, 1])
	_stage(table, own)
	engine.apply_action_by_key(0, _find_key(engine, 0, "reserve", {"card": own}))
	_act(h, engine)
	_give(h, engine, 0, {"gold": 3})
	var from_reserve := _find_key(engine, 0, "buy", {"card": own})
	h.check(not from_reserve.is_empty(), "a reserved card is offered for purchase")
	h.check(bool(engine.apply_action_by_key(0, from_reserve).get("ok", false)), "the reserved card is bought")
	h.equal(table.reserved_count(0), 0, "the reserve is empty again")
	h.equal(int(table.card_counts[0]), 4, "the card counts as a purchase")
	h.equal(int(table.bonuses[0].get(str(table.card_data(own).get("bonus", "")), 0)), 1, "its bonus arrives")

	# --- refusals ---
	var hidden := int((table.decks[2] as Array)[0])
	h.equal(str(engine.apply_action(GameEngine.make_action("buy", {"card": hidden})).get("error_key", "")),
		"game.splendor.error.not_your_card", "a card still in a deck cannot be bought")
	var pricey := _first_market_card(table, 2)
	h.equal(str(engine.apply_action(GameEngine.make_action("buy", {"card": pricey})).get("error_key", "")),
		"game.splendor.error.cannot_afford", "a card beyond the player's means is refused")


# ----------------------------------------------------------------- token limit

func _token_limit(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	_give(h, engine, 0, {"white": 4, "blue": 3, "green": 2})
	var key := _find_key(engine, 0, "take", {"take": "black,blue,red"})
	h.check(not key.is_empty(), "three more gems are offered")
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "the take pushes the hand to twelve")
	h.equal(table.token_total(0), SplendorEngine.TOKEN_LIMIT, "the engine returns the surplus automatically")
	h.equal(int(table.tokens[0].get("white", 0)), 3, "the most abundant colour is returned first")
	h.equal(int(table.tokens[0].get("blue", 0)), 3, "then the next most abundant")
	h.equal(int(table.tokens[0].get("green", 0)), 2, "the middle colour is kept")
	h.equal(int(table.tokens[0].get("black", 0)), 1, "the new onyx is kept")
	h.equal(int(table.tokens[0].get("red", 0)), 1, "the new ruby is kept")
	h.equal(table.pile("white"), 1, "the returned white gem is back in the supply")
	h.equal(table.pile("blue"), 1, "the returned blue gem too")
	h.check(_log_has(engine, "game.splendor.log_return.other"), "the return is logged")

	# A tie with gold keeps the gold: it is returned only when it is strictly the
	# most abundant colour.
	var tied := _engine(h, 2)
	var tied_table := tied as SplendorEngine
	_give(h, tied, 0, {"gold": 3, "white": 3, "blue": 2, "green": 2})
	var tied_key := _find_key(tied, 0, "take", {"take": "black,red,white"})
	h.check(bool(tied.apply_action_by_key(0, tied_key).get("ok", false)), "the take applies")
	h.equal(tied_table.token_total(0), SplendorEngine.TOKEN_LIMIT, "the hand returns to ten tokens")
	h.check(int(tied_table.tokens[0].get("gold", 0)) < 3, "a strictly most abundant gold pile is returned")
	h.equal(_tokens_conserved(tied), true, "and every gem stays somewhere on the table")


# --------------------------------------------------------------------- nobles

func _nobles(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	h.equal(table.nobles.size(), 3, "two players reveal three nobles")
	# Four bonuses of every colour satisfy every revealed noble at once, which
	# pins down the "first noble in reveal order visits" simplification.
	var all_bonuses: Dictionary = {}
	for colour: String in SplendorEngine.GEM_COLOURS:
		all_bonuses[colour] = 4
	_grant_bonus(engine, 0, all_bonuses)
	var first_card := _card_with(h, "white", [0, 0, 0, 2, 1])
	_stage(table, first_card)
	var first_key := _find_key(engine, 0, "buy", {"card": first_card})
	h.check(not first_key.is_empty(), "the first card is affordable")
	h.check(bool(engine.apply_action_by_key(0, first_key).get("ok", false)), "the purchase applies")
	var first_noble := int(table.nobles[0])
	h.equal(int(table.noble_owner[first_noble]), 0, "the first noble in reveal order visits")
	h.equal(int(table.points[0]), int(table.noble_data(first_noble).get("points", 0)), "and its points are scored")
	h.check(_log_has(engine, "game.splendor.log_noble"), "the visit is logged")
	h.equal((engine.public_state().get("noble_owner", []) as Array)[first_noble], 0, "noble owners are public")

	# The next purchase calls the next noble; claimed nobles never return.
	_act(h, engine)
	var second_card := _card_with(h, "blue", [0, 0, 0, 0, 3])
	_stage(table, second_card)
	h.check(bool(engine.apply_action_by_key(0, _find_key(engine, 0, "buy", {"card": second_card})).get("ok", false)),
		"the second card is bought")
	var second_noble := int(table.nobles[1])
	h.equal(int(table.noble_owner[second_noble]), 0, "the next noble visits")
	h.equal(int(table.points[0]), 6, "and adds three more points")
	h.equal(int(table.noble_owner[first_noble]), 0, "the first noble stays with its owner")

	# The noble tiles can be switched off.
	var quiet := _engine(h, 2, {"nobles": false})
	var quiet_table := quiet as SplendorEngine
	h.equal(quiet_table.nobles.size(), 0, "the nobles can be switched off")
	h.equal(quiet_table.public_state().get("nobles_enabled", true), false, "and the snapshot says so")
	_grant_bonus(quiet, 0, all_bonuses)
	var quiet_card := _card_with(h, "white", [0, 0, 0, 2, 1])
	_stage(quiet_table, quiet_card)
	h.check(bool(quiet.apply_action_by_key(0, _find_key(quiet, 0, "buy", {"card": quiet_card})).get("ok", false)),
		"the purchase still applies")
	h.equal(int(quiet_table.points[0]), 0, "but no noble visits")


# ------------------------------------------------------------------- endings

func _endings(h: TestHarness) -> void:
	# Crossing the target starts the final round; the match ends when the round
	# has been played out completely.
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	table.points[0] = table.target_points - 1
	var card := _card_with(h, "white", [0, 0, 4, 0, 0], 1)
	_stage(table, card)
	_give(h, engine, 0, {"green": 4})
	h.check(bool(engine.apply_action_by_key(0, _find_key(engine, 0, "buy", {"card": card})).get("ok", false)),
		"player one crosses the target")
	h.equal(int(table.points[0]), table.target_points, "the target is reached")
	h.equal(engine.phase(), "final_round", "the final round begins")
	h.check(not engine.finished, "the remaining players still move")
	h.check(_log_has(engine, "game.splendor.log_final_round"), "the final round is announced")
	_act(h, engine)
	h.check(engine.finished, "the match ends when the round is complete")
	h.equal(engine.winner_index(), 0, "the player who crossed the target wins")
	h.equal(str(engine.result.get("reason_key", "")), "game.splendor.reason_final_score", "the result explains itself")

	# A match that is over refuses every further action.
	h.equal(str(engine.apply_action(GameEngine.make_action("take", {"take": "black,blue,white"})).get("error_key", "")),
		"game.common.match_over", "a finished match refuses actions")
	h.equal(str(engine.apply_action_by_key(0, "type=take|take=white,blue").get("error_key", "")),
		"game.common.match_over", "…also through the keyed path")
	h.check(engine.legal_actions(0).is_empty(), "and offers none")

	# Equal points: fewer development cards win.
	var tie := _engine(h, 2)
	var tie_table := tie as SplendorEngine
	tie_table.points[0] = 17
	tie_table.points[1] = 17
	tie_table.card_counts[0] = 5
	tie_table.card_counts[1] = 8
	tie_table.final_turn = 1
	_act(h, tie)
	h.check(tie.finished, "the injected final turn ends the match")
	h.equal(tie.winner_index(), 0, "fewer cards win a tie on points")

	# Equal points and equal cards: a draw.
	var draw := _engine(h, 2)
	var draw_table := draw as SplendorEngine
	draw_table.points[0] = 12
	draw_table.points[1] = 12
	draw_table.card_counts[0] = 4
	draw_table.card_counts[1] = 4
	draw_table.final_turn = 1
	_act(h, draw)
	h.check(draw.finished, "the match ends")
	h.equal(draw.winner_index(), -1, "equal points and cards are a draw")
	h.equal(str(draw.result.get("reason_key", "")), "game.splendor.reason_tie", "the draw is announced")
	h.equal((draw.result.get("scores", []) as Array).size(), 2, "both players appear in the score")

	# Safety valve: a board nobody can move on only offers passes, and everybody
	# passing in a row ends the match on score.
	var stuck := _engine(h, 2)
	var stuck_table := stuck as SplendorEngine
	for colour: String in SplendorEngine.ALL_COLOURS:
		stuck_table.piles[colour] = 0
	for player: int in range(2):
		for _slot: int in range(SplendorEngine.MAX_RESERVED):
			var reserved_card := int((stuck_table.decks[2] as Array).pop_front())
			(stuck_table.reserved[player] as Array).append(reserved_card)
	stuck_table.points[0] = 3
	stuck_table.points[1] = 1
	h.equal(stuck.legal_actions(0).size(), 1, "a stuck player has exactly one action")
	h.equal(str(stuck.legal_actions(0)[0].get("type", "")), "pass", "and it is a pass")
	EngineHarness.check_legal_action_shape(h, stuck, "deadlocked")
	_act(h, stuck)
	h.check(not stuck.finished, "one pass alone does not end the match")
	_act(h, stuck)
	h.check(stuck.finished, "everybody passing in a row ends the match")
	h.equal(str(stuck.result.get("reason_key", "")), "game.splendor.reason_deadlock", "the deadlock explains itself")
	h.equal(stuck.winner_index(), 0, "the higher score wins a deadlocked match")


# ----------------------------------------------------------- illegal actions

func _illegal_actions(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	h.equal(str(engine.apply_action(GameEngine.make_action("nope")).get("error_key", "")),
		"game.splendor.error.unknown_action", "an unknown action type is refused")
	h.equal(str(engine.apply_action({}).get("error_key", "")),
		"game.splendor.error.unknown_action", "an action without a type is refused")
	h.equal(str(engine.apply_action(GameEngine.make_action("pass")).get("error_key", "")),
		"game.splendor.error.must_act", "passing with legal moves available is refused")
	var waiting := engine.apply_action_by_key(1, _find_key(engine, 1, "take", {"take": "black,blue,white"}))
	h.equal(str(waiting.get("error_key", "")), "game.common.not_your_turn", "playing out of turn is refused")
	h.equal(str(engine.apply_action_by_key(0, "type=take|take=white,blue").get("error_key", "")),
		"game.common.illegal_action", "an unknown action key is refused")
	h.equal(str(engine.apply_action_by_key(0, "").get("error_key", "")),
		"game.common.illegal_action", "an empty key is refused")
	h.equal(engine.turn, 0, "no rejected action moved the match on")
	h.equal(engine.decision_player(), 0, "player one is still to move")
	h.equal((engine.public_state().get("log", []) as Array).size(), 1, "and only the match start was logged")


# ----------------------------------------------------------------- snapshots

func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	EngineHarness.check_snapshot_round_trip(h, engine, "fresh table")

	# A table in progress: reserves are private, so the copy needs both halves.
	_act(h, engine)
	var stolen := _first_market_card(engine as SplendorEngine, 1)
	engine.apply_action_by_key(1, _find_key(engine, 1, "reserve", {"card": stolen}))
	_act(h, engine)
	var copy := Session.create_engine("splendor")
	h.check(copy != null, "the engine can be instantiated again")
	h.check(copy != null and copy.has_method("restore_state"), "the copy restores snapshots")
	if copy == null:
		return
	copy.restore_state(engine.public_state())
	(copy as SplendorEngine).restore_reserved(_privates(engine))
	h.equal(copy.public_state(), engine.public_state(), "a merged snapshot round trips")
	h.equal((copy as SplendorEngine).private_state(1), engine.private_state(1), "the reserve travels with its owner")
	h.equal(_keys(copy, copy.decision_player()), _keys(engine, engine.decision_player()), "the copy offers the same actions")

	# Both engines must react to the same action in the same way.
	var key := BotDirector.choose_action(engine, engine.decision_player())
	h.check(not key.is_empty(), "the bot finds a move in the current position")
	h.check(bool(engine.apply_action_by_key(engine.decision_player(), key).get("ok", false)), "the action applies to the original")
	h.check(bool(copy.apply_action_by_key(copy.decision_player(), key).get("ok", false)), "and to the copy")
	h.equal(copy.public_state(), engine.public_state(), "both engines stay in step")
	h.equal((copy as SplendorEngine).private_state(0), engine.private_state(0), "and so do their reserves")


# ------------------------------------------------------------------- privacy

func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var table := engine as SplendorEngine
	var mine := _first_market_card(table, 0)
	engine.apply_action_by_key(0, _find_key(engine, 0, "reserve", {"card": mine}))
	var theirs := _first_market_card(table, 1)
	engine.apply_action_by_key(1, _find_key(engine, 1, "reserve", {"card": theirs}))
	var mine_private: Array = table.private_state(0).get("reserved", [])
	var theirs_private: Array = table.private_state(1).get("reserved", [])
	h.equal(mine_private, [mine], "player one only sees their own reserve")
	h.equal(theirs_private, [theirs], "player two only sees their own reserve")
	h.check(not mine_private.has(theirs), "the opponent's card is not in player one's reserve")
	h.check(not engine.public_state().has("reserved"), "the public snapshot never carries reserve lists")
	EngineHarness.check_privacy(h, engine, _leaked_reserve, "splendor")


# ------------------------------------------------------------------ bot match

func _bot_match(h: TestHarness) -> void:
	for player_count: int in [2, 3, 4]:
		var engine := _engine(h, player_count, {}, 40000 + player_count)
		var steps := _play_watched(h, engine, 2000)
		h.greater(float(steps), 0.0, "the %d-player bot match makes progress" % player_count)
		h.check(engine.finished, "the %d-player bot match finishes (%d actions)" % [player_count, steps])
		if engine.finished:
			var reason := str(engine.result.get("reason_key", ""))
			h.check(not reason.is_empty(), "the finished match explains itself")
			h.check(Loc.has_key(reason, "en"), "the reason is translated")
			h.equal((engine.result.get("scores", []) as Array).size(), player_count, "every player appears in the score")
			var winner := engine.winner_index()
			h.check(winner >= -1 and winner < player_count, "the winner index is valid")
			h.check(_log_has(engine, "game.common.match_finished"), "the match log closes with the result")
		for entry: Dictionary in engine.move_log:
			h.check(Loc.has_key(str(entry.get("text_key", "")), "en"),
				"log entry %s is translated" % entry.get("text_key", ""))

	# The whole match is reproducible from the same seed.
	var first := _engine(h, 2, {}, 20260101)
	EngineHarness.play_out(first, 1200)
	var again := _engine(h, 2, {}, 20260101)
	EngineHarness.play_out(again, 1200)
	h.check(first.finished, "the scripted match finishes")
	h.equal(again.public_state(), first.public_state(), "the bot match is reproducible")

	# The nobles can be switched off without stalling the match.
	var quiet := _engine(h, 3, {"nobles": false}, 777)
	var quiet_steps := EngineHarness.play_out(quiet, 2000)
	h.greater(float(quiet_steps), 0.0, "the match without nobles progresses")
	h.check(quiet.finished, "and still finishes")


# ------------------------------------------------------------------- helpers

## Creates a Splendor engine through the shared harness.
func _engine(h: TestHarness, player_count: int = 2, options: Dictionary = {}, seed_value: int = 20251019) -> GameEngine:
	var engine := EngineHarness.create("splendor", player_count, seed_value, options)
	h.check(engine != null, "the splendor engine is creatable")
	return engine


## Plays the first legal action of the decision player, keeping a scenario moving.
func _act(h: TestHarness, engine: GameEngine) -> void:
	var actor := engine.decision_player()
	var actions := engine.legal_actions(actor)
	h.check(not actions.is_empty(), "the decision player has an action")
	if actions.is_empty():
		return
	var outcome := engine.apply_action_by_key(actor, str(actions[0].get("key", "")))
	h.check(bool(outcome.get("ok", false)), "the first legal action applies")


## Bot-driven play that watches the rules invariants on every step.
func _play_watched(h: TestHarness, engine: GameEngine, limit: int) -> int:
	var table := engine as SplendorEngine
	var totals := _token_totals(engine)
	var steps := 0
	while not engine.finished and steps < limit:
		for player: int in range(engine.player_count()):
			h.check(table.token_total(player) <= SplendorEngine.TOKEN_LIMIT,
				"player %d stays within the ten token hand limit" % player)
		var actor := engine.decision_player()
		var key := BotDirector.choose_action(engine, actor)
		h.check(not key.is_empty(), "the bot always proposes an action")
		if key.is_empty():
			break
		var outcome := engine.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal")
		if not bool(outcome.get("ok", false)):
			break
		h.equal(_token_totals(engine), totals, "gems are conserved")
		steps += 1
	return steps


## Key of the legal action of `type_name` carrying `params`, or "".
func _find_key(engine: GameEngine, player: int, type_name: String, params: Dictionary) -> String:
	for action: Dictionary in engine.legal_actions(player):
		if str(action.get("type", "")) != type_name:
			continue
		var matching := true
		for field: Variant in params:
			if str(action.get(field, "")) != str(params[field]):
				matching = false
				break
		if matching:
			return str(action.get("key", ""))
	return ""


## Sorted keys of every legal action of `player`.
func _keys(engine: GameEngine, player: int) -> Array:
	var keys: Array = []
	for action: Dictionary in engine.legal_actions(player):
		keys.append(str(action.get("key", "")))
	keys.sort()
	return keys


func _count_type(engine: GameEngine, player: int, type_name: String) -> int:
	var count := 0
	for action: Dictionary in engine.legal_actions(player):
		if str(action.get("type", "")) == type_name:
			count += 1
	return count


func _log_has(engine: GameEngine, text_key: String) -> bool:
	for entry: Dictionary in engine.move_log:
		if str(entry.get("text_key", "")) == text_key:
			return true
	return false


## Private snapshots of every player, ready for `restore_reserved`.
func _privates(engine: GameEngine) -> Array:
	var out: Array = []
	for player: int in range(engine.player_count()):
		out.append(engine.private_state(player))
	return out


## Id of the first card on the market row of `tier` (0-based), or -1.
func _first_market_card(table: SplendorEngine, tier: int) -> int:
	for slot: Variant in table.market[tier] as Array:
		if int(slot) >= 0:
			return int(slot)
	return -1


## Id of the only card in the dataset with the given bonus, points and cost.
func _card_with(h: TestHarness, bonus: String, cost: Array, points: int = 0) -> int:
	for card_id: int in range(SplendorEngine.CARDS.size()):
		var card := SplendorEngine.CARDS[card_id]
		if str(card.get("bonus", "")) == bonus and int(card.get("points", 0)) == points \
				and card.get("cost", []) == cost:
			return card_id
	h.check(false, "the dataset holds a %s card worth %d points and costing %s" % [bonus, points, cost])
	return -1


## Puts `card_id` on the market so a scenario can buy it. The replaced card goes
## to the front of its tier deck, which keeps the deck sizes honest.
func _stage(table: SplendorEngine, card_id: int) -> void:
	var tier := int(table.card_data(card_id).get("tier", 1)) - 1
	if (table.market[tier] as Array).has(card_id):
		return
	for other: int in range(3):
		if (table.decks[other] as Array).has(card_id):
			(table.decks[other] as Array).erase(card_id)
	var row: Array = table.market[tier]
	var replaced := int(row[0])
	if replaced >= 0:
		(table.decks[tier] as Array).push_front(replaced)
	row[0] = card_id


## Moves tokens from the supply to `player`, as if they had been taken earlier.
func _give(h: TestHarness, engine: GameEngine, player: int, counts: Dictionary) -> void:
	var table := engine as SplendorEngine
	for colour: Variant in counts:
		var name := str(colour)
		var amount := int(counts[colour])
		h.check(table.pile(name) >= amount, "the supply holds %d %s" % [amount, name])
		table.piles[name] = table.pile(name) - amount
		table.tokens[player][name] = int(table.tokens[player][name]) + amount


## Grants card bonuses directly, as a shortcut to the board a scenario needs.
func _grant_bonus(engine: GameEngine, player: int, counts: Dictionary) -> void:
	var table := engine as SplendorEngine
	for colour: Variant in counts:
		var name := str(colour)
		table.bonuses[player][name] = int(table.bonuses[player].get(name, 0)) + int(counts[colour])


## Tokens per colour across the supply and every player.
func _token_totals(engine: GameEngine) -> Dictionary:
	var table := engine as SplendorEngine
	var totals := table.piles.duplicate()
	for player: int in range(table.player_count()):
		for colour: String in SplendorEngine.ALL_COLOURS:
			totals[colour] = int(totals.get(colour, 0)) + int(table.tokens[player].get(colour, 0))
	return totals


func _tokens_conserved(engine: GameEngine) -> bool:
	var table := engine as SplendorEngine
	for colour: String in SplendorEngine.ALL_COLOURS:
		var expected := SplendorEngine.GOLD_PILE if colour == SplendorEngine.GOLD else SplendorEngine.PILE_SIZES[table.player_count() - 2]
		if int(_token_totals(engine).get(colour, 0)) != expected:
			return false
	return true


## Reserves of the other player that leaked into `mine` (none is correct).
func _leaked_reserve(theirs: Dictionary, mine: Dictionary) -> Array:
	var leaked: Array = []
	var mine_cards: Array = mine.get("reserved", [])
	for card_id: Variant in theirs.get("reserved", []):
		if mine_cards.has(card_id):
			leaked.append(card_id)
	return leaked
