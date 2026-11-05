extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = MatchScene.instantiate()
	game.screen = "match"
	game.computer_team = ""
	root.add_child(game)
	if DisplayServer.get_name() == "headless":
		# The dummy display reports 64x64; use a real viewport for UI assertions.
		root.size_changed.disconnect(game._resize)
		root.content_scale_size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	assert(game.dice.visible and game.dice.second.visible, "Opening kickoff needs the center dice")
	assert(game.header is MarginContainer and game.dock is MarginContainer, "The HUD must have no panel backgrounds")
	assert(game.dice.find_children("*", "PanelContainer", true, false).is_empty())
	assert(game.dice.first.viewport.transparent_bg and game.dice.first.viewport.own_world_3d)
	for value in range(1, 7):
		game.dice.first.face = value
		var side = game.dice.first.rig.get_node("Face%d" % value)
		assert(side.get_child_count() == value, "Each 3D face must have the correct number of pips")
		var facing = game.dice.first.rig.basis * side.basis.y
		assert(facing.dot(Vector3.BACK) > 0.8, "The rolled value must be the camera-facing face")
	game.dice.first.face = 5
	assert(not game.primary.visible)
	await process_frame
	await process_frame
	assert(game.dock.size.y < 80, "The idle strip must stay compact")
	await _snapshot("-dice")
	# A tied kickoff remains on the dice, without consuming a turn.
	_seed_roll(game, [3, 3])
	await game._roll_turn()
	assert(game.state.phase == "ready" and game.dice.visible and not game.animating)
	assert(not game.dice.first.disabled)
	assert(game.dice.caption.text.contains("tie"))
	_seed_roll(game, [6, 4])
	await game._roll_turn()
	assert(game.state.phase == "kick" and game.state.remaining == 2)
	assert(not game.dice.visible and game.die_badge.face == 2)
	assert(not game.dice.first.rolling)
	assert((game.die_badge.rig.basis * game.die_badge.rig.get_node("Face2").basis.y).dot(Vector3.BACK) > 0.8)
	assert(game.board.pieces.size() == game.state.pawns.size())
	assert(game.board.stadium.stands.size() == 2 and game.board.stadium.towers.size() == 4)
	game.board.stadium.update_view(Vector3(0, 12, 11), false)
	assert(not game.board.stadium.stands[1].visible and game.board.stadium.stands[0].visible)
	game.board.stadium.update_view(Vector3(13, 18, 0), false)
	assert(game.board.stadium.stands[0].visible and game.board.stadium.stands[1].visible)
	game.board.stadium.update_view(Vector3(0, 18, 0), true)
	for tower in game.board.stadium.towers:
		assert(tower.visible)
	game._layout()
	var start = Rules.kickoff(Rules.create_game(), 6, 4)
	start.phase = "roll"
	start.opening = false
	start.kickoffKind = null
	start.ball = {"x": 3, "y": 1}
	game._accept(start, false)
	await process_frame
	assert(game.dice.visible and not game.dice.second.visible)
	assert(game.board.eligible_players.is_empty(), "Players highlight only after the roll")
	_seed_roll(game, [2])
	game.dice.first.pressed.emit()
	assert(game.animating and game.dice.busy and game.dice.first.rolling)
	assert(game.dice.first.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	game._roll_turn()
	_tap_cell(game, Vector2i(2, 1))
	assert(game.state.phase == "roll", "Dice animation must block board input and duplicate rolls")
	while game.animating:
		await process_frame
	assert(game.state.remaining == 2 and game.state.rolls.blue == 1)
	assert(not game.dice.visible and game.die_badge.face == 2)
	assert(not game.dice.first.rolling)
	assert((game.die_badge.rig.basis * game.die_badge.rig.get_node("Face2").basis.y).dot(Vector3.BACK) > 0.8)
	assert(game.prompt.text == "2 moves left")
	assert(game.board.eligible_players.size() == 5)
	for id in game.board.eligible_players:
		assert(id.begins_with("blue-"))
	assert(not game.primary.visible, "Choose a player instead of showing a menu of turn actions")
	await process_frame
	await _snapshot("-select")
	# A blocked player must neither highlight nor be selectable.
	var blocked = game.state.duplicate(true)
	var cells = [Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 0), Vector2i(2, 2)]
	for i in range(4):
		var opponent = Rules.pawn_by_id(blocked, "red-%d" % (i + 1))
		opponent.x = cells[i].x
		opponent.y = cells[i].y
	game._accept(blocked, false)
	assert(not "blue-1" in game.board.eligible_players)
	await physics_frame
	var player = game.board.pieces["blue-1"]
	game._tap(game.board.camera.unproject_position(player.position + Vector3(0, 0.65, 0)))
	assert(game.state.selected == null)
	game._accept(Rules.roll_die(start, 6), false)
	await create_timer(0.3).timeout
	game._tap(game.board.camera.unproject_position(player.position + Vector3(0, 0.65, 0)))
	assert(game.state.selected == "blue-1")
	_tap_cell(game, Vector2i(3, 1))
	assert(game.state.phase == "kick" and game.state.remaining == 5)
	assert(player.get_node("Rig").position.length() > 0.5)
	await create_timer(0.3).timeout
	assert(absf(player.get_node("Rig").position.x) < 0.01)
	var origin = game.state.duplicate(true)
	assert(game.undo_button.visible and not game.undo_button.disabled)
	game.undo_button.pressed.emit()
	assert(game.state.phase == "run" and game.state.remaining == 6, "Undo at ball contact must restore the run and its movement point")
	assert(Rules.pawn_by_id(game.state, "blue-1").x == 2)
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(3, 1))
	assert(game.state == origin)
	await create_timer(0.3).timeout
	var origin_position = game.board.ball.position
	for cell in [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 2)]:
		_tap_cell(game, cell)
	assert(game.kick_plan.size() == 3 and game.state == origin)
	assert(game.board.ball.position.is_equal_approx(origin_position))
	assert(game.primary.text == "Confirm kick" and not game.primary.disabled)
	await _check_confirmation(game)
	var confirmation_position = game.primary.position
	_tap_cell(game, Vector2i(6, 3))
	assert(game.kick_plan.size() == 3, "A second bend is invalid")
	game.undo_button.pressed.emit()
	assert(game.kick_plan.size() == 2 and not game._preview_state().curved)
	assert(game.primary.visible and game._preview_state().remaining == 4)
	await _check_confirmation(game)
	assert(not game.primary.position.is_equal_approx(confirmation_position), "Confirmation must follow the rewound endpoint")
	_tap_cell(game, Vector2i(6, 2))
	assert(game.primary.visible, "A legal route exposes confirmation without a hidden second tap")
	await _check_confirmation(game)
	assert(game._preview_state().remaining > 0, "A legal kick may finish early")
	var expected = Rules.commit_turn(game._preview_state())
	game.primary.pressed.emit()
	assert(game.animating and game.primary.disabled)
	assert(not game.primary.visible, "Hide confirmation while the ball travels")
	await create_timer(0.06).timeout
	assert(not game.board.ball.position.is_equal_approx(origin_position))
	assert(game.state == origin, "Do not hand over until the ball arrives")
	_tap_cell(game, Vector2i(5, 1))
	game._primary()
	game._undo()
	assert(game.state == origin, "Undo cannot interrupt an animated kick")
	_tap_cell(game, Vector2i(7, 3))
	while game.animating:
		await process_frame
	assert(game.state == expected and game.state.team == "red" and game.state.phase == "roll")
	assert(game.dice.visible and game.history.is_empty() and game.kick_plan.is_empty())
	_tap_cell(game, Vector2i(5, 1))
	game._undo()
	assert(game.state == expected, "Rewinding must not cross into the previous player's turn")
	# A pass must continue off the receiver before the turn can finish.
	game._accept(origin, false)
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(4, 2))
	_tap_cell(game, Vector2i(4, 3))
	assert(game._preview_state().selected == "blue-3" and game.primary.disabled)
	assert(not game.primary.visible, "An unfinished pass must leave the board clear")
	await game._confirm_kick()
	assert(game.state == origin and not game.animating)
	game._undo()
	assert(game.kick_plan.size() == 1 and game._preview_state().selected == origin.selected)
	assert(not "blue-3" in game._preview_state().used, "Rewinding a pass restores who can kick")
	_tap_cell(game, Vector2i(4, 3))
	_tap_cell(game, Vector2i(5, 3))
	expected = Rules.commit_turn(game._preview_state())
	await game._confirm_kick()
	assert(game.state == expected and game.dice.visible)
	# Goal celebration scores once before giving the opponent its dice prompt.
	var goal = Rules.create_game()
	goal.phase = "kick"
	goal.selected = "blue-1"
	goal.used = ["blue-1"]
	goal.remaining = 2
	goal.roll = 6
	goal.ball = {"x": 9, "y": 2}
	Rules.pawn_by_id(goal, "blue-1").x = 8
	Rules.pawn_by_id(goal, "blue-1").y = 2
	Rules.pawn_by_id(goal, "red-0").y = 4
	game._accept(goal, false)
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(10, 2))
	assert(game.state.score.blue == 0)
	_tap_cell(game, Vector2i(9, 2))
	assert(game.kick_plan.is_empty() and game._preview_state().score.blue == 0)
	_tap_cell(game, Vector2i(10, 2))
	await _check_confirmation(game)
	await game._confirm_kick()
	assert(game.state.score.blue == 1 and game.state.phase == "roll" and game.state.team == "red")
	assert(game.dice.visible)
	# Exact kickoff distance is checked before confirmation.
	game._accept(Rules.kickoff(Rules.create_game(), 6, 4), false)
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(5, 3))
	_tap_cell(game, Vector2i(5, 3))
	assert(game.primary.disabled and not game.primary.visible, "Retapping cannot bypass kickoff distance")
	await game._confirm_kick()
	assert(game.state.remaining == 2)
	_tap_cell(game, Vector2i(6, 3))
	assert(not game.primary.disabled)
	await game._confirm_kick()
	assert(game.state.phase == "roll" and game.state.team == "red" and not game.state.opening)
	# Required relocation is also drafted before the kick finishes the turn.
	var relocation = Rules.create_game()
	relocation.phase = "kick"
	relocation.selected = "blue-1"
	relocation.used = ["blue-1"]
	relocation.remaining = 2
	relocation.free = true
	relocation.ball = {"x": 0, "y": 2}
	Rules.pawn_by_id(relocation, "blue-1").x = 0
	Rules.pawn_by_id(relocation, "blue-1").y = 2
	game._accept(relocation, false)
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(1, 2))
	assert(game._preview_state().phase == "relocate" and game.primary.disabled)
	await game._confirm_kick()
	assert(game.state == relocation)
	_tap_cell(game, Vector2i(0, 1))
	assert(game._preview_state().phase == "kick" and not game.primary.disabled)
	assert(game.state == relocation)
	game._undo()
	assert(game._preview_state().phase == "relocate", "Undo restores required relocation before removing the kick")
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(0, 1))
	await game._confirm_kick()
	assert(game.state.phase == "roll" and game.state.team == "red")
	assert(Rules.pawn_by_id(game.state, "blue-1").y == 1)
	# Half-time and full-time must retain their special transitions.
	for half in [1, 2]:
		var last = origin.duplicate(true)
		last.half = half
		last.rolls = {"blue": half * 10, "red": half * 10}
		game._accept(last, false)
		await create_timer(0.3).timeout
		_tap_cell(game, Vector2i(4, 1))
		await game._confirm_kick()
		assert(game.state.phase == ("halftime" if half == 1 else "finished"))
		assert(game.dice.visible == (half == 1))
		if half == 1:
			assert(game.dice.second.visible)
		else:
			assert(game.results.visible and game.result_title.text == "HONOURS EVEN")
			assert(game.primary.get_parent() == game.result_actions and game.primary.text == "Play again")
			assert(game.result_home.visible and not game.header.visible and not game.dock.visible)
			await process_frame
			await _snapshot("-results")
	# Running without a kick still has an explicit way to finish.
	game._accept(Rules.roll_die(start, 6), false)
	await create_timer(0.3).timeout
	var runner = game.board.pieces["blue-2"]
	game._tap(game.board.camera.unproject_position(runner.position + Vector3(0, 0.65, 0)))
	var run_origin = game.state.duplicate(true)
	_tap_cell(game, Vector2i(3, 4))
	_tap_cell(game, Vector2i(3, 5))
	_tap_cell(game, Vector2i(4, 5))
	assert(game.state.phase == "run" and not game.primary.disabled)
	assert(game.dock.is_ancestor_of(game.primary), "End turn stays in the bottom controls")
	_tap_cell(game, Vector2i(2, 4))
	assert(game.state == run_origin, "Tapping an earlier run square restores the whole move budget")
	_tap_cell(game, Vector2i(3, 4))
	game._primary()
	assert(game.state.team == "red" and game.dice.visible)
	# Kick back along the run trail without rewinding the player.
	var backtrack = start.duplicate(true)
	Rules.pawn_by_id(backtrack, "blue-1").x = 1
	game._accept(Rules.roll_die(backtrack, 3), false)
	game._accept(Rules.select_pawn(game.state, "blue-1"))
	await create_timer(0.3).timeout
	_tap_cell(game, Vector2i(2, 1))
	_tap_cell(game, Vector2i(3, 1))
	var contact = game.state.duplicate(true)
	await create_timer(0.3).timeout
	for cell in [Vector2i(2, 1), Vector2i(1, 1)]:
		_tap_cell(game, cell)
		assert(game.state == contact, "Kicking onto a vacated run square must not undo the run")
		assert(Rules.same(game._preview_state().ball, {"x": cell.x, "y": cell.y}))
	assert(game.kick_plan.size() == 2)
	_tap_cell(game, Vector2i(2, 1))
	assert(game.kick_plan.size() == 1, "Kick route rewinding still works on a former run square")
	_tap_cell(game, Vector2i(3, 1))
	assert(game.kick_plan.is_empty() and game.state == contact)
	# Capture a route and its confirmation beside the endpoint.
	game._accept(origin, false)
	await create_timer(0.3).timeout
	for cell in [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 2)]:
		_tap_cell(game, cell)
	await process_frame
	await process_frame
	assert(game.dock.size.x <= root.get_visible_rect().size.x - 20, "The strip must fit a narrow phone")
	assert(game.dock.size.y < 80, "Confirmation must not expand into a large action panel")
	await _check_confirmation(game)
	await _snapshot("")
	game._menu_action(0)
	await create_timer(0.6).timeout
	await _check_confirmation(game)
	await _snapshot("-overhead")
	_tap_cell(game, Vector2i(3, 1))
	assert(game.kick_plan.is_empty() and game._preview_state() == origin, "Tap the ball to clear the whole route")
	assert(not game.primary.visible and game.dock.is_ancestor_of(game.primary))
	print("PASS: center dice, ties, docking, eligible players, animated paths, confirmation handoff, passes, goals, relocation, halftime and full time.")
	quit()

