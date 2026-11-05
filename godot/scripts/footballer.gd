extends RefCounted

# The visual rig faces +Z; the collision stays centered on the board square.
static func build(board: Node3D, p: Dictionary, appearance: Dictionary) -> StaticBody3D:
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
	var team: Color = appearance.color
	var kit = team.darkened(0.45) if p.keeper else team
	piece.set_meta("kit", appearance.duplicate())
	var cream = Color("fff4dc")
	var navy = Color("15263c")
	board._cylinder(piece, Vector3(0, 0.035, 0), 0.31, 0.06, team.darkened(0.25)).name = "Base"
	for side in [-1, 1]:
		var x = side * 0.105
		var leg = Node3D.new()
		leg.name = "LeftLeg" if side == -1 else "RightLeg"
		leg.position = Vector3(x, 0.43, 0)
		rig.add_child(leg)
		board._rounded_box(leg, Vector3(0, -0.3, 0.045), Vector3(0.16, 0.12, 0.27), 0.045, cream if index % 2 else Color("d8ff3e"))
		board._rounded_box(leg, Vector3(0, -0.14, 0), Vector3(0.13, 0.25, 0.14), 0.05, cream)
		board._box(leg, Vector3(0, -0.1, 0.073), Vector3(0.125, 0.045, 0.01), kit)
		var arm = Node3D.new()
		arm.name = "LeftArm" if side == -1 else "RightArm"
		arm.position = Vector3(side * 0.245, 0.77, 0)
		rig.add_child(arm)
		board._rounded_box(arm, Vector3(0, -0.1, 0), Vector3(0.16, 0.22, 0.2), 0.07, kit)
		board._rounded_box(arm, Vector3(side * 0.03, -0.25, 0.025), Vector3(0.12, 0.2, 0.13), 0.055, skin)
		board._sphere(arm, Vector3(side * 0.03, -0.33, 0.045), 0.075, cream if p.keeper else skin)
	board._rounded_box(rig, Vector3(0, 0.43, 0), Vector3(0.35, 0.19, 0.25), 0.055, navy)
	board._rounded_box(rig, Vector3(0, 0.66, 0), Vector3(0.38, 0.34, 0.28), 0.075, kit)
	var design = Node3D.new()
	design.name = "ShirtDesign"
	rig.add_child(design)
	var trim = navy if team.get_luminance() > 0.5 else cream
	if appearance.design == 1:
		for x in [-0.09, 0.09]:
			board._box(design, Vector3(x, 0.66, 0.142), Vector3(0.045, 0.25, 0.008), trim)
	elif appearance.design == 2:
		for y in [0.59, 0.71]:
			board._box(design, Vector3(0, y, 0.142), Vector3(0.33, 0.04, 0.008), trim)
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
	number.modulate = trim if not p.keeper else cream
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

static func animate(piece: Node3D, time: float, running: bool = false) -> void:
	var rig = piece.get_node("Rig")
	var phase = time * (16.0 if running else 2.2)
	rig.position.y = absf(sin(phase)) * 0.07 if running else sin(phase) * 0.009
	rig.scale.y = 1.0 if running else 1.0 + sin(phase) * 0.012
	rig.rotation.z = sin(phase * 0.5) * (0.04 if running else 0.018)
	for side in [-1, 1]:
		var arm = rig.get_node("LeftArm" if side == -1 else "RightArm")
		var leg = rig.get_node("LeftLeg" if side == -1 else "RightLeg")
		arm.rotation.x = sin(phase) * side * (0.65 if running else 0.07)
		leg.rotation.x = -sin(phase) * side * (0.7 if running else 0.015)
