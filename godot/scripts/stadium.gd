extends Node3D

var stands: Array[Node3D] = []
var towers: Array[Node3D] = []

func build(board: Node3D) -> void:
	name = "Stadium"
	var concrete = Color("26384b")
	var silver = Color("94a9b7")
	board._rounded_box(self, Vector3(0, -0.53, 0), Vector3(15.8, 0.65, 11.2), 0.25, Color("101e30"))
	board._rounded_box(self, Vector3(0, -0.22, 0), Vector3(15.5, 0.12, 10.9), 0.05, concrete)
	board._box(self, Vector3(0, -0.44, 5.58), Vector3(13.8, 0.045, 0.015), Color("55c6df"))
	for side in [-1, 1]:
		var stand = Node3D.new()
		add_child(stand)
		stand.position = Vector3(0, 0, side * 3.65)
		stand.rotation.y = 0 if side == 1 else PI
		stands.append(stand)
		for tier in range(3):
			var z = 0.4 + tier * 0.5
			var y = 0.05 + tier * 0.32
			board._box(stand, Vector3(0, y - 0.16, z), Vector3(11.8, 0.28 + tier * 0.05, 0.48), concrete.lightened(tier * 0.035))
			board._box(stand, Vector3(0, y, z - 0.24), Vector3(11.8, 0.035, 0.035), silver)
			for aisle in [-3, 3]:
				board._box(stand, Vector3(aisle, y + 0.03, z), Vector3(0.45, 0.06, 0.46), Color("b3b99c"))
		_make_crowd(stand, side)
		board._box(stand, Vector3(0, 1.1, 1.65), Vector3(12.1, 0.07, 0.07), silver)
		for x in [-6, -4, -2, 0, 2, 4, 6]:
			board._box(stand, Vector3(x, 0.5, 1.65), Vector3(0.045, 1.2, 0.045), silver)
		# Low advertising boards keep the touch surface unobstructed.
		for x in [-3.9, 0.0, 3.9]:
			board._rounded_box(self, Vector3(x, 0.17, side * 3.3), Vector3(3.65, 0.28, 0.1), 0.025, Color("15253b"))
			var label = Label3D.new()
			label.text = "TABLETOP FC" if x == 0 else "THE BEAUTIFUL GAME"
			label.font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
			label.font_size = 48
			label.pixel_size = 0.004
			label.outline_size = 0
			label.modulate = Color("d8ff3e") if x == 0 else Color("a8c5d2")
			label.position = Vector3(x, 0.17, side * 3.238)
			label.rotation.y = PI if side == 1 else 0
			add_child(label)
	for x in [-6.7, 6.7]:
		for z in [-4.6, 4.6]:
			var tower = Node3D.new()
			add_child(tower)
			tower.position = Vector3(x, 0, z)
			tower.look_at(Vector3(0, 0, 0))
			towers.append(tower)
			board._rounded_box(tower, Vector3(0, 0.05, 0), Vector3(0.4, 0.3, 0.4), 0.06, concrete)
			board._cylinder(tower, Vector3(0, 1.75, 0), 0.065, 3.5, silver)
			board._box(tower, Vector3(0, 3.45, 0), Vector3(1.2, 0.57, 0.18), Color("18283c"))
			for col in range(4):
				for row in range(2):
					var lamp = board._box(tower, Vector3((col - 1.5) * 0.27, 3.31 + row * 0.26, -0.105), Vector3(0.22, 0.19, 0.025), Color("e2f5ff"))
					var glow = StandardMaterial3D.new()
					glow.albedo_color = Color("e2f5ff")
					glow.emission_enabled = true
					glow.emission = Color("b6deff")
					glow.emission_energy_multiplier = 2.0
					lamp.material_override = glow
			var light = SpotLight3D.new()
			add_child(light)
			light.position = Vector3(x, 3.5, z)
			light.look_at(Vector3(x * 0.3, 0, z * 0.25))
			light.light_color = Color("c8e8ff")
			light.light_energy = 0.45
			light.spot_range = 13
			light.spot_angle = 58
	for x in [-4.94, 4.94]:
		for z in [-2.94, 2.94]:
			board._cylinder(self, Vector3(x, 0.32, z), 0.018, 0.58, Color("fff4dc"))
			board._box(self, Vector3(x + 0.09, 0.55, z), Vector3(0.18, 0.13, 0.018), Color("d8ff3e"))

func _make_crowd(parent: Node3D, side: int) -> void:
	var seats: Array[Transform3D] = []
	var bodies: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var colors: Array[Color] = []
	var skins: Array[Color] = []
	for tier in range(3):
		for column in range(27):
			var x = (column - 13) * 0.42
			if absf(absf(x) - 3.0) < 0.33:
				continue
			var y = 0.16 + tier * 0.32
			var z = 0.4 + tier * 0.5
			seats.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
			if (column + tier * 3) % 7 == 0:
				continue
			bodies.append(Transform3D(Basis.IDENTITY, Vector3(x, y + 0.17, z)))
			heads.append(Transform3D(Basis.IDENTITY, Vector3(x, y + 0.39, z - 0.015)))
			colors.append(Color(["3e98d4", "e75f70", "d9bb6a", "e2e7dd", "334a65"][(column + tier + (1 if side == 1 else 0)) % 5]))
			skins.append(Color(["c98255", "f1bd8e", "75442e", "e0a075"][(column + tier) % 4]))
	var seat = BoxMesh.new()
	seat.size = Vector3(0.32, 0.12, 0.32)
	_batch(parent, seat, seats, [], Color("2f7096") if side == -1 else Color("9c485b"))
	var body = CapsuleMesh.new()
	body.radius = 0.11
	body.height = 0.3
	body.radial_segments = 8
	body.rings = 2
	_batch(parent, body, bodies, colors, Color.WHITE)
	var head = SphereMesh.new()
	head.radius = 0.095
	head.height = 0.19
	head.radial_segments = 8
	head.rings = 4
	_batch(parent, head, heads, skins, Color.WHITE)

func _batch(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], tint: Color) -> void:
	assert(colors.is_empty() or colors.size() == transforms.size())
	var batch = MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		batch.multimesh.set_instance_transform(i, transforms[i])
		batch.multimesh.set_instance_color(i, tint if colors.is_empty() else colors[i])
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	batch.material_override = material
	parent.add_child(batch)

func update_view(camera_position: Vector3, overhead: bool) -> void:
	var direction = Vector3(camera_position.x, 0, camera_position.z).normalized()
	# Hide foreground seating and towers, never shrink the pitch to fit scenery.
	for stand in stands:
		stand.visible = overhead or direction.dot(stand.position.normalized()) < 0.5
	for tower in towers:
		tower.visible = overhead or direction.dot(tower.position.normalized()) < 0.4
