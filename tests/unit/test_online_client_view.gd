extends RefCounted
## Online client replica contract (Wave A §6.3 regression).
##
## For every game: a host plays a couple of actions, then the client receives
## exactly what the host's replication would send — the public snapshot plus
## its OWN seat's tailored private slice and legal list (the T_STATE payload).
## The client's engine replica must then render the seat's data as the host
## does through [GameView.private_info], answer its own private_state from
## authoritative structures, and expose nothing of the other seats.

const SEED: int = 20251103
const TEST_PEER: int = 707


func suite_name() -> String:
	return "online client view (13 games)"


func run(h: TestHarness) -> void:
	for entry: Variant in Catalog.games():
		if entry is GameEntry:
			_check_entry(h, entry)
	Net.set_host_peer(0)


func _check_entry(h: TestHarness, entry: GameEntry) -> void:
	var game_id := entry.id
	# The host: a hotseat match driven a couple of steps.
	Session.configure(game_id, entry.min_players)
	Session.set_option("seed", SEED)
	var host := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	if host == null:
		h.check(false, "%s: host session starts" % game_id)
		return
	var host_engine: GameEngine = host.engine
	for step: int in range(2):
		if host_engine.finished:
			break
		if not EngineHarness.step_first_legal(host_engine):
			break
	# Host replication payload for seat 1: public + that seat's slice + legal.
	var legal: Array = []
	var slice: Dictionary = host_engine.private_state(1)
	if host_engine.decision_player() == 1 and not host_engine.finished:
		legal = host_engine.legal_actions(1)
	var payload: Dictionary = {
		"seq": 5,
		"game": game_id,
		"public": host_engine.public_state(),
		"private": slice,
		"legal": legal,
	}
	# The client: rendering model only, fed by the replicated state.
	var client := Session.start_online_client(game_id, 1)
	if client == null:
		h.check(false, "%s: client session starts" % game_id)
		Session.end_session(false)
		return
	h.is_true(client.mode == GameSession.Mode.ONLINE_CLIENT, "%s: client mode is ONLINE_CLIENT" % game_id)
	h.equal(int(client.local_player), 1, "%s: client seat is 1" % game_id)
	Net.set_host_peer(TEST_PEER)
	client._apply_snapshot(TEST_PEER, NetProtocol.envelope(NetProtocol.T_STATE, payload))
	_check_client(h, client, game_id, payload, slice)
	# The message shape deduplicates nothing: a second identical snapshot is
	# idempotent and keeps the replica consistent.
	client._apply_snapshot(TEST_PEER, NetProtocol.envelope(NetProtocol.T_STATE, payload))
	_check_client(h, client, game_id, payload, slice)
	# A state from a NON-host peer must be ignored (the guard before install):
	_pre_check_snapshot_guard(h, client, game_id, payload)
	# End of the test: drop the session and free nothing owned by it.
	Session.end_session(false)


func _pre_check_snapshot_guard(h: TestHarness, client: GameSession, game_id: String, payload: Dictionary) -> void:
	var seq_before := client.state_seq
	Net.set_host_peer(TEST_PEER + 1)
	client._apply_snapshot(TEST_PEER + 1, NetProtocol.envelope(NetProtocol.T_STATE, payload))
	h.equal(client.state_seq, seq_before, "%s: a snapshot from a non-host peer is ignored" % game_id)
	Net.set_host_peer(TEST_PEER)


func _check_client(h: TestHarness, client: GameSession, game_id: String, payload: Dictionary, slice: Dictionary) -> void:
	var engine: GameEngine = client.engine
	h.equal(client.state_seq, int(payload.get("seq", 0)), "%s: the snapshot sequence advances" % game_id)
	h.is_true(not client.last_public.is_empty(), "%s: the public snapshot is stored" % game_id)
	h.equal(client.last_private, slice, "%s: the client stores exactly seat 1's tailored slice" % game_id)
	h.equal(_keys_of(client.available_actions()), _keys_of(payload.get("legal", [])),
		"%s: the client's available actions are the host's legal list" % game_id)
	h.is_true(engine.players.size() == _expected_players(game_id), "%s: the replica restores the seating" % game_id)
	# The replica answers its OWN seat like the host would (structured adopt).
	if not slice.is_empty():
		h.equal(engine.private_state(1), slice, "%s: the replica's own private state matches the host slice" % game_id)
	# ... and never leaks other seats' private data.
	h.is_true(not engine.public_state().has("hands"), "%s: the replica's public state never carries a hands list" % game_id)
	# The GameView helper is the authorized access point for views.
	var view: GameView = _mount_view(h, game_id)
	if view == null:
		return
	view.configure(client)
	view.refresh_board()
	h.equal(view.private_info(), client.last_private, "%s: views see the tailored snapshot slice (§6.3 helper)" % game_id)
	h.greater(float(view.get_child_count()), 0.0, "%s: the client view renders content" % game_id)
	view.free()


func _expected_players(game_id: String) -> int:
	for entry: Variant in Catalog.games():
		if entry is GameEntry and entry.id == game_id:
			return entry.min_players
	return 0


func _mount_view(h: TestHarness, game_id: String) -> GameView:
	var path := String(_view_scripts().get(game_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		h.check(false, "%s: a view script is registered in game_screen" % game_id)
		return null
	var script := load(path) as GDScript
	h.is_true(script != null and script.can_instantiate(), "%s: the view script compiles" % game_id)
	if script == null or not script.can_instantiate():
		return null
	var instance: Variant = script.new()
	if not (instance is GameView):
		if instance is Node:
			(instance as Node).free()
		h.check(false, "%s: the view extends GameView" % game_id)
		return null
	return instance


func _view_scripts() -> Dictionary:
	var script := load("res://scripts/ui/screens/game_screen.gd") as GDScript
	if script == null:
		return {}
	return script.get_script_constant_map().get("VIEW_SCRIPTS", {})


func _keys_of(actions: Array) -> Array:
	var out: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			out.append(String((action as Dictionary).get("key", "")))
	return out
