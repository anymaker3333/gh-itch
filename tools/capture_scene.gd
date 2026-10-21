extends SceneTree
## Screenshot helper for manual visual checks.
##
##     godot --path . --script tools/capture_scene.gd -- \
##         --shot /tmp/gh.png [--route library] [--frames 120]
##
## Runs the real application with a visible window, waits for it to settle,
## optionally navigates to a route with the real router and saves a PNG of the
## root viewport. Unlike the MCP screenshot path (which returned fully
## transparent images in this environment), the grab happens on
## `RenderingServer.frame_post_draw`, when the framebuffer is valid.
##
## This script is a development tool: it is not part of the application and not
## part of the test suite. Exit code 0 when the PNG was written.

var _core: Node = null


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("capture: main.tscn did not load")
		quit(1)
		return
	root.add_child(packed.instantiate())
	_core = Node.new()
	_core.set_script(load("res://tools/capture_core.gd"))
	root.add_child(_core)
	_core.call("setup", root, OS.get_cmdline_user_args())


func _process(_delta: float) -> bool:
	if _core == null:
		return true
	return bool(_core.call("step"))
