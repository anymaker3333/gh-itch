class_name DanyEngine
extends GameEngine
## DANY rules engine: a hidden-information bluffing game for 2-6 seats.
##
## The 45-card deck holds five cosmetic suits (ember, tide, grove, dusk, frost)
## with values 1-9. Cards are dealt as evenly as possible; the remainder is
## sealed away unseen and never used. Hands are private - only their sizes, the
## public reputations, insights and the move log are visible.
##
## A turn: the decision player lays 1-3 cards from their hand face down (toggling
## hand slots) and then claims a value V: "the cards I laid add up to exactly V".
## The player may lie. The other living players answer in seat order, each either
## inspecting the claim or letting it stand:
##   * inspected, truthful - the claimant earns 1 insight, the inspector loses
##     1 reputation for doubting an honest hand;
##   * inspected, false    - the claimant loses 1 reputation, the inspector earns
##     2 insight for catching the lie;
##   * unchallenged        - nothing happens beyond the cards leaving the hand.
## Laid cards always leave the hand: shown when inspected, discarded unseen
## otherwise.
##
## The oracle is the smallest value a claim may name. It starts at 1 each round
## and rises to V + 1 after every resolved claim, so a round gradually demands
## bolder claims (honest or not). When it would pass 27 - the most three cards
## can sum to - a new round opens and the oracle drops back to 1.
##
## A player whose reputation reaches 0 is eliminated and their hand is discarded.
## The match ends when one seat remains (last_standing), when every living hand
## is empty (hands_empty) or at the hard turn cap (turn_limit); the last two are
## ranked by insight, then reputation, and a perfect tie is a draw. An eliminated
## seat never acts again; an alive seat with an empty hand may only fold.
##
## Documented simplifications: suits have no rule effect (they only colour the
## cards) and a claim concerns the sum of the laid cards, not their order.

const SUITS: Array[String] = ["ember", "tide", "grove", "dusk", "frost"]
const DECK_SIZE: int = 45
const CARDS_PER_SUIT: int = 9
const MAX_SELECTION: int = 3
## Nine plus nine plus nine: the largest sum three cards can make.
const MAX_CLAIM: int = 27
const START_REPUTATION: int = 3

const PHASE_SELECT: String = "select"
const PHASE_INSPECT: String = "inspect"
const PHASE_FINISHED: String = "finished"

## Private card lists, one plain array of card dictionaries per seat.
var hands: Array = []
## Public mirror of `hands[x].size()` so a public snapshot can restore the shape
## of the table without ever seeing a card.
var hand_counts: Array[int] = []
## Hand slots laid face down this turn (indices into the owner's hand).
var pending_slots: Array[int] = []
var claimed_value: int = -1
var oracle: int = 1
var reputations: Array[int] = []
var insights: Array[int] = []
var eliminated: Array[bool] = []
## Seat whose turn it is; during the inspect phase this stays on the claimant.
var turn_pos: int = 0
## Responder currently on the spot during the inspect phase (-1 otherwise).
var inspect_pos: int = -1
var turn_phase: String = PHASE_SELECT
var turn_count: int = 0
var turn_cap: int = 1


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "dany"


func setup(options: Dictionary) -> void:
	super.setup(options)
	var count := player_count()
	var deck := _build_deck()
	_shuffle(deck)
	var per := DECK_SIZE / maxi(1, count)
	hands = []
	hand_counts = []
	for seat: int in range(count):
		var hand: Array = deck.slice(seat * per, (seat + 1) * per)
		hands.append(hand)
		hand_counts.append(hand.size())
	reputations = []
	insights = []
	eliminated = []
	for seat: int in range(count):
		reputations.append(START_REPUTATION)
		insights.append(0)
		eliminated.append(false)
	pending_slots = []
	claimed_value = -1
	oracle = 1
	round_index = 1
	turn_pos = 0
	inspect_pos = -1
	turn_phase = PHASE_SELECT
	turn_count = 0
	turn_cap = DECK_SIZE * maxi(1, count)
	log_event("game.dany.log_start", {
		"count": count,
		"per_player": per,
		"sealed": DECK_SIZE - per * count,
	})


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_SELECT, PHASE_INSPECT, PHASE_FINISHED])


func phase() -> String:
	return turn_phase


func decision_player() -> int:
	if finished or player_count() == 0:
		return -1
	if turn_phase == PHASE_INSPECT and _alive(inspect_pos):
		return inspect_pos
	if _alive(turn_pos):
		return turn_pos
	return _next_alive_after(turn_pos)


