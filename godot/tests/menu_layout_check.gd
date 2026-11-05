extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = MatchScene.instantiate()
	root.add_child(game)
	root.size_changed.disconnect(game._resize)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for viewport_size in [Vector2i(1700, 995), Vector2i(1280, 800), Vector2i(1024, 600), Vector2i(320, 568), Vector2i(640, 360), Vector2i(1700, 995)]:
		root.content_scale_size = viewport_size
		for frame in range(6):
			await process_frame
		var menu = game.lobby
		assert(root.get_visible_rect().encloses(menu.home.get_global_rect()), "Home controls must remain on screen")
		assert(menu.play_button.size.y >= 44)
		assert(menu.how_to_button.get_global_rect().end.y <= viewport_size.y, "Help must fit at %s: %s" % [viewport_size, menu.how_to_button.get_global_rect()])
		if viewport_size.x >= 1024:
			assert(menu.title.get_theme_font_size("font_size") >= 110, "Desktop title must scale with the window")
			assert(menu.home.size.x >= viewport_size.x * 0.28, "Desktop menu must fill a meaningful share of the screen")
			assert(menu.play_button.size.y >= 59, "Desktop actions need a larger visual target")
		else:
			assert(menu.title.get_theme_font_size("font_size") == 58, "Keep compact layouts unchanged")
		if viewport_size == Vector2i(1700, 995) and not OS.get_cmdline_user_args().is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("PASS: desktop menu scales up, remains on screen, and resets correctly for compact layouts.")
	quit()
