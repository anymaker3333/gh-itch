class_name MonopolyEngine
extends GameEngine
## Monopoly rules engine (standard 40-space board).
##
## Implemented: dice movement with doubles (three doubles in a row send you to
## jail), GO salary, buy-or-auction on unowned spaces, rent with colour-group
## doubling, railroad and utility rents, Chance and Community Chest drawn
## deterministically from the seeded RNG, taxes, jail (fine, card or doubles),
## houses and hotels with the even-build rule, property trading with
## accept/decline, bankruptcy to the bank or to a creditor and a turn cap as the
## final end condition.
##
## Documented simplifications:
##  * No mortgages and no discretionary house sales: when a payment exceeds the
##    player's cash, houses are sold back automatically at half price and, if
##    that is still not enough, the player goes bankrupt (the shortfall is
##    forgiven).
##  * Trading is limited to one house-free property per side with an optional
##    cash sweetener, or a cash-only offer for a house-free property.
##  * A "get out of jail free" card is discarded when it is used or when its
##    holder goes bankrupt instead of returning to the bottom of the deck.
##  * Deck order is exposed in the public snapshot with a "_" prefix so that the
##    host-authoritative state restores exactly; the view never shows it.
##
## Action keys only use the space index, the counterpart and the amounts, so the
## same action keeps its key across snapshots.

const BOARD_SIZE: int = 40
const START_CASH: int = 1500
const GO_SALARY: int = 200
const JAIL_POS: int = 10
const JAIL_FINE: int = 50
const AUCTION_STEP: int = 10
const MAX_CARD_CHAIN: int = 6
const TRADE_SWEETENER: int = 200
## Bounded trade enumeration (§6.7): after value-ranked pruning at most this
## many offers reach the action list, so the action bar and every replicated
## snapshot stay small.
const MAX_TRADE_OFFERS: int = 48
const BANK: int = -1

## Colour groups: name -> member count (used for the even-build rule and rent).
const GROUP_SIZE: Dictionary = {
	"brown": 2, "light_blue": 3, "pink": 3, "orange": 3,
	"red": 3, "yellow": 3, "green": 3, "dark_blue": 2,
}

## The standard 40 spaces. `kind` is one of corner/property/railroad/utility/
## tax/chance/chest. Properties carry their colour group, price, house cost and
## rent ladder (base, 1-4 houses, hotel); railroads carry their 1-4 rent step.
const SPACES: Array[Dictionary] = [
	{"id": "go", "kind": "corner"},
	{"id": "mediterranean", "kind": "property", "group": "brown", "price": 60, "house": 50, "rent": [2, 10, 30, 90, 160, 250]},
	{"id": "community_chest", "kind": "chest"},
	{"id": "baltic", "kind": "property", "group": "brown", "price": 60, "house": 50, "rent": [4, 20, 60, 180, 320, 450]},
	{"id": "income_tax", "kind": "tax", "amount": 200},
	{"id": "reading_railroad", "kind": "railroad", "price": 200, "rent": [25, 50, 100, 200]},
	{"id": "oriental", "kind": "property", "group": "light_blue", "price": 100, "house": 50, "rent": [6, 30, 90, 270, 400, 550]},
	{"id": "chance", "kind": "chance"},
	{"id": "vermont", "kind": "property", "group": "light_blue", "price": 100, "house": 50, "rent": [6, 30, 90, 270, 400, 550]},
	{"id": "connecticut", "kind": "property", "group": "light_blue", "price": 120, "house": 50, "rent": [8, 40, 100, 300, 450, 600]},
	{"id": "jail", "kind": "corner"},
	{"id": "st_charles", "kind": "property", "group": "pink", "price": 140, "house": 100, "rent": [10, 50, 150, 450, 625, 750]},
	{"id": "electric_company", "kind": "utility", "price": 150},
	{"id": "states", "kind": "property", "group": "pink", "price": 140, "house": 100, "rent": [10, 50, 150, 450, 625, 750]},
	{"id": "virginia", "kind": "property", "group": "pink", "price": 160, "house": 100, "rent": [12, 60, 180, 500, 700, 900]},
	{"id": "pennsylvania_railroad", "kind": "railroad", "price": 200, "rent": [25, 50, 100, 200]},
	{"id": "st_james", "kind": "property", "group": "orange", "price": 180, "house": 100, "rent": [14, 70, 200, 550, 750, 950]},
	{"id": "community_chest", "kind": "chest"},
	{"id": "tennessee", "kind": "property", "group": "orange", "price": 180, "house": 100, "rent": [14, 70, 200, 550, 750, 950]},
	{"id": "new_york", "kind": "property", "group": "orange", "price": 200, "house": 100, "rent": [16, 80, 220, 600, 800, 1000]},
	{"id": "free_parking", "kind": "corner"},
	{"id": "kentucky", "kind": "property", "group": "red", "price": 220, "house": 150, "rent": [18, 90, 250, 700, 875, 1050]},
	{"id": "chance", "kind": "chance"},
	{"id": "indiana", "kind": "property", "group": "red", "price": 220, "house": 150, "rent": [18, 90, 250, 700, 875, 1050]},
	{"id": "illinois", "kind": "property", "group": "red", "price": 240, "house": 150, "rent": [20, 100, 300, 750, 925, 1100]},
	{"id": "bo_railroad", "kind": "railroad", "price": 200, "rent": [25, 50, 100, 200]},
	{"id": "atlantic", "kind": "property", "group": "yellow", "price": 260, "house": 150, "rent": [22, 110, 330, 800, 975, 1150]},
	{"id": "ventnor", "kind": "property", "group": "yellow", "price": 260, "house": 150, "rent": [22, 110, 330, 800, 975, 1150]},
	{"id": "water_works", "kind": "utility", "price": 150},
	{"id": "marvin_gardens", "kind": "property", "group": "yellow", "price": 280, "house": 150, "rent": [24, 120, 360, 850, 1025, 1200]},
	{"id": "go_to_jail", "kind": "corner"},
	{"id": "pacific", "kind": "property", "group": "green", "price": 300, "house": 200, "rent": [26, 130, 390, 900, 1100, 1275]},
	{"id": "north_carolina", "kind": "property", "group": "green", "price": 300, "house": 200, "rent": [26, 130, 390, 900, 1100, 1275]},
	{"id": "community_chest", "kind": "chest"},
	{"id": "pennsylvania", "kind": "property", "group": "green", "price": 320, "house": 200, "rent": [28, 150, 450, 1000, 1200, 1400]},
	{"id": "short_line", "kind": "railroad", "price": 200, "rent": [25, 50, 100, 200]},
	{"id": "chance", "kind": "chance"},
	{"id": "park_place", "kind": "property", "group": "dark_blue", "price": 350, "house": 200, "rent": [35, 175, 500, 1100, 1300, 1500]},
	{"id": "luxury_tax", "kind": "tax", "amount": 100},
	{"id": "boardwalk", "kind": "property", "group": "dark_blue", "price": 400, "house": 200, "rent": [50, 200, 600, 1400, 1700, 2000]},
]

