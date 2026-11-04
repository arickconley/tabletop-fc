extends SceneTree

const Rules = preload("res://scripts/rules.gd")
const METHODS = {"kickoff": "kickoff", "halftimeKickoff": "kickoff", "rollDie": "roll_die", "selectPawn": "select_pawn", "runStep": "run_step", "kickStep": "kick_step", "relocate": "relocate", "commitTurn": "commit_turn", "continueAfterGoal": "continue_after_goal"}

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	var path = args[0] if not args.is_empty() else "/tmp/tabletop-fc-rules.json"
	var cases = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rules = Rules.new()
	if not cases is Array or cases.is_empty():
		push_error("Generate reference cases with node godot/tests/reference.mjs first.")
		quit(1)
		return
	for i in range(cases.size()):
		var test = cases[i]
		var before = test.state.duplicate(true)
		var params: Array = [test.state]
		params.append_array(test.args)
		var actual = rules.callv(METHODS[test.method], params)
		if test.state != before:
			push_error("Transition %d mutated its input" % i)
			quit(1)
			return
		if test.get("invalid", false):
			if not actual.has("error"):
				push_error("Transition %d accepted an illegal action" % i)
				quit(1)
				return
		elif JSON.parse_string(JSON.stringify(actual)) != test.expected or JSON.parse_string(JSON.stringify(Rules.legal_targets(actual))) != test.targets:
			push_error("Transition %d (%s) differs from the web rules\nExpected: %s\nActual: %s" % [i, test.method, JSON.stringify(test.expected), JSON.stringify(actual)])
			quit(1)
			return
	print("PASS: %d transitions match the web rules, including legal targets, immutable state, invalid actions, goals, relocation, halftime and complete matches." % cases.size())
	quit()
