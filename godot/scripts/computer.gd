class_name MatchComputer
extends RefCounted

const Rules = preload("res://scripts/rules.gd")
const WIDTH = 64
const MAX_NODES = 18000
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

func _init(state: Dictionary) -> void:
	team = state.team
	if state.phase not in ["select", "run", "kick", "relocate", "review"]:
		done = true
		return
	frontier = [{"state": state, "path": [], "score": _value(state)}]
	visited[_key(state)] = true

static func apply_action(state: Dictionary, action: Dictionary) -> Dictionary:
	match action.kind:
		"select": return Rules.select_pawn(state, action.id)
		"run": return Rules.run_step(state, action.x, action.y)
		"kick": return Rules.kick_step(state, action.x, action.y)
		"relocate": return Rules.relocate(state, action.x, action.y)
		"end": return Rules.commit_turn(state)
	return {"error": "Unknown computer action."}

static func _actions(state: Dictionary) -> Array:
	var result: Array = []
	if state.phase == "select":
		for pawn in state.pawns:
			if pawn.team == state.team:
				result.append({"kind": "select", "id": pawn.id})
	else:
		for target in Rules.legal_targets(state):
			result.append({"kind": state.phase, "x": target.x, "y": target.y})
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
		return 100000
	var progress = state.ball.x if team == "blue" else 9 - state.ball.x
	var ours = 100.0
	var theirs = 100.0
	var exposed = 0.0
	for pawn in state.pawns:
		var distance = absf(pawn.x - state.ball.x) + absf(pawn.y - state.ball.y)
		if pawn.team == team:
			ours = minf(ours, distance)
			if pawn.keeper:
				exposed = absf(pawn.x - (0 if team == "blue" else 9))
		else:
			theirs = minf(theirs, distance)
	var central = minf(absf(state.ball.y - 2), absf(state.ball.y - 3))
	var danger = maxf(0, 4 - progress) * maxf(0, 4 - theirs)
	return progress * 7 - ours * 5 + minf(theirs, 6) * 2 - maxf(0, ours - theirs) * 7 - central * 2 - exposed * 2 - danger * 3

# Same bounded beam search as src/ai.js; yield between nodes to keep the pitch responsive.
# shortcut: prunes alternatives to 64 per depth; widen if stronger opponents are needed.
func advance(budget_usec: int = 4000) -> void:
	var deadline = Time.get_ticks_usec() + budget_usec
	while not done:
		if cursor == frontier.size():
			next_frontier.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.path.size() < b.path.size())
			frontier = next_frontier.slice(0, WIDTH)
			next_frontier = []
			cursor = 0
			depth += 1
			if frontier.is_empty() or depth > 28:
				done = true
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
		if nodes < MAX_NODES:
			for action in _actions(state):
				nodes += 1
				if nodes > MAX_NODES:
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
				next_frontier.append({"state": child, "path": path, "score": _value(child) + (14 if contact else 0)})
		if Time.get_ticks_usec() >= deadline:
			return
