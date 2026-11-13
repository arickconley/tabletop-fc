extends Node3D

const Save = preload("res://scripts/match_save.gd")
const SessionMenu = preload("res://scripts/session_menu.gd")
const MatchAudio = preload("res://scripts/match_audio.gd")
var session_menu: Control
var audio: Node
var preferences = {"reduced_motion": false, "muted": false}
var persistence_enabled = not "--script" in OS.get_cmdline_args()
var save_path = "user://match.save"
var saved_match: Dictionary = {}
var pending_save: Dictionary = {}
var save_error = ""
var keyboard_cell = Vector2i(4, 3)
var keyboard_active = false
var compact_layout = false
const Rules = preload("res://scripts/rules.gd")
const Pitch = preload("res://scripts/board.gd")
const DicePrompt = preload("res://scripts/turn_dice.gd")
const Computer = preload("res://scripts/computer.gd")
const Kits = preload("res://scripts/team_kits.gd")
const Lobby = preload("res://scripts/team_lobby.gd")
const UI = preload("res://scripts/ui_theme.gd")
const GoalCelebration = preload("res://scripts/goal_celebration.gd")
var celebration: Node3D
var journey: Node3D
var team_kits = {"blue": Kits.make(0), "red": Kits.make(1)}
var screen = "home"
var lobby: Control
var pending_home = false
const GOLD = Color("d8ff3e")
var state = Rules.create_game()
var history: Array = []
var kick_plan: Array[Dictionary] = []
var animating = false
var computer_team = "red"
var pending_computer_team = "red"
var computer_busy = false
var computer_thinking = false
var computer_failed = false
var match_generation = 0
var relocation_preview: Dictionary = {}
var dice: Control
var die_badge: Button
var board: Node3D
var hud: Control
var header_shade: ColorRect
var header: MarginContainer
var dock: MarginContainer
var play_area: Rect2
var scoreboard: Label
var match_detail: Label
var turn_label: Label
var prompt: Label
var feedback: Label
var primary: Button
var undo_button: Button
var turn_actions: HBoxContainer
var results: Control
var result_panel: PanelContainer
var result_title: Label
var result_score: Label
var result_actions: VBoxContainer
var result_home: Button
var menu: MenuButton
var restart: ConfirmationDialog
var help: AcceptDialog
var help_body: RichTextLabel
var result_detail: Label
var modal_shade: ColorRect
var random = RandomNumberGenerator.new()
var press_position = Vector2.INF
var touch_index = -1
var mouse_pressed = false
var pointer_last = Vector2.ZERO
var pointer_dragged = false

func _ready() -> void:
	random.randomize()
	board = Pitch.new()
	add_child(board)
	journey = $StadiumJourney
	journey.setup(board)
	audio = MatchAudio.new()
	add_child(audio)
	_load_preferences()
	_make_hud()
	celebration = GoalCelebration.new(self)
	add_child(celebration)
	session_menu = SessionMenu.new(self)
	hud.add_child(session_menu)
	board.kicked.connect(func(): audio.play("kick"))
	_apply_preferences()
	if persistence_enabled:
		saved_match = Save.read_match(save_path)
		if saved_match.has("error"):
			save_error = saved_match.error
			saved_match = {}
		lobby.update_continue(not saved_match.is_empty(), save_error)
	board.camera_changed.connect(_position_confirmation)
	if screen == "match":
		journey.mode = "game"
		journey.groundskeeper.hide()
		journey.hero.hide()
		board.camera.make_current()
	get_window().size_changed.connect(_resize)
	_resize()
	_render()

func _label(text: String, size: int, color: Color = UI.TEXT) -> Label:
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
	button.pressed.connect(func():
		if audio != null:
			audio.play("select")
	)
	UI.button(button, accent)
	return button

