extends RefCounted
## Ticket to Ride: Europe rules suite: board data, the opening ticket draft, card
## drawing, claiming routes with colours, locomotives and ferries, tunnel
## exploration, destination tickets, the final round, scoring, the turn cap,
## illegal moves, determinism, snapshots, privacy and a bot-only match.
##
## Scenario tests drive the engine with public actions and only seed hands,
## trains and decks (test setup); the engine itself is never patched.


func suite_name() -> String:
	return "ticket to ride europe rules"


func run(h: TestHarness) -> void:
	_board_data(h)
	_opening(h)
	_pack(h)
	_drawing(h)
	_claiming(h)
	_ferries(h)
	_tunnels(h)
	_tickets(h)
	_final_round(h)
	_scoring(h)
	_turn_cap(h)
	_illegal(h)
	_determinism(h)
	_snapshot(h)
	_privacy(h)
	_bot_match(h)


# -------------------------------------------------------------------- helpers

func _engine(h: TestHarness, player_count: int = 2, options: Dictionary = {}, seed_value: int = 424242) -> TicketToRideEngine:
	var engine := EngineHarness.create("ticket_to_ride_europe", player_count, seed_value, options) as TicketToRideEngine
	h.check(engine != null, "the ticket to ride europe engine must be creatable")
	return engine


func _first_key(engine: TicketToRideEngine, player: int) -> String:
	var actions: Array[Dictionary] = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	return String(actions[0].get("key", ""))


