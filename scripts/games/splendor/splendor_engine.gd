class_name SplendorEngine
extends GameEngine
## Splendor rules engine for 2 to 4 players.
##
## Implementation of the standard Renaissance gem-merchant game: 90 development
## cards in three tiers, 10 noble tiles and six token colours (five gems plus the
## gold joker). On a turn a player takes three different gems, takes two gems of
## one colour (only from a pile holding at least four), reserves a card together
## with one gold joker (at most three reserved cards), buys a card from the market
## or from their own reserve. Bonuses from bought cards discount future purchases
## and gold substitutes for missing gems. Nobles visit automatically once a player
## collects the required bonuses, and the match ends after the round in which a
## player reaches the target score.
##
## Pure logic: no nodes, no file IO. All randomness (deck and noble shuffles) comes
## from the inherited [member GameEngine.rng], so the same seed and the same action
## sequence always produce the same [method public_state].
##
## Simplifications, all documented here and covered by the rules suite:
##  * A player is never blocked by the ten-token hand limit. When a take or a
##    reservation pushes a player over ten tokens, the engine returns the excess
##    automatically: always the most abundant colour first, and gold only when it is
##    strictly the most abundant one (official play lets the player choose).
##  * When several revealed nobles qualify at once, the first one in reveal order
##    visits (official play lets the player choose which one).
##  * A "pass" action exists solely as a safety valve: it is legal only when a
##    player has no other action, and the match ends when every player had to pass
##    in a row, or after a long streak without a single purchase.

const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4
const DEFAULT_TARGET_POINTS: int = 15

## Rules constants of the standard game.
const MARKET_SIZE: int = 4
const MAX_RESERVED: int = 3
const TOKEN_LIMIT: int = 10
const NOBLES_EXTRA: int = 1
const GOLD_PILE: int = 5
## Gem tokens per colour in a 2 / 3 / 4 player game.
const PILE_SIZES: Array[int] = [4, 5, 7]
## A streak of this many actions without a single purchase means nobody can make
## progress any more, so the match is adjudicated instead of running forever.
const STALE_ACTION_LIMIT: int = 200

const GOLD: String = "gold"
## Display and payout order of the five gem colours.
const GEM_COLOURS: Array[String] = ["white", "blue", "green", "red", "black"]
const ALL_COLOURS: Array[String] = ["white", "blue", "green", "red", "black", "gold"]

