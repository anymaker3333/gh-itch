extends RefCounted
## Durak rules suite: opening deal, trump order, attack/defence rules, helpers,
## pick-ups, refills, the fool ending, snapshots and privacy.
##
## Positions are installed with the engine's [method DurakEngine.load_position]
## seam (the card-game counterpart of chess' FEN) so every rule can be tested in
## isolation instead of shuffling for it.

const TRUMP: String = "H7"


func suite_name() -> String:
	return "durak rules"


func run(h: TestHarness) -> void:
	_opening(h)
	_trump_order(h)
	_attack_and_defence(h)
	_helpers(h)
	_pick_up(h)
	_refill_and_rotation(h)
	_empty_attacker_rotation(h)
	_illegal_actions(h)
	_match_end(h)
	_snapshots(h)
	_determinism(h)
	_bot_match(h)
	_privacy(h)


func _engine(h: TestHarness, players: int = 2, seed_value: int = 20251019, options: Dictionary = {}) -> DurakEngine:
	var engine := EngineHarness.create("durak", players, seed_value, options)
	h.check(engine != null, "durak engine must be creatable")
	return engine as DurakEngine


## A two-player position with an empty deck (except the trump card) and no
## random refills, so the assertions stay exact.
func _position(h: TestHarness, first: Array, second: Array, trump: String = TRUMP) -> DurakEngine:
	var engine := _engine(h)
	var ok := engine.load_position([first, second], [trump], trump, 0)
	h.check(ok, "the position must load")
	return engine


func _key_for_card(engine: DurakEngine, card: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("card", "")) == card:
			return String(action.get("key", ""))
	return "missing:%s" % card


func _defends(engine: DurakEngine) -> Array[String]:
	var out: Array[String] = []
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "defend":
			out.append(String(action.get("card", "")))
	return out


# --------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.player_count(), 2, "durak seats two players by default")
	h.equal(engine.hand_size, 6, "each player is dealt six cards")
	var total := engine.deck_count
	for count: int in engine.hand_counts:
		total += count
	h.equal(total, 36, "hand plus deck always holds the full 36-card deck")
	h.check(engine.deck_count == 36 - 12, "24 cards are left in the deck")
	h.equal(engine.trump_suit, DurakEngine.card_suit(engine.trump_card), "the trump card fixes the trump suit")
	h.equal(engine.trump_card, engine.deck[0], "the trump card waits at the bottom of the deck")
	h.equal(engine.phase(), "attack", "a fresh match starts with an attack")
	h.equal(engine.decision_player(), engine.attacker, "the attacker opens")
	h.equal(engine.round_cap, 6, "a round holds up to six attacks")
	EngineHarness.check_legal_action_shape(h, engine, "durak opening")
	h.check(engine.legal_actions(engine.decision_player()).size() > 0, "the attacker may play")
	h.check(engine.private_state(0).has("hand"), "player 0 sees a hand")
	h.check(not engine.private_state(0).has("trump_card"), "the private snapshot holds nothing but the hand")

	var four := _engine(h, 4)
	h.equal(four.player_count(), 4, "four seats are supported")
	h.equal(four.hand_counts[3], 6, "four players get six cards each")
	h.equal(four.deck_count, 36 - 24, "only twelve cards are left with four players")

	var other := _engine(h)
	h.equal(engine.public_state(), other.public_state(), "the same seed deals the same public state")
	h.equal(engine.private_state(0), other.private_state(0), "the same seed deals the same hand")
	h.equal(engine.private_state(1), other.private_state(1), "…to every seat")
	var lower := _engine(h, 2, 999)
	h.check(lower.private_state(0) != engine.private_state(0), "a different seed deals differently")


# ----------------------------------------------------------------- trump order