func _make_hud() -> void:
	get_viewport().gui_embed_subwindows = true
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.theme = UI.make()
	header_shade = ColorRect.new()
	header_shade.color = Color(UI.INK, 0.94)
	header_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(header_shade)
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
	match_detail = _label("", 14, UI.MUTED)
	match_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores.add_child(match_detail)
	menu = MenuButton.new()
	menu.text = "Menu"
	menu.flat = false
	menu.tooltip_text = "Match options"
	menu.custom_minimum_size = Vector2(44, 44)
	UI.button(menu)
	menu.get_popup().theme = hud.theme
	top.add_child(menu)
	menu.get_popup().add_check_item("Overhead view", 0)
	menu.get_popup().add_item("Reset camera", 7)
	menu.get_popup().add_item("How to play", 1)
	menu.get_popup().add_item("Pause / Options", 6)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("New match", 2)
	menu.get_popup().add_item("Main menu", 5)
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
	actions.custom_minimum_size.y = 48
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
	turn_actions = actions
	undo_button = _button("Undo", _undo)
	undo_button.tooltip_text = "Undo the last step, including reaching the ball"
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
	restart.theme = hud.theme
	restart.dialog_autowrap = true
	UI.button(restart.get_ok_button(), true)
	UI.button(restart.get_cancel_button())
	restart.title = "Start a new match?"
	restart.dialog_text = "This replaces the current local match."
	restart.confirmed.connect(func():
		if pending_home:
			await _open_home()
		else:
			await _open_setup(pending_computer_team)
	)
	hud.add_child(restart)
	help = AcceptDialog.new()
	help.theme = hud.theme
	help.ok_button_text = "Got it"
	UI.button(help.get_ok_button(), true)
	help.title = "MATCH GUIDE"
	help_body = RichTextLabel.new()
	help_body.custom_minimum_size = Vector2(220, 140)
	help_body.add_theme_font_size_override("normal_font_size", 20)
	help_body.text = "GETTING STARTED\nChoose Play match, pick your kit, and play against the computer or a friend.\n\nYOUR TURN\nRoll, choose a highlighted player, then tap adjacent squares to run. Reaching the ball starts a kick.\n\nCAMERA\nDrag the pitch with one finger to rotate; drag up or down to tilt. Tap without dragging to choose a square. Menu offers Reset camera and Overhead view.\n\nKICKING\nTap highlighted squares to plan a route, then Confirm kick. Normal kicks get one free step and one 45° bend. Passes start a fresh kick; each player can kick once per turn.\n\nUNDO\nUndo removes the last step, even after reaching the ball. Tap earlier route squares to rewind. Changes remain editable until you confirm or end the turn.\n\nWINNING\nPlay two halves of ten rolls each. Most goals wins. Kickoffs use the exact dice difference. Keepers may stay in their goal mouth; runners must leave. Only one runner may finish in your defensive box, and the opponent must have a path to the ball.\n\nKEYBOARD\nArrow keys move the square cursor (relative to the screen). Enter selects a square; C confirms a kick or ends a turn; Z undoes; Escape pauses. Tab selects buttons. Reduced motion and sound are in Options."
	help.add_child(help_body)
	hud.add_child(help)
	dice = DicePrompt.new()
	hud.add_child(dice)
	dice.roll_requested.connect(_roll_turn)
	# Keep match options reachable above the central dice overlay.
	hud.move_child(header, -1)
	lobby = Lobby.new(self)
	hud.add_child(lobby)
	lobby.play_requested.connect(func():
		if screen == "home":
			if not saved_match.is_empty() and saved_match.state.phase != "finished":
				pending_home = false
				pending_computer_team = computer_team
				restart.title = "Replace saved match?"
				restart.dialog_text = "Your saved match will be replaced when the new match starts."
				restart.popup_centered_clamped(Vector2i(440, 180), 0.9)
			else:
				_open_setup(computer_team)
	)
	lobby.back_requested.connect(func():
		if screen == "setup":
			_open_home()
	)
	lobby.start_requested.connect(_start_match)
	lobby.continue_requested.connect(_continue_match)
	lobby.options_requested.connect(func(): session_menu.open())
	_make_results()
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.047, 0.09, 0.8)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(modal_shade)
	modal_shade.hide()
	for dialog in [help, restart]:
		dialog.visibility_changed.connect(func(): modal_shade.visible = help.visible or restart.visible)

func _show_help() -> void:
	UI.button(help.get_ok_button(), true)
	var viewport_size = get_viewport().get_visible_rect().size
	var title_height = help.get_theme_constant("title_height", "Window")
	help.popup_centered(Vector2i(mini(560, int(viewport_size.x) - 32), mini(520, int(viewport_size.y) - title_height - 32)))
	help.position.y = maxi(help.position.y, title_height + 16)

