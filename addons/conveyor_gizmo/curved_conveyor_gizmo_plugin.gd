@tool
extends EditorNode3DGizmoPlugin


const HANDLE_COLOR := Color(1, 0.5, 0, 1)
const ANGLE_ID := 3000
const WIDTH_ID := 3001
const CURVED_SCRIPT_PATHS := [
	"res://src/Conveyor/curved_belt_conveyor.gd",
	"res://src/RollerConveyor/curved_roller_conveyor.gd",
]

var sideguard_mode := false

var _initial_state: Dictionary = {}


func _init() -> void:
	create_handle_material("curved_handles")
	var mat := get_material("curved_handles", null)
	if mat:
		mat.albedo_color = HANDLE_COLOR


func _get_gizmo_name() -> String:
	return "CurvedConveyor"


func _has_gizmo(node: Node3D) -> bool:
	if node == null or node.has_meta("is_preview"):
		return false
	var script_obj := node.get_script()
	if script_obj == null:
		return false
	return script_obj.resource_path in CURVED_SCRIPT_PATHS


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	if sideguard_mode:
		return
	var node := gizmo.get_node_3d()
	var inner_radius := float(node.inner_radius)
	var width := float(node.width)
	var angle_rad := deg_to_rad(float(node.conveyor_angle))
	var avg_radius := inner_radius + width * 0.5
	var outer_radius := inner_radius + width

	var handles := PackedVector3Array()
	var handle_ids := PackedInt32Array()
	handles.append(_arc_point(angle_rad, avg_radius))
	handle_ids.append(ANGLE_ID)
	handles.append(_arc_point(angle_rad * 0.5, outer_radius))
	handle_ids.append(WIDTH_ID)
	gizmo.add_handles(handles, get_material("curved_handles", gizmo), handle_ids)


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	if handle_id == ANGLE_ID:
		return "Curve angle"
	if handle_id == WIDTH_ID:
		return "Width"
	return ""


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var node := gizmo.get_node_3d()
	if handle_id == ANGLE_ID:
		return float(node.conveyor_angle)
	return float(node.width)


func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> void:
	var node := gizmo.get_node_3d()
	if handle_id == ANGLE_ID:
		_initial_state = {"conveyor_angle": float(node.conveyor_angle)}
	else:
		_initial_state = {"width": float(node.width)}


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		camera: Camera3D, screen_point: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var hit_local := _project_to_arc_plane(node, camera, screen_point)
	if hit_local == Vector3.INF:
		return
	if handle_id == ANGLE_ID:
		# Inverse of _arc_point: -x = sin t * r, z = cos t * r.
		var deg := rad_to_deg(atan2(-hit_local.x, hit_local.z))
		node.conveyor_angle = clampf(deg, 5.0, 180.0)
	else:
		var radius := Vector2(hit_local.x, hit_local.z).length()
		node.width = maxf(0.1, radius - float(node.inner_radius))
	node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		_restore: Variant, cancel: bool) -> void:
	if _initial_state.is_empty():
		return
	var node := gizmo.get_node_3d() if gizmo else null
	var prop := "conveyor_angle" if handle_id == ANGLE_ID else "width"
	var action := "Set Curve Angle" if handle_id == ANGLE_ID else "Resize Curve Width"
	if cancel:
		node.set(prop, _initial_state[prop])
	else:
		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, node)
		undo_redo.add_do_property(node, prop, node.get(prop))
		undo_redo.add_undo_property(node, prop, _initial_state[prop])
		undo_redo.add_do_method(node, "update_gizmos")
		undo_redo.add_undo_method(node, "update_gizmos")
		undo_redo.commit_action()
	_initial_state.clear()


static func _arc_point(t: float, r: float) -> Vector3:
	return Vector3(-sin(t) * r, 0.0, cos(t) * r)


static func _project_to_arc_plane(node: Node3D, camera: Camera3D, screen_point: Vector2) -> Vector3:
	var xform := node.global_transform
	var plane_point := xform.origin
	var plane_normal := xform.basis.y.normalized()
	var ray_from := camera.project_ray_origin(screen_point)
	var ray_dir := camera.project_ray_normal(screen_point)
	var denom := ray_dir.dot(plane_normal)
	if absf(denom) < 1.0e-6:
		return Vector3.INF
	var t := (plane_point - ray_from).dot(plane_normal) / denom
	if t < 0.0:
		return Vector3.INF
	var hit_world := ray_from + ray_dir * t
	return xform.affine_inverse() * hit_world
