extends RefCounted
## Coup rules suite: the hidden deal, every action and claim, challenges, blocks,
## the reveal step, elimination, the forced coup and the hidden-information
## invariants.
##
## The engine is deterministic, so each fixture is reached by driving the exact
## actions the rule under test needs; where a challenge must be provably true or
## false, the suite deals the hand directly.

const SEED: int = 20251019
const COPIES: int = 15
const VIEW_PATH: String = "res://scripts/games/coup/coup_view.gd"


func suite_name() -> String:
	return "coup rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_income(h)
	_foreign_aid(h)
	_tax(h)
	_steal(h)
	_assassinate(h)
	_challenged_claim_resolves(h)
	_exchange(h)
	_coup(h)
	_rejection(h)
	_privacy(h)
	_snapshot(h)
	_bot_match(h)
	_view_table(h)


# --------------------------------------------------------------------- set-up

func _engine(h: TestHarness, players: int = 2, seed_value: int = SEED, options: Dictionary = {}) -> GameEngine:
	var engine := EngineHarness.create("coup", players, seed_value, options)
	h.check(engine != null, "coup engine must be creatable")
	return engine


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


## Deals an exact hand, so a challenge can be tested as true or false on purpose.
func _set_hand(engine: GameEngine, player: int, roles: Array) -> void:
	var hand: Array[String] = []
	for role: Variant in roles:
		hand.append(String(role))
	engine.hands[player] = hand


## Lets every seat before `player` pass, then returns whether it is their turn.
func _pass_until(engine: GameEngine, player: int) -> bool:
	var guard := 0
	while not engine.finished and engine.decision_player() != player and guard < 24:
		if not bool(_apply(engine, "pass").get("ok", false)):
			return false
		guard += 1
	return engine.decision_player() == player


func _challenge_as(engine: GameEngine, player: int) -> bool:
	if not _pass_until(engine, player):
		return false
	return bool(_apply(engine, "challenge").get("ok", false))


## Passes out an open challenge or block window (used for windows nobody contests).
func _pass_all(engine: GameEngine) -> void:
	var guard := 0
	while not engine.finished and guard < 24:
		var step := String(engine.public_state().get("step", ""))
		if step != "challenge" and step != "block":
			break
		if not bool(_apply(engine, "pass").get("ok", false)):
			break
		guard += 1


func _has_type(engine: GameEngine, type: String) -> bool:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == type:
			return true
	return false


func _step_name(engine: GameEngine) -> String:
	return String(engine.public_state().get("step", ""))


## Every influence card of the court: hands (hidden), revealed cards and deck.
func _card_total(engine: GameEngine) -> int:
	var total: int = (engine.private_state(-1).get("deck", []) as Array).size()
	var revealed: Array = engine.public_state().get("revealed", [])
	for player: int in range(engine.player_count()):
		total += engine.hand_of(player).size()
		if player < revealed.size():
			total += (revealed[player] as Array).size()
	return total


# ------------------------------------------------------------------- openings

func _opening(h: TestHarness) -> void:
	var first := _engine(h)
	h.equal(first.phase(), "action", "a match opens with the action step")
	h.equal(first.decision_player(), 0, "the first seat acts first")
	h.equal(first.coins_of(0), 2, "players open with two coins")
	h.equal(first.coins_of(1), 2, "both seats open with two coins")
	h.equal(first.hand_of(0).size(), 2, "players open with two hidden influence")
	h.equal(first.public_state().get("hand_counts", []), [2, 2], "the influence count is public knowledge")
	h.equal((first.private_state(-1).get("deck", []) as Array).size(), COPIES - 4, "the court keeps the rest of the deck")
	h.equal(first.legal_actions(0).size(), 5, "income, aid, tax, exchange and one steal are on offer")
	h.equal(first.legal_actions(1).size(), 0, "the seat that is not acting has no actions")
	EngineHarness.check_legal_action_shape(h, first, "coup opening")

	# Same seed, same deal; a different seed shuffles differently.
	var second := _engine(h)
	h.equal(second.private_state(0), first.private_state(0), "the deal is reproducible")
	var other := _engine(h, 2, SEED + 1)
	h.not_equal(other.private_state(-1), first.private_state(-1), "a different seed shuffles differently")

	# The deck is a table secret and hands never leave the seat's snapshot.
	h.check(not first.public_state().has("hands"), "the public state carries no hands")
	h.check(not first.public_state().has("deck"), "the public state carries no deck")
	h.check(not first.private_state(0).has("deck"), "a seat never sees the deck")
	h.check(not first.private_state(-1).is_empty(), "the table holds the draw pile")
	h.equal(int(first.public_state().get("deck_count", -1)), COPIES - 4, "the deck size is public knowledge")


