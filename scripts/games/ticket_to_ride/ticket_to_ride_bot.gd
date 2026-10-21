extends RefCounted
## Ticket to Ride: Europe bot: a greedy ticket-driven route planner.
##
## The bot is deterministic and reads only the public state plus its own hand and
## tickets through `private_state()`. It keeps the tickets it can plausibly
## connect, claims the cheapest links leading from its network towards the
## endpoints of its kept tickets, and draws the colours those links still need.
## `BotDirector` re-validates every key, so a mistake can only waste a turn.

var engine: GameEngine = null
var player: int = 0
var _public: Dictionary = {}
var _private: Dictionary = {}


func choose_action(active_engine: GameEngine, active_player: int) -> String:
	engine = active_engine
	player = active_player
	if engine == null:
		return ""
	_public = engine.public_state()
	_private = engine.private_state(player)
	var actions: Array = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	match String(engine.phase()):
		"tickets":
			return VariantUtil.as_string(_pick_keep(actions).get("key", ""), "")
		"tunnel":
			return VariantUtil.as_string(_pick_tunnel(actions).get("key", ""), "")
	var claim := _pick_claim(actions)
	if not claim.is_empty():
		return VariantUtil.as_string(claim.get("key", ""), "")
	var draw := _pick_draw(actions)
	if not draw.is_empty():
		return VariantUtil.as_string(draw.get("key", ""), "")
	return VariantUtil.as_string(VariantUtil.as_dict(actions[0]).get("key", ""), "")


# --------------------------------------------------------------------- helpers

func _hand() -> Dictionary:
	var hand: Variant = _private.get("hand", {})
	if hand is Dictionary:
		return hand as Dictionary
	return {}


func _hand_total() -> int:
	var total := 0
	for count: Variant in _hand().values():
		total += VariantUtil.as_int(count, 0)
	return total


func _tickets() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in VariantUtil.as_array(_private.get("tickets", [])):
		out.append(VariantUtil.as_string(id, ""))
	return out


func _ticket(id: String) -> Dictionary:
	for entry: Dictionary in TicketToRideEngine.TICKETS:
		if VariantUtil.as_string(entry.get("id", ""), "") == id:
			return entry
	return {}


func _route(index: int) -> Dictionary:
	if index < 0 or index >= TicketToRideEngine.ROUTES.size():
		return {}
	return TicketToRideEngine.ROUTES[index]


func _network_cities() -> Array[String]:
	var out: Array[String] = []
	var owner: Array = VariantUtil.as_array(_public.get("route_owner", []))
	for index: int in range(mini(owner.size(), TicketToRideEngine.ROUTES.size())):
		if VariantUtil.as_int(owner[index], -1) != player:
			continue
		var route := _route(index)
		for key: String in ["a", "b"]:
			var city := VariantUtil.as_string(route.get(key, ""), "")
			if not city.is_empty() and not out.has(city):
				out.append(city)
	return out


func _adjacency() -> Dictionary:
	var adjacency: Dictionary = {}
	for index: int in range(TicketToRideEngine.ROUTES.size()):
		var route := _route(index)
		var a := VariantUtil.as_string(route.get("a", ""), "")
		var b := VariantUtil.as_string(route.get("b", ""), "")
		var length := VariantUtil.as_int(route.get("length", 1), 1)
		_append_edge(adjacency, a, b, length, index)
		_append_edge(adjacency, b, a, length, index)
	return adjacency


func _append_edge(adjacency: Dictionary, from: String, to: String, length: int, index: int) -> void:
	var list: Array = adjacency.get(from, [])
	list.append({"city": to, "length": length, "route": index})
	adjacency[from] = list


