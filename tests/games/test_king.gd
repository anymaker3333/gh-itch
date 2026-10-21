extends RefCounted
## King rules suite: the deal, the optional pass, trick taking with and without
## the led suit, penalty counters, the moon, the match end, snapshots and
## privacy.
##
## Positions are installed with the engine's [method KingEngine.load_position]
## seam (the card-game counterpart of chess' FEN) so every rule can be tested in
## isolation instead of shuffling for it.


func suite_name() -> String:
	return "king rules"


func run(h: TestHarness) -> void:
	_deal(h)
	_passing(h)
	_trick_taking(h)
	_following_suit(h)
	_penalties(h)
	_moon(h)
	_match_end(h)
	_illegal_actions(h)
	_snapshots(h)
	_determinism(h)
	_bot_match(h)
	_privacy(h)


func _engine(h: TestHarness, players: int = 3, seed_value: int = 20251020, options: Dictionary = {}) -> KingEngine:
	var engine := EngineHarness.create("king", players, seed_value, options)
	h.check(engine != null, "king engine must be creatable")
	return engine as KingEngine


## A position in the play phase: no set-aside pile, so the assertions stay exact.
func _position(h: TestHarness, hands: Array, leader: int = 0) -> KingEngine:
	var engine := _engine(h, hands.size())
	var ok := engine.load_position(hands, [], leader)
	h.check(ok, "the position must load")
	return engine


func _key_for_card(engine: KingEngine, card: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("card", "")) == card:
			return String(action.get("key", ""))
	return "missing:%s" % card


func _plays(engine: KingEngine) -> Array[String]:
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


func _all_cards(engine: KingEngine) -> Array:
	var cards: Array = []
	for hand: Variant in engine.hands:
		for card: Variant in hand as Array:
			cards.append(String(card))
	for card: Variant in engine.set_aside:
		cards.append(String(card))
	return cards


# ----------------------------------------------------------------------- deal

func _deal(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.player_count(), 3, "king seats three players by default")
	h.equal(engine.phase(), "passing", "a fresh deal starts with the pass")
	h.equal(engine.cards_per_player, 17, "three players receive seventeen cards each")
	h.equal(engine.hand_counts, [17, 17, 17] as Array[int], "every seat is dealt the same hand")
	h.equal(engine.set_aside.size(), 1, "the leftover card is set aside")
	h.equal(engine.leader, 0, "seat 0 leads the first trick")
	_check_full_deck(h, engine, "three players")
	EngineHarness.check_legal_action_shape(h, engine, "king opening")
	h.check(engine.private_state(0).has("hand"), "player 0 sees a hand")
	h.check(not engine.private_state(0).has("trick"), "the private snapshot holds nothing but the hand and the picks")

	var four := _engine(h, 4)
	h.equal(four.cards_per_player, 13, "four players receive thirteen cards each")
	h.equal(four.set_aside.size(), 0, "four players use the whole deck")
	h.equal(four.phase(), "passing", "four players also pass first")

	var five := _engine(h, 5)
	h.equal(five.cards_per_player, 10, "five players receive ten cards each")
	h.equal(five.set_aside.size(), 2, "five players leave two cards aside")

	var six := _engine(h, 6)
	h.equal(six.cards_per_player, 8, "six players receive eight cards each")
	h.equal(six.set_aside.size(), 4, "six players leave four cards aside")
	_check_full_deck(h, six, "six players")

	var no_pass := _engine(h, 3, 4242, {"passing": false})
	h.equal(no_pass.phase(), "playing", "the pass can be switched off")
	h.equal(no_pass.decision_player(), 0, "seat 0 opens the play when there is no pass")
	var plain := _engine(h, 3, 4243, {"shoot_moon": false})
	h.check(not plain.shoot_moon, "the moon rule can be switched off")
	h.equal(engine.options_schema().size(), 2, "two setup options are exposed")

	var same := _engine(h)
	h.equal(same.private_state(0), engine.private_state(0), "the same seed deals the same hand")
	h.equal(same.public_state(), engine.public_state(), "the same seed deals the same public state")
	var other := _engine(h, 3, 4244)
	h.check(other.private_state(0) != engine.private_state(0), "a different seed deals differently")


