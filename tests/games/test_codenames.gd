extends RefCounted
## Codenames rules suite: dealing, clues, guessing, the assassin, the turn limit,
## team flexibility, hidden key cards, snapshots and bot playouts.
##
## Several rule checks craft a position by writing the engine's key card, which is
## the same technique the chess suite uses with FEN: it isolates one rule without
## replaying a whole match.

const MAX_BOT_STEPS: int = 4000


func suite_name() -> String:
	return "codenames rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_clue_and_guesses(h)
	_assassin(h)
	_agents_complete(h)
	_turn_limit(h)
	_illegal_actions(h)
	_team_flexibility(h)
	_determinism(h)
	_snapshots(h)
	_privacy(h)
	_bot_match(h)


func _engine(h: TestHarness, count: int = 4, seed_value: int = 20251019) -> GameEngine:
	var engine := EngineHarness.create("codenames", count, seed_value)
	h.check(engine != null, "codenames engine must be creatable")
	return engine


# ------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.phase(), "clue", "a match opens in the clue phase")
	h.equal(engine.decision_player(), 0, "the red spymaster (seat 0) gives the first clue")
	h.equal(engine.grid.size(), CodenamesEngine.CELLS, "the grid holds 25 words")
	var seen: Dictionary = {}
	for word: String in engine.grid:
		h.check(not seen.has(word), "grid words are distinct: %s" % word)
		h.check(CodenamesEngine.WORD_POOL.has(word), "%s comes from the word pool" % word)
		seen[word] = true
	var counts := {"red": 0, "blue": 0, "neutral": 0, "assassin": 0}
	for label: String in engine.key_card:
		counts[label] = int(counts.get(label, 0)) + 1
	h.equal(counts["red"], 9, "the starting team has nine agents")
	h.equal(counts["blue"], 8, "the other team has eight")
	h.equal(counts["neutral"], 7, "seven bystanders")
	h.equal(counts["assassin"], 1, "one assassin")
	h.equal(engine.legal_actions(0).size(), 72, "every cue word is offered with three numbers")
	EngineHarness.check_legal_action_shape(h, engine, "codenames opening")
	h.check(engine.private_state(0).has("key_card"), "the red spymaster sees the key card")
	h.check(engine.private_state(1).has("key_card"), "the blue spymaster sees the same key card")
	h.equal(engine.private_state(1)["key_card"], engine.private_state(0)["key_card"], "both spymasters share one key card")
	h.check(not engine.private_state(2).has("key_card"), "an operative never sees the key card")
	h.equal(String(engine.private_state(2).get("role", "")), "operative", "the second red seat is an operative")
	h.check(not engine.public_state().has("key_card"), "the key card is not public")
	h.check(not str(engine.public_state()).contains("assassin"), "the public snapshot never names the assassin")
	# Determinism: same seed, same draw.
	var twin := _engine(h)
	h.equal(twin.grid, engine.grid, "the same seed draws the same grid")
	h.equal(twin.key_card, engine.key_card, "…and the same key card")
	var other := _engine(h, 4, 777)
	h.check(other.grid != engine.grid or other.key_card != engine.key_card, "a different seed draws a different position")


# ------------------------------------------------------- clues and guessing

func _clue_and_guesses(h: TestHarness) -> void:
	var engine := _engine(h)
	var clue := _first_of_type(engine, "clue")
	h.check(not clue.is_empty(), "a clue is legal in the clue phase")
	var outcome := _apply(engine, clue)
	h.check(bool(outcome.get("ok", false)), "the clue applies")
	h.equal(engine.phase(), "guess", "clues move the table to guessing")
	h.equal(engine.guesses_left, int(clue.get("number", 1)) + 1, "a clue allows number + 1 guesses")
	h.equal(engine.decision_player(), 2, "the first operative of the red team guesses")
	h.check(engine.legal_actions(2).size() > 25, "every unrevealed card can be guessed plus a stop")

	var own := _cell_with_key(engine, "red")
	h.check(own >= 0, "red has an unrevealed agent")
	var before: int = int(engine.remaining[0])
	_apply(engine, _guess_action(engine, own))
	h.equal(engine.remaining[0], before - 1, "guessing an own agent reduces the team's count")
	h.equal(engine.phase(), "guess", "a correct guess keeps the turn")
	h.equal(engine.decision_player(), 2, "the same operative keeps guessing")

	# A bystander ends the turn and hands it to the other team.
	var neutral := _cell_with_key(engine, "neutral")
	h.check(neutral >= 0, "a bystander is still hidden")
	_apply(engine, _guess_action(engine, neutral))
	h.equal(engine.phase(), "clue", "a bystander ends the turn")
	h.equal(engine.active_team, CodenamesEngine.BLUE, "the other team is next")
	h.equal(engine.decision_player(), 1, "the blue spymaster gives the next clue")

	# Revealing an opponent agent counts for that opponent and ends the turn.
	var second := _engine(h)
	_apply(second, _first_of_type(second, "clue"))
	var blue_cell := _cell_with_key(second, "blue")
	var blue_before: int = int(second.remaining[1])
	_apply(second, _guess_action(second, blue_cell))
	h.equal(second.remaining[1], blue_before - 1, "revealing a blue agent counts for blue")
	h.equal(second.active_team, CodenamesEngine.BLUE, "and ends the red turn")

	# Stopping ends the turn without revealing anything.
	var third := _engine(h)
	_apply(third, _first_of_type(third, "clue"))
	var stop := _first_of_type(third, "stop")
	h.check(not stop.is_empty(), "the operatives may stop guessing")
	_apply(third, stop)
	h.equal(third.phase(), "clue", "stopping ends the turn")
	h.equal(third.active_team, CodenamesEngine.BLUE, "and passes it to the other team")


