extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func touch(position: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)

func drag(position: Vector2, index: int = 0) -> void:
	var event = InputEventScreenDrag.new()
	event.position = position
	event.index = index
	root.push_input(event, true)

func settle() -> void:
	for i in range(8):
		await process_frame

func capture(name: String) -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var game = MatchScene.instantiate()
	game.screen = "match"
	game.computer_team = ""
	root.add_child(game)
	root.size_changed.disconnect(game._resize)
	root.content_scale_size = root.size
	game._layout()
	var state = Rules.kickoff(Rules.create_game(), 6, 4)
	state.phase = "roll"
	state.opening = false
	state.ball = {"x": 3, "y": 1}
	state.selected = null
	game._accept(Rules.roll_die(state, 4), false)
	await settle()
	await create_timer(0.6).timeout
	var at = game.board.camera.unproject_position(game.board.pieces["blue-1"].position + Vector3.UP * 0.65)
	touch(at, true)
	drag(at + Vector2(3, 2))
	touch(at + Vector2(3, 2), false)
	assert(game.state.selected == "blue-1", "Small finger jitter must remain a tap")
	await settle()
	var original = game.state.duplicate(true)
	var center = game.play_area.get_center()
	var pose = game.board.camera.transform
	touch(center, true)
	drag(center + Vector2(70, -35))
	assert(not game.board.camera.transform.is_equal_approx(pose), "One finger must orbit and tilt immediately")
	assert(game.board.orbit_tilt > 0, "Dragging up raises the view to expose obscured squares")
	drag(center)
	touch(center, false)
	assert(game.state == original and game.kick_plan.is_empty(), "A drag returning to its start must not play a move")
	touch(center, true)
	drag(center + Vector2(65, -25))
	touch(game.menu.get_global_rect().get_center(), false)
	assert(game.touch_index == -1 and not game.menu.get_popup().visible, "A gesture ending over the HUD must release without opening it")
	assert(game.state == original)
	var yaw = game.board.orbit_yaw
	pose = game.board.camera.transform
	game._render()
	await settle()
	assert(game.board.camera.transform.is_equal_approx(pose), "HUD updates must preserve the chosen camera")
	await capture("portrait-orbit")
	# A tap is picked through the rotated camera, not the original projection.
	at = game.board.camera.unproject_position(game.board.cell_position(2, 0, 0.04))
	touch(at, true)
	touch(at, false)
	assert(Rules.pawn_by_id(game.state, "blue-1").y == 0, "Squares must remain tappable after rotation")
	await create_timer(0.3).timeout
	pose = game.board.camera.transform
	touch(game.undo_button.get_global_rect().get_center(), true)
	drag(center)
	touch(center, false)
	assert(game.touch_index == -1 and game.board.camera.transform.is_equal_approx(pose), "A drag starting on a button must not rotate the board")
	# Check framing and picking around a complete orbit, including both tilt limits.
	for size in [Vector2i(390, 844), Vector2i(640, 360)]:
		root.size = size
		root.content_scale_size = size
		game._layout()
		await settle()
		for angle in range(0, 360, 30):
			game.board.orbit_yaw = deg_to_rad(angle)
			game.board.orbit(Vector2(0, -10000 if angle % 60 == 0 else 10000), game.play_area)
			for x in [-1, 0, 9, 10]:
				for y in [0, 5]:
					var point = game.board.camera.unproject_position(game.board.cell_position(x, y, 0.04))
					assert(game.play_area.grow(1).has_point(point), "Rotating must keep every playable square inside the HUD")
			assert(game.state.phase == "run")
	game.board.orbit_yaw = yaw
	game._menu_action(7)
	await create_timer(0.6).timeout
	assert(game.board.orbit_yaw == 0 and game.board.orbit_tilt == 0 and not game.board.top_view)
	await capture("landscape-reset")
	game._menu_action(0)
	await create_timer(0.6).timeout
	center = game.play_area.get_center()
	pose = game.board.camera.transform
	touch(center, true)
	drag(center + Vector2(50, 0))
	touch(center + Vector2(50, 0), false)
	assert(game.board.top_view and not game.board.camera.transform.is_equal_approx(pose), "Overhead view can rotate too")
	# Canceled/multiple touches and pause must never turn a partial gesture into a tap.
	original = game.state.duplicate(true)
	touch(center, true)
	touch(center, false, 0, true)
	assert(game.state == original)
	touch(center, true)
	touch(center + Vector2(20, 0), true, 1)
	drag(center + Vector2(40, 0), 1)
	touch(center, false)
	touch(center, false, 1)
	assert(game.state == original and game.touch_index == -1)
	touch(center, true)
	game.session_menu.open()
	assert(game.touch_index == -1)
	game.session_menu.close()
	pose = game.board.camera.transform
	game.animating = true
	touch(center, true)
	drag(center + Vector2(100, 0))
	touch(center, false)
	assert(game.board.camera.transform.is_equal_approx(pose), "Cinematics must retain camera ownership")
	game.animating = false
	game.set_preference("reduced_motion", true)
	touch(center, true)
	drag(center + Vector2(30, 0))
	touch(center + Vector2(30, 0), false)
	assert(not game.board.camera.transform.is_equal_approx(pose), "Reduced motion still permits direct camera control")
	print("PASS: touch taps, orbit/tilt, no accidental moves, HUD release, rotated picking, full-circle framing, reset, overhead, cancellation, pause and reduced motion.")
	quit()
