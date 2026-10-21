class_name UI
extends RefCounted
## Widget factory and small layout helpers.
##
## Screens are built in code; using one factory for labels, buttons, panels and
## rows keeps spacing, theme variations and behaviour consistent between screens
## and makes it cheap to add a new one.

const FORM_CONTROL_WIDTH: int = 360

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme == null:
		_theme = ThemeBuilder.build()
	return _theme


## Label that keeps the width of its longest word when it is auto-wrapped.
##
## A plain [Label] with word wrapping reports a one-character minimum width. In
## an HBox or a flow container that is enough to shrink the label into a tall
## column of single letters (audit: Bridge player names, Citadels titles, DANY's
## hand heading). Reporting the longest word as the minimum width keeps the text
## horizontal while still allowing it to wrap in narrow columns.
class AutoLabel:
	extends Label

	var _setting_minimum: bool = false

	func _ready() -> void:
		minimum_size_changed.connect(_refresh_minimum_width)
		_refresh_minimum_width()

	func _refresh_minimum_width() -> void:
		if _setting_minimum or autowrap_mode == TextServer.AUTOWRAP_OFF or text.is_empty():
			return
		var font: Font = get_theme_font("font")
		if font == null:
			return
		var font_size: int = get_theme_font_size("font_size")
		var longest: String = _longest_word(text)
		if longest.is_empty():
			return
		var width: float = minf(font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 4.0, 280.0)
		if width <= custom_minimum_size.x:
			return
		_setting_minimum = true
		custom_minimum_size.x = width
		_setting_minimum = false

	func _longest_word(source: String) -> String:
		var longest := ""
		for line: String in source.split("\n"):
			for word: String in line.split(" ", false):
				if word.length() > longest.length():
					longest = word
		return longest


## Caps a page container at a comfortable reading width. Unlike a fixed-size
## wrapper this never demands more width than the window has, so it also works
## at 1280x720 and with the sidebar hidden.
class MaxWidthBox:
	extends Container

	var max_width: int = 1280
	var align_center: bool = false

	func _get_minimum_size() -> Vector2:
		var result := Vector2.ZERO
		for child: Node in get_children():
			if child is Control and (child as Control).visible:
				result = result.max((child as Control).get_combined_minimum_size())
		return result

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		for child: Node in get_children():
			if child is Control and (child as Control).visible:
				var width: float = minf(size.x, float(max_width))
				var x: float = (size.x - width) * 0.5 if align_center else 0.0
				fit_child_in_rect(child as Control, Rect2(x, 0.0, width, size.y))


# --------------------------------------------------------------------- labels

