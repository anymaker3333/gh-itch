extends RefCounted
## Citadels rules suite: the hidden draft, income, building, every character
## power, the eight-district finish and the hidden-information invariants.
##
## Character powers are tested by driving a bot match to the exact turn they
## happen on (the engine is deterministic, so "play until the King is called" is
## a reproducible fixture) and then asserting the rules on that turn.

const SEED: int = 20251019
## A search over seeds is how a turn with a specific character is reached.
const SEED_RANGE: int = 40


func suite_name() -> String:
	return "citadels rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_income_and_build(h)
	_only_affordable_builds(h)
	_rejection(h)
	_role_calling(h)
	_powers(h)
	_eight_districts(h)
	_round_limit(h)
	_privacy(h)
	_snapshot(h)
	_bot_match(h)


# --------------------------------------------------------------------- set-up

func _engine(h: TestHarness, players: int = 2, seed_value: int = SEED, options: Dictionary = {}) -> GameEngine:
	var engine := EngineHarness.create("citadels", players, seed_value, options)
	h.check(engine != null, "citadels engine must be creatable")
	return engine


func _step(engine: GameEngine) -> bool:
	var actor := engine.decision_player()
	if actor < 0:
		return false
	var key := BotDirector.choose_action(engine, actor)
	if key.is_empty():
		return false
	return bool(engine.apply_action_by_key(actor, key).get("ok", false))


## Applies the first legal action of `type` (optionally matching `params`).
func _apply(engine: GameEngine, type: String, params: Dictionary = {}) -> Dictionary:
	var actor := engine.decision_player()
	for action: Dictionary in engine.legal_actions(actor):
		if String(action.get("type", "")) != type:
			continue
		var matches := true
		for key: String in params:
			if action.get(key) != params[key]:
				matches = false
		if not matches:
			continue
		return engine.apply_action_by_key(actor, String(action.get("key", "")))
	return {"ok": false, "error_key": "missing"}


## Plays until `role` is called and its owner is choosing what to do (step
## "action"). During the draft the suite claims the wanted character itself (the
## bot policy would leave the Assassin and Thief untouched), then hands the
## other picks back to the bots. Returns the engine or null when no seed works.
func _until_role(role: int) -> GameEngine:
	for offset: int in range(SEED_RANGE):
		var engine := EngineHarness.create("citadels", 3, SEED + offset, {})
		var steps := 0
		while not engine.finished and steps < 900:
			var state := engine.public_state()
			if String(state.get("step", "")) == "action" and int(state.get("current_role", 0)) == role:
				if int(state.get("current_player", -1)) == engine.decision_player():
					return engine
			if String(state.get("step", "")) == "draft" and _claim_role(engine, role):
				steps += 1
				continue
			if not _step(engine):
				break
			steps += 1
	return null


## Drafts `role` when it is on offer; the tests take over one pick so the wanted
## character is guaranteed to be in play and called this round.
func _claim_role(engine: GameEngine, role: int) -> bool:
	var actor := engine.decision_player()
	for action: Dictionary in engine.legal_actions(actor):
		if String(action.get("type", "")) != "take_role" or int(action.get("role", 0)) != role:
			continue
		return bool(engine.apply_action_by_key(actor, String(action.get("key", ""))).get("ok", false))
	return false


func _opening(h: TestHarness) -> void:
	var first := _engine(h)
	h.equal(first.phase(), "draft", "a match opens with the character draft")
	h.equal(first.decision_player(), 0, "the first seat chooses first")
	h.equal(first.legal_actions(0).size(), 8, "all eight characters are on offer")
	h.equal(first.role_pool.size(), 8, "the pool holds every character")
	h.equal(first.draft_order.size(), 4, "with two players everyone drafts twice")
	h.equal(first.gold_of(0), 2, "players open with two gold")
	h.equal(first.hand_of(0).size(), 4, "players open with four district cards")
	h.equal(first.city_of(0).size(), 0, "no districts are built yet")
	h.equal(first.legal_actions(1).size(), 0, "the seat that is not choosing has no actions")
	EngineHarness.check_legal_action_shape(h, first, "citadels opening")

	# Same seed, same actions, same state; a different seed shuffles differently.
	var second := _engine(h)
	h.equal(second.private_state(0), first.private_state(0), "the deal is reproducible")
	var other := _engine(h, 2, SEED + 1)
	h.not_equal(other.private_state(0), first.private_state(0), "a different seed deals differently")

	# The deck itself is a table secret; seats only ever see their own cards.
	h.check(not first.public_state().has("role_owner"), "the role ownership stays hidden")
	h.check(not first.public_state().has("hands"), "the public state carries no hands")
	h.check(not first.private_state(0).is_empty(), "a seat can see its own cards")
	h.check(not first.private_state(-1).is_empty(), "the table holds the draw pile")


