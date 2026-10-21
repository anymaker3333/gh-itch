extends Node
## Authoritative Steam integration manager (autoload `SteamSvc`).
##
## Responsibilities: initialise the Steamworks API exactly once, keep the
## identity, pump callbacks, own the lobby lifecycle (create / search / join /
## invite / leave), publish Game Hub lobby metadata, and shut everything down
## cleanly. It never simulates Steam: if the extension or the client is missing
## the service reports a debuggable state and the rest of the application keeps
## working offline.

signal state_changed(state: int, detail: String)
signal identity_ready(steam_id: int, persona_name: String)
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(response: int)
signal lobby_match_list(lobbies: Array)
signal lobby_data_changed()
signal lobby_members_changed()
signal lobby_left()
signal lobby_message_received(steam_id: int, message: String)
signal invite_received(lobby_id: int, inviter_id: int)
signal friends_updated(friends: Array)
signal relay_status_changed(available: bool, detail: String)
signal steam_error(context: String, detail: String)

enum State { UNAVAILABLE = 0, DISABLED = 1, INITIALIZING = 2, READY = 3, FAILED = 4 }

## Lobby metadata keys. `GAMEHUB_LOBBY_ID_VALUE` identifies Game Hub lobbies so
## unrelated Spacewar (App 480) lobbies are never listed.
const KEY_GAMEHUB: String = "gamehub_id"
const GAMEHUB_LOBBY_ID_VALUE: String = "gh-n3uf"
const KEY_PROTOCOL: String = "protocol_version"
const KEY_GAME_VERSION: String = "game_version"
const KEY_GAME_ID: String = "game_id"
const KEY_GAME_NAME: String = "game_name"
const KEY_GAME_MODE: String = "game_mode"
const KEY_STATUS: String = "status"
const KEY_HOST_NAME: String = "host_name"
const KEY_EXPANSIONS: String = "expansions"
const KEY_MAX_PLAYERS: String = "max_players"
const KEY_TRANSPORT: String = "transport"
const KEY_LANGUAGE: String = "language"

const LOBBY_TYPE_PRIVATE: int = 0
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_TYPE_INVISIBLE: int = 3
const LOBBY_COMPARISON_EQUAL: int = 0

## Steam member-state bits used by `lobby_chat_update`.
const CHAT_STATE_ENTERED: int = 0x0001
const CHAT_STATE_LEFT: int = 0x0002
const CHAT_STATE_DISCONNECTED: int = 0x0004
const CHAT_STATE_KICKED: int = 0x0008
const CHAT_STATE_BANNED: int = 0x0010

const FRIEND_FLAG_IMMEDIATE: int = 4
const FRIEND_FLAG_ALL: int = 0xFFFF

var state: State = State.UNAVAILABLE
var state_detail: String = ""
var gateway: SteamGateway = null

var steam_id: int = 0
var persona_name: String = ""
var app_id: int = 480
var relay_available: bool = false
var relay_detail: String = ""

var lobby_id: int = 0
var lobby_visibility: String = "public"
var lobby_max_members: int = 4
var members: Array[Dictionary] = []
var chat_log: Array[Dictionary] = []
var last_lobby_list: Array[Dictionary] = []

var _pending_lobby_config: Dictionary = {}
var _callbacks_enabled: bool = false


func _ready() -> void:
	# itch.io build: Steamworks is not available on this platform. The service
	# stays in DISABLED state so the rest of the application (and the online
	# screen, which falls back to the local ENet test transport) keeps working.
	_set_state(State.DISABLED, "Steam integration is not available in this build.")
	return


func _process(_delta: float) -> void:
	if state == State.READY and _callbacks_enabled and gateway.supports("run_callbacks"):
		gateway.call_method("run_callbacks")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		shutdown()


# ---------------------------------------------------------------- lifecycle

func _configure_app_id() -> void:
	app_id = int(Prefs.get_value("steam/app_id", 480))
	# The Steamworks SDK reads steam_appid.txt from the working directory when the
	# game is not launched through the Steam client. It is development tooling and
	# must never be shipped (see docs/STEAM_INTEGRATION.md).
	var path := "steam_appid.txt"
	var needs_write := true
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			needs_write = file.get_as_text().strip_edges() != str(app_id)
			file.close()
	if needs_write:
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out != null:
			out.store_string(str(app_id))
			out.close()
			Log.info("SteamSvc: wrote steam_appid.txt", {"app_id": app_id})


