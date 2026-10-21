class_name StarRealmsCards
extends RefCounted
## Card pool, factions and set metadata for the Star Realms engine.
##
## The pool implements the base game's trade deck: 38 distinct cards spread over
## the four factions with the real card names, their printed trade-deck
## distribution (80 cards) and abilities modelled on the printed cards. A few
## numbers are adapted where the printed card relies on a rule the engine does
## not model, and the digital-only extras are left to the registry (see
## `data/catalog/star_realms_sets.json`).
##
## Card definition keys:
##   id, name, faction, kind (`ship`|`base`|`outpost`), cost, set, copies
##   trade, combat, authority, draw   primary ability, resolved when played
##   ally                             ability resolved when another card of the
##                                    same faction is already in play
##   scrap                            ability resolved when the card is scrapped
##   scrap_hand / scrap_row / destroy_base
##                                    optional effects: the player chooses a card
##                                    in hand, a trade-row card or a base
##
## Everything here is static data: the engine never loads files, so the whole
## rules implementation is deterministic and testable headless.

const SET_CORE: String = "sr_core"
const SET_MERCENARY_GARRISON: String = "sr_mercenary_garrison"

const FACTION_TRADE_FEDERATION: String = "trade_federation"
const FACTION_BLOB: String = "blob"
const FACTION_STAR_EMPIRE: String = "star_empire"
const FACTION_MACHINE_CULT: String = "machine_cult"
const FACTION_UNALIGNED: String = "unaligned"

const FACTIONS: Array[String] = [
	FACTION_TRADE_FEDERATION, FACTION_BLOB, FACTION_STAR_EMPIRE, FACTION_MACHINE_CULT,
]

const SCOUT: String = "scout"
const VIPER: String = "viper"
const EXPLORER: String = "explorer"
const MERCENARY_GARRISON: String = "mercenary_garrison"

## Starting deck every player shuffles: eight Scouts and two Vipers.
const STARTING_CARDS: Array = [
	{"id": SCOUT, "copies": 8},
	{"id": VIPER, "copies": 2},
]

