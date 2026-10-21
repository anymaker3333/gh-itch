class_name CoupEngine
extends GameEngine
## Coup rules engine (2-6 players): hidden influence, claims, challenges, blocks
## and elimination.
##
## Each player starts with two face-down influence cards and two coins. On a turn
## the player takes one action: income (one coin), foreign aid (two coins), a
## claim (Tax, Steal, Assassinate, Exchange), or a coup. Claims may be challenged
## by any other player and targeted actions may be blocked by the required
## character; a failed challenge or a completed coup costs the victim one
## influence. The last player with a hidden influence card wins.
##
## Steps (phase ids): "action" (the turn player chooses), "challenge" (players in
## turn order may challenge a claim or pass), "block" (a block is being claimed),
## "lose" (a player picks the influence to reveal), "exchange" (the Ambassador
## picks which cards to return) and "finished".
##
## Hidden information: each seat's influence travels in [method private_state];
## the Court deck travels as table secrets ([code]private_state(-1)[/code]).
##
## Simplifications (documented on purpose): costs paid for an action that is
## successfully challenged are returned (as the printed rules say) while an
## assassination stopped by a block keeps its cost paid; the shown card of a
## proven claim is shuffled back and replaced from the deck; the bot never bluffs
## a block; a turn limit ends a pathological match instead of stalling.

const ROLES: Array[String] = ["duke", "assassin", "captain", "ambassador", "contessa"]
const ACTION_TYPES: Array[String] = ["income", "foreign_aid", "tax", "exchange", "coup",
	"assassinate", "steal", "challenge", "pass", "block", "lose_card", "return_card"]
const COPIES_PER_ROLE: int = 3
const START_INFLUENCE: int = 2

## Public mirror of every seat's remaining influence. Snapshot data only: a
## live engine recomputes counts from the authoritative hands, while a client
## replica (which holds just its own influence) uses these counts as the
## authority for the other seats' aliveness and rendering.
var hand_counts: Array[int] = []
## True on a replica whose hands are incomplete (client slice or spectator
## restore): other seats' aliveness then comes from [member hand_counts], never
## from the empty local placeholders.
var _hands_unknown: bool = false
const START_COINS: int = 2
const TAX_AMOUNT: int = 3
const STEAL_AMOUNT: int = 2
const ASSASSINATE_COST: int = 3
const COUP_COST: int = 7
const MANDATORY_COUP_COINS: int = 10
const EXCHANGE_DRAW: int = 2
const MAX_TURNS: int = 600

## step: "action" | "challenge" | "block" | "lose" | "exchange" | "finished".
var step: String = "action"
var current: int = 0
var coins: Array[int] = []
var hands: Array = []  # player -> Array[String] of face-down influence
var revealed: Array = []  # player -> Array[String] of face-up influence
var deck: Array[String] = []
## The action being resolved: {type, actor, target, stage, keep?}. Public: the
## declared action is something every seat can see.
var pending: Dictionary = {}
## The claim under challenge: {kind: "action"|"block", role, player, type, target}.
var claim: Dictionary = {}
var window: Array[int] = []  # seats still asked in a challenge/block window
var window_pos: int = 0
var loser: int = -1
var turn_count: int = 0


# ---------------------------------------------------------------- engine hooks

func game_id() -> String:
	return "coup"


func setup(options: Dictionary) -> void:
	super.setup(options)
	deck.clear()
	for role: String in ROLES:
		for _copy: int in range(COPIES_PER_ROLE):
			deck.append(role)
	_shuffle(deck)
	hands.clear()
	revealed.clear()
	coins.clear()
	for player: int in range(player_count()):
		var hand: Array[String] = []
		hands.append(hand)
		var shown: Array[String] = []
		revealed.append(shown)
		coins.append(START_COINS)
		_draw_into(player, START_INFLUENCE)
	step = "action"
	current = 0
	turn_count = 0
	loser = -1
	pending = {}
	claim = {}
	window.clear()
	window_pos = 0
	round_index = 1
	log_event("game.coup.log_start", {"players": player_count(), "player": player_name(0)})


