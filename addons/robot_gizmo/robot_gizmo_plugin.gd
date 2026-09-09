@tool
extends EditorNode3DGizmoPlugin

const JOINT_COLORS = [
	Color(1.0, 0.2, 0.2),
	Color(1.0, 0.6, 0.2),
	Color(1.0, 1.0, 0.2),
	Color(0.2, 1.0, 0.2),
	Color(0.2, 0.6, 1.0),
	Color(0.8, 0.2, 1.0),
]

const ARC_SEGMENTS = 32
const ARC_RADIUS_SCALE = 1.5
const EE_COLOR = Color(0.2, 0.9, 0.9)
const EE_SUBGIZMO_ID = 0
const TOOL_JOINT_INDEX = 5

const EOAT_COLOR = Color(0.95, 0.6, 0.15)
const EOAT_FRAME_Y = -0.075
const EOAT_HANDLE_SIZE_X = 10
const EOAT_HANDLE_SIZE_Z = 11

var _drag_joint_idx: int = -1
var _initial_joint_angle: float = 0.0
var _drag_start_mouse_angle: float = 0.0
var _pivot_screen_pos: Vector2 = Vector2.ZERO

var _initial_joint_angles: Array = []
var _initial_eoat_size: float = 0.0


func _get_gizmo_name() -> String:
	return "RobotJointGizmo"


func _has_gizmo(node: Node3D) -> bool:
	if node.get_script() == null:
		return false
	var script_path = node.get_script().resource_path
	return script_path == "res://src/SixAxisRobot/six_axis_robot.gd"


func _init() -> void:
	for i in range(6):
		create_material("joint_%d" % i, JOINT_COLORS[i])
		var mat = get_material("joint_%d" % i, null)
		if mat:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mat.render_priority = 10
	
	create_handle_material("handles", false)
	
	create_material("ee_line", EE_COLOR)
	var ee_mat = get_material("ee_line", null)
	if ee_mat:
		ee_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ee_mat.no_depth_test = true
		ee_mat.render_priority = 10

	create_material("eoat_line", EOAT_COLOR)
	var eoat_mat = get_material("eoat_line", null)
	if eoat_mat:
		eoat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eoat_mat.no_depth_test = true
		eoat_mat.render_priority = 10


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node = gizmo.get_node_3d()
	if node == null:
		return

	if not EditorInterface.get_selection().get_selected_nodes().has(node):
		return

	if node.get("show_gizmos"):
		_draw_joints(gizmo, node)

	if node.get("show_eoat_gizmo"):
		_draw_eoat(gizmo, node)