func _income(h: TestHarness) -> void:
	var engine := _engine(h)
	var before: int = engine.coins_of(0)
	h.check(bool(_apply(engine, "income").get("ok", false)), "income is legal on a fresh turn")
	h.equal(engine.coins_of(0), before + 1, "income is exactly one coin")
	h.equal(engine.decision_player(), 1, "the turn passes on")
	h.equal(_step_name(engine), "action", "the next seat chooses an action")


func _foreign_aid(h: TestHarness) -> void:
	# Nobody blocks: two coins.
	var aid := _engine(h)
	h.check(bool(_apply(aid, "foreign_aid").get("ok", false)), "foreign aid may be declared")
	h.equal(_step_name(aid), "block", "a block window opens")
	h.equal(aid.decision_player(), 1, "the other seat may block")
	_pass_all(aid)
	h.equal(aid.coins_of(0), 4, "foreign aid pays two coins")

	# A Duke blocks it: nothing is paid.
	var blocked := _engine(h)
	_set_hand(blocked, 1, ["duke", "contessa"])
	_apply(blocked, "foreign_aid")
	h.check(bool(_apply(blocked, "block", {"role": "duke"}).get("ok", false)), "a Duke may block foreign aid")
	_pass_all(blocked)
	h.equal(blocked.coins_of(0), 2, "a blocked foreign aid pays nothing")
	h.equal(blocked.hand_of(1).size(), 2, "the unproven block stays hidden")
	h.equal(blocked.decision_player(), 1, "the turn passes after the block")

	# A bluffed block is caught and the aid proceeds.
	var caught := _engine(h)
	_set_hand(caught, 1, ["captain", "captain"])
	_apply(caught, "foreign_aid")
	_apply(caught, "block", {"role": "duke"})
	h.check(_challenge_as(caught, 0), "the actor may challenge a block")
	_apply(caught, "lose_card", {"slot": 0})
	h.equal(caught.hand_of(1).size(), 1, "the bluffer loses an influence")
	h.equal(caught.coins_of(0), 4, "the aid still pays once the bluff is caught")


# --------------------------------------------------------------- claims

func _tax(h: TestHarness) -> void:
	# An unchallenged claim never reveals the card.
	var engine := _engine(h)
	_set_hand(engine, 0, ["duke", "assassin"])
	h.check(bool(_apply(engine, "tax").get("ok", false)), "Tax may be declared")
	h.equal(_step_name(engine), "challenge", "a challenge window opens")
	_pass_all(engine)
	h.equal(engine.coins_of(0), 5, "Tax collects three coins")
	h.equal(engine.hand_of(0).size(), 2, "an unchallenged claim keeps the hand intact")
	h.check(engine.hand_of(0).has("duke"), "the card was never shown")

	# Challenging a real Duke: the challenger loses an influence.
	var truth := _engine(h, 3)
	_set_hand(truth, 0, ["duke", "captain"])
	_apply(truth, "tax")
	h.check(_challenge_as(truth, 1), "a player may challenge a claim")
	h.equal(_step_name(truth), "lose", "the challenger must lose an influence")
	h.equal(truth.decision_player(), 1, "the challenger picks the card")
	_apply(truth, "lose_card", {"slot": 0})
	h.equal(truth.hand_of(1).size(), 1, "the challenger loses one card")
	h.equal(truth.hand_of(0).size(), 2, "the shown card is replaced from the court")
	h.equal(truth.coins_of(0), 5, "the proven claim still collects the taxes")
	h.equal(_card_total(truth), COPIES, "a proven claim keeps the court complete")

	# A caught bluff loses an influence and the action dies.
	var bluff := _engine(h)
	_set_hand(bluff, 0, ["captain", "contessa"])
	_apply(bluff, "tax")
	_challenge_as(bluff, 1)
	_apply(bluff, "lose_card", {"slot": 0})
	h.equal(bluff.coins_of(0), 2, "a caught tax collects nothing")
	h.equal(bluff.hand_of(0).size(), 1, "the bluffer loses an influence")
	h.equal(bluff.decision_player(), 1, "the turn moves on")
	h.equal((bluff.public_state().get("revealed", []) as Array)[0].size(), 1, "the revealed card is public")


