class_name MonopolyView
extends GameView
## Monopoly table: the standard ring board in a compact 11x11 grid, a player
## panel, and context panels for buying, auctions, trades, building and jail.
##
## The view never mutates the engine: clicks only submit action keys, and every
## panel is rebuilt from `engine.public_state()` plus the acting player's
## `private_state()` (the pending trade offer).

const BOARD_SIDE: int = 11
const CELL: Vector2 = Vector2(70, 42)

const GROUP_COLORS: Dictionary = {
	"brown": Color("8a5a44"),
	"light_blue": Color("7ec8e3"),
	"pink": Color("d96b9c"),
	"orange": Color("e08b3c"),
	"red": Color("d64545"),
	"yellow": Color("e3c94b"),
	"green": Color("3f9e5f"),
	"dark_blue": Color("3f62c4"),
}

const PLAYER_COLORS: Array[Color] = [
	Color("4ea1ff"), Color("39d98a"), Color("ffc24b"),
	Color("ff5f6d"), Color("b98cff"), Color("5ac8fa"),
]

var _cells: Array[Button] = []
var _grid: GridContainer
var _status: Label
var _players_box: VBoxContainer
var _context_box: VBoxContainer
var _details: Label
var _details_title: Label
var _side: VBoxContainer


func requires_handover() -> bool:
	return true


func build_board() -> void:
	var layout := UI.row(14)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var left := UI.column(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	_grid = UI.grid(BOARD_SIDE, 2, 2)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_grid)
	var cells: Array = []
	cells.resize(BOARD_SIDE * BOARD_SIDE)
	cells.fill(null)
	for space: int in range(40):
		var xy := _cell_xy(space)
		var button := Button.new()
		button.custom_minimum_size = _cell_size()
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 9)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD
		button.clip_text = true
		button.set_meta("space", space)
		button.pressed.connect(_on_cell_pressed.bind(space))
		cells[xy.x * BOARD_SIDE + xy.y] = button
		_cells.append(button)
	for index: int in range(cells.size()):
		if cells[index] == null:
			var filler := Control.new()
			filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.add_child(filler)
		else:
			_grid.add_child(cells[index])
	_status = UI.label("", "Small")
	# The shared top strip already carries turn and round; hide the duplicate
	# board footer on short windows so the bottom row is never clipped.
	_status.visible = viewport_size().y >= 820.0
	left.add_child(_status)

	_side = UI.column(0)
	_side.custom_minimum_size = Vector2(300 if _narrow() else 360, 0)
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_side)
	var side_body := UI.column(10)
	_side.add_child(UI.scroll(side_body, false))
	side_body.add_child(UI.section_header(Loc.t("game.monopoly.players_title"), Loc.t("game.monopoly.players_hint")))
	_players_box = UI.column(6)
	side_body.add_child(_players_box)
	side_body.add_child(UI.divider())
	_context_box = UI.column(8)
	side_body.add_child(_context_box)
	side_body.add_child(UI.divider())
	_details_title = UI.label(Loc.t("game.monopoly.details_title"), "Subtitle")
	side_body.add_child(_details_title)
	_details = UI.label(Loc.t("game.monopoly.details_hint"), "Small")
	side_body.add_child(_details)
	# Cells are sized from viewport geometry: apply the real measurement once the
	# view is in the tree (deferred), then again on every resize.
	_apply_cell_size()


## Re-measures the responsive cell sizes as soon as the view has real viewport
## geometry (it is built and configured before entering the scene tree) and
## again whenever the viewport size changes.
func _ready() -> void:
	# Neither GameView nor the container base script implements _ready, so the
	# built-in callback is replaced exactly here; re-apply with the real size.
	_apply_cell_size()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_cell_size)


func _narrow() -> bool:
	# Off-tree construction gets the stable default geometry from GameView;
	# `_ready()`/the deferred `_apply_cell_size()` re-measure the real window.
	return viewport_size().x < 1500.0


func _cell_size() -> Vector2:
	# At 1280x720 the full 11-row board must stay above the action bar and
	# beside the player rail. Narrower cells keep the whole ring visible;
	# tooltips still carry every detail.
	var vp := viewport_size()
	var width := 54.0 if vp.x < 1500.0 else CELL.x
	if vp.y < 820.0:
		return Vector2(width, 33)
	return Vector2(width, CELL.y)


func _apply_cell_size() -> void:
	var cell := _cell_size()
	for button: Button in _cells:
		button.custom_minimum_size = cell
	if _status != null:
		_status.visible = viewport_size().y >= 820.0
	if _side != null:
		_side.custom_minimum_size.x = 300 if _narrow() else 360