func _check_full_deck(h: TestHarness, engine: KingEngine, label: String) -> void:
	var cards := _all_cards(engine)
	h.equal(cards.size(), KingEngine.DECK_SIZE, "%s: the deal uses the whole deck" % label)
	var seen: Dictionary = {}
	var duplicates := 0
	for card: Variant in cards:
		if seen.has(card):
			duplicates += 1
		seen[card] = true
	h.equal(duplicates, 0, "%s: no card is dealt twice" % label)


# ----------------------------------------------------------------- the pass

func _passing(h: TestHarness) -> void:
	var engine := _engine(h)
	h.check(engine.load_position([
		["S6", "H9", "CK", "CQ", "D8", "D7"],
		["S9", "SJ", "H6", "D6", "C10", "D5"],
		["S7", "H8", "D9", "CJ", "D10", "SQ"],
	], [], 0, true), "the passing position loads")
	h.equal(engine.phase(), "passing", "the deal starts with the pass")
	h.equal(engine.decision_player(), 0, "seat 0 picks first")
	h.check(engine.private_state(0).has("picks"), "the picker sees their own picks")
	h.equal(_sorted(engine.private_state(0).get("picks", [])), [] as Array[String], "no card is picked yet")

	var strict := _engine(h)
	h.check(not strict.load_position([["S6", "H9"], ["S9", "SJ", "H6"], ["S7", "H8", "D9"]], [], 0, true),
		"the pass needs at least three cards per hand")
	h.check(not strict.load_position([["S6", "S6", "H9"], ["S9", "SJ", "H6"], ["S7", "H8", "D9"]], [], 0),
		"a duplicated card is refused")
	h.check(not strict.load_position([["S6"], ["S9", "SJ", "H6"]], [], 0), "a position must fill every seat")

	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "S6")).get("ok", false)), "seat 0 picks the S6")
	h.equal(engine.picks_count[0], 1, "the pick is counted")
	h.equal(engine.hand_counts[0], 5, "the picked card leaves the hand")
	h.equal(engine.decision_player(), 1, "the next seat picks")
	var out_of_turn := engine.apply_action_by_key(0, _key_for_card(engine, "H6"))
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "picking out of turn is rejected")
	var cheat := engine.apply_action({"type": "pick", "card": "HA", "key": "card=HA|type=pick"})
	h.equal(String(cheat.get("error_key", "")), "game.king.error.illegal_action", "a card outside the hand cannot be picked")

	engine.apply_action_by_key(1, _key_for_card(engine, "H6"))
	engine.apply_action_by_key(2, _key_for_card(engine, "SQ"))
	engine.apply_action_by_key(0, _key_for_card(engine, "CQ"))
	engine.apply_action_by_key(1, _key_for_card(engine, "D6"))
	engine.apply_action_by_key(2, _key_for_card(engine, "D10"))
	engine.apply_action_by_key(0, _key_for_card(engine, "D8"))
	engine.apply_action_by_key(1, _key_for_card(engine, "D5"))
	engine.apply_action_by_key(2, _key_for_card(engine, "CJ"))

	h.equal(engine.phase(), "playing", "the play starts after the last pick")
	h.equal(engine.leader, 0, "the first leader opens the play")
	h.equal(engine.picks_count, [0, 0, 0] as Array[int], "the pick counters reset")
	h.check(not engine.private_state(0).has("picks"), "picks stay private to the passing phase")
	h.equal(_sorted(engine.private_state(0).get("hand", [])), _sorted(["H9", "CK", "D7", "SQ", "D10", "CJ"]),
		"seat 0 receives the picks of the player on the right")
	h.equal(_sorted(engine.private_state(1).get("hand", [])), _sorted(["S9", "SJ", "C10", "S6", "CQ", "D8"]),
		"seat 1 receives the picks of seat 0")
	h.equal(_sorted(engine.private_state(2).get("hand", [])), _sorted(["S7", "H8", "D9", "H6", "D6", "D5"]),
		"seat 2 receives the picks of seat 1")


# --------------------------------------------------------------- trick taking

