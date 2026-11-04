extends Node3D

const Rules = preload("res://scripts/rules.gd")
const Pitch = preload("res://scripts/board.gd")
const DicePrompt = preload("res://scripts/turn_dice.gd")
const GOLD = Color("d8ff3e")
var state = Rules.create_game()
var history: Array = []
var kick_plan: Array[Dictionary] = []
var animating = false
var relocation_preview: Dictionary = {}
var dice: Control
var die_badge: Button
var board: Node3D
var hud: Control
var header: MarginContainer
var dock: MarginContainer
var scoreboard: Label
var match_detail: Label
var turn_label: Label
var prompt: Label
var feedback: Label
var primary: Button
var undo_button: Button
var menu: MenuButton
var restart: ConfirmationDialog
var help: AcceptDialog
var random = RandomNumberGenerator.new()
var press_position = Vector2.INF
var touch_index = -1

func _ready() -> void:
	random.randomize()
	board = Pitch.new()
	add_child(board)
	_make_hud()
	get_window().size_changed.connect(_resize)
	_resize()
	_render()

func _label(text: String, size: int, color: Color = Color("ecf3ff")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, accent: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 44)
	button.pressed.connect(callback)
	var style = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = GOLD
	style.border_width_bottom = 2 if accent else 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	button.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.border_width_bottom = 2
	hover.border_color = Color.WHITE
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled = style.duplicate()
	disabled.border_color = Color("52677e")
	button.add_theme_stylebox_override("disabled", disabled)
	var focus = style.duplicate()
	focus.border_width_bottom = 4
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", GOLD if accent else Color("c2d4e9"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color("718298"))
	return button

