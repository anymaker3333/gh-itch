class_name BridgeEngine
extends GameEngine
## Contract bridge for exactly four players (two partnerships).
##
## Rules implemented (documented simplifications):
##  * One deal per match. Seats 0 and 2 are North/South, seats 1 and 3 are
##    East/West. Seat 0 deals.
##  * Auction in strain order clubs, diamonds, hearts, spades, no-trump. A bid
##    must be strictly higher than the previous one. Doubles and redoubles are
##    not implemented. Four initial passes pass the deal out (a draw); three
##    passes after a bid end the auction.
##  * The declarer is the first player of the winning partnership who named the
##    final strain. The declarer's partner is dummy: their hand is revealed
##    after the opening lead and the declarer chooses dummy's cards.
##  * Play: follow the led suit when possible, otherwise any card. The highest
##    card of the led suit wins unless the contract has trumps and a trump was
##    played, in which case the highest trump wins.
##  * Scoring is duplicate-style without vulnerability: 20 per trick in minors,
##    30 in majors, 40 for the first no-trump trick and 30 for each further one;
##    partscore bonus 50, game bonus 300, small slam 500, grand slam 750,
##    overtricks at the contract rate and 50 per undertrick.
##
## Hidden information: the four hands live in [method private_state]. Dummy's
## hand enters the public snapshot only once the opening lead is played.

const SUITS: Array[String] = ["C", "D", "H", "S"]
const STRAINS: Array[String] = ["C", "D", "H", "S", "NT"]
const RANKS: Array[String] = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const ACTION_TYPES: Array[String] = ["pass", "bid", "play"]
const SEATS: int = 4
const TRICKS: int = 13
const DECK_SIZE: int = 52

var hands: Array = []
var hand_counts: Array[int] = []
var phase_id: String = "auction"
var dealer: int = 0
var auction: Array[Dictionary] = []
var current_bidder: int = 0
var passes_in_row: int = 0
var highest_level: int = 0
var highest_strain: String = ""
var highest_bidder: int = -1
var contract_level: int = 0
var contract_strain: String = ""
var declarer: int = -1
var dummy: int = -1
var dummy_revealed: bool = false
var leader: int = 0
var turn_seat: int = 0
var trick: Array[Dictionary] = []
var trick_no: int = 1
var tricks_ns: int = 0
var tricks_ew: int = 0
## False after a public-only restore (spectator/client model): the dummy hand is
## visible, but without the private halves nobody may act locally.
var _has_hands: bool = true


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "bridge"


func setup(options: Dictionary) -> void:
	super.setup(options)
	# Bridge is a fixed four-seat game. Pad missing seats with simple bots so a
	# misconfigured session still produces a legal deal instead of half a table.
	while players.size() < SEATS:
		var seat := players.size()
		players.append({
			"index": seat,
			"name": "Bot %d" % (seat + 1),
			"kind": "bot",
			"peer_id": 0,
			"steam_id": 0,
		})
	dealer = 0
	_deal_and_reset_auction()


