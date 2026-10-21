class_name CitadelsEngine
extends GameEngine
## Citadels rules engine (2-8 players): hidden character draft, gold/card income,
## district building and the eight character powers.
##
## A round has two halves. First every player drafts characters in seat order
## (with 2-3 players each drafts two). Then characters 1-8 are called in order:
## the owner takes income (two gold or two cards), uses their power once and may
## build one district (three as the Architect). The first player to complete a
## city of eight districts ends the round and the highest score wins.
##
## Hidden information: the districts in a player's hand and the characters they
## drafted. [method private_state] exposes only the owner's secrets; the draw
## pile travels in the "table secrets" snapshot ([code]private_state(-1)[/code])
## so a match can be saved and resumed without leaking it to a seat.
##
## Simplifications (documented on purpose): the deck is 45 districts, unique
## districts have no special power, the Assassin's victim is revealed at once,
## the Thief robs immediately when stealing, the Magician may swap hands with a
## player or discard and redraw, and a round limit ends stalled matches.

const ROLE_COUNT: int = 8
const DISTRICT_GOAL: int = 8
const DEFAULT_ROUND_LIMIT: int = 30
const COLOUR_COUNT: int = 5

## Index 0 is unused so role ids match the calling order 1-8.
const ROLE_KEYS: Array = ["", "assassin", "thief", "magician", "king", "bishop", "merchant", "architect", "warlord"]
const COLOURS: Array = ["noble", "religious", "trade", "military", "unique"]

## Static district deck: 45 cards in total (Chess-style: no runtime file IO).
const DISTRICTS: Array = [
	{"id": "castle", "cost": 4, "colour": "noble", "copies": 3},
	{"id": "manor", "cost": 3, "colour": "noble", "copies": 4},
	{"id": "palace", "cost": 5, "colour": "noble", "copies": 2},
	{"id": "cathedral", "cost": 5, "colour": "religious", "copies": 2},
	{"id": "monastery", "cost": 3, "colour": "religious", "copies": 4},
	{"id": "temple", "cost": 2, "colour": "religious", "copies": 3},
	{"id": "harbour", "cost": 4, "colour": "trade", "copies": 3},
	{"id": "trading_post", "cost": 3, "colour": "trade", "copies": 3},
	{"id": "market", "cost": 2, "colour": "trade", "copies": 4},
	{"id": "tavern", "cost": 1, "colour": "trade", "copies": 4},
	{"id": "fortress", "cost": 5, "colour": "military", "copies": 2},
	{"id": "battlefield", "cost": 3, "colour": "military", "copies": 3},
	{"id": "watchtower", "cost": 1, "colour": "military", "copies": 3},
	{"id": "library", "cost": 6, "colour": "unique", "copies": 1},
	{"id": "university", "cost": 6, "colour": "unique", "copies": 1},
	{"id": "observatory", "cost": 5, "colour": "unique", "copies": 1},
	{"id": "graveyard", "cost": 5, "colour": "unique", "copies": 1},
	{"id": "smithy", "cost": 5, "colour": "unique", "copies": 1},
]

const ACTION_TYPES: Array = ["take_role", "income", "draw_cards", "build", "end_turn",
	"assassinate", "steal", "magician_swap", "magician_discard", "destroy"]

## step: "draft" | "income" | "action" | "finished" (phase ids).
var step: String = "draft"
var deck: Array[String] = []
var discard: Array[String] = []
var hands: Array = []  # player -> Array[String] of district ids
var cities: Array = []  # player -> Array[String] of built district ids
var gold: Array[int] = []
var role_owner: Array[int] = []  # role id -> player, -1 when undrafted
var role_pool: Array[int] = []
var draft_order: Array[int] = []
var draft_index: int = 0
var first_player: int = 0
var roles_per_player: int = 1
var two_roles: bool = true
var current_role: int = 0
var current_player: int = -1
var killed_role: int = 0
var power_used: bool = false
var builds_done: int = 0
var build_limit: int = 1
var first_to_eight: int = -1
var round_limit: int = DEFAULT_ROUND_LIMIT


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "citadels"


