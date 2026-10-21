extends ScreenBase
## Online play: Steam status, lobby creation, lobby browser, invitations.
##
## Everything here talks to [code]SteamSvc[/code]; when Steam is unavailable the
## screen explains why and only offers the explicitly labelled local test
## transport (used by automated tests and LAN debugging).

var _status_panel: VBoxContainer
var _host_panel: VBoxContainer
var _browse_panel: VBoxContainer
var _dev_panel: VBoxContainer
var _lobby_list: VBoxContainer
var _host_game_id: String = ""
var _host_visibility: String = "public"
var _host_max_players: int = 4
var _test_port: int = 47000
var _test_address: String = "127.0.0.1"


func build() -> void:
	title_key = "online.title"
	subtitle_key = "online.subtitle"
	var column := UI.column(16)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(column)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(scroll, 24, 20, 24, 24))

	_status_panel = UI.column(10)
	column.add_child(UI.panel_with(_status_panel, "CardPanel", 18))
	_host_panel = UI.column(12)
	column.add_child(UI.panel_with(_host_panel, "CardPanel", 18))
	_browse_panel = UI.column(12)
	column.add_child(UI.panel_with(_browse_panel, "CardPanel", 18))
	_dev_panel = UI.column(12)
	column.add_child(UI.panel_with(_dev_panel, "CardPanel", 18))


func on_enter() -> void:
	if params.has("game_id"):
		_host_game_id = String(params["game_id"])
	SteamSvc.state_changed.connect(_on_steam_state)
	SteamSvc.lobby_match_list.connect(_on_match_list)
	SteamSvc.lobby_joined.connect(_on_lobby_joined)
	SteamSvc.lobby_join_failed.connect(_on_lobby_join_failed)
	SteamSvc.invite_received.connect(_on_invite)
	Net.link_state_changed.connect(_on_link_changed)
	_rebuild()


func on_exit() -> void:
	if SteamSvc.state_changed.is_connected(_on_steam_state):
		SteamSvc.state_changed.disconnect(_on_steam_state)
	if SteamSvc.lobby_match_list.is_connected(_on_match_list):
		SteamSvc.lobby_match_list.disconnect(_on_match_list)
	if SteamSvc.lobby_joined.is_connected(_on_lobby_joined):
		SteamSvc.lobby_joined.disconnect(_on_lobby_joined)
	if SteamSvc.lobby_join_failed.is_connected(_on_lobby_join_failed):
		SteamSvc.lobby_join_failed.disconnect(_on_lobby_join_failed)
	if SteamSvc.invite_received.is_connected(_on_invite):
		SteamSvc.invite_received.disconnect(_on_invite)
	if Net.link_state_changed.is_connected(_on_link_changed):
		Net.link_state_changed.disconnect(_on_link_changed)


func _on_steam_state(_state: int, _detail: String) -> void:
	_rebuild()


func _on_link_changed(_state: int, _detail: String) -> void:
	_rebuild()


func _rebuild() -> void:
	_build_status()
	_build_host()
	_build_browse()
	_build_dev()


func _clear(box: VBoxContainer) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _build_status() -> void:
	_clear(_status_panel)
	_status_panel.add_child(UI.section_header(Loc.t("online.steam_title"), Loc.t("online.steam_hint")))
	var row := UI.row(10)
	var status_chip := UI.chip(SteamSvc.status_text(), _state_color())
	# Keep the raw SDK message available for support without showing an
	# untranslated English sentence in the middle of the localised screen.
	status_chip.tooltip_text = SteamSvc.state_detail
	row.add_child(status_chip)
	if SteamSvc.is_ready():
		row.add_child(UI.chip("SteamID %s" % SteamSvc.steam_id_string(), Palette.INFO))
		row.add_child(UI.chip(Loc.t("online.relay_ok") if SteamSvc.relay_available else Loc.t("online.relay_unknown"), Palette.POSITIVE if SteamSvc.relay_available else Palette.WARNING))
	_status_panel.add_child(row)
	var actions := UI.row(10)
	if not SteamSvc.is_ready():
		actions.add_child(UI.button(Loc.t("online.retry_steam"), "Button", func() -> void:
			SteamSvc.initialise(true)
		))
	actions.add_child(UI.button(Loc.t("online.open_settings"), "GhostButton", func() -> void:
		Nav.go(Nav.ROUTE_SETTINGS, {"section": 0})
	))
	actions.add_child(UI.button(Loc.t("online.how_to"), "LinkButton", func() -> void:
		Notify.alert(Loc.t("online.how_to_title"), Loc.t("online.how_to_body"))
	))
	_status_panel.add_child(actions)
	if not SteamSvc.is_ready():
		var notice := UI.label(Loc.t("online.offline_notice"), "Body")
		notice.add_theme_color_override("font_color", Palette.TEXT)
		_status_panel.add_child(UI.panel_with(notice, "AccentPanel", 12))


