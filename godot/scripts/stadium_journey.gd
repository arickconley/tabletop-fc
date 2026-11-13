class_name StadiumJourney
extends Node3D

const Footballer = preload("res://scripts/footballer.gd")
const Kits = preload("res://scripts/team_kits.gd")
var board: Node3D
var camera: Camera3D
var camera_motion: Tween
var camera_destination: Dictionary = {}
var room: Node3D
var room_geometry: Array[GeometryInstance3D] = []
var hero: Node3D
var groundskeeper: Node3D
var skip_requested = false
var walk_motion: Tween
var crane_motion: Tween
var mode = "home"
var elapsed = 0.0
var destination = Vector3.ZERO
var random = RandomNumberGenerator.new()

func setup(pitch: Node3D) -> void:
	board = pitch
	$EditorPreview.free()
	random.randomize()
	camera = Camera3D.new()
	camera.name = "ActiveCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.05
	camera.far = 250
	add_child(camera)
	room = $LockerRoomAndTunnel
	for geometry in room.find_children("*", "GeometryInstance3D", true, false):
		room_geometry.append(geometry)
	_build_groundskeeper()
	dress(Kits.make(0))
	home()

func _off_field_piece(id: String, kit: Dictionary) -> Node3D:
	var piece = Footballer.build(board, {"id": id, "team": "blue", "keeper": false}, kit)
	piece.reparent(self, false)
	piece.collision_layer = 0
	piece.collision_mask = 0
	piece.get_node("Base").hide()
	for child in piece.get_children():
		if child is Label3D:
			child.hide()
	return piece

func _build_groundskeeper() -> void:
	groundskeeper = _off_field_piece("groundskeeper-0", {"name": "Grounds", "color": Color("697e61"), "design": 0})
	groundskeeper.position = Vector3(-2.5, 0.08, 0.8)
	var rig = groundskeeper.get_node("Rig")
	board._cylinder(rig, Vector3(0, 1.36, 0), 0.26, 0.08, Color("274333"))
	board._box(rig, Vector3(0, 1.32, 0.2), Vector3(0.43, 0.035, 0.25), Color("274333"))
	var mower = Node3D.new()
	mower.name = "Mower"
	rig.add_child(mower)
	mower.position = Vector3(0, 0, 0.8)
	board._rounded_box(mower, Vector3(0, 0.14, 0), Vector3(0.62, 0.2, 0.6), 0.07, Color("305c43"))
	board._box(mower, Vector3(0, 0.28, -0.05), Vector3(0.3, 0.15, 0.25), Color("17231f"))
	for x in [-0.32, 0.32]:
		for z in [-0.2, 0.2]:
			var wheel = board._cylinder(mower, Vector3(x, 0.1, z), 0.11, 0.07, Color("192323"))
			wheel.rotation.z = PI / 2
		var handle = board._box(mower, Vector3(x * 0.7, 0.4, -0.35), Vector3(0.025, 0.65, 0.025), Color("9ca8a1"))
		handle.rotation.x = -0.55
	var grip = board._box(mower, Vector3(0, 0.65, -0.5), Vector3(0.45, 0.025, 0.025), Color("9ca8a1"))
	grip.name = "Grip"
	for side in [-1, 1]:
		var arm: Node3D = rig.get_node("LeftArm" if side == -1 else "RightArm")
		var hand: Node3D = arm.get_child(2)
		hand.name = "Hand"
		var reach = mower.position + grip.position + Vector3(side * 0.224, 0, 0) - arm.position
		arm.basis = Basis(Quaternion(hand.position.normalized(), reach.normalized())).scaled(Vector3.ONE * reach.length() / hand.position.length())
		arm.set_meta("push_basis", arm.basis)
	_next_destination()

func _next_destination() -> void:
	destination = Vector3(random.randf_range(-3.7, 3.7), 0.08, random.randf_range(-1.6, 1.6))

