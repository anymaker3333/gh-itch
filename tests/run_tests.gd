extends SceneTree
## Headless test runner (entry point).
##
##     godot --headless --path . --script tests/run_tests.gd                # everything
##     godot --headless --path . --script tests/run_tests.gd -- --filter chess
##     godot --headless --path . --script tests/run_tests.gd -- --filter coup,dany
##     godot --headless --path . --script tests/run_tests.gd -- --list
##
## Godot instantiates the project autoloads even with a custom main loop, but
## their `_ready()` runs on the first frame, after `_initialize()`. This entry
## point therefore only waits for the services to come up and then hands over to
## `tests/support/test_runner_core.gd`, which is loaded at runtime and can use the
## autoload singletons directly. Exit code = number of failed checks (capped at
## 100 so it stays inside the POSIX 0-255 range).

const CORE_SCRIPT: String = "res://tests/support/test_runner_core.gd"

var _frame: int = 0
var _done: bool = false


func _initialize() -> void:
	# See steam_service.gd: Steamworks teardown is unreliable across the many
	# short-lived headless processes of an automated run.
	OS.set_environment("GAMEHUB_DISABLE_STEAM", "1")


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame < 2:
		return false
	_done = true
	var script := load(CORE_SCRIPT) as GDScript
	if script == null:
		printerr("runner: cannot load %s" % CORE_SCRIPT)
		quit(100)
		return true
	var core: Variant = script.new()
	if core == null:
		printerr("runner: cannot instantiate the runner core")
		quit(100)
		return true
	core.call("setup", OS.get_cmdline_user_args())
	var failures := int(core.call("run"))
	quit(clampi(failures, 0, 100))
	return true
