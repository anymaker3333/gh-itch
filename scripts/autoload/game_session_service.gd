extends Node
## Session lifecycle service (autoload `Session`).
##
## Owns the currently running [GameSession], the pending configuration for the
## next match (game, players, options, mode) and the online lobby context. The UI
## talks to this service only, so "start a game" means the same thing from the
## library, the setup screen and the online lobby.

signal session_started(session: GameSession)
signal session_ended(result: Dictionary)
signal pending_config_changed()
signal session_error(message_key: String, args: Dictionary)

const ENGINE_SCRIPTS: Dictionary = {
	"citadels": "res://scripts/games/citadels/citadels_engine.gd",
	"codenames": "res://scripts/games/codenames/codenames_engine.gd",
	"dany": "res://scripts/games/dany/dany_engine.gd",
	"spyfall": "res://scripts/games/spyfall/spyfall_engine.gd",
	"chess": "res://scripts/games/chess/chess_engine.gd",
	"durak": "res://scripts/games/durak/durak_engine.gd",
	"bridge": "res://scripts/games/bridge/bridge_engine.gd",
	"king": "res://scripts/games/king/king_engine.gd",
	"monopoly": "res://scripts/games/monopoly/monopoly_engine.gd",
	"ticket_to_ride_europe": "res://scripts/games/ticket_to_ride/ticket_to_ride_engine.gd",
	"coup": "res://scripts/games/coup/coup_engine.gd",
	"splendor": "res://scripts/games/splendor/splendor_engine.gd",
	"star_realms": "res://scripts/games/star_realms/star_realms_engine.gd",
}

var current: GameSession = null

## Configuration for the next match, filled by the setup screen / lobby screen.
var pending: Dictionary = {
	"game_id": "",
	"player_count": 2,
	"names": [],
	"kinds": [],
	"options": {},
	"seed": 0,
	"mode": GameSession.Mode.LOCAL_HOTSEAT,
}

## Online context (mirrors the Steam lobby for the lobby screen).
var lobby: Dictionary = {
	"lobby_id": 0,
	"visibility": "public",
	"max_players": 4,
	"game_id": "",
	"mode": "hotseat",
	"expansions": [],
}


func _ready() -> void:
	Net.message_received.connect(_on_net_message)
	Net.peer_unregistered.connect(_on_peer_unregistered)
	Net.transport_error.connect(_on_transport_error)


# ------------------------------------------------------------ configuration

func configure(game_id: String, player_count: int, options: Dictionary = {}) -> void:
	var entry := Catalog.get_entry(game_id)
	if entry == null:
		session_error.emit("setup.error_unknown_game", {})
		return
	pending["game_id"] = game_id
	pending["player_count"] = clampi(player_count, entry.min_players, entry.max_players)
	pending["options"] = options.duplicate(true)
	_ensure_player_slots()
	pending_config_changed.emit()


func set_player_name(index: int, name: String) -> void:
	_ensure_player_slots()
	if index >= 0 and index < VariantUtil.as_int(pending["player_count"], 0):
		var names: Array = pending["names"]
		names[index] = name
		pending_config_changed.emit()


func set_player_kind(index: int, kind: String) -> void:
	_ensure_player_slots()
	if index >= 0 and index < VariantUtil.as_int(pending["player_count"], 0):
		var kinds: Array = pending["kinds"]
		kinds[index] = kind
		pending_config_changed.emit()


func set_option(key: String, value: Variant) -> void:
	var options: Dictionary = pending["options"]
	options[key] = value
	pending["options"] = options
	pending_config_changed.emit()


func option(key: String, default: Variant = null) -> Variant:
	return VariantUtil.as_dict(pending.get("options", {})).get(key, default)


func pending_names() -> Array:
	_ensure_player_slots()
	return pending["names"]


func pending_kinds() -> Array:
	_ensure_player_slots()
	return pending["kinds"]


func _ensure_player_slots() -> void:
	var count := VariantUtil.as_int(pending["player_count"], 0)
	var names: Array = pending["names"]
	var kinds: Array = pending["kinds"]
	var base_name := Prefs.profile_name()
	while names.size() < count:
		names.append(Loc.t("player.default_number", {"number": names.size() + 1}))
	while kinds.size() < count:
		kinds.append("local")
	names.resize(count)
	kinds.resize(count)
	names[0] = base_name
	pending["names"] = names
	pending["kinds"] = kinds