# ------------------------------------------------------------------ endings

func _assassin(h: TestHarness) -> void:
	var engine := _engine(h)
	_apply(engine, _first_of_type(engine, "clue"))
	var cell := 0
	engine.key_card[cell] = CodenamesEngine.ASSASSIN
	engine.revealed[cell] = 0
	h.check(engine.finished == false, "the match is running when the assassin appears")
	_apply(engine, _guess_action(engine, cell))
	h.check(engine.finished, "revealing the assassin ends the match immediately")
	h.equal(String(engine.result.get("reason_key", "")), "game.codenames.reason_assassin", "the reason is the assassin")
	h.equal(engine.winner_index(), 1, "the other team wins")
	h.equal(engine.phase(), "finished", "the finished phase is reported")
	h.check(engine.legal_actions(1).is_empty(), "nobody acts after the assassin")


func _agents_complete(h: TestHarness) -> void:
	var engine := _engine(h)
	_apply(engine, _first_of_type(engine, "clue"))
	var own := _cell_with_key(engine, "red")
	engine.remaining[CodenamesEngine.RED] = 1
	_apply(engine, _guess_action(engine, own))
	h.check(engine.finished, "revealing the last agent ends the match")
	h.equal(String(engine.result.get("reason_key", "")), "game.codenames.reason_all_agents", "the reason is a completed team")
	h.equal(engine.winner_index(), 0, "red's spymaster is credited with the win")
	h.equal(int(engine.result.get("_winner_team", -1)), CodenamesEngine.RED, "the winning team is recorded")

	# Handing the opponent their last agent wins the match for them.
	var gift := _engine(h)
	_apply(gift, _first_of_type(gift, "clue"))
	var blue_cell := _cell_with_key(gift, "blue")
	gift.remaining[CodenamesEngine.BLUE] = 1
	_apply(gift, _guess_action(gift, blue_cell))
	h.check(gift.finished, "revealing the opponent's last agent ends the match")
	h.equal(int(gift.result.get("_winner_team", -1)), CodenamesEngine.BLUE, "the opponent wins")


func _turn_limit(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.turn = CodenamesEngine.MAX_TURNS - 1
	_apply(engine, _first_of_type(engine, "clue"))
	_apply(engine, _first_of_type(engine, "stop"))
	h.check(engine.finished, "the clue limit ends a match that drags on")
	h.equal(String(engine.result.get("reason_key", "")), "game.codenames.reason_turn_limit", "the reason is the turn limit")
	h.equal(engine.winner_index(), -1, "nothing revealed is a draw")

	var leading := _engine(h)
	leading.remaining[CodenamesEngine.RED] = 7
	leading.turn = CodenamesEngine.MAX_TURNS - 1
	_apply(leading, _first_of_type(leading, "clue"))
	_apply(leading, _first_of_type(leading, "stop"))
	h.check(leading.finished, "the limit also ends a match with a leader")
	h.equal(leading.winner_index(), 0, "the team with more revealed agents wins at the limit")


# --------------------------------------------------------------- rejections

func _illegal_actions(h: TestHarness) -> void:
	var engine := _engine(h)
	var clue_key := String(_first_of_type(engine, "clue").get("key", ""))
	var waiting := 1
	var out_of_turn := engine.apply_action_by_key(waiting, clue_key)
	h.check(not bool(out_of_turn.get("ok", false)), "acting out of turn is rejected")
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "the rejection says whose turn it is")
	var bogus := engine.apply_action_by_key(0, "card=99|type=guess")
	h.check(not bool(bogus.get("ok", false)), "an unknown key is rejected")
	h.equal(String(bogus.get("error_key", "")), "game.common.illegal_action", "the rejection points at the action")
	# A clue is no longer legal once the table is guessing.
	_apply(engine, _first_of_type(engine, "clue"))
	var late := engine.apply_action({"type": "clue", "word": "hot", "number": 1, "key": "stale-clue"})
	h.check(not bool(late.get("ok", false)), "a clue after the clue phase is rejected")
	h.equal(String(late.get("error_key", "")), "game.codenames.error.illegal_action", "with the game's own error key")
	h.check(Loc.has_key("game.codenames.error.illegal_action"), "the rejection key is translated")


