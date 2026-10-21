extends SceneTree
## Windowed visual audit harness for desktop/manual runs.
##
## Run windowed:
##   godot --path . --resolution 1600x900 --position 180,80 --script tools/_ui_audit.gd
##
## Optional exact-size and scoped captures:
##   godot --path . --script tools/_ui_audit.gd -- \
##     --out=/tmp/opencode/ui_audit_1280 --size=1280x720 --scope=games --only=splendor,dany
##
## Loads the real main scene, forces the Ukrainian locale without persisting it,
## walks every screen route (including all 13 game tables), captures the real
## viewport and writes a structural report. No project file is modified. Labels
## inside ScrollContainers are intentionally skipped; those controls are
## reachable by scrolling and are reviewed from screenshots.

const DEFAULT_OUT_DIR: String = "/tmp/opencode/ui_audit"
const WAIT_BOOT: int = 25
const WAIT_ROUTE: int = 10
const WAIT_GAME: int = 30

const ROUTES: Array[Dictionary] = [
	{"name": "01_library", "route": "library", "params": {}},
	{"name": "02_all_games", "route": "all_games", "params": {}},
	{"name": "03_favorites", "route": "favorites", "params": {}},
	{"name": "04_recent", "route": "recent", "params": {}},
	{"name": "05_details_chess", "route": "game_details", "params": {"game_id": "chess"}},
	{"name": "06_details_star_realms", "route": "game_details", "params": {"game_id": "star_realms"}},
	{"name": "07_setup_chess", "route": "game_setup", "params": {"game_id": "chess"}},
	{"name": "08_star_realms_sets", "route": "star_realms_sets", "params": {"game_id": "star_realms"}},
	{"name": "09_settings", "route": "settings", "params": {}},
	{"name": "10_settings_display", "route": "settings_display", "params": {}},
	{"name": "11_settings_audio", "route": "settings_audio", "params": {}},
	{"name": "12_settings_language", "route": "settings_language", "params": {}},
	{"name": "13_settings_accessibility", "route": "settings_accessibility", "params": {}},
	{"name": "14_diagnostics", "route": "diagnostics", "params": {}},
	{"name": "15_about", "route": "about", "params": {}},
	{"name": "16_online", "route": "online", "params": {}},
	{"name": "17_lobby", "route": "lobby", "params": {}},
	{"name": "18_game_empty", "route": "game", "params": {}},
]

const GAME_SCENARIOS: Array[Dictionary] = [
	{"name": "30_game_chess", "game": "chess"},
	{"name": "31_game_durak", "game": "durak"},
	{"name": "32_game_star_realms", "game": "star_realms"},
	{"name": "33_game_monopoly", "game": "monopoly"},
	{"name": "34_game_splendor", "game": "splendor"},
	{"name": "35_game_bridge", "game": "bridge"},
	{"name": "36_game_king", "game": "king"},
	{"name": "37_game_coup", "game": "coup"},
	{"name": "38_game_codenames", "game": "codenames"},
	{"name": "39_game_citadels", "game": "citadels"},
	{"name": "40_game_dany", "game": "dany"},
	{"name": "41_game_spyfall", "game": "spyfall"},
	{"name": "42_game_ticket_to_ride_europe", "game": "ticket_to_ride_europe"},
]

var _main: Node = null
var _shell: Node = null
var _nav: Node = null
var _loc: Node = null
var _notify: Node = null
var _frame: int = 0
var _state: int = 0
var _index: int = 0
var _wait: int = 0
var _capture_name: String = ""
var _shots: int = 0
var _issues: Array[String] = []
var _missing_before: int = 0
var _report_lines: Array[String] = []
var _out_dir: String = DEFAULT_OUT_DIR
var _size: Vector2i = Vector2i(1600, 900)
var _scope: String = "all"
var _only: Array[String] = []
var _theme: String = "default"
var _sidebar: bool = true
var _viewport: SubViewport = null


func _initialize() -> void:
	_parse_args()
	OS.set_environment("GAMEHUB_DISABLE_STEAM", "1")
	# Capture from an exact-size offscreen viewport instead of the desktop
	# window. The display manager may be in a borderless mode sized to the
	# physical screen, so `--size` would otherwise be rounded to the monitor.
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	_viewport.gui_embed_subwindows = true
	root.add_child(_viewport)
	DirAccess.make_dir_recursive_absolute(_out_dir)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--scope="):
			_scope = arg.trim_prefix("--scope=")
		elif arg.begins_with("--only="):
			for item: String in arg.trim_prefix("--only=").split(","):
				if not item.is_empty():
					_only.append(item)
		elif arg.begins_with("--theme="):
			_theme = arg.trim_prefix("--theme=")
		elif arg.begins_with("--sidebar="):
			_sidebar = arg.trim_prefix("--sidebar=") != "0"


func _wanted(label: String, id: String = "") -> bool:
	if _only.is_empty():
		return true
	return _only.has(label) or _only.has(id)


