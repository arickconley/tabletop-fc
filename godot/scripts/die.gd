class_name MatchDie
extends Button

const NORMALS = {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.FORWARD, 5: Vector3.BACK, 3: Vector3.RIGHT, 4: Vector3.LEFT}
static var cube_mesh: ArrayMesh
static var pip_mesh: SphereMesh
var viewport: SubViewport
var rig: Node3D
var body_material: StandardMaterial3D
var rolling = false
var face = 1:
	set(value):
		face = clampi(value, 1, 6)
		if rig != null:
			rig.basis = resting_basis(face)
			_refresh()
var tint = Color("fff4dc"):
	set(value):
		tint = value
		if body_material != null:
			body_material.albedo_color = tint
			_refresh()

static func resting_basis(value: int) -> Basis:
	return Basis.from_euler(Vector3(0.35, -0.4, 0.04)) * Basis(Quaternion(NORMALS[value], Vector3.BACK))

static func pip_positions(value: int) -> Array[Vector2]:
	var pips: Array[Vector2] = []
	if value % 2 == 1:
		pips.append(Vector2.ZERO)
	if value >= 2:
		pips.append_array([Vector2(-0.24, -0.24), Vector2(0.24, 0.24)])
	if value >= 4:
		pips.append_array([Vector2(-0.24, 0.24), Vector2(0.24, -0.24)])
	if value == 6:
		pips.append_array([Vector2(-0.24, 0), Vector2(0.24, 0)])
	return pips

static func _rounded_cube() -> ArrayMesh:
	if cube_mesh != null:
		return cube_mesh
	var box = BoxMesh.new()
	box.size = Vector3.ONE
	box.subdivide_width = 8
	box.subdivide_height = 8
	box.subdivide_depth = 8
	var arrays = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		var center = vertices[i].clamp(Vector3.ONE * -0.38, Vector3.ONE * 0.38)
		normals[i] = (vertices[i] - center).normalized()
		vertices[i] = center + normals[i] * 0.12
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	cube_mesh = ArrayMesh.new()
	cube_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return cube_mesh

func _ready() -> void:
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		event.connect(queue_redraw)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(256, 256)
	add_child(viewport)
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0, 0, 0, 0)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c4d7ed")
	world.environment.ambient_light_energy = 0.42
	viewport.add_child(world)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9
	camera.position = Vector3(0, 0.02, 4)
	viewport.add_child(camera)
	camera.make_current()
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -35, -20)
	light.light_energy = 1.4
	viewport.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 110, 0)
	fill.light_color = Color("adcfff")
	fill.light_energy = 0.45
	viewport.add_child(fill)
	rig = Node3D.new()
	viewport.add_child(rig)
	var body = MeshInstance3D.new()
	body.mesh = _rounded_cube()
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = tint
	body_material.roughness = 0.28
	body.material_override = body_material
	rig.add_child(body)
	if pip_mesh == null:
		pip_mesh = SphereMesh.new()
		pip_mesh.radius = 0.072
		pip_mesh.height = 0.012
		pip_mesh.radial_segments = 16
		pip_mesh.rings = 6
	var ink = StandardMaterial3D.new()
	ink.albedo_color = Color("102035")
	ink.roughness = 0.55
	for value in NORMALS:
		var side = Node3D.new()
		side.name = "Face%d" % value
		side.basis = Basis(Quaternion(Vector3.UP, NORMALS[value]))
		rig.add_child(side)
		for pip in pip_positions(value):
			var dot = MeshInstance3D.new()
			dot.mesh = pip_mesh
			dot.material_override = ink
			dot.position = Vector3(pip.x, 0.501, pip.y)
			side.add_child(dot)
	var display = TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(display)
	rig.basis = resting_basis(face)
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	var pixels = clampi(ceili(maxf(size.x, size.y) * 2), 96, 512)
	viewport.size = Vector2i(pixels, pixels)
	_refresh()
	queue_redraw()

func _refresh() -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if rolling else SubViewport.UPDATE_ONCE

func _draw() -> void:
	if not disabled and has_focus():
		draw_line(Vector2(size.x * 0.28, size.y * 0.94), Vector2(size.x * 0.72, size.y * 0.94), Color("d8ff3e"), 2, true)

func roll_to(value: int) -> void:
	var start = rig.rotation
	face = value
	var end = resting_basis(face).get_euler() + Vector3(TAU * 2, TAU * 3, TAU)
	rig.rotation = start
	rolling = true
	_refresh()
	var motion = create_tween()
	motion.tween_method(func(progress: float):
		rig.rotation = start.lerp(end, progress)
		rig.position.y = sin(progress * PI) * 0.23
	, 0.0, 1.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await motion.finished
	rig.position = Vector3.ZERO
	rig.basis = resting_basis(face)
	rolling = false
	_refresh()
