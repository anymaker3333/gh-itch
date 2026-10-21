class_name ExpansionSet
extends RefCounted
## Description of a Star Realms edition / expansion selection.
##
## The registry is data-driven (`data/catalog/star_realms_sets.json`) so that new
## sets can be added without touching catalog or rules code.

var id: String = ""
var name_key: String = ""
var desc_key: String = ""
var kind: String = "expansion"  ## base | expansion | promo
var required: bool = false  ## base edition is always part of a session
var default_enabled: bool = false
var content_ready: bool = false  ## card data actually implemented
var card_pool: String = ""  ## data file with the cards of this set
var depends_on: PackedStringArray = PackedStringArray()
var conflicts_with: PackedStringArray = PackedStringArray()
var min_players: int = 2
var max_players: int = 2
var card_count: int = 0
var implemented_card_count: int = 0
var accreditation: String = ""


static func from_dict(data: Dictionary) -> ExpansionSet:
	var entry := new()
	entry.id = VariantUtil.as_string(data.get("id", ""), "")
	entry.name_key = VariantUtil.as_string(data.get("name_key", "sr.set.%s.name" % entry.id), "sr.set.%s.name" % entry.id)
	entry.desc_key = VariantUtil.as_string(data.get("desc_key", "sr.set.%s.desc" % entry.id), "sr.set.%s.desc" % entry.id)
	entry.kind = VariantUtil.as_string(data.get("kind", "expansion"), "expansion")
	entry.required = bool(data.get("required", false))
	entry.default_enabled = bool(data.get("default_enabled", false))
	entry.content_ready = bool(data.get("content_ready", false))
	entry.card_pool = VariantUtil.as_string(data.get("card_pool", ""), "")
	entry.depends_on = _arr(data.get("depends_on", []))
	entry.conflicts_with = _arr(data.get("conflicts_with", []))
	entry.min_players = VariantUtil.as_int(data.get("min_players", 2), 2)
	entry.max_players = VariantUtil.as_int(data.get("max_players", 2), 2)
	entry.card_count = VariantUtil.as_int(data.get("card_count", 0), 0)
	entry.implemented_card_count = VariantUtil.as_int(data.get("implemented_card_count", 0), 0)
	entry.accreditation = VariantUtil.as_string(data.get("accreditation", ""), "")
	return entry


static func _arr(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			out.append(VariantUtil.as_string(item, ""))
	return out


func display_name() -> String:
	return Loc.t(name_key)


func description() -> String:
	return Loc.t(desc_key)


func is_base() -> bool:
	return kind == "base" or required


func status_key() -> String:
	if content_ready:
		return "sr.set.status_ready"
	return "sr.set.status_data_pending"


func status_text() -> String:
	return Loc.t(status_key())


func status_color() -> Color:
	return Color("#39d98a") if content_ready else Color("#ffc24b")


func conflicts_with_set(other_id: String) -> bool:
	return conflicts_with.has(other_id)


func requires_set(other_id: String) -> bool:
	return depends_on.has(other_id)


func players_text() -> String:
	if min_players == max_players:
		return Loc.tp("library.players_exact", min_players)
	return Loc.t("library.players_range", {"min": min_players, "max": max_players})