func dress(kit: Dictionary) -> void:
	if is_instance_valid(hero) and hero.get_parent() == self:
		hero.free()
	hero = _off_field_piece("blue-1", kit)
	hero.position = to_local($Blocking/CaptainStart.global_position)
	hero.get_node("Rig").rotation.y = -0.15
	hero.visible = mode != "home"

func _process(delta: float) -> void:
	if board == null:
		return
	elapsed += 0.0 if board.reduced_motion else delta
	# Cut away foreground architecture as the camera rises, keeping every square visible.
	var cutaway = clampf((camera.position.y - 4.0) / 3.0, 0.0, 1.0)
	room.visible = cutaway < 1.0
	if room.visible:
		for geometry in room_geometry:
			geometry.transparency = cutaway
	if mode == "home" and not board.reduced_motion:
		var direction = destination - groundskeeper.position
		if direction.length() < 0.12:
			_next_destination()
		else:
			groundskeeper.position = groundskeeper.position.move_toward(destination, delta * 0.65)
			groundskeeper.get_node("Rig").rotation.y = lerp_angle(groundskeeper.get_node("Rig").rotation.y, atan2(direction.x, direction.z), minf(1, delta * 3))
			Footballer.animate(groundskeeper, 0.0 if board.reduced_motion else elapsed * 0.45, not board.reduced_motion)
			# Keep both hands on the handle after the shared walk cycle animates the limbs.
			for name in ["LeftArm", "RightArm"]:
				var arm = groundskeeper.get_node("Rig/" + name)
				arm.basis = arm.get_meta("push_basis")
	elif mode == "locker" and is_instance_valid(hero):
		Footballer.animate(hero, 0.0 if board.reduced_motion else elapsed)
		hero.get_node("Rig").rotation.y = -0.15 + (0.0 if board.reduced_motion else sin(elapsed * 0.6) * 0.12)

func _home_pose() -> Dictionary:
	return $Shots/HomePortrait.pose() if get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x else $Shots/HomeLandscape.pose()

func _room_pose() -> Dictionary:
	return $Shots/LockerPortrait.pose() if get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x else $Shots/LockerLandscape.pose()

func _set_pose(pose: Dictionary) -> void:
	camera.global_transform = pose.transform
	camera.size = pose.size
	camera.fov = pose.fov
	camera.h_offset = pose.h
	camera.v_offset = pose.v

func _blend(progress: float, start: Dictionary, finish: Dictionary) -> void:
	camera.global_transform = start.transform.interpolate_with(finish.transform, progress)
	camera.size = lerpf(start.size, finish.size, progress)
	camera.fov = lerpf(start.fov, finish.fov, progress)
	camera.h_offset = lerpf(start.h, finish.h, progress)
	camera.v_offset = lerpf(start.v, finish.v, progress)