func initialise(force: bool = false) -> bool:
	if state == State.READY and not force:
		return true
	if not gateway.available:
		_set_state(State.UNAVAILABLE, gateway.unavailable_reason() if gateway != null else "Steam gateway missing.")
		return false
	_set_state(State.INITIALIZING, "Initialising Steamworks (%d)" % app_id)
	var result: Variant = gateway.call_method("steamInitEx", [app_id, false], {})
	var status := 1
	var verbal := "steamInitEx unavailable"
	if result is Dictionary:
		status = int(result.get("status", 1))
		verbal = String(result.get("verbal", ""))
	state_detail = verbal
	if status != 0:
		_set_state(State.FAILED, verbal)
		Log.error("SteamSvc: initialisation failed", {"status": status, "verbal": verbal, "app_id": app_id})
		return false
	_callbacks_enabled = true
	steam_id = int(gateway.call_method("getSteamID", [], 0))
	persona_name = String(gateway.call_method("getPersonaName", [], ""))
	if persona_name.is_empty():
		persona_name = "Steam User"
	Prefs.set_value("profile/display_name", persona_name)
	_connect_steam_signals()
	_relay_init()
	_set_state(State.READY, "Steamworks active for App %d" % app_id)
	Log.info("SteamSvc: ready", {"steam_id": str(steam_id), "persona": persona_name})
	identity_ready.emit(steam_id, persona_name)
	return true


func shutdown() -> void:
	if gateway == null or not gateway.available:
		return
	if lobby_id != 0:
		leave_lobby()
	if state == State.READY and gateway.supports("steamShutdown"):
		gateway.call_method("steamShutdown")
		Log.info("SteamSvc: shutdown complete")
	_callbacks_enabled = false


func _relay_init() -> void:
	if not gateway.supports("initRelayNetworkAccess"):
		relay_detail = "Steam networking sockets API unavailable in this build."
		relay_status_changed.emit(false, relay_detail)
		return
	gateway.call_method("initRelayNetworkAccess")
	Log.info("SteamSvc: requested relay network access")


func _connect_steam_signals() -> void:
	gateway.connect_signal("lobby_created", _on_lobby_created)
	gateway.connect_signal("lobby_joined", _on_lobby_joined)
	gateway.connect_signal("lobby_match_list", _on_lobby_match_list)
	gateway.connect_signal("lobby_data_update", _on_lobby_data_update)
	gateway.connect_signal("lobby_chat_update", _on_lobby_chat_update)
	gateway.connect_signal("lobby_message", _on_lobby_message)
	gateway.connect_signal("lobby_invite", _on_lobby_invite)
	gateway.connect_signal("join_requested", _on_join_requested)
	gateway.connect_signal("relay_network_status", _on_relay_network_status)
	gateway.connect_signal("avatar_loaded", _on_avatar_loaded)
	gateway.connect_signal("persona_state_change", _on_persona_state_change)


func _set_state(new_state: State, detail: String) -> void:
	if state == new_state and state_detail == detail:
		return
	state = new_state
	state_detail = detail
	Log.info("SteamSvc: state", {"state": state_name(), "detail": detail})
	state_changed.emit(int(state), detail)


func state_name() -> String:
	match state:
		State.READY:
			return "READY"
		State.INITIALIZING:
			return "INITIALIZING"
		State.DISABLED:
			return "DISABLED"
		State.FAILED:
			return "FAILED"
		_:
			return "UNAVAILABLE"


func is_ready() -> bool:
	return state == State.READY


func status_text() -> String:
	match state:
		State.READY:
			return Loc.t("steam.status_ready", {"name": persona_name})
		State.INITIALIZING:
			return Loc.t("steam.status_initialising")
		State.DISABLED:
			return Loc.t("steam.status_disabled")
		State.FAILED:
			return Loc.t("steam.status_failed")
		_:
			return Loc.t("steam.status_unavailable")


# ------------------------------------------------------------------ identity

func display_name() -> String:
	if is_ready() and not persona_name.is_empty():
		return persona_name
	return Prefs.profile_name()


func steam_id_string() -> String:
	return "" if steam_id == 0 else str(steam_id)


