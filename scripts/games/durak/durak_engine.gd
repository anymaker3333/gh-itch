class_name DurakEngine
extends GameEngine
## Durak for two to four players, played with the classic 36-card deck (6..Ace).
##
## Rules implemented:
##  * The deck is shuffled with the seeded RNG. The bottom card is turned face up
##    and fixes the trump suit; it is the last card drawn.
##  * Every player is dealt `hand_size` cards (six by default). After each round
##    players draw back up to that size, starting with the attacker; the defender
##    draws last.
##  * The player holding the lowest trump opens the first attack (seat 0 when
##    nobody holds a trump).
##  * The defender answers one attack card at a time: a card is beaten by a higher
##    card of the same suit or by any trump, and a trump only by a higher trump.
##    The defender may always pick the whole table up instead.
##  * Every player except the defender may join the attack, but added cards must
##    repeat a rank already present on the table. A round holds at most six attack
##    cards and never more than the defender held at the start of the round.
##  * A fully beaten table is discarded and the defender takes over the attack;
##    after a pick-up the turn passes to the next player with cards.
##  * Match end: when one player is left holding cards that player is the fool.
##    `winner` is the player who shed their hand last; everyone else who went out
##    shares the win. If the last cards leave play together the match is a draw.
##
## Hidden information: only [method private_state] carries a hand. A snapshot
## restored from [method public_state] alone is a spectator model - it knows the
## counts, not the cards - which is why online clients receive their legal action
## list from the host instead of recomputing it (see [GameSession]).

