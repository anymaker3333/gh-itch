extends RefCounted
## Spyfall rules suite: the deal, the question loop, all four endings, the shared
## (role-independent) action set, snapshots, hidden identities and bot playouts.

const MAX_BOT_STEPS: int = 2000


func suite_name() -> String:
	return "spyfall rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_question_loop(h)
	_endings(h)
	_role_quirks(h)
	_illegal_actions(h)
	_seat_flexibility(h)
	_determinism(h)
	_snapshots(h)
	_privacy(h)
	_strings(h)
	_bot_match(h)


func _engine(h: TestHarness, count: int = 5, seed_value: int = 20251020) -> GameEngine:
	var engine := EngineHarness.create("spyfall", count, seed_value)
	h.check(engine != null, "spyfall engine must be creatable")
	return engine


# ------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.phase(), "ask", "a match opens in the questioning phase")
	h.equal(engine.player_count(), 5, "five seats are dealt in")
	h.check(SpyfallEngine.LOCATIONS.has(String(engine.location)), "a real location is drawn")
	h.equal(engine.candidates.size(), 3, "the spy gets three candidate places")
	h.check(engine.candidates.has(String(engine.location)), "one candidate is the true location")
	var spies := 0
	for player: int in range(engine.player_count()):
		if bool(engine.private_state(player).get("is_spy", false)):
			spies += 1
	h.equal(spies, 1, "exactly one seat is the spy")
	h.check(engine.spy >= 0 and engine.spy < engine.player_count(), "the spy is a real seat")
	h.check(engine.private_state(engine.spy).has("candidates"), "the spy knows the candidate list")
	h.check(not engine.private_state(engine.spy).has("location"), "the spy does not know the location")
	var agent := _first_agent(engine)
	h.equal(String(engine.private_state(agent).get("location", "")), String(engine.location), "an agent knows the location")
	h.check(SpyfallEngine.ROLES.has(String(engine.private_state(agent).get("role", ""))), "an agent gets a flavour role")
	h.check(not engine.public_state().has("spy"), "the spy is not public")
	h.check(not engine.public_state().has("location"), "the location is not public")
	h.check(not engine.public_state().has("_reveal"), "nothing is revealed while the match runs")
	h.equal(engine.asks_limit, 3 * 5, "three rounds of five questions are played")
	h.equal(engine.legal_actions(0).size(), 9 * 4 + 4 + SpyfallEngine.LOCATIONS.size(), "asking, accusing and naming are offered")
	EngineHarness.check_legal_action_shape(h, engine, "spyfall opening")
	var twin := _engine(h)
	h.equal(twin.public_state(), engine.public_state(), "the same seed deals the same table")
	h.equal(twin.location, engine.location, "…the same location")
	h.equal(twin.spy, engine.spy, "…and the same spy")
	h.equal(twin.candidates, engine.candidates, "…and the same candidates")


# ------------------------------------------------------------- question loop

func _question_loop(h: TestHarness) -> void:
	var engine := _engine(h)
	var asker := engine.decision_player()
	var ask := _first_of_type(engine, "ask")
	h.check(not ask.is_empty(), "asking is legal")
	_apply(engine, ask)
	h.equal(engine.phase(), "answer", "the target must answer")
	h.equal(engine.decision_player(), int(ask.get("target", -1)), "the asked player is on the spot")
	h.check(engine.legal_actions(engine.decision_player()).size() == SpyfallEngine.ANSWERS.size(), "every answer card is offered")
	var answer := _first_of_type(engine, "answer")
	_apply(engine, answer)
	h.equal(engine.phase(), "ask", "the table returns to questions")
	h.equal(engine.history.size(), 1, "the exchange is recorded")
	h.equal(engine.ask_count, 1, "one question is counted")
	var record: Dictionary = engine.history[0]
	h.equal(int(record.get("asker", -1)), asker, "the asker is recorded")
	h.equal(int(record.get("target", -1)), int(ask.get("target", -1)), "the answerer is recorded")
	h.equal(int(record.get("answer", -1)), int(answer.get("answer", -1)), "the answer card is recorded")
	h.check(engine.decision_player() != asker or engine.player_count() == 1, "the turn moved on")
	# On-topic knowledge: agents' location declares which answers fit.
	var agent := _first_agent(engine)
	var topics: Array = engine.topics_of(String(engine.location))
	h.check(topics.size() >= 4, "a location declares several on-topic answers")
	for index: Variant in topics:
		h.check(engine.is_on_topic(String(engine.location), int(index)), "topic %s fits the location" % index)
	h.check(engine.topics_of(String(engine.private_state(agent).get("location", ""))) == topics, "agents share the location's topics")


