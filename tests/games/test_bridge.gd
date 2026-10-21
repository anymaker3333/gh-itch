extends RefCounted
## Bridge rules suite: the deal, the auction, declarer determination, the dummy,
## follow-suit, trumps, scoring, snapshots, determinism and privacy.
##
## Positions are installed with [method BridgeEngine.load_position], so the
## trick and scoring rules are tested exactly instead of shuffling for them.


func suite_name() -> String:
	return "bridge rules"


func run(h: TestHarness) -> void:
	_deal(h)
	_auction(h)
	_declarer(h)
	_trick_taking(h)
	_following_suit(h)
	_trumps(h)
	_scoring(h)
	_finish(h)
	_illegal_actions(h)
	_snapshots(h)
	_determinism(h)
	_bot_match(h)
	_privacy(h)


func _engine(h: TestHarness, seed_value: int = 20251021) -> BridgeEngine:
	var engine := EngineHarness.create("bridge", 4, seed_value)
	h.check(engine != null, "bridge engine must be creatable")
	return engine as BridgeEngine


func _key_for_card(engine: BridgeEngine, card: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("card", "")) == card:
			return String(action.get("key", ""))
	return "missing:%s" % card


func _bid_key(engine: BridgeEngine, level: int, strain: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "bid" \
				and int(action.get("level", 0)) == level \
				and String(action.get("strain", "")) == strain:
			return String(action.get("key", ""))
	return "missing:%d%s" % [level, strain]


func _pass_key(engine: BridgeEngine) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "pass":
			return String(action.get("key", ""))
	return "missing:pass"


func _plays(engine: BridgeEngine) -> Array[String]:
	var out: Array[String] = []
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "play":
			out.append(String(action.get("card", "")))
	return out


func _sorted(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for card: Variant in cards:
		out.append(String(card))
	out.sort()
	return out


func _deck() -> Array[String]:
	var cards: Array[String] = []
	for suit: String in BridgeEngine.SUITS:
		for rank: String in BridgeEngine.RANKS:
			cards.append(suit + rank)
	return cards


## Builds a legal 4×13 position. `lead` gives the first cards of each seat;
## the rest is filled deterministically from the unused cards. `void_seat` is
## filled without spades, which makes it possible to test trumping a spade lead.
func _position(h: TestHarness, lead: Array, declarer: int = 0, level: int = 3,
		strain: String = "NT", leader: int = 0, void_seat: int = -1) -> BridgeEngine:
	var engine := _engine(h)
	var used: Dictionary = {}
	var hands: Array = [[], [], [], []]
	for seat: int in range(4):
		var given: Array = lead[seat] if seat < lead.size() else []
		for card: Variant in given:
			var code := String(card)
			used[code] = true
			(hands[seat] as Array).append(code)
	var filler: Array[String] = []
	for card: String in _deck():
		if not used.has(card):
			filler.append(card)
	for seat: int in range(4):
		while (hands[seat] as Array).size() < 13:
			var picked := ""
			for index: int in range(filler.size() - 1, -1, -1):
				var candidate := filler[index]
				if seat == void_seat and BridgeEngine.card_suit(candidate) == "S":
					continue
				picked = candidate
				filler.remove_at(index)
				break
			if picked.is_empty():
				break
			(hands[seat] as Array).append(picked)
	var ok := engine.load_position(hands, declarer, level, strain, leader)
	h.check(ok, "the bridge position must load")
	return engine


# ----------------------------------------------------------------------- deal

func _deal(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.player_count(), 4, "bridge seats four players")
	h.equal(engine.phase(), "auction", "a fresh deal starts with the auction")
	h.equal(engine.dealer, 0, "seat 0 deals")
	h.equal(engine.decision_player(), 0, "seat 0 bids first")
	h.equal(engine.hand_counts, [13, 13, 13, 13] as Array[int], "every seat is dealt thirteen cards")
	h.equal(BridgeEngine.partnership(0), 0, "seats 0 and 2 are partners")
	h.equal(BridgeEngine.partnership(2), 0, "seat 2 is North–South")
	h.equal(BridgeEngine.partnership(1), 1, "seats 1 and 3 are partners")
	h.equal(BridgeEngine.partner_of(0), 2, "seat 0's partner is seat 2")
	var cards: Array = []
	for seat: int in range(4):
		for card: Variant in engine.private_state(seat).get("hand", []):
			cards.append(String(card))
	h.equal(cards.size(), BridgeEngine.DECK_SIZE, "the deal uses the whole deck")
	var seen: Dictionary = {}
	var duplicates := 0
	for card: Variant in cards:
		if seen.has(card):
			duplicates += 1
		seen[card] = true
	h.equal(duplicates, 0, "no card is dealt twice")
	EngineHarness.check_legal_action_shape(h, engine, "bridge opening")
	h.check(engine.legal_actions(0).size() == 36, "the opening bidder may pass or make any of the 35 bids")
	h.equal(engine.options_schema().size(), 0, "bridge exposes no setup options")

	var same := _engine(h)
	h.equal(same.private_state(0), engine.private_state(0), "the same seed deals the same hand")
	h.equal(same.public_state(), engine.public_state(), "the same seed deals the same public state")
	var other := _engine(h, 4243)
	h.check(other.private_state(0) != engine.private_state(0), "a different seed deals differently")


# -------------------------------------------------------------------- auction

func _auction(h: TestHarness) -> void:
	var engine := _engine(h)
	h.check(bool(engine.apply_action_by_key(0, _bid_key(engine, 1, "C")).get("ok", false)), "seat 0 opens 1♣")
	h.equal(engine.highest_level, 1, "the highest level is remembered")
	h.equal(engine.highest_strain, "C", "the highest strain is remembered")
	h.equal(engine.highest_bidder, 0, "the highest bidder is remembered")
	h.equal(engine.decision_player(), 1, "the auction moves clockwise")
	h.equal(engine.passes_in_row, 0, "a bid resets the pass counter")
	var lower := engine.apply_action({"type": "bid", "level": 1, "strain": "C", "key": "level=1|strain=C|type=bid"})
	h.equal(String(lower.get("error_key", "")), "game.bridge.error.illegal_action", "an equal bid is rejected")
	var out_of_turn := engine.apply_action_by_key(0, _bid_key(engine, 1, "D"))
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "bidding out of turn is rejected")

	h.check(bool(engine.apply_action_by_key(1, _bid_key(engine, 1, "D")).get("ok", false)), "seat 1 overcalls 1♦")
	h.check(bool(engine.apply_action_by_key(2, _bid_key(engine, 1, "H")).get("ok", false)), "seat 2 bids 1♥")
	h.check(bool(engine.apply_action_by_key(3, _bid_key(engine, 1, "S")).get("ok", false)), "seat 3 bids 1♠")
	h.check(bool(engine.apply_action_by_key(0, _bid_key(engine, 1, "NT")).get("ok", false)), "seat 0 bids 1NT")
	h.check(bool(engine.apply_action_by_key(1, _pass_key(engine)).get("ok", false)), "seat 1 passes")
	h.check(bool(engine.apply_action_by_key(2, _pass_key(engine)).get("ok", false)), "seat 2 passes")
	h.equal(engine.phase(), "auction", "two passes do not end the auction")
	h.check(bool(engine.apply_action_by_key(3, _pass_key(engine)).get("ok", false)), "seat 3 makes the third pass")
	h.equal(engine.phase(), "play", "three passes after a bid end the auction")
	h.equal(engine.contract_level, 1, "the contract level is the last bid")
	h.equal(engine.contract_strain, "NT", "the contract strain is the last bid")
	h.equal(engine.declarer, 0, "the first North–South player to bid no-trump declares")
	h.equal(engine.dummy, 2, "the declarer's partner is dummy")
	h.equal(engine.leader, 1, "the player on the declarer's left leads")
	h.equal(engine.dummy_revealed, false, "dummy stays hidden until the opening lead")
	h.equal(engine.public_state().get("dummy_hand", []), [], "the public snapshot hides dummy before the lead")
	EngineHarness.check_legal_action_shape(h, engine, "bridge opening lead")

	var passed := _engine(h, 99)
	for _i: int in range(4):
		passed.apply_action_by_key(passed.decision_player(), _pass_key(passed))
	h.check(passed.finished, "four opening passes end the deal")
	h.equal(passed.winner_index(), -1, "a passed-out deal is a draw")
	h.equal(String(passed.result.get("reason_key", "")), "game.bridge.reason.passed_out", "the passed-out reason is recorded")
	var passed_scores: Array = passed.result.get("scores", [])
	h.equal(passed_scores.size(), 4, "the passed-out result lists all four seats")
	for entry: Variant in passed_scores:
		h.equal(int((entry as Dictionary).get("score", -1)), 0, "a passed-out deal scores zero")
		h.equal(int((entry as Dictionary).get("tricks", -1)), 0, "a passed-out deal has no tricks")
	h.check(Loc.has_key("game.bridge.reason.passed_out", "en"), "the reason is translated")


## Declarer is the first player of the winning partnership to name the strain,
## not necessarily the last bidder.
func _declarer(h: TestHarness) -> void:
	var engine := _engine(h, 100)
	engine.apply_action_by_key(0, _pass_key(engine))
	engine.apply_action_by_key(1, _bid_key(engine, 1, "H"))
	engine.apply_action_by_key(2, _pass_key(engine))
	engine.apply_action_by_key(3, _bid_key(engine, 2, "H"))
	engine.apply_action_by_key(0, _pass_key(engine))
	engine.apply_action_by_key(1, _pass_key(engine))
	engine.apply_action_by_key(2, _pass_key(engine))
	h.equal(engine.phase(), "play", "the auction ends after the third pass")
	h.equal(engine.declarer, 1, "the first East–West heart bidder declares")
	h.equal(engine.dummy, 3, "the other East–West seat is dummy")
	h.equal(engine.leader, 2, "the player to the declarer's left leads")


# --------------------------------------------------------------- trick taking

func _trick_taking(h: TestHarness) -> void:
	var engine := _position(h, [
		["SA", "H2", "D2", "C2"],
		["S2", "H3", "D3", "C3"],
		["S3", "H4", "D4", "C4"],
		["S4", "H5", "D5", "C5"],
	], 0, 3, "NT", 1)
	h.equal(engine.phase(), "play", "the position starts in the play")
	h.equal(engine.decision_player(), 1, "the opening leader acts first")
	h.check(bool(engine.apply_action_by_key(1, _key_for_card(engine, "S2")).get("ok", false)), "seat 1 leads a spade")
	h.equal(engine.dummy_revealed, true, "the opening lead exposes dummy")
	h.equal((engine.public_state().get("dummy_hand", []) as Array).size(), 13, "dummy's whole hand becomes public")
	h.equal(engine.decision_player(), 0, "the declarer chooses dummy's card")
	h.equal(_plays(engine).has("H4"), false, "dummy must follow the led suit")
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "S3")).get("ok", false)), "the declarer plays dummy's S3")
	h.check(bool(engine.apply_action_by_key(3, _key_for_card(engine, "S4")).get("ok", false)), "seat 3 follows")
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "SA")).get("ok", false)), "the declarer follows with the SA")
	h.equal(engine.trick.size(), 0, "a full trick is resolved")
	h.equal(engine.leader, 0, "the SA wins the trick")
	h.equal(engine.decision_player(), 0, "the winner leads the next trick")
	h.equal(engine.tricks_ns, 1, "North–South take the trick")
	h.equal(engine.tricks_ew, 0, "East–West have no trick yet")
	h.equal(engine.trick_no, 2, "the trick counter advances")


