extends Node
## Navigation stack (autoload `Nav`).
##
## Screens are identified by stable route strings. The application shell
## (scripts/ui/app_shell.gd) reacts to the signals and swaps the visible screen,
## optionally with a short transition. Screens never instantiate each other
## directly, which keeps back navigation, parameters and screen lifetime in one
## place.

signal route_changed(route: String, params: Dictionary, previous: String)
signal stack_changed(depth: int)
signal transition_requested(kind: String)

const ROUTE_LIBRARY: String = "library"
const ROUTE_ALL_GAMES: String = "all_games"
const ROUTE_FAVORITES: String = "favorites"
const ROUTE_RECENT: String = "recent"
const ROUTE_SETTINGS: String = "settings"
const ROUTE_DISPLAY_SETTINGS: String = "settings_display"
const ROUTE_AUDIO_SETTINGS: String = "settings_audio"
const ROUTE_LANGUAGE_SETTINGS: String = "settings_language"
const ROUTE_ACCESSIBILITY: String = "settings_accessibility"
const ROUTE_DIAGNOSTICS: String = "diagnostics"
const ROUTE_ABOUT: String = "about"
const ROUTE_ONLINE: String = "online"
const ROUTE_LOBBY: String = "lobby"
const ROUTE_GAME_DETAILS: String = "game_details"
const ROUTE_GAME_SETUP: String = "game_setup"
const ROUTE_STAR_REALMS_SETS: String = "star_realms_sets"
const ROUTE_GAME: String = "game"

const MAX_STACK: int = 24

var _stack: Array[Dictionary] = []
var _pending_transition: String = "none"


func _ready() -> void:
	_stack = [{"route": ROUTE_LIBRARY, "params": {}}]


func current_route() -> String:
	if _stack.is_empty():
		return ROUTE_LIBRARY
	return String(_stack.back().route)


func current_params() -> Dictionary:
	if _stack.is_empty():
		return {}
	return _stack.back().params as Dictionary


func depth() -> int:
	return _stack.size()


func can_go_back() -> bool:
	return _stack.size() > 1


func stack_snapshot() -> Array[Dictionary]:
	return _stack.duplicate(true)


## Navigates to `route`. `mode` is one of `push`, `replace` or `reset`.
func go(route: String, params: Dictionary = {}, mode: String = "push", transition: String = "slide") -> void:
	if route.is_empty():
		Log.error("Nav: empty route requested")
		return
	var previous := current_route()
	match mode:
		"replace":
			if _stack.is_empty():
				_stack.append({"route": route, "params": params})
			else:
				_stack[_stack.size() - 1] = {"route": route, "params": params}
		"reset":
			_stack = [{"route": route, "params": params}]
			transition = "none"
		_:
			if previous == route and _stack.back().params == params:
				return
			_stack.append({"route": route, "params": params})
			while _stack.size() > MAX_STACK:
				_stack.remove_at(0)
	_pending_transition = transition
	Log.info("Nav: route change", {"route": route, "mode": mode, "from": previous})
	stack_changed.emit(_stack.size())
	route_changed.emit(route, params, previous)
	transition_requested.emit(transition)


func back() -> bool:
	if not can_go_back():
		return false
	var previous := current_route()
	_stack.pop_back()
	var route := current_route()
	_pending_transition = "slide_back"
	Log.info("Nav: back", {"route": route, "from": previous})
	stack_changed.emit(_stack.size())
	route_changed.emit(route, current_params(), previous)
	transition_requested.emit("slide_back")
	return true


func replace_top(route: String, params: Dictionary = {}) -> void:
	go(route, params, "replace")


func reset_to(route: String, params: Dictionary = {}) -> void:
	go(route, params, "reset")


## Used by the router to find out whether the stack already contains a route
## (avoids duplicated screens when re-entering, e.g. via a notification).
func contains(route: String) -> bool:
	for frame: Dictionary in _stack:
		if String(frame.route) == route:
			return true
	return false


func transition_kind() -> String:
	return _pending_transition
