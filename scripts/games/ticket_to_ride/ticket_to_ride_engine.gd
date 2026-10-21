class_name TicketToRideEngine
extends GameEngine
## Ticket to Ride: Europe rules engine (compact recreation of the board).
##
## Implemented rules: eight card colours plus locomotives (110 cards), a market
## row of five face-up cards, blind and face-up drawing with the locomotive
## restrictions, claiming routes with colour or gray payment, locomotive
## requirements on ferry routes, tunnel exploration with an extra payment or a
## clean retreat, destination tickets (three dealt at the start with at least two
## kept; three drawn mid-game with at least one kept), the final round triggered
## by a player's last trains, scoring with route points, completed and unfinished
## tickets, and the +10 longest continuous path bonus.
##
## Documented simplifications:
##  * No train stations: a route must touch the player's own network.
##  * The route table is a compact recreation of the Europe board: 47 routes over
##    43 cities, including tunnel and ferry links.
##  * The longest path is the longest simple city path through the player's own
##    routes; players tied for the longest share the +10 bonus.
##  * A safety `turn_cap` (like Monopoly's) ends pathological matches, and a
##    `pass` action exists purely so a player with no legal move cannot deadlock.
##  * Deck order travels in the public snapshot with a "_" prefix so the host
##    authoritative state restores exactly; hands, kept tickets and pending
##    ticket offers are private.
##
## Action keys only use route indices, colours and keep-lists, so the same action
## keeps its key across snapshots. Snapshots carry every player's hidden state
## separately: a client restores the public snapshot plus its own
## `private_state()` (which is why the public snapshot alone cannot replay a
## draft or a turn for a seat whose hand it does not carry).

const COLOURS: Array[String] = [
	"purple", "blue", "orange", "white", "green", "yellow", "black", "red",
]
const LOCOMOTIVE: String = "locomotive"
const CARDS_PER_COLOUR: int = 12
const LOCOMOTIVES: int = 14
const FACE_UP_SIZE: int = 5
const TRAIN_STOCK: int = 45
const FINAL_ROUND_TRIGGER: int = 2
const TUNNEL_REVEAL: int = 3
const START_TICKETS: int = 3
const START_KEEP: int = 2
const MID_TICKETS: int = 3
const MID_KEEP: int = 1
const LONGEST_PATH_BONUS: int = 10
const LONGEST_PATH_BUDGET: int = 400000

## Points earned for a claimed route, indexed by its length.
const POINTS: Array[int] = [0, 1, 2, 4, 7, 10, 15, 18, 21]

const CITIES: Array[String] = [
	"amsterdam", "angora", "athina", "barcelona", "berlin", "brest",
	"bruxelles", "bucuresti", "budapest", "cadiz", "constantinopoli",
	"dieppe", "edinburgh", "erzurum", "essen", "frankfurt", "geneve",
	"hamburg", "kobenhavn", "kyiv", "lisboa", "london", "madrid",
	"marseille", "moskva", "munchen", "palermo", "pamplona", "paris",
	"petrograd", "riga", "roma", "rotterdam", "sarajevo", "sevilla",
	"smolensk", "sofia", "stockholm", "venezia", "wien", "wilno",
	"zagreb", "zurich",
]