func setup(options: Dictionary) -> void:
	super.setup(options)
	round_limit = clampi(VariantUtil.as_int(options.get("round_limit", DEFAULT_ROUND_LIMIT), DEFAULT_ROUND_LIMIT), 10, 60)
	two_roles = bool(options.get("two_roles", true))
	roles_per_player = 2 if two_roles and player_count() <= 3 else 1
	deck.clear()
	for entry: Dictionary in DISTRICTS:
		for _copy: int in range(VariantUtil.as_int(entry.get("copies", 1), 1)):
			deck.append(VariantUtil.as_string(entry.get("id", ""), ""))
	_shuffle(deck)
	discard.clear()
	hands.clear()
	cities.clear()
	gold.clear()
	for player: int in range(player_count()):
		var hand: Array[String] = []
		var city: Array[String] = []
		hands.append(hand)
		cities.append(city)
		gold.append(2)
		_draw_into(player, 4)
	role_owner.clear()
	for _role: int in range(ROLE_COUNT + 1):
		role_owner.append(-1)
	killed_role = 0
	first_to_eight = -1
	first_player = 0
	step = "draft"
	round_index = 0
	_start_round()
	log_event("game.citadels.log_start", {"players": player_count()})


func phases() -> PackedStringArray:
	return PackedStringArray(["draft", "income", "action", "finished"])


func phase() -> String:
	return "finished" if finished else step


func decision_player() -> int:
	if finished:
		return -1
	match step:
		"draft":
			if draft_index < draft_order.size():
				return draft_order[draft_index]
		"income", "action":
			return current_player
	return -1


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "round_limit", "label_key": "game.citadels.option.round_limit", "type": "int",
			"default": DEFAULT_ROUND_LIMIT, "min": 10, "max": 60,
			"hint_key": "game.citadels.option.round_limit_hint"},
		{"key": "two_roles", "label_key": "game.citadels.option.two_roles", "type": "bool",
			"default": true, "hint_key": "game.citadels.option.two_roles_hint"},
	]


# ------------------------------------------------------------------- helpers

## Cost/colour lookup for a district id (the deck table is tiny and static).
static func district_cost(card_id: String) -> int:
	for entry: Dictionary in DISTRICTS:
		if VariantUtil.as_string(entry.get("id", ""), "") == card_id:
			return VariantUtil.as_int(entry.get("cost", 0), 0)
	return 0


static func district_colour(card_id: String) -> String:
	for entry: Dictionary in DISTRICTS:
		if VariantUtil.as_string(entry.get("id", ""), "") == card_id:
			return VariantUtil.as_string(entry.get("colour", ""), "")
	return "unique"


func role_key(role: int) -> String:
	if role < 1 or role > ROLE_COUNT:
		return ""
	return VariantUtil.as_string(ROLE_KEYS[role], "")


func role_name(role: int) -> String:
	var key := role_key(role)
	return "" if key.is_empty() else Loc.t("game.citadels.role.%s" % key)


func district_name(card_id: String) -> String:
	return Loc.t("game.citadels.district.%s" % card_id)


func hand_of(player: int) -> Array[String]:
	if player < 0 or player >= hands.size():
		var empty: Array[String] = []
		return empty
	return hands[player]


func city_of(player: int) -> Array[String]:
	if player < 0 or player >= cities.size():
		var empty: Array[String] = []
		return empty
	return cities[player]


func gold_of(player: int) -> int:
	return gold[player] if player >= 0 and player < gold.size() else 0


## Winning score breakdown: district costs, +3 for all five colours and +4 for
## the player who first completed a city of eight districts.
func score_of(player: int) -> Dictionary:
	var base := 0
	var seen: Dictionary = {}
	for card_id: String in city_of(player):
		base += district_cost(card_id)
		seen[district_colour(card_id)] = true
	var colour_bonus := 3 if seen.size() >= COLOUR_COUNT else 0
	var first_bonus := 4 if first_to_eight == player else 0
	return {"base": base, "colour": colour_bonus, "first": first_bonus, "total": base + colour_bonus + first_bonus}