func _trick_taking(h: TestHarness) -> void:
	var engine := _position(h, [
		["D9", "H4", "S2", "C3"],
		["DK", "H5", "S4", "C5"],
		["HA", "S5", "C6", "H7"],
	], 0)
	h.equal(engine.led_suit(), "", "no suit is led before the first card")
	h.equal(engine.decision_player(), 0, "the leader opens the trick")
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "D9")).get("ok", false)), "the leader plays D9")
	h.equal(engine.led_suit(), "D", "the first card fixes the led suit")
	h.equal(_plays(engine), ["DK"] as Array[String], "a player holding the led suit must follow it")
	h.check(bool(engine.apply_action_by_key(1, _key_for_card(engine, "DK")).get("ok", false)), "seat 1 follows with the DK")
	h.equal(_plays(engine).size(), 4, "a player without the led suit may play any card")
	engine.apply_action_by_key(2, _key_for_card(engine, "HA"))
	h.check(engine.trick.is_empty(), "a full trick is resolved")
	h.equal(engine.leader, 1, "the highest card of the led suit takes the trick")
	h.equal(engine.decision_player(), 1, "the winner leads the next trick")
	h.equal(engine.hearts_taken[1], 1, "the winner takes the off-suit heart of the trick")
	h.equal(engine.hearts_taken[2], 0, "a heart shed into a lost trick is not counted against its owner")
	h.equal(engine.trick_no, 2, "the trick counter advances")


# ----------------------------------------------------------- following suit

func _following_suit(h: TestHarness) -> void:
	var engine := _position(h, [["S6", "H2", "C3"], ["S9", "H5", "C4"], ["S7", "H6", "C5"]], 0)
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "S6")).get("ok", false)), "seat 0 leads the S6")
	h.equal(_plays(engine), ["S9"] as Array[String], "a spade is the only legal answer")
	var cheat := engine.apply_action({"type": "play", "card": "H5", "key": "card=H5|type=play"})
	h.equal(String(cheat.get("error_key", "")), "game.king.error.illegal_action", "an off-suit card is rejected while the suit can be followed")
	engine.apply_action_by_key(1, _key_for_card(engine, "S9"))
	engine.apply_action_by_key(2, _key_for_card(engine, "S7"))
	h.check(engine.trick.is_empty(), "the spade trick is resolved")
	h.equal(engine.leader, 1, "the S9 beats the S7 and the S6")
	# The winner leads; the others must follow the new suit again.
	h.equal(engine.led_suit(), "", "the resolved trick clears the lead")


# ------------------------------------------------------------------ penalties

func _penalties(h: TestHarness) -> void:
	var engine := _position(h, [
		["H2", "S3", "C4", "D5"],
		["H7", "SQ", "C5", "D6"],
		["HK", "S6", "C7", "D8"],
	], 0)
	engine.apply_action_by_key(0, _key_for_card(engine, "H2"))
	engine.apply_action_by_key(1, _key_for_card(engine, "H7"))
	engine.apply_action_by_key(2, _key_for_card(engine, "HK"))
	h.equal(engine.leader, 2, "the king of hearts takes the first trick")
	h.equal(engine.kings_taken[2], 1, "the king of hearts is a bonus for the winner")
	h.equal(engine.hearts_taken[2], 3, "the winner takes every heart of the trick")
	h.equal(engine.hearts_taken[0], 0, "a heart shed into a lost trick is not counted against its owner")
	engine.apply_action_by_key(2, _key_for_card(engine, "S6"))
	engine.apply_action_by_key(0, _key_for_card(engine, "S3"))
	engine.apply_action_by_key(1, _key_for_card(engine, "SQ"))
	h.equal(engine.queens_taken[1], 1, "the queen of spades is counted once")
	h.equal(engine.leader, 1, "the queen of spades takes the second trick")
	engine.apply_action_by_key(1, _key_for_card(engine, "C5"))
	engine.apply_action_by_key(2, _key_for_card(engine, "C7"))
	engine.apply_action_by_key(0, _key_for_card(engine, "C4"))
	h.equal(engine.leader, 2, "the higher club takes the third trick")
	engine.apply_action_by_key(2, _key_for_card(engine, "D8"))
	engine.apply_action_by_key(0, _key_for_card(engine, "D5"))
	engine.apply_action_by_key(1, _key_for_card(engine, "D6"))
	h.check(engine.finished, "the last card ends the deal")
	h.equal(engine.hearts_taken, [0, 0, 3] as Array[int], "hearts are counted per winner")
	h.equal(engine.queens_taken, [0, 1, 0] as Array[int], "the queen of spades is counted once")
	h.equal(engine.kings_taken, [0, 0, 1] as Array[int], "the king of hearts is counted once")
	h.equal(engine.score_for(1), 5, "the queen of spades adds five points")
	h.equal(engine.score_for(2), -2, "the king bonus offsets the hearts")
	h.equal(engine.winner_index(), 2, "the smallest score wins")


