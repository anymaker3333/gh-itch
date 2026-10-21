class_name TicketToRideView
extends GameView
## Ticket to Ride: Europe table: a schematic map of the 47 routes over the 43
## cities, the face-up market row, the local player's hand and tickets, the
## destination-ticket offer, tunnel exploration and the final-round banner.
##
## The view never mutates the engine: map clicks and card clicks only submit
## action keys, and every panel is rebuilt from `engine.public_state()` plus the
## acting player's `private_state()` (hand, kept tickets, pending offer).

const MAP_SIZE: Vector2 = Vector2(1000, 680)
const CITY_DOT: float = 5.0

const SEAT_COLORS: Array[Color] = [
	Color("4ea1ff"), Color("39d98a"), Color("ffc24b"),
	Color("ff5f6d"), Color("b98cff"),
]

const CARD_COLORS: Dictionary = {
	"purple": Color("9b6bd6"),
	"blue": Color("4ea1ff"),
	"orange": Color("e08b3c"),
	"white": Color("e8eef8"),
	"green": Color("39b54a"),
	"yellow": Color("e3c94b"),
	"black": Color("6b7789"),
	"red": Color("d64545"),
	"locomotive": Color("8ecbff"),
	"grey": Color("93a1b8"),
}

## Normalised city positions for the schematic map (west to east, north to south).
const CITY_POS: Dictionary = {
	"edinburgh": Vector2(0.22, 0.10), "london": Vector2(0.29, 0.24),
	"dieppe": Vector2(0.31, 0.35), "brest": Vector2(0.12, 0.37),
	"paris": Vector2(0.35, 0.40), "bruxelles": Vector2(0.41, 0.31),
	"amsterdam": Vector2(0.43, 0.22), "rotterdam": Vector2(0.45, 0.27),
	"essen": Vector2(0.49, 0.23), "hamburg": Vector2(0.53, 0.15),
	"berlin": Vector2(0.59, 0.23), "frankfurt": Vector2(0.51, 0.33),
	"munchen": Vector2(0.55, 0.42), "zurich": Vector2(0.48, 0.48),
	"geneve": Vector2(0.44, 0.55), "marseille": Vector2(0.42, 0.66),
	"barcelona": Vector2(0.33, 0.74), "pamplona": Vector2(0.27, 0.66),
	"madrid": Vector2(0.23, 0.77), "lisboa": Vector2(0.08, 0.80),
	"cadiz": Vector2(0.15, 0.90), "sevilla": Vector2(0.19, 0.84),
	"wien": Vector2(0.63, 0.45), "venezia": Vector2(0.57, 0.53),
	"roma": Vector2(0.57, 0.63), "palermo": Vector2(0.59, 0.77),
	"kobenhavn": Vector2(0.57, 0.07), "stockholm": Vector2(0.65, 0.02),
	"petrograd": Vector2(0.79, 0.06), "riga": Vector2(0.73, 0.16),
	"wilno": Vector2(0.73, 0.27), "smolensk": Vector2(0.85, 0.20),
	"moskva": Vector2(0.91, 0.14), "kyiv": Vector2(0.81, 0.41),
	"bucuresti": Vector2(0.77, 0.53), "constantinopoli": Vector2(0.87, 0.61),
	"angora": Vector2(0.91, 0.69), "erzurum": Vector2(0.95, 0.62),
	"sofia": Vector2(0.77, 0.61), "athina": Vector2(0.73, 0.75),
	"sarajevo": Vector2(0.67, 0.61), "zagreb": Vector2(0.63, 0.55),
	"budapest": Vector2(0.69, 0.47),
}

var _map: Control
var _status: Label
var _market_box: HBoxContainer
var _market_counts: Label
var _hand_box: HFlowContainer
var _tickets_box: VBoxContainer
var _players_box: VBoxContainer
var _context_box: VBoxContainer
var _selected_route: int = -1
var _offer_selection: Array = []


func requires_handover() -> bool:
	return true


