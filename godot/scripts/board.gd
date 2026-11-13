extends Node3D

signal entrance_finished
signal camera_changed
signal kicked

const Rules = preload("res://scripts/rules.gd")
const Footballer = preload("res://scripts/footballer.gd")
const Stadium = preload("res://scripts/stadium.gd")
const Kits = preload("res://scripts/team_kits.gd")
var team_kits = {"blue": Kits.make(0), "red": Kits.make(1)}
var reduced_motion = false
var entrance_motion: Tween
var keyboard_marker: MeshInstance3D
var selected_ring: MeshInstance3D
var selected_id = ""
var kicking: Dictionary = {}
var entering = false
var celebrating = false
const GOLD = Color("d8ff3e")
var camera: Camera3D
var camera_motion: Tween
var camera_target: Dictionary = {}
var pieces = {}
var ball: MeshInstance3D
var highlights: Node3D
var top_view = false
var portrait = false
var orbit_yaw = 0.0
var orbit_tilt = 0.0
var stadium: Node3D
var materials = {}
var rounded_meshes = {}
var primitive_meshes = {}
var player_motion = {}
var ball_motion: Tween
var ball_target = Vector3.INF
var ball_in_flight = false
var idle_time = 0.0
var eligible_players: Array[String] = []
var eligible_rings: Array[MeshInstance3D] = []

func _ready() -> void:
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("101c30")
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c0d5ef")
	world.environment.ambient_light_energy = 0.48
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.8
	sun.light_color = Color("ffe4bd")
	sun.directional_shadow_max_distance = 100
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 30
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = 250
	add_child(camera)
	camera.make_current()
	_make_pitch()
	batch_static(self)
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(self)
	var cursor_mesh = TorusMesh.new()
	cursor_mesh.inner_radius = 0.42
	cursor_mesh.outer_radius = 0.46
	keyboard_marker = _mesh(self, cursor_mesh, Vector3.ZERO, Color.WHITE)
	keyboard_marker.hide()
	highlights = Node3D.new()
	add_child(highlights)
	ball = _sphere(self, Vector3(0, 0.22, 0), 0.17, Color("fff4dc"))
	# Inlaid dark panels read as a football even at board scale.
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var panel = _sphere(ball, normal * 0.153, 0.072, Color("172638"))
		panel.scale = Vector3(1, 0.25, 1)
		panel.quaternion = Quaternion(Vector3.UP, normal)

func _material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.8
		materials[color] = material
	return materials[color]

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	parent.add_child(instance)
	instance.position = at
	var dimensions = mesh.get_aabb().size
	if minf(dimensions.x, minf(dimensions.y, dimensions.z)) < 0.04:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func batch_static(parent: Node3D) -> void:
	var groups = {}
	for child in parent.get_children():
		if child is MeshInstance3D:
			var key = str(child.material_override.get_instance_id()) + ":" + str(child.cast_shadow)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(child)
	for group in groups.values():
		if group.size() < 2:
			continue
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for instance in group:
			surface.append_from(instance.mesh, 0, instance.transform)
		var merged = MeshInstance3D.new()
		merged.mesh = surface.commit()
		merged.material_override = group[0].material_override
		merged.cast_shadow = group[0].cast_shadow
		parent.add_child(merged)
		for instance in group:
			instance.free()

func show_keyboard_cell(cell: Vector2i, shown: bool = true) -> void:
	keyboard_marker.position = cell_position(cell.x, cell.y, 0.12)
	keyboard_marker.visible = shown

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var key = "box:" + str(size)
	if not primitive_meshes.has(key):
		var mesh = BoxMesh.new()
		mesh.size = size
		primitive_meshes[key] = mesh
	return _mesh(parent, primitive_meshes[key], at, color)

