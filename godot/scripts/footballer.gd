extends RefCounted

# The visual rig faces +Z; the collision stays centered on the board square.
static func build(board: Node3D, p: Dictionary) -> StaticBody3D:
	var piece = StaticBody3D.new()
	piece.name = p.id
	piece.set_meta("pawn_id", p.id)
	board.add_child(piece)
	var rig = Node3D.new()
	rig.name = "Rig"
	piece.add_child(rig)
	rig.rotation.y = PI / 2 if p.team == "blue" else -PI / 2
	var index = int(p.id.right(1)) + (0 if p.team == "blue" else 2)
	var skin = Color(["c98255", "f1bd8e", "75442e", "e0a075", "a96843"][index % 5])
	var hair = Color(["251c22", "63361e", "201b22", "30212a", "dab46c"][index % 5])
	var team = Color("2789eb") if p.team == "blue" else Color("ee4964")
	var kit = (Color("ffc943") if p.team == "blue" else Color("38d5ba")) if p.keeper else team
	var cream = Color("fff4dc")
	var navy = Color("15263c")
	board._cylinder(piece, Vector3(0, 0.035, 0), 0.31, 0.06, team.darkened(0.25))
	for side in [-1, 1]:
		var x = side * 0.105
		board._rounded_box(rig, Vector3(x, 0.13, 0.045), Vector3(0.16, 0.12, 0.27), 0.045, cream if index % 2 else Color("d8ff3e"))
		board._rounded_box(rig, Vector3(x, 0.29, 0), Vector3(0.13, 0.25, 0.14), 0.05, cream)
		board._box(rig, Vector3(x, 0.33, 0.073), Vector3(0.125, 0.045, 0.01), kit)
		board._rounded_box(rig, Vector3(side * 0.245, 0.67, 0), Vector3(0.16, 0.22, 0.2), 0.07, kit)
		board._rounded_box(rig, Vector3(side * 0.275, 0.52, 0.025), Vector3(0.12, 0.2, 0.13), 0.055, skin)
		board._sphere(rig, Vector3(side * 0.275, 0.44, 0.045), 0.075, cream if p.keeper else skin)
	board._rounded_box(rig, Vector3(0, 0.43, 0), Vector3(0.35, 0.19, 0.25), 0.055, navy)
	board._rounded_box(rig, Vector3(0, 0.66, 0), Vector3(0.38, 0.34, 0.28), 0.075, kit)
	for x in [-0.09, 0.09]:
		board._box(rig, Vector3(x, 0.66, 0.142), Vector3(0.025, 0.24, 0.008), kit.lightened(0.3))
	board._cylinder(rig, Vector3(0, 0.83, 0), 0.095, 0.035, cream)
	board._sphere(rig, Vector3(-0.105, 0.73, 0.148), 0.025, cream)
	board._rounded_box(rig, Vector3(0, 1.055, 0), Vector3(0.46, 0.46, 0.42), 0.16, skin)
	for side in [-1, 1]:
		board._sphere(rig, Vector3(side * 0.233, 1.05, 0), 0.063, skin)
		var eye = board._sphere(rig, Vector3(side * 0.092, 1.085, 0.198), 0.048, cream)
		eye.scale = Vector3(0.85, 1.1, 0.42)
		var pupil = board._sphere(rig, Vector3(side * 0.09, 1.08, 0.217), 0.024, navy)
		pupil.scale.z = 0.35
		board._rounded_box(rig, Vector3(side * 0.092, 1.15, 0.197), Vector3(0.09, 0.026, 0.028), 0.012, hair)
	board._sphere(rig, Vector3(0, 1.025, 0.218), 0.044, skin.lightened(0.06))
	board._rounded_box(rig, Vector3(0, 0.96, 0.202), Vector3(0.095, 0.023, 0.018), 0.008, Color("794a40"))
	board._rounded_box(rig, Vector3(0, 1.23, -0.035), Vector3(0.47, 0.18, 0.4), 0.08, hair)
	if index % 3 == 0:
		for x in [-0.14, 0.0, 0.14]:
			board._sphere(rig, Vector3(x, 1.31, -0.015), 0.105, hair)
	elif index % 3 == 1:
		var fringe = board._rounded_box(rig, Vector3(0.06, 1.29, 0.1), Vector3(0.3, 0.17, 0.25), 0.075, hair)
		fringe.rotation.z = -0.18
	else:
		board._rounded_box(rig, Vector3(0, 1.32, -0.01), Vector3(0.12, 0.15, 0.36), 0.055, hair)
	var number = Label3D.new()
	number.text = "1" if p.keeper else p.id.right(1)
	number.font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	number.font_size = 48
	number.pixel_size = 0.0035
	number.position = Vector3(0, 0.65, -0.145)
	number.rotation.y = PI
	number.modulate = cream
	number.outline_size = 0
	rig.add_child(number)
	var label = Label3D.new()
	label.text = "K" if p.keeper else p.id.right(1)
	label.font = number.font
	label.font_size = 40
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = team.lightened(0.4)
	label.outline_modulate = Color("080f20")
	label.position.y = 1.61
	piece.add_child(label)
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.4
	collision.shape = shape
	collision.position.y = 0.7
	piece.add_child(collision)
	return piece