# ------------------------------------------------------------------ the moon

func _moon(h: TestHarness) -> void:
	var engine := _engine(h, 3, 999)
	engine.hearts_taken = [0, 13, 0] as Array[int]
	engine.queens_taken = [0, 1, 0] as Array[int]
	engine.kings_taken = [0, 1, 0] as Array[int]
	h.check(engine.is_moon_shooter(1), "every heart plus the queen of spades is a moon")
	h.check(not engine.is_moon_shooter(0), "an empty scorecard is not a moon")
	h.equal(engine.score_for(1), -5, "the moon waives the hearts and the queen")
	var off := _engine(h, 3, 999, {"shoot_moon": false})
	off.hearts_taken = [0, 13, 0] as Array[int]
	off.queens_taken = [0, 1, 0] as Array[int]
	off.kings_taken = [0, 1, 0] as Array[int]
	h.check(off.is_moon_shooter(1), "the shot is still detected when the option is off")
	h.equal(off.score_for(1), 13, "with the option off the moon pays 13 points")
	var almost := _engine(h, 3, 999)
	almost.hearts_taken = [0, 12, 1] as Array[int]
	almost.queens_taken = [0, 1, 0] as Array[int]
	h.check(not almost.is_moon_shooter(1), "twelve hearts are not a moon")


# ----------------------------------------------------------------- match end

func _match_end(h: TestHarness) -> void:
	var engine := _position(h, [["D9"], ["H2"], ["C4"]], 0)
	engine.apply_action_by_key(0, _key_for_card(engine, "D9"))
	engine.apply_action_by_key(1, _key_for_card(engine, "H2"))
	engine.apply_action_by_key(2, _key_for_card(engine, "C4"))
	h.check(engine.finished, "the last trick ends the deal")
	h.equal(engine.winner_index(), 1, "the lowest score wins and a tie goes to the lowest seat")
	h.equal(String(engine.result.get("reason_key", "")), "game.king.reason.finished", "the deal end is the reason")
	h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the reason is translated")
	h.equal(engine.scores_text(), "P1: 1, P2: 0, P3: 0", "every seat is reported with its score")
	h.check(engine.legal_actions(0).is_empty(), "a finished deal offers no actions")
	var over := engine.apply_action_by_key(0, "type=play|card=D9")
	h.equal(String(over.get("error_key", "")), "game.common.match_over", "no action after the match")


# ----------------------------------------------------------------- legality

func _illegal_actions(h: TestHarness) -> void:
	var engine := _position(h, [["D9", "H4"], ["DK", "H5"], ["D8", "H6"]], 0)
	var out_of_turn := engine.apply_action_by_key(1, String(engine.legal_actions(0)[0].get("key", "")))
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "playing out of turn is rejected")
	var unknown := engine.apply_action({"type": "explode", "key": "type=explode"})
	h.equal(String(unknown.get("error_key", "")), "game.king.error.unknown_action", "an unknown action type is rejected")
	var cheat := engine.apply_action({"type": "play", "card": "HA", "key": "card=HA|type=play"})
	h.equal(String(cheat.get("error_key", "")), "game.king.error.illegal_action", "a card that is not in hand is rejected")
	engine.apply_action_by_key(0, _key_for_card(engine, "D9"))
	var pick := engine.apply_action({"type": "pick", "card": "H5", "key": "card=H5|type=pick"})
	h.equal(String(pick.get("error_key", "")), "game.king.error.illegal_action", "there is no passing once the play started")


# ----------------------------------------------------------------- snapshots

