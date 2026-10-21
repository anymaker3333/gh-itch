extends RefCounted
## Action-submission regression (Wave A gate §6.1).
##
## One valid user click must produce exactly one accepted game action and one
## engine state transition. The test exercises the production wiring: the real
## view is mounted on a real session and its `action_requested` signal is routed
## exactly the way `GameScreen._on_view_action()` routes it
##
##     view.submit(key)  →  action_requested(key)  →  submit_action_key(key)
##
## instead of calling the engine directly. The historical bug: `GameView.submit`
## submitted directly to the session AND emitted the signal, so `GameScreen`
## submitted the same action a second time. DANY's double-selection and Chess's
## rejection spam were both consequences of that.

const TEST_SEED: int = 20261019


func suite_name() -> String:
	return "action submit wiring"


func run(h: TestHarness) -> void:
	_one_click_one_action(h, "dany")
	_one_click_one_action(h, "chess")
	_one_click_one_action(h, "coup")
	_one_click_one_action(h, "splendor")
	_one_click_one_action(h, "bridge")
	_standalone_view_still_works(h, "coup")


## Mounts the real view, routes its signal through the GameScreen's exact path
## and drives one legal action through `view.submit()` exactly once per game.
func _one_click_one_action(h: TestHarness, game_id: String) -> void:
	Session.configure(game_id, 2)
	h.check(Session.engine_available(game_id), "%s: engine registered" % game_id)
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	h.is_true(session != null, "%s: local hotseat session starts" % game_id)
	if session == null:
		return
	var view: GameView = _mount_view(h, session, game_id)
	if view == null:
		return
	# Production wiring: GameScreen mounts the view with
	#   view.action_requested.connect(_on_view_action)
	# and _on_view_action(key) does `Session.current.submit_action_key(key)` —
	# nothing else. Reproduce that exactly (the session variable is stable here).
	view.action_requested.connect(func(action_key: String) -> void:
		session.submit_action_key(action_key)
	)
	var applied: Array = []
	var rejected: Array = []
	var before_count: int = session.engine.action_count
	session.engine.action_applied.connect(func(_a: Dictionary) -> void: applied.append(_a))
	session.action_rejected.connect(func(reason_key: String, detail: String) -> void:
		rejected.append([reason_key, detail])
	)
	# One click = one submission through the view.
	var actions := view.legal_actions()
	h.greater(float(actions.size()), 0.0, "%s: the acting player has a legal action" % game_id)
	var action: Dictionary = actions[0]
	var key := String(action.get("key", ""))
	h.check(not key.is_empty(), "%s: the first legal action has a key" % game_id)
	view.submit(key)
	# One accepted action only. The historical bug produced two accepts for one
	# click (the second usually rejected as illegal or "not your turn").
	h.equal(applied.size(), 1, "%s: exactly one action_applied emission" % game_id)
	h.equal(session.engine.action_count - before_count, 1, "%s: action_count advanced by exactly 1" % game_id)
	h.is_true(rejected.is_empty(), "%s: a single legal click must not trigger a rejection" % game_id)
	Session.end_session(false)
	view.free()


## Without a GameScreen connected to the signal, a standalone view (tests,
## inspectors) must still drive the session — the single-owner rule is
## "one component submits", not "nothing ever submits".
func _standalone_view_still_works(h: TestHarness, game_id: String) -> void:
	Session.configure(game_id, 2)
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	if session == null:
		h.check(false, "%s: standalone session starts" % game_id)
		return
	var view: GameView = _mount_view(h, session, game_id)
	if view == null:
		return
	var actions := view.legal_actions()
	if actions.is_empty():
		h.check(false, "%s: standalone view has an action" % game_id)
		return
	var before: int = session.engine.action_count
	view.submit(String(actions[0].get("key", "")))
	h.equal(session.engine.action_count - before, 1, "%s: a standalone view submits exactly once" % game_id)
	Session.end_session(false)
	view.free()


## Loads the real view script through GameScreen's registry and mounts it.
func _mount_view(h: TestHarness, session: GameSession, game_id: String) -> GameView:
	var path := String(_view_scripts().get(game_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		h.check(false, "%s: view registered and loadable" % game_id)
		return null
	var script := load(path) as GDScript
	h.is_true(script != null and script.can_instantiate(), "%s: view script compiles" % game_id)
	if script == null:
		return null
	var instance: Variant = script.new()
	h.is_true(instance is GameView, "%s: view extends GameView" % game_id)
	if not (instance is GameView):
		if instance is Node:
			(instance as Node).free()
		return null
	var view: GameView = instance
	view.configure(session)
	h.greater(float(view.get_child_count()), 0.0, "%s: the mounted view builds a board" % game_id)
	return view


func _view_scripts() -> Dictionary:
	var script := load("res://scripts/ui/screens/game_screen.gd") as GDScript
	if script == null:
		return {}
	return script.get_script_constant_map().get("VIEW_SCRIPTS", {})