# ------------------------------------------------------------------- endings

func _endings(h: TestHarness) -> void:
	# 1. An agent accuses the spy: the agents win, the accuser is credited.
	var caught := _engine(h)
	var accuser := _first_agent(caught)
	h.check(not caught.apply_action_by_key(accuser, _accuse_key(caught, accuser, caught.spy)).ok if accuser != caught.decision_player() else true,
		"only the player on the spot may accuse")
	caught.turn_pos = caught.turn_order.find(accuser)
	_apply(caught, _action_for(caught, "accuse", {"target": caught.spy}))
	h.check(caught.finished, "accusing the spy ends the match")
	h.equal(String(caught.result.get("reason_key", "")), "game.spyfall.reason_spy_caught", "the reason is the catch")
	h.equal(caught.winner_index(), accuser, "the accuser is credited")
	h.equal(int(caught.result.get("_spy", -1)), caught.spy, "the result reveals the spy")
	h.equal(String(caught.result.get("_location", "")), String(caught.location), "the result reveals the location")
	h.check(caught.public_state().has("_reveal"), "the finished table shows the reveal")

	# 2. A wrong accusation clears the target and continues.
	var miss := _engine(h)
	var innocent := _first_agent(miss)
	var wrong_accuser := _innocent(miss, innocent)
	miss.turn_pos = miss.turn_order.find(wrong_accuser)
	_apply(miss, _action_for(miss, "accuse", {"target": innocent}))
	h.check(not miss.finished, "a miss does not end the match")
	h.check(miss.cleared.has(innocent), "the target is publicly cleared")
	for action: Dictionary in miss.legal_actions(miss.decision_player()):
		h.check(not (String(action.get("type", "")) == "accuse" and int(action.get("target", -1)) == innocent),
			"a cleared player is not accused again")
	# …and the accuser may not accuse twice.
	miss.turn_pos = miss.turn_order.find(wrong_accuser)
	if miss.decision_player() == wrong_accuser:
		for action: Dictionary in miss.legal_actions(wrong_accuser):
			h.check(String(action.get("type", "")) != "accuse", "an accuser spends their one accusation")

	# 3. The spy names the true location: the spy wins.
	var guessed := _engine(h)
	guessed.turn_pos = guessed.turn_order.find(guessed.spy)
	_apply(guessed, _action_for(guessed, "name_location", {"location": guessed.location}))
	h.check(guessed.finished, "naming the location ends the match")
	h.equal(String(guessed.result.get("reason_key", "")), "game.spyfall.reason_spy_guessed", "the reason is a correct naming")
	h.equal(guessed.winner_index(), guessed.spy, "the spy wins")

	# 4. The spy names a wrong location: the agents win.
	var wrong := _engine(h)
	wrong.turn_pos = wrong.turn_order.find(wrong.spy)
	var other_location := _other_location(wrong)
	_apply(wrong, _action_for(wrong, "name_location", {"location": other_location}))
	h.check(wrong.finished, "a wrong naming ends the match too")
	h.equal(String(wrong.result.get("reason_key", "")), "game.spyfall.reason_spy_misguessed", "the reason is a misguess")
	h.check(wrong.winner_index() != wrong.spy, "the spy loses")

	# 5. Running out of questions: the spy survives.
	var survivor := _engine(h, 3, 7)
	survivor.ask_count = survivor.asks_limit - 1
	_apply(survivor, _first_of_type(survivor, "ask"))
	_apply(survivor, _first_of_type(survivor, "answer"))
	h.check(survivor.finished, "the question limit ends the match")
	h.equal(String(survivor.result.get("reason_key", "")), "game.spyfall.reason_spy_survived", "the reason is survival")
	h.equal(survivor.winner_index(), survivor.spy, "the spy wins by surviving")

	# 6. Every agent spends their accusation: the spy survives as well.
	var spent := _engine(h, 3, 3)
	var accusers: Array[int] = []
	for seat: int in range(spent.player_count()):
		if seat != spent.spy:
			accusers.append(seat)
	spent.turn_pos = spent.turn_order.find(accusers[0])
	_apply(spent, _action_for(spent, "accuse", {"target": accusers[1]}))
	h.check(not spent.finished, "one lead left keeps the match alive")
	spent.turn_pos = spent.turn_order.find(accusers[1])
	_apply(spent, _action_for(spent, "accuse", {"target": accusers[0]}))
	h.check(spent.finished, "the last accusation ends the match")
	h.equal(String(spent.result.get("reason_key", "")), "game.spyfall.reason_spy_survived", "no leads left means survival")