func _following_suit(h: TestHarness) -> void:
	var engine := _position(h, [
		["S6", "H2", "C2", "D2"],
		["S9", "H5", "C3", "D3"],
		["S7", "H6", "C4", "D4"],
		["S8", "H7", "C5", "D5"],
	], 0, 3, "NT", 0)
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	h.equal(_plays(engine).has("H5"), false, "a defender with a spade may not discard")
	var cheat := engine.apply_action({"type": "play", "card": "H5", "key": "card=H5|type=play"})
	h.equal(String(cheat.get("error_key", "")), "game.bridge.error.illegal_action", "an off-suit card is rejected")
	engine.apply_action_by_key(1, _key_for_card(engine, "S9"))
	engine.apply_action_by_key(0, _key_for_card(engine, "S7"))
	engine.apply_action_by_key(3, _key_for_card(engine, "S8"))
	h.equal(engine.leader, 1, "the S9 beats the S8, S7 and S6")
	h.equal(engine.tricks_ew, 1, "East–West take the trick")


func _trumps(h: TestHarness) -> void:
	# Declarer 0 (N–S), dummy 2 is void in spades and plays a heart.
	var engine := _position(h, [
		["SA", "H2", "C2", "D2"],
		["S2", "H3", "C3", "D3"],
		["H4", "C4", "D4", "H6"],
		["S4", "H5", "C5", "D5"],
	], 0, 2, "H", 1, 2)
	engine.apply_action_by_key(1, _key_for_card(engine, "S2"))
	h.equal(_plays(engine).has("H4"), true, "a void player may trump")
	engine.apply_action_by_key(0, _key_for_card(engine, "H4"))
	engine.apply_action_by_key(3, _key_for_card(engine, "S4"))
	engine.apply_action_by_key(0, _key_for_card(engine, "SA"))
	h.equal(engine.leader, 2, "the lowest trump beats the ace of the led suit")
	h.equal(engine.tricks_ns, 1, "the trump trick goes to the declaring side")
	h.check(engine.led_suit().is_empty(), "the trick is cleared for the next lead")

	# No-trump: the same low heart loses to the ace of spades.
	var nt := _position(h, [
		["SA", "H2", "C2", "D2"],
		["S2", "H3", "C3", "D3"],
		["H4", "C4", "D4", "H6"],
		["S4", "H5", "C5", "D5"],
	], 0, 2, "NT", 1, 2)
	nt.apply_action_by_key(1, _key_for_card(nt, "S2"))
	nt.apply_action_by_key(0, _key_for_card(nt, "H4"))
	nt.apply_action_by_key(3, _key_for_card(nt, "S4"))
	nt.apply_action_by_key(0, _key_for_card(nt, "SA"))
	h.equal(nt.leader, 0, "without trumps the ace of the led suit wins")
	h.equal(nt.tricks_ns, 1, "North–South still take the trick")