## Cards hidden in hands plus cards still in the pile; drawing needs at least one.
func _available_cards() -> int:
	return deck.size() + discard.size()


func _draw_district() -> String:
	if deck.is_empty() and not discard.is_empty():
		deck.append_array(discard)
		discard.clear()
		_shuffle(deck)
	if deck.is_empty():
		return ""
	return deck.pop_front()


func _draw_into(player: int, count: int) -> int:
	var drawn: Array[String] = []
	for _i: int in range(count):
		var card := _draw_district()
		if card.is_empty():
			break
		drawn.append(card)
	var hand: Array[String] = hands[player]
	hand.append_array(drawn)
	return drawn.size()


## Deterministic Fisher-Yates with the engine rng (never Array.shuffle()).
func _shuffle(cards: Array) -> void:
	for i: int in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = cards[i]
		cards[i] = cards[j]
		cards[j] = swap


func _is_protected_by_bishop(target: int) -> bool:
	if killed_role == 5:
		return false
	return role_owner[5] == target


# --------------------------------------------------------------- round starts

func _start_round() -> void:
	round_index += 1
	role_pool.clear()
	for role: int in range(1, ROLE_COUNT + 1):
		role_pool.append(role)
	role_owner.clear()
	for _role: int in range(ROLE_COUNT + 1):
		role_owner.append(-1)
	draft_order.clear()
	for _pass: int in range(roles_per_player):
		for offset: int in range(player_count()):
			draft_order.append((first_player + offset) % player_count())
	draft_index = 0
	current_role = 0
	current_player = -1
	killed_role = 0
	power_used = false
	builds_done = 0
	build_limit = 1
	step = "draft"
	log_event("game.citadels.log_round", {"round": round_index, "player": player_name(first_player)})


func _take_role(player: int, role: int) -> Dictionary:
	if role < 1 or role > ROLE_COUNT or not role_pool.has(role):
		return _fail("game.citadels.error.role_unavailable")
	role_pool.erase(role)
	role_owner[role] = player
	draft_index += 1
	# The chosen character stays secret until it is called.
	log_event("game.citadels.log_draft", {"player": player_name(player)}, player)
	if draft_index >= draft_order.size():
		_call_next_role(1)
	return _ok()


func _call_next_role(from_role: int) -> void:
	var role := from_role
	while role <= ROLE_COUNT and role_owner[role] < 0:
		role += 1
	if role > ROLE_COUNT:
		_end_round()
		return
	current_role = role
	if role == killed_role:
		log_event("game.citadels.log_killed", {"role": role_name(role)})
		_call_next_role(role + 1)
		return
	var owner := role_owner[role]
	current_player = owner
	power_used = false
	builds_done = 0
	build_limit = 1
	step = "income"
	log_event("game.citadels.log_call", {"player": player_name(owner), "role": role_name(role)}, owner)
	_apply_upkeep(owner, role)


## Automatic part of a character power, applied the moment the role is called.
func _apply_upkeep(player: int, role: int) -> void:
	match role:
		4:  # King: takes the crown and collects one gold per noble district.
			first_player = player
			var nobles := _colour_count(player, "noble")
			gold[player] += nobles
			log_event("game.citadels.log_crown", {"player": player_name(player), "role": role_name(role)}, player)
			if nobles > 0:
				log_event("game.citadels.log_upkeep", {
					"player": player_name(player), "gold": nobles, "role": role_name(role),
				}, player)
		5:  # Bishop: one gold per religious district.
			var religious := _colour_count(player, "religious")
			if religious > 0:
				gold[player] += religious
				log_event("game.citadels.log_upkeep", {
					"player": player_name(player), "gold": religious, "role": role_name(role),
				}, player)
		6:  # Merchant: one gold, plus one per trade district.
			var trade := _colour_count(player, "trade") + 1
			gold[player] += trade
			log_event("game.citadels.log_upkeep", {
				"player": player_name(player), "gold": trade, "role": role_name(role),
			}, player)
		7:  # Architect: draws two extra district cards and may build three times.
			build_limit = 3
			var drawn := _draw_into(player, 2)
			log_event("game.citadels.log_architect", {"player": player_name(player), "count": drawn}, player)