## Chance deck (16 cards, the standard list; the nearest-railroad card appears
## twice). Card ids double as `game.monopoly.card.<id>` string keys.
const CHANCE_CARDS: Array[String] = [
	"advance_go", "advance_illinois", "advance_st_charles", "nearest_utility",
	"nearest_railroad", "nearest_railroad", "dividend", "jail_free",
	"back_three", "go_jail", "repairs", "fine_15", "reading_railroad",
	"boardwalk", "chairman", "loan",
]

## Community Chest deck (16 cards).
const CHEST_CARDS: Array[String] = [
	"advance_go", "bank_error", "doctors", "stock_sale",
	"jail_free", "go_jail", "holiday", "tax_refund",
	"birthday", "insurance", "hospital", "school",
	"consultancy", "street_repairs", "beauty", "inheritance",
]

# ------------------------------------------------------------------------ state

var cash: Array[int] = []
var pos: Array[int] = []
var jailed: Array[int] = []
var jail_rolls: Array[int] = []
var jail_cards: Array[int] = []
var bankrupt: Array[int] = []
var owner: Array[int] = []          # space -> player index or BANK
var houses: Array[int] = []         # space -> 0-4 houses, 5 = hotel
var chance_deck: Array[String] = []
var chest_deck: Array[String] = []
var last_roll: Array[int] = [0, 0]
var active: int = 0
var doubles_streak: int = 0
var extra_roll: int = 0
var pending_buy: int = -1
var auction: Dictionary = {}        # space, bid, leader, bidders, seat
var trade: Dictionary = {}          # from, to, give, take, cash
var turn_cap: int = 200
var allow_auction: bool = true


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "monopoly"


func setup(options: Dictionary) -> void:
	super.setup(options)
	turn_cap = maxi(10, VariantUtil.as_int(options.get("turn_cap", 200), 200))
	allow_auction = bool(options.get("auction", true))
	var count := player_count()
	cash.clear()
	pos.clear()
	jailed.clear()
	jail_rolls.clear()
	jail_cards.clear()
	bankrupt.clear()
	for i: int in range(count):
		cash.append(START_CASH)
		pos.append(0)
		jailed.append(0)
		jail_rolls.append(0)
		jail_cards.append(0)
		bankrupt.append(0)
	owner.clear()
	houses.clear()
	for space: int in range(BOARD_SIZE):
		owner.append(BANK)
		houses.append(0)
	chance_deck = _shuffled(CHANCE_CARDS)
	chest_deck = _shuffled(CHEST_CARDS)
	last_roll = [0, 0]
	active = 0
	doubles_streak = 0
	extra_roll = 0
	pending_buy = -1
	auction = {}
	trade = {}
	turn = 0
	round_index = 1
	log_event("game.monopoly.log_start", {
		"players": ", ".join(seat_names()),
		"cash": START_CASH,
	})


func phases() -> PackedStringArray:
	return PackedStringArray(["turn", "buy", "jail", "auction", "trade", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	if not trade.is_empty():
		return "trade"
	if not auction.is_empty():
		return "auction"
	if pending_buy >= 0:
		return "buy"
	if active >= 0 and active < jailed.size() and jailed[active] == 1:
		return "jail"
	return "turn"


func decision_player() -> int:
	if finished or players.is_empty():
		return 0
	if not trade.is_empty():
		return VariantUtil.as_int(trade.get("to", active), active)
	if not auction.is_empty():
		var bidders: Array = VariantUtil.as_array(auction.get("bidders", []))
		var seat := VariantUtil.as_int(auction.get("seat", 0), 0)
		if seat >= 0 and seat < bidders.size():
			return VariantUtil.as_int(bidders[seat], active)
		return active
	return active


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "turn_cap", "label_key": "game.monopoly.option.turn_cap", "type": "int",
			"default": 200, "min": 20, "max": 400, "hint_key": "game.monopoly.option.turn_cap_hint"},
		{"key": "auction", "label_key": "game.monopoly.option.auction", "type": "bool",
			"default": true, "hint_key": "game.monopoly.option.auction_hint"},
	]


func seat_names() -> Array:
	var out: Array = []
	for i: int in range(player_count()):
		out.append(player_name(i))
	return out


func _shuffled(source: Array) -> Array[String]:
	var deck: Array[String] = []
	for card: Variant in source:
		deck.append(VariantUtil.as_string(card, ""))
	for i: int in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	return deck


func space_id(space: int) -> String:
	if space < 0 or space >= BOARD_SIZE:
		return "?"
	return VariantUtil.as_string(SPACES[space].get("id", ""), "?")


