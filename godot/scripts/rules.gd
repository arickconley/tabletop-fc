class_name MatchRules
extends RefCounted

# Rendering-independent port of src/game.js. Coordinates and state keys match
# the web edition so recorded turns can be compared between implementations.
const WIDTH = 10
const HEIGHT = 6
const DIRECTIONS = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const ORTHOGONAL = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func other(team: String) -> String:
	return "red" if team == "blue" else "blue"

static func inside(x: int, y: int) -> bool:
	return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT

static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.x == b.x and a.y == b.y

static func pawn_at(s: Dictionary, x: float, y: float) -> Dictionary:
	for p in s.pawns:
		if p.x == x and p.y == y:
			return p
	return {}

static func pawn_by_id(s: Dictionary, id) -> Dictionary:
	for p in s.pawns:
		if p.id == id:
			return p
	return {}

static func in_ring(x: int, y: int) -> bool:
	return x in [4, 5] and y in [2, 3]

static func in_mouth(team: String, x: int, y: int) -> bool:
	return x == (0 if team == "blue" else 9) and y in [2, 3]

static func in_box(team: String, x: int, y: int) -> bool:
	return (x <= 1 if team == "blue" else x >= 8) and y in [2, 3]

static func create_game() -> Dictionary:
	var pawns: Array = []
	var shapes = {"blue": [[0, 3], [2, 1], [2, 4], [4, 3], [6, 0]], "red": [[9, 2], [7, 1], [7, 4], [5, 2], [3, 5]]}
	for team in shapes:
		for i in range(5):
			pawns.append({"id": "%s-%d" % [team, i], "team": team, "keeper": i == 0, "x": shapes[team][i][0], "y": shapes[team][i][1]})
	return {
		"phase": "ready", "team": "blue", "pawns": pawns,
		"ball": {"x": 4.5, "y": 2.5}, "remaining": 0, "roll": 0,
		"selected": null, "used": [], "direction": null, "curved": false,
		"free": false, "opening": false, "openingTeam": null,
		"halftimeTeam": null, "nextTurnTeam": null, "kickoffKind": null,
		"formation": null, "half": 1, "rolls": {"blue": 0, "red": 0},
		"score": {"blue": 0, "red": 0}, "turn": 1, "winner": null,
		"trail": [], "lastDice": null,
	}

static func _begin_kick(s: Dictionary, p: Dictionary, free: bool = true) -> void:
	s.selected = p.id
	s.used.append(p.id)
	s.direction = null
	s.curved = false
	s.free = free
	s.phase = "kick"

static func kickoff(state: Dictionary, blue: int, red: int) -> Dictionary:
	if state.phase not in ["ready", "halftime"]:
		return {"error": "A kickoff is not due."}
	if blue < 1 or blue > 6 or red < 1 or red > 6:
		return {"error": "A die must show 1–6."}
	if blue == red:
		return {"error": "Tied kickoff rolls. Roll again."}
	var s = state.duplicate(true)
	if s.phase == "ready":
		s.formation = s.pawns.duplicate(true)
		s.openingTeam = "blue" if blue > red else "red"
		s.halftimeTeam = other(s.openingTeam)
		s.kickoffKind = "opening"
		s.team = s.openingTeam
	else:
		s.half = 2
		s.kickoffKind = "halftime"
		s.team = s.halftimeTeam
	s.nextTurnTeam = other(s.team)
	s.opening = true
	s.lastDice = [blue, red]
	s.remaining = absi(blue - red)
	s.roll = s.remaining
	s.used = []
	s.trail = []
	for p in s.pawns:
		if p.team == s.team and not p.keeper and in_ring(p.x, p.y):
			s.ball = {"x": p.x, "y": p.y}
			_begin_kick(s, p, false)
			return s
	return {"error": "The kickoff team needs a runner in the center ring."}

static func roll_die(state: Dictionary, n: int) -> Dictionary:
	if state.phase != "roll":
		return {"error": "Finish the current turn first."}
	if n < 1 or n > 6:
		return {"error": "A die must show 1–6."}
	if state.rolls[state.team] >= (10 if state.half == 1 else 20):
		return {"error": "This player has used every roll in this half."}
	var s = state.duplicate(true)
	s.rolls[s.team] += 1
	s.roll = n
	s.remaining = n
	s.phase = "select"
	s.used = []
	s.selected = null
	s.trail = []
	s.lastDice = null
	return s