func phases() -> PackedStringArray:
	return PackedStringArray(["action", "challenge", "block", "lose", "exchange", "finished"])


func phase() -> String:
	return "finished" if finished else step


func decision_player() -> int:
	if finished:
		return -1
	match step:
		"action", "exchange":
			return current
		"challenge", "block":
			return _window_player()
		"lose":
			return loser
	return -1


func options_schema() -> Array[Dictionary]:
	return []


# ------------------------------------------------------------------- helpers

func is_alive(player: int) -> bool:
	if _hands_unknown and player != _client_seat:
		# A replica cannot see other seats' influence; the public counts are
		# the authority here.
		if player >= 0 and player < hand_counts.size():
			return VariantUtil.as_int(hand_counts[player], 0) > 0
		return false
	return player >= 0 and player < hands.size() and not hands[player].is_empty()


## Remaining influence of `player` as public data understands it: the real hand
## when this engine is complete, the snapshot's public count otherwise.
func _influence_count(player: int) -> int:
	if _hands_unknown and player != _client_seat:
		if player >= 0 and player < hand_counts.size():
			return VariantUtil.as_int(hand_counts[player], 0)
		return 0
	return hand_of(player).size()


func hand_of(player: int) -> Array[String]:
	if player < 0 or player >= hands.size():
		var empty: Array[String] = []
		return empty
	return hands[player]


func coins_of(player: int) -> int:
	return coins[player] if player >= 0 and player < coins.size() else 0


func role_name(role: String) -> String:
	return Loc.t("game.coup.role.%s" % role)


## Match score: surviving influence outweighs coins, so the ranking stays stable.
func score_of(player: int) -> int:
	return hand_of(player).size() * 10 + coins_of(player)


func _alive_players() -> Array[int]:
	var out: Array[int] = []
	for player: int in range(player_count()):
		if is_alive(player):
			out.append(player)
	return out


func _opponents(player: int) -> Array[int]:
	var out: Array[int] = []
	for other: int in range(player_count()):
		if other != player and is_alive(other):
			out.append(other)
	return out


## Deterministic Fisher-Yates with the engine rng (never Array.shuffle()).
func _shuffle(cards: Array) -> void:
	for i: int in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = cards[i]
		cards[i] = cards[j]
		cards[j] = swap


func _draw_into(player: int, count: int) -> int:
	var drawn: Array[String] = []
	for _i: int in range(count):
		if deck.is_empty():
			break
		drawn.append(deck.pop_front())
	var hand: Array[String] = hands[player]
	hand.append_array(drawn)
	return drawn.size()


func _hand_has(player: int, role: String) -> bool:
	var hand: Array[String] = hands[player]
	return hand.has(role)


## Turns a shown card back into the court: it is shuffled in and replaced.
func _replace_shown_card(player: int, role: String) -> void:
	var hand: Array[String] = hands[player]
	for slot: int in range(hand.size()):
		if hand[slot] == role:
			hand.remove_at(slot)
			break
	deck.append(role)
	_shuffle(deck)
	_draw_into(player, 1)


func _next_alive(from_player: int) -> int:
	var count := player_count()
	for offset: int in range(1, count + 1):
		var seat := (from_player + offset) % count
		if is_alive(seat):
			return seat
	return from_player


# ---------------------------------------------------------- legal action list

func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished or player != decision_player():
		return out
	match step:
		"action":
			_append_action_options(out, player)
		"challenge":
			out.append(make_action("challenge", {}, "game.coup.action.challenge"))
			out.append(make_action("pass", {}, "game.coup.action.pass"))
		"block":
			_append_block_options(out)
		"lose":
			_append_lose_options(out, player)
		"exchange":
			_append_return_options(out, player)
	return out