## 47 Europe routes. `grey` routes accept any single colour, `ferries` lists how
## many locomotives the payment must include and `tunnel` marks the exploration
## routes.
const ROUTES: Array[Dictionary] = [
	{"id": "edinburgh_london", "a": "edinburgh", "b": "london", "length": 4, "colour": "orange"},
	{"id": "london_dieppe", "a": "london", "b": "dieppe", "length": 2, "colour": "grey", "ferries": 2},
	{"id": "london_amsterdam", "a": "london", "b": "amsterdam", "length": 2, "colour": "grey", "ferries": 2},
	{"id": "dieppe_paris", "a": "dieppe", "b": "paris", "length": 1, "colour": "purple"},
	{"id": "brest_paris", "a": "brest", "b": "paris", "length": 3, "colour": "black"},
	{"id": "brest_pamplona", "a": "brest", "b": "pamplona", "length": 4, "colour": "purple"},
	{"id": "paris_bruxelles", "a": "paris", "b": "bruxelles", "length": 2, "colour": "yellow"},
	{"id": "bruxelles_amsterdam", "a": "bruxelles", "b": "amsterdam", "length": 1, "colour": "black"},
	{"id": "amsterdam_essen", "a": "amsterdam", "b": "essen", "length": 3, "colour": "yellow"},
	{"id": "rotterdam_essen", "a": "rotterdam", "b": "essen", "length": 2, "colour": "blue"},
	{"id": "essen_frankfurt", "a": "essen", "b": "frankfurt", "length": 2, "colour": "green"},
	{"id": "hamburg_berlin", "a": "hamburg", "b": "berlin", "length": 2, "colour": "grey"},
	{"id": "hamburg_kobenhavn", "a": "hamburg", "b": "kobenhavn", "length": 3, "colour": "grey"},
	{"id": "frankfurt_berlin", "a": "frankfurt", "b": "berlin", "length": 3, "colour": "red"},
	{"id": "kobenhavn_stockholm", "a": "kobenhavn", "b": "stockholm", "length": 5, "colour": "blue"},
	{"id": "stockholm_petrograd", "a": "stockholm", "b": "petrograd", "length": 4, "colour": "purple"},
	{"id": "petrograd_riga", "a": "petrograd", "b": "riga", "length": 3, "colour": "blue"},
	{"id": "petrograd_moskva", "a": "petrograd", "b": "moskva", "length": 4, "colour": "white"},
	{"id": "riga_wilno", "a": "riga", "b": "wilno", "length": 4, "colour": "green"},
	{"id": "moskva_smolensk", "a": "moskva", "b": "smolensk", "length": 4, "colour": "orange"},
	{"id": "kyiv_bucuresti", "a": "kyiv", "b": "bucuresti", "length": 4, "colour": "yellow"},
	{"id": "berlin_wien", "a": "berlin", "b": "wien", "length": 3, "colour": "green"},
	{"id": "munchen_wien", "a": "munchen", "b": "wien", "length": 2, "colour": "orange"},
	{"id": "munchen_zurich", "a": "munchen", "b": "zurich", "length": 2, "colour": "blue"},
	{"id": "munchen_venezia", "a": "munchen", "b": "venezia", "length": 2, "colour": "grey", "tunnel": true},
	{"id": "venezia_roma", "a": "venezia", "b": "roma", "length": 2, "colour": "black"},
	{"id": "roma_palermo", "a": "roma", "b": "palermo", "length": 3, "colour": "grey", "ferries": 2},
	{"id": "paris_geneve", "a": "paris", "b": "geneve", "length": 3, "colour": "white"},
	{"id": "marseille_barcelona", "a": "marseille", "b": "barcelona", "length": 4, "colour": "grey"},
	{"id": "marseille_roma", "a": "marseille", "b": "roma", "length": 4, "colour": "red"},
	{"id": "wien_budapest", "a": "wien", "b": "budapest", "length": 2, "colour": "red"},
	{"id": "budapest_zagreb", "a": "budapest", "b": "zagreb", "length": 3, "colour": "orange"},
	{"id": "zagreb_sarajevo", "a": "zagreb", "b": "sarajevo", "length": 3, "colour": "red"},
	{"id": "sarajevo_sofia", "a": "sarajevo", "b": "sofia", "length": 3, "colour": "grey", "tunnel": true},
	{"id": "sofia_constantinopoli", "a": "sofia", "b": "constantinopoli", "length": 3, "colour": "red"},
	{"id": "constantinopoli_bucuresti", "a": "constantinopoli", "b": "bucuresti", "length": 3, "colour": "yellow"},
	{"id": "constantinopoli_angora", "a": "constantinopoli", "b": "angora", "length": 2, "colour": "grey"},
	{"id": "angora_erzurum", "a": "angora", "b": "erzurum", "length": 3, "colour": "black"},
	{"id": "pamplona_paris", "a": "pamplona", "b": "paris", "length": 4, "colour": "blue"},
	{"id": "barcelona_pamplona", "a": "barcelona", "b": "pamplona", "length": 2, "colour": "grey", "tunnel": true},
	{"id": "madrid_pamplona", "a": "madrid", "b": "pamplona", "length": 3, "colour": "black"},
	{"id": "barcelona_madrid", "a": "barcelona", "b": "madrid", "length": 3, "colour": "yellow"},
	{"id": "madrid_lisboa", "a": "madrid", "b": "lisboa", "length": 3, "colour": "blue"},
	{"id": "madrid_cadiz", "a": "madrid", "b": "cadiz", "length": 3, "colour": "green"},
	{"id": "madrid_sevilla", "a": "madrid", "b": "sevilla", "length": 2, "colour": "red"},
	{"id": "lisboa_cadiz", "a": "lisboa", "b": "cadiz", "length": 2, "colour": "blue"},
	{"id": "sofia_athina", "a": "sofia", "b": "athina", "length": 3, "colour": "green"},
]

## 27 destination tickets. Long hauls are worth 20-21 points, the rest 5-13.
const TICKETS: Array[Dictionary] = [
	{"id": "brest_petrograd", "a": "brest", "b": "petrograd", "value": 20},
	{"id": "cadiz_stockholm", "a": "cadiz", "b": "stockholm", "value": 21},
	{"id": "edinburgh_constantinopoli", "a": "edinburgh", "b": "constantinopoli", "value": 21},
	{"id": "lisboa_moskva", "a": "lisboa", "b": "moskva", "value": 20},
	{"id": "palermo_moskva", "a": "palermo", "b": "moskva", "value": 20},
	{"id": "kobenhavn_erzurum", "a": "kobenhavn", "b": "erzurum", "value": 21},
	{"id": "amsterdam_wilno", "a": "amsterdam", "b": "wilno", "value": 12},
	{"id": "angora_paris", "a": "angora", "b": "paris", "value": 11},
	{"id": "athina_berlin", "a": "athina", "b": "berlin", "value": 12},
	{"id": "berlin_bucuresti", "a": "berlin", "b": "bucuresti", "value": 8},
	{"id": "brest_venezia", "a": "brest", "b": "venezia", "value": 13},
	{"id": "cadiz_paris", "a": "cadiz", "b": "paris", "value": 11},
	{"id": "essen_kyiv", "a": "essen", "b": "kyiv", "value": 12},
	{"id": "frankfurt_smolensk", "a": "frankfurt", "b": "smolensk", "value": 13},
	{"id": "london_wien", "a": "london", "b": "wien", "value": 10},
	{"id": "madrid_munchen", "a": "madrid", "b": "munchen", "value": 10},
	{"id": "constantinopoli_roma", "a": "constantinopoli", "b": "roma", "value": 13},
	{"id": "amsterdam_pamplona", "a": "amsterdam", "b": "pamplona", "value": 7},
	{"id": "athina_marseille", "a": "athina", "b": "marseille", "value": 8},
	{"id": "barcelona_bruxelles", "a": "barcelona", "b": "bruxelles", "value": 8},
	{"id": "barcelona_munchen", "a": "barcelona", "b": "munchen", "value": 8},
	{"id": "brest_marseille", "a": "brest", "b": "marseille", "value": 7},
	{"id": "budapest_sofia", "a": "budapest", "b": "sofia", "value": 5},
	{"id": "dieppe_marseille", "a": "dieppe", "b": "marseille", "value": 8},
	{"id": "edinburgh_paris", "a": "edinburgh", "b": "paris", "value": 7},
	{"id": "moskva_riga", "a": "moskva", "b": "riga", "value": 8},
	{"id": "roma_zurich", "a": "roma", "b": "zurich", "value": 6},
]

