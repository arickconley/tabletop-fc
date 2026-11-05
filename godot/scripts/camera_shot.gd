@tool
extends Node3D

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		aim()

func aim() -> void:
	var lens = get_node_or_null("Camera")
	var target = get_node_or_null("Target")
	if lens != null and target != null and lens.global_position.distance_to(target.global_position) > 0.001:
		lens.look_at(target.global_position)

func pose() -> Dictionary:
	aim()
	var lens: Camera3D = $Camera
	return {"transform": lens.global_transform, "size": lens.size, "fov": lens.fov, "h": lens.h_offset, "v": lens.v_offset}