func space_kind(space: int) -> String:
	return VariantUtil.as_string(SPACES[space].get("kind", ""), "")


func is_solvent(player: int) -> bool:
	return player >= 0 and player < player_count() and bankrupt[player] == 0


func net_worth(player: int) -> int:
	var total := cash[player]
	for space: int in range(BOARD_SIZE):
		if owner[space] == player:
			total += VariantUtil.as_int(SPACES[space].get("price", 0), 0) + houses[space] * house_cost(space)
	return total


func house_cost(space: int) -> int:
	return VariantUtil.as_int(SPACES[space].get("house", 0), 0)


# -------------------------------------------------------------- action listing

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player != decision_player() or not is_solvent(player):
		return out
	var current := phase()
	if current == "finished":
		return out
	if current == "trade":
		out.append(make_action("accept_trade", {"from": VariantUtil.as_int(trade.get("from", -1), -1)},
			"game.monopoly.action.accept_trade"))
		out.append(make_action("decline_trade", {"from": VariantUtil.as_int(trade.get("from", -1), -1)},
			"game.monopoly.action.decline_trade"))
		return out
	if current == "auction":
		_auction_actions(player, out)
		return out
	if current == "buy":
		var price := VariantUtil.as_int(SPACES[pending_buy].get("price", 0), 0)
		if price > 0 and cash[player] >= price:
			out.append(make_action("buy", {"space": pending_buy}, "game.monopoly.action.buy"))
		out.append(make_action("pass_buy", {"space": pending_buy}, "game.monopoly.action.pass_buy"))
		return out
	if current == "jail":
		if cash[player] >= JAIL_FINE:
			out.append(make_action("pay_fine", {}, "game.monopoly.action.pay_fine"))
		if jail_cards[player] > 0:
			out.append(make_action("use_card", {}, "game.monopoly.action.use_card"))
		out.append(make_action("roll", {}, "game.monopoly.action.roll_jail"))
		return out
	# current == "turn"
	out.append(make_action("roll", {}, "game.monopoly.action.roll"))
	for space: int in _buildable_spaces(player):
		var action := make_action("build_house", {"space": space})
		action["label_key"] = ""
		action["_direct"] = false
		action["_price"] = house_cost(space)
		out.append(action)
	for action: Dictionary in _trade_offers(player):
		out.append(action)
	return out


func _auction_actions(player: int, out: Array[Dictionary]) -> void:
	var bidders: Array = auction.get("bidders", [])
	if bidders.is_empty():
		return
	var space := VariantUtil.as_int(auction.get("space", -1), -1)
	var bid := VariantUtil.as_int(auction.get("bid", 0), 0)
	var amounts: Array[int] = [bid + AUCTION_STEP, bid + 50, bid + 100]
	var seen: Dictionary = {}
	for amount: int in amounts:
		if amount <= cash[player] and not seen.has(amount):
			seen[amount] = true
			var action := make_action("bid", {"space": space, "amount": amount})
			action["label_key"] = ""
			action["_direct"] = false
			out.append(action)
	var pass_action := make_action("pass_bid", {"space": space})
	pass_action["label_key"] = ""
	pass_action["_direct"] = false
	out.append(pass_action)


# ------------------------------------------------------------------ board math

func group_spaces(group: String) -> Array[int]:
	var out: Array[int] = []
	for space: int in range(BOARD_SIZE):
		if VariantUtil.as_string(SPACES[space].get("group", ""), "") == group:
			out.append(space)
	return out


func owns_group(player: int, group: String) -> bool:
	var members := group_spaces(group)
	if members.is_empty():
		return false
	for space: int in members:
		if owner[space] != player:
			return false
	return true


func count_kind(player: int, kind: String) -> int:
	var count := 0
	for space: int in range(BOARD_SIZE):
		if owner[space] == player and space_kind(space) == kind:
			count += 1
	return count


## Rent for a landing on `space` (already owned by somebody else).
func rent_for(space: int, dice: int) -> int:
	var data: Dictionary = SPACES[space]
	match VariantUtil.as_string(data.get("kind", ""), ""):
		"railroad":
			var count := count_kind(owner[space], "railroad")
			var ladder: Array = data.get("rent", [25, 50, 100, 200])
			return VariantUtil.as_int(ladder[clampi(count - 1, 0, ladder.size() - 1)], 0)
		"utility":
			var both := count_kind(owner[space], "utility") >= 2
			return (10 if both else 4) * maxi(dice, 1)
		"property":
			var ladder: Array = data.get("rent", [0])
			if houses[space] > 0:
				return VariantUtil.as_int(ladder[clampi(houses[space], 0, ladder.size() - 1)], 0)
			var base := VariantUtil.as_int(ladder[0], 0)
			if owns_group(owner[space], VariantUtil.as_string(data.get("group", ""), "")):
				return base * 2
			return base
	return 0


func _buildable_spaces(player: int) -> Array[int]:
	var out: Array[int] = []
	if cash[player] <= 0:
		return out
	for space: int in range(BOARD_SIZE):
		if owner[space] != player or space_kind(space) != "property" or houses[space] >= 5:
			continue
		var group := VariantUtil.as_string(SPACES[space].get("group", ""), "")
		if not owns_group(player, group):
			continue
		var members := group_spaces(group)
		var lowest := 5
		for member: int in members:
			lowest = mini(lowest, houses[member])
		if houses[space] != lowest:
			continue
		if cash[player] < house_cost(space):
			continue
		out.append(space)
	return out


func can_build(player: int, space: int) -> bool:
	return _buildable_spaces(player).has(space)