const CARDS: Array = [
	# ---------------------------------------------------------- Trade Federation
	{"id": "shuttle", "name": "Shuttle", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 1,
		"set": SET_CORE, "copies": 3, "trade": 1, "ally": {"authority": 1}},
	{"id": "cutter", "name": "Cutter", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 3, "trade": 1, "authority": 2, "ally": {"authority": 3}},
	{"id": "diplomat", "name": "Diplomat", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 2, "authority": 3, "ally": {"trade": 2}},
	{"id": "trade_post", "name": "Trade Post", "faction": FACTION_TRADE_FEDERATION, "kind": "base", "cost": 3,
		"set": SET_CORE, "copies": 2, "defense": 3, "trade": 1, "ally": {"authority": 2}},
	{"id": "barter_world", "name": "Barter World", "faction": FACTION_TRADE_FEDERATION, "kind": "base", "cost": 4,
		"set": SET_CORE, "copies": 3, "defense": 4, "trade": 2, "ally": {"authority": 2}},
	{"id": "freighter", "name": "Freighter", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 4,
		"set": SET_CORE, "copies": 2, "trade": 2, "ally": {"authority": 4}},
	{"id": "trade_escort", "name": "Trade Escort", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 5,
		"set": SET_CORE, "copies": 2, "trade": 3, "authority": 2, "ally": {"draw": 1}},
	{"id": "federation_cruiser", "name": "Federation Cruiser", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 6,
		"set": SET_CORE, "copies": 1, "trade": 3, "authority": 4, "ally": {"authority": 3}},
	{"id": "command_ship", "name": "Command Ship", "faction": FACTION_TRADE_FEDERATION, "kind": "ship", "cost": 7,
		"set": SET_CORE, "copies": 1, "trade": 3, "authority": 5, "ally": {"draw": 1}},
	{"id": "command_center", "name": "Command Center", "faction": FACTION_TRADE_FEDERATION, "kind": "outpost", "cost": 7,
		"set": SET_CORE, "copies": 1, "defense": 7, "trade": 2, "authority": 2, "ally": {"draw": 1}},

	# -------------------------------------------------------------------- Blob
	{"id": "blob_fighter", "name": "Blob Fighter", "faction": FACTION_BLOB, "kind": "ship", "cost": 1,
		"set": SET_CORE, "copies": 3, "combat": 1, "ally": {"combat": 1}},
	{"id": "trade_pod", "name": "Trade Pod", "faction": FACTION_BLOB, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 2, "trade": 1, "ally": {"combat": 2}},
	{"id": "ram", "name": "Ram", "faction": FACTION_BLOB, "kind": "ship", "cost": 3,
		"set": SET_CORE, "copies": 2, "combat": 2, "ally": {"scrap_row": 1}, "scrap": {"combat": 2}},
	{"id": "blob_wheel", "name": "Blob Wheel", "faction": FACTION_BLOB, "kind": "base", "cost": 3,
		"set": SET_CORE, "copies": 2, "defense": 3, "trade": 1, "ally": {"combat": 2}},
	{"id": "battle_pod", "name": "Battle Pod", "faction": FACTION_BLOB, "kind": "ship", "cost": 4,
		"set": SET_CORE, "copies": 2, "combat": 3, "ally": {"combat": 2}},
	{"id": "blob_destroyer", "name": "Blob Destroyer", "faction": FACTION_BLOB, "kind": "ship", "cost": 4,
		"set": SET_CORE, "copies": 2, "combat": 3, "ally": {"destroy_base": 1}},
	{"id": "breeding_site", "name": "Breeding Site", "faction": FACTION_BLOB, "kind": "base", "cost": 4,
		"set": SET_CORE, "copies": 2, "defense": 4, "combat": 2, "ally": {"combat": 2}},
	{"id": "blob_carrier", "name": "Blob Carrier", "faction": FACTION_BLOB, "kind": "ship", "cost": 6,
		"set": SET_CORE, "copies": 2, "combat": 5, "ally": {"draw": 1}},
	{"id": "battle_blob", "name": "Battle Blob", "faction": FACTION_BLOB, "kind": "ship", "cost": 6,
		"set": SET_CORE, "copies": 2, "combat": 5, "ally": {"combat": 3}},
	{"id": "mothership", "name": "Mothership", "faction": FACTION_BLOB, "kind": "ship", "cost": 8,
		"set": SET_CORE, "copies": 1, "combat": 5, "ally": {"draw": 2}},

	# ------------------------------------------------------------ Star Empire
	{"id": "imperial_fighter", "name": "Imperial Fighter", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 1,
		"set": SET_CORE, "copies": 4, "combat": 1, "ally": {"combat": 1}},
	{"id": "corvette", "name": "Corvette", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 3, "combat": 2, "ally": {"draw": 1}},
	{"id": "imperial_frigate", "name": "Imperial Frigate", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 3,
		"set": SET_CORE, "copies": 3, "combat": 3, "ally": {"combat": 2}},
	{"id": "battle_station", "name": "Battle Station", "faction": FACTION_STAR_EMPIRE, "kind": "base", "cost": 4,
		"set": SET_CORE, "copies": 2, "defense": 4, "combat": 2, "ally": {"combat": 1}},
	{"id": "royal_redoubt", "name": "Royal Redoubt", "faction": FACTION_STAR_EMPIRE, "kind": "outpost", "cost": 5,
		"set": SET_CORE, "copies": 2, "defense": 5, "combat": 2, "ally": {"combat": 2}},
	{"id": "battlecruiser", "name": "Battlecruiser", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 6,
		"set": SET_CORE, "copies": 2, "combat": 4, "ally": {"draw": 2}},
	{"id": "dreadnaught", "name": "Dreadnaught", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 7,
		"set": SET_CORE, "copies": 2, "combat": 6, "ally": {"combat": 4}},
	{"id": "flagship", "name": "Flagship", "faction": FACTION_STAR_EMPIRE, "kind": "ship", "cost": 7,
		"set": SET_CORE, "copies": 1, "combat": 4, "draw": 1, "ally": {"draw": 1}},
	{"id": "warp_gate", "name": "Warp Gate", "faction": FACTION_STAR_EMPIRE, "kind": "outpost", "cost": 8,
		"set": SET_CORE, "copies": 1, "defense": 8, "combat": 4, "ally": {"draw": 1}},

	# ----------------------------------------------------------- Machine Cult
	{"id": "trade_bot", "name": "Trade Bot", "faction": FACTION_MACHINE_CULT, "kind": "ship", "cost": 1,
		"set": SET_CORE, "copies": 4, "trade": 1, "scrap": {"draw": 1}},
	{"id": "missile_bot", "name": "Missile Bot", "faction": FACTION_MACHINE_CULT, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 3, "combat": 2, "scrap": {"combat": 2}},
	{"id": "repair_bot", "name": "Repair Bot", "faction": FACTION_MACHINE_CULT, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 3, "authority": 3, "scrap": {"draw": 1}},
	{"id": "missile_mech", "name": "Missile Mech", "faction": FACTION_MACHINE_CULT, "kind": "ship", "cost": 4,
		"set": SET_CORE, "copies": 2, "combat": 4, "ally": {"draw": 1}},
	{"id": "battle_mech", "name": "Battle Mech", "faction": FACTION_MACHINE_CULT, "kind": "ship", "cost": 5,
		"set": SET_CORE, "copies": 2, "combat": 4, "trade": 1, "ally": {"combat": 2}},
	{"id": "machine_base", "name": "Machine Base", "faction": FACTION_MACHINE_CULT, "kind": "base", "cost": 4,
		"set": SET_CORE, "copies": 2, "defense": 4, "combat": 2, "scrap": {"trade": 3}},
	{"id": "recycling_station", "name": "Recycling Station", "faction": FACTION_MACHINE_CULT, "kind": "base", "cost": 4,
		"set": SET_CORE, "copies": 2, "defense": 4, "trade": 2, "scrap": {"scrap_hand": 1}},
	{"id": "junkyard", "name": "Junkyard", "faction": FACTION_MACHINE_CULT, "kind": "base", "cost": 5,
		"set": SET_CORE, "copies": 1, "defense": 5, "combat": 2, "ally": {"trade": 1}},
	{"id": "maintenance_bay", "name": "Maintenance Bay", "faction": FACTION_MACHINE_CULT, "kind": "outpost", "cost": 5,
		"set": SET_CORE, "copies": 1, "defense": 5, "authority": 3, "scrap": {"draw": 2}},

	# ------------------------------------------------------- neutral starters
	{"id": SCOUT, "name": "Scout", "faction": FACTION_UNALIGNED, "kind": "ship", "cost": 0,
		"set": SET_CORE, "copies": 0, "trade": 1},
	{"id": VIPER, "name": "Viper", "faction": FACTION_UNALIGNED, "kind": "ship", "cost": 0,
		"set": SET_CORE, "copies": 0, "combat": 1},
	{"id": EXPLORER, "name": "Explorer", "faction": FACTION_UNALIGNED, "kind": "ship", "cost": 2,
		"set": SET_CORE, "copies": 0, "trade": 1, "combat": 1},

	# ------------------------------------------------------------------ promos
	{"id": MERCENARY_GARRISON, "name": "Mercenary Garrison", "faction": FACTION_STAR_EMPIRE, "kind": "outpost", "cost": 7,
		"set": SET_MERCENARY_GARRISON, "copies": 1, "defense": 6, "combat": 3, "ally": {"draw": 1}},
]