func build_board() -> void:
	var layout := UI.row(14)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var left := UI.column(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	_map = Control.new()
	_map.custom_minimum_size = MAP_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_on_map_draw)
	_map.gui_input.connect(_on_map_input)
	left.add_child(UI.scroll(_map, true))
	_status = UI.label("", "Small")
	left.add_child(_status)

	var side := UI.column(10)
	side.custom_minimum_size = Vector2(430, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(side)
	_context_box = UI.column(8)
	side.add_child(_context_box)
	side.add_child(UI.divider())
	side.add_child(UI.section_header(Loc.t("game.ticket_to_ride_europe.view.market_title"),
		Loc.t("game.ticket_to_ride_europe.view.market_hint")))
	_market_box = UI.row(8)
	side.add_child(_market_box)
	_market_counts = UI.label("", "Caption")
	side.add_child(_market_counts)
	side.add_child(UI.divider())
	side.add_child(UI.section_header(Loc.t("game.ticket_to_ride_europe.view.hand_title"),
		Loc.t("game.ticket_to_ride_europe.view.hand_hint")))
	_hand_box = UI.flow(6, 6)
	side.add_child(_hand_box)
	side.add_child(UI.section_header(Loc.t("game.ticket_to_ride_europe.view.tickets_title"),
		Loc.t("game.ticket_to_ride_europe.view.tickets_hint")))
	_tickets_box = UI.column(4)
	side.add_child(UI.scroll(_tickets_box, false))
	side.add_child(UI.section_header(Loc.t("game.ticket_to_ride_europe.view.players_title"),
		Loc.t("game.ticket_to_ride_europe.view.players_hint")))
	_players_box = UI.column(6)
	side.add_child(_players_box)


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	_status.text = _status_text(state)
	_refresh_context(state)
	_refresh_market(state)
	_refresh_hand()
	_refresh_tickets()
	_refresh_players(state)
	_map.queue_redraw()


# ------------------------------------------------------------------- the map

func _on_map_draw() -> void:
	if engine == null:
		return
	var size := _map.size
	var state := engine.public_state()
	var claimed: Array = VariantUtil.as_array(state.get("route_owner", []))
	var claimable := {}
	for action: Dictionary in actions_of_type("claim_route"):
		var index := VariantUtil.as_int(action.get("route", -1), -1)
		var list: Array = claimable.get(index, [])
		list.append(action)
		claimable[index] = list
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route: Dictionary = TicketToRideEngine.ROUTES[index]
		var a := _point(VariantUtil.as_string(route.get("a", ""), ""), size)
		var b := _point(VariantUtil.as_string(route.get("b", ""), ""), size)
		var colour: Color = CARD_COLORS.get(VariantUtil.as_string(route.get("colour", ""), "grey"), Palette.TEXT_MUTED)
		var owner := VariantUtil.as_int(claimed[index], -1) if index < claimed.size() else -1
		var width := 3.0
		var alpha := 0.5
		if claimable.has(index):
			alpha = 1.0
			width = 5.0
		if _selected_route == index:
			_map.draw_line(a, b, Palette.FOCUS, width + 6.0)
		elif claimable.has(index):
			_map.draw_line(a, b, Palette.tint(Palette.FOCUS, 0.45), width + 3.0)
		if owner >= 0:
			_map.draw_line(a, b, SEAT_COLORS[owner % SEAT_COLORS.size()], 9.0)
		var line_colour := colour
		line_colour.a = alpha
		if bool(route.get("tunnel", false)):
			_map.draw_dashed_line(a, b, line_colour, width)
		elif VariantUtil.as_int(route.get("ferries", 0), 0) > 0:
			_draw_dotted(a, b, line_colour, width)
		else:
			_map.draw_line(a, b, line_colour, width)
	for city: String in TicketToRideEngine.CITIES:
		var point := _point(city, size)
		_map.draw_circle(point, CITY_DOT, Palette.TEXT)
		_map.draw_string(ThemeDB.fallback_font, point + Vector2(7, 4),
			Loc.t("game.ticket_to_ride_europe.city.%s" % city),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT_MUTED)


func _draw_dotted(a: Vector2, b: Vector2, colour: Color, width: float) -> void:
	var steps := maxi(2, int(a.distance_to(b) / 14.0))
	for index: int in range(steps + 1):
		_map.draw_circle(a.lerp(b, float(index) / float(steps)), width * 0.9, colour)


func _point(city: String, size: Vector2) -> Vector2:
	var normalised: Vector2 = CITY_POS.get(city, Vector2(0.5, 0.5))
	return Vector2(normalised.x * size.x, normalised.y * size.y)


func _on_map_input(event: InputEvent) -> void:
	if engine == null or engine.finished:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var index := _route_at(mouse.position)
	if index < 0:
		return
	var variants := _claim_actions_for(index)
	if variants.size() == 1:
		submit(VariantUtil.as_string(variants[0].get("key", ""), ""))
		return
	_selected_route = index
	refresh_board()


func _route_at(position: Vector2) -> int:
	var size := _map.size
	var best := -1
	var best_distance := 16.0
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route: Dictionary = TicketToRideEngine.ROUTES[index]
		var a := _point(VariantUtil.as_string(route.get("a", ""), ""), size)
		var b := _point(VariantUtil.as_string(route.get("b", ""), ""), size)
		var distance := _point_segment_distance(position, a, b)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)


