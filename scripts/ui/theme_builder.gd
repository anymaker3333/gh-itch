class_name ThemeBuilder
extends RefCounted
## Builds the Game Hub [Theme] in code.
##
## Building the theme programmatically keeps colours, radii, spacing and states
## in one place, makes the look testable (a test asserts every state style
## exists) and avoids hand-maintained .tres files drifting apart.

const FONT_FAMILIES: Array[String] = [
	"Inter", "Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial",
	"Noto Sans CJK SC", "Noto Sans CJK JP", "WenQuanYi Zen Hei",
	"Noto Sans Arabic", "Noto Sans Hebrew",
]

const SIZE_CAPTION: int = 12
const SIZE_SMALL: int = 14
const SIZE_BODY: int = 16
const SIZE_SUBTITLE: int = 20
const SIZE_TITLE: int = 26
const SIZE_DISPLAY: int = 34

const RADIUS_SMALL: int = 6
const RADIUS: int = 10
const RADIUS_LARGE: int = 16

static var _cached: Theme = null


## Drop the cached resource after the palette has changed.
static func invalidate() -> void:
	_cached = null


static func build() -> Theme:
	if _cached != null:
		return _cached
	var theme := Theme.new()
	var font := _base_font()
	theme.default_font = font
	theme.default_font_size = SIZE_BODY

	_style_labels(theme)
	_style_buttons(theme)
	_style_panels(theme)
	_style_inputs(theme)
	_style_scrollbars(theme)
	_style_containers(theme)
	_style_misc(theme)
	_cached = theme
	return theme


static func _base_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_FAMILIES)
	font.allow_system_fallback = true
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.multichannel_signed_distance_field = true
	font.msdf_pixel_range = 12
	font.msdf_size = 32
	return font


static func mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["JetBrains Mono", "Noto Sans Mono", "DejaVu Sans Mono", "monospace"])
	font.allow_system_fallback = true
	font.multichannel_signed_distance_field = true
	return font


# ------------------------------------------------------------------- helpers

static func flat(
	bg: Color,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0,
	radius: int = RADIUS,
	content_margin: int = 10
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if border_width > 0:
		box.border_color = border_color
		box.set_border_width_all(border_width)
	box.content_margin_left = content_margin
	box.content_margin_right = content_margin
	box.content_margin_top = maxi(4, content_margin - 2)
	box.content_margin_bottom = maxi(4, content_margin - 2)
	return box


static func empty_box(height: int) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_top = height
	return box


# -------------------------------------------------------------------- styling

static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_font_size("font_size", "Label", SIZE_BODY)

	# Semantic label variations - these are the vocabulary screens use.
	_add_label_variation(theme, "Title", SIZE_TITLE, Palette.TEXT)
	_add_label_variation(theme, "Display", SIZE_DISPLAY, Palette.TEXT)
	_add_label_variation(theme, "Subtitle", SIZE_SUBTITLE, Palette.TEXT)
	_add_label_variation(theme, "Body", SIZE_BODY, Palette.TEXT)
	_add_label_variation(theme, "Small", SIZE_SMALL, Palette.TEXT_MUTED)
	_add_label_variation(theme, "Caption", SIZE_CAPTION, Palette.TEXT_DIM)
	_add_label_variation(theme, "Muted", SIZE_SMALL, Palette.TEXT_MUTED)
	_add_label_variation(theme, "Accent", SIZE_SMALL, Palette.ACCENT)
	_add_label_variation(theme, "Positive", SIZE_SMALL, Palette.POSITIVE)
	_add_label_variation(theme, "Warning", SIZE_SMALL, Palette.WARNING)
	_add_label_variation(theme, "Danger", SIZE_SMALL, Palette.DANGER)
	_add_label_variation(theme, "Mono", SIZE_SMALL, Palette.TEXT_MUTED, true)


static func _add_label_variation(theme: Theme, name: String, size: int, color: Color, mono: bool = false) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)
	if mono:
		theme.set_font("font", name, mono_font())