## Enumerates the concrete trade offers the active player may propose. Every
## offer is one house-free property per side (optionally with cash) or a cash
## offer for a house-free property. Returns finished action dictionaries.
##
## Bounded (§6.7): the full cross product (every give × every take × the cash
## variants) grows to hundreds of near-identical offers in a developed match.
## Each candidate is ranked by value balance — the distance between what the
## responder gives away and what they receive — and only the fairest
## [constant MAX_TRADE_OFFERS] reach the action list. Deterministic keys make
## the pruning stable across snapshots.
func _trade_offers(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var candidates: Array = []
	var mine: Array[int] = []
	var theirs: Array[int] = []
	for space: int in range(BOARD_SIZE):
		if space_kind(space) != "property" and space_kind(space) != "railroad" and space_kind(space) != "utility":
			continue
		if houses[space] > 0:
			continue
		if owner[space] == player:
			mine.append(space)
	for other: int in range(player_count()):
		if other == player or not is_solvent(other):
			continue
		theirs.clear()
		for space: int in range(BOARD_SIZE):
			if owner[space] == other and houses[space] == 0:
				theirs.append(space)
		for take: int in theirs:
			var price := VariantUtil.as_int(SPACES[take].get("price", 0), 0)
			for cash_offer: int in [price, price + 100]:
				if cash[player] >= cash_offer:
					var action := make_action("propose_trade", {
						"to": other, "give": -1, "take": take, "cash": cash_offer,
					})
					_style_trade(action)
					_rank_offer(action, 0, take, cash_offer)
					candidates.append(action)
			for give: int in mine:
				var cash_taken := 0
				while true:
					var action := make_action("propose_trade", {
						"to": other, "give": give, "take": take, "cash": cash_taken,
					})
					_style_trade(action)
					_rank_offer(action, give, take, cash_taken)
					candidates.append(action)
					if cash_taken != 0:
						break
					cash_taken = TRADE_SWEETENER
					if cash[player] < cash_taken:
						break
	# Fairest first, key order as the tiebreak: the pruning is deterministic
	# for the same board, so an offer survives pruning consistently.
	candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ra := VariantUtil.as_int(VariantUtil.as_dict(a).get("_rank", 0), 0)
		var rb := VariantUtil.as_int(VariantUtil.as_dict(b).get("_rank", 0), 0)
		if ra != rb:
			return ra < rb
		return VariantUtil.as_string(VariantUtil.as_dict(a).get("key", ""), "") < VariantUtil.as_string(VariantUtil.as_dict(b).get("key", ""), ""))
	for index: int in range(mini(candidates.size(), MAX_TRADE_OFFERS)):
		var offer: Dictionary = candidates[index]
		offer.erase("_rank")
		out.append(offer)
	return out


## Value-balance rank: how far the responder's side of the offer sits from an
## even trade (smaller = fairer, so the most acceptable offers survive pruning).
func _rank_offer(action: Dictionary, give: int, take: int, cash: int) -> void:
	var give_value := VariantUtil.as_int(SPACES[give].get("price", 0), 0) if give >= 0 else 0
	var take_value := VariantUtil.as_int(SPACES[take].get("price", 0), 0)
	action["_rank"] = absi(give_value + cash - take_value)


func _style_trade(action: Dictionary) -> void:
	action["label_key"] = ""
	action["_direct"] = false
	action["_kind"] = "cash" if VariantUtil.as_int(action.get("give", -1), -1) < 0 else "swap"


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var actor := decision_player()
	var wanted := VariantUtil.as_string(action.get("key", ""), "")
	var legal := find_legal_action(actor, wanted)
	if legal.is_empty():
		return _fail("game.monopoly.error.illegal_action")
	var action_type := VariantUtil.as_string(legal.get("type", ""), "")
	match action_type:
		"roll":
			_apply_roll(actor, legal)
		"buy":
			_apply_buy(actor, VariantUtil.as_int(legal.get("space", -1), -1))
		"pass_buy":
			_apply_pass_buy(actor, VariantUtil.as_int(legal.get("space", -1), -1))
		"build_house":
			_apply_build(actor, VariantUtil.as_int(legal.get("space", -1), -1))
		"propose_trade":
			_apply_propose_trade(actor, legal)
		"accept_trade":
			_apply_trade_answer(actor, true)
		"decline_trade":
			_apply_trade_answer(actor, false)
		"bid":
			_apply_bid(actor, VariantUtil.as_int(legal.get("space", -1), -1), VariantUtil.as_int(legal.get("amount", 0), 0))
		"pass_bid":
			_apply_pass_bid(actor, VariantUtil.as_int(legal.get("space", -1), -1))
		"pay_fine":
			_apply_pay_fine(actor)
		"use_card":
			_apply_use_card(actor)
		_:
			return _fail("game.monopoly.error.unknown_action")
	if not finished:
		turn += 1
	return _ok(legal)


func _apply_roll(player: int, action: Dictionary) -> void:
	var d1 := rng.randi_range(1, 6)
	var d2 := rng.randi_range(1, 6)
	last_roll = [d1, d2]
	var dice := d1 + d2
	if jailed[player] == 1:
		if d1 == d2:
			jailed[player] = 0
			jail_rolls[player] = 0
			log_event("game.monopoly.log_jail_doubles", {"player": player_name(player), "total": dice}, player)
			_move_and_resolve(player, dice)
			return
		jail_rolls[player] += 1
		if jail_rolls[player] >= 3 and cash[player] >= JAIL_FINE:
			cash[player] -= JAIL_FINE
			jailed[player] = 0
			jail_rolls[player] = 0
			log_event("game.monopoly.log_jail_pay", {"player": player_name(player), "amount": JAIL_FINE}, player)
			_move_and_resolve(player, dice)
		else:
			log_event("game.monopoly.log_jail_attempt", {"player": player_name(player), "total": dice}, player)
			_end_turn()
		return
	doubles_streak += 1
	log_event("game.monopoly.log_roll", {
		"player": player_name(player), "d1": d1, "d2": d2, "total": dice,
	}, player)
	if doubles_streak >= 3:
		_send_to_jail(player)
		log_event("game.monopoly.log_triple_jail", {"player": player_name(player)}, player)
		_end_turn()
		return
	extra_roll = 1 if d1 == d2 else 0
	if d1 == d2:
		log_event("game.monopoly.log_doubles", {"player": player_name(player)}, player)
	_move_and_resolve(player, dice)


