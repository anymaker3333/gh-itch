extends Node
## Central, data-driven game catalog (autoload `Catalog`).
##
## The catalog is loaded from `res://data/catalog/games.json`; no game is
## hardcoded in UI code. Adding a game means adding a JSON record (and its
## translation keys + artwork) - navigation, search, filters and the details
## screen pick it up automatically.

signal catalog_loaded(count: int)
signal edition_registry_loaded(registry_id: String, count: int)

const CATALOG_PATH: String = "res://data/catalog/games.json"
const SETS_DIR: String = "res://data/catalog/"

enum SortKey { CATALOG_ORDER = 0, NAME = 1, PLAYERS = 2, RECENT = 3, COMPLEXITY = 4, PLAYTIME = 5 }

var _games: Array[GameEntry] = []
var _by_id: Dictionary = {}
var _edition_registries: Dictionary = {}  # registry id -> Array[ExpansionSet]
var _categories: PackedStringArray = PackedStringArray()
var loaded: bool = false


func _ready() -> void:
	load_catalog()


# ------------------------------------------------------------------- loading

func load_catalog() -> bool:
	_games.clear()
	_by_id.clear()
	var data := _read_json(CATALOG_PATH)
	if data.is_empty():
		Log.error("Catalog: could not read game catalog", {"path": CATALOG_PATH})
		return false
	var raw_games: Variant = data.get("games", [])
	if not (raw_games is Array) or (raw_games as Array).is_empty():
		Log.error("Catalog: catalog contains no games", {"path": CATALOG_PATH})
		return false
	var index := 0
	for item: Variant in raw_games:
		var entry := GameEntry.from_dict(item, index)
		if entry == null:
			continue
		if _by_id.has(entry.id):
			Log.error("Catalog: duplicate game id ignored", {"id": entry.id})
			continue
		_games.append(entry)
		_by_id[entry.id] = entry
		if not _categories.has(entry.category):
			_categories.append(entry.category)
		index += 1
	_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool: return a.order < b.order)
	for entry: GameEntry in _games:
		if entry.has_editions:
			load_edition_registry(entry.edition_registry)
	loaded = true
	Log.info("Catalog: loaded", {"games": _games.size(), "categories": _categories.size()})
	catalog_loaded.emit(_games.size())
	return true


func load_edition_registry(registry_id: String) -> Array[ExpansionSet]:
	if registry_id.is_empty():
		return []
	if _edition_registries.has(registry_id):
		return _edition_registries[registry_id]
	var path := "%s%s.json" % [SETS_DIR, registry_id]
	var data := _read_json(path)
	var sets: Array[ExpansionSet] = []
	var raw: Variant = data.get("sets", [])
	if raw is Array:
		for item: Variant in raw:
			var set := ExpansionSet.from_dict(item)
			if not set.id.is_empty():
				sets.append(set)
	_edition_registries[registry_id] = sets
	Log.info("Catalog: edition registry loaded", {"registry": registry_id, "sets": sets.size()})
	edition_registry_loaded.emit(registry_id, sets.size())
	return sets


func registry_path(registry_id: String) -> String:
	return "%s%s.json" % [SETS_DIR, registry_id]


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		Log.error("Catalog: file not found", {"path": path})
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		Log.error("Catalog: JSON error", {"path": path, "line": parser.get_error_line(), "msg": parser.get_error_message()})
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


# --------------------------------------------------------------- basic access

func games() -> Array[GameEntry]:
	return _games


func count() -> int:
	return _games.size()


func get_entry(id: String) -> GameEntry:
	return _by_id.get(id, null)


func exists(id: String) -> bool:
	return _by_id.has(id)


func categories() -> PackedStringArray:
	return _categories


func order_of(id: String) -> int:
	var entry := get_entry(id)
	return entry.order if entry != null else 999


# ------------------------------------------------------------ filtering API

