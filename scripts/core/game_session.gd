class_name GameSession
extends Node
## One running match: authoritative rules engine + session lifecycle.
##
## Host-authoritative listen-server model. The host owns the [GameEngine]; clients
## only send *intended actions* (validated against the host's legal action list)
## and render snapshots. Hidden information never leaves the host except towards
## its owner.

signal state_updated()
signal private_state_updated()
signal action_rejected(reason_key: String, detail: String)
signal player_connection_changed(player_index: int, connected: bool)
signal session_finished(result: Dictionary)
signal notice(message_key: String, args: Dictionary)

enum Mode { LOCAL_HOTSEAT = 0, SOLO_AI = 1, ONLINE_HOST = 2, ONLINE_CLIENT = 3 }

const BOT_THINK_SEC: float = 0.65
## Bounded bot retries (§6.4): after this many consecutive failed bot actions
## the driver stops instead of retrying forever.
const BOT_MAX_FAILS: int = 3
const STATE_MESSAGE_SIZE_WARN: int = 200000

var mode: Mode = Mode.LOCAL_HOTSEAT
var engine: GameEngine = null
var game_id: String = ""
var config: Dictionary = {}

## For online sessions: the local player index. -1 means "hotseat, whoever acts".
var local_player: int = -1

## Client-side last snapshots received from the host.
var last_public: Dictionary = {}
var last_private: Dictionary = {}
var last_legal: Array = []
var state_seq: int = 0

var action_seq_sent: int = 0
var _last_applied_seq: Dictionary = {}  # peer id -> last accepted action seq
var _bot_timer: float = 0.0
## Consecutive bot failures (§6.4): at [constant BOT_MAX_FAILS] the bot driver
## stops and the session stalls visibly instead of rejecting in a loop.
var _bot_fail_streak: int = 0
var _bot_stalled: bool = false
var disconnected_players: Array[int] = []


func is_host() -> bool:
	return mode == Mode.ONLINE_HOST or mode == Mode.LOCAL_HOTSEAT or mode == Mode.SOLO_AI


func is_online() -> bool:
	return mode == Mode.ONLINE_HOST or mode == Mode.ONLINE_CLIENT


func is_local_mode() -> bool:
	return not is_online()


## Player index that the local input device controls right now.
func active_local_player() -> int:
	if engine == null or engine.players.is_empty():
		return -1
	if mode == Mode.ONLINE_CLIENT or mode == Mode.ONLINE_HOST:
		return local_player
	return engine.decision_player()


func engine_for_view() -> GameEngine:
	return engine


# ------------------------------------------------------------------ lifecycle

func start(new_engine: GameEngine, new_mode: Mode, options: Dictionary, config_data: Dictionary = {}) -> void:
	engine = new_engine
	mode = new_mode
	game_id = new_engine.game_id()
	config = config_data.duplicate(true)
	engine.setup(options)
	_bot_fail_streak = 0
	_bot_stalled = false
	_last_applied_seq.clear()
	if mode == Mode.ONLINE_HOST:
		# The host always plays seat 0; remote seats follow the lobby seat order.
		local_player = 0
		Net._set_link(Net.Link.MATCH_RUNNING, "match running")
	elif mode == Mode.ONLINE_CLIENT:
		local_player = maxi(0, local_player)
		Net._set_link(Net.Link.MATCH_RUNNING, "match running")
	else:
		local_player = -1
	engine.state_changed.connect(_on_engine_state_changed)
	engine.match_finished.connect(_on_engine_finished)
	Log.info("Session: started", {
		"game": game_id,
		"mode": mode_name(),
		"players": engine.player_count(),
		"seed": engine.seed,
	})
	state_updated.emit()


func mode_name() -> String:
	match mode:
		Mode.SOLO_AI:
			return "solo_ai"
		Mode.ONLINE_HOST:
			return "online_host"
		Mode.ONLINE_CLIENT:
			return "online_client"
		_:
			return "hotseat"