# --------------------------------------------------------------- 2..8 seats

func _team_flexibility(h: TestHarness) -> void:
	for count: int in range(2, 9):
		var engine := _engine(h, count, 1000 + count)
		h.equal(engine.player_count(), count, "%d seats are supported" % count)
		h.check(engine.legal_actions(engine.decision_player()).size() > 0, "%d seats have a legal opening" % count)
		var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
		h.check(engine.finished, "%d-seat bot match finishes (%d steps)" % [count, steps])
		h.check(not String(engine.result.get("reason_key", "")).is_empty(), "%d-seat match explains its ending" % count)
	var two := _engine(h, 2)
	for team: int in [0, 1]:
		h.equal(two.team_members(team).size(), 1, "two seats give each team one member")
		h.equal(two.spymaster_of(team), team, "each team's single member is its spymaster")
	h.check(two.legal_actions(two.decision_player()).size() > 0, "two-seat teams can still act")
	EngineHarness.play_out(two, MAX_BOT_STEPS)
	h.check(two.finished, "a two-seat bot match finishes as well")


# ------------------------------------------------ determinism and snapshots

func _determinism(h: TestHarness) -> void:
	var first := _engine(h)
	var second := _engine(h)
	for step: int in range(30):
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the codenames bot always finds an action (%d)" % step)
		var outcome := first.apply_action_by_key(actor, key)
		h.check(bool(outcome.get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same actions give the same state")


func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, engine, "codenames clue phase")
	_apply(engine, _first_of_type(engine, "clue"))
	EngineHarness.check_snapshot_round_trip(h, engine, "codenames guess phase")
	var copy := EngineHarness.create("codenames", 4, 1)
	copy.restore_state(engine.public_state())
	h.equal(copy.decision_player(), engine.decision_player(), "the restored copy waits for the same seat")
	h.equal(copy.phase(), engine.phase(), "the restored copy is in the same phase")
	h.equal(copy.legal_actions(copy.decision_player()).size(), engine.legal_actions(engine.decision_player()).size(),
		"the restored copy offers the same actions")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h)
	_apply(engine, _first_of_type(engine, "clue"))
	EngineHarness.check_privacy(h, engine, _leaks, "codenames")
	for player: int in range(engine.player_count()):
		var private := engine.private_state(player)
		if String(private.get("role", "")) != "spymaster":
			h.check(not private.has("key_card"), "no key card leaks to seat %d" % player)
	var fresh := _engine(h)
	h.check(not fresh.public_state().has("key_card"), "the public snapshot has no key-card field")
	h.check(not str(fresh.public_state()).contains("assassin"), "the public snapshot never names the assassin")


func _leaks(theirs: Dictionary, mine: Dictionary) -> Array:
	var out: Array = []
	if mine.has("key_card") and String(mine.get("role", "")) != "spymaster":
		out.append("key_card")
	return out


func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	var steps := EngineHarness.play_out(engine, MAX_BOT_STEPS)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "the bot match finishes")
	h.check(not String(engine.result.get("reason_key", "")).is_empty(), "the finish has a reason")
	h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the reason is translated")
	h.greater(float(engine.move_log.size()), 0.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
	h.check(not Loc.missing_keys().has("game.codenames.log_clue"), "the clue log uses a real string")


# ------------------------------------------------------------------ helpers

func _apply(engine: GameEngine, action: Dictionary) -> Dictionary:
	return engine.apply_action_by_key(engine.decision_player(), String(action.get("key", "")))


func _first_of_type(engine: GameEngine, action_type: String) -> Dictionary:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == action_type:
			return action
	return {}


func _guess_action(engine: GameEngine, cell: int) -> Dictionary:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "guess" and int(action.get("card", -1)) == cell:
			return action
	return {}


func _cell_with_key(engine: GameEngine, label: String) -> int:
	for cell: int in range(CodenamesEngine.CELLS):
		if engine.revealed[cell] == 0 and String(engine.key_card[cell]) == label:
			return cell
	return -1