func _trump_order(h: TestHarness) -> void:
	# Nobody holds a trump: seat 0 opens.
	var plain := _engine(h)
	h.check(plain.load_position(
		[["S6", "C7", "D8", "C9", "D10", "CJ"], ["S8", "C10", "DJ", "CQ", "DK", "CA"]],
		["H7"], TRUMP, -1), "a trump-less position loads")
	h.equal(plain.attacker, 0, "seat 0 opens when nobody holds a trump")

	# The lowest trump opens - seat 1 holds the H6.
	var with_trumps := _engine(h)
	with_trumps.load_position(
		[["S6", "C7", "D8", "C9", "D10", "CJ"], ["H6", "H8", "S9", "SQ", "SK", "HA"]],
		[TRUMP], TRUMP, -1)
	h.equal(with_trumps.attacker, 1, "the lowest trump opens")

	# A trump beats a plain card of another suit, a higher trump beats a trump
	# and a plain card never beats a trump.
	var engine := _position(h, ["S6", "H9", "CK", "CQ", "S10", "D8"], ["S9", "H6", "DJ", "D6", "C10", "SJ"])
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "S6")).get("ok", false)), "the attacker plays S6")
	h.equal(engine.phase(), "defense", "an uncovered card puts durak in the defence phase")
	h.equal(engine.decision_player(), 1, "the defender answers")
	var defends := _defends(engine)
	defends.sort()
	h.equal(defends, ["H6", "S9", "SJ"] as Array[String], "only higher spades and the trump may beat S6")
	h.check(not defends.has("D6"), "a plain card of another suit may not beat S6")
	# The trump beats the plain attack.
	h.check(bool(engine.apply_action_by_key(1, _key_for_card(engine, "H6")).get("ok", false)), "the trump H6 beats S6")

	# A trump attack can only be beaten by a higher trump.
	var trumped := _position(h, ["H9", "S6", "CK", "CQ", "S10", "D8"], ["H10", "H6", "S9", "SJ", "DJ", "D6"])
	trumped.apply_action_by_key(0, _key_for_card(trumped, "H9"))
	var defenders := _defends(trumped)
	h.equal(defenders.size(), 1, "exactly one card beats the H9")
	h.equal(defenders[0], "H10", "only a higher trump beats a trump")


# --------------------------------------------------------- attack and defence

func _attack_and_defence(h: TestHarness) -> void:
	var engine := _position(h, ["S6", "S10", "CK", "CQ", "D8", "H9"], ["S9", "SJ", "H6", "D6", "C10", "D7"])
	h.check(bool(engine.apply_action_by_key(0, _key_for_card(engine, "S6")).get("ok", false)), "the attack lands")
	h.check(bool(engine.apply_action_by_key(1, _key_for_card(engine, "S9")).get("ok", false)), "the defence lands")
	h.equal(String((engine.table[0] as Dictionary).get("defense", "")), "S9", "the table keeps the pair together")
	h.equal(engine.phase(), "attack", "a beaten card returns the turn to the attackers")
	h.equal(engine.decision_player(), 0, "the attacker continues")
	h.equal(engine.last_adder, 0, "the attacker stays the last adder")
	var attacks: Array[String] = []
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "attack":
			attacks.append(String(action.get("card", "")))
	h.equal(attacks, ["H9"] as Array[String], "only a rank already on the table may be added")
	h.check(engine.legal_actions(0).size() == 2, "the attacker may add H9 or finish the attack")
	# A helper would also be bound by the ranks on the table: the 6 and the 9.
	engine.apply_action_by_key(0, _key_for_card(engine, "H9"))
	h.equal(engine.phase(), "defense", "the added card is unanswered again")
	h.check(_defends(engine).is_empty(), "nothing beats the added H9 for the defender")
	h.equal(engine.legal_actions(1).size(), 1, "taking is the only answer left")
	h.equal(String(engine.legal_actions(1)[0].get("type", "")), "take", "…and it is the pick-up")


# -------------------------------------------------------------------- helpers