static func _style_buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", flat(Palette.BG_ELEVATED, Palette.BORDER, 1, RADIUS, 12))
	theme.set_stylebox("hover", "Button", flat(Palette.BG_HOVER, Palette.BORDER_STRONG, 1, RADIUS, 12))
	theme.set_stylebox("pressed", "Button", flat(Palette.BG_ACTIVE, Palette.ACCENT_PRESSED, 1, RADIUS, 12))
	theme.set_stylebox("disabled", "Button", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 12))
	theme.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS, 12))
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_DIM)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_font_size("font_size", "Button", SIZE_SMALL)

	_button_variation(theme, "PrimaryButton", Palette.ACCENT, Palette.ACCENT_HOVER, Palette.ACCENT_PRESSED, Palette.TEXT_ON_ACCENT)
	_button_variation(theme, "DangerButton", Palette.DANGER, Palette.DANGER.lightened(0.12), Palette.DANGER.darkened(0.2), Color.WHITE)
	_button_variation(theme, "PositiveButton", Palette.POSITIVE, Palette.POSITIVE.lightened(0.12), Palette.POSITIVE.darkened(0.2), Palette.BG_DEEPEST)
	_button_variation(theme, "GhostButton", Color(0, 0, 0, 0), Palette.BG_HOVER, Palette.BG_ACTIVE, Palette.TEXT)
	_style_compact_button(theme)
	_style_danger_outline(theme)
	_button_variation(theme, "SidebarButton", Color(0, 0, 0, 0), Palette.BG_HOVER, Palette.BG_ACTIVE, Palette.TEXT_MUTED)
	_button_variation(theme, "ChipButton", Palette.BG_PANEL, Palette.BG_HOVER, Palette.BG_ACTIVE, Palette.TEXT_MUTED)

	theme.set_stylebox("normal", "LinkButton", flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, RADIUS_SMALL, 4))
	theme.set_stylebox("hover", "LinkButton", flat(Palette.tint(Palette.ACCENT, 0.14), Color.TRANSPARENT, 0, RADIUS_SMALL, 4))
	theme.set_color("font_color", "LinkButton", Palette.ACCENT)
	theme.set_color("font_hover_color", "LinkButton", Palette.ACCENT_HOVER)
	theme.set_font_size("font_size", "LinkButton", SIZE_SMALL)


static func _style_danger_outline(theme: Theme) -> void:
	var name := "DangerOutline"
	theme.set_type_variation(name, "Button")
	theme.set_stylebox("normal", name, flat(Color(0, 0, 0, 0), Palette.DANGER, 1, RADIUS, 12))
	theme.set_stylebox("hover", name, flat(Palette.tint(Palette.DANGER, 0.16), Palette.DANGER, 1, RADIUS, 12))
	theme.set_stylebox("pressed", name, flat(Palette.tint(Palette.DANGER, 0.28), Palette.DANGER.lightened(0.12), 1, RADIUS, 12))
	theme.set_stylebox("disabled", name, flat(Color(0, 0, 0, 0), Palette.tint(Palette.DANGER, 0.35), 1, RADIUS, 12))
	theme.set_stylebox("focus", name, flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS, 12))
	theme.set_color("font_color", name, Palette.DANGER)
	theme.set_color("font_hover_color", name, Palette.DANGER.lightened(0.12))
	theme.set_color("font_pressed_color", name, Palette.DANGER.lightened(0.2))
	theme.set_color("font_disabled_color", name, Palette.tint(Palette.DANGER, 0.5))
	theme.set_font_size("font_size", name, SIZE_SMALL)


## Dense button for cards and other places where 34 px of chrome would force a
## whole row to grow. It keeps the same focus/disabled affordances.
static func _style_compact_button(theme: Theme) -> void:
	var name := "CompactButton"
	theme.set_type_variation(name, "Button")
	theme.set_stylebox("normal", name, flat(Palette.BG_ELEVATED, Palette.BORDER, 1, RADIUS_SMALL, 4))
	theme.set_stylebox("hover", name, flat(Palette.BG_HOVER, Palette.BORDER_STRONG, 1, RADIUS_SMALL, 4))
	theme.set_stylebox("pressed", name, flat(Palette.BG_ACTIVE, Palette.ACCENT_PRESSED, 1, RADIUS_SMALL, 4))
	theme.set_stylebox("disabled", name, flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS_SMALL, 4))
	theme.set_stylebox("focus", name, flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS_SMALL, 4))
	theme.set_color("font_color", name, Palette.TEXT)
	theme.set_color("font_hover_color", name, Color.WHITE)
	theme.set_color("font_pressed_color", name, Color.WHITE)
	theme.set_color("font_disabled_color", name, Palette.TEXT_DIM)
	theme.set_color("font_focus_color", name, Color.WHITE)
	theme.set_font_size("font_size", name, SIZE_CAPTION)


