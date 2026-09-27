class_name UiTheme
extends RefCounted
## Interface colours and fonts from docs/05_ART_AUDIO.md §2 and the mockups (docs/mockups/*.png):
## Ruslan Display for titles, Alegreya Sans for the interface, Alegreya Italic for map labels (all OFL,
## art/fonts). Buttons are at least 44 px high (Steam Deck).

const TEXT := Color("e9eeec")
const TEXT2 := Color("c9d5d9")
const MUTED := Color(0.79, 0.84, 0.85, 0.55)
const FIRE := Color("ff9a40")
const FIRE_TEXT := Color("2a1606")
const PANEL := Color(0.035, 0.063, 0.086, 0.72)
const PANEL_SOFT := Color(0.12, 0.14, 0.16, 0.62)
const BIRCH := Color("d9cbb0")
const RED := Color("b8433a")
const OK := Color("8fe3a0")
const PAPER := Color("e7dcc4")
const INK := Color("3a2e24")
const CINNABAR := Color("7a2f25")
const HEALTH := Color("c9473d")
const HEALTH_BONUS := Color("e3806b")
const STAMINA := Color("d9cbb0")

static var _fonts: Dictionary = {}
static var _theme: Theme


static func font(kind: String) -> Font:
	if _fonts.is_empty():
		_fonts["title"] = load("res://art/fonts/RuslanDisplay-Regular.ttf")
		_fonts["ui"] = load("res://art/fonts/AlegreyaSans-Regular.ttf")
		_fonts["bold"] = load("res://art/fonts/AlegreyaSans-Bold.ttf")
		_fonts["italic"] = load("res://art/fonts/Alegreya-Italic.ttf")
		var caps := FontVariation.new()
		caps.base_font = _fonts["bold"]
		caps.spacing_glyph = 2
		_fonts["caps"] = caps
	return _fonts.get(kind, _fonts["ui"])


static func panel(color: Color = PANEL, radius: int = 10, pad: int = 14, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("ui")
	t.default_font_size = 19
	t.set_color("font_color", "Label", TEXT)
	for kind: String in ["Button"]:
		t.set_stylebox("normal", kind, panel(Color(0.06, 0.09, 0.12, 0.85), 10, 16, Color(1, 1, 1, 0.14)))
		t.set_stylebox("hover", kind, panel(Color(0.11, 0.15, 0.19, 0.92), 10, 16, Color(1, 1, 1, 0.3)))
		t.set_stylebox("pressed", kind, panel(Color(0.16, 0.2, 0.24, 0.95), 10, 16, FIRE))
		t.set_stylebox("focus", kind, panel(Color(0, 0, 0, 0), 10, 16, FIRE))
		t.set_stylebox("disabled", kind, panel(Color(0.06, 0.09, 0.12, 0.5), 10, 16, Color(1, 1, 1, 0.06)))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, MUTED)
		t.set_font("font", kind, font("bold"))
	# the fire button: the one action that matters right now
	t.set_type_variation("FireButton", "Button")
	t.set_stylebox("normal", "FireButton", panel(FIRE, 26, 22))
	t.set_stylebox("hover", "FireButton", panel(FIRE.lightened(0.12), 26, 22))
	t.set_stylebox("pressed", "FireButton", panel(FIRE.darkened(0.12), 26, 22))
	t.set_color("font_color", "FireButton", FIRE_TEXT)
	t.set_color("font_hover_color", "FireButton", FIRE_TEXT)
	t.set_color("font_pressed_color", "FireButton", FIRE_TEXT)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font("title"))
	t.set_font_size("font_size", "Title", 34)
	t.set_type_variation("Caps", "Label")
	t.set_font("font", "Caps", font("caps"))
	t.set_font_size("font_size", "Caps", 14)
	t.set_color("font_color", "Caps", BIRCH)
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 16)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("normal", "LineEdit", panel(Color(0.08, 0.11, 0.14, 0.9), 8, 12, Color(1, 1, 1, 0.16)))
	t.set_stylebox("focus", "LineEdit", panel(Color(0, 0, 0, 0), 8, 12, FIRE))
	t.set_stylebox("panel", "PopupPanel", panel(Color(0.05, 0.08, 0.1, 0.96)))
	t.set_stylebox("panel", "TooltipPanel", panel(Color(0.05, 0.08, 0.1, 0.96), 6, 10))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = FIRE
	grabber.set_corner_radius_all(6)
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	_theme = t
	return t


static func label(text: String, size: int = 19, color: Color = TEXT, kind: String = "ui") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
