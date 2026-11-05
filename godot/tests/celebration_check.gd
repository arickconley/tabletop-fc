extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func wait_for_cinematic(game: Node3D, time: float) -> void:
	var deadline = Time.get_ticks_msec() + 10000
	while (not game.celebration.active or game.celebration.elapsed < time) and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(game.celebration.active and game.celebration.elapsed >= time, "Goal celebration must progress")

func capture(name: String) -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(args[0])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	var game = MatchScene.instantiate()
	game.screen = "match"
	game.computer_team = ""
	root.add_child(game)
	root.size_changed.disconnect(game._resize)
	root.content_scale_size = Vector2i(1280, 800)
	await process_frame
	for team in ["blue", "red"]:
		var blue = team == "blue"
		var start = Rules.create_game()
		start.team = team
		start.phase = "kick"
		start.selected = team + "-1"
		start.used = [start.selected]
		start.free = true
		start.remaining = 5
		start.roll = 6
		start.rolls[team] = 1
		start.ball = {"x": 3 if blue else 6, "y": 2 if blue else 3}
		start.pawns = [
			{"id": team + "-1", "team": team, "x": start.ball.x, "y": start.ball.y, "keeper": false},
			{"id": team + "-2", "team": team, "x": 7 if blue else 2, "y": start.ball.y, "keeper": false},
			{"id": ("red" if blue else "blue") + "-1", "team": "red" if blue else "blue", "x": 1 if blue else 8, "y": 5, "keeper": false}]
		game._accept(start, false)
		game.board.top_view = not blue
		game._layout()
		await create_timer(0.7).timeout
		var view = start
		for x in (range(4, 11) if blue else range(5, -2, -1)):
			view = Rules.kick_step(view, x, start.ball.y)
			assert(not view.has("error"))
			game.kick_plan.append(view)
		var expected = Rules.continue_after_goal(view)
		var camera_before = game.board.camera.transform
		game._confirm_kick()
		await wait_for_cinematic(game, 0.2)
		assert(game.state.score[team] == 1 and game.animating)
		assert(game.celebration.scorer == game.board.pieces[team + "-2"], "Replay must follow the receiver who scored")
		assert(game.celebration.path.size() == 4, "Replay only the final kick, not its preceding pass")
		assert(game.celebration.path[0].is_equal_approx(game.board._ball_position(game.kick_plan[3])))
		assert(game.get_viewport().get_camera_3d() == game.celebration.camera)
		assert(not game.header.visible and not game.dock.visible and game.celebration.overlay.visible)
		var labels_before = game.celebration.labels.duplicate()
		for label in labels_before:
			assert(not label.visible, "Player markers stay out of the cinematic")
		var scored = game.state.duplicate(true)
		game._undo()
		game._primary()
		game._roll_turn()
		game._menu_action(5)
		game._tap(Vector2(300, 300))
		assert(game.state == scored and game.animating, "Gameplay input must not alter a replay")
		await wait_for_cinematic(game, 1.05)
		assert(absf(game.celebration.scorer.get_node("Rig/RightLeg").rotation.x) > 0.1, "The replay animates a real kick")
		await capture(team + "-kick")
		await wait_for_cinematic(game, 2.0)
		assert(not game.board.ball.position.is_equal_approx(game.celebration.path.back()))
		assert(game.state == scored, "Replaying the ball must not replay the rules or score again")
		await capture(team + "-replay")
		await wait_for_cinematic(game, 3.9)
		assert(game.celebration.effects.get_child_count() >= 2)
		await capture(team + "-fireworks")
		if not blue:
			root.size = Vector2i(390, 844)
			root.content_scale_size = Vector2i(390, 844)
			await process_frame
			await process_frame
			assert(root.get_visible_rect().encloses(game.celebration.skip.get_global_rect()))
			await capture("portrait-fireworks")
			game.celebration.skip.pressed.emit()
		else:
			while game.animating:
				await process_frame
		assert(game.state == expected and game.state.score[team] == 1)
		assert(not game.celebration.active and not game.board.celebrating)
		assert(game.celebration.effects.get_child_count() == 0)
		for label in labels_before:
			assert(label.visible == labels_before[label], "Restore gameplay markers after the cinematic")
		assert(game.get_viewport().get_camera_3d() == game.board.camera)
		assert(game.board.top_view == not blue)
		if blue:
			assert(game.board.camera.transform.is_equal_approx(camera_before), "Return to the original gameplay view")
		assert(game.dice.visible and not game.animating)
	# Skipping still follows halftime/full-time scoring boundaries exactly once.
	for half in [1, 2]:
		var start = Rules.kickoff(Rules.create_game(), 6, 4)
		start.opening = false
		start.kickoffKind = null
		start.phase = "kick"
		start.half = half
		start.rolls = {"blue": half * 10, "red": half * 10}
		start.selected = "blue-1"
		start.used = [start.selected]
		start.free = true
		start.ball = {"x": 8, "y": 1}
		Rules.pawn_by_id(start, "blue-1").x = 8
		Rules.pawn_by_id(start, "blue-1").y = 1
		Rules.pawn_by_id(start, "red-0").y = 4
		game._accept(start, false)
		var bend = Rules.kick_step(start, 9, 2)
		var goal = Rules.kick_step(bend, 10, 2)
		game.kick_plan.append(bend)
		game.kick_plan.append(goal)
		game._confirm_kick()
		await wait_for_cinematic(game, 0.1)
		assert(game.celebration.path.size() == 3 and goal.curved, "Replay preserves the actual bent shot")
		assert(game.celebration.path[1].is_equal_approx(game.board._ball_position(bend)))
		var escape = InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		game.celebration._unhandled_key_input(escape)
		game.celebration.finish()
		assert(game.state == Rules.continue_after_goal(goal))
		assert(game.state.phase == ("halftime" if half == 1 else "finished"))
		assert(game.state.score.blue == 1)
	print("PASS: both goals, final-scorer replay, kick pose, fireworks, input locks, one score, camera restoration, resize, skip, halftime and full time.")
	quit()
