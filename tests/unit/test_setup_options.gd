extends RefCounted
## Setup-option regression (Wave B §7.4).
##
## Verifies that options configured on the session actually reach the engine:
## player names, fixed seeds and other persisted setup settings.

func suite_name() -> String:
	return "setup options"


func run(h: TestHarness) -> void:
	_seed_reaches_engine(h)
	_names_reach_engine(h)


func _seed_reaches_engine(h: TestHarness) -> void:
	Session.configure("chess", 2)
	Session.set_option("seed", 12345)
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	h.is_true(session != null, "chess: session starts")
	if session == null:
		return
	h.equal(session.engine.seed, 12345, "the configured seed reaches the engine")
	Session.end_session(false)


func _names_reach_engine(h: TestHarness) -> void:
	Session.configure("chess", 2)
	Session.pending["names"] = [Prefs.profile_name(), "Bob"]
	var session := Session.start_local_session(GameSession.Mode.LOCAL_HOTSEAT)
	h.is_true(session != null, "chess: session starts")
	if session == null:
		return
	h.equal(session.engine.player_name(1), "Bob", "player 1 keeps the configured name")
	Session.end_session(false)
