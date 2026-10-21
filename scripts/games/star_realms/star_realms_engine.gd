class_name StarRealmsEngine
extends GameEngine
## Star Realms rules engine (deck-building card game for 2-4 players).
##
## Every player starts with the same 10-card personal deck (8 Scouts, 2 Vipers)
## and 50 authority. On a turn a player draws up to 5 cards, plays them for
## trade (used to buy cards from the shared trade row) and combat (used to
## destroy bases and to damage the opponent's authority), then discards the hand.
## Bought cards go to the discard pile, so a deck grows stronger over time.
## A player wins when every opponent's authority has been reduced to 0
## (the authority-pile variant used by this implementation).
##
## Implemented rules: the trade row of 5 cards plus the always available
## Explorer, base and outpost defence (outposts must be destroyed before their
## owner can be attacked), ally abilities (another card of the same faction in
## play), scrap abilities (the card leaves the game), optional "scrap a card /
## a trade-row card" effects and "destroy a base" abilities. Destroyed and
## scrapped bases go to their owner's discard pile; scrapped cards leave the game.
##
## Deliberate simplifications: a card's combat must be spent in one go (bases are
## destroyed for exactly their defence, authority takes the whole remaining
## pool), and optional effects stay available until the end of the turn.
##
## The engine is deterministic: every shuffle uses the inherited [member rng], so
## the same seed and the same action sequence always produce the same state.
## Hands, decks and discard piles are private - [method legal_actions] only ever
## answers for the player whose input the engine is waiting for.

const START_AUTHORITY: int = 50
const HAND_SIZE: int = 5
const TRADE_ROW_SIZE: int = 5
const EXPLORER_COST: int = 2
## Safety net so a pathological match cannot run forever; a real match ends long
## before this many turns.
const MAX_TURNS: int = 600

var trade_row: Array[Dictionary] = []
var trade_deck: Array[Dictionary] = []
## Per-player table state: authority, hand/deck/discard/removed, cards in play,
## bases, the current pools and the optional effects waiting for a target.
var boards: Array[Dictionary] = []
var used_sets: PackedStringArray = PackedStringArray(["sr_core"])
var turn_player: int = 0
var turns_started: int = 0
var last_event: Dictionary = {}

var _next_uid: int = 1
var _uid_hint: int = 0
## Trade-deck size remembered from the last restored snapshot: a client that only
## receives [method public_state] knows how many cards are left even though the
## deck itself stays hidden.
var _public_trade_deck_count: int = 0
## True when this engine holds the REAL shuffled deck order (after setup, or a
## restore that carried the seat -1 table secret). While false the public count
## memory is the only source for [code]trade_deck_count[/code].
var _trade_deck_known: bool = false


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "star_realms"


func setup(options: Dictionary) -> void:
	super.setup(options)
	var authority := clampi(int(options.get("authority", START_AUTHORITY)), 20, 120)
	used_sets = _selected_sets(options)
	_next_uid = 1
	_public_trade_deck_count = 0
	trade_row.clear()
	trade_deck.clear()
	boards.clear()
	last_event = {}

	var deck: Array[Dictionary] = []
	for definition: Dictionary in StarRealmsCards.pool_for_sets(used_sets):
		for copy: int in range(int(definition.copies)):
			deck.append(_make_instance(String(definition.id)))
	_shuffle(deck)
	trade_deck = deck
	_trade_deck_known = true
	_refill_row()

	for index: int in range(player_count()):
		var board := {
			"index": index,
			"authority": authority,
			"hand": [] as Array,
			"deck": [] as Array,
			"discard": [] as Array,
			"removed": [] as Array,
			"in_play": [] as Array,
			"bases": [] as Array,
			"pending": [] as Array,
			"trade": 0,
			"combat": 0,
		}
		boards.append(board)
		for entry: Dictionary in StarRealmsCards.STARTING_CARDS:
			for copy: int in range(int(entry.copies)):
				board.deck.append(_make_instance(String(entry.id)))
		_shuffle(board.deck)
		_draw(index, HAND_SIZE)

	turn_player = 0
	turns_started = 0
	round_index = 1
	_begin_turn(0)
	log_event("game.star_realms.log_start", {
		"players": _player_list(),
		"sets": _sets_label(),
		"authority": authority,
	})


func phases() -> PackedStringArray:
	return PackedStringArray(["play", "finished"])


func phase() -> String:
	return "finished" if finished else "play"


