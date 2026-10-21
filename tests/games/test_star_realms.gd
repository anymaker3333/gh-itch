extends RefCounted
## Star Realms rules suite: setup, buying, combat, outposts, allies, scrap,
## optional effects, endings, determinism, snapshots and edition gating.
##
## Each rule is exercised in isolation with `debug_set_hand` / `debug_set_row`, so
## the tests never depend on a shuffled opening hand. The bot playout at the end
## checks that every rule keeps working together in a full match.

const SEED: int = 20251019


func suite_name() -> String:
	return "star realms rules"


func run(h: TestHarness) -> void:
	_setup(h)
	_buying(h)
	_explorer(h)
	_combat_and_outposts(h)
	_allies(h)
	_destroy_outpost_protection(h)
	_scrap(h)
	_optional_effects(h)
	_endings(h)
	_illegal_actions(h)
	_snapshots(h)
	_edition_gating(h)
	_determinism_and_bot(h)


func _engine(h: TestHarness, player_count: int = 2, options: Dictionary = {}) -> StarRealmsEngine:
	var engine := EngineHarness.create("star_realms", player_count, SEED, options) as StarRealmsEngine
	h.check(engine != null, "the star realms engine must be creatable")
	return engine


# --------------------------------------------------------------------- setup

func _setup(h: TestHarness) -> void:
	var engine := _engine(h)
	h.equal(engine.decision_player(), 0, "player one starts")
	h.equal(engine.phase(), "play", "the match starts in the play phase")
	h.check(engine.phases().has("play") and engine.phases().has("finished"), "both phases are declared")
	h.equal(engine.trade_row.size(), StarRealmsEngine.TRADE_ROW_SIZE, "the trade row holds five cards")
	h.equal(engine.trade_deck_size(), 75, "the remaining trade deck holds 75 cards")
	for player: int in range(2):
		h.equal(engine.authority_of(player), StarRealmsEngine.START_AUTHORITY, "player %d starts at 50 authority" % player)
		h.equal(engine.hand_of(player).size(), StarRealmsEngine.HAND_SIZE, "player %d draws five cards" % player)
		h.equal(engine.deck_of(player).size(), 5, "player %d keeps five cards in the deck" % player)
		h.equal(engine.discard_of(player).size(), 0, "player %d starts with an empty discard pile" % player)
	EngineHarness.check_legal_action_shape(h, engine, "star realms start")
	h.equal(engine.legal_actions(1).size(), 0, "the waiting player gets no actions (hidden hands)")
	var seat := (engine.public_state()["seats"] as Array)[0] as Dictionary
	h.has_key(seat, "hand_count", "the public state exposes the hand size")
	h.check(not seat.has("hand"), "the public state never exposes the hand itself")
	h.check(not engine.private_state(0).is_empty(), "the owner receives a private snapshot")
	h.check(engine.private_state(0).has("hand"), "the private snapshot carries the hand")


# ------------------------------------------------------------------- buying