func _travel(pose: Dictionary, duration: float) -> void:
	var start = {"transform": camera.global_transform, "size": camera.size, "fov": camera.fov, "h": camera.h_offset, "v": camera.v_offset}
	if camera_motion != null:
		camera_motion.kill()
	camera_destination = pose
	camera_motion = create_tween()
	if skip_requested or board.reduced_motion:
		camera_motion.set_speed_scale(1000.0)
	camera_motion.tween_method(_blend.bind(start, pose), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await camera_motion.finished

func resize_view() -> void:
	if mode not in ["home", "locker"]:
		return
	var pose = _home_pose() if mode == "home" else _room_pose()
	if pose == camera_destination:
		return
	if camera_destination.is_empty():
		_set_pose(pose)
		camera_destination = pose
	else:
		_travel(pose, 0.45)

func home() -> void:
	mode = "home"
	hero.hide()
	groundskeeper.show()
	camera.make_current()
	resize_view()

func to_locker() -> void:
	skip_requested = false
	if mode == "game":
		_set_pose({"transform": board.camera.global_transform, "size": board.camera.size, "fov": board.camera.fov, "h": board.camera.h_offset, "v": board.camera.v_offset})
	mode = "travel"
	groundskeeper.hide()
	hero.show()
	camera.make_current()
	# Approach the open front before descending under the roof.
	await _travel($Shots/RoomApproach.pose(), 1.15)
	await _travel(_room_pose(), 1.1)
	mode = "locker"
	resize_view()

func to_home() -> void:
	skip_requested = false
	if mode == "game":
		_set_pose({"transform": board.camera.global_transform, "size": board.camera.size, "fov": board.camera.fov, "h": board.camera.h_offset, "v": board.camera.v_offset})
		camera.make_current()
		mode = "travel"
		await _travel(_home_pose(), 1.3)
		home()
		return
	mode = "travel"
	await _travel($Shots/RoomApproach.pose(), 0.8)
	await _travel(_home_pose(), 1.1)
	home()

func _follow_pose() -> Dictionary:
	var pose = $Shots/Shoulder.pose()
	var origin = hero.global_position
	pose.transform.origin += origin - $Shots/Shoulder.global_position
	pose.transform.origin.z += 0.5
	pose.transform.origin.y += 0.12
	pose.transform = pose.transform.looking_at(origin + Vector3(-2.2, 0.8, 0.0))
	return pose

func _walk(progress: float, start: Vector3, finish: Vector3) -> void:
	hero.position = start.lerp(finish, progress)
	var direction = finish - start
	hero.get_node("Rig").rotation.y = atan2(direction.x, direction.z)
	Footballer.animate(hero, elapsed, true)
	_set_pose(_follow_pose())

func _crane(progress: float, finish: Dictionary) -> void:
	# Track a visible subject throughout the rise instead of blending two unrelated aim directions.
	var start = _follow_pose()
	var target = hero.global_position.lerp(Vector3(0, 0.5, 0), progress)
	_blend(progress, start, finish)
	var tracking = camera.global_transform.looking_at(target + Vector3.UP * 0.55)
	camera.global_transform = tracking.interpolate_with(finish.transform, smoothstep(0.65, 1.0, progress))

func walk_out(state: Dictionary) -> void:
	skip_requested = skip_requested or board.reduced_motion
	mode = "travel"
	groundskeeper.hide()
	hero.show()
	board.entering = true
	# The customized dressing-room player becomes the actual blue-1 match piece.
	board.pieces["blue-1"].free()
	hero.reparent(board, true)
	board.pieces["blue-1"] = hero
	await _travel(_follow_pose(), 0.65)
	mode = "tunnel"
	for point in [board.to_local($Blocking/Door.global_position), board.to_local($Blocking/PitchEntry.global_position)]:
		var tween = create_tween()
		walk_motion = tween
		if skip_requested or board.reduced_motion:
			tween.set_speed_scale(1000.0)
		tween.tween_method(_walk.bind(hero.position, point), 0.0, 1.0, hero.position.distance_to(point) / 1.8)
		await tween.finished
	mode = "crane"
	board.enter_pitch(state, "blue-1")
	if skip_requested:
		board.entrance_motion.set_speed_scale(1000.0)
	var final = {"transform": board.camera.global_transform, "size": board.camera.size, "fov": board.camera.fov, "h": board.camera.h_offset, "v": board.camera.v_offset}
	var crane = create_tween()
	crane_motion = crane
	if skip_requested or board.reduced_motion:
		crane.set_speed_scale(1000.0)
	crane.tween_method(_crane.bind(final), 0.0, 1.0, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await crane.finished
	if board.entering:
		await board.entrance_finished
	# Refit after rotation/resizing during the shot before handing the camera back.
	final = {"transform": board.camera.global_transform, "size": board.camera.size, "fov": board.camera.fov, "h": board.camera.h_offset, "v": board.camera.v_offset}
	await _travel(final, 0.25)
	for piece in board.pieces.values():
		piece.collision_layer = 1
		piece.get_node("Base").show()
		for child in piece.get_children():
			if child is Label3D:
				child.show()
	board.ball.show()
	mode = "game"
	board.camera.make_current()

func skip_entrance() -> void:
	skip_requested = true
	for tween in [camera_motion, walk_motion, crane_motion, board.entrance_motion]:
		if tween != null and tween.is_valid():
			tween.set_speed_scale(1000.0)
