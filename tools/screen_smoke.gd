extends SceneTree
## Bootstrap for the screen smoke walker (see tools/screen_smoke_core.gd).
##
##     godot --headless --path . --script tools/screen_smoke.gd
##
## A script passed with --script is compiled before the project autoloads are
## registered, so this file may not reference service singletons. It only boots
## the real shell and then loads tools/screen_smoke_core.gd at runtime, which
## can use Nav and friends. Exit code comes from the core.

const CORE_SCRIPT: String = "res://tools/screen_smoke_core.gd"

var _core: Variant = null
var _frame: int = 0


func _initialize() -> void:
	# See steam_service.gd: skip Steamworks in automated headless runs.
	OS.set_environment("GAMEHUB_DISABLE_STEAM", "1")


func _process(_delta: float) -> bool:
	if _core == null:
		_frame += 1
		if _frame < 2:
			return false
		var script := load(CORE_SCRIPT) as GDScript
		if script == null:
			printerr("screen smoke: cannot load %s" % CORE_SCRIPT)
			quit(1)
			return true
		_core = script.new()
		if _core == null:
			printerr("screen smoke: cannot instantiate %s" % CORE_SCRIPT)
			quit(1)
			return true
		_core.call("setup", root)
		return false
	if bool(_core.call("step")):
		quit(int(_core.call("exit_code")))
		return true
	return false
