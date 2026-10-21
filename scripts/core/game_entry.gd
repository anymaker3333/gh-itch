class_name GameEntry
extends RefCounted
## Immutable catalog record for one game.
##
## Everything user-visible is stored as a translation key so the catalog stays
## language neutral; presentation code resolves keys through [Loc].

## Implementation status. A game only becomes `PLAYABLE` after its documented
## local acceptance criteria pass (see docs/GAME_CATALOG.md).
enum Status { PLANNED = 0, IN_DEVELOPMENT = 1, PARTIAL = 2, PLAYABLE = 3 }

## Multiplayer maturity. `VERIFIED` requires a real networked test run.
enum OnlineStatus { NOT_IMPLEMENTED = 0, IMPLEMENTED = 1, VERIFIED = 2 }

var id: String = ""
var name_key: String = ""
var desc_key: String = ""
var category: String = "cards"
var tags: PackedStringArray = PackedStringArray()
var aliases: PackedStringArray = PackedStringArray()
var min_players: int = 2
var max_players: int = 2
var art_path: String = ""
var accent: Color = Color.WHITE
var status: Status = Status.IN_DEVELOPMENT
var online_status: OnlineStatus = OnlineStatus.NOT_IMPLEMENTED
var modes: PackedStringArray = PackedStringArray()
var estimated_minutes: int = 30
var complexity: int = 2
var ruleset_version: String = "1.0"
var has_editions: bool = false
var edition_registry: String = ""
var order: int = 0
var release_tag: String = ""
var notes_key: String = ""


static func from_dict(data: Dictionary, index: int) -> GameEntry:
	var entry := new()
	entry.id = VariantUtil.as_string(data.get("id", ""), "")
	if entry.id.is_empty():
		push_error("GameEntry: catalog record without id")
		return null
	entry.name_key = VariantUtil.as_string(data.get("name_key", "game.%s.name" % entry.id), "game.%s.name" % entry.id)
	entry.desc_key = VariantUtil.as_string(data.get("desc_key", "game.%s.desc" % entry.id), "game.%s.desc" % entry.id)
	entry.category = VariantUtil.as_string(data.get("category", "cards"), "cards")
	entry.tags = _to_string_array(data.get("tags", []))
	entry.aliases = _to_string_array(data.get("aliases", []))
	entry.min_players = VariantUtil.as_int(data.get("min_players", 2), 2)
	entry.max_players = VariantUtil.as_int(data.get("max_players", 2), 2)
	entry.art_path = VariantUtil.as_string(data.get("art", "res://assets/art/%s.svg" % entry.id), "res://assets/art/%s.svg" % entry.id)
	entry.accent = Color(VariantUtil.as_string(data.get("accent", ""), "#4ea1ff"))
	entry.status = _to_status(VariantUtil.as_string(data.get("status", "in_development"), "in_development"))
	entry.online_status = _to_online_status(VariantUtil.as_string(data.get("online_status", "not_implemented"), "not_implemented"))
	entry.modes = _to_string_array(data.get("modes", ["hotseat"]))
	entry.estimated_minutes = VariantUtil.as_int(data.get("minutes", 30), 30)
	entry.complexity = VariantUtil.as_int(data.get("complexity", 2), 2)
	entry.ruleset_version = VariantUtil.as_string(data.get("ruleset_version", "1.0"), "1.0")
	entry.edition_registry = VariantUtil.as_string(data.get("edition_registry", ""), "")
	entry.has_editions = not entry.edition_registry.is_empty()
	entry.order = VariantUtil.as_int(data.get("order", index), index)
	entry.release_tag = VariantUtil.as_string(data.get("release_tag", ""), "")
	entry.notes_key = VariantUtil.as_string(data.get("notes_key", "game.%s.notes" % entry.id), "game.%s.notes" % entry.id)
	return entry


static func _to_string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			out.append(VariantUtil.as_string(item, ""))
	return out


static func _to_status(value: String) -> Status:
	match value:
		"playable":
			return Status.PLAYABLE
		"partial":
			return Status.PARTIAL
		"planned":
			return Status.PLANNED
		_:
			return Status.IN_DEVELOPMENT


static func _to_online_status(value: String) -> OnlineStatus:
	match value:
		"verified":
			return OnlineStatus.VERIFIED
		"implemented":
			return OnlineStatus.IMPLEMENTED
		_:
			return OnlineStatus.NOT_IMPLEMENTED


# ------------------------------------------------------------- presentation

func display_name() -> String:
	return Loc.t(name_key)


func description() -> String:
	return Loc.t(desc_key)


func status_key() -> String:
	match status:
		Status.PLAYABLE:
			return "status.playable"
		Status.PARTIAL:
			return "status.partial"
		Status.PLANNED:
			return "status.planned"
		_:
			return "status.in_development"


func status_text() -> String:
	return Loc.t(status_key())


func online_status_key() -> String:
	match online_status:
		OnlineStatus.VERIFIED:
			return "online_status.verified"
		OnlineStatus.IMPLEMENTED:
			return "online_status.implemented"
		_:
			return "online_status.not_implemented"


func online_status_text() -> String:
	return Loc.t(online_status_key())


func status_color() -> Color:
	match status:
		Status.PLAYABLE:
			return Color("#39d98a")
		Status.PARTIAL:
			return Color("#ffc24b")
		Status.PLANNED:
			return Color("#8c99ad")
		_:
			return Color("#4ea1ff")


func category_text() -> String:
	return Loc.t("category.%s" % category)


func players_text() -> String:
	if min_players == max_players:
		return Loc.tp("library.players_exact", min_players)
	return Loc.tp("library.players_range", max_players, {"min": min_players, "max": max_players})


func minutes_text() -> String:
	return Loc.tp("library.minutes", estimated_minutes)


func modes_text() -> String:
	var parts := PackedStringArray()
	for mode: String in modes:
		parts.append(Loc.t("mode.%s" % mode))
	return ", ".join(parts)


func supports_mode(mode: String) -> bool:
	return modes.has(mode)


func is_playable() -> bool:
	return status == Status.PLAYABLE or status == Status.PARTIAL


func supports_players(count: int) -> bool:
	return count >= min_players and count <= max_players


## Localised aliases plus the localised display name and internal id, used for
## search matching.
func search_terms() -> PackedStringArray:
	var out := PackedStringArray([display_name().to_lower(), id.replace("_", " ")])
	for alias: String in aliases:
		out.append(alias.to_lower())
	return out


func matches_query(query: String) -> bool:
	var needle := query.strip_edges().to_lower()
	if needle.is_empty():
		return true
	for term: String in search_terms():
		if term.contains(needle):
			return true
	return false
