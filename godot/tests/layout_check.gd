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
	root.add_child(game)
	await settle()
	game._accept(Rules.kickoff(Rules.create_game(), 3, 4), false)
	await settle()
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 3, 0.04)))
	await settle()
	assert(game._preview_state().remaining == 0)
	game._tap(game.board.camera.unproject_position(game.board.cell_position(5, 4, 0.04)))
	await settle()
	assert(game.feedback.visible and game.feedback.text == "Confirm or undo this path.")
	print("Feedback strip height: ", game.dock.size.y, "; content height: ", game.dock.get_combined_minimum_size().y)
	assert(check_strip(game), "Feedback must fit its content and remain bottom-aligned")
	for width in [640, 1280, 1920, 640]:
		root.size = Vector2i(width, 1000)
		await settle()
		game._accept({"error": "Leave an opponent a path to the ball. Undo the last square and choose another route."})
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