func _process(_delta: float) -> bool:
	_frame += 1
	match _state:
		0:
			if _frame >= 2:
				_boot()
				_state = 1
				_wait = WAIT_BOOT
		1:
			_wait -= 1
			if _wait <= 0:
				_capture("00_home_forced_uk")
				_index = 0
				if _scope == "games":
					_state = 20
					_wait = 6
				else:
					_state = 2
		2:
			while _index < ROUTES.size() and not _wanted(String(ROUTES[_index]["name"]), String(ROUTES[_index]["route"])):
				_index += 1
			if _index >= ROUTES.size():
				_state = 10
				_wait = 8
				return false
			var entry: Dictionary = ROUTES[_index]
			_capture_name = String(entry["name"])
			_clear_toasts()
			_nav.call("go", String(entry["route"]), entry["params"], "replace", "none")
			_wait = WAIT_ROUTE
			_state = 3
		3:
			_wait -= 1
			if _wait <= 0:
				_clear_toasts()
				_capture(_capture_name)
				_index += 1
				_state = 2
		10:
			# Empty search results state.
			if _wait > 0:
				_wait -= 1
				return false
			var library := _screen("library")
			if library != null:
				library.call("on_search", "zzzz-no-such-game")
				_wait = WAIT_ROUTE
				_state = 11
			else:
				_state = 12
		11:
			_wait -= 1
			if _wait <= 0:
				_capture("19_library_empty_search")
				var lib := _screen("library")
				if lib != null:
					lib.call("on_search", "")
				_state = 12
				_wait = 6
		12:
			# Confirmation modal.
			if _wait > 0:
				_wait -= 1
				return false
			_notify.call("confirm", "Підтвердити дію", "Це тестова модальна панель для візуальної перевірки. Текст має переноситися, кнопки — бути доступними.", "Підтвердити", Callable(self, "_noop"), "Скасувати", true)
			_wait = 6
			_state = 13
		13:
			_wait -= 1
			if _wait <= 0:
				_capture("90_modal_confirm")
				var modals: Node = _shell.get("modals")
				if modals != null:
					modals.call("dismiss")
				_state = 14
				_wait = 4
		14:
			_wait -= 1
			if _wait <= 0:
				_notify.call("warning", "Тестове попередження: перевірка тостів і довгого тексту.")
				_wait = 3
				_state = 15
		15:
			_wait -= 1
			if _wait <= 0:
				_capture("91_toast_warning")
				_clear_toasts()
				if _scope == "shell":
					_finish()
					return true
				_index = 0
				_state = 20
				_wait = 6
		20:
			# Real match screens.
			if _wait > 0:
				_wait -= 1
				return false
			while _index < GAME_SCENARIOS.size() and not _wanted(String(GAME_SCENARIOS[_index]["name"]), String(GAME_SCENARIOS[_index]["game"])):
				_index += 1
			if _index >= GAME_SCENARIOS.size():
				_finish()
				return true
			var scenario: Dictionary = GAME_SCENARIOS[_index]
			var game := String(scenario["game"])
			_clear_toasts()
			_nav.call("go", "game_setup", {"game_id": game}, "replace", "none")
			_wait = WAIT_ROUTE
			_state = 21
		21:
			_wait -= 1
			if _wait <= 0:
				var setup := _screen("game_setup")
				if setup == null:
					_issues.append("scenario %s: setup screen missing" % String(GAME_SCENARIOS[_index]["game"]))
					_index += 1
					_state = 20
					_wait = 4
				else:
					setup.call("_start", 0)
					_wait = WAIT_GAME
					_state = 22
		22:
			_wait -= 1
			if _wait <= 0:
				_clear_toasts()
				_capture(String(GAME_SCENARIOS[_index]["name"]))
				_index += 1
				_state = 20
				_wait = 4
	return false


func _clear_toasts() -> void:
	if _shell == null:
		return
	var layer: Node = _shell.get("toasts") as Node
	if layer != null:
		layer.call("clear_all")


func _boot() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("AUDIT: main.tscn did not load")
		quit(2)
		return
	var theme_svc: Node = root.get_node_or_null("ThemeSvc")
	if theme_svc != null:
		theme_svc.call("_activate", _theme)
	_nav = root.get_node("Nav")
	_loc = root.get_node("Loc")
	_notify = root.get_node("Notify")
	# Force Ukrainian for the visual pass without persisting the preference.
	_loc.call("set_locale", "uk", false)
	# Give the navigation singleton a current route before the shell is built.
	# Without this the offscreen viewport can stay on the window clear colour.
	_nav.call("go", "library", {}, "replace", "none")
	_main = packed.instantiate()
	_viewport.add_child(_main)
	_shell = _main.get("shell")
	if _shell == null:
		printerr("AUDIT: shell missing")
		quit(3)
		return
	_shell.set("_sidebar_visible", _sidebar)
	var sidebar: Control = _shell.get("_sidebar") as Control
	if sidebar != null:
		sidebar.visible = _sidebar
	var split: HSplitContainer = _shell.get("_sidebar_split") as HSplitContainer
	if split != null and _sidebar:
		split.split_offset = int(_shell.get("_sidebar_width"))
	print("AUDIT boot theme=%s locale=%s translation_server=%s viewport=%s sidebar=%s" % [
		_theme,
		String(_loc.get("current_locale")),
		TranslationServer.get_locale(),
		str(_viewport.size),
		str(_sidebar),
	])
	_report_lines.append("theme=%s locale=%s viewport=%s sidebar=%s" % [
		_theme, String(_loc.get("current_locale")), str(_viewport.size), str(_sidebar)])


