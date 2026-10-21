class_name KingEngine
extends GameEngine
## King for three to six players, played with the full 52-card deck.
##
## Rules implemented:
##  * The deck is shuffled with the seeded RNG and dealt evenly (lowest card of
##    the deck first); with three, five or six players the leftover cards are set
##    aside face down and never enter play.
##  * Optional pass (default on): every player picks three cards one at a time.
##    The picks stay private until the last player is done; only then does each
##    player send their picked cards to the player on their left, so nobody can
##    react to what is being handed over. The leader (seat 0) opens the play.
##  * Trick taking without trumps: every player must follow the led suit while
##    they can and may play any card when they cannot. The highest card of the
##    led suit takes the trick and leads the next one.
##  * Penalties (fewest points wins): every heart scores one point, the queen of
##    spades five, and the king of hearts -5 (a bonus for whoever takes it).
##  * Shoot the moon (default on): a player who takes every heart *and* the queen
##    of spades has the heart and queen points waived but keeps the king of hearts
##    bonus. The deal is the match; the lowest score wins and a tie goes to the
##    lowest seat, so there is no draw.
##
## Hidden information: hands and pending picks live in [method private_state];
## a snapshot restored from [method public_state] alone is a spectator model - it
## knows counts, played cards and penalties, but no cards (see [GameSession]).

const SUITS: Array[String] = ["S", "H", "D", "C"]
const RANKS: Array[String] = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const ACTION_TYPES: Array[String] = ["pick", "play"]
const MIN_PLAYERS: int = 3
const MAX_PLAYERS: int = 6
## How many cards every player passes to the left.
const PASS_COUNT: int = 3
const HEART_POINTS: int = 1
const QUEEN_POINTS: int = 5
const KING_BONUS: int = 5
const MOON_HEARTS: int = 13
const HEART_QUEEN: String = "SQ"
const HEART_KING: String = "HK"
const DECK_SIZE: int = 52

var passing_enabled: bool = true
var shoot_moon: bool = true
var hands: Array = []
var hand_counts: Array[int] = []
var set_aside: Array[String] = []
var set_aside_count: int = 0
var picks: Array = []
var picks_count: Array[int] = []
var phase_id: String = "playing"
var passing_seat: int = 0
var leader: int = 0
var turn_seat: int = 0
var trick: Array[Dictionary] = []
var hearts_taken: Array[int] = []
var queens_taken: Array[int] = []
var kings_taken: Array[int] = []
var cards_per_player: int = 0
var trick_no: int = 1


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "king"


func setup(options: Dictionary) -> void:
	super.setup(options)
	passing_enabled = bool(options.get("passing", true))
	shoot_moon = bool(options.get("shoot_moon", true))
	var seats := maxi(player_count(), 1)
	cards_per_player = DECK_SIZE / seats
	var deck := _shuffled_deck()
	hands.clear()
	picks.clear()
	hand_counts.clear()
	picks_count.clear()
	hearts_taken.clear()
	queens_taken.clear()
	kings_taken.clear()
	for seat: int in range(seats):
		var hand: Array[String] = []
		hands.append(hand)
		var picked: Array[String] = []
		picks.append(picked)
		hand_counts.append(0)
		picks_count.append(0)
		hearts_taken.append(0)
		queens_taken.append(0)
		kings_taken.append(0)
	for _draw: int in range(cards_per_player):
		for seat: int in range(seats):
			VariantUtil.as_array(hands[seat]).append(deck.pop_back())
	set_aside = deck
	set_aside_count = set_aside.size()
	_sync_counts()
	trick.clear()
	trick_no = 1
	round_index = 1
	leader = 0
	turn_seat = 0
	passing_seat = 0
	phase_id = "passing" if passing_enabled else "playing"
	_sync_turn()
	log_event("game.king.log_start", {"cards": cards_per_player, "aside": set_aside.size()})


func phases() -> PackedStringArray:
	return PackedStringArray(["passing", "playing", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	return phase_id


func decision_player() -> int:
	if finished:
		return 0
	return passing_seat if phase_id == "passing" else turn_seat


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "passing", "label_key": "game.king.option.passing", "type": "bool", "default": true,
			"hint_key": "game.king.option.passing_hint"},
		{"key": "shoot_moon", "label_key": "game.king.option.shoot_moon", "type": "bool", "default": true,
			"hint_key": "game.king.option.shoot_moon_hint"},
	]