func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	_full_round_trip(h, engine, "opening")
	var public_only := Session.create_engine("king")
	public_only.restore_state(engine.public_state())
	h.equal(public_only.public_state(), engine.public_state(), "the public snapshot round trips")
	h.equal(public_only.legal_actions(public_only.decision_player()).size(), 0, "a public-only snapshot cannot pick a card")
	engine.apply_action_by_key(engine.decision_player(), String(engine.legal_actions(engine.decision_player())[0].get("key", "")))
	_full_round_trip(h, engine, "mid-passing")
	for _step: int in range(engine.player_count() * KingEngine.PASS_COUNT):
		if engine.phase() != "passing":
			break
		engine.apply_action_by_key(engine.decision_player(), String(engine.legal_actions(engine.decision_player())[0].get("key", "")))
	h.equal(engine.phase(), "playing", "the passing phase completes")
	_full_round_trip(h, engine, "first trick")
	engine.apply_action_by_key(engine.decision_player(), String(engine.legal_actions(engine.decision_player())[0].get("key", "")))
	_full_round_trip(h, engine, "mid-trick")
	var spectator := Session.create_engine("king")
	spectator.restore_state(engine.public_state())
	h.equal(spectator.public_state(), engine.public_state(), "the public snapshot round trips mid-trick")
	h.equal(spectator.legal_actions(spectator.decision_player()).size(), 0, "a public-only snapshot cannot play a card")
	EngineHarness.check_snapshot_round_trip(h, _finished_engine(h), "king (finished)")


## Public + private + set-aside: the state the host and its clients really hold.
func _full_round_trip(h: TestHarness, engine: KingEngine, label: String) -> void:
	var merged := engine.public_state()
	var hands: Array = []
	var picks: Array = []
	for seat: int in range(engine.player_count()):
		hands.append(engine.private_state(seat).get("hand", []))
		picks.append(engine.private_state(seat).get("picks", []))
	merged["hands"] = hands
	merged["picks"] = picks
	merged["set_aside"] = engine.set_aside.duplicate()
	var copy := Session.create_engine("king") as KingEngine
	copy.restore_state(merged)
	h.equal(copy.public_state(), engine.public_state(), "%s: the public state survives a snapshot" % label)
	h.equal(copy.set_aside, engine.set_aside, "%s: the set-aside pile survives a snapshot" % label)
	for seat: int in range(engine.player_count()):
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


func _finished_engine(h: TestHarness) -> KingEngine:
	var engine := _position(h, [["D9"], ["H2"], ["C4"]], 0)
	engine.apply_action_by_key(0, _key_for_card(engine, "D9"))
	engine.apply_action_by_key(1, _key_for_card(engine, "H2"))
	engine.apply_action_by_key(2, _key_for_card(engine, "C4"))
	return engine


# --------------------------------------------------------------- determinism

func _determinism(h: TestHarness) -> void:
	var first := _engine(h, 3, 777)
	var second := _engine(h, 3, 777)
	for step: int in range(40):
		if first.finished:
			break
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		h.equal(first.public_state(), second.public_state(), "the same actions give the same state (%d)" % step)
		h.equal(first.private_state(0), second.private_state(0), "…and the same hands (%d)" % step)


func _bot_match(h: TestHarness) -> void:
	for players: int in [3, 6]:
		var engine := _engine(h, players, 880000 + players)
		var steps := EngineHarness.play_out(engine, 400)
		h.greater(float(steps), 0.0, "the %d-player bot match makes progress" % players)
		h.check(engine.finished, "the %d-player bot match finishes" % players)
		if engine.finished:
			h.check(not String(engine.result.get("reason_key", "")).is_empty(), "a finished match explains itself")
			h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the end reason is translated")
		for entry: Dictionary in engine.move_log:
			h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
			h.no_raw_key(String(entry.get("text", "")), "log text is rendered")
	var no_pass := _engine(h, 4, 880200, {"passing": false})
	h.equal(no_pass.phase(), "playing", "the pass can be skipped")
	EngineHarness.play_out(no_pass, 400)
	h.check(no_pass.finished, "a match without the pass also finishes")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	# Nothing of another seat may show up in my private snapshot.
	EngineHarness.check_privacy(h, engine, func(theirs: Dictionary, mine: Dictionary) -> Array:
		var mine_text := JSON.stringify(mine)
		var leaked: Array = []
		for key: String in ["hand", "picks"]:
			for card: Variant in theirs.get(key, []):
				if mine_text.contains("\"%s\"" % String(card)):
					leaked.append(card)
		return leaked
	, "king")
	var public_text := JSON.stringify(engine.public_state())
	for seat: int in range(engine.player_count()):
		for card: Variant in engine.private_state(seat).get("hand", []):
			h.check(not public_text.contains("\"%s\"" % String(card)),
				"card %s of player %d is not in the public snapshot" % [card, seat])
