extends RefCounted
## DANY rules suite: the deal, laying cards and claiming, every inspection
## outcome, the climbing oracle, eliminations, all three endings, snapshots,
## hidden hands and bot playouts.

const MAX_BOT_STEPS: int = 4000


func suite_name() -> String:
	return "dany rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_selection(h)
	_claiming(h)
	_inspections(h)
	_oracle_and_rounds(h)
	_elimination(h)
	_endings(h)
	_empty_hands(h)
	_illegal_actions(h)
	_seat_flexibility(h)
	_determinism(h)
	_snapshots(h)
	_privacy(h)
	_strings(h)
	_bot_match(h)


func _engine(h: TestHarness, count: int = 3, seed_value: int = 20251021) -> GameEngine:
	var engine := EngineHarness.create("dany", count, seed_value)
	h.check(engine != null, "dany engine must be creatable")
	return engine


# ------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.phase(), "select", "a match opens in the laying phase")
	h.equal(engine.player_count(), 3, "three seats are dealt in")
	h.equal(int(engine.oracle), 1, "the oracle opens at one")
	h.equal(int(engine.round_index), 1, "the first round opens")
	h.equal(int(engine.turn_pos), 0, "seat zero moves first")
	h.equal(engine.decision_player(), 0, "seat zero decides first")
	var per := 45 / 3
	for seat: int in range(3):
		h.equal(int(engine.hand_counts[seat]), per, "seat %d is dealt %d cards" % [seat, per])
		h.equal((engine.hands[seat] as Array).size(), per, "seat %d really holds them" % seat)
		h.equal(int(engine.reputations[seat]), DanyEngine.START_REPUTATION, "seat %d starts reputable" % seat)
		h.equal(int(engine.insights[seat]), 0, "seat %d starts without insight" % seat)
		h.check(not bool(engine.eliminated[seat]), "seat %d starts in the game" % seat)
	h.equal(int(engine.turn_cap), 45 * 3, "the turn cap scales with the table")
	# Every card of the deck is unique and somewhere.
	var ids: Dictionary = {}
	for seat: int in range(3):
		for card: Variant in engine.hands[seat]:
			var record: Dictionary = card
			var id := String(record.get("id", ""))
			h.check(not ids.has(id), "card %s appears once" % id)
			ids[id] = true
			h.check(int(record.get("value", 0)) >= 1 and int(record.get("value", 0)) <= 9, "card %s has a 1..9 value" % id)
			h.check(DanyEngine.SUITS.has(String(record.get("suit", ""))), "card %s belongs to a suit" % id)
	h.equal(ids.size(), 45, "all 45 cards are dealt out")
	# The opening action list: only the hand slots can be touched - a claim needs
	# at least one laid card first.
	h.equal(engine.legal_actions(0).size(), per, "only laying is offered before any card is laid")
	for action: Dictionary in engine.legal_actions(0):
		h.equal(String(action.get("type", "")), "select", "…and every opening action lays a card")
	EngineHarness.check_legal_action_shape(h, engine, "dany opening")
	var twin := _engine(h)
	h.equal(twin.public_state(), engine.public_state(), "the same seed deals the same table")
	h.equal(twin.private_state(0), engine.private_state(0), "…and the same hand")
	h.equal(twin.private_state(1), engine.private_state(1), "…to every seat")


# ----------------------------------------------------------------- selection

func _selection(h: TestHarness) -> void:
	var engine := _engine(h)
	h.check(_first_of_type(engine, "claim").is_empty(), "a claim needs at least one card")
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	h.equal(_slots(engine), [0], "a card is laid")
	h.check(not _first_of_type(engine, "claim").is_empty(), "now a claim is offered")
	_apply(engine, _action_for(engine, "select", {"slot": 1}))
	_apply(engine, _action_for(engine, "select", {"slot": 2}))
	h.equal(_slots(engine), [0, 1, 2], "up to three cards may be laid")
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "select":
			h.check(_slots(engine).has(int(action.get("slot", -1))), "a full spread may only be taken back")
	_apply(engine, _action_for(engine, "select", {"slot": 1}))
	h.equal(_slots(engine), [0, 2], "a card can be taken back")
	h.check(not _action_for(engine, "select", {"slot": 1}).is_empty(), "…and laid again")
	var claims := 0
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "claim":
			claims += 1
			h.check(int(action.get("value", 0)) >= int(engine.oracle), "claims respect the oracle")
	h.equal(claims, DanyEngine.MAX_CLAIM, "every value above the oracle can be claimed")