func _steal(h: TestHarness) -> void:
	var steal := _engine(h)
	steal.coins[1] = 5
	_apply(steal, "steal", {"target": 1})
	_pass_all(steal)
	h.equal(steal.coins_of(0), 4, "the Captain takes two coins")
	h.equal(steal.coins_of(1), 3, "the victim loses exactly two coins")

	# A target with one coin loses just that coin.
	var thin := _engine(h)
	thin.coins[1] = 1
	_apply(thin, "steal", {"target": 1})
	_pass_all(thin)
	h.equal(thin.coins_of(0), 3, "the theft is limited to what the victim holds")
	h.equal(thin.coins_of(1), 0, "the victim is left with nothing")

	# A Captain block stops the theft.
	var block := _engine(h)
	block.coins[1] = 5
	_set_hand(block, 1, ["captain", "duke"])
	_apply(block, "steal", {"target": 1})
	_pass_until(block, 1)
	_apply(block, "pass")
	h.check(bool(_apply(block, "block", {"role": "captain"}).get("ok", false)), "the target may block with the Captain")
	_pass_all(block)
	h.equal(block.coins_of(0), 2, "a blocked steal takes nothing")
	h.equal(block.coins_of(1), 5, "the victim keeps the coins")
	h.equal(block.hand_of(1).size(), 2, "an unchallenged block reveals nothing")

	# A bluffed Captain block is caught and the theft proceeds.
	var fake := _engine(h)
	fake.coins[1] = 5
	_set_hand(fake, 1, ["duke", "duke"])
	_apply(fake, "steal", {"target": 1})
	_pass_until(fake, 1)
	_apply(fake, "pass")
	_apply(fake, "block", {"role": "captain"})
	h.check(_challenge_as(fake, 0), "the actor may challenge the block")
	_apply(fake, "lose_card", {"slot": 0})
	h.equal(fake.hand_of(1).size(), 1, "the bluffer loses an influence")
	h.equal(fake.coins_of(0), 4, "the theft still happens once the bluff is caught")
	h.equal(fake.coins_of(1), 3, "the victim pays after the failed bluff")


func _assassinate(h: TestHarness) -> void:
	# Uncontested: the cost is paid and the victim loses an influence.
	var hit := _engine(h)
	hit.coins[0] = 5
	_apply(hit, "assassinate", {"target": 1})
	h.equal(hit.coins_of(0), 2, "an assassination costs three coins")
	_pass_all(hit)
	h.equal(_step_name(hit), "lose", "the victim loses an influence")
	_apply(hit, "lose_card", {"slot": 0})
	h.equal(hit.hand_of(1).size(), 1, "the victim reveals one card")
	h.equal((hit.public_state().get("revealed", []) as Array)[1].size(), 1, "the revealed card is public")
	h.equal(hit.decision_player(), 1, "the turn passes")

	# A Contessa block saves the victim, but the coins stay paid.
	var saved := _engine(h)
	saved.coins[0] = 5
	_set_hand(saved, 1, ["contessa", "duke"])
	_apply(saved, "assassinate", {"target": 1})
	_apply(saved, "pass")
	h.check(bool(_apply(saved, "block", {"role": "contessa"}).get("ok", false)), "the victim may block with the Contessa")
	_pass_all(saved)
	h.equal(saved.hand_of(1).size(), 2, "the Contessa saves the victim")
	h.equal(saved.coins_of(0), 2, "the coins of a blocked assassination stay paid")
	h.equal(saved.decision_player(), 1, "the turn moves on")

	# Beaten challenge, then a block: the victim may still answer the action.
	var chain := _engine(h, 3)
	chain.coins[0] = 5
	_set_hand(chain, 0, ["assassin", "captain"])
	_set_hand(chain, 1, ["contessa", "duke"])
	_apply(chain, "assassinate", {"target": 1})
	h.check(_challenge_as(chain, 1), "the victim may challenge the assassin")
	_apply(chain, "lose_card", {"slot": 1})
	h.equal(_step_name(chain), "block", "a beaten challenge still opens the block window")
	h.check(bool(_apply(chain, "block", {"role": "contessa"}).get("ok", false)), "the saved Contessa may block")
	_pass_all(chain)
	h.equal(chain.hand_of(1).size(), 1, "the Contessa remains in hand")
	h.equal((chain.public_state().get("revealed", []) as Array)[1].size(), 1, "the failed challenge cost one influence")

	# A caught assassin gets the coins back and loses an influence.
	var caught := _engine(h)
	caught.coins[0] = 5
	_set_hand(caught, 0, ["captain", "captain"])
	_apply(caught, "assassinate", {"target": 1})
	_challenge_as(caught, 1)
	_apply(caught, "lose_card", {"slot": 0})
	h.equal(caught.coins_of(0), 5, "a caught assassination refunds its cost")
	h.equal(caught.hand_of(0).size(), 1, "the bluffer loses an influence")
	h.equal(caught.decision_player(), 1, "the victim survives the turn")
	h.equal(caught.hand_of(1).size(), 2, "the victim keeps both influences")