func refresh_board() -> void:
	if engine == null:
		return
	var state := engine.public_state()
	_refresh_cells(state)
	_status.text = _status_text(state)
	_refresh_players(state)
	_refresh_context(state)


func _refresh_cells(state: Dictionary) -> void:
	var positions: Array = state.get("positions", [])
	var owner: Array = state.get("owner", [])
	var houses: Array = state.get("houses", [])
	var active := int(state.get("active", 0))
	for space: int in range(40):
		var button := _cells[space]
		var data: Dictionary = MonopolyEngine.SPACES[space]
		var background := _space_color(data)
		var border := Color.TRANSPARENT
		if space < owner.size() and int(owner[space]) >= 0:
			border = PLAYER_COLORS[int(owner[space]) % PLAYER_COLORS.size()]
		var here: Array = []
		for player: int in range(engine.player_count()):
			if player < positions.size() and int(positions[player]) == space:
				here.append(engine.player_name(player))
		var text := Loc.t("game.monopoly.space.%s" % String(data.get("id", "")))
		if space < houses.size() and int(houses[space]) > 0:
			text += "\n" + ("🏨" if int(houses[space]) >= 5 else "🏠".repeat(int(houses[space])))
		if not here.is_empty():
			text += "\n▸" + ", ".join(PackedStringArray(here))
		button.text = text
		var is_active_space := active < positions.size() and space == int(positions[active])
		button.add_theme_stylebox_override("normal", _cell_style(background, border, 2 if is_active_space else 1))
		button.add_theme_stylebox_override("hover", _cell_style(background.lightened(0.12), border, 2))
		button.add_theme_stylebox_override("pressed", _cell_style(background.darkened(0.12), border, 2))
		button.tooltip_text = _space_tooltip(space, data, owner, houses)
		button.disabled = engine.finished