func _rounded_box(parent: Node3D, at: Vector3, size: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var key = str(size) + ":" + str(radius)
	if not rounded_meshes.has(key):
		var cube = BoxMesh.new()
		cube.size = size
		cube.subdivide_width = 6
		cube.subdivide_height = 6
		cube.subdivide_depth = 6
		var arrays = cube.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var inner = size * 0.5 - Vector3.ONE * radius
		for i in vertices.size():
			var center = vertices[i].clamp(-inner, inner)
			normals[i] = (vertices[i] - center).normalized()
			vertices[i] = center + normals[i] * radius
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var rounded = ArrayMesh.new()
		rounded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		rounded_meshes[key] = rounded
	return _mesh(parent, rounded_meshes[key], at, color)

func _sphere(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var key = "sphere:" + str(radius)
	if not primitive_meshes.has(key):
		var mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2
		mesh.radial_segments = 20
		mesh.rings = 10
		primitive_meshes[key] = mesh
	return _mesh(parent, primitive_meshes[key], at, color)

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var key = "cylinder:" + str(radius) + ":" + str(height)
	if not primitive_meshes.has(key):
		var mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 20
		primitive_meshes[key] = mesh
	return _mesh(parent, primitive_meshes[key], at, color)

func _make_pitch() -> void:
	_box(self, Vector3(0, -0.25, 0), Vector3(11.9, 0.4, 7), Color("15253b"))
	_box(self, Vector3(0, -0.07, 0), Vector3(10.3, 0.08, 6.3), Color("2e674b"))
	for x in range(10):
		for y in range(6):
			var color = Color("397a51") if x % 2 == 0 else Color("43885b")
			_box(self, cell_position(x, y, 0), Vector3(0.99, 0.06, 0.99), color)
	var white = Color("e4edcf")
	for z in [-3.0, 3.0]:
		_box(self, Vector3(0, 0.043, z), Vector3(10.04, 0.015, 0.035), white)
	for x in [-5.0, 5.0]:
		_box(self, Vector3(x, 0.043, 0), Vector3(0.035, 0.015, 6), white)
	_cylinder(self, Vector3(0, 0.045, 0), 0.055, 0.014, white)
	_box(self, Vector3(0, 0.04, 0), Vector3(0.025, 0.015, 6), white)
	var ring = TorusMesh.new()
	ring.inner_radius = 0.97
	ring.outer_radius = 1.0
	_mesh(self, ring, Vector3(0, 0.045, 0), white)
	for end in [-1, 1]:
		var edge = end * 5.0
		_box(self, Vector3(edge - end, 0.045, -1), Vector3(2, 0.015, 0.025), white)
		_box(self, Vector3(edge - end, 0.045, 1), Vector3(2, 0.015, 0.025), white)
		_box(self, Vector3(edge - end * 2, 0.045, 0), Vector3(0.025, 0.015, 2), white)
		_box(self, Vector3(edge + end * 0.45, 0, 0), Vector3(0.9, 0.06, 2.05), Color("263c4c"))
		for z in [-1, 1]:
			_box(self, Vector3(edge, 0.45, z), Vector3(0.07, 0.9, 0.07), white)
			_box(self, Vector3(edge + end * 0.45, 0.88, z), Vector3(0.9, 0.045, 0.045), white)
		_box(self, Vector3(edge, 0.88, 0), Vector3(0.07, 0.07, 2.07), white)
		for z in [-1, 1]:
			for i in range(1, 4):
				_box(self, Vector3(edge + end * i * 0.22, 0.44, z), Vector3(0.012, 0.88, 0.012), Color("93aaa8"))
			for i in range(1, 5):
				_box(self, Vector3(edge + end * 0.44, i * 0.22, z), Vector3(0.88, 0.012, 0.012), Color("93aaa8"))
		for i in range(9):
			_box(self, Vector3(edge + end * 0.88, 0.44, -1 + i * 0.25), Vector3(0.018, 0.88, 0.018), Color("73898d"))
		for i in range(5):
			_box(self, Vector3(edge + end * 0.88, i * 0.22, 0), Vector3(0.018, 0.018, 2), Color("73898d"))

func _make_player(p: Dictionary) -> StaticBody3D:
	return Footballer.build(self, p, team_kits[p.team])

func set_kits(kits: Dictionary) -> void:
	team_kits = kits.duplicate(true)
	for motion in player_motion.values():
		motion.kill()
	player_motion.clear()
	for piece in pieces.values():
		piece.free()
	pieces.clear()

func _entrance_step(progress: float, piece: Node3D, start: Vector3, gate: Vector3, target: Vector3) -> void:
	piece.show()
	var split = start.distance_to(gate) / (start.distance_to(gate) + gate.distance_to(target))
	var direction: Vector3
	if progress < split:
		piece.position = start.lerp(gate, progress / split)
		direction = gate - start
	else:
		piece.position = gate.lerp(target, (progress - split) / (1.0 - split))
		direction = target - gate
	piece.get_node("Rig").rotation.y = atan2(direction.x, direction.z)
	Footballer.animate(piece, idle_time + float(abs(hash(piece.name)) % 100), true)

func enter_pitch(state: Dictionary, lead: String) -> void:
	entering = true
	var entrance = create_tween().set_parallel(true)
	entrance_motion = entrance
	if reduced_motion:
		entrance.set_speed_scale(1000.0)
	var order = 0
	for p in state.pawns:
		var piece: Node3D = pieces[p.id]
		var start = Vector3(6.8, 0.08, 2.2)
		var gate = Vector3(4.4, 0.08, 2.2)
		piece.get_node("Base").hide()
		for child in piece.get_children():
			if child is Label3D:
				child.hide()
		if p.id == lead:
			start = piece.position
			gate = start
		var target = cell_position(p.x, p.y)
		piece.position = start
		piece.visible = p.id == lead
		var delay = 0.0 if p.id == lead else 0.3 + order * 0.22
		entrance.tween_method(_entrance_step.bind(piece, start, gate, target), 0.0, 1.0, 2.8).set_delay(delay)
		order += 1
	await entrance.finished
	for p in state.pawns:
		var piece: Node3D = pieces[p.id]
		piece.position = cell_position(p.x, p.y)
		piece.get_node("Rig").position = Vector3.ZERO
		piece.get_node("Rig").rotation = Vector3(0, PI / 2 if p.team == "blue" else -PI / 2, 0)
		Footballer.animate(piece, 0)
	entering = false
	entrance_finished.emit()

func hide_match() -> void:
	for piece in pieces.values():
		piece.hide()
	ball.hide()
	highlights.hide()
	keyboard_marker.hide()

static func cell_position(x: float, y: float, height: float = 0.08) -> Vector3:
	return Vector3(x - 4.5, height, y - 2.5)

func _ball_position(state: Dictionary) -> Vector3:
	var at = cell_position(state.ball.x, state.ball.y, 0.24)
	var carrier = Rules.pawn_at(state, state.ball.x, state.ball.y)
	if not carrier.is_empty():
		var heading = PI / 2 if carrier.team == "blue" else -PI / 2
		if pieces.has(carrier.id):
			heading = pieces[carrier.id].get_node("Rig").rotation.y
		at += Vector3(sin(heading), 0, cos(heading)) * 0.32
	return at

func _process(delta: float) -> void:
	idle_time += delta
	for ring in eligible_rings:
		ring.scale = Vector3.ONE * (1.0 if reduced_motion else 1.0 + sin(idle_time * 4) * 0.06)
	if is_instance_valid(selected_ring) and pieces.has(selected_id):
		var piece = pieces[selected_id]
		selected_ring.position = piece.position + piece.get_node("Rig").position
		selected_ring.position.y = 0.1
	if entering or celebrating:
		return
	for id in pieces:
		var motion: Tween = player_motion.get(id)
		if (motion != null and motion.is_running()) or kicking.has(id):
			continue
		Footballer.animate(pieces[id], 0.0 if reduced_motion else idle_time + float(abs(hash(id)) % 100))

func _step_player(progress: float, piece: Node3D, offset: Vector3, heading: float, target_heading: float) -> void:
	var rig = piece.get_node("Rig")
	rig.position = Vector3.ZERO
	Footballer.animate(piece, idle_time + float(abs(hash(piece.name)) % 100), true)
	rig.position += offset * (1.0 - smoothstep(0.0, 1.0, progress))
	rig.rotation.y = lerp_angle(heading, target_heading, smoothstep(0.0, 0.6, progress))

func _move_player(piece: Node3D, target: Vector3) -> void:
	if piece.position.is_equal_approx(target):
		return
	var rig: Node3D = piece.get_node("Rig")
	var start = piece.position + rig.position
	var id = piece.get_meta("pawn_id")
	var motion: Tween = player_motion.get(id)
	if motion != null:
		motion.kill()
	var direction = target - piece.position
	var heading = rig.rotation.y
	var target_heading = atan2(direction.x, direction.z)
	piece.position = target
	if reduced_motion:
		rig.position = Vector3.ZERO
		rig.rotation.y = target_heading
		Footballer.animate(piece, 0)
		return
	rig.position = start - target
	motion = create_tween()
	player_motion[id] = motion
	motion.tween_method(_step_player.bind(piece, start - target, heading, target_heading), 0.0, 1.0, 0.24)

func _roll_ball(progress: float, start: Vector3, target: Vector3, initial_basis: Basis) -> void:
	var direction = target - start
	ball.position = start.lerp(target, progress) + Vector3.UP * sin(progress * PI) * 0.045
	var axis = Vector3.UP.cross(direction).normalized()
	if not axis.is_zero_approx():
		ball.basis = Basis(axis, direction.length() * progress / 0.17) * initial_basis

func _sync_ball(state: Dictionary) -> void:
	var target = _ball_position(state)
	if ball_in_flight or target.is_equal_approx(ball_target):
		return
	if ball_motion != null:
		ball_motion.kill()
	if ball_target == Vector3.INF or reduced_motion:
		ball.position = target
	else:
		ball_motion = create_tween()
		ball_motion.tween_method(_roll_ball.bind(ball.position, target, ball.basis), 0.0, 1.0, 0.24)
	ball_target = target

func _kick_pose(progress: float, piece: Node3D) -> void:
	var rig = piece.get_node("Rig")
	var swing = sin(progress * PI)
	rig.get_node("RightLeg").rotation.x = -swing * 0.95
	rig.rotation.x = -swing * 0.12

func play_kick(origin: Dictionary, plan: Array) -> void:
	assert(not plan.is_empty())
	ball_in_flight = true
	if ball_motion != null:
		ball_motion.kill()
	var previous = origin
	var last_kicker = ""
	for step in plan:
		if previous.selected != last_kicker and pieces.has(previous.selected):
			last_kicker = previous.selected
			var piece: Node3D = pieces[last_kicker]
			var rig: Node3D = piece.get_node("Rig")
			var direction = cell_position(step.ball.x, step.ball.y) - piece.position
			rig.rotation.y = atan2(direction.x, direction.z)
			kicking[last_kicker] = true
			if not reduced_motion:
				var contact = create_tween()
				contact.tween_property(ball, "position", _ball_position(previous), 0.08)
				contact.parallel().tween_method(_kick_pose.bind(piece), 0.0, 0.5, 0.08)
				await contact.finished
				var follow = create_tween()
				follow.tween_method(_kick_pose.bind(piece), 0.5, 1.0, 0.14)
				follow.tween_callback(func(): kicking.erase(piece.get_meta("pawn_id")))
			else:
				kicking.erase(last_kicker)
			kicked.emit()
		var target = _ball_position(step)
		ball_motion = create_tween()
		ball_motion.tween_method(_roll_ball.bind(ball.position, target, ball.basis), 0.0, 1.0, 0.001 if reduced_motion else maxf(0.12, ball.position.distance_to(target) * 0.16))
		await ball_motion.finished
		previous = step
	ball_target = _ball_position(plan.back())
	ball.position = ball_target
	ball_in_flight = false

func _route_line(start: Vector3, end: Vector3, width: float = 0.055) -> void:
	var direction = end - start
	if direction.length() < 0.001:
		return
	var line = _box(highlights, (start + end) * 0.5, Vector3(width, 0.02, direction.length()), GOLD)
	line.rotation.y = atan2(direction.x, direction.z)

func _draw_plan(state: Dictionary, plan: Array) -> void:
	var start = cell_position(state.ball.x, state.ball.y, 0.075)
	for i in plan.size():
		var step = plan[i]
		var end = cell_position(step.ball.x, step.ball.y, 0.075)
		var direction = (end - start).normalized()
		var side = Vector3.UP.cross(direction)
		_route_line(start, end)
		_route_line(end - direction * 0.3 + side * 0.11, end - direction * 0.16)
		_route_line(end - direction * 0.3 - side * 0.11, end - direction * 0.16)
		_cylinder(highlights, end + Vector3.UP * 0.015, 0.13, 0.025, Color("142c35"))
		var number = Label3D.new()
		number.text = str(i + 1)
		number.font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
		number.font_size = 40
		number.pixel_size = 0.005
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		number.no_depth_test = true
		number.modulate = GOLD
		number.position = end + Vector3.UP * 0.2
		highlights.add_child(number)
		start = end
	if not plan.is_empty():
		var ring = TorusMesh.new()
		ring.inner_radius = 0.22
		ring.outer_radius = 0.26
		_mesh(highlights, ring, start + Vector3.UP * 0.025, GOLD)

func update_state(state: Dictionary, preview: Dictionary = {}, plan: Array = []) -> void:
	ball.show()
	highlights.show()
	var shown = state if preview.is_empty() else preview
	for p in shown.pawns:
		var target = cell_position(p.x, p.y)
		if not pieces.has(p.id):
			pieces[p.id] = _make_player(p)
			pieces[p.id].position = target
		else:
			_move_player(pieces[p.id], target)
		pieces[p.id].show()
	_sync_ball(state)
	selected_ring = null
	selected_id = ""
	eligible_players.clear()
	eligible_rings.clear()
	for child in highlights.get_children():
		child.free()
	if shown.phase == "select" or (shown.phase == "run" and shown.remaining == shown.roll):
		for p in shown.pawns:
			var choice = Rules.select_pawn(shown, p.id)
			if not choice.has("error") and not Rules.legal_targets(choice).is_empty():
				eligible_players.append(p.id)
				var halo = TorusMesh.new()
				halo.inner_radius = 0.35
				halo.outer_radius = 0.4
				eligible_rings.append(_mesh(highlights, halo, cell_position(p.x, p.y, 0.105), Kits.accent(team_kits[p.team])))
	if not ball_in_flight and (plan.is_empty() or shown.phase in ["kick", "relocate"]):
		for target in Rules.legal_targets(shown):
			var at = cell_position(target.x, target.y, 0.06)
			for x in [-1, 1]:
				for z in [-1, 1]:
					_box(highlights, at + Vector3(x * 0.32, 0, z * 0.4), Vector3(0.2, 0.02, 0.035), GOLD)
					_box(highlights, at + Vector3(x * 0.4, 0, z * 0.32), Vector3(0.035, 0.02, 0.2), GOLD)
	_draw_plan(state, plan)
	var selected = Rules.pawn_by_id(shown, shown.get("relocating", shown.selected))
	if not selected.is_empty():
		var ring = TorusMesh.new()
		ring.inner_radius = 0.36
		ring.outer_radius = 0.41
		selected_ring = _mesh(highlights, ring, cell_position(selected.x, selected.y, 0.1), GOLD)
		selected_id = selected.id

func orbit(delta: Vector2, available: Rect2) -> void:
	var span = maxf(1.0, minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y))
	orbit_yaw = wrapf(orbit_yaw - delta.x * PI / span, -PI, PI)
	if not top_view:
		var base = _default_camera_position()
		var elevation = asin(base.normalized().y)
		orbit_tilt = clampf(elevation + orbit_tilt - delta.y * 2.0 / span, deg_to_rad(35), deg_to_rad(80)) - elevation
	fit(available, true)

func _default_camera_position() -> Vector3:
	var size = get_viewport().get_visible_rect().size
	return Vector3(13, 18, 0) if size.x < size.y else (Vector3(0, 13, 7) if size.y < 500 else Vector3(1.5, 12, 11))

func fit(available: Rect2, immediate: bool = false) -> void:
	var size = get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		return
	portrait = size.x < size.y
	var position = _default_camera_position()
	var elevation = clampf(asin(position.normalized().y) + orbit_tilt, deg_to_rad(35), deg_to_rad(80))
	var heading = atan2(position.x, position.z) + orbit_yaw
	position = Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation)) * position.length()
	var up = Vector3.UP
	if top_view:
		position = Vector3(0, 18, 0.001)
		up = Vector3.LEFT if portrait else Vector3.FORWARD
		position = position.rotated(Vector3.UP, orbit_yaw)
		up = up.rotated(Vector3.UP, orbit_yaw)
	var transform = Transform3D(Basis.looking_at(-position, up), position)
	var bounds = AABB()
	var first = true
	for x in [-5.8, 5.8]:
		for y in [0.0, 1.72]:
			for z in [-3.05, 3.05]:
				var point = transform.affine_inverse() * Vector3(x, y, z)
				if first:
					bounds.position = point
					first = false
				bounds = bounds.expand(point)
	var zoom = maxf(bounds.size.y * size.y / maxf(available.size.y, 80), bounds.size.x * size.y / maxf(available.size.x, 120)) * 1.04
	var center = bounds.get_center()
	# Dolly back to fit the pitch with the same perspective lens used by the entrance.
	var distance = zoom / (2.0 * tan(deg_to_rad(camera.fov) * 0.5)) + bounds.size.z * 0.5
	transform.origin = position.normalized() * distance
	var target = {"transform": transform, "size": zoom,
		"h": center.x + zoom * (size.x * 0.5 - available.get_center().x) / size.y,
		"v": center.y + zoom * (available.get_center().y - size.y * 0.5) / size.y}
	if target == camera_target:
		stadium.update_view(camera.position, top_view)
		return
	var first_fit = camera_target.is_empty()
	camera_target = target
	if camera_motion != null:
		camera_motion.kill()
	if immediate or first_fit or reduced_motion or not camera.is_current():
		_blend_camera(1.0, target, target)
		return
	var start = {"transform": camera.transform, "size": camera.size, "h": camera.h_offset, "v": camera.v_offset}
	camera_motion = create_tween()
	camera_motion.tween_method(_blend_camera.bind(start, target), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _blend_camera(progress: float, start: Dictionary, finish: Dictionary) -> void:
	camera.transform = start.transform.interpolate_with(finish.transform, progress)
	camera.size = lerpf(start.size, finish.size, progress)
	camera.h_offset = lerpf(start.h, finish.h, progress)
	camera.v_offset = lerpf(start.v, finish.v, progress)
	stadium.update_view(camera.position, top_view)
	camera_changed.emit()

func pick(screen_point: Vector2, preferred_targets: Array = [], path_targets: Array = []) -> Dictionary:
	var origin = camera.project_ray_origin(screen_point)
	var direction = camera.project_ray_normal(screen_point)
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 100)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	var point = Plane(Vector3.UP, 0.04).intersects_ray(origin, direction)
	var cell = {}
	if point != null:
		var x = floori(point.x + 5)
		var y = floori(point.z + 3)
		if x >= -1 and x <= 10 and y >= 0 and y < 6:
			cell = {"x": x, "y": y}
	# Route squares stay tappable even when a foreground player overlaps them.
	for target in path_targets:
		if not cell.is_empty() and Rules.same(target, cell):
			return cell
	if not hit.is_empty() and hit.collider.has_meta("pawn_id"):
		var pawn = {"pawn_id": hit.collider.get_meta("pawn_id")}
		# A valid receiver wins; an ineligible foreground player must not block a legal square.
		var at: Vector3 = hit.collider.position
		for target in preferred_targets:
			if target.x == floori(at.x + 5) and target.y == floori(at.z + 3):
				return pawn
		for target in preferred_targets:
			if not cell.is_empty() and Rules.same(target, cell):
				return cell
		return pawn
	return cell

func prepare_players(state: Dictionary) -> void:
	for p in state.pawns:
		if not pieces.has(p.id):
			pieces[p.id] = _make_player(p)
			pieces[p.id].position = cell_position(p.x, p.y)
			pieces[p.id].hide()
			await get_tree().process_frame
			while get_tree().paused:
				await get_tree().process_frame