# ------------------------------------------------------------------ claiming

func _claiming(h: TestHarness) -> void:
	# Laying two cards worth exactly the claim: inspected and honest.
	var engine := _engine(h)
	_force_hand(engine, 0, [4, 5, 7])
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	_apply(engine, _action_for(engine, "select", {"slot": 1}))
	_apply(engine, _action_for(engine, "claim", {"value": 9}))
	h.equal(engine.phase(), "inspect", "a claim opens the inspection")
	h.equal(int(engine.claimed_value), 9, "the claim is on the table")
	h.equal(engine.decision_player(), 1, "the neighbour answers first")
	h.equal(engine.legal_actions(1).size(), 2, "the neighbour may doubt or let it stand")
	EngineHarness.check_legal_action_shape(h, engine, "dany inspection")
	# …but a player who is not on the spot has nothing to do.
	h.equal(engine.legal_actions(0).size(), 0, "the claimant waits")
	var inspect := _first_of_type(engine, "inspect")
	h.check(not inspect.is_empty(), "public state names the claim to inspect")
	_apply(engine, inspect)
	h.equal(int(engine.insights[0]), 1, "an honest claim earns insight")
	h.equal(int(engine.reputations[1]), DanyEngine.START_REPUTATION - 1, "the needless doubt costs a reputation")
	h.equal(int(engine.hand_counts[0]), 1, "the laid cards leave the hand")
	h.equal(_slots(engine).size(), 0, "the table is cleared")
	h.equal(engine.phase(), "select", "the table returns to laying cards")
	h.equal(engine.decision_player(), 1, "the next seat takes the turn")
	h.equal(int(engine.oracle), 10, "the oracle climbs to the claimed value plus one")
	h.check(_last_log_key(engine) == "game.dany.log_inspected_true", "the honest inspection is logged")


func _inspections(h: TestHarness) -> void:
	# 1. Unchallenged: nobody doubts, nothing happens.
	var calm := _engine(h)
	_force_hand(calm, 0, [6])
	_apply(calm, _action_for(calm, "select", {"slot": 0}))
	_apply(calm, _action_for(calm, "claim", {"value": 6}))
	h.equal(calm.decision_player(), 1, "the first neighbour answers")
	_apply(calm, _first_of_type(calm, "pass"))
	h.equal(calm.decision_player(), 2, "the second neighbour answers")
	_apply(calm, _first_of_type(calm, "pass"))
	h.equal(calm.phase(), "select", "everybody let it stand")
	h.equal(int(calm.insights[0]), 0, "an unchallenged claim earns nothing")
	h.equal(int(calm.reputations[1]), DanyEngine.START_REPUTATION, "…and costs nobody")
	h.equal(int(calm.hand_counts[0]), 0, "the cards are gone nonetheless")
	h.check(_last_log_key(calm) == "game.dany.log_unchallenged", "the quiet claim is logged")

	# 2. Caught lying: the liar loses a reputation, the catcher gains insight.
	var caught := _engine(h)
	_force_hand(caught, 0, [1, 1, 9])
	_apply(caught, _action_for(caught, "select", {"slot": 0}))
	_apply(caught, _action_for(caught, "select", {"slot": 1}))
	_apply(caught, _action_for(caught, "claim", {"value": 5}))
	_apply(caught, _first_of_type(caught, "inspect"))
	h.equal(int(caught.reputations[0]), DanyEngine.START_REPUTATION - 1, "a caught lie costs a reputation")
	h.equal(int(caught.insights[1]), 2, "the catcher earns two insight")
	h.equal(int(caught.hand_counts[0]), 1, "only the laid cards are discarded")
	h.check(_last_log_key(caught) == "game.dany.log_inspected_false", "the catch is logged")

	# 3. The responder ring skips the claimant and the eliminated, in seat order.
	var ring := _engine(h, 4)
	_force_hand(ring, 1, [2])
	ring.turn_pos = 1
	_apply(ring, _action_for(ring, "select", {"slot": 0}))
	_apply(ring, _action_for(ring, "claim", {"value": 2}))
	h.equal(ring.decision_player(), 2, "the ring starts after the claimant")
	_apply(ring, _first_of_type(ring, "inspect"))
	h.equal(int(ring.insights[1]), 1, "the claim was honest")