static func select_pawn(state: Dictionary, id: String) -> Dictionary:
	if state.phase not in ["select", "run"]:
		return {"error": "Choose a player after rolling."}
	if state.phase == "run" and state.remaining != state.roll:
		return {"error": "Only one player can run each turn. Undo to change players."}
	var s = state.duplicate(true)
	var p = pawn_by_id(s, id)
	if p.is_empty() or p.team != s.team:
		return {"error": "Choose a player on the active team."}
	s.selected = id
	s.phase = "run"
	if same(p, s.ball):
		_begin_kick(s, p)
	elif run_options(s).is_empty():
		s.phase = "review"
	return s

static func run_options(s: Dictionary) -> Array:
	if s.phase != "run":
		return []
	var p = pawn_by_id(s, s.selected)
	var result: Array = []
	for d in ORTHOGONAL:
		var x = p.x + d.x
		var y = p.y + d.y
		if inside(x, y) and pawn_at(s, x, y).is_empty():
			result.append({"x": x, "y": y})
	return result

static func _target(options: Array, x: int, y: int) -> Dictionary:
	for p in options:
		if p.x == x and p.y == y:
			return p
	return {}

static func run_step(state: Dictionary, x: int, y: int) -> Dictionary:
	if _target(run_options(state), x, y).is_empty():
		return {"error": "Choose an adjacent highlighted square."}
	var s = state.duplicate(true)
	var p = pawn_by_id(s, s.selected)
	s.trail.append({"x": p.x, "y": p.y, "kind": "run"})
	p.x = x
	p.y = y
	s.remaining -= 1
	if same(p, s.ball):
		_begin_kick(s, p)
	elif s.remaining == 0 or run_options(s).is_empty():
		s.phase = "review"
	return s

static func kick_options(s: Dictionary) -> Array:
	if s.phase != "kick" or (not s.free and s.remaining <= 0):
		return []
	var result: Array = []
	for dir in range(8):
		if s.direction != null:
			var delta = mini(posmod(dir - int(s.direction), 8), posmod(int(s.direction) - dir, 8))
			if delta != 0 and (s.curved or delta != 1):
				continue
		var x = s.ball.x + DIRECTIONS[dir].x
		var y = s.ball.y + DIRECTIONS[dir].y
		if not inside(x, y):
			var goal_x = 10 if s.team == "blue" else -1
			if not s.opening and x == goal_x and (y == 2 or y == 3) and in_mouth(other(s.team), s.ball.x, s.ball.y) and position_errors(s).is_empty():
				result.append({"x": x, "y": y, "dir": dir, "goal": true})
			continue
		var p = pawn_at(s, x, y)
		if not p.is_empty() and (p.team != s.team or p.id in s.used):
			continue
		result.append({"x": x, "y": y, "dir": dir, "pass": not p.is_empty()})
	return result

static func kick_step(state: Dictionary, x: int, y: int) -> Dictionary:
	var option = _target(kick_options(state), x, y)
	if option.is_empty():
		return {"error": "Choose a highlighted square. A kick can bend once by 45°."}
	var s = state.duplicate(true)
	var kicker = pawn_by_id(s, s.selected)
	s.trail.append({"x": s.ball.x, "y": s.ball.y, "kind": "kick"})
	if not s.free:
		s.remaining -= 1
	s.free = false
	if s.direction != null and s.direction != option.dir:
		s.curved = true
	s.direction = option.dir
	s.ball = {"x": x, "y": y}
	if option.get("goal", false):
		s.phase = "goal"
		s.score[s.team] += 1
		return s
	var receiver = pawn_at(s, x, y)
	if not receiver.is_empty():
		_begin_kick(s, receiver, not s.opening)
	elif s.remaining == 0:
		s.phase = "review"
	if not kicker.keeper and in_mouth(kicker.team, kicker.x, kicker.y):
		s.resumePhase = s.phase
		s.relocating = kicker.id
		s.phase = "relocate"
	return s

static func relocation_options(s: Dictionary) -> Array:
	if s.phase != "relocate":
		return []
	var p = pawn_by_id(s, s.relocating)
	var result: Array = []
	for d in ORTHOGONAL:
		var x = p.x + d.x
		var y = p.y + d.y
		if inside(x, y) and pawn_at(s, x, y).is_empty() and not same({"x": x, "y": y}, s.ball) and not in_mouth(s.team, x, y):
			result.append({"x": x, "y": y})
	return result