## Challenge resolution (§6.7 regression): a victim who loses their LAST card
## inside the failed challenge of an assassination claim is out of the game
## before the claim resolves. The resolution must then skip the second
## influence loss (the seat has nothing left to lose) and pass the turn on -
## a lose window over an empty hand has no legal action and stalls the match.
func _challenged_claim_resolves(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	engine.coins[0] = 5
	_set_hand(engine, 0, ["assassin", "captain"])
	_set_hand(engine, 1, ["captain"])  # challenges and goes out on the reveal
	_set_hand(engine, 2, ["contessa", "ambassador"])
	_set_hand(engine, 3, ["duke", "ambassador"])
	h.check(bool(_apply(engine, "assassinate", {"target": 1}).get("ok", false)), "the assassin is declared")
	h.check(_challenge_as(engine, 1), "the victim challenges the assassin claim")
	h.check(bool(_apply(engine, "lose_card", {"slot": 0}).get("ok", false)), "the failed challenger loses their card")
	h.equal((engine.public_state().get("revealed", []) as Array)[1].size(), 1, "the challenger's card is public")
	h.is_true(not engine.finished, "the match continues with three seats alive")
	h.is_true(not String(_step_name(engine)).is_empty(), "the engine reaches a legal step")
	var actor := engine.decision_player()
	h.is_true(actor >= 0, "a decision player exists after the challenge")
	h.greater(float(engine.legal_actions(actor).size()), 0.0,
		"the claim resolution never opens a lose window with no influence to lose (§6.7 coup challenge)")


func _exchange(h: TestHarness) -> void:
	var swap := _engine(h)
	_set_hand(swap, 0, ["ambassador", "duke"])
	_apply(swap, "exchange")
	_pass_all(swap)
	h.equal(_step_name(swap), "exchange", "the Ambassador studies the court")
	h.equal(swap.hand_of(0).size(), 4, "two cards are drawn")
	h.check(bool(_apply(swap, "return_card", {"slot": 0}).get("ok", false)), "a card can be returned")
	h.equal(swap.hand_of(0).size(), 3, "cards are returned one at a time")
	_apply(swap, "return_card", {"slot": 0})
	h.equal(swap.hand_of(0).size(), 2, "the exchange keeps the influence count")
	h.equal(swap.decision_player(), 1, "the turn passes once the exchange is done")
	h.equal(_card_total(swap), COPIES, "the court always holds fifteen cards")

	# Challenging a real Ambassador: the challenger loses, the exchange proceeds.
	var truth := _engine(h, 3)
	_set_hand(truth, 0, ["ambassador", "captain"])
	_apply(truth, "exchange")
	_challenge_as(truth, 1)
	_apply(truth, "lose_card", {"slot": 0})
	h.equal(_step_name(truth), "exchange", "the proven Ambassador still studies the court")
	h.equal(truth.hand_of(1).size(), 1, "the challenger loses an influence")

	# A caught exchange costs the claimant an influence.
	var fake := _engine(h)
	_set_hand(fake, 0, ["captain", "duke"])
	_apply(fake, "exchange")
	_challenge_as(fake, 1)
	_apply(fake, "lose_card", {"slot": 0})
	h.equal(fake.hand_of(0).size(), 1, "a caught exchange costs an influence")
	h.equal(_step_name(fake), "action", "the court is never studied")
	h.equal(fake.decision_player(), 1, "the turn moves on")


func _coup(h: TestHarness) -> void:
	# Ten coins force a coup: no other action is offered.
	var engine := _engine(h)
	engine.coins[0] = 10
	var forced := true
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) != "coup":
			forced = false
	h.check(forced, "ten coins leave only coups on offer")
	h.check(not _has_type(engine, "income"), "income is not an option at ten coins")
	_apply(engine, "coup", {"target": 1})
	h.equal(engine.coins_of(0), 3, "a coup costs seven coins")
	h.equal(_step_name(engine), "lose", "the coup victim loses an influence")
	_apply(engine, "lose_card", {"slot": 0})
	h.equal(engine.decision_player(), 1, "the turn passes after the coup")

	# Eliminating the last influence ends the match.
	var final := _engine(h)
	_set_hand(final, 1, ["duke"])
	final.coins[0] = 7
	_apply(final, "coup", {"target": 1})
	h.equal(final.hand_of(1).size(), 1, "the victim is down to one influence")
	_apply(final, "lose_card", {"slot": 0})
	h.check(final.finished, "a player with no influence left is out")
	h.equal(final.winner_index(), 0, "the last player with influence wins")
	h.equal(String(final.result.get("reason_key", "")), "game.coup.reason_last_standing",
		"the finish explains itself")
	h.equal((final.result.get("scores", []) as Array).size(), 2, "every player is scored")
	h.check(final.legal_actions(final.decision_player()).is_empty(), "no actions are offered after the match")


