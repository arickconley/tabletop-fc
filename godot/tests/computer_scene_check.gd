extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
const Rules = preload("res://scripts/rules.gd")

func _initialize() -> void:
	run.call_deferred()

func wait_for_human(game: Node3D) -> bool:
	var deadline = Time.get_ticks_msec() + 30000
	while game.computer_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	return not game.computer_busy and not game.computer_failed and not game.animating

func seed_rolls(game: Node3D, values: Array) -> void:
	var random = RandomNumberGenerator.new()
	for seed_value in range(100000):
		random.seed = seed_value
		var actual: Array = []
		for value in values:
			actual.append(random.randi_range(1, 6))
		if actual == values:
			game.random.seed = seed_value
			return
	assert(false, "Could not seed the dice")

func run() -> void:
	var game = MatchScene.instantiate()
	game.screen = "match"
	root.add_child(game)
	await process_frame
	assert(game.computer_team == "red")
	assert(game.dice.caption.text.contains("You’re Blue"))
	assert(not game.computer_busy, "The human starts the opening dice")
	game._new_match("")
	assert(game.computer_team == "" and not game.computer_busy)
	game._new_match("red")
	assert(game.computer_team == "red")
	# The computer can win the opening roll and must spend the exact distance.
	game._accept(Rules.kickoff(Rules.create_game(), 1, 6), false)
	assert(game.computer_busy and not game.primary.visible)
	var before = game.state.duplicate(true)
	game._tap(Vector2(300, 300))
	game._primary()
	game._roll_turn()
	game._menu_action(4)
	assert(game.state == before and game.computer_team == "red", "Human controls must not alter the computer turn")
	assert(await wait_for_human(game), "Computer kickoff must finish")
	assert(game.state.team == "blue" and game.state.phase == "roll")
	assert(game.dice.visible and not game.dice.first.disabled)
	assert(game.history.is_empty() and game.kick_plan.is_empty())
	# Normal rolls happen automatically, with dice animation, then legal playback.
	var normal = game.state.duplicate(true)
	normal.team = "red"
	game._accept(normal, false)
	assert(await wait_for_human(game), "A normal computer turn must finish")
	assert(game.state.rolls.red == 1 and game.state.team == "blue")
	assert(game.dice.visible and not game.dice.first.disabled)
	# A scoring pass must play the route and restart for the human.
	var shot = normal.duplicate(true)
	shot.pawns = [
		{"id": "r", "team": "red", "x": 3, "y": 2, "keeper": false},
		{"id": "r2", "team": "red", "x": 2, "y": 2, "keeper": false},
		{"id": "b", "team": "blue", "x": 8, "y": 5, "keeper": false}]
	shot.ball = {"x": 3, "y": 2}
	game._accept(Rules.roll_die(shot, 2), false)
	assert(await wait_for_human(game), "Computer scoring pass must finish")
	assert(game.state.score.red == 1 and game.state.team == "blue")
	assert(game.state.phase == "roll" and game.dice.visible)
	# Half-time dice belong to the fixed second-half kicker.
	var half = normal.duplicate(true)
	half.phase = "halftime"
	half.halftimeTeam = "red"
	half.rolls = {"blue": 10, "red": 10}
	seed_rolls(game, [3, 3, 6, 1])
	game._accept(half, false)
	assert(await wait_for_human(game), "Computer must roll and complete its halftime kickoff")
	assert(game.state.half == 2 and game.state.team == "blue")
	assert(game.state.rolls == {"blue": 10, "red": 10})
	# The computer must stop at full time and preserve the selected mode on replay.
	var last = normal.duplicate(true)
	last.half = 2
	last.rolls = {"blue": 20, "red": 19}
	game._accept(last, false)
	assert(await wait_for_human(game), "Computer must finish its last roll")
	assert(game.state.phase == "finished" and not game.dice.visible)
	assert(game.state.rolls == {"blue": 20, "red": 20})
	assert(game.primary.visible and game.primary.text == "Play again" and not game.primary.disabled)
	game._primary()
	var deadline = Time.get_ticks_msec() + 5000
	while game.screen != "setup" and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(game.state.phase == "ready" and game.computer_team == "red" and game.screen == "setup")
	game.screen = "match"
	# A stale deferred turn cannot move pieces in a replacement match.
	game._accept(normal, false)
	game._new_match("")
	await create_timer(0.6).timeout
	assert(game.state.phase == "ready" and game.computer_team == "" and not game.computer_busy)
	# Local mode leaves Red's dice and moves under human control.
	game._accept(normal, false)
	await create_timer(0.6).timeout
	assert(game.state == normal and not game.computer_busy)
	assert(game.dice.visible and not game.dice.first.disabled)
	assert(not game.menu.disabled)
	print("PASS: mode selection, automatic dice, animated computer kickoff/run/pass/goal, input locking, human handoff, tied halftime dice, full time, replay, cancellation and local play.")
	quit()