# ---------------------------------------------------------------- card helpers

static func card_suit(card: String) -> String:
	return card.substr(0, 1)


static func card_rank(card: String) -> String:
	return card.substr(1)


static func rank_index(card: String) -> int:
	return RANKS.find(card_rank(card))


## Compact stable text for the log, e.g. "KH" for the king of hearts.
static func card_text(card: String) -> String:
	return card_rank(card) + card_suit(card)


## The suit that must be followed in the current trick (empty before the lead).
func led_suit() -> String:
	if trick.is_empty():
		return ""
	return card_suit(VariantUtil.as_string(VariantUtil.as_dict(trick[0]).get("card", ""), ""))


func penalty_points(card: String) -> int:
	var points := 0
	if card_suit(card) == "H":
		points += HEART_POINTS
	if card == HEART_QUEEN:
		points += QUEEN_POINTS
	if card == HEART_KING:
		points -= KING_BONUS
	return points


## How much a card hurts to keep: the bot passes the highest values and the view
## marks them as dangerous. The king of hearts and the queen of spades lead.
func pass_danger(card: String) -> int:
	if card == HEART_KING:
		return 100
	if card == HEART_QUEEN:
		return 90
	if card_suit(card) == "H":
		return 50 + rank_index(card)
	return rank_index(card)


## Hand ordered for the view: by suit, then by rank.
func sorted_hand(seat: int) -> Array[String]:
	var cards: Array[String] = []
	for card: Variant in VariantUtil.as_array(hands[seat]):
		cards.append(VariantUtil.as_string(card, ""))
	cards.sort_custom(_card_order_less)
	return cards


func _card_order_less(a: String, b: String) -> bool:
	var suit_a := SUITS.find(card_suit(a))
	var suit_b := SUITS.find(card_suit(b))
	if suit_a == suit_b:
		if rank_index(a) == rank_index(b):
			return a < b
		return rank_index(a) < rank_index(b)
	return suit_a < suit_b


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


# -------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player < 0 or player >= player_count() or player != decision_player():
		return out
	if phase_id == "passing":
		for card: String in sorted_hand(player):
			var pick := make_action("pick", {"card": card})
			pick["_direct"] = false
			out.append(pick)
		return out
	var led := led_suit()
	var can_follow := not led.is_empty() and _has_suit(player, led)
	for card: String in sorted_hand(player):
		if led.is_empty() or not can_follow or card_suit(card) == led:
			var play := make_action("play", {"card": card})
			play["_direct"] = false
			out.append(play)
	return out


func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var type := VariantUtil.as_string(action.get("type", ""), "")
	if not ACTION_TYPES.has(type):
		return _fail("game.king.error.unknown_action")
	var player := decision_player()
	var legal := find_legal_action(player, VariantUtil.as_string(action.get("key", ""), ""))
	if legal.is_empty():
		return _fail("game.king.error.illegal_action")
	match type:
		"pick":
			_commit_pick(player, VariantUtil.as_string(legal.get("card", ""), ""))
		"play":
			_commit_play(player, VariantUtil.as_string(legal.get("card", ""), ""))
	return _ok(action)


# ---------------------------------------------------------------- the passing

func _commit_pick(seat: int, card: String) -> void:
	_take_from_hand(seat, card)
	VariantUtil.as_array(picks[seat]).append(card)
	picks_count[seat] += 1
	log_event("game.king.log_pick", {"player": player_name(seat), "picked": picks_count[seat]}, seat)
	passing_seat = (passing_seat + 1) % maxi(player_count(), 1)
	_sync_turn()
	if _picks_done():
		_exchange_picks()


func _picks_done() -> bool:
	for count: int in picks_count:
		if count < PASS_COUNT:
			return false
	return true


