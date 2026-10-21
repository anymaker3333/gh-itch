extends Node
## Persistent user preferences (autoload `Prefs`).
##
## Thin, typed layer over a `ConfigFile` stored at `user://gamehub_settings.cfg`.
## Every write is validated, cached, persisted (debounced) and broadcast so that
## screens can react to changes without polling.

signal setting_changed(path: String, value: Variant)
signal settings_saved()
signal settings_reset()

const SETTINGS_PATH: String = "user://gamehub_settings.cfg"
const SAVE_DEBOUNCE_SEC: float = 0.6

## Default values are also the schema used for validation and reset.
const DEFAULTS: Dictionary = {
	"general/locale": "en",
	"general/ui_scale": 1.0,
	"general/confirm_on_exit": true,
	"general/show_development_titles": true,
	"general/reduced_motion": false,
	"general/sidebar_visible": true,
	"general/sidebar_width": 272,
	"general/log_visible": true,
	"general/log_width": 340,
	"display/mode": 0,
	"display/width": 1600,
	"display/height": 900,
	"display/screen": 0,
	"display/vsync": 1,
	"display/max_fps": 0,
	"audio/master_volume": 0.85,
	"audio/sfx_volume": 0.8,
	"audio/music_volume": 0.5,
	"audio/mute": false,
	"profile/display_name": "",
	"appearance/theme_id": "default",
	"library/favorites": [],
	"library/recent": [],
	"star_realms/selected_sets": ["sr_core"],
	"star_realms/expansions_enabled": false,
	"steam/app_id": 480,
	"steam/enabled": true,
	"steam/use_steam_transport": true,
	"steam/allow_local_test_transport": true,
	"net/protocol_version": 1,
}

enum WindowMode { WINDOWED = 0, FULLSCREEN = 1, BORDERLESS_FULLSCREEN = 2 }

var _config: ConfigFile = ConfigFile.new()
var _save_timer: Timer
var _dirty: bool = false


func _ready() -> void:
	_load()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_now()


# ---------------------------------------------------------------- public API

func get_value(path: String, fallback: Variant = null) -> Variant:
	if _config.has_section_key(_section(path), _key(path)):
		return _config.get_value(_section(path), _key(path))
	if DEFAULTS.has(path):
		return DEFAULTS[path]
	return fallback


func set_value(path: String, value: Variant) -> void:
	var sanitized: Variant = _sanitize(path, value)
	if _config.has_section_key(_section(path), _key(path)):
		var current: Variant = _config.get_value(_section(path), _key(path))
		if _values_equal(current, sanitized):
			return
	_config.set_value(_section(path), _key(path), sanitized)
	_dirty = true
	if _save_timer != null:
		_save_timer.start()
	setting_changed.emit(path, sanitized)


func has(path: String) -> bool:
	return _config.has_section_key(_section(path), _key(path))


func save_now() -> void:
	if not _dirty:
		return
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		Log.error("Prefs: failed to save settings", {"error": err})
	else:
		_dirty = false
		settings_saved.emit()


func reset_to_defaults(section_filter: String = "") -> void:
	var kept: Dictionary = {}
	if not section_filter.is_empty():
		for path: String in DEFAULTS:
			if not path.begins_with(section_filter):
				kept[path] = get_value(path)
	_config = ConfigFile.new()
	for path: String in DEFAULTS:
		_config.set_value(_section(path), _key(path), DEFAULTS[path])
	for path: String in kept:
		_config.set_value(_section(path), _key(path), kept[path])
	_dirty = true
	save_now()
	settings_reset.emit()
	# Notify every consumer about the restored values.
	for path: String in DEFAULTS:
		setting_changed.emit(path, _config.get_value(_section(path), _key(path)))


# ------------------------------------------------------------ typed helpers

func locale() -> String:
	return String(get_value("general/locale", "en"))


func ui_scale() -> float:
	return float(get_value("general/ui_scale", 1.0))


func window_mode() -> int:
	return int(get_value("display/mode", 0))


func window_width() -> int:
	return int(get_value("display/width", 1600))


func window_height() -> int:
	return int(get_value("display/height", 900))


func screen_index() -> int:
	return int(get_value("display/screen", 0))


func favorites() -> Array:
	var value: Variant = get_value("library/favorites", [])
	return value if value is Array else []


func is_favorite(game_id: String) -> bool:
	return favorites().has(game_id)


func toggle_favorite(game_id: String) -> bool:
	var list: Array = favorites().duplicate()
	var now_favorite := false
	if list.has(game_id):
		list.erase(game_id)
	else:
		list.append(game_id)
		now_favorite = true
	set_value("library/favorites", list)
	return now_favorite


func recent_entries() -> Array:
	var value: Variant = get_value("library/recent", [])
	return value if value is Array else []