# --------------------------------------------------------------- rejections

func _rejection(h: TestHarness) -> void:
	var engine := _engine(h)
	var bogus := GameEngine.make_action("teleport", {})
	h.equal(String(engine.apply_action(bogus).get("error_key", "")), "game.coup.error.unknown_action",
		"an unknown action type is rejected")
	var unaffordable := GameEngine.make_action("coup", {"target": 1})
	h.equal(String(engine.apply_action(unaffordable).get("error_key", "")), "game.coup.error.illegal_action",
		"a coup that cannot be paid is not on the list")
	# Income is refused while another player answers a claim.
	_apply(engine, "tax")
	h.equal(_step_name(engine), "challenge", "the claim is waiting")
	var income := GameEngine.make_action("income", {})
	h.equal(String(engine.apply_action(income).get("error_key", "")), "game.coup.error.illegal_action",
		"actions outside the current window are rejected")
	# The same income action is legal again once the window closes.
	_pass_all(engine)
	h.equal(engine.decision_player(), 1, "the window closed and the turn moved on")
	h.check(bool(_apply(engine, "income").get("ok", false)), "income is legal again on the new turn")
	# A stale block key cannot be replayed outside a block window.
	var stale := GameEngine.make_action("block", {"role": "duke"})
	h.equal(String(engine.apply_action(stale).get("error_key", "")), "game.coup.error.illegal_action",
		"a stale block is rejected")


# ------------------------------------------------------------------- privacy

func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	EngineHarness.play_out(engine, 40)
	EngineHarness.check_privacy(h, engine, _leaked_secrets, "coup")
	h.check(not engine.public_state().has("hands"), "hands never appear in the public state")
	h.check(not engine.public_state().has("deck"), "the deck never appears in the public state")
	h.check(not engine.private_state(0).has("deck"), "a seat never sees the court deck")
	h.check(not (engine.private_state(-1).get("deck", []) as Array).is_empty(), "the table holds the court deck")
	var mine: Array = engine.private_state(0).get("hand", [])
	if not mine.is_empty():
		h.check(not engine.private_state(1).has("deck"), "another seat never sees the deck either")


## Secret hands must never appear in another seat's snapshot.
func _leaked_secrets(theirs: Dictionary, mine: Dictionary) -> Array:
	var out: Array = []
	var their_hand: Array = theirs.get("hand", [])
	if not their_hand.is_empty() and their_hand == mine.get("hand", []):
		out.append("hand %s" % str(their_hand))
	return out


