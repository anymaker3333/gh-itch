class_name Palette
extends RefCounted
## Single source of truth for the Game Hub visual identity.
##
## A dark "control room" theme: deep blue-black surfaces, layered elevation,
## a cool primary accent for navigation and a warm/positive secondary accent for
## confirmations. Game cards get their own accent colour from the catalog.
##
## The colour tokens are `static var`s rather than constants so `ThemeSvc` can
## swap the active menu palette at runtime. `defaults()` remains the baseline.

static var BG_DEEPEST := Color("#080a0f")
static var BG_BASE := Color("#0d1118")
static var BG_PANEL := Color("#141a24")
static var BG_ELEVATED := Color("#1b2230")
static var BG_HOVER := Color("#222b3b")
static var BG_ACTIVE := Color("#2a3446")

static var BORDER := Color("#2a3345")
static var BORDER_STRONG := Color("#3b4761")

static var TEXT := Color("#e8eef8")
static var TEXT_MUTED := Color("#93a1b8")
static var TEXT_DIM := Color("#6b7789")
static var TEXT_ON_ACCENT := Color("#04121f")

static var ACCENT := Color("#4ea1ff")
static var ACCENT_HOVER := Color("#6fb4ff")
static var ACCENT_PRESSED := Color("#3d84d6")
static var ACCENT_SOFT := Color("#1d3552")
static var ACCENT_DIM := Color("#152a44")

static var POSITIVE := Color("#39d98a")
static var WARNING := Color("#ffc24b")
static var DANGER := Color("#ff5f6d")
static var INFO := Color("#5ac8fa")

static var FOCUS := Color("#8ecbff")


## Every configurable colour token, in the order custom theme files are documented.
const THEME_KEYS: Array[String] = [
	"bg_deepest", "bg_base", "bg_panel", "bg_elevated", "bg_hover", "bg_active",
	"border", "border_strong", "text", "text_muted", "text_dim", "text_on_accent",
	"accent", "accent_hover", "accent_pressed", "accent_soft", "accent_dim",
	"positive", "warning", "danger", "info", "focus",
]


## The built-in control-room palette. Kept separate from the live values so a
## theme can always return here, even after another palette has been applied.
static func defaults() -> Dictionary:
	return {
		"bg_deepest": "#080a0f", "bg_base": "#0d1118", "bg_panel": "#141a24",
		"bg_elevated": "#1b2230", "bg_hover": "#222b3b", "bg_active": "#2a3446",
		"border": "#2a3345", "border_strong": "#3b4761",
		"text": "#e8eef8", "text_muted": "#93a1b8", "text_dim": "#6b7789",
		"text_on_accent": "#04121f",
		"accent": "#4ea1ff", "accent_hover": "#6fb4ff", "accent_pressed": "#3d84d6",
		"accent_soft": "#1d3552", "accent_dim": "#152a44",
		"positive": "#39d98a", "warning": "#ffc24b", "danger": "#ff5f6d",
		"info": "#5ac8fa", "focus": "#8ecbff",
	}


## Current values as hex strings; used as the base when a partial theme is loaded.
static func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for key: String in THEME_KEYS:
		out[key] = snapshot_raw(key).to_html(false)
	return out


## Merge a dictionary of colour tokens into the live palette. Missing or invalid
## values keep their current colour, so a theme can override only what it needs.
static func apply(values: Dictionary) -> void:
	for key: String in THEME_KEYS:
		if not values.has(key):
			continue
		var text := String(values[key])
		if not Color.html_is_valid(text):
			continue
		set_color(key, Color(text))


static func reset() -> void:
	apply(defaults())


## Internal mapping from the serialized token name to the static property.
static func snapshot_raw(key: String) -> Color:
	match key:
		"bg_deepest": return BG_DEEPEST
		"bg_base": return BG_BASE
		"bg_panel": return BG_PANEL
		"bg_elevated": return BG_ELEVATED
		"bg_hover": return BG_HOVER
		"bg_active": return BG_ACTIVE
		"border": return BORDER
		"border_strong": return BORDER_STRONG
		"text": return TEXT
		"text_muted": return TEXT_MUTED
		"text_dim": return TEXT_DIM
		"text_on_accent": return TEXT_ON_ACCENT
		"accent": return ACCENT
		"accent_hover": return ACCENT_HOVER
		"accent_pressed": return ACCENT_PRESSED
		"accent_soft": return ACCENT_SOFT
		"accent_dim": return ACCENT_DIM
		"positive": return POSITIVE
		"warning": return WARNING
		"danger": return DANGER
		"info": return INFO
		"focus": return FOCUS
	return Color.WHITE


static func set_color(key: String, value: Color) -> void:
	match key:
		"bg_deepest": BG_DEEPEST = value
		"bg_base": BG_BASE = value
		"bg_panel": BG_PANEL = value
		"bg_elevated": BG_ELEVATED = value
		"bg_hover": BG_HOVER = value
		"bg_active": BG_ACTIVE = value
		"border": BORDER = value
		"border_strong": BORDER_STRONG = value
		"text": TEXT = value
		"text_muted": TEXT_MUTED = value
		"text_dim": TEXT_DIM = value
		"text_on_accent": TEXT_ON_ACCENT = value
		"accent": ACCENT = value
		"accent_hover": ACCENT_HOVER = value
		"accent_pressed": ACCENT_PRESSED = value
		"accent_soft": ACCENT_SOFT = value
		"accent_dim": ACCENT_DIM = value
		"positive": POSITIVE = value
		"warning": WARNING = value
		"danger": DANGER = value
		"info": INFO = value
		"focus": FOCUS = value


## Returns the accent for a game (falls back to the primary accent).
static func game_accent(entry: GameEntry) -> Color:
	if entry == null:
		return ACCENT
	return entry.accent


## Soft tint used for card backgrounds/badges.
static func tint(color: Color, alpha: float = 0.16) -> Color:
	return Color(color.r, color.g, color.b, alpha)


## Slightly darkened variant for gradients.
static func shade(color: Color, factor: float = 0.65) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


static func lighten(color: Color, amount: float = 0.25) -> Color:
	return color.lerp(Color.WHITE, amount)