func record_recent(game_id: String) -> void:
	var list: Array = []
	for item: Variant in recent_entries():
		if item is Dictionary and String(item.get("id", "")) != game_id:
			list.append(item)
		else:
			# Keep previous play count for the same game.
			if item is Dictionary:
				list.append({"id": game_id, "plays": int(item.get("plays", 0)), "ts": 0})
	var head: Dictionary = {"id": game_id, "plays": 0, "ts": 0}
	# Re-add the game at the front with an incremented play counter.
	for item: Variant in list:
		if item is Dictionary and String(item.get("id", "")) == game_id:
			head = item
			list.erase(item)
			break
	head["ts"] = int(Time.get_unix_time_from_system())
	head["plays"] = int(head.get("plays", 0)) + 1
	list.push_front(head)
	while list.size() > 30:
		list.pop_back()
	set_value("library/recent", list)


func clear_recent() -> void:
	set_value("library/recent", [])


func selected_star_realms_sets() -> Array:
	var value: Variant = get_value("star_realms/selected_sets", ["sr_core"])
	return value if value is Array else ["sr_core"]


func set_star_realms_sets(sets: Array) -> void:
	var cleaned: Array = []
	for entry: Variant in sets:
		var id := String(entry)
		if not id.is_empty() and not cleaned.has(id):
			cleaned.append(id)
	if not cleaned.has("sr_core"):
		cleaned.push_front("sr_core")
	set_value("star_realms/selected_sets", cleaned)


func profile_name() -> String:
	var name_value := String(get_value("profile/display_name", ""))
	if name_value.strip_edges().is_empty():
		return _default_profile_name()
	return name_value


func _default_profile_name() -> String:
	var loc := get_node_or_null("/root/Loc")
	if loc != null:
		return String(loc.call("t", "player.default"))
	return "Player"


# ---------------------------------------------------------------- internals

func _load() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		# Missing or corrupt file: fall back to defaults (also handles upgrades).
		if err != ERR_FILE_NOT_FOUND:
			Log.warn("Prefs: settings file unreadable, regenerating defaults", {"error": err})
		_config = ConfigFile.new()
		for path: String in DEFAULTS:
			_config.set_value(_section(path), _key(path), DEFAULTS[path])
		_dirty = true
		save_now()
	else:
		_migrate()
		Log.info("Prefs: loaded settings", {"path": SETTINGS_PATH})


## Fills in missing keys and repairs invalid values (schema evolution safety net).
func _migrate() -> void:
	var changed := false
	for path: String in DEFAULTS:
		if not _config.has_section_key(_section(path), _key(path)):
			_config.set_value(_section(path), _key(path), DEFAULTS[path])
			changed = true
			continue
		var value: Variant = _config.get_value(_section(path), _key(path))
		var sanitized: Variant = _sanitize(path, value)
		if not _values_equal(value, sanitized):
			_config.set_value(_section(path), _key(path), sanitized)
			changed = true
	# Unknown keys are preserved but never trusted.
	for section: String in _config.get_sections():
		for key: String in _config.get_section_keys(section):
			var path := "%s/%s" % [section, key]
			if not DEFAULTS.has(path):
				Log.debug("Prefs: unknown setting kept as-is", {"path": path})
	if changed:
		_dirty = true
		save_now()


func _sanitize(path: String, value: Variant) -> Variant:
	match path:
		"general/locale":
			return String(value) if value is String else "en"
		"general/ui_scale":
			return clampf(float(value), 0.75, 1.75) if value is float or value is int else 1.0
		"display/mode":
			return clampi(int(value), 0, 2)
		"display/width", "display/height":
			return clampi(int(value), 640, 16384)
		"display/screen":
			return clampi(int(value), 0, maxi(0, DisplayServer.get_screen_count() - 1))
		"display/vsync":
			return clampi(int(value), 0, 3)
		"display/max_fps":
			return clampi(int(value), 0, 480)
		"audio/master_volume", "audio/sfx_volume", "audio/music_volume":
			return clampf(float(value), 0.0, 1.0)
		"library/favorites":
			return _string_array(value)
		"library/recent":
			var list: Array = []
			if value is Array:
				for item: Variant in value:
					if item is Dictionary and not String(item.get("id", "")).is_empty():
						list.append({
							"id": String(item.get("id", "")),
							"plays": int(item.get("plays", 0)),
							"ts": int(item.get("ts", 0)),
						})
			return list
		"star_realms/selected_sets":
			var sets := _string_array(value)
			if not sets.has("sr_core"):
				sets.push_front("sr_core")
			return sets
		"steam/app_id":
			return clampi(int(value), 0, 0x7FFFFFFF)
		"profile/display_name":
			return String(value).substr(0, 32)
		"appearance/theme_id":
			return String(value) if not String(value).is_empty() else "default"
		"net/protocol_version":
			return maxi(1, int(value))
		_:
			return value


func _string_array(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item: Variant in value:
			var text := String(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out


func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i: int in range(a.size()):
			if not _values_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		return JSON.stringify(a) == JSON.stringify(b)
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _section(path: String) -> String:
	var slash := path.find("/")
	return path.substr(0, slash) if slash >= 0 else path


func _key(path: String) -> String:
	var slash := path.find("/")
	return path.substr(slash + 1) if slash >= 0 else path
