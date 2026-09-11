@tool
extends EditorNode3DGizmoPlugin

const PATH_COLOR = Color(0.2, 1.0, 0.3)
const WAYPOINT_COLOR = Color(1.0, 0.8, 0.2)
const MARKER_SIZE = 0.15
const LIFT_OFFSET = 0.05


func _init() -> void:
	create_material("path", PATH_COLOR)
	var path_mat = get_material("path", null)
	if path_mat:
		path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		path_mat.no_depth_test = true
		path_mat.render_priority = 10

	create_material("waypoint", WAYPOINT_COLOR)
	var wp_mat = get_material("waypoint", null)
	if wp_mat:
		wp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wp_mat.no_depth_test = true
		wp_mat.render_priority = 10


func _get_gizmo_name() -> String:
	return "AGVPathGizmo"


func _has_gizmo(node: Node3D) -> bool:
	if node.get_script() == null:
		return false
	var script_path = node.get_script().resource_path
	return script_path == "res://src/AGV/agv.gd"


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node: Node3D = gizmo.get_node_3d()
	if node == null:
		return

	if not node.get("show_gizmos"):
		return

	if not EditorInterface.get_selection().get_selected_nodes().has(node):
		return

	var home_pos: Vector3 = node.get("home_position")
	var waypoints: Dictionary = node.get("waypoints")

	var parent_points: Array = [home_pos]
	for key in waypoints.keys():
		var wp = waypoints[key]
		if wp:
			parent_points.append(wp.position)

	if parent_points.size() < 2:
		return

	var parent_xform: Transform3D = Transform3D.IDENTITY
	var parent_node := node.get_parent()
	if parent_node is Node3D:
		parent_xform = (parent_node as Node3D).global_transform
	var agv_inv: Transform3D = node.global_transform.affine_inverse()

	var local_points: Array = []
	for p in parent_points:
		var world_p: Vector3 = parent_xform * p
		var local_p: Vector3 = agv_inv * world_p
		local_p.y += LIFT_OFFSET
		local_points.append(local_p)

	var path_lines := PackedVector3Array()
	for i in range(local_points.size() - 1):
		path_lines.append(local_points[i])
		path_lines.append(local_points[i + 1])
		_append_arrowhead(path_lines, local_points[i], local_points[i + 1])
	gizmo.add_lines(path_lines, get_material("path", gizmo), false)

	var marker_lines := PackedVector3Array()
	for p in local_points:
		marker_lines.append(p + Vector3(-MARKER_SIZE, 0, 0))
		marker_lines.append(p + Vector3(MARKER_SIZE, 0, 0))
		marker_lines.append(p + Vector3(0, 0, -MARKER_SIZE))
		marker_lines.append(p + Vector3(0, 0, MARKER_SIZE))
	gizmo.add_lines(marker_lines, get_material("waypoint", gizmo), false)


func _append_arrowhead(lines: PackedVector3Array, from_p: Vector3, to_p: Vector3) -> void:
	var dir := to_p - from_p
	dir.y = 0
	var dist := dir.length()
	if dist < 0.3:
		return
	dir = dir / dist
	var side := Vector3(-dir.z, 0, dir.x)
	var head_len := minf(0.3, dist * 0.25)
	var head_tip := to_p - dir * (MARKER_SIZE + 0.05)
	var head_base := head_tip - dir * head_len
	lines.append(head_tip)
	lines.append(head_base + side * head_len * 0.5)
	lines.append(head_tip)
	lines.append(head_base - side * head_len * 0.5)
