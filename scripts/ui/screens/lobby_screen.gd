extends ScreenBase
## Lobby screen: members, host controls, invitations, match start handshake.
##
## Host flow: configure -> create gameplay transport (Steam Networking Sockets
## through SteamMultiplayerPeer) -> publish metadata -> start the match, which is
## broadcast with the authoritative seat order. Client flow: connect to the host,
## wait for the start message, then open the game screen in client mode.

var _header: VBoxContainer
var _members_box: VBoxContainer
var _chat_box: VBoxContainer
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _actions_box: VBoxContainer
var _ready_state: bool = false
var _test_transport: bool = false
var _starting: bool = false


func build() -> void:
	title_key = "lobby.title"
	subtitle_key = "lobby.subtitle"
	var layout := UI.row(16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(layout, 24, 20, 24, 24))

	var left := UI.column(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	_header = UI.column(10)
	left.add_child(UI.panel_with(_header, "CardPanel", 18))
	var members_panel := UI.panel("CardPanel")
	members_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(members_panel)
	_members_box = UI.column(8)
	members_panel.add_child(UI.margin_container(UI.scroll(_members_box), 16))

	var right := UI.column(14)
	right.custom_minimum_size = Vector2(400, 0)
	layout.add_child(right)
	_actions_box = UI.column(10)
	right.add_child(UI.panel_with(_actions_box, "CardPanel", 18))
	var chat_panel := UI.panel("CardPanel")
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(chat_panel)
	_chat_box = UI.column(8)
	chat_panel.add_child(UI.margin_container(_chat_box, 14))
	_chat_box.add_child(UI.heading(Loc.t("lobby.chat"), "Subtitle"))
	var chat_scroll := UI.scroll(UI.column(4), false)
	_chat_box.add_child(chat_scroll)
	_chat_log = chat_scroll.get_child(0) as VBoxContainer
	_chat_input = UI.line_edit(Loc.t("lobby.chat_placeholder"))
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_box.add_child(_chat_input)


func on_enter() -> void:
	_test_transport = bool(params.get("test_transport", false))
	SteamSvc.lobby_members_changed.connect(_rebuild_members)
	SteamSvc.lobby_data_changed.connect(_rebuild_header)
	SteamSvc.lobby_message_received.connect(_on_lobby_message)
	SteamSvc.lobby_left.connect(_on_lobby_left)
	SteamSvc.state_changed.connect(_on_steam_state)
	Net.peer_registered.connect(_on_peer_registered)
	Net.seat_assigned.connect(_on_peer_registered)
	Net.peer_unregistered.connect(_on_peer_unregistered)
	Net.message_received.connect(_on_net_message)
	Net.transport_error.connect(_on_transport_error)
	Net.link_state_changed.connect(_on_link_changed)
	_ensure_transport()
	_rebuild_all()


func on_exit() -> void:
	if SteamSvc.lobby_members_changed.is_connected(_rebuild_members):
		SteamSvc.lobby_members_changed.disconnect(_rebuild_members)
	if SteamSvc.lobby_data_changed.is_connected(_rebuild_header):
		SteamSvc.lobby_data_changed.disconnect(_rebuild_header)
	if SteamSvc.lobby_message_received.is_connected(_on_lobby_message):
		SteamSvc.lobby_message_received.disconnect(_on_lobby_message)
	if SteamSvc.lobby_left.is_connected(_on_lobby_left):
		SteamSvc.lobby_left.disconnect(_on_lobby_left)
	if SteamSvc.state_changed.is_connected(_on_steam_state):
		SteamSvc.state_changed.disconnect(_on_steam_state)
	if Net.peer_registered.is_connected(_on_peer_registered):
		Net.peer_registered.disconnect(_on_peer_registered)
	if Net.seat_assigned.is_connected(_on_peer_registered):
		Net.seat_assigned.disconnect(_on_peer_registered)
	if Net.peer_unregistered.is_connected(_on_peer_unregistered):
		Net.peer_unregistered.disconnect(_on_peer_unregistered)
	if Net.message_received.is_connected(_on_net_message):
		Net.message_received.disconnect(_on_net_message)
	if Net.transport_error.is_connected(_on_transport_error):
		Net.transport_error.disconnect(_on_transport_error)
	if Net.link_state_changed.is_connected(_on_link_changed):
		Net.link_state_changed.disconnect(_on_link_changed)


## Opens the gameplay transport as soon as the lobby screen appears, so the
## member list shows real connections instead of a "connected" assumption.
func _ensure_transport() -> void:
	if _test_transport or SteamSvc.lobby_id == 0 or not SteamSvc.is_ready():
		return
	if Net.link == Net.Link.MATCH_RUNNING:
		return
	if SteamSvc.is_host():
		if not Net.is_transport_active():
			Net.host_steam_lobby(SteamSvc.lobby_id)
	elif Net.link != Net.Link.CONNECTED:
		if Net.link != Net.Link.CONNECTING:
			Net.join_steam_lobby(SteamSvc.lobby_id)


func _rebuild_all() -> void:
	_rebuild_header()
	_rebuild_members()
	_rebuild_actions()
	_rebuild_chat()


func _clear(box: Node) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _rebuild_header() -> void:
	_clear(_header)
	var lobby: Dictionary = Session.lobby
	var game_id := String(lobby.get("game_id", ""))
	if _test_transport:
		_header.add_child(UI.heading(Loc.t("lobby.test_title"), "Subtitle"))
		_header.add_child(UI.label(Loc.t("lobby.test_body"), "Small"))
	var game_label := Loc.t("lobby.no_game_selected")
	if Catalog.exists(game_id):
		game_label = Catalog.get_entry(game_id).display_name()
	_header.add_child(UI.kv_row(Loc.t("lobby.game"), game_label))
	_header.add_child(UI.kv_row(Loc.t("lobby.host"), _host_name()))
	var visibility := String(lobby.get("visibility", "public"))
	_header.add_child(UI.kv_row(Loc.t("lobby.visibility"), Loc.t("online.visibility_%s" % visibility)))
	var transport_label := Loc.t("common.none")
	if Net.transport == Net.Transport.STEAM:
		transport_label = Loc.t("lobby.transport_steam")
	elif Net.transport == Net.Transport.LOCAL_TEST:
		transport_label = Loc.t("lobby.transport_test")
	if SteamSvc.lobby_id != 0 and not _test_transport:
		_header.add_child(UI.kv_row(Loc.t("lobby.id"), str(SteamSvc.lobby_id)))
	_header.add_child(UI.kv_row(Loc.t("lobby.transport"), "%s  ·  %s" % [transport_label, Net.link_name()]))
	if Net.transport == Net.Transport.STEAM:
		_header.add_child(UI.kv_row(Loc.t("lobby.relay"), Loc.t("common.yes") if SteamSvc.relay_available else Loc.t("common.unknown")))
	var connected := Net.peers.size() if Net.is_transport_active() else SteamSvc.members.size()
	_header.add_child(UI.kv_row(Loc.t("lobby.players"), "%d / %d" % [connected, int(lobby.get("max_players", 4))]))
	if bool(lobby.get("expansions", []).size() > 0):
		_header.add_child(UI.kv_row(Loc.t("lobby.expansions"), ",".join(lobby.get("expansions", []))))


func _host_name() -> String:
	if Net.is_transport_active():
		var info: Dictionary = Net.peer_info(Net.host_peer_id)
		return String(info.get("name", Loc.t("common.unknown")))
	if SteamSvc.lobby_id == 0:
		return Loc.t("common.unknown")
	var owner := SteamSvc.host_steam_id()
	return SteamSvc.member_name(owner) if owner != 0 else Loc.t("common.unknown")


func _rebuild_members() -> void:
	if _members_box == null:
		return
	_clear(_members_box)
	_members_box.add_child(UI.section_header(Loc.t("lobby.members_title"), Loc.t("lobby.members_hint")))
	var members: Array = []
	if Net.is_transport_active():
		for peer_id: int in Net.peer_ids():
			var info: Dictionary = Net.peer_info(peer_id)
			members.append({
				"name": VariantUtil.as_string(info.get("name", ""), "?"),
				"is_host": Net.is_host_peer(peer_id),
				"is_local": peer_id == Net.local_peer_id,
				"ready": bool(info.get("ready", false)),
				"seat": int(info.get("player_index", -1)),
				"steam_id": VariantUtil.as_int(info.get("steam_id", 0), 0),
				"avatar": null,
			})
	else:
		members = SteamSvc.members
	if members.is_empty():
		_members_box.add_child(UI.label(Loc.t("lobby.no_members"), "Small"))
	for member: Variant in members:
		var data: Dictionary = member
		var row := UI.row(10)
		var avatar: Texture2D = data.get("avatar", null)
		if avatar != null:
			var avatar_rect := TextureRect.new()
			avatar_rect.texture = avatar
			avatar_rect.custom_minimum_size = Vector2(32, 32)
			avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(avatar_rect)
		var name_box := UI.column(2)
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(UI.label(String(data.get("name", "?")), "Body"))
		var detail := ""
		if bool(data.get("is_host", false)):
			detail = Loc.t("lobby.host_badge")
		elif bool(data.get("is_local", false)):
			detail = Loc.t("lobby.you_badge")
		var seat := int(data.get("seat", -1))
		if seat >= 0:
			detail += ("  ·  " if not detail.is_empty() else "") + "#%d" % (seat + 1)
		var steam_id := int(data.get("steam_id", 0))
		if steam_id != 0:
			detail += ("  ·  " if not detail.is_empty() else "") + str(steam_id)
		if not detail.is_empty():
			name_box.add_child(UI.label(detail, "Caption"))
		row.add_child(name_box)
		row.add_child(UI.chip(Loc.t("lobby.ready") if bool(data.get("ready", false)) else Loc.t("lobby.not_ready"), Palette.POSITIVE if bool(data.get("ready", false)) else Palette.TEXT_MUTED))
		_members_box.add_child(UI.panel_with(row, "ElevatedPanel", 10))
	var hints := UI.column(4)
	hints.add_child(UI.label(Loc.t("lobby.net_hint"), "Caption"))
	_members_box.add_child(hints)


func _rebuild_actions() -> void:
	_clear(_actions_box)
	_actions_box.add_child(UI.section_header(Loc.t("lobby.actions_title"), ""))
	var is_host := _is_host()
	if is_host:
		var entries: Array = []
		for entry: GameEntry in Catalog.games():
			if entry.supports_mode("online") and Session.engine_available(entry.id):
				entries.append({"label": entry.display_name(), "value": entry.id})
		if not entries.is_empty():
			var current := String(Session.lobby.get("game_id", ""))
			_actions_box.add_child(UI.form_row(Loc.t("lobby.game"), UI.dropdown(entries, current, func(value: String) -> void:
				Session.lobby["game_id"] = value
				if not _test_transport and SteamSvc.lobby_id != 0:
					SteamSvc.publish_lobby_state("open", {SteamSvc.KEY_GAME_ID: value})
				_rebuild_header()
			)))
		var start := UI.button(Loc.t("lobby.start_match"), "PrimaryButton", _start_match)
		start.disabled = _starting or String(Session.lobby.get("game_id", "")).is_empty()
		_actions_box.add_child(start)
		if _starting:
			_actions_box.add_child(UI.label(Loc.t("lobby.connecting"), "Warning"))
		_actions_box.add_child(UI.button(Loc.t("lobby.invite_overlay"), "Button", func() -> void:
			SteamSvc.open_invite_overlay()
		))
		_actions_box.add_child(UI.button(Loc.t("online.friends"), "GhostButton", func() -> void:
			Nav.go(Nav.ROUTE_ONLINE, {"game_id": String(Session.lobby.get("game_id", ""))})
		))
	else:
		_actions_box.add_child(UI.label(Loc.t("lobby.waiting_host"), "Small"))
		_actions_box.add_child(UI.toggle(Loc.t("lobby.mark_ready"), _ready_state, func(value: bool) -> void:
			_ready_state = value
			if Net.is_transport_active():
				Net.send_to_host(NetProtocol.envelope(NetProtocol.T_LOBBY_STATE, {"ready": value}))
				Net.register_peer(Net.local_peer_id, {"ready": value})
			else:
				SteamSvc.set_member_data("ready", "1" if value else "0")
			_rebuild_members()
		))
	_actions_box.add_child(UI.divider())
	_actions_box.add_child(UI.button(Loc.t("lobby.leave"), "DangerButton", func() -> void:
		_leave_lobby()
	))


func _rebuild_chat() -> void:
	if _chat_log == null:
		return
	_clear(_chat_log)
	var entries: Array = SteamSvc.chat_log if not _test_transport else SteamSvc.chat_log
	if entries.is_empty():
		_chat_log.add_child(UI.label(Loc.t("lobby.chat_empty"), "Caption"))
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var row := UI.column(2)
		row.add_child(UI.label(String(data.get("name", "?")), "Caption"))
		row.add_child(UI.label(String(data.get("message", "")), "Small"))
		_chat_log.add_child(row)


func _is_host() -> bool:
	if _test_transport:
		return Net.role == Net.Role.HOST
	return SteamSvc.is_host()


# ------------------------------------------------------------------- actions

func _start_match() -> void:
	if _starting:
		return
	var game_id := String(Session.lobby.get("game_id", ""))
	if game_id.is_empty():
		Notify.error(Loc.t("online.pick_game"))
		return
	var entry := Catalog.get_entry(game_id)
	if entry == null:
		Notify.error(Loc.t("online.pick_game"))
		return
	if not _test_transport and not SteamSvc.is_ready():
		Notify.error(Loc.t("steam.error_not_ready"))
		return
	if _test_transport:
		if Net.role != Net.Role.HOST:
			Notify.error(Loc.t("net.error_not_host"))
			return
	elif not Net.is_transport_active():
		if SteamSvc.lobby_id == 0 or not Net.host_steam_lobby(SteamSvc.lobby_id):
			Notify.error(Loc.t("net.error_not_host"))
			return
	_starting = true
	_rebuild_actions()
	# Seat order is decided here and only here: seat 0 is the host, the connected
	# clients follow in peer order, and any seat nobody took is filled with a bot
	# so that a host can start a match before the lobby fills up.
	var target := clampi(int(Session.lobby.get("max_players", entry.max_players)), entry.min_players, entry.max_players)
	var remote := _remote_seats()
	var seat_number := 1 + remote.size()
	while 1 + remote.size() < target:
		seat_number += 1
		remote.append({
			"name": "%s %d" % [Loc.t("game.common.bot"), seat_number],
			"steam_id": 0,
			"peer_id": 0,
			"kind": "bot",
		})
	Session.configure(game_id, 1 + remote.size())
	var session := Session.start_online_host(remote)
	if session == null:
		_starting = false
		_rebuild_actions()
		Notify.error(Loc.t("setup.error_start_failed"))
		return
	var seat_map: Array = [{"peer_id": Net.local_peer_id, "index": 0, "name": Prefs.profile_name()}]
	for i: int in range(1, session.engine.player_count()):
		seat_map.append({"peer_id": session.peer_for_player(i), "index": i, "name": session.engine.player_name(i)})
	var message := NetProtocol.envelope(NetProtocol.T_START_MATCH, {
		"game_id": game_id,
		"seed": session.engine.seed,
		"seats": seat_map,
		"config": session.config,
		"player_count": session.engine.player_count(),
	})
	Net.broadcast(message)
	session.push_state()
	if not _test_transport and SteamSvc.lobby_id != 0:
		SteamSvc.publish_lobby_state("in_match", {SteamSvc.KEY_GAME_ID: game_id})
	Notify.success(Loc.t("lobby.match_starting"))
	Nav.go(Nav.ROUTE_GAME, {"game_id": game_id}, "push", "none")


## Connected clients, in seat order, as the engine's remote seats.
func _remote_seats() -> Array:
	var out: Array = []
	var ordered: Array = []
	for peer_id: int in Net.peer_ids():
		if peer_id == Net.local_peer_id:
			continue
		ordered.append(peer_id)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		return int(Net.peer_info(a).get("player_index", 999)) < int(Net.peer_info(b).get("player_index", 999))
	)
	for peer_id: int in ordered:
		var info: Dictionary = Net.peer_info(peer_id)
		out.append({
			"name": VariantUtil.as_string(info.get("name", ""), "?"),
			"steam_id": VariantUtil.as_int(info.get("steam_id", 0), 0),
			"peer_id": peer_id,
			"kind": "remote",
		})
	return out


