class_name SpyfallEngine
extends GameEngine
## Spyfall rules engine: one spy hides among the agents, who all know the
## location, and the table asks questions until somebody dares to accuse.
##
## Hotseat model: every seat plays at the same table (pass the device), so
## [method requires_handover] is true in the view. One action set is shared by
## every role — the engine never asks a player "are you the spy?" through the
## action list, which keeps snapshots role-independent (see the rules suite).
##
## The spoken part of Spyfall is modelled with a fixed list of question cards and
## a fixed list of vague answer cards: an answering player picks a card, the
## choice becomes public. Locations declare which answers are *on topic* for
## them, so a spy who does not know the location answers off topic and can be
## caught by deduction. Roles are flavour only.
##
## Endings (all bounded): an agent accuses the spy (agents win), the spy names
## the location (right: spy wins, wrong: agents win), every agent spends their
## accusation without a hit, or the question rounds run out — in the last two
## cases the spy survives and wins.

const PHASE_ASK: String = "ask"
const PHASE_ANSWER: String = "answer"
const PHASE_FINISHED: String = "finished"

const MAX_ROUNDS: int = 5

## Locations offered in the catalogue. `LOCATION_TOPICS` lists the indices of
## the answer cards that make sense there; `LOCATION_ROLES` is flavour text.
const LOCATIONS: Array[String] = [
	"casino", "hospital", "beach", "school", "museum", "restaurant", "airport", "circus",
]

const LOCATION_TOPICS: Dictionary = {
	"casino": [1, 2, 3, 5, 9, 10],
	"hospital": [1, 2, 3, 5, 6, 10],
	"beach": [0, 2, 4, 7, 9, 11],
	"school": [1, 2, 3, 6, 8, 10],
	"museum": [1, 3, 5, 9, 10, 11],
	"restaurant": [0, 2, 4, 5, 9, 10],
	"airport": [1, 3, 5, 6, 8, 10],
	"circus": [0, 2, 3, 4, 6, 9],
}

## Roles are shared by every location and are pure flavour (documented).
const ROLES: Array[String] = ["regular", "newcomer", "staff", "visitor", "owner", "witness"]

const QUESTIONS: Array[String] = [
	"game.spyfall.question.work", "game.spyfall.question.arrived",
	"game.spyfall.question.best_time", "game.spyfall.question.brought",
	"game.spyfall.question.entrance", "game.spyfall.question.worst",
	"game.spyfall.question.charge", "game.spyfall.question.cost",
	"game.spyfall.question.happening",
]

const ANSWERS: Array[String] = [
	"game.spyfall.answer.shift", "game.spyfall.answer.permission",
	"game.spyfall.answer.everybody", "game.spyfall.answer.rules",
	"game.spyfall.answer.loud", "game.spyfall.answer.back",
	"game.spyfall.answer.watch", "game.spyfall.answer.sea",
	"game.spyfall.answer.bell", "game.spyfall.answer.weekend",
	"game.spyfall.answer.staff", "game.spyfall.answer.silent",
]

var spy: int = -1
var location: String = ""
var candidates: Array[String] = []
var cleared: Array[int] = []
var accused: Array[int] = []
var history: Array = []
var turn_phase: String = PHASE_ASK
var turn_pos: int = 0
var turn_order: Array[int] = []
var ask_count: int = 0
var asks_limit: int = 1
var rounds_limit: int = 3
var pending_question: int = -1
var pending_target: int = -1
var pending_asker: int = -1


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "spyfall"


func setup(options: Dictionary) -> void:
	super.setup(options)
	rounds_limit = clampi(VariantUtil.as_int(options.get("rounds", 3), 3), 1, MAX_ROUNDS)
	spy = rng.randi_range(0, maxi(0, player_count() - 1))
	location = LOCATIONS[rng.randi_range(0, LOCATIONS.size() - 1)]
	candidates = _draw_candidates()
	cleared = []
	accused = []
	history = []
	turn_phase = PHASE_ASK
	turn_pos = 0
	turn_order = []
	for i: int in range(player_count()):
		turn_order.append(i)
	ask_count = 0
	asks_limit = maxi(1, rounds_limit * player_count())
	pending_question = -1
	pending_target = -1
	pending_asker = -1
	log_event("game.spyfall.log_start", {"count": player_count(), "rounds": rounds_limit})


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "rounds", "label_key": "game.spyfall.option.rounds", "type": "int", "default": 3,
			"min": 1, "max": MAX_ROUNDS, "hint_key": "game.spyfall.option.rounds_hint"},
	]


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_ASK, PHASE_ANSWER, PHASE_FINISHED])


