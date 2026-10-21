extends SceneTree
## Two-process multiplayer smoke test (entry point).
##
##     godot --headless --path . --script tools/net_smoke.gd -- --role host --port 47120
##     godot --headless --path . --script tools/net_smoke.gd -- --role client --port 47120
##
## Drives the *real* transport stack (transport -> protocol handshake ->
## GameSession host/client replication) between two OS processes over ENet on
## loopback. `tools/run_net_smoke.sh` launches both roles and merges the verdicts.
##
## Like `tests/run_tests.gd`, this only waits for the autoloads to come up and
## then hands over to a runtime-loaded core (autoload identifiers do not exist
## yet while the entry script itself compiles).

const CORE_SCRIPT: String = "res://tools/net_smoke_core.gd"
const TIMEOUT_SEC: float = 90.0

var _core: Variant = null
var _elapsed: float = 0.0
var _frame: int = 0


func _initialize() -> void:
	# See steam_service.gd: skip Steamworks in automated headless runs.
	OS.set_environment("GAMEHUB_DISABLE_STEAM", "1")


func _process(delta: float) -> bool:
	if _core == null:
		_frame += 1
		if _frame < 2:
			return false
		var script := load(CORE_SCRIPT) as GDScript
		if script == null:
			printerr("net_smoke: cannot load %s" % CORE_SCRIPT)
			quit(100)
			return true
		_core = script.new()
		_core.call("setup", OS.get_cmdline_user_args())
		return false
	_elapsed += delta
	if int(_core.call("poll", delta)) != 0:
		quit(clampi(int(_core.call("exit_code")), 0, 100))
		return true
	if _elapsed > TIMEOUT_SEC:
		_core.call("on_timeout")
		printerr("net_smoke: timed out after %.1fs" % _elapsed)
		quit(3)
		return true
	return false
