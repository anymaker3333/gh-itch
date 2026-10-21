class_name ToastLayer
extends Control
## Transient notification stack shown in the bottom-right corner.
##
## Each toast is a small panel with a coloured accent bar; it auto-dismisses but
## can be clicked away, and the layer never blocks mouse input to the UI below.

const MAX_VISIBLE: int = 4
const LIFETIME_SEC: float = 4.5

var _stack: VBoxContainer
var _bottom_inset: int = 0


## Screens with a persistent bottom bar (the in-game action bar) reserve room so
## a toast never sits on top of the primary actions.
func set_bottom_inset(pixels: int) -> void:
	_bottom_inset = maxi(0, pixels)
	_apply_inset()


func _apply_inset() -> void:
	if _stack != null:
		_stack.offset_bottom = -24 - _bottom_inset


## Removes every visible toast immediately. Used by the visual audit before a
## route capture so a previous notification cannot cover the screen under test.
func clear_all() -> void:
	if _stack == null:
		return
	for child: Node in _stack.get_children():
		_stack.remove_child(child)
		child.queue_free()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack = VBoxContainer.new()
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.add_theme_constant_override("separation", 8)
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_right = -24
	_stack.offset_bottom = -24
	_stack.offset_left = -420
	_stack.offset_top = -600
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_apply_inset()
	Notify.notification_posted.connect(_on_notification)
	for queued: Dictionary in Notify.drain_queue():
		_spawn(String(queued.message), Notify.kind_name(int(queued.kind)))


func _on_notification(message: String, kind: String) -> void:
	_spawn(message, kind)


func info(message: String) -> void:
	_spawn(message, "info")


func success(message: String) -> void:
	_spawn(message, "success")


func warning(message: String) -> void:
	_spawn(message, "warning")


func error(message: String) -> void:
	_spawn(message, "error")


func _spawn(message: String, kind: String) -> void:
	if _stack == null:
		return
	while _stack.get_child_count() >= MAX_VISIBLE:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	var color := Notify.color_for_kind(kind)
	var box := PanelContainer.new()
	box.theme_type_variation = "ElevatedPanel"
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := ThemeBuilder.flat(Palette.BG_ELEVATED, Palette.tint(color, 0.6), 1, ThemeBuilder.RADIUS, 12)
	style.border_width_left = 4
	style.border_color = color
	box.add_theme_stylebox_override("panel", style)
	var content := UI.row(10)
	var icon := UI.label(_icon_for(kind), "Subtitle")
	icon.add_theme_color_override("font_color", color)
	icon.autowrap_mode = TextServer.AUTOWRAP_OFF
	content.add_child(icon)
	var text := UI.label(message, "Small")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(240, 0)
	content.add_child(text)
	box.add_child(content)
	_stack.add_child(box)

	if not bool(Prefs.get_value("general/reduced_motion", false)):
		box.modulate.a = 0.0
		box.position.x += 20.0
		var tween := box.create_tween()
		tween.set_parallel(true)
		tween.tween_property(box, "modulate:a", 1.0, 0.15)
		tween.tween_property(box, "position:x", box.position.x - 20.0, 0.18).set_trans(Tween.TRANS_CUBIC)
	var timer := get_tree().create_timer(LIFETIME_SEC)
	timer.timeout.connect(func() -> void: _dismiss(box))
	box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_dismiss(box)
	)


func _dismiss(box: Node) -> void:
	if not is_instance_valid(box):
		return
	if not box.is_inside_tree():
		return
	if bool(Prefs.get_value("general/reduced_motion", false)):
		box.queue_free()
		return
	var tween := box.create_tween()
	tween.tween_property(box, "modulate:a", 0.0, 0.18)
	tween.tween_callback(box.queue_free)


func _icon_for(kind: String) -> String:
	match kind:
		"success":
			return "✔"
		"warning":
			return "!"
		"error":
			return "✖"
		_:
			return "i"