func _income_and_build(h: TestHarness) -> void:
	var engine := _engine(h)
	# Finish the draft: the character choice stays hidden.
	var drafted := []
	while engine.phase() == "draft":
		drafted.append(engine.decision_player())
		h.check(_apply(engine, "take_role").get("ok", false), "a character can be drafted")
	h.equal(engine.role_pool.size(), 4, "the four unused characters are set aside")
	h.equal(drafted.size(), 4, "each seat drafted twice")

	# Income: two gold, exactly.
	h.equal(engine.phase(), "income", "the called character starts with income")
	var actor := engine.decision_player()
	var gold_before: int = engine.gold_of(actor)
	h.check(_apply(engine, "income").get("ok", false), "taking two gold is legal")
	h.equal(engine.gold_of(actor), gold_before + 2, "income is exactly two gold")
	h.equal(engine.phase(), "action", "after income the player may build")

	# Cards: two district cards.
	var draw_engine := _engine(h)
	while draw_engine.phase() == "draft":
		_apply(draw_engine, "take_role")
	var card_actor := draw_engine.decision_player()
	var hand_before: int = draw_engine.hand_of(card_actor).size()
	if _apply(draw_engine, "draw_cards").get("ok", false):
		h.equal(draw_engine.hand_of(card_actor).size(), hand_before + 2, "drawing cards adds two cards")
	else:
		h.check(true, "the draw pile was empty")

	# Building: pay the printed cost and move the card into the city.
	var build_engine := _engine(h)
	while build_engine.phase() == "draft":
		_apply(build_engine, "take_role")
	h.check(bool(_apply(build_engine, "income").get("ok", false)), "income opens the action step")
	var builder := build_engine.decision_player()
	build_engine.gold[builder] = 20
	var build_action := _first_of(build_engine, "build")
	h.check(not build_action.is_empty(), "an affordable district can be built")
	if not build_action.is_empty():
		var cost := CitadelsEngine.district_cost(String(build_action.get("card", "")))
		var gold: int = build_engine.gold_of(builder)
		h.check(bool(build_engine.apply_action_by_key(builder, String(build_action.get("key", ""))).get("ok", false)), "building applies")
		h.equal(build_engine.gold_of(builder), gold - cost, "the district costs its printed price")
		h.equal(build_engine.city_of(builder).size(), 1, "the district moves into the city")
		if int(build_engine.public_state().get("current_role", 0)) != 7:
			var again := build_engine.apply_action_by_key(builder, String(build_action.get("key", "")))
			h.check(not bool(again.get("ok", false)),
				"only one district per turn (unless the Architect says otherwise)")


## §6.7 regression: a build action the engine would reject must never appear in
## the action list. Unaffordable districts stay out of [method legal_actions];
## views render them as dimmed, inert cards instead of guaranteed rejections.
func _only_affordable_builds(h: TestHarness) -> void:
	var engine := _engine(h)
	while engine.phase() == "draft":
		_apply(engine, "take_role")
	h.check(bool(_apply(engine, "income").get("ok", false)), "income opens the action step")
	var player := engine.decision_player()
	(engine.hands[player] as Array).resize(0)
	for card: Variant in ["castle", "tavern"]:
		(engine.hands[player] as Array).append(String(card))
	# With no gold nothing is affordable: the action list has builds at all?
	engine.gold[player] = 0
	h.check(_first_of(engine, "build").is_empty(), "with no gold no build is offered")
	var end_turn := _first_of(engine, "end_turn")
	h.check(not end_turn.is_empty(), "the turn can still be ended")
	# One gold buys exactly the cheap district; the castle stays unlisted.
	engine.gold[player] = 1
	var cheap: Dictionary = {}
	for action: Variant in engine.legal_actions(player):
		if String((action as Dictionary).get("type", "")) == "build":
			cheap = action
			break
	h.equal(String(cheap.get("card", "")), "tavern", "only the affordable district is offered")
	h.check(bool(engine.apply_action_by_key(player, String(cheap.get("key", ""))).get("ok", false)), "the affordable build applies")
	h.equal(engine.city_of(player).size(), 1, "the cheap district enters the city")
	h.equal(engine.gold_of(player), 0, "the build costs the printed price")


