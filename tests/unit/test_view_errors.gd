extends RefCounted
## Null and view-error regression (Wave 1 gate §5.4).
##
## Mounts each applicable view and checks it builds a board without unhandled
## errors. Null/unavailable engines are handled by GameView.configure guards.

func suite_name() -> String:
	return "view errors"


func run(h: TestHarness) -> void:
	for entry: Variant in Catalog.games():
		if not (entry is GameEntry):
			continue
		var game_id := String((entry as GameEntry).id)
		if not Session.engine_available(game_id):
			continue
		Session.configure(game_id, (entry as GameEntry).min_players)
		Session.set_option("seed", 20261019)
		var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
		h.is_true(session != null, "%s: session starts" % game_id)
		if session == null:
			continue
		var path := ""
		var screen_script := load("res://scripts/ui/screens/game_screen.gd") as GDScript
		if screen_script != null:
			var view_scripts: Dictionary = screen_script.get_script_constant_map().get("VIEW_SCRIPTS", {})
			path = String(view_scripts.get(game_id, ""))
		if path.is_empty():
			Session.end_session(false)
			continue
		var script := load(path) as GDScript
		h.is_true(script != null and script.can_instantiate(), "%s: view script compiles" % game_id)
		if script == null or not script.can_instantiate():
			Session.end_session(false)
			continue
		var instance: Variant = script.new()
		h.is_true(instance is GameView, "%s: view extends GameView" % game_id)
		if not (instance is GameView):
			if instance is Node:
				(instance as Node).free()
			Session.end_session(false)
			continue
		var view: GameView = instance
		view.configure(session)
		h.greater(float(view.get_child_count()), 0.0, "%s: mounted view builds a board" % game_id)
		view.free()
		Session.end_session(false)