static func _button_variation(theme: Theme, name: String, bg: Color, hover: Color, pressed: Color, font_color: Color) -> void:
	theme.set_type_variation(name, "Button")
	theme.set_stylebox("normal", name, flat(bg, bg.lightened(0.18), 1, RADIUS, 12))
	theme.set_stylebox("hover", name, flat(hover, hover.lightened(0.2), 1, RADIUS, 12))
	theme.set_stylebox("pressed", name, flat(pressed, pressed.lightened(0.1), 1, RADIUS, 12))
	theme.set_stylebox("disabled", name, flat(bg.darkened(0.35), bg.darkened(0.4), 1, RADIUS, 12))
	theme.set_stylebox("focus", name, flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS, 12))
	theme.set_color("font_color", name, font_color)
	theme.set_color("font_hover_color", name, font_color)
	theme.set_color("font_pressed_color", name, font_color)
	theme.set_color("font_disabled_color", name, font_color.darkened(0.5))
	theme.set_font_size("font_size", name, SIZE_SMALL)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 12))
	theme.set_stylebox("panel", "PanelContainer", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 0))

	_panel_variation(theme, "CardPanel", Palette.BG_PANEL, Palette.BORDER, RADIUS_LARGE, 0)
	_panel_variation(theme, "ElevatedPanel", Palette.BG_ELEVATED, Palette.BORDER_STRONG, RADIUS, 0)
	_panel_variation(theme, "FlatPanel", Palette.BG_BASE, Palette.BORDER, RADIUS, 0)
	_panel_variation(theme, "TransparentPanel", Color(0, 0, 0, 0), Color(0, 0, 0, 0), RADIUS, 0)
	_panel_variation(theme, "AccentPanel", Palette.ACCENT_DIM, Palette.ACCENT_PRESSED, RADIUS, 0)
	_panel_variation(theme, "DangerPanel", Palette.tint(Palette.DANGER, 0.18), Palette.DANGER, RADIUS, 0)

	theme.set_stylebox("panel", "PopUpPanel", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS, 6))
	theme.set_stylebox("panel", "TooltipPanel", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS_SMALL, 8))
	theme.set_color("font_color", "TooltipLabel", Palette.TEXT_MUTED)


static func _panel_variation(theme: Theme, name: String, bg: Color, border: Color, radius: int, margin: int) -> void:
	theme.set_type_variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, flat(bg, border, 1 if border.a > 0.0 else 0, radius, margin))


