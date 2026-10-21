extends Node
## Network transport and link state machine (autoload `Net`).
##
## Owns the [MultiplayerPeer] used for gameplay, the peer registry and the
## explicit link state machine:
##
##   OFFLINE -> STEAM_READY -> LOBBY_JOINED -> CONNECTING -> CONNECTED
##           -> MATCH_RUNNING -> DISCONNECTING -> OFFLINE
##
## Gameplay messages are application-level dictionaries exchanged through
## [method MultiplayerPeer.put_packet]; the host remains authoritative (see
## scripts/core/game_session.gd). The Steam transport uses
## [code]SteamMultiplayerPeer[/code] from the GodotSteam GDExtension, which
## tunnels through Steam Networking Sockets (with relay). A local ENet transport
## exists **only** for automated tests and LAN debugging and is labelled as such
## in the UI - it is never presented as Steam networking.

signal link_state_changed(state: int, detail: String)
signal peer_registered(peer_id: int, info: Dictionary)
## Emitted when a connected peer gains a player seat (after the `hello`/`welcome`
## handshake). `peer_registered` only fires on the first sighting, when the peer
## is usually still seatless, so lobby code must follow this signal to react to
## seats being handed out.
signal seat_assigned(peer_id: int, info: Dictionary)
signal peer_unregistered(peer_id: int, info: Dictionary)
signal message_received(peer_id: int, message: Dictionary)
signal transport_error(context: String, detail: String)
signal stats_changed()

enum Transport { NONE = 0, STEAM = 1, LOCAL_TEST = 2, WEBSOCKET = 3 }
enum Link { OFFLINE = 0, STEAM_READY = 1, LOBBY_JOINED = 2, CONNECTING = 3, CONNECTED = 4, MATCH_RUNNING = 5, DISCONNECTING = 6 }
enum Role { NONE = 0, HOST = 1, CLIENT = 2 }

const HEARTBEAT_INTERVAL_SEC: float = 2.5
const PEER_TIMEOUT_SEC: float = 15.0
const TEST_PORT_MIN: int = 47000
const TEST_PORT_MAX: int = 47999

var transport: Transport = Transport.NONE
var link: Link = Link.OFFLINE
var role: Role = Role.NONE
var peer: MultiplayerPeer = null
var local_peer_id: int = 0

## Peer id of the authoritative host of the current transport. Under ENet this is
## always 1; under Steam it is the host's SteamID, which the client learns from
## the `welcome` message. Game code never hardcodes a peer id - it asks here.
var host_peer_id: int = 0

## peer_id -> { "steam_id": int, "name": String, "player_index": int, "last_seen": float, "rtt_ms": int }
var peers: Dictionary = {}

var _heartbeat_timer: float = 0.0
var _packets_sent: int = 0
var _packets_received: int = 0
var _bytes_sent: int = 0
var _bytes_received: int = 0
var _link_detail: String = ""
var cached_stats: Dictionary = {}


func _ready() -> void:
	SteamSvc.state_changed.connect(_on_steam_state)


func _process(delta: float) -> void:
	if peer == null:
		return
	_poll_packets()
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL_SEC:
		_heartbeat_timer = 0.0
		_send_heartbeats()
		_check_peer_timeouts()


# -------------------------------------------------------------- link control

func _on_steam_state(state: int, detail: String) -> void:
	if link == Link.MATCH_RUNNING or link == Link.CONNECTED:
		return
	if state == SteamSvc.State.READY:
		if link == Link.OFFLINE:
			_set_link(Link.STEAM_READY, detail)
	else:
		if link == Link.STEAM_READY or link == Link.LOBBY_JOINED:
			_set_link(Link.OFFLINE, detail)


func _set_link(new_link: Link, detail: String = "") -> void:
	if link == new_link and _link_detail == detail:
		return
	link = new_link
	_link_detail = detail
	Log.info("Net: link state", {"state": link_name(), "detail": detail, "transport": transport_name()})
	link_state_changed.emit(int(link), detail)


func link_name() -> String:
	match link:
		Link.STEAM_READY:
			return "STEAM_READY"
		Link.LOBBY_JOINED:
			return "LOBBY_JOINED"
		Link.CONNECTING:
			return "CONNECTING"
		Link.CONNECTED:
			return "CONNECTED"
		Link.MATCH_RUNNING:
			return "MATCH_RUNNING"
		Link.DISCONNECTING:
			return "DISCONNECTING"
		_:
			return "OFFLINE"