func phase() -> String:
	return turn_phase


func round_limit() -> int:
	return asks_limit


# ------------------------------------------------------------- turn machinery

func decision_player() -> int:
	if finished:
		return -1
	if turn_phase == PHASE_ANSWER:
		return pending_target if _alive(pending_target) else _next_actor()
	return _next_actor()


func _next_actor() -> int:
	if turn_order.is_empty():
		return -1
	for step: int in range(turn_order.size()):
		var index := (turn_pos + step) % turn_order.size()
		var candidate: int = int(turn_order[index])
		if _alive(candidate):
			return candidate
	return -1


func _alive(player: int) -> bool:
	if player < 0 or player >= player_count():
		return false
	return not bool(players[player].get("resigned", false))


func _living_players() -> Array[int]:
	var out: Array[int] = []
	for i: int in range(player_count()):
		if _alive(i):
			out.append(i)
	return out


func _advance() -> void:
	if turn_order.is_empty():
		return
	for step: int in range(turn_order.size()):
		turn_pos = (turn_pos + 1) % turn_order.size()
		if _alive(int(turn_order[turn_pos])):
			return


func _remove_from_order(player: int) -> void:
	var index := turn_order.find(player)
	if index < 0:
		return
	turn_order.remove_at(index)
	if turn_pos >= turn_order.size():
		turn_pos = 0


# -------------------------------------------------------------------- topics

func topics_of(location_id: String) -> Array:
	return VariantUtil.array_copy(LOCATION_TOPICS.get(location_id, []))


func is_on_topic(location_id: String, answer: int) -> bool:
	return topics_of(location_id).has(answer)


func _draw_candidates() -> Array[String]:
	var pool: Array[String] = []
	for id: String in LOCATIONS:
		if id != location:
			pool.append(id)
	var out: Array[String] = [location]
	# Two decoys keep the spy's guess meaningful without making it a lottery.
	for i: int in range(2):
		if pool.is_empty():
			break
		var index := rng.randi_range(0, pool.size() - 1)
		out.append(VariantUtil.as_string(pool[index], ""))
		pool.remove_at(index)
	out.sort()
	return out


# --------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player < 0 or player != decision_player():
		return out
	if turn_phase == PHASE_ASK:
		for question: int in range(QUESTIONS.size()):
			for target: int in _living_players():
				if target == player:
					continue
				var ask := make_action("ask", {"question": question, "target": target})
				ask["_direct"] = false
				out.append(ask)
		for target: int in _living_players():
			if target == player or cleared.has(target) or accused.has(player):
				continue
			var accuse := make_action("accuse", {"target": target})
			accuse["_direct"] = false
			out.append(accuse)
		for candidate: String in LOCATIONS:
			var name_action := make_action("name_location", {"location": candidate})
			name_action["_direct"] = false
			out.append(name_action)
	elif turn_phase == PHASE_ANSWER:
		for answer: int in range(ANSWERS.size()):
			var reply := make_action("answer", {"answer": answer})
			reply["_direct"] = false
			out.append(reply)
	return out


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	if player < 0:
		return _fail("game.common.match_over")
	var selected: Dictionary = {}
	for candidate: Dictionary in legal_actions(player):
		if VariantUtil.as_string(candidate.get("key", ""), "") == VariantUtil.as_string(action.get("key", ""), ""):
			selected = candidate
			break
	if selected.is_empty():
		return _fail("game.spyfall.error.illegal_action")
	match VariantUtil.as_string(selected.get("type", ""), ""):
		"ask":
			_commit_ask(player, VariantUtil.as_int(selected.get("question", 0), 0), VariantUtil.as_int(selected.get("target", -1), -1))
		"answer":
			_commit_answer(player, VariantUtil.as_int(selected.get("answer", -1), -1))
		"accuse":
			_commit_accusation(player, VariantUtil.as_int(selected.get("target", -1), -1))
		"name_location":
			_commit_naming(player, VariantUtil.as_string(selected.get("location", ""), ""))
		_:
			return _fail("game.spyfall.error.illegal_action")
	return _ok(action)


func _commit_ask(asker: int, question: int, target: int) -> void:
	pending_question = question
	pending_target = target
	pending_asker = asker
	turn_phase = PHASE_ANSWER
	log_event("game.spyfall.log_ask", {
		"player": player_name(asker),
		"target": player_name(target),
		"question": Loc.t(QUESTIONS[clampi(question, 0, QUESTIONS.size() - 1)]),
	}, asker)


func _commit_answer(answerer: int, answer: int) -> void:
	var index := clampi(answer, 0, ANSWERS.size() - 1)
	history.append({
		"asker": pending_asker,
		"target": answerer,
		"question": pending_question,
		"answer": index,
	})
	log_event("game.spyfall.log_answer", {
		"player": player_name(answerer),
		"answer": Loc.t(ANSWERS[index]),
	}, answerer)
	pending_question = -1
	pending_target = -1
	pending_asker = -1
	turn_phase = PHASE_ASK
	ask_count += 1
	_advance()
	if ask_count >= asks_limit:
		_finish_spy("game.spyfall.reason_spy_survived")


func _commit_accusation(accuser: int, target: int) -> void:
	accused.append(accuser)
	log_event("game.spyfall.log_accuse", {
		"player": player_name(accuser),
		"target": player_name(target),
	}, accuser)
	if target == spy:
		_finish_agents("game.spyfall.reason_spy_caught", accuser)
		return
	cleared.append(target)
	log_event("game.spyfall.log_cleared", {"target": player_name(target)})
	if _all_agents_spent():
		_finish_spy("game.spyfall.reason_spy_survived")
		return
	_advance()


## True when every living player other than the spy has used their accusation.
func _all_agents_spent() -> bool:
	for player: int in _living_players():
		if player == spy:
			continue
		if not accused.has(player):
			return false
	return true


func _commit_naming(actor: int, named: String) -> void:
	if actor != spy:
		# The action set is role-independent (snapshots must restore identically),
		# so a non-spy may name a place too - it simply carries no weight.
		log_event("game.spyfall.log_named_ignored", {"player": player_name(actor), "location": _location_text(named)}, actor)
		_advance()
		return
	if named == location:
		log_event("game.spyfall.log_spy_correct", {"player": player_name(actor), "location": _location_text(named)}, actor)
		_finish_spy("game.spyfall.reason_spy_guessed")
		return
	log_event("game.spyfall.log_spy_wrong", {"player": player_name(actor), "location": _location_text(named)}, actor)
	_finish_agents("game.spyfall.reason_spy_misguessed", _last_asker())


func _location_text(location_id: String) -> String:
	return Loc.t("game.spyfall.location.%s" % location_id)


func _last_asker() -> int:
	for i: int in range(history.size() - 1, -1, -1):
		var asker := VariantUtil.as_int(VariantUtil.as_dict(history[i]).get("asker", -1), -1)
		if asker >= 0 and _alive(asker):
			return asker
	for player: int in _living_players():
		if player != spy:
			return player
	return -1


func _finish_agents(reason_key: String, credited: int) -> void:
	turn_phase = PHASE_FINISHED
	finish(credited if credited >= 0 else -1, reason_key, _scores(false))
	_reveal_result()


func _finish_spy(reason_key: String) -> void:
	turn_phase = PHASE_FINISHED
	finish(spy, reason_key, _scores(true))
	_reveal_result()


func _reveal_result() -> void:
	result["_spy"] = spy
	result["_location"] = location
	log_event("game.spyfall.log_reveal", {
		"spy": player_name(spy),
		"location": _location_text(location),
	})


