extends Node3D

signal completed

const UI = preload("res://scripts/ui_theme.gd")
const DURATION = 6.4
var game: Node3D
var camera: Camera3D
var overlay: Control
var strip: ColorRect
var banner: VBoxContainer
var title: Label
var score: Label
var skip: Button
var effects: Node3D
var active = false
var elapsed = 0.0
var fired = 0
var scorer: Node3D
var poses: Dictionary = {}
var labels: Dictionary = {}
var path: Array[Vector3] = []
var saved_ball: Transform3D
var entry_camera: Transform3D
var side = 1.0
var flank = 1.0
var team_color: Color

func _init(match_game: Node3D) -> void:
	game = match_game

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 100
	add_child(camera)
	effects = Node3D.new()
	add_child(effects)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.hud.add_child(overlay)
	strip = ColorRect.new()
	strip.color = Color(UI.INK, 0.94)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 100
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(strip)
	banner = VBoxContainer.new()
	banner.add_theme_constant_override("separation", 0)
	overlay.add_child(banner)
	title = game._label("GOAL!", 48, UI.ACCENT)
	title.add_theme_font_override("font", UI.DISPLAY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(title)
	score = game._label("", 20)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(score)
	skip = game._button("Skip celebration", finish)
	skip.tooltip_text = "Return to the match (Escape)"
	overlay.add_child(skip)
	overlay.resized.connect(_layout)
	overlay.hide()

func _layout() -> void:
	var size = overlay.size
	var safe = Rect2(Vector2.ZERO, size)
	if OS.has_feature("ios") or OS.has_feature("android"):
		var pixels = DisplayServer.get_display_safe_area()
		var ratio = size / Vector2(get_window().size)
		safe = Rect2(Vector2(pixels.position) * ratio, Vector2(pixels.size) * ratio)
	banner.position = safe.position + Vector2(16, 8)
	banner.size = Vector2(safe.size.x - 32, 0)
	strip.offset_bottom = safe.position.y + 100
	skip.size = skip.get_combined_minimum_size()
	skip.position = safe.end - skip.size - Vector2(16, 16)
	camera.fov = 65 if size.x < size.y else 52

func play(origin: Dictionary, plan: Array) -> void:
	assert(not active and not plan.is_empty() and plan.back().phase == "goal")
	var previous = origin if plan.size() == 1 else plan[-2]
	var scorer_id: String = previous.selected
	scorer = game.board.pieces[scorer_id]
	var first = plan.size() - 1
	while first > 0 and (origin if first == 1 else plan[first - 2]).selected == scorer_id:
		first -= 1
	previous = origin if first == 0 else plan[first - 1]
	path = [game.board._ball_position(previous)]
	for step in plan.slice(first):
		path.append(game.board._ball_position(step))
	side = 1.0 if origin.team == "blue" else -1.0
	flank = 1.0 if path.back().z >= 0 else -1.0
	team_color = game.team_kits[origin.team].color
	saved_ball = game.board.ball.transform
	entry_camera = game.get_viewport().get_camera_3d().global_transform
	poses.clear()
	labels.clear()
	for piece in game.board.pieces.values():
		for child in piece.get_children():
			if child is Label3D:
				labels[child] = child.visible
				child.hide()
	for pawn in origin.pawns:
		if pawn.team == origin.team:
			var rig = game.board.pieces[pawn.id].get_node("Rig")
			for node in [rig, rig.get_node("LeftArm"), rig.get_node("RightArm"), rig.get_node("RightLeg")]:
				poses[node] = node.transform
	game.board.celebrating = true
	game.board.highlights.hide()
	game.header.hide()
	game.dock.hide()
	game.primary.hide()
	elapsed = 0.0
	fired = 0
	active = true
	score.text = game._score_text()
	overlay.show()
	_layout()
	_frame()
	camera.make_current()
	skip.grab_focus()
	await completed

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	if elapsed >= DURATION:
		finish()
	else:
		_frame()

func _frame() -> void:
	var replay = clampf((elapsed - 1.15) / 2.0, 0.0, 1.0)
	var goal = path.back()
	var focus = scorer.position.lerp(goal, replay * 0.65) + Vector3.UP * 0.65
	var at = focus + Vector3(-side * 3.1, 1.35, flank * 3.1)
	title.text = "GOAL REPLAY" if elapsed >= 0.85 and elapsed < 3.15 else "GOAL!"
	if elapsed >= 0.85:
		var index = replay * (path.size() - 1)
		var segment = mini(int(index), path.size() - 2)
		game.board._roll_ball(index - segment, path[segment], path[segment + 1], saved_ball.basis)
		var rig = scorer.get_node("Rig")
		var direction = path[1] - path[0]
		rig.rotation.y = atan2(direction.x, direction.z)
		var swing = clampf((elapsed - 0.85) / 0.55, 0.0, 1.0)
		rig.get_node("RightLeg").rotation.x = sin(swing * TAU) * 0.95
		rig.rotation.x = -sin(swing * PI) * 0.14
	if elapsed >= 3.15:
		var sweep = clampf((elapsed - 3.15) / 2.5, 0.0, 1.0)
		var finish_focus = scorer.position.lerp(goal, 0.55) + Vector3.UP * 0.75
		focus = focus.lerp(finish_focus, smoothstep(0.0, 0.7, elapsed - 3.15))
		at = focus + Vector3(-side * lerpf(3.1, 4.0, sweep), lerpf(1.35, 2.5, sweep), flank * lerpf(3.1, 4.3, sweep))
		for node in poses:
			if node.name == "LeftArm" or node.name == "RightArm":
				node.rotation.z = (-1 if node.name == "LeftArm" else 1) * (2.35 + sin(elapsed * 7) * 0.12) * smoothstep(3.15, 3.5, elapsed)
		while fired < 4 and elapsed >= 3.15 + fired * 0.4:
			_burst(goal + Vector3(-side * 0.2, 1.7 + (fired % 2) * 0.7, -1.4 if fired % 2 == 0 else 1.4), team_color if fired % 2 == 0 else UI.ACCENT)
			fired += 1
	if overlay.size.x < overlay.size.y:
		at = focus + (at - focus) * 1.3
	var pose = Transform3D(Basis.IDENTITY, at).looking_at(focus)
	camera.fov = 65 if overlay.size.x < overlay.size.y else 52
	if elapsed < 0.85:
		pose = entry_camera.interpolate_with(pose, smoothstep(0.0, 0.85, elapsed))
		camera.fov = lerpf(game.board.camera.fov, camera.fov, smoothstep(0.0, 0.85, elapsed))
	elif elapsed > 5.65:
		pose = pose.interpolate_with(game.board.camera.global_transform, smoothstep(5.65, DURATION, elapsed))
		camera.fov = lerpf(camera.fov, game.board.camera.fov, smoothstep(5.65, DURATION, elapsed))
	camera.global_transform = pose
	game.board.stadium.update_view(at, false)

func _burst(at: Vector3, color: Color) -> void:
	var sparks = CPUParticles3D.new()
	sparks.emitting = false
	sparks.amount = 90
	sparks.lifetime = 1.8
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180
	sparks.gravity = Vector3(0, -0.8, 0)
	sparks.initial_velocity_min = 1.8
	sparks.initial_velocity_max = 2.5
	sparks.particle_flag_align_y = true
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.025, 0.16, 0.025)
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	sparks.mesh = mesh
	var fade = Gradient.new()
	fade.colors = PackedColorArray([color.lightened(0.5), color, Color(color, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	sparks.color_ramp = fade
	effects.add_child(sparks)
	sparks.position = at
	sparks.emitting = true

func _unhandled_key_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()

func finish() -> void:
	if not active:
		return
	active = false
	for node in poses:
		node.transform = poses[node]
	poses.clear()
	for label in labels:
		label.visible = labels[label]
	labels.clear()
	game.board.ball.transform = saved_ball
	game.board.celebrating = false
	game.board.highlights.show()
	game.board.camera.make_current()
	game.board.stadium.update_view(game.board.camera.position, game.board.top_view)
	for child in effects.get_children():
		child.free()
	overlay.hide()
	completed.emit()