func decision_player() -> int:
	return turn_player


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "authority", "label_key": "game.star_realms.option.authority", "type": "int",
			"default": START_AUTHORITY, "min": 20, "max": 100,
			"hint_key": "game.star_realms.option.authority_hint"},
		{"key": "editions", "label_key": "game.star_realms.option.editions", "type": "enum",
			"default": "selected", "values": ["selected", "core"],
			"labels": {
				"selected": "game.star_realms.option.editions_selected",
				"core": "game.star_realms.option.editions_core",
			},
			"hint_key": "game.star_realms.option.editions_hint"},
	]


# --------------------------------------------------------------- setup helpers

## Enabled sets for a match: the setup option first, the player's edition
## selection from [Prefs] as the default, and only sets the pool implements.
func _selected_sets(options: Dictionary) -> PackedStringArray:
	var requested := PackedStringArray()
	if String(options.get("editions", "selected")) != "core":
		requested = _string_list(options.get("sets", []))
	if requested.is_empty():
		requested = _string_list(Prefs.selected_star_realms_sets())
	var implemented := StarRealmsCards.implemented_sets()
	var out := PackedStringArray()
	for set_id: String in requested:
		if implemented.has(set_id) and not out.has(set_id):
			out.append(set_id)
	if not out.has(StarRealmsCards.SET_CORE):
		out.insert(0, StarRealmsCards.SET_CORE)
	return out


