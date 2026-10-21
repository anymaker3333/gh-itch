extends RefCounted
## Route walker for the screen smoke, loaded at runtime by tools/screen_smoke.gd
## so that the autoload singletons are available.
##
## Boots the real shell, drives the real router through every screen route and
## checks that each route produced a visible screen in the tree. The boot smoke
## only proves that the library screen builds; screens are instantiated lazily,
## so this is the guard for the details, setup, lobby, online, settings,
## diagnostics and about screens. tools/run_screen_smoke.sh additionally fails
## on any SCRIPT ERROR printed while walking.

const WARMUP_FRAMES: int = 4
const SETTLE_FRAMES: int = 20
const CARD_SCRIPT_PATH: String = "res://scripts/ui/components/game_card.gd"

var _shell: Node = null
var _routes: Array[Dictionary] = []
var _index: int = 0
var _visited: int = 0
var _skipped: Array[String] = []
var _failed: Array[String] = []
var _warmup: int = 0
var _settle: int = 0
var _done: bool = false
var _code: int = 0


func setup(scene_root: Node) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("screen smoke: res://scenes/main.tscn did not load")
		_done = true
		_code = 1
		return
	var main_node := packed.instantiate()
	scene_root.add_child(main_node)
	# Main builds the shell synchronously in _ready(); grab it from there.
	_shell = main_node.get("shell") as Node
	if _shell == null:
		printerr("screen smoke: the shell did not come up")
		_done = true
		_code = 1
		return
	_build_routes()
	print("screen smoke: visiting %d routes" % _routes.size())


func step() -> bool:
	if _done:
		return true
	if _shell == null:
		_done = true
		_code = 1
		return true
	_warmup += 1
	if _warmup < WARMUP_FRAMES:
		return false
	if _index < _routes.size():
		_visit(_routes[_index])
		_index += 1
		return false
	_settle += 1
	if _settle < SETTLE_FRAMES:
		return false
	_finish()
	return _done


func exit_code() -> int:
	return _code


func _build_routes() -> void:
	_routes = [
		{"route": Nav.ROUTE_LIBRARY, "params": {}},
		{"route": Nav.ROUTE_ALL_GAMES, "params": {}},
		{"route": Nav.ROUTE_FAVORITES, "params": {}},
		{"route": Nav.ROUTE_RECENT, "params": {}},
		{"route": Nav.ROUTE_GAME_DETAILS, "params": {"game_id": "chess"}},
		{"route": Nav.ROUTE_GAME_DETAILS, "params": {"game_id": "star_realms"}},
		{"route": Nav.ROUTE_GAME_SETUP, "params": {"game_id": "chess"}},
		{"route": Nav.ROUTE_STAR_REALMS_SETS, "params": {"game_id": "star_realms"}},
		{"route": Nav.ROUTE_SETTINGS, "params": {}},
		{"route": Nav.ROUTE_DISPLAY_SETTINGS, "params": {}},
		{"route": Nav.ROUTE_AUDIO_SETTINGS, "params": {}},
		{"route": Nav.ROUTE_LANGUAGE_SETTINGS, "params": {}},
		{"route": Nav.ROUTE_ACCESSIBILITY, "params": {}},
		{"route": Nav.ROUTE_DIAGNOSTICS, "params": {}},
		{"route": Nav.ROUTE_ABOUT, "params": {}},
		{"route": Nav.ROUTE_ONLINE, "params": {}},
		{"route": Nav.ROUTE_LOBBY, "params": {}},
		{"route": Nav.ROUTE_GAME, "params": {}},
	]


func _route_script_path(route: String) -> String:
	var script := _shell.get_script() as GDScript
	if script == null:
		return ""
	var table: Dictionary = script.get_script_constant_map().get("ROUTE_SCREENS", {})
	return String(table.get(route, ""))


func _visit(entry: Dictionary) -> void:
	var route := String(entry.get("route", ""))
	var params: Dictionary = entry.get("params", {})
	var path := _route_script_path(route)
	if path.is_empty() or not ResourceLoader.exists(path):
		_skipped.append(route)
		print("SKIP  %-20s (screen script not present yet)" % route)
		return
	var screens: Dictionary = _shell.get("_screens")
	# The game route intentionally redirects to the library without a session.
	# Start a real hotseat match so the walker exercises the game screen itself.
	if route == Nav.ROUTE_GAME and Session.current == null:
		Session.configure("chess", 2)
		if Session.start_local_session() == null:
			_failed.append(route)
			print("FAIL  %-20s could not create a local match" % route)
			return
	Nav.go(route, params)
	var screen := screens.get(route, null) as Node
	if screen == null or not is_instance_valid(screen):
		_failed.append(route)
		print("FAIL  %-20s no screen was instantiated" % route)
		return
	if not screen.is_inside_tree():
		_failed.append(route)
		print("FAIL  %-20s screen is not in the tree" % route)
		return
	if not screen.visible:
		_failed.append(route)
		print("FAIL  %-20s screen is not visible" % route)
		return
	# The library is the entry screen: an empty or collapsed grid is a release
	# blocker that a simple "screen mounted" check cannot see (the page used to
	# keep its minimum size while both the card list and the scroll area were
	# clipped away).
	if route == Nav.ROUTE_LIBRARY or route == Nav.ROUTE_ALL_GAMES:
		if not _check_library_content(route, screen as Control):
			return
	_visited += 1
	print("OK    %-20s" % route)


## Guards the library page: it must fill the screen and actually contain the
## catalog's game cards, clipped into view.
func _check_library_content(route: String, screen: Control) -> bool:
	var page := screen.get_child(0) as Control
	if page == null:
		_failed.append(route)
		print("FAIL  %-20s library page container is missing" % route)
		return false
	if page.size.y < screen.size.y - 1.0 or page.size.x < screen.size.x - 1.0:
		_failed.append(route)
		print("FAIL  %-20s library page does not fill the screen (page=%s screen=%s)" % [route, page.size, screen.size])
		return false
	var card_script := load(CARD_SCRIPT_PATH) as GDScript
	var cards := 0
	var card_visible := false
	var screen_rect := screen.get_global_rect()
	for child: Node in screen.find_children("*", "Button", true, false):
		if card_script == null or child.get_script() != card_script:
			continue
		cards += 1
		var card := child as Control
		if card.is_visible_in_tree() and screen_rect.intersects(card.get_global_rect()):
			card_visible = true
	if cards < Catalog.count():
		_failed.append(route)
		print("FAIL  %-20s library shows %d of %d cards" % [route, cards, Catalog.count()])
		return false
	if not card_visible:
		_failed.append(route)
		print("FAIL  %-20s no library card intersects the visible screen" % route)
		return false
	return true


func _finish() -> void:
	_done = true
	if _failed.is_empty():
		print("SCREEN SMOKE OK  visited=%d skipped=%d failed=0" % [_visited, _skipped.size()])
		_code = 0
		return
	print("SCREEN SMOKE FAILED  visited=%d skipped=%d failed=%d" % [_visited, _skipped.size(), _failed.size()])
	print("failed routes: %s" % ", ".join(PackedStringArray(_failed)))
	_code = 1