# -------------------------------------------------------------------- scoring

func _scoring(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.contract_score(1, "C", 7), 70, "1♣ made scores 20 + 50 partscore")
	h.equal(engine.contract_score(2, "C", 8), 90, "2♣ with an overtrick scores 20 + 20 + 50")
	h.equal(engine.contract_score(3, "NT", 9), 400, "3NT made scores 100 + 300 game bonus")
	h.equal(engine.contract_score(4, "H", 10), 420, "4♥ made scores 120 + 300")
	h.equal(engine.contract_score(5, "C", 11), 400, "5♣ made scores 100 + 300")
	h.equal(engine.contract_score(6, "S", 12), 980, "6♠ made scores 180 + 300 + 500")
	h.equal(engine.contract_score(7, "NT", 13), 1270, "7NT made scores 220 + 300 + 750")
	h.equal(engine.contract_score(2, "NT", 8), 120, "2NT made scores 70 + 50 partscore")
	h.equal(engine.contract_score(2, "NT", 9), 150, "2NT with an overtrick scores 70 + 30 + 50")
	h.equal(engine.contract_score(4, "H", 9), -50, "one undertrick costs 50")
	h.equal(engine.contract_score(4, "H", 6), -200, "four undertricks cost 200")
	h.equal(engine.contract_score(0, "H", 10), 0, "an impossible contract scores nothing")
	h.equal(engine.contract_score(4, "X", 10), 0, "an unknown strain scores nothing")


