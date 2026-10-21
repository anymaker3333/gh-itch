extends Node
## Capture logic for tools/capture_scene.gd (loaded at runtime so it can use the
## autoloads through the scene tree). Waits, optionally navigates, grabs one
## frame and quits.

const NAV_SETTLE_FRAMES: int = 30

var _root: Node = null
var _shot: String = "user://capture.png"
var _route: String = ""
var _wait_frames: int = 120

var _phase: int = 0
var _frames: int = 0
var _done: bool = false


func setup(root_node: Node, args: PackedStringArray) -> void:
	_root = root_node
	var i := 0
	while i < args.size():
		match String(args[i]):
			"--shot":
				if i + 1 < args.size():
					_shot = String(args[i + 1])
					i += 1
			"--route":
				if i + 1 < args.size():
					_route = String(args[i + 1])
					i += 1
			"--frames":
				if i + 1 < args.size():
					_wait_frames = maxi(1, int(args[i + 1]))
					i += 1
		i += 1


func step() -> bool:
	if _done:
		return true
	if _phase == 0:
		_frames += 1
		if _frames < _wait_frames:
			return false
		_navigate()
		_phase = 1
		_frames = 0
		return false
	if _phase == 1:
		_frames += 1
		if _frames < NAV_SETTLE_FRAMES:
			return false
		_phase = 2
		_frames = 0
		RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)
		return false
	# waiting for the grab; bail out if the signal never arrives
	_frames += 1
	if _frames > 300:
		printerr("capture: frame_post_draw never fired; giving up")
		_done = true
		get_tree().quit(1)
		return true
	return false


func _navigate() -> void:
	if _route.is_empty():
		return
	var nav := _root.get_node_or_null("Nav")
	if nav == null:
		printerr("capture: Nav autoload not found; staying on the current route")
		return
	nav.call("go", _route, {})


func _grab() -> void:
	_done = true
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("capture: viewport returned no image")
		get_tree().quit(1)
		return
	var err := image.save_png(_shot)
	if err != OK:
		printerr("capture: save_png failed (%d)" % err)
		get_tree().quit(1)
		return
	var alpha := image.get_pixel(image.get_width() / 2, image.get_height() / 2).a
	print("capture: wrote %s (%dx%d, centre alpha=%.2f)" % [_shot, image.get_width(), image.get_height(), alpha])
	get_tree().quit(0)