# ------------------------------------------------------------ oracle & rounds

func _oracle_and_rounds(h: TestHarness) -> void:
	var engine := _engine(h)
	_force_hand(engine, 0, [9, 9, 9])
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	_apply(engine, _action_for(engine, "select", {"slot": 1}))
	_apply(engine, _action_for(engine, "select", {"slot": 2}))
	_apply(engine, _action_for(engine, "claim", {"value": 27}))
	_apply(engine, _first_of_type(engine, "inspect"))
	h.equal(int(engine.oracle), 1, "the oracle resets once it passes twenty-seven")
	h.equal(int(engine.round_index), 2, "a new round begins")
	h.check(_last_log_key(engine) == "game.dany.log_new_round", "the new round is logged")
	# A claim exactly at the top: 27 was the ceiling, so the next claim is 1 again.
	var next_actor := engine.decision_player()
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	var claims := 0
	var lowest := 99
	for action: Dictionary in engine.legal_actions(next_actor):
		if String(action.get("type", "")) == "claim":
			claims += 1
			lowest = mini(lowest, int(action.get("value", 0)))
	h.equal(claims, DanyEngine.MAX_CLAIM, "claims stay available in the new round")
	h.equal(lowest, 1, "only the fresh oracle is claimable now")


# --------------------------------------------------------------- elimination

func _elimination(h: TestHarness) -> void:
	var engine := _engine(h)
	_set_field(engine, "reputations", 0, 1)
	_force_hand(engine, 0, [1])
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	_apply(engine, _action_for(engine, "claim", {"value": 2}))
	_apply(engine, _first_of_type(engine, "inspect"))
	h.check(bool(engine.eliminated[0]), "a liar without reputation leaves the table")
	h.equal(int(engine.hand_counts[0]), 0, "the eliminated hand is discarded")
	h.equal((engine.hands[0] as Array).size(), 0, "…for good")
	h.equal(engine.decision_player(), 1, "play moves on to the next living seat")
	h.equal(engine.private_state(0).get("hand", []).size(), 0, "the eliminated seat holds nothing")
	h.check(_last_log_key(engine) == "game.dany.log_eliminated", "the elimination is logged")
	# The fallen seat is skipped by the claim ring as well.
	_force_hand(engine, 1, [3])
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	_apply(engine, _action_for(engine, "claim", {"value": 3}))
	h.equal(engine.decision_player(), 2, "the eliminated seat is skipped in the ring")
	h.equal(engine.legal_actions(1).size(), 0, "…and gets no actions any more")
	_apply(engine, _first_of_type(engine, "pass"))
	h.check(engine.phase() == "select", "the claim stood with one living responder")


# ------------------------------------------------------------------- endings

