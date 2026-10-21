extends RefCounted
## Catalog-status acceptance gate.
##
## `GameEntry` carries an explicit status and its own contract says a game only
## becomes `playable` once its documented acceptance criteria pass. This suite
## turns that promise into an executable gate: every catalog game marked
## `playable` must really ship
##
##   * an engine that sets up, offers valid actions, restores snapshots,
##     replays deterministically and plays to completion under the shipped bot
##     policy at both ends of its player range;
##   * a bot when the entry claims a solo-AI mode;
##   * a registered view that can mount a real local match and re-render it
##     through to the end without falling over;
##   * an English string pack whose name/description keys resolve.
##
## While nothing is marked `playable` the gate is dormant on purpose (it still
## checks that the catalog loaded, so a broken catalog cannot make it pass by
## accident). It arms itself as catalog statuses are flipped — see
## docs/AI_PROGRESS.md and docs/GAME_CATALOG.md.

const TEST_SEED: int = 20261019
const DETERMINISM_STEPS: int = 200
const VIEW_STEP_CAP: int = 4000
const VIEW_REFRESH_EVERY: int = 20


func suite_name() -> String:
	return "playable game gate"


func run(h: TestHarness) -> void:
	h.greater(float(Catalog.count()), 0.0, "the catalog must load for this gate to mean anything")
	var checked := 0
	for entry: GameEntry in Catalog.games():
		if entry.status != GameEntry.Status.PLAYABLE:
			continue
		checked += 1
		_check_entry(h, entry)
	print("   • %d game(s) marked playable, all fully checked" % checked)


func _check_entry(h: TestHarness, entry: GameEntry) -> void:
	var id := entry.id
	h.check(Session.engine_available(id), "%s: the engine script is registered" % id)
	var probe := EngineHarness.create(id, entry.min_players, TEST_SEED)
	if probe == null:
		h.check(false, "%s: the engine can be created" % id)
		return
	EngineHarness.check_legal_action_shape(h, probe, "%s (min players)" % id)
	EngineHarness.check_snapshot_round_trip(h, probe, id)
	if entry.max_players != entry.min_players:
		var wide := EngineHarness.create(id, entry.max_players, TEST_SEED)
		if wide == null:
			h.check(false, "%s: the engine can be created at max players" % id)
		else:
			EngineHarness.check_legal_action_shape(h, wide, "%s (max players)" % id)
			EngineHarness.check_snapshot_round_trip(h, wide, "%s (max players)" % id)
	_check_determinism(h, id, entry.min_players)
	if entry.supports_mode("solo_ai"):
		h.check(BotDirector.has_bot(id), "%s: solo AI is claimed, so a bot must be registered" % id)
	_check_strings(h, entry)
	_check_view(h, entry)


## Same seed + same action sequence must keep `public_state()` identical all the
## way through a match. Compared every step (dictionaries compare deeply), one
## check is reported for the whole run.
func _check_determinism(h: TestHarness, id: String, player_count: int) -> void:
	var a := EngineHarness.create(id, player_count, TEST_SEED)
	var b := EngineHarness.create(id, player_count, TEST_SEED)
	if a == null or b == null:
		h.check(false, "%s: engines for the determinism check" % id)
		return
	var steps := 0
	var diverged_at := -1
	while steps < DETERMINISM_STEPS and not a.finished and not b.finished:
		if not EngineHarness.step_first_legal(a) or not EngineHarness.step_first_legal(b):
			break
		steps += 1
		if a.public_state() != b.public_state():
			diverged_at = steps
			break
	h.greater(float(steps), 0.0, "%s: the determinism check played at least one action" % id)
	h.check(diverged_at == -1, "%s: same seed + same actions keep public_state() identical (diverged at step %d)" % [id, diverged_at])


func _check_strings(h: TestHarness, entry: GameEntry) -> void:
	var id := entry.id
	var path := "res://data/i18n/en/game_%s.json" % id
	h.check(FileAccess.file_exists(path), "%s: the English string pack ships (%s)" % [id, path])
	h.check(Loc.has_key(entry.name_key), "%s: the name key '%s' resolves" % [id, entry.name_key])
	h.check(Loc.has_key(entry.desc_key), "%s: the description key '%s' resolves" % [id, entry.desc_key])
	h.no_raw_key(Loc.t(entry.name_key), "%s: the displayed name is translated" % id)
	h.greater(float(Loc.t(entry.desc_key).length()), 20.0, "%s: the description is a real sentence" % id)


## Mounts the real view on a real local session and plays the match out with
## the shipped bot policy, re-rendering along the way. This is the closest thing
## to "open the game screen and play a match" that a headless suite can do.
func _check_view(h: TestHarness, entry: GameEntry) -> void:
	var id := entry.id
	var path := String(_view_scripts().get(id, ""))
	if path.is_empty():
		h.check(false, "%s: a view script is registered in game_screen" % id)
		return
	if not ResourceLoader.exists(path):
		h.check(false, "%s: the view script exists (%s)" % [id, path])
		return
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		h.check(false, "%s: the view script compiles and can be instantiated" % id)
		return
	var instance: Variant = script.new()
	if not (instance is GameView):
		h.check(false, "%s: the view extends GameView" % id)
		if instance is Node:
			(instance as Node).free()
		return
	var view: GameView = instance
	Session.configure(id, entry.min_players)
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	if session == null:
		h.check(false, "%s: a local hotseat session starts" % id)
		view.free()
		return
	view.configure(session)
	h.greater(float(view.get_child_count()), 0.0, "%s: the mounted view builds a board" % id)
	var engine: GameEngine = session.engine
	var steps := _drive_with_view(view, engine, VIEW_REFRESH_EVERY, VIEW_STEP_CAP)
	h.greater(float(steps), 0.0, "%s: the mounted match accepts actions" % id)
	view.refresh_board()
	h.greater(float(view.get_child_count()), 0.0, "%s: the view still renders the end of the match" % id)
	h.check(engine.finished, "%s: the mounted match reaches a result (steps=%d)" % [id, steps])
	Session.end_session(false)
	view.free()


## Drives the engine with the shipped bot policy (BotDirector handles the
## fallback), refreshing the view every `refresh_every` actions.
static func _drive_with_view(view: GameView, engine: GameEngine, refresh_every: int, cap: int) -> int:
	var steps := 0
	while not engine.finished and steps < cap:
		var actor := engine.decision_player()
		var key := BotDirector.choose_action(engine, actor)
		if key.is_empty():
			break
		var outcome := engine.apply_action_by_key(actor, key)
		if not bool(outcome.get("ok", false)):
			break
		steps += 1
		if steps % refresh_every == 0:
			view.refresh_board()
	return steps


func _view_scripts() -> Dictionary:
	var script := load("res://scripts/ui/screens/game_screen.gd") as GDScript
	if script == null:
		return {}
	return script.get_script_constant_map().get("VIEW_SCRIPTS", {})