func _keys_of(actions: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	for action: Variant in actions:
		if action is Dictionary:
			keys.append(String((action as Dictionary).get("key", "")))
	keys.sort()
	return keys


func _type_key(engine: TicketToRideEngine, type: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == type:
			return String(action.get("key", ""))
	return ""


func _slot_key(engine: TicketToRideEngine, slot: int) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "draw_face" and int(action.get("slot", -1)) == slot:
			return String(action.get("key", ""))
	return ""


func _keep_key(engine: TicketToRideEngine, count: int) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) == "keep_tickets" and int(action.get("_count", 0)) == count:
			return String(action.get("key", ""))
	return ""


func _claim_key(engine: TicketToRideEngine, route: int, colour: String) -> String:
	for action: Dictionary in engine.legal_actions(engine.decision_player()):
		if String(action.get("type", "")) != "claim_route":
			continue
		if int(action.get("route", -1)) == route and String(action.get("colour", "")) == colour:
			return String(action.get("key", ""))
	return ""


func _route_index(id: String) -> int:
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route: Dictionary = TicketToRideEngine.ROUTES[index]
		if String(route.get("id", "")) == id:
			return index
	return -1


func _skip_opening(engine: TicketToRideEngine) -> TicketToRideEngine:
	var guard := 0
	while not engine.finished and engine.phase() == "tickets" and guard < 64:
		guard += 1
		var actor := engine.decision_player()
		engine.apply_action_by_key(actor, _first_key(engine, actor))
	return engine


func _reason_key(engine: TicketToRideEngine) -> String:
	return String(engine.result.get("reason_key", ""))


func _final_state(engine: TicketToRideEngine) -> Dictionary:
	return engine.public_state().get("final", {})


# ----------------------------------------------------------------- board data

func _board_data(h: TestHarness) -> void:
	h.equal(TicketToRideEngine.ROUTES.size(), 47, "the board has 47 routes")
	h.equal(TicketToRideEngine.CITIES.size(), 43, "the board has 43 cities")
	h.equal(TicketToRideEngine.TICKETS.size(), 27, "the ticket deck has 27 tickets")
	h.equal(TicketToRideEngine.COLOURS.size(), 8, "cards come in eight colours")
	var seen_ids: Dictionary = {}
	var used_cities: Dictionary = {}
	var adjacency: Dictionary = {}
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route: Dictionary = TicketToRideEngine.ROUTES[index]
		var id := String(route.get("id", ""))
		h.check(not seen_ids.has(id), "route ids are unique (%s)" % id)
		seen_ids[id] = true
		var a := String(route.get("a", ""))
		var b := String(route.get("b", ""))
		h.check(a != b, "route %s joins two different cities" % id)
		h.check(TicketToRideEngine.CITIES.has(a) and TicketToRideEngine.CITIES.has(b),
			"route %s names cities of the board" % id)
		used_cities[a] = true
		used_cities[b] = true
		var length := int(route.get("length", 0))
		h.check(length >= 1 and length <= 8, "route %s has a playable length" % id)
		h.check(int(route.get("ferries", 0)) <= length, "route %s asks no more locomotives than cards" % id)
		var colour := String(route.get("colour", ""))
		h.check(colour == "grey" or TicketToRideEngine.COLOURS.has(colour),
			"route %s uses a real colour" % id)
		var from_list: Array = adjacency.get(a, [])
		from_list.append(b)
		adjacency[a] = from_list
		var to_list: Array = adjacency.get(b, [])
		to_list.append(a)
		adjacency[b] = to_list
	for city: String in TicketToRideEngine.CITIES:
		h.check(used_cities.has(city), "city %s carries at least one route" % city)
	var start: String = TicketToRideEngine.CITIES[0]
	var seen: Dictionary = {start: true}
	var frontier: Array[String] = [start]
	while not frontier.is_empty():
		var city: String = frontier.pop_back()
		for next: Variant in adjacency.get(city, []):
			if not seen.has(next):
				seen[next] = true
				frontier.append(String(next))
	h.equal(seen.size(), TicketToRideEngine.CITIES.size(), "the map is one connected network")
	var ticket_ids: Dictionary = {}
	for index: int in range(TicketToRideEngine.TICKETS.size()):
		var ticket: Dictionary = TicketToRideEngine.TICKETS[index]
		var id := String(ticket.get("id", ""))
		h.check(not ticket_ids.has(id), "ticket ids are unique (%s)" % id)
		ticket_ids[id] = true
		var a := String(ticket.get("a", ""))
		var b := String(ticket.get("b", ""))
		h.check(a != b, "ticket %s joins two different cities" % id)
		h.check(TicketToRideEngine.CITIES.has(a) and TicketToRideEngine.CITIES.has(b),
			"ticket %s names cities of the board" % id)
		h.check(int(ticket.get("value", 0)) >= 5, "ticket %s is worth points" % id)
	h.equal(TicketToRideEngine.POINTS.size(), 9, "the points table covers routes up to eight cars")


# --------------------------------------------------------------------- opening

func _opening(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	h.equal(engine.phase(), "tickets", "the opening draft is the first phase")
	h.equal(engine.decision_player(), 0, "the first seat drafts first")
	h.equal(engine.offer.size(), 3, "three tickets are offered")
	h.equal(engine.offer_min, 2, "at least two tickets must be kept")
	h.equal(engine.trains_left, [45, 45, 45], "everybody starts with 45 trains")
	h.equal(engine.deck.size() + engine.face_up.size() + engine.discard.size(), 110,
		"the deck holds 110 cards")
	h.equal(engine.face_up.size(), 5, "five cards are laid out")
	h.check(not engine.face_up.has(TicketToRideEngine.LOCOMOTIVE),
		"the opening market replaces every locomotive")
	h.check(engine.legal_actions(1).is_empty(), "the other seats wait for the draft")
	var actions: Array[Dictionary] = engine.legal_actions(0)
	h.equal(actions.size(), 4, "every combination of at least two tickets is offered")
	for action: Dictionary in actions:
		h.check(String(action.get("type", "")) == "keep_tickets", "the draft offers ticket choices")
		h.check(int(action.get("_count", 0)) >= 2, "a draft choice keeps at least two tickets")
		h.check(not bool(action.get("_direct", true)), "draft choices need a confirmation")
	EngineHarness.check_legal_action_shape(h, engine, "ticket draft")
	var twin := _engine(h, 3)
	h.equal(engine.public_state(), twin.public_state(), "the same seed lays out the same board")
	h.equal(engine.private_state(0), twin.private_state(0), "the same seed deals the same tickets")
	var shuffled := _engine(h, 3, {}, 777)
	h.not_equal(shuffled.private_state(0), engine.private_state(0),
		"another seed deals other tickets")


# ------------------------------------------------------------------ string pack

func _pack(h: TestHarness) -> void:
	h.check(Loc.has_key("game.ticket_to_ride_europe.name"), "the game has a name")
	h.check(Loc.has_key("game.ticket_to_ride_europe.desc"), "the game has a description")
	h.greater(float(Loc.t("game.ticket_to_ride_europe.desc").length()), 20.0,
		"the description is substantial")
	for phase: String in ["tickets", "turn", "tunnel", "finished"]:
		h.check(Loc.has_key("game.ticket_to_ride_europe.phase.%s" % phase), "phase %s is translated" % phase)
	for option: String in ["turn_cap", "turn_cap_hint", "longest_path", "longest_path_hint"]:
		h.check(Loc.has_key("game.ticket_to_ride_europe.option.%s" % option), "option %s is translated" % option)
	for action: String in ["draw_deck", "draw_tickets", "pay_tunnel", "abort_tunnel", "pass"]:
		h.check(Loc.has_key("game.ticket_to_ride_europe.action.%s" % action), "action %s is translated" % action)
	for colour: String in TicketToRideEngine.COLOURS + [TicketToRideEngine.LOCOMOTIVE, "grey"]:
		h.check(Loc.has_key("game.ticket_to_ride_europe.colour.%s" % colour), "colour %s is translated" % colour)
	for city: String in TicketToRideEngine.CITIES:
		h.check(Loc.has_key("game.ticket_to_ride_europe.city.%s" % city), "city %s is translated" % city)
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route: Dictionary = TicketToRideEngine.ROUTES[index]
		h.check(Loc.has_key("game.ticket_to_ride_europe.route.%s" % String(route.get("id", ""))),
			"route %s is translated" % String(route.get("id", "")))
	for index: int in range(TicketToRideEngine.TICKETS.size()):
		var ticket: Dictionary = TicketToRideEngine.TICKETS[index]
		h.check(Loc.has_key("game.ticket_to_ride_europe.ticket.%s" % String(ticket.get("id", ""))),
			"ticket %s is translated" % String(ticket.get("id", "")))
	for key: String in [
		"game.ticket_to_ride_europe.error.illegal_action",
		"game.ticket_to_ride_europe.error.unknown_action",
		"game.ticket_to_ride_europe.reason.final_round",
		"game.ticket_to_ride_europe.reason.turn_cap",
		"game.ticket_to_ride_europe.log_kept.other",
		"game.ticket_to_ride_europe.log_tunnel_pay",
		"game.ticket_to_ride_europe.view.market_title",
		"game.ticket_to_ride_europe.view.status_round",
		"game.ticket_to_ride_europe.view.trains_left.one",
	]:
		h.check(Loc.has_key(key), "key %s exists" % key)
		h.no_raw_key(Loc.t(key), "key %s renders as text" % key)


# --------------------------------------------------------------------- drawing

func _drawing(h: TestHarness) -> void:
	var engine := _skip_opening(_engine(h))
	h.equal(engine.phase(), "turn", "the draft ends in the turn phase")
	h.equal(engine.decision_player(), 0, "the first seat takes the first turn")
	h.equal(engine.hand_count(0), 0, "players start with empty hands")
	EngineHarness.check_legal_action_shape(h, engine, "first turn")
	var deck_before := engine.deck.size()

	h.check(bool(engine.apply_action_by_key(0, _type_key(engine, "draw_deck")).get("ok", false)),
		"the first blind draw is legal")
	h.equal(engine.hand_count(0), 1, "the first blind draw adds a card")
	h.equal(engine.drawn, 1, "the engine counts the first card")
	h.equal(engine.decision_player(), 0, "one card does not end the turn")
	h.check(bool(engine.apply_action_by_key(0, _type_key(engine, "draw_deck")).get("ok", false)),
		"the second blind draw is legal")
	h.equal(engine.hand_count(0), 2, "the second blind draw adds a card")
	h.equal(engine.drawn, 0, "the draw counter resets")
	h.equal(engine.decision_player(), 1, "the second card ends the turn")
	h.equal(engine.deck.size(), deck_before - 2, "the deck shrinks by the drawn cards")

	var market := _skip_opening(_engine(h))
	market.face_up.clear()
	market.face_up.append("red")
	market.face_up.append("blue")
	var first_card := String(market.face_up[0])
	h.check(bool(market.apply_action_by_key(0, _slot_key(market, 0)).get("ok", false)),
		"a face-up card can be taken")
	h.equal(int(market.hands[0].get(first_card, 0)), 1, "the face-up card joins the hand")
	h.equal(market.face_up.size(), 5, "the market is refilled after a take")
	h.equal(market.decision_player(), 0, "one face-up card does not end the turn")
	h.check(bool(market.apply_action_by_key(0, _slot_key(market, 0)).get("ok", false)),
		"the second face-up card is legal")
	h.equal(market.decision_player(), 1, "the second card ends the turn")

	var loco_first := _skip_opening(_engine(h))
	loco_first.face_up.clear()
	loco_first.face_up.append("locomotive")
	loco_first.face_up.append("red")
	h.check(not _slot_key(loco_first, 0).is_empty(), "a market locomotive can open a turn")
	h.check(bool(loco_first.apply_action_by_key(0, _slot_key(loco_first, 0)).get("ok", false)),
		"taking the locomotive is legal")
	h.equal(int(loco_first.hands[0].get("locomotive", 0)), 1, "the locomotive joins the hand")
	h.equal(loco_first.decision_player(), 1, "a market locomotive ends the turn at once")

	var loco_second := _skip_opening(_engine(h))
	loco_second.face_up.clear()
	loco_second.face_up.append("locomotive")
	loco_second.face_up.append("red")
	h.check(bool(loco_second.apply_action_by_key(0, _slot_key(loco_second, 1)).get("ok", false)),
		"the coloured card is taken first")
	h.equal(loco_second.drawn, 1, "the first card is counted")
	h.check(_slot_key(loco_second, 0).is_empty(), "a face-up locomotive cannot be the second card")

	var reshuffle := _skip_opening(_engine(h))
	reshuffle.deck.clear()
	reshuffle.discard.clear()
	reshuffle.discard.append("red")
	reshuffle.face_up.clear()
	h.check(bool(reshuffle.apply_action_by_key(0, _type_key(reshuffle, "draw_deck")).get("ok", false)),
		"an empty deck reshuffles the discard pile")
	h.equal(int(reshuffle.hands[0].get("red", 0)), 1, "the recycled card joins the hand")
	h.equal(reshuffle.discard.size(), 0, "the discard pile is emptied into the deck")
	h.equal(reshuffle.deck.size(), 0, "the recycled card came from the discard pile")

	var stuck := _skip_opening(_engine(h))
	stuck.deck.clear()
	stuck.discard.clear()
	stuck.face_up.clear()
	stuck.ticket_deck.clear()
	stuck.ticket_discard.clear()
	stuck.hands[0].clear()
	h.equal(stuck.legal_actions(0).size(), 1, "a player with nothing to do is offered one action")
	h.equal(String((stuck.legal_actions(0)[0] as Dictionary).get("type", "")), "pass",
		"the fallback action is a pass")
	h.check(bool(stuck.apply_action_by_key(0, _type_key(stuck, "pass")).get("ok", false)), "passing is legal")
	h.equal(stuck.decision_player(), 1, "passing ends the turn")


# ------------------------------------------------------------------- claiming

func _claiming(h: TestHarness) -> void:
	var route := _route_index("frankfurt_berlin")
	h.check(route >= 0, "the route table contains frankfurt-berlin")
	var engine := _skip_opening(_engine(h))
	engine.hands[0].clear()
	engine.hands[0]["red"] = 3
	var key := _claim_key(engine, route, "red")
	h.check(not key.is_empty(), "three red cards pay for a red route")
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "the claim is legal")
	h.equal(engine.route_owner[route], 0, "the claim marks the owner")
	h.equal(engine.trains_left[0], 42, "the claim spends three trains")
	h.equal(int(engine.hands[0].get("red", 0)), 0, "the claim spends the red cards")
	h.equal(engine.route_points(0), 4, "a three-car route scores four points")
	h.equal(engine.decision_player(), 1, "claiming ends the turn")

	var short := _skip_opening(_engine(h))
	short.hands[0].clear()
	short.hands[0]["red"] = 2
	h.check(_claim_key(short, route, "red").is_empty(), "too few cards cannot pay a route")
	for action: Dictionary in short.legal_actions(0):
		h.check(not (String(action.get("type", "")) == "claim_route" and int(action.get("route", -1)) == route),
			"no variant is offered for an unaffordable route")

	var no_trains := _skip_opening(_engine(h))
	no_trains.hands[0].clear()
	no_trains.hands[0]["red"] = 3
	no_trains.hands[0]["purple"] = 1
	no_trains.trains_left[0] = 2
	h.check(_claim_key(no_trains, route, "red").is_empty(), "two trains cannot cover three cars")
	h.check(not _claim_key(no_trains, _route_index("dieppe_paris"), "purple").is_empty(),
		"a single-car route still fits two trains")

	var grey_route := _route_index("hamburg_berlin")
	var grey := _skip_opening(_engine(h))
	grey.hands[0].clear()
	grey.hands[0]["green"] = 2
	h.check(not _claim_key(grey, grey_route, "green").is_empty(), "a grey route takes a real colour")
	h.check(_claim_key(grey, grey_route, "red").is_empty(), "a grey route still needs the cards")
	h.check(bool(grey.apply_action_by_key(0, _claim_key(grey, grey_route, "green")).get("ok", false)),
		"the grey claim is legal")
	h.equal(int(grey.hands[0].get("green", 0)), 0, "the grey claim spends the chosen colour")
	h.equal(grey.route_owner[grey_route], 0, "the grey route is claimed")

	var mixed := _skip_opening(_engine(h))
	mixed.hands[0].clear()
	mixed.hands[0]["red"] = 2
	mixed.hands[0]["locomotive"] = 1
	h.check(not _claim_key(mixed, route, "red").is_empty(), "a locomotive fills a colour shortfall")
	h.check(bool(mixed.apply_action_by_key(0, _claim_key(mixed, route, "red")).get("ok", false)),
		"the mixed claim is legal")
	h.equal(int(mixed.hands[0].get("red", 0)), 0, "the mixed claim spends the red cards")
	h.equal(int(mixed.hands[0].get("locomotive", 0)), 0, "the locomotive is spent as well")


# -------------------------------------------------------------------- ferries

func _ferries(h: TestHarness) -> void:
	var route := _route_index("london_dieppe")
	var engine := _skip_opening(_engine(h))
	engine.hands[0].clear()
	engine.hands[0]["red"] = 2
	h.check(_claim_key(engine, route, "red").is_empty(), "a ferry needs locomotives")
	engine.hands[0]["locomotive"] = 2
	var key := _claim_key(engine, route, "red")
	h.check(not key.is_empty(), "two locomotives board the ferry")
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "the ferry claim is legal")
	h.equal(int(engine.hands[0].get("locomotive", 0)), 0, "the ferry spends both locomotives")
	h.equal(int(engine.hands[0].get("red", 0)), 2, "the coloured cards stay in hand")
	h.equal(engine.route_owner[route], 0, "the ferry route is claimed")

	var long_route := _route_index("roma_palermo")
	var long_ferry := _skip_opening(_engine(h))
	long_ferry.hands[0].clear()
	long_ferry.hands[0]["blue"] = 1
	long_ferry.hands[0]["locomotive"] = 2
	var long_key := _claim_key(long_ferry, long_route, "blue")
	h.check(not long_key.is_empty(), "a three-car ferry takes two locomotives plus a colour")
	h.check(bool(long_ferry.apply_action_by_key(0, long_key).get("ok", false)), "the big ferry is legal")
	h.equal(int(long_ferry.hands[0].get("blue", 0)), 0, "the colour card is spent")
	h.equal(int(long_ferry.hands[0].get("locomotive", 0)), 0, "both locomotives are spent on the ferry")

	var weak := _skip_opening(_engine(h))
	weak.hands[0].clear()
	weak.hands[0]["red"] = 4
	weak.hands[0]["locomotive"] = 1
	h.check(_claim_key(weak, route, "red").is_empty(), "one locomotive cannot board a two-locomotive ferry")


