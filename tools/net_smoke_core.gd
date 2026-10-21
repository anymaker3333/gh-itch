extends RefCounted
## Core of the two-process multiplayer smoke test.
##
## Loaded at runtime by `tools/net_smoke.gd` so that the autoload singletons are
## available. The core exercises the complete online path with **real sockets**
## (nothing is simulated or short-circuited):
##
##   host  : Net.host_local_test -> accept `hello` -> seat 1 -> start match ->
##           apply the client's actions -> replicate states -> finish the match
##   client: Net.join_local_test -> `hello`/`welcome` -> receive `start_match` ->
##           create a client session -> send actions -> resign -> apply the result
##
## Both roles print their own PASS/FAIL line and return their own exit code;
## `tools/run_net_smoke.sh` requires both of them.

## How many of its own moves the client plays before resigning.
const CLIENT_MOVES: int = 2
const HOST_NAME: String = "Smoke Host"
const CLIENT_NAME: String = "Smoke Client"
## Seconds the socket stays open after the verdict, so the packets that were sent
## last (final snapshot, `match_end`, `bye`) reach the other process.
const HOST_CLOSE_GRACE_SEC: float = 1.5
const CLIENT_CLOSE_GRACE_SEC: float = 0.3

var role: String = "host"
var port: int = 47120
var address: String = "127.0.0.1"
## Game under test and how many human seats to open (2 by default: host + one
## client). Games with hidden information also assert that the private slice of
## the replicated snapshot is non-empty when `--expect-private` is passed.
var game_id: String = "chess"
var player_count: int = 2
var expect_private: bool = false

var checks: int = 0
var failures: PackedStringArray = PackedStringArray()
var _done: bool = false
var _exit_code: int = 0
var _phase: String = "boot"
## After the verdict is printed the socket stays open for a moment: closing the
## ENet host immediately would drop the packets still in flight (final snapshot,
## `match_end`, `bye`), and the client would never see the result.
var _closing: bool = false
var _summary_phase: String = ""
var _close_deadline: float = 0.0
var _host_moves: int = 0
var _client_moves: int = 0
var _resigned: bool = false
var _started_at: float = 0.0
var _start_deadline: float = 0.0
var _peer_id: int = 0
var _snapshot_checked: bool = false
var _remote_peers: Array[int] = []
var _remote_infos: Dictionary = {}


func setup(args: PackedStringArray) -> void:
	for index: int in range(args.size()):
		match args[index]:
			"--role":
				if index + 1 < args.size():
					role = String(args[index + 1])
			"--port":
				if index + 1 < args.size():
					port = int(args[index + 1])
			"--address":
				if index + 1 < args.size():
					address = String(args[index + 1])
			"--game":
				if index + 1 < args.size():
					game_id = String(args[index + 1])
			"--players":
				if index + 1 < args.size():
					player_count = maxi(2, int(args[index + 1]))
			"--expect-private":
				expect_private = true
	_started_at = _now()
	Prefs.set_value("profile/display_name", HOST_NAME if role == "host" else CLIENT_NAME)
	Net.message_received.connect(_on_message)
	Net.seat_assigned.connect(_on_seat_assigned)
	Net.transport_error.connect(_on_transport_error)
	print("════════════════════════════════════════════════════════════")
	print(" net smoke  ·  role=%s  ·  %s:%d" % [role, address, port])
	print("════════════════════════════════════════════════════════════")
	if role == "host":
		_start_host()
	else:
		_start_client()


func poll(_delta: float) -> int:
	if _done:
		return 1
	_tick()
	return 1 if _done else 0


func exit_code() -> int:
	return _exit_code


func on_timeout() -> void:
	_check(false, "%s: finished within the time budget (phase=%s)" % [role, _phase])
	_finish()


# ------------------------------------------------------------------ host role

func _start_host() -> void:
	Session.lobby = {
		"lobby_id": 0,
		"visibility": "private",
		"max_players": player_count,
		"game_id": game_id,
		"mode": "local_test",
		"expansions": [],
	}
	_check(Net.host_local_test(port), "host: ENet server listening on port %d" % port)
	_check(Net.role == Net.Role.HOST, "host: transport role is HOST")
	_check(Net.local_peer_id != 0, "host: local peer id assigned (%d)" % Net.local_peer_id)
	_phase = "waiting_hello"
	_start_deadline = _now() + 30.0