## The simultaneous exchange: every player's picks go to the player on their
## left. Executed in one step so nobody can adapt to an incoming card first.
func _exchange_picks() -> void:
	var seats := maxi(player_count(), 1)
	for seat: int in range(seats):
		var incoming: Array = picks[(seat - 1 + seats) % seats]
		var hand: Array = hands[seat]
		for card: Variant in incoming:
			hand.append(VariantUtil.as_string(card, ""))
	for seat: int in range(seats):
		VariantUtil.as_array(picks[seat]).clear()
		picks_count[seat] = 0
	_sync_counts()
	phase_id = "playing"
	leader = 0
	turn_seat = 0
	trick.clear()
	trick_no = 1
	round_index = 1
	_sync_turn()
	log_event("game.king.log_pass", {})


# ---------------------------------------------------------------- the playing

func _commit_play(seat: int, card: String) -> void:
	_take_from_hand(seat, card)
	trick.append({"player": seat, "card": card})
	log_event("game.king.log_play", {"player": player_name(seat), "card": card_text(card)}, seat)
	if trick.size() >= player_count():
		_resolve_trick()
		return
	turn_seat = (seat + 1) % maxi(player_count(), 1)
	_sync_turn()


## The trick winner takes every card of the trick, so the penalties of a trick
## are settled here, once, on top of whoever won it.
func _register_penalty(seat: int, card: String) -> void:
	if card_suit(card) == "H":
		hearts_taken[seat] += 1
	if card == HEART_QUEEN:
		queens_taken[seat] += 1
	if card == HEART_KING:
		kings_taken[seat] += 1


func _resolve_trick() -> void:
	var winner := _trick_winner()
	for entry: Dictionary in trick:
		_register_penalty(winner, VariantUtil.as_string(entry.get("card", ""), ""))
	log_event("game.king.log_trick", {"player": player_name(winner)}, winner)
	trick.clear()
	trick_no += 1
	round_index = trick_no
	if _hands_empty():
		_finish_match()
		return
	leader = winner
	turn_seat = winner
	_sync_turn()


func _trick_winner() -> int:
	var led := led_suit()
	var best := -1
	var best_card := ""
	for entry: Dictionary in trick:
		var card := VariantUtil.as_string(entry.get("card", ""), "")
		if card_suit(card) != led:
			continue
		if best < 0 or rank_index(card) > rank_index(best_card):
			best = VariantUtil.as_int(entry.get("player", 0), 0)
			best_card = card
	return maxi(best, 0)


func _hands_empty() -> bool:
	for hand: Variant in hands:
		if not VariantUtil.as_array(hand).is_empty():
			return false
	return true


# --------------------------------------------------------------------- scoring

## True when `seat` took every heart and the queen of spades. The shoot-the-moon
## option decides whether that also waives the points (see [method score_for]).
func is_moon_shooter(seat: int) -> bool:
	if seat < 0 or seat >= hearts_taken.size():
		return false
	return hearts_taken[seat] >= MOON_HEARTS and queens_taken[seat] >= 1


func score_for(seat: int) -> int:
	if seat < 0 or seat >= hearts_taken.size():
		return 0
	if shoot_moon and is_moon_shooter(seat):
		return -kings_taken[seat] * KING_BONUS
	return hearts_taken[seat] * HEART_POINTS \
		+ queens_taken[seat] * QUEEN_POINTS \
		- kings_taken[seat] * KING_BONUS


func _scores() -> Array:
	var out := []
	for seat: int in range(player_count()):
		out.append({
			"player": seat,
			"name": player_name(seat),
			"score": score_for(seat),
			"hearts": hearts_taken[seat] if seat < hearts_taken.size() else 0,
			"queen": queens_taken[seat] if seat < queens_taken.size() else 0,
			"king": kings_taken[seat] if seat < kings_taken.size() else 0,
		})
	return out


## The match ends when every hand is empty: lowest score wins, a tie goes to the
## lowest seat, so the result is never a draw.
func _finish_match() -> void:
	if player_count() <= 0:
		return
	for seat: int in range(player_count()):
		if is_moon_shooter(seat):
			log_event("game.king.log_moon", {"player": player_name(seat)}, seat)
	var best_seat := 0
	var best_score := score_for(0)
	for seat: int in range(1, player_count()):
		var score := score_for(seat)
		if score < best_score:
			best_score = score
			best_seat = seat
	finish(best_seat, "game.king.reason.finished", _scores())