func _make_results() -> void:
	results = Control.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(results)
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.047, 0.09, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	results.add_child(shade)
	result_panel = PanelContainer.new()
	result_panel.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	results.add_child(result_panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	result_panel.add_child(content)
	var eyebrow = _label("TABLETOP FC  /  FULL TIME", 16, UI.ACCENT)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(eyebrow)
	result_title = _label("", 44)
	result_title.add_theme_font_override("font", preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf"))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(result_title)
	result_score = _label("", 28)
	result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(result_score)
	result_detail = _label("Two halves. Twenty rolls each.", 18, UI.MUTED)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(result_detail)
	result_actions = VBoxContainer.new()
	result_actions.add_theme_constant_override("separation", 8)
	content.add_child(result_actions)
	result_home = _button("Main menu", _open_home)
	result_actions.add_child(result_home)
	results.hide()

func _open_home() -> void:
	if animating:
		return
	_save_match()
	screen = "to_home"
	animating = true
	match_generation += 1
	computer_busy = false
	lobby.hide()
	_render()
	await journey.to_home()
	screen = "home"
	animating = false
	lobby.present("home")
	lobby.update_continue(not saved_match.is_empty(), save_error)
	_render()

func _open_setup(opponent: String) -> void:
	if animating:
		return
	screen = "to_locker"
	animating = true
	_new_match(opponent)
	lobby.select_opponent(opponent)
	lobby.hide()
	await journey.to_locker()
	screen = "setup"
	animating = false
	lobby.present("setup")
	_layout()

func _start_match(color_index: int, design_index: int, opponent: String) -> void:
	if screen != "setup" or animating:
		return
	screen = "entrance"
	animating = true
	journey.skip_requested = false
	team_kits = {"blue": Kits.make(color_index, design_index), "red": Kits.opponent(color_index, random)}
	board.set_kits(team_kits)
	dice.team_kits = team_kits
	_new_match(opponent)
	await board.prepare_players(state)
	board.update_state(state)
	board.hide_match()
	_layout()
	lobby.set_buttons_enabled(false)
	lobby.hide()
	await journey.walk_out(state)
	animating = false
	screen = "match"
	_save_match()
	audio.play("whistle")
	header.modulate.a = 0.0
	dock.modulate.a = 0.0
	_render()
	var reveal = create_tween().set_parallel(true)
	reveal.tween_property(header, "modulate:a", 1.0, 0.3)
	reveal.tween_property(dock, "modulate:a", 1.0, 0.3)

func _score_text() -> String:
	return "%s   %d  —  %d   %s" % [team_kits.blue.name.to_upper(), state.score.blue, state.score.red, team_kits.red.name.to_upper()]

func _new_match(opponent: String) -> void:
	match_generation += 1
	computer_team = opponent
	computer_busy = false
	computer_thinking = false
	computer_failed = false
	_accept(Rules.create_game(), false)

func _is_computer_turn() -> bool:
	return screen == "match" and computer_team != "" and state.team == computer_team and state.phase not in ["ready", "finished"]

func _computer_current(generation: int) -> bool:
	return generation == match_generation and is_inside_tree() and _is_computer_turn()

func _computer_turn(generation: int) -> void:
	if not _computer_current(generation):
		return
	_render()
	await get_tree().create_timer(0.25, false).timeout
	if not _computer_current(generation):
		return
	while state.phase in ["roll", "halftime"]:
		await _roll_turn(true)
		if not _computer_current(generation):
			if generation == match_generation:
				computer_busy = false
				_render()
			return
		_render()
	computer_thinking = true
	_render()
	var search = Computer.new(state, random.randi())
	while not search.done:
		search.advance()
		await get_tree().process_frame
		while get_tree().paused:
			await get_tree().process_frame
		if not _computer_current(generation):
			return
	computer_thinking = false
	if search.plan.is_empty():
		computer_failed = true
		computer_busy = false
		_render()
		return
	for action in search.plan:
		if action.kind == "end":
			if not kick_plan.is_empty():
				await _confirm_kick(true)
			else:
				_accept(Computer.apply_action(state, action), false)
			break
		var next = Computer.apply_action(_preview_state(), action)
		if next.has("error"):
			computer_failed = true
			break
		if action.kind == "kick":
			relocation_preview.clear()
			kick_plan.append(next)
			_render()
		elif action.kind == "relocate" and not kick_plan.is_empty():
			relocation_preview = next
			_render()
		else:
			_accept(next, false)
		await get_tree().create_timer(0.24 if action.kind in ["select", "run", "relocate"] else 0.1, false).timeout
		if not _computer_current(generation):
			return
		if next.phase == "goal":
			await _confirm_kick(true)
			break
	if generation == match_generation:
		computer_busy = false
		_render()

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
	compact_layout = safe.size.y < 500 and safe.size.x > safe.size.y
	match_detail.visible = not compact_layout
	var width = minf(820, safe.size.x - 24)
	var left = safe.position.x + (safe.size.x - width) * 0.5
	header.size = Vector2(width, header.get_combined_minimum_size().y)
	header.position = Vector2(left, safe.position.y + (4 if compact_layout else 12))
	header_shade.visible = compact_layout and screen == "match" and (celebration == null or not celebration.active) and state.phase != "finished"
	header_shade.size = Vector2(size.x, header.position.y + header.size.y + 2)
	dock.size = Vector2(width, 0)
	dock.size.y = dock.get_combined_minimum_size().y
	dock.position = Vector2(left, safe.end.y - dock.size.y - (4 if compact_layout else 12))
	var top = header.position.y + header.size.y + (2 if compact_layout else 12)
	# Feedback may wrap or disappear without changing the pitch framing.
	var bottom = safe.end.y - (6 if compact_layout else 12) - turn_actions.get_combined_minimum_size().y - (24 if compact_layout else 48)
	play_area = Rect2(safe.position.x + 12, top, safe.size.x - 24, bottom - top - (2 if compact_layout else 12))
	board.fit(play_area)
	journey.resize_view()
	if screen == "match" and state.phase != "finished":
		var parent = turn_actions if compact_layout or kick_plan.is_empty() else hud
		if primary.get_parent() != parent:
			primary.reparent(parent, false)
			_layout.call_deferred()
	_position_confirmation()
	if results.visible:
		var compact = safe.size.y < 500
		result_detail.visible = not compact
		result_title.add_theme_font_size_override("font_size", 32 if compact else 44)
		result_panel.get_child(0).add_theme_constant_override("separation", 8 if compact else 16)
		result_panel.size = Vector2(minf(440, safe.size.x - 32), 0)
		result_panel.size.y = result_panel.get_combined_minimum_size().y
		result_panel.position = safe.position + (safe.size - result_panel.size) * 0.5

func _position_confirmation() -> void:
	if primary.get_parent() == hud and primary.visible:
		primary.size = primary.get_combined_minimum_size()
		var ball = kick_plan.back().ball
		var endpoint = board.camera.unproject_position(board.cell_position(ball.x, ball.y, 0.04))
		var position = endpoint + Vector2(16, -primary.size.y - 16)
		if position.x + primary.size.x > play_area.end.x:
			position.x = endpoint.x - primary.size.x - 16
		if position.y < play_area.position.y:
			position.y = endpoint.y + 16
		primary.position = position.clamp(play_area.position, (play_area.end - primary.size).max(play_area.position))

func _preview_state() -> Dictionary:
	if not relocation_preview.is_empty():
		return relocation_preview
	return state if kick_plan.is_empty() else kick_plan.back()

func _finish_state(next: Dictionary) -> Dictionary:
	return Rules.continue_after_goal(next) if next.phase == "goal" else Rules.commit_turn(next)

func _confirm_kick(automatic: bool = false) -> void:
	if screen != "match" or animating or dice.visible or kick_plan.is_empty() or (_is_computer_turn() and not automatic):
		return
	var next = _preview_state()
	var finished = _finish_state(next)
	if finished.has("error"):
		feedback.text = finished.error
		feedback.show()
		_layout.call_deferred()
		return
	animating = true
	pending_save = _snapshot(finished)
	_save_match()
	feedback.hide()
	_render()
	await board.play_kick(state, kick_plan)
	if next.phase == "goal":
		var origin = state
		state = next
		audio.play("goal")
		await celebration.play(origin, kick_plan)
	animating = false
	pending_save.clear()
	_accept(finished, false)

func _roll_turn(automatic: bool = false) -> void:
	if screen != "match" or animating or (_is_computer_turn() and not automatic) or not state.phase in ["ready", "roll", "halftime"]:
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
		die_badge.tint = Kits.accent(team_kits[next.team])
	var result_text = "A tie!" if next.has("error") else "%s · %d %s" % [team_kits[next.team].name.to_upper(), moves, "move" if moves == 1 else "moves"]
	if not next.has("error"):
		pending_save = _snapshot(next)
		_save_match()
	audio.play("dice")
	await dice.reveal(values, moves, result_text, die_badge)
	animating = false
	menu.disabled = false
	pending_save.clear()
	if not next.has("error"):
		_accept(next, false)

func _render() -> void:
	if screen == "match":
		_save_match()
	var view = _preview_state()
	if screen != "match":
		results.hide()
		board.hide_match()
		header.hide()
		dock.hide()
		primary.hide()
		dice.hide()
		_layout.call_deferred()
		return
	var action_parent = result_actions if state.phase == "finished" else (hud if not kick_plan.is_empty() and not compact_layout else turn_actions)
	if primary.get_parent() != action_parent:
		primary.reparent(action_parent, false)
		if action_parent == result_actions:
			result_actions.move_child(primary, 0)
	results.visible = state.phase == "finished"
	board.update_state(state, view, kick_plan)
	lobby.hide()
	header.show()
	dock.show()
	scoreboard.text = _score_text()
	match_detail.text = "%s HALF   ·   ROLLS %d/20 : %d/20" % ["1ST" if view.half == 1 else "2ND", view.rolls.blue, view.rolls.red]
	var instructions = {"ready": "KICKOFF", "roll": "YOUR TURN", "select": "CHOOSE PLAYER", "run": "RUN", "kick": "PLAN KICK", "relocate": "MOVE OUT OF GOAL", "review": "READY TO FINISH", "halftime": "HALFTIME", "goal": "GOAL!", "finished": "FULL TIME"}
	turn_label.text = "%s · %s" % [team_kits[view.team].name.to_upper(), "COMPUTER" if _is_computer_turn() else instructions.get(view.phase, "")]
	turn_label.add_theme_color_override("font_color", Kits.accent(team_kits[view.team]))
	var moves_left = view.remaining + (1 if view.free else 0)
	prompt.text = "%d %s left" % [moves_left, "move" if moves_left == 1 else "moves"]
	die_badge.face = maxi(1, state.roll)
	die_badge.tint = Kits.accent(team_kits[state.team])
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
	dock.visible = not dice.visible
	if view.phase == "select":
		primary.visible = board.eligible_players.is_empty()
	if view.phase == "finished":
		prompt.text = "Draw!" if view.winner == null else "%s wins!" % team_kits[view.winner].name
		primary.text = "Play again"
		primary.disabled = false
		result_title.text = "HONOURS EVEN" if view.winner == null else (("YOU WIN!" if view.winner == "blue" else "COMPUTER WINS") if computer_team != "" else "%s WINS" % team_kits[view.winner].name.to_upper())
		result_score.text = _score_text()
		header.hide()
		dock.hide()
		primary.grab_focus.call_deferred()
	if not kick_plan.is_empty():
		primary.show()
		primary.text = "Confirm kick"
		var finished = _finish_state(view)
		primary.disabled = finished.has("error")
		if primary.disabled:
			primary.hide()
			feedback.text = finished.error
			feedback.show()
	elif view.phase in ["run", "review"] and primary.disabled:
		feedback.text = str(Rules.end_turn_errors(view)[0])
		feedback.show()
	if not feedback.visible and view.phase not in ["review", "finished"] and (kick_plan.is_empty() or primary.disabled):
		var tips = {"select": "Choose a highlighted player. Arrow keys + Enter also work.", "run": "Run to the ball to start a kick. Z / Undo revises your last step.", "kick": "Plan the highlighted route. One free step and one 45° bend per kick.", "relocate": "Move your runner to a highlighted square outside the goal mouth."}
		if view.opening:
			feedback.text = "Kickoff must use the exact dice difference; no free step."
		else:
			feedback.text = tips.get(view.phase, "")
		feedback.visible = not feedback.text.is_empty() and not compact_layout
	if not save_error.is_empty():
		feedback.text = save_error
		feedback.show()
	if animating:
		prompt.text = "Ball in play…"
		primary.disabled = true
		primary.hide()
		feedback.hide()
	if _is_computer_turn():
		primary.hide()
		feedback.hide()
		if computer_thinking:
			prompt.text = "Thinking…"
		if dice.visible:
			prompt.text = "Rolling…"
			dice.first.disabled = true
			dice.second.disabled = true
			dice.caption.text = "Computer is rolling…"
		if computer_failed:
			primary.text = "Take over"
			primary.show()
			primary.disabled = false
			feedback.text = "Computer could not finish. Take over this turn, or restart from Menu."
			feedback.show()
	elif state.phase == "ready" and computer_team != "":
		dice.caption.text = "You’re %s · Computer is %s\nTap the dice · highest roll kicks off" % [team_kits.blue.name, team_kits.red.name]
	undo_button.visible = (not history.is_empty() or not kick_plan.is_empty() or not relocation_preview.is_empty()) and view.phase != "finished" and not _is_computer_turn()
	undo_button.disabled = animating or computer_busy
	menu.disabled = false
	for id in [0, 1, 2, 5, 7]:
		menu.get_popup().set_item_disabled(menu.get_popup().get_item_index(id), animating or computer_busy)
	_layout.call_deferred()
	if _is_computer_turn() and not computer_busy and not animating and not computer_failed:
		computer_busy = true
		_computer_turn.call_deferred(match_generation)

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
	if computer_failed:
		computer_team = ""
		computer_failed = false
		computer_busy = false
		_render()
		return
	if screen != "match" or animating or dice.visible or computer_busy or _is_computer_turn():
		return
	if not kick_plan.is_empty():
		_confirm_kick()
	elif state.phase == "finished":
		_rematch()
	else:
		_accept(Rules.commit_turn(state), false)

func _undo() -> void:
	if screen != "match" or animating or dice.visible or computer_busy or _is_computer_turn() or state.phase == "finished":
		return
	if not relocation_preview.is_empty():
		relocation_preview.clear()
	elif not kick_plan.is_empty():
		kick_plan.pop_back()
	elif not history.is_empty():
		state = history.pop_back()
	else:
		return
	feedback.hide()
	_render()

func _revisit_square(hit: Dictionary) -> bool:
	if not relocation_preview.is_empty():
		var before = kick_plan.back()
		if Rules.same(hit, Rules.pawn_by_id(before, before.relocating)):
			relocation_preview.clear()
			_render()
			return true
	if not kick_plan.is_empty():
		if Rules.same(hit, kick_plan.back().ball):
			_render()
			return true
		for i in range(kick_plan.size() - 2, -1, -1):
			if Rules.same(hit, kick_plan[i].ball):
				kick_plan.resize(i + 1)
				relocation_preview.clear()
				_render()
				return true
		if Rules.same(hit, state.ball):
			kick_plan.clear()
			relocation_preview.clear()
			_render()
			return true
	# A legal kick onto the run trail takes priority over undoing the run.
	if state.phase == "kick":
		for target in Rules.legal_targets(_preview_state()):
			if Rules.same(hit, target):
				return false
	for i in range(history.size() - 1, -1, -1):
		var previous = history[i]
		if previous.selected == state.selected and previous.phase == "run":
			if Rules.same(hit, Rules.pawn_by_id(previous, previous.selected)):
				state = previous
				history.resize(i)
				kick_plan.clear()
				relocation_preview.clear()
				_render()
				return true
	return false

func _menu_action(id: int) -> void:
	if id == 6:
		session_menu.open()
		return
	if screen != "match" or animating or computer_busy:
		return
	match id:
		0:
			board.top_view = not board.top_view
			menu.get_popup().set_item_checked(0, board.top_view)
			_layout()
		7:
			board.orbit_yaw = 0.0
			board.orbit_tilt = 0.0
			board.top_view = false
			menu.get_popup().set_item_checked(0, false)
			_layout()
		1: _show_help()
		2, 3, 4, 5:
			pending_home = id == 5
			pending_computer_team = computer_team if id in [2, 5] else ("red" if id == 3 else "")
			restart.title = "Return to main menu?" if pending_home else "Start a new match?"
			restart.ok_button_text = "Leave match" if pending_home else "New match"
			restart.dialog_text = "Leave this match and return to the main menu?" if pending_home else "Leave this match and choose your kit for a new game?"
			if state.phase == "ready":
				if pending_home:
					await _open_home()
				else:
					await _open_setup(pending_computer_team)
			else:
				restart.popup_centered_clamped(Vector2i(440, 180), 0.9)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_keyboard(event)
		return
	if not _can_orbit():
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1 and not mouse_pressed and play_area.has_point(event.position):
			touch_index = event.index
			_begin_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and touch_index == -1 and play_area.has_point(event.position):
			mouse_pressed = true
			_begin_pointer(event.position)

func _can_orbit() -> bool:
	return screen == "match" and not animating and not dice.visible and not computer_busy and state.phase != "finished" and not get_tree().paused and not help.visible and not restart.visible and not menu.get_popup().visible

func _begin_pointer(position: Vector2) -> void:
	press_position = position
	pointer_last = position
	pointer_dragged = false
	get_viewport().set_input_as_handled()

func _cancel_pointer() -> void:
	touch_index = -1
	mouse_pressed = false
	press_position = Vector2.INF
	pointer_dragged = false

func _drag_pointer(position: Vector2) -> void:
	if not _can_orbit():
		_cancel_pointer()
		return
	if not pointer_dragged and press_position.distance_to(position) < 12:
		return
	pointer_dragged = true
	board.orbit(position - pointer_last, play_area)
	pointer_last = position

func _end_pointer(position: Vector2, canceled: bool = false) -> void:
	var tap = not canceled and not pointer_dragged and press_position.distance_to(position) < 12 and play_area.has_point(position) and _can_orbit()
	_cancel_pointer()
	if tap:
		_tap(position)

func _tap(position: Vector2) -> void:
	if screen != "match" or animating or dice.visible or computer_busy or _is_computer_turn():
		return
	var view = _preview_state()
	var targets = Rules.legal_targets(view) if state.phase in ["kick", "relocate"] else []
	var path_targets: Array = []
	if not kick_plan.is_empty():
		path_targets.append(state.ball)
		for step in kick_plan:
			path_targets.append(step.ball)
	if not relocation_preview.is_empty():
		var before = kick_plan.back()
		path_targets.append(Rules.pawn_by_id(before, before.relocating))
	for previous in history:
		if previous.selected == state.selected and previous.phase == "run":
			path_targets.append(Rules.pawn_by_id(previous, previous.selected))
	var hit = board.pick(position, targets, path_targets)
	if hit.is_empty():
		return
	if hit.has("pawn_id"):
		var picked = Rules.pawn_by_id(view, hit.pawn_id)
		hit = {"x": picked.x, "y": picked.y}
	_choose_square(hit)

func _choose_square(hit: Dictionary) -> void:
	if screen != "match" or animating or dice.visible or computer_busy or _is_computer_turn():
		return
	var view = _preview_state()
	audio.play("select")
	if _revisit_square(hit):
		return
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
			feedback.text = "Confirm the kick, or use Undo to revise the route." if view.phase != "kick" else next.error
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

func _keyboard(event: InputEventKey) -> void:
	if screen != "match" or animating or dice.visible or computer_busy or help.visible or restart.visible:
		return
	var direction = Vector2.ZERO
	match event.keycode:
		KEY_LEFT: direction = Vector2.LEFT
		KEY_RIGHT: direction = Vector2.RIGHT
		KEY_UP: direction = Vector2.UP
		KEY_DOWN: direction = Vector2.DOWN
		KEY_Z, KEY_BACKSPACE: _undo()
		KEY_C: _primary()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if keyboard_active:
				_choose_square({"x": keyboard_cell.x, "y": keyboard_cell.y})
		_: return
	if direction != Vector2.ZERO:
		var origin = board.camera.unproject_position(board.cell_position(keyboard_cell.x, keyboard_cell.y))
		var best = Vector2i.ZERO
		var score = -INF
		for step in Rules.ORTHOGONAL:
			var projected = board.camera.unproject_position(board.cell_position(keyboard_cell.x + step.x, keyboard_cell.y + step.y)) - origin
			var alignment = projected.normalized().dot(direction)
			if alignment > score:
				score = alignment
				best = step
		keyboard_cell += best
		keyboard_cell.x = clampi(keyboard_cell.x, -1, 10)
		keyboard_cell.y = clampi(keyboard_cell.y, 0, 5)
		keyboard_active = true
		get_viewport().gui_release_focus()
		board.show_keyboard_cell(keyboard_cell)
	get_viewport().set_input_as_handled()

func _snapshot(next: Dictionary = {}) -> Dictionary:
	return {"version": 1, "state": state.duplicate(true) if next.is_empty() else next.duplicate(true),
		"history": history.duplicate(true) if next.is_empty() else [], "plan": kick_plan.duplicate(true) if next.is_empty() else [],
		"relocation": relocation_preview.duplicate(true) if next.is_empty() else {},
		"opponent": computer_team, "kits": team_kits.duplicate(true)}

func _save_match() -> void:
	if not persistence_enabled or screen != "match":
		return
	var data = _snapshot() if pending_save.is_empty() else pending_save
	if data == saved_match:
		return
	var error = Save.write_match(save_path, data)
	if error == OK:
		saved_match = data.duplicate(true)
		save_error = ""
	else:
		save_error = "Could not save this match. Keep the game open to preserve progress."

func _continue_match() -> void:
	if saved_match.is_empty() or animating:
		return
	match_generation += 1
	state = saved_match.state.duplicate(true)
	history = saved_match.history.duplicate(true)
	kick_plan.assign(saved_match.plan.duplicate(true))
	relocation_preview = saved_match.relocation.duplicate(true)
	computer_team = saved_match.opponent
	for team in ["blue", "red"]:
		team_kits[team] = Kits.make(saved_match.kits[team].index, saved_match.kits[team].design)
	board.set_kits(team_kits)
	dice.team_kits = team_kits
	if computer_team == state.team:
		kick_plan.clear()
		relocation_preview.clear()
	computer_busy = false
	computer_failed = false
	journey.mode = "game"
	journey.room.hide()
	journey.groundskeeper.hide()
	if is_instance_valid(journey.hero):
		journey.hero.hide()
	screen = "match"
	board.ball_target = Vector3.INF
	board.camera.make_current()
	_render()

func _rematch() -> void:
	match_generation += 1
	computer_busy = false
	computer_failed = false
	board.ball_target = Vector3.INF
	_accept(Rules.create_game(), false)
	audio.play("whistle")

func _load_preferences() -> void:
	if not persistence_enabled:
		return
	var config = ConfigFile.new()
	if config.load("user://preferences.cfg") == OK:
		for key in preferences:
			var value = config.get_value("options", key, false)
			if value is bool:
				preferences[key] = value

func set_preference(key: String, value: bool) -> void:
	if not preferences.has(key):
		return
	preferences[key] = value
	_apply_preferences()
	if persistence_enabled:
		var config = ConfigFile.new()
		for option in preferences:
			config.set_value("options", option, preferences[option])
		if config.save("user://preferences.cfg") != OK:
			save_error = "Options could not be saved on this device."

func _apply_preferences() -> void:
	board.reduced_motion = preferences.reduced_motion
	dice.reduced_motion = preferences.reduced_motion
	audio.muted = preferences.muted
	if preferences.reduced_motion and screen == "entrance":
		journey.skip_entrance()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_cancel_pointer()
	if not persistence_enabled or session_menu == null:
		return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_save_match()
		if screen in ["match", "entrance"]:
			session_menu.open()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_match()

func _input(event: InputEvent) -> void:
	# Own a board gesture through release, including when it crosses a HUD control.
	if touch_index >= 0:
		if event is InputEventScreenDrag and event.index == touch_index:
			_drag_pointer(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch:
			if event.index == touch_index and not event.pressed:
				_end_pointer(event.position, event.canceled)
			elif event.pressed and event.index != touch_index:
				_cancel_pointer()
			get_viewport().set_input_as_handled()
	elif mouse_pressed:
		if event is InputEventMouseMotion:
			_drag_pointer(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_pointer(event.position)
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and not menu.get_popup().visible:
		_keyboard(event)
