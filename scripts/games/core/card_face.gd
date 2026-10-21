class_name CardFace
extends PanelContainer
## Reusable card widget used by every card-based game view.
##
## A card is pure presentation: the owning view maps a card model (dictionary)
## onto it and reacts to [signal clicked]. Cards can be marked selected, dimmed,
## highlighted or face down, which is enough for hand, table, market and deck
## representations across the catalog.

signal clicked(card_id: String)
signal hovered(card_id: String, entered: bool)

const WIDTH_SMALL: int = 96
const WIDTH_MEDIUM: int = 128
const WIDTH_LARGE: int = 168
const RATIO: float = 1.4

var card_id: String = ""
var selected: bool = false
var _compact: bool = false

var _accent_bar: ColorRect
var _title: Label
var _subtitle: Label
var _cost: Label
var _footer: Label
var _body: RichTextLabel
var _glyph: Label
var _border_color: Color = Palette.BORDER


func _init() -> void:
	theme_type_variation = "TransparentPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL


func configure(data: Dictionary, width: int = WIDTH_MEDIUM, compact: bool = false) -> void:
	card_id = String(data.get("id", ""))
	_compact = compact
	_build(width)
	var accent: Color = data.get("accent", Palette.ACCENT)
	var face_down := bool(data.get("face_down", false))
	var dimmed := bool(data.get("dimmed", false))
	var highlight := bool(data.get("highlight", false))
	selected = bool(data.get("selected", false))
	if face_down:
		_accent_bar.color = Palette.BORDER
		_title.text = ""
		_subtitle.text = ""
		_cost.text = ""
		_footer.text = ""
		_body.text = ""
		_glyph.text = "✦"
		_glyph.visible = true
		_glyph.add_theme_color_override("font_color", Palette.tint(accent, 0.75))
	else:
		_glyph.visible = not String(data.get("glyph", "")).is_empty()
		_glyph.text = String(data.get("glyph", ""))
		_glyph.add_theme_color_override("font_color", accent)
		_accent_bar.color = accent
		_title.text = String(data.get("title", ""))
		_subtitle.text = String(data.get("subtitle", ""))
		_cost.text = String(data.get("cost", ""))
		_footer.text = String(data.get("footer", ""))
		_body.text = String(data.get("body", ""))
	modulate = Color(1, 1, 1, 0.62 if dimmed else 1.0)
	_border_color = Palette.FOCUS if selected else (Palette.ACCENT if highlight else (accent if not face_down else Palette.BORDER))
	_apply_border()
	tooltip_text = String(data.get("tooltip", _title.text))
	visible = true


func _build(width: int) -> void:
	if _compact:
		_build_compact(width)
		return
	if _title != null:
		custom_minimum_size = Vector2(width, int(float(width) * RATIO))
		return
	custom_minimum_size = Vector2(width, int(float(width) * RATIO))
	var column := UI.column(0)
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(0, 4)
	column.add_child(_accent_bar)
	var inner := UI.column(4)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# `margin_xy` parents `inner` into the returned container, so add that
	# container to the outer column afterwards. The accent bar stays flush
	# because it is the column's first child, outside the margin.
	var padding := UI.margin_xy(inner, 10, 8, 10, 10)
	padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(padding)
	_glyph = UI.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_glyph.autowrap_mode = TextServer.AUTOWRAP_OFF
	_glyph.visible = false
	inner.add_child(_glyph)
	var header := UI.row(6)
	inner.add_child(header)
	_title = UI.label("", "Small")
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_title.add_theme_font_size_override("font_size", 13)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	_cost = UI.label("", "Body")
	_cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	_cost.add_theme_color_override("font_color", Palette.WARNING)
	header.add_child(_cost)
	_subtitle = UI.label("", "Caption")
	inner.add_child(_subtitle)
	_body = UI.rich_text()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 12)
	inner.add_child(_body)
	_footer = UI.label("", "Caption")
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_footer)

	_input_setup()


## Dense variant for tables that must show a hand and a market above the fold.
## The full text remains available through the card tooltip; the visible card
## clips to a predictable height instead of growing with every wrapped line.
func _build_compact(width: int) -> void:
	var height := maxi(128, int(float(width) * 1.12))
	if _title != null:
		custom_minimum_size = Vector2(width, height)
		return
	custom_minimum_size = Vector2(width, height)
	clip_contents = true
	var column := UI.column(0)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(0, 3)
	column.add_child(_accent_bar)
	var inner := UI.column(2)
	var padding := UI.margin_xy(inner, 7, 5, 7, 5)
	padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(padding)
	var header := UI.row(4)
	inner.add_child(header)
	_glyph = UI.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	_glyph.autowrap_mode = TextServer.AUTOWRAP_OFF
	_glyph.custom_minimum_size = Vector2(14, 0)
	_glyph.visible = false
	header.add_child(_glyph)
	_title = UI.label("", "Small")
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_title.add_theme_font_size_override("font_size", 12)
	_title.custom_minimum_size = Vector2(0, 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 2
	_title.clip_text = true
	header.add_child(_title)
	_cost = UI.label("", "Body")
	_cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	_cost.add_theme_font_size_override("font_size", 13)
	_cost.add_theme_color_override("font_color", Palette.WARNING)
	header.add_child(_cost)
	_subtitle = UI.label("", "Caption")
	_subtitle.add_theme_font_size_override("font_size", 10)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	_subtitle.clip_text = true
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(_subtitle)
	_body = UI.rich_text()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 11)
	_body.fit_content = false
	_body.scroll_active = false
	_body.clip_contents = true
	inner.add_child(_body)
	_footer = UI.label("", "Caption")
	_footer.add_theme_font_size_override("font_size", 10)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_footer)
	_input_setup()


func _input_setup() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func() -> void:
		_border_color = Palette.FOCUS if selected else Palette.BORDER_STRONG
		_apply_border()
		hovered.emit(card_id, true)
	)
	mouse_exited.connect(func() -> void:
		_border_color = Palette.FOCUS if selected else Palette.BORDER
		_apply_border()
		hovered.emit(card_id, false)
	)
	focus_entered.connect(func() -> void:
		_border_color = Palette.FOCUS
		_apply_border()
	)
	focus_exited.connect(func() -> void:
		_border_color = Palette.FOCUS if selected else Palette.BORDER
		_apply_border()
	)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			Audio.play(Audio.Sfx.CLICK)
			clicked.emit(card_id)
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE):
			clicked.emit(card_id)


func _apply_border() -> void:
	add_theme_stylebox_override("panel", ThemeBuilder.flat(Palette.BG_ELEVATED, _border_color, 2 if selected else 1, ThemeBuilder.RADIUS, 0))


func set_selected(value: bool) -> void:
	selected = value
	_border_color = Palette.FOCUS if value else Palette.BORDER
	_apply_border()


## Small helper to build a card dictionary consistently across games.
static func data(id: String, title: String, subtitle: String = "", cost: String = "", body: String = "", footer: String = "", accent: Color = Color(0, 0, 0, 0), glyph: String = "") -> Dictionary:
	if accent.a <= 0.0:
		accent = Palette.ACCENT
	return {
		"id": id, "title": title, "subtitle": subtitle, "cost": cost,
		"body": body, "footer": footer, "accent": accent, "glyph": glyph,
	}
