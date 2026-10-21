class_name ScreenBase
extends Control
## Base class for every full-page screen.
##
## The shell instantiates screens, hands them their route parameters through
## [method setup] and asks them to refresh when something global changes (locale,
## preferences, catalog). Screens never navigate directly - they push routes
## through [code]Nav[/code].

## Localised screen title shown in the top bar.
var title_key: String = ""
var subtitle_key: String = ""
var params: Dictionary = {}

## Guards the first layout pass so screens can build lazily.
var _built: bool = false
var _initialised: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(route_params: Dictionary) -> void:
	params = route_params.duplicate(true)
	if not _built:
		_built = true
		build()
		_fit_build_root()
	_initialised = true
	on_enter()


## Screens build one page container and add it directly. A plain Control is not
## a Container, so that child would otherwise keep its minimum size instead of
## filling the screen. Pin the first built child to the full screen rectangle.
func _fit_build_root() -> void:
	if get_child_count() == 0:
		return
	var page := get_child(0) as Control
	if page == null:
		return
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Build the UI tree. Called once per screen instance.
func build() -> void:
	pass


## Refresh dynamic content. Called on enter and whenever global state changes.
func on_enter() -> void:
	pass


func on_exit() -> void:
	pass


## Return true to keep the instance cached when navigating away.
func keep_alive() -> bool:
	return false


func screen_title() -> String:
	return Loc.t(title_key) if not title_key.is_empty() else ""


func screen_subtitle() -> String:
	return Loc.t(subtitle_key) if not subtitle_key.is_empty() else ""


## Called when the locale changed or preferences were written.
func refresh_texts() -> void:
	pass


## A screen may veto the standard "go back" behaviour (e.g. a running match).
func allows_back() -> bool:
	return true


func on_back() -> bool:
	## Return true when the screen handled the back request itself.
	return false


## Convenience navigation helpers.
func go(route: String, route_params: Dictionary = {}) -> void:
	Nav.go(route, route_params)


func go_back() -> void:
	Nav.back()


func is_active_screen() -> bool:
	return visible and is_inside_tree()