func own_avatar_texture() -> Texture2D:
	return _avatars.get(steam_id, null)


var _avatars: Dictionary = {}


func friend_list() -> Array[Dictionary]:
	var friends: Array[Dictionary] = []
	if not is_ready():
		return friends
	var count := int(gateway.call_method("getFriendCount", [FRIEND_FLAG_IMMEDIATE], 0))
	for i: int in range(count):
		var friend_id := int(gateway.call_method("getFriendByIndex", [i, FRIEND_FLAG_IMMEDIATE], 0))
		if friend_id == 0:
			continue
		friends.append({
			"steam_id": friend_id,
			"name": String(gateway.call_method("getFriendPersonaName", [friend_id], "Unknown")),
		})
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	friends_updated.emit(friends)
	return friends


# -------------------------------------------------------------------- lobbies

func create_lobby(visibility: String, max_members: int, metadata: Dictionary) -> void:
	if not is_ready():
		steam_error.emit("lobby_create", Loc.t("steam.error_not_ready"))
		return
	if lobby_id != 0:
		leave_lobby()
	lobby_visibility = visibility
	lobby_max_members = clampi(max_members, 2, 16)
	_pending_lobby_config = metadata.duplicate(true)
	var lobby_type := LOBBY_TYPE_PUBLIC
	match visibility:
		"private":
			lobby_type = LOBBY_TYPE_PRIVATE
		"friends":
			lobby_type = LOBBY_TYPE_FRIENDS_ONLY
		"invisible":
			lobby_type = LOBBY_TYPE_INVISIBLE
	steam_error.emit("lobby_create", "")
	Log.info("SteamSvc: creating lobby", {"visibility": visibility, "max": lobby_max_members})
	gateway.call_method("createLobby", [lobby_type, lobby_max_members])


func refresh_lobby_list(max_results: int = 50) -> void:
	if not is_ready():
		steam_error.emit("lobby_search", Loc.t("steam.error_not_ready"))
		return
	gateway.call_method("addRequestLobbyListStringFilter", [KEY_GAMEHUB, GAMEHUB_LOBBY_ID_VALUE, LOBBY_COMPARISON_EQUAL])
	gateway.call_method("addRequestLobbyListNumericalFilter", [KEY_PROTOCOL, int(Prefs.get_value("net/protocol_version", 1)), LOBBY_COMPARISON_EQUAL])
	gateway.call_method("addRequestLobbyListResultCountFilter", [max_results])
	gateway.call_method("requestLobbyList")
	Log.info("SteamSvc: lobby list requested")


func join_lobby(id: int) -> void:
	if not is_ready():
		steam_error.emit("lobby_join", Loc.t("steam.error_not_ready"))
		return
	if lobby_id != 0 and lobby_id != id:
		leave_lobby()
	Log.info("SteamSvc: joining lobby", {"lobby": id})
	gateway.call_method("joinLobby", [id])


func leave_lobby() -> void:
	if lobby_id == 0:
		return
	var id := lobby_id
	Log.info("SteamSvc: leaving lobby", {"lobby": id})
	gateway.call_method("leaveLobby", [id])
	lobby_id = 0
	members.clear()
	chat_log.clear()
	lobby_left.emit()
	lobby_members_changed.emit()


func set_lobby_metadata(key: String, value: String) -> bool:
	if lobby_id == 0:
		return false
	var ok := bool(gateway.call_method("setLobbyData", [lobby_id, key, value], false))
	if not ok:
		Log.warn("SteamSvc: setLobbyData failed", {"key": key, "value": value})
	return ok


func publish_lobby_state(state_value: String, extra: Dictionary = {}) -> void:
	if lobby_id == 0:
		return
	set_lobby_metadata(KEY_STATUS, state_value)
	for key: Variant in extra:
		set_lobby_metadata(String(key), str(extra[key]))


func lobby_metadata(key: String) -> String:
	if lobby_id == 0:
		return ""
	return String(gateway.call_method("getLobbyData", [lobby_id, key], ""))


func invite_friend(friend_steam_id: int) -> bool:
	if lobby_id == 0:
		return false
	var ok := bool(gateway.call_method("inviteUserToLobby", [lobby_id, friend_steam_id], false))
	if not ok:
		steam_error.emit("lobby_invite", Loc.t("steam.error_invite_failed"))
	return ok