func _finish(h: TestHarness) -> void:
	var made := _position(h, [], 0, 1, "C", 1)
	made.tricks_ns = 7
	made.tricks_ew = 6
	made._finish_deal()
	h.check(made.finished, "the deal finishes")
	h.equal(made.winner_index(), 0, "the declaring side wins when the contract makes")
	h.equal(String(made.result.get("reason_key", "")), "game.bridge.reason.made", "the made reason is recorded")
	h.equal(int((made.result.get("contract", {}) as Dictionary).get("tricks", -1)), 7, "the contract result reports the tricks")
	h.equal(int((made.result.get("contract", {}) as Dictionary).get("score", 0)), 70, "the contract result reports the score")
	h.equal(int((made.result.get("scores", []) as Array)[0].get("score", 0)), 70, "seat 0 scores the contract")

	var down := _position(h, [], 0, 4, "H", 1)
	down.tricks_ns = 9
	down.tricks_ew = 4
	down._finish_deal()
	h.check(down.finished, "a defeated contract finishes too")
	h.equal(down.winner_index(), 1, "a defender represents the winning side")
	h.equal(String(down.result.get("reason_key", "")), "game.bridge.reason.down", "the down reason is recorded")
	h.equal(int((down.result.get("contract", {}) as Dictionary).get("score", 0)), -50, "the defeated contract reports the penalty")
	h.equal(int((down.result.get("scores", []) as Array)[0].get("score", 0)), -50, "the declaring side scores the penalty")

	var passed := _engine(h, 101)
	for _i: int in range(4):
		passed.apply_action_by_key(passed.decision_player(), _pass_key(passed))
	h.check(passed.finished, "the passed-out deal is finished")
	h.equal(passed.legal_actions(0).size(), 0, "a finished auction offers no actions")