## `filters` keys: `search` (String), `categories` (Array[String]),
## `players` (int, 0 = any), `statuses` (Array[int]), `modes` (Array[String]),
## `favorites_only` (bool), `recent_only` (bool), `playable_only` (bool).
func query(filters: Dictionary = {}, sort_key: SortKey = SortKey.CATALOG_ORDER, ascending: bool = true) -> Array[GameEntry]:
	var search := String(filters.get("search", ""))
	var cats: Array = filters.get("categories", [])
	var players := int(filters.get("players", 0))
	var statuses: Array = filters.get("statuses", [])
	var modes: Array = filters.get("modes", [])
	var favorites_only := bool(filters.get("favorites_only", false))
	var recent_only := bool(filters.get("recent_only", false))
	var playable_only := bool(filters.get("playable_only", false))

	var result: Array[GameEntry] = []
	for entry: GameEntry in _games:
		if not search.strip_edges().is_empty() and not entry.matches_query(search):
			continue
		if not cats.is_empty() and not cats.has(entry.category):
			continue
		if players > 0 and not entry.supports_players(players):
			continue
		if not statuses.is_empty() and not statuses.has(int(entry.status)):
			continue
		if playable_only and entry.status == GameEntry.Status.PLANNED:
			continue
		if not modes.is_empty():
			var matched := false
			for mode: String in entry.modes:
				if modes.has(mode):
					matched = true
					break
			if not matched:
				continue
		if favorites_only and not Prefs.is_favorite(entry.id):
			continue
		if recent_only and not _seen_recently(entry.id):
			continue
		result.append(entry)

	result.sort_custom(func(a: GameEntry, b: GameEntry) -> bool: return _compare(a, b, sort_key, ascending))
	return result


func _compare(a: GameEntry, b: GameEntry, sort_key: SortKey, ascending: bool) -> bool:
	var less := false
	match sort_key:
		SortKey.NAME:
			less = a.display_name().naturalnocasecmp_to(b.display_name()) < 0
		SortKey.PLAYERS:
			less = a.min_players < b.min_players if a.min_players != b.min_players else a.display_name() < b.display_name()
		SortKey.RECENT:
			var ra := _recent_rank(a.id)
			var rb := _recent_rank(b.id)
			if ra != rb:
				less = ra < rb
			else:
				less = a.display_name().naturalnocasecmp_to(b.display_name()) < 0
		SortKey.COMPLEXITY:
			less = a.complexity < b.complexity if a.complexity != b.complexity else a.display_name() < b.display_name()
		SortKey.PLAYTIME:
			less = a.estimated_minutes < b.estimated_minutes
		_:
			less = a.order < b.order
	if not ascending:
		return not less and a.id != b.id
	return less


func _recent_rank(id: String) -> int:
	var index := 0
	for item: Variant in Prefs.recent_entries():
		if item is Dictionary and String(item.get("id", "")) == id:
			return index
		index += 1
	return 1000 + order_of(id)


func _seen_recently(id: String) -> bool:
	for item: Variant in Prefs.recent_entries():
		if item is Dictionary and String(item.get("id", "")) == id:
			return true
	return false


func recently_played() -> Array[GameEntry]:
	var out: Array[GameEntry] = []
	for item: Variant in Prefs.recent_entries():
		if item is Dictionary:
			var entry := get_entry(String(item.get("id", "")))
			if entry != null:
				out.append(entry)
	return out


func favorites() -> Array[GameEntry]:
	var out: Array[GameEntry] = []
	for entry: GameEntry in _games:
		if Prefs.is_favorite(entry.id):
			out.append(entry)
	return out


func play_count(id: String) -> int:
	for item: Variant in Prefs.recent_entries():
		if item is Dictionary and String(item.get("id", "")) == id:
			return int(item.get("plays", 0))
	return 0


# --------------------------------------------------------- edition registries

func edition_sets(registry_id: String) -> Array[ExpansionSet]:
	return load_edition_registry(registry_id)


func edition_set(registry_id: String, set_id: String) -> ExpansionSet:
	for set: ExpansionSet in edition_sets(registry_id):
		if set.id == set_id:
			return set
	return null


## Validates a selection: forces mandatory sets in, drops unknown set ids and
## removes sets that conflict with an already selected one.
func validate_selection(registry_id: String, selection: Array) -> Dictionary:
	var sets := edition_sets(registry_id)
	var known: Dictionary = {}
	for set: ExpansionSet in sets:
		known[set.id] = set
	var cleaned: Array = []
	var rejected: Array = []
	for item: Variant in selection:
		var id := String(item)
		if not known.has(id):
			rejected.append({"id": id, "reason": "unknown"})
			continue
		if cleaned.has(id):
			continue
		var set: ExpansionSet = known[id]
		var blocked := ""
		for other: Variant in cleaned:
			var other_set: ExpansionSet = known[String(other)]
			if set.conflicts_with_set(other_set.id) or other_set.conflicts_with_set(set.id):
				blocked = other_set.id
				break
		if not blocked.is_empty():
			rejected.append({"id": id, "reason": "conflict", "with": blocked})
			continue
		if not set.content_ready:
			rejected.append({"id": id, "reason": "content_pending"})
			continue
		cleaned.append(id)
	for set: ExpansionSet in sets:
		if set.required and not cleaned.has(set.id):
			cleaned.push_front(set.id)
	return {"selected": cleaned, "rejected": rejected}