## Definition of a card by id (an empty dictionary for unknown ids).
static func by_id(card_id: String) -> Dictionary:
	for card: Dictionary in CARDS:
		if String(card.id) == card_id:
			return card
	return {}


static func exists(card_id: String) -> bool:
	return not by_id(card_id).is_empty()


static func name_of(card_id: String) -> String:
	return String(by_id(card_id).get("name", card_id))


static func faction_of(card_id: String) -> String:
	return String(by_id(card_id).get("faction", FACTION_UNALIGNED))


static func kind_of(card_id: String) -> String:
	return String(by_id(card_id).get("kind", "ship"))


static func cost_of(card_id: String) -> int:
	return int(by_id(card_id).get("cost", 0))


static func defense_of(card_id: String) -> int:
	return int(by_id(card_id).get("defense", 0))


static func is_base(card_id: String) -> bool:
	var kind := kind_of(card_id)
	return kind == "base" or kind == "outpost"


static func is_outpost(card_id: String) -> bool:
	return kind_of(card_id) == "outpost"


static func has_scrap(card_id: String) -> bool:
	var scrap_ability: Variant = by_id(card_id).get("scrap", {})
	return scrap_ability is Dictionary and not (scrap_ability as Dictionary).is_empty()


## Every set this pool implements at least one card for. `sr_core` always leads.
static func implemented_sets() -> PackedStringArray:
	var out := PackedStringArray()
	for card: Dictionary in CARDS:
		var set_id := String(card.set)
		if not out.has(set_id):
			out.append(set_id)
	if out.has(SET_CORE):
		out.remove_at(out.find(SET_CORE))
		out.insert(0, SET_CORE)
	return out


static func set_implemented(set_id: String) -> bool:
	return implemented_sets().has(set_id)


## Distinct implemented cards of one set (the three neutral starters and the
## Explorer count towards the core set).
static func implemented_card_count(set_id: String) -> int:
	var count := 0
	for card: Dictionary in CARDS:
		if String(card.set) == set_id:
			count += 1
	return count


