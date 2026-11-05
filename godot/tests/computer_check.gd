extends SceneTree

const Rules = preload("res://scripts/rules.gd")
const Computer = preload("res://scripts/computer.gd")
var plans = 0
var longest_usec = 0

func _initialize() -> void:
	run.call_deferred()

func finish(state: Dictionary) -> Dictionary:
	var original = state.duplicate(true)
	var search = Computer.new(state)
	var began = Time.get_ticks_usec()
	while not search.done:
		search.advance()
	longest_usec = maxi(longest_usec, Time.get_ticks_usec() - began)
	assert(not search.plan.is_empty(), "No complete turn: %s" % state)
	assert(state == original, "Search must not mutate the live match")
	assert(search.nodes <= Computer.MAX_NODES + 1)
	var result = state
	for action in search.plan:
		result = Computer.apply_action(result, action)
		assert(not result.has("error"), "Every action must obey the match rules")
	assert(result.phase in ["roll", "goal", "halftime", "finished"])
	plans += 1
	return result

func pawn(id: String, team: String, x: int, y: int) -> Dictionary:
	return {"id": id, "team": team, "x": x, "y": y, "keeper": false}

func turn(pawns: Array, ball: Dictionary, roll: int) -> Dictionary:
	var state = Rules.kickoff(Rules.create_game(), 1, 6)
	state.phase = "roll"
	state.opening = false
	state.kickoffKind = null
	state.selected = null
	state.used = []
	state.pawns = pawns
	state.ball = ball
	return Rules.roll_die(state, roll)

func run() -> void:
	for team in ["blue", "red"]:
		for distance in range(1, 6):
			var kickoff = Rules.kickoff(Rules.create_game(), distance + 1 if team == "blue" else 1, distance + 1 if team == "red" else 1)
			var result = finish(kickoff)
			assert(result.team == Rules.other(team))
			assert(result.rolls == {"blue": 0, "red": 0})
			assert(result.score == {"blue": 0, "red": 0})
	var shot = turn([pawn("r", "red", 2, 2), pawn("b", "blue", 8, 5)], {"x": 2, "y": 2}, 2)
	assert(finish(shot).score.red == 1, "Take an available goal")
	var passing = turn([pawn("r", "red", 3, 2), pawn("r2", "red", 2, 2), pawn("b", "blue", 8, 5)], {"x": 3, "y": 2}, 2)
	var goal = finish(passing)
	assert(goal.phase == "goal" and "r2" in goal.used, "Use the pass and its free step to score")
	var relocation = turn([pawn("r", "red", 9, 2), pawn("b", "blue", 2, 5)], {"x": 9, "y": 2}, 2)
	relocation = Rules.kick_step(Rules.select_pawn(relocation, "r"), 8, 2)
	assert(relocation.phase == "relocate")
	var relocated = finish(relocation)
	assert(not Rules.in_mouth("red", relocated.pawns[0].x, relocated.pawns[0].y))
	var blocked = turn([pawn("r", "red", 2, 1), pawn("b", "blue", 8, 5)], {"x": 2, "y": 1}, 5)
	blocked = Rules.kick_step(Rules.select_pawn(blocked, "r"), 1, 0)
	blocked = Rules.kick_step(blocked, 0, 0)
	assert(Rules.legal_targets(blocked).is_empty())
	assert(finish(blocked).ball == {"x": 0, "y": 0})
	var impossible = Rules.kickoff(Rules.create_game(), 1, 6)
	impossible.ball = {"x": 0, "y": 0}
	impossible.direction = 5
	impossible.curved = true
	var search = Computer.new(impossible)
	while not search.done:
		search.advance()
	assert(search.plan.is_empty(), "Never return an illegal partial kickoff")
	for seed_value in range(1, 4):
		var random = RandomNumberGenerator.new()
		random.seed = seed_value
		var state = Rules.kickoff(Rules.create_game(), 6 if seed_value % 2 else 1, 1 if seed_value % 2 else 6)
		var turns = 0
		var halftime = false
		while state.phase != "finished" and turns < 110:
			turns += 1
			match state.phase:
				"roll": state = Rules.roll_die(state, random.randi_range(1, 6))
				"goal": state = Rules.continue_after_goal(state)
				"halftime":
					assert(state.rolls == {"blue": 10, "red": 10})
					assert(state.team == Rules.other(state.openingTeam))
					halftime = true
					state = Rules.kickoff(state, 6, 1)
				_: state = finish(state)
		assert(state.phase == "finished" and halftime)
		assert(state.rolls == {"blue": 20, "red": 20})
		assert(state.score.blue + state.score.red > 0, "Create scoring chances")
		print("Match ", seed_value, ": ", state.score)
	print("PASS: ", plans, " legal computer plans, kickoffs, passes, goals, relocation and three full matches. Longest search: ", longest_usec / 1000, " ms.")
	quit()
