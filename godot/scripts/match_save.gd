extends RefCounted

const Rules = preload("res://scripts/rules.gd")
const Kits = preload("res://scripts/team_kits.gd")
const PHASES = ["ready", "roll", "select", "run", "kick", "relocate", "review", "halftime", "goal", "finished"]

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= low and value <= high

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var s: Dictionary = value
	for key in Rules.create_game():
		if not s.has(key):
			return false
	if s.phase not in PHASES or s.team not in ["blue", "red"]:
		return false
	if not s.pawns is Array or s.pawns.size() != 10 or not s.ball is Dictionary:
		return false
	var ids = []
	var cells = []
	for p in s.pawns:
		if not p is Dictionary or p.get("team") not in ["blue", "red"] or not p.get("keeper") is bool:
			return false
		if p.get("id") not in [p.team + "-0", p.team + "-1", p.team + "-2", p.team + "-3", p.team + "-4"] or p.id in ids:
			return false
		if p.keeper != p.id.ends_with("-0") or not _integer(p.get("x"), 0, 9) or not _integer(p.get("y"), 0, 5):
			return false
		var cell = Vector2i(p.x, p.y)
		if cell in cells:
			return false
		ids.append(p.id)
		cells.append(cell)
	if not (s.ball.get("x") is float or s.ball.get("x") is int) or not (s.ball.get("y") is float or s.ball.get("y") is int):
		return false
	if not (s.ball.x == 4.5 and s.ball.y == 2.5 and s.phase in ["ready", "halftime", "finished"]) and not (_integer(s.ball.x, -1, 10) and _integer(s.ball.y, 0, 5)):
		return false
	for key in ["selected", "relocating"]:
		if s.get(key) != null and s[key] not in ids:
			return false
	if s.phase in ["run", "kick", "relocate", "review"] and s.selected == null:
		return false
	if s.phase == "relocate" and (s.get("relocating") == null or s.get("resumePhase") not in ["kick", "review"]):
		return false
	for key in ["openingTeam", "halftimeTeam", "nextTurnTeam", "winner"]:
		if s[key] not in [null, "blue", "red"]:
			return false
	for key in ["free", "opening", "curved"]:
		if not s[key] is bool:
			return false
	if not _integer(s.remaining, 0, 6) or not _integer(s.roll, 0, 6) or not _integer(s.half, 1, 2) or not _integer(s.turn, 1, 100):
		return false
	if s.direction != null and not _integer(s.direction, 0, 7):
		return false
	for key in ["rolls", "score"]:
		if not s[key] is Dictionary:
			return false
		for team in ["blue", "red"]:
			if not _integer(s[key].get(team), 0, 20):
				return false
	if not s.used is Array or s.used.size() > 5 or not s.trail is Array or s.trail.size() > 64:
		return false
	for id in s.used:
		if id not in ids:
			return false
	for step in s.trail:
		if not step is Dictionary or step.get("kind") not in ["run", "kick"] or not _integer(step.get("x"), 0, 9) or not _integer(step.get("y"), 0, 5):
			return false
	if s.formation != null:
		var formation = Rules.create_game()
		formation.pawns = s.formation
		if not valid_state(formation):
			return false
	return true

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not valid_state(data.get("state")):
		return false
	if data.get("opponent") not in ["", "red"] or not data.get("kits") is Dictionary:
		return false
	for team in ["blue", "red"]:
		var kit = data.kits.get(team)
		if not kit is Dictionary or not _integer(kit.get("index"), 0, 11) or not _integer(kit.get("design"), 0, 2):
			return false
	for key in ["history", "plan"]:
		if not data.get(key) is Array or data[key].size() > 64:
			return false
		for state in data[key]:
			if not valid_state(state):
				return false
	return data.get("relocation") is Dictionary and (data.relocation.is_empty() or valid_state(data.relocation))

static func read_match(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 2_000_000:
		return {"error": "The saved match could not be opened."}
	var data = file.get_var(false)
	if not valid(data):
		return {"error": "The saved match is damaged or from an unsupported version. You can start a new match."}
	return data

static func write_match(path: String, data: Dictionary) -> Error:
	if not valid(data):
		return ERR_INVALID_DATA
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(data, false)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return error
	# Replace only after a complete write; a failed save leaves the previous match intact.
	return DirAccess.rename_absolute(path + ".tmp", path)