func _colour_count(player: int, colour: String) -> int:
	var count := 0
	for card_id: String in city_of(player):
		if district_colour(card_id) == colour:
			count += 1
	return count


# ---------------------------------------------------------- legal action list

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player != decision_player():
		return out
	match step:
		"draft":
			for role: int in role_pool:
				out.append(make_action("take_role", {"role": role}, "game.citadels.role.%s" % role_key(role)))
		"income":
			out.append(make_action("income", {}, "game.citadels.action.income"))
			if _available_cards() > 0:
				out.append(make_action("draw_cards", {}, "game.citadels.action.draw"))
		"action":
			_append_action_step(out, player)
	return out


func _append_action_step(out: Array[Dictionary], player: int) -> void:
	if builds_done < build_limit and city_of(player).size() < DISTRICT_GOAL:
		var hand: Array[String] = hands[player]
		for slot: int in range(hand.size()):
			# Only affordable districts are legal builds (§6.7): an entry the
			# engine rejects on apply must never reach the action list. Views
			# render a card without an action as a dimmed, inert face.
			if gold[player] < district_cost(hand[slot]):
				continue
			var build := make_action("build", {"card": hand[slot], "slot": slot}, "game.citadels.action.build")
			build["_direct"] = false
			out.append(build)
	if not power_used:
		_append_power_actions(out, player)
	var end_turn := make_action("end_turn", {}, "game.citadels.action.end_turn")
	end_turn["_direct"] = true
	out.append(end_turn)


func _append_power_actions(out: Array[Dictionary], player: int) -> void:
	match current_role:
		1:  # Assassin: name a character that will not act this round.
			for role: int in range(2, ROLE_COUNT + 1):
				if role == killed_role:
					continue
				out.append(_power_action("assassinate", {"role": role}, "game.citadels.action.assassinate"))
		2:  # Thief: rob a character (the gold moves at once in this simplification).
			for role: int in range(3, ROLE_COUNT + 1):
				out.append(_power_action("steal", {"role": role}, "game.citadels.action.steal"))
		3:  # Magician: swap hands with a player or throw the hand away and redraw.
			for target: int in range(player_count()):
				if target != player:
					out.append(_power_action("magician_swap", {"target": target}, "game.citadels.action.swap"))
			if not hand_of(player).is_empty():
				var discard_action := make_action("magician_discard", {}, "game.citadels.action.discard")
				discard_action["_direct"] = true
				out.append(discard_action)
		8:  # Warlord: raze one district for cost minus one gold.
			for target: int in range(player_count()):
				if target == player or _is_protected_by_bishop(target):
					continue
				var city: Array[String] = cities[target]
				for slot: int in range(city.size()):
					var price := maxi(0, district_cost(city[slot]) - 1)
					if price > gold[player]:
						continue
					var raze := _power_action("destroy", {"target": target, "slot": slot}, "game.citadels.action.destroy") 
					raze["_price"] = price
					out.append(raze)


func _power_action(type: String, params: Dictionary, label_key: String) -> Dictionary:
	var action := make_action(type, params, label_key)
	action["_direct"] = false
	return action


