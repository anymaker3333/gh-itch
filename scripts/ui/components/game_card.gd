class_name GameCard
extends Button
## Library card for one catalog entry.
##
## A "button" so that keyboard focus, activation (Enter/Space) and hover feedback
## come for free; the visual contents are composed on top with mouse filtering
## disabled so the button itself owns all input.

signal activated(game_id: String)
signal favorite_toggled(game_id: String, now_favorite: bool)

const CARD_WIDTH: int = 300
## Tall enough for the artwork, title, metadata and the status/online row.
## The previous 208 px clipped that last row on every card.
const CARD_HEIGHT: int = 236
const ART_HEIGHT: int = 118
const FOCUS_BORDER: int = 2

var entry: GameEntry = null

var _art: TextureRect
var _art_placeholder: Control
var _title: Label
var _meta: Label
var _status: Label
var _status_box: PanelContainer
var _favorite: Button
var _border: Panel
var _online: Label
var _accent: ColorRect


func _init() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	flat = true
	clip_contents = true
	text = ""
	toggle_mode = false


func configure(game_entry: GameEntry) -> void:
	entry = game_entry
	# `configure()` is called before the card enters the tree (see
	# `library_screen._make_card`), so `_ready()` has not run yet; build the
	# child controls now instead of dereferencing null members.
	_build()
	_accent.color = entry.accent
	var texture: Texture2D = null
	if ResourceLoader.exists(entry.art_path):
		texture = load(entry.art_path) as Texture2D
	if texture != null:
		_art.texture = texture
		_art.visible = true
		_art_placeholder.visible = false
	else:
		_art.visible = false
		_art_placeholder.visible = true
	_title.text = entry.display_name()
	_meta.text = "%s  ·  %s" % [entry.players_text(), entry.minutes_text()]
	_status.text = entry.status_text()
	_status_box.add_theme_stylebox_override("panel", _pill_style(entry.status_color()))
	_favorite.button_pressed = Prefs.is_favorite(entry.id)
	_favorite.text = "★" if Prefs.is_favorite(entry.id) else "☆"
	tooltip_text = "%s\n%s" % [entry.display_name(), entry.description()]


func _ready() -> void:
	_build()
	pressed.connect(_on_pressed)
	focus_entered.connect(_update_border)
	focus_exited.connect(_update_border)
	mouse_entered.connect(_update_border)
	mouse_exited.connect(_update_border)


func _build() -> void:
	if _title != null:
		return  # already built
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var background := ColorRect.new()
	background.color = Palette.BG_PANEL
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(column)

	# --- artwork area -------------------------------------------------------
	var art_wrap := Control.new()
	art_wrap.custom_minimum_size = Vector2(0, ART_HEIGHT)
	art_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art_wrap)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(_art)
	_art_placeholder = _build_placeholder()
	_art_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(_art_placeholder)
	var art_shade := ColorRect.new()
	art_shade.color = Color(0.03, 0.04, 0.06, 0.55)
	art_shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	art_shade.custom_minimum_size = Vector2(0, 44)
	art_shade.offset_top = -44
	art_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(art_shade)

	# --- text area ----------------------------------------------------------
	var info := MarginContainer.new()
	info.add_theme_constant_override("margin_left", 12)
	info.add_theme_constant_override("margin_right", 12)
	info.add_theme_constant_override("margin_top", 10)
	info.add_theme_constant_override("margin_bottom", 10)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(info)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 4)
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(info_box)
	_title = UI.heading("", "Subtitle")
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_title)
	_meta = UI.label("", "Caption")
	_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_meta)
	info_box.add_child(UI.spacer())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(bottom)
	_status = UI.label("", "Caption")
	# A wrapping label in an HBox has a 1 px minimum width, which collapsed the
	# status pill to an empty coloured square.
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box = UI.panel("TransparentPanel")
	_status_box.add_theme_stylebox_override("panel", _pill_style(Palette.TEXT_MUTED))
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_child(_status)
	bottom.add_child(_status_box)
	_online = UI.label("", "Caption")
	_online.visible = false
	_online.autowrap_mode = TextServer.AUTOWRAP_OFF
	_online.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_online.clip_text = true
	_online.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_online)

	# --- accent + favourite + focus border ----------------------------------
	_accent = ColorRect.new()
	_accent.color = Palette.ACCENT
	_accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_accent.custom_minimum_size = Vector2(0, 3)
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_accent)

	_favorite = UI.button("☆", "GhostButton", _on_favorite_pressed)
	_favorite.custom_minimum_size = Vector2(32, 32)
	_favorite.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_favorite.offset_left = -40
	_favorite.offset_top = 8
	_favorite.offset_right = -8
	_favorite.offset_bottom = 40
	_favorite.focus_mode = Control.FOCUS_ALL
	root.add_child(_favorite)

	_border = Panel.new()
	_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.visible = false
	_border.add_theme_stylebox_override("panel", ThemeBuilder.flat(Color(0, 0, 0, 0), Palette.FOCUS, FOCUS_BORDER, ThemeBuilder.RADIUS_LARGE, 0))
	root.add_child(_border)


func _build_placeholder() -> Control:
	var wrap := Control.new()
	var base := ColorRect.new()
	base.color = Palette.BG_ELEVATED
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(base)
	var glyph := UI.centered("◆", "Display")
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override("font_color", Palette.tint(Palette.ACCENT, 0.8))
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(glyph)
	return wrap


func _pill_style(color: Color) -> StyleBoxFlat:
	return ThemeBuilder.flat(Palette.tint(color, 0.16), Palette.tint(color, 0.5), 1, 7, 8)


func _online_color() -> Color:
	match entry.online_status:
		GameEntry.OnlineStatus.VERIFIED:
			return Palette.POSITIVE
		GameEntry.OnlineStatus.IMPLEMENTED:
			return Palette.INFO
		_:
			return Palette.TEXT_DIM


func _update_border() -> void:
	var focused := has_focus()
	var hovered := is_hovered()
	_border.visible = focused or hovered
	if _border.visible:
		_border.add_theme_stylebox_override(
			"panel",
			ThemeBuilder.flat(
				Color(0, 0, 0, 0) if focused else Palette.tint(entry.accent if entry != null else Palette.ACCENT, 0.12),
				Palette.FOCUS if focused else Palette.BORDER_STRONG,
				FOCUS_BORDER if focused else 1,
				ThemeBuilder.RADIUS_LARGE,
				0
			)
		)


func _on_favorite_pressed() -> void:
	if entry == null:
		return
	var now_favorite := Prefs.toggle_favorite(entry.id)
	_favorite.text = "★" if now_favorite else "☆"
	_favorite.add_theme_color_override("font_color", Palette.WARNING if now_favorite else Palette.TEXT_MUTED)
	Audio.play(Audio.Sfx.NOTIFY if now_favorite else Audio.Sfx.CLICK)
	favorite_toggled.emit(entry.id, now_favorite)


func _on_pressed() -> void:
	if entry == null:
		return
	Audio.play(Audio.Sfx.CONFIRM)
	activated.emit(entry.id)


func _gui_input(event: InputEvent) -> void:
	# Keep keyboard/gamepad activation predictable: the Button handles it, we only
	# add a hover sound for parity with the rest of the UI.
	if event is InputEventMouseMotion:
		pass


func refresh_status() -> void:
	if entry == null:
		return
	_status.text = entry.status_text()
	_online.text = entry.online_status_text()
