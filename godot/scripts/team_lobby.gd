class_name TeamLobby
extends Control

signal play_requested
signal back_requested
signal start_requested(color_index: int, design_index: int, opponent: String)

const Kits = preload("res://scripts/team_kits.gd")
const UI = preload("res://scripts/ui_theme.gd")
var game: Node3D
var page = "home"
var selected_color = 0
var selected_design = 0
var opponent = "red"
var preview_player: Node3D:
	get: return game.journey.hero
var shade: ColorRect
var broadcast: Label
var crest: Label
var home: VBoxContainer
var setup: VBoxContainer
var setup_scroll: ScrollContainer
var footer: HBoxContainer
var swatches: GridContainer
var designs: HBoxContainer
var modes: HBoxContainer
var color_label: Label
var title: Label
var tagline: Label
var how_to_button: Button
var play_button: Button
var start_button: Button
var back_button: Button

func _init(match_game: Node3D) -> void:
	game = match_game

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	shade = ColorRect.new()
	shade.material = ShaderMaterial.new()
	shade.material.shader = preload("res://scripts/menu_backdrop.gdshader")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	broadcast = game._label("MATCHDAY  /  TABLETOP FC", 14, UI.ACCENT)
	add_child(broadcast)
	home = VBoxContainer.new()
	home.add_theme_constant_override("separation", 8)
	add_child(home)
	tagline = game._label("BIG GAME. SMALL PITCH.", 14, UI.MUTED)
	home.add_child(tagline)
	title = game._label("TABLE\nTOP", 68)
	title.add_theme_font_override("font", preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf"))
	title.add_theme_constant_override("line_spacing", -20)
	title.add_theme_color_override("font_shadow_color", UI.INK)
	title.add_theme_constant_override("shadow_offset_y", 4)
	home.add_child(title)
	crest = game._label(" FC ", 30, UI.INK)
	crest.add_theme_font_override("font", preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf"))
	var badge = StyleBoxFlat.new()
	badge.bg_color = UI.ACCENT
	crest.add_theme_stylebox_override("normal", badge)
	crest.rotation = -0.13
	title.add_child(crest)
	play_button = game._button("Play match", func(): play_requested.emit(), true)
	home.add_child(play_button)
	how_to_button = game._button("How to play", func(): game._show_help())
	home.add_child(how_to_button)
	setup_scroll = ScrollContainer.new()
	setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(setup_scroll)
	setup = VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", 8)
	setup_scroll.add_child(setup)
	setup.add_child(game._label("MATCH SETUP", 14, UI.ACCENT))
	setup.add_child(game._label("Choose your kit", 34))
	color_label = game._label("", 20)
	setup.add_child(color_label)
	swatches = GridContainer.new()
	swatches.columns = 6
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	setup.add_child(swatches)
	for i in Kits.COLORS.size():
		var swatch = Button.new()
		swatch.name = Kits.NAMES[i]
		swatch.tooltip_text = Kits.NAMES[i]
		swatch.custom_minimum_size = Vector2(44, 44)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.pressed.connect(select_color.bind(i))
		swatches.add_child(swatch)
	setup.add_child(game._label("SHIRT", 14, UI.MUTED))
	designs = HBoxContainer.new()
	designs.add_theme_constant_override("separation", 8)
	setup.add_child(designs)
	for i in Kits.DESIGNS.size():
		var button = game._button(Kits.DESIGNS[i], select_design.bind(i))
		button.add_theme_font_size_override("font_size", 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		designs.add_child(button)
	setup.add_child(game._label("OPPONENT", 14, UI.MUTED))
	modes = HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	setup.add_child(modes)
	for choice in ["red", ""]:
		var button = game._button("Computer" if choice == "red" else "2 players", select_opponent.bind(choice))
		button.add_theme_font_size_override("font_size", 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(button)
	var note = game._label("Your opponent wears a contrasting kit.", 16, UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup.add_child(note)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)
	start_button = game._button("Start match", func(): start_requested.emit(selected_color, selected_design, opponent), true)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button = game._button("Back", func(): back_requested.emit())
	footer.add_child(back_button)
	footer.add_child(start_button)
	resized.connect(_layout)
	_refresh()
	present("home")

func present(next_page: String) -> void:
	page = next_page
	modulate.a = 1.0
	show()
	home.visible = page == "home"
	setup_scroll.visible = page == "setup"
	footer.visible = page == "setup"
	set_buttons_enabled(true)
	broadcast.visible = page == "home"
	shade.material.set_shader_parameter("locker", page != "home")
	_layout.call_deferred()
	(play_button if page == "home" else swatches.get_child(selected_color)).grab_focus.call_deferred()

func set_buttons_enabled(enabled: bool) -> void:
	for button in find_children("*", "Button", true, false):
		button.disabled = not enabled

func select_color(index: int) -> void:
	selected_color = clampi(index, 0, Kits.COLORS.size() - 1)
	_refresh()

func select_design(index: int) -> void:
	selected_design = clampi(index, 0, Kits.DESIGNS.size() - 1)
	_refresh()

func select_opponent(value: String) -> void:
	opponent = value
	_refresh()

func _refresh() -> void:
	color_label.text = "TEAM COLOUR · " + Kits.NAMES[selected_color]
	for i in swatches.get_child_count():
		var button: Button = swatches.get_child(i)
		var style = StyleBoxFlat.new()
		style.bg_color = Kits.COLORS[i]
		style.set_corner_radius_all(8)
		style.border_color = UI.ACCENT
		style.set_border_width_all(3 if i == selected_color else 0)
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, style)
		var focus = style.duplicate()
		focus.draw_center = false
		focus.border_color = UI.TEXT
		focus.set_border_width_all(2)
		focus.set_expand_margin_all(3)
		button.add_theme_stylebox_override("focus", focus)
		button.text = "✓" if i == selected_color else ""
		button.add_theme_color_override("font_color", UI.INK if Kits.COLORS[i].get_luminance() > 0.4 else UI.TEXT)
		button.add_theme_color_override("font_hover_color", button.get_theme_color("font_color"))
	for i in designs.get_child_count():
		designs.get_child(i).text = ("✓ " if i == selected_design else "") + Kits.DESIGNS[i]
		UI.button(designs.get_child(i), false, i == selected_design)
	for i in modes.get_child_count():
		var selected = (i == 0) == (opponent == "red")
		modes.get_child(i).text = ("✓ " if selected else "") + ("Computer" if i == 0 else "2 players")
		UI.button(modes.get_child(i), false, selected)
	game.journey.dress(Kits.make(selected_color, selected_design))

func _layout() -> void:
	if setup == null:
		return
	var safe = Rect2(Vector2.ZERO, size)
	if OS.has_feature("ios") or OS.has_feature("android"):
		var pixels = DisplayServer.get_display_safe_area()
		var ratio = size / Vector2(get_window().size)
		safe = Rect2(Vector2(pixels.position) * ratio, Vector2(pixels.size) * ratio)
	var portrait = safe.size.x < 700 and safe.size.y > safe.size.x
	shade.material.set_shader_parameter("portrait", portrait)
	var compact = portrait or safe.size.y < 440
	var home_scale = 1.0 if compact else clampf(minf(safe.size.x / 900.0, safe.size.y / 600.0) * 1.35, 1.15, 1.8)
	title.add_theme_font_size_override("font_size", roundi((58 if compact else 82) * home_scale))
	title.add_theme_constant_override("line_spacing", roundi(-20 * home_scale))
	title.add_theme_constant_override("shadow_offset_y", roundi(4 * home_scale))
	crest.add_theme_font_size_override("font_size", roundi(30 * home_scale))
	crest.position = Vector2(120 if compact else 166, 85 if compact else 115) * home_scale
	broadcast.add_theme_font_size_override("font_size", roundi(14 * home_scale))
	broadcast.position = safe.position + Vector2(24, 14) * home_scale
	tagline.add_theme_font_size_override("font_size", roundi(14 * home_scale))
	for button in [play_button, how_to_button]:
		button.add_theme_font_size_override("font_size", roundi(20 * home_scale))
		button.custom_minimum_size.y = 44 * home_scale
	home.add_theme_constant_override("separation", roundi(8 * home_scale))
	var width = minf(370, safe.size.x - 32) if portrait else minf(390, safe.size.x * 0.5 - 16)
	swatches.columns = 6 if width >= 304 else 4
	setup.get_child(0).visible = safe.size.y >= 500
	setup.get_child(1).add_theme_font_size_override("font_size", 26 if safe.size.y < 500 else 34)
	setup.add_theme_constant_override("separation", 8)
	var home_width = minf(260, safe.size.x - 48) if compact else minf(300 * home_scale, safe.size.x * 0.36)
	home.size = Vector2(home_width, 0)
	home.size.y = home.get_combined_minimum_size().y
	footer.size = Vector2(width, 48)
	var left = (safe.size.x - width) * 0.5 if portrait else safe.size.x * 0.5
	if portrait:
		var hero_height = clampf(safe.size.y * 0.36, 160, 300)
		home.position = safe.position + Vector2(24, maxf(90, safe.size.y - home.size.y - 20))
		footer.position = safe.position + Vector2(left, safe.size.y - 60)
		setup_scroll.position = safe.position + Vector2(left, hero_height + 8)
		setup_scroll.size = Vector2(width, maxf(80, safe.size.y - hero_height - 80))
	else:
		home.position = safe.position + Vector2(32 * home_scale, maxf(48, (safe.size.y - home.size.y) * 0.5))
		var height = minf(480, safe.size.y - 100)
		setup_scroll.position = safe.position + Vector2(left, (safe.size.y - height - 60) * 0.5)
		setup_scroll.size = Vector2(width, height)
		footer.position = setup_scroll.position + Vector2(0, height + 8)