func _check_confirmation(game: Node3D) -> void:
	assert(game.primary.visible, "Every legal kick exposes its confirmation immediately")
	await process_frame
	await process_frame
	assert(game.primary.visible and game.primary.get_parent() == game.hud)
	var rect = game.primary.get_global_rect()
	assert(root.get_visible_rect().encloses(rect), "Confirmation must stay on screen")
	assert(rect.position.y >= game.header.get_global_rect().end.y)
	assert(rect.end.y <= game.dock.position.y, "Confirmation must not overlap the HUD")
	assert(rect.size.x >= 44 and rect.size.y >= 44, "Keep a touch-sized target")
	var ball = game.kick_plan.back().ball
	var endpoint = game.board.camera.unproject_position(game.board.cell_position(ball.x, ball.y, 0.04))
	assert(not rect.has_point(endpoint), "Keep the selected square visible")
	assert(rect.get_center().distance_to(endpoint) < rect.size.length() + 32, "Confirmation must stay beside the endpoint")

func _tap_cell(game: Node3D, cell: Vector2i) -> void:
	game._tap(game.board.camera.unproject_position(game.board.cell_position(cell.x, cell.y, 0.04)))

func _seed_roll(game: Node3D, values: Array) -> void:
	var probe = RandomNumberGenerator.new()
	for seed_value in range(4096):
		probe.seed = seed_value
		var matches = true
		for value in values:
			if probe.randi_range(1, 6) != value:
				matches = false
		if matches:
			game.random.seed = seed_value
			return
	assert(false, "Could not find a deterministic dice seed")

func _snapshot(suffix: String) -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].get_basename() + suffix + ".png")