func _endings(h: TestHarness) -> void:
	# 1. Last player standing.
	var last := _engine(h, 2)
	_set_field(last, "reputations", 1, 1)
	_force_hand(last, 1, [1])
	last.turn_pos = 1
	_apply(last, _action_for(last, "select", {"slot": 0}))
	_apply(last, _action_for(last, "claim", {"value": 2}))
	_apply(last, _first_of_type(last, "inspect"))
	h.check(last.finished, "one seat remaining ends the match")
	h.equal(String(last.result.get("reason_key", "")), "game.dany.reason_last_standing", "the reason is survival")
	h.equal(last.winner_index(), 0, "the survivor takes the match")

	# 2. Empty hands and identical records: a draw.
	var drawn := _engine(h, 2)
	_force_hand(drawn, 0, [5])
	_floor_hand(drawn, 1)
	_apply(drawn, _action_for(drawn, "select", {"slot": 0}))
	_apply(drawn, _action_for(drawn, "claim", {"value": 5}))
	_apply(drawn, _first_of_type(drawn, "pass"))
	h.check(drawn.finished, "empty hands end the match")
	h.equal(String(drawn.result.get("reason_key", "")), "game.dany.reason_hands_empty", "the reason is the empty table")
	h.equal(drawn.winner_index(), -1, "identical records draw")

	# 3. Empty hands, insight decides.
	var insight := _engine(h, 2)
	_set_field(insight, "insights", 1, 1)
	_force_hand(insight, 0, [5])
	_floor_hand(insight, 1)
	_apply(insight, _action_for(insight, "select", {"slot": 0}))
	_apply(insight, _action_for(insight, "claim", {"value": 5}))
	_apply(insight, _first_of_type(insight, "pass"))
	h.equal(insight.winner_index(), 1, "more insight wins the empty table")

	# 4. Equal insight: reputation breaks the tie.
	var tie := _engine(h, 2)
	_set_field(tie, "insights", 0, 1)
	_set_field(tie, "insights", 1, 1)
	_set_field(tie, "reputations", 1, 2)
	_force_hand(tie, 0, [5])
	_floor_hand(tie, 1)
	_apply(tie, _action_for(tie, "select", {"slot": 0}))
	_apply(tie, _action_for(tie, "claim", {"value": 5}))
	_apply(tie, _first_of_type(tie, "pass"))
	h.equal(tie.winner_index(), 0, "reputation breaks an insight tie")

	# 5. The hard turn cap also ranks by insight.
	var capped := _engine(h, 2)
	_set_field(capped, "insights", 1, 3)
	capped.turn_count = int(capped.turn_cap) - 1
	_force_hand(capped, 0, [3, 4])
	_force_hand(capped, 1, [5])
	_apply(capped, _action_for(capped, "select", {"slot": 0}))
	_apply(capped, _action_for(capped, "claim", {"value": 3}))
	_apply(capped, _first_of_type(capped, "pass"))
	h.check(capped.finished, "the turn cap ends the match")
	h.equal(String(capped.result.get("reason_key", "")), "game.dany.reason_turn_limit", "the reason is the cap")
	h.equal(capped.winner_index(), 1, "the cap ranks by insight")


# ---------------------------------------------------------------- empty hand

func _empty_hands(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	_floor_hand(engine, 0)
	h.equal(engine.legal_actions(0).size(), 1, "an empty hand offers one move")
	h.equal(String(_first_of_type(engine, "pass").get("type", "")), "pass", "…folding")
	_apply(engine, _first_of_type(engine, "pass"))
	h.equal(engine.decision_player(), 1, "the fold passes the turn")
	h.equal(int(engine.hand_counts[0]), 0, "…and changes nothing else")
	_floor_hand(engine, 1)
	engine.turn_pos = 1
	_apply(engine, _first_of_type(engine, "pass"))
	h.check(engine.finished, "an all-empty fold loop ends the match")
	h.equal(String(engine.result.get("reason_key", "")), "game.dany.reason_hands_empty", "the empty table decides")


# --------------------------------------------------------------- rejections

func _illegal_actions(h: TestHarness) -> void:
	var engine := _engine(h)
	var waiting := 1
	var stale := engine.legal_actions(engine.decision_player())[0]
	var out_of_turn := engine.apply_action_by_key(waiting, String(stale.get("key", "")))
	h.check(not bool(out_of_turn.get("ok", false)), "acting out of turn is rejected")
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "the rejection says whose turn it is")
	var bogus := engine.apply_action_by_key(engine.decision_player(), "claim=99|type=claim")
	h.check(not bool(bogus.get("ok", false)), "an unknown action is rejected")
	h.equal(String(bogus.get("error_key", "")), "game.common.illegal_action", "the rejection names the action")
	var early := engine.apply_action({"type": "claim", "value": 3, "key": "claim-early"})
	h.check(not bool(early.get("ok", false)), "a claim without a laid card is rejected")
	h.equal(String(early.get("error_key", "")), "game.dany.error.illegal_action", "with the game's own error key")
	var ghost := engine.apply_action({"type": "select", "slot": 99, "key": "slot-99"})
	h.check(not bool(ghost.get("ok", false)), "a hand slot that does not exist is rejected")
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	var lowball := engine.apply_action({"type": "claim", "value": 0, "key": "claim-low"})
	h.check(not bool(lowball.get("ok", false)), "a claim under the oracle is rejected")
	h.check(Loc.has_key("game.dany.error.illegal_action"), "the rejection key is translated")