func _snapshot(h: TestHarness) -> void:
	var opening := _engine(h)
	EngineHarness.check_snapshot_round_trip(h, opening, "coup opening")
	var engine := _engine(h, 3)
	EngineHarness.play_out(engine, 60)
	EngineHarness.check_snapshot_round_trip(h, engine, "coup mid-match")
	# The deck and the hidden hands survive an explicit restore.
	var copy := Session.create_engine("coup")
	var snapshot := engine.public_state()
	snapshot["private_states"] = {
		"0": engine.private_state(0), "1": engine.private_state(1),
		"2": engine.private_state(2), "-1": engine.private_state(-1),
	}
	copy.restore_state(snapshot)
	h.equal(copy.private_state(-1), engine.private_state(-1), "the court deck survives a snapshot")
	h.equal(copy.private_state(0), engine.private_state(0), "the hidden hand survives a snapshot")
	h.equal(copy.public_state().get("coins"), engine.public_state().get("coins"), "coins survive a snapshot")
	h.equal(copy.public_state().get("revealed"), engine.public_state().get("revealed"),
		"revealed influences survive a snapshot")


# ----------------------------------------------------------------- bot match

func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var steps := EngineHarness.play_out(engine, 4000)
	h.greater(float(steps), 0.0, "the bot match makes progress")
	h.check(engine.finished, "two bots finish a match")
	h.equal(String(engine.result.get("reason_key", "")), "game.coup.reason_last_standing",
		"the match ends with a last player standing")
	h.check(engine.winner_index() >= 0, "a winner is declared")
	h.greater(float(engine.hand_of(engine.winner_index()).size()), 0.0, "the winner still holds influence")
	h.greater(float(engine.move_log.size()), 0.0, "the match is logged")
	for entry: Dictionary in engine.move_log:
		h.check(Loc.has_key(String(entry.get("text_key", "")), "en"),
			"log entry '%s' is translated" % entry.get("text_key", ""))
	h.equal(_card_total(engine), COPIES, "no influence card is lost or duplicated")
	for player: int in range(engine.player_count()):
		h.check(engine.coins_of(player) >= 0, "coins are never negative")
		h.check(engine.hand_of(player).size() <= 2, "nobody keeps more than two hidden cards")

	# Six players, and the same seed replays identically.
	var big := _engine(h, 6, SEED + 3)
	EngineHarness.play_out(big, 6000)
	h.check(big.finished, "six bots finish a match")
	h.equal(_card_total(big), COPIES, "a six-player match keeps the court complete")
	var replay_a := _engine(h, 4, SEED + 9)
	var replay_b := _engine(h, 4, SEED + 9)
	EngineHarness.play_out(replay_a, 4000)
	EngineHarness.play_out(replay_b, 4000)
	h.equal(replay_b.public_state(), replay_a.public_state(), "the same seed and bots replay identically")
	h.equal(replay_b.winner_index(), replay_a.winner_index(), "a replay crowns the same winner")


# ------------------------------------------------------------------- the board