static func _style_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", flat(Palette.BG_BASE, Palette.BORDER, 1, RADIUS, 10))
	theme.set_stylebox("focus", "LineEdit", flat(Palette.BG_BASE, Palette.ACCENT, 2, RADIUS, 10))
	theme.set_stylebox("read_only", "LineEdit", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 10))
	theme.set_color("font_color", "LineEdit", Palette.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Palette.TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", Palette.ACCENT)
	theme.set_color("selection_color", "LineEdit", Palette.tint(Palette.ACCENT, 0.4))
	theme.set_font_size("font_size", "LineEdit", SIZE_SMALL)

	theme.set_stylebox("normal", "TextEdit", flat(Palette.BG_BASE, Palette.BORDER, 1, RADIUS, 10))
	theme.set_stylebox("focus", "TextEdit", flat(Palette.BG_BASE, Palette.ACCENT, 2, RADIUS, 10))
	theme.set_color("font_color", "TextEdit", Palette.TEXT)
	theme.set_font_size("font_size", "TextEdit", SIZE_SMALL)

	theme.set_stylebox("normal", "SpinBox", flat(Palette.BG_BASE, Palette.BORDER, 1, RADIUS, 8))
	theme.set_color("font_color", "SpinBox", Palette.TEXT)

	for cls: String in ["OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		theme.set_font_size("font_size", cls, SIZE_SMALL)
		theme.set_color("font_color", cls, Palette.TEXT)
		theme.set_color("font_hover_color", cls, Color.WHITE)
		theme.set_color("font_pressed_color", cls, Color.WHITE)
		theme.set_color("font_disabled_color", cls, Palette.TEXT_DIM)

	theme.set_stylebox("normal", "OptionButton", flat(Palette.BG_ELEVATED, Palette.BORDER, 1, RADIUS, 10))
	theme.set_stylebox("hover", "OptionButton", flat(Palette.BG_HOVER, Palette.BORDER_STRONG, 1, RADIUS, 10))
	theme.set_stylebox("pressed", "OptionButton", flat(Palette.BG_ACTIVE, Palette.ACCENT_PRESSED, 1, RADIUS, 10))
	theme.set_stylebox("focus", "OptionButton", flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS, 10))
	theme.set_stylebox("disabled", "OptionButton", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 10))

	theme.set_stylebox("panel", "PopupMenu", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS, 6))
	theme.set_color("font_color", "PopupMenu", Palette.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", Palette.TEXT_DIM)
	theme.set_stylebox("hover", "PopupMenu", flat(Palette.tint(Palette.ACCENT, 0.25), Color.TRANSPARENT, 0, RADIUS_SMALL, 6))

	# Toggles: only the pill track and knob carry state. Painting the whole
	# button made checked rows look like saturated full-width progress bars.
	theme.set_stylebox("normal", "CheckButton", flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 8, 4))
	theme.set_stylebox("pressed", "CheckButton", flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 8, 4))
	theme.set_stylebox("hover", "CheckButton", flat(Palette.tint(Palette.ACCENT, 0.08), Color.TRANSPARENT, 0, 8, 4))
	theme.set_stylebox("hover_pressed", "CheckButton", flat(Palette.tint(Palette.ACCENT, 0.13), Color.TRANSPARENT, 0, 8, 4))
	theme.set_stylebox("disabled", "CheckButton", flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 8, 4))
	theme.set_stylebox("focus", "CheckButton", flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, 8, 4))
	theme.set_icon("checked", "CheckButton", _toggle_icon(Palette.ACCENT, Palette.TEXT_ON_ACCENT, true))
	theme.set_icon("unchecked", "CheckButton", _toggle_icon(Palette.BG_ELEVATED, Palette.TEXT_MUTED, false))
	theme.set_icon("checked_disabled", "CheckButton", _toggle_icon(Palette.tint(Palette.ACCENT, 0.4), Palette.TEXT_DIM, true))
	theme.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(Palette.BG_PANEL, Palette.TEXT_DIM, false))

	theme.set_stylebox("normal", "CheckBox", flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, RADIUS_SMALL, 4))
	theme.set_stylebox("hover", "CheckBox", flat(Palette.BG_HOVER, Color.TRANSPARENT, 0, RADIUS_SMALL, 4))
	theme.set_stylebox("pressed", "CheckBox", flat(Palette.BG_ACTIVE, Color.TRANSPARENT, 0, RADIUS_SMALL, 4))
	theme.set_stylebox("focus", "CheckBox", flat(Color(0, 0, 0, 0), Palette.FOCUS, 2, RADIUS_SMALL, 4))
	theme.set_icon("checked", "CheckBox", _check_icon(Palette.ACCENT))
	theme.set_icon("unchecked", "CheckBox", _check_icon(Palette.BG_ELEVATED))
	theme.set_icon("checked_disabled", "CheckBox", _check_icon(Palette.tint(Palette.ACCENT, 0.35)))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_icon(Palette.BG_PANEL))

	theme.set_stylebox("slider", "HSlider", flat(Palette.BG_BASE, Palette.BORDER, 1, 6, 0))
	theme.set_stylebox("grabber_area", "HSlider", flat(Palette.ACCENT, Palette.ACCENT, 0, 6, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat(Palette.ACCENT_HOVER, Palette.ACCENT_HOVER, 0, 6, 0))

	theme.set_stylebox("panel", "ProgressBar", flat(Palette.BG_BASE, Palette.BORDER, 1, RADIUS_SMALL, 2))
	theme.set_stylebox("fill", "ProgressBar", flat(Palette.ACCENT, Palette.ACCENT, 0, RADIUS_SMALL, 2))
	theme.set_color("font_color", "ProgressBar", Palette.TEXT)
	theme.set_font_size("font_size", "ProgressBar", SIZE_CAPTION)


## Draws a 36×20 pill switch at 4× and downsamples it for smooth edges.
static func _toggle_icon(track: Color, knob: Color, checked: bool) -> ImageTexture:
	const SUPERSAMPLE: int = 4
	const WIDTH: int = 36
	const HEIGHT: int = 20
	var image := Image.create(WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var outer := Rect2i(0, 0, WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE)
	var border: Color = track.lightened(0.15) if checked else Palette.BORDER_STRONG
	_fill_round_rect(image, outer, 10 * SUPERSAMPLE, border)
	_fill_round_rect(
		image,
		Rect2i(2 * SUPERSAMPLE, 2 * SUPERSAMPLE, (WIDTH - 4) * SUPERSAMPLE, (HEIGHT - 4) * SUPERSAMPLE),
		8 * SUPERSAMPLE,
		track
	)
	var center := Vector2i((26 if checked else 10) * SUPERSAMPLE, HEIGHT * SUPERSAMPLE / 2)
	_fill_circle(image, center, 7 * SUPERSAMPLE, knob)
	image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _fill_round_rect(image: Image, rect: Rect2i, radius: float, color: Color) -> void:
	var inner_min := Vector2(rect.position.x, rect.position.y) + Vector2(radius, radius)
	var inner_max := Vector2(rect.end.x, rect.end.y) - Vector2(radius, radius)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var point := Vector2(x + 0.5, y + 0.5)
			var nearest := Vector2(
				clampf(point.x, inner_min.x, inner_max.x),
				clampf(point.y, inner_min.y, inner_max.y)
			)
			if point.distance_to(nearest) <= radius:
				image.set_pixel(x, y, color)


static func _fill_circle(image: Image, center: Vector2i, radius: float, color: Color) -> void:
	for y: int in range(center.y - int(radius), center.y + int(radius) + 1):
		for x: int in range(center.x - int(radius), center.x + int(radius) + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(center.x, center.y)) <= radius:
				image.set_pixel(x, y, color)


static func _check_icon(fill: Color) -> ImageTexture:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var box := Rect2i(2, 2, 14, 14)
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var edge := x == box.position.x or y == box.position.y or x == box.end.x - 1 or y == box.end.y - 1
			image.set_pixel(x, y, Palette.TEXT_DIM if edge else fill)
	return ImageTexture.create_from_image(image)


static func _style_scrollbars(theme: Theme) -> void:
	for cls: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", cls, flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 6, 0))
		theme.set_stylebox("grabber", cls, flat(Palette.BORDER_STRONG, Color.TRANSPARENT, 0, 6, 2))
		theme.set_stylebox("grabber_highlight", cls, flat(Palette.ACCENT_PRESSED, Color.TRANSPARENT, 0, 6, 2))
		theme.set_stylebox("grabber_pressed", cls, flat(Palette.ACCENT, Color.TRANSPARENT, 0, 6, 2))


static func _style_containers(theme: Theme) -> void:
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 12)
	theme.set_constant("v_separation", "GridContainer", 12)
	theme.set_constant("separation", "FlowContainer", 10)
	theme.set_constant("h_separation", "HFlowContainer", 10)
	theme.set_constant("v_separation", "VFlowContainer", 10)
	theme.set_constant("margin_left", "MarginContainer", 0)
	theme.set_constant("margin_right", "MarginContainer", 0)

	theme.set_stylebox("panel", "TabContainer", flat(Palette.BG_PANEL, Palette.BORDER, 1, RADIUS, 8))
	theme.set_stylebox("tab_selected", "TabContainer", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS, 10))
	theme.set_stylebox("tab_unselected", "TabContainer", flat(Palette.BG_BASE, Color.TRANSPARENT, 0, RADIUS, 10))
	theme.set_stylebox("tab_hovered", "TabContainer", flat(Palette.BG_HOVER, Palette.BORDER, 1, RADIUS, 10))
	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", Palette.TEXT_MUTED)
	theme.set_font_size("font_size", "TabContainer", SIZE_SMALL)

	theme.set_stylebox("panel", "ItemList", flat(Palette.BG_BASE, Palette.BORDER, 1, RADIUS, 8))
	theme.set_stylebox("selected", "ItemList", flat(Palette.tint(Palette.ACCENT, 0.28), Color.TRANSPARENT, 0, RADIUS_SMALL, 6))
	theme.set_stylebox("hovered", "ItemList", flat(Palette.BG_HOVER, Color.TRANSPARENT, 0, RADIUS_SMALL, 6))
	theme.set_color("font_color", "ItemList", Palette.TEXT)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_font_size("font_size", "ItemList", SIZE_SMALL)


static func _style_misc(theme: Theme) -> void:
	theme.set_stylebox("panel", "AcceptDialog", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS, 16))
	theme.set_stylebox("panel", "Window", flat(Palette.BG_ELEVATED, Palette.BORDER_STRONG, 1, RADIUS, 12))
	theme.set_color("title_color", "Window", Palette.TEXT)
	theme.set_constant("title_height", "Window", 30)
	var hline := StyleBoxLine.new()
	hline.color = Palette.BORDER
	hline.thickness = 1
	hline.vertical = false
	theme.set_stylebox("separator", "HSeparator", hline)
	theme.set_constant("separation", "HSeparator", 1)
	var vline := StyleBoxLine.new()
	vline.color = Palette.BORDER
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_color("font_color", "RichTextLabel", Palette.TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", SIZE_SMALL)
	theme.set_font_size("default_font_size", "RichTextLabel", SIZE_SMALL)
