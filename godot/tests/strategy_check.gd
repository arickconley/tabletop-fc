extends SceneTree

const Rules = preload("res://scripts/rules.gd")
const Computer = preload("res://scripts/computer.gd")

func _initialize() -> void:
	run.call_deferred()

func solve(state: Dictionary, seed_value: int = 1) -> Dictionary:
	var original = state.duplicate(true)
	var search = Computer.new(state, seed_value)
	var max_slice = 0
	while not search.done:
		var began = Time.get_ticks_usec()
		search.advance()
		max_slice = maxi(max_slice, Time.get_ticks_usec() - began)
	assert(state == original and not search.plan.is_empty())
	var result = state
	for action in search.plan:
		result = Computer.apply_action(result, action)
		assert(not result.has("error"))
	assert(search.nodes <= Computer.MAX_NODES + 1)
	assert(search.reply_nodes <= Computer.FINALISTS * 6 * (Computer.REPLY_NODES + 1))
	return {"state": result, "plan": search.plan, "slice_usec": max_slice}

func reflected(state: Dictionary) -> Dictionary:
	var result = state.duplicate(true)
	result.ball.y = 5 - result.ball.y
	for p in result.pawns:
		p.y = 5 - p.y
	return result

func pawn(id: String, team: String, x: int, y: int, keeper: bool = false) -> Dictionary:
	return {"id": id, "team": team, "x": x, "y": y, "keeper": keeper}

func turn(pawns: Array, ball: Dictionary, roll: int) -> Dictionary:
	var state = Rules.create_game()
	state.phase = "roll"
	state.pawns = pawns
	state.ball = ball
	return Rules.roll_die(state, roll)

func run() -> void:
	var outcomes = {}
	var y_sum = 0.0
	var mirror_y_sum = 0.0
	var slowest_slice = 0
	for i in range(12):
		var start = Rules.kickoff(Rules.create_game(), 1, 5)
		var result = solve(start, i)
		outcomes[str(result.state.ball)] = true
		y_sum += result.state.ball.y
		mirror_y_sum += solve(reflected(start), i).state.ball.y
		slowest_slice = maxi(slowest_slice, result.slice_usec)
		if i == 0:
			assert(solve(start, i).plan == result.plan, "A fixed seed must reproduce a decision")
	assert(outcomes.size() >= 2, "Repeated openings need competitive alternatives, not the same sideline every time")
	assert(absf((y_sum + mirror_y_sum) / 12.0 - 5.0) < 1.0, "Mirrored fields must not retain a fixed flank preference")
	# The tempting forward square concedes on a six. A diagonal clearance does not.
	var trap = turn([pawn("blue-1", "blue", 4, 2), pawn("blue-0", "blue", 0, 5, true), pawn("red-1", "red", 6, 2)], {"x": 4, "y": 2}, 1)
	var blunder = Rules.commit_turn(Rules.kick_step(Rules.select_pawn(trap, "blue-1"), 5, 2))
	var counter = Rules.run_step(Rules.select_pawn(Rules.roll_die(blunder, 6), "red-1"), 5, 2)
	for x in range(4, -2, -1):
		counter = Rules.kick_step(counter, x, 3)
		assert(not counter.has("error"))
	assert(counter.phase == "goal", "The tactical fixture must contain a real legal counterattack")
	for i in range(6):
		var start = trap if i % 2 == 0 else reflected(trap)
		var result = solve(start, i).state
		var opponent = Rules.pawn_by_id(result, "red-1")
		var reach = absi(opponent.x - result.ball.x) + absi(opponent.y - result.ball.y)
		var shot = result.ball.x + 1
		assert(reach + shot - 1 > 6, "Choose a clearance that cannot concede next turn, including the free kick step")
	var passing = turn([pawn("blue-1", "blue", 5, 2), pawn("blue-2", "blue", 7, 2), pawn("blue-3", "blue", 8, 3), pawn("red-1", "red", 1, 5)], {"x": 5, "y": 2}, 2)
	for i in range(6):
		var result = solve(passing if i % 2 == 0 else reflected(passing), i).state
		assert(result.phase == "goal" and result.used.size() >= 3, "Take the scoring combination through two receivers on either flank")
	print("PASS: seeded variety, mirrored flanks, safe counterattack clearance and two-pass goals. Longest opening search slice: ", slowest_slice / 1000.0, " ms.")
	quit()