func _append_action_options(out: Array[Dictionary], player: int) -> void:
	var targets := _opponents(player)
	if coins[player] >= MANDATORY_COUP_COINS:
		# With ten coins the rules force a coup; it is the only legal action.
		for target: int in targets:
			out.append(_target_action("coup", target, "game.coup.action.coup"))
		return
	out.append(make_action("income", {}, "game.coup.action.income"))
	out.append(make_action("foreign_aid", {}, "game.coup.action.foreign_aid"))
	out.append(make_action("tax", {}, "game.coup.action.tax"))
	out.append(make_action("exchange", {}, "game.coup.action.exchange"))
	for target: int in targets:
		if coins[player] >= ASSASSINATE_COST:
			out.append(_target_action("assassinate", target, "game.coup.action.assassinate"))
		out.append(_target_action("steal", target, "game.coup.action.steal"))
	if coins[player] >= COUP_COST:
		for target: int in targets:
			out.append(_target_action("coup", target, "game.coup.action.coup"))


## Targeted actions are submitted from the board (one per target).
func _target_action(type: String, target: int, label_key: String) -> Dictionary:
	var action := make_action(type, {"target": target}, label_key)
	action["_direct"] = false
	action["_target_name"] = player_name(target)
	return action


func _append_block_options(out: Array[Dictionary]) -> void:
	for role: String in _block_roles(VariantUtil.as_string(pending.get("type", ""), "")):
		match role:
			"duke":
				out.append(make_action("block", {"role": role}, "game.coup.action.block_duke"))
			"captain":
				out.append(make_action("block", {"role": role}, "game.coup.action.block_captain"))
			"ambassador":
				out.append(make_action("block", {"role": role}, "game.coup.action.block_ambassador"))
			"contessa":
				out.append(make_action("block", {"role": role}, "game.coup.action.block_contessa"))
	out.append(make_action("pass", {}, "game.coup.action.pass"))


## Characters that may stop an action (empty when the action cannot be blocked).
static func _block_roles(type: String) -> Array[String]:
	match type:
		"foreign_aid":
			return ["duke"]
		"assassinate":
			return ["contessa"]
		"steal":
			return ["captain", "ambassador"]
	var none: Array[String] = []
	return none


func _append_lose_options(out: Array[Dictionary], player: int) -> void:
	var hand: Array[String] = hands[player]
	for slot: int in range(hand.size()):
		var action := make_action("lose_card", {"slot": slot}, "game.coup.action.lose")
		action["_direct"] = false
		action["_role"] = hand[slot]
		out.append(action)


func _append_return_options(out: Array[Dictionary], player: int) -> void:
	var hand: Array[String] = hands[player]
	for slot: int in range(hand.size()):
		var action := make_action("return_card", {"slot": slot}, "game.coup.action.return")
		action["_direct"] = false
		action["_role"] = hand[slot]
		out.append(action)


func _window_player() -> int:
	if window_pos < 0 or window_pos >= window.size():
		return -1
	return window[window_pos]


# --------------------------------------------------------------- apply action

func apply_action(action: Dictionary) -> Dictionary:
	if finished:
		return _fail("game.common.match_over")
	var type := VariantUtil.as_string(action.get("type", ""), "")
	if not ACTION_TYPES.has(type):
		return _fail("game.coup.error.unknown_action")
	var actor := decision_player()
	if actor < 0:
		return _fail("game.coup.error.illegal_action")
	# The action must be one of the keys offered to the deciding player.
	var offered: Dictionary = {}
	for candidate: Dictionary in legal_actions(actor):
		if VariantUtil.as_string(candidate.get("key", ""), "") == VariantUtil.as_string(action.get("key", ""), ""):
			offered = candidate
			break
	if offered.is_empty():
		return _fail("game.coup.error.illegal_action")
	match type:
		"income", "foreign_aid", "tax", "exchange", "coup", "assassinate", "steal":
			return _declare(actor, offered)
		"challenge":
			return _challenge(actor)
		"pass":
			return _window_pass()
		"block":
			return _claim_block(actor, VariantUtil.as_string(offered.get("role", ""), ""))
		"lose_card":
			return _lose_card(actor, VariantUtil.as_int(offered.get("slot", -1), -1))
		"return_card":
			return _return_card(actor, VariantUtil.as_int(offered.get("slot", -1), -1))
	return _fail("game.coup.error.unknown_action")


