class_name MatchComputer
extends RefCounted

const Rules = preload("res://scripts/rules.gd")
const WIDTH = 64
const MAX_NODES = 18000
const REPLY_NODES = 900
const FINALISTS = 6
var done = false
var plan: Array = []
var nodes = 0
var best_value = -INF
var team: String
var frontier: Array = []
var next_frontier: Array = []
var visited: Dictionary = {}
var cursor = 0
var depth = 0
var random = RandomNumberGenerator.new()
var analyze_replies: bool
var candidates: Array = []
var evaluating_replies = false
var candidate_index = 0
var reply_roll = 1
var reply_search: RefCounted
var reply_start: Dictionary = {}
var reply_total = 0.0
var reply_nodes = 0
var decision_value = -INF

func _init(state: Dictionary, seed_value: int = -1, with_replies: bool = true) -> void:
	team = state.team
	analyze_replies = with_replies
	if seed_value < 0:
		random.randomize()
	else:
		random.seed = seed_value
	if state.phase not in ["select", "run", "kick", "relocate", "review"]:
		done = true
		return
	frontier = [{"state": state, "path": [], "score": _value(state), "tie": random.randf()}]
	visited[_key(state)] = true

static func apply_action(state: Dictionary, action: Dictionary) -> Dictionary:
	match action.kind:
		"select": return Rules.select_pawn(state, action.id)
		"run": return Rules.run_step(state, action.x, action.y)
		"kick": return Rules.kick_step(state, action.x, action.y)
		"relocate": return Rules.relocate(state, action.x, action.y)
		"end": return Rules.commit_turn(state)
	return {"error": "Unknown computer action."}

func _actions(state: Dictionary) -> Array:
	var result: Array = []
	if state.phase == "select":
		for pawn in state.pawns:
			if pawn.team == state.team:
				result.append({"kind": "select", "id": pawn.id})
	else:
		for target in Rules.legal_targets(state):
			result.append({"kind": state.phase, "x": target.x, "y": target.y})
	# Shuffle with this search's seed so equal routes do not always favor the first flank.
	for i in range(result.size() - 1, 0, -1):
		var j = random.randi_range(0, i)
		var swap = result[i]
		result[i] = result[j]
		result[j] = swap
	return result

static func _key(state: Dictionary) -> String:
	var positions: Array = []
	for pawn in state.pawns:
		positions.append([pawn.x, pawn.y])
	return str([state.phase, state.remaining, state.selected, state.ball.x, state.ball.y,
		positions, state.used, state.direction, state.curved, state.free,
		state.get("relocating"), state.get("resumePhase")])

func _value(state: Dictionary) -> float:
	if state.phase == "goal":
		return 100000 if state.team == team else -100000
	var progress = state.ball.x if team == "blue" else 9 - state.ball.x
	var ours = 100.0
	var theirs = 100.0
	var exposed = 0.0
	var support = 100.0
	var runner = 100.0
	for pawn in state.pawns:
		var distance = absf(pawn.x - state.ball.x) + absf(pawn.y - state.ball.y)
		if pawn.team == team:
			ours = minf(ours, distance)
			if pawn.keeper:
				exposed = absf(pawn.x - (0 if team == "blue" else 9))
			else:
				support = minf(support, maxf(runner, distance))
				runner = minf(runner, distance)
		else:
			theirs = minf(theirs, distance)
	var central = minf(absf(state.ball.y - 2), absf(state.ball.y - 3))
	var danger = maxf(0, 4 - progress) * maxf(0, 4 - theirs)
	return progress * 7 - ours * 5 + minf(theirs, 6) * 2 - maxf(0, ours - theirs) * 7 - central * 2 - exposed * 4 - danger * 3 - minf(support, 6) * 1.5