# --------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var type := VariantUtil.as_string(action.get("type", ""), "")
	if not ACTION_TYPES.has(type):
		return _fail("game.citadels.error.unknown_action")
	var actor := decision_player()
	if actor < 0:
		return _fail("game.citadels.error.illegal_action")
	var wanted := VariantUtil.as_string(action.get("key", ""), "")
	var params: Dictionary = {}
	for candidate: Dictionary in legal_actions(actor):
		if VariantUtil.as_string(candidate.get("key", ""), "") == wanted:
			params = candidate
			break
	if params.is_empty():
		return _fail("game.citadels.error.illegal_action")
	match type:
		"take_role":
			return _take_role(actor, VariantUtil.as_int(params.get("role", 0), 0))
		"income":
			return _take_income(actor)
		"draw_cards":
			return _take_cards(actor)
		"build":
			return _build(actor, VariantUtil.as_string(params.get("card", ""), ""), VariantUtil.as_int(params.get("slot", -1), -1))
		"end_turn":
			_call_next_role(current_role + 1)
			return _ok(action)
		"assassinate":
			return _assassinate(actor, VariantUtil.as_int(params.get("role", 0), 0))
		"steal":
			return _steal(actor, VariantUtil.as_int(params.get("role", 0), 0))
		"magician_swap":
			return _magician_swap(actor, VariantUtil.as_int(params.get("target", -1), -1))
		"magician_discard":
			return _magician_discard(actor)
		"destroy":
			return _destroy(actor, VariantUtil.as_int(params.get("target", -1), -1), VariantUtil.as_int(params.get("slot", -1), -1))
	return _fail("game.citadels.error.unknown_action")


func _take_income(player: int) -> Dictionary:
	gold[player] += 2
	log_event("game.citadels.log_income", {"player": player_name(player)}, player)
	step = "action"
	return _ok()


func _take_cards(player: int) -> Dictionary:
	if _available_cards() <= 0:
		return _fail("game.citadels.error.illegal_action")
	var drawn := _draw_into(player, 2)
	log_event("game.citadels.log_cards", {"player": player_name(player), "count": drawn}, player)
	step = "action"
	return _ok()


func _build(player: int, card: String, slot: int) -> Dictionary:
	var hand: Array[String] = hands[player]
	if slot < 0 or slot >= hand.size() or hand[slot] != card:
		return _fail("game.citadels.error.bad_target")
	if builds_done >= build_limit or city_of(player).size() >= DISTRICT_GOAL:
		return _fail("game.citadels.error.illegal_action")
	var cost := district_cost(card)
	if gold[player] < cost:
		return _fail("game.citadels.error.cannot_afford")
	gold[player] -= cost
	hand.remove_at(slot)
	var city: Array[String] = cities[player]
	city.append(card)
	builds_done += 1
	log_event("game.citadels.log_build", {
		"player": player_name(player), "district": district_name(card), "cost": cost,
	}, player)
	if city.size() >= DISTRICT_GOAL:
		if first_to_eight < 0:
			first_to_eight = player
		log_event("game.citadels.log_complete", {"player": player_name(player)}, player)
	return _ok()


func _assassinate(player: int, role: int) -> Dictionary:
	if current_role != 1 or power_used or role < 2 or role > ROLE_COUNT or role == killed_role:
		return _fail("game.citadels.error.bad_target")
	killed_role = role
	power_used = true
	log_event("game.citadels.log_assassinate", {
		"player": player_name(player), "role": role_name(role),
	}, player)
	return _ok()


func _steal(player: int, role: int) -> Dictionary:
	if current_role != 2 or power_used or role < 3 or role > ROLE_COUNT:
		return _fail("game.citadels.error.bad_target")
	power_used = true
	var victim := role_owner[role]
	var taken := 0
	if victim >= 0:
		taken = gold[victim]
		gold[victim] = 0
		gold[player] += taken
	log_event("game.citadels.log_steal", {
		"player": player_name(player), "role": role_name(role), "gold": taken,
	}, player)
	return _ok()


func _magician_swap(player: int, target: int) -> Dictionary:
	if current_role != 3 or power_used or target < 0 or target >= player_count() or target == player:
		return _fail("game.citadels.error.bad_target")
	power_used = true
	var mine: Array[String] = hands[player]
	var theirs: Array[String] = hands[target]
	hands[player] = theirs
	hands[target] = mine
	log_event("game.citadels.log_swap", {
		"player": player_name(player), "target": player_name(target),
	}, player)
	return _ok()


func _magician_discard(player: int) -> Dictionary:
	if current_role != 3 or power_used:
		return _fail("game.citadels.error.illegal_action")
	var hand: Array[String] = hands[player]
	var count := hand.size()
	if count <= 0:
		return _fail("game.citadels.error.illegal_action")
	power_used = true
	discard.append_array(hand)
	hand.clear()
	var drawn := _draw_into(player, count)
	log_event("game.citadels.log_discard", {
		"player": player_name(player), "count": drawn,
	}, player)
	return _ok()


