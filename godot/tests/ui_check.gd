extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")
const UI = preload("res://scripts/ui_theme.gd")

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in range(8):
		await process_frame

func check_button(button: Button) -> void:
	assert(button.size.x >= 44 and button.size.y >= 44, "%s needs a touch-sized target" % button.text)
	assert(button.get_minimum_size().x <= button.size.x + 1, "%s must fit its label" % button.text)
	assert(root.get_visible_rect().encloses(button.get_global_rect()), "%s must fit the screen" % button.text)

func check_primary(button: Button) -> void:
	check_button(button)
	assert(button.get_theme_stylebox("normal").bg_color == UI.ACCENT, "Primary actions must share the same treatment")
	assert(button.get_theme_color("font_color") == UI.INK, "Primary labels must stay legible on lime")

func check_hud(game: Node3D) -> void:
	assert(root.get_visible_rect().encloses(game.header.get_global_rect()))
	assert(root.get_visible_rect().encloses(game.dock.get_global_rect()))
	for label in [game.turn_label, game.prompt]:
		var text_size = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
		assert(text_size.x <= label.size.x + 1, "The turn instruction must remain readable: %s" % label.text)

func check_window(window: Window, title_bar: bool = false) -> void:
	var bounds = Rect2(window.position, window.size)
	if title_bar:
		var title_height = window.get_theme_constant("title_height")
		bounds.position.y -= title_height
		bounds.size.y += title_height
	assert(root.get_visible_rect().encloses(bounds), "%s must fit: position=%s size=%s decorated=%s viewport=%s" % [window.title, window.position, window.size, bounds, root.get_visible_rect()])

func capture(name: String, viewport_size: Vector2i) -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("%s-%dx%d.png" % [name, viewport_size.x, viewport_size.y]))

func run() -> void:
	var game = MatchScene.instantiate()
	game.computer_team = ""
	root.add_child(game)
	root.size_changed.disconnect(game._resize)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for viewport_size in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(640, 360), Vector2i(1280, 800)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		game.screen = "home"
		game.journey.home()
		game.lobby.present("home")
		game._render()
		await settle()
		check_primary(game.lobby.play_button)
		check_button(game.lobby.how_to_button)
		assert(root.get_visible_rect().encloses(game.lobby.home.get_global_rect()))
		await capture("home", viewport_size)
		game.lobby.update_continue(true, "")
		await settle()
		check_button(game.lobby.continue_button)
		check_button(game.lobby.options_button)
		check_button(game.lobby.play_button)
		await capture("continue", viewport_size)
		game.session_menu.open()
		await settle()
		for button in [game.session_menu.motion, game.session_menu.mute, game.session_menu.resume]:
			check_button(button)
		assert(root.get_visible_rect().encloses(game.session_menu.panel.get_global_rect()))
		await capture("options", viewport_size)
		game.session_menu.close()
		game.lobby.update_continue(false, "")
		game.screen = "setup"
		game.journey.mode = "locker"
		game.journey.hero.show()
		game.journey.groundskeeper.hide()
		if game.journey.camera_motion != null:
			game.journey.camera_motion.kill()
		game.journey.camera_destination = {}
		game.journey.resize_view()
		game.lobby.present("setup")
		await settle()
		check_primary(game.lobby.start_button)
		check_button(game.lobby.back_button)
		assert(root.get_visible_rect().encloses(game.lobby.setup_scroll.get_global_rect()))
		assert(game.lobby.setup_scroll.get_global_rect().end.y <= game.lobby.footer.position.y)
		assert(game.lobby.setup.get_combined_minimum_size().x <= game.lobby.setup_scroll.size.x, "Kit settings must not scroll horizontally")
		if viewport_size.y > viewport_size.x:
			var hero = game.journey.hero.get_node("Rig")
			for height in [0.85, 1.45]:
				var head = game.journey.camera.unproject_position(hero.to_global(Vector3(0, height, 0)))
				assert(root.get_visible_rect().has_point(head), "The captain's face must remain on screen")
				assert(head.y < game.lobby.setup_scroll.position.y - 16, "Keep the captain's face clear of kit controls")
		for group in [game.lobby.swatches, game.lobby.designs, game.lobby.modes]:
			for button in group.get_children():
				game.lobby.setup_scroll.ensure_control_visible(button)
				await settle()
				check_button(button)
				assert(game.lobby.setup_scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), "%s at %s must fit scroll area %s (%s)" % [button.name, button.get_global_rect(), game.lobby.setup_scroll.get_global_rect(), viewport_size])
		game.lobby.setup_scroll.scroll_vertical = 0
		await settle()
		await capture("setup", viewport_size)
		game.screen = "match"
		game.journey.mode = "game"
		game.journey.hero.hide()
		game.journey.room.hide()
		game.journey.set_process(false)
		game.board.camera.make_current()
		game._accept(Rules.create_game(), false)
		await settle()
		check_button(game.menu)
		check_button(game.dice.first)
		check_button(game.dice.second)
		assert(root.get_visible_rect().encloses(game.dice.caption.get_global_rect()))
		await capture("kickoff", viewport_size)
		var normal = Rules.kickoff(Rules.create_game(), 6, 4)
		normal.phase = "roll"
		normal.opening = false
		normal.ball = {"x": 3, "y": 1}
		game._accept(Rules.select_pawn(Rules.roll_die(normal, 3), "blue-1"), false)
		await settle()
		check_hud(game)
		check_primary(game.primary)
		await capture("run", viewport_size)
		game._accept(Rules.run_step(game.state, 3, 1))
		game.kick_plan.append(Rules.kick_step(game.state, 4, 1))
		game._render()
		await settle()
		check_primary(game.primary)
		check_button(game.undo_button)
		check_hud(game)
		assert(game.primary.get_parent() == game.turn_actions if game.compact_layout else not game.primary.get_global_rect().intersects(game.dock.get_global_rect()))
		await capture("confirmation", viewport_size)
		game.menu.show_popup()
		await settle()
		await capture("menu", viewport_size)
		check_window(game.menu.get_popup())
		game.menu.get_popup().hide()
		game._menu_action(2)
		await settle()
		await capture("restart", viewport_size)
		assert(game.restart.visible)
		check_window(game.restart, true)
		for button in [game.restart.get_ok_button(), game.restart.get_cancel_button()]:
			assert(button.size.x >= 44 and button.size.y >= 44, "Restart confirmation actions need touch-sized targets")
		game.restart.hide()
		game._show_help()
		await settle()
		await capture("help", viewport_size)
		check_window(game.help, true)
		assert(game.help.get_ok_button().size.y >= 44, "Closing rules needs a touch-sized target")
		game.help.hide()
		var final_state = normal.duplicate(true)
		final_state.phase = "finished"
		final_state.score = {"blue": 3, "red": 1}
		final_state.winner = "blue"
		game._accept(final_state, false)
		await settle()
		assert(game.results.visible and root.get_visible_rect().encloses(game.result_panel.get_global_rect()), "Full-time content must fit")
		assert(is_equal_approx(game.result_panel.size.y, game.result_panel.get_combined_minimum_size().y), "Full-time panel must fit its content after resizing")
		check_primary(game.primary)
		check_button(game.result_home)
		await capture("results", viewport_size)
		game.journey.set_process(true)
	print("PASS: home, kit setup, dice, match controls, help and full-time screens share accessible controls and fit four viewport sizes.")
	quit()