func _start_host_match() -> void:
	Session.configure(game_id, player_count)
	var remote_players: Array = []
	var ordered: Array = []
	for pid: int in _remote_peers:
		ordered.append({"peer_id": pid, "info": _remote_infos.get(pid, {})})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int((a.get("info", {}) as Dictionary).get("player_index", 0)) < int((b.get("info", {}) as Dictionary).get("player_index", 0))
	)
	for item: Dictionary in ordered:
		var pid: int = int(item.get("peer_id", 0))
		var info: Dictionary = item.get("info", {}) as Dictionary
		remote_players.append({
			"name": String(info.get("name", "Client")),
			"steam_id": int(info.get("steam_id", 0)),
			"peer_id": pid,
			"kind": "remote",
		})
	var session := Session.start_online_host(remote_players)
	_check(session != null, "host: online session created")
	if session == null:
		_finish()
		return
	session.session_finished.connect(_on_session_finished)
	_check(session.engine.player_count() == player_count, "host: %d seats (host + client)" % player_count)
	_check(session.local_player == 0, "host: local player is seat 0")
	for i: int in range(1, session.engine.player_count()):
		_check(session.engine.players[i].get("kind", "") == "remote", "host: seat %d is a remote seat" % i)
		_check(int(session.engine.players[i].get("peer_id", 0)) > 0, "host: seat %d has a peer" % i)
	_check(session.mode == GameSession.Mode.ONLINE_HOST, "host: session mode is ONLINE_HOST")
	var seat_map: Array = [{"peer_id": Net.local_peer_id, "index": 0, "name": HOST_NAME}]
	for i: int in range(1, session.engine.player_count()):
		seat_map.append({"peer_id": session.peer_for_player(i), "index": i, "name": session.engine.player_name(i)})
	Net.broadcast(NetProtocol.envelope(NetProtocol.T_START_MATCH, {
		"game_id": game_id,
		"seed": session.engine.seed,
		"seats": seat_map,
		"player_count": session.engine.player_count(),
		"config": session.config,
	}))
	session.push_state()
	_check(session.state_seq > 0, "host: first snapshot pushed to the client")
	_phase = "playing"


# ---------------------------------------------------------------- client role

func _start_client() -> void:
	_check(Net.join_local_test(address, port), "client: connecting to %s:%d" % [address, port])
	_check(Net.role == Net.Role.CLIENT, "client: transport role is CLIENT")
	_phase = "connecting"
	_start_deadline = _now() + 30.0


func _on_start_match(message: Dictionary) -> void:
	var seats: Array = message.get("seats", [])
	var local_index := -1
	for seat: Variant in seats:
		if seat is Dictionary and int((seat as Dictionary).get("peer_id", 0)) == Net.local_peer_id:
			local_index = int((seat as Dictionary).get("index", -1))
	_check(local_index >= 1 and local_index < player_count, "client: seat assignment is a valid remote seat (got %d)" % local_index)
	if local_index < 0:
		_finish()
		return
	Session.configure(game_id, int(message.get("player_count", player_count)))
	Session.set_option("seed", int(message.get("seed", 0)))
	var session := Session.start_online_client(game_id, local_index)
	_check(session != null, "client: client session created")
	if session == null:
		_finish()
		return
	session.session_finished.connect(_on_session_finished)
	_check(session.mode == GameSession.Mode.ONLINE_CLIENT, "client: session mode is ONLINE_CLIENT")
	_check(session.local_player == local_index, "client: local player matches the assigned seat")
	Net.send_to_host(NetProtocol.envelope(NetProtocol.T_LOBBY_STATE, {"request_state": true}))
	_phase = "awaiting_state"


# -------------------------------------------------------------------- driving

func _tick() -> void:
	if _closing:
		if _now() >= _close_deadline:
			_closing = false
			_done = true
			Net.close()
		return
	_phase_timers()
	var session := Session.current
	match _phase:
		"playing":
			if session == null or session.engine == null:
				return
			if role == "host":
				_host_tick(session)
			else:
				_client_tick(session)
		"awaiting_state":
			if session != null and not session.last_public.is_empty():
				_phase = "playing"


func _phase_timers() -> void:
	if _phase == "waiting_hello" or _phase == "connecting":
		if _now() > _start_deadline:
			_check(false, "%s: handshake completed before the deadline (phase=%s)" % [role, _phase])
			_finish()
		return
	if _phase == "awaiting_state" and _now() > _start_deadline:
		_check(false, "client: first snapshot arrived before the deadline")
		_finish()


func _host_tick(session: GameSession) -> void:
	var engine := session.engine
	if engine.finished:
		return
	if engine.decision_player() == 0 and not engine.is_bot(0):
		var key := BotDirector.choose_action(engine, 0)
		if not key.is_empty():
			session.submit_action_key(key)
			_host_moves = engine.action_count


func _client_tick(session: GameSession) -> void:
	var engine := session.engine
	if engine.finished:
		_finish()
		return
	var actions: Array = session.available_actions()
	if _client_moves < CLIENT_MOVES:
		if actions.is_empty():
			return
		var key := String((actions[0] as Dictionary).get("key", ""))
		session.submit_action_key(key)
		_client_moves += 1
		return
	if not _resigned:
		session.resign(session.local_player)
		_resigned = true


# -------------------------------------------------------------------- results

func _on_message(peer_id: int, message: Dictionary) -> void:
	match NetProtocol.type_of(message):
		NetProtocol.T_START_MATCH:
			if role == "client":
				_on_start_match(message)
		NetProtocol.T_STATE:
			if role == "client":
				_checks_snapshots(peer_id, message)
		NetProtocol.T_MATCH_END:
			if role == "client":
				_finish()


