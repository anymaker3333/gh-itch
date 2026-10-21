class_name GameEngine
extends RefCounted
## Base class for every game rules engine.
##
## Engines are pure logic: no nodes, no UI, no networking. They are deterministic
## for a given seed, which makes rules testable in headless mode and makes
## host-authoritative state replication straightforward.
##
## Contract used by the session layer and the UI:
##  * [method legal_actions] enumerates everything the given player may do now,
##    each entry being a serialisable dictionary with a stable [code]key[/code].
##  * [method apply_action] re-validates the action (never trusting the caller),
##    mutates the state and returns a result dictionary.
##  * [method public_state] / [method private_state] produce serialisable
##    snapshots; private information is only ever sent to its owner.

signal state_changed()
signal action_applied(action: Dictionary)
signal match_finished(result: Dictionary)
signal log_appended(entry: Dictionary)

const MAX_LOG_ENTRIES: int = 300

## players: [{ "index": int, "name": String, "kind": "local"|"bot"|"remote",
##             "peer_id": int, "steam_id": int }]
var players: Array[Dictionary] = []
var seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn: int = 0
var round_index: int = 1
var finished: bool = false
var result: Dictionary = {}
var move_log: Array[Dictionary] = []
var action_count: int = 0
var started: bool = false


# --------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "generic"


## Called once by the session with `{ "player_names": [...], "seed": int, ... }`.
func setup(options: Dictionary) -> void:
	seed = VariantUtil.as_int(options.get("seed", 0), 0)
	if seed == 0:
		seed = int(Time.get_unix_time_from_system() * 1000.0) ^ int(randi())
	rng.seed = seed
	players.clear()
	var names: Array = VariantUtil.as_array(options.get("player_names", []))
	var kinds: Array = VariantUtil.as_array(options.get("player_kinds", []))
	for i: int in range(names.size()):
		players.append({
			"index": i,
			"name": VariantUtil.as_string(names[i], ""),
			"kind": VariantUtil.as_string(kinds[i], "local") if i < kinds.size() else "local",
			"peer_id": 0,
			"steam_id": 0,
		})
	turn = 0
	round_index = 1
	finished = false
	result = {}
	move_log.clear()
	action_count = 0
	started = true
	_terminal_reported = false
	# A fresh match is authoritative: any client slice from a previous snapshot
	# would leak stale private data into the next one.
	_client_seat = -1
	_client_slice = {}
	state_changed.emit()


## Short machine-readable phase id (used for hints and tests).
func phase() -> String:
	return "play"


## Every phase id this engine can report, so tooling can verify that each one has
## a translation. Engines with a state machine override this.
func phases() -> PackedStringArray:
	return PackedStringArray([phase()])


## Localised phase label.
func phase_hint() -> String:
	return Loc.t("game.common.phase", {"phase": Loc.t("game.%s.phase.%s" % [game_id(), phase()])})


func player_count() -> int:
	return players.size()


func player_name(index: int) -> String:
	if index < 0 or index >= players.size():
		return "?"
	return String(players[index].name)


func is_bot(index: int) -> bool:
	return index >= 0 and index < players.size() and VariantUtil.as_string(players[index].kind) == "bot"


## Extra setup options this game exposes to the setup screen.
## Each entry: { key, label_key, type: "bool"|"int"|"enum", default, min, max,
## values, labels, hint_key }
func options_schema() -> Array[Dictionary]:
	return []


func decision_player() -> int:
	return turn


func legal_actions(_player: int) -> Array[Dictionary]:
	return []


func apply_action(_action: Dictionary) -> Dictionary:
	return _fail("game.common.not_implemented")


func is_finished() -> bool:
	return finished


func winner_index() -> int:
	return VariantUtil.as_int(result.get("winner", -1), -1)