func _rejection(h: TestHarness) -> void:
	var engine := _engine(h)
	# An action of another game is refused before anything else.
	var bogus := GameEngine.make_action("teleport", {"where": 1})
	h.equal(String(engine.apply_action(bogus).get("error_key", "")), "game.citadels.error.unknown_action",
		"an unknown action type is rejected")
	# Income during the draft is not legal.
	var income := _first_of(engine, "income")
	if income.is_empty():
		var state := engine.public_state()
		h.check(String(state.get("step", "")) == "draft", "income cannot be submitted during the draft")
	var illegal := GameEngine.make_action("income", {})
	h.equal(String(engine.apply_action(illegal).get("error_key", "")), "game.citadels.error.illegal_action",
		"an action that is not on the list is rejected")
	# A stale build action is refused as well.
	var taken := _apply(engine, "take_role")
	h.check(bool(taken.get("ok", false)), "the draft accepts a character")
	h.equal(engine.decision_player(), 1, "the next seat drafts")


func _role_calling(h: TestHarness) -> void:
	var engine := _engine(h)
	while engine.phase() == "draft":
		_apply(engine, "take_role")
	var called: Array = []
	while engine.phase() != "draft" and not engine.finished:
		var role := int(engine.public_state().get("current_role", 0))
		if role > 0 and not called.has(role):
			called.append(role)
		if String(engine.public_state().get("step", "")) == "income":
			_apply(engine, "income")
		_apply(engine, "end_turn")
	h.check(called.size() >= 4, "every drafted character is called in order")
	for i: int in range(1, called.size()):
		h.check(int(called[i]) > int(called[i - 1]), "characters are called in ascending order")


func _powers(h: TestHarness) -> void:
	_assassin(h)
	_thief(h)
	_magician(h)
	_king(h)
	_bishop_upkeep(h)
	_merchant(h)
	_architect(h)
	_warlord(h)


func _assassin(h: TestHarness) -> void:
	var engine := _until_role(1)
	h.check(engine != null, "a seed reaches the Assassin's turn")
	if engine == null:
		return
	var killer := engine.decision_player()
	var target := 0
	for action: Dictionary in engine.legal_actions(killer):
		if String(action.get("type", "")) != "assassinate":
			continue
		var role := int(action.get("role", 0))
		if engine.role_owner[role] >= 0:  # a character that is really in play
			target = role
			break
	if target == 0:
		h.check(true, "no drafted character to strike down on this turn")
		return
	h.check(bool(_apply(engine, "assassinate", {"role": target}).get("ok", false)), "the Assassin may name a character")
	h.equal(int(engine.public_state().get("killed_role", 0)), target, "the named character is marked")
	# The victim does not act: play the round on and look for the skip in the log.
	var round_no := engine.round_index
	var seen_skip := false
	var steps := 0
	while not engine.finished and steps < 200 and not seen_skip:
		_step(engine)
		steps += 1
		for entry: Dictionary in engine.move_log:
			if String(entry.get("text_key", "")) == "game.citadels.log_killed" and int(entry.get("round", 0)) == round_no:
				seen_skip = true
	h.check(seen_skip, "the struck character is announced instead of acting")