func _destroy(player: int, target: int, slot: int) -> Dictionary:
	if current_role != 8 or power_used:
		return _fail("game.citadels.error.illegal_action")
	if target < 0 or target >= player_count() or target == player or _is_protected_by_bishop(target):
		return _fail("game.citadels.error.bad_target")
	var city: Array[String] = cities[target]
	if slot < 0 or slot >= city.size():
		return _fail("game.citadels.error.bad_target")
	var cost := maxi(0, district_cost(city[slot]) - 1)
	if gold[player] < cost:
		return _fail("game.citadels.error.cannot_afford")
	var card := city[slot]
	gold[player] -= cost
	city.remove_at(slot)
	discard.append(card)
	power_used = true
	log_event("game.citadels.log_destroy", {
		"player": player_name(player), "district": district_name(card),
		"target": player_name(target), "cost": cost,
	}, player)
	return _ok()


# ----------------------------------------------------------------- round end

func _end_round() -> void:
	step = "finished"
	var complete := false
	for player: int in range(player_count()):
		if city_of(player).size() >= DISTRICT_GOAL:
			complete = true
	if complete:
		_score_and_finish("game.citadels.reason_city_complete")
		return
	if round_index >= round_limit:
		_score_and_finish("game.citadels.reason_round_limit")
		return
	current_player = -1
	power_used = false
	_start_round()


func _score_and_finish(reason_key: String) -> void:
	var scores: Array = []
	var best_rank := Vector3i(-1000, -1, 1)
	var winner := -1
	for player: int in range(player_count()):
		var total := VariantUtil.as_int(score_of(player).get("total", 0), 0)
		scores.append({"player": player, "name": player_name(player), "score": total})
		# Rank: score, then whoever completed a city of eight first, then seat.
		var rank := Vector3i(total, 1 if first_to_eight == player else 0, -player)
		if winner < 0 or _rank_after(rank, best_rank):
			best_rank = rank
			winner = player
	step = "finished"
	finish(winner, reason_key, scores)


static func _rank_after(candidate: Vector3i, champion: Vector3i) -> bool:
	if candidate.x != champion.x:
		return candidate.x > champion.x
	if candidate.y != champion.y:
		return candidate.y > champion.y
	return candidate.z > champion.z


# ------------------------------------------------------------------ snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["step"] = step
	state["gold"] = gold.duplicate()
	state["cities"] = cities.duplicate(true)
	var counts: Array = []
	for player: int in range(player_count()):
		counts.append(hand_of(player).size())
	state["hand_counts"] = counts
	state["role_pool"] = role_pool.duplicate()
	state["current_role"] = current_role
	state["killed_role"] = killed_role
	state["first_player"] = first_player
	state["roles_per_player"] = roles_per_player
	state["draft_index"] = draft_index
	state["draft_order_size"] = draft_order.size()
	state["build_limit"] = build_limit
	state["builds_done"] = builds_done
	state["power_used"] = power_used
	state["current_player"] = current_player
	state["first_to_eight"] = first_to_eight
	state["round_limit"] = round_limit
	state["_scores"] = _score_preview()
	return state


func _score_preview() -> Dictionary:
	var out: Dictionary = {}
	for player: int in range(player_count()):
		out[str(player)] = score_of(player)
	return out


func private_state(player: int) -> Dictionary:
	if player < 0:
		# Table secrets: the draw pile. Never sent to a seat, but a snapshot of
		# the table needs it to resume the match (the harness merges it too).
		return {"deck": deck.duplicate(), "discard": discard.duplicate()}
	if player >= player_count():
		return {}
	var roles: Array[int] = []
	for role: int in range(1, ROLE_COUNT + 1):
		if role_owner[role] == player:
			roles.append(role)
	return {"seat": player, "hand": hand_of(player).duplicate(), "roles": roles}


