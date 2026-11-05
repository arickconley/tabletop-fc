extends RefCounted

const INK = Color("101c2e")
const SURFACE = Color("17283e")
const TEXT = Color("f3f6fa")
const MUTED = Color("b0bfd0")
const ACCENT = Color("d8ff3e")
const BORDER = Color("40536b")
const DISPLAY = preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
const FONT = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")

static func _box(fill: Color, border: Color, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func make() -> Theme:
	var theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0.02, 0.04, 0.07, 0.8))
	theme.set_constant("shadow_offset_y", "Label", 1)
	for container in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", container, 8)
	for kind in ["Button", "PrimaryButton", "SelectedButton"]:
		if kind != "Button":
			theme.set_type_variation(kind, "Button")
		var primary = kind == "PrimaryButton"
		var selected = kind == "SelectedButton"
		var fill = ACCENT if primary else SURFACE
		var border = ACCENT if primary or selected else BORDER
		theme.set_stylebox("normal", kind, _box(fill, border))
		theme.set_stylebox("hover", kind, _box(Color("e7ff88") if primary else Color("243b54"), ACCENT if selected else TEXT))
		theme.set_stylebox("pressed", kind, _box(Color("bfdc3b") if primary else INK, ACCENT))
		theme.set_stylebox("disabled", kind, _box(INK, BORDER))
		var focus = _box(Color.TRANSPARENT, TEXT)
		focus.draw_center = false
		focus.set_border_width_all(2)
		focus.set_expand_margin_all(3)
		theme.set_stylebox("focus", kind, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(state, kind, INK if primary else TEXT)
		theme.set_color("font_disabled_color", kind, Color("8293a8"))
		theme.set_color("font_shadow_color", kind, Color.TRANSPARENT)
		theme.set_constant("outline_size", kind, 0)
	var panel = _box(INK, BORDER, 24)
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	for kind in ["PanelContainer", "AcceptDialog", "PopupMenu"]:
		theme.set_stylebox("panel", kind, panel)
	theme.set_stylebox("hover", "PopupMenu", _box(SURFACE, ACCENT))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", ACCENT)
	theme.set_color("font_separator_color", "PopupMenu", MUTED)
	theme.set_constant("v_separation", "PopupMenu", 24)
	theme.set_constant("h_separation", "PopupMenu", 12)
	var window_border = _box(INK, BORDER)
	window_border.expand_margin_top = 40
	theme.set_stylebox("embedded_border", "Window", window_border)
	theme.set_color("title_color", "Window", TEXT)
	theme.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	theme.set_font("title_font", "Window", FONT)
	theme.set_font_size("title_font_size", "Window", 22)
	theme.set_constant("title_height", "Window", 40)
	theme.set_constant("buttons_separation", "AcceptDialog", 12)
	theme.set_constant("buttons_min_height", "AcceptDialog", 48)
	theme.set_constant("buttons_min_width", "AcceptDialog", 44)
	for kind in ["VScrollBar", "HScrollBar"]:
		var track = StyleBoxEmpty.new()
		track.content_margin_left = 4
		track.content_margin_right = 4
		theme.set_stylebox("scroll", kind, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grabber = _box(BORDER if state == "grabber" else MUTED, Color.TRANSPARENT, 4)
			grabber.content_margin_top = 4
			grabber.content_margin_bottom = 4
			theme.set_stylebox(state, kind, grabber)
	return theme

static func button(control: Button, primary: bool = false, selected: bool = false) -> void:
	control.theme_type_variation = "PrimaryButton" if primary else ("SelectedButton" if selected else "Button")
	control.custom_minimum_size = Vector2(44, 48)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