## Wanted routes: every link on the shortest chains from the endpoints of the
## kept tickets towards the player's network, weighted by the ticket value.
func _plan() -> Dictionary:
	var plan: Dictionary = {}
	var owned := _network_cities()
	if owned.is_empty():
		return plan
	var adjacency := _adjacency()
	var dist: Dictionary = {}
	var parent_route: Dictionary = {}
	var parent_city: Dictionary = {}
	var queue: Array[String] = []
	for city: String in owned:
		dist[city] = 0
		queue.append(city)
	var head := 0
	while head < queue.size():
		var city: String = queue[head]
		head += 1
		for edge: Variant in adjacency.get(city, []):
			var step: Dictionary = edge
			var next := VariantUtil.as_string(step.get("city", ""), "")
			if dist.has(next):
				continue
			dist[next] = VariantUtil.as_int(dist[city], 0) + 1
			parent_route[next] = VariantUtil.as_int(step.get("route", -1), -1)
			parent_city[next] = city
			queue.append(next)
	for id: String in _tickets():
		var ticket := _ticket(id)
		var value := VariantUtil.as_int(ticket.get("value", 0), 0)
		if value <= 0:
			continue
		for key: String in ["a", "b"]:
			var city := VariantUtil.as_string(ticket.get(key, ""), "")
			var guard := 0
			while parent_route.has(city) and guard < TicketToRideEngine.CITIES.size():
				guard += 1
				var index := VariantUtil.as_int(parent_route[city], -1)
				if index >= 0:
					plan[index] = VariantUtil.as_int(plan.get(index, 0), 0) + value
				var previous := VariantUtil.as_string(parent_city.get(city, ""), "")
				if previous.is_empty() or previous == city:
					break
				city = previous
	return plan


func _distance_from_network() -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[String] = []
	for city: String in _network_cities():
		dist[city] = 0
		queue.append(city)
	if queue.is_empty():
		return dist
	var adjacency := _adjacency()
	var head := 0
	while head < queue.size():
		var city: String = queue[head]
		head += 1
		for edge: Variant in adjacency.get(city, []):
			var next := VariantUtil.as_string(VariantUtil.as_dict(edge).get("city", ""), "")
			if dist.has(next):
				continue
			dist[next] = VariantUtil.as_int(dist[city], 0) + 1
			queue.append(next)
	return dist


## Cards the wanted routes still need, by colour (locomotives included).
func _colour_needs(plan: Dictionary) -> Dictionary:
	var needs: Dictionary = {}
	var hand := _hand()
	for index: Variant in plan:
		var route := _route(VariantUtil.as_int(index, -1))
		var length := VariantUtil.as_int(route.get("length", 0), 0)
		if length <= 0:
			continue
		var ferries := VariantUtil.as_int(route.get("ferries", 0), 0)
		needs[TicketToRideEngine.LOCOMOTIVE] = VariantUtil.as_int(needs.get(TicketToRideEngine.LOCOMOTIVE, 0), 0) + ferries
		var colour := VariantUtil.as_string(route.get("colour", ""), "grey")
		if colour == "grey":
			colour = _best_grey_colour(length)
		needs[colour] = VariantUtil.as_int(needs.get(colour, 0), 0) + length
	return needs


func _best_grey_colour(length: int) -> String:
	var hand := _hand()
	var best := TicketToRideEngine.COLOURS[0]
	var best_count := -1
	for colour: String in TicketToRideEngine.COLOURS:
		var count := VariantUtil.as_int(hand.get(colour, 0), 0)
		if count > best_count:
			best_count = count
			best = colour
	return best


func _ferry_need(plan: Dictionary) -> int:
	var ferry_cards := 0
	for index: Variant in plan:
		ferry_cards += VariantUtil.as_int(_route(VariantUtil.as_int(index, -1)).get("ferries", 0), 0)
	return maxi(0, ferry_cards - VariantUtil.as_int(_hand().get(TicketToRideEngine.LOCOMOTIVE, 0), 0))


# ------------------------------------------------------------------- decisions