func _helpers(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	h.check(engine.load_position(
		[["S6", "D6", "CK", "CQ", "D8", "H9"], ["S9", "H6", "DJ", "D7", "C10", "SJ"], ["S7", "H8", "D9", "CJ", "D10", "SQ"]],
		[TRUMP], TRUMP, 0), "the three-player position loads")
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	engine.apply_action_by_key(1, _key_for_card(engine, "S9"))
	h.equal(engine.decision_player(), 2, "the helper gets the turn after the defender answered")
	var attacks: Array[String] = []
	for action: Dictionary in engine.legal_actions(2):
		if String(action.get("type", "")) == "attack":
			attacks.append(String(action.get("card", "")))
	h.equal(attacks, ["D9"] as Array[String], "the helper may only add a rank on the table")
	h.check(bool(engine.apply_action_by_key(2, _key_for_card(engine, "D9")).get("ok", false)), "the helper adds the D9")
	engine.apply_action_by_key(1, _key_for_card(engine, "DJ"))
	h.equal(engine.decision_player(), 0, "the round returns to the attacker")
	# Everybody finishes: the table is discarded and the defender takes the lead.
	var pass_actions := engine.legal_actions(0)
	var passed := false
	for action: Dictionary in pass_actions:
		if String(action.get("type", "")) == "pass":
			passed = bool(engine.apply_action_by_key(0, String(action.get("key", ""))).get("ok", false))
	h.check(passed, "the attacker may finish the attack")
	engine.apply_action_by_key(2, _pass_key(engine, 2))
	h.check(engine.table.is_empty(), "a beaten table is cleared")
	h.equal(engine.discard_count, 4, "both pairs left play")
	h.equal(engine.attacker, 1, "the defender takes over the attack")
	h.equal(engine.defender, 2, "the next player with cards defends")
	h.check(engine.hand_counts[1] == 5, "the defender redraws one of the two cards played")
	h.check(engine.hand_counts[2] == 5, "the helper redraws the card they played")
	h.equal(engine.deck_count, 0, "the last card was the trump card")
	h.check(engine.hand_counts[1] == 5 and engine.deck_count == 0, "the trump card is drawn last")


func _pass_key(engine: DurakEngine, player: int) -> String:
	for action: Dictionary in engine.legal_actions(player):
		if String(action.get("type", "")) == "pass":
			return String(action.get("key", ""))
	return ""


# -------------------------------------------------------------------- pick-up

func _pick_up(h: TestHarness) -> void:
	var engine := _position(h, ["S6", "H9", "CK", "CQ", "D8", "S10"], ["S9", "SJ", "H6", "D6", "C10", "D7"])
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	var take_key := ""
	for action: Dictionary in engine.legal_actions(1):
		if String(action.get("type", "")) == "take":
			take_key = String(action.get("key", ""))
	h.check(not take_key.is_empty(), "the defender may always pick the cards up")
	h.check(bool(engine.apply_action_by_key(1, take_key).get("ok", false)), "the pick-up applies")
	h.equal(engine.hand_counts[1], 7, "the defender takes the table into their hand")
	h.check(engine.table.is_empty(), "the table is cleared after a pick-up")
	h.equal(engine.attacker, 0, "the attack moves to the next player after the defender")
	h.equal(engine.discard_count, 0, "nothing leaves play on a pick-up")
	h.equal(engine.deck_count, 0, "the trump card leaves the deck on the refill")


func _refill_and_rotation(h: TestHarness) -> void:
	var engine := _engine(h, 2, 20251019, {"hand_size": 4})
	h.check(engine.hand_size == 4, "the hand size option is honoured")
	h.equal(engine.deck_count, 36 - 8, "a smaller hand leaves more cards in the deck")
	h.check(engine.load_position(
		[["S6", "H9"], ["S9", "H6"]],
		[TRUMP, "D6", "D7", "D8", "D9", "D10", "DJ"], TRUMP, 0), "a short-handed position loads")
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	engine.apply_action_by_key(1, _key_for_card(engine, "H6"))
	var pass_key := _pass_key(engine, 0)
	h.check(bool(engine.apply_action_by_key(0, pass_key).get("ok", false)), "the attacker finishes")
	h.equal(engine.hand_counts[1], 4, "the new attacker (the old defender) refills first")
	h.equal(engine.hand_counts[0], 4, "the other seat also draws back to the hand size")
	h.equal(engine.deck_count, 1, "six cards left the deck, the trump card stays")
	h.equal(engine.attacker, 1, "a successful defence hands the attack over")
	h.equal(engine.defender, 0, "the other seat defends")


# ------------------------------------------------------------------- legality

## Empty-attacker rotation (§6.7 regression): after the final successful
## defence the defender may sit on an empty hand with the deck gone, while the
## match still runs. The opening right must move to the next seat that holds
## cards — an empty hand on an open table can neither attack nor pass.
func _empty_attacker_rotation(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	# Deck empty; the trump card hides in the attacker's hand so no refill
	# happens. Seat 2 attacks S9, seat 0 beats it with the trump H10 (their
	# only card), the cap-1 table clears at once.
	h.check(engine.load_position([["H10"], ["D6"], ["S9", "H7"]], [], "H7", 2), "the position must load")
	h.equal(engine.attacker, 2, "the loaded attack belongs to seat 2")
	h.equal(engine.defender, 0, "the defender is seat 0")
	var attack: Dictionary = engine.legal_actions(2)[0]
	h.check(bool(engine.apply_action_by_key(2, String(attack.get("key", ""))).get("ok")), "the attack applies")
	var defend: Dictionary = {}
	for option: Variant in engine.legal_actions(0):
		if String((option as Dictionary).get("type", "")) == "defend":
			defend = option
			break
	h.greater(float(defend.size()), 0.0, "the defender has a beating card")
	h.check(bool(engine.apply_action_by_key(0, String(defend.get("key", ""))).get("ok")), "the defence applies")
	# The round is over (cap 1), the match is not: seat 1 and seat 2 hold cards.
	h.is_true(not engine.finished, "the match continues while two seats hold cards")
	var actor := engine.decision_player()
	h.is_true(actor != 0, "the emptied defender does not open the next round")
	h.greater(float(engine.legal_actions(actor).size()), 0.0,
		"a new round never starts on a seat with no legal action (§6.7 durak attack deadlock)")


func _illegal_actions(h: TestHarness) -> void:
	var engine := _position(h, ["S6", "H9", "CK", "CQ", "D8", "S10"], ["S9", "SJ", "H6", "D6", "C10", "D7"])
	var out_of_turn := engine.apply_action_by_key(1, String(engine.legal_actions(0)[0].get("key", "")))
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "playing out of turn is rejected")
	var unknown := engine.apply_action({ "type": "explode", "key": "type=explode" })
	h.equal(String(unknown.get("error_key", "")), "game.durak.error.unknown_action", "an unknown action type is rejected")
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	var cheat := engine.apply_action({ "type": "defend", "card": "HA", "beat": "S6", "key": "beat=S6|card=HA|type=defend" })
	h.equal(String(cheat.get("error_key", "")), "game.durak.error.illegal_action", "a card that is not in hand is rejected")
	var covered := engine.apply_action({ "type": "attack", "card": "H9", "key": "card=H9|type=attack" })
	h.equal(String(covered.get("error_key", "")), "game.durak.error.illegal_action", "a card of a new rank may not be added")
	engine.apply_action_by_key(1, _key_for_card(engine, "S9"))
	var stale := engine.apply_action({ "type": "defend", "card": "D7", "beat": "S6", "key": "beat=S6|card=D7|type=defend" })
	h.equal(String(stale.get("error_key", "")), "game.durak.error.illegal_action", "a beaten card cannot be defended twice")


# ----------------------------------------------------------------- match end

func _match_end(h: TestHarness) -> void:
	var engine := _engine(h)
	h.check(engine.load_position([["S6"], ["S7", "H6"]], [TRUMP], TRUMP, 0), "the endgame position loads")
	h.equal(engine.round_cap, 2, "the round is capped by the defender's hand")
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	engine.apply_action_by_key(1, _key_for_card(engine, "S7"))
	h.check(engine.finished, "a shed hand ends the match")
	h.equal(engine.winner_index(), 0, "the player who shed their hand last wins")
	h.equal(String(engine.result.get("reason_key", "")), "game.durak.reason.fool", "the fool is the reason")
	h.equal(int((engine.result.scores as Array)[1].score), 2, "the fool keeps the cards left in hand")
	h.equal(int((engine.result.scores as Array)[0].score), 0, "the winner holds nothing")
	h.check(engine.legal_actions(0).is_empty(), "a finished match offers no actions")
	var over := engine.apply_action_by_key(0, "type=attack|card=S6")
	h.equal(String(over.get("error_key", "")), "game.common.match_over", "no action after the match")


func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	_full_round_trip(h, engine, "opening")
	# The public snapshot alone is a spectator model: it round trips, but a
	# card-less engine cannot play a card.
	var public_only := Session.create_engine("durak")
	public_only.restore_state(engine.public_state())
	h.equal(public_only.public_state(), engine.public_state(), "the public snapshot round trips")
	h.equal(public_only.legal_actions(public_only.decision_player()).size(), 0, "a public-only snapshot cannot play cards")
	engine.apply_action_by_key(engine.decision_player(), String(engine.legal_actions(engine.decision_player())[0].get("key", "")))
	_full_round_trip(h, engine, "mid-round")
	var after_attack := Session.create_engine("durak")
	after_attack.restore_state(engine.public_state())
	for action: Dictionary in after_attack.legal_actions(after_attack.decision_player()):
		h.equal(String(action.get("type", "")), "take",
			"a public-only snapshot only keeps the card-less actions")
	EngineHarness.check_snapshot_round_trip(h, _finished_engine(h), "durak (finished)")


## Public + private + deck: the state the host and its clients really hold.
func _full_round_trip(h: TestHarness, engine: DurakEngine, label: String) -> void:
	var merged := engine.public_state()
	var hands: Array = []
	for seat: int in range(engine.player_count()):
		hands.append(engine.private_state(seat).get("hand", []))
	merged["hands"] = hands
	merged["deck"] = engine.deck.duplicate()
	var copy := Session.create_engine("durak") as DurakEngine
	copy.restore_state(merged)
	h.equal(copy.public_state(), engine.public_state(), "%s: the public state survives a snapshot" % label)
	h.equal(copy.deck, engine.deck, "%s: the deck order survives a snapshot" % label)
	for seat: int in range(engine.player_count()):
		h.equal(copy.private_state(seat), engine.private_state(seat), "%s: hand %d survives a snapshot" % [label, seat])
	h.equal(_keys(copy.legal_actions(copy.decision_player())), _keys(engine.legal_actions(engine.decision_player())),
		"%s: legal actions survive a snapshot" % label)


func _keys(actions: Array) -> Array:
	var keys: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys


func _finished_engine(h: TestHarness) -> DurakEngine:
	var engine := _engine(h)
	engine.load_position([["S6"], ["S7", "H6"]], [TRUMP], TRUMP, 0)
	engine.apply_action_by_key(0, _key_for_card(engine, "S6"))
	engine.apply_action_by_key(1, _key_for_card(engine, "S7"))
	return engine


# ------------------------------------------------------------- determinism

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
	for players: int in [2, 4]:
		var engine := _engine(h, players, 880000 + players)
		var steps := EngineHarness.play_out(engine, 1500)
		h.greater(float(steps), 0.0, "the %d-player bot match makes progress" % players)
		h.check(engine.finished, "the %d-player bot match finishes" % players)
		if engine.finished:
			h.check(not String(engine.result.get("reason_key", "")).is_empty(), "a finished match explains itself")
			h.check(Loc.has_key(String(engine.result.get("reason_key", "")), "en"), "the end reason is translated")
		for entry: Dictionary in engine.move_log:
			h.check(Loc.has_key(String(entry.get("text_key", "")), "en"), "log entry %s is translated" % entry.get("text_key", ""))
			h.no_raw_key(String(entry.get("text", "")), "log text is rendered")


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 4)
	# Nothing of another seat may show up in my private snapshot.
	EngineHarness.check_privacy(h, engine, func(theirs: Dictionary, mine: Dictionary) -> Array:
		var mine_text := JSON.stringify(mine)
		var leaked: Array = []
		for card: Variant in theirs.get("hand", []):
			if mine_text.contains("\"%s\"" % String(card)):
				leaked.append(card)
		return leaked
	, "durak")
	var public_text := JSON.stringify(engine.public_state())
	for seat: int in range(engine.player_count()):
		for card: Variant in engine.private_state(seat).get("hand", []):
			h.check(not public_text.contains("\"%s\"" % String(card)),
				"card %s of player %d is not in the public snapshot" % [card, seat])