func _screen(route: String) -> Node:
	var screens: Dictionary = _shell.get("_screens")
	return screens.get(route, null) as Node


func _capture(label: String) -> void:
	RenderingServer.force_draw()
	var img := _viewport.get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, label]
	var err := img.save_png(path)
	print("AUDIT shot %-24s %s err=%d" % [label, str(img.get_size()), err])
	_shots += 1
	var route := String(_nav.call("current_route"))
	var screen: Control = _shell.get("_current") as Control
	if screen != null:
		_inspect(label, route, screen)


func _inspect(label: String, route: String, screen: Control) -> void:
	var line := "== %s route=%s screen=%s" % [label, route, str(screen.size)]
	_report_lines.append(line)
	if not screen.is_visible_in_tree():
		_issues.append("%s: screen not visible in tree" % label)
	if screen.size.x < 2.0 or screen.size.y < 2.0:
		_issues.append("%s: screen size is %s" % [label, str(screen.size)])
	var page := screen.get_child(0) as Control
	if page == null:
		_issues.append("%s: no page child" % label)
		return
	if absf(page.size.x - screen.size.x) > 1.5 or absf(page.size.y - screen.size.y) > 1.5:
		_issues.append("%s: page %s does not fill screen %s" % [label, str(page.size), str(screen.size)])
	var labels := 0
	var buttons := 0
	var zero_controls := 0
	var clipped := 0
	var out_of_bounds := 0
	var screen_rect := screen.get_global_rect()
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		if _inside_scroll(control):
			continue
		if control is Label:
			labels += 1
			var label_control := control as Label
			if label_control.autowrap_mode == TextServer.AUTOWRAP_OFF \
					and not label_control.clip_text \
					and label_control.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				var minimum := label_control.get_minimum_size()
				if minimum.x > label_control.size.x + 2.0:
					clipped += 1
					_report_lines.append("  clipped label '%s' size=%s min=%s" % [
						label_control.text.left(50), str(label_control.size), str(minimum)])
		if control is BaseButton or control is LineEdit or control is OptionButton \
				or control is HSlider or control is SpinBox:
			buttons += 1
			if control.size.x < 2.0 or control.size.y < 2.0:
				zero_controls += 1
				_report_lines.append("  zero-size interactive %s '%s' size=%s" % [
					control.get_class(), _control_text(control), str(control.size)])
		var rect := control.get_global_rect()
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		if rect.position.x < screen_rect.position.x - 2.0 \
				or rect.position.y < screen_rect.position.y - 2.0 \
				or rect.end.x > screen_rect.end.x + 2.0 \
				or rect.end.y > screen_rect.end.y + 2.0:
			out_of_bounds += 1
			if out_of_bounds <= 8:
				_report_lines.append("  outside screen %s '%s' rect=%s screen=%s" % [
					control.get_class(), _control_text(control), str(rect), str(screen_rect)])
	if clipped > 0:
		_issues.append("%s: %d clipped labels" % [label, clipped])
	if zero_controls > 0:
		_issues.append("%s: %d zero-size interactive controls" % [label, zero_controls])
	if out_of_bounds > 0:
		_issues.append("%s: %d controls outside screen" % [label, out_of_bounds])
	_report_lines.append("  labels=%d interactive=%d clipped=%d outside=%d" % [labels, buttons, clipped, out_of_bounds])
	print("AUDIT inspect %-24s labels=%d interactive=%d clipped=%d outside=%d" % [label, labels, buttons, clipped, out_of_bounds])


func _control_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text.left(40)
	if control is BaseButton:
		return (control as BaseButton).text.left(40)
	if control is LineEdit:
		return (control as LineEdit).text.left(40)
	return String(control.name)


func _inside_scroll(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _finish() -> void:
	var missing: PackedStringArray = _loc.call("missing_keys")
	var path := "%s/report.txt" % _out_dir
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_line("UI AUDIT %s" % Time.get_datetime_string_from_system())
		out.store_line("theme=%s size=%s sidebar=%s" % [_theme, str(_size), str(_sidebar)])
		for line: String in _report_lines:
			out.store_line(line)
		out.store_line("")
		out.store_line("MISSING KEYS: %d" % missing.size())
		for key: String in missing:
			out.store_line("  " + key)
		out.store_line("")
		out.store_line("ISSUES: %d" % _issues.size())
		for issue: String in _issues:
			out.store_line("  " + issue)
		out.close()
	print("AUDIT finished shots=%d issues=%d missing=%d report=%s" % [
		_shots, _issues.size(), missing.size(), path])
	quit(0)


func _noop() -> void:
	pass
