extends ScreenBase
## In-game screen: shared frame around every game's board view.
##
## Provides the player strip, turn/phase indicator, move log, action bar,
## privacy handover for hotseat hidden-information games, connection status for
## online matches and the end-of-match dialog. Game-specific presentation lives
## in the [GameView] subclass registered for the game.

const VIEW_SCRIPTS: Dictionary = {
	"citadels": "res://scripts/games/citadels/citadels_view.gd",
	"codenames": "res://scripts/games/codenames/codenames_view.gd",
	"dany": "res://scripts/games/dany/dany_view.gd",
	"spyfall": "res://scripts/games/spyfall/spyfall_view.gd",
	"chess": "res://scripts/games/chess/chess_view.gd",
	"durak": "res://scripts/games/durak/durak_view.gd",
	"bridge": "res://scripts/games/bridge/bridge_view.gd",
	"king": "res://scripts/games/king/king_view.gd",
	"monopoly": "res://scripts/games/monopoly/monopoly_view.gd",
	"ticket_to_ride_europe": "res://scripts/games/ticket_to_ride/ticket_to_ride_view.gd",
	"coup": "res://scripts/games/coup/coup_view.gd",
	"splendor": "res://scripts/games/splendor/splendor_view.gd",
	"star_realms": "res://scripts/games/star_realms/star_realms_view.gd",
}

var view: GameView = null
var _game_split: HSplitContainer
var _side_panel: Control
var _board_host: MarginContainer
var _board_scroll: ScrollContainer
var _players_strip: HFlowContainer
var _status_label: Label
var _log_list: VBoxContainer
var _action_row: HBoxContainer
var _action_panel: PanelContainer
var _extra_actions: HBoxContainer
var _handover: Control
var _handover_label: Label
var _handover_button: Button
var _confirmed_player: int = -1
var _end_dialog_shown: bool = false
var _net_label: Label
var _log_title: Label
var _log_toggle: Button
var _log_hide: Button
var _log_width: int = 340
var _log_visible: bool = true
var _log_preferred_visible: bool = true
var _log_user_override: bool = false
var _log_was_compact: bool = false


func build() -> void:
	var layout := HSplitContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	layout.add_theme_constant_override("separation", 12)
	_game_split = layout
	_log_width = clampi(int(Prefs.get_value("general/log_width", 340)), 260, 620)
	_log_preferred_visible = bool(Prefs.get_value("general/log_visible", true))
	_log_visible = _log_preferred_visible
	add_child(UI.margin_xy(layout, 16, 10, 16, 12))

	var main_column := UI.column(12)
	main_column.custom_minimum_size = Vector2(520, 0)
	main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(main_column)

	# --- status strip -------------------------------------------------------
	var strip := UI.panel("CardPanel")
	main_column.add_child(strip)
	var strip_row := UI.row(12)
	strip.add_child(UI.margin_container(strip_row, 10))
	_players_strip = UI.flow(8, 8)
	_players_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(_players_strip)
	# Keep the turn status on one line. A wrapping label in this row has a
	# minimum width of 1 px, so an HBox spacer would squeeze it into a vertical
	# column and inflate the whole match screen to several thousand pixels.
	_status_label = UI.label("", "Body")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip_row.add_child(_status_label)
	_log_toggle = UI.icon_button("▤", Loc.t("game.common.log"), _toggle_log)
	strip_row.add_child(_log_toggle)

	# --- board --------------------------------------------------------------
	var board_panel := UI.panel("CardPanel")
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_column.add_child(board_panel)
	_board_host = UI.margin_container(null, 12)
	_board_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.add_child(_board_host)
	# Some tables (Star Realms, Bridge, Monopoly) are deliberately larger than
	# the board panel. Scrolling keeps every control reachable instead of
	# clipping the hand or the far side of the board.
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_host.add_child(_board_scroll)

	# --- action bar ---------------------------------------------------------
	var action_panel := UI.panel("ElevatedPanel")
	_action_panel = action_panel
	action_panel.resized.connect(_update_toast_inset)
	main_column.add_child(action_panel)
	var action_box := UI.column(8)
	action_panel.add_child(UI.margin_container(action_box, 10))
	# Keep the action bar to one row even when a game offers many actions. A
	# horizontal scroll container contributes no minimum width to the split, so
	# a long Coup action list can no longer push the log panel off-screen.
	var action_scroll := ScrollContainer.new()
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.custom_minimum_size = Vector2(0, 44)
	action_box.add_child(action_scroll)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 4)
	_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(_action_row)
	# One compact action row: primary actions first, destructive actions right.
	_extra_actions = _action_row

	# --- side panel ---------------------------------------------------------
	_side_panel = UI.column(12)
	_side_panel.custom_minimum_size = Vector2(_log_width, 0)
	_side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_panel.visible = _log_visible
	layout.add_child(_side_panel)
	var log_panel := UI.panel("CardPanel")
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_panel.add_child(log_panel)
	var log_box := UI.column(8)
	log_panel.add_child(UI.margin_container(log_box, 12))
	var log_header := UI.row(6)
	log_box.add_child(log_header)
	_log_title = UI.heading(Loc.t("game.common.log"), "Subtitle")
	_log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_header.add_child(_log_title)
	_log_hide = UI.icon_button("–", Loc.t("common.close"), _hide_log)
	log_header.add_child(_log_hide)
	_net_label = UI.label("", "Caption")
	log_box.add_child(_net_label)
	log_box.add_child(UI.divider())
	var log_scroll := UI.scroll(UI.column(6), false)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_child(log_scroll)
	_log_list = log_scroll.get_child(0) as VBoxContainer
	layout.split_offset = 100000
	layout.dragged.connect(_on_log_dragged)
	resized.connect(_on_resized)
	_update_log_toggle()
	call_deferred("_apply_responsive_log")

	_handover = _build_handover()
	add_child(_handover)