## Turns the pending configuration into a running session.
func start_local_session(mode: GameSession.Mode = GameSession.Mode.LOCAL_HOTSEAT) -> GameSession:
	var game_id := String(pending["game_id"])
	var engine := create_engine(game_id)
	if engine == null:
		session_error.emit("setup.error_engine_unavailable", {"game": game_id})
		return null
	_ensure_player_slots()
	var names: Array = pending["names"].duplicate()
	var kinds: Array = pending["kinds"].duplicate()
	if mode == GameSession.Mode.SOLO_AI:
		for i: int in range(1, kinds.size()):
			kinds[i] = "bot"
	var options: Dictionary = VariantUtil.dict_copy(pending.get("options", {}))
	options["player_names"] = names
	options["player_kinds"] = kinds
	options["seed"] = VariantUtil.as_int(options.get("seed", pending["seed"]), VariantUtil.as_int(pending["seed"], 0))
	_end_session(false)
	var session := GameSession.new()
	add_child(session)
	session.start(engine, mode, options, pending.duplicate(true))
	current = session
	Prefs.record_recent(game_id)
	Log.info("Session: local match created", {"game": game_id, "mode": session.mode_name()})
	session_started.emit(session)
	return session


## Host side of an online match: seat 0 is the local host, the rest are remote
## players supplied by the lobby (or bots filling unused seats).
func start_online_host(remote_players: Array) -> GameSession:
	var game_id := String(pending["game_id"])
	var engine := create_engine(game_id)
	if engine == null:
		session_error.emit("setup.error_engine_unavailable", {"game": game_id})
		return null
	var names: Array = [Prefs.profile_name()]
	var kinds: Array = ["local"]
	var peers: Array = [0]
	for entry: Variant in remote_players:
		var data := VariantUtil.as_dict(entry)
		names.append(VariantUtil.as_string(data.get("name", ""), Loc.t("player.default")))
		kinds.append(VariantUtil.as_string(data.get("kind", ""), "remote"))
		peers.append(VariantUtil.as_int(data.get("peer_id", 0), 0))
	var options: Dictionary = VariantUtil.dict_copy(pending.get("options", {}))
	options["player_names"] = names
	options["player_kinds"] = kinds
	options["seed"] = VariantUtil.as_int(options.get("seed", pending["seed"]), VariantUtil.as_int(pending["seed"], 0))
	_end_session(false)
	var session := GameSession.new()
	add_child(session)
	session.start(engine, GameSession.Mode.ONLINE_HOST, options, pending.duplicate(true))
	for i: int in range(engine.player_count()):
		engine.players[i]["peer_id"] = VariantUtil.as_int(peers[i], 0)
		if i > 0:
			engine.players[i]["steam_id"] = VariantUtil.as_int(
				VariantUtil.as_dict(remote_players[i - 1]).get("steam_id", 0), 0)
	current = session
	Prefs.record_recent(game_id)
	Log.info("Session: online host match created", {"game": game_id, "seats": engine.player_count()})
	session_started.emit(session)
	return session


## Client side of an online match: the host owns the engine; we keep a local
## instance purely as a rendering model fed by snapshots.
func start_online_client(game_id: String, local_index: int = 2) -> GameSession:
	var engine := create_engine(game_id)
	if engine == null:
		session_error.emit("setup.error_engine_unavailable", {"game": game_id})
		return null
	_end_session(false)
	var session := GameSession.new()
	add_child(session)
	session.mode = GameSession.Mode.ONLINE_CLIENT
	session.engine = engine
	session.game_id = game_id
	session.local_player = local_index
	session.engine.players = []
	current = session
	Prefs.record_recent(game_id)
	Log.info("Session: online client created", {"game": game_id, "local_index": local_index})
	session_started.emit(session)
	return session


func create_engine(game_id: String) -> GameEngine:
	var path := String(ENGINE_SCRIPTS.get(game_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		Log.error("Session: no engine registered", {"game": game_id, "path": path})
		return null
	var script := load(path) as GDScript
	if script == null:
		Log.error("Session: engine script failed to load", {"path": path})
		return null
	var instance: Variant = script.new()
	if not (instance is GameEngine):
		Log.error("Session: engine script is not a GameEngine", {"path": path})
		return null
	return instance


func engine_available(game_id: String) -> bool:
	var path := String(ENGINE_SCRIPTS.get(game_id, ""))
	return not path.is_empty() and ResourceLoader.exists(path)


func end_session(emit_result: bool = true) -> void:
	_end_session(emit_result)


func _end_session(emit_result: bool) -> void:
	if current == null:
		return
	var result: Dictionary = current.engine.result.duplicate(true) if current.engine != null else {}
	var session := current
	current = null
	session.stop()
	if is_instance_valid(session):
		session.queue_free()
	if emit_result and not result.is_empty():
		session_ended.emit(result)


# -------------------------------------------------------------- net plumbing

func _on_net_message(peer_id: int, message: Dictionary) -> void:
	if current == null:
		return
	current.handle_network_message(peer_id, message)


func _on_peer_unregistered(peer_id: int, _info: Dictionary) -> void:
	if current == null or not current.is_online():
		return
	if peer_id == 0:
		return
	current.handle_peer_left(peer_id)


func _on_transport_error(context: String, detail: String) -> void:
	if detail.is_empty():
		return
	Log.warn("Session: transport error", {"context": context, "detail": detail})
	session_error.emit("net.transport_error", {"detail": detail})
