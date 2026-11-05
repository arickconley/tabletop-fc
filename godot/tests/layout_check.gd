extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in range(5):
		await process_frame

func check_strip(game: Node3D) -> bool:
	var fits_content = absf(game.dock.size.y - game.dock.get_combined_minimum_size().y) < 1.0
	var bottom = root.get_visible_rect().size.y - 12
	return fits_content and game.dock.size.y < 140 and absf(game.dock.get_rect().end.y - bottom) < 1.0

func run() -> void:
	var game = MatchScene.instantiate()
	game.screen = "match"
	game.computer_team = ""
	root.add_child(game)
	if DisplayServer.get_name() == "headless":
		root.size_changed.disconnect(game._resize)
		root.content_scale_size = Vector2i(1280, 800)
	await settle()
	await create_timer(0.6).timeout
	game._accept(Rules.kickoff(Rules.create_game(), 6, 4), false)
	await settle()
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 3, 0.04)))
	await settle()
	assert(game.feedback.visible, "An incomplete kickoff must explain the exact distance")
	var kickoff_size = game.board.camera.size
	var kickoff_offset = game.board.camera.v_offset
	game._tap(game.board.camera.unproject_position(game.board.cell_position(6, 3, 0.04)))
	await settle()
	assert(not game.feedback.visible)
	assert(is_equal_approx(kickoff_size, game.board.camera.size) and is_equal_approx(kickoff_offset, game.board.camera.v_offset), "Completing kickoff must not reframe the pitch")
	var perspective = game.board.camera.transform
	game._menu_action(0)
	assert(game.board.camera.transform.is_equal_approx(perspective), "View switches must start from the current pose")
	await create_timer(0.18).timeout
	var midway = game.board.camera.transform
	assert(not midway.is_equal_approx(perspective), "The camera must ease toward overhead")
	assert(midway.origin.distance_to(Vector3(0, 18, 0.001)) > 0.1, "The camera must not snap to overhead")
	game._menu_action(0)
	assert(game.board.camera.transform.is_equal_approx(midway), "Interrupting a camera move must remain continuous")
	await create_timer(0.6).timeout
	assert(game.board.camera.transform.is_equal_approx(perspective))
	game._accept(Rules.kickoff(Rules.create_game(), 3, 4), false)
	await settle()
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 3, 0.04)))
	await settle()
	assert(game._preview_state().remaining == 0)
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 4, 0.04)))
	await settle()
	assert(game.feedback.visible and game.feedback.text == "Tap the last square to finish, or an earlier square to go back.")
	print("Feedback strip height: ", game.dock.size.y, "; content height: ", game.dock.get_combined_minimum_size().y)
	assert(check_strip(game), "Feedback must fit its content and remain bottom-aligned")
	for width in [640, 1280, 1920, 640]:
		root.size = Vector2i(width, 1000)
		if DisplayServer.get_name() == "headless":
			root.content_scale_size = Vector2i(width, 1000)
		await settle()
		await create_timer(0.6).timeout
		game._accept({"error": "Leave an opponent a path to the ball. Tap an earlier square and choose another route."})
		await settle()
		assert(check_strip(game), "Feedback must fit its content and remain bottom-aligned")
		game._render()
		await settle()
		assert(not game.feedback.visible)
		assert(check_strip(game), "Feedback must fit its content and remain bottom-aligned")
		assert(game.dock.size.y < 80, "Hiding feedback must restore the compact counter")
	# Leave the reported feedback visible for a screenshot.
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 4, 0.04)))
	await settle()
	assert(check_strip(game), "Feedback must fit its content and remain bottom-aligned")
	var args = OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
	print("PASS: feedback appears, wraps, resizes and hides without enlarging the counter.")
	quit()