func _leave_lobby() -> void:
	if Net.is_transport_active():
		Net.close()
	if not _test_transport and SteamSvc.lobby_id != 0:
		SteamSvc.leave_lobby()
	Session.lobby["lobby_id"] = 0
	Nav.go(Nav.ROUTE_ONLINE, {}, "replace")


func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_chat_input.text = ""
	if _test_transport:
		SteamSvc.chat_log.append({"steam_id": Net.local_peer_id, "name": Prefs.profile_name(), "message": text})
		Net.broadcast(NetProtocol.envelope(NetProtocol.T_CHAT, {"message": text, "name": Prefs.profile_name()}))
	else:
		SteamSvc.send_lobby_chat(text)
	_rebuild_chat()


# ------------------------------------------------------------------ signals

func _on_lobby_message(_steam_id: int, _message: String) -> void:
	_rebuild_chat()


func _on_lobby_left() -> void:
	if is_inside_tree() and visible:
		Notify.warning(Loc.t("lobby.left"))
		Nav.go(Nav.ROUTE_ONLINE, {}, "replace")


func _on_steam_state(state: int, _detail: String) -> void:
	if state != SteamSvc.State.READY and not _test_transport:
		Notify.warning(Loc.t("steam.notice_failed"))
		_leave_lobby()