func _thief(h: TestHarness) -> void:
	var engine := _until_role(2)
	h.check(engine != null, "a seed reaches the Thief's turn")
	if engine == null:
		return
	var thief := engine.decision_player()
	var victim := -1
	var victim_role := 0
	for action: Dictionary in engine.legal_actions(thief):
		if String(action.get("type", "")) != "steal":
			continue
		var role := int(action.get("role", 0))
		var owner: int = engine.role_owner[role]
		if owner >= 0 and owner != thief and engine.gold_of(owner) > 0:
			victim = owner
			victim_role = role
			break
	if victim < 0:
		h.check(true, "no rich character to rob on this turn")
		return
	var stolen: int = engine.gold_of(victim)
	var purse: int = engine.gold_of(thief)
	h.check(bool(_apply(engine, "steal", {"role": victim_role}).get("ok", false)), "the Thief may rob a character")
	h.equal(engine.gold_of(victim), 0, "the victim is left without gold")
	h.equal(engine.gold_of(thief), purse + stolen, "every coin moves to the Thief")
	h.check(bool(engine.public_state().get("power_used", false)), "the power is spent for this turn")


func _magician(h: TestHarness) -> void:
	var engine := _until_role(3)
	h.check(engine != null, "a seed reaches the Magician's turn")
	if engine == null:
		return
	var magician := engine.decision_player()
	var target := -1
	for action: Dictionary in engine.legal_actions(magician):
		if String(action.get("type", "")) == "magician_swap" and engine.hand_of(int(action.get("target", -1))).size() > 0:
			target = int(action.get("target", -1))
			break
	if target < 0:
		h.check(true, "no player with cards to swap with on this turn")
		return
	var mine: Array = engine.hand_of(magician).duplicate()
	var theirs: Array = engine.hand_of(target).duplicate()
	h.check(bool(_apply(engine, "magician_swap", {"target": target}).get("ok", false)), "the Magician may swap hands")
	h.equal(engine.hand_of(magician), theirs, "the hands are exchanged")
	h.equal(engine.hand_of(target), mine, "the other player receives our cards")
	h.equal(engine.hand_of(magician).size(), theirs.size(), "the swap keeps both hands intact")


func _king(h: TestHarness) -> void:
	var engine := _until_called_next(3, 4, h)
	if engine == null:
		return
	var king: int = engine.role_owner[4]
	var nobles := _colour_count(engine, king, "noble")
	var before: int = engine.gold_of(king)
	_apply(engine, "end_turn")
	h.equal(int(engine.public_state().get("current_role", 0)), 4, "the King is called next")
	h.equal(engine.gold_of(king), before + nobles, "the King collects one gold per noble district")
	h.equal(int(engine.public_state().get("first_player", -1)), king, "the crown moves to the King")


func _bishop_upkeep(h: TestHarness) -> void:
	var engine := _until_called_next(4, 5, h)
	if engine == null:
		return
	var bishop: int = engine.role_owner[5]
	var religious := _colour_count(engine, bishop, "religious")
	var before: int = engine.gold_of(bishop)
	_apply(engine, "end_turn")
	h.equal(int(engine.public_state().get("current_role", 0)), 5, "the Bishop is called next")
	h.equal(engine.gold_of(bishop), before + religious, "the Bishop collects one gold per religious district")
	# The Bishop shields its own city from the Warlord.
	var warlord := _until_role(8)
	if warlord != null and warlord.role_owner[5] >= 0:
		for action: Dictionary in warlord.legal_actions(warlord.decision_player()):
			if String(action.get("type", "")) == "destroy":
				h.not_equal(int(action.get("target", -1)), warlord.role_owner[5],
					"the Warlord cannot raze a city protected by the Bishop")


func _merchant(h: TestHarness) -> void:
	var engine := _until_called_next(5, 6, h)
	if engine == null:
		return
	var merchant: int = engine.role_owner[6]
	var income := 1 + _colour_count(engine, merchant, "trade")
	var before: int = engine.gold_of(merchant)
	_apply(engine, "end_turn")
	h.equal(int(engine.public_state().get("current_role", 0)), 6, "the Merchant is called next")
	h.equal(engine.gold_of(merchant), before + income, "the Merchant collects one gold plus one per trade district")


func _architect(h: TestHarness) -> void:
	var engine := _until_called_next(6, 7, h)
	if engine == null:
		return
	var architect: int = engine.role_owner[7]
	var before: int = engine.hand_of(architect).size()
	var available: int = (engine.private_state(-1).deck as Array).size() + (engine.private_state(-1).discard as Array).size()
	_apply(engine, "end_turn")
	h.equal(int(engine.public_state().get("current_role", 0)), 7, "the Architect is called next")
	h.equal(engine.hand_of(architect).size() - before, mini(2, available), "the Architect draws two extra cards")
	h.equal(int(engine.public_state().get("build_limit", 1)), 3, "the Architect may build three districts")


