extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Kits = preload("res://scripts/team_kits.gd")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in range(6):
		await process_frame

func wait_for_screen(game: Node3D, expected: String) -> bool:
	var deadline = Time.get_ticks_msec() + 20000
	while game.screen != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	return game.screen == expected

func screenshot(suffix: String) -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].get_basename() + suffix + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 800)
	var random = RandomNumberGenerator.new()
	random.seed = 27
	for color in Kits.COLORS.size():
		assert(not Kits.opponents(color).is_empty())
		var seen: Dictionary = {}
		for i in range(100):
			var opponent = Kits.opponent(color, random)
			assert(opponent.index != color and opponent.index in Kits.opponents(color))
			seen[opponent.index] = true
		assert(seen.size() >= 3, "Opponent colours must vary")
	var game = MatchScene.instantiate()
	root.add_child(game)
	await settle()
	assert(game.screen == "home" and game.lobby.visible)
	assert(not game.dice.visible and not game.header.visible and not game.dock.visible)
	var original = game.state.duplicate(true)
	game._roll_turn()
	game._tap(Vector2(300, 300))
	assert(game.state == original, "Menus must block gameplay")
	assert(game.board.pieces.is_empty(), "The main menu must have no footballers")
	assert(not game.board.ball.visible and game.journey.groundskeeper.visible)
	assert(not game.journey.room.visible, "Foreground architecture must not cover the stadium menu")
	assert(not game.journey.hero.visible)
	var grounds_position = game.journey.groundskeeper.position
	await create_timer(0.3).timeout
	assert(not grounds_position.is_equal_approx(game.journey.groundskeeper.position))
	assert(game.get_viewport().get_camera_3d() == game.journey.camera)
	await screenshot("-home")
	var home_camera = game.journey.camera.transform
	game.lobby.play_button.pressed.emit()
	assert(game.screen == "to_locker" and not game.lobby.visible)
	game.lobby.play_button.pressed.emit()
	await create_timer(0.7).timeout
	assert(not home_camera.is_equal_approx(game.journey.camera.transform), "The camera must travel into the room")
	assert(game.state == original and not game.dice.visible)
	await screenshot("-descent")
	assert(await wait_for_screen(game, "setup"))
	await settle()
	assert(game.screen == "setup" and game.lobby.setup_scroll.visible)
	assert(absf(game.journey.camera.rotation.x) < deg_to_rad(8), "Locker room view should be near eye level")
	assert(not game.journey.has_node("EditorPreview"), "Editor references must not duplicate runtime scenery")
	var portrait = root.get_visible_rect().size.y > root.get_visible_rect().size.x
	var authored_camera = game.journey.get_node("Shots/LockerPortrait/Camera" if portrait else "Shots/LockerLandscape/Camera")
	var authored_position = authored_camera.position
	var authored_fov = authored_camera.fov
	authored_camera.position.x += 0.1
	authored_camera.fov += 2.0
	game.journey.resize_view()
	await create_timer(0.5).timeout
	assert(game.journey.camera.global_position.is_equal_approx(authored_camera.global_position), "Scene camera edits must drive the live shot")
	assert(is_equal_approx(game.journey.camera.fov, authored_camera.fov))
	authored_camera.position = authored_position
	authored_camera.fov = authored_fov
	game.journey.resize_view()
	await create_timer(0.5).timeout
	assert(game.lobby.swatches.get_child_count() == 12)
	assert(game.lobby.designs.get_child_count() == 3)
	game.lobby.swatches.get_child(8).pressed.emit()
	game.lobby.designs.get_child(2).pressed.emit()
	assert(game.lobby.preview_player.get_meta("kit") == Kits.make(8, 2))
	assert(game.lobby.preview_player.get_node("Rig/ShirtDesign").get_child_count() == 2)
	var pose = game.lobby.preview_player.get_node("Rig/LeftArm").rotation.x
	await create_timer(0.2).timeout
	assert(not is_equal_approx(pose, game.lobby.preview_player.get_node("Rig/LeftArm").rotation.x))
	# Every colour and design reaches the actual match model used in the preview.
	for color in Kits.COLORS.size():
		game.lobby.select_color(color)
		assert(game.lobby.preview_player.get_meta("kit").color == Kits.COLORS[color])
	for design in range(3):
		game.lobby.select_design(design)
		assert(game.lobby.preview_player.get_node("Rig/ShirtDesign").get_child_count() == (0 if design == 0 else 2))
	game.lobby.select_color(8)
	game.lobby.select_design(2)
	await settle()
	var viewport_rect = root.get_visible_rect()
	assert(viewport_rect.encloses(game.lobby.footer.get_global_rect()), "Continue and Back must fit the screen")
	assert(viewport_rect.encloses(game.lobby.setup_scroll.get_global_rect()))
	assert(game.lobby.swatches.get_combined_minimum_size().x <= game.lobby.setup_scroll.size.x)
	await screenshot("-setup")
	game.lobby.setup_scroll.scroll_vertical = 1000
	await settle()
	assert(game.lobby.setup_scroll.get_global_rect().encloses(game.lobby.modes.get_global_rect()), "Game modes must be reachable by scrolling on short screens")
	assert(game.lobby.setup_scroll.get_global_rect().encloses(game.lobby.designs.get_global_rect()), "Shirt designs must remain reachable")
	await screenshot("-options")
	game.lobby.back_button.pressed.emit()
	assert(await wait_for_screen(game, "home"))
	assert(game.state == original)
	game.lobby.play_button.pressed.emit()
	assert(await wait_for_screen(game, "setup"))
	assert(game.lobby.selected_color == 8 and game.lobby.selected_design == 2)
	# The customized actor leaves the room, traverses the tunnel, and joins the actual match.
	var chosen_player = game.journey.hero
	game.lobby.start_button.pressed.emit()
	assert(game.screen == "entrance" and game.animating and not game.dice.visible)
	var opponent_index = game.team_kits.red.index
	game.lobby.start_button.pressed.emit()
	assert(game.team_kits.red.index == opponent_index, "Repeated start must not reroll the opponent")
	await create_timer(0.9).timeout
	assert(game.board.entering and game.screen == "entrance" and game.journey.mode == "tunnel")
	assert(game.board.pieces["blue-1"] == chosen_player, "Follow the same customized player into the match")
	assert(game.journey.camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	assert(game.journey.camera.position.distance_to(chosen_player.position) < 2.0, "The follow camera must be at a teammate\'s shoulder, not far above the captain")
	var follow_fov = game.journey.camera.fov
	var follow_camera_position = game.journey.camera.position
	assert(game.state == original and not game.computer_busy)
	var moving_piece = game.board.pieces["blue-1"]
	assert(not moving_piece.position.is_equal_approx(game.board.cell_position(2, 1)))
	var run_pose = moving_piece.get_node("Rig/LeftLeg").rotation.x
	var run_position = moving_piece.position
	await create_timer(0.08).timeout
	assert(not is_equal_approx(run_pose, moving_piece.get_node("Rig/LeftLeg").rotation.x))
	assert(not run_position.is_equal_approx(moving_piece.position))
	assert(not follow_camera_position.is_equal_approx(game.journey.camera.position), "Follow by translating the camera")
	assert(is_equal_approx(game.journey.camera.fov, follow_fov), "Walking must not zoom the lens")
	await screenshot("-entrance")
	await create_timer(1.6).timeout
	await screenshot("-tunnel")
	var deadline = Time.get_ticks_msec() + 20000
	var followed_onto_grass = false
	while game.journey.mode == "tunnel" and Time.get_ticks_msec() < deadline:
		if moving_piece.position.x < 4.3:
			followed_onto_grass = true
			assert(game.journey.camera.position.y < 2.0, "Stay at player height while leaving the tunnel")
		await process_frame
	assert(followed_onto_grass, "Follow the player beyond the tunnel before rising")
	assert(game.journey.camera.position.x < 5.15, "The follow camera must clear the tunnel roof")
	await screenshot("-exit")
	await create_timer(0.7).timeout
	assert(game.journey.mode == "crane" and game.journey.camera.position.y > 2.0)
	await screenshot("-crane")
	var last_camera = game.journey.camera.position
	var last_delta = game.get_process_delta_time()
	while game.screen == "entrance" and Time.get_ticks_msec() < deadline:
		await process_frame
		var camera = game.get_viewport().get_camera_3d()
		# process_frame precedes tweens, so this displacement used the preceding delta.
		assert(camera.position.distance_to(last_camera) < maxf(0.3, last_delta * 40.0), "The crane and camera handoff must not jump")
		last_camera = camera.position
		last_delta = game.get_process_delta_time()
	assert(game.screen == "match" and not game.animating and not game.board.entering)
	assert(game.dice.visible and game.dice.second.visible)
	assert(game.get_viewport().get_camera_3d() == game.board.camera)
	assert(game.board.camera.transform.is_equal_approx(game.journey.camera.transform))
	assert(is_equal_approx(game.board.camera.size, game.journey.camera.size), "HUD reveal must not change the final camera framing")
	assert(is_equal_approx(game.board.camera.v_offset, game.journey.camera.v_offset))
	assert(not game.journey.groundskeeper.visible)
	assert(not game.journey.room.visible, "The tunnel must not obscure the playable squares")
	assert(game.state == original, "Entrance animation must not change rules or player positions")
	for pawn in game.state.pawns:
		var piece = game.board.pieces[pawn.id]
		assert(piece.position.is_equal_approx(game.board.cell_position(pawn.x, pawn.y)))
		assert(piece.get_meta("kit") == game.team_kits[pawn.team])
	assert(game.team_kits.blue == Kits.make(8, 2))
	assert(game.team_kits.red.index in Kits.opponents(8))
	assert(game.dice.first.tint == Kits.accent(game.team_kits.blue))
	assert(game.dice.second.tint == Kits.accent(game.team_kits.red))
	assert(game.scoreboard.text == "PURPLE   0  —  0   " + game.team_kits.red.name.to_upper(), "The scoreboard must use both chosen kit names")
	assert(game.dice.caption.text.contains("You’re Purple"))
	await settle()
	await screenshot("-kickoff")
	var normal = Rules.kickoff(Rules.create_game(), 6, 1)
	normal.phase = "roll"
	normal.opening = false
	normal.ball = {"x": 3, "y": 1}
	game._accept(Rules.roll_die(normal, 2), false)
	assert(game.die_badge.tint == Kits.accent(game.team_kits.blue))
	assert(not game.board.eligible_rings.is_empty())
	assert(game.board.eligible_rings[0].material_override.albedo_color == Kits.accent(game.team_kits.blue))
	assert(game.turn_label.text.begins_with("PURPLE"))
	game._menu_action(5)
	assert(game.restart.visible, "Leaving a match requires the existing restart confirmation")
	game.restart.confirmed.emit()
	game.restart.hide()
	assert(await wait_for_screen(game, "home"))
	assert(not game.dice.visible)
	for piece in game.board.pieces.values():
		assert(not piece.visible)
	game.lobby.play_button.pressed.emit()
	assert(await wait_for_screen(game, "setup"))
	game.lobby.modes.get_child(1).pressed.emit()
	assert(game.lobby.opponent == "")
	print("PASS: empty stadium and groundskeeper, camera descent, locker-room kits, same-player tunnel follow, crane to gameplay, positions, input locks, colours, return trip and local mode.")
	quit()