## The 90 development cards of the standard game. `cost` is ordered like
## [constant GEM_COLOURS]: white, blue, green, red, black. The array index is the
## card id, which is what action keys and snapshots carry.
const CARDS: Array[Dictionary] = [
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 0, 0, 2, 1]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 1, 1, 1, 1]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 1, 2, 1, 1]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 2, 0, 0, 2]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 2, 2, 0, 1]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [0, 3, 0, 0, 0]},
	{"tier": 1, "bonus": "white", "points": 0, "cost": [3, 1, 0, 0, 1]},
	{"tier": 1, "bonus": "white", "points": 1, "cost": [0, 0, 4, 0, 0]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [0, 0, 0, 0, 3]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [0, 0, 2, 0, 2]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [0, 1, 3, 1, 0]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [1, 0, 0, 0, 2]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [1, 0, 1, 1, 1]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [1, 0, 1, 2, 1]},
	{"tier": 1, "bonus": "blue", "points": 0, "cost": [1, 0, 2, 2, 0]},
	{"tier": 1, "bonus": "blue", "points": 1, "cost": [0, 0, 0, 4, 0]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [0, 0, 0, 3, 0]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [0, 1, 0, 2, 2]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [0, 2, 0, 2, 0]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [1, 1, 0, 1, 1]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [1, 1, 0, 1, 2]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [1, 3, 1, 0, 0]},
	{"tier": 1, "bonus": "green", "points": 0, "cost": [2, 1, 0, 0, 0]},
	{"tier": 1, "bonus": "green", "points": 1, "cost": [0, 0, 0, 0, 4]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [0, 2, 1, 0, 0]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [1, 0, 0, 1, 3]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [1, 1, 1, 0, 1]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [2, 0, 0, 2, 0]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [2, 0, 1, 0, 2]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [2, 1, 1, 0, 1]},
	{"tier": 1, "bonus": "red", "points": 0, "cost": [3, 0, 0, 0, 0]},
	{"tier": 1, "bonus": "red", "points": 1, "cost": [4, 0, 0, 0, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [0, 0, 1, 3, 1]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [0, 0, 2, 1, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [0, 0, 3, 0, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [1, 1, 1, 1, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [1, 2, 1, 1, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [2, 0, 2, 0, 0]},
	{"tier": 1, "bonus": "black", "points": 0, "cost": [2, 2, 0, 1, 0]},
	{"tier": 1, "bonus": "black", "points": 1, "cost": [0, 4, 0, 0, 0]},
	{"tier": 2, "bonus": "white", "points": 1, "cost": [0, 0, 3, 2, 2]},
	{"tier": 2, "bonus": "white", "points": 1, "cost": [2, 3, 0, 3, 0]},
	{"tier": 2, "bonus": "white", "points": 2, "cost": [0, 0, 0, 5, 0]},
	{"tier": 2, "bonus": "white", "points": 2, "cost": [0, 0, 0, 5, 3]},
	{"tier": 2, "bonus": "white", "points": 2, "cost": [0, 0, 1, 4, 2]},
	{"tier": 2, "bonus": "white", "points": 3, "cost": [6, 0, 0, 0, 0]},
	{"tier": 2, "bonus": "blue", "points": 1, "cost": [0, 2, 2, 3, 0]},
	{"tier": 2, "bonus": "blue", "points": 1, "cost": [0, 2, 3, 0, 3]},
	{"tier": 2, "bonus": "blue", "points": 2, "cost": [0, 5, 0, 0, 0]},
	{"tier": 2, "bonus": "blue", "points": 2, "cost": [2, 0, 0, 1, 4]},
	{"tier": 2, "bonus": "blue", "points": 2, "cost": [5, 3, 0, 0, 0]},
	{"tier": 2, "bonus": "blue", "points": 3, "cost": [0, 6, 0, 0, 0]},
	{"tier": 2, "bonus": "green", "points": 1, "cost": [2, 3, 0, 0, 2]},
	{"tier": 2, "bonus": "green", "points": 1, "cost": [3, 0, 2, 3, 0]},
	{"tier": 2, "bonus": "green", "points": 2, "cost": [0, 0, 5, 0, 0]},
	{"tier": 2, "bonus": "green", "points": 2, "cost": [0, 5, 3, 0, 0]},
	{"tier": 2, "bonus": "green", "points": 2, "cost": [4, 2, 0, 0, 1]},
	{"tier": 2, "bonus": "green", "points": 3, "cost": [0, 0, 6, 0, 0]},
	{"tier": 2, "bonus": "red", "points": 1, "cost": [0, 3, 0, 2, 3]},
	{"tier": 2, "bonus": "red", "points": 1, "cost": [2, 0, 0, 2, 3]},
	{"tier": 2, "bonus": "red", "points": 2, "cost": [0, 0, 0, 0, 5]},
	{"tier": 2, "bonus": "red", "points": 2, "cost": [1, 4, 2, 0, 0]},
	{"tier": 2, "bonus": "red", "points": 2, "cost": [3, 0, 0, 0, 5]},
	{"tier": 2, "bonus": "red", "points": 3, "cost": [0, 0, 0, 6, 0]},
	{"tier": 2, "bonus": "black", "points": 1, "cost": [3, 0, 3, 0, 2]},
	{"tier": 2, "bonus": "black", "points": 1, "cost": [3, 2, 2, 0, 0]},
	{"tier": 2, "bonus": "black", "points": 2, "cost": [0, 0, 5, 3, 0]},
	{"tier": 2, "bonus": "black", "points": 2, "cost": [0, 1, 4, 2, 0]},
	{"tier": 2, "bonus": "black", "points": 2, "cost": [5, 0, 0, 0, 0]},
	{"tier": 2, "bonus": "black", "points": 3, "cost": [0, 0, 0, 0, 6]},
	{"tier": 3, "bonus": "white", "points": 3, "cost": [0, 3, 3, 5, 3]},
	{"tier": 3, "bonus": "white", "points": 4, "cost": [0, 0, 0, 0, 7]},
	{"tier": 3, "bonus": "white", "points": 4, "cost": [3, 0, 0, 3, 6]},
	{"tier": 3, "bonus": "white", "points": 5, "cost": [3, 0, 0, 0, 7]},
	{"tier": 3, "bonus": "blue", "points": 3, "cost": [3, 0, 3, 3, 5]},
	{"tier": 3, "bonus": "blue", "points": 4, "cost": [6, 3, 0, 0, 3]},
	{"tier": 3, "bonus": "blue", "points": 4, "cost": [7, 0, 0, 0, 0]},
	{"tier": 3, "bonus": "blue", "points": 5, "cost": [7, 3, 0, 0, 0]},
	{"tier": 3, "bonus": "green", "points": 3, "cost": [5, 3, 0, 3, 3]},
	{"tier": 3, "bonus": "green", "points": 4, "cost": [0, 7, 0, 0, 0]},
	{"tier": 3, "bonus": "green", "points": 4, "cost": [3, 6, 3, 0, 0]},
	{"tier": 3, "bonus": "green", "points": 5, "cost": [0, 7, 3, 0, 0]},
	{"tier": 3, "bonus": "red", "points": 3, "cost": [3, 5, 3, 0, 3]},
	{"tier": 3, "bonus": "red", "points": 4, "cost": [0, 0, 7, 0, 0]},
	{"tier": 3, "bonus": "red", "points": 4, "cost": [0, 3, 6, 3, 0]},
	{"tier": 3, "bonus": "red", "points": 5, "cost": [0, 0, 7, 3, 0]},
	{"tier": 3, "bonus": "black", "points": 3, "cost": [3, 3, 5, 3, 0]},
	{"tier": 3, "bonus": "black", "points": 4, "cost": [0, 0, 0, 7, 0]},
	{"tier": 3, "bonus": "black", "points": 4, "cost": [0, 0, 3, 6, 3]},
	{"tier": 3, "bonus": "black", "points": 5, "cost": [0, 0, 0, 7, 3]},
]

## The 10 noble tiles, 3 points each. `cost` uses the same order as [constant CARDS].
const NOBLES: Array[Dictionary] = [
	{"points": 3, "cost": [0, 0, 0, 4, 4]},
	{"points": 3, "cost": [0, 0, 3, 3, 3]},
	{"points": 3, "cost": [0, 0, 4, 4, 0]},
	{"points": 3, "cost": [0, 3, 3, 3, 0]},
	{"points": 3, "cost": [0, 4, 4, 0, 0]},
	{"points": 3, "cost": [3, 0, 0, 3, 3]},
	{"points": 3, "cost": [3, 3, 0, 0, 3]},
	{"points": 3, "cost": [3, 3, 3, 0, 0]},
	{"points": 3, "cost": [4, 0, 0, 0, 4]},
	{"points": 3, "cost": [4, 4, 0, 0, 0]},
]

## Match options (mirrors [method options_schema]).
var target_points: int = DEFAULT_TARGET_POINTS
var nobles_enabled: bool = true

## Token supply: colour -> remaining count. Includes [constant GOLD].
var piles: Dictionary = {}
## Visible market rows, one [Array] of card ids per tier; -1 marks an empty slot.
var market: Array = [[], [], []]
## Cards still hidden in each tier deck, drawn from the front.
var decks: Array = [[], [], []]
## Revealed noble ids, in reveal order.
var nobles: Array[int] = []
## Noble id -> player index, or -1 while the noble is still waiting.
var noble_owner: Array[int] = []

## Per player: tokens held, bonuses bought, score, number of bought cards, reserves.
var tokens: Array[Dictionary] = []
var bonuses: Array[Dictionary] = []
var points: Array[int] = []
var card_counts: Array[int] = []
var reserved: Array = []

## `turn` at which the final round ends; 0 while nobody reached the target.
var final_turn: int = 0
## Actions since the last purchase (safety valve) and passes in a row.
var stale_actions: int = 0
var consecutive_passes: int = 0


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "splendor"


func setup(options: Dictionary) -> void:
	super.setup(options)
	target_points = clampi(VariantUtil.as_int(options.get("target_points", DEFAULT_TARGET_POINTS), DEFAULT_TARGET_POINTS), 5, 30)
	nobles_enabled = bool(options.get("nobles", true))
	var count := clampi(player_count(), MIN_PLAYERS, MAX_PLAYERS)
	_seed_decks()
	_deal_market()
	piles = {}
	var per_colour := int(PILE_SIZES[count - MIN_PLAYERS])
	for colour: String in GEM_COLOURS:
		piles[colour] = per_colour
	piles[GOLD] = GOLD_PILE
	_reveal_nobles(count)
	tokens = []
	bonuses = []
	points = []
	card_counts = []
	reserved = []
	for player: int in range(player_count()):
		tokens.append(_empty_counts(GEM_COLOURS.size() + 1))
		bonuses.append(_empty_counts(GEM_COLOURS.size()))
		points.append(0)
		card_counts.append(0)
		reserved.append(_empty_cards())
	final_turn = 0
	stale_actions = 0
	consecutive_passes = 0
	round_index = 1
	log_event("game.splendor.log_start", {"players": _player_list_text()})


func phases() -> PackedStringArray:
	return PackedStringArray(["playing", "final_round", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	return "final_round" if final_turn > 0 else "playing"


func decision_player() -> int:
	return turn % maxi(1, player_count())


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "target_points", "label_key": "game.splendor.option.target_points", "type": "int",
			"default": DEFAULT_TARGET_POINTS, "min": 10, "max": 20,
			"hint_key": "game.splendor.option.target_points_hint"},
		{"key": "nobles", "label_key": "game.splendor.option.nobles", "type": "bool",
			"default": true, "hint_key": "game.splendor.option.nobles_hint"},
	]


# ------------------------------------------------------------- setup helpers

func _seed_decks() -> void:
	decks = [[], [], []]
	var by_tier: Array = [[], [], []]
	for card_id: int in range(CARDS.size()):
		var tier := clampi(VariantUtil.as_int(VariantUtil.as_dict(CARDS[card_id]).get("tier", 1), 1) - 1, 0, 2)
		VariantUtil.as_array(by_tier[tier]).append(card_id)
	for tier: int in range(3):
		var ids: Array[int] = []
		for card_id: Variant in VariantUtil.as_array(by_tier[tier]):
			ids.append(VariantUtil.as_int(card_id, -1))
		_shuffle(ids)
		decks[tier] = ids


## Fisher-Yates using the inherited, seed-derived generator.
func _shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


func _deal_market() -> void:
	market = [_empty_cards(), _empty_cards(), _empty_cards()]
	for tier: int in range(3):
		for _slot: int in range(MARKET_SIZE):
			VariantUtil.as_array(market[tier]).append(_draw(tier))


## Removes and returns the top card of a tier deck, or -1 when it is empty.
func _draw(tier: int) -> int:
	var deck: Array = VariantUtil.as_array(decks[tier])
	if deck.is_empty():
		return -1
	return int(deck.pop_front())


func _reveal_nobles(count: int) -> void:
	nobles = []
	noble_owner = []
	for noble_id: int in range(NOBLES.size()):
		noble_owner.append(-1)
	if not nobles_enabled:
		return
	var ids: Array[int] = []
	for noble_id: int in range(NOBLES.size()):
		ids.append(noble_id)
	_shuffle(ids)
	var reveal := mini(ids.size(), count + NOBLES_EXTRA)
	for i: int in range(reveal):
		nobles.append(ids[i])


func _empty_counts(size: int) -> Dictionary:
	var out: Dictionary = {}
	for colour: String in ALL_COLOURS:
		if out.size() >= size:
			break
		out[colour] = 0
	return out


func _empty_cards() -> Array[int]:
	var out: Array[int] = []
	return out


func _player_list_text() -> String:
	var names := PackedStringArray()
	for index: int in range(player_count()):
		names.append(player_name(index))
	return ", ".join(names)


# --------------------------------------------------------------- public reads

## Card dictionary for `card_id` (never mutate the returned dictionary).
func card_data(card_id: int) -> Dictionary:
	if card_id < 0 or card_id >= CARDS.size():
		return {}
	return CARDS[card_id]


## Noble dictionary for `noble_id`.
func noble_data(noble_id: int) -> Dictionary:
	if noble_id < 0 or noble_id >= NOBLES.size():
		return {}
	return NOBLES[noble_id]


func pile(colour: String) -> int:
	return VariantUtil.as_int(piles.get(colour, 0), 0)


func token_total(player: int) -> int:
	var total := 0
	if player < 0 or player >= tokens.size():
		return 0
	for colour: String in tokens[player]:
		total += VariantUtil.as_int(tokens[player][colour], 0)
	return total


func reserved_count(player: int) -> int:
	if player < 0 or player >= reserved.size():
		return 0
	return VariantUtil.as_array(reserved[player]).size()


func score_of(player: int) -> int:
	if player < 0 or player >= points.size():
		return 0
	return int(points[player])


func gold_of(player: int) -> int:
	if player < 0 or player >= tokens.size():
		return 0
	return VariantUtil.as_int(tokens[player].get(GOLD, 0), 0)


# ------------------------------------------------------------------ deck data

func _gem_key(colour: String) -> String:
	match colour:
		"white":
			return "game.splendor.gem.white"
		"blue":
			return "game.splendor.gem.blue"
		"green":
			return "game.splendor.gem.green"
		"red":
			return "game.splendor.gem.red"
		"black":
			return "game.splendor.gem.black"
		_:
			return "game.splendor.gem.gold"


func _colours_text(colours: Array) -> String:
	var names := PackedStringArray()
	for colour: Variant in colours:
		names.append(Loc.t(_gem_key(String(colour))))
	return ", ".join(names)


# -------------------------------------------------------------- action build

func legal_actions(player: int) -> Array[Dictionary]:
	## Everything `player` may do now. Callers may ask for a player who is not to
	## move (the bot does this when it evaluates), so the list depends on the
	## engine state only and never on [method decision_player].
	var out: Array[Dictionary] = []
	if finished or player < 0 or player >= player_count():
		return out
	out.append_array(_take_actions(player))
	out.append_array(_reserve_actions(player))
	out.append_array(_buy_actions(player))
	if out.is_empty():
		# Safety valve: a deadlocked player may pass so that the match can end.
		var pass_action := make_action("pass", {}, "game.splendor.pass")
		pass_action["_direct"] = true
		out.append(pass_action)
	return out


func _take_actions(_player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var available: Array[String] = []
	for colour: String in GEM_COLOURS:
		if pile(colour) > 0:
			available.append(colour)
	if available.size() >= 3:
		for combo: Variant in _combinations(available, 3):
			out.append(_take_action(VariantUtil.as_array(combo)))
	elif not available.is_empty():
		# Fewer than three colours left in the supply: take what there is.
		out.append(_take_action(available))
	for colour: String in GEM_COLOURS:
		if pile(colour) >= 4:
			out.append(_take_action([colour, colour]))
	return out


func _take_action(colours: Array) -> Dictionary:
	var sorted := colours.duplicate()
	sorted.sort()
	var parts := PackedStringArray()
	for colour: Variant in sorted:
		parts.append(String(colour))
	var action := make_action("take", {"take": ",".join(parts)})
	action["label_key"] = ""
	action["_direct"] = false
	action["_gems"] = sorted
	return action


func _reserve_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if reserved_count(player) >= MAX_RESERVED:
		return out
	for tier: int in range(3):
		var row: Array = VariantUtil.as_array(market[tier])
		for slot: int in range(row.size()):
			var card_id := int(row[slot])
			if card_id >= 0:
				out.append(_reserve_action(card_id, tier + 1))
		if not VariantUtil.as_array(decks[tier]).is_empty():
			out.append(_blind_reserve_action(tier + 1))
	return out


func _reserve_action(card_id: int, tier: int) -> Dictionary:
	var card := card_data(card_id)
	var action := make_action("reserve", {"card": card_id})
	action["label_key"] = ""
	action["_direct"] = false
	action["_card"] = card_id
	action["_tier"] = tier
	action["_blind"] = false
	action["_bonus"] = VariantUtil.as_string(card.get("bonus", ""), "")
	action["_points"] = VariantUtil.as_int(card.get("points", 0), 0)
	action["_cost"] = VariantUtil.array_copy(card.get("cost", []))
	return action


func _blind_reserve_action(tier: int) -> Dictionary:
	var action := make_action("reserve", {"tier": tier, "blind": true})
	action["label_key"] = ""
	action["_direct"] = false
	action["_card"] = -1
	action["_tier"] = tier
	action["_blind"] = true
	return action


func _buy_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card_id: int in _visible_card_ids():
		if _can_afford(player, card_id):
			out.append(_buy_action(player, card_id, false))
	for card_id: Variant in VariantUtil.as_array(reserved[player]):
		if _can_afford(player, int(card_id)):
			out.append(_buy_action(player, int(card_id), true))
	return out


func _buy_action(_player: int, card_id: int, from_reserve: bool) -> Dictionary:
	var card := card_data(card_id)
	var action := make_action("buy", {"card": card_id})
	action["label_key"] = ""
	action["_direct"] = false
	action["_card"] = card_id
	action["_tier"] = VariantUtil.as_int(card.get("tier", 0), 0)
	action["_bonus"] = VariantUtil.as_string(card.get("bonus", ""), "")
	action["_points"] = VariantUtil.as_int(card.get("points", 0), 0)
	action["_cost"] = VariantUtil.array_copy(card.get("cost", []))
	action["_reserve"] = from_reserve
	return action


func _visible_card_ids() -> Array[int]:
	var out: Array[int] = []
	for tier: int in range(3):
		for slot: Variant in VariantUtil.as_array(market[tier]):
			var card_id := int(slot)
			if card_id >= 0:
				out.append(card_id)
	return out


## All combinations of `k` items, in deterministic order.
func _combinations(items: Array, k: int) -> Array:
	var out: Array = []
	if k <= 0 or k > items.size():
		return out
	var indices: Array[int] = []
	for i: int in range(k):
		indices.append(i)
	while true:
		var combo: Array = []
		for i: int in indices:
			combo.append(items[i])
		out.append(combo)
		var pos := k - 1
		while pos >= 0 and indices[pos] == items.size() - k + pos:
			pos -= 1
		if pos < 0:
			break
		indices[pos] += 1
		for j: int in range(pos + 1, k):
			indices[j] = indices[j - 1] + 1
	return out


# ----------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	match str(action.get("type", "")):
		"take":
			return _apply_take(player, action)
		"reserve":
			return _apply_reserve(player, action)
		"buy":
			return _apply_buy(player, action)
		"pass":
			return _apply_pass(player)
		_:
			return _fail("game.splendor.error.unknown_action")


## Tolerant integer read for incoming actions. Anything that is not a number or a
## numeric string becomes `fallback`, so a malformed message is rejected instead
## of crashing the engine.
static func _int_param(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	if value is String or value is StringName:
		var text := String(value).strip_edges()
		if text.is_valid_int():
			return int(text)
	return fallback


func _apply_take(player: int, action: Dictionary) -> Dictionary:
	var take_text := str(action.get("take", ""))
	if take_text.is_empty():
		return _fail("game.splendor.error.take_invalid")
	var colours: Array[String] = []
	for piece: String in take_text.split(",", false):
		colours.append(piece)
	if colours.is_empty() or colours.size() > 3:
		return _fail("game.splendor.error.take_invalid")
	for colour: String in colours:
		if not GEM_COLOURS.has(colour):
			return _fail("game.splendor.error.take_invalid")
	if colours.size() == 2 and colours[0] == colours[1]:
		if pile(colours[0]) < 4:
			return _fail("game.splendor.error.take_pile")
	else:
		var unique: Dictionary = {}
		for colour: String in colours:
			if unique.has(colour):
				return _fail("game.splendor.error.take_invalid")
			unique[colour] = true
		if colours.size() != _max_different():
			return _fail("game.splendor.error.take_size")
	for colour: String in colours:
		if pile(colour) <= 0:
			return _fail("game.splendor.error.take_gems")
	for colour: String in colours:
		piles[colour] = pile(colour) - 1
		tokens[player][colour] = VariantUtil.as_int(tokens[player][colour], 0) + 1
	log_event(_take_log_key(colours.size()), {
		"player": player_name(player),
		"gems": _colours_text(colours),
		"count": colours.size(),
	}, player)
	_finish_turn(player, false, false)
	return _ok(action)


## Log key for a take of `count` gems. `log_event` renders through `Loc.t`, so
## the engine has to pick the `.one` / `.other` form itself.
func _take_log_key(count: int) -> String:
	if count == 1:
		return "game.splendor.log_take.one"
	return "game.splendor.log_take.other"


## Number of different gems the supply currently allows a player to take.
func _max_different() -> int:
	var available := 0
	for colour: String in GEM_COLOURS:
		if pile(colour) > 0:
			available += 1
	return mini(3, available)


func _apply_reserve(player: int, action: Dictionary) -> Dictionary:
	if reserved_count(player) >= MAX_RESERVED:
		return _fail("game.splendor.error.reserve_full")
	var card_id := -1
	var tier := 0
	if bool(action.get("blind", false)):
		tier = _int_param(action.get("tier", 0), 0)
		if tier < 1 or tier > 3 or VariantUtil.as_array(decks[tier - 1]).is_empty():
			return _fail("game.splendor.error.no_card")
		card_id = _draw(tier - 1)
		if card_id < 0:
			return _fail("game.splendor.error.no_card")
	else:
		card_id = _int_param(action.get("card", -1), -1)
		# An empty market slot carries the id -1; it must be rejected before the
		# slot is refilled, so that a rejected action never mutates the board.
		if card_id < 0 or not _market_has(card_id):
			return _fail("game.splendor.error.no_card")
		_replace_market_slot(card_id)
	VariantUtil.as_array(reserved[player]).append(card_id)
	if pile(GOLD) > 0:
		piles[GOLD] = pile(GOLD) - 1
		tokens[player][GOLD] = VariantUtil.as_int(tokens[player][GOLD], 0) + 1
		log_event("game.splendor.log_reserve_gold", {"player": player_name(player)}, player)
	else:
		log_event("game.splendor.log_reserve", {"player": player_name(player)}, player)
	_finish_turn(player, false, false)
	return _ok(action)


func _apply_buy(player: int, action: Dictionary) -> Dictionary:
	var card_id := _int_param(action.get("card", -1), -1)
	var from_reserve := VariantUtil.as_array(reserved[player]).has(card_id)
	if not from_reserve and not _market_has(card_id):
		return _fail("game.splendor.error.not_your_card")
	if not _can_afford(player, card_id):
		return _fail("game.splendor.error.cannot_afford")
	var card := card_data(card_id)
	var payment := _payment(player, card_id)
	if from_reserve:
		VariantUtil.as_array(reserved[player]).erase(card_id)
	else:
		_replace_market_slot(card_id)
	for colour: Variant in payment:
		tokens[player][String(colour)] = VariantUtil.as_int(tokens[player][String(colour)], 0) - VariantUtil.as_int(payment[colour], 0)
		piles[String(colour)] = pile(String(colour)) + VariantUtil.as_int(payment[colour], 0)
	var bonus := VariantUtil.as_string(card.get("bonus", ""), "")
	bonuses[player][bonus] = VariantUtil.as_int(bonuses[player][bonus], 0) + 1
	points[player] = int(points[player]) + VariantUtil.as_int(card.get("points", 0), 0)
	card_counts[player] = int(card_counts[player]) + 1
	log_event("game.splendor.log_buy", {
		"player": player_name(player),
		"bonus": Loc.t(_gem_key(bonus)),
		"points": Loc.tp("game.splendor.points", VariantUtil.as_int(card.get("points", 0), 0)),
	}, player)
	_visit_noble(player)
	_finish_turn(player, true, false)
	return _ok(action)


func _apply_pass(player: int) -> Dictionary:
	if not _take_actions(player).is_empty() or not _reserve_actions(player).is_empty() \
			or not _buy_actions(player).is_empty():
		return _fail("game.splendor.error.must_act")
	log_event("game.splendor.log_pass", {"player": player_name(player)}, player)
	_finish_turn(player, false, true)
	return _ok(make_action("pass", {}, "game.splendor.pass"))


# -------------------------------------------------------------------- payments

## Minimal deterministic payment: bonuses first, then held gems, gold last.
func _payment(player: int, card_id: int) -> Dictionary:
	var card := card_data(card_id)
	var cost: Array = card.get("cost", [])
	var payment: Dictionary = {}
	var gold := 0
	for i: int in range(GEM_COLOURS.size()):
		var colour := GEM_COLOURS[i]
		var need := maxi(0, int(cost[i]) - VariantUtil.as_int(bonuses[player].get(colour, 0), 0))
		var from_tokens := mini(need, VariantUtil.as_int(tokens[player].get(colour, 0), 0))
		if from_tokens > 0:
			payment[colour] = from_tokens
		gold += need - from_tokens
	if gold > 0:
		payment[GOLD] = gold
	return payment


func _can_afford(player: int, card_id: int) -> bool:
	if card_data(card_id).is_empty():
		return false
	var payment := _payment(player, card_id)
	return VariantUtil.as_int(payment.get(GOLD, 0), 0) <= VariantUtil.as_int(tokens[player].get(GOLD, 0), 0)


# ------------------------------------------------------------ board mutations

func _market_has(card_id: int) -> bool:
	for tier: int in range(3):
		for slot: Variant in VariantUtil.as_array(market[tier]):
			if int(slot) == card_id:
				return true
	return false


## Takes the card out of its market slot and draws a replacement for that tier.
func _replace_market_slot(card_id: int) -> void:
	for tier: int in range(3):
		var row: Array = VariantUtil.as_array(market[tier])
		for slot: int in range(row.size()):
			if int(row[slot]) == card_id:
				row[slot] = _draw(tier)
				return


func _visit_noble(player: int) -> void:
	if not nobles_enabled:
		return
	for noble_id: int in nobles:
		if noble_id < 0 or noble_id >= NOBLES.size() or noble_owner[noble_id] >= 0:
			continue
		if not _meets_requirement(player, noble_id):
			continue
		noble_owner[noble_id] = player
		points[player] = int(points[player]) + VariantUtil.as_int(VariantUtil.as_dict(NOBLES[noble_id]).get("points", 0), 0)
		log_event("game.splendor.log_noble", {
			"player": player_name(player),
			"points": Loc.tp("game.splendor.points", VariantUtil.as_int(VariantUtil.as_dict(NOBLES[noble_id]).get("points", 0), 0)),
		}, player)
		return


func _meets_requirement(player: int, noble_id: int) -> bool:
	var cost: Array = VariantUtil.as_array(VariantUtil.as_dict(NOBLES[noble_id]).get("cost", []))
	for i: int in range(GEM_COLOURS.size()):
		if VariantUtil.as_int(bonuses[player].get(GEM_COLOURS[i], 0), 0) < int(cost[i]):
			return false
	return true


# ------------------------------------------------------------------ turn flow

func _finish_turn(player: int, purchased: bool, passed: bool) -> void:
	turn += 1
	round_index = (turn / maxi(1, player_count())) + 1
	if purchased:
		stale_actions = 0
	else:
		stale_actions += 1
	consecutive_passes = consecutive_passes + 1 if passed else 0
	_return_excess_tokens(player)
	var count := maxi(1, player_count())
	if final_turn == 0 and int(points[player]) >= target_points:
		# The round is played out completely: the match ends when the player who
		# crossed the target would move again.
		final_turn = ((turn - 1) / count + 1) * count
		log_event("game.splendor.log_final_round", {
			"player": player_name(player),
			"points": target_points,
		}, player)
	if final_turn > 0 and turn >= final_turn:
		_finish_by_score("game.splendor.reason_final_score")
	elif consecutive_passes >= count:
		_finish_by_score("game.splendor.reason_deadlock")
	elif stale_actions >= STALE_ACTION_LIMIT:
		_finish_by_score("game.splendor.reason_deadlock")


## Hand limit: returns the excess to the supply, most abundant colour first.
func _return_excess_tokens(player: int) -> void:
	var total := token_total(player)
	if total <= TOKEN_LIMIT:
		return
	var returned := 0
	while total > TOKEN_LIMIT:
		var colour := _most_abundant(player)
		tokens[player][colour] = VariantUtil.as_int(tokens[player][colour], 0) - 1
		piles[colour] = pile(colour) + 1
		total -= 1
		returned += 1
	log_event(_return_log_key(returned), {
		"player": player_name(player),
		"count": returned,
	}, player)


## Log key for returning `count` tokens (see [method _take_log_key]).
func _return_log_key(count: int) -> String:
	if count == 1:
		return "game.splendor.log_return.one"
	return "game.splendor.log_return.other"


func _most_abundant(player: int) -> String:
	var best := GOLD
	var best_count := -1
	for colour: String in ALL_COLOURS:
		var count := VariantUtil.as_int(tokens[player].get(colour, 0), 0)
		if count > best_count:
			best_count = count
			best = colour
	return best


func _finish_by_score(reason_key: String) -> void:
	var best_points := -1
	var leaders: Array[int] = []
	for player: int in range(player_count()):
		if int(points[player]) > best_points:
			best_points = int(points[player])
			leaders = [player]
		elif int(points[player]) == best_points:
			leaders.append(player)
	var winner := -1
	var reason := reason_key
	if leaders.size() == 1:
		winner = leaders[0]
	else:
		var fewest := card_counts[leaders[0]]
		for player: int in leaders:
			fewest = mini(fewest, int(card_counts[player]))
		var tied: Array[int] = []
		for player: int in leaders:
			if int(card_counts[player]) == fewest:
				tied.append(player)
		if tied.size() == 1:
			winner = tied[0]
		else:
			reason = "game.splendor.reason_tie"
	finish(winner, reason, _scores())


func _scores() -> Array:
	var out: Array = []
	for player: int in range(player_count()):
		out.append({"player": player, "name": player_name(player), "score": int(points[player])})
	return out


# ------------------------------------------------------------------ snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["piles"] = piles.duplicate()
	state["market"] = _copy_card_lists(market)
	# Engine bookkeeping: a snapshot must be able to continue the match, so the
	# hidden remainder of each deck travels with it. The view never renders it.
	state["_decks"] = _copy_card_lists(decks)
	state["nobles"] = nobles.duplicate()
	state["noble_owner"] = noble_owner.duplicate()
	state["tokens"] = _copy_dicts(tokens)
	state["bonuses"] = _copy_dicts(bonuses)
	state["points"] = points.duplicate()
	state["cards"] = card_counts.duplicate()
	state["reserved_counts"] = _reserved_counts()
	state["target_points"] = target_points
	state["nobles_enabled"] = nobles_enabled
	state["final_turn"] = final_turn
	state["_stale"] = stale_actions
	state["_passes"] = consecutive_passes
	return state


## Only the acting player's reserved cards are private in Splendor.
func private_state(player: int) -> Dictionary:
	var out: Array[int] = []
	if player >= 0 and player < reserved.size():
		for card_id: Variant in VariantUtil.as_array(reserved[player]):
			out.append(int(card_id))
	return {"reserved": out}


## Installs ONE seat's private reserve on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own reserves.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if not (slice.has("reserved") and slice.get("reserved") is Array):
		return
	if seat < 0 or seat >= player_count():
		return
	while reserved.size() < player_count():
		reserved.append(_empty_cards())
	var cards := _empty_cards()
	copy_int_array(slice.get("reserved", []), cards)
	reserved[seat] = cards


func _restore_extra(state: Dictionary) -> void:
	target_points = clampi(VariantUtil.as_int(state.get("target_points", DEFAULT_TARGET_POINTS), DEFAULT_TARGET_POINTS), 5, 30)
	nobles_enabled = bool(state.get("nobles_enabled", true))
	piles = VariantUtil.dict_copy(state.get("piles", {}))
	_restore_card_lists(state.get("market", []), market)
	_restore_card_lists(state.get("_decks", []), decks)
	copy_int_array(state.get("nobles", []), nobles)
	copy_int_array(state.get("noble_owner", []), noble_owner)
	tokens = _restore_dicts(state.get("tokens", []))
	bonuses = _restore_dicts(state.get("bonuses", []))
	copy_int_array(state.get("points", []), points)
	copy_int_array(state.get("cards", []), card_counts)
	final_turn = VariantUtil.as_int(state.get("final_turn", 0), 0)
	stale_actions = VariantUtil.as_int(state.get("_stale", 0), 0)
	consecutive_passes = VariantUtil.as_int(state.get("_passes", 0), 0)
	reserved = []
	for player: int in range(player_count()):
		var cards := _empty_cards()
		reserved.append(cards)
	# Private reserves arrive per seat: a save file keys one slice per seat
	# under "private_states"; the harness/online client shape merges the acting
	# player's flat list at the top level; whole-match snapshots use a
	# per-player array of lists under "reserved".
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	if not privates.is_empty():
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("reserved") and (state.get("reserved", []) is Array):
		var source: Array = state.get("reserved", [])
		if source.size() > 0 and source[0] is Array:
			# Whole-match form: one list per player.
			for player: int in range(player_count()):
				if player < source.size() and source[player] is Array:
					var cards := _empty_cards()
					copy_int_array(source[player], cards)
					reserved[player] = cards
		else:
			# Client shape (harness contract): the acting player's flat list.
			if decision_player() >= 0 and decision_player() < player_count():
				var cards := _empty_cards()
				copy_int_array(source, cards)
				reserved[decision_player()] = cards


## Convenience for hosts and tests: merge every player's private snapshot into
## this engine after [method restore_state].
func restore_reserved(privates: Array) -> void:
	reserved = []
	for player: int in range(player_count()):
		var cards := _empty_cards()
		if player < privates.size() and privates[player] is Dictionary:
			copy_int_array(VariantUtil.as_dict(privates[player]).get("reserved", []), cards)
		reserved.append(cards)


func _reserved_counts() -> Array[int]:
	var out: Array[int] = []
	for player: int in range(player_count()):
		out.append(reserved_count(player))
	return out


func _copy_card_lists(source: Array) -> Array:
	var out: Array = []
	for tier: int in range(source.size()):
		var copy: Array[int] = []
		copy_int_array(source[tier], copy)
		out.append(copy)
	return out


func _copy_dicts(source: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry: Dictionary in source:
		out.append(entry.duplicate())
	return out


func _restore_card_lists(source: Variant, target: Array) -> void:
	var rows: Array = source if source is Array else []
	target.clear()
	for tier: int in range(rows.size()):
		if not (rows[tier] is Array):
			continue
		var row: Array[int] = []
		copy_int_array(rows[tier], row)
		target.append(row)


func _restore_dicts(source: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if source is Array:
		for entry: Variant in source:
			if entry is Dictionary:
				out.append(VariantUtil.dict_copy(entry))
	return out