static func relocate(state: Dictionary, x: int, y: int) -> Dictionary:
	if _target(relocation_options(state), x, y).is_empty():
		return {"error": "Move to an empty adjacent square outside your goal mouth."}
	var s = state.duplicate(true)
	var p = pawn_by_id(s, s.relocating)
	p.x = x
	p.y = y
	s.phase = s.resumePhase
	s.erase("relocating")
	s.erase("resumePhase")
	return s

static func opponent_can_reach_ball(s: Dictionary) -> bool:
	var occupied = {}
	var queue: Array[Vector2i] = []
	var visited = {}
	for p in s.pawns:
		var cell = Vector2i(p.x, p.y)
		occupied[cell] = true
		if p.team != s.team:
			queue.append(cell)
			visited[cell] = true
	var ball = Vector2i(s.ball.x, s.ball.y)
	if occupied.has(ball):
		return false
	var i = 0
	while i < queue.size():
		var p = queue[i]
		i += 1
		if p == ball:
			return true
		for d in ORTHOGONAL:
			var next = p + d
			if inside(next.x, next.y) and not visited.has(next) and not occupied.has(next):
				visited[next] = true
				queue.append(next)
	return false

static func position_errors(s: Dictionary) -> Array:
	var errors: Array = []
	var box_count = 0
	for p in s.pawns:
		if p.team != s.team or p.keeper:
			continue
		if in_mouth(s.team, p.x, p.y) and not "A runner cannot finish in its own goal mouth." in errors:
			errors.append("A runner cannot finish in its own goal mouth.")
		if in_box(s.team, p.x, p.y):
			box_count += 1
	if box_count > 1:
		errors.append("Only one runner may finish in your defensive box.")
	return errors

static func end_turn_errors(s: Dictionary) -> Array:
	if s.opening and (s.phase != "review" or s.remaining != 0):
		return ["Kickoffs must use their exact distance."]
	if s.phase == "relocate":
		return ["Move the runner out of the goal mouth first."]
	if s.phase not in ["select", "run", "kick", "review"]:
		return ["Roll before ending a turn."]
	if not pawn_at(s, s.ball.x, s.ball.y).is_empty():
		return ["Kick the ball off its player before ending the turn."]
	var errors = position_errors(s)
	if not opponent_can_reach_ball(s):
		errors.append("Leave an opponent a path to the ball.")
	return errors

static func _clear_turn(s: Dictionary) -> void:
	s.opening = false
	s.kickoffKind = null
	s.nextTurnTeam = null
	s.phase = "roll"
	s.selected = null
	s.used = []
	s.free = false
	s.remaining = 0
	s.roll = 0
	s.lastDice = null
	s.direction = null
	s.curved = false
	s.trail = []

static func _reset_formation(s: Dictionary) -> void:
	s.pawns = s.formation.duplicate(true) if s.formation != null else create_game().pawns
	s.ball = {"x": 4.5, "y": 2.5}

static func _advance_normal_turn(s: Dictionary) -> void:
	var next = other(s.team)
	_clear_turn(s)
	if s.rolls.blue == 20 and s.rolls.red == 20:
		s.phase = "finished"
		s.winner = null if s.score.blue == s.score.red else ("blue" if s.score.blue > s.score.red else "red")
	elif s.half == 1 and s.rolls.blue == 10 and s.rolls.red == 10:
		s.turn += 1
		s.phase = "halftime"
		s.team = s.halftimeTeam
		_reset_formation(s)
	else:
		s.turn += 1
		s.team = next

static func commit_turn(state: Dictionary) -> Dictionary:
	var errors = end_turn_errors(state)
	if not errors.is_empty():
		return {"error": errors[0]}
	var s = state.duplicate(true)
	if s.opening:
		s.team = s.nextTurnTeam
		_clear_turn(s)
	else:
		_advance_normal_turn(s)
	return s

static func continue_after_goal(state: Dictionary) -> Dictionary:
	if state.phase != "goal":
		return {"error": "There is no goal to restart from."}
	var s = state.duplicate(true)
	_advance_normal_turn(s)
	if s.phase == "roll":
		_reset_formation(s)
		for p in s.pawns:
			if p.team == s.team and not p.keeper and in_ring(p.x, p.y):
				s.ball = {"x": p.x, "y": p.y}
	return s

static func legal_targets(s: Dictionary) -> Array:
	match s.phase:
		"run": return run_options(s)
		"kick": return kick_options(s)
		"relocate": return relocation_options(s)
	return []