func stop() -> void:
	if engine != null and engine.match_finished.is_connected(_on_engine_finished):
		engine.match_finished.disconnect(_on_engine_finished)
	if engine != null and engine.state_changed.is_connected(_on_engine_state_changed):
		engine.state_changed.disconnect(_on_engine_state_changed)
	if is_online() and Net.is_transport_active():
		Net.close()
	engine = null
	last_public.clear()
	last_private.clear()
	last_legal.clear()


# ------------------------------------------------------------------- actions

## Actions the local player may perform now (host: from the engine; client: from
## the last snapshot the host sent).
func available_actions() -> Array:
	if mode == Mode.ONLINE_CLIENT:
		if engine == null or engine.finished:
			return []
		if local_player != engine.decision_player():
			return []
		return last_legal.duplicate(true)
	if engine == null:
		return []
	var actor := active_local_player()
	if actor < 0:
		return []
	return engine.legal_actions(actor)


func submit_action_key(key: String) -> void:
	if key.is_empty():
		return
	if mode == Mode.ONLINE_CLIENT:
		action_seq_sent += 1
		Net.send_to_host(NetProtocol.envelope(NetProtocol.T_ACTION, {
			"seq": action_seq_sent,
			"player": local_player,
			"key": key,
			"based_on": state_seq,
		}))
		return
	var actor := active_local_player()
	if actor < 0:
		return
	var outcome := engine.apply_action_by_key(actor, key)
	if not bool(outcome.get("ok", false)):
		_emit_rejection(
			VariantUtil.as_string(outcome.get("error_key", ""), "game.common.illegal_action"),
			VariantUtil.as_string(outcome.get("error", ""), "")
		)
		return
	if is_online():
		_replicate_state()


func _emit_rejection(reason_key: String, detail: String) -> void:
	Log.info("Session: action rejected", {"reason": reason_key, "detail": detail})
	action_rejected.emit(reason_key, detail)


## Pushes the current snapshot to every connected peer (host only). Called right
## after a match starts and whenever a client asks to resynchronise.
func push_state() -> void:
	if is_online() and mode == Mode.ONLINE_HOST:
		_replicate_state()


# --------------------------------------------------------- host replication

func _on_engine_state_changed() -> void:
	if mode == Mode.ONLINE_CLIENT:
		return
	state_updated.emit()
	if is_online():
		# Mitigation for clients stuck mid-turn: nothing to do here, states are
		# pushed explicitly by the action path. Keep the hook for safety.
		pass


func _on_engine_finished(result_data: Dictionary) -> void:
	Log.info("Session: match finished", {"game": game_id, "winner": result_data.get("winner", -1)})
	if is_online():
		_replicate_state()
		var message := NetProtocol.envelope(NetProtocol.T_MATCH_END, {"result": engine.public_state().get("result", {})})
		Net.broadcast(message)
		Net._set_link(Net.Link.CONNECTED, "match finished")
	session_finished.emit(result_data)
	state_updated.emit()


## Sends each participant its own tailored snapshot: common public state, that
## player's private information and its current legal action list.
func _replicate_state() -> void:
	state_seq += 1
	var public_snapshot := engine.public_state()
	for peer_id: int in Net.peer_ids():
		if peer_id == Net.local_peer_id:
			continue
		var info: Dictionary = Net.peer_info(peer_id)
		var player_index := VariantUtil.as_int(info.get("player_index", -1), -1)
		var payload: Dictionary = {
			"seq": state_seq,
			"game": game_id,
			"public": public_snapshot,
			"private": {},
			"legal": [],
		}
		if player_index >= 0:
			payload["private"] = engine.private_state(player_index)
			payload["legal"] = engine.legal_actions(player_index) if player_index == engine.decision_player() and not engine.finished else []
		var message := NetProtocol.envelope(NetProtocol.T_STATE, payload)
		var encoded_size := NetProtocol.encode(message).size()
		if encoded_size > STATE_MESSAGE_SIZE_WARN:
			Log.warn("Session: large state message", {"bytes": encoded_size, "game": game_id})
		Net.send(peer_id, message)