func _on_peer_registered(_peer_id: int, _info: Dictionary) -> void:
	_rebuild_all()


func _on_peer_unregistered(_peer_id: int, info: Dictionary) -> void:
	_rebuild_all()
	if not _is_host():
		Notify.warning(Loc.t("lobby.peer_left", {"name": VariantUtil.as_string(info.get("name", ""), "?")}))


func _on_net_message(peer_id: int, message: Dictionary) -> void:
	match NetProtocol.type_of(message):
		NetProtocol.T_CHAT:
			SteamSvc.chat_log.append({
				"steam_id": peer_id,
				"name": VariantUtil.as_string(message.get("name", ""), "?"),
				"message": VariantUtil.as_string(message.get("message", ""), ""),
			})
			_rebuild_chat()
		NetProtocol.T_HELLO, NetProtocol.T_WELCOME:
			# Handled by Net itself (seat assignment / host identity); the member
			# list is refreshed through `peer_registered` and `seat_assigned`.
			pass
		NetProtocol.T_LOBBY_STATE:
			pass
		NetProtocol.T_START_MATCH:
			_on_match_started(message)
		NetProtocol.T_REJECT:
			Notify.error(Loc.t(NetProtocol.reason_key(VariantUtil.as_int(message.get("reason", 0), 0))))
		NetProtocol.T_BYE:
			pass


