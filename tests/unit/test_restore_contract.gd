extends RefCounted
## Snapshot and restore contract (§5.3 / Wave A §6.3).
##
## Covers all engines and EVERY snapshot shape the project uses:
##
##   1. save-file shape: public snapshot + a `private_states` bag keyed by seat
##      (with "-1" for table secrets) — what a saved match contains;
##   2. client shape: public snapshot plus ONE seat's slice installed through
##      `adopt_private_view` — what `GameSession._apply_snapshot` gives an
##      online client's engine replica;
##   3. merged client shape (harness contract): the decision player's slice
##      merged at the top level of the public snapshot.
##
## After restore, legal-action lists must match the original, and applying the
## same legal next action to the original and the restored engine must produce
## identical authoritative state. For hidden-information games every seat is
## tested: each seat's own private slice keeps the match playable, and no other
## seat's private data may substitute for it.

const ACTIONS_TO_COMPARE: int = 6


func suite_name() -> String:
	return "restore contract (13 engines)"


func run(h: TestHarness) -> void:
	for entry: Variant in Catalog.games():
		if entry is GameEntry:
			_check_engine(h, entry)


func _check_engine(h: TestHarness, entry: GameEntry) -> void:
	var game_id := entry.id
	var engine := EngineHarness.create(game_id, entry.min_players, 20251019)
	if engine == null:
		h.check(false, "%s: engine creatable" % game_id)
		return
	# Play a couple of legal actions so the snapshot is not just the opening.
	for step: int in range(2):
		if engine.finished:
			break
		if not EngineHarness.step_first_legal(engine):
			break
	_check_save_shape(h, engine, game_id)
	_check_client_shape_every_seat(h, engine, game_id)
	_apply_same_action_after_restore(h, engine, game_id)


## Save-file shape: public + every seat's private data in the `private_states` bag.
func _check_save_shape(h: TestHarness, engine: GameEngine, game_id: String) -> void:
	var public_snapshot := engine.public_state()
	var snapshot := public_snapshot.duplicate(true)
	var secrets: Dictionary = {}
	for seat: int in range(-1, engine.player_count()):
		var slice: Dictionary = engine.private_state(seat)
		if not slice.is_empty():
			secrets[str(seat)] = slice
	snapshot["private_states"] = secrets
	var copy := Session.create_engine(game_id)
	if copy == null:
		h.check(false, "%s: engine copy creatable" % game_id)
		return
	copy.restore_state(snapshot)
	h.equal(copy.public_state(), public_snapshot, "%s: save-shape public state round trips" % game_id)
	h.equal(_keys_of(copy.legal_actions(copy.decision_player())), _keys_of(engine.legal_actions(engine.decision_player())),
		"%s: save-shape restore keeps the decision player's legal actions" % game_id)


## Client shape, per seat: restore the public snapshot, then install exactly
## the seat's own authorized slice the way `GameSession._apply_snapshot` does
## on an online client (`adopt_private_view`). Every seat in hidden-information
## games must be able to keep playing from exactly what that seat would
## receive — and no other seat's private data may ride along.
func _check_client_shape_every_seat(h: TestHarness, engine: GameEngine, game_id: String) -> void:
	var public_snapshot := engine.public_state()
	for seat: int in range(engine.player_count()):
		var slice := engine.private_state(seat)
		var copy := Session.create_engine(game_id)
		if copy == null:
			h.check(false, "%s: client copy for seat %d" % [game_id, seat])
			continue
		copy.restore_state(public_snapshot)
		if not slice.is_empty():
			copy.adopt_private_view(seat, slice)
		# The seat must see its own slice back through the engine contract.
		h.equal(copy.private_state(seat), slice, "%s: seat %d receives exactly its authorized private slice" % [game_id, seat])
		# No other seat's secrets may ride along: the replica renders its board
		# from public state plus this one slice, nothing else.
		h.check(not copy.public_state().has("hand"), "%s: seat %d public state carries no explicit hand field" % [game_id, seat])
		var original_actions := _keys_of(engine.legal_actions(seat))
		h.equal(_keys_of(copy.legal_actions(seat)), original_actions,
			"%s: seat %d's legal actions survive a client-shape restore" % [game_id, seat])
	# The documented harness/EngineHarness merged form on top: the decision
	# player's own slice merged into the public snapshot at the top level must
	# also restore that seat's ability to act (EngineHarness contract).
	var actor := engine.decision_player()
	if actor < 0:
		return
	var actor_slice := engine.private_state(actor)
	var merged := public_snapshot.duplicate(true)
	if not actor_slice.is_empty():
		merged.merge(actor_slice, true)
	var merged_copy := Session.create_engine(game_id)
	if merged_copy == null:
		h.check(false, "%s: merged-form copy" % game_id)
		return
	merged_copy.restore_state(merged)
	h.equal(_keys_of(merged_copy.legal_actions(actor)), _keys_of(engine.legal_actions(actor)),
		"%s: decision player's merged-form restore keeps legal actions" % [game_id])