# ------------------------------------------------------------- action resolution

func _declare(actor: int, offered: Dictionary) -> Dictionary:
	var type := VariantUtil.as_string(offered.get("type", ""), "")
	var target := VariantUtil.as_int(offered.get("target", -1), -1)
	if type == "coup" or type == "assassinate" or type == "steal":
		if not is_alive(target) or target == actor:
			return _fail("game.coup.error.bad_target")
	pending = {"type": type, "actor": actor, "target": target, "stage": "start"}
	match type:
		"income":
			coins[actor] += 1
			log_event("game.coup.log_income", {"player": player_name(actor)}, actor)
			_finish_turn()
		"foreign_aid":
			pending["stage"] = "block"
			log_event("game.coup.log_foreign_aid", {"player": player_name(actor)}, actor)
			_open_block_window()
		"tax":
			log_event("game.coup.log_tax", {"player": player_name(actor)}, actor)
			_open_claim(actor, "duke", "action", type, target)
		"exchange":
			log_event("game.coup.log_exchange", {"player": player_name(actor)}, actor)
			_open_claim(actor, "ambassador", "action", type, target)
		"assassinate":
			coins[actor] -= ASSASSINATE_COST
			log_event("game.coup.log_assassinate", {
				"player": player_name(actor), "target": player_name(target),
			}, actor)
			_open_claim(actor, "assassin", "action", type, target)
		"steal":
			log_event("game.coup.log_steal", {
				"player": player_name(actor), "target": player_name(target),
			}, actor)
			_open_claim(actor, "captain", "action", type, target)
		"coup":
			coins[actor] -= COUP_COST
			log_event("game.coup.log_coup", {
				"player": player_name(actor), "target": player_name(target),
			}, actor)
			_begin_lose(target)
	return _ok(offered)


func _open_claim(player: int, role: String, kind: String, type: String, target: int) -> void:
	claim = {"kind": kind, "role": role, "player": player, "type": type, "target": target}
	step = "challenge"
	_open_window(player)


## Challenge window: every other living seat, in order after the claimant.
func _open_window(claimant: int) -> void:
	window.clear()
	window_pos = 0
	var count := player_count()
	for offset: int in range(1, count):
		var seat := (claimant + offset) % count
		if seat != claimant and is_alive(seat):
			window.append(seat)
	if window.is_empty():
		_resolve_window_stage()


func _open_block_window() -> void:
	var type := VariantUtil.as_string(pending.get("type", ""), "")
	var actor := VariantUtil.as_int(pending.get("actor", -1), -1)
	window.clear()
	window_pos = 0
	if type == "foreign_aid":
		var count := player_count()
		for offset: int in range(1, count):
			var seat := (actor + offset) % count
			if is_alive(seat):
				window.append(seat)
	else:
		# Only the victim of an assassination or a theft may block it.
		var target := VariantUtil.as_int(pending.get("target", -1), -1)
		if is_alive(target):
			window.append(target)
	step = "block"
	if window.is_empty():
		_resolve_window_stage()


func _window_pass() -> Dictionary:
	window_pos += 1
	if window_pos >= window.size():
		_resolve_window_stage()
	return _ok()


## Called when a window exhausts: the claim stands, or the action resolves.
func _resolve_window_stage() -> void:
	if step == "challenge":
		if VariantUtil.as_string(claim.get("kind", ""), "") == "block":
			# An unchallenged block stops the action.
			_cancel_pending()
		else:
			pending["stage"] = "claim_done"
			_continue_pending()
	elif step == "block":
		pending["stage"] = "block_done"
		_resolve_pending()