func _role_quirks(h: TestHarness) -> void:
	var engine := _engine(h)
	var agent := _first_agent(engine)
	engine.turn_pos = engine.turn_order.find(agent)
	var before: int = engine.history.size()
	_apply(engine, _action_for(engine, "name_location", {"location": engine.location}))
	h.check(not engine.finished, "an agent naming the location is ignored")
	h.equal(engine.history.size(), before, "…and records nothing")
	h.check(engine.decision_player() >= 0, "the table keeps playing")


# --------------------------------------------------------------- rejections

func _illegal_actions(h: TestHarness) -> void:
	var engine := _engine(h)
	var waiting := 1
	var stale := engine.legal_actions(engine.decision_player())[0]
	var out_of_turn := engine.apply_action_by_key(waiting, String(stale.get("key", "")))
	h.check(not bool(out_of_turn.get("ok", false)), "acting out of turn is rejected")
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "the rejection says whose turn it is")
	var bogus := engine.apply_action_by_key(engine.decision_player(), "answer=99|type=answer")
	h.check(not bool(bogus.get("ok", false)), "an unknown action is rejected")
	h.equal(String(bogus.get("error_key", "")), "game.common.illegal_action", "the rejection names the action")
	var late := engine.apply_action({"type": "answer", "answer": 0, "key": "stale-answer"})
	h.check(not bool(late.get("ok", false)), "an answer before a question is rejected")
	h.equal(String(late.get("error_key", "")), "game.spyfall.error.illegal_action", "with the game's own error key")
	h.check(Loc.has_key("game.spyfall.error.illegal_action"), "the rejection key is translated")


# --------------------------------------------------------------- 3..8 seats

func _seat_flexibility(h: TestHarness) -> void:
	var outcomes: Dictionary = {}
	for count: int in range(3, 9):
		var engine := _engine(h, count, 3000 + count)
		h.equal(engine.player_count(), count, "%d seats are supported" % count)
		h.check(engine.legal_actions(engine.decision_player()).size() > 0, "%d seats have a legal opening" % count)
		h.check(engine.spy >= 0 and engine.spy < count, "the spy is inside a %d-seat table" % count)
		var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
		h.check(engine.finished, "%d-seat bot match finishes (%d steps)" % [count, steps])
		var reason := String(engine.result.get("reason_key", ""))
		h.check(not reason.is_empty(), "%d-seat match explains its ending" % count)
		outcomes[reason] = int(outcomes.get(reason, 0)) + 1
	h.check(true, "bot endings observed: %s" % str(outcomes))