func _apply_buy(player: int, space: int) -> void:
	if space != pending_buy or space < 0:
		return
	var price := VariantUtil.as_int(SPACES[space].get("price", 0), 0)
	if cash[player] < price or price <= 0:
		return
	cash[player] -= price
	owner[space] = player
	pending_buy = -1
	log_event("game.monopoly.log_buy", {
		"player": player_name(player), "space": _space_name(space), "price": price,
	}, player)
	_after_resolution()


func _apply_pass_buy(player: int, space: int) -> void:
	if space != pending_buy or space < 0:
		return
	pending_buy = -1
	if allow_auction:
		_start_auction(space)
	else:
		log_event("game.monopoly.log_skip", {
			"player": player_name(player), "space": _space_name(space),
		}, player)
		_after_resolution()


func _apply_build(player: int, space: int) -> void:
	if not can_build(player, space):
		return
	var cost := house_cost(space)
	cash[player] -= cost
	houses[space] += 1
	log_event("game.monopoly.log_build", {
		"player": player_name(player), "space": _space_name(space),
		"houses": _house_text(space), "cost": cost,
	}, player)


func _apply_propose_trade(player: int, action: Dictionary) -> void:
	var to := VariantUtil.as_int(action.get("to", -1), -1)
	if to < 0 or to == player or not is_solvent(to):
		return
	trade = {
		"from": player,
		"to": to,
		"give": VariantUtil.as_int(action.get("give", -1), -1),
		"take": VariantUtil.as_int(action.get("take", -1), -1),
		"cash": VariantUtil.as_int(action.get("cash", 0), 0),
	}
	log_event("game.monopoly.log_trade_offer", {
		"player": player_name(player), "other": player_name(to),
	}, player)


func _apply_trade_answer(player: int, accepted: bool) -> void:
	if trade.is_empty() or VariantUtil.as_int(trade.get("to", -1), -1) != player:
		return
	if VariantUtil.as_int(trade.get("take", -1), -1) < 0:
		# Public-only restore: the terms are gone, so nothing can be accepted.
		trade = {}
		return
	var other := VariantUtil.as_int(trade.get("from", -1), -1)
	if not _trade_still_valid():
		trade = {}
		log_event("game.monopoly.log_trade_declined", {
			"player": player_name(player), "other": player_name(other),
		}, player)
		return
	if accepted:
		var give := VariantUtil.as_int(trade.get("give", -1), -1)
		var take := VariantUtil.as_int(trade.get("take", -1), -1)
		var sweetener := VariantUtil.as_int(trade.get("cash", 0), 0)
		if give >= 0:
			owner[give] = player
		if take >= 0:
			owner[take] = other
		if sweetener > 0:
			cash[other] -= sweetener
			cash[player] += sweetener
		log_event("game.monopoly.log_trade_accepted", {
			"player": player_name(other), "other": player_name(player),
		}, player)
	else:
		log_event("game.monopoly.log_trade_declined", {
			"player": player_name(player), "other": player_name(other),
		}, player)
	trade = {}


func _trade_still_valid() -> bool:
	if trade.is_empty():
		return false
	var from := VariantUtil.as_int(trade.get("from", -1), -1)
	var to := VariantUtil.as_int(trade.get("to", -1), -1)
	if not is_solvent(from) or not is_solvent(to):
		return false
	var give := VariantUtil.as_int(trade.get("give", -1), -1)
	var take := VariantUtil.as_int(trade.get("take", -1), -1)
	var sweetener := VariantUtil.as_int(trade.get("cash", 0), 0)
	if cash[from] < sweetener:
		return false
	if give >= 0 and (owner[give] != from or houses[give] > 0):
		return false
	if take >= 0 and (owner[take] != to or houses[take] > 0):
		return false
	return true


func _apply_bid(player: int, space: int, amount: int) -> void:
	if auction.is_empty() or VariantUtil.as_int(auction.get("space", -1), -1) != space:
		return
	if cash[player] < amount or amount <= VariantUtil.as_int(auction.get("bid", 0), 0):
		return
	auction["bid"] = amount
	auction["leader"] = player
	var bidders: Array = auction.get("bidders", [])
	var seat := VariantUtil.as_int(auction.get("seat", 0), 0)
	if bidders.size() <= 1:
		log_event("game.monopoly.log_auction_bid", {
			"player": player_name(player), "space": _space_name(space), "amount": amount,
		}, player)
		_auction_close()
		return
	auction["seat"] = (seat + 1) % bidders.size()
	log_event("game.monopoly.log_auction_bid", {
		"player": player_name(player), "space": _space_name(space), "amount": amount,
	}, player)


func _apply_pass_bid(player: int, space: int) -> void:
	if auction.is_empty() or VariantUtil.as_int(auction.get("space", -1), -1) != space:
		return
	var bidders: Array = VariantUtil.as_array(auction.get("bidders", []))
	var seat := VariantUtil.as_int(auction.get("seat", 0), 0)
	if seat < 0 or seat >= bidders.size() or VariantUtil.as_int(bidders[seat], -1) != player:
		return
	log_event("game.monopoly.log_auction_pass", {
		"player": player_name(player), "space": _space_name(space),
	}, player)
	bidders.remove_at(seat)
	auction["bidders"] = bidders
	var leader := VariantUtil.as_int(auction.get("leader", -1), -1)
	if (leader >= 0 and bidders.size() <= 1) or bidders.is_empty():
		_auction_close()
		return
	auction["seat"] = seat % bidders.size()