## Installs ONE seat's private slice on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own hand and its
## own character assignments (the other characters are hidden while the round
## runs), and the drawing pile only arrives as a seat -1 table secret.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0:
		# Table secrets: the draw pile and its discard.
		if slice.has("deck"):
			GameEngine.copy_string_array(slice.get("deck", []), deck)
		if slice.has("discard"):
			GameEngine.copy_string_array(slice.get("discard", []), discard)
		return
	if seat >= player_count():
		return
	while hands.size() < player_count():
		var filler: Array[String] = []
		hands.append(filler)
	var hand: Array[String] = []
	GameEngine.copy_string_array(slice.get("hand", []), hand)
	hands[seat] = hand
	var roles: Array = slice.get("roles", []) if slice.get("roles", []) is Array else []
	for role: Variant in roles:
		var role_id := int(role)
		if role_id >= 1 and role_id <= ROLE_COUNT:
			role_owner[role_id] = seat


func _restore_extra(state: Dictionary) -> void:
	step = VariantUtil.as_string(state.get("step", "draft"), "draft")
	gold.clear()
	GameEngine.copy_int_array(state.get("gold", []), gold)
	while gold.size() < player_count():
		gold.append(0)
	var city_snapshot: Array = state.get("cities", []) if state.get("cities", []) is Array else []
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	hands.clear()
	cities.clear()
	for player: int in range(player_count()):
		var city: Array[String] = []
		if player < city_snapshot.size():
			GameEngine.copy_string_array(city_snapshot[player], city)
		cities.append(city)
	role_owner.clear()
	for _role: int in range(ROLE_COUNT + 1):
		role_owner.append(-1)
	if not privates.is_empty():
		# Save-file shape: every seat's private slice keyed by seat index.
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
	elif state.has("hand"):
		# Client shape (harness contract): the acting player's own hand and
		# characters merged at the top level, attributed to the decision player.
		_adopt_private_extra(decision_player(), state)
	else:
		# Public-only spectator: hands stay hidden.
		for _player: int in range(player_count()):
			var empty: Array[String] = []
			hands.append(empty)
	GameEngine.copy_int_array(state.get("role_pool", []), role_pool)
	draft_index = VariantUtil.as_int(state.get("draft_index", 0), 0)
	first_player = VariantUtil.as_int(state.get("first_player", 0), 0)
	roles_per_player = maxi(1, VariantUtil.as_int(state.get("roles_per_player", 1), 1))
	# The draft order is deterministic, so it is rebuilt from the public fields
	# (crown seat and roles per player) instead of being shipped in the snapshot.
	GameEngine.copy_int_array(_rebuild_order(state), draft_order)
	current_role = VariantUtil.as_int(state.get("current_role", 0), 0)
	current_player = VariantUtil.as_int(state.get("current_player", -1), -1)
	killed_role = VariantUtil.as_int(state.get("killed_role", 0), 0)
	power_used = bool(state.get("power_used", false))
	builds_done = VariantUtil.as_int(state.get("builds_done", 0), 0)
	build_limit = maxi(1, VariantUtil.as_int(state.get("build_limit", 1), 1))
	first_to_eight = VariantUtil.as_int(state.get("first_to_eight", -1), -1)
	round_limit = maxi(1, VariantUtil.as_int(state.get("round_limit", DEFAULT_ROUND_LIMIT), DEFAULT_ROUND_LIMIT))
	# Table secrets: whole-match form at the top level, save files under "-1".
	var table: Dictionary = privates.get("-1", {}) if privates.get("-1", {}) is Dictionary else {}
	GameEngine.copy_string_array(table.get("deck", state.get("_deck", [])), deck)
	GameEngine.copy_string_array(table.get("discard", state.get("_discard", [])), discard)


## Draft order for a round: seat order starting at the crown, once per role.
func _rebuild_order(state: Dictionary) -> Array:
	var order: Array = []
	var count := player_count()
	if count <= 0:
		return order
	for _pass: int in range(roles_per_player):
		for offset: int in range(count):
			order.append((first_player + offset) % count)
	return order
