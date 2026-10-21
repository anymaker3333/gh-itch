extends RefCounted
const STEPS_CAP: int = 2000
const GAMES: int = 120
func run() -> void:
	var deadlocks: int = 0
	var overruns: int = 0
	var finished: int = 0
	var rejects: int = 0
	for g: int in range(GAMES):
		var players := 3 + (g % 6)
		var engine: GameEngine = EngineHarness.create("king", players, 88000 + g)
		if engine == null:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = 246 + g
		var steps: int = 0
		var done: bool = false
		while not engine.finished and steps < STEPS_CAP:
			steps += 1
			var actor := engine.decision_player()
			var actions := engine.legal_actions(actor)
			if actions.is_empty():
				deadlocks += 1
				var st: Dictionary = engine.public_state()
				print("DEADLOCK g=%d s=%d phase=%s actor=%d turn=%s leader=%s trick_no=%s picks=%s" % [
					g, steps, String(st.get("phase_id", "")), actor, st.get("turn_seat"), st.get("leader"), st.get("trick_no"), str(engine.picks_count)])
				break
			var pick: Dictionary = actions[rng.randi_range(0, actions.size() - 1)]
			var outcome := engine.apply_action_by_key(actor, String(pick.get("key", "")))
			if not bool(outcome.get("ok", false)):
				rejects += 1
				print("REJECTED g=%d s=%d phase=%s key=%s err=%s" % [g, steps, engine.phase_id, pick.get("key", ""), outcome.get("error_key", "")])
				break
		if engine.finished:
			finished += 1
			done = true
		elif steps >= STEPS_CAP:
			overruns += 1
			var st2: Dictionary = engine.public_state()
			print("OVERRUN g=%d phase=%s trick_no=%s leader=%s turn=%s" % [g, String(st2.get("phase_id", "")), st2.get("trick_no"), st2.get("leader"), st2.get("turn_seat")])
	print("games=%d finished=%d deadlocks=%d overruns=%d rejects=%d" % [GAMES, finished, deadlocks, overruns, rejects])
