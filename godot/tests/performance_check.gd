extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")
var stage = "warmup"
var samples = {}
var draws = {}
var game: Node3D
var previous_usec = 0

func _initialize() -> void:
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now = Time.get_ticks_usec()
	if previous_usec != 0:
		if not samples.has(stage):
			samples[stage] = []
			draws[stage] = []
		var milliseconds = (now - previous_usec) / 1000.0
		samples[stage].append(milliseconds)
		draws[stage].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if milliseconds > 35 and stage != "warmup":
			print("PROFILE slow_frame stage=", stage, " mode=", game.journey.mode, " ms=", milliseconds,
				" mesh_compilations=", Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
				" surface_compilations=", Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))
	previous_usec = now
	return false

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = MatchScene.instantiate()
	root.add_child(game)
	await create_timer(2).timeout
	stage = "home"
	await create_timer(2).timeout
	stage = "locker_travel"
	await game._open_setup("")
	stage = "locker"
	await create_timer(2).timeout
	stage = "entrance"
	await game._start_match(0, 1, "")
	stage = "dice"
	while game.state.phase == "ready":
		await game._roll_turn()
	stage = "gameplay"
	await create_timer(3).timeout
	for key in samples:
		var values = samples[key]
		values.sort()
		var counts = draws[key]
		counts.sort()
		print("PROFILE ", key, " frames=", values.size(), " median_ms=", snappedf(values[values.size() / 2], 0.01),
			" p95_ms=", snappedf(values[mini(values.size() - 1, int(values.size() * 0.95))], 0.01),
			" max_ms=", snappedf(values.back(), 0.01), " median_draws=", counts[counts.size() / 2])
	if DisplayServer.get_name() != "headless":
		assert(draws.gameplay[draws.gameplay.size() / 2] < 900, "Draw submissions must stay below the native rendering budget")
	assert(game.screen == "match" and game.state.phase == "kick")
	print("PASS: menu, locker room, entrance, dice and gameplay performance sampled; rendering budget checked.")
	quit()