func _draw_joints(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	var pivots = [
		node.get("_base_pivot"),
		node.get("_upper_arm_pivot"),
		node.get("_forearm_pivot"),
		node.get("_wrist_rot_pivot"),
		node.get("_wrist_pitch_pivot"),
		node.get("_tool_pivot"),
	]
	
	var robot_scale: float = node.get("robot_scale") if node.get("robot_scale") else 3.0
	
	var all_handles = PackedVector3Array()
	var all_handle_ids = PackedInt32Array()
	
	for i in range(6):
		var pivot = pivots[i]
		if pivot == null:
			continue

		if i == TOOL_JOINT_INDEX:
			continue

		var arc_radius: float = _get_arc_radius(i, robot_scale)
		var arc_data := _generate_arc_with_handle(i, pivot, node, arc_radius)
		
		if arc_data.lines.size() > 0:
			gizmo.add_lines(arc_data.lines, get_material("joint_%d" % i, gizmo), false)
		
		all_handles.append(arc_data.handle_pos)
		all_handle_ids.append(i)
	
	if all_handles.size() > 0:
		gizmo.add_handles(all_handles, get_material("handles", gizmo), all_handle_ids)
	
	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var tip_local: Vector3 = node.to_local(tip_global)
	
	var ee_lines = PackedVector3Array()
	var cross_size: float = 0.08 * robot_scale
	ee_lines.append(tip_local + Vector3(-cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(0, -cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, 0, -cross_size))
	ee_lines.append(tip_local + Vector3(0, 0, cross_size))
	gizmo.add_lines(ee_lines, get_material("ee_line", gizmo), false)


func _draw_eoat(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	var eoat: Node3D = node.call("get_attached_tool")
	if eoat == null or not ("tool_size_x" in eoat):
		return

	var half_x: float = eoat.get("tool_size_x") * 0.5
	var half_z: float = eoat.get("tool_size_z") * 0.5
	var to_node := node.global_transform.affine_inverse() * eoat.global_transform

	var corners = [
		Vector3(-half_x, EOAT_FRAME_Y, -half_z),
		Vector3(half_x, EOAT_FRAME_Y, -half_z),
		Vector3(half_x, EOAT_FRAME_Y, half_z),
		Vector3(-half_x, EOAT_FRAME_Y, half_z),
	]
	var lines = PackedVector3Array()
	for i in range(4):
		lines.append(to_node * corners[i])
		lines.append(to_node * corners[(i + 1) % 4])
	gizmo.add_lines(lines, get_material("eoat_line", gizmo), false)

	var handles = PackedVector3Array([
		to_node * Vector3(half_x, EOAT_FRAME_Y, 0),
		to_node * Vector3(0, EOAT_FRAME_Y, half_z),
	])
	gizmo.add_handles(handles, get_material("handles", gizmo), PackedInt32Array([EOAT_HANDLE_SIZE_X, EOAT_HANDLE_SIZE_Z]))


func _get_arc_radius(joint_idx: int, robot_scale: float) -> float:
	var base_radii = [0.25, 0.2, 0.15, 0.12, 0.1, 0.08]
	return base_radii[joint_idx] * robot_scale * ARC_RADIUS_SCALE


func _generate_arc_with_handle(joint_idx: int, pivot: Node3D, robot: Node3D, radius: float) -> Dictionary:
	var lines = PackedVector3Array()
	var handle_pos = Vector3.ZERO
	var is_y_axis = joint_idx in [0, 3, 5]
	
	var pivot_pos = robot.to_local(pivot.global_position)
	var pivot_basis = robot.global_transform.affine_inverse().basis * pivot.global_transform.basis
	
	var axis: Vector3
	var perp1: Vector3
	var perp2: Vector3
	
	if is_y_axis:
		axis = pivot_basis.y.normalized()
		perp1 = pivot_basis.x.normalized()
		perp2 = pivot_basis.z.normalized()
	else:
		axis = pivot_basis.z.normalized()
		perp1 = pivot_basis.x.normalized()
		perp2 = pivot_basis.y.normalized()
	
	for i in range(ARC_SEGMENTS):
		var t1 = (float(i) / ARC_SEGMENTS) * TAU
		var t2 = (float(i + 1) / ARC_SEGMENTS) * TAU
		
		var p1 = pivot_pos + (perp1 * cos(t1) + perp2 * sin(t1)) * radius
		var p2 = pivot_pos + (perp1 * cos(t2) + perp2 * sin(t2)) * radius
		
		lines.append(p1)
		lines.append(p2)
	
	handle_pos = pivot_pos + perp1 * radius
	var cross_size = radius * 0.3
	lines.append(handle_pos - perp1 * cross_size)
	lines.append(handle_pos + perp1 * cross_size)
	lines.append(handle_pos - perp2 * cross_size)
	lines.append(handle_pos + perp2 * cross_size)
	
	lines.append(pivot_pos)
	lines.append(handle_pos)
	
	return {"lines": lines, "handle_pos": handle_pos}


func _is_eoat_handle(handle_id: int) -> bool:
	return handle_id == EOAT_HANDLE_SIZE_X or handle_id == EOAT_HANDLE_SIZE_Z


func _eoat_size_prop(handle_id: int) -> String:
	return "tool_size_x" if handle_id == EOAT_HANDLE_SIZE_X else "tool_size_z"


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	if _is_eoat_handle(handle_id):
		return "EOAT Size X" if handle_id == EOAT_HANDLE_SIZE_X else "EOAT Size Z"
	return "J%d" % (handle_id + 1)


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var node = gizmo.get_node_3d()
	if node == null:
		return 0.0

	if _is_eoat_handle(handle_id):
		return node.get(_eoat_size_prop(handle_id))

	var angle_props = ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]
	return node.get(angle_props[handle_id])


func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	if _is_eoat_handle(handle_id):
		_initial_eoat_size = node.get(_eoat_size_prop(handle_id))
		return

	_drag_joint_idx = handle_id
	var angle_props = ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]
	_initial_joint_angle = node.get(angle_props[handle_id])
	_drag_start_mouse_angle = -999.0
	_pivot_screen_pos = Vector2.ZERO


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	if _is_eoat_handle(handle_id):
		_set_eoat_handle(node, handle_id, camera, screen_pos)
		return

	var pivots = [
		node.get("_base_pivot"),
		node.get("_upper_arm_pivot"),
		node.get("_forearm_pivot"),
		node.get("_wrist_rot_pivot"),
		node.get("_wrist_pitch_pivot"),
		node.get("_tool_pivot"),
	]
	
	var pivot = pivots[handle_id]
	if pivot == null:
		return
	
	if _pivot_screen_pos == Vector2.ZERO:
		_pivot_screen_pos = camera.unproject_position(pivot.global_position)
	
	var to_mouse = screen_pos - _pivot_screen_pos
	var mouse_angle = atan2(to_mouse.y, to_mouse.x)
	
	if _drag_start_mouse_angle < -900.0:
		_drag_start_mouse_angle = mouse_angle
		return
	
	var delta_angle = rad_to_deg(mouse_angle - _drag_start_mouse_angle)
	var is_y_axis = handle_id in [0, 3, 5]
	var joint_axis: Vector3
	if is_y_axis:
		joint_axis = pivot.global_transform.basis.y.normalized()
	else:
		joint_axis = pivot.global_transform.basis.z.normalized()
	
	var camera_forward = -camera.global_transform.basis.z.normalized()
	var axis_dot = joint_axis.dot(camera_forward)
	if axis_dot < 0:
		delta_angle = -delta_angle
	
	var new_angle = _initial_joint_angle + delta_angle
	
	var angle_props = ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]
	node.set(angle_props[handle_id], new_angle)

	node.update_gizmos()