func _start_auction(space: int) -> void:
	var bidders: Array = []
	for i: int in range(player_count()):
		var candidate := (active + i) % player_count()
		if is_solvent(candidate):
			bidders.append(candidate)
	auction = {"space": space, "bid": 0, "leader": -1, "bidders": bidders, "seat": 0}
	log_event("game.monopoly.log_auction_start", {
		"space": _space_name(space),
	}, active)


func _auction_close() -> void:
	var space := VariantUtil.as_int(auction.get("space", -1), -1)
	var leader := VariantUtil.as_int(auction.get("leader", -1), -1)
	var bid := VariantUtil.as_int(auction.get("bid", 0), 0)
	auction = {}
	if space < 0:
		_after_resolution()
		return
	if leader >= 0 and is_solvent(leader) and cash[leader] >= bid:
		cash[leader] -= bid
		owner[space] = leader
		log_event("game.monopoly.log_auction_won", {
			"player": player_name(leader), "space": _space_name(space), "amount": bid,
		}, leader)
	else:
		log_event("game.monopoly.log_auction_none", {"space": _space_name(space)}, active)
	_after_resolution()


func _apply_pay_fine(player: int) -> void:
	if jailed[player] == 0 or cash[player] < JAIL_FINE:
		return
	cash[player] -= JAIL_FINE
	jailed[player] = 0
	jail_rolls[player] = 0
	log_event("game.monopoly.log_jail_pay", {"player": player_name(player), "amount": JAIL_FINE}, player)


func _apply_use_card(player: int) -> void:
	if jailed[player] == 0 or jail_cards[player] <= 0:
		return
	jail_cards[player] -= 1
	jailed[player] = 0
	jail_rolls[player] = 0
	log_event("game.monopoly.log_jail_card", {"player": player_name(player)}, player)


# ------------------------------------------------------------------- movement

func _move_and_resolve(player: int, dice: int) -> void:
	var start := pos[player]
	var target := (start + dice) % BOARD_SIZE
	if target < start:
		cash[player] += GO_SALARY
		log_event("game.monopoly.log_go", {"player": player_name(player), "amount": GO_SALARY}, player)
	pos[player] = target
	log_event("game.monopoly.log_move", {
		"player": player_name(player), "space": _space_name(target),
	}, player)
	_resolve_landing(player, dice, 0)


func _resolve_landing(player: int, dice: int, depth: int) -> void:
	if finished:
		return
	var space := pos[player]
	match space_kind(space):
		"property", "railroad", "utility":
			if owner[space] == BANK:
				pending_buy = space
			elif owner[space] != player:
				var rent := rent_for(space, dice)
				log_event("game.monopoly.log_rent", {
					"player": player_name(player), "space": _space_name(space),
					"amount": rent, "owner": player_name(owner[space]),
				}, player)
				_pay(player, rent, owner[space])
				_after_payment(player)
			else:
				_after_resolution()
		"tax":
			var amount := VariantUtil.as_int(SPACES[space].get("amount", 0), 0)
			log_event("game.monopoly.log_tax", {
				"player": player_name(player), "space": _space_name(space), "amount": amount,
			}, player)
			_pay(player, amount, BANK)
			_after_payment(player)
		"chance":
			_draw_card(player, chance_deck, dice, depth)
		"chest":
			_draw_card(player, chest_deck, dice, depth)
		"go_to_jail":
			_send_to_jail(player)
			log_event("game.monopoly.log_go_jail", {"player": player_name(player)}, player)
			_end_turn()
		_:
			_after_resolution()


## Shared post-payment handling: a bankrupt player must hand the turn on, every
## other outcome continues through the normal resolution path.
func _after_payment(player: int) -> void:
	if finished:
		return
	if not is_solvent(player):
		_end_turn()
	else:
		_after_resolution()


func _send_to_jail(player: int) -> void:
	pos[player] = JAIL_POS
	jailed[player] = 1
	jail_rolls[player] = 0
	extra_roll = 0
	doubles_streak = 0


# -------------------------------------------------------------- chance / chest

func _draw_card(player: int, deck: Array[String], dice: int, depth: int) -> void:
	if deck.is_empty():
		_after_resolution()
		return
	var card: String = deck.pop_front()
	log_event("game.monopoly.log_card", {
		"player": player_name(player), "card": _card_text(card),
	}, player)
	if card == "jail_free":
		jail_cards[player] += 1
		_after_resolution()
		return
	deck.append(card)
	if depth >= MAX_CARD_CHAIN:
		_after_resolution()
		return
	_apply_card_effect(player, card, dice, depth)