# ------------------------------------------------------------- turn machinery

func _alive(seat: int) -> bool:
	if seat < 0 or seat >= player_count():
		return false
	if eliminated[seat]:
		return false
	return not bool(players[seat].get("resigned", false))


func _living_count() -> int:
	var living := 0
	for seat: int in range(player_count()):
		if _alive(seat):
			living += 1
	return living


## The next living seat after `seat`, wrapping once; `seat` itself when alone.
func _next_alive_after(seat: int) -> int:
	for step: int in range(1, player_count() + 1):
		var candidate := (seat + step) % player_count()
		if _alive(candidate):
			return candidate
	return seat


## Next player after `after_seat` who still has to answer the claim at `turn_pos`.
## Returns the claimant when the ring is complete (nobody left to doubt).
func _next_responder(after_seat: int) -> int:
	var claimant := turn_pos
	for step: int in range(1, player_count() + 1):
		var candidate := (after_seat + step) % player_count()
		if candidate == claimant:
			return claimant
		if _alive(candidate):
			return candidate
	return claimant


# --------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player < 0 or player != decision_player():
		return out
	if turn_phase == PHASE_SELECT:
		if int(hand_counts[player]) <= 0:
			out.append(make_action("pass", {}, "game.dany.pass"))
			return out
		for slot: int in range(int(hand_counts[player])):
			if pending_slots.has(slot):
				out.append(make_action("select", {"slot": slot}, "game.dany.deselect"))
			elif pending_slots.size() < MAX_SELECTION:
				out.append(make_action("select", {"slot": slot}, "game.dany.select"))
		if pending_slots.size() >= 1:
			for value: int in range(oracle, MAX_CLAIM + 1):
				out.append(make_action("claim", {"value": value}, "game.dany.claim"))
	elif turn_phase == PHASE_INSPECT:
		out.append(make_action("inspect", {}, "game.dany.inspect"))
		out.append(make_action("pass", {}, "game.dany.hold"))
	return out


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	if player < 0:
		return _fail("game.common.match_over")
	var selected: Dictionary = {}
	for candidate: Dictionary in legal_actions(player):
		if VariantUtil.as_string(candidate.get("key", ""), "") == VariantUtil.as_string(action.get("key", ""), ""):
			selected = candidate
			break
	if selected.is_empty():
		return _fail("game.dany.error.illegal_action")
	match VariantUtil.as_string(selected.get("type", ""), ""):
		"select":
			_commit_select(player, VariantUtil.as_int(selected.get("slot", -1), -1))
		"claim":
			_commit_claim(player, VariantUtil.as_int(selected.get("value", 0), 0))
		"inspect":
			_resolve_claim(player, true)
		"pass":
			_commit_pass(player)
		_:
			return _fail("game.dany.error.illegal_action")
	return _ok(action)


func _commit_select(player: int, slot: int) -> void:
	if pending_slots.has(slot):
		pending_slots.erase(slot)
	else:
		pending_slots.append(slot)
		pending_slots.sort()
	log_event("game.dany.log_lay", {"player": player_name(player), "count": pending_slots.size()}, player)


func _commit_claim(player: int, value: int) -> void:
	pending_slots.sort()
	claimed_value = value
	turn_phase = PHASE_INSPECT
	inspect_pos = _next_responder(player)
	log_event("game.dany.log_claim", {
		"player": player_name(player),
		"cards": pending_slots.size(),
		"value": value,
	}, player)
	if inspect_pos == player:
		# Nobody is left to doubt the claim; it simply stands.
		_resolve_claim(player, false)


## Pass on the inspect phase (let the claim stand) or fold with an empty hand.
func _commit_pass(player: int) -> void:
	if turn_phase == PHASE_INSPECT:
		var next := _next_responder(player)
		if next == turn_pos:
			_resolve_claim(player, false)
		else:
			inspect_pos = next
		return
	log_event("game.dany.log_fold", {"player": player_name(player)}, player)
	turn_count += 1
	if turn_count >= turn_cap:
		_finish_ranking("game.dany.reason_turn_limit")
		return
	turn_pos = _next_alive_after(player)
	if _all_hands_empty():
		_finish_ranking("game.dany.reason_hands_empty")


# ------------------------------------------------------------ claim resolution