func phases() -> PackedStringArray:
	return PackedStringArray(["auction", "play", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	return phase_id


func decision_player() -> int:
	if finished:
		return 0
	if phase_id == "auction":
		return current_bidder
	# On dummy's turn the declarer chooses the card.
	if dummy >= 0 and turn_seat == dummy:
		return declarer
	return turn_seat


func options_schema() -> Array[Dictionary]:
	return []


func _deal_and_reset_auction() -> void:
	var deck := _shuffled_deck()
	hands.clear()
	hand_counts.clear()
	for seat: int in range(SEATS):
		var hand: Array[String] = []
		hands.append(hand)
		hand_counts.append(0)
	for _draw: int in range(TRICKS):
		for seat: int in range(SEATS):
			VariantUtil.as_array(hands[seat]).append(deck.pop_back())
	_sync_counts()
	auction.clear()
	current_bidder = dealer
	passes_in_row = 0
	highest_level = 0
	highest_strain = ""
	highest_bidder = -1
	contract_level = 0
	contract_strain = ""
	declarer = -1
	dummy = -1
	dummy_revealed = false
	leader = (dealer + 1) % SEATS
	turn_seat = leader
	trick.clear()
	trick_no = 1
	tricks_ns = 0
	tricks_ew = 0
	phase_id = "auction"
	round_index = 1
	_has_hands = true
	_sync_turn()
	log_event("game.bridge.log_start", {
		"player": player_name(dealer),
		"cards": TRICKS,
	})


# ---------------------------------------------------------------- card helpers

static func card_suit(card: String) -> String:
	return card.substr(0, 1)


static func card_rank(card: String) -> String:
	return card.substr(1)


static func rank_index(card: String) -> int:
	return RANKS.find(card_rank(card))


static func strain_index(strain: String) -> int:
	return STRAINS.find(strain)


static func card_text(card: String) -> String:
	return card_rank(card) + card_suit(card)


static func bid_text(level: int, strain: String) -> String:
	var symbol := "NT" if strain == "NT" else strain
	return "%d%s" % [level, symbol]


static func partnership(seat: int) -> int:
	return seat % 2


static func partner_of(seat: int) -> int:
	return (seat + 2) % SEATS


## Hand ordered for the view: by suit, then by rank.
func sorted_hand(seat: int) -> Array[String]:
	var cards: Array[String] = []
	if seat < 0 or seat >= hands.size():
		return cards
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


func led_suit() -> String:
	if trick.is_empty():
		return ""
	return card_suit(VariantUtil.as_string(VariantUtil.as_dict(trick[0]).get("card", ""), ""))


func is_no_trump() -> bool:
	return contract_strain == "NT"


func needed_tricks() -> int:
	return contract_level + 6


## Tricks the declaring partnership has taken so far.
func declarer_tricks() -> int:
	if declarer < 0:
		return 0
	return tricks_ns if partnership(declarer) == 0 else tricks_ew


func defenders_tricks() -> int:
	return TRICKS - declarer_tricks()


func dummy_seat() -> int:
	return dummy


# -------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or not _has_hands or player < 0 or player >= SEATS or player != decision_player():
		return out
	if phase_id == "auction":
		var pass_action := make_action("pass", {}, "game.bridge.action.pass")
		pass_action["_direct"] = true
		out.append(pass_action)
		for level: int in range(1, 8):
			for strain: String in STRAINS:
				if _bid_is_higher(level, strain):
					var bid := make_action("bid", {"level": level, "strain": strain})
					bid["_direct"] = false
					bid["_bid"] = bid_text(level, strain)
					out.append(bid)
		return out
	var hand: Array = hands[turn_seat] if turn_seat >= 0 and turn_seat < hands.size() else []
	var led := led_suit()
	var can_follow := not led.is_empty() and _has_suit(turn_seat, led)
	for card: String in sorted_hand(turn_seat):
		if led.is_empty() or not can_follow or card_suit(card) == led:
			var play := make_action("play", {"card": card})
			play["_direct"] = false
			out.append(play)
	return out


func _bid_is_higher(level: int, strain: String) -> bool:
	if highest_level == 0:
		return true
	if level > highest_level:
		return true
	if level < highest_level:
		return false
	return strain_index(strain) > strain_index(highest_strain)


func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var type := VariantUtil.as_string(action.get("type", ""), "")
	if not ACTION_TYPES.has(type):
		return _fail("game.bridge.error.unknown_action")
	var player := decision_player()
	var legal := find_legal_action(player, VariantUtil.as_string(action.get("key", ""), ""))
	if legal.is_empty():
		return _fail("game.bridge.error.illegal_action")
	match type:
		"pass":
			if phase_id != "auction":
				return _fail("game.bridge.error.illegal_action")
			_commit_pass(player)
		"bid":
			if phase_id != "auction":
				return _fail("game.bridge.error.illegal_action")
			_commit_bid(player, VariantUtil.as_int(legal.get("level", 0), 0), VariantUtil.as_string(legal.get("strain", ""), ""))
		"play":
			if phase_id != "play":
				return _fail("game.bridge.error.illegal_action")
			_commit_play(player, VariantUtil.as_string(legal.get("card", ""), ""))
	return _ok(action)


# ------------------------------------------------------------------- auction

func _commit_pass(seat: int) -> void:
	auction.append({"player": seat, "type": "pass"})
	passes_in_row += 1
	log_event("game.bridge.log_pass", {"player": player_name(seat)}, seat)
	if highest_bidder < 0:
		if passes_in_row >= SEATS:
			_finish_passed_out()
			return
	else:
		if passes_in_row >= 3:
			_start_play()
			return
	current_bidder = (seat + 1) % SEATS
	_sync_turn()


func _commit_bid(seat: int, level: int, strain: String) -> void:
	auction.append({
		"player": seat,
		"type": "bid",
		"level": level,
		"strain": strain,
		"bid": bid_text(level, strain),
	})
	highest_level = level
	highest_strain = strain
	highest_bidder = seat
	passes_in_row = 0
	log_event("game.bridge.log_bid", {
		"player": player_name(seat),
		"bid": bid_text(level, strain),
	}, seat)
	current_bidder = (seat + 1) % SEATS
	_sync_turn()


func _start_play() -> void:
	contract_level = highest_level
	contract_strain = highest_strain
	declarer = _find_declarer()
	dummy = partner_of(declarer)
	leader = (declarer + 1) % SEATS
	turn_seat = leader
	phase_id = "play"
	dummy_revealed = false
	trick.clear()
	trick_no = 1
	round_index = 1
	_sync_turn()
	log_event("game.bridge.log_contract", {
		"player": player_name(declarer),
		"bid": bid_text(contract_level, contract_strain),
	})


## The first player of the winning partnership who bid the final strain.
func _find_declarer() -> int:
	for entry: Dictionary in auction:
		if VariantUtil.as_string(entry.get("type", ""), "") != "bid":
			continue
		if VariantUtil.as_string(entry.get("strain", ""), "") != contract_strain:
			continue
		var seat := VariantUtil.as_int(entry.get("player", -1), -1)
		if partnership(seat) == partnership(highest_bidder):
			return seat
	return highest_bidder


func _finish_passed_out() -> void:
	phase_id = "finished"
	finish(-1, "game.bridge.reason.passed_out", _scores(0, 0, false))


# ---------------------------------------------------------------- the playing

func _commit_play(seat: int, card: String) -> void:
	if seat != turn_seat and not (turn_seat == dummy and seat == declarer):
		return
	_take_from_hand(turn_seat, card)
	trick.append({"player": turn_seat, "card": card})
	log_event("game.bridge.log_play", {
		"player": player_name(turn_seat),
		"card": card_text(card),
	}, turn_seat)
	if trick.size() == 1 and not dummy_revealed:
		dummy_revealed = true
		log_event("game.bridge.log_dummy", {"player": player_name(dummy)}, dummy)
	if trick.size() >= SEATS:
		_resolve_trick()
		return
	turn_seat = (turn_seat + 1) % SEATS
	_sync_turn()


func _resolve_trick() -> void:
	var winner := _trick_winner()
	if partnership(winner) == 0:
		tricks_ns += 1
	else:
		tricks_ew += 1
	log_event("game.bridge.log_trick", {
		"player": player_name(winner),
		"trick": trick_no,
	}, winner)
	trick.clear()
	if trick_no >= TRICKS:
		_finish_deal()
		return
	trick_no += 1
	round_index = trick_no
	leader = winner
	turn_seat = winner
	_sync_turn()


func _trick_winner() -> int:
	var led := led_suit()
	var best := -1
	var best_trump := false
	var best_rank := -1
	for entry: Dictionary in trick:
		var card := VariantUtil.as_string(entry.get("card", ""), "")
		var suit := card_suit(card)
		var trump := (not is_no_trump()) and suit == contract_strain
		if not trump and suit != led:
			continue
		var rank := rank_index(card)
		if best < 0 or (trump and not best_trump) or (trump == best_trump and rank > best_rank):
			best = VariantUtil.as_int(entry.get("player", 0), 0)
			best_trump = trump
			best_rank = rank
	return maxi(best, 0)


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


# --------------------------------------------------------------------- scoring

## Pure duplicate scoring for one contract (no vulnerability, no doubles).
func contract_score(level: int, strain: String, tricks: int) -> int:
	if level < 1 or level > 7 or not STRAINS.has(strain):
		return 0
	var needed := level + 6
	var per_trick := 20
	if strain == "NT":
		per_trick = 30
	elif strain == "H" or strain == "S":
		per_trick = 30
	var contract_points := level * per_trick
	if strain == "NT":
		contract_points += 10
	if tricks < needed:
		return -50 * (needed - tricks)
	var overtricks := tricks - needed
	var score := contract_points
	score += overtricks * per_trick
	score += 300 if contract_points >= 100 else 50
	if level == 6:
		score += 500
	elif level == 7:
		score += 750
	return score


func _finish_deal() -> void:
	phase_id = "finished"
	var tricks := declarer_tricks()
	var made := tricks >= needed_tricks()
	var score := contract_score(contract_level, contract_strain, tricks)
	var declarer_side := partnership(declarer)
	var scores := _scores(score, tricks, made)
	var winner := declarer if made else (declarer + 1) % SEATS
	if declarer < 0:
		winner = -1
	finish(winner, "game.bridge.reason.made" if made else "game.bridge.reason.down", scores)
	result["contract"] = {
		"level": contract_level,
		"strain": contract_strain,
		"bid": bid_text(contract_level, contract_strain),
		"declarer": declarer,
		"declarer_name": player_name(declarer),
		"dummy": dummy,
		"tricks": tricks,
		"needed": needed_tricks(),
		"made": made,
		"score": score,
		"side": "NS" if declarer_side == 0 else "EW",
	}
	log_event("game.bridge.log_made" if made else "game.bridge.log_down", {
		"contract": bid_text(contract_level, contract_strain),
		"tricks": tricks,
	})


## Per-seat score list. Partnerships score together; the defending side gets 0
## when the contract makes and the declaring side is negative when it goes down.
func _scores(declarer_score: int, tricks: int, made: bool) -> Array:
	var out := []
	var has_contract := declarer >= 0
	for seat: int in range(SEATS):
		var side := "NS" if partnership(seat) == 0 else "EW"
		var in_contract := has_contract and partnership(seat) == partnership(declarer)
		var seat_tricks := 0
		if has_contract:
			seat_tricks = tricks if in_contract else TRICKS - tricks
		out.append({
			"player": seat,
			"name": player_name(seat),
			"score": declarer_score if in_contract else 0,
			"side": side,
			"tricks": seat_tricks,
			"made": made,
		})
	return out


# ----------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["phase_id"] = phase_id
	state["dealer"] = dealer
	state["auction"] = auction.duplicate(true)
	state["current_bidder"] = current_bidder
	state["passes_in_row"] = passes_in_row
	state["highest_level"] = highest_level
	state["highest_strain"] = highest_strain
	state["highest_bidder"] = highest_bidder
	state["contract_level"] = contract_level
	state["contract_strain"] = contract_strain
	state["contract_bid"] = bid_text(contract_level, contract_strain) if contract_level > 0 else ""
	state["declarer"] = declarer
	state["dummy"] = dummy
	state["dummy_revealed"] = dummy_revealed
	state["dummy_hand"] = sorted_hand(dummy) if dummy_revealed and dummy >= 0 else []
	state["leader"] = leader
	state["turn_seat"] = turn_seat
	state["trick"] = trick.duplicate(true)
	state["trick_no"] = trick_no
	state["tricks_ns"] = tricks_ns
	state["tricks_ew"] = tricks_ew
	state["hand_counts"] = hand_counts.duplicate()
	return state


func private_state(player: int) -> Dictionary:
	if player < 0 or player >= hands.size():
		return {}
	var hand: Array[String] = []
	for card: Variant in VariantUtil.as_array(hands[player]):
		hand.append(VariantUtil.as_string(card, ""))
	return {"hand": hand}


## Installs ONE seat's hand on a client replica or from one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own cards plus
## the public counts.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0 or seat >= SEATS:
		return
	while hands.size() < SEATS:
		var filler: Array[String] = []
		hands.append(filler)
	_has_hands = true
	var hand: Array[String] = []
	copy_string_array(slice.get("hand", []), hand)
	hands[seat] = hand
	while hand_counts.size() < SEATS:
		hand_counts.append(0)
	hand_counts[seat] = hand.size()


func _restore_extra(state: Dictionary) -> void:
	phase_id = VariantUtil.as_string(state.get("phase_id", "auction"), "auction")
	dealer = VariantUtil.as_int(state.get("dealer", 0), 0)
	current_bidder = VariantUtil.as_int(state.get("current_bidder", dealer), dealer)
	passes_in_row = VariantUtil.as_int(state.get("passes_in_row", 0), 0)
	highest_level = VariantUtil.as_int(state.get("highest_level", 0), 0)
	highest_strain = VariantUtil.as_string(state.get("highest_strain", ""), "")
	highest_bidder = VariantUtil.as_int(state.get("highest_bidder", -1), -1)
	contract_level = VariantUtil.as_int(state.get("contract_level", 0), 0)
	contract_strain = VariantUtil.as_string(state.get("contract_strain", ""), "")
	declarer = VariantUtil.as_int(state.get("declarer", -1), -1)
	dummy = VariantUtil.as_int(state.get("dummy", -1), -1)
	dummy_revealed = bool(state.get("dummy_revealed", false))
	leader = VariantUtil.as_int(state.get("leader", 0), 0)
	turn_seat = VariantUtil.as_int(state.get("turn_seat", leader), leader)
	trick_no = maxi(1, VariantUtil.as_int(state.get("trick_no", 1), 1))
	round_index = maxi(1, VariantUtil.as_int(state.get("round", trick_no), trick_no))
	tricks_ns = VariantUtil.as_int(state.get("tricks_ns", 0), 0)
	tricks_ew = VariantUtil.as_int(state.get("tricks_ew", 0), 0)
	auction.clear()
	for entry: Variant in VariantUtil.as_array(state.get("auction", [])):
		if entry is Dictionary:
			auction.append((entry as Dictionary).duplicate(true))
	trick.clear()
	for entry: Variant in VariantUtil.as_array(state.get("trick", [])):
		if entry is Dictionary:
			trick.append((entry as Dictionary).duplicate(true))
	# Snapshot forms, strongest first:
	#   * save files: per-seat "private_states" bag (every hand);
	#   * whole-match snapshots: every hand under "hands";
	#   * client shape (the documented harness contract): the acting player's
	#     private slice merged at the top level, attributed to the decision
	#     player — only that seat's cards are present;
	#   * public-only spectator: counts plus the dummy hand once it is exposed.
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	hands.clear()
	hand_counts.clear()
	copy_int_array(state.get("hand_counts", []), hand_counts)
	if not privates.is_empty():
		for seat: int in range(SEATS):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hands"):
		_has_hands = true
		hand_counts.clear()
		for entry: Variant in VariantUtil.as_array(state.get("hands", [])):
			var hand: Array[String] = []
			copy_string_array(entry, hand)
			hands.append(hand)
			hand_counts.append(hand.size())
	elif state.has("hand"):
		_adopt_private_extra(decision_player(), state)
	else:
		_has_hands = false
		for _seat: int in range(SEATS):
			var empty: Array[String] = []
			hands.append(empty)
		if dummy >= 0 and dummy < hands.size() and dummy_revealed:
			var dummy_hand: Array[String] = []
			copy_string_array(state.get("dummy_hand", []), dummy_hand)
			hands[dummy] = dummy_hand
			hand_counts[dummy] = dummy_hand.size()
		# The public hand counters describe the real hands; do not recompute them
		# from the partial spectator model.
		return


# ------------------------------------------------------------- test/debug seam

## Installs an exact play position. All four hands must hold 13 distinct valid
## cards. The auction is synthesised so the view shows a contract.
func load_position(new_hands: Array, new_declarer: int, new_level: int, new_strain: String, new_leader: int) -> bool:
	if new_hands.size() != SEATS:
		return false
	if new_declarer < 0 or new_declarer >= SEATS:
		return false
	if new_level < 1 or new_level > 7 or not STRAINS.has(new_strain):
		return false
	var seen: Dictionary = {}
	var rebuilt: Array = []
	for entry: Variant in new_hands:
		if not (entry is Array) or VariantUtil.as_array(entry).size() != TRICKS:
			return false
		var hand: Array[String] = []
		for card: Variant in VariantUtil.as_array(entry):
			var code := VariantUtil.as_string(card, "")
			if not _valid_card(code) or seen.has(code):
				return false
			seen[code] = true
			hand.append(code)
		rebuilt.append(hand)
	hands = rebuilt
	_sync_counts()
	_has_hands = true
	contract_level = new_level
	contract_strain = new_strain
	declarer = new_declarer
	dummy = partner_of(new_declarer)
	highest_level = new_level
	highest_strain = new_strain
	highest_bidder = new_declarer
	auction.clear()
	auction.append({
		"player": new_declarer,
		"type": "bid",
		"level": new_level,
		"strain": new_strain,
		"bid": bid_text(new_level, new_strain),
	})
	passes_in_row = 0
	phase_id = "play"
	dummy_revealed = false
	leader = clampi(new_leader, 0, SEATS - 1)
	turn_seat = leader
	trick.clear()
	trick_no = 1
	tricks_ns = 0
	tricks_ew = 0
	round_index = 1
	finished = false
	result = {}
	_sync_turn()
	return true


func _valid_card(card: String) -> bool:
	return card.length() >= 2 and SUITS.has(card_suit(card)) and RANKS.has(card_rank(card))
