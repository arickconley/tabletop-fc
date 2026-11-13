extends Control

const UI = preload("res://scripts/ui_theme.gd")
var game: Node3D
var panel: PanelContainer
var pause_button: Button
var skip_button: Button
var resume: Button
var motion: CheckButton
var mute: CheckButton
var caption: Label
var previous_focus: Control
var opened = false

func _init(owner_game: Node3D) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade = ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(UI.INK, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shade.hide()
	panel = PanelContainer.new()
	add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	caption = game._label("PAUSED", 32)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(caption)
	motion = CheckButton.new()
	motion.text = "Reduced motion"
	motion.custom_minimum_size.y = 48
	motion.toggled.connect(func(value): game.set_preference("reduced_motion", value))
	content.add_child(motion)
	mute = CheckButton.new()
	mute.text = "Mute sound"
	mute.custom_minimum_size.y = 48
	mute.toggled.connect(func(value): game.set_preference("muted", value))
	content.add_child(mute)
	resume = game._button("Resume", close, true)
	content.add_child(resume)
	panel.hide()
	pause_button = game._button("Pause", open)
	pause_button.tooltip_text = "Pause (Escape)"
	add_child(pause_button)
	skip_button = game._button("Skip entrance", func(): game.journey.skip_entrance())
	add_child(skip_button)
	resized.connect(_layout)
	_layout()

func _process(_delta: float) -> void:
	pause_button.visible = not opened and (game.screen == "entrance" or (game.screen == "match" and (game.animating or game.computer_busy)))
	skip_button.visible = not opened and game.screen == "entrance"
	if game.journey.skip_requested:
		skip_button.disabled = true
	else:
		skip_button.disabled = false

func _layout() -> void:
	var safe = Rect2(Vector2.ZERO, size)
	if OS.has_feature("ios") or OS.has_feature("android"):
		var pixels = DisplayServer.get_display_safe_area()
		safe = Rect2(Vector2(pixels.position) * size / Vector2(get_window().size), Vector2(pixels.size) * size / Vector2(get_window().size))
	panel.size = Vector2(minf(340, safe.size.x - 32), 0)
	panel.position = safe.position + (safe.size - panel.size) * 0.5
	pause_button.size = pause_button.get_combined_minimum_size()
	pause_button.position = safe.position + Vector2(safe.size.x - pause_button.size.x - 12, 12)
	skip_button.size = skip_button.get_combined_minimum_size()
	skip_button.position = safe.end - skip_button.size - Vector2(12, 12)

func open() -> void:
	if opened:
		return
	opened = true
	game._cancel_pointer()
	previous_focus = get_viewport().gui_get_focus_owner()
	game._save_match()
	get_tree().paused = true
	$Shade.show()
	panel.show()
	caption.text = "PAUSED" if game.screen in ["match", "entrance"] else "OPTIONS"
	resume.text = "Resume" if game.screen in ["match", "entrance"] else "Done"
	motion.set_pressed_no_signal(game.preferences.reduced_motion)
	mute.set_pressed_no_signal(game.preferences.muted)
	_layout()
	resume.grab_focus()

func close() -> void:
	opened = false
	panel.hide()
	$Shade.hide()
	get_tree().paused = false
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not opened and game.celebration.active:
			game.celebration.finish()
			get_viewport().set_input_as_handled()
			return
		if game.help.visible or game.restart.visible or game.menu.get_popup().visible:
			return
		if opened:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif opened and event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var controls = [motion, mute, resume]
		var index = controls.find(get_viewport().gui_get_focus_owner())
		controls[posmod(index + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()
		get_viewport().set_input_as_handled()