func transport_name() -> String:
	match transport:
		Transport.STEAM:
			return "steam"
		Transport.LOCAL_TEST:
			return "local_test"
		Transport.WEBSOCKET:
			return "websocket"
		_:
			return "none"

func link_detail() -> String:
	return _link_detail


func notify_lobby_joined(lobby_id: int) -> void:
	if link == Link.MATCH_RUNNING:
		return
	_set_link(Link.LOBBY_JOINED, "lobby %d" % lobby_id)


func is_transport_active() -> bool:
	return peer != null and link != Link.OFFLINE


func stats() -> Dictionary:
	return {
		"transport": transport_name(),
		"link": link_name(),
		"role": "host" if role == Role.HOST else ("client" if role == Role.CLIENT else "none"),
		"peers": peers.size(),
		"local_peer_id": local_peer_id,
		"host_peer_id": host_peer_id,
		"sent": _packets_sent,
		"received": _packets_received,
		"bytes_sent": _bytes_sent,
		"bytes_received": _bytes_received,
	}


# ------------------------------------------------------- Steam transport path

## Starts hosting a gameplay transport bound to a Steam lobby the local user owns.
func host_steam_lobby(lobby_id: int) -> bool:
	if not SteamSvc.is_ready():
		transport_error.emit("steam_host", Loc.t("steam.error_not_ready"))
		return false
	if SteamSvc.lobby_id != lobby_id or not SteamSvc.is_host():
		transport_error.emit("steam_host", Loc.t("net.error_not_host"))
		return false
	if link == Link.MATCH_RUNNING or link == Link.CONNECTED:
		transport_error.emit("steam_host", Loc.t("net.error_already_connected"))
		return false
	var steam_peer := _create_steam_peer()
	if steam_peer == null:
		return false
	var err := int(steam_peer.call("host_with_lobby", lobby_id))
	if err != OK:
		transport_error.emit("steam_host", Loc.t("net.error_peer_setup_failed", {"code": err}))
		Log.error("Net: host_with_lobby failed", {"error": err})
		return false
	transport = Transport.STEAM
	_assign_peer(steam_peer, Role.HOST)
	_set_link(Link.CONNECTED, "Steam lobby %d" % lobby_id)
	return true


## Connects the gameplay transport to the host of a Steam lobby we already joined.
func join_steam_lobby(lobby_id: int) -> bool:
	if not SteamSvc.is_ready():
		transport_error.emit("steam_join", Loc.t("steam.error_not_ready"))
		return false
	if SteamSvc.lobby_id != lobby_id:
		transport_error.emit("steam_join", Loc.t("net.error_not_in_lobby"))
		return false
	if link == Link.MATCH_RUNNING or link == Link.CONNECTED:
		transport_error.emit("steam_join", Loc.t("net.error_already_connected"))
		return false
	var steam_peer := _create_steam_peer()
	if steam_peer == null:
		return false
	_set_link(Link.CONNECTING, "Steam lobby %d" % lobby_id)
	var err := int(steam_peer.call("connect_to_lobby", lobby_id))
	if err != OK:
		transport_error.emit("steam_join", Loc.t("net.error_peer_setup_failed", {"code": err}))
		Log.error("Net: connect_to_lobby failed", {"error": err})
		_set_link(Link.LOBBY_JOINED, "connect failed")
		return false
	transport = Transport.STEAM
	_assign_peer(steam_peer, Role.CLIENT)
	return true


func _create_steam_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		transport_error.emit("steam_peer", Loc.t("net.error_no_steam_peer"))
		Log.error("Net: SteamMultiplayerPeer class unavailable")
		return null
	var instance: Variant = ClassDB.instantiate("SteamMultiplayerPeer")
	if not (instance is MultiplayerPeer):
		transport_error.emit("steam_peer", Loc.t("net.error_no_steam_peer"))
		return null
	return instance


# --------------------------------------------------------- local test path