func _claim_actions_for(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: Dictionary in actions_of_type("claim_route"):
		if VariantUtil.as_int(action.get("route", -1), -1) == index:
			out.append(action)
	return out


# ---------------------------------------------------------------- context

func _refresh_context(state: Dictionary) -> void:
	_clear(_context_box)
	if engine.finished:
		return
	var phase := engine.phase()
	if phase == "tickets":
		_build_offer_panel(state)
	elif phase == "tunnel":
		_build_tunnel_panel(state)
	elif _selected_route >= 0:
		_build_selection_panel()
	else:
		_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.map_hint"), "Small"))
	if bool(VariantUtil.as_dict(state.get("final", {})).get("triggered", false)) and not engine.finished:
		var left := VariantUtil.as_int(VariantUtil.as_dict(state.get("final", {})).get("turns_left", 0), 0)
		_context_box.add_child(UI.chip(Loc.t("game.ticket_to_ride_europe.view.final_banner", {"turns": left}), Palette.WARNING))


func _build_offer_panel(state: Dictionary) -> void:
	var private := _private_for(acting_player())
	var offered: Array = private.get("offer", [])
	var min_keep := VariantUtil.as_int(state.get("offer_min", 1), 1)
	_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.offer_title"), "Subtitle"))
	_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.offer_hint", {"min": min_keep}), "Caption"))
	if _offer_selection.size() != offered.size():
		_offer_selection.clear()
		for _index: int in range(offered.size()):
			_offer_selection.append(true)
	var flow := UI.flow(8, 8)
	for index: int in range(offered.size()):
		var id := VariantUtil.as_string(offered[index], "")
		var face := CardFace.new()
		face.configure({
			"id": str(index),
			"title": Loc.t("game.ticket_to_ride_europe.ticket.%s" % id),
			"subtitle": Loc.t("game.ticket_to_ride_europe.view.ticket_value", {"value": _ticket_value(id)}),
			"accent": Palette.ACCENT,
			"glyph": "🎫",
			"selected": bool(_offer_selection[index]),
		}, CardFace.WIDTH_MEDIUM)
		face.clicked.connect(_on_offer_card_clicked)
		flow.add_child(face)
	_context_box.add_child(flow)
	var kept := 0
	for selected: Variant in _offer_selection:
		if bool(selected):
			kept += 1
	var confirm := UI.button(Loc.t("game.ticket_to_ride_europe.view.keep_confirm", {"count": kept}), "Button",
		func() -> void: _submit_keep())
	confirm.disabled = kept < min_keep
	_context_box.add_child(confirm)


func _on_offer_card_clicked(card_id: String) -> void:
	var index := int(card_id)
	if index >= 0 and index < _offer_selection.size():
		_offer_selection[index] = not bool(_offer_selection[index])
		refresh_board()


func _submit_keep() -> void:
	var keep := PackedStringArray()
	for index: int in range(_offer_selection.size()):
		if bool(_offer_selection[index]):
			keep.append(str(index))
	var wanted := ",".join(keep)
	for action: Dictionary in legal_actions():
		if VariantUtil.as_string(action.get("type", ""), "") == "keep_tickets" and VariantUtil.as_string(action.get("keep", ""), "") == wanted:
			submit(VariantUtil.as_string(action.get("key", ""), ""))
			return


func _build_tunnel_panel(state: Dictionary) -> void:
	var tunnel: Dictionary = state.get("tunnel", {})
	var route := VariantUtil.as_int(tunnel.get("route", -1), -1)
	_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.tunnel_title",
		{"route": Loc.t("game.ticket_to_ride_europe.route.%s" % VariantUtil.as_string(TicketToRideEngine.ROUTES[clampi(route, 0, TicketToRideEngine.ROUTES.size() - 1)].get("id", ""), "?"))}), "Subtitle"))
	var flow := UI.flow(8, 8)
	for card: Variant in tunnel.get("revealed", []):
		var card_id := VariantUtil.as_string(card, "")
		var face := CardFace.new()
		face.configure({
			"id": card_id,
			"title": Loc.t("game.ticket_to_ride_europe.colour.%s" % card_id),
			"accent": CARD_COLORS.get(card_id, Palette.TEXT_MUTED),
			"glyph": "🚇",
		}, CardFace.WIDTH_SMALL)
		flow.add_child(face)
	_context_box.add_child(flow)
	_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.tunnel_hint",
		{"extra": VariantUtil.as_int(tunnel.get("extra", 0), 0)}), "Body"))
	var row := UI.flow(8, 8)
	for action: Dictionary in actions_of_type("pay_tunnel"):
		row.add_child(UI.button(Loc.t("game.ticket_to_ride_europe.view.tunnel_pay"), "Button",
			func() -> void: submit(VariantUtil.as_string(action.get("key", ""), ""))))
	for action: Dictionary in actions_of_type("abort_tunnel"):
		row.add_child(UI.button(Loc.t("game.ticket_to_ride_europe.view.tunnel_abort"), "GhostButton",
			func() -> void: submit(VariantUtil.as_string(action.get("key", ""), ""))))
	_context_box.add_child(row)