func _challenge(player: int) -> Dictionary:
	var claimant := VariantUtil.as_int(claim.get("player", -1), -1)
	var role := VariantUtil.as_string(claim.get("role", ""), "")
	var kind := VariantUtil.as_string(claim.get("kind", ""), "action")
	log_event("game.coup.log_challenge", {
		"player": player_name(player), "claimant": player_name(claimant), "role": role_name(role),
	}, player)
	if _hand_has(claimant, role):
		log_event("game.coup.log_show", {
			"player": player_name(claimant), "role": role_name(role),
		}, claimant)
		_replace_shown_card(claimant, role)
		if kind == "action":
			pending["stage"] = "claim_done"
			_begin_lose(player)
		else:
			_begin_lose(player)
	else:
		log_event("game.coup.log_caught", {
			"player": player_name(claimant), "role": role_name(role),
		}, claimant)
		if kind == "action":
			_refund_action_cost()
			_begin_lose(claimant)
		else:
			pending["stage"] = "block_done"
			_begin_lose(claimant)
	return _ok()


## A successfully challenged action is cancelled and its cost returns.
func _refund_action_cost() -> void:
	var actor := VariantUtil.as_int(pending.get("actor", -1), -1)
	if actor < 0:
		return
	if VariantUtil.as_string(pending.get("type", ""), "") == "assassinate":
		coins[actor] += ASSASSINATE_COST
		log_event("game.coup.log_refund", {"player": player_name(actor)}, actor)


func _claim_block(player: int, role: String) -> Dictionary:
	if not _block_roles(VariantUtil.as_string(pending.get("type", ""), "")).has(role):
		return _fail("game.coup.error.bad_target")
	claim = {
		"kind": "block", "role": role, "player": player,
		"type": VariantUtil.as_string(pending.get("type", ""), ""), "target": VariantUtil.as_int(pending.get("target", -1), -1),
	}
	log_event("game.coup.log_block", {
		"player": player_name(player), "role": role_name(role),
	}, player)
	step = "challenge"
	_open_window(player)
	return _ok()


# --------------------------------------------------------------- lose influence

func _begin_lose(player: int) -> void:
	loser = player
	window.clear()
	window_pos = 0
	step = "lose"


func _lose_card(player: int, slot: int) -> Dictionary:
	var hand: Array[String] = hands[player]
	if player != loser or slot < 0 or slot >= hand.size():
		return _fail("game.coup.error.illegal_action")
	var card := hand[slot]
	hand.remove_at(slot)
	var shown: Array[String] = revealed[player]
	shown.append(card)
	log_event("game.coup.log_reveal", {
		"player": player_name(player), "role": role_name(card),
	}, player)
	loser = -1
	var continuation := _lose_continuation()
	if hand.is_empty():
		log_event("game.coup.log_out", {"player": player_name(player)}, player)
		if _alive_players().size() <= 1:
			_finish_last_standing()
			return _ok()
	match continuation:
		"cancel":
			_cancel_pending()
		"continue":
			_continue_pending()
		_:
			_finish_turn()
	return _ok()


## What happens once the revealed card is settled. Everything needed is public
## (`pending` / `claim`), so a snapshot restores straight into this state.
func _lose_continuation() -> String:
	if pending.is_empty() or VariantUtil.as_string(pending.get("type", ""), "") == "coup":
		return "advance"
	var stage := VariantUtil.as_string(pending.get("stage", ""), "")
	if stage == "claim_done" or stage == "block_done":
		return "continue"
	return "cancel"


# --------------------------------------------------------------- pending action

func _cancel_pending() -> void:
	pending = {}
	claim = {}
	_finish_turn()


func _continue_pending() -> void:
	if VariantUtil.as_string(pending.get("stage", ""), "") == "claim_done":
		var type := VariantUtil.as_string(pending.get("type", ""), "")
		if type == "assassinate" or type == "steal":
			pending["stage"] = "block"
			_open_block_window()
			return
	_resolve_pending()