func _checks_snapshots(peer_id: int, message: Dictionary) -> void:
	if not _snapshot_checked:
		_snapshot_checked = true
		_check(Net.is_host_peer(peer_id), "client: snapshots come from the host peer (%d)" % peer_id)
		_check(message.has("public"), "client: snapshot carries public state")
		_check(message.has("private"), "client: snapshot carries the private slice")
		_check(message.has("legal"), "client: snapshot carries the legal action list")
		var public_state: Dictionary = message.get("public", {})
		_check(String(public_state.get("game", "")) == game_id, "client: snapshot is for %s" % game_id)
		if expect_private:
			_check(not (message.get("private", {}) as Dictionary).is_empty(),
				"client: private slice is non-empty for hidden-information %s" % game_id)


func _on_seat_assigned(peer_id: int, info: Dictionary) -> void:
	if role != "host" or _phase != "waiting_hello":
		return
	var seat := int(info.get("player_index", -1))
	if seat < 1:
		return
	if _remote_peers.has(peer_id):
		return
	_remote_peers.append(peer_id)
	_remote_infos[peer_id] = info
	_check(Net.host_peer_id == Net.local_peer_id, "host: host peer id is the local peer")
	if _remote_peers.size() < player_count - 1:
		return
	_start_host_match()


func _on_transport_error(context: String, detail: String) -> void:
	if _closing:
		# Teardown after the verdict always disturbs the transport; that is not a
		# test failure.
		return
	_check(false, "%s: transport error [%s] %s" % [role, context, detail])


## The authoritative engine finished (host) or the host reported the result
## (client): either way the smoke run is over.
func _on_session_finished(_result: Dictionary) -> void:
	if _phase == "playing" or _phase == "awaiting_state":
		_finish()


func _check(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		print("  ✓ %s" % message)
		return true
	failures.append(message)
	printerr("  ✗ %s" % message)
	return false


func _finish() -> void:
	if _done or _closing:
		return
	_summary_phase = _phase
	var session := Session.current
	if role == "client" and session != null and session.engine != null:
		var engine := session.engine
		_check(engine.finished, "client: match reported as finished")
		_check(engine.winner_index() == 0, "client: the host (seat 0) won (got %d)" % engine.winner_index())
		_check(String(engine.result.get("reason_key", "")) == "game.common.last_player_standing",
			"client: reason is last_player_standing (got '%s')" % String(engine.result.get("reason_key", "")))
		_check(engine.player_count() == player_count, "client: %d seats after the snapshot" % player_count)
		_check(_client_moves == CLIENT_MOVES, "client: sent %d of its own moves (got %d)" % [CLIENT_MOVES, _client_moves])
		_check(_snapshot_checked, "client: received at least one replicated snapshot")
	if role == "host" and session != null and session.engine != null:
		var engine := session.engine
		_check(engine.finished, "host: match finished")
		_check(engine.winner_index() == 0, "host: the host seat won (got %d)" % engine.winner_index())
		_check(String(engine.result.get("reason_key", "")) == "game.common.last_player_standing",
			"host: reason is last_player_standing (got '%s')" % String(engine.result.get("reason_key", "")))
		_check(engine.action_count >= CLIENT_MOVES, "host: applied the client's moves (%d actions)" % engine.action_count)
		var client_logged := 0
		for entry: Variant in engine.move_log:
			if entry is Dictionary and int((entry as Dictionary).get("player", -1)) == 1:
				client_logged += 1
		_check(client_logged >= CLIENT_MOVES, "host: the client's moves appear in the shared log (%d)" % client_logged)
	var stats := Net.stats()
	print("────────────────────────────────────────────────────────────")
	print(" %s summary  ·  game=%s  seats=%d  client_moves=%d  host_moves=%d  snapshots=%d  phase=%s" % [
		role, game_id, player_count, _client_moves, _host_moves, session.state_seq if session != null else 0, _summary_phase,
	])
	print(" transport=%s link=%s peers=%d sent=%d received=%d bytes_out=%d bytes_in=%d" % [
		String(stats.get("transport", "?")), String(stats.get("link", "?")), int(stats.get("peers", 0)),
		int(stats.get("sent", 0)), int(stats.get("received", 0)),
		int(stats.get("bytes_sent", 0)), int(stats.get("bytes_received", 0)),
	])
	if failures.is_empty():
		print(" PASS  %s: %d checks, 0 failures" % [role, checks])
	else:
		print(" FAIL  %s: %d checks, %d failures" % [role, checks, failures.size()])
		for failure: String in failures:
			print("   • %s" % failure)
	print("════════════════════════════════════════════════════════════")
	_exit_code = clampi(failures.size(), 0, 100)
	# Keep the socket open for a moment (see HOST_CLOSE_GRACE_SEC): a transport
	# closed in the same frame drops the packets that are still in flight.
	_closing = true
	_close_deadline = _now() + (HOST_CLOSE_GRACE_SEC if role == "host" else CLIENT_CLOSE_GRACE_SEC)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