# ----------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["passing"] = passing_enabled
	state["shoot_moon"] = shoot_moon
	state["phase_id"] = phase_id
	state["cards_per_player"] = cards_per_player
	state["hand_counts"] = hand_counts.duplicate()
	state["picks_count"] = picks_count.duplicate()
	state["set_aside_count"] = set_aside_count
	state["leader"] = leader
	state["turn_seat"] = turn_seat
	state["passing_seat"] = passing_seat
	state["trick"] = trick.duplicate(true)
	state["trick_no"] = trick_no
	state["hearts_taken"] = hearts_taken.duplicate()
	state["queens_taken"] = queens_taken.duplicate()
	state["kings_taken"] = kings_taken.duplicate()
	return state


func private_state(player: int) -> Dictionary:
	if player < 0:
		# Table secret: the cards removed from play at the start of the deal.
		return {"set_aside": set_aside.duplicate()}
	if player >= hands.size():
		return {}
	var hand: Array[String] = []
	for card: Variant in VariantUtil.as_array(hands[player]):
		hand.append(VariantUtil.as_string(card, ""))
	var state := {"hand": hand}
	if phase_id == "passing":
		var picked: Array[String] = []
		for card: Variant in VariantUtil.as_array(picks[player]):
			picked.append(VariantUtil.as_string(card, ""))
		state["picks"] = picked
	return state


## Installs ONE seat's private slice on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own cards plus
## the public counts.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0:
		# Table secret: the set-aside cards.
		if slice.has("set_aside"):
			var aside: Array[String] = []
			copy_string_array(slice.get("set_aside", []), aside)
			set_aside = aside
			set_aside_count = aside.size()
		return
	if seat >= player_count():
		return
	while hands.size() < player_count():
		var empty: Array[String] = []
		hands.append(empty)
	while picks.size() < player_count():
		var empty_picks: Array[String] = []
		picks.append(empty_picks)
	var hand: Array[String] = []
	copy_string_array(slice.get("hand", []), hand)
	hands[seat] = hand
	var picked: Array[String] = []
	copy_string_array(slice.get("picks", []), picked)
	picks[seat] = picked
	while hand_counts.size() < player_count():
		hand_counts.append(0)
	hand_counts[seat] = hand.size()
	while picks_count.size() < player_count():
		picks_count.append(0)
	picks_count[seat] = picked.size()


func _restore_extra(state: Dictionary) -> void:
	passing_enabled = bool(state.get("passing", passing_enabled))
	shoot_moon = bool(state.get("shoot_moon", shoot_moon))
	phase_id = VariantUtil.as_string(state.get("phase_id", "playing"), "playing")
	cards_per_player = VariantUtil.as_int(state.get("cards_per_player", 0), 0)
	leader = VariantUtil.as_int(state.get("leader", 0), 0)
	turn_seat = VariantUtil.as_int(state.get("turn_seat", leader), leader)
	passing_seat = VariantUtil.as_int(state.get("passing_seat", turn_seat), turn_seat)
	trick_no = maxi(1, VariantUtil.as_int(state.get("trick_no", 1), 1))
	round_index = maxi(1, VariantUtil.as_int(state.get("round", trick_no), trick_no))
	trick.clear()
	for entry: Variant in VariantUtil.as_array(state.get("trick", [])):
		if entry is Dictionary:
			trick.append((entry as Dictionary).duplicate(true))
	copy_int_array(state.get("hearts_taken", []), hearts_taken)
	copy_int_array(state.get("queens_taken", []), queens_taken)
	copy_int_array(state.get("kings_taken", []), kings_taken)
	copy_int_array(state.get("picks_count", []), picks_count)
	# Snapshot forms, strongest first (see the shared contract in
	# docs/GAME_ENGINE_CONTRACT.md): the save-file bag, whole-match "hands",
	# the merged client slice for the decision player, public-only spectator.
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	hands.clear()
	picks.clear()
	copy_int_array(state.get("hand_counts", []), hand_counts)
	copy_int_array(state.get("picks_count", []), picks_count)
	if not privates.is_empty():
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hands"):
		for entry: Variant in VariantUtil.as_array(state.get("hands", [])):
			var hand: Array[String] = []
			copy_string_array(entry, hand)
			hands.append(hand)
		_sync_counts()
		# Whole-match snapshots carry each seat's passing picks as per-seat
		# arrays under "picks" (see the king rules suite).
		var stored: Array = VariantUtil.as_array(state.get("picks", []))
		for seat: int in range(maxi(player_count(), 1)):
			var picked: Array[String] = []
			if seat < stored.size():
				copy_string_array(stored[seat], picked)
			picks.append(picked)
			if picks_count.size() > seat:
				picks_count[seat] = picked.size()
	elif state.has("hand"):
		# Client shape: the acting player's own hand (and picks) attributed to
		# the decision player.
		_adopt_private_extra(decision_player(), state)
	else:
		# Spectator model: counts yes, cards no.
		for _seat: int in range(maxi(player_count(), 1)):
			var empty: Array[String] = []
			hands.append(empty)
			var empty_picks: Array[String] = []
			picks.append(empty_picks)
	# The set-aside cards are a table secret: whole-match form at the top level,
	# save files under the "-1" bag key.
	var table_secret: Dictionary = privates.get("-1", {}) if privates.get("-1", {}) is Dictionary else {}
	set_aside_count = VariantUtil.as_int(state.get("set_aside_count", 0), 0)
	if state.has("set_aside") or table_secret.has("set_aside"):
		var aside: Array[String] = []
		copy_string_array(state.get("set_aside", table_secret.get("set_aside", [])), aside)
		set_aside = aside
		set_aside_count = aside.size()
	else:
		set_aside.clear()