## Serialisable snapshot visible to everybody.
func public_state() -> Dictionary:
	return {
		"game": game_id(),
		"turn": turn,
		"round": round_index,
		"phase": phase(),
		"decision_player": decision_player(),
		"finished": finished,
		"players": players.duplicate(true),
		"result": result.duplicate(true),
		"log": move_log.slice(maxi(0, move_log.size() - 12)),
	}


## Additional snapshot only `player` may see. Engines with hidden information
## override this; the default exposes nothing.
func private_state(_player: int) -> Dictionary:
	return {}


# ------------------------------------------------- client-side private slices

## Seat whose authorized private slice a client replica carries, or -1.
## A host replica never uses this path: it holds every seat's private state.
var _client_seat: int = -1
## The authorized slice itself, exactly as the host tailored it: used as the
## verbatim answer for its owner seat when a game has no structured restore.
var _client_slice: Dictionary = {}


## Installs the ONE private slice that belongs to `seat` on a client replica —
## the `private` payload of the host's snapshot on top of a public-state
## restore. Games with structured private state override
## [method _adopt_private_extra] to fill their real fields, so legal actions and
## rendering keep working from authoritative structures; the verbatim slice
## remains the owner-seat answer for games whose private view is opaque.
##
## Never used on the host: a host engine holds every seat's private state after
## its own setup, and adopting a slice there would *replace* authority with a
## client copy. The session only calls this in ONLINE_CLIENT mode.
func adopt_private_view(seat: int, slice: Dictionary) -> void:
	_client_seat = seat
	_client_slice = slice.duplicate(true)
	_adopt_private_extra(_client_seat, _client_slice)


## Per-game installation of one seat's private slice. Implementations must not
## clear data of other seats: a client replica only ever knows its own slice
## plus the public snapshot.
func _adopt_private_extra(_seat: int, _slice: Dictionary) -> void:
	pass


## Rebuilds state from a snapshot (clients, save/load, tests).
##
## A snapshot arrives from the network and may be malformed, so every field is
## read defensively: a wrong type must degrade into an empty value instead of
## raising "Invalid cast" or "Invalid get index" and aborting the restore.
func restore_state(state: Dictionary) -> void:
	finished = bool(state.get("finished", false))
	# A restored match never re-emits the terminal event of a match that the
	# snapshot already reports as finished.
	_terminal_reported = finished
	result = VariantUtil.dict_copy(state.get("result", {}))
	turn = VariantUtil.as_int(state.get("turn", 0), 0)
	round_index = VariantUtil.as_int(state.get("round", 1), 1)
	# Element-wise copy: snapshots arrive as plain (untyped) arrays, and
	# assigning those straight to `Array[Dictionary]` fails at runtime.
	# The key's presence decides whether the list is replaced; a wrongly typed
	# value leaves the current list untouched rather than raising.
	if state.has("players") and state["players"] is Array:
		players.clear()
		for entry: Variant in VariantUtil.as_array(state.get("players", [])):
			if entry is Dictionary:
				players.append((entry as Dictionary).duplicate(true))
	if state.has("log") and state["log"] is Array:
		move_log.clear()
		for entry: Variant in VariantUtil.as_array(state.get("log", [])):
			if entry is Dictionary:
				move_log.append((entry as Dictionary).duplicate(true))
	_restore_extra(state)
	state_changed.emit()


## Engine-specific extension point for [method restore_state].
func _restore_extra(_state: Dictionary) -> void:
	pass


## Copies a plain snap-shot array into a `Array[String]` field.
##
## Snapshots always travel as *untyped* arrays (JSON-like dictionaries), and
## assigning one straight to a typed array is a runtime error in Godot, so
## engines must copy element-wise when they restore their state.
static func copy_string_array(source: Variant, target: Array[String]) -> void:
	target.clear()
	for entry: Variant in VariantUtil.as_array(source):
		target.append(VariantUtil.as_string(entry, ""))


## Same as [method copy_string_array] for `Array[int]` fields.
static func copy_int_array(source: Variant, target: Array[int]) -> void:
	target.clear()
	for entry: Variant in VariantUtil.as_array(source):
		target.append(VariantUtil.as_int(entry, 0))