## Registers a peer as a participant (index must match the engine's player order).
func assign_peer_player(peer_id: int, player_index: int, name: String, steam_id: int) -> void:
	Net.register_peer(peer_id, {"player_index": player_index, "name": name, "steam_id": steam_id})
	if engine != null and player_index >= 0 and player_index < engine.players.size():
		engine.players[player_index]["peer_id"] = peer_id
		engine.players[player_index]["steam_id"] = steam_id
		if VariantUtil.as_string(engine.players[player_index].kind) == "remote":
			engine.players[player_index]["name"] = name


func peer_for_player(player_index: int) -> int:
	if engine == null or player_index < 0 or player_index >= engine.players.size():
		return 0
	return VariantUtil.as_int(engine.players[player_index].get("peer_id", 0), 0)


func handle_remote_action(peer_id: int, message: Dictionary) -> void:
	if mode != Mode.ONLINE_HOST:
		return
	var info: Dictionary = Net.peer_info(peer_id)
	var player_index := VariantUtil.as_int(info.get("player_index", -1), -1)
	if player_index < 0:
		Net.send(peer_id, NetProtocol.reject(NetProtocol.Reject.NOT_PLAYER))
		return
	var seq := VariantUtil.as_int(message.get("seq", 0), 0)
	if seq <= VariantUtil.as_int(_last_applied_seq.get(peer_id, 0), 0):
		# Duplicate/out-of-order action: ignore, but confirm the current state so
		# the sender can resynchronise.
		Log.warn("Session: duplicate action ignored", {"peer": peer_id, "seq": seq})
		Net.send(peer_id, NetProtocol.envelope(NetProtocol.T_STATE, {
			"seq": state_seq, "game": game_id,
			"public": engine.public_state(),
			"private": engine.private_state(player_index),
			"legal": engine.legal_actions(player_index),
		}))
		return
	var key := VariantUtil.as_string(message.get("key", ""), "")
	if key.is_empty():
		Net.send(peer_id, NetProtocol.reject(NetProtocol.Reject.MALFORMED))
		return
	if engine.finished:
		Net.send(peer_id, NetProtocol.reject(NetProtocol.Reject.MATCH_RUNNING, "match already finished"))
		return
	if player_index != engine.decision_player():
		_last_applied_seq[peer_id] = seq
		Net.send(peer_id, NetProtocol.envelope(NetProtocol.T_ACTION_RESULT, {
			"seq": seq, "ok": false, "reason": int(NetProtocol.Reject.OUT_OF_TURN),
			"key": key, "error_key": "game.common.not_your_turn",
		}))
		_emit_rejection("game.common.not_your_turn", "peer %d" % peer_id)
		return
	var outcome := engine.apply_action_by_key(player_index, key)
	_last_applied_seq[peer_id] = seq
	if not bool(outcome.get("ok", false)):
		var error_key := VariantUtil.as_string(outcome.get("error_key", ""), "game.common.illegal_action")
		if error_key.is_empty():
			error_key = "game.common.illegal_action"
		Net.send(peer_id, NetProtocol.envelope(NetProtocol.T_ACTION_RESULT, {
			"seq": seq, "ok": false, "reason": int(NetProtocol.Reject.ILLEGAL_ACTION),
			"key": key, "error_key": error_key,
		}))
		_emit_rejection(error_key, "peer %d" % peer_id)
		return
	Net.send(peer_id, NetProtocol.envelope(NetProtocol.T_ACTION_RESULT, {"seq": seq, "ok": true, "key": key}))
	_replicate_state()
	state_updated.emit()


