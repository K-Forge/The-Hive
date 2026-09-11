@tool
extends EditorNode3DGizmoPlugin

const AXIS_PROPS = ["x_position", "y_position", "z_position"]
const EE_COLOR = Color(0.2, 0.9, 0.9)
const EE_SUBGIZMO_ID = 0

var _initial_positions: Array = []


func _get_gizmo_name() -> String:
	return "GantryAxisGizmo"


func _has_gizmo(node: Node3D) -> bool:
	if node.get_script() == null:
		return false
	var script_path = node.get_script().resource_path
	return script_path == "res://src/Gantry/gantry.gd"


func _init() -> void:
	create_material("ee_line", EE_COLOR)
	var ee_mat = get_material("ee_line", null)
	if ee_mat:
		ee_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ee_mat.no_depth_test = true
		ee_mat.render_priority = 10


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node = gizmo.get_node_3d()
	if node == null:
		return

	if not node.get("show_gizmos"):
		return

	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var tip_local: Vector3 = node.to_local(tip_global)

	var ee_lines = PackedVector3Array()
	var cross_size: float = 0.06
	ee_lines.append(tip_local + Vector3(-cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(0, -cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, 0, -cross_size))
	ee_lines.append(tip_local + Vector3(0, 0, cross_size))
	gizmo.add_lines(ee_lines, get_material("ee_line", gizmo), false)


# --- End effector subgizmo ---


func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, point: Vector2) -> int:
	var node = gizmo.get_node_3d()
	if node == null:
		return -1

	if not node.get("show_gizmos"):
		return -1

	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var tip_screen := camera.unproject_position(tip_global)

	if tip_screen.distance_to(point) < 20.0:
		_initial_positions = Array(node.call("get_axis_positions"))
		return EE_SUBGIZMO_ID

	return -1


func _subgizmos_intersect_frustum(gizmo: EditorNode3DGizmo, camera: Camera3D, frustum: Array[Plane]) -> PackedInt32Array:
	var node = gizmo.get_node_3d()
	if node == null:
		return PackedInt32Array()

	if not node.get("show_gizmos"):
		return PackedInt32Array()

	var tip_global: Vector3 = node.call("get_tool_tip_position")

	for plane: Plane in frustum:
		if not plane.is_point_over(tip_global):
			return PackedInt32Array()

	_initial_positions = Array(node.call("get_axis_positions"))
	return PackedInt32Array([EE_SUBGIZMO_ID])


func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int) -> Transform3D:
	var node = gizmo.get_node_3d()
	if node == null:
		return Transform3D()

	var tip_global: Transform3D = node.call("get_tool_tip_transform")
	return node.global_transform.affine_inverse() * tip_global


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int, xform: Transform3D) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	var global_target: Vector3 = node.global_transform * xform.origin
	var local_target: Vector3 = node.to_local(global_target)

	var current_tip_global: Vector3 = node.call("get_tool_tip_position")
	var current_tip_local: Vector3 = node.to_local(current_tip_global)
	var delta: Vector3 = local_target - current_tip_local

	node.set("x_position", node.get("x_position") + delta.x)
	node.set("y_position", node.get("y_position") + delta.z)
	node.set("z_position", node.get("z_position") - delta.y)
	node.update_gizmos()


func _commit_subgizmos(gizmo: EditorNode3DGizmo, ids: PackedInt32Array, restores: Array[Transform3D], cancel: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	if cancel:
		for i in range(3):
			if i < _initial_positions.size():
				node.set(AXIS_PROPS[i], _initial_positions[i])
	else:
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Move Gantry End Effector")
		for i in range(3):
			undo_redo.add_do_property(node, AXIS_PROPS[i], node.get(AXIS_PROPS[i]))
			if i < _initial_positions.size():
				undo_redo.add_undo_property(node, AXIS_PROPS[i], _initial_positions[i])
		undo_redo.commit_action()

	_initial_positions = []

	if node:
		node.update_gizmos()