# ------------------------------------------------------------------- 2..6 seats

func _seat_flexibility(h: TestHarness) -> void:
	var outcomes: Dictionary = {}
	for count: int in range(2, 7):
		var engine := _engine(h, count, 4000 + count)
		h.equal(engine.player_count(), count, "%d seats are supported" % count)
		var per := 45 / count
		for seat: int in range(count):
			h.equal(int(engine.hand_counts[seat]), per, "a %d-seat table deals %d cards each" % [count, per])
		var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
		h.check(engine.finished, "%d-seat bot match finishes (%d steps)" % [count, steps])
		var reason := String(engine.result.get("reason_key", ""))
		h.check(Loc.has_key(reason, "en"), "%d-seat ending is translated" % count)
		outcomes[reason] = int(outcomes.get(reason, 0)) + 1
	h.check(true, "bot endings observed: %s" % str(outcomes))


# ------------------------------------------------ determinism and snapshots

func _determinism(h: TestHarness) -> void:
	var first := _engine(h, 4)
	var second := _engine(h, 4)
	for step: int in range(30):
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the dany bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same actions give the same state")
	# Hidden cards must not differ either.
	if not first.finished:
		for seat: int in range(4):
			h.equal(first.private_state(seat), second.private_state(seat), "seat %d holds the same hand" % seat)


func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, engine, "dany opening")
	_apply(engine, _action_for(engine, "select", {"slot": 0}))
	_apply(engine, _action_for(engine, "select", {"slot": 2}))
	EngineHarness.check_snapshot_round_trip(h, engine, "dany mid-selection")
	_apply(engine, _action_for(engine, "claim", {"value": int(engine.oracle) + 4}))
	EngineHarness.check_snapshot_round_trip(h, engine, "dany inspection")
	_apply(engine, _first_of_type(engine, "inspect"))
	EngineHarness.check_snapshot_round_trip(h, engine, "dany after an inspection")
	var copy := EngineHarness.create("dany", 3, 4)
	copy.restore_state(engine.public_state())
	h.equal(copy.decision_player(), engine.decision_player(), "the restored copy waits for the same seat")
	h.equal(copy.phase(), engine.phase(), "the restored copy is in the same phase")
	h.equal(copy.legal_actions(copy.decision_player()).size(), engine.legal_actions(engine.decision_player()).size(),
		"the restored copy offers the same actions")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	EngineHarness.check_privacy(h, engine, _leaks, "dany")
	var state := engine.public_state()
	h.check(state.has("hand_counts"), "the public snapshot carries hand sizes")
	h.check(not state.has("hands") and not state.has("hand"), "…but never a hand")
	var text := str(state)
	for seat: int in range(4):
		for card: Variant in engine.hands[seat]:
			var id := String((card as Dictionary).get("id", ""))
			h.check(not text.contains(id), "card %s stays hidden" % id)
		for key: Variant in engine.private_state(seat):
			h.check(String(key) == "hand", "a private seat sees only its own hand")


func _leaks(theirs: Dictionary, mine: Dictionary) -> Array:
	var out: Array = []
	var mine_ids: Dictionary = {}
	for card: Variant in mine.get("hand", []):
		mine_ids[String((card as Dictionary).get("id", ""))] = true
	for card: Variant in theirs.get("hand", []):
		var id := String((card as Dictionary).get("id", ""))
		if mine_ids.has(id):
			out.append("card %s" % id)
	return out


# ------------------------------------------------------------------ strings