# ------------------------------------------------------------- result helpers

## Terminal-event guard: `finish()` is the ONE authoritative place where the
## engine's `match_finished` signal is emitted. Engines call it whenever the
## match ends (from `apply_action`, from resign paths, from tests). `_ok()`
## after a terminal `apply_action` used to emit the same signal a second time,
## which doubled every "match finished" log line, replication snapshot and
## session-finished handler on the exact same action.
var _terminal_reported: bool = false

func _fail(key: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error_key": key, "error": Loc.t(key, args)}


func _ok(action: Dictionary = {}) -> Dictionary:
	action_count += 1
	action_applied.emit(action)
	state_changed.emit()
	if finished and not _terminal_reported:
		_terminal_reported = true
		match_finished.emit(result)
	return {"ok": true, "action": action}


func finish(winner: int, reason_key: String, scores: Array = []) -> void:
	# Exactly one terminal event per match: a second (re-entrant or repeated)
	# finish() call neither rewrites the result nor re-emits the signal.
	if finished:
		return
	finished = true
	result = {
		"winner": winner,
		"reason_key": reason_key,
		"reason": Loc.t(reason_key),
		"scores": scores,
	}
	log_event("game.common.match_finished", {"winner": player_name(winner) if winner >= 0 else Loc.t("game.common.draw")})
	match_finished.emit(result)
	_terminal_reported = true


## Appends a human readable entry to the shared move log.
func log_event(text_key: String, args: Dictionary = {}, player: int = -1) -> void:
	move_log.append({
		"seq": move_log.size(),
		"player": player,
		"text_key": text_key,
		"args": args,
		"text": Loc.t(text_key, args),
		"turn": turn,
		"round": round_index,
	})
	if move_log.size() > MAX_LOG_ENTRIES:
		move_log.remove_at(0)
	log_appended.emit(move_log.back())


func recent_log(count: int = 8) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(move_log.size() - 1, maxi(-1, move_log.size() - count - 1), -1):
		out.append(move_log[i])
	return out


# ----------------------------------------------------------- action utilities

## Stable identity for a legal action: type plus its parameters, sorted.
##
## Fields whose name starts with `_` are metadata for views and transports and
## are excluded, so an action keeps the same key whether or not presentation
## data (piece glyphs, flags, target hints) is attached to it.
static func action_key(action: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys: Array = action.keys()
	keys.sort()
	for key: Variant in keys:
		var name := VariantUtil.as_string(key, "")
		if name == "label_key" or name == "key" or name.begins_with("_"):
			continue
		parts.append("%s=%s" % [name, str(action[key])])
	return "|".join(parts)


static func make_action(type: String, params: Dictionary = {}, label_key: String = "") -> Dictionary:
	var action := params.duplicate(true)
	action["type"] = type
	if not label_key.is_empty():
		action["label_key"] = label_key
	action["key"] = action_key(action)
	return action


## Finds the legal action matching `key` (used to validate incoming messages).
func find_legal_action(player: int, key: String) -> Dictionary:
	for action: Dictionary in legal_actions(player):
		if VariantUtil.as_string(action.get("key", ""), "") == key:
			return action
	return {}


## Applies an action identified by `key` after checking it is legal.
func apply_action_by_key(player: int, key: String) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	if player != decision_player():
		return _fail("game.common.not_your_turn")
	var action := find_legal_action(player, key)
	if action.is_empty():
		return _fail("game.common.illegal_action")
	return apply_action(action)


func scores_text() -> String:
	var parts := PackedStringArray()
	for entry: Variant in result.get("scores", []):
		if entry is Dictionary:
			parts.append("%s: %s" % [VariantUtil.as_string(entry.get("name", ""), "?"), str(entry.get("score", 0))])
	return ", ".join(parts)


func winner_text() -> String:
	var winner := winner_index()
	if winner < 0:
		return Loc.t("game.common.draw")
	return player_name(winner)
