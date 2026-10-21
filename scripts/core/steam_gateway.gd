class_name SteamGateway
extends RefCounted
## Thin, defensive wrapper around the GodotSteam GDExtension singleton.
##
## The extension is a native dependency: it may be missing entirely (no addon
## installed) or only partially compatible with the running engine. All calls go
## through this gateway so that the rest of the project can query availability,
## call methods and connect signals without risking a parse/runtime failure when
## a method is absent. Nothing here simulates Steam - if the extension or the
## Steam client is missing, [member available] is `false` and callers must show a
## degraded state instead of pretending to be online.

const SINGLETON_NAME := "Steam"

var available: bool = false
var extension_version: String = ""
var methods: PackedStringArray = PackedStringArray()
var signals: PackedStringArray = PackedStringArray()

var _steam: Object = null


func _init() -> void:
	if not Engine.has_singleton(SINGLETON_NAME):
		return
	_steam = Engine.get_singleton(SINGLETON_NAME)
	if _steam == null:
		return
	available = true
	methods = _steam.get_method_list().map(func(entry: Dictionary) -> String: return VariantUtil.as_string(entry.get("name", ""), ""))
	signals = _steam.get_signal_list().map(func(entry: Dictionary) -> String: return VariantUtil.as_string(entry.get("name", ""), ""))
	for entry: Dictionary in _steam.get_signal_list():
		if VariantUtil.as_string(entry.get("name", ""), "") == "steam_api_call_completed":
			break
	if _steam.has_method("getSteamVersion"):
		extension_version = "Steamworks %s" % str(_steam.call("getSteamVersion"))
	Log.info("SteamGateway: detected", {
		"available": available,
		"methods": methods.size(),
		"signals": signals.size(),
		"steamworks": extension_version,
	})


func instance() -> Object:
	return _steam


## Note: named `supports` rather than `has_method` so it cannot shadow
## `Object.has_method`, which typed call sites rely on.
func supports(method: String) -> bool:
	return available and methods.has(method)


func supports_signal(signal_name: String) -> bool:
	return available and signals.has(signal_name)


## Calls a GodotSteam method, returning `default` when it is unavailable.
func call_method(method: String, args: Array = [], default: Variant = null) -> Variant:
	if not supports(method):
		Log.error("SteamGateway: method unavailable", {"method": method})
		return default
	return _steam.callv(method, args)


func connect_signal(signal_name: String, callable: Callable) -> bool:
	if not supports_signal(signal_name):
		return false
	if _steam.is_connected(signal_name, callable):
		return true
	var err: int = _steam.connect(signal_name, callable)
	if err != OK:
		Log.error("SteamGateway: could not connect signal", {"signal": signal_name, "error": err})
		return false
	return true


func disconnect_signal(signal_name: String, callable: Callable) -> void:
	if supports_signal(signal_name) and _steam.is_connected(signal_name, callable):
		_steam.disconnect(signal_name, callable)


## Describes why Steam is unavailable, for the UI and docs.
func unavailable_reason() -> String:
	if not Engine.has_singleton(SINGLETON_NAME):
		return "The GodotSteam GDExtension is not installed (addons/godotsteam)."
	return "The GodotSteam singleton could not be created."