# ------------------------------------------------------------------- legality

func _illegal_actions(h: TestHarness) -> void:
	var engine := _position(h, [
		["S6", "H2", "C2", "D2"],
		["S9", "H5", "C3", "D3"],
		["S7", "H6", "C4", "D4"],
		["S8", "H7", "C5", "D5"],
	], 0, 3, "NT", 0)
	var out_of_turn := engine.apply_action_by_key(1, String(engine.legal_actions(0)[0].get("key", "")))
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "playing out of turn is rejected")
	var unknown := engine.apply_action({"type": "explode", "key": "type=explode"})
	h.equal(String(unknown.get("error_key", "")), "game.bridge.error.unknown_action", "an unknown action type is rejected")
	var cheat := engine.apply_action({"type": "play", "card": "HA", "key": "card=HA|type=play"})
	h.equal(String(cheat.get("error_key", "")), "game.bridge.error.illegal_action", "a card that is not in play is rejected")
	var limit := _position(h, [], 0, 3, "NT", 0)
	var bad := limit.apply_action({"type": "bid", "level": 9, "strain": "NT", "key": "level=9|strain=NT|type=bid"})
	h.equal(String(bad.get("error_key", "")), "game.bridge.error.illegal_action", "an impossible bid is rejected")


# ------------------------------------------------------------------ snapshots

func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, engine, "bridge (opening)")
	engine.apply_action_by_key(0, _bid_key(engine, 1, "C"))
	engine.apply_action_by_key(1, _bid_key(engine, 1, "S"))
	EngineHarness.check_snapshot_round_trip(h, engine, "bridge (mid-auction)")
	_full_round_trip(h, engine, "mid-auction")

	var play := _position(h, [
		["SA", "H2", "C2", "D2"],
		["S2", "H3", "C3", "D3"],
		["S3", "H4", "C4", "D4"],
		["S4", "H5", "C5", "D5"],
	], 0, 3, "NT", 1)
	EngineHarness.check_snapshot_round_trip(h, play, "bridge (before the lead)")
	play.apply_action_by_key(1, _key_for_card(play, "S2"))
	EngineHarness.check_snapshot_round_trip(h, play, "bridge (dummy exposed)")
	_full_round_trip(h, play, "dummy exposed")
	var spectator := Session.create_engine("bridge")
	spectator.restore_state(play.public_state())
	h.equal(spectator.public_state(), play.public_state(), "the public snapshot round trips")
	h.equal(spectator.legal_actions(spectator.decision_player()).size(), 0, "a public-only snapshot cannot play a card")

	EngineHarness.check_snapshot_round_trip(h, _finished_engine(h), "bridge (finished)")