# ------------------------------------------------ determinism and snapshots

func _determinism(h: TestHarness) -> void:
	var first := _engine(h)
	var second := _engine(h)
	for step: int in range(24):
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the spyfall bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same actions give the same state")


func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, engine, "spyfall questioning")
	_apply(engine, _first_of_type(engine, "ask"))
	EngineHarness.check_snapshot_round_trip(h, engine, "spyfall answering")
	_apply(engine, _first_of_type(engine, "answer"))
	EngineHarness.check_snapshot_round_trip(h, engine, "spyfall after an exchange")
	var copy := EngineHarness.create("spyfall", 5, 4)
	copy.restore_state(engine.public_state())
	h.equal(copy.decision_player(), engine.decision_player(), "the restored copy waits for the same seat")
	h.equal(copy.phase(), engine.phase(), "the restored copy is in the same phase")
	h.equal(copy.legal_actions(copy.decision_player()).size(), engine.legal_actions(engine.decision_player()).size(),
		"the restored copy offers the same actions")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h)
	EngineHarness.check_privacy(h, engine, _leaks, "spyfall")
	for player: int in range(engine.player_count()):
		var private := engine.private_state(player)
		if bool(private.get("is_spy", false)):
			h.check(not private.has("location"), "the spy's card never states the location")
		else:
			h.check(not private.has("candidates"), "only the spy gets a candidate list")
			h.equal(String(private.get("location", "")), String(engine.location), "agents know the location")


func _leaks(theirs: Dictionary, mine: Dictionary) -> Array:
	var out: Array = []
	if bool(theirs.get("is_spy", false)) and bool(mine.get("is_spy", false)):
		out.append("spy identity")
	if mine.has("candidates") and not bool(mine.get("is_spy", false)):
		out.append("candidates")
	return out


# ------------------------------------------------------------------ strings

func _strings(h: TestHarness) -> void:
	for location: String in SpyfallEngine.LOCATIONS:
		h.check(Loc.has_key("game.spyfall.location.%s" % location), "location %s is translated" % location)
	for role: String in SpyfallEngine.ROLES:
		h.check(Loc.has_key("game.spyfall.role.%s" % role), "role %s is translated" % role)
	for key: String in SpyfallEngine.QUESTIONS:
		h.check(Loc.has_key(key), "question card %s is translated" % key)
	for key: String in SpyfallEngine.ANSWERS:
		h.check(Loc.has_key(key), "answer card %s is translated" % key)
		h.no_raw_key(Loc.t(key), "answer card %s renders as text" % key)
	for reason: String in ["game.spyfall.reason_spy_caught", "game.spyfall.reason_spy_survived",
			"game.spyfall.reason_spy_guessed", "game.spyfall.reason_spy_misguessed"]:
		h.check(Loc.has_key(reason), "%s is translated" % reason)
		h.no_raw_key(Loc.t(reason), "%s renders as text" % reason)


func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 6)
	var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "the bot match finishes")
	h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the reason is translated")
	h.greater(float(engine.move_log.size()), 0.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
	h.check(not Loc.missing_keys().has("game.spyfall.log_ask"), "the ask log uses a real string")


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


func _accuse_key(engine: GameEngine, actor: int, target: int) -> String:
	for action: Dictionary in engine.legal_actions(actor):
		if String(action.get("type", "")) == "accuse" and int(action.get("target", -1)) == target:
			return String(action.get("key", ""))
	return "missing:accuse"


func _first_agent(engine: GameEngine) -> int:
	for player: int in range(engine.player_count()):
		if player != engine.spy:
			return player
	return 0


func _innocent(engine: GameEngine, exclude: int) -> int:
	for player: int in range(engine.player_count()):
		if player != engine.spy and player != exclude:
			return player
	return 0


func _other_location(engine: GameEngine) -> String:
	for location: String in SpyfallEngine.LOCATIONS:
		if location != String(engine.location):
			return location
	return ""