# ------------------------------------------------------------------------ state

var hands: Array[Dictionary] = []        # per player: colour -> count (private)
var kept_tickets: Array[Array] = []      # per player: ticket ids (private)
var route_owner: Array[int] = []         # route index -> player, -1 = open
var trains_left: Array[int] = []
var deck: Array[String] = []
var discard: Array[String] = []
var face_up: Array[String] = []
var ticket_deck: Array[String] = []
var ticket_discard: Array[String] = []
var offer: Array[String] = []            # tickets dealt to the chooser (private)
var offer_player: int = -1
var offer_min: int = MID_KEEP
var opening_index: int = -1              # >= 0 while the opening tickets run
var active: int = 0
var drawn: int = 0                       # cards drawn in the current turn
var tunnel_route: int = -1
var tunnel_colour: String = ""
var tunnel_extra: int = 0
var tunnel_revealed: Array[String] = []
var tunnel_base: Dictionary = {}         # the base payment, refunded on retreat
var final_triggered: bool = false
var final_turns_left: int = 0
var trigger_player: int = -1
var turn_cap: int = 200
var longest_bonus_enabled: bool = true
var _path_budget: int = 0


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "ticket_to_ride_europe"


func setup(options: Dictionary) -> void:
	super.setup(options)
	turn_cap = maxi(20, VariantUtil.as_int(options.get("turn_cap", 200), 200))
	longest_bonus_enabled = bool(options.get("longest_path", true))
	var count := player_count()
	hands.clear()
	kept_tickets.clear()
	trains_left.clear()
	for index: int in range(count):
		hands.append({})
		kept_tickets.append([])
		trains_left.append(TRAIN_STOCK)
	route_owner.clear()
	for index: int in range(ROUTES.size()):
		route_owner.append(-1)
	deck = _build_deck()
	_shuffle(deck)
	discard.clear()
	face_up.clear()
	_refill_face_up()
	_replace_initial_locomotives()
	ticket_deck = _ticket_ids()
	_shuffle(ticket_deck)
	ticket_discard.clear()
	offer.clear()
	offer_player = -1
	offer_min = MID_KEEP
	opening_index = 0
	active = 0
	drawn = 0
	_clear_tunnel()
	final_triggered = false
	final_turns_left = 0
	trigger_player = -1
	turn = 0
	round_index = 1
	log_event("game.ticket_to_ride_europe.log_start", {"players": ", ".join(seat_names())})
	_deal_offer(0, START_TICKETS, START_KEEP)


func phases() -> PackedStringArray:
	return PackedStringArray(["tickets", "turn", "tunnel", "finished"])


func phase() -> String:
	if finished:
		return "finished"
	if not offer.is_empty():
		return "tickets"
	if tunnel_route >= 0:
		return "tunnel"
	return "turn"


func decision_player() -> int:
	if finished or players.is_empty():
		return 0
	return clampi(active, 0, player_count() - 1)


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "turn_cap", "label_key": "game.ticket_to_ride_europe.option.turn_cap", "type": "int",
			"default": 200, "min": 20, "max": 500, "hint_key": "game.ticket_to_ride_europe.option.turn_cap_hint"},
		{"key": "longest_path", "label_key": "game.ticket_to_ride_europe.option.longest_path", "type": "bool",
			"default": true, "hint_key": "game.ticket_to_ride_europe.option.longest_path_hint"},
	]


func seat_names() -> Array:
	var out: Array = []
	for index: int in range(player_count()):
		out.append(player_name(index))
	return out


# ------------------------------------------------------------------ data helpers

func colour_name(colour: String) -> String:
	return Loc.t("game.ticket_to_ride_europe.colour.%s" % colour)


func route_name(index: int) -> String:
	if index < 0 or index >= ROUTES.size():
		return "?"
	return Loc.t("game.ticket_to_ride_europe.route.%s" % VariantUtil.as_string(ROUTES[index].get("id", ""), "?"))


func route_length(index: int) -> int:
	if index < 0 or index >= ROUTES.size():
		return 0
	return VariantUtil.as_int(ROUTES[index].get("length", 0), 0)


func ticket_by_id(id: String) -> Dictionary:
	for entry: Dictionary in TICKETS:
		if VariantUtil.as_string(entry.get("id", ""), "") == id:
			return entry
	return {}