func _resolve_pending() -> void:
	var type := VariantUtil.as_string(pending.get("type", ""), "")
	var actor := VariantUtil.as_int(pending.get("actor", -1), -1)
	var target := VariantUtil.as_int(pending.get("target", -1), -1)
	pending = {}
	claim = {}
	match type:
		"foreign_aid":
			coins[actor] += 2
			log_event("game.coup.log_aid_done", {"player": player_name(actor)}, actor)
			_finish_turn()
		"tax":
			coins[actor] += TAX_AMOUNT
			log_event("game.coup.log_tax_done", {"player": player_name(actor)}, actor)
			_finish_turn()
		"steal":
			if not is_alive(target):
				# The target went out of influence earlier in this turn
				# (challenged and lost the last card): their coins are gone,
				# so there is nothing left to steal. Pass the turn.
				_finish_turn()
			else:
				var amount := mini(STEAL_AMOUNT, coins[target])
				coins[target] -= amount
				coins[actor] += amount
				log_event("game.coup.log_steal_done", {
					"player": player_name(actor), "target": player_name(target), "gold": amount,
				}, actor)
				_finish_turn()
		"assassinate":
			if not is_alive(target):
				# Same principle: the victim already lost their influence in
				# the challenge; the hit collected, nothing left to reveal.
				_finish_turn()
			else:
				_begin_lose(target)
		"exchange":
			_draw_into(actor, EXCHANGE_DRAW)
			var keep := maxi(1, hands[actor].size() - EXCHANGE_DRAW)
			pending = {"type": "exchange", "actor": actor, "keep": keep}
			step = "exchange"
			if hands[actor].size() <= keep:
				pending = {}
				_finish_turn()
		_:
			_finish_turn()


func _return_card(player: int, slot: int) -> Dictionary:
	var hand: Array[String] = hands[player]
	if player != current or slot < 0 or slot >= hand.size():
		return _fail("game.coup.error.illegal_action")
	var keep := VariantUtil.as_int(pending.get("keep", hand.size()), hand.size())
	if hand.size() <= keep:
		return _fail("game.coup.error.illegal_action")
	deck.append(hand[slot])
	hand.remove_at(slot)
	_shuffle(deck)
	if hand.size() <= keep:
		log_event("game.coup.log_exchange_done", {"player": player_name(player)}, player)
		pending = {}
		_finish_turn()
	return _ok()


# ------------------------------------------------------------------ turn flow

func _finish_turn() -> void:
	turn_count += 1
	if turn_count >= MAX_TURNS:
		_finish_turn_limit()
		return
	var previous := current
	current = _next_alive(current)
	if current <= previous:
		round_index += 1
	step = "action"
	pending = {}
	claim = {}
	window.clear()
	window_pos = 0
	loser = -1
	log_event("game.coup.log_turn", {"player": player_name(current)})


func _finish_last_standing() -> void:
	var winner := -1
	for player: int in range(player_count()):
		if is_alive(player):
			winner = player
	step = "finished"
	finish(winner, "game.coup.reason_last_standing", _scores())


## Safety net: every normal match ends through elimination long before this.
func _finish_turn_limit() -> void:
	var winner := -1
	var best := -1
	for player: int in range(player_count()):
		var score := score_of(player)
		if score > best or (score == best and winner < 0):
			best = score
			winner = player
	step = "finished"
	finish(winner, "game.coup.reason_turn_limit", _scores())


func _scores() -> Array:
	var out: Array = []
	for player: int in range(player_count()):
		out.append({"player": player, "name": player_name(player), "score": score_of(player)})
	return out


# ------------------------------------------------------------------ snapshots

func public_state() -> Dictionary:
	var state := super.public_state()
	state["step"] = step
	state["current"] = current
	state["coins"] = coins.duplicate()
	var counts: Array = []
	for player: int in range(player_count()):
		counts.append(_influence_count(player))
	state["hand_counts"] = counts
	state["revealed"] = revealed.duplicate(true)
	state["pending"] = pending.duplicate(true)
	state["claim"] = claim.duplicate(true)
	state["window"] = window.duplicate()
	state["window_pos"] = window_pos
	state["loser"] = loser
	state["deck_count"] = deck.size()
	state["turn_count"] = turn_count
	return state


