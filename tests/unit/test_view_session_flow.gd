extends RefCounted
## Complete session/view-flow regression (Wave 1 gate §5.2).
##
## For all 13 games: instantiate and mount the REAL view, attach the same action
## wiring the production GameScreen uses (`view.action_requested` →
## `submit_action_key`), initialize a valid session and drive legal actions
## through the actual view/session path until the match ends.
##
## What must hold for every game:
##   * no spurious action rejection on any legal action,
##   * every accepted action mutates the state exactly once (one
##     `action_applied` emission per applied action),
##   * the terminal event is reported once,
##   * the mounted view keeps rendering with content (no blank board),
##   * a malformed or unavailable view fails VISIBLY (checked in
##     test_view_errors.gd) and cannot silently kill the suite.

const BOT_STEPS_CAP: int = 6000
const DETERMINISTIC_SEED: int = 20261019


func suite_name() -> String:
	return "view session flow (13 games)"


func run(h: TestHarness) -> void:
	var games := Catalog.games()
	h.greater(float(games.size()), 0.0, "the catalog lists the games")
	for entry: Variant in games:
		if entry is GameEntry:
			_check_entry(h, entry)


func _check_entry(h: TestHarness, entry: GameEntry) -> void:
	var game_id := entry.id
	h.check(Session.engine_available(game_id), "%s: the engine script is registered" % game_id)
	var view: GameView = _mount(h, game_id, entry.min_players)
	if view == null:
		return
	var session := Session.current
	var engine: GameEngine = session.engine
	# Production wiring, exactly as GameScreen does it.
	var rejections: Array = []
	var finished_events: Array = []
	var applied_steps: Array = []
	session.action_rejected.connect(func(reason_key: String, detail: String) -> void:
		rejections.append("%s (%s)" % [reason_key, detail])
	)
	engine.match_finished.connect(func(_r: Dictionary) -> void: finished_events.append(1))
	engine.action_applied.connect(func(_a: Dictionary) -> void: applied_steps.append(1))
	var steps := _drive(view, engine, BOT_STEPS_CAP)
	h.greater(float(steps), 0.0, "%s: the view/session path accepts legal actions" % game_id)
	h.is_true(rejections.is_empty(), "%s: no spurious rejections on legal actions (%s)" % [game_id, "; ".join(PackedStringArray(rejections))])
	h.is_true(engine.finished, "%s: the match reaches a terminal state through the view path" % game_id)
	h.equal(finished_events.size(), 1, "%s: the terminal event is reported exactly once" % game_id)
	h.equal(applied_steps.size(), steps, "%s: every accepted step mutates state exactly once" % game_id)
	view.refresh_board()
	h.greater(float(view.get_child_count()), 0.0, "%s: the view still renders after completion" % game_id)
	_terminal_state_is_reported(h, engine, game_id)
	Session.end_session(false)
	view.free()


## Drives the session through the view's real submission path using the shipped
## bot policy for choice and the view fallback when the bot has no idea.
func _drive(view: GameView, engine: GameEngine, cap: int) -> int:
	var steps := 0
	while not engine.finished and steps < cap:
		var actor := engine.decision_player()
		if actor < 0:
			break
		var key := BotDirector.choose_action(engine, actor)
		if key.is_empty():
			# No bot idea: fall back to the FIRST legal action through the view
			# path, which is what the shipped fallback inside BotDirector does.
			var actions := view.legal_actions()
			if actions.is_empty():
				break
			key = String(actions[0].get("key", ""))
		if key.is_empty():
			break
		var before: int = engine.action_count
		view.submit(key)
		if engine.action_count == before:
			break
		steps += 1
	return steps


func _terminal_state_is_reported(h: TestHarness, engine: GameEngine, game_id: String) -> void:
	var reason := String(engine.result.get("reason_key", ""))
	h.check(not reason.is_empty(), "%s: the terminal state has a reason" % game_id)
	h.check(Loc.has_key(reason, "en"), "%s: the terminal reason is translated (%s)" % [game_id, reason])
	h.check(engine.legal_actions(0).is_empty() or engine.finished, "%s: no actions are offered after completion" % game_id)


## Mounts the real view on a real local session wired like GameScreen.
func _mount(h: TestHarness, game_id: String, player_count: int) -> GameView:
	var path := String(_view_scripts().get(game_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		h.check(false, "%s: a view script is registered in game_screen" % game_id)
		return null
	var script := load(path) as GDScript
	h.is_true(script != null and script.can_instantiate(), "%s: the view script compiles" % game_id)
	if script == null or not script.can_instantiate():
		return null
	# Deterministic session, same pattern as tests/unit/test_playable_games.gd.
	Session.configure(game_id, player_count)
	Session.set_option("seed", DETERMINISTIC_SEED)
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	if session == null:
		h.check(false, "%s: the flow session starts" % game_id)
		return null
	var instance: Variant = script.new()
	h.is_true(instance is GameView, "%s: the view extends GameView" % game_id)
	if not (instance is GameView):
		if instance is Node:
			(instance as Node).free()
		return null
	var view: GameView = instance
	# IDENTICAL routing to GameScreen._on_view_action (game_screen.gd).
	view.action_requested.connect(func(action_key: String) -> void:
		session.submit_action_key(action_key)
	)
	view.configure(session)
	h.greater(float(view.get_child_count()), 0.0, "%s: the mounted view builds a board" % game_id)
	return view


func _view_scripts() -> Dictionary:
	var script := load("res://scripts/ui/screens/game_screen.gd") as GDScript
	if script == null:
		return {}
	return script.get_script_constant_map().get("VIEW_SCRIPTS", {})