func _resolve_claim(inspector: int, inspected: bool) -> void:
	var claimant := turn_pos
	var claimed := claimed_value
	var cards := _pending_cards(claimant)
	var total := _cards_total(cards)
	var truthful := total == claimed
	if inspected:
		if truthful:
			insights[claimant] += 1
			reputations[inspector] -= 1
			log_event("game.dany.log_inspected_true", {
				"player": player_name(claimant),
				"inspector": player_name(inspector),
				"value": claimed,
				"cards": _cards_text(cards),
			}, inspector)
		else:
			reputations[claimant] -= 1
			insights[inspector] += 2
			log_event("game.dany.log_inspected_false", {
				"player": player_name(claimant),
				"inspector": player_name(inspector),
				"value": claimed,
				"total": total,
				"cards": _cards_text(cards),
			}, inspector)
	else:
		log_event("game.dany.log_unchallenged", {
			"player": player_name(claimant),
			"cards": cards.size(),
		}, claimant)
	_discard_pending(claimant)
	pending_slots = []
	claimed_value = -1
	inspect_pos = -1
	turn_phase = PHASE_SELECT
	for seat: int in range(player_count()):
		if not eliminated[seat] and reputations[seat] <= 0:
			_eliminate(seat)
	if _living_count() <= 1:
		_finish_last_standing()
		return
	if _all_hands_empty():
		_finish_ranking("game.dany.reason_hands_empty")
		return
	_advance_oracle(claimed)
	turn_count += 1
	if turn_count >= turn_cap:
		_finish_ranking("game.dany.reason_turn_limit")
		return
	turn_pos = _next_alive_after(claimant)


## The oracle climbs after every resolved claim; when it passes the largest
## possible claim a new round opens at the bottom again.
func _advance_oracle(claimed: int) -> void:
	oracle = claimed + 1
	if oracle > MAX_CLAIM:
		oracle = 1
		round_index += 1
		log_event("game.dany.log_new_round", {"round": round_index})


func _pending_cards(claimant: int) -> Array:
	var cards: Array = []
	var hand: Array = hands[claimant] if claimant >= 0 and claimant < hands.size() else []
	for slot: int in pending_slots:
		if slot >= 0 and slot < hand.size():
			cards.append(hand[slot])
	return cards


func _discard_pending(claimant: int) -> void:
	var slots: Array[int] = []
	copy_int_array(pending_slots, slots)
	slots.sort()
	slots.reverse()
	var hand: Array = hands[claimant]
	for slot: int in slots:
		if slot >= 0 and slot < hand.size():
			hand.remove_at(slot)
	hand_counts[claimant] = hand.size()


func _eliminate(seat: int) -> void:
	eliminated[seat] = true
	hands[seat] = []
	hand_counts[seat] = 0
	log_event("game.dany.log_eliminated", {"player": player_name(seat)}, seat)


func _all_hands_empty() -> bool:
	for seat: int in range(player_count()):
		if _alive(seat) and int(hand_counts[seat]) > 0:
			return false
	return true


# ------------------------------------------------------------------- endings

func _finish_last_standing() -> void:
	var last := -1
	for seat: int in range(player_count()):
		if _alive(seat):
			last = seat
	turn_phase = PHASE_FINISHED
	finish(last, "game.dany.reason_last_standing", _scores())


## Highest insight wins; reputation breaks ties; a perfect tie is a draw.
func _finish_ranking(reason_key: String) -> void:
	var best := -1
	var best_insight := -1
	var best_reputation := -1
	var tied := false
	for seat: int in range(player_count()):
		if not _alive(seat):
			continue
		var insight := int(insights[seat])
		var reputation := int(reputations[seat])
		if best < 0 or insight > best_insight or (insight == best_insight and reputation > best_reputation):
			best = seat
			best_insight = insight
			best_reputation = reputation
			tied = false
		elif insight == best_insight and reputation == best_reputation:
			tied = true
	turn_phase = PHASE_FINISHED
	finish(-1 if tied else best, reason_key, _scores())


func _scores() -> Array:
	var out: Array = []
	for seat: int in range(player_count()):
		out.append({
			"player": seat,
			"name": player_name(seat),
			"score": int(insights[seat]) * 10 + maxi(0, int(reputations[seat])),
			"insight": insights[seat],
			"reputation": reputations[seat],
			"eliminated": eliminated[seat],
		})
	return out


# ------------------------------------------------------------------ card text