func _full_round_trip(h: TestHarness, engine: BridgeEngine, label: String) -> void:
	var merged := engine.public_state()
	var hands: Array = []
	for seat: int in range(4):
		hands.append(engine.private_state(seat).get("hand", []))
	merged["hands"] = hands
	var copy := Session.create_engine("bridge") as BridgeEngine
	copy.restore_state(merged)
	h.equal(copy.public_state(), engine.public_state(), "%s: the public state survives a snapshot" % label)
	for seat: int in range(4):
		h.equal(copy.private_state(seat), engine.private_state(seat), "%s: seat %d survives a snapshot" % [label, seat])
	h.equal(_keys(copy.legal_actions(copy.decision_player())), _keys(engine.legal_actions(engine.decision_player())),
		"%s: legal actions survive a snapshot" % label)


func _keys(actions: Array) -> Array:
	var keys: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys


func _finished_engine(h: TestHarness) -> BridgeEngine:
	var engine := _position(h, [], 0, 1, "C", 1)
	engine.tricks_ns = 7
	engine.tricks_ew = 6
	engine._finish_deal()
	return engine


# --------------------------------------------------------------- determinism

func _determinism(h: TestHarness) -> void:
	var first := _engine(h, 777)
	var second := _engine(h, 777)
	for step: int in range(60):
		if first.finished:
			break
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the bridge bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bridge bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		h.equal(first.public_state(), second.public_state(), "the same actions give the same state (%d)" % step)
		h.equal(first.private_state(0), second.private_state(0), "…and the same hands (%d)" % step)


func _bot_match(h: TestHarness) -> void:
	for seed_value: int in [880001, 880002, 880003]:
		var engine := _engine(h, seed_value)
		var steps := EngineHarness.play_out(engine, 500)
		h.greater(float(steps), 0.0, "the bridge bot match makes progress")
		h.check(engine.finished, "the bridge bot match finishes")
		if engine.finished:
			h.check(not String(engine.result.get("reason_key", "")).is_empty(), "a finished match explains itself")
			h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the end reason is translated")
			var contract := engine.result.get("contract", {}) as Dictionary
			if not contract.is_empty():
				h.equal(engine.declarer_tricks(), int(contract.get("tricks", -1)), "the contract result matches the tricks")
				h.equal(engine.finished, true, "the finished flag is set")
		for entry: Dictionary in engine.move_log:
			h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
			h.no_raw_key(String(entry.get("text", "")), "log text is rendered")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	EngineHarness.check_privacy(h, engine, func(theirs: Dictionary, mine: Dictionary) -> Array:
		var mine_text := JSON.stringify(mine)
		var leaked: Array = []
		for card: Variant in theirs.get("hand", []):
			if mine_text.contains("\"%s\"" % String(card)):
				leaked.append(card)
		return leaked
	, "bridge")
	var public_text := JSON.stringify(engine.public_state())
	for seat: int in range(4):
		for card: Variant in engine.private_state(seat).get("hand", []):
			h.check(not public_text.contains("\"%s\"" % String(card)),
				"card %s of player %d is not in the public snapshot" % [card, seat])
	var play := _position(h, [
		["SA", "H2", "C2", "D2"],
		["S2", "H3", "C3", "D3"],
		["S3", "H4", "C4", "D4"],
		["S4", "H5", "C5", "D5"],
	], 0, 3, "NT", 1)
	play.apply_action_by_key(1, _key_for_card(play, "S2"))
	h.equal(_sorted(play.public_state().get("dummy_hand", [])), _sorted(play.private_state(2).get("hand", [])),
		"only the dummy hand is exposed")
	var after_lead := JSON.stringify(play.public_state())
	for seat: int in [0, 1, 3]:
		for card: Variant in play.private_state(seat).get("hand", []):
			h.check(not after_lead.contains("\"%s\"" % String(card)),
				"hidden card %s of player %d stays private after the lead" % [card, seat])