## Client-side message handling.
func handle_network_message(peer_id: int, message: Dictionary) -> void:
	var type := NetProtocol.type_of(message)
	match type:
		NetProtocol.T_ACTION:
			# Host side: clients only ever send *intended* actions; the host
			# validates them against its authoritative engine.
			if mode == Mode.ONLINE_HOST:
				handle_remote_action(peer_id, message)
		NetProtocol.T_STATE, NetProtocol.T_PRIVATE_STATE:
			if mode != Mode.ONLINE_CLIENT:
				return
			_apply_snapshot(peer_id, message)
		NetProtocol.T_ACTION_RESULT:
			if mode != Mode.ONLINE_CLIENT:
				return
			if not bool(message.get("ok", false)):
				var error_key := VariantUtil.as_string(message.get("error_key", ""), "game.common.illegal_action")
				if error_key.is_empty():
					error_key = "game.common.illegal_action"
				_emit_rejection(error_key, "")
		NetProtocol.T_RESIGN:
			if mode != Mode.ONLINE_HOST:
				return
			var info: Dictionary = Net.peer_info(peer_id)
			_resign_player(VariantUtil.as_int(info.get("player_index", -1), -1))
		NetProtocol.T_MATCH_END:
			if mode != Mode.ONLINE_CLIENT:
				return
			if not last_public.is_empty():
				var result := VariantUtil.as_dict(message.get("result", {}))
				last_public["finished"] = true
				last_public["result"] = result
				if engine != null:
					engine.restore_state(last_public)
					engine.finished = true
					engine.result = result.duplicate(true)
			session_finished.emit(last_public.get("result", {}))
			state_updated.emit()
		NetProtocol.T_REJECT:
			_emit_rejection(
				NetProtocol.reason_key(VariantUtil.as_int(message.get("reason", 0), 0)),
				VariantUtil.as_string(message.get("detail", ""), "")
			)
		NetProtocol.T_LOBBY_STATE:
			# A client that just created its session asks for the first snapshot.
			if mode == Mode.ONLINE_HOST and bool(message.get("request_state", false)):
				push_state()


func _apply_snapshot(from_peer: int, message: Dictionary) -> void:
	if not Net.is_host_peer(from_peer):
		Log.warn("Session: ignoring state from non-host peer", {"peer": from_peer, "host": Net.host_peer_id})
		return
	if message.has("public"):
		last_public = VariantUtil.dict_copy(message.get("public", {}))
		last_private = VariantUtil.dict_copy(message.get("private", {}))
		last_legal = VariantUtil.array_copy(message.get("legal", []))
		state_seq = VariantUtil.as_int(message.get("seq", state_seq), state_seq)
		if engine != null:
			engine.restore_state(last_public)
			# The snapshot's private part belongs to this client's seat: install
			# it so views and rule logic keep working from the replica. The
			# host never does this - its engine is the authoritative one.
			if local_player >= 0 and not last_private.is_empty():
				engine.adopt_private_view(local_player, last_private)
		private_state_updated.emit()
		state_updated.emit()


# ------------------------------------------------------------------ lifecycle

func resign(player_index: int) -> void:
	if mode == Mode.ONLINE_CLIENT:
		Net.send_to_host(NetProtocol.envelope(NetProtocol.T_RESIGN, {"player": player_index}))
		return
	_resign_player(player_index)


func _resign_player(player_index: int) -> void:
	if engine == null or player_index < 0 or player_index >= engine.player_count():
		return
	engine.players[player_index]["resigned"] = true
	engine.log_event("game.common.player_resigned", {"player": engine.player_name(player_index)}, player_index)
	var remaining: Array[int] = []
	for i: int in range(engine.player_count()):
		if not bool(engine.players[i].get("resigned", false)) and not disconnected_players.has(i):
			remaining.append(i)
	if remaining.size() <= 1:
		engine.finish(remaining[0] if remaining.size() == 1 else -1, "game.common.last_player_standing")
	else:
		if engine.decision_player() == player_index:
			_advance_turn()
		if is_online():
			_replicate_state()
	state_updated.emit()