func _on_match_started(message: Dictionary) -> void:
	var game_id := VariantUtil.as_string(message.get("game_id", ""), "")
	var seats: Array = VariantUtil.as_array(message.get("seats", []))
	var local_index := -1
	for seat: Variant in seats:
		if not (seat is Dictionary):
			continue
		var data: Dictionary = seat
		if VariantUtil.as_int(data.get("peer_id", 0), 0) == Net.local_peer_id:
			local_index = VariantUtil.as_int(data.get("index", -1), -1)
	if local_index < 0:
		Log.error("Lobby: start message without a seat for this peer", {"peer_id": Net.local_peer_id})
		Notify.error(Loc.t("net.reject_not_player"))
		return
	var player_count := VariantUtil.as_int(message.get("player_count", seats.size()), seats.size())
	Session.configure(game_id, maxi(player_count, local_index + 1))
	Session.set_option("seed", VariantUtil.as_int(message.get("seed", 0), 0))
	var session := Session.start_online_client(game_id, local_index)
	if session == null:
		Notify.error(Loc.t("setup.error_start_failed"))
		return
	if message.has("config") and message["config"] is Dictionary:
		session.config = VariantUtil.dict_copy(message.get("config", {}))
	Net.send_to_host(NetProtocol.envelope(NetProtocol.T_LOBBY_STATE, {"request_state": true}))
	Notify.success(Loc.t("lobby.match_starting"))
	Nav.go(Nav.ROUTE_GAME, {"game_id": game_id}, "push", "none")


func _on_link_changed(_state: int, _detail: String) -> void:
	_rebuild_all()


func _on_transport_error(context: String, detail: String) -> void:
	if detail.is_empty():
		return
	Notify.error(Loc.t("net.transport_error_detail", {"context": context, "detail": detail}))


func refresh_texts() -> void:
	_rebuild_all()
