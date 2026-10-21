class_name DisplayManager
extends RefCounted
## Window mode / resolution management.
##
## Keeps "window mode" and "resolution" as separate settings, validates requested
## resolutions against the display server, and offers a safety net: any change
## that could make the window unreachable is applied with an automatic revert
## unless the user confirms it.

## Static event hook (static classes cannot declare signals): listeners receive
## ("applied", {...}), ("reverted", {...}) and ("confirmation_finished", {...}).
static var _listeners: Array[Callable] = []

static func add_listener(callback: Callable) -> void:
	if not _listeners.has(callback):
		_listeners.append(callback)

static func remove_listener(callback: Callable) -> void:
	_listeners.erase(callback)

static func _emit_event(event: String, data: Dictionary = {}) -> void:
	for callback: Callable in _listeners.duplicate():
		if callback.is_valid():
			callback.call(event, data)

const MODE_WINDOWED: int = 0
const MODE_FULLSCREEN: int = 1
const MODE_BORDERLESS: int = 2

const MIN_WIDTH: int = 800
const MIN_HEIGHT: int = 540
const REVERT_SECONDS: float = 12.0

static var _revert_timer: SceneTreeTimer = null
static var _pending_snapshot: Dictionary = {}


static func apply_from_prefs() -> void:
	var mode := Prefs.window_mode()
	var size := Vector2i(Prefs.window_width(), Prefs.window_height())
	var screen := Prefs.screen_index()
	_apply(int(mode), size, screen, false)
	_apply_vsync(int(Prefs.get_value("display/vsync", 1)))
	_apply_max_fps(int(Prefs.get_value("display/max_fps", 0)))


## Applies a window configuration. `with_revert` arms the automatic recovery
## countdown for potentially unreachable configurations.
static func _apply(mode: int, size: Vector2i, screen: int, with_revert: bool) -> void:
	var window := _window()
	if window == null:
		return
	var safe_screen := clampi(screen, 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var usable := DisplayServer.screen_get_usable_rect(safe_screen)
	var safe_size := sanitize_size(size, usable)
	match mode:
		MODE_FULLSCREEN:
			window.mode = Window.MODE_FULLSCREEN
		MODE_BORDERLESS:
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			window.size = usable.size
			window.position = usable.position
		_:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.size = safe_size
			# Keep the window inside the usable area of the target screen.
			var position := window.position
			position.x = clampi(position.x, usable.position.x, maxi(usable.position.x, usable.end.x - safe_size.x))
			position.y = clampi(position.y, usable.position.y, maxi(usable.position.y, usable.end.y - safe_size.y))
			window.position = position
	Log.info("DisplayManager: applied", {"mode": mode, "size": str(safe_size), "screen": safe_screen})
	_emit_event("applied", {"mode": mode, "size": safe_size})
	if with_revert:
		_arm_revert()


## Applies a user-requested configuration with the safety countdown.
static func request(mode: int, size: Vector2i, screen: int = -1) -> void:
	_pending_snapshot = {
		"mode": Prefs.window_mode(),
		"width": Prefs.window_width(),
		"height": Prefs.window_height(),
		"screen": Prefs.screen_index(),
	}
	if screen < 0:
		screen = Prefs.screen_index()
	_apply(mode, size, screen, true)


static func confirm_pending() -> void:
	if _revert_timer == null:
		return
	_revert_timer = null
	_pending_snapshot.clear()
	_emit_event("confirmation_finished", {"kept": true})
	Log.info("DisplayManager: display change kept")


static func revert_pending(reason: String = "user") -> void:
	if _pending_snapshot.is_empty():
		return
	_revert_timer = null
	_apply(
		int(_pending_snapshot.get("mode", MODE_WINDOWED)),
		Vector2i(int(_pending_snapshot.get("width", 1600)), int(_pending_snapshot.get("height", 900))),
		int(_pending_snapshot.get("screen", 0)),
		false
	)
	_pending_snapshot.clear()
	_emit_event("reverted", {"reason": reason})
	_emit_event("confirmation_finished", {"kept": false})
	Log.info("DisplayManager: display change reverted", {"reason": reason})


static func has_pending() -> bool:
	return _revert_timer != null


## Arms the automatic recovery countdown: if the user cannot see or click the
## window any more, the previous configuration is restored automatically.
static func _arm_revert() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var timer := tree.create_timer(REVERT_SECONDS)
	_revert_timer = timer
	timer.timeout.connect(func() -> void:
		if _revert_timer == timer:
			revert_pending("timeout")
	)


static func toggle_fullscreen() -> void:
	var window := _window()
	if window == null:
		return
	if window.mode == Window.MODE_FULLSCREEN:
		Prefs.set_value("display/mode", MODE_WINDOWED)
		_apply(MODE_WINDOWED, Vector2i(Prefs.window_width(), Prefs.window_height()), Prefs.screen_index(), false)
	else:
		Prefs.set_value("display/mode", MODE_FULLSCREEN)
		_apply(MODE_FULLSCREEN, Vector2i(Prefs.window_width(), Prefs.window_height()), Prefs.screen_index(), false)
	Notify.info(Loc.t("display.toggled", {"mode": Loc.t(mode_key(int(Prefs.window_mode())))}))
	_emit_event("applied", {"mode": int(Prefs.window_mode()), "size": Vector2i(Prefs.window_width(), Prefs.window_height())})


static func mode_key(mode: int) -> String:
	match mode:
		MODE_FULLSCREEN:
			return "display.mode_fullscreen"
		MODE_BORDERLESS:
			return "display.mode_borderless"
		_:
			return "display.mode_windowed"


## Resolutions offered in the settings screen: the sane 16:9 family plus the
## native size of the current screen. Values are validated against the display
## capabilities before being used.
static func available_resolutions() -> Array[Vector2i]:
	var values: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1440, 900),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]
	var screen := clampi(Prefs.screen_index(), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var native := DisplayServer.screen_get_size(screen)
	if native.x > 0 and native.y > 0 and not values.has(native):
		values.append(native)
	values.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return values


static func sanitize_size(requested: Vector2i, usable: Rect2i) -> Vector2i:
	var width := clampi(requested.x, MIN_WIDTH, maxi(MIN_WIDTH, usable.size.x))
	var height := clampi(requested.y, MIN_HEIGHT, maxi(MIN_HEIGHT, usable.size.y))
	return Vector2i(width, height)


static func display_summary() -> String:
	var screen := clampi(Prefs.screen_index(), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var native := DisplayServer.screen_get_size(screen)
	var window := _window()
	var actual := window.size if window != null else Vector2i.ZERO
	return Loc.t("display.summary", {
		"mode": Loc.t(mode_key(Prefs.window_mode())),
		"size": "%d×%d" % [actual.x, actual.y],
		"native": "%d×%d" % [native.x, native.y],
		"screens": DisplayServer.get_screen_count(),
	})


static func _apply_vsync(mode: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(mode)


static func _apply_max_fps(value: int) -> void:
	Engine.max_fps = maxi(0, value)


static func _window() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root
