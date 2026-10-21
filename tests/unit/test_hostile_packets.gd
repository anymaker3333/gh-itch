extends RefCounted
## Hostile-input regression suite.
##
## Every message in this file is one a remote peer could send. The rule the
## whole network layer must obey: a malformed or hostile packet is *rejected*,
## never crashes the receiver. In Godot 4.7 a `String(variant)` or `int(variant)`
## call on the wrong type raises at runtime and aborts the enclosing function,
## so a single hostile packet used to take down a whole match.
##
## These are regression tests for that class of failure, not a description of
## the protocol.

func suite_name() -> String:
	return "hostile packets"


func run(h: TestHarness) -> void:
	_test_engine_restore(h)
	_test_snapshot_apply(h)
	_test_match_end(h)
	_test_action_result(h)
	_test_lobby_chat(h)
	_test_handshake(h)


## A snapshot with a null or wrongly typed field must not raise.
func _test_engine_restore(h: TestHarness) -> void:
	var engine := ChessEngine.new()
	engine.setup({"player_names": ["A", "B"], "player_kinds": ["local", "local"], "seed": 7})
	engine.restore_state({"result": null, "turn": null, "round": null})
	h.equal(engine.result, {}, "a null result restores as an empty dictionary")
	h.equal(engine.turn, 0, "a null turn restores as 0")
	h.equal(engine.round_index, 1, "a null round restores as 1")
	engine.restore_state({"result": "not a dictionary", "players": "not an array", "log": 5})
	h.equal(engine.result, {}, "a wrongly typed result restores as an empty dictionary")
	engine.restore_state({"players": [null, 5, "x"]})
	h.equal(engine.players.size(), 0, "a players array of non-dictionaries is ignored")
	var log_before := engine.move_log.size()
	engine.restore_state({"log": "not an array"})
	h.equal(engine.move_log.size(), log_before, "a wrongly typed log leaves the current log untouched")
	engine.restore_state({})
	h.is_true(not engine.finished, "an empty snapshot restores a running match")


## A snapshot whose "public" payload is not a dictionary must not raise.
func _test_snapshot_apply(h: TestHarness) -> void:
	var session := GameSession.new()
	var engine := ChessEngine.new()
	engine.setup({"player_names": ["A", "B"], "player_kinds": ["local", "local"], "seed": 7})
	session.engine = engine
	session.mode = GameSession.Mode.ONLINE_CLIENT
	session.local_player = 1
	# The client only accepts snapshots from the authoritative host.
	Net.host_peer_id = 7
	session._apply_snapshot(7, {"public": null})
	h.equal(session.last_public, {}, "a null public payload leaves the snapshot empty")
	session._apply_snapshot(7, {"public": "not a dictionary"})
	h.equal(session.last_public, {}, "a wrongly typed public payload leaves the snapshot empty")
	session._apply_snapshot(7, {"public": {"turn": 0}, "private": null, "legal": null, "seq": null})
	h.equal(session.last_private, {}, "a null private payload leaves the private slice empty")
	h.equal(session.last_legal, [], "a null legal payload leaves the action list empty")
	h.equal(session.state_seq, 0, "a null sequence keeps the previous sequence")
	session._apply_snapshot(7, {"public": {"turn": 1}, "private": {"a": 1}, "legal": ["k"]})
	h.equal(session.last_public.get("turn", -1), 1, "a well-formed snapshot is applied")
	h.equal(session.last_private.get("a", 0), 1, "a well-formed private slice is applied")
	h.equal(session.last_legal.size(), 1, "a well-formed action list is applied")
	# A snapshot from a peer that is not the host is ignored.
	session.last_public = {}
	session._apply_snapshot(9, {"public": {"turn": 5}})
	h.equal(session.last_public, {}, "a snapshot from a non-host peer is ignored")
	Net.host_peer_id = 0
	session.free()


## The match-end packet carries a result; a null one must not raise.
func _test_match_end(h: TestHarness) -> void:
	var session := GameSession.new()
	var engine := ChessEngine.new()
	engine.setup({"player_names": ["A", "B"], "player_kinds": ["local", "local"], "seed": 7})
	session.engine = engine
	session.mode = GameSession.Mode.ONLINE_CLIENT
	session.local_player = 1
	session.last_public = {"turn": 0}
	session.handle_network_message(1, {"t": NetProtocol.T_MATCH_END, "result": null})
	h.equal(session.engine.result, {}, "a null match-end result leaves the result empty")
	session.last_public = {"turn": 0}
	session.handle_network_message(1, {"t": NetProtocol.T_MATCH_END, "result": "not a dictionary"})
	h.equal(session.engine.result, {}, "a wrongly typed match-end result leaves the result empty")
	session.free()


## The action-result packet carries an error key; a null one must not raise.
func _test_action_result(h: TestHarness) -> void:
	var session := GameSession.new()
	var engine := ChessEngine.new()
	engine.setup({"player_names": ["A", "B"], "player_kinds": ["local", "local"], "seed": 7})
	session.engine = engine
	session.mode = GameSession.Mode.ONLINE_CLIENT
	var reasons: Array[String] = []
	session.action_rejected.connect(func(reason: String, _detail: String) -> void:
		reasons.append(reason)
	)
	session.handle_network_message(1, {"t": NetProtocol.T_ACTION_RESULT, "ok": false, "error_key": null})
	h.equal(reasons.size(), 1, "a null error key still reports one rejection")
	h.equal(reasons[0], "game.common.illegal_action", "a null error key falls back to the generic reason")
	session.handle_network_message(1, {"t": NetProtocol.T_ACTION_RESULT, "ok": false, "error_key": 42})
	h.equal(reasons.size(), 2, "a numeric error key still reports one rejection")
	h.equal(reasons[1], "game.common.illegal_action", "a numeric error key falls back to the generic reason")
	session.free()


## The lobby chat is the most reachable path: a peer only has to send a chat
## packet, no seat and no match required.
func _test_lobby_chat(h: TestHarness) -> void:
	var chat_name := VariantUtil.as_string({"name": null}.get("name", ""), "?")
	h.equal(chat_name, "?", "a null chat name falls back")
	var chat_body := VariantUtil.as_string({"message": 42}.get("message", ""), "")
	h.equal(chat_body, "", "a numeric chat body falls back")
	h.equal(VariantUtil.as_string({"name": "Bob"}.get("name", ""), "?"), "Bob", "a well-formed chat name is kept")


## The handshake fields are read straight off the wire.
func _test_handshake(h: TestHarness) -> void:
	h.equal(VariantUtil.as_string({"name": null}.get("name", ""), "Player"), "Player",
		"a null peer name falls back")
	h.equal(VariantUtil.as_int({"steam_id": null}.get("steam_id", 0), 0), 0,
		"a null steam id falls back")
	h.equal(VariantUtil.as_int({"protocol": null}.get("protocol", 1), 1), 1,
		"a null protocol version falls back")
	h.equal(VariantUtil.as_string({"language": null}.get("language", ""), ""), "",
		"a null language falls back")
	h.equal(VariantUtil.as_string({"host": null}.get("host", ""), "Host"), "Host",
		"a null host name falls back")