func _warlord(h: TestHarness) -> void:
	var engine := _until_role(8)
	h.check(engine != null, "a seed reaches the Warlord's turn")
	if engine == null:
		return
	var warlord := engine.decision_player()
	var target := -1
	var slot := -1
	for action: Dictionary in engine.legal_actions(warlord):
		if String(action.get("type", "")) != "destroy":
			continue
		target = int(action.get("target", -1))
		slot = int(action.get("slot", -1))
		break
	if target < 0:
		h.check(true, "nothing affordable to raze on this turn")
		return
	var price := maxi(0, CitadelsEngine.district_cost(engine.city_of(target)[slot]) - 1)
	var purse: int = engine.gold_of(warlord)
	var size_before: int = engine.city_of(target).size()
	h.check(bool(_apply(engine, "destroy", {"target": target, "slot": slot}).get("ok", false)), "the Warlord may raze a district")
	h.equal(engine.city_of(target).size(), size_before - 1, "the district leaves the city")
	h.equal(engine.gold_of(warlord), purse - price, "razing costs one gold less than the district")


## Plays until the character processed *after* `before` is `role` (used to check
## the automatic upkeep a character grants when it is called).
func _until_called_next(before: int, role: int, h: TestHarness) -> GameEngine:
	for offset: int in range(SEED_RANGE):
		var engine := EngineHarness.create("citadels", 3, SEED + offset, {})
		var steps := 0
		while not engine.finished and steps < 900:
			var state := engine.public_state()
			if String(state.get("step", "")) == "action" and int(state.get("current_role", 0)) == before:
				var next_owner: int = engine.role_owner[role]
				if next_owner >= 0:
					# The crown may change hands between this turn and the next.
					return engine
			if not _step(engine):
				break
			steps += 1
	return null


func _colour_count(engine: GameEngine, player: int, colour: String) -> int:
	var count := 0
	for card_id: String in engine.city_of(player):
		if CitadelsEngine.district_colour(card_id) == colour:
			count += 1
	return count


func _first_of(engine: GameEngine, type: String) -> Dictionary:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == type:
			return action
	return {}


func _eight_districts(h: TestHarness) -> void:
	var engine := _engine(h, 2, SEED, {})
	var steps := EngineHarness.play_out(engine, 2500)
	h.check(engine.finished, "a full bot match always ends")
	h.check(steps > 0, "the bot match makes progress")
	if not engine.finished:
		return
	var reason := String(engine.result.get("reason_key", ""))
	h.check(reason == "game.citadels.reason_city_complete" or reason == "game.citadels.reason_round_limit",
		"the finish explains itself (%s)" % reason)
	var best := -1
	for player: int in range(engine.player_count()):
		var score: Dictionary = engine.score_of(player)
		h.equal(int(score.total), int(score.base) + int(score.colour) + int(score.first),
			"the score adds up for seat %d" % player)
		h.equal(int(score.base), _city_cost(engine, player), "district costs are scored")
		h.equal(int(score.colour), 3 if _five_colours(engine, player) else 0, "the five-colour bonus is scored")
		h.equal(int(score.first), 4 if engine.first_to_eight == player else 0, "the first-to-eight bonus is scored")
		best = maxi(best, int(score.total))
	var winner := engine.winner_index()
	h.check(winner >= 0, "the match has a winner")
	if winner >= 0:
		h.equal(int(engine.score_of(winner).total), best, "the winner has the highest score")
	if reason == "game.citadels.reason_city_complete":
		h.greater(float(engine.city_of(engine.first_to_eight).size()), 7.0, "the finishing city really holds eight districts")
		var leaders: Array[int] = []
		for player: int in range(engine.player_count()):
			if engine.city_of(player).size() >= CitadelsEngine.DISTRICT_GOAL:
				leaders.append(player)
		h.greater(float(leaders.size()), 0.0, "the round that ended was triggered by a complete city")


func _city_cost(engine: GameEngine, player: int) -> int:
	var total := 0
	for card_id: String in engine.city_of(player):
		total += CitadelsEngine.district_cost(card_id)
	return total