func _build_selection_panel() -> void:
	var route: Dictionary = TicketToRideEngine.ROUTES[clampi(_selected_route, 0, TicketToRideEngine.ROUTES.size() - 1)]
	_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.claim_route", {
		"route": engine.route_name(_selected_route),
	}), "Subtitle"))
	_context_box.add_child(UI.label(_route_description(route), "Small"))
	var variants := _claim_actions_for(_selected_route)
	if variants.is_empty():
		_context_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.claim_unavailable"), "Caption"))
		return
	for action: Dictionary in variants:
		var colour := VariantUtil.as_string(action.get("colour", ""), "")
		var button := UI.button(Loc.t("game.ticket_to_ride_europe.view.claim_with", {
			"colour": Loc.t("game.ticket_to_ride_europe.colour.%s" % colour),
		}), "Button", func() -> void: submit(VariantUtil.as_string(action.get("key", ""), "")))
		_context_box.add_child(button)


func _route_description(route: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append(Loc.t("game.ticket_to_ride_europe.view.route_desc", {
		"length": VariantUtil.as_int(route.get("length", 0), 0),
		"colour": Loc.t("game.ticket_to_ride_europe.colour.%s" % VariantUtil.as_string(route.get("colour", ""), "grey")),
	}))
	var ferries := VariantUtil.as_int(route.get("ferries", 0), 0)
	if ferries > 0:
		parts.append(Loc.t("game.ticket_to_ride_europe.view.route_ferry", {"ferries": ferries}))
	if bool(route.get("tunnel", false)):
		parts.append(Loc.t("game.ticket_to_ride_europe.view.route_tunnel"))
	return " · ".join(parts)


# ------------------------------------------------------------------ panels

func _refresh_market(state: Dictionary) -> void:
	_clear(_market_box)
	var face_up: Array = state.get("face_up", [])
	var takeable := {}
	for action: Dictionary in actions_of_type("draw_face"):
		takeable[VariantUtil.as_int(action.get("slot", -1), -1)] = true
	for slot: int in range(face_up.size()):
		var card := VariantUtil.as_string(face_up[slot], "")
		var face := CardFace.new()
		face.configure({
			"id": str(slot),
			"title": Loc.t("game.ticket_to_ride_europe.colour.%s" % card),
			"accent": CARD_COLORS.get(card, Palette.TEXT_MUTED),
			"glyph": "🚃",
			"dimmed": not takeable.has(slot),
		}, CardFace.WIDTH_SMALL)
		face.clicked.connect(_on_market_clicked)
		_market_box.add_child(face)
	_market_counts.text = Loc.t("game.ticket_to_ride_europe.view.market_counts", {
		"deck": VariantUtil.as_int(state.get("deck_count", 0), 0),
		"discard": VariantUtil.as_int(state.get("discard_count", 0), 0),
		"tickets": VariantUtil.as_int(state.get("tickets_left", 0), 0),
	})


func _on_market_clicked(card_id: String) -> void:
	var slot := int(card_id)
	for action: Dictionary in actions_of_type("draw_face"):
		if VariantUtil.as_int(action.get("slot", -1), -1) == slot:
			submit(VariantUtil.as_string(action.get("key", ""), ""))
			return


func _refresh_hand() -> void:
	_clear(_hand_box)
	var player := acting_player()
	var private := _private_for(player)
	var hand: Dictionary = private.get("hand", {})
	var total := 0
	for colour: String in TicketToRideEngine.COLOURS + [TicketToRideEngine.LOCOMOTIVE]:
		var count := VariantUtil.as_int(hand.get(colour, 0), 0)
		total += count
		if count <= 0:
			continue
		var chip := UI.chip(Loc.t("game.ticket_to_ride_europe.view.hand_chip", {
			"colour": Loc.t("game.ticket_to_ride_europe.colour.%s" % colour),
			"count": count,
		}), CARD_COLORS.get(colour, Palette.TEXT_MUTED))
		_hand_box.add_child(chip)
	if total == 0:
		_hand_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.hand_empty"), "Small"))


func _refresh_tickets() -> void:
	_clear(_tickets_box)
	var player := acting_player()
	var private := _private_for(player)
	var tickets: Array = private.get("tickets", [])
	if tickets.is_empty():
		_tickets_box.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.tickets_empty"), "Small"))
		return
	for id: Variant in tickets:
		var ticket_id := VariantUtil.as_string(id, "")
		var row := UI.row(6)
		var value := _ticket_value(ticket_id)
		var label := UI.label(Loc.t("game.ticket_to_ride_europe.ticket.%s" % ticket_id), "Small")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(UI.label(Loc.t("game.ticket_to_ride_europe.view.ticket_value", {"value": value}), "Caption"))
		_tickets_box.add_child(row)


func _refresh_players(state: Dictionary) -> void:
	_clear(_players_box)
	var trains: Array = state.get("trains_left", [])
	var hands: Array = state.get("hand_count", [])
	var tickets: Array = state.get("ticket_count", [])
	var points: Array = state.get("route_points", [])
	for player: int in range(engine.player_count()):
		var box := UI.column(2)
		var title := UI.row(6)
		var name_label := UI.label(engine.player_name(player), "Body")
		name_label.add_theme_color_override("font_color", SEAT_COLORS[player % SEAT_COLORS.size()])
		title.add_child(name_label)
		if engine.decision_player() == player and not engine.finished:
			title.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
		box.add_child(title)
		box.add_child(UI.kv_row(Loc.t("game.ticket_to_ride_europe.view.players_trains"),
			Loc.tp("game.ticket_to_ride_europe.view.trains_left", _at(trains, player))))
		box.add_child(UI.kv_row(Loc.t("game.ticket_to_ride_europe.view.players_cards"),
			Loc.tp("game.ticket_to_ride_europe.view.cards_in_hand", _at(hands, player))))
		box.add_child(UI.kv_row(Loc.t("game.ticket_to_ride_europe.view.players_tickets"),
			Loc.tp("game.ticket_to_ride_europe.view.tickets_held", _at(tickets, player))))
		box.add_child(UI.kv_row(Loc.t("game.ticket_to_ride_europe.view.players_points"), str(_at(points, player))))
		_players_box.add_child(UI.panel_with(box, "CardPanel", 8))


## A public-state array shorter than the seating (mid-setup replica) must not
## crash a per-seat render loop; a missing entry reads as zero.
static func _at(source: Array, index: int) -> int:
	if index >= 0 and index < source.size():
		return VariantUtil.as_int(source[index], 0)
	return 0


func _status_text(state: Dictionary) -> String:
	if engine.finished:
		return Loc.t("game.common.finished_status", {"winner": engine.winner_text()})
	var lines := PackedStringArray()
	lines.append(engine.phase_hint())
	lines.append(Loc.t("game.ticket_to_ride_europe.view.status_round", {
		"round": engine.round_index,
		"cap": VariantUtil.as_int(state.get("turn_cap", 0), 0),
	}))
	lines.append(Loc.t("game.ticket_to_ride_europe.view.legend"))
	return "\n".join(lines)


func _ticket_value(id: String) -> int:
	for entry: Dictionary in TicketToRideEngine.TICKETS:
		if VariantUtil.as_string(entry.get("id", ""), "") == id:
			return VariantUtil.as_int(entry.get("value", 0), 0)
	return 0


func _private_for(_player: int) -> Dictionary:
	# §6.3: private data reaches views only through the authorized helper.
	return private_info()


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