## Development/test transport. Used by automated multiplayer tests and for LAN
## debugging; it is explicitly *not* Steam networking.
func host_local_test(port: int = 47000, max_clients: int = 8) -> bool:
	if not bool(Prefs.get_value("net/allow_local_test_transport", true)):
		transport_error.emit("local_host", Loc.t("net.error_local_disabled"))
		return false
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(clampi(port, TEST_PORT_MIN, TEST_PORT_MAX), max_clients, 8)
	if err != OK:
		transport_error.emit("local_host", Loc.t("net.error_peer_setup_failed", {"code": err}))
		return false
	transport = Transport.LOCAL_TEST
	_assign_peer(enet, Role.HOST)
	_set_link(Link.CONNECTED, "ENet port %d" % port)
	return true


func join_local_test(address: String = "127.0.0.1", port: int = 47000) -> bool:
	if not bool(Prefs.get_value("net/allow_local_test_transport", true)):
		transport_error.emit("local_join", Loc.t("net.error_local_disabled"))
		return false
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, clampi(port, TEST_PORT_MIN, TEST_PORT_MAX))
	if err != OK:
		transport_error.emit("local_join", Loc.t("net.error_peer_setup_failed", {"code": err}))
		return false
	transport = Transport.LOCAL_TEST
	_set_link(Link.CONNECTING, "%s:%d" % [address, port])
	_assign_peer(enet, Role.CLIENT)
	return true


# -------------------------------------------------------- websocket transport
## Browser-capable transport (WebSocket). Works in HTML5 builds and on desktop.
## Requires a reachable URL for clients; hosting requires a routable address (a
## browser client cannot listen, so desktop builds usually host).
func host_websocket(port: int = 9000) -> bool:
	if link == Link.MATCH_RUNNING or link == Link.CONNECTED:
		transport_error.emit("ws_host", Loc.t("net.error_already_connected"))
		return false
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_server(clampi(port, 1024, 65535))
	if err != OK:
		transport_error.emit("ws_host", Loc.t("net.error_peer_setup_failed", {"code": err}))
		Log.error("Net: WebSocket server failed", {"error": err})
		return false
	transport = Transport.WEBSOCKET
	_assign_peer(ws, Role.HOST)
	_set_link(Link.CONNECTED, "WebSocket port %d" % port)
	return true


func join_websocket(url: String) -> bool:
	if url.strip_edges().is_empty():
		transport_error.emit("ws_join", Loc.t("net.error_peer_setup_failed", {"code": -1}))
		return false
	if link == Link.MATCH_RUNNING or link == Link.CONNECTED:
		transport_error.emit("ws_join", Loc.t("net.error_already_connected"))
		return false
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_client(url.strip_edges())
	if err != OK:
		transport_error.emit("ws_join", Loc.t("net.error_peer_setup_failed", {"code": err}))
		Log.error("Net: WebSocket client failed", {"error": err})
		return false
	transport = Transport.WEBSOCKET
	_set_link(Link.CONNECTING, url.strip_edges())
	_assign_peer(ws, Role.CLIENT)
	return true


# ------------------------------------------------------------- peer handling

func _assign_peer(new_peer: MultiplayerPeer, new_role: Role) -> void:
	close(false)
	peer = new_peer
	role = new_role
	_connect_transport_signals(new_peer)
	local_peer_id = peer.get_unique_id()
	if role == Role.HOST:
		host_peer_id = local_peer_id
		register_peer(local_peer_id, {
			"name": _local_name(),
			"steam_id": SteamSvc.steam_id,
			"player_index": 0,
			"host": true,
			"ready": true,
		})
	else:
		# ENet-derived transports use peer 1 for the server; Steam replaces this
		# with the real host id as soon as `welcome` arrives.
		host_peer_id = 1
	cached_stats = stats()