# ------------------------------------------------------------- test/debug seam

## Installs an exact position (rules suite, tooling). Every card must be valid
## and no card may appear twice; `new_set_aside` may be empty. With
## `start_passing` the engine starts in the passing phase and every hand must
## hold at least [constant PASS_COUNT] cards. Returns false for a bad position.
func load_position(new_hands: Array, new_set_aside: Array, new_leader: int, start_passing: bool = false) -> bool:
	var seats := player_count()
	if seats < 1 or new_hands.size() != seats:
		return false
	var seen: Dictionary = {}
	var rebuilt: Array = []
	for entry: Variant in new_hands:
		if not (entry is Array):
			return false
		var hand: Array[String] = []
		for card: Variant in VariantUtil.as_array(entry):
			var code := VariantUtil.as_string(card, "")
			if not _valid_card(code) or seen.has(code):
				return false
			seen[code] = true
			hand.append(code)
		if start_passing and hand.size() < PASS_COUNT:
			return false
		rebuilt.append(hand)
	var rebuilt_aside: Array[String] = []
	for card: Variant in new_set_aside:
		var code := VariantUtil.as_string(card, "")
		if not _valid_card(code) or seen.has(code):
			return false
		seen[code] = true
		rebuilt_aside.append(code)
	hands = rebuilt
	set_aside = rebuilt_aside
	set_aside_count = rebuilt_aside.size()
	_sync_counts()
	picks.clear()
	picks_count.clear()
	hearts_taken.clear()
	queens_taken.clear()
	kings_taken.clear()
	for _seat: int in range(seats):
		var picked: Array[String] = []
		picks.append(picked)
		picks_count.append(0)
		hearts_taken.append(0)
		queens_taken.append(0)
		kings_taken.append(0)
	trick.clear()
	trick_no = 1
	round_index = 1
	passing_seat = 0
	phase_id = "passing" if start_passing else "playing"
	leader = clampi(new_leader, 0, maxi(seats - 1, 0))
	turn_seat = leader
	finished = false
	result = {}
	_sync_turn()
	return true


func _valid_card(card: String) -> bool:
	return card.length() >= 2 and SUITS.has(card_suit(card)) and RANKS.has(card_rank(card))


# ------------------------------------------------------------------- internal

func _take_from_hand(seat: int, card: String) -> void:
	var hand: Array = hands[seat]
	hand.erase(card)
	_sync_counts()


func _has_suit(seat: int, suit: String) -> bool:
	for card: Variant in VariantUtil.as_array(hands[seat]):
		if card_suit(VariantUtil.as_string(card, "")) == suit:
			return true
	return false


func _sync_counts() -> void:
	hand_counts.clear()
	for hand: Variant in hands:
		hand_counts.append(VariantUtil.as_array(hand).size())


func _sync_turn() -> void:
	turn = decision_player() if not finished else 0