func open_invite_overlay() -> void:
	if lobby_id == 0:
		return
	if gateway.supports("activateGameOverlayInviteDialog"):
		gateway.call_method("activateGameOverlayInviteDialog", [lobby_id])
	else:
		steam_error.emit("overlay", Loc.t("steam.error_overlay_unavailable"))


func send_lobby_chat(message: String) -> void:
	if lobby_id == 0 or message.strip_edges().is_empty():
		return
	gateway.call_method("sendLobbyChatMsg", [lobby_id, message.substr(0, 400)])


func host_steam_id() -> int:
	if lobby_id == 0:
		return 0
	return int(gateway.call_method("getLobbyOwner", [lobby_id], 0))


func is_host() -> bool:
	return is_ready() and lobby_id != 0 and host_steam_id() == steam_id


func refresh_members() -> void:
	members.clear()
	if not is_ready() or lobby_id == 0:
		lobby_members_changed.emit()
		return
	var count := int(gateway.call_method("getNumLobbyMembers", [lobby_id], 0))
	var owner := host_steam_id()
	for i: int in range(count):
		var member_id := int(gateway.call_method("getLobbyMemberByIndex", [lobby_id, i], 0))
		if member_id == 0:
			continue
		var name := String(gateway.call_method("getLobbyMemberData", [lobby_id, member_id, "player_name"], ""))
		if name.is_empty():
			name = String(gateway.call_method("getFriendPersonaName", [member_id], "Steam user"))
		members.append({
			"steam_id": member_id,
			"name": name,
			"is_host": member_id == owner,
			"is_local": member_id == steam_id,
			"ready": String(gateway.call_method("getLobbyMemberData", [lobby_id, member_id, "ready"], "")) == "1",
			"avatar": _avatars.get(member_id, null),
		})
	lobby_members_changed.emit()


# ----------------------------------------------------------------- callbacks

func _on_lobby_created(connect_result: int, id: int) -> void:
	if connect_result != 1:
		Log.error("SteamSvc: lobby creation failed", {"result": connect_result})
		steam_error.emit("lobby_create", Loc.t("steam.error_lobby_create_failed"))
		return
	lobby_id = id
	Log.info("SteamSvc: lobby created", {"lobby": id})
	# Lobby metadata is written after the lobby exists; only the host may do this.
	set_lobby_metadata(KEY_GAMEHUB, GAMEHUB_LOBBY_ID_VALUE)
	set_lobby_metadata(KEY_PROTOCOL, str(int(Prefs.get_value("net/protocol_version", 1))))
	set_lobby_metadata(KEY_GAME_VERSION, String(ProjectSettings.get_setting("application/config/version", "0.0.0")))
	set_lobby_metadata(KEY_HOST_NAME, display_name())
	set_lobby_metadata(KEY_MAX_PLAYERS, str(lobby_max_members))
	set_lobby_metadata(KEY_LANGUAGE, Loc.current_locale)
	for key: Variant in _pending_lobby_config:
		set_lobby_metadata(String(key), str(_pending_lobby_config[key]))
	_pending_lobby_config.clear()
	gateway.call_method("setLobbyJoinable", [lobby_id, true])
	gateway.call_method("setLobbyMemberLimit", [lobby_id, lobby_max_members])
	set_member_data("player_name", display_name())
	refresh_members()
	lobby_created.emit(lobby_id)
	lobby_joined.emit(lobby_id)


func _on_lobby_joined(id: int, permissions: int, locked: bool, response: int) -> void:
	if response != 1:
		Log.error("SteamSvc: lobby join failed", {"lobby": id, "response": response, "permissions": permissions})
		lobby_join_failed.emit(response)
		steam_error.emit("lobby_join", Loc.t("steam.error_lobby_join_failed", {"code": response}))
		return
	lobby_id = id
	set_member_data("player_name", display_name())
	Log.info("SteamSvc: lobby joined", {"lobby": id, "locked": locked})
	refresh_members()
	lobby_joined.emit(id)


