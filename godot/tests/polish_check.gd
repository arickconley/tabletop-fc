extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")
const Save = preload("res://scripts/match_save.gd")

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in range(5):
		await process_frame

func run() -> void:
	root.size = Vector2i(1280, 800)
	var game = MatchScene.instantiate()
	game.screen = "match"
	game.computer_team = ""
	root.add_child(game)
	await settle()
	var start = Rules.kickoff(Rules.create_game(), 6, 4)
	start.phase = "roll"
	start.opening = false
	start.selected = null
	start.used = []
	start.roll = 0
	start.remaining = 0
	start.ball = {"x": 3, "y": 1}
	game._accept(Rules.select_pawn(Rules.roll_die(start, 4), "blue-1"), false)
	var piece = game.board.pieces["blue-1"]
	var leg = piece.get_node("Rig/LeftLeg")
	var before = leg.rotation.x
	game._accept(Rules.run_step(game.state, 3, 1))
	await create_timer(0.12).timeout
	assert(absf(leg.rotation.x - before) > 0.05, "Running must animate legs, not just slide the rig")
	assert(game.board.selected_ring.position.distance_to(Vector3(piece.position.x + piece.get_node("Rig").position.x, 0.1, piece.position.z + piece.get_node("Rig").position.z)) < 0.1)
	await create_timer(0.2).timeout
	assert(absf(piece.get_node("Rig").position.x) < 0.01, "The model must settle on its logical square")
	piece.get_node("Rig").rotation.y = PI / 2
	var offset = game.board._ball_position(game.state) - game.board.cell_position(3, 1, 0.24)
	assert(offset.x > 0.3 and absf(offset.z) < 0.01, "Ball contact follows the player's facing")
	game.kick_plan.append(Rules.kick_step(game.state, 4, 1))
	game._render()
	var snapshot = game._snapshot()
	assert(Save.valid(snapshot))
	var path = "/tmp/tabletop-fc-polish-%d.save" % OS.get_process_id()
	assert(Save.write_match(path, snapshot) == OK)
	assert(Save.read_match(path) == snapshot)
	var broken = snapshot.duplicate(true)
	broken.state.pawns[0].x = "bad"
	assert(not Save.valid(broken))
	assert(Save.write_match(path, broken) == ERR_INVALID_DATA)
	assert(Save.read_match(path) == snapshot, "Invalid writes must preserve the last good save")
	var file = FileAccess.open(path + ".corrupt", FileAccess.WRITE)
	file.store_var("not a match")
	file.close()
	assert(Save.read_match(path + ".corrupt").has("error"))
	game.saved_match = snapshot
	game.screen = "home"
	game._continue_match()
	assert(game.state == snapshot.state and game.history == snapshot.history and game.kick_plan == snapshot.plan, "Continue restores the current roll, undo history and kick draft")
	game._undo()
	assert(game.kick_plan.is_empty() and game.state.roll == 4, "Resuming must not grant another roll")
	game.session_menu.open()
	var frozen = game.board.idle_time
	await create_timer(0.15).timeout
	assert(is_equal_approx(frozen, game.board.idle_time), "Pause freezes the pitch")
	game.session_menu.close()
	game.set_preference("reduced_motion", true)
	game.set_preference("muted", true)
	assert(game.board.reduced_motion and game.dice.reduced_motion and game.audio.muted)
	game._accept(start, false)
	game.persistence_enabled = true
	game.save_path = path
	game._roll_turn()
	await process_frame
	var rolled = Save.read_match(path)
	assert(rolled.state.phase == "select" and rolled.state.roll > 0, "The die result is saved before presentation finishes")
	while game.animating:
		await process_frame
	game.persistence_enabled = false
	var rolled_state = game.state.duplicate(true)
	game.keyboard_cell = Vector2i(2, 1)
	game.keyboard_active = true
	var enter = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._keyboard(enter)
	assert(game.state.selected == "blue-1", "Keyboard selection uses the same rule actions as taps")
	var right = InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	var screen_before = game.board.camera.unproject_position(game.board.cell_position(game.keyboard_cell.x, game.keyboard_cell.y))
	game._keyboard(right)
	var screen_after = game.board.camera.unproject_position(game.board.cell_position(game.keyboard_cell.x, game.keyboard_cell.y))
	assert(screen_after.x > screen_before.x, "Right follows screen direction")
	var final = rolled_state.duplicate(true)
	final.phase = "finished"
	final.winner = "blue"
	game.computer_team = "red"
	game._accept(final, false)
	assert(game.result_title.text == "YOU WIN!")
	var kits = game.team_kits.duplicate(true)
	game._primary()
	assert(game.screen == "match" and game.state.phase == "ready" and game.team_kits == kits and game.computer_team == "red", "Rematch preserves kits/mode and skips the lobby")
	await game._open_home()
	await game._open_setup("")
	game.set_preference("reduced_motion", false)
	game._start_match(0, 0, "")
	game.journey.skip_entrance()
	var deadline = Time.get_ticks_msec() + 2000
	while game.screen == "entrance" and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(game.screen == "match" and not game.board.entering, "Skipping before models finish loading must still complete the entrance")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".corrupt")
	print("PASS: moving legs and markers, ball contact, atomic saves, corrupt-save recovery, resumed drafts, pause, reduced motion, interrupted dice, keyboard play and direct rematches.")
	quit()