const SUITS: Array[String] = ["S", "H", "D", "C"]
const RANKS: Array[String] = ["6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const ACTION_TYPES: Array[String] = ["attack", "defend", "take", "pass"]
const MIN_PLAYERS: int = 2
const DEFAULT_HAND_SIZE: int = 6
const MIN_HAND_SIZE: int = 4
const MAX_HAND_SIZE: int = 9
const MAX_ATTACKS: int = 6
## Bound for the safety draw: rounds in a row that ended with a pick-up while the
## deck was empty.
const STALEMATE_LIMIT: int = 8

var hand_size: int = DEFAULT_HAND_SIZE
var deck: Array[String] = []
var deck_count: int = 0
var trump_card: String = ""
var trump_suit: String = ""
var hands: Array = []
var hand_counts: Array[int] = []
var table: Array[Dictionary] = []
var attacker: int = 0
var defender: int = 0
var chain_seat: int = 0
var last_adder: int = -1
var passed: Array[int] = []
var out_players: Array[int] = []
var last_out: int = -1
var round_cap: int = MAX_ATTACKS
var discard_count: int = 0
var round_no: int = 1
## Consecutive rounds that ended with the defender picking the table up while the
## deck was empty. Durak has no draw rule, but a match must still terminate, so
## an endless pick-up cycle is declared a draw (see [_end_round]).
var stalemate: int = 0


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "durak"


func setup(options: Dictionary) -> void:
	super.setup(options)
	hand_size = clampi(VariantUtil.as_int(options.get("hand_size", DEFAULT_HAND_SIZE), DEFAULT_HAND_SIZE), MIN_HAND_SIZE, MAX_HAND_SIZE)
	_clear_round()
	deck = _shuffled_deck()
	trump_card = deck[0]
	trump_suit = card_suit(trump_card)
	deck_count = deck.size()
	hands.clear()
	for seat: int in range(maxi(player_count(), MIN_PLAYERS)):
		var hand: Array[String] = []
		hands.append(hand)
	out_players.clear()
	last_out = -1
	discard_count = 0
	stalemate = 0
	round_no = 1
	for draw: int in range(hand_size):
		for seat: int in range(player_count()):
			VariantUtil.as_array(hands[seat]).append(deck.pop_back())
	deck_count = deck.size()
	_sync_counts()
	attacker = _lowest_trump_holder()
	defender = _next_with_cards(attacker)
	chain_seat = attacker
	round_cap = _round_cap_for(defender)
	log_event("game.durak.log_start", {
		"player": player_name(attacker),
		"card": card_text(trump_card),
	})


func phases() -> PackedStringArray:
	return PackedStringArray(["attack", "defense", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	return "defense" if _uncovered_index() >= 0 else "attack"


func decision_player() -> int:
	if finished:
		return 0
	return defender if _uncovered_index() >= 0 else chain_seat


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "hand_size", "label_key": "game.durak.option.hand_size", "type": "int",
			"default": DEFAULT_HAND_SIZE, "min": MIN_HAND_SIZE, "max": MAX_HAND_SIZE,
			"hint_key": "game.durak.option.hand_size_hint"},
	]


# ---------------------------------------------------------------- card helpers

static func card_suit(card: String) -> String:
	return card.substr(0, 1)


static func card_rank(card: String) -> String:
	return card.substr(1)


static func rank_index(card: String) -> int:
	return RANKS.find(card_rank(card))


## Human readable card, e.g. "Ace of spades" style short forms are left to the
## view; the log needs a compact stable text.
static func card_text(card: String) -> String:
	return card_rank(card) + card_suit(card)


func is_trump(card: String) -> bool:
	return card_suit(card) == trump_suit


## True when `candidate` beats `target` under the trump rules.
func card_beats(candidate: String, target: String) -> bool:
	if candidate == target:
		return false
	var candidate_suit := card_suit(candidate)
	var target_suit := card_suit(target)
	var candidate_rank := rank_index(candidate)
	var target_rank := rank_index(target)
	if candidate_suit == trump_suit:
		if target_suit != trump_suit:
			return true
		return candidate_rank > target_rank
	if target_suit == trump_suit:
		return false
	return candidate_suit == target_suit and candidate_rank > target_rank


func _shuffled_deck() -> Array[String]:
	var cards: Array[String] = []
	for suit: String in SUITS:
		for rank: String in RANKS:
			cards.append(suit + rank)
	for index: int in range(cards.size() - 1, 0, -1):
		var swap_with := rng.randi_range(0, index)
		var held := cards[index]
		cards[index] = cards[swap_with]
		cards[swap_with] = held
	return cards


func _lowest_trump_holder() -> int:
	var best_seat := 0
	var best_rank := RANKS.size()
	for seat: int in range(player_count()):
		for card: Variant in VariantUtil.as_array(hands[seat]):
			var code := VariantUtil.as_string(card, "")
			if is_trump(code) and rank_index(code) < best_rank:
				best_rank = rank_index(code)
				best_seat = seat
	return best_seat


func _next_with_cards(from_seat: int) -> int:
	var count := player_count()
	for step: int in range(1, count + 1):
		var seat := (from_seat + step) % count
		if not VariantUtil.as_array(hands[seat]).is_empty():
			return seat
	return from_seat


func _round_cap_for(seat: int) -> int:
	return clampi(VariantUtil.as_array(hands[seat]).size(), 1, MAX_ATTACKS)


func _sync_counts() -> void:
	hand_counts.clear()
	for hand: Variant in hands:
		hand_counts.append(VariantUtil.as_array(hand).size())


func _uncovered_index() -> int:
	for index: int in range(table.size()):
		if VariantUtil.as_string(table[index].get("defense", ""), "").is_empty():
			return index
	return -1


## Hand ordered the way the view and the bot like it: lowest cards first, trump
## last. Always returns a fresh array.
func sorted_hand(seat: int) -> Array[String]:
	var cards: Array[String] = []
	for card: Variant in VariantUtil.as_array(hands[seat]):
		cards.append(VariantUtil.as_string(card, ""))
	cards.sort_custom(_card_order_less.bind(trump_suit))
	return cards


func _card_order_less(a: String, b: String, trump: String) -> bool:
	var value_a := rank_index(a) + (100 if card_suit(a) == trump else 0)
	var value_b := rank_index(b) + (100 if card_suit(b) == trump else 0)
	if value_a == value_b:
		return a < b
	return value_a < value_b


# -------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player < 0 or player >= player_count() or player != decision_player():
		return out
	var uncovered := _uncovered_index()
	if uncovered >= 0:
		var target := VariantUtil.as_string(VariantUtil.as_dict(table[uncovered]).get("attack", ""), "")
		for card: String in sorted_hand(player):
			if card_beats(card, target):
				var defend := make_action("defend", {"card": card, "beat": target})
				defend["_direct"] = false
				out.append(defend)
		var take := make_action("take", {}, "game.durak.action_take")
		take["_direct"] = true
		out.append(take)
		return out
	# Attack phase: the attacker opens, then everybody except the defender may
	# add cards of a rank that is already on the table.
	var open_table := table.is_empty()
	var attackable := _table_ranks()
	var can_attack := table.size() < round_cap and (not open_table or player == attacker)
	if can_attack:
		for card: String in sorted_hand(player):
			if not open_table and not attackable.has(card_rank(card)):
				continue
			var attack := make_action("attack", {"card": card})
			attack["_direct"] = false
			out.append(attack)
	if not open_table:
		var done := make_action("pass", {}, "game.durak.action_pass")
		done["_direct"] = true
		out.append(done)
	return out


func _table_ranks() -> Dictionary:
	var ranks: Dictionary = {}
	for slot: Dictionary in table:
		ranks[card_rank(VariantUtil.as_string(slot.get("attack", ""), ""))] = true
		var defense := VariantUtil.as_string(slot.get("defense", ""), "")
		if not defense.is_empty():
			ranks[card_rank(defense)] = true
	return ranks


func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var type := VariantUtil.as_string(action.get("type", ""), "")
	if not ACTION_TYPES.has(type):
		return _fail("game.durak.error.unknown_action")
	var player := decision_player()
	var legal := find_legal_action(player, VariantUtil.as_string(action.get("key", ""), ""))
	if legal.is_empty():
		return _fail("game.durak.error.illegal_action")
	match type:
		"attack":
			_commit_attack(player, VariantUtil.as_string(legal.get("card", ""), ""))
		"defend":
			_commit_defend(player, VariantUtil.as_string(legal.get("card", ""), ""), VariantUtil.as_string(legal.get("beat", ""), ""))
		"take":
			_commit_take(player)
		"pass":
			_commit_pass(player)
	return _ok(action)


# ------------------------------------------------------------------- the round

func _commit_attack(seat: int, card: String) -> void:
	_take_from_hand(seat, card)
	table.append({"attack": card, "defense": ""})
	last_adder = seat
	log_event("game.durak.log_attack", {
		"player": player_name(seat),
		"card": card_text(card),
	}, seat)


func _commit_defend(seat: int, card: String, beat: String) -> void:
	_take_from_hand(seat, card)
	for index: int in range(table.size()):
		var slot: Dictionary = table[index]
		if VariantUtil.as_string(slot.get("attack", ""), "") == beat and VariantUtil.as_string(slot.get("defense", ""), "").is_empty():
			slot["defense"] = card
			break
	log_event("game.durak.log_defend", {
		"player": player_name(seat),
		"attack": card_text(beat),
		"card": card_text(card),
	}, seat)
	if _uncovered_index() < 0:
		_after_covered()


func _commit_pass(seat: int) -> void:
	passed.append(seat)
	if not _advance_chain(seat):
		_end_round(true)


func _commit_take(seat: int) -> void:
	log_event("game.durak.log_take", {"player": player_name(seat)}, seat)
	_end_round(false)


func _take_from_hand(seat: int, card: String) -> void:
	var hand: Array = hands[seat]
	hand.erase(card)
	_sync_counts()


func _after_covered() -> void:
	if table.size() >= round_cap:
		_end_round(true)
		return
	var from_seat := last_adder if last_adder >= 0 else attacker
	if not _advance_chain(from_seat):
		_end_round(true)


## Moves the "who may add next" pointer forward. Returns false when every
## eligible attacker has finished, which ends the round as a success.
func _advance_chain(from_seat: int) -> bool:
	var count := player_count()
	for step: int in range(1, count + 1):
		var seat := (from_seat + step) % count
		if seat == defender or passed.has(seat) or VariantUtil.as_array(hands[seat]).is_empty():
			continue
		chain_seat = seat
		return true
	return false


## Resolves the round: the table is either discarded (defended) or picked up
## (taken), everybody redraws and the match end is checked.
func _end_round(defended: bool) -> void:
	if table.is_empty():
		return
	if defended:
		for slot: Dictionary in table:
			discard_count += 1
			if not VariantUtil.as_string(slot.get("defense", ""), "").is_empty():
				discard_count += 1
		table.clear()
		stalemate = 0
		attacker = defender
		defender = _next_with_cards(attacker)
		log_event("game.durak.log_clear", {"player": player_name(attacker)}, attacker)
	else:
		var picked: Array[String] = []
		for slot: Dictionary in table:
			picked.append(VariantUtil.as_string(slot.get("attack", ""), ""))
			var defense := VariantUtil.as_string(slot.get("defense", ""), "")
			if not defense.is_empty():
				picked.append(defense)
		table.clear()
		var hand: Array = hands[defender]
		for card: String in picked:
			hand.append(card)
		_sync_counts()
		stalemate += 1 if deck.is_empty() else 0
		attacker = _next_with_cards(defender)
		defender = _next_with_cards(attacker)
	_clear_round()
	_refill(attacker)
	_mark_outs()
	round_no += 1
	round_index = round_no
	if _check_match_end():
		return
	if stalemate >= STALEMATE_LIMIT:
		finish(-1, "game.durak.reason.stalemate", _scores())
		return
	# The opening right stays with hands that hold cards: a seat that emptied
	# itself with the final defence (and an empty deck cannot refill it) can
	# neither attack nor pass on an open table, which would stall the match
	# between the two seats that still can act.
	if VariantUtil.as_array(hands[attacker]).is_empty():
		attacker = _next_with_cards(attacker)
	if defender == attacker or VariantUtil.as_array(hands[defender]).is_empty():
		defender = _next_with_cards(attacker)
	round_cap = _round_cap_for(defender)
	chain_seat = attacker
	log_event("game.durak.log_round", {
		"round": round_no,
		"player": player_name(attacker),
		"defender": player_name(defender),
	}, attacker)

func _clear_round() -> void:
	table.clear()
	passed.clear()
	last_adder = -1


func _refill(from_seat: int) -> void:
	for step: int in range(player_count()):
		var seat := (from_seat + step) % player_count()
		while VariantUtil.as_array(hands[seat]).size() < hand_size and not deck.is_empty():
			VariantUtil.as_array(hands[seat]).append(deck.pop_back())
	deck_count = deck.size()
	_sync_counts()


func _mark_outs() -> void:
	for seat: int in range(player_count()):
		if VariantUtil.as_array(hands[seat]).is_empty() and not out_players.has(seat):
			out_players.append(seat)
			last_out = seat
			log_event("game.durak.log_out", {"player": player_name(seat)}, seat)


## Returns true when the match ended.
func _check_match_end() -> bool:
	var with_cards: Array[int] = []
	for seat: int in range(player_count()):
		if VariantUtil.as_array(hands[seat]).is_empty():
			continue
		with_cards.append(seat)
	if with_cards.size() > 1:
		return false
	var scores := _scores()
	if with_cards.is_empty():
		finish(-1, "game.durak.reason.draw", scores)
		return true
	var fool := with_cards[0]
	log_event("game.durak.log_fool", {"player": player_name(fool)}, fool)
	finish(last_out if last_out >= 0 else -1, "game.durak.reason.fool", scores)
	return true


func _scores() -> Array:
	var out := []
	for seat: int in range(player_count()):
		out.append({
			"player": seat,
			"name": player_name(seat),
			"score": VariantUtil.as_array(hands[seat]).size(),
		})
	return out


# ----------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["trump_card"] = trump_card
	state["trump_suit"] = trump_suit
	state["deck_count"] = deck_count
	state["discard_count"] = discard_count
	state["table"] = table.duplicate(true)
	state["attacker"] = attacker
	state["defender"] = defender
	state["chain_seat"] = chain_seat
	state["round_cap"] = round_cap
	state["hand_size"] = hand_size
	state["hand_counts"] = hand_counts.duplicate()
	state["out"] = out_players.duplicate()
	state["last_out"] = last_out
	state["stalemate"] = stalemate
	return state


func private_state(player: int) -> Dictionary:
	if player < 0:
		# Table secret: the stock order matters for every later draw.
		return {"deck": deck.duplicate()}
	if player >= hands.size():
		return {}
	var hand: Array[String] = []
	for card: Variant in VariantUtil.as_array(hands[player]):
		hand.append(VariantUtil.as_string(card, ""))
	return {"hand": hand}


## Installs ONE seat's private slice on a replica or from a save-file bag.
## Other seats stay untouched: a client replica only knows its own cards plus
## the public counts.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0:
		# Table secret: the stock order.
		if slice.has("deck"):
			var restored_deck: Array[String] = []
			copy_string_array(slice.get("deck", []), restored_deck)
			deck = restored_deck
			deck_count = deck.size()
		return
	if seat >= player_count():
		return
	while hands.size() < player_count():
		hands.append([])
	var hand: Array[String] = []
	copy_string_array(slice.get("hand", []), hand)
	hands[seat] = hand
	if slice.has("deck"):
		# A whole-table restore merged its stock into this slice.
		var restored_deck: Array[String] = []
		copy_string_array(slice.get("deck", []), restored_deck)
		deck = restored_deck
		deck_count = deck.size()
	# Counts stay public truth: keep every other seat's count from the public
	# snapshot and only refresh this seat's.
	if hand_counts.size() <= seat:
		while hand_counts.size() < player_count():
			hand_counts.append(0)
	hand_counts[seat] = hand.size()


func _restore_extra(state: Dictionary) -> void:
	trump_card = VariantUtil.as_string(state.get("trump_card", ""), "")
	trump_suit = VariantUtil.as_string(state.get("trump_suit", ""), "")
	if trump_suit.is_empty() and not trump_card.is_empty():
		trump_suit = card_suit(trump_card)
	deck_count = VariantUtil.as_int(state.get("deck_count", 0), 0)
	discard_count = VariantUtil.as_int(state.get("discard_count", 0), 0)
	attacker = VariantUtil.as_int(state.get("attacker", 0), 0)
	defender = VariantUtil.as_int(state.get("defender", 0), 0)
	chain_seat = VariantUtil.as_int(state.get("chain_seat", attacker), attacker)
	round_cap = VariantUtil.as_int(state.get("round_cap", MAX_ATTACKS), MAX_ATTACKS)
	hand_size = clampi(VariantUtil.as_int(state.get("hand_size", DEFAULT_HAND_SIZE), DEFAULT_HAND_SIZE), MIN_HAND_SIZE, MAX_HAND_SIZE)
	last_out = VariantUtil.as_int(state.get("last_out", -1), -1)
	stalemate = VariantUtil.as_int(state.get("stalemate", 0), 0)
	round_index = maxi(1, VariantUtil.as_int(state.get("round", 1), 1))
	table.clear()
	for entry: Variant in VariantUtil.as_array(state.get("table", [])):
		if entry is Dictionary:
			table.append((entry as Dictionary).duplicate(true))
	copy_int_array(state.get("out", []), out_players)
	passed.clear()
	last_adder = -1
	# A snapshot of the whole match carries every hand under "hands"; the test
	# harness and save files instead key private slices by seat under
	# "private_states". A public-only snapshot is a spectator model: counts yes,
	# cards no.
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	hands.clear()
	# Public counts are copied first in every form; the per-seat adopt below
	# then overrides the seat it actually received cards for.
	copy_int_array(state.get("hand_counts", []), hand_counts)
	# Where does the stock (table secret) come from in this snapshot form?
	var deck_source: Dictionary = privates.get("-1", {}) if privates.get("-1", {}) is Dictionary else {}
	if not privates.is_empty():
		# Save-file shape: every seat's private slice keyed by seat index.
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hands"):
		for entry: Variant in VariantUtil.as_array(state.get("hands", [])):
			var hand: Array[String] = []
			copy_string_array(entry, hand)
			hands.append(hand)
		deck_source = state
	elif state.has("hand") or state.has("deck"):
		# Client shape (the documented harness contract): the acting player's
		# private slice merged at the top level, attributed to the decision
		# player. Permissions still hold: only this seat's cards are present.
		_adopt_private_extra(decision_player(), state)
		deck_source = state
	else:
		# Public-only spectator model: counts yes, cards no.
		for seat: int in range(player_count()):
			var empty: Array[String] = []
			hands.append(empty)
	if state.has("deck") or deck_source.has("deck"):
		var restored_deck: Array[String] = []
		copy_string_array(state.get("deck", deck_source.get("deck", [])), restored_deck)
		deck = restored_deck
		deck_count = deck.size()
	else:
		deck.clear()


# ------------------------------------------------------------- test/debug seam

## Installs an exact position (rules suite, tooling). Every card must be a valid
## code, no card may appear twice and a non-empty deck must still hold the trump
## card at its bottom (index 0). `new_attacker` of -1 opens the attack with the
## lowest trump as [method setup] does. Returns false for an unusable position.
func load_position(new_hands: Array, new_deck: Array, new_trump: String, new_attacker: int) -> bool:
	if new_hands.size() != player_count():
		return false
	var seen: Dictionary = {}
	var rebuilt: Array = []
	for entry: Variant in new_hands:
		var hand: Array[String] = []
		for card: Variant in VariantUtil.as_array(entry):
			var code := VariantUtil.as_string(card, "")
			if not _valid_card(code) or seen.has(code):
				return false
			seen[code] = true
			hand.append(code)
		rebuilt.append(hand)
	var rebuilt_deck: Array[String] = []
	for card: Variant in new_deck:
		var code := VariantUtil.as_string(card, "")
		if not _valid_card(code) or seen.has(code):
			return false
		seen[code] = true
		rebuilt_deck.append(code)
	if not new_trump.is_empty():
		if not _valid_card(new_trump):
			return false
		if not rebuilt_deck.is_empty() and String(rebuilt_deck[0]) != new_trump:
			return false
		if not seen.has(new_trump):
			rebuilt_deck.push_front(new_trump)
			seen[new_trump] = true
	hands = rebuilt
	deck = rebuilt_deck
	trump_card = new_trump if not new_trump.is_empty() else (String(deck[0]) if not deck.is_empty() else "")
	trump_suit = card_suit(trump_card) if not trump_card.is_empty() else ""
	deck_count = deck.size()
	_sync_counts()
	out_players.clear()
	last_out = -1
	discard_count = 0
	stalemate = 0
	round_no = 1
	round_index = 1
	attacker = _lowest_trump_holder() if new_attacker < 0 else clampi(new_attacker, 0, maxi(0, player_count() - 1))
	defender = _next_with_cards(attacker)
	_clear_round()
	chain_seat = attacker
	round_cap = _round_cap_for(defender)
	finished = false
	result = {}
	return true


func _valid_card(card: String) -> bool:
	return card.length() >= 2 and SUITS.has(card_suit(card)) and RANKS.has(card_rank(card))