## Called by the lobby when the host announces its peer id (`welcome` message).
func set_host_peer(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == host_peer_id:
		return
	Log.info("Net: host peer id learned", {"peer_id": peer_id})
	host_peer_id = peer_id


# --------------------------------------------------- transport level signals

## The transport (ENet or Steam) is the source of truth for "who is actually
## connected": its signals drive registration and loss detection; the protocol
## handshake only adds the seat/name metadata on top.
func _connect_transport_signals(target: MultiplayerPeer) -> void:
	if target.has_signal("peer_connected") and not target.peer_connected.is_connected(_on_transport_peer_connected):
		target.peer_connected.connect(_on_transport_peer_connected)
	if target.has_signal("peer_disconnected") and not target.peer_disconnected.is_connected(_on_transport_peer_disconnected):
		target.peer_disconnected.connect(_on_transport_peer_disconnected)


func _on_transport_peer_connected(peer_id: int) -> void:
	Log.info("Net: transport peer connected", {
		"peer_id": peer_id, "role": role_name(), "transport": transport_name(),
	})
	if not peers.has(peer_id):
		register_peer(peer_id, {"name": "", "player_index": -1})
	cached_stats = stats()
	stats_changed.emit()


func _on_transport_peer_disconnected(peer_id: int) -> void:
	Log.info("Net: transport peer disconnected", {
		"peer_id": peer_id, "role": role_name(), "transport": transport_name(),
	})
	if role == Role.CLIENT and peer_id == host_peer_id:
		transport_error.emit("host_left", Loc.t("net.notice_link_lost"))
	if peers.has(peer_id):
		unregister_peer(peer_id)
	cached_stats = stats()
	stats_changed.emit()


func role_name() -> String:
	match role:
		Role.HOST:
			return "host"
		Role.CLIENT:
			return "client"
		_:
			return "none"


func is_host_peer(peer_id: int) -> bool:
	return host_peer_id != 0 and peer_id == host_peer_id


## Sends a message to the authoritative host (no-op when we are the host).
func send_to_host(message: Dictionary) -> void:
	if host_peer_id == 0 or host_peer_id == local_peer_id:
		return
	send(host_peer_id, message)


## Announces this peer to the host. The lobby calls it once the transport is
## connected; the host answers with `welcome`.
func announce_self() -> void:
	if role != Role.CLIENT:
		return
	send_to_host(NetProtocol.envelope(NetProtocol.T_HELLO, {
		"name": _local_name(),
		"steam_id": SteamSvc.steam_id,
		"protocol": NetProtocol.VERSION,
		"game_version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"language": Loc.current_locale,
	}))


func register_peer(peer_id: int, info: Dictionary) -> void:
	var entry: Dictionary = peers.get(peer_id, {})
	var had_seat := int(entry.get("player_index", -1)) >= 0
	entry.merge(info, true)
	entry["last_seen"] = _now()
	entry["rtt_ms"] = int(entry.get("rtt_ms", 0))
	var is_new := not peers.has(peer_id)
	peers[peer_id] = entry
	if is_new:
		Log.info("Net: peer registered", {"peer_id": peer_id, "info": entry})
		peer_registered.emit(peer_id, entry)
	elif not had_seat and int(entry.get("player_index", -1)) >= 0:
		Log.info("Net: seat assigned", {"peer_id": peer_id, "seat": int(entry["player_index"])})
		seat_assigned.emit(peer_id, entry)
	cached_stats = stats()
	stats_changed.emit()


func unregister_peer(peer_id: int) -> void:
	if not peers.has(peer_id):
		return
	var info: Dictionary = peers[peer_id]
	peers.erase(peer_id)
	Log.info("Net: peer removed", {"peer_id": peer_id, "name": info.get("name", "")})
	peer_unregistered.emit(peer_id, info)
	cached_stats = stats()
	stats_changed.emit()


func peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: Variant in peers:
		ids.append(int(id))
	ids.sort()
	return ids


func peer_info(peer_id: int) -> Dictionary:
	return peers.get(peer_id, {})


func steam_id_of(peer_id: int) -> int:
	var info: Dictionary = peers.get(peer_id, {})
	if info.has("steam_id"):
		return int(info["steam_id"])
	if peer != null and peer.has_method("get_steam_id_for_peer_id"):
		return int(peer.call("get_steam_id_for_peer_id", peer_id))
	return 0


func peer_id_of_steam_id(steam_id: int) -> int:
	for id: Variant in peers:
		if int(peers[id].get("steam_id", 0)) == steam_id:
			return int(id)
	if peer != null and peer.has_method("get_peer_id_for_steam_id"):
		return int(peer.call("get_peer_id_for_steam_id", steam_id))
	return 0


func _local_name() -> String:
	if SteamSvc.is_ready():
		return SteamSvc.display_name()
	return Prefs.profile_name()


# ---------------------------------------------------------------- messaging

func send(peer_id: int, message: Dictionary) -> void:
	if peer == null:
		return
	var packet := NetProtocol.encode(message)
	if packet.size() > NetProtocol.MAX_PACKET_BYTES:
		Log.error("Net: refusing to send oversized packet", {"size": packet.size(), "type": NetProtocol.type_of(message)})
		return
	peer.set_target_peer(peer_id)
	var err := peer.put_packet(packet)
	if err != OK:
		Log.warn("Net: put_packet failed", {"peer_id": peer_id, "error": err, "type": NetProtocol.type_of(message)})
		return
	_packets_sent += 1
	_bytes_sent += packet.size()


func broadcast(message: Dictionary, except_peer: int = 0) -> void:
	if peer == null:
		return
	var packet := NetProtocol.encode(message)
	if packet.size() > NetProtocol.MAX_PACKET_BYTES:
		Log.error("Net: refusing to broadcast oversized packet", {"size": packet.size(), "type": NetProtocol.type_of(message)})
		return
	for id: int in peer_ids():
		if id == local_peer_id or id == except_peer:
			continue
		peer.set_target_peer(id)
		var err := peer.put_packet(packet)
		if err != OK:
			Log.warn("Net: broadcast put_packet failed", {"peer_id": id, "error": err})
			continue
		_packets_sent += 1
		_bytes_sent += packet.size()


func disconnect_peer(peer_id: int, send_bye: bool = true) -> void:
	if peer == null or peer_id == local_peer_id:
		return
	if send_bye:
		send(peer_id, NetProtocol.envelope(NetProtocol.T_BYE, {"reason": "closed"}))
	if peer.has_method("disconnect_peer"):
		peer.call("disconnect_peer", peer_id)
	unregister_peer(peer_id)


func close(emit_signal: bool = true) -> void:
	if peer == null:
		return
	_set_link(Link.DISCONNECTING, "closing transport")
	if role == Role.HOST:
		for id: int in peer_ids():
			if id != local_peer_id:
				send(id, NetProtocol.envelope(NetProtocol.T_BYE, {"reason": "host_shutdown"}))
	if peer.has_method("close"):
		peer.call("close")
	peers.clear()
	peer = null
	role = Role.NONE
	transport = Transport.NONE
	local_peer_id = 0
	host_peer_id = 0
	cached_stats = stats()
	stats_changed.emit()
	if SteamSvc.is_ready():
		_set_link(Link.STEAM_READY, "transport closed")
	else:
		_set_link(Link.OFFLINE, "transport closed")
	if emit_signal:
		peer_unregistered.emit(0, {})


# ------------------------------------------------------------------- polling

func _poll_packets() -> void:
	if peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		# The transport vanished underneath us: a Steam connection dropped, the
		# host shut the lobby down or ENet reset the socket. Tear down instead of
		# polling a dead peer.
		Log.warn("Net: transport went away", {"transport": transport_name(), "role": role_name()})
		var was_client := role == Role.CLIENT
		close()
		if was_client:
			transport_error.emit("transport_lost", Loc.t("net.notice_link_lost"))
		return
	# The peer is owned by this service, not by a MultiplayerAPI, so nothing else
	# drives its socket: we poll it ourselves once per frame (ENet flushes
	# outgoing packets, accepts connections and receives data here; the Steam
	# peer runs its SteamNetworkingSockets callbacks here).
	peer.poll()
	var status := peer.get_connection_status()
	if role == Role.CLIENT and status == MultiplayerPeer.CONNECTION_CONNECTED and link == Link.CONNECTING:
		_set_link(Link.CONNECTED, "transport connected")
		# Introduce ourselves as soon as the transport is up, so the host can
		# assign a seat before any match starts.
		announce_self()
	while peer != null and peer.get_available_packet_count() > 0:
		# Order matters: `get_packet_peer()` reads the head of the queue, so it
		# must be called *before* `get_packet()` consumes that packet.
		var from_peer := peer.get_packet_peer()
		var packet := peer.get_packet()
		_bytes_received += packet.size()
		var message := NetProtocol.decode(packet)
		if message.is_empty():
			continue
		var invalid := NetProtocol.validate(message)
		if not invalid.is_empty():
			Log.warn("Net: rejected message", {"from": from_peer, "reason": invalid})
			if invalid == "version" and from_peer != local_peer_id:
				send(from_peer, NetProtocol.reject(NetProtocol.Reject.VERSION))
			continue
		_packets_received += 1
		if peers.has(from_peer):
			peers[from_peer]["last_seen"] = _now()
		var type := NetProtocol.type_of(message)
		match type:
			NetProtocol.T_PING:
				var pong := NetProtocol.envelope(NetProtocol.T_PONG, {"echo": message.get("ts", 0)})
				send(from_peer, pong)
				continue
			NetProtocol.T_PONG:
				var sent_ts := int(message.get("echo", 0))
				if peers.has(from_peer):
					peers[from_peer]["rtt_ms"] = clampi(Time.get_ticks_msec() - sent_ts, 0, 60000)
				cached_stats = stats()
				stats_changed.emit()
				continue
			NetProtocol.T_BYE:
				Log.info("Net: peer said goodbye", {"peer_id": from_peer})
				unregister_peer(from_peer)
				continue
			# The connection handshake belongs to the transport, not to any screen:
			# it runs identically in the lobby, in tools and in tests.
			NetProtocol.T_HELLO:
				if role == Role.HOST:
					_accept_hello(from_peer, message)
					continue
			NetProtocol.T_WELCOME:
				if role == Role.CLIENT:
					_accept_welcome(message)
					continue
			NetProtocol.T_LOBBY_STATE:
				if role == Role.HOST and not bool(message.get("request_state", false)):
					register_peer(from_peer, {"ready": bool(message.get("ready", false))})
					continue
		message_received.emit(from_peer, message)


## Host side of the handshake: give the newcomer a seat and answer `welcome`.
##
## Every field comes from a remote peer, so each one is converted defensively:
## a peer that sends `{"name": null}` must be registered with a fallback name,
## not take the host down.
func _accept_hello(peer_id: int, message: Dictionary) -> void:
	var known: Dictionary = peers.get(peer_id, {})
	var seat := VariantUtil.as_int(known.get("player_index", -1), -1)
	if seat < 0:
		seat = next_seat_index()
	var peer_name := VariantUtil.as_string(message.get("name", ""), "")
	if peer_name.is_empty():
		peer_name = "Player"
	register_peer(peer_id, {
		"name": peer_name,
		"player_index": seat,
		"steam_id": VariantUtil.as_int(message.get("steam_id", 0), 0),
		"language": VariantUtil.as_string(message.get("language", ""), ""),
		"protocol": VariantUtil.as_int(message.get("protocol", NetProtocol.VERSION), NetProtocol.VERSION),
	})
	Log.info("Net: client introduced itself", {"peer_id": peer_id, "seat": seat})
	send(peer_id, NetProtocol.envelope(NetProtocol.T_WELCOME, {
		"host": _local_name(),
		"host_peer_id": local_peer_id,
		"seat": seat,
		"protocol": NetProtocol.VERSION,
		"lobby": Session.lobby,
	}))


## Client side: learn who the authoritative host is (Steam uses its SteamID).
func _accept_welcome(message: Dictionary) -> void:
	set_host_peer(VariantUtil.as_int(message.get("host_peer_id", host_peer_id), host_peer_id))
	var host_name := VariantUtil.as_string(message.get("host", ""), "")
	if host_name.is_empty():
		host_name = "Host"
	register_peer(host_peer_id, {
		"name": host_name,
		"player_index": 0,
		"steam_id": SteamSvc.host_steam_id(),
		"host": true,
		"ready": true,
	})
	if message.has("lobby") and message["lobby"] is Dictionary:
		Session.lobby.merge(message["lobby"], true)


## Next free seat: 0 is the host, the rest are handed out in introduction order.
func next_seat_index() -> int:
	var used: Dictionary = {0: true} if role == Role.HOST else {}
	for id: int in peers:
		used[int(peers[id].get("player_index", -1))] = true
	var index := 1 if role == Role.HOST else 0
	while used.has(index):
		index += 1
	return index


func _send_heartbeats() -> void:
	if peer == null:
		return
	var ping := NetProtocol.envelope(NetProtocol.T_PING, {"ts": Time.get_ticks_msec()})
	for id: int in peer_ids():
		if id == local_peer_id:
			continue
		send(id, ping)


func _check_peer_timeouts() -> void:
	if peer == null or role != Role.HOST:
		return
	var now := _now()
	for id: int in peer_ids():
		if id == local_peer_id:
			continue
		var entry: Dictionary = peers[id]
		if now - float(entry.get("last_seen", now)) > PEER_TIMEOUT_SEC:
			Log.warn("Net: peer timed out", {"peer_id": id, "name": entry.get("name", "")})
			disconnect_peer(id, false)
			transport_error.emit("timeout", Loc.t("net.error_peer_timeout", {"name": String(entry.get("name", "?"))}))


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