func handle_peer_left(peer_id: int) -> void:
	if engine == null:
		return
	var info: Dictionary = Net.peer_info(peer_id)
	var player_index := VariantUtil.as_int(info.get("player_index", -1), -1)
	if player_index < 0:
		return
	if not disconnected_players.has(player_index):
		disconnected_players.append(player_index)
	player_connection_changed.emit(player_index, false)
	engine.log_event("net.player_disconnected", {"player": engine.player_name(player_index)}, player_index)
	notice.emit("net.notice_player_left", {"player": engine.player_name(player_index)})
	if mode == Mode.ONLINE_HOST:
		# Hand the disconnected seat to a bot so the match can continue; players
		# who reconnect before their next turn reclaim it (see docs).
		engine.players[player_index]["kind"] = "bot"
		_replicate_state()
	state_updated.emit()


func reclaim_player(peer_id: int, player_index: int) -> void:
	if player_index < 0 or player_index >= engine.players.size() or peer_id < 0:
		# A stale or malformed reconnect request must not corrupt the seating.
		Log.warn("Session: malformed player reclaim", {"peer": peer_id, "player": player_index})
		return
	if disconnected_players.has(player_index):
		disconnected_players.erase(player_index)
	engine.players[player_index]["kind"] = "remote"
	engine.players[player_index]["peer_id"] = peer_id
	player_connection_changed.emit(player_index, true)
	notice.emit("net.notice_player_rejoined", {"player": engine.player_name(player_index)})
	_replicate_state()
	state_updated.emit()


# --------------------------------------------------------------------- bots

func _process(delta: float) -> void:
	if engine == null or engine.finished:
		return
	if mode == Mode.ONLINE_CLIENT:
		return
	if _bot_stalled:
		# Bounded retries (§6.4): a bot that repeatedly cannot act must not
		# spin here forever; the match waits for a human to intervene.
		return
	if not engine.is_bot(engine.decision_player()):
		_bot_fail_streak = 0
		return
	_bot_timer += delta
	if _bot_timer < BOT_THINK_SEC:
		return
	_bot_timer = 0.0
	step_bot()


## Performs one bot decision. Also used by deterministic tests, which call this
## directly instead of waiting for the timer.
func step_bot() -> bool:
	if engine == null or engine.finished:
		return false
	var actor := engine.decision_player()
	if not engine.is_bot(actor):
		return false
	var choice: String = BotDirector.choose_action(engine, actor)
	if choice.is_empty():
		Log.error("Session: bot has no action", {"game": game_id, "player": actor})
		return false
	var outcome := engine.apply_action_by_key(actor, choice)
	if not bool(outcome.get("ok", false)):
		_bot_fail_streak += 1
		Log.error("Session: bot action rejected", {"game": game_id, "key": choice, "error": outcome.get("error_key", ""), "streak": _bot_fail_streak})
		if _bot_fail_streak >= BOT_MAX_FAILS:
			_bot_stalled = true
			# Surfaced on the rejection channel so screens already listening
			# show why the match stopped moving.
			action_rejected.emit(VariantUtil.as_string(outcome.get("error_key", ""), "game.common.illegal_action"), "bot:%d" % actor)
		return false
	_bot_fail_streak = 0
	if is_online():
		_replicate_state()
	return true


## Runs bot turns until a human must act or the match ends (tests, AI-only games).
func run_until_human(max_steps: int = 2000) -> int:
	var steps := 0
	while engine != null and not engine.finished and steps < max_steps:
		if not engine.is_bot(engine.decision_player()):
			break
		if not step_bot():
			break
		steps += 1
	return steps


func _advance_turn() -> void:
	if engine == null:
		return
	engine.turn = (engine.turn + 1) % maxi(1, engine.player_count())