func _on_lobby_match_list(lobbies: Array) -> void:
	last_lobby_list.clear()
	for raw: Variant in lobbies:
		if not (raw is Dictionary):
			continue
		var id := int(raw.get("lobby_id", raw.get("lobby", 0)))
		if id == 0:
			continue
		last_lobby_list.append({
			"lobby_id": id,
			"game_id": _lobby_key(raw, KEY_GAME_ID),
			"game_name": _lobby_key(raw, KEY_GAME_NAME),
			"mode": _lobby_key(raw, KEY_GAME_MODE),
			"status": _lobby_key(raw, KEY_STATUS),
			"host": _lobby_key(raw, KEY_HOST_NAME),
			"members": int(raw.get("members", 0)),
			"max_members": int(_lobby_key(raw, KEY_MAX_PLAYERS).to_int()),
			"language": _lobby_key(raw, KEY_LANGUAGE),
			"expansions": _lobby_key(raw, KEY_EXPANSIONS),
			"protocol": int(_lobby_key(raw, KEY_PROTOCOL).to_int()),
		})
	Log.info("SteamSvc: lobby list received", {"count": last_lobby_list.size()})
	lobby_match_list.emit(last_lobby_list)


func _lobby_key(raw: Dictionary, key: String) -> String:
	for field: Variant in raw:
		if String(field).to_lower() == key:
			return String(raw[field])
	return ""


func _on_lobby_data_update(success: int, _id: int, _member_id: int) -> void:
	if success != 1:
		Log.warn("SteamSvc: lobby data update reported failure", {"success": success})
	lobby_data_changed.emit()
	refresh_members()


func _on_lobby_chat_update(_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	var label := "update"
	if chat_state & CHAT_STATE_ENTERED:
		label = "entered"
	elif chat_state & CHAT_STATE_LEFT:
		label = "left"
	elif chat_state & CHAT_STATE_DISCONNECTED:
		label = "disconnected"
	elif chat_state & CHAT_STATE_KICKED:
		label = "kicked"
	Log.info("SteamSvc: lobby membership changed", {"member": str(changed_id), "by": str(making_change_id), "change": label})
	refresh_members()


func _on_lobby_message(id: int, user: int, message: String, chat_type: int) -> void:
	if id != lobby_id:
		return
	chat_log.append({"steam_id": user, "name": member_name(user), "message": message, "type": chat_type})
	if chat_log.size() > 200:
		chat_log.pop_front()
	lobby_message_received.emit(user, message)


func member_name(member_steam_id: int) -> String:
	for member: Dictionary in members:
		if int(member.steam_id) == member_steam_id:
			return String(member.name)
	if member_steam_id == steam_id:
		return display_name()
	return String(gateway.call_method("getFriendPersonaName", [member_steam_id], "Steam user"))


func set_member_data(key: String, value: String) -> void:
	if lobby_id != 0:
		gateway.call_method("setLobbyMemberData", [lobby_id, key, value])


func _on_lobby_invite(inviter: int, lobby: int, _game: int) -> void:
	Log.info("SteamSvc: invite received", {"inviter": str(inviter), "lobby": str(lobby)})
	invite_received.emit(lobby, inviter)


func _on_join_requested(lobby: int, _user: int) -> void:
	Log.info("SteamSvc: join requested through Steam", {"lobby": str(lobby)})
	join_lobby(lobby)


func _on_relay_network_status(available: int, ping_measurement: int, available_config: int, available_relay: int, debug_message: String) -> void:
	relay_available = available == 1 and available_relay == 1
	relay_detail = "availability=%d relay=%d config=%d ping=%d %s" % [available, available_relay, available_config, ping_measurement, debug_message]
	Log.info("SteamSvc: relay status", {"available": relay_available, "detail": relay_detail})
	relay_status_changed.emit(relay_available, relay_detail)


func _on_avatar_loaded(avatar_id: int, size: int, data: PackedByteArray) -> void:
	var image := Image.new()
	var err := OK
	if size == 0:
		err = image.load_png_from_buffer(data)
	else:
		err = image.load_jpg_from_buffer(data)
	if err != OK:
		return
	_avatars[avatar_id] = ImageTexture.create_from_image(image)
	refresh_members()


func _on_persona_state_change(user: int, _flags: int) -> void:
	if user == steam_id:
		var name_now := String(gateway.call_method("getPersonaName", [], persona_name))
		if name_now != persona_name:
			persona_name = name_now
			identity_ready.emit(steam_id, persona_name)