func _pick_claim(actions: Array) -> Dictionary:
	var plan := _plan()
	var hand := _hand()
	var best: Dictionary = {}
	var best_score := -1e9
	for action: Variant in actions:
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if VariantUtil.as_string(entry.get("type", ""), "") != "claim_route":
			continue
		var index := VariantUtil.as_int(entry.get("route", -1), -1)
		var route := _route(index)
		if route.is_empty():
			continue
		var length := VariantUtil.as_int(route.get("length", 1), 1)
		var chosen := VariantUtil.as_string(entry.get("colour", ""), "")
		var weight := VariantUtil.as_int(plan.get(index, 0), 0)
		var score := 0.5 / float(maxi(1, length))
		if weight > 0:
			score = float(weight) * 10.0 + 6.0 / float(maxi(1, length))
		score += 0.25 * float(VariantUtil.as_int(hand.get(chosen, 0), 0))
		var ferries := VariantUtil.as_int(route.get("ferries", 0), 0)
		var loco_part := clampi(maxi(ferries, length - VariantUtil.as_int(hand.get(chosen, 0), 0)), 0, length)
		score -= 1.0 * float(loco_part)
		if score > best_score:
			best_score = score
			best = entry
	if best.is_empty():
		return {}
	var best_index := VariantUtil.as_int(best.get("route", -1), -1)
	if VariantUtil.as_int(plan.get(best_index, 0), 0) <= 0 and _hand_total() < 9 and not _network_cities().is_empty():
		return {}
	return best


func _pick_draw(actions: Array) -> Dictionary:
	var plan := _plan()
	var hand := _hand()
	var needs := _colour_needs(plan)
	var loco_need := _ferry_need(plan)
	if _hand_total() >= 14:
		for action: Variant in actions:
			if action is Dictionary and VariantUtil.as_string(VariantUtil.as_dict(action).get("type", ""), "") == "draw_tickets":
				return action
	var best: Dictionary = {}
	var best_score := 0.0
	for action: Variant in actions:
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if VariantUtil.as_string(entry.get("type", ""), "") != "draw_face":
			continue
		var card := VariantUtil.as_string(entry.get("_card", ""), "")
		var score := 0.0
		if card == TicketToRideEngine.LOCOMOTIVE:
			score = maxf(float(VariantUtil.as_int(needs.get(TicketToRideEngine.LOCOMOTIVE, 0), 0)), float(loco_need)) - 0.5
		else:
			score = float(VariantUtil.as_int(needs.get(card, 0), 0)) + 0.1 * float(VariantUtil.as_int(hand.get(card, 0), 0))
		if score > best_score:
			best_score = score
			best = entry
	if not best.is_empty() and best_score > 0.0:
		return best
	for action: Variant in actions:
		if action is Dictionary and VariantUtil.as_string(VariantUtil.as_dict(action).get("type", ""), "") == "draw_deck":
			return action
	return {}


func _pick_keep(actions: Array) -> Dictionary:
	var offered: Array = VariantUtil.as_array(_private.get("offer", []))
	var dist := _distance_from_network()
	var best: Dictionary = {}
	var best_score := -1e9
	var best_count := -1
	for action: Variant in actions:
		if not (action is Dictionary):
			continue
		var entry: Dictionary = action
		if VariantUtil.as_string(entry.get("type", ""), "") != "keep_tickets":
			continue
		var keep := VariantUtil.as_string(entry.get("keep", ""), "").split(",", false)
		var score := 0.0
		for item: String in keep:
			var index := int(item)
			if index < 0 or index >= offered.size():
				continue
			var ticket := _ticket(VariantUtil.as_string(offered[index], ""))
			var value := VariantUtil.as_int(ticket.get("value", 0), 0)
			var a := VariantUtil.as_string(ticket.get("a", ""), "")
			var b := VariantUtil.as_string(ticket.get("b", ""), "")
			var reach := VariantUtil.as_int(dist.get(a, 99), 99) + VariantUtil.as_int(dist.get(b, 99), 99)
			score += float(value)
			if reach <= 6:
				score += 2.0
			elif reach >= 60:
				score -= 2.0
		var count := keep.size()
		if score > best_score + 0.0001 or (absf(score - best_score) <= 0.0001 and count > best_count):
			best_score = score
			best_count = count
			best = entry
	return best


func _pick_tunnel(actions: Array) -> Dictionary:
	for action: Variant in actions:
		if action is Dictionary and VariantUtil.as_string(VariantUtil.as_dict(action).get("type", ""), "") == "pay_tunnel":
			return action
	for action: Variant in actions:
		if action is Dictionary and VariantUtil.as_string(VariantUtil.as_dict(action).get("type", ""), "") == "abort_tunnel":
			return action
	return {}