func ticket_value(id: String) -> int:
	return VariantUtil.as_int(ticket_by_id(id).get("value", 0), 0)


func hand_count(player: int) -> int:
	if player < 0 or player >= hands.size():
		return 0
	var total := 0
	for count: Variant in hands[player].values():
		total += VariantUtil.as_int(count, 0)
	return total


# -------------------------------------------------------------- action listing

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or players.is_empty() or player != decision_player():
		return out
	match phase():
		"tickets":
			_offer_actions(out)
		"tunnel":
			_tunnel_actions(player, out)
		"turn":
			_turn_actions(player, out)
	return out


func _offer_actions(out: Array[Dictionary]) -> void:
	var size := offer.size()
	if size == 0:
		return
	for mask: int in range(1, 1 << size):
		var keep := PackedStringArray()
		for index: int in range(size):
			if mask & (1 << index) != 0:
				keep.append(str(index))
		if keep.size() < offer_min:
			continue
		var action := make_action("keep_tickets", {"keep": ",".join(keep)})
		action["label_key"] = ""
		action["_direct"] = false
		action["_count"] = keep.size()
		out.append(action)


func _tunnel_actions(player: int, out: Array[Dictionary]) -> void:
	if _payment_possible(player, tunnel_colour, tunnel_extra, 0):
		out.append(make_action("pay_tunnel", {"extra": tunnel_extra},
			"game.ticket_to_ride_europe.action.pay_tunnel"))
	out.append(make_action("abort_tunnel", {"extra": tunnel_extra},
		"game.ticket_to_ride_europe.action.abort_tunnel"))


func _turn_actions(player: int, out: Array[Dictionary]) -> void:
	if _can_draw():
		out.append(make_action("draw_deck", {}, "game.ticket_to_ride_europe.action.draw_deck"))
	for slot: int in range(face_up.size()):
		var card: String = face_up[slot]
		if card.is_empty():
			continue
		# A face-up locomotive can only ever be the first card of a turn.
		if drawn > 0 and card == LOCOMOTIVE:
			continue
		var action := make_action("draw_face", {"slot": slot})
		action["label_key"] = ""
		action["_direct"] = false
		action["_card"] = card
		out.append(action)
	if not ticket_deck.is_empty() or not ticket_discard.is_empty():
		out.append(make_action("draw_tickets", {}, "game.ticket_to_ride_europe.action.draw_tickets"))
	for index: int in range(ROUTES.size()):
		out.append_array(_claim_actions(player, index))
	if out.is_empty():
		out.append(make_action("pass", {}, "game.ticket_to_ride_europe.action.pass"))