func _build_handover() -> Control:
	var panel := UI.panel("ElevatedPanel")
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	var box := UI.column(16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(UI.margin_container(box, 24))
	box.add_child(UI.centered("🙈", "Display"))
	_handover_label = UI.centered("", "Subtitle")
	box.add_child(_handover_label)
	var buttons := UI.row(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_handover_button = UI.button(Loc.t("game.common.ready"), "PrimaryButton", func() -> void:
		_confirmed_player = engine_player()
		_handover.visible = false
		view.visible = true
		_refresh_board()
	)
	buttons.add_child(_handover_button)
	box.add_child(buttons)
	return panel


func on_enter() -> void:
	if Session.current == null or Session.current.engine == null:
		Log.warn("GameScreen: no active session, returning to library")
		Nav.reset_to(Nav.ROUTE_LIBRARY)
		return
	_load_view()
	Session.current.state_updated.connect(_on_state_updated)
	Session.current.private_state_updated.connect(_on_state_updated)
	Session.current.action_rejected.connect(_on_action_rejected)
	Session.current.notice.connect(_on_notice)
	Net.link_state_changed.connect(_on_link_changed)
	Net.transport_error.connect(_on_transport_error)
	title_key = "game.%s.name" % Session.current.game_id
	subtitle_key = "game.%s.desc" % Session.current.game_id
	_end_dialog_shown = false
	_confirmed_player = -1
	_refresh_all()
	call_deferred("_update_toast_inset")


func on_exit() -> void:
	var shell := _find_shell()
	if shell != null and shell.toasts != null:
		shell.toasts.set_bottom_inset(0)
	if Session.current != null:
		if Session.current.state_updated.is_connected(_on_state_updated):
			Session.current.state_updated.disconnect(_on_state_updated)
		if Session.current.private_state_updated.is_connected(_on_state_updated):
			Session.current.private_state_updated.disconnect(_on_state_updated)
		if Session.current.action_rejected.is_connected(_on_action_rejected):
			Session.current.action_rejected.disconnect(_on_action_rejected)
		if Session.current.notice.is_connected(_on_notice):
			Session.current.notice.disconnect(_on_notice)
	if Net.link_state_changed.is_connected(_on_link_changed):
		Net.link_state_changed.disconnect(_on_link_changed)
	if Net.transport_error.is_connected(_on_transport_error):
		Net.transport_error.disconnect(_on_transport_error)


func _load_view() -> void:
	var game_id := Session.current.game_id
	var path := String(VIEW_SCRIPTS.get(game_id, ""))
	for child: Node in _board_scroll.get_children():
		_board_scroll.remove_child(child)
		child.queue_free()
	view = null
	if path.is_empty() or not ResourceLoader.exists(path):
		Log.error("GameScreen: no view registered", {"game": game_id, "path": path})
		_board_scroll.add_child(UI.centered(Loc.t("game.common.view_missing"), "Subtitle"))
		return
	var script := load(path) as GDScript
	if script == null:
		return
	var instance: Variant = script.new()
	if not (instance is GameView):
		Log.error("GameScreen: view script is not a GameView", {"path": path})
		return
	view = instance
	_board_scroll.add_child(view)
	view.action_requested.connect(_on_view_action)
	view.view_message.connect(func(message_key: String, args: Dictionary) -> void:
		Notify.info(Loc.t(message_key, args))
	)
	view.configure(Session.current)


func engine_player() -> int:
	if Session.current == null or Session.current.engine == null:
		return -1
	if Session.current.is_online():
		return Session.current.local_player
	return Session.current.engine.decision_player()


# ------------------------------------------------------------------ log panel

func _toggle_log() -> void:
	_log_user_override = true
	_set_log_visible(not _log_visible)


func _hide_log() -> void:
	_log_user_override = true
	_set_log_visible(false)


func _set_log_visible(visible: bool, persist: bool = true) -> void:
	_log_visible = visible
	if _side_panel != null:
		_side_panel.visible = visible
	if visible and _game_split != null:
		_game_split.split_offset = maxi(0, int(_game_split.size.x) - _log_width)
	_update_log_toggle()
	if persist:
		_log_preferred_visible = visible
		Prefs.set_value("general/log_visible", visible)


## Below roughly 1500 px the log costs more than it gives: it squeezes the table
## and causes horizontal overflow in card games. Hide it automatically, but keep
## an explicit user choice until the window crosses the breakpoint again.
func _apply_responsive_log() -> void:
	if not is_inside_tree():
		return
	var compact := size.x > 0.0 and size.x < 1500.0
	if compact != _log_was_compact:
		_log_was_compact = compact
		_log_user_override = false
	if _log_user_override:
		return
	if compact:
		if _log_visible:
			_set_log_visible(false, false)
	elif _log_visible != _log_preferred_visible:
		_set_log_visible(_log_preferred_visible, false)


func _on_resized() -> void:
	_apply_responsive_log()
	_update_toast_inset()


## Keep transient notifications above the persistent action bar instead of
## covering the primary game actions in the bottom-right corner.
func _update_toast_inset() -> void:
	if _action_panel == null:
		return
	var shell := _find_shell()
	if shell == null or shell.toasts == null:
		return
	shell.toasts.set_bottom_inset(int(_action_panel.size.y) + 16)


func _find_shell() -> AppShell:
	var node: Node = get_parent()
	while node != null:
		if node is AppShell:
			return node as AppShell
		node = node.get_parent()
	return null


func _on_log_dragged(offset: int) -> void:
	if _game_split == null:
		return
	_log_width = clampi(int(_game_split.size.x) - offset, 260, 620)
	if _side_panel != null:
		_side_panel.custom_minimum_size = Vector2(_log_width, 0)
	Prefs.set_value("general/log_width", _log_width)


func _update_log_toggle() -> void:
	if _log_toggle != null:
		var action_key := "game.common.log_hide" if _log_visible else "game.common.log_show"
		_log_toggle.tooltip_text = Loc.t(action_key) + " (Ctrl+L)"
	if _log_hide != null:
		_log_hide.tooltip_text = Loc.t("game.common.log_hide")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key_event := event as InputEventKey
		if key_event.ctrl_pressed and key_event.keycode == KEY_L:
			_toggle_log()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	_refresh_players()
	_refresh_status()
	_refresh_actions()
	_refresh_board()
	_refresh_log()
	_refresh_handover()


func _refresh_players() -> void:
	for child: Node in _players_strip.get_children():
		_players_strip.remove_child(child)
		child.queue_free()
	if Session.current == null or Session.current.engine == null:
		return
	var engine := Session.current.engine
	for index: int in range(engine.player_count()):
		var box := UI.row(6)
		var name_label := UI.label(engine.player_name(index), "Small")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if index == engine.decision_player() and not engine.finished:
			name_label.add_theme_color_override("font_color", Palette.POSITIVE)
		box.add_child(name_label)
		if engine.is_bot(index):
			box.add_child(UI.chip(Loc.t("game.common.bot"), Palette.TEXT_MUTED))
		if index == engine.winner_index():
			box.add_child(UI.chip("🏆", Palette.WARNING))
		_players_strip.add_child(UI.panel_with(box, "ElevatedPanel", 8))


func _refresh_status() -> void:
	if Session.current == null or Session.current.engine == null:
		return
	var engine := Session.current.engine
	if engine.finished:
		_status_label.text = Loc.t("game.common.finished_status", {"winner": engine.winner_text()})
		return
	var phase := Loc.t("game.%s.phase.%s" % [engine.game_id(), engine.phase()]) if Loc.has_key("game.%s.phase.%s" % [engine.game_id(), engine.phase()]) else engine.phase()
	var turn_name := engine.player_name(engine.decision_player())
	var text := Loc.t("game.common.turn_of", {"player": turn_name, "phase": phase, "round": engine.round_index})
	if Session.current.is_online():
		var mine := engine.decision_player() == Session.current.local_player
		text += "  ·  " + (Loc.t("game.common.your_turn") if mine else Loc.t("game.common.waiting"))
	_net_label.text = "" if not Session.current.is_online() else Loc.t("net.status_line", {
		"transport": Net.transport_name(),
		"peers": Net.peers.size(),
		"link": Net.link_name(),
	})
	_status_label.text = text


func _refresh_actions() -> void:
	for child: Node in _action_row.get_children():
		_action_row.remove_child(child)
		child.queue_free()
	if Session.current == null or Session.current.engine == null:
		return
	var engine := Session.current.engine
	var my_turn := view == null or view.is_my_turn()
	if not my_turn:
		_action_row.add_child(UI.label(Loc.t("game.common.waiting_for", {"player": engine.player_name(engine.decision_player())}), "Small"))
	else:
		var actions: Array = Session.current.available_actions()
		var grouped: Dictionary = {}
		for action: Variant in actions:
			if not (action is Dictionary):
				continue
			var entry: Dictionary = action
			var label_key := String(entry.get("label_key", ""))
			if label_key.is_empty():
				continue
			# Actions that request a target/selection are rendered by the board view;
			# here we only surface the "simple" ones (submit immediately). Engines
			# mark those with `_direct` (see docs/GAME_ENGINE_CONTRACT.md).
			if bool(entry.get("_direct", true)):
				grouped[label_key] = entry
		for label_key: Variant in grouped:
			var action: Dictionary = grouped[label_key]
			var button := UI.button(Loc.t(String(label_key)), "PrimaryButton", func() -> void:
				Session.current.submit_action_key(String(action.get("key", "")))
			)
			button.disabled = not bool(action.get("enabled", true))
			_action_row.add_child(button)
		if grouped.is_empty():
			var hint := UI.label(Loc.t("game.common.pick_from_board"), "Caption")
			hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_action_row.add_child(hint)
	if view != null:
		for extra: Control in view.action_bar_extras():
			_extra_actions.add_child(extra)
	_extra_actions.visible = _extra_actions.get_child_count() > 0
	_action_row.add_child(UI.spacer())
	var resign := UI.button(Loc.t("game.common.resign"), "DangerOutline", func() -> void:
		Notify.confirm(Loc.t("game.common.resign"), Loc.t("game.common.resign_confirm"), Loc.t("game.common.resign"), func(accepted: bool) -> void:
			if accepted and Session.current != null:
				Session.current.resign(engine_player())
		, Loc.t("common.cancel"), true)
	)
	resign.disabled = engine.finished
	_extra_actions.add_child(resign)
	var leave := UI.button(Loc.t("game.common.leave"), "Button", func() -> void:
		_request_leave()
	)
	_extra_actions.add_child(leave)
	_extra_actions.visible = true


func _refresh_board() -> void:
	if view != null:
		view.local_player = engine_player()
		view.refresh_board()


func _refresh_log() -> void:
	for child: Node in _log_list.get_children():
		_log_list.remove_child(child)
		child.queue_free()
	if Session.current == null or Session.current.engine == null:
		return
	for entry: Dictionary in Session.current.engine.recent_log(20):
		var row := UI.row(6)
		var turn_label := UI.label("R%d" % int(entry.get("round", 1)), "Caption")
		turn_label.custom_minimum_size = Vector2(28, 0)
		row.add_child(turn_label)
		var text := UI.label(view.log_text(entry) if view != null else String(entry.get("text", "")), "Small")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_log_list.add_child(row)


func _refresh_handover() -> void:
	if view == null or not view.requires_handover() or Session.current == null:
		_handover.visible = false
		return
	if Session.current.is_online():
		_handover.visible = false
		return
	var player := Session.current.engine.decision_player()
	if _confirmed_player < 0:
		# The first acting player is already looking at the device; later turns
		# must pass it explicitly before the next hand is revealed.
		_confirmed_player = player
		_handover.visible = false
		view.visible = true
		return
	if _confirmed_player == player:
		_handover.visible = false
		view.visible = true
		return
	if _confirmed_player != player and Session.current.engine.players.size() > 1:
		_handover_label.text = Loc.t("game.common.handover", {"player": Session.current.engine.player_name(player)})
		_handover.visible = true
		view.visible = false
	else:
		_handover.visible = false
		view.visible = true


# ------------------------------------------------------------------ signals

func _on_state_updated() -> void:
	if Session.current == null:
		return
	_refresh_all()
	if Session.current.engine != null and Session.current.engine.finished and not _end_dialog_shown:
		_end_dialog_shown = true
		_show_end_dialog()


func _on_view_action(key: String) -> void:
	if Session.current == null:
		return
	Session.current.submit_action_key(key)
	Audio.play(Audio.Sfx.CARD)


func _on_action_rejected(reason_key: String, detail: String) -> void:
	_extra_actions.visible = true
	Notify.error(Loc.t(reason_key, {"detail": detail}) if Loc.has_key(reason_key) else Loc.t("game.common.illegal_action"))
	Audio.play(Audio.Sfx.ERROR)


func _on_notice(message_key: String, args: Dictionary) -> void:
	Notify.info(Loc.t(message_key, args))


func _on_link_changed(state: int, _detail: String) -> void:
	if Session.current == null or not Session.current.is_online():
		return
	if state == Net.Link.DISCONNECTING or state == Net.Link.OFFLINE:
		Notify.warning(Loc.t("net.notice_link_lost"))
	_refresh_status()


func _on_transport_error(context: String, detail: String) -> void:
	Notify.error(Loc.t("net.transport_error_detail", {"context": context, "detail": detail}))


# --------------------------------------------------------------- end of match

func _show_end_dialog() -> void:
	var engine := Session.current.engine
	var body := Loc.t("game.common.result_body", {"winner": engine.winner_text()})
	var scores := engine.scores_text()
	if not scores.is_empty():
		body += "\n\n" + scores
	_extra_actions.visible = true
	Notify.alert(Loc.t("game.common.match_over"), body)
	Audio.play(Audio.Sfx.WIN if engine.winner_index() == engine_player() else Audio.Sfx.LOSE)
	_refresh_actions()


func _request_leave() -> void:
	var running := Session.current != null and Session.current.engine != null and not Session.current.engine.finished
	if not running:
		_leave_match()
		return
	Notify.confirm(Loc.t("game.common.leave"), Loc.t("game.common.leave_confirm"), Loc.t("game.common.leave"), func(accepted: bool) -> void:
		if accepted:
			_leave_match()
	, Loc.t("common.cancel"), true)


func _leave_match() -> void:
	var game_id := Session.current.game_id if Session.current != null else ""
	Session.end_session()
	if Catalog.exists(game_id):
		Nav.go(Nav.ROUTE_GAME_DETAILS, {"game_id": game_id}, "replace")
	else:
		Nav.go(Nav.ROUTE_LIBRARY, {}, "replace")


func allows_back() -> bool:
	## Leaving a running match must be confirmed; the flow is handled by on_back.
	if Session.current == null or Session.current.engine == null:
		return true
	return Session.current.engine.finished


func on_back() -> bool:
	_request_leave()
	return true


func refresh_texts() -> void:
	if _log_title != null:
		_log_title.text = Loc.t("game.common.log")
	if _handover_button != null:
		_handover_button.text = Loc.t("game.common.ready")
	_update_log_toggle()
	# Game views build many static labels once (tab names, hints, prompts). A
	# fresh view is the cheapest way to guarantee that a live language switch
	# updates all of them without touching the match state.
	if view != null and Session.current != null:
		_load_view()
	_refresh_all()
