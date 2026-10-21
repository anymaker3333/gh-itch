class_name GameView
extends VBoxContainer
## Base class for every game's board/table view.
##
## Views are pure presentation over a [GameEngine]: they render from
## `engine.public_state()` and the authorized slice returned by
## [method private_info], and submit actions through the session. They never
## mutate game state directly, which keeps hotseat, solo and online paths
## identical.

signal action_requested(key: String)
signal view_message(message_key: String, args: Dictionary)

var session: GameSession = null
var engine: GameEngine = null
var local_player: int = 0

## Handover prompt required before the given player may see the table.
var _confirm_overlay: Control = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)


func configure(game_session: GameSession) -> void:
	session = game_session
	engine = game_session.engine_for_view()
	local_player = maxi(0, game_session.active_local_player())
	if not _built_once:
		_built_once = true
		build_board()
	refresh_board()


var _built_once: bool = false


## Build static structure. Called once.
func build_board() -> void:
	pass


## Re-render the board from the current state. Called on every state change and
## after each local action.
func refresh_board() -> void:
	pass


## True when this game hides information and hotseat play needs a handover step.
func requires_handover() -> bool:
	return false


## Format one move-log entry for display. Views with compact card codes or
## other machine-readable values override this; the default is the engine text.
func log_text(entry: Dictionary) -> String:
	return VariantUtil.as_string(entry.get("text", ""), "")


## Extra controls shown in the action bar (e.g. "confirm selection").
func action_bar_extras() -> Array[Control]:
	var out: Array[Control] = []
	return out


# ------------------------------------------------------------------ helpers

func acting_player() -> int:
	if engine == null:
		return 0
	if session != null and session.is_online():
		return local_player
	return engine.decision_player()


## The private information this view is authorized to show right now.
##
## Single access point for hidden data (§6.3): on an online client the replica's
## engine only knows the seat's own authorized slice, and the authoritative
## answer is the host-tailored `private` payload of the last snapshot
## (`session.last_private`); everywhere else (hotseat, solo, host) the engine
## itself answers for the seat the local device controls. Views must render
## private panels from this helper and never call `engine.private_state()`
## directly — that keeps the "private data only reaches its owner" rule true
## for every mode with one implementation.
func private_info() -> Dictionary:
	if session != null and session.mode == GameSession.Mode.ONLINE_CLIENT:
		return session.last_private
	if engine == null:
		return {}
	return engine.private_state(acting_player())


func is_my_turn() -> bool:
	if engine == null:
		return false
	if session != null and session.is_online():
		return local_player == engine.decision_player()
	return true


## Submits one player action. Exactly one component submits each action:
##
##  * when a screen is wired to [signal action_requested] (GameScreen does this
##    once per mounted view), the screen routes the action to the session;
##  * only when nobody listens to the signal (a standalone view in tests or
##    inspectors) does the view submit to the session itself.
##
## Submitting both ways — the historical behaviour — applied every action twice:
## DANY registered two selections per click, Chess rejected the duplicate and
## Splendor played its card sound twice.
func submit(key: String) -> void:
	if key.is_empty():
		return
	if action_requested.get_connections().is_empty():
		if session != null:
			session.submit_action_key(key)
		return
	action_requested.emit(key)


func legal_actions() -> Array:
	if session != null:
		return session.available_actions()
	if engine == null:
		return []
	return engine.legal_actions(engine.decision_player())


## Real viewport size when in the scene tree; the project's configured default
## geometry when the view is constructed off-tree.
##
## `get_viewport_rect()` logs an unhandled engine error outside the tree, and
## views are built and configured before they are mounted (headless tests,
## cached screens, responsive re-measures). The default matches
## `project.godot`'s 1600x900 window so off-tree layout stays sane.
func viewport_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	)


## Actions of a single type, for filtering the ones a widget should show.
func actions_of_type(action_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: Variant in legal_actions():
		if action is Dictionary and VariantUtil.as_string(action.get("type", ""), "") == action_type:
			out.append(action)
	return out


## Builds a row of buttons for actions of one type.
func action_buttons(action_type: String, container: Container, label_field: String = "label_key") -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var actions := actions_of_type(action_type)
	for action: Dictionary in actions:
		var label_key := VariantUtil.as_string(action.get(label_field, ""), "")
		var text := Loc.t(label_key) if not label_key.is_empty() else VariantUtil.as_string(action.get("key", ""), "")
		var enabled := bool(action.get("enabled", true))
		var button := UI.button(text, "Button", func() -> void:
			submit(VariantUtil.as_string(action.get("key", ""), ""))
		)
		button.disabled = not enabled
		if action.has("tooltip_key"):
			button.tooltip_text = Loc.t(VariantUtil.as_string(action["tooltip_key"], ""))
		container.add_child(button)


## Convenience for card dictionaries with an "id".
func card_row(cards: Array, width: int = CardFace.WIDTH_MEDIUM) -> HFlowContainer:
	var flow := UI.flow(10, 10)
	for card: Variant in cards:
		if card is Dictionary:
			var face := CardFace.new()
			face.configure(card, width)
			flow.add_child(face)
	return flow


func player_panel(index: int) -> PanelContainer:
	var box := UI.column(4)
	var title := UI.row(6)
	title.add_child(UI.label(engine.player_name(index), "Body"))
	if bool(engine.players[index].get("kind", "") == "bot"):
		title.add_child(UI.chip(Loc.t("game.common.bot"), Palette.TEXT_MUTED))
	if engine.decision_player() == index and not engine.finished:
		title.add_child(UI.chip(Loc.t("game.common.active"), Palette.POSITIVE))
	box.add_child(title)
	return UI.panel_with(box, "CardPanel", 10)


func seat_labels() -> Array[String]:
	var out: Array[String] = []
	for index: int in range(engine.player_count()):
		out.append(engine.player_name(index))
	return out