## The board view is presentation only, but a broken one strands the table: the
## screens call `configure()` -> `build_board()` -> `refresh_board()` and then
## submit through the session, so the suite drives that exact path headlessly.
func _view_table(h: TestHarness) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	h.check(tree != null, "a SceneTree is available for the board test")
	if tree == null:
		return
	Session.configure("coup", 2, {"seed": SEED})
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	h.check(session != null, "a hotseat session starts for the board")
	if session == null:
		return
	var script := load(VIEW_PATH) as GDScript
	h.check(script != null, "the coup view script loads")
	var view: GameView = null
	if script != null:
		view = script.new() as GameView
	h.check(view != null, "the coup view instantiates as a GameView")
	if view == null:
		Session.end_session(false)
		return
	h.is_true(view.requires_handover(), "the view hides the table behind a handover")
	tree.root.add_child(view)
	view.configure(session)
	var engine: GameEngine = session.engine
	h.check(view.get("_status") != null, "the board builds its status line")
	h.check(view.get("_players_box") != null, "the board builds the player list")
	# The screen parents these into the action bar; here they are freed by hand.
	var extras := view.action_bar_extras()
	h.equal(extras.size(), 3, "the action bar shows phase, coins and court size")
	for chip: Control in extras:
		chip.free()

	# An exchange: the view turns hand cards into the only way to return them.
	engine.hands[0] = ["ambassador", "duke"] as Array[String]
	var exchange_key := ""
	for action: Dictionary in session.available_actions():
		if String(action.get("type", "")) == "exchange":
			exchange_key = String(action.get("key", ""))
			break
	h.check(bool(engine.apply_action_by_key(0, exchange_key).get("ok", false)), "exchange opens for the board")
	_pass_all(engine)
	h.equal(_step_name(engine), "exchange", "the board reaches the exchange step")
	view.refresh_board()
	h.check(_view_raw_keys(view).is_empty(), "every board label resolves: %s" % _view_raw_keys(view))
	var faces := _hand_faces(view)
	h.equal(faces.size(), 4, "the exchange shows both drawn cards")
	if faces.size() == 4:
		(faces[0] as CardFace).clicked.emit("card")
		view.refresh_board()
		var left := _hand_faces(view)
		if left.size() == 3:
			(left[2] as CardFace).clicked.emit("card")
	h.equal((engine.hands[0] as Array).size(), 2, "a click returns the card through the session")
	h.check(_view_raw_keys(view).is_empty(), "the board still resolves after the exchange")
	h.equal(_card_total(engine), COPIES, "the exchange keeps the court complete")

	# A block: both window lines name the claim, the role and the action.
	engine.hands[1] = ["ambassador", "duke"] as Array[String]
	h.check(bool(_apply(engine, "foreign_aid").get("ok", false)), "foreign aid opens the block window")
	h.equal(engine.decision_player(), 0, "the rival may block the aid")
	view.refresh_board()
	var block_line := String(view.get("_claim").text)
	h.check(not view.get("_claim").visible or not block_line.is_empty(), "the block line renders")
	h.check(not block_line.contains("game.") and not block_line.contains("%"), "the block line resolves: %s" % block_line)
	h.check(bool(_apply(engine, "block", {"role": "duke"}).get("ok", false)), "a Duke may block the aid")
	view.refresh_board()
	var claim_line := String(view.get("_claim").text)
	h.is_true(claim_line.contains(engine.role_name("duke")), "the block names the Duke: %s" % claim_line)
	h.check(not claim_line.contains("game.") and not claim_line.contains("%"), "the claim line resolves: %s" % claim_line)
	h.check(_view_raw_keys(view).is_empty(), "the board resolves during challenge windows")
	_apply(engine, "pass")
	h.equal(_step_name(engine), "action", "the window closes when nobody challenges")

	# A full match driven only through the session, the way a player plays.
	var steps := 0
	var raw_hits := 0
	var seen_steps: Dictionary = {}
	while not engine.finished and steps < 400:
		steps += 1
		view.refresh_board()
		seen_steps[String(engine.public_state().get("step", ""))] = true
		if not _view_raw_keys(view).is_empty():
			raw_hits += 1
		var actions := session.available_actions()
		h.check(actions.size() > 0, "the board always offers an action (step %d)" % steps)
		if actions.is_empty():
			break
		var pick: Dictionary = actions[(steps * 7) % actions.size()]
		session.submit_action_key(String(pick.get("key", "")))
	h.check(engine.finished, "a match played through the board finishes (%d steps)" % steps)
	h.equal(raw_hits, 0, "no label falls back to a raw key during the match")
	h.check(seen_steps.has("action") and seen_steps.has("lose"),
		"the board rendered the action and reveal steps: %s" % [seen_steps.keys()])
	h.greater(float((view.get("_players_box") as VBoxContainer).get_child_count()), 0.0,
		"the board lists a panel per seat")
	view.free()
	Session.end_session(false)


## Anything the view renders as a raw key or an unfilled placeholder.
func _view_raw_keys(view: GameView) -> String:
	var out: Array[String] = []
	_collect_labels(view, out, true)
	return " | ".join(out)


func _hand_faces(view: GameView) -> Array[Node]:
	var out: Array[Node] = []
	var flow: Node = view.get("_hand_flow")
	if flow != null:
		for child: Node in flow.get_children():
			out.append(child)
	return out


func _collect_labels(node: Node, out: Array[String], only_raw: bool = false) -> void:
	for child: Node in node.get_children():
		if child is Label:
			var text: String = (child as Label).text
			if not only_raw or text.contains("game.") or text.contains("{") or text.contains("%s"):
				out.append(text)
		_collect_labels(child, out, only_raw)