func _cards_text(cards: Array) -> String:
	var parts := PackedStringArray()
	for card: Variant in cards:
		parts.append(_card_text(VariantUtil.as_dict(card)))
	return ", ".join(parts)


func _card_text(card: Dictionary) -> String:
	return Loc.t("game.dany.card", {
		"value": VariantUtil.as_int(card.get("value", 0), 0),
		"suit": Loc.t("game.dany.suit.%s" % VariantUtil.as_string(card.get("suit", ""), "")),
	})


func _cards_total(cards: Array) -> int:
	var total := 0
	for card: Variant in cards:
		total += VariantUtil.as_int(VariantUtil.as_dict(card).get("value", 0), 0)
	return total


func _build_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for suit: String in SUITS:
		for value: int in range(1, CARDS_PER_SUIT + 1):
			deck.append({"id": "%s-%d" % [suit, value], "suit": suit, "value": value})
	return deck


## Fisher-Yates drawing every index from the engine's own [member rng], so a
## seed alone reproduces the whole deal (Array.shuffle would use the global one).
func _shuffle(deck: Array) -> void:
	for index: int in range(deck.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = deck[index]
		deck[index] = deck[swap]
		deck[swap] = held


# ------------------------------------------------------------------ snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["hand_counts"] = hand_counts.duplicate()
	state["pending_slots"] = pending_slots.duplicate()
	state["claimed_value"] = claimed_value
	state["oracle"] = oracle
	state["reputations"] = reputations.duplicate()
	state["insights"] = insights.duplicate()
	state["eliminated"] = eliminated.duplicate()
	state["turn_pos"] = turn_pos
	state["inspect_pos"] = inspect_pos
	state["turn_count"] = turn_count
	state["turn_cap"] = turn_cap
	return state


## Only the seat's own cards: everybody else ever sees sizes and the public log.
func private_state(player: int) -> Dictionary:
	if player < 0 or player >= player_count():
		return {}
	var hand: Array = []
	for entry: Variant in hands[player]:
		if entry is Dictionary:
			hand.append(VariantUtil.dict_copy(entry))
	return {"hand": hand}


func _restore_extra(state: Dictionary) -> void:
	copy_int_array(state.get("hand_counts", []), hand_counts)
	copy_int_array(state.get("pending_slots", []), pending_slots)
	copy_int_array(state.get("reputations", []), reputations)
	copy_int_array(state.get("insights", []), insights)
	eliminated = []
	for entry: Variant in VariantUtil.as_array(state.get("eliminated", [])):
		eliminated.append(bool(entry))
	claimed_value = VariantUtil.as_int(state.get("claimed_value", -1), -1)
	oracle = clampi(VariantUtil.as_int(state.get("oracle", 1), 1), 1, MAX_CLAIM)
	turn_pos = VariantUtil.as_int(state.get("turn_pos", 0), 0)
	inspect_pos = VariantUtil.as_int(state.get("inspect_pos", -1), -1)
	turn_count = VariantUtil.as_int(state.get("turn_count", 0), 0)
	turn_cap = maxi(1, VariantUtil.as_int(state.get("turn_cap", DECK_SIZE * maxi(1, player_count())), DECK_SIZE * maxi(1, player_count())))
	turn_phase = PHASE_FINISHED if finished else (PHASE_INSPECT if inspect_pos >= 0 else PHASE_SELECT)
	# A public snapshot never carries cards. The counts above drive every rule,
	# so legal actions survive the round trip; the owner's own private slice
	# (save-file bag or the client shape merged at the top level) restores the
	# actual cards, which the discard sub-phase needs to stay consistent.
	hands = []
	for seat: int in range(player_count()):
		hands.append([])
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	if not privates.is_empty():
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hand"):
		# Client shape (harness contract): the acting player's cards merged at
		# the top level, attributed to the decision player.
		_adopt_private_extra(decision_player(), state)


## Installs ONE seat's card list on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own cards.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0 or seat >= player_count():
		return
	while hands.size() < player_count():
		hands.append([])
	var hand: Array = []
	for entry: Variant in VariantUtil.as_array(slice.get("hand", [])):
		if entry is Dictionary:
			hand.append(VariantUtil.dict_copy(entry))
	hands[seat] = hand
	if hand_counts.size() <= seat:
		while hand_counts.size() < player_count():
			hand_counts.append(0)
	hand_counts[seat] = hand.size()
