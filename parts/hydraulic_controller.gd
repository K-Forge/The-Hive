@tool
extends Node3D

@export var hydraulic_base_anchor: Node3D
@export var hydraulic_rod_anchor: Node3D

@export var up_vector: Vector3 = Vector3.UP
@export var use_parent_up_vectors: bool = true

func _process(_delta: float) -> void:
	if not hydraulic_base_anchor or not hydraulic_rod_anchor:
		return

	var base_pos := hydraulic_base_anchor.global_position
	var rod_pos := hydraulic_rod_anchor.global_position

	if base_pos.distance_squared_to(rod_pos) < 0.000001:
		return

	var base_up := up_vector
	var rod_up := up_vector

	if use_parent_up_vectors:
		if hydraulic_base_anchor.get_parent() is Node3D:
			base_up = (hydraulic_base_anchor.get_parent() as Node3D).global_transform.basis.y.normalized()
		if hydraulic_rod_anchor.get_parent() is Node3D:
			rod_up = (hydraulic_rod_anchor.get_parent() as Node3D).global_transform.basis.y.normalized()

	hydraulic_base_anchor.look_at(rod_pos, base_up, true)
	hydraulic_rod_anchor.look_at(base_pos, rod_up, true)