func private_state(player: int) -> Dictionary:
	if player < 0:
		# Table secrets: the Court deck. Never sent to a seat, but a snapshot of
		# the table needs it to resume the match (the harness merges it too).
		return {"deck": deck.duplicate()}
	if player >= player_count():
		return {}
	return {"seat": player, "hand": hand_of(player).duplicate()}


## Installs ONE seat's influence cards on a replica or one save-file bag slot.
## Other seats stay untouched: a client replica only knows its own influence,
## and the SHUFFLED COURT DECK must only ever arrive as a seat -1 table secret,
## because a leaked deck would betray every later draw.
func _adopt_private_extra(seat: int, slice: Dictionary) -> void:
	if seat < 0:
		if slice.has("deck"):
			GameEngine.copy_string_array(slice.get("deck", []), deck)
		return
	if seat >= player_count():
		return
	while hands.size() < player_count():
		var filler: Array[String] = []
		hands.append(filler)
	# A private slice may arrive as an opaque view (client replica seeded only
	# with the public snapshot) - install just what was authorized.
	var hand: Array[String] = []
	GameEngine.copy_string_array(slice.get("hand", []), hand)
	hands[seat] = hand


func _restore_extra(state: Dictionary) -> void:
	step = VariantUtil.as_string(state.get("step", "action"), "action")
	current = VariantUtil.as_int(state.get("current", 0), 0)
	GameEngine.copy_int_array(state.get("coins", []), coins)
	while coins.size() < player_count():
		coins.append(0)
	var revealed_snapshot: Array = state.get("revealed", []) if state.get("revealed", []) is Array else []
	var privates: Dictionary = state.get("private_states", {}) if state.get("private_states", {}) is Dictionary else {}
	hands.clear()
	revealed.clear()
	for player: int in range(player_count()):
		var shown: Array[String] = []
		if player < revealed_snapshot.size():
			GameEngine.copy_string_array(revealed_snapshot[player], shown)
		revealed.append(shown)
	# The public influence counts are authoritative in every restoration form:
	# a live engine recomputes them from its hands as it plays.
	hand_counts.clear()
	GameEngine.copy_int_array(state.get("hand_counts", []), hand_counts)
	_hands_unknown = true
	if not privates.is_empty():
		# Save-file shape: every seat's private slice keyed by seat index.
		for seat: int in range(player_count()):
			var slice: Dictionary = privates.get(str(seat), {}) if privates.get(str(seat), {}) is Dictionary else {}
			_adopt_private_extra(seat, slice)
		# A bag holds every seat: this engine is a complete host replica.
		_hands_unknown = privates.size() < player_count()
	elif state.has("hand"):
		# Client shape (harness contract): the acting player's own influence
		# merged at the top level, attributed to the decision player.
		_adopt_private_extra(decision_player(), state)
	else:
		# Public-only spectator: influence stays hidden.
		for _player: int in range(player_count()):
			var empty: Array[String] = []
			hands.append(empty)
	pending = VariantUtil.dict_copy(state.get("pending", {}))
	claim = VariantUtil.dict_copy(state.get("claim", {}))
	GameEngine.copy_int_array(state.get("window", []), window)
	window_pos = VariantUtil.as_int(state.get("window_pos", 0), 0)
	loser = VariantUtil.as_int(state.get("loser", -1), -1)
	turn_count = VariantUtil.as_int(state.get("turn_count", 0), 0)
	# The shuffled court deck: whole-match form at the top level, save files
	# under the "-1" bag key.
	var table: Dictionary = privates.get("-1", {}) if privates.get("-1", {}) is Dictionary else {}
	GameEngine.copy_string_array(table.get("deck", state.get("_deck", [])), deck)
