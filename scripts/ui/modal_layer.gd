class_name ModalLayer
extends Control
## Modal dialogs (confirm / prompt / choose) plus the global "busy" blocker.
##
## Dialogs are callback based (no awaiting in screen code) and always restore
## focus to the previously focused control, which keeps keyboard navigation
## usable. The layer is hidden while no dialog is open so it never steals input.

var _dim: ColorRect
var _dialog_center: CenterContainer
var _dialog_holder: VBoxContainer
var _previous_focus: Control = null
var _open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	_dialog_center = CenterContainer.new()
	_dialog_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_center)
	_dialog_holder = VBoxContainer.new()
	_dialog_holder.custom_minimum_size = Vector2(520, 0)
	_dialog_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_center.add_child(_dialog_holder)


func is_open() -> bool:
	return _open


func confirm(title: String, body: String, confirm_label: String, on_confirmed: Callable, cancel_label: String = "", danger: bool = false) -> void:
	_close_existing()
	var panel := UI.panel_with(_build_confirm_body(title, body, confirm_label, cancel_label, on_confirmed, danger), "ElevatedPanel", 20)
	_show_dialog(panel)


func alert(title: String, body: String, close_label: String = "") -> void:
	confirm(title, body, close_label if not close_label.is_empty() else Loc.t("common.close"), func(_accepted: bool) -> void: pass)


func prompt(title: String, placeholder: String, initial: String, on_submit: Callable) -> void:
	_close_existing()
	var box := UI.column(14)
	box.add_child(UI.heading(title, "Subtitle"))
	var field := UI.line_edit(placeholder, initial)
	box.add_child(field)
	var buttons := UI.row(10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UI.button(Loc.t("common.cancel"), "GhostButton", func() -> void: _dismiss())
	var accept := UI.button(Loc.t("common.save"), "PrimaryButton", func() -> void:
		var value := field.text.strip_edges()
		_dismiss()
		on_submit.call(value)
	)
	buttons.add_child(cancel)
	buttons.add_child(accept)
	box.add_child(buttons)
	field.text_submitted.connect(func(submitted: String) -> void:
		_dismiss()
		on_submit.call(submitted.strip_edges())
	)
	_show_dialog(UI.panel_with(box, "ElevatedPanel", 20))
	field.grab_focus()
	field.select_all()


## `entries`: [{ "label": String, "value": String, "disabled": bool, "hint": String }]
func choose(title: String, body: String, entries: Array, on_choose: Callable) -> void:
	_close_existing()
	var box := UI.column(12)
	box.add_child(UI.heading(title, "Subtitle"))
	if not body.is_empty():
		box.add_child(UI.label(body, "Small"))
	var list := UI.column(6)
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var row := UI.row(8)
		var button := UI.button(
			String(data.get("label", "?")),
			"GhostButton",
			func() -> void:
				_dismiss()
				on_choose.call(str(data.get("value", "")))
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = bool(data.get("disabled", false))
		var hint := String(data.get("hint", ""))
		if not hint.is_empty():
			button.tooltip_text = hint
		row.add_child(button)
		if not hint.is_empty():
			row.add_child(UI.label(hint, "Caption"))
		list.add_child(row)
	if entries.is_empty():
		list.add_child(UI.label(Loc.t("common.nothing_to_show"), "Small"))
	box.add_child(UI.scroll(list))
	box.custom_minimum_size = Vector2(520, 0)
	var buttons := UI.row(10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UI.button(Loc.t("common.cancel"), "GhostButton", func() -> void: _dismiss()))
	box.add_child(buttons)
	_show_dialog(UI.panel_with(box, "ElevatedPanel", 20))


func _build_confirm_body(title: String, body: String, confirm_label: String, cancel_label: String, on_confirmed: Callable, danger: bool) -> Control:
	var box := UI.column(14)
	box.add_child(UI.heading(title, "Subtitle"))
	if not body.is_empty():
		var text := UI.label(body, "Small")
		text.custom_minimum_size = Vector2(460, 0)
		box.add_child(text)
	var buttons := UI.row(10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UI.button(cancel_label if not cancel_label.is_empty() else Loc.t("common.cancel"), "GhostButton", func() -> void:
		_dismiss()
		on_confirmed.call(false)
	)
	var accept := UI.button(confirm_label if not confirm_label.is_empty() else Loc.t("common.confirm"), "DangerButton" if danger else "PrimaryButton", func() -> void:
		_dismiss()
		on_confirmed.call(true)
	)
	buttons.add_child(cancel)
	buttons.add_child(accept)
	box.add_child(buttons)
	return box


func _show_dialog(panel: Control) -> void:
	_clear_children()
	_previous_focus = get_viewport().gui_get_focus_owner()
	_dialog_holder.add_child(panel)
	_dim.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_open = true
	UI.fade_in(panel, 0.14)
	# Focus the first focusable control inside the dialog for keyboard users.
	var first := _first_focusable(panel)
	if first != null:
		first.call_deferred("grab_focus")


func _first_focusable(node: Node) -> Control:
	if node is Button and (node as Button).focus_mode != Control.FOCUS_NONE:
		return node as Control
	for child: Node in node.get_children():
		var found := _first_focusable(child)
		if found != null:
			return found
	return null


func dismiss() -> void:
	_dismiss()


func _dismiss() -> void:
	_clear_children()
	_dim.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open = false
	if _previous_focus != null and is_instance_valid(_previous_focus):
		_previous_focus.call_deferred("grab_focus")
	_previous_focus = null


func _close_existing() -> void:
	if _open:
		_clear_children()
		_open = false


func _clear_children() -> void:
	for child: Node in _dialog_holder.get_children():
		_dialog_holder.remove_child(child)
		child.queue_free()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_dismiss()
		get_viewport().set_input_as_handled()