func _state_color() -> Color:
	match SteamSvc.state:
		SteamSvc.State.READY:
			return Palette.POSITIVE
		SteamSvc.State.INITIALIZING:
			return Palette.WARNING
		SteamSvc.State.FAILED:
			return Palette.DANGER
		_:
			return Palette.TEXT_MUTED


func _build_host() -> void:
	_clear(_host_panel)
	_host_panel.add_child(UI.section_header(Loc.t("online.host_title"), Loc.t("online.host_hint")))
	var entries: Array = []
	for entry: GameEntry in Catalog.games():
		if not entry.supports_mode("online"):
			continue
		var label := entry.display_name()
		if not Session.engine_available(entry.id):
			label += "  (" + Loc.t("online.no_engine") + ")"
		entries.append({"label": label, "value": entry.id, "disabled": not Session.engine_available(entry.id)})
	if entries.is_empty():
		_host_panel.add_child(UI.label(Loc.t("online.no_online_games"), "Small"))
		return
	var selected := _host_game_id if not _host_game_id.is_empty() else String(entries[0].value)
	var game_row := UI.form_row(Loc.t("online.game"), UI.dropdown(entries, selected, func(value: String) -> void:
		_host_game_id = value
		var entry := Catalog.get_entry(value)
		if entry != null:
			_host_max_players = clampi(_host_max_players, entry.min_players, entry.max_players)
		_build_host()
	))
	_host_panel.add_child(game_row)
	var entry := Catalog.get_entry(selected)
	if entry != null:
		_host_max_players = clampi(_host_max_players, entry.min_players, maxi(entry.min_players, entry.max_players))
		_host_panel.add_child(UI.kv_row(Loc.t("online.players_supported"), entry.players_text()))
		_host_panel.add_child(UI.kv_row(Loc.t("online.modes"), entry.modes_text()))
		var max_label := UI.value_label(str(_host_max_players), 32)
		var max_callback := func(value: float) -> void:
			_host_max_players = int(value)
			max_label.text = str(_host_max_players)
		var max_slider := UI.slider(entry.min_players, entry.max_players, 1, _host_max_players, max_callback)
		_host_panel.add_child(UI.form_row(Loc.t("online.max_players"), UI.row(10, [max_slider, max_label])))
		if entry.has_editions:
			var open_sets := func() -> void:
				Nav.go(Nav.ROUTE_STAR_REALMS_SETS, {"game_id": entry.id})
			_host_panel.add_child(UI.form_row(
				Loc.t("sr.selection_title"),
				UI.row(10, [
					UI.label(Loc.t("sr.selection_summary", {"count": Prefs.selected_star_realms_sets().size()}), "Small"),
					UI.button(Loc.t("sr.open_menu"), "GhostButton", open_sets),
				]),
				Loc.t("sr.selection_hint_short")
			))
	var visibility_callback := func(value: String) -> void:
		_host_visibility = value
	_host_panel.add_child(UI.form_row(
		Loc.t("online.visibility"),
		UI.dropdown([
			{"label": Loc.t("online.visibility_public"), "value": "public"},
			{"label": Loc.t("online.visibility_friends"), "value": "friends"},
			{"label": Loc.t("online.visibility_private"), "value": "private"},
		], _host_visibility, visibility_callback),
		Loc.t("online.visibility_hint")
	))
	var create := UI.button(Loc.t("online.create_lobby"), "PrimaryButton", _create_lobby)
	create.disabled = not SteamSvc.is_ready()
	_host_panel.add_child(create)
	if not SteamSvc.is_ready():
		_host_panel.modulate = Color(1, 1, 1, 0.55)
		_set_form_disabled(_host_panel)
	else:
		_host_panel.modulate = Color.WHITE