# -------------------------------------------------------------------- tunnels

func _tunnels(h: TestHarness) -> void:
	var route := _route_index("munchen_venezia")
	h.check(route >= 0, "the route table contains munchen-venezia")
	var engine := _skip_opening(_engine(h))
	engine.hands[0].clear()
	engine.hands[0]["red"] = 6
	engine.deck.clear()
	engine.discard.clear()
	for _i: int in range(3):
		engine.deck.append("red")
	engine.deck.append("green")
	var key := _claim_key(engine, route, "red")
	h.check(not key.is_empty(), "a tunnel can be entered")
	h.check(bool(engine.apply_action_by_key(0, key).get("ok", false)), "entering the tunnel is legal")
	h.equal(engine.phase(), "tunnel", "matching cards trigger the tunnel phase")
	var tunnel: Dictionary = engine.public_state().get("tunnel", {})
	h.equal(int(tunnel.get("extra", 0)), 3, "three matching cards are revealed")
	h.equal(int(tunnel.get("route", -1)), route, "the tunnel names its route")
	h.equal(int(engine.hands[0].get("red", 0)), 4, "the base payment is taken first")
	h.equal(engine.tunnel_revealed.size(), 3, "the revealed cards are remembered")
	EngineHarness.check_legal_action_shape(h, engine, "tunnel decision")
	h.check(bool(engine.apply_action_by_key(0, _type_key(engine, "abort_tunnel")).get("ok", false)),
		"retreating from the tunnel is legal")
	h.equal(int(engine.hands[0].get("red", 0)), 6, "retreating refunds the base payment")
	h.equal(engine.route_owner[route], -1, "an abandoned tunnel stays open")
	h.equal(engine.discard.size(), 3, "the revealed cards are discarded")
	h.equal(engine.decision_player(), 1, "retreating ends the turn")

	var payer := _skip_opening(_engine(h))
	payer.hands[0].clear()
	payer.hands[0]["red"] = 6
	payer.deck.clear()
	payer.discard.clear()
	for _i: int in range(3):
		payer.deck.append("red")
	var pay_key := _claim_key(payer, route, "red")
	payer.apply_action_by_key(0, pay_key)
	h.check(bool(payer.apply_action_by_key(0, _type_key(payer, "pay_tunnel")).get("ok", false)),
		"paying the tunnel is legal")
	h.equal(int(payer.hands[0].get("red", 0)), 1, "the extra cards are spent")
	h.equal(payer.route_owner[route], 0, "the paid tunnel is claimed")
	h.equal(payer.trains_left[0], 43, "the tunnel costs its length in trains")
	h.equal(payer.discard.size(), 3, "the revealed cards are discarded after paying")
	h.equal(payer.decision_player(), 1, "the paid tunnel ends the turn")
	h.equal(payer.phase(), "turn", "the tunnel phase closes")

	var clean := _skip_opening(_engine(h))
	clean.hands[0].clear()
	clean.hands[0]["red"] = 2
	clean.deck.clear()
	clean.discard.clear()
	clean.deck.append("blue")
	clean.deck.append("green")
	clean.deck.append("yellow")
	clean.apply_action_by_key(0, _claim_key(clean, route, "red"))
	h.equal(clean.phase(), "turn", "a clean tunnel commits at once")
	h.equal(clean.route_owner[route], 0, "the clean tunnel is claimed")
	h.equal(clean.discard.size(), 3, "the revealed cards are discarded")
	h.equal(int(clean.hands[0].get("red", 0)), 0, "only the base payment is spent")

	var loco_tunnel := _skip_opening(_engine(h))
	loco_tunnel.hands[0].clear()
	loco_tunnel.hands[0]["red"] = 6
	loco_tunnel.deck.clear()
	loco_tunnel.discard.clear()
	loco_tunnel.deck.append("locomotive")
	loco_tunnel.deck.append("blue")
	loco_tunnel.deck.append("blue")
	loco_tunnel.apply_action_by_key(0, _claim_key(loco_tunnel, route, "red"))
	h.equal(int((loco_tunnel.public_state().get("tunnel", {}) as Dictionary).get("extra", 0)), 1,
		"a revealed locomotive counts as an extra card")
	h.check(bool(loco_tunnel.apply_action_by_key(0, _type_key(loco_tunnel, "pay_tunnel")).get("ok", false)),
		"a single extra card can be paid")
	h.equal(int(loco_tunnel.hands[0].get("red", 0)), 3, "the extra card is spent besides the base")

	var broke := _skip_opening(_engine(h))
	broke.hands[0].clear()
	broke.hands[0]["red"] = 2
	broke.deck.clear()
	broke.discard.clear()
	for _i: int in range(3):
		broke.deck.append("red")
	broke.apply_action_by_key(0, _claim_key(broke, route, "red"))
	h.equal(broke.phase(), "tunnel", "the broke player still faces the tunnel")
	h.check(_type_key(broke, "pay_tunnel").is_empty(), "an unaffordable tunnel offers no payment")
	h.check(not _type_key(broke, "abort_tunnel").is_empty(), "retreating stays available")