func _string_list(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			var text := String(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	elif value is String and not String(value).is_empty():
		for item: String in String(value).split(",", false):
			var text := item.strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out


func _sets_label() -> String:
	var names := PackedStringArray()
	for set_id: String in used_sets:
		names.append(Loc.t("sr.set.%s.name" % set_id))
	return ", ".join(names)


func _player_list() -> String:
	var names := PackedStringArray()
	for index: int in range(player_count()):
		names.append(player_name(index))
	return ", ".join(names)


func _make_instance(card_id: String) -> Dictionary:
	var instance := {"uid": _next_uid, "id": card_id}
	_next_uid += 1
	_uid_hint = maxi(_uid_hint, _next_uid)
	return instance


## Deterministic Fisher-Yates in place; [method RandomNumberGenerator.shuffle]
## would use the global RNG, which is not seeded from the match seed.
func _shuffle(cards: Array) -> void:
	for index: int in range(cards.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		if other == index:
			continue
		var swap: Variant = cards[index]
		cards[index] = cards[other]
		cards[other] = swap


# ------------------------------------------------------------------- accessors

func board_of(player: int) -> Dictionary:
	if player < 0 or player >= boards.size():
		return {}
	return boards[player]


func authority_of(player: int) -> int:
	return int(board_of(player).get("authority", 0))


func trade_of(player: int) -> int:
	return int(board_of(player).get("trade", 0))


func combat_of(player: int) -> int:
	return int(board_of(player).get("combat", 0))


func hand_of(player: int) -> Array:
	return board_of(player).get("hand", [])


func deck_of(player: int) -> Array:
	return board_of(player).get("deck", [])


func discard_of(player: int) -> Array:
	return board_of(player).get("discard", [])


func removed_of(player: int) -> Array:
	return board_of(player).get("removed", [])


func in_play_of(player: int) -> Array:
	return board_of(player).get("in_play", [])


func bases_of(player: int) -> Array:
	return board_of(player).get("bases", [])


func trade_deck_size() -> int:
	return trade_deck.size()


# ------------------------------------------------------------- test/debug hooks

## Test hook: adds trade and combat to a player's pool.
func grant(player: int, trade: int, combat: int) -> void:
	var board := board_of(player)
	if board.is_empty():
		return
	board["trade"] = int(board.trade) + trade
	board["combat"] = int(board.combat) + combat


## Test hook: sets a player's authority (a value of 0 or less eliminates them).
func set_authority(player: int, value: int) -> void:
	var board := board_of(player)
	if board.is_empty():
		return
	board["authority"] = maxi(0, value)


## Test hook: replaces a player's hand with the given card ids.
func debug_set_hand(player: int, card_ids: Array) -> void:
	var board := board_of(player)
	if board.is_empty():
		return
	var hand: Array = []
	for card_id: Variant in card_ids:
		hand.append(_make_instance(String(card_id)))
	board["hand"] = hand
	board["pending"] = []


## Test hook: puts a card into a player's base area (as if it had been played).
func debug_play_base(player: int, card_id: String) -> void:
	var board := board_of(player)
	if board.is_empty():
		return
	board.bases.append(_make_instance(card_id))


## Test hook: replaces the trade row with the given card ids and refills it.
func debug_set_row(card_ids: Array) -> void:
	var row: Array[Dictionary] = []
	for card_id: Variant in card_ids:
		row.append(_make_instance(String(card_id)))
	trade_row = row
	_refill_row()


# -------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	## Only the player whose input the engine waits for gets a list: hands are
	## private, so answering for anybody else would leak hidden information.
	var out: Array[Dictionary] = []
	if finished or player != decision_player():
		return out
	var board := board_of(player)
	if board.is_empty():
		return out

	for card: Dictionary in board.hand:
		out.append(_entry("play_card", {"card": int(card.uid)}))

	var pending := _pending_kinds(board)
	for kind: String in pending.keys():
		match kind:
			"scrap_hand":
				for card: Dictionary in board.hand:
					out.append(_entry("scrap_hand", {"card": int(card.uid)}))
			"scrap_row":
				for slot: int in range(trade_row.size()):
					out.append(_entry("scrap_row", {"slot": slot}))
			"destroy_base":
				for other: int in range(player_count()):
					if other == player:
						continue
					for index: int in range(bases_of(other).size()):
						# Outpost protection covers destruction too: while an
						# outpost is in play only it may be targeted.
						if not _may_target_base(other, index):
							continue
						out.append(_entry("destroy_base", {"player": other, "base": index}))

	for slot: int in range(trade_row.size()):
		if int(board.trade) >= StarRealmsCards.cost_of(String(trade_row[slot].id)):
			out.append(_entry("buy", {"slot": slot}))
	if int(board.trade) >= EXPLORER_COST:
		out.append(_entry("buy_explorer", {}))

	if int(board.combat) > 0:
		for other: int in range(player_count()):
			if other == player or authority_of(other) <= 0:
				continue
			if _has_outpost(other):
				continue
			out.append(_entry("attack_authority", {"player": other}))
		for other: int in range(player_count()):
			if other == player or authority_of(other) <= 0:
				continue
			var bases := bases_of(other)
			for index: int in range(bases.size()):
				var card_id := String(bases[index].id)
				if int(board.combat) < StarRealmsCards.defense_of(card_id):
					continue
				if not _may_target_base(other, index):
					continue
				out.append(_entry("attack_base", {"player": other, "base": index}))

	for card: Dictionary in board.in_play:
		if StarRealmsCards.has_scrap(String(card.id)):
			out.append(_entry("scrap_play", {"card": int(card.uid)}))
	for card: Dictionary in board.bases:
		if StarRealmsCards.has_scrap(String(card.id)):
			out.append(_entry("scrap_play", {"card": int(card.uid)}))

	out.append(_entry("end_turn", {}, "game.star_realms.action_end_turn"))
	return out


func _entry(action_type: String, params: Dictionary, label_key: String = "") -> Dictionary:
	var action := make_action(action_type, params, label_key)
	action["_direct"] = not label_key.is_empty()
	return action


## Pending optional effects by kind, deduplicated: using one consumes a single
## entry, so offering the same target twice would only create duplicate keys.
func _pending_kinds(board: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for effect: Variant in board.get("pending", []):
		if effect is Dictionary:
			var kind := String((effect as Dictionary).get("kind", ""))
			counts[kind] = int(counts.get(kind, 0)) + int((effect as Dictionary).get("count", 1))
	return counts


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var actor := decision_player()
	var chosen: Dictionary = {}
	for candidate: Dictionary in legal_actions(actor):
		if String(candidate.get("key", "")) == String(action.get("key", "")):
			chosen = candidate
			break
	if chosen.is_empty():
		return _fail(_rejection(action, actor))
	_resolve(actor, chosen)
	turn += 1
	_check_end()
	if not finished:
		state_changed.emit()
	return _ok(action)


## Explains why a submitted action is not in the current legal list.
func _rejection(action: Dictionary, actor: int) -> String:
	match String(action.get("type", "")):
		"play_card":
			return "game.star_realms.error.no_such_card"
		"scrap_hand":
			if not _pending_has(actor, "scrap_hand"):
				return "game.star_realms.error.no_effect"
			return "game.star_realms.error.no_such_card"
		"scrap_play":
			return "game.star_realms.error.no_such_card"
		"buy":
			var slot := int(action.get("slot", -1))
			if slot >= 0 and slot < trade_row.size():
				return "game.star_realms.error.cannot_afford"
			return "game.star_realms.error.no_such_card"
		"buy_explorer":
			return "game.star_realms.error.cannot_afford"
		"attack_authority":
			var target := int(action.get("player", -1))
			if target < 0 or target >= player_count() or authority_of(target) <= 0:
				return "game.star_realms.error.no_such_card"
			if _has_outpost(target):
				return "game.star_realms.error.outpost_blocks"
			return "game.star_realms.error.no_combat"
		"attack_base":
			var owner := int(action.get("player", -1))
			var index := int(action.get("base", -1))
			if owner < 0 or owner >= player_count() or index < 0 or index >= bases_of(owner).size():
				return "game.star_realms.error.no_such_card"
			if not _may_target_base(owner, index):
				return "game.star_realms.error.outpost_blocks"
			return "game.star_realms.error.no_combat"
		"scrap_row":
			if not _pending_has(actor, "scrap_row"):
				return "game.star_realms.error.no_effect"
			return "game.star_realms.error.no_such_card"
		"destroy_base":
			if not _pending_has(actor, "destroy_base"):
				return "game.star_realms.error.no_effect"
			var db_owner := int(action.get("player", -1))
			var db_index := int(action.get("base", -1))
			if not _may_target_base(db_owner, db_index):
				return "game.star_realms.error.outpost_blocks"
			return "game.star_realms.error.no_such_card"
		"end_turn":
			return "game.common.illegal_action"
		_:
			return "game.star_realms.error.unknown_action"


func _resolve(actor: int, action: Dictionary) -> void:
	last_event = {"kind": String(action.get("type", "")), "player": actor}
	match String(action.get("type", "")):
		"play_card":
			_play_card(actor, int(action.get("card", -1)))
		"buy":
			_buy(actor, int(action.get("slot", -1)))
		"buy_explorer":
			_buy_explorer(actor)
		"attack_authority":
			_attack_authority(actor, int(action.get("player", -1)))
		"attack_base":
			_attack_base(actor, int(action.get("player", -1)), int(action.get("base", -1)))
		"scrap_play":
			_scrap_play(actor, int(action.get("card", -1)))
		"scrap_hand":
			_scrap_hand(actor, int(action.get("card", -1)))
		"scrap_row":
			_scrap_row(actor, int(action.get("slot", -1)))
		"destroy_base":
			_destroy_base(actor, int(action.get("player", -1)), int(action.get("base", -1)))
		"end_turn":
			_end_turn(actor)


# -------------------------------------------------------------- action effects

func _play_card(actor: int, uid: int) -> void:
	var board := board_of(actor)
	var card := _take_card(board.hand, uid)
	if card.is_empty():
		return
	var card_id := String(card.id)
	var definition := StarRealmsCards.by_id(card_id)
	var ally_ready := _faction_in_play(actor, String(definition.get("faction", ""))) > 0
	if StarRealmsCards.is_base(card_id):
		board.bases.append(card)
	else:
		board.in_play.append(card)
	last_event["card"] = StarRealmsCards.name_of(card_id)
	log_event("game.star_realms.log_play", {
		"player": player_name(actor),
		"card": StarRealmsCards.name_of(card_id),
	}, actor)
	_apply_effects(actor, definition)
	var ally: Variant = definition.get("ally", {})
	if ally_ready and ally is Dictionary and not (ally as Dictionary).is_empty():
		log_event("game.star_realms.log_ally", {
			"player": player_name(actor),
			"card": StarRealmsCards.name_of(card_id),
		}, actor)
		_apply_effects(actor, ally)


func _apply_effects(actor: int, ability: Dictionary) -> void:
	if ability.is_empty():
		return
	var board := board_of(actor)
	board["trade"] = int(board.trade) + int(ability.get("trade", 0))
	board["combat"] = int(board.combat) + int(ability.get("combat", 0))
	board["authority"] = int(board.authority) + int(ability.get("authority", 0))
	var draw := int(ability.get("draw", 0))
	if draw > 0:
		_draw(actor, draw)
	if int(ability.get("scrap_hand", 0)) > 0:
		board.pending.append({"kind": "scrap_hand", "count": 1})
	if int(ability.get("scrap_row", 0)) > 0:
		board.pending.append({"kind": "scrap_row", "count": 1})
	if int(ability.get("destroy_base", 0)) > 0:
		board.pending.append({"kind": "destroy_base", "count": 1})


func _buy(actor: int, slot: int) -> void:
	if slot < 0 or slot >= trade_row.size():
		return
	var board := board_of(actor)
	var card: Dictionary = trade_row[slot]
	var card_id := String(card.id)
	var cost := StarRealmsCards.cost_of(card_id)
	board["trade"] = int(board.trade) - cost
	trade_row.remove_at(slot)
	board.discard.append(card)
	_refill_row()
	last_event["card"] = StarRealmsCards.name_of(card_id)
	log_event("game.star_realms.log_buy", {
		"player": player_name(actor),
		"card": StarRealmsCards.name_of(card_id),
		"cost": cost,
	}, actor)


func _buy_explorer(actor: int) -> void:
	var board := board_of(actor)
	board["trade"] = int(board.trade) - EXPLORER_COST
	board.discard.append(_make_instance(StarRealmsCards.EXPLORER))
	last_event["card"] = StarRealmsCards.name_of(StarRealmsCards.EXPLORER)
	log_event("game.star_realms.log_explorer", {
		"player": player_name(actor),
		"cost": EXPLORER_COST,
	}, actor)


func _attack_authority(actor: int, target: int) -> void:
	if target < 0 or target >= boards.size():
		return
	var board := board_of(actor)
	var damage := int(board.combat)
	board["combat"] = 0
	boards[target]["authority"] = maxi(0, authority_of(target) - damage)
	log_event("game.star_realms.log_attack", {
		"player": player_name(actor),
		"target": player_name(target),
		"damage": damage,
	}, actor)
	if authority_of(target) <= 0:
		_eliminate(target)


func _attack_base(actor: int, owner: int, index: int) -> void:
	if not _may_target_base(owner, index):
		return
	var board := board_of(actor)
	var bases := bases_of(owner)
	var card: Dictionary = bases[index]
	var card_id := String(card.id)
	var defense := StarRealmsCards.defense_of(card_id)
	board["combat"] = int(board.combat) - defense
	bases.remove_at(index)
	boards[owner].discard.append(card)
	last_event["card"] = StarRealmsCards.name_of(card_id)
	log_event("game.star_realms.log_base_destroyed", {
		"player": player_name(actor),
		"owner": player_name(owner),
		"card": StarRealmsCards.name_of(card_id),
	}, actor)


func _scrap_play(actor: int, uid: int) -> void:
	var board := board_of(actor)
	var card: Dictionary = _take_card(board.in_play, uid)
	if card.is_empty():
		card = _take_card(board.bases, uid)
	if card.is_empty():
		return
	board.removed.append(card)
	var card_id := String(card.id)
	last_event["card"] = StarRealmsCards.name_of(card_id)
	log_event("game.star_realms.log_scrap", {
		"player": player_name(actor),
		"card": StarRealmsCards.name_of(card_id),
	}, actor)
	_apply_effects(actor, StarRealmsCards.by_id(card_id).get("scrap", {}))


func _scrap_hand(actor: int, uid: int) -> void:
	var board := board_of(actor)
	var card := _take_card(board.hand, uid)
	if card.is_empty():
		return
	board.removed.append(card)
	_consume_pending(actor, "scrap_hand")
	log_event("game.star_realms.log_scrap_hand", {
		"player": player_name(actor),
		"card": StarRealmsCards.name_of(String(card.id)),
	}, actor)


func _scrap_row(actor: int, slot: int) -> void:
	if slot < 0 or slot >= trade_row.size():
		return
	var board := board_of(actor)
	var card: Dictionary = trade_row[slot]
	trade_row.remove_at(slot)
	board.removed.append(card)
	_refill_row()
	_consume_pending(actor, "scrap_row")
	log_event("game.star_realms.log_scrap_row", {
		"player": player_name(actor),
		"card": StarRealmsCards.name_of(String(card.id)),
	}, actor)


func _destroy_base(actor: int, owner: int, index: int) -> void:
	var bases := bases_of(owner)
	if index < 0 or index >= bases.size():
		return
	# Outpost protection is a rules boundary, not a UI hint: re-validated here
	# so no caller can resolve a protected base (§6.7).
	if not _may_target_base(owner, index):
		return
	var card: Dictionary = bases[index]
	bases.remove_at(index)
	boards[owner].discard.append(card)
	_consume_pending(actor, "destroy_base")
	log_event("game.star_realms.log_base_destroyed", {
		"player": player_name(actor),
		"owner": player_name(owner),
		"card": StarRealmsCards.name_of(String(card.id)),
	}, actor)


func _end_turn(actor: int) -> void:
	var board := board_of(actor)
	for card: Dictionary in board.in_play:
		board.discard.append(card)
	for card: Dictionary in board.hand:
		board.discard.append(card)
	board["in_play"] = [] as Array
	board["hand"] = [] as Array
	board["pending"] = [] as Array
	board["trade"] = 0
	board["combat"] = 0
	var next := _next_alive(actor)
	if next < 0:
		return
	_begin_turn(next)


# ------------------------------------------------------------------ turn flow

func _begin_turn(player: int) -> void:
	turn_player = player
	turns_started += 1
	var board := board_of(player)
	board["trade"] = 0
	board["combat"] = 0
	board["pending"] = [] as Array
	_draw(player, maxi(0, HAND_SIZE - board.hand.size()))
	round_index = 1 + int(turns_started / maxi(1, player_count()))
	log_event("game.star_realms.log_turn", {
		"player": player_name(player),
		"round": round_index,
	}, player)


func _next_alive(from_player: int) -> int:
	var total := maxi(1, player_count())
	for step: int in range(1, total + 1):
		var index := (from_player + step) % total
		if authority_of(index) > 0:
			return index
	return -1


func _draw(player: int, count: int) -> int:
	var board := board_of(player)
	var drawn := 0
	while drawn < count:
		if board.deck.is_empty():
			if board.discard.is_empty():
				break
			board["deck"] = board.discard
			board["discard"] = [] as Array
			_shuffle(board.deck)
		board.hand.append(board.deck.pop_back())
		drawn += 1
	return drawn


func _refill_row() -> void:
	while trade_row.size() < TRADE_ROW_SIZE and not trade_deck.is_empty():
		trade_row.append(trade_deck.pop_back())


func _faction_in_play(player: int, faction: String) -> int:
	if faction.is_empty() or faction == StarRealmsCards.FACTION_UNALIGNED:
		return 0
	var count := 0
	for card: Dictionary in in_play_of(player):
		if StarRealmsCards.faction_of(String(card.id)) == faction:
			count += 1
	for card: Dictionary in bases_of(player):
		if StarRealmsCards.faction_of(String(card.id)) == faction:
			count += 1
	return count


## Outposts of one player block attacks against that player's other bases and
## authority (the rule is per player, so another opponent's outpost is irrelevant).
func _has_outpost(player: int) -> bool:
	for card: Dictionary in bases_of(player):
		if StarRealmsCards.is_outpost(String(card.id)):
			return true
	return false


func _may_target_base(owner: int, index: int) -> bool:
	if owner < 0 or owner >= boards.size():
		return false
	var bases := bases_of(owner)
	if index < 0 or index >= bases.size():
		return false
	if not _has_outpost(owner):
		return true
	return StarRealmsCards.is_outpost(String(bases[index].id))


func _take_card(cards: Array, uid: int) -> Dictionary:
	for index: int in range(cards.size()):
		if int((cards[index] as Dictionary).get("uid", -1)) == uid:
			return cards.pop_at(index)
	return {}


func _consume_pending(player: int, kind: String) -> void:
	var pending: Array = boards[player].get("pending", [])
	for index: int in range(pending.size()):
		var effect: Dictionary = pending[index]
		if String(effect.get("kind", "")) != kind:
			continue
		if int(effect.get("count", 1)) > 1:
			effect["count"] = int(effect.count) - 1
		else:
			pending.remove_at(index)
		return


func _pending_has(player: int, kind: String) -> bool:
	for effect: Variant in boards[player].get("pending", []):
		if effect is Dictionary and String((effect as Dictionary).get("kind", "")) == kind:
			return true
	return false


func _eliminate(player: int) -> void:
	## A player who ran out of authority leaves the table; their cards go to the
	## discard pile so that nothing of theirs blocks the remaining players.
	var board := board_of(player)
	for card: Dictionary in board.in_play:
		board.discard.append(card)
	for card: Dictionary in board.bases:
		board.discard.append(card)
	for card: Dictionary in board.hand:
		board.discard.append(card)
	board["in_play"] = [] as Array
	board["bases"] = [] as Array
	board["hand"] = [] as Array
	board["pending"] = [] as Array
	board["trade"] = 0
	board["combat"] = 0
	log_event("game.star_realms.log_eliminated", {"player": player_name(player)}, player)


# ----------------------------------------------------------------- match end

func _check_end() -> void:
	if finished:
		return
	var alive: Array[int] = []
	for index: int in range(player_count()):
		if authority_of(index) > 0:
			alive.append(index)
	if alive.size() <= 1:
		finish(alive[0] if alive.size() == 1 else -1, "game.star_realms.reason_last_standing", _scores())
		return
	if turns_started > MAX_TURNS:
		finish(_leader(), "game.star_realms.reason_exhausted", _scores())


func _leader() -> int:
	var best := -1
	var best_value := -1
	for index: int in range(player_count()):
		var value := authority_of(index)
		if value > best_value:
			best_value = value
			best = index
	return best


func _scores() -> Array:
	var out: Array = []
	for index: int in range(player_count()):
		out.append({
			"player": index,
			"name": player_name(index),
			"score": authority_of(index),
		})
	return out


# ------------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	var seats: Array = []
	for index: int in range(boards.size()):
		var board: Dictionary = boards[index]
		seats.append({
			"index": index,
			"authority": int(board.authority),
			"hand_count": _public_count(board, "hand", board.hand),
			"deck_count": _public_count(board, "deck", board.deck),
			"discard_count": _public_count(board, "discard", board.discard),
			"removed_count": _public_count(board, "removed", board.removed),
			"trade": int(board.trade),
			"combat": int(board.combat),
			"in_play": _cards(board.in_play),
			"bases": _cards(board.bases),
			"pending": _pending_texts(board),
		})
	var sets: Array = []
	for set_id: String in used_sets:
		sets.append(set_id)
	state["seats"] = seats
	state["trade_row"] = _cards(trade_row)
	# With the real deck in hand the array is the truth; a public-only mirror
	# falls back to the remembered count so a draw-free client still shows the
	# market size.
	state["trade_deck_count"] = trade_deck.size() if _trade_deck_known else maxi(0, _public_trade_deck_count)
	state["sets"] = sets
	state["turn_player"] = turn_player
	state["turns_started"] = turns_started
	state["_last_event"] = last_event.duplicate(true)
	return state


func private_state(player: int) -> Dictionary:
	if player == -1:
		# Table secret: the shuffled trade deck order matters for every later
		# refill, but only a whole-table snapshot (a save file) may carry it -
		# never a seat's slice.
		return {"trade_deck": trade_deck.duplicate(true)}
	if player < 0 or player >= boards.size():
		return {}
	var board: Dictionary = boards[player]
	return {
		"hand": _cards(board.hand),
		"deck": _cards(board.deck),
		"discard": _cards(board.discard),
		"removed": _cards(board.removed),
	}


func _cards(cards: Array) -> Array:
	var out: Array = []
	for card: Variant in cards:
		if card is Dictionary:
			out.append((card as Dictionary).duplicate(true))
	return out


func _pending_texts(board: Dictionary) -> Array:
	var out: Array = []
	for effect: Variant in board.get("pending", []):
		if effect is Dictionary:
			out.append((effect as Dictionary).duplicate(true))
	return out


## Public size of a private zone: for a board this engine truly holds (live
## play or a slice adoption) the zone array is the authority; a public mirror
## board (zones knowingly empty) answers with the remembered snapshot counts.
func _public_count(board: Dictionary, key: String, zone: Array) -> int:
	if not bool(board.get("_mirror", false)):
		return zone.size()
	var known: Dictionary = board.get("known", {}) as Dictionary
	return int(known.get(key, 0))


func _restore_extra(state: Dictionary) -> void:
	used_sets = PackedStringArray()
	copy_string_array(state.get("sets", ["sr_core"]), used_sets)
	if used_sets.is_empty():
		used_sets.append("sr_core")
	_fill_instances(state.get("trade_row", []), trade_row)
	# The trade deck order is a table secret: whole-match snapshots carry it at
	# the top level, save files under the "-1" bag key. Without it the packed
	# counts stay but refills cannot produce the real next cards.
	var privates_bag: Variant = state.get("private_states", {})
	var table_secret: Dictionary = privates_bag.get("-1", {}) if privates_bag is Dictionary else {}
	if table_secret.has("trade_deck"):
		_fill_instances(table_secret.get("trade_deck", []), trade_deck)
		_trade_deck_known = true
		_public_trade_deck_count = trade_deck.size()
	elif state.has("trade_deck"):
		_fill_instances(state.get("trade_deck", []), trade_deck)
		_trade_deck_known = true
		_public_trade_deck_count = trade_deck.size()
	else:
		# Public-only mirror: the deck stays hidden; the remembered count is
		# the only source for the emitted size.
		_trade_deck_known = false
		_public_trade_deck_count = int(state.get("trade_deck_count", 0))
	last_event = (state.get("_last_event", {}) as Dictionary).duplicate(true)
	turn_player = int(state.get("turn_player", 0))
	turns_started = int(state.get("turns_started", 0))

	boards.clear()
	var seats: Array = state.get("seats", [])
	for index: int in range(seats.size()):
		var seat: Dictionary = seats[index]
		boards.append({
			"index": index,
			"authority": int(seat.get("authority", 0)),
			"hand": [] as Array,
			"deck": [] as Array,
			"discard": [] as Array,
			"removed": [] as Array,
			"in_play": _instances(seat.get("in_play", [])),
			"bases": _instances(seat.get("bases", [])),
			"pending": _instances(seat.get("pending", [])),
			"trade": int(seat.get("trade", 0)),
			"combat": int(seat.get("combat", 0)),
			# Zone sizes are public information: a mirror that only receives the
			# public snapshot still shows the right card counts. `_mirror`
			# marks that this board's zones are NOT held locally — a slice
			# adoption clears it for the seat it installs.
			"known": {
				"hand": int(seat.get("hand_count", 0)),
				"deck": int(seat.get("deck_count", 0)),
				"discard": int(seat.get("discard_count", 0)),
				"removed": int(seat.get("removed_count", 0)),
			},
			"_mirror": true,
		})
	# Private zones arrive per seat: a save file keys one slice per seat under
	# "private_states"; the harness/online client shape merges the acting
	# player's zones at the top level. Both paths run through the same
	# per-seat installer.
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	if not privates.is_empty():
		for seat: int in range(boards.size()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hand"):
		# Client shape (harness contract): zones attributed to the decision
		# player — exactly what [method private_state] produces and what a
		# client receives together with the public snapshot.
		_adopt_private_extra(decision_player(), state)
	_next_uid = _highest_uid() + 1
	_uid_hint = _next_uid


## Installs ONE seat's private zones on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own cards.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat == -1:
		# Table secret: the shuffled trade deck, for whole-table restores.
		if slice.has("trade_deck"):
			_fill_instances(slice.get("trade_deck", []), trade_deck)
			_trade_deck_known = true
			_public_trade_deck_count = trade_deck.size()
		return
	if seat < 0 or seat >= boards.size():
		return
	if not (slice.has("hand") or slice.has("deck") or slice.has("discard") or slice.has("removed")):
		return
	var board: Dictionary = boards[seat]
	var hand: Array = _instances(slice.get("hand", []))
	var deck_zone: Array = _instances(slice.get("deck", []))
	var discard_zone: Array = _instances(slice.get("discard", []))
	var removed_zone: Array = _instances(slice.get("removed", []))
	board["hand"] = hand
	board["deck"] = deck_zone
	board["discard"] = discard_zone
	board["removed"] = removed_zone
	board["known"] = {
		"hand": hand.size(),
		"deck": deck_zone.size(),
		"discard": discard_zone.size(),
		"removed": removed_zone.size(),
	}
	# This board's cards now live here locally: the zone array, not the public
	# count memory, is the authority for its sizes.
	board["_mirror"] = false


## Copies a snapshot list into a typed `Array[Dictionary]` field. Snapshots arrive
## as plain untyped arrays, and assigning one straight to a typed array is a
## runtime error in Godot, so the copy is element-wise.
func _fill_instances(source: Variant, target: Array[Dictionary]) -> void:
	target.clear()
	if source is Array:
		for item: Variant in source:
			if item is Dictionary:
				target.append((item as Dictionary).duplicate(true))


func _instances(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary and (item as Dictionary).has("id"):
				out.append({
					"uid": int((item as Dictionary).get("uid", 0)),
					"id": String((item as Dictionary).get("id", "")),
				})
			elif item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out


func _highest_uid() -> int:
	var highest := 0
	for card: Variant in trade_row:
		highest = maxi(highest, int((card as Dictionary).get("uid", 0)))
	for card: Variant in trade_deck:
		highest = maxi(highest, int((card as Dictionary).get("uid", 0)))
	for board: Dictionary in boards:
		for key: String in ["hand", "deck", "discard", "removed", "in_play", "bases"]:
			for card: Variant in board.get(key, []):
				highest = maxi(highest, int((card as Dictionary).get("uid", 0)))
	return highest