func _apply_card_effect(player: int, card: String, dice: int, depth: int) -> void:
	match card:
		"advance_go":
			_card_move(player, 0, true, dice, depth)
		"advance_illinois":
			_card_move(player, 24, true, dice, depth)
		"advance_st_charles":
			_card_move(player, 11, true, dice, depth)
		"reading_railroad":
			_card_move(player, 5, true, dice, depth)
		"boardwalk":
			_card_move(player, 39, true, dice, depth)
		"nearest_railroad":
			_card_move(player, _nearest(player, [5, 15, 25, 35]), true, dice, depth)
		"nearest_utility":
			_card_move(player, _nearest(player, [12, 28]), true, dice, depth)
		"back_three":
			pos[player] = (pos[player] + BOARD_SIZE - 3) % BOARD_SIZE
			log_event("game.monopoly.log_move", {
				"player": player_name(player), "space": _space_name(pos[player]),
			}, player)
			_resolve_landing(player, dice, depth + 1)
		"go_jail":
			_send_to_jail(player)
			log_event("game.monopoly.log_go_jail", {"player": player_name(player)}, player)
			_end_turn()
		"dividend", "loan", "bank_error", "holiday", "tax_refund", "insurance", "beauty", "inheritance", "stock_sale":
			var gain := _card_amount(card)
			cash[player] += gain
			log_event("game.monopoly.log_gain", {"player": player_name(player), "amount": gain}, player)
			_after_resolution()
		"fine_15", "doctors", "hospital", "school":
			var loss := _card_amount(card)
			_pay(player, loss, BANK)
			_after_payment(player)
		"consultancy":
			cash[player] += 25
			log_event("game.monopoly.log_gain", {"player": player_name(player), "amount": 25}, player)
			_after_resolution()
		"repairs":
			var bill := _repairs(player, 25, 100)
			_pay(player, bill, BANK)
			_after_payment(player)
		"street_repairs":
			var street_bill := _repairs(player, 40, 115)
			_pay(player, street_bill, BANK)
			_after_payment(player)
		"chairman":
			for other: int in range(player_count()):
				if other != player and is_solvent(other):
					_pay(player, 50, other)
					if finished:
						return
			_after_payment(player)
		"birthday":
			for other: int in range(player_count()):
				if other != player and is_solvent(other):
					_pay(other, 10, player)
					if finished:
						return
			_after_resolution()
		_:
			_after_resolution()


func _card_amount(card: String) -> int:
	match card:
		"dividend", "stock_sale":
			return 50
		"loan":
			return 150
		"bank_error":
			return 200
		"holiday", "insurance":
			return 100
		"tax_refund":
			return 20
		"beauty":
			return 10
		"inheritance":
			return 100
	return 0


func _repairs(player: int, per_house: int, per_hotel: int) -> int:
	var bill := 0
	for space: int in range(BOARD_SIZE):
		if owner[space] != player:
			continue
		if houses[space] == 5:
			bill += per_hotel
		else:
			bill += houses[space] * per_house
	return bill


func _card_move(player: int, target: int, collect: bool, dice: int, depth: int) -> void:
	if target < 0:
		_after_resolution()
		return
	var start := pos[player]
	if collect and target < start:
		cash[player] += GO_SALARY
		log_event("game.monopoly.log_go", {"player": player_name(player), "amount": GO_SALARY}, player)
	pos[player] = target
	log_event("game.monopoly.log_move", {
		"player": player_name(player), "space": _space_name(target),
	}, player)
	_resolve_landing(player, dice, depth + 1)


func _nearest(player: int, spaces: Array) -> int:
	var here := pos[player]
	for step: int in range(1, BOARD_SIZE + 1):
		var candidate := (here + step) % BOARD_SIZE
		if spaces.has(candidate):
			return candidate
	return here


func _card_text(card: String) -> String:
	return Loc.t("game.monopoly.card.%s" % card)


func _space_name(space: int) -> String:
	return Loc.t("game.monopoly.space.%s" % space_id(space))


func _house_text(space: int) -> String:
	if houses[space] >= 5:
		return Loc.t("game.monopoly.hotel")
	return Loc.tp("game.monopoly.houses", houses[space])


func _after_resolution() -> void:
	if finished:
		return
	if pending_buy >= 0:
		return
	if active >= 0 and active < jailed.size() and jailed[active] == 1:
		_end_turn()
		return
	if extra_roll > 0:
		return
	_end_turn()


func _end_turn() -> void:
	extra_roll = 0
	pending_buy = -1
	auction = {}
	trade = {}
	doubles_streak = 0
	var count := player_count()
	var next := active
	for step: int in range(1, count + 1):
		var candidate := (active + step) % count
		if is_solvent(candidate):
			next = candidate
			break
	if next <= active:
		round_index += 1
	active = next
	if round_index > turn_cap:
		_finish_by_net_worth("game.monopoly.reason.turn_cap")


func _finish_by_net_worth(reason: String) -> void:
	var best := -1
	var best_value := -1
	var tied := false
	for i: int in range(player_count()):
		var value := net_worth(i)
		if value > best_value:
			best_value = value
			best = i
			tied = false
		elif value == best_value:
			tied = true
	finish(-1 if tied else best, reason, _scores())


func _scores() -> Array:
	var out: Array = []
	for i: int in range(player_count()):
		out.append({"player": i, "name": player_name(i), "score": net_worth(i)})
	return out


# ------------------------------------------------------------------- payments

## Pays `amount` to `creditor` (BANK for the bank). Houses are sold back at half
## price automatically; an unpaid remainder bankrupts the player.
func _pay(player: int, amount: int, creditor: int) -> void:
	if amount <= 0 or not is_solvent(player):
		return
	if cash[player] < amount:
		_liquidate(player, amount)
	var paid := mini(cash[player], amount)
	cash[player] -= paid
	if creditor != BANK and is_solvent(creditor):
		cash[creditor] += paid
	if paid < amount:
		_bankrupt(player, creditor)


func _liquidate(player: int, target: int) -> void:
	while cash[player] < target:
		var best := -1
		for space: int in range(BOARD_SIZE):
			if owner[space] == player and houses[space] > 0:
				if best < 0 or houses[space] > houses[best]:
					best = space
		if best < 0:
			return
		houses[best] -= 1
		# Half price for the house. Monopoly cash is whole currency units, so
		# the half is rounded down explicitly: the integer division this
		# replaces truncated towards zero, and every house cost in [constant
		# SPACES] is even, so the two agree.
		cash[player] += floori(house_cost(best) / 2.0)
		log_event("game.monopoly.log_liquidate", {
			"player": player_name(player), "space": _space_name(best),
		}, player)