func _strings(h: TestHarness) -> void:
	var engine := _engine(h)
	for phase: String in engine.phases():
		h.check(Loc.has_key("game.dany.phase.%s" % phase, "en"), "phase %s is translated" % phase)
	for suit: String in DanyEngine.SUITS:
		h.check(Loc.has_key("game.dany.suit.%s" % suit, "en"), "suit %s is translated" % suit)
		h.no_raw_key(Loc.t("game.dany.suit.%s" % suit), "suit %s renders as text" % suit)
	for key: String in ["game.dany.select", "game.dany.deselect", "game.dany.claim", "game.dany.pass",
			"game.dany.inspect", "game.dany.hold"]:
		h.check(Loc.has_key(key, "en"), "action %s is translated" % key)
	for reason: String in ["game.dany.reason_last_standing", "game.dany.reason_hands_empty", "game.dany.reason_turn_limit"]:
		h.check(Loc.has_key(reason, "en"), "%s is translated" % reason)
		h.no_raw_key(Loc.t(reason), "%s renders as text" % reason)
	h.check(Loc.has_key("game.dany.card", "en"), "the card wording is translated")
	h.no_raw_key(Loc.t("game.dany.card", {"value": 3, "suit": Loc.t("game.dany.suit.ember")}), "a card renders as text")
	h.check(Loc.t("game.dany.card", {"value": 3, "suit": Loc.t("game.dany.suit.ember")}).contains("3"), "the card names its value")
	h.check(Loc.t("game.dany.desc").length() > 20.0, "the description is substantial")


func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "the bot match finishes")
	var reason := String(engine.result.get("reason_key", ""))
	h.check(Loc.has_key(reason, "en"), "the reason is translated")
	h.greater(float(engine.move_log.size()), 0.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
		h.no_raw_key(String(entry.get("text", "")), "log entry %s renders as text" % entry.get("text_key", ""))
	h.check(not Loc.missing_keys().has("game.dany.log_claim"), "the claim log uses a real string")
	# Every surviving card is still a unique member of the deck.
	var seen: Dictionary = {}
	for seat: int in range(4):
		for card: Variant in engine.hands[seat]:
			var id := String((card as Dictionary).get("id", ""))
			h.check(not seen.has(id), "card %s survives once" % id)
			seen[id] = true
	h.check(seen.size() <= 45, "the table never gains cards")


# ------------------------------------------------------------------ helpers

func _apply(engine: GameEngine, action: Dictionary) -> Dictionary:
	return engine.apply_action_by_key(engine.decision_player(), String(action.get("key", "")))


func _first_of_type(engine: GameEngine, action_type: String) -> Dictionary:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == action_type:
			return action
	return {}


func _action_for(engine: GameEngine, action_type: String, params: Dictionary) -> Dictionary:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) != action_type:
			continue
		var matches := true
		for key: Variant in params:
			if str(action.get(key, null)) != str(params[key]):
				matches = false
				break
		if matches:
			return action
	return {}


func _slots(engine: GameEngine) -> Array:
	var out: Array = []
	for slot: Variant in engine.pending_slots:
		out.append(int(slot))
	out.sort()
	return out


func _last_log_key(engine: GameEngine) -> String:
	if engine.move_log.is_empty():
		return ""
	return String((engine.move_log.back() as Dictionary).get("text_key", ""))


## Replaces a seat's hand with known cards (unique ids) for exact arithmetic in
## tests, keeping the public hand count in step. Array reads through a dynamic
## property return the live array, so writing into the local writes the engine.
func _force_hand(engine: GameEngine, seat: int, values: Array) -> void:
	var cards: Array = []
	for index: int in range(values.size()):
		cards.append({"id": "test-%d-%d" % [seat, index], "suit": "ember", "value": int(values[index])})
	var hands: Array = engine.hands
	hands[seat] = cards
	var counts: Array = engine.hand_counts
	counts[seat] = cards.size()


func _floor_hand(engine: GameEngine, seat: int) -> void:
	_force_hand(engine, seat, [])


func _set_field(engine: GameEngine, field: String, index: int, value: int) -> void:
	var values: Array = engine.get(field)
	values[index] = value