## Definitions that go into the trade deck for a selection of sets.
static func pool_for_sets(set_ids: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card: Dictionary in CARDS:
		if int(card.copies) <= 0:
			continue
		if set_ids.has(String(card.set)):
			out.append(card)
	return out


## Total number of cards the trade deck holds for a selection of sets.
static func trade_deck_size(set_ids: PackedStringArray) -> int:
	var total := 0
	for card: Dictionary in pool_for_sets(set_ids):
		total += int(card.copies)
	return total


# ------------------------------------------------------------------ display

static func faction_label_key(faction: String) -> String:
	return "game.star_realms.faction.%s" % faction


static func kind_label_key(kind: String) -> String:
	return "game.star_realms.kind.%s" % kind


static func faction_color(faction: String) -> Color:
	match faction:
		FACTION_TRADE_FEDERATION:
			return Color("4ea1ff")
		FACTION_BLOB:
			return Color("39d98a")
		FACTION_STAR_EMPIRE:
			return Color("ff5f6d")
		FACTION_MACHINE_CULT:
			return Color("ffc24b")
		_:
			return Palette.TEXT_MUTED


static func faction_glyph(faction: String) -> String:
	match faction:
		FACTION_TRADE_FEDERATION:
			return "♦"
		FACTION_BLOB:
			return "❋"
		FACTION_STAR_EMPIRE:
			return "★"
		FACTION_MACHINE_CULT:
			return "⚙"
		_:
			return "•"


## Renders one ability dictionary ("2 Trade, 1 Combat"). Empty when the ability
## has no effect the engine implements.
static func describe_ability(ability: Dictionary) -> String:
	var parts := PackedStringArray()
	var trade := int(ability.get("trade", 0))
	if trade > 0:
		parts.append(Loc.t("game.star_realms.ability.trade", {"n": trade}))
	var combat := int(ability.get("combat", 0))
	if combat > 0:
		parts.append(Loc.t("game.star_realms.ability.combat", {"n": combat}))
	var authority := int(ability.get("authority", 0))
	if authority > 0:
		parts.append(Loc.t("game.star_realms.ability.authority", {"n": authority}))
	var draw := int(ability.get("draw", 0))
	if draw > 0:
		parts.append(Loc.t("game.star_realms.ability.draw", {"n": draw}))
	if int(ability.get("scrap_hand", 0)) > 0:
		parts.append(Loc.t("game.star_realms.ability.scrap_hand"))
	if int(ability.get("scrap_row", 0)) > 0:
		parts.append(Loc.t("game.star_realms.ability.scrap_row"))
	if int(ability.get("destroy_base", 0)) > 0:
		parts.append(Loc.t("game.star_realms.ability.destroy_base"))
	return ", ".join(parts)


## Full card text: primary ability plus the ally and scrap lines.
static func describe_card(card_id: String) -> String:
	var card := by_id(card_id)
	var lines := PackedStringArray()
	var primary := describe_ability(card)
	if not primary.is_empty():
		lines.append(primary)
	var ally: Dictionary = card.get("ally", {})
	var ally_text := describe_ability(ally)
	if not ally_text.is_empty():
		lines.append(Loc.t("game.star_realms.ally", {"text": ally_text}))
	var scrap: Dictionary = card.get("scrap", {})
	var scrap_text := describe_ability(scrap)
	if not scrap_text.is_empty():
		lines.append(Loc.t("game.star_realms.scrap_ability", {"text": scrap_text}))
	return "\n".join(lines)


## Turns a card instance (or definition) into the dictionary [CardFace] expects.
static func face_data(card_id: String, uid: String = "", selected: bool = false, dimmed: bool = false, highlight: bool = false) -> Dictionary:
	var card := by_id(card_id)
	var faction := String(card.get("faction", FACTION_UNALIGNED))
	var kind := String(card.get("kind", "ship"))
	var subtitle := "%s · %s" % [Loc.t(faction_label_key(faction)), Loc.t(kind_label_key(kind))]
	var footer := ""
	if is_base(card_id):
		footer = Loc.t("game.star_realms.defense", {"n": int(card.get("defense", 0))})
	return {
		"id": uid if not uid.is_empty() else card_id,
		"title": String(card.get("name", card_id)),
		"subtitle": subtitle,
		"cost": str(int(card.get("cost", 0))) if int(card.get("cost", 0)) > 0 else "",
		"body": describe_card(card_id),
		"footer": footer,
		"accent": faction_color(faction),
		"glyph": faction_glyph(faction),
		"selected": selected,
		"dimmed": dimmed,
		"highlight": highlight,
		"tooltip": String(card.get("name", card_id)),
	}