func _bankrupt(player: int, creditor: int) -> void:
	if not is_solvent(player):
		return
	bankrupt[player] = 1
	jail_cards[player] = 0
	if creditor != BANK and is_solvent(creditor):
		for space: int in range(BOARD_SIZE):
			if owner[space] == player:
				owner[space] = creditor
				houses[space] = 0
		cash[creditor] += cash[player]
	else:
		for space: int in range(BOARD_SIZE):
			if owner[space] == player:
				owner[space] = BANK
				houses[space] = 0
	cash[player] = 0
	log_event("game.monopoly.log_bankrupt", {
		"player": player_name(player),
		"creditor": player_name(creditor) if creditor != BANK else Loc.t("game.monopoly.bank"),
	}, player)
	_clear_involvement(player)
	var solvent := 0
	var last := -1
	for i: int in range(player_count()):
		if is_solvent(i):
			solvent += 1
			last = i
	if solvent <= 1:
		var reason := "game.monopoly.reason.last_standing" if solvent == 1 else "game.monopoly.reason.all_bankrupt"
		finish(last, reason, _scores())


func _clear_involvement(player: int) -> void:
	if not auction.is_empty():
		var bidders: Array = auction.get("bidders", [])
		var seat := VariantUtil.as_int(auction.get("seat", 0), 0)
		var index := bidders.find(player)
		if index >= 0:
			bidders.remove_at(index)
			if index < seat:
				seat -= 1
			auction["bidders"] = bidders
			if bidders.is_empty():
				_auction_close()
				return
			auction["seat"] = seat % bidders.size()
	if not trade.is_empty() and (VariantUtil.as_int(trade.get("from", -1), -1) == player or VariantUtil.as_int(trade.get("to", -1), -1) == player):
		trade = {}


# ------------------------------------------------------------------ snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["cash"] = cash.duplicate()
	state["positions"] = pos.duplicate()
	state["jail"] = jailed.duplicate()
	state["jail_rolls"] = jail_rolls.duplicate()
	state["jail_cards"] = jail_cards.duplicate()
	state["bankrupt"] = bankrupt.duplicate()
	state["owner"] = owner.duplicate()
	state["houses"] = houses.duplicate()
	state["active"] = active
	state["doubles"] = doubles_streak
	state["extra_roll"] = extra_roll
	state["last_roll"] = last_roll.duplicate()
	state["pending_buy"] = pending_buy
	state["auction"] = auction.duplicate(true)
	# Only the existence and the parties of a pending offer are public; the terms
	# travel through private_state so hotseat play can hide them.
	state["trade"] = {"from": VariantUtil.as_int(trade.get("from", -1), -1), "to": VariantUtil.as_int(trade.get("to", -1), -1)} if not trade.is_empty() else {}
	state["turn_cap"] = turn_cap
	state["_chance_deck"] = chance_deck.duplicate()
	state["_chest_deck"] = chest_deck.duplicate()
	return state


func private_state(player: int) -> Dictionary:
	if trade.is_empty():
		return {}
	if player == VariantUtil.as_int(trade.get("from", -1), -1) or player == VariantUtil.as_int(trade.get("to", -1), -1):
		return {"trade_offer": trade.duplicate(true)}
	return {}


## Installs the full pending-trade terms when a slice carries them. Seats
## without offers install nothing: a skeleton entry from the public marker must
## never be wiped by an empty slice.
func _adopt_private_extra(_seat: int, slice: Dictionary) -> void:
	if slice.has("trade_offer") and (slice.get("trade_offer", {}) is Dictionary):
		trade = VariantUtil.dict_copy(slice.get("trade_offer", {}))


func _restore_extra(state: Dictionary) -> void:
	copy_int_array(state.get("cash", []), cash)
	copy_int_array(state.get("positions", []), pos)
	copy_int_array(state.get("jail", []), jailed)
	copy_int_array(state.get("jail_rolls", []), jail_rolls)
	copy_int_array(state.get("jail_cards", []), jail_cards)
	copy_int_array(state.get("bankrupt", []), bankrupt)
	copy_int_array(state.get("owner", []), owner)
	copy_int_array(state.get("houses", []), houses)
	copy_string_array(state.get("_chance_deck", []), chance_deck)
	copy_string_array(state.get("_chest_deck", []), chest_deck)
	copy_int_array(state.get("last_roll", []), last_roll)
	active = VariantUtil.as_int(state.get("active", 0), 0)
	doubles_streak = VariantUtil.as_int(state.get("doubles", 0), 0)
	extra_roll = VariantUtil.as_int(state.get("extra_roll", 0), 0)
	pending_buy = VariantUtil.as_int(state.get("pending_buy", -1), -1)
	auction = VariantUtil.dict_copy(state.get("auction", {}))
	trade = {}
	var marker: Dictionary = state.get("trade", {})
	if not marker.is_empty():
		# The terms are private: a public-only snapshot restores the marker in
		# skeleton form, and private slices restore the full terms when they
		# carry them (a save-file bag for an offer seat, or the harness merged
		# shape attributed to the decision player).
		trade = {"from": VariantUtil.as_int(marker.get("from", -1), -1), "to": VariantUtil.as_int(marker.get("to", -1), -1), "give": -1, "take": -1, "cash": 0}
		var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
		for seat: int in [VariantUtil.as_int(marker.get("from", -1), -1), VariantUtil.as_int(marker.get("to", -1), -1)]:
			if privates.has(str(seat)) and (privates.get(str(seat), {}) is Dictionary):
				_adopt_private_extra(seat, privates.get(str(seat), {}))
		if state.has("trade_offer"):
			_adopt_private_extra(decision_player(), state)
	turn_cap = VariantUtil.as_int(state.get("turn_cap", 200), 200)
	var count := player_count()
	while cash.size() < count:
		cash.append(START_CASH)
		pos.append(0)
		jailed.append(0)
		jail_rolls.append(0)
		jail_cards.append(0)
		bankrupt.append(0)
	while owner.size() < BOARD_SIZE:
		owner.append(BANK)
		houses.append(0)