func _claim_actions(player: int, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if route_owner[index] >= 0:
		return out
	var route: Dictionary = ROUTES[index]
	var length := VariantUtil.as_int(route.get("length", 0), 0)
	if length <= 0 or trains_left[player] < length:
		return out
	var ferries := VariantUtil.as_int(route.get("ferries", 0), 0)
	if VariantUtil.as_int(hands[player].get(LOCOMOTIVE, 0), 0) < ferries:
		return out
	var route_colour := VariantUtil.as_string(route.get("colour", ""), "grey")
	if route_colour == "grey":
		# A grey route may be paid with any single colour (locomotives wild).
		# Offer one claim action per colour the player can actually cover, so
		# the chosen colour is carried through to the payment.
		for colour: String in COLOURS:
			if not _payment_possible(player, colour, length, ferries):
				continue
			var action := make_action("claim_route", {"route": index, "colour": colour})
			action["label_key"] = ""
			action["_direct"] = false
			action["_length"] = length
			action["_ferries"] = ferries
			action["_tunnel"] = bool(route.get("tunnel", false))
			action["_route_colour"] = route_colour
			out.append(action)
		return out
	if not _payment_possible(player, route_colour, length, ferries):
		return out
	var action := make_action("claim_route", {"route": index, "colour": route_colour})
	action["label_key"] = ""
	action["_direct"] = false
	action["_length"] = length
	action["_ferries"] = ferries
	action["_tunnel"] = bool(route.get("tunnel", false))
	action["_route_colour"] = route_colour
	out.append(action)
	return out


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	var chosen := find_legal_action(player, VariantUtil.as_string(action.get("key", ""), ""))
	if chosen.is_empty():
		return _fail("game.ticket_to_ride_europe.error.illegal_action")
	match VariantUtil.as_string(chosen.get("type", ""), ""):
		"draw_deck":
			_apply_draw_deck(player)
		"draw_face":
			_apply_draw_face(player, chosen)
		"draw_tickets":
			_apply_draw_tickets(player)
		"claim_route":
			_apply_claim(player, chosen)
		"keep_tickets":
			_apply_keep(player, chosen)
		"pay_tunnel":
			_apply_pay_tunnel(player)
		"abort_tunnel":
			_apply_abort_tunnel(player)
		"pass":
			_apply_pass(player)
		_:
			return _fail("game.ticket_to_ride_europe.error.unknown_action")
	return _ok(chosen)


func _apply_draw_deck(player: int) -> void:
	var card := _draw_card()
	if card.is_empty():
		_end_turn(player)
		return
	_add_to_hand(player, card)
	drawn += 1
	# The card itself stays hidden, so the log only mentions the draw.
	log_event("game.ticket_to_ride_europe.log_draw_blind", {"player": player_name(player)}, player)
	if drawn >= 2:
		_end_turn(player)


func _apply_draw_face(player: int, action: Dictionary) -> void:
	var slot := VariantUtil.as_int(action.get("slot", -1), -1)
	if slot < 0 or slot >= face_up.size():
		_end_turn(player)
		return
	var card: String = face_up[slot]
	face_up.remove_at(slot)
	_refill_face_up()
	_add_to_hand(player, card)
	drawn += 1
	log_event("game.ticket_to_ride_europe.log_draw_face", {
		"player": player_name(player), "card": colour_name(card),
	}, player)
	if card == LOCOMOTIVE or drawn >= 2:
		_end_turn(player)


func _apply_draw_tickets(player: int) -> void:
	log_event("game.ticket_to_ride_europe.log_draw_tickets", {"player": player_name(player)}, player)
	_deal_offer(player, MID_TICKETS, MID_KEEP)
	if offer.is_empty():
		_end_turn(player)


func _apply_keep(player: int, action: Dictionary) -> void:
	var keep_list := VariantUtil.as_string(action.get("keep", ""), "").split(",", false)
	var kept := 0
	for index: int in range(offer.size()):
		var id: String = offer[index]
		if keep_list.has(str(index)):
			kept_tickets[player].append(id)
			kept += 1
		else:
			ticket_discard.append(id)
	log_event("game.ticket_to_ride_europe.log_keep_tickets", {
		"player": player_name(player),
		"kept": Loc.tp("game.ticket_to_ride_europe.log_kept", kept),
	}, player)
	offer.clear()
	offer_player = -1
	if opening_index >= 0:
		opening_index += 1
		if opening_index < player_count():
			active = opening_index
			_deal_offer(active, START_TICKETS, START_KEEP)
			return
		opening_index = -1
		active = 0
		log_event("game.ticket_to_ride_europe.log_first_turn", {"player": player_name(0)})
		return
	_end_turn(player)


func _apply_claim(player: int, action: Dictionary) -> void:
	var index := VariantUtil.as_int(action.get("route", -1), -1)
	if index < 0 or index >= ROUTES.size():
		_end_turn(player)
		return
	var colour := VariantUtil.as_string(action.get("colour", ""), "")
	var route: Dictionary = ROUTES[index]
	var length := VariantUtil.as_int(route.get("length", 0), 0)
	var ferries := VariantUtil.as_int(route.get("ferries", 0), 0)
	var base := _payment(player, colour, length, ferries)
	_remove_payment(player, base)
	tunnel_base = base
	tunnel_route = index
	tunnel_colour = colour
	tunnel_extra = 0
	tunnel_revealed.clear()
	if bool(route.get("tunnel", false)):
		tunnel_revealed = _reveal_tunnel()
		tunnel_extra = _tunnel_extra(tunnel_revealed, colour)
		log_event("game.ticket_to_ride_europe.log_tunnel_reveal", {
			"player": player_name(player),
			"route": route_name(index),
			"extra": tunnel_extra,
		}, player)
		if tunnel_extra > 0:
			return
	_commit_claim(player, index, colour)


func _apply_pay_tunnel(player: int) -> void:
	var cost := _payment(player, tunnel_colour, tunnel_extra, 0)
	_remove_payment(player, cost)
	log_event("game.ticket_to_ride_europe.log_tunnel_pay", {
		"player": player_name(player), "extra": tunnel_extra,
	}, player)
	var index := tunnel_route
	var colour := tunnel_colour
	_commit_claim(player, index, colour)


func _apply_abort_tunnel(player: int) -> void:
	var index := tunnel_route
	_add_payment(player, tunnel_base)
	_discard_revealed()
	_clear_tunnel()
	log_event("game.ticket_to_ride_europe.log_tunnel_abort", {
		"player": player_name(player), "route": route_name(index),
	}, player)
	_end_turn(player)


func _apply_pass(player: int) -> void:
	log_event("game.ticket_to_ride_europe.log_pass", {"player": player_name(player)}, player)
	_end_turn(player)


func _commit_claim(player: int, index: int, colour: String) -> void:
	if index < 0 or index >= ROUTES.size():
		_clear_tunnel()
		_end_turn(player)
		return
	route_owner[index] = player
	trains_left[player] = maxi(0, trains_left[player] - route_length(index))
	_discard_revealed()
	_clear_tunnel()
	log_event("game.ticket_to_ride_europe.log_claim", {
		"player": player_name(player),
		"route": route_name(index),
		"colour": colour_name(colour),
	}, player)
	_end_turn(player)


# ----------------------------------------------------------------------- flow

func _end_turn(player: int) -> void:
	drawn = 0
	if finished or players.is_empty():
		return
	if round_index > turn_cap:
		_finish_match("game.ticket_to_ride_europe.reason.turn_cap")
		return
	if not final_triggered and trains_left[player] <= FINAL_ROUND_TRIGGER:
		final_triggered = true
		trigger_player = player
		final_turns_left = player_count() - 1
		log_event("game.ticket_to_ride_europe.log_final_round", {"player": player_name(player)}, player)
		if final_turns_left <= 0:
			_finish_match("game.ticket_to_ride_europe.reason.final_round")
			return
	elif final_triggered:
		final_turns_left -= 1
		if final_turns_left <= 0:
			_finish_match("game.ticket_to_ride_europe.reason.final_round")
			return
	turn += 1
	active = (player + 1) % player_count()
	round_index = (turn / player_count()) + 1


func _finish_match(reason: String) -> void:
	var scores: Array = []
	var best_total := -1
	var winner := -1
	var tied := false
	for player: int in range(player_count()):
		var total := VariantUtil.as_int(score_breakdown(player).get("total", 0), 0)
		scores.append({"player": player, "name": player_name(player), "score": total})
		if total > best_total:
			best_total = total
			winner = player
			tied = false
		elif total == best_total:
			tied = true
	if tied:
		winner = -1
	finish(winner, reason, scores)


func _deal_offer(player: int, count: int, keep_min: int) -> void:
	offer.clear()
	offer_player = player
	offer_min = keep_min
	for _i: int in range(count):
		var id := _draw_ticket()
		if id.is_empty():
			break
		offer.append(id)
	offer_min = mini(offer_min, offer.size())
	if offer.is_empty():
		offer_player = -1


# ---------------------------------------------------------------------- cards

func _build_deck() -> Array[String]:
	var cards: Array[String] = []
	for colour: String in COLOURS:
		for _i: int in range(CARDS_PER_COLOUR):
			cards.append(colour)
	for _i: int in range(LOCOMOTIVES):
		cards.append(LOCOMOTIVE)
	return cards


func _ticket_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in TICKETS:
		ids.append(VariantUtil.as_string(entry.get("id", ""), ""))
	return ids


func _shuffle(cards: Array[String]) -> void:
	for i: int in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap


func _draw_card() -> String:
	if deck.is_empty():
		if discard.is_empty():
			return ""
		deck = discard.duplicate()
		discard.clear()
		_shuffle(deck)
	if deck.is_empty():
		return ""
	return deck.pop_front()


func _draw_ticket() -> String:
	if ticket_deck.is_empty():
		if ticket_discard.is_empty():
			return ""
		ticket_deck = ticket_discard.duplicate()
		ticket_discard.clear()
		_shuffle(ticket_deck)
	if ticket_deck.is_empty():
		return ""
	return ticket_deck.pop_front()


func _can_draw() -> bool:
	return not deck.is_empty() or not discard.is_empty() or not face_up.is_empty()


func _refill_face_up() -> void:
	while face_up.size() < FACE_UP_SIZE:
		var card := _draw_card()
		if card.is_empty():
			break
		face_up.append(card)
	# Three visible locomotives clear the whole row (standard rule); the guard
	# keeps the reshuffle from looping when the deck itself is exhausted.
	var visible_locos := 0
	for card: String in face_up:
		if card == LOCOMOTIVE:
			visible_locos += 1
	var guard := 0
	while visible_locos >= 3 and guard < 10:
		guard += 1
		for card: String in face_up:
			discard.append(card)
		face_up.clear()
		while face_up.size() < FACE_UP_SIZE:
			var replacement := _draw_card()
			if replacement.is_empty():
				break
			face_up.append(replacement)
		visible_locos = 0
		for card: String in face_up:
			if card == LOCOMOTIVE:
				visible_locos += 1


func _replace_initial_locomotives() -> void:
	# The opening market replaces any locomotive (standard setup rule).
	for _round: int in range(FACE_UP_SIZE):
		var replaced := false
		var slot := face_up.size() - 1
		while slot >= 0:
			if face_up[slot] == LOCOMOTIVE:
				discard.append(face_up[slot])
				face_up.remove_at(slot)
				replaced = true
			slot -= 1
		if not replaced:
			return
		_refill_face_up()


func _add_to_hand(player: int, card: String) -> void:
	var hand: Dictionary = hands[player]
	hand[card] = VariantUtil.as_int(hand.get(card, 0), 0) + 1


func _add_payment(player: int, payment: Dictionary) -> void:
	var hand: Dictionary = hands[player]
	for colour: Variant in payment:
		hand[String(colour)] = VariantUtil.as_int(hand.get(String(colour), 0), 0) + VariantUtil.as_int(payment[colour], 0)


func _remove_payment(player: int, payment: Dictionary) -> void:
	var hand: Dictionary = hands[player]
	for colour: Variant in payment:
		var key := String(colour)
		var left := VariantUtil.as_int(hand.get(key, 0), 0) - VariantUtil.as_int(payment[colour], 0)
		if left > 0:
			hand[key] = left
		else:
			hand.erase(key)


func _loco_count(player: int) -> int:
	return VariantUtil.as_int(hands[player].get(LOCOMOTIVE, 0), 0)


func _payment_possible(player: int, colour: String, amount: int, ferries: int) -> bool:
	if amount <= 0:
		return true
	var coloured := VariantUtil.as_int(hands[player].get(colour, 0), 0)
	if colour == LOCOMOTIVE:
		coloured = _loco_count(player)
	return coloured + _loco_count(player) >= amount and _loco_count(player) >= ferries


## The cheapest legal payment: ferries and any shortfall eat locomotives first.
func _payment(player: int, colour: String, amount: int, ferries: int) -> Dictionary:
	var payment: Dictionary = {}
	if amount <= 0:
		return payment
	var coloured := VariantUtil.as_int(hands[player].get(colour, 0), 0) if colour != LOCOMOTIVE else _loco_count(player)
	var locos := _loco_count(player)
	var loco_part := clampi(maxi(ferries, amount - coloured), 0, mini(locos, amount))
	var colour_part := amount - loco_part
	if loco_part > 0:
		payment[LOCOMOTIVE] = loco_part
	if colour_part > 0:
		payment[colour] = colour_part
	return payment


# --------------------------------------------------------------------- tunnels

func _reveal_tunnel() -> Array[String]:
	var revealed: Array[String] = []
	for _i: int in range(TUNNEL_REVEAL):
		var card := _draw_card()
		if card.is_empty():
			break
		revealed.append(card)
	return revealed


func _tunnel_extra(revealed: Array[String], colour: String) -> int:
	var extra := 0
	for card: String in revealed:
		if card == colour or card == LOCOMOTIVE:
			extra += 1
	return extra


func _discard_revealed() -> void:
	for card: String in tunnel_revealed:
		discard.append(card)
	tunnel_revealed.clear()


func _clear_tunnel() -> void:
	tunnel_route = -1
	tunnel_colour = ""
	tunnel_extra = 0
	tunnel_revealed.clear()
	tunnel_base = {}


# --------------------------------------------------------------------- scoring

func route_points(player: int) -> int:
	var total := 0
	for index: int in range(ROUTES.size()):
		if route_owner[index] == player:
			total += int(POINTS[clampi(route_length(index), 0, POINTS.size() - 1)])
	return total


func ticket_points(player: int) -> int:
	var total := 0
	for id: Variant in kept_tickets[player]:
		var ticket := ticket_by_id(VariantUtil.as_string(id, ""))
		if ticket.is_empty():
			continue
		var value := VariantUtil.as_int(ticket.get("value", 0), 0)
		if network_connected(player, VariantUtil.as_string(ticket.get("a", ""), ""), VariantUtil.as_string(ticket.get("b", ""), "")):
			total += value
		else:
			total -= value
	return total


## True when `a` and `b` sit in one connected component of the player's network.
func network_connected(player: int, a: String, b: String) -> bool:
	if a == b:
		return true
	var adjacency := _network(player)
	var frontier: Array[String] = [a]
	var seen: Dictionary = {a: true}
	while not frontier.is_empty():
		var city: String = frontier.pop_back()
		var neighbours: Array = adjacency.get(city, [])
		for other: Variant in neighbours:
			var next := VariantUtil.as_string(VariantUtil.as_dict(other).get("city", ""), "")
			if next == b:
				return true
			if not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return false


func _network(player: int) -> Dictionary:
	var adjacency: Dictionary = {}
	for index: int in range(ROUTES.size()):
		if route_owner[index] != player:
			continue
		var route: Dictionary = ROUTES[index]
		var a := VariantUtil.as_string(route.get("a", ""), "")
		var b := VariantUtil.as_string(route.get("b", ""), "")
		var length := VariantUtil.as_int(route.get("length", 1), 1)
		_link(adjacency, a, b, length)
		_link(adjacency, b, a, length)
	return adjacency


func _link(adjacency: Dictionary, from: String, to: String, length: int) -> void:
	var list: Array = adjacency.get(from, [])
	list.append({"city": to, "length": length})
	adjacency[from] = list


## Longest continuous path through the player's own routes, in trains used.
func longest_path(player: int) -> int:
	var adjacency := _network(player)
	_path_budget = LONGEST_PATH_BUDGET
	var best := 0
	for city: Variant in adjacency.keys():
		if _path_budget <= 0:
			break
		var seen: Dictionary = {}
		seen[VariantUtil.as_string(city, "")] = true
		best = maxi(best, _walk(VariantUtil.as_string(city, ""), adjacency, seen))
	return best


func _walk(city: String, adjacency: Dictionary, seen: Dictionary) -> int:
	if _path_budget <= 0:
		return 0
	_path_budget -= 1
	var best := 0
	for edge: Variant in adjacency.get(city, []):
		var step: Dictionary = edge
		var next := VariantUtil.as_string(step.get("city", ""), "")
		if seen.has(next):
			continue
		var length := VariantUtil.as_int(step.get("length", 1), 1)
		seen[next] = true
		best = maxi(best, length + _walk(next, adjacency, seen))
		seen.erase(next)
	return best


## Routes, tickets, longest-path bonus and total for the final scoring.
func score_breakdown(player: int) -> Dictionary:
	var routes := route_points(player)
	var tickets := ticket_points(player)
	var longest := longest_path(player)
	var bonus := 0
	if longest_bonus_enabled and longest > 0:
		var best := 0
		for other: int in range(player_count()):
			best = maxi(best, longest_path(other))
		if longest == best:
			bonus = LONGEST_PATH_BONUS
	return {
		"routes": routes,
		"tickets": tickets,
		"longest": longest,
		"bonus": bonus,
		"total": routes + tickets + bonus,
	}


# ------------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["route_owner"] = route_owner.duplicate()
	state["trains_left"] = trains_left.duplicate()
	state["face_up"] = face_up.duplicate()
	state["deck_count"] = deck.size()
	state["discard_count"] = discard.size()
	state["tickets_left"] = ticket_deck.size()
	state["hand_count"] = _hand_counts()
	state["route_points"] = _route_points()
	state["ticket_count"] = _ticket_counts()
	state["active"] = active
	state["drawn"] = drawn
	state["opening_index"] = opening_index
	state["longest_path"] = longest_bonus_enabled
	state["offer_player"] = offer_player
	state["offer_count"] = offer.size()
	state["offer_min"] = offer_min
	state["tunnel"] = _tunnel_state()
	state["final"] = {
		"triggered": final_triggered,
		"turns_left": final_turns_left,
		"triggered_by": trigger_player,
	}
	state["turn_cap"] = turn_cap
	state["_deck"] = deck.duplicate()
	state["_discard"] = discard.duplicate()
	state["_ticket_deck"] = ticket_deck.duplicate()
	state["_ticket_discard"] = ticket_discard.duplicate()
	state["_tunnel_base"] = tunnel_base.duplicate()
	return state


func _hand_counts() -> Array:
	var out: Array = []
	for player: int in range(player_count()):
		out.append(hand_count(player))
	return out


func _route_points() -> Array:
	var out: Array = []
	for player: int in range(player_count()):
		out.append(route_points(player))
	return out


func _ticket_counts() -> Array:
	var out: Array = []
	for player: int in range(player_count()):
		out.append(kept_tickets[player].size())
	return out


func _tunnel_state() -> Dictionary:
	if tunnel_route < 0:
		return {}
	return {
		"route": tunnel_route,
		"colour": tunnel_colour,
		"extra": tunnel_extra,
		"revealed": tunnel_revealed.duplicate(),
	}


func private_state(player: int) -> Dictionary:
	if player < 0 or player >= player_count():
		return {}
	var out: Dictionary = {
		"player": player,
		"hand": VariantUtil.dict_copy(hands[player]),
		"tickets": VariantUtil.array_copy(kept_tickets[player]),
	}
	if offer_player == player and not offer.is_empty():
		out["offer"] = offer.duplicate()
	return out


func _restore_extra(state: Dictionary) -> void:
	copy_int_array(state.get("route_owner", []), route_owner)
	if route_owner.size() != ROUTES.size():
		route_owner.clear()
		for index: int in range(ROUTES.size()):
			route_owner.append(-1)
	copy_int_array(state.get("trains_left", []), trains_left)
	while trains_left.size() < player_count():
		trains_left.append(TRAIN_STOCK)
	copy_string_array(state.get("_deck", []), deck)
	copy_string_array(state.get("_discard", []), discard)
	copy_string_array(state.get("face_up", []), face_up)
	copy_string_array(state.get("_ticket_deck", []), ticket_deck)
	copy_string_array(state.get("_ticket_discard", []), ticket_discard)
	while hands.size() < player_count():
		hands.append({})
		kept_tickets.append([])
	while hands.size() > player_count():
		hands.pop_back()
		kept_tickets.pop_back()
	active = VariantUtil.as_int(state.get("active", 0), 0)
	drawn = VariantUtil.as_int(state.get("drawn", 0), 0)
	opening_index = VariantUtil.as_int(state.get("opening_index", -1), -1)
	longest_bonus_enabled = bool(state.get("longest_path", true))
	offer_player = VariantUtil.as_int(state.get("offer_player", -1), -1)
	offer_min = VariantUtil.as_int(state.get("offer_min", MID_KEEP), MID_KEEP)
	turn_cap = maxi(20, VariantUtil.as_int(state.get("turn_cap", 200), 200))
	final_triggered = bool(VariantUtil.as_dict(state.get("final", {})).get("triggered", false))
	final_turns_left = VariantUtil.as_int(VariantUtil.as_dict(state.get("final", {})).get("turns_left", 0), 0)
	trigger_player = VariantUtil.as_int(VariantUtil.as_dict(state.get("final", {})).get("triggered_by", -1), -1)
	_clear_tunnel()
	var tunnel: Dictionary = state.get("tunnel", {})
	if not tunnel.is_empty():
		tunnel_route = VariantUtil.as_int(tunnel.get("route", -1), -1)
		tunnel_colour = VariantUtil.as_string(tunnel.get("colour", ""), "")
		tunnel_extra = VariantUtil.as_int(tunnel.get("extra", 0), 0)
		copy_string_array(tunnel.get("revealed", []), tunnel_revealed)
	tunnel_base = VariantUtil.dict_copy(state.get("_tunnel_base", {}))
	# Private fields arrive per seat: a save file keys one slice per seat under
	# "private_states"; the harness/online client shape merges the acting
	# player's zones at the top level with the owner named by "player".
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	if not privates.is_empty():
		for seat_key: Variant in privates:
			var slice: Variant = privates.get(seat_key, {})
			if slice is Dictionary:
				var slice_dict: Dictionary = slice
				var owner := VariantUtil.as_int(slice_dict.get("player", int(str(seat_key)) if str(seat_key).is_valid_int() else -2), -2)
				_adopt_private_extra(owner, slice_dict)
	elif state.has("player") and state.has("hand"):
		# Client shape (harness contract): the slice names its own owner.
		_adopt_private_extra(VariantUtil.as_int(state.get("player", -1), -1), state)


## Installs ONE seat's private slice on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own tickets.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0 or seat >= hands.size():
		return
	if not (slice.has("hand") or slice.has("tickets")):
		return
	hands[seat] = VariantUtil.dict_copy(slice.get("hand", {}))
	# `kept_tickets` holds plain arrays, so the string copy is manual.
	kept_tickets[seat].clear()
	for id: Variant in VariantUtil.as_array(slice.get("tickets", [])):
		kept_tickets[seat].append(VariantUtil.as_string(id, ""))
	if slice.has("offer") and offer_player == seat:
		copy_string_array(slice.get("offer", []), offer)