func _refresh_players(state: Dictionary) -> void:
	_clear(_players_box)
	var cash: Array = state.get("cash", [])
	var jail: Array = state.get("jail", [])
	var cards: Array = state.get("jail_cards", [])
	var bankrupt: Array = state.get("bankrupt", [])
	for player: int in range(engine.player_count()):
		var row := UI.column(2)
		var title := UI.flow(6, 4)
		var name_label := UI.label(engine.player_name(player), "Body")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.custom_minimum_size = Vector2(80, 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", PLAYER_COLORS[player % PLAYER_COLORS.size()])
		title.add_child(name_label)
		if int(bankrupt[player]) == 1:
			title.add_child(UI.chip(Loc.t("game.monopoly.player_bankrupt"), Palette.DANGER))
		elif int(jail[player]) == 1:
			title.add_child(UI.chip(Loc.t("game.monopoly.player_jail"), Palette.WARNING))
		if int(cards[player]) > 0:
			title.add_child(UI.chip(Loc.tp("game.monopoly.player_cards", int(cards[player])), Palette.INFO))
		if int(state.get("active", 0)) == player and not engine.finished:
			title.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
		row.add_child(title)
		var props := 0
		var owned: Array = state.get("owner", [])
		for space: int in range(owned.size()):
			if int(owned[space]) == player:
				props += 1
		row.add_child(UI.kv_row(Loc.t("game.monopoly.player_cash"), str(int(cash[player]))))
		row.add_child(UI.kv_row(Loc.t("game.monopoly.player_props"), Loc.tp("game.monopoly.props_count", props)))
		_players_box.add_child(UI.panel_with(row, "CardPanel", 8))


func _refresh_context(state: Dictionary) -> void:
	_clear(_context_box)
	var phase := engine.phase()
	match phase:
		"auction":
			_build_auction_panel(state)
		"trade":
			_build_trade_panel(state)
		"buy":
			var space := int(state.get("pending_buy", -1))
			_context_box.add_child(UI.label(Loc.t("game.monopoly.buy_hint", {
				"space": _space_name(space),
				"price": int((MonopolyEngine.SPACES[space] as Dictionary).get("price", 0)),
			}), "Body"))
			_context_box.add_child(UI.label(Loc.t("game.monopoly.buy_choose"), "Caption"))
		"jail":
			_context_box.add_child(UI.label(Loc.t("game.monopoly.jail_hint"), "Body"))
		_:
			if engine.finished:
				return
			_build_turn_panel()


func _build_auction_panel(state: Dictionary) -> void:
	var auction: Dictionary = state.get("auction", {})
	var space := int(auction.get("space", -1))
	_context_box.add_child(UI.label(Loc.t("game.monopoly.auction_title", {"space": _space_name(space)}), "Subtitle"))
	var leader := int(auction.get("leader", -1))
	_context_box.add_child(UI.label(Loc.t("game.monopoly.auction_bid", {"amount": int(auction.get("bid", 0))}), "Body"))
	if leader >= 0:
		_context_box.add_child(UI.label(Loc.t("game.monopoly.auction_leader", {"player": engine.player_name(leader)}), "Small"))
	else:
		_context_box.add_child(UI.label(Loc.t("game.monopoly.auction_no_bid"), "Small"))
	var row := UI.flow(6, 6)
	for action: Dictionary in actions_of_type("bid"):
		var button := UI.button(Loc.t("game.monopoly.bid_button", {"amount": int(action.get("amount", 0))}), "Button",
			func() -> void: submit(String(action.get("key", ""))))
		row.add_child(button)
	for action: Dictionary in actions_of_type("pass_bid"):
		row.add_child(UI.button(Loc.t("game.monopoly.pass_bid"), "GhostButton",
			func() -> void: submit(String(action.get("key", "")))))
	_context_box.add_child(row)


func _build_trade_panel(state: Dictionary) -> void:
	var private := _private_for(acting_player())
	var offer: Dictionary = private.get("trade_offer", {})
	_context_box.add_child(UI.label(Loc.t("game.monopoly.trade_title"), "Subtitle"))
	if offer.is_empty():
		_context_box.add_child(UI.label(Loc.t("game.monopoly.trade_unknown"), "Small"))
		return
	var from := int(offer.get("from", -1))
	var to := int(offer.get("to", -1))
	var take := int(offer.get("take", -1))
	var give := int(offer.get("give", -1))
	var cash := int(offer.get("cash", 0))
	var text := ""
	if give >= 0:
		text = Loc.t("game.monopoly.trade_swap_cash", {
			"from": engine.player_name(from), "give": _space_name(give),
			"amount": cash, "take": _space_name(take),
		}) if cash > 0 else Loc.t("game.monopoly.trade_swap", {
			"from": engine.player_name(from), "give": _space_name(give), "take": _space_name(take),
		})
	else:
		text = Loc.t("game.monopoly.trade_cash_offer", {
			"from": engine.player_name(from), "amount": cash, "take": _space_name(take),
		})
	_context_box.add_child(UI.label(text, "Body"))
	_context_box.add_child(UI.label(Loc.t("game.monopoly.trade_answer", {"player": engine.player_name(to)}), "Caption"))


func _build_turn_panel() -> void:
	_context_box.add_child(UI.label(Loc.t("game.monopoly.turn_title"), "Subtitle"))
	var player := acting_player()
	var builds: Array = actions_of_type("build_house")
	if not builds.is_empty():
		var box := UI.flow(6, 6)
		var shown := 0
		for action: Dictionary in builds:
			if shown >= 12:
				break
			shown += 1
			var space := int(action.get("space", -1))
			var cost := int(action.get("_price", 0))
			var button := UI.button(Loc.t("game.monopoly.build_button", {
				"space": _space_name(space), "cost": cost,
			}), "GhostButton", func() -> void: submit(String(action.get("key", ""))))
			box.add_child(button)
		_context_box.add_child(box)
	var offers: Array = actions_of_type("propose_trade")
	_context_box.add_child(UI.label(Loc.t("game.monopoly.trade_offers_title"), "Caption"))
	if offers.is_empty():
		_context_box.add_child(UI.label(Loc.t("game.monopoly.trade_no_offers"), "Small"))
		return
	var list := UI.column(4)
	var shown_offers := 0
	for action: Dictionary in offers:
		if shown_offers >= 24:
			break
		shown_offers += 1
		var give := int(action.get("give", -1))
		var take := int(action.get("take", -1))
		var cash := int(action.get("cash", 0))
		var text := ""
		if give < 0:
			text = Loc.t("game.monopoly.trade_buy_button", {
				"amount": cash, "take": _space_name(take),
			})
		elif cash > 0:
			text = Loc.t("game.monopoly.trade_offer_cash_button", {
				"give": _space_name(give), "amount": cash, "take": _space_name(take),
			})
		else:
			text = Loc.t("game.monopoly.trade_offer_button", {
				"give": _space_name(give), "take": _space_name(take),
			})
		var button := UI.button(text, "GhostButton",
			func() -> void: submit(String(action.get("key", ""))), Loc.t("game.monopoly.trade_offer_tooltip", {"player": engine.player_name(player)}))
		list.add_child(button)
	_context_box.add_child(UI.scroll(list, false))


func _status_text(state: Dictionary) -> String:
	if engine.finished:
		return Loc.t("game.common.finished_status", {"winner": engine.winner_text()})
	var lines := PackedStringArray()
	lines.append(engine.phase_hint())
	var roll: Array = state.get("last_roll", [])
	if roll.size() == 2 and int(roll[0]) > 0:
		lines.append(Loc.t("game.monopoly.dice_line", {
			"d1": int(roll[0]), "d2": int(roll[1]), "total": int(roll[0]) + int(roll[1]),
		}))
	lines.append(Loc.t("game.monopoly.round_line", {"round": engine.round_index, "cap": int(state.get("turn_cap", 0))}))
	if int(state.get("extra_roll", 0)) > 0:
		lines.append(Loc.t("game.monopoly.extra_roll"))
	return "\n".join(lines)


func _on_cell_pressed(space: int) -> void:
	if engine == null or engine.finished:
		return
	for action: Dictionary in actions_of_type("build_house"):
		if int(action.get("space", -1)) == space:
			submit(String(action.get("key", "")))
			return
	var state := engine.public_state()
	_details.text = _space_tooltip(space, MonopolyEngine.SPACES[space], state.get("owner", []), state.get("houses", []))


func _space_tooltip(space: int, data: Dictionary, owner: Array, houses: Array) -> String:
	var lines := PackedStringArray()
	lines.append(_space_name(space))
	var kind := String(data.get("kind", ""))
	if kind == "property" or kind == "railroad" or kind == "utility":
		lines.append(Loc.t("game.monopoly.price_line", {"price": int(data.get("price", 0))}))
		var owned := space < owner.size() and int(owner[space]) >= 0
		if owned:
			lines.append(Loc.t("game.monopoly.owner_line", {"player": engine.player_name(int(owner[space]))}))
		else:
			lines.append(Loc.t("game.monopoly.unowned"))
	if kind == "property":
		var rents: Array = data.get("rent", [])
		lines.append(Loc.t("game.monopoly.rent_base", {"amount": int(rents[0])}))
		for index: int in range(1, mini(5, rents.size())):
			lines.append(Loc.t("game.monopoly.rent_house", {"houses": index, "amount": int(rents[index])}))
		if rents.size() > 5:
			lines.append(Loc.t("game.monopoly.rent_hotel", {"amount": int(rents[5])}))
		lines.append(Loc.t("game.monopoly.house_cost_line", {"amount": int(data.get("house", 0))}))
		lines.append(Loc.t("game.monopoly.group_line", {"group": Loc.t("game.monopoly.group.%s" % String(data.get("group", "")))}))
	elif kind == "railroad":
		var rents: Array = data.get("rent", [])
		lines.append(Loc.t("game.monopoly.rent_rr", {"amount": int(rents[0]), "amount2": int(rents[rents.size() - 1])}))
	elif kind == "utility":
		lines.append(Loc.t("game.monopoly.rent_utility"))
	elif kind == "tax":
		lines.append(Loc.t("game.monopoly.tax_line", {"amount": int(data.get("amount", 0))}))
	if space < houses.size() and int(houses[space]) > 0:
		if int(houses[space]) >= 5:
			lines.append(Loc.t("game.monopoly.hotel_line"))
		else:
			lines.append(Loc.tp("game.monopoly.houses", int(houses[space])))
	return "\n".join(lines)


func _space_name(space: int) -> String:
	return Loc.t("game.monopoly.space.%s" % MonopolyEngine.SPACES[clampi(space, 0, 39)].get("id", "?"))


func _space_color(data: Dictionary) -> Color:
	match String(data.get("kind", "")):
		"property":
			var group_colour: Color = GROUP_COLORS.get(String(data.get("group", "")), Palette.BG_HOVER)
			return group_colour.darkened(0.35)
		"railroad":
			return Palette.BG_ACTIVE
		"utility":
			return Palette.tint(Palette.INFO, 0.25)
		"chance":
			return Palette.tint(Palette.WARNING, 0.25)
		"chest":
			return Palette.tint(Palette.POSITIVE, 0.22)
		"tax":
			return Palette.tint(Palette.DANGER, 0.25)
		_:
			return Palette.BG_HOVER


func _cell_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	return ThemeBuilder.flat(background, border, width, 4, 0)


func _private_for(_player: int) -> Dictionary:
	# §6.3: private data reaches views only through the authorized helper.
	return private_info()


func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	if engine != null and int(engine.public_state().get("extra_roll", 0)) > 0:
		out.append(UI.chip(Loc.t("game.monopoly.extra_roll_chip"), Palette.WARNING))
	return out


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _cell_xy(index: int) -> Vector2i:
	if index <= 0:
		return Vector2i(10, 10)
	if index < 10:
		return Vector2i(10, 10 - index)
	if index < 20:
		return Vector2i(20 - index, 0)
	if index < 30:
		return Vector2i(0, index - 20)
	return Vector2i(index - 30, 10)