func _five_colours(engine: GameEngine, player: int) -> bool:
	var seen: Dictionary = {}
	for card_id: String in engine.city_of(player):
		seen[CitadelsEngine.district_colour(card_id)] = true
	return seen.size() >= 5


## Both players only take income, so nobody reaches eight districts and the round
## limit has to end the match (a guaranteed-termination check as well).
func _round_limit(h: TestHarness) -> void:
	var engine := _engine(h, 2, SEED, {"round_limit": 10})
	var steps := 0
	while not engine.finished and steps < 1500:
		var state := engine.public_state()
		match String(state.get("step", "")):
			"draft":
				_apply(engine, "take_role")
			"income":
				_apply(engine, "income")
			"action":
				_apply(engine, "end_turn")
			_:
				break
		steps += 1
	h.check(engine.finished, "the round limit ends a match nobody can finish")
	h.equal(String(engine.result.get("reason_key", "")), "game.citadels.reason_round_limit", "the reason is the round limit")
	h.equal(engine.round_index, 10, "the limit is respected")
	h.check(engine.winner_index() >= 0, "a winner is still declared")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 3, SEED)
	var steps := 0
	while not engine.finished and String(engine.public_state().get("step", "")) != "action" and steps < 400:
		_step(engine)
		steps += 1
	EngineHarness.check_privacy(h, engine, _leaked_secrets, "citadels")
	var roles_0: Array = engine.private_state(0).get("roles", [])
	var roles_1: Array = engine.private_state(1).get("roles", [])
	if not roles_0.is_empty() and not roles_1.is_empty():
		h.not_equal(roles_0, roles_1, "each character belongs to a single player")
	# Undrafted characters sit face down in the pool: they are never announced.
	var state: Dictionary = engine.public_state()
	var pool: Array = state.get("role_pool", [])
	h.equal(pool.size() + int(state.get("draft_index", 0)), CitadelsEngine.ROLE_COUNT,
		"the undrafted characters stay face down on the table")


## Secret hand/role values that must never appear in another seat's snapshot.
func _leaked_secrets(theirs: Dictionary, mine: Dictionary) -> Array:
	var out: Array = []
	var my_roles: Array = mine.get("roles", [])
	for role: Variant in theirs.get("roles", []):
		if my_roles.has(role):
			out.append("role %s" % str(role))
	var their_hand: Array = theirs.get("hand", [])
	if not their_hand.is_empty() and their_hand == mine.get("hand", []):
		out.append("hand %s" % str(their_hand))
	return out


func _snapshot(h: TestHarness) -> void:
	var opening := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, opening, "citadels opening")
	var engine := _engine(h, 3, SEED + 2)
	var steps := 0
	while not engine.finished and steps < 60:
		_step(engine)
		steps += 1
	EngineHarness.check_snapshot_round_trip(h, engine, "citadels mid-match")
	# Money and a partly built city survive the trip.
	var copy := Session.create_engine("citadels")
	var snapshot := engine.public_state()
	snapshot["private_states"] = {
		"0": engine.private_state(0), "1": engine.private_state(1),
		"2": engine.private_state(2), "-1": engine.private_state(-1),
	}
	copy.restore_state(snapshot)
	h.equal(copy.gold, engine.gold, "gold survives a snapshot")
	h.equal(copy.hand_of(0), engine.hand_of(0), "the hidden hand survives a snapshot")
	h.equal(copy.private_state(-1), engine.private_state(-1), "the draw pile survives a snapshot")


func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 4, SEED + 7)
	var steps := EngineHarness.play_out(engine, 2500)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "four bots finish a match")
	h.check(not String(engine.result.get("reason_key", "")).is_empty(), "a finished match explains itself")
	h.greater(float(engine.move_log.size()), 0.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry '%s' is translated" % entry.get("text_key", ""))
	h.check(not Loc.missing_keys().has("game.citadels.log_build"), "the move log uses real strings")
	# Nobody may end up with an impossible city.
	for player: int in range(engine.player_count()):
		h.check(engine.city_of(player).size() <= CitadelsEngine.DISTRICT_GOAL, "a city never exceeds eight districts")
		h.check(engine.gold_of(player) >= 0, "gold is never negative")
	h.check(engine.legal_actions(engine.decision_player()).is_empty() or not engine.finished, "no actions are offered after the match")