## Applies the same legal next action on the original and the save-shape copy
## and compares the resulting authoritative public snapshots.
func _apply_same_action_after_restore(h: TestHarness, engine: GameEngine, game_id: String) -> void:
	if engine.finished:
		h.equal(true, true, "%s: terminal match has no next action to compare" % game_id)
		return
	var public_snapshot := engine.public_state()
	var snapshot := public_snapshot.duplicate(true)
	var secrets: Dictionary = {}
	for seat: int in range(-1, engine.player_count()):
		var slice: Dictionary = engine.private_state(seat)
		if not slice.is_empty():
			secrets[str(seat)] = slice
	snapshot["private_states"] = secrets
	var copy := Session.create_engine(game_id)
	if copy == null:
		h.check(false, "%s: comparison copy" % game_id)
		return
	copy.restore_state(snapshot)
	var actor := engine.decision_player()
	h.equal(copy.decision_player(), actor, "%s: the copy waits for the same seat" % game_id)
	var original_actions := engine.legal_actions(actor)
	var copy_actions := copy.legal_actions(actor)
	h.equal(_keys_of(copy_actions), _keys_of(original_actions), "%s: both sides offer the same next actions" % game_id)
	for step: int in range(ACTIONS_TO_COMPARE):
		if engine.finished or copy == null or copy.finished:
			break
		var action := _matching_action(original_actions, copy_actions, step)
		if action.is_empty():
			break
		var key := String(action.get("key", ""))
		# Each side acts with its OWN current decision player: a fixed actor
		# would be correctly rejected by a side whose turn has moved on, which
		# faked convergence failures.
		var original_outcome := engine.apply_action_by_key(engine.decision_player(), key)
		var copy_outcome := copy.apply_action_by_key(copy.decision_player(), key)
		h.equal(bool(copy_outcome.get("ok", false)), bool(original_outcome.get("ok", false)),
			"%s: step %d is accepted on both sides" % [game_id, step])
		if not bool(original_outcome.get("ok", false)):
			break
		original_actions = engine.legal_actions(engine.decision_player())
		copy_actions = copy.legal_actions(copy.decision_player())
		h.equal(_keys_of(copy_actions), _keys_of(original_actions), "%s: step %d keeps the action lists in sync" % [game_id, step])
	h.equal(copy.public_state(), engine.public_state(), "%s: same actions converge to identical state" % game_id)


## The step-th entry common to both action lists (by key), so engine order
## differences cannot create false positives.
func _matching_action(original: Array, copy_actions: Array, step: int) -> Dictionary:
	var copy_keys := {}
	for action: Variant in copy_actions:
		copy_keys[String((action as Dictionary).get("key", ""))] = action
	var matched := 0
	for action: Variant in original:
		if String((action as Dictionary).get("key", "")) in copy_keys:
			if matched == step:
				return action
			matched += 1
	return {}


func _keys_of(actions: Array) -> Array:
	var keys: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys
