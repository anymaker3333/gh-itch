class_name CodenamesEngine
extends GameEngine
## Codenames rules engine (5×5 word grid, two teams, spymaster clues).
##
## Hotseat model (documented simplification): players are split into two teams by
## seat parity (even seats = red, odd seats = blue) and the lowest-index member of
## a team is that team's spymaster. With two players each seat is both spymaster
## and operative, which is playable but degenerate; four or more seats are the
## intended experience. Both spymasters see the same key card, operatives never do.
##
## Clues are drawn from a fixed cue vocabulary and are associated with the grid
## words through a static table, so a clue mechanically carries information
## instead of relying on free text: bots (and humans) can rank guesses by
## association, which keeps the game deterministic and testable.
##
## Randomness only comes from the inherited [member rng]: the same seed draws the
## same grid and the same key card.

const GRID_SIZE: int = 5
const CELLS: int = GRID_SIZE * GRID_SIZE
const MAX_CLUE_NUMBER: int = 3
const MAX_TURNS: int = 40

const RED: int = 0
const BLUE: int = 1
const NEUTRAL: String = "neutral"
const ASSASSIN: String = "assassin"
const CARD_RED: String = "red"
const CARD_BLUE: String = "blue"

## Word pool the 25 grid words are drawn from (distinct, drawn with `rng`).
const WORD_POOL: Array[String] = [
	"fire", "ice", "moon", "star", "river", "mountain", "forest", "desert",
	"ocean", "storm", "crown", "sword", "shield", "key", "lock", "clock",
	"mirror", "shadow", "light", "night", "song", "dance", "dream", "letter",
	"book", "garden", "bridge", "tower", "market", "train",
]

## Static association table: grid word -> cue words that hint at it. The cue
## vocabulary is derived from this table (sorted, unique) so it cannot drift.
const ASSOCIATIONS: Dictionary = {
	"fire": ["hot", "bright", "wind"],
	"ice": ["cold", "water", "stone"],
	"moon": ["sky", "dark", "time"],
	"star": ["sky", "bright", "dark"],
	"river": ["water", "travel", "deep"],
	"mountain": ["stone", "high", "cold"],
	"forest": ["tree", "green", "dark"],
	"desert": ["hot", "water", "travel"],
	"ocean": ["water", "deep", "travel"],
	"storm": ["wind", "dark", "water"],
	"crown": ["royal", "gold", "high"],
	"sword": ["sharp", "iron", "guard"],
	"shield": ["guard", "iron", "closed"],
	"key": ["open", "iron", "gold"],
	"lock": ["closed", "iron", "guard"],
	"clock": ["time", "bright", "gold"],
	"mirror": ["bright", "water", "cold"],
	"shadow": ["dark", "sleep", "wind"],
	"light": ["bright", "open", "sky"],
	"night": ["dark", "sleep", "sky"],
	"song": ["music", "open", "bright"],
	"dance": ["music", "bright", "travel"],
	"dream": ["sleep", "dark", "time"],
	"letter": ["paper", "open", "time"],
	"book": ["paper", "time", "closed"],
	"garden": ["green", "tree", "bright"],
	"bridge": ["travel", "water", "high"],
	"tower": ["high", "stone", "sky"],
	"market": ["gold", "travel", "open"],
	"train": ["travel", "iron", "time"],
}

var grid: Array[String] = []
var key_card: Array[String] = []
var revealed: Array[int] = []
var active_team: int = RED
var remaining: Array[int] = [9, 8]
## Agents each team has to reveal (the starting team has nine).
var to_reveal: Array[int] = [9, 8]
var clue_word: String = ""
var clue_number: int = 0
var guesses_left: int = 0
var guesses_made: int = 0
var turn_phase: String = "clue"
var _cue_vocab: Array[String] = []


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "codenames"


func setup(options: Dictionary) -> void:
	super.setup(options)
	var starting := VariantUtil.as_string(options.get("starting_team", "red"), "red")
	active_team = BLUE if starting == "blue" else RED
	to_reveal = [9, 8]
	if active_team == BLUE:
		to_reveal[0] = 8
		to_reveal[1] = 9
	remaining = to_reveal.duplicate()
	clue_word = ""
	clue_number = 0
	guesses_left = 0
	guesses_made = 0
	turn_phase = "clue"
	_cue_vocab = _build_cue_vocab()
	_deal_words()
	_deal_key_card()
	log_event("game.codenames.log_start", {
		"red_spy": player_name(spymaster_of(RED)),
		"blue_spy": player_name(spymaster_of(BLUE)),
	})


func options_schema() -> Array[Dictionary]:
	return [
		{"key": "starting_team", "label_key": "game.codenames.option.starting_team", "type": "enum",
			"default": "red", "values": ["red", "blue"],
			"labels": {
				"red": "game.codenames.option.team_red",
				"blue": "game.codenames.option.team_blue",
			},
			"hint_key": "game.codenames.option.starting_team_hint"},
	]


func phases() -> PackedStringArray:
	return PackedStringArray(["clue", "guess", "finished"])


func phase() -> String:
	return turn_phase


# ------------------------------------------------------------------ team model

func team_of(player: int) -> int:
	return player % 2


func team_members(team: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(player_count()):
		if team_of(i) == team:
			out.append(i)
	return out


## The team's first seat is its spymaster; with one member that player does both.
func spymaster_of(team: int) -> int:
	var members := team_members(team)
	return members[0] if not members.is_empty() else -1


func is_spymaster(player: int) -> bool:
	return player >= 0 and player < player_count() and spymaster_of(team_of(player)) == player


## Operatives of a team: every member except the spymaster (a one-member team
## both gives the clue and guesses).
func _operatives(team: int) -> Array[int]:
	var out: Array[int] = []
	var members := team_members(team)
	for member: int in members:
		if member != spymaster_of(team) or members.size() == 1:
			out.append(member)
	return out


func _alive(player: int) -> bool:
	if player < 0 or player >= player_count():
		return false
	return not bool(players[player].get("resigned", false))


func _living_count(team: int) -> int:
	var count := 0
	for member: int in team_members(team):
		if _alive(member):
			count += 1
	return count


# -------------------------------------------------------------------- dealing

func _build_cue_vocab() -> Array[String]:
	var seen: Dictionary = {}
	for word: Variant in ASSOCIATIONS:
		for cue: Variant in VariantUtil.as_array(ASSOCIATIONS[word]):
			seen[VariantUtil.as_string(cue, "")] = true
	var out: Array[String] = []
	for cue: Variant in seen:
		out.append(VariantUtil.as_string(cue, ""))
	out.sort()
	return out


func _deal_words() -> void:
	var pool: Array = WORD_POOL.duplicate()
	var picked: Array[String] = []
	for i: int in range(CELLS):
		var index := rng.randi_range(0, pool.size() - 1)
		picked.append(VariantUtil.as_string(pool[index], ""))
		pool.remove_at(index)
	grid = picked


func _deal_key_card() -> void:
	var cards: Array[String] = []
	var red_cards := to_reveal[RED]
	var blue_cards := to_reveal[BLUE]
	if red_cards + blue_cards != 17:
		red_cards = 9
		blue_cards = 8
	for i: int in range(red_cards):
		cards.append(CARD_RED)
	for i: int in range(blue_cards):
		cards.append(CARD_BLUE)
	for i: int in range(7):
		cards.append(NEUTRAL)
	cards.append(ASSASSIN)
	# Fisher-Yates with the engine rng keeps the draw reproducible.
	for i: int in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	key_card = cards
	revealed = []
	revealed.resize(CELLS)
	revealed.fill(0)


# ------------------------------------------------------------------- decision

func decision_player() -> int:
	if finished:
		return -1
	if turn_phase == "clue":
		var spy := spymaster_of(active_team)
		if _alive(spy):
			return spy
		for member: int in team_members(active_team):
			if _alive(member):
				return member
		return -1
	var live: Array[int] = []
	for member: int in _operatives(active_team):
		if _alive(member):
			live.append(member)
	if live.is_empty():
		return -1
	return live[guesses_made % live.size()]


## Resignation guard: when an entire team has left, the other team wins.
func _guard_abandonment() -> void:
	if finished:
		return
	if _living_count(active_team) > 0:
		return
	var other := BLUE if active_team == RED else RED
	if _living_count(other) <= 0:
		return
	turn_phase = "finished"
	_finish_team(other, "game.codenames.reason_abandoned")


# --------------------------------------------------------------- legal actions

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_guard_abandonment()
	if finished or player < 0 or player != decision_player():
		return out
	if turn_phase == "clue":
		for cue: String in _cue_vocab:
			for number: int in range(1, MAX_CLUE_NUMBER + 1):
				var action := make_action("clue", {"word": cue, "number": number})
				action["_direct"] = false
				action["_team"] = active_team
				out.append(action)
	elif turn_phase == "guess":
		for cell: int in range(CELLS):
			if revealed[cell] == 1:
				continue
			var action := make_action("guess", {"card": cell})
			action["_direct"] = false
			action["_team"] = active_team
			out.append(action)
		var stop := make_action("stop", {}, "game.codenames.stop")
		stop["_direct"] = true
		stop["_team"] = active_team
		out.append(stop)
	return out


# ---------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	_guard_abandonment()
	if finished:
		return _fail("game.common.match_over")
	var player := decision_player()
	if player < 0:
		return _fail("game.common.match_over")
	var wanted := VariantUtil.as_string(action.get("key", ""), "")
	var selected: Dictionary = {}
	for candidate: Dictionary in legal_actions(player):
		if VariantUtil.as_string(candidate.get("key", ""), "") == wanted:
			selected = candidate
			break
	if selected.is_empty():
		return _fail("game.codenames.error.illegal_action")
	match VariantUtil.as_string(selected.get("type", ""), ""):
		"clue":
			_commit_clue(player, VariantUtil.as_string(selected.get("word", ""), ""), VariantUtil.as_int(selected.get("number", 1), 1))
		"guess":
			if key_card.size() != CELLS:
				# A restored replica without the spymaster's key card cannot
				# resolve a guess; refusing it honestly beats faking a reveal or
				# crashing on an out-of-bounds read.
				return _fail("game.common.illegal_action")
			_commit_guess(player, VariantUtil.as_int(selected.get("card", -1), -1))
		"stop":
			_commit_stop(player)
		_:
			return _fail("game.codenames.error.illegal_action")
	return _ok(action)


func _commit_clue(player: int, word: String, number: int) -> void:
	clue_word = word
	clue_number = clampi(number, 1, MAX_CLUE_NUMBER)
	guesses_left = clue_number + 1
	guesses_made = 0
	turn_phase = "guess"
	log_event("game.codenames.log_clue", {
		"player": player_name(player),
		"word": word,
		"number": clue_number,
		"team": _team_label(active_team),
	}, player)


func _commit_stop(player: int) -> void:
	log_event("game.codenames.log_stop", {
		"player": player_name(player),
		"team": _team_label(active_team),
	}, player)
	_end_turn()


func _commit_guess(player: int, cell: int) -> void:
	if cell < 0 or cell >= CELLS or revealed[cell] == 1:
		return
	revealed[cell] = 1
	guesses_made += 1
	var card := key_card[cell]
	var label := grid[cell]
	if card == CARD_RED or card == CARD_BLUE:
		var owner := RED if card == CARD_RED else BLUE
		remaining[owner] = maxi(0, remaining[owner] - 1)
		log_event("game.codenames.log_agent", {
			"player": player_name(player),
			"card": label,
			"team": _team_label(owner),
		}, player)
		if remaining[owner] <= 0:
			_finish_team(owner, "game.codenames.reason_all_agents")
			return
		if owner == active_team:
			guesses_left -= 1
			if guesses_left <= 0:
				_end_turn()
			return
		_end_turn()
		return
	if card == ASSASSIN:
		log_event("game.codenames.log_assassin", {"player": player_name(player), "card": label}, player)
		var other := BLUE if active_team == RED else RED
		_finish_team(other, "game.codenames.reason_assassin")
		return
	log_event("game.codenames.log_bystander", {"player": player_name(player), "card": label}, player)
	_end_turn()


func _end_turn() -> void:
	turn += 1
	clue_word = ""
	clue_number = 0
	guesses_left = 0
	guesses_made = 0
	active_team = BLUE if active_team == RED else RED
	turn_phase = "clue"
	if turn >= MAX_TURNS:
		_finish_on_turn_limit()


func _team_label(team: int) -> String:
	return Loc.t("game.codenames.team_red" if team == RED else "game.codenames.team_blue")


func _finish_team(team: int, reason_key: String) -> void:
	turn_phase = "finished"
	finish(spymaster_of(team), reason_key, _scores())
	result["_winner_team"] = team
	result["_team_scores"] = _team_totals()


func _finish_on_turn_limit() -> void:
	var totals := _team_totals()
	if int(totals["red"]) == int(totals["blue"]):
		turn_phase = "finished"
		finish(-1, "game.codenames.reason_turn_limit", _scores())
		return
	_finish_team(RED if int(totals["red"]) > int(totals["blue"]) else BLUE, "game.codenames.reason_turn_limit")


func _team_totals() -> Dictionary:
	return {"red": to_reveal[RED] - remaining[RED], "blue": to_reveal[BLUE] - remaining[BLUE]}


func _scores() -> Array:
	var totals := _team_totals()
	var out: Array = []
	for i: int in range(player_count()):
		out.append({
			"player": i,
			"name": player_name(i),
			"score": totals["red"] if team_of(i) == RED else totals["blue"],
		})
	return out


# ------------------------------------------------------------------- snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["grid"] = grid.duplicate()
	state["revealed"] = revealed.duplicate()
	state["active_team"] = active_team
	state["remaining"] = remaining.duplicate()
	state["to_reveal"] = to_reveal.duplicate()
	state["clue"] = {"word": clue_word, "number": clue_number}
	state["guesses_left"] = guesses_left
	state["guesses_made"] = guesses_made
	state["teams"] = [team_members(RED), team_members(BLUE)]
	state["spymasters"] = [spymaster_of(RED), spymaster_of(BLUE)]
	state["cue_vocab"] = _cue_vocab.duplicate()
	return state


## Only the spymaster of each team may see the key card; operatives get their role
## and team so the view knows what to render. Never leaks into public_state().
func private_state(player: int) -> Dictionary:
	var out: Dictionary = {
		"team": team_of(player),
		"role": "spymaster" if is_spymaster(player) else "operative",
	}
	if is_spymaster(player):
		out["key_card"] = key_card.duplicate()
	return out


func _restore_extra(state: Dictionary) -> void:
	copy_string_array(state.get("grid", []), grid)
	copy_int_array(state.get("revealed", []), revealed)
	key_card.clear()
	if state.has("_key_card") or state.has("key_card"):
		# Whole-match snapshots carry the card as "_key_card"; the harness
		# contract merges the owner's private slice, whose key is "key_card".
		copy_string_array(state.get("_key_card", state.get("key_card", [])), key_card)
	elif state.has("private_states") and (state.get("private_states") is Dictionary):
		# Save-file shape: the spymaster slice carries the key card.
		var bag: Dictionary = state.get("private_states", {})
		for seat_key: Variant in bag:
			var slice: Variant = bag.get(seat_key, {})
			if slice is Dictionary and VariantUtil.as_dict(slice).has("key_card"):
				copy_string_array(VariantUtil.as_dict(slice).get("key_card", []), key_card)
				break
	# A snap-snapshot without a usable key card keeps the table playable for
	# operatives only; guesses that would need the card are rejected below
	# instead of crashing on an out-of-bounds read.
	copy_int_array(state.get("remaining", []), remaining)
	if remaining.size() != 2:
		remaining = [9, 8]
	copy_int_array(state.get("to_reveal", []), to_reveal)
	if to_reveal.size() != 2:
		to_reveal = [9, 8]
	active_team = VariantUtil.as_int(state.get("active_team", RED), RED)
	var clue: Dictionary = VariantUtil.as_dict(state.get("clue", {}))
	clue_word = VariantUtil.as_string(clue.get("word", ""), "")
	clue_number = VariantUtil.as_int(clue.get("number", 0), 0)
	guesses_left = VariantUtil.as_int(state.get("guesses_left", 0), 0)
	guesses_made = VariantUtil.as_int(state.get("guesses_made", 0), 0)
	turn_phase = "finished" if finished else ("clue" if clue_word.is_empty() else "guess")
	_cue_vocab = _build_cue_vocab()


## Installs ONE seat's slice on a client replica. Only a spymaster slice carries
## the key card; an operative replica must not receive one, and the adopt path
## never adds it.
func _adopt_private_extra(_seat: int, slice: Dictionary) -> void:
	if slice.has("key_card"):
		copy_string_array(slice.get("key_card", []), key_card)


# --------------------------------------------------------------- bot utilities

## Cue words that hint at `word` (empty when the word is unknown to the table).
func cues_for(word: String) -> Array:
	return VariantUtil.array_copy(ASSOCIATIONS.get(word, []))


func unrevealed_cells() -> Array[int]:
	var out: Array[int] = []
	for cell: int in range(CELLS):
		if revealed[cell] == 0:
			out.append(cell)
	return out


func card_owner_label(cell: int) -> String:
	if cell < 0 or cell >= key_card.size():
		return ""
	return key_card[cell]


## Agents a team has still to reveal at the restored state (used by the view).
static func team_remaining(state: Dictionary, team: int) -> int:
	var remaining: Array = state.get("remaining", [9, 8])
	if team < 0 or team >= remaining.size():
		return 0
	return int(remaining[team])