func _consider(state: Dictionary, path: Array, score: float) -> void:
	if not analyze_replies:
		return
	var positions: Array = [state.ball]
	for pawn in state.pawns:
		positions.append([pawn.x, pawn.y])
	var key = str(positions)
	for candidate in candidates:
		if candidate.key == key:
			if score > candidate.score:
				candidate.score = score
				candidate.path = path
			return
	candidates.append({"state": state, "path": path, "score": score, "key": key, "variety": random.randf_range(-1.0, 1.0)})
	candidates.sort_custom(func(a, b): return a.score + a.variety > b.score + b.variety)
	if candidates.size() > FINALISTS:
		candidates.resize(FINALISTS)

func _finish_search() -> void:
	if not analyze_replies or candidates.is_empty():
		done = true
	else:
		evaluating_replies = true

func _advance_replies(deadline: int) -> void:
	while Time.get_ticks_usec() < deadline:
		if candidate_index == candidates.size():
			done = true
			return
		var candidate = candidates[candidate_index]
		if reply_roll == 1 and reply_search == null:
			reply_start = Rules.commit_turn(candidate.state)
			if reply_start.phase != "roll":
				reply_total = candidate.score * 6
				reply_roll = 7
		if reply_roll > 6:
			var score = candidate.score * 0.3 + reply_total / 6.0 * 0.7 + candidate.variety
			if score > decision_value:
				decision_value = score
				plan = candidate.path + [{"kind": "end"}]
			candidate_index += 1
			reply_roll = 1
			reply_total = 0.0
			continue
		if reply_search == null:
			var rolled = Rules.roll_die(reply_start, reply_roll)
			reply_search = get_script().new(rolled, random.randi(), false)
		reply_search.advance(maxi(1, deadline - Time.get_ticks_usec()))
		if not reply_search.done:
			return
		reply_nodes += reply_search.nodes
		var response = Rules.roll_die(reply_start, reply_roll)
		for action in reply_search.plan:
			response = apply_action(response, action)
		# Average all six unknown rolls; never peek at the real next die.
		var protect_lead = candidate.state.score[team] > candidate.state.score[Rules.other(team)] and candidate.state.rolls[team] >= 15
		reply_total += (-400.0 if protect_lead else -240.0) if response.phase == "goal" else _value(response)
		reply_search = null
		reply_roll += 1

# shortcut: bounded beams can miss long combinations; widen only with a measured mobile budget.
func advance(budget_usec: int = 4000) -> void:
	var deadline = Time.get_ticks_usec() + budget_usec
	if evaluating_replies:
		_advance_replies(deadline)
		return
	var width = WIDTH if analyze_replies else 16
	var limit = MAX_NODES if analyze_replies else REPLY_NODES
	while not done:
		if cursor == frontier.size():
			next_frontier.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.tie > b.tie)
			frontier = next_frontier.slice(0, width)
			next_frontier = []
			cursor = 0
			depth += 1
			if frontier.is_empty() or depth > 28:
				_finish_search()
				return
		var node: Dictionary = frontier[cursor]
		cursor += 1
		var state: Dictionary = node.state
		if state.phase == "goal":
			plan = node.path
			done = true
			return
		if Rules.end_turn_errors(state).is_empty():
			var score = _value(state) - node.path.size() * 0.025
			if score > best_value:
				best_value = score
				plan = node.path + [{"kind": "end"}]
			_consider(state, node.path, score)
		if nodes < limit:
			for action in _actions(state):
				nodes += 1
				if nodes > limit:
					break
				var child = apply_action(state, action)
				if child.has("error"):
					continue
				var key = _key(child)
				if visited.has(key):
					continue
				visited[key] = true
				var path: Array = node.path + [action]
				if child.phase == "goal":
					plan = path
					done = true
					return
				var contact = Rules.pawn_at(child, child.ball.x, child.ball.y).get("team") == team
				next_frontier.append({"state": child, "path": path, "score": _value(child) + (14 if contact else 0), "tie": random.randf()})
		if Time.get_ticks_usec() >= deadline:
			return