static func label(text: String, variation: String = "Body", align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := AutoLabel.new()
	node.text = text
	node.theme_type_variation = variation
	node.horizontal_alignment = align
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func heading(text: String, variation: String = "Title") -> Label:
	var node := label(text, variation)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	return node


static func caption(text: String) -> Label:
	return label(text, "Caption")


static func centered(text: String, variation: String = "Subtitle") -> Label:
	return label(text, variation, HORIZONTAL_ALIGNMENT_CENTER)


## Compact right-aligned numeric readout for sliders. Without an explicit
## minimum width and autowrap disabled, a label in an HBox next to an expanding
## slider collapses to one character per line.
static func value_label(text: String, min_width: int = 56) -> Label:
	var node := label(text, "Small", HORIZONTAL_ALIGNMENT_RIGHT)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.custom_minimum_size = Vector2(min_width, 0)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return node


# -------------------------------------------------------------------- buttons

static func button(text: String, variation: String = "Button", on_press: Callable = Callable(), tooltip: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.theme_type_variation = variation
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not on_press.is_valid():
		pass
	else:
		node.pressed.connect(on_press)
	_connect_audio(node, variation)
	if not tooltip.is_empty():
		node.tooltip_text = tooltip
	return node


static func icon_button(glyph: String, tooltip: String, on_press: Callable = Callable(), variation: String = "GhostButton") -> Button:
	var node := button(glyph, variation, on_press, tooltip)
	node.custom_minimum_size = Vector2(34, 34)
	node.add_theme_font_size_override("font_size", ThemeBuilder.SIZE_BODY)
	return node


static func link_button(text: String, on_press: Callable = Callable()) -> LinkButton:
	var node := LinkButton.new()
	node.text = text
	if on_press.is_valid():
		node.pressed.connect(on_press)
	_connect_audio(node, "LinkButton")
	return node


static func _connect_audio(node: Control, variation: String) -> void:
	if node is Button:
		var button_node := node as Button
		button_node.mouse_entered.connect(func() -> void: Audio.play(Audio.Sfx.HOVER))
		if variation == "PrimaryButton" or variation == "PositiveButton":
			button_node.pressed.connect(func() -> void: Audio.play(Audio.Sfx.CONFIRM))
		else:
			button_node.pressed.connect(func() -> void: Audio.play(Audio.Sfx.CLICK))


# --------------------------------------------------------------------- panels

static func panel(variation: String = "CardPanel") -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = variation
	return node


static func panel_with(child: Control, variation: String = "CardPanel", margin: int = 16) -> PanelContainer:
	var node := panel(variation)
	node.add_child(margin_container(child, margin))
	return node


static func margin_container(child: Control, margin: int = 16) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", margin)
	node.add_theme_constant_override("margin_right", margin)
	node.add_theme_constant_override("margin_top", margin)
	node.add_theme_constant_override("margin_bottom", margin)
	if child != null:
		node.add_child(child)
	return node


static func margin_xy(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", left)
	node.add_theme_constant_override("margin_right", right)
	node.add_theme_constant_override("margin_top", top)
	node.add_theme_constant_override("margin_bottom", bottom)
	if child != null:
		node.add_child(child)
	return node


# ------------------------------------------------------------------ containers

static func column(separation: int = 12, children: Array = []) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	for child: Variant in children:
		if child is Node:
			node.add_child(child)
	return node


static func row(separation: int = 10, children: Array = []) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	for child: Variant in children:
		if child is Node:
			node.add_child(child)
	return node


static func hsep(separation: int = 10) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func vsep(separation: int = 10) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func grid(columns: int = 2, h: int = 14, v: int = 14) -> GridContainer:
	var node := GridContainer.new()
	node.columns = columns
	node.add_theme_constant_override("h_separation", h)
	node.add_theme_constant_override("v_separation", v)
	return node


static func flow(h: int = 14, v: int = 14) -> HFlowContainer:
	var node := HFlowContainer.new()
	node.add_theme_constant_override("h_separation", h)
	node.add_theme_constant_override("v_separation", v)
	return node


static func spacer(size: int = 0, vertical: bool = false) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not vertical else Control.SIZE_SHRINK_BEGIN
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL if vertical else Control.SIZE_SHRINK_BEGIN
	if size > 0:
		node.custom_minimum_size = Vector2(size, size) if not vertical else Vector2(0, size)
	return node


static func hspacer(width: int = 0) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(width, 0)
	return node


static func fixed_spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


## Wraps a page body in a readable-width container. The child still fills the
## available height and shrinks with the window.
static func max_width(child: Control, width: int = 1280, center: bool = false) -> Control:
	var node := MaxWidthBox.new()
	node.max_width = width
	node.align_center = center
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if child != null:
		node.add_child(child)
	return node


static func divider() -> HSeparator:
	return HSeparator.new()


static func dynamic_divider() -> HSeparator:
	var node := HSeparator.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	node.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if child != null:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.add_child(child)
	return node


# ---------------------------------------------------------------- small parts

static func chip(text: String, color: Color = Color(0, 0, 0, 0), background: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	if color.a <= 0.0:
		color = Palette.TEXT_MUTED
	var box := panel("TransparentPanel")
	var style := ThemeBuilder.flat(
		background if background.a > 0.0 else Palette.tint(color, 0.14),
		Palette.tint(color, 0.45),
		1,
		7,
		8
	)
	box.add_theme_stylebox_override("panel", style)
	var text_label := label(text, "Caption")
	text_label.add_theme_color_override("font_color", color)
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(text_label)
	return box


static func status_pill(text: String, color: Color) -> PanelContainer:
	return chip(text, color)


static func kv_row(key: String, value: String, value_color: Color = Color(0, 0, 0, 0)) -> HBoxContainer:
	if value_color.a <= 0.0:
		value_color = Palette.TEXT
	var node := row(12)
	var key_label := label(key, "Small")
	key_label.custom_minimum_size = Vector2(170, 0)
	key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var value_label := label(value, "Body")
	value_label.add_theme_color_override("font_color", value_color)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_child(key_label)
	node.add_child(value_label)
	return node


## Section header used inside settings screens and side panels.
static func section_header(text: String, subtitle: String = "") -> VBoxContainer:
	var box := column(4)
	box.add_child(heading(text, "Subtitle"))
	if not subtitle.is_empty():
		box.add_child(label(subtitle, "Small"))
	return box


## One settings/setup row: the label stays on the left and the control is
## right-aligned at a comfortable width. Letting controls expand across a
## 1600-1920 px window produced 1200 px sliders and full-width toggle bars.
static func form_row(label_text: String, control: Control, hint: String = "") -> VBoxContainer:
	var box := column(4)
	var top := row(12)
	var text_label := label(label_text, "Body")
	text_label.custom_minimum_size = Vector2(220, 0)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(text_label)
	top.add_child(spacer())
	if control is CheckButton:
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		control.size_flags_horizontal = Control.SIZE_FILL
		control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, FORM_CONTROL_WIDTH)
	top.add_child(control)
	box.add_child(top)
	if not hint.is_empty():
		var hint_label := label(hint, "Caption")
		hint_label.add_theme_constant_override("line_spacing", 0)
		box.add_child(hint_label)
	return box


## Compact switch. The theme draws only the track/knob; the control must not
## stretch to the row width, or the checked background becomes a full-width bar.
static func toggle(text: String, value: bool, on_change: Callable) -> CheckButton:
	var node := CheckButton.new()
	node.text = text
	node.button_pressed = value
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.custom_minimum_size = Vector2(0, 30)
	node.add_theme_constant_override("h_separation", 8)
	node.toggled.connect(func(pressed: bool) -> void:
		Audio.play(Audio.Sfx.CLICK)
		on_change.call(pressed)
	)
	return node


static func slider(min_value: float, max_value: float, step: float, value: float, on_change: Callable) -> HSlider:
	var node := HSlider.new()
	node.min_value = min_value
	node.max_value = max_value
	node.step = step
	node.value = value
	node.custom_minimum_size = Vector2(240, 24)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.value_changed.connect(func(new_value: float) -> void: on_change.call(new_value))
	return node


static func dropdown(entries: Array, selected: String, on_change: Callable) -> OptionButton:
	var node := OptionButton.new()
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var index := 0
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		node.add_item(String(entry.get("label", "")), i)
		node.set_item_metadata(i, str(entry.get("value", "")))
		if str(entry.get("value", "")) == selected:
			index = i
	node.selected = index
	node.item_selected.connect(func(item_index: int) -> void:
		Audio.play(Audio.Sfx.CLICK)
		on_change.call(String(node.get_item_metadata(item_index)))
	)
	return node


static func line_edit(placeholder: String, text: String = "", on_submit: Callable = Callable()) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.text = text
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.clear_button_enabled = true
	if on_submit.is_valid():
		node.text_submitted.connect(func(submitted: String) -> void: on_submit.call(submitted))
	return node


static func rich_text(bbcode: String = "") -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.text = bbcode
	return node


static func progress(value: float, max_value: float = 1.0) -> ProgressBar:
	var node := ProgressBar.new()
	node.max_value = max_value
	node.value = value
	node.show_percentage = false
	node.custom_minimum_size = Vector2(0, 6)
	return node


static func separator_label(text: String) -> VBoxContainer:
	var box := column(6)
	box.add_child(label(text, "Caption"))
	box.add_child(divider())
	return box


# ------------------------------------------------------------- interactions

static func tooltip(node: Control, text: String) -> Control:
	node.tooltip_text = text
	return node


## Subtle hover feedback used by cards and list rows.
static func animate_hover(node: Control, scale: float = 1.02, duration: float = 0.12) -> void:
	if bool(Prefs.get_value("general/reduced_motion", false)):
		return
	node.pivot_offset = node.size * 0.5
	node.mouse_entered.connect(func() -> void:
		var tween := node.create_tween()
		tween.tween_property(node, "scale", Vector2(scale, scale), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	)
	node.mouse_exited.connect(func() -> void:
		var tween := node.create_tween()
		tween.tween_property(node, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	)
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)


static func fade_in(node: Node, duration: float = 0.18, delay: float = 0.0) -> void:
	if bool(Prefs.get_value("general/reduced_motion", false)):
		return
	if not (node is CanvasItem):
		return
	var item := node as CanvasItem
	item.modulate.a = 0.0
	var tween := item.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(item, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE)


static func slide_in(node: Control, from_x: float = 24.0, duration: float = 0.2) -> void:
	if bool(Prefs.get_value("general/reduced_motion", false)):
		return
	var target := node.position
	node.position = target + Vector2(from_x, 0)
	var tween := node.create_tween()
	tween.tween_property(node, "position", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Convenience: formatted localised text with placeholders.
static func t(key: String, args: Dictionary = {}) -> String:
	return Loc.t(key, args)