func _make_hud() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var theme = Theme.new()
	theme.default_font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	theme.default_font_size = 20
	for type in ["Label", "Button"]:
		theme.set_color("font_shadow_color", type, Color(0.01, 0.025, 0.05, 0.95))
		theme.set_constant("shadow_offset_y", type, 1)
		theme.set_constant("shadow_outline_size", type, 1)
	hud.theme = theme
	header = MarginContainer.new()
	header.add_theme_constant_override("margin_left", 6)
	header.add_theme_constant_override("margin_right", 6)
	hud.add_child(header)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	header.add_child(top)
	top.add_child(_label("TFC", 26, GOLD))
	var scores = VBoxContainer.new()
	scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scores.add_theme_constant_override("separation", 0)
	top.add_child(scores)
	scoreboard = _label("", 26)
	scoreboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores.add_child(scoreboard)
	match_detail = _label("", 14, Color("96abc2"))
	match_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores.add_child(match_detail)
	menu = MenuButton.new()
	menu.text = "..."
	menu.tooltip_text = "Match options"
	menu.custom_minimum_size = Vector2(44, 44)
	top.add_child(menu)
	menu.get_popup().add_check_item("Overhead view", 0)
	menu.get_popup().add_item("How to play", 1)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Restart match", 2)
	menu.get_popup().id_pressed.connect(_menu_action)
	dock = MarginContainer.new()
	# Wrapped feedback settles after container layout; refit when its minimum changes.
	dock.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	dock.add_theme_constant_override("margin_left", 6)
	dock.add_theme_constant_override("margin_right", 6)
	hud.add_child(dock)
	var bottom = VBoxContainer.new()
	dock.add_child(bottom)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	bottom.add_child(actions)
	die_badge = DicePrompt.Die.new()
	die_badge.custom_minimum_size = Vector2(44, 44)
	die_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	die_badge.disabled = true
	die_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(die_badge)
	var copy = VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(copy)
	turn_label = _label("", 12)
	turn_label.clip_text = true
	turn_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(turn_label)
	prompt = _label("", 20)
	prompt.clip_text = true
	prompt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(prompt)
	undo_button = _button("Undo", _undo)
	undo_button.add_theme_font_size_override("font_size", 18)
	for style in ["normal", "hover", "pressed", "disabled"]:
		undo_button.get_theme_stylebox(style).content_margin_left = 6
		undo_button.get_theme_stylebox(style).content_margin_right = 6
	undo_button.tooltip_text = "Undo your last move without rerolling"
	actions.add_child(undo_button)
	primary = _button("Kick off", _primary, true)
	primary.custom_minimum_size.x = 72
	primary.add_theme_font_size_override("font_size", 18)
	actions.add_child(primary)
	feedback = _label("", 16, Color("efce95"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.hide()
	bottom.add_child(feedback)
	restart = ConfirmationDialog.new()
	restart.title = "Start a new match?"
	restart.dialog_text = "This replaces the current local match."
	restart.confirmed.connect(func():
		state = Rules.create_game()
		relocation_preview.clear()
		kick_plan.clear()
		history.clear()
		feedback.hide()
		_render()
	)
	hud.add_child(restart)
	help = AcceptDialog.new()
	help.title = "How to play"
	help.dialog_text = "Two players share this screen.\n\nTap the center dice, choose a highlighted player, then tap squares.\nRun one square at a time. Contact with the ball starts a kick.\nTap squares to plan the kick, then press Confirm kick.\nNumbered arrows show the route; Undo removes its last square.\nEach kick has one free step and one 45° bend.\nA pass grants a fresh kick; each player kicks once per turn.\n\nConfirm kick plays the route and ends your turn.\nUndo revises your current turn before confirmation.\nA pass must leave its receiver before confirming.\nIf you only run, use End turn when ready.\nKickoffs must use their exact distance.\nKeepers may stay in the goal mouth; runners must leave.\n20 rolls each, with halftime after 10. Highest score wins.\n\nUse the menu to switch between 3D and overhead views."
	hud.add_child(help)
	dice = DicePrompt.new()
	hud.add_child(dice)
	dice.roll_requested.connect(_roll_turn)

func _resize() -> void:
	var window = get_window()
	var scale_factor = maxf(1.0, DisplayServer.screen_get_scale())
	window.content_scale_size = Vector2i(Vector2(window.size) / scale_factor)
	_layout.call_deferred()

func _layout() -> void:
	var size = get_viewport().get_visible_rect().size
	var safe = Rect2(Vector2.ZERO, size)
	if OS.has_feature("ios") or OS.has_feature("android"):
		var pixels = DisplayServer.get_display_safe_area()
		var ratio = size / Vector2(get_window().size)
		safe = Rect2(Vector2(pixels.position) * ratio, Vector2(pixels.size) * ratio)
	if primary.text.begins_with("Confirm"):
		primary.text = "Confirm\nkick" if size.x < 380 else "Confirm kick"
	var width = minf(820, safe.size.x - 24)
	var left = safe.position.x + (safe.size.x - width) * 0.5
	header.size = Vector2(width, header.get_combined_minimum_size().y)
	header.position = Vector2(left, safe.position.y + 12)
	dock.size = Vector2(width, 0)
	dock.size.y = dock.get_combined_minimum_size().y
	dock.position = Vector2(left, safe.end.y - dock.size.y - 12)
	var top = header.position.y + header.size.y + 12
	board.fit(Rect2(safe.position.x + 12, top, safe.size.x - 24, dock.position.y - top - 12))

func _preview_state() -> Dictionary:
	if not relocation_preview.is_empty():
		return relocation_preview
	return state if kick_plan.is_empty() else kick_plan.back()

func _finish_state(next: Dictionary) -> Dictionary:
	return Rules.continue_after_goal(next) if next.phase == "goal" else Rules.commit_turn(next)

func _confirm_kick() -> void:
	if animating or dice.visible or kick_plan.is_empty():
		return
	var next = _preview_state()
	var finished = _finish_state(next)
	if finished.has("error"):
		feedback.text = finished.error
		feedback.show()
		_layout.call_deferred()
		return
	animating = true
	feedback.hide()
	_render()
	await board.play_kick(state, kick_plan)
	if next.phase == "goal":
		state = next
		scoreboard.text = "BLUE   %d  —  %d   RED" % [state.score.blue, state.score.red]
		prompt.text = "Goal!"
		await get_tree().create_timer(0.65).timeout
	animating = false
	_accept(finished, false)

func _roll_turn() -> void:
	if animating or not state.phase in ["ready", "roll", "halftime"]:
		return
	animating = true
	var values = [random.randi_range(1, 6)]
	var next: Dictionary
	if state.phase == "roll":
		next = Rules.roll_die(state, values[0])
	else:
		values.append(random.randi_range(1, 6))
		next = Rules.kickoff(state, values[0], values[1])
	var moves = 0 if next.has("error") else int(next.remaining)
	if not next.has("error"):
		die_badge.tint = Pitch.BLUE if next.team == "blue" else Pitch.RED
	var result_text = "A tie!" if next.has("error") else "%s · %d %s" % [next.team.to_upper(), moves, "move" if moves == 1 else "moves"]
	menu.disabled = true
	await dice.reveal(values, moves, result_text, die_badge)
	animating = false
	menu.disabled = false
	if not next.has("error"):
		_accept(next, false)

func _render() -> void:
	var view = _preview_state()
	board.update_state(state, view, kick_plan)
	scoreboard.text = "BLUE   %d  —  %d   RED" % [state.score.blue, state.score.red]
	match_detail.text = "%s HALF   ·   ROLLS %d/20 : %d/20" % ["1ST" if view.half == 1 else "2ND", view.rolls.blue, view.rolls.red]
	var instructions = {"ready": "KICKOFF", "roll": "YOUR TURN", "select": "CHOOSE PLAYER", "run": "RUN", "kick": "PLAN KICK", "relocate": "MOVE OUT OF GOAL", "review": "READY TO FINISH", "halftime": "HALFTIME", "goal": "GOAL!", "finished": "FULL TIME"}
	turn_label.text = "%s · %s" % [view.team.to_upper(), instructions.get(view.phase, "")]
	turn_label.add_theme_color_override("font_color", Pitch.BLUE if view.team == "blue" else Pitch.RED)
	var moves_left = view.remaining + (1 if view.free else 0)
	prompt.text = "%d %s left" % [moves_left, "move" if moves_left == 1 else "moves"]
	die_badge.face = maxi(1, state.roll)
	die_badge.tint = Pitch.BLUE if state.team == "blue" else Pitch.RED
	die_badge.modulate.a = 1.0 if state.roll > 0 else 0.25
	primary.text = "End turn"
	primary.visible = view.phase in ["run", "review", "finished"]
	primary.disabled = not Rules.end_turn_errors(view).is_empty()
	feedback.hide()
	if state.phase in ["ready", "roll", "halftime"]:
		prompt.text = "Tap the dice" if state.phase != "roll" else "Tap the die"
		if not animating:
			dice.present(state)
	else:
		dice.hide()
	if view.phase == "select":
		primary.visible = board.eligible_players.is_empty()
	if view.phase == "finished":
		prompt.text = "Draw!" if view.winner == null else "%s wins!" % view.winner.capitalize()
		primary.text = "Play again"
		primary.disabled = false
	if not kick_plan.is_empty():
		primary.show()
		primary.text = "Confirm kick"
		var finished = _finish_state(view)
		primary.disabled = finished.has("error")
		if primary.disabled:
			feedback.text = finished.error
			feedback.show()
	elif view.phase == "review" and primary.disabled:
		feedback.text = str(Rules.end_turn_errors(view)[0])
		feedback.show()
	undo_button.visible = not history.is_empty() or not kick_plan.is_empty()
	undo_button.disabled = animating
	undo_button.tooltip_text = "Revise this turn"
	if animating:
		prompt.text = "Ball in play…"
		primary.disabled = true
		feedback.hide()
	menu.disabled = animating
	_layout.call_deferred()

func _accept(next: Dictionary, remember: bool = true) -> void:
	if next.has("error"):
		feedback.text = next.error
		feedback.show()
		_layout.call_deferred()
		return
	if remember:
		history.append(state)
	else:
		history.clear()
	relocation_preview.clear()
	kick_plan.clear()
	state = next
	feedback.hide()
	_render()

func _primary() -> void:
	if animating or dice.visible:
		return
	if not kick_plan.is_empty():
		_confirm_kick()
	elif state.phase == "finished":
		_accept(Rules.create_game(), false)
	else:
		_accept(Rules.commit_turn(state), false)

func _undo() -> void:
	if animating or dice.visible:
		return
	if not relocation_preview.is_empty():
		relocation_preview.clear()
		_render()
	elif not kick_plan.is_empty():
		kick_plan.pop_back()
		feedback.hide()
		_render()
	elif not history.is_empty():
		state = history.pop_back()
		feedback.hide()
		_render()

func _menu_action(id: int) -> void:
	if animating:
		return
	match id:
		0:
			board.top_view = not board.top_view
			menu.get_popup().set_item_checked(0, board.top_view)
			_layout()
		1: help.popup_centered()
		2: restart.popup_centered()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			press_position = event.position
		elif not event.pressed and event.index == touch_index:
			if not event.canceled and press_position.distance_to(event.position) < 12:
				_tap(event.position)
			touch_index = -1
			press_position = Vector2.INF
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_position = event.position
		else:
			if press_position.distance_to(event.position) < 8:
				_tap(event.position)
			press_position = Vector2.INF

func _tap(position: Vector2) -> void:
	if animating or dice.visible:
		return
	var view = _preview_state()
	var hit = board.pick(position, Rules.legal_targets(view) if state.phase in ["kick", "relocate"] else [])
	if hit.is_empty():
		return
	if hit.has("pawn_id"):
		var picked = Rules.pawn_by_id(view, hit.pawn_id)
		hit = {"x": picked.x, "y": picked.y}
	if state.phase == "kick":
		if view.phase == "relocate":
			var relocated = Rules.relocate(view, hit.x, hit.y)
			if relocated.has("error"):
				feedback.text = relocated.error
				feedback.show()
			else:
				relocation_preview = relocated
				_render()
			return
		var next = Rules.kick_step(view, hit.x, hit.y)
		if next.has("error"):
			feedback.text = "Confirm or undo this path." if view.phase != "kick" else next.error
			feedback.show()
			_layout.call_deferred()
		else:
			relocation_preview.clear()
			kick_plan.append(next)
			feedback.hide()
			_render()
		return
	var p = Rules.pawn_at(state, hit.x, hit.y)
	if state.phase in ["select", "run"] and not p.is_empty() and p.team == state.team:
		if p.id in board.eligible_players:
			_accept(Rules.select_pawn(state, p.id))
	else:
		match state.phase:
			"run": _accept(Rules.run_step(state, hit.x, hit.y))
			"relocate": _accept(Rules.relocate(state, hit.x, hit.y))