func _set_eoat_handle(node: Node3D, handle_id: int, camera: Camera3D, screen_pos: Vector2) -> void:
	var eoat: Node3D = node.call("get_attached_tool")
	if eoat == null:
		return

	var axis_local := Vector3.RIGHT if handle_id == EOAT_HANDLE_SIZE_X else Vector3.BACK
	var origin := eoat.global_transform * Vector3(0, EOAT_FRAME_Y, 0)
	var axis_vec := eoat.global_transform.basis * axis_local
	var axis_scale := axis_vec.length()
	if axis_scale < 0.0001:
		return
	var axis_dir := axis_vec / axis_scale

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var points := Geometry3D.get_closest_points_between_segments(
		origin - axis_dir * 100.0, origin + axis_dir * 100.0,
		ray_from, ray_from + ray_dir * 1000.0)

	var dist := (points[0] - origin).dot(axis_dir)
	node.set(_eoat_size_prop(handle_id), absf(dist) * 2.0 / axis_scale)
	node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	if _is_eoat_handle(handle_id):
		var prop := _eoat_size_prop(handle_id)
		if cancel:
			node.set(prop, _initial_eoat_size)
		else:
			var eoat_undo_redo = EditorInterface.get_editor_undo_redo()
			eoat_undo_redo.create_action("Resize Robot EOAT")
			eoat_undo_redo.add_do_property(node, prop, node.get(prop))
			eoat_undo_redo.add_undo_property(node, prop, _initial_eoat_size)
			eoat_undo_redo.commit_action()
		node.update_gizmos()
		return

	var angle_props = ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]

	if cancel:
		node.set(angle_props[handle_id], _initial_joint_angle)
	else:
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Rotate Robot J%d" % (handle_id + 1))
		undo_redo.add_do_property(node, angle_props[handle_id], node.get(angle_props[handle_id]))
		undo_redo.add_undo_property(node, angle_props[handle_id], _initial_joint_angle)
		undo_redo.commit_action()
	
	_drag_joint_idx = -1
	_drag_start_mouse_angle = 0.0
	_pivot_screen_pos = Vector2.ZERO
	
	if node:
		node.update_gizmos()


func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, point: Vector2) -> int:
	var node = gizmo.get_node_3d()
	if node == null:
		return -1
	
	if not node.get("show_gizmos"):
		return -1
	
	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var tip_screen := camera.unproject_position(tip_global)
	
	if tip_screen.distance_to(point) < 20.0:
		_initial_joint_angles = Array(node.call("get_joint_angles"))
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
	
	_initial_joint_angles = Array(node.call("get_joint_angles"))
	return PackedInt32Array([EE_SUBGIZMO_ID])


func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int) -> Transform3D:
	var node = gizmo.get_node_3d()
	if node == null:
		return Transform3D()
	
	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var local_origin: Vector3 = node.global_transform.affine_inverse() * tip_global
	return Transform3D(Basis.IDENTITY, local_origin)


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int, xform: Transform3D) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return
	
	var global_target: Vector3 = node.global_transform * xform.origin
	node.call("solve_ik", global_target)
	node.update_gizmos()


func _commit_subgizmos(gizmo: EditorNode3DGizmo, ids: PackedInt32Array, restores: Array[Transform3D], cancel: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return
	
	var angle_props = ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]
	
	if cancel:
		for i in range(6):
			if i < _initial_joint_angles.size():
				node.set(angle_props[i], _initial_joint_angles[i])
	else:
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Move Robot End Effector")
		for i in range(6):
			undo_redo.add_do_property(node, angle_props[i], node.get(angle_props[i]))
			if i < _initial_joint_angles.size():
				undo_redo.add_undo_property(node, angle_props[i], _initial_joint_angles[i])
		undo_redo.commit_action()
	
	_initial_joint_angles = []
	
	if node:
		node.update_gizmos()
