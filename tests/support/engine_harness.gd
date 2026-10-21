class_name EngineHarness
extends RefCounted
## Helpers shared by the per-game rules suites.
##
## Builds engines with a deterministic seed, drives bots to completion and
## provides the invariants every game must satisfy (finite matches, legal actions
## always applicable, snapshots restorable, hidden information protected).

const MAX_BOT_STEPS: int = 4000


## Creates an engine for `game_id`, sets it up and returns it (null + message on
## failure, so suites can report a readable error instead of crashing).
static func create(game_id: String, player_count: int = 2, seed_value: int = 424242, options: Dictionary = {}) -> GameEngine:
	if not Session.engine_available(game_id):
		Log.error("test: engine unavailable", {"game": game_id})
		return null
	var engine := Session.create_engine(game_id)
	if engine == null:
		return null
	var names: Array = []
	var kinds: Array = []
	for i: int in range(player_count):
		names.append("P%d" % (i + 1))
		kinds.append("local")
	var setup_options: Dictionary = options.duplicate(true)
	setup_options["player_names"] = names
	setup_options["player_kinds"] = kinds
	setup_options["seed"] = seed_value
	engine.setup(setup_options)
	return engine


## Applies the first legal action of the decision player. Returns false when the
## engine offers no action (which is itself a bug worth reporting).
static func step_first_legal(engine: GameEngine) -> bool:
	var actor := engine.decision_player()
	var actions := engine.legal_actions(actor)
	if actions.is_empty():
		return false
	var action: Dictionary = actions[0]
	var outcome := engine.apply_action_by_key(actor, String(action.get("key", "")))
	return bool(outcome.get("ok", false))


## Plays up to `max_steps` actions using the bot policy (or first-legal fallback)
## and returns the number of steps performed.
static func play_out(engine: GameEngine, max_steps: int = MAX_BOT_STEPS) -> int:
	var steps := 0
	while not engine.finished and steps < max_steps:
		var actor := engine.decision_player()
		var key := BotDirector.choose_action(engine, actor)
		if key.is_empty():
			break
		var outcome := engine.apply_action_by_key(actor, key)
		if not bool(outcome.get("ok", false)):
			return steps
		steps += 1
	return steps


## Legal-action invariants: unique keys, every key resolvable, labels localised.
static func check_legal_action_shape(h: TestHarness, engine: GameEngine, label: String) -> void:
	var actor := engine.decision_player()
	var actions := engine.legal_actions(actor)
	h.greater(float(actions.size()), 0.0, "%s: decision player must have at least one action" % label)
	var seen: Dictionary = {}
	for action: Variant in actions:
		if not (action is Dictionary):
			h.check(false, "%s: legal action is not a dictionary" % label)
			continue
		var entry: Dictionary = action
		var key := String(entry.get("key", ""))
		h.check(not key.is_empty(), "%s: action without key" % label)
		h.check(not seen.has(key), "%s: duplicate action key '%s'" % [label, key])
		seen[key] = true
		h.check(entry.has("type"), "%s: action without type ('%s')" % [label, key])
		var label_key := String(entry.get("label_key", ""))
		if not label_key.is_empty():
			h.check(Loc.has_key(label_key), "%s: missing translation for action label '%s'" % [label, label_key])
			h.no_raw_key(Loc.t(label_key), "%s: action label" % label)


## Snapshot round trip.
##
## Every legal action key must survive a snapshot, and a snapshot must be enough
## to keep playing. The harness therefore feeds the copy both forms of private
## state an engine may rely on:
##
##   * the acting player's private state, merged at the **top level** - the
##     shape an online client receives (public snapshot + own private state);
##   * a `private_states` **bag** with every seat's [method
##     GameEngine.private_state] keyed by seat index, plus `-1` for table
##     secrets such as a shuffled draw pile - the shape a save file needs to
##     restore a whole match.
##
## Engines consume whichever form their snapshot format uses; unknown keys are
## ignored, so this is safe for games without hidden information. Restoring the
## public half alone cannot reproduce hand-driven actions, which is why the
## private halves are supplied here.
static func check_snapshot_round_trip(h: TestHarness, engine: GameEngine, label: String) -> void:
	var public_snapshot := engine.public_state()
	var actor := engine.decision_player()
	var snapshot := public_snapshot.duplicate(true)
	if actor >= 0:
		snapshot.merge(engine.private_state(actor), true)
	var secrets: Dictionary = {}
	for player: int in range(-1, engine.player_count()):
		var private_snapshot := engine.private_state(player)
		if not private_snapshot.is_empty():
			secrets[str(player)] = private_snapshot
	snapshot["private_states"] = secrets
	var copy := Session.create_engine(engine.game_id())
	if copy == null:
		h.check(false, "%s: could not create engine copy" % label)
		return
	copy.restore_state(snapshot)
	h.equal(copy.public_state(), public_snapshot, "%s: public snapshot must round trip" % label)
	var before := engine.legal_actions(actor)
	var after := copy.legal_actions(actor)
	h.equal(_keys_of(after), _keys_of(before), "%s: legal actions must survive a snapshot" % label)


static func _keys_of(actions: Array) -> Array:
	var keys: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys


## Hidden information invariant: no other player's private snapshot may contain a
## value that only the owner is allowed to see.
static func check_privacy(h: TestHarness, engine: GameEngine, secrets_of: Callable, label: String) -> void:
	for player: int in range(engine.player_count()):
		var mine := engine.private_state(player)
		for other: int in range(engine.player_count()):
			if other == player:
				continue
			var theirs := engine.private_state(other)
			var leaked: Array = secrets_of.call(theirs, mine)
			for item: Variant in leaked:
				h.check(false, "%s: player %d can see '%s' of player %d" % [label, player, str(item), other])
	h.checks_run += 1