func _set_form_disabled(root: Node) -> void:
	for node: Node in root.find_children("*", "Control", true, false):
		if node is BaseButton:
			(node as BaseButton).disabled = true
		elif node is LineEdit:
			(node as LineEdit).editable = false
		elif node is HSlider:
			(node as HSlider).editable = false


func _build_browse() -> void:
	_clear(_browse_panel)
	_browse_panel.add_child(UI.section_header(Loc.t("online.browse_title"), Loc.t("online.browse_hint")))
	var row := UI.row(10)
	var refresh := UI.button(Loc.t("online.refresh"), "Button", func() -> void:
		SteamSvc.refresh_lobby_list()
	)
	refresh.disabled = not SteamSvc.is_ready()
	row.add_child(refresh)
	row.add_child(UI.button(Loc.t("online.friends"), "GhostButton", _show_friends))
	_browse_panel.add_child(row)
	_lobby_list = UI.column(8)
	_browse_panel.add_child(_lobby_list)
	_populate_lobby_list()


func _populate_lobby_list() -> void:
	_clear(_lobby_list)
	if SteamSvc.last_lobby_list.is_empty():
		_lobby_list.add_child(UI.label(Loc.t("online.no_lobbies"), "Small"))
		return
	for lobby: Variant in SteamSvc.last_lobby_list:
		var data: Dictionary = lobby
		var row := UI.row(10)
		var info := UI.column(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var game_id := String(data.get("game_id", ""))
		var game_label := game_id
		if Catalog.exists(game_id):
			game_label = Catalog.get_entry(game_id).display_name()
		info.add_child(UI.label("%s  ·  %s" % [game_label, String(data.get("host", "?"))], "Body"))
		info.add_child(UI.label(Loc.t("online.lobby_line", {
			"members": int(data.get("members", 0)),
			"max": int(data.get("max_members", 0)),
			"status": String(data.get("status", "")),
			"language": String(data.get("language", "")),
		}), "Caption"))
		row.add_child(info)
		if not String(data.get("expansions", "")).is_empty():
			row.add_child(UI.chip(String(data.get("expansions", "")), Palette.ACCENT))
		var join := UI.button(Loc.t("online.join"), "Button", func() -> void:
			SteamSvc.join_lobby(int(data.get("lobby_id", 0)))
		)
		join.disabled = not SteamSvc.is_ready()
		row.add_child(join)
		_lobby_list.add_child(row)


func _build_dev() -> void:
	_clear(_dev_panel)
	_dev_panel.add_child(UI.section_header(Loc.t("online.test_title"), Loc.t("online.test_hint")))
	var row := UI.row(10)
	row.add_child(UI.label(Loc.t("online.test_port"), "Small"))
	var port_field := UI.line_edit("47000", str(_test_port))
	port_field.custom_minimum_size = Vector2(120, 0)
	port_field.text_changed.connect(func(text: String) -> void: _test_port = int(text))
	row.add_child(port_field)
	row.add_child(UI.label(Loc.t("online.test_address"), "Small"))
	var address_field := UI.line_edit("127.0.0.1", _test_address)
	address_field.custom_minimum_size = Vector2(160, 0)
	address_field.text_changed.connect(func(text: String) -> void: _test_address = text)
	row.add_child(address_field)
	_dev_panel.add_child(row)
	var buttons := UI.row(10)
	buttons.add_child(UI.button(Loc.t("online.test_host"), "Button", func() -> void:
		if Net.host_local_test(_test_port):
			Net.notify_lobby_joined(0)
			Session.lobby = {"lobby_id": 0, "visibility": "private", "max_players": 8, "game_id": _host_game_id, "mode": "local_test", "expansions": []}
			Nav.go(Nav.ROUTE_LOBBY, {"test_transport": true})
		else:
			Notify.error(Loc.t("net.error_local_disabled"))
	))
	buttons.add_child(UI.button(Loc.t("online.test_join"), "Button", func() -> void:
		if Net.join_local_test(_test_address, _test_port):
			Session.lobby = {"lobby_id": 0, "visibility": "private", "max_players": 8, "game_id": "", "mode": "local_test", "expansions": []}
			Nav.go(Nav.ROUTE_LOBBY, {"test_transport": true})
		else:
			Notify.error(Loc.t("net.error_local_disabled"))
	))
	_dev_panel.add_child(buttons)
	_dev_panel.add_child(UI.label(Loc.t("online.test_warning"), "Warning"))


# ------------------------------------------------------------------ actions

func _create_lobby() -> void:
	if not SteamSvc.is_ready():
		Notify.error(Loc.t("steam.error_not_ready"))
		return
	var entry := Catalog.get_entry(_host_game_id)
	if entry == null:
		Notify.error(Loc.t("online.pick_game"))
		return
	var expansions: Array = Prefs.selected_star_realms_sets() if entry.has_editions else []
	var metadata := {
		SteamSvc.KEY_GAME_ID: entry.id,
		SteamSvc.KEY_GAME_NAME: entry.display_name(),
		SteamSvc.KEY_GAME_MODE: "online",
		SteamSvc.KEY_STATUS: "open",
		SteamSvc.KEY_MAX_PLAYERS: str(_host_max_players),
		SteamSvc.KEY_EXPANSIONS: ",".join(expansions),
		SteamSvc.KEY_LANGUAGE: Loc.current_locale,
	}
	Session.lobby = {
		"lobby_id": 0,
		"visibility": _host_visibility,
		"max_players": _host_max_players,
		"game_id": entry.id,
		"mode": "online",
		"expansions": expansions,
	}
	SteamSvc.create_lobby(_host_visibility, _host_max_players, metadata)
	Notify.info(Loc.t("online.creating"))


func _show_friends() -> void:
	if not SteamSvc.is_ready():
		Notify.error(Loc.t("steam.error_not_ready"))
		return
	var friends := SteamSvc.friend_list()
	if friends.is_empty():
		Notify.info(Loc.t("online.no_friends"))
		return
	var entries: Array = []
	for friend: Dictionary in friends:
		entries.append({
			"label": String(friend.name),
			"value": str(int(friend.steam_id)),
		})
	Notify.choose(Loc.t("online.friends_title"), Loc.t("online.friends_hint"), entries, func(value: String) -> void:
		if SteamSvc.lobby_id == 0:
			Notify.warning(Loc.t("online.need_lobby"))
			return
		if SteamSvc.invite_friend(int(value)):
			Notify.success(Loc.t("online.invited"))
	)


func _on_match_list(_lobbies: Array) -> void:
	_populate_lobby_list()
	Notify.info(Loc.tp("online.list_received", SteamSvc.last_lobby_list.size()))


func _on_lobby_joined(lobby_id: int) -> void:
	Session.lobby["lobby_id"] = lobby_id
	Net.notify_lobby_joined(lobby_id)
	Nav.go(Nav.ROUTE_LOBBY, {"lobby_id": lobby_id})


func _on_lobby_join_failed(response: int) -> void:
	Notify.error(Loc.t("steam.error_lobby_join_failed", {"code": response}))


func _on_invite(lobby_id: int, inviter: int) -> void:
	var name := SteamSvc.member_name(inviter)
	Notify.confirm(
		Loc.t("online.invite_title"),
		Loc.t("online.invite_body", {"name": name}),
		Loc.t("online.join"),
		func(accepted: bool) -> void:
			if accepted:
				SteamSvc.join_lobby(lobby_id)
	)


func refresh_texts() -> void:
	_rebuild()
