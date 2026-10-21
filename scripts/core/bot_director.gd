class_name BotDirector
extends RefCounted
## Dispatches AI decisions to the bot implementation of the running game.
##
## Each playable game ships a bot script with a static [code]choose_action[/code]
## (or [code]choose[/code]) entry point. Games without a bespoke bot fall back to
## a generic policy: pick the first legal action, which is always valid and keeps
## hotseat/solo modes functional (documented as a simple AI).

const BOT_SCRIPTS: Dictionary = {
	"chess": "res://scripts/games/chess/chess_bot.gd",
	"checkers_placeholder": "",
	"citadels": "res://scripts/games/citadels/citadels_bot.gd",
	"codenames": "res://scripts/games/codenames/codenames_bot.gd",
	"dany": "res://scripts/games/dany/dany_bot.gd",
	"spyfall": "res://scripts/games/spyfall/spyfall_bot.gd",
	"durak": "res://scripts/games/durak/durak_bot.gd",
	"bridge": "res://scripts/games/bridge/bridge_bot.gd",
	"king": "res://scripts/games/king/king_bot.gd",
	"monopoly": "res://scripts/games/monopoly/monopoly_bot.gd",
	"ticket_to_ride_europe": "res://scripts/games/ticket_to_ride/ticket_to_ride_bot.gd",
	"coup": "res://scripts/games/coup/coup_bot.gd",
	"splendor": "res://scripts/games/splendor/splendor_bot.gd",
	"star_realms": "res://scripts/games/star_realms/star_realms_bot.gd",
}

static var _cache: Dictionary = {}


static func choose_action(engine: GameEngine, player: int) -> String:
	var actions: Array[Dictionary] = engine.legal_actions(player)
	if actions.is_empty():
		return ""
	var script: GDScript = _bot_script(engine.game_id())
	if script == null:
		return VariantUtil.as_string(actions[0].get("key", ""), "")
	var instance: Variant = script.new()
	var key := ""
	if instance.has_method("choose_action"):
		# A bot script returns its choice as a Variant, so the key must be read
		# through the type-safe helper: a bot that answers with something else
		# must not take the whole turn down.
		key = VariantUtil.as_string(instance.call("choose_action", engine, player), "")
	elif instance.has_method("choose"):
		var action: Variant = instance.call("choose", engine, player)
		if action is Dictionary:
			key = VariantUtil.as_string(VariantUtil.as_dict(action).get("key", ""), "")
	if key.is_empty():
		key = VariantUtil.as_string(actions[0].get("key", ""), "")
	else:
		# Defensive: never return an action the engine does not consider legal.
		var found := false
		for action: Dictionary in actions:
			if VariantUtil.as_string(action.get("key", ""), "") == key:
				found = true
				break
		if not found:
			Log.warn("BotDirector: bot proposed an illegal action, falling back", {"game": engine.game_id(), "key": key})
			key = VariantUtil.as_string(actions[0].get("key", ""), "")
	return key


static func has_bot(game_id: String) -> bool:
	return _bot_script(game_id) != null


static func _bot_script(game_id: String) -> GDScript:
	if _cache.has(game_id):
		return _cache[game_id]
	var path := VariantUtil.as_string(BOT_SCRIPTS.get(game_id, ""), "")
	var script: GDScript = null
	if not path.is_empty() and ResourceLoader.exists(path):
		script = load(path) as GDScript
	_cache[game_id] = script
	return script