# -------------------------------------------------------------------- tickets

func _tickets(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	h.equal(engine.legal_actions(0).size(), 4, "the opening offers four keep-combinations")
	h.check(bool(engine.apply_action_by_key(0, _first_key(engine, 0)).get("ok", false)), "the first keep is legal")
	h.equal(engine.kept_tickets[0].size(), 2, "the first seat keeps two tickets")
	h.equal(engine.ticket_discard.size(), 1, "the unkept ticket is discarded")
	h.equal(engine.decision_player(), 1, "the second seat drafts next")
	h.check(bool(engine.apply_action_by_key(1, _keep_key(engine, 3)).get("ok", false)),
		"keeping all three tickets is legal")
	h.equal(engine.kept_tickets[1].size(), 3, "the second seat keeps three tickets")
	engine.apply_action_by_key(2, _first_key(engine, 2))
	h.equal(engine.phase(), "turn", "the draft ends after every seat")
	h.equal(engine.decision_player(), 0, "the first seat opens the game")
	h.check(_claim_key(engine, _route_index("dieppe_paris"), "purple").is_empty(),
		"an empty hand cannot claim on the first turn")

	h.check(bool(engine.apply_action_by_key(0, _type_key(engine, "draw_tickets")).get("ok", false)),
		"drawing tickets mid-game is legal")
	h.equal(engine.phase(), "tickets", "a fresh offer waits for a choice")
	h.equal(engine.offer.size(), 3, "three tickets are offered mid-game")
	h.equal(engine.offer_min, 1, "a mid-game offer keeps at least one ticket")
	h.equal(engine.legal_actions(0).size(), 7, "every non-empty subset is offered mid-game")
	h.check(bool(engine.apply_action_by_key(0, _keep_key(engine, 1)).get("ok", false)),
		"keeping a single ticket is legal")
	h.equal(engine.kept_tickets[0].size(), 3, "the kept ticket joins the others")
	h.equal(engine.decision_player(), 1, "the ticket turn ends")

	var recycled := _skip_opening(_engine(h))
	recycled.ticket_deck.clear()
	recycled.ticket_discard.clear()
	var recycled_ids: Array[String] = ["athina_berlin", "berlin_bucuresti"]
	for id: String in recycled_ids:
		recycled.ticket_discard.append(id)
	h.check(bool(recycled.apply_action_by_key(0, _type_key(recycled, "draw_tickets")).get("ok", false)),
		"discarded tickets can be drawn again")
	h.equal(recycled.offer.size(), 2, "only the remaining tickets are offered")
	h.equal(recycled.offer_min, 1, "the keep minimum never exceeds the offer")
	for id: Variant in recycled.offer:
		h.check(recycled_ids.has(String(id)), "the recycled ticket comes from the discard pile")
	h.check(bool(recycled.apply_action_by_key(0, _keep_key(recycled, 2)).get("ok", false)),
		"both recycled tickets can be kept")
	h.equal(recycled.kept_tickets[0].size(), 4, "the recycled tickets join the opening pair")

	var thin := _engine(h, 2)
	thin.ticket_deck.clear()
	thin.ticket_discard.clear()
	thin.ticket_deck.append("madrid_munchen")
	thin._deal_offer(1, TicketToRideEngine.START_TICKETS, TicketToRideEngine.START_KEEP)
	h.equal(thin.offer.size(), 1, "no more than the remaining tickets are offered")
	h.equal(thin.offer_min, 1, "the keep minimum drops to the offer size")


# ---------------------------------------------------------------- final round

func _final_round(h: TestHarness) -> void:
	var engine := _skip_opening(_engine(h, 2))
	engine.kept_tickets[0].clear()
	engine.kept_tickets[1].clear()
	engine.hands[0].clear()
	engine.hands[0]["purple"] = 1
	engine.trains_left[0] = 3
	var route := _route_index("dieppe_paris")
	h.check(bool(engine.apply_action_by_key(0, _claim_key(engine, route, "purple")).get("ok", false)),
		"the last claim is legal")
	h.equal(engine.trains_left[0], 2, "two trains remain")
	h.check(bool(_final_state(engine).get("triggered", false)), "the final round is announced")
	h.equal(int(_final_state(engine).get("turns_left", 0)), 1, "the other seat gets one turn")
	h.equal(engine.decision_player(), 1, "play passes to the last seat")
	h.check(not engine.finished, "the match continues for the final round")
	engine.apply_action_by_key(1, _type_key(engine, "draw_deck"))
	h.check(not engine.finished, "the final round lasts a full turn")
	engine.apply_action_by_key(1, _type_key(engine, "draw_deck"))
	h.check(engine.finished, "the final round ends the match")
	h.equal(_reason_key(engine), "game.ticket_to_ride_europe.reason.final_round",
		"the reason names the final round")
	h.check(Loc.has_key(_reason_key(engine)), "the final-round reason is translated")
	var scores: Array = engine.result.get("scores", [])
	h.equal(scores.size(), 2, "both seats are scored")
	h.equal(engine.winner_index(), 0, "the seat with points wins")
	h.equal(int(engine.score_breakdown(0).get("total", 0)), 11,
		"one car plus the longest bonus")
	h.equal(int(engine.score_breakdown(1).get("total", 0)), 0, "an empty network scores nothing")
	var logged := false
	for entry: Variant in engine.move_log:
		if String((entry as Dictionary).get("text_key", "")) == "game.ticket_to_ride_europe.log_final_round":
			logged = true
	h.check(logged, "the final round is announced in the log")

	var three := _skip_opening(_engine(h, 3))
	three.kept_tickets[0].clear()
	three.hands[0].clear()
	three.hands[0]["purple"] = 1
	three.trains_left[0] = 3
	three.apply_action_by_key(0, _claim_key(three, route, "purple"))
	h.equal(int(_final_state(three).get("turns_left", 0)), 2, "both other seats get a turn")
	h.check(not three.finished, "the three-player match continues")
	three.apply_action_by_key(1, _type_key(three, "draw_deck"))
	three.apply_action_by_key(1, _type_key(three, "draw_deck"))
	h.check(not three.finished, "the second seat finished its final turn")
	three.apply_action_by_key(2, _type_key(three, "draw_deck"))
	three.apply_action_by_key(2, _type_key(three, "draw_deck"))
	h.check(three.finished, "the last seat closes the final round")
	h.equal((three.result.get("scores", []) as Array).size(), 3, "all three seats are scored")


# -------------------------------------------------------------------- scoring

func _scoring(h: TestHarness) -> void:
	var engine := _skip_opening(_engine(h, 2))
	engine.route_owner[_route_index("edinburgh_london")] = 0
	engine.route_owner[_route_index("london_dieppe")] = 0
	engine.route_owner[_route_index("dieppe_paris")] = 0
	engine.kept_tickets[0].clear()
	engine.kept_tickets[0].append("edinburgh_paris")
	engine.kept_tickets[1].clear()
	var breakdown: Dictionary = engine.score_breakdown(0)
	h.equal(int(breakdown.get("routes", 0)), 10, "route points follow the length table")
	h.equal(int(breakdown.get("tickets", 0)), 7, "a completed ticket scores its value")
	h.equal(int(breakdown.get("longest", 0)), 7, "the longest chain is measured in cars")
	h.equal(int(breakdown.get("bonus", 0)), 10, "the longest chain earns the bonus")
	h.equal(int(breakdown.get("total", 0)), 27, "the total adds routes, tickets and bonus")
	h.equal(engine.public_state().get("route_points", []), [10, 0], "route points are public")
	engine.kept_tickets[0].append("lisboa_moskva")
	h.equal(int(engine.score_breakdown(0).get("tickets", 0)), -13, "an unfinished ticket is deducted")
	h.equal(int(engine.score_breakdown(0).get("total", 0)), 7, "the deduction reduces the total")

	var simple := _skip_opening(_engine(h, 2, {"longest_path": false}))
	simple.route_owner[_route_index("edinburgh_london")] = 0
	simple.kept_tickets[0].clear()
	h.equal(int(simple.score_breakdown(0).get("bonus", 0)), 0, "the longest bonus can be switched off")
	h.equal(int(simple.score_breakdown(0).get("total", 0)), 7, "without the bonus only routes count")

	var tie := _skip_opening(_engine(h, 2))
	tie.route_owner[_route_index("edinburgh_london")] = 0
	tie.route_owner[_route_index("brest_pamplona")] = 1
	tie.kept_tickets[0].clear()
	tie.kept_tickets[1].clear()
	h.equal(int(tie.score_breakdown(0).get("bonus", 0)), 10, "a tied longest chain earns the bonus")
	h.equal(int(tie.score_breakdown(1).get("bonus", 0)), 10, "both tied players share the bonus")
	h.equal(int(tie.score_breakdown(1).get("routes", 0)), 7, "the tied player's routes count")


# ------------------------------------------------------------------- turn cap

func _turn_cap(h: TestHarness) -> void:
	var engine := _engine(h, 2, {"turn_cap": 20})
	h.equal(engine.turn_cap, 20, "the option sets the cap")
	var floor_engine := _engine(h, 2, {"turn_cap": 5})
	h.equal(floor_engine.turn_cap, 20, "the cap has a floor")
	var steps := 0
	var stuck := false
	while not engine.finished and steps < 600:
		if not EngineHarness.step_first_legal(engine):
			stuck = true
			break
		steps += 1
	h.check(not stuck, "the first-legal player always has a move")
	h.check(engine.finished, "the turn cap ends the match (%d steps)" % steps)
	h.equal(_reason_key(engine), "game.ticket_to_ride_europe.reason.turn_cap", "the reason names the cap")
	h.check(Loc.has_key(_reason_key(engine)), "the cap reason is translated")
	h.equal((engine.result.get("scores", []) as Array).size(), 2, "both seats are scored")
	var late := engine.apply_action_by_key(0, "pass")
	h.equal(bool(late.get("ok", true)), false, "a finished match rejects further actions")
	h.equal(String(late.get("error_key", "")), "game.common.match_over", "the rejection names the end of the match")


# -------------------------------------------------------------------- illegal

func _illegal(h: TestHarness) -> void:
	var engine := _skip_opening(_engine(h))
	h.check(engine.legal_actions(1).is_empty(), "the waiting seat has no actions")
	var out_of_turn := engine.apply_action_by_key(1, "pass")
	h.equal(bool(out_of_turn.get("ok", true)), false, "acting out of turn is rejected")
	h.equal(String(out_of_turn.get("error_key", "")), "game.common.not_your_turn",
		"the rejection names the turn order")
	h.check(Loc.has_key(String(out_of_turn.get("error_key", ""))), "the rejection key is translated")
	var bogus := engine.apply_action_by_key(0, "colour=purple|route=999|type=claim_route")
	h.equal(bool(bogus.get("ok", true)), false, "an unknown key is rejected")
	h.equal(String(bogus.get("error_key", "")), "game.common.illegal_action",
		"the rejection names the illegal action")
	var forged := engine.apply_action({"key": "keep=0|type=keep_tickets"})
	h.equal(bool(forged.get("ok", true)), false, "a forged action object is rejected")
	h.equal(String(forged.get("error_key", "")), "game.ticket_to_ride_europe.error.illegal_action",
		"the engine reports its own illegal-action key")
	engine.hands[0].clear()
	engine.hands[0]["purple"] = 1
	var short_route := _route_index("dieppe_paris")
	var legal_claim := _claim_key(engine, short_route, "purple")
	h.check(not legal_claim.is_empty(), "a single purple card pays the short route")
	engine.hands[0].clear()
	h.check(_claim_key(engine, short_route, "purple").is_empty(), "the claim leaves the table without cards")
	var unaffordable := engine.apply_action_by_key(0, legal_claim)
	h.equal(bool(unaffordable.get("ok", true)), false, "an unaffordable claim is rejected")
	h.equal(String(unaffordable.get("error_key", "")), "game.common.illegal_action",
		"the engine re-validates the payment")


# ---------------------------------------------------------------- determinism

func _determinism(h: TestHarness) -> void:
	var a := _engine(h, 3)
	var b := _engine(h, 3)
	var same := true
	var steps := 0
	while not a.finished and steps < 60:
		if _keys_of(a.legal_actions(a.decision_player())) != _keys_of(b.legal_actions(b.decision_player())):
			same = false
			break
		if not EngineHarness.step_first_legal(a) or not EngineHarness.step_first_legal(b):
			same = false
			break
		steps += 1
	h.check(same, "the same seed offers the same actions at every step (%d steps)" % steps)
	h.equal(a.public_state(), b.public_state(), "the public state stays identical")
	h.equal(a.private_state(0), b.private_state(0), "the first hand stays identical")
	h.equal(a.private_state(2), b.private_state(2), "the third hand stays identical")


# ------------------------------------------------------------------ snapshots

func _shared_fields() -> Array[String]:
	# Fields a merged snapshot must reproduce exactly. Seats other than the
	# snapshot owner keep their hidden hands and tickets to themselves, so the
	# aggregate counts (`hand_count`, `ticket_count`) are not part of this list.
	return [
		"turn", "round", "phase", "decision_player", "route_owner", "route_points",
		"trains_left", "face_up", "deck_count", "discard_count", "tickets_left",
		"_deck", "_discard", "_ticket_deck", "_ticket_discard", "active", "drawn",
		"opening_index", "offer_player", "offer_count", "offer_min", "tunnel",
		"final", "turn_cap", "longest_path",
	]


func _snapshot(h: TestHarness) -> void:
	var draft := _engine(h, 3)
	h.check(bool(draft.apply_action_by_key(0, _first_key(draft, 0)).get("ok", false)),
		"the first seat keeps its tickets")
	h.equal(draft.decision_player(), 1, "the second seat drafts next")
	var draft_copy := Session.create_engine("ticket_to_ride_europe") as TicketToRideEngine
	var draft_state := draft.public_state()
	draft_state.merge(draft.private_state(1), true)
	draft_copy.restore_state(draft_state)
	for field: String in _shared_fields():
		h.equal(draft_copy.public_state().get(field), draft.public_state().get(field),
			"the draft snapshot keeps %s" % field)
	h.equal(draft_copy.private_state(1), draft.private_state(1), "the draft offer travels with its seat")
	h.equal(_keys_of(draft_copy.legal_actions(1)), _keys_of(draft.legal_actions(1)),
		"the draft choices survive the snapshot")
	h.check(bool(draft_copy.apply_action_by_key(1, _first_key(draft_copy, 1)).get("ok", false)),
		"the restored engine accepts the seat's choice")
	h.equal(draft_copy.decision_player(), 2, "the restored draft moves to the next seat")
	h.equal(draft_copy.phase(), "tickets", "the third seat still has to choose")
	h.equal(draft_copy.offer.size(), 3, "the third seat gets a fresh offer")
	h.check(bool(draft.apply_action_by_key(1, _first_key(draft, 1)).get("ok", false)),
		"the original engine takes the same choice")
	h.equal(draft_copy.private_state(2), draft.private_state(2),
		"the third seat is dealt the same tickets after the restore")

	var engine := _skip_opening(_engine(h, 3))
	for _i: int in range(6):
		EngineHarness.step_first_legal(engine)
	var actor := engine.decision_player()
	var merged := engine.public_state()
	merged.merge(engine.private_state(actor), true)
	var copy := Session.create_engine("ticket_to_ride_europe") as TicketToRideEngine
	copy.restore_state(merged)
	for field: String in _shared_fields():
		h.equal(copy.public_state().get(field), engine.public_state().get(field),
			"the turn snapshot keeps %s" % field)
	h.equal(copy.private_state(actor), engine.private_state(actor),
		"the actor's hidden state travels with the snapshot")
	h.equal(_keys_of(copy.legal_actions(actor)), _keys_of(engine.legal_actions(actor)),
		"the legal actions survive the snapshot")
	var move := _first_key(engine, actor)
	h.check(bool(copy.apply_action_by_key(actor, move).get("ok", false)),
		"the restored engine accepts the same move")
	h.check(bool(engine.apply_action_by_key(actor, move).get("ok", false)),
		"the original engine accepts the same move")
	h.equal(copy.private_state(actor), engine.private_state(actor),
		"the two engines stay in step on hidden cards")
	for field: String in ["turn", "round", "active", "drawn", "_deck", "_ticket_deck"]:
		h.equal(copy.public_state().get(field), engine.public_state().get(field),
			"the two engines stay in step on %s" % field)


# -------------------------------------------------------------------- privacy

func _ticket_overlap(theirs: Dictionary, mine: Dictionary) -> Array:
	var leaked: Array = []
	for field: String in ["tickets", "offer"]:
		var secret: Array = theirs.get(field, [])
		var own: Array = mine.get(field, [])
		for item: Variant in secret:
			if own.has(item):
				leaked.append("%s:%s" % [field, str(item)])
	return leaked


func _privacy(h: TestHarness) -> void:
	var engine := _engine(h, 3)
	var public := engine.public_state()
	for field: String in ["hand", "tickets", "offer"]:
		h.check(not public.has(field), "the public state hides %s" % field)
	h.equal(engine.private_state(1).get("offer", []), [], "only the drafting seat sees the offer")
	h.equal(engine.private_state(1).get("tickets", []), [], "a waiting seat holds no tickets")
	h.equal(engine.private_state(-1), {}, "an invalid seat has no private state")
	h.equal(engine.private_state(9), {}, "a seat beyond the table has no private state")
	EngineHarness.check_privacy(h, engine, _ticket_overlap, "ticket draft")
	engine = _skip_opening(engine)
	engine.hands[0].clear()
	engine.hands[0]["red"] = 2
	engine.hands[0]["locomotive"] = 1
	engine.hands[1].clear()
	engine.hands[1]["blue"] = 3
	h.equal(engine.private_state(0).get("hand", {}), {"red": 2, "locomotive": 1},
		"the first seat sees its own hand")
	h.equal(engine.private_state(1).get("hand", {}), {"blue": 3}, "the second seat sees its own hand")
	h.equal(int((engine.private_state(0).get("hand", {}) as Dictionary).get("blue", 0)), 0,
		"the first seat cannot see the second hand")
	h.equal(int((engine.private_state(1).get("hand", {}) as Dictionary).get("red", 0)), 0,
		"the second seat cannot see the first hand")
	engine.kept_tickets[0].clear()
	engine.kept_tickets[0].append("athina_berlin")
	engine.kept_tickets[1].clear()
	engine.kept_tickets[1].append("dieppe_marseille")
	engine.kept_tickets[2].clear()
	h.equal(engine.private_state(0).get("tickets", []), ["athina_berlin"], "kept tickets stay private")
	h.check(not (engine.private_state(0).get("tickets", []) as Array).has("dieppe_marseille"),
		"the first seat cannot see the second seat's tickets")
	h.equal(engine.public_state().get("ticket_count", []), [1, 1, 0], "ticket counts stay public")
	h.equal(engine.public_state().get("hand_count", []), [3, 3, 0], "hand sizes stay public")
	EngineHarness.check_privacy(h, engine, _ticket_overlap, "kept tickets")


# ------------------------------------------------------------------ bot match

func _bot_match(h: TestHarness) -> void:
	var engine := _engine(h, 2)
	var illegal := ""
	var steps := 0
	while not engine.finished and steps < 4000:
		var actor := engine.decision_player()
		var key := BotDirector.choose_action(engine, actor)
		var action := engine.find_legal_action(actor, key)
		if action.is_empty():
			illegal = key
			break
		engine.apply_action(action)
		steps += 1
	h.check(illegal.is_empty(), "the bot only proposes legal actions (%s)" % illegal)
	h.check(engine.finished, "a bot-only match finishes (%d steps)" % steps)
	h.check(String(_reason_key(engine)).begins_with("game.ticket_to_ride_europe.reason."),
		"the match ends with one of the game's reasons")
	h.check(Loc.has_key(_reason_key(engine)), "the ending reason is translated")
	var scores: Array = engine.result.get("scores", [])
	h.equal(scores.size(), 2, "both seats are scored")
	var best := -99999
	var best_player := -1
	var tied := false
	for entry: Variant in scores:
		var score := int((entry as Dictionary).get("score", 0))
		var seat := int((entry as Dictionary).get("player", -1))
		if score > best:
			best = score
			best_player = seat
			tied = false
		elif score == best:
			tied = true
	h.equal(engine.winner_index(), -1 if tied else best_player, "the winner has the highest score")
	for entry: Variant in scores:
		h.check(int((entry as Dictionary).get("score", 0)) > -1000,
			"seat %s scores a plausible total" % str((entry as Dictionary).get("name", "?")))

	var crowd := _engine(h, 5)
	var crowd_steps := EngineHarness.play_out(crowd)
	h.check(crowd.finished, "a five-player bot match finishes (%d steps)" % crowd_steps)
	h.equal((crowd.result.get("scores", []) as Array).size(), 5, "all five seats are scored")