func _scores(spy_won: bool) -> Array:
	var out: Array = []
	for i: int in range(player_count()):
		var winner := (i == spy) if spy_won else (i != spy)
		out.append({
			"player": i,
			"name": player_name(i),
			"score": 1 if winner else 0,
		})
	return out


# ------------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["history"] = history.duplicate(true)
	state["cleared"] = cleared.duplicate()
	state["accused"] = accused.duplicate()
	state["asks"] = ask_count
	state["asks_limit"] = asks_limit
	state["rounds"] = rounds_limit
	state["pending"] = {"question": pending_question, "target": pending_target}
	state["turn_order"] = turn_order.duplicate()
	state["turn_pos"] = turn_pos
	if finished:
		state["_reveal"] = {"spy": spy, "location": location}
	return state


## Agents learn the location and a flavour role; the spy only learns that they
## are the spy and get a short list of candidate places to name.
func private_state(player: int) -> Dictionary:
	if player < 0 or player >= player_count():
		return {}
	if spy >= 0 and player == spy:
		return {"is_spy": true, "candidates": candidates.duplicate()}
	if location.is_empty():
		# A replica without the shared location (never set up, spectator
		# restore) has nothing authorized to answer with — for any seat.
		return {}
	return {
		"is_spy": false,
		"location": location,
		"role": ROLES[player % ROLES.size()],
	}


func _restore_extra(state: Dictionary) -> void:
	history = VariantUtil.array_copy(state.get("history", []))
	copy_int_array(state.get("cleared", []), cleared)
	copy_int_array(state.get("accused", []), accused)
	copy_int_array(state.get("turn_order", []), turn_order)
	ask_count = VariantUtil.as_int(state.get("asks", 0), 0)
	asks_limit = maxi(1, VariantUtil.as_int(state.get("asks_limit", 1), 1))
	rounds_limit = clampi(VariantUtil.as_int(state.get("rounds", 3), 3), 1, MAX_ROUNDS)
	var pending: Dictionary = VariantUtil.as_dict(state.get("pending", {}))
	pending_question = VariantUtil.as_int(pending.get("question", -1), -1)
	pending_target = VariantUtil.as_int(pending.get("target", -1), -1)
	turn_phase = PHASE_FINISHED if finished else (PHASE_ANSWER if pending_target >= 0 else PHASE_ASK)
	turn_pos = VariantUtil.as_int(state.get("turn_pos", 0), 0)
	if turn_order.is_empty():
		for i: int in range(player_count()):
			turn_order.append(i)
	# A public-only snapshot does not carry the spy or the location: rebuilding
	# them is only possible once the match is over (the reveal is public then),
	# from the save-file bag's seat slices, or merged at the top level (the
	# harness client shape, attributed to the decision player).
	var reveal: Dictionary = VariantUtil.as_dict(state.get("_reveal", {}))
	spy = VariantUtil.as_int(reveal.get("spy", -1), -1)
	location = VariantUtil.as_string(reveal.get("location", ""), "")
	candidates = []
	copy_string_array(reveal.get("candidates", []), candidates)
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	if not privates.is_empty():
		for seat_key: Variant in privates:
			var slice: Variant = privates.get(seat_key, {})
			if slice is Dictionary:
				_adopt_private_extra(int(str(seat_key)) if str(seat_key).is_valid_int() else -2, slice)
	elif reveal.is_empty() and (state.has("is_spy") or state.has("location")):
		# Merged client shape from the harness contract.
		_adopt_private_extra(decision_player(), state)


## Installs ONE seat's slice on a client replica or from a save-file bag slot.
## A spy slice reveals that this seat is the spy plus its candidate list; a
## regular slice reveals the shared location (the seat's role is derived from
## the seat index, exactly like the engine's own private_state()).
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0 or slice.is_empty():
		return
	if bool(slice.get("is_spy", false)):
		spy = seat
		copy_string_array(slice.get("candidates", []), candidates)
	elif slice.has("location"):
		location = VariantUtil.as_string(slice.get("location", ""), "")
