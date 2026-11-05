extends SceneTree

const MatchScene = preload("res://scenes/match.tscn")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = MatchScene.instantiate()
	root.add_child(game)
	await process_frame
	var keeper = game.journey.groundskeeper
	var grip = keeper.get_node("Rig/Mower/Grip")
	var start = keeper.position
	var leg = keeper.get_node("Rig/LeftLeg")
	var first_leg_angle = leg.rotation.x
	var leg_moved = false
	for frame in range(12):
		if frame == 6:
			game.journey.destination = keeper.position + Vector3(1, 0, -1)
		await create_timer(0.06).timeout
		leg_moved = leg_moved or absf(leg.rotation.x - first_leg_angle) > 0.05
		for side in [-1, 1]:
			var hand = keeper.get_node("Rig/" + ("LeftArm" if side == -1 else "RightArm") + "/Hand")
			var target = grip.to_global(Vector3(side * 0.224, 0, 0))
			assert(hand.global_position.distance_to(target) < 0.001, "Hands must stay on the mower while walking and turning")
	assert(leg_moved and keeper.position.distance_to(start) > 0.1, "Pinning the arms must preserve walking")
	print("PASS: both hands remain attached to the mower handle while the groundskeeper walks and turns.")
	quit()