func _buying(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_row(["cutter", "ram", "corvette", "trade_bot", "repair_bot"])
	engine.debug_set_hand(0, ["scout", "scout", "scout", "scout", "scout"])
	h.equal(_play_all(engine), 5, "all five scouts are played")
	h.equal(engine.trade_of(0), 5, "five scouts give five trade")
	h.check(_apply(engine, "buy", {"slot": 0}), "the cutter is affordable")
	h.equal(engine.trade_of(0), 3, "buying the cutter costs two trade")
	h.equal(_discard_id_count(engine, 0, "cutter"), 1, "the bought card goes to the discard pile")
	h.equal(engine.trade_row.size(), 5, "the row is refilled after a purchase")
	# A card that costs more than the pool is not offered and cannot be forced.
	var poor := _engine(h)
	h.check(not _has_action(poor, "buy", {}), "no card is affordable without trade")
	var forced := poor.apply_action(StarRealmsEngine.make_action("buy", {"slot": 0}))
	h.equal(String(forced.get("error_key", "")), "game.star_realms.error.cannot_afford", "forcing an unaffordable buy is rejected")


func _explorer(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_hand(0, ["scout", "scout", "scout", "scout", "scout"])
	_play_all(engine)
	h.equal(engine.trade_of(0), 5, "five trade available")
	h.check(_apply(engine, "buy_explorer", {}), "the explorer is always available")
	h.equal(engine.trade_of(0), 3, "the explorer costs two trade")
	h.check(_apply(engine, "buy_explorer", {}), "a second explorer is affordable")
	h.equal(engine.trade_of(0), 1, "two explorers cost four trade")
	h.check(not _has_action(engine, "buy_explorer", {}), "no explorer is offered below two trade")
	h.equal(_discard_id_count(engine, 0, "explorer"), 2, "both explorers reached the discard pile")


# ------------------------------------------------------- combat and outposts

func _combat_and_outposts(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_hand(0, ["viper", "viper", "viper", "viper", "viper"])
	_play_all(engine)
	h.equal(engine.combat_of(0), 5, "five vipers give five combat")
	engine.debug_play_base(1, "royal_redoubt")
	engine.debug_play_base(1, "battle_station")
	h.check(not _has_action(engine, "attack_authority", {"player": 1}), "an outpost blocks attacks on authority")
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "attack_base":
			h.equal(int(action.get("base", -1)), 0, "only the outpost may be targeted while it stands")
	h.check(_apply(engine, "attack_base", {"player": 1, "base": 0}), "the outpost is destroyed for its defence")
	h.equal(engine.combat_of(0), 0, "five combat destroy the five-defence outpost exactly")
	h.equal(engine.bases_of(1).size(), 1, "the second base survives")
	engine.grant(0, 0, 4)
	h.check(_has_action(engine, "attack_authority", {"player": 1}), "authority is attackable once the outpost is gone")
	h.check(_apply(engine, "attack_authority", {"player": 1}), "the attack lands on authority")
	h.equal(engine.authority_of(1), 46, "authority drops by the combat spent")
	h.equal(engine.combat_of(0), 0, "attacking authority spends the whole pool")
	# Outposts may not be bypassed by a fabricated action either.
	var bypass := engine.apply_action(StarRealmsEngine.make_action("attack_base", {"player": 1, "base": 0}))
	h.equal(String(bypass.get("error_key", "")), "game.star_realms.error.no_combat", "attacking without combat is rejected")
	engine.grant(0, 0, 6)
	engine.debug_play_base(1, "royal_redoubt")
	for action: Dictionary in engine.legal_actions(0):
		if String(action.get("type", "")) == "attack_base":
			h.equal(int(action.get("base", -1)), 1, "the new outpost is the only legal target")
	var blocked := engine.apply_action(StarRealmsEngine.make_action("attack_base", {"player": 1, "base": 0}))
	h.equal(String(blocked.get("error_key", "")), "game.star_realms.error.outpost_blocks", "an outpost blocks its neighbours")


# ------------------------------------------------------------------- allies

func _allies(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_hand(0, ["blob_fighter", "blob_fighter", "scout", "viper", "viper"])
	h.check(_play_card(engine, "blob_fighter"), "the first blob fighter is played")
	h.equal(engine.combat_of(0), 1, "no ally fires for the first card of a faction")
	h.check(_play_card(engine, "blob_fighter"), "the second blob fighter is played")
	h.equal(engine.combat_of(0), 3, "the ally ability adds its combat")
	engine.debug_set_hand(0, ["scout", "viper"])
	_play_all(engine)
	h.equal(engine.combat_of(0), 4, "unaligned cards never trigger an ally")
	h.check(_log_has_key(engine, "log_ally"), "ally triggers are logged")
	# A base on the table counts for future allies.
	var with_base := _engine(h)
	with_base.debug_play_base(0, "blob_wheel")
	with_base.debug_set_hand(0, ["blob_fighter"])
	h.check(_play_card(with_base, "blob_fighter"), "a fighter joins a blob base")
	h.equal(with_base.combat_of(0), 2, "the base triggers the fighter's ally ability")


# -------------------------------------------------------------------- scrap

## §6.7 regression: a destroy_base ability honours Outpost protection. While
## the victim keeps an outpost in play their ordinary bases are untouchable —
## the outpost falls first, exactly as the attack actions already require.
func _destroy_outpost_protection(h: TestHarness) -> void:
	var engine := _engine(h)
	# Two blob destroyers: one punch tears the outpost down, the second shows
	# the ordinary base opening up once the shield is gone.
	engine.debug_set_hand(0, ["blob_fighter", "blob_destroyer", "blob_destroyer", "scout", "scout"])
	_play_all(engine)
	engine.debug_play_base(1, "command_center")  # outpost, defence 7
	engine.debug_play_base(1, "blob_wheel")      # ordinary base, defence 3
	h.check(_has_action(engine, "destroy_base", {"player": 1, "base": 0}),
		"the ally destroyer opens the outpost for the pawn")
	h.check(not _has_action(engine, "destroy_base", {"player": 1, "base": 1}),
		"an outpost shields the victim's ordinary base from destroy_base")
	# A fabricated pointer past the outpost is rejected, not resolved.
	var bypass := engine.apply_action(StarRealmsEngine.make_action("destroy_base", {"player": 1, "base": 1}))
	h.check(not bool(bypass.get("ok", false)), "a fabricated destroy_base cannot bypass an outpost")
	h.equal(String(bypass.get("error_key", "")), "game.star_realms.error.outpost_blocks",
		"the rejection explains the outpost protection")
	h.check(_apply(engine, "destroy_base", {"player": 1, "base": 0}), "the outpost itself is destroyable")
	# With the outpost gone the ordinary base is a fair target again.
	h.check(_has_action(engine, "destroy_base", {"player": 1, "base": 0}),
		"the ordinary base is targetable once the outpost fell")
	h.check(_apply(engine, "destroy_base", {"player": 1, "base": 0}), "the ordinary base is destroyed")
	h.equal(engine.bases_of(1).size(), 0, "the victim ends with no bases")


func _scrap(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_hand(0, ["trade_bot", "scout", "scout", "scout", "scout"])
	h.check(_play_card(engine, "trade_bot"), "the trade bot is played")
	h.equal(engine.trade_of(0), 1, "the trade bot produces one trade")
	h.check(_has_scrap_play(engine, 0), "a scrap ability is offered for the card in play")
	h.check(_apply(engine, "scrap_play", {"card": _in_play_uid(engine, 0)}), "the trade bot is scrapped")
	h.equal(engine.removed_of(0).size(), 1, "scrapped cards leave the game")
	h.equal(engine.in_play_of(0).size(), 0, "the scrapped card leaves play")
	h.equal(engine.hand_of(0).size(), 5, "the scrap ability drew a replacement card")
	h.check(not _has_scrap_play(engine, 0), "a scrapped card cannot be scrapped twice")


# --------------------------------------------------------- optional effects

func _optional_effects(h: TestHarness) -> void:
	# `scrap_row`: the battle pod's ally lets the player scrap a trade-row card.
	var row := _engine(h)
	row.debug_set_row(["cutter", "ram", "corvette", "trade_bot", "repair_bot"])
	row.debug_play_base(0, "blob_wheel")
	row.debug_set_hand(0, ["ram"])
	h.check(_play_card(row, "ram"), "the ram is played next to a blob base")
	h.check(_has_action(row, "scrap_row", {"slot": 0}), "the ally effect offers every row slot")
	var row_size := row.trade_row.size()
	h.check(_apply(row, "scrap_row", {"slot": 0}), "the cutter is scrapped from the row")
	h.equal(row.removed_of(0).size(), 1, "the scrapped row card leaves the game")
	h.equal(row.trade_row.size(), row_size, "the row is refilled after a scrap")
	h.check(not _has_action(row, "scrap_row", {}), "the effect is consumed once used")

	# `scrap_hand`: scrapping the recycling station lets the player scrap a card.
	var hand := _engine(h)
	hand.debug_play_base(0, "recycling_station")
	hand.debug_set_hand(0, ["scout", "scout", "viper", "viper", "viper"])
	h.check(_apply(hand, "scrap_play", {"card": _in_play_uid(hand, 0)}), "the station is scrapped for its ability")
	h.equal(hand.bases_of(0).size(), 0, "scrapping a base removes it from the table")
	h.check(_has_action(hand, "scrap_hand", {"card": _hand_uid(hand, 0, "scout")}), "a hand card may be scrapped")
	h.check(_apply(hand, "scrap_hand", {"card": _hand_uid(hand, 0, "scout")}), "the hand card is scrapped")
	h.equal(hand.removed_of(0).size(), 2, "both scrapped cards left the game")

	# `destroy_base`: the blob destroyer's ally destroys a base for free.
	var destroy := _engine(h)
	destroy.debug_play_base(0, "blob_wheel")
	destroy.debug_play_base(1, "machine_base")
	destroy.debug_play_base(1, "battle_station")
	destroy.debug_set_hand(0, ["blob_destroyer"])
	h.check(_play_card(destroy, "blob_destroyer"), "the blob destroyer is played")
	h.check(_has_action(destroy, "destroy_base", {"player": 1, "base": 0}), "the ally effect offers the enemy bases")
	h.check(_apply(destroy, "destroy_base", {"player": 1, "base": 0}), "an enemy base is destroyed for free")
	h.equal(destroy.bases_of(1).size(), 1, "the other base survives")
	h.equal(_discard_id_count(destroy, 1, "machine_base"), 1, "a destroyed base goes to its owner's discard pile")


# ------------------------------------------------------------------ endings

func _endings(h: TestHarness) -> void:
	var duel := _engine(h)
	duel.set_authority(1, 4)
	duel.debug_set_hand(0, ["viper", "viper", "viper", "viper", "viper"])
	_play_all(duel)
	h.check(_apply(duel, "attack_authority", {"player": 1}), "the killing blow is dealt")
	h.check(duel.finished, "a player at zero authority ends the match")
	h.equal(duel.winner_index(), 0, "the survivor wins")
	h.equal(String(duel.result.get("reason_key", "")), "game.star_realms.reason_last_standing", "the reason is last fleet standing")
	h.equal(duel.legal_actions(0).size(), 0, "no actions remain after the match")
	var after := duel.apply_action_by_key(0, StarRealmsEngine.make_action("end_turn", {})["key"])
	h.equal(String(after.get("error_key", "")), "game.common.match_over", "the engine refuses actions after the match")

	# With three players the match continues after the first elimination.
	var three := _engine(h, 3)
	three.set_authority(1, 3)
	three.grant(0, 0, 5)
	h.check(_apply(three, "attack_authority", {"player": 1}), "player one is eliminated")
	h.check(not three.finished, "the match continues with two players left")
	h.check(_apply(three, "end_turn", {}), "the turn ends after the elimination")
	h.equal(three.decision_player(), 2, "the turn skips the eliminated seat")
	h.equal(three.legal_actions(1).size(), 0, "the eliminated player gets no actions")
	three.grant(2, 0, 2)
	h.check(_has_action(three, "attack_authority", {"player": 0}), "the remaining rival can be attacked")

	# A match that never reaches zero authority ends on the turn limit.
	var exhausted := _engine(h)
	exhausted.turns_started = StarRealmsEngine.MAX_TURNS + 1
	exhausted.set_authority(0, 5)
	exhausted.set_authority(1, 3)
	h.check(_apply(exhausted, "end_turn", {}), "the turn-limit turn can be ended")
	h.check(exhausted.finished, "the turn limit ends the match")
	h.equal(String(exhausted.result.get("reason_key", "")), "game.star_realms.reason_exhausted", "the reason is the turn limit")
	h.equal(exhausted.winner_index(), 0, "the leader on authority wins")


# --------------------------------------------------------- illegal actions

func _illegal_actions(h: TestHarness) -> void:
	var engine := _engine(h)
	var out_of_turn := engine.apply_action_by_key(1, StarRealmsEngine.make_action("end_turn", {})["key"])
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn", "the waiting player may not act")
	var unknown := engine.apply_action_by_key(0, StarRealmsEngine.make_action("dance", {})["key"])
	h.equal(String(unknown.get("error_key", "")), "game.common.illegal_action", "an unknown key is rejected before dispatch")
	var fake := engine.apply_action(StarRealmsEngine.make_action("dance", {}))
	h.equal(String(fake.get("error_key", "")), "game.star_realms.error.unknown_action", "apply_action re-validates every action")
	var stale_play := engine.apply_action(StarRealmsEngine.make_action("play_card", {"card": 999999}))
	h.equal(String(stale_play.get("error_key", "")), "game.star_realms.error.no_such_card", "playing a card that is not in hand is rejected")
	var bad_scrap := engine.apply_action(StarRealmsEngine.make_action("scrap_row", {"slot": 0}))
	h.equal(String(bad_scrap.get("error_key", "")), "game.star_realms.error.no_effect", "a scrap with no pending effect is rejected")
	# The end turn action is the only directly labelled one.
	var labelled := 0
	for action: Dictionary in engine.legal_actions(0):
		if action.has("label_key"):
			labelled += 1
			h.check(bool(action.get("_direct", false)), "a labelled action is a direct one")
	h.equal(labelled, 1, "only end turn is offered as a direct button")


# ---------------------------------------------------------------- snapshots

func _snapshots(h: TestHarness) -> void:
	var engine := _engine(h)
	engine.debug_set_hand(0, ["viper", "viper", "scout", "scout", "scout"])
	_play_all(engine)
	engine.grant(0, 3, 2)
	var public_snapshot := engine.public_state()
	var copy := Session.create_engine("star_realms") as StarRealmsEngine
	h.check(copy != null, "a second engine can be created")
	copy.restore_state(public_snapshot)
	h.equal(copy.public_state(), public_snapshot, "the public snapshot round trips")
	h.equal(copy.hand_of(copy.decision_player()).size(), 0, "a public-only restore has no hand")
	for action: Dictionary in copy.legal_actions(copy.decision_player()):
		h.not_equal(String(action.get("type", "")), "play_card", "a public-only restore cannot play cards")
	# Hands are private, so a faithful restore merges the private snapshot of the
	# player the engine waits for (exactly what the session sends to a client).
	var merged := engine.public_state()
	merged.merge(engine.private_state(engine.decision_player()), true)
	copy.restore_state(merged)
	h.equal(copy.public_state(), engine.public_state(), "the restored copy matches the live state")
	h.equal(_action_keys(copy.legal_actions(copy.decision_player())), _action_keys(engine.legal_actions(engine.decision_player())),
		"the restored copy offers the same actions")
	h.equal(copy.private_state(copy.decision_player()), engine.private_state(engine.decision_player()),
		"the restored copy keeps the private hand")
	var follow_up := copy.apply_action_by_key(copy.decision_player(), String((engine.legal_actions(engine.decision_player())[0] as Dictionary).key))
	h.check(bool(follow_up.get("ok", false)), "the restored copy can continue the match")


# ------------------------------------------------------------ edition gating

func _edition_gating(h: TestHarness) -> void:
	var core := _engine(h)
	h.equal(Array(core.used_sets), ["sr_core"], "the default match uses the core set")
	h.equal(StarRealmsCards.trade_deck_size(core.used_sets), 80, "the core trade deck holds eighty cards")
	var promos := _engine(h, 2, {"sets": ["sr_core", "sr_mercenary_garrison"]})
	h.check(Array(promos.used_sets).has("sr_mercenary_garrison"), "an implemented promo can be enabled")
	h.equal(StarRealmsCards.trade_deck_size(promos.used_sets), 81, "the promo adds one card to the trade deck")
	var core_only := _engine(h, 2, {"editions": "core", "sets": ["sr_core", "sr_mercenary_garrison"]})
	h.equal(Array(core_only.used_sets), ["sr_core"], "the core-only option overrides the selection")
	var unknown := _engine(h, 2, {"sets": ["sr_colony_wars"]})
	h.equal(Array(unknown.used_sets), ["sr_core"], "sets without imported cards are ignored")
	h.equal(StarRealmsCards.implemented_sets(), PackedStringArray(["sr_core", "sr_mercenary_garrison"]),
		"the pool implements the core set and the promo")


# ------------------------------------------------- determinism and the bot

func _determinism_and_bot(h: TestHarness) -> void:
	var first := _engine(h)
	var second := _engine(h)
	for step: int in range(40):
		var actor := first.decision_player()
		var key := BotDirector.choose_action(first, actor)
		h.check(not key.is_empty(), "the bot always finds an action (%d)" % step)
		h.check(bool(first.apply_action_by_key(actor, key).get("ok", false)), "the bot action is legal (%d)" % step)
		second.apply_action_by_key(second.decision_player(), key)
		if first.finished:
			break
	h.equal(first.public_state(), second.public_state(), "the same actions give the same state")
	h.check(_log_keys_are_translated(first), "every log entry of the bot match is translated")

	var match_engine := _engine(h)
	var steps := EngineHarness.play_out(match_engine, 3000)
	h.greater(float(steps), 0.0, "the bot playout makes progress")
	h.check(match_engine.finished, "two bots finish a match")
	if match_engine.finished:
		h.check(not String(match_engine.result.get("reason_key", "")).is_empty(), "the finished match explains itself")
		h.check(match_engine.winner_index() >= -1 and match_engine.winner_index() < 2, "the winner is a valid seat")
	h.check(_log_keys_are_translated(match_engine), "every log entry of the full match is translated")
	var missing: Array[String] = []
	for key: String in Loc.missing_keys():
		if key.begins_with("game.star_realms.") or key.begins_with("sr."):
			missing.append(key)
	h.equal(missing.size(), 0, "no star realms key fell back to English")


# ------------------------------------------------------------------ helpers

## Applies the first legal action of `action_type` whose parameters match.
func _apply(engine: StarRealmsEngine, action_type: String, params: Dictionary) -> bool:
	var actor := engine.decision_player()
	for action: Dictionary in engine.legal_actions(actor):
		if String(action.get("type", "")) != action_type:
			continue
		var matches := true
		for key: Variant in params:
			if int(action.get(key, -1)) != int(params[key]):
				matches = false
				break
		if matches:
			return bool(engine.apply_action_by_key(actor, String(action.get("key", ""))).get("ok", false))
	return false


func _has_action(engine: StarRealmsEngine, action_type: String, params: Dictionary) -> bool:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) != action_type:
			continue
		var matches := true
		for key: Variant in params:
			if int(action.get(key, -1)) != int(params[key]):
				matches = false
				break
		if matches:
			return true
	return false


func _play_card(engine: StarRealmsEngine, card_id: String) -> bool:
	var uid := _hand_uid(engine, engine.decision_player(), card_id)
	if uid < 0:
		return false
	return _apply(engine, "play_card", {"card": uid})


## Plays cards until the hand offers none (draws extend the loop).
func _play_all(engine: StarRealmsEngine) -> int:
	var played := 0
	for _guard: int in range(60):
		var actor := engine.decision_player()
		var offered := false
		for action: Dictionary in engine.legal_actions(actor):
			if String(action.get("type", "")) == "play_card":
				offered = bool(engine.apply_action_by_key(actor, String(action.get("key", ""))).get("ok", false))
				break
		if not offered:
			break
		played += 1
	return played


func _hand_uid(engine: StarRealmsEngine, player: int, card_id: String) -> int:
	for card: Dictionary in engine.hand_of(player):
		if String(card.get("id", "")) == card_id:
			return int(card.get("uid", -1))
	return -1


func _in_play_uid(engine: StarRealmsEngine, player: int) -> int:
	var cards := engine.in_play_of(player)
	if cards.is_empty():
		cards = engine.bases_of(player)
	if cards.is_empty():
		return -1
	return int((cards[0] as Dictionary).get("uid", -1))


func _has_scrap_play(engine: StarRealmsEngine, player: int) -> bool:
	for action: Dictionary in engine.legal_actions(player):
		if String(action.get("type", "")) == "scrap_play":
			return true
	return false


func _discard_id_count(engine: StarRealmsEngine, player: int, card_id: String) -> int:
	var count := 0
	for card: Dictionary in engine.discard_of(player):
		if String(card.get("id", "")) == card_id:
			count += 1
	return count


func _log_has_key(engine: StarRealmsEngine, suffix: String) -> bool:
	for entry: Dictionary in engine.move_log:
		if String(entry.get("text_key", "")).ends_with(suffix):
			return true
	return false


func _log_keys_are_translated(engine: StarRealmsEngine) -> bool:
	for entry: Dictionary in engine.move_log:
		var key := String(entry.get("text_key", ""))
		if key.is_empty() or not Loc.has_key(key, "en"):
			return false
	return true


func _action_keys(actions: Array) -> Array:
	var keys: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys
