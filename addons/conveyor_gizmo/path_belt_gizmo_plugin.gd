@tool
extends EditorNode3DGizmoPlugin

## Drag-handle gizmo for path-based [BeltConveyor]: per-segment length, tail, width.

const HANDLE_COLOR := Color(1, 0.5, 0, 1)
const PATH_BELT_SCRIPT_PATH := "res://src/Conveyor/belt_conveyor.gd"
const TAIL_HANDLE_ID := 1500
const WIDTH_LEFT_ID := 2000
const WIDTH_RIGHT_ID := 2001

## When true, suppress own handles so sideguard handles don't compete.
var sideguard_mode := false

var _initial_state: Dictionary = {}


func _init() -> void:
	create_handle_material("path_belt_handles")
	var mat := get_material("path_belt_handles", null)
	if mat:
		mat.albedo_color = HANDLE_COLOR


func _get_gizmo_name() -> String:
	return "BeltConveyor"


func _has_gizmo(node: Node3D) -> bool:
	if node == null:
		return false
	if node.has_meta("is_preview"):
		return false
	var script_obj := node.get_script()
	if script_obj == null:
		return false
	return script_obj.resource_path == PATH_BELT_SCRIPT_PATH


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	if sideguard_mode:
		return
	var node := gizmo.get_node_3d()
	var segments: Array = _get_segments(node)
	if segments.is_empty():
		return
	var ends := _segment_end_positions(node)
	var handles := PackedVector3Array()
	var handle_ids := PackedInt32Array()
	handles.append(Vector3.ZERO)
	handle_ids.append(TAIL_HANDLE_ID)
	for i in range(ends.size()):
		# Null entries keep index parity with `segments` but have no handle.
		if segments[i] == null:
			continue
		handles.append(ends[i])
		handle_ids.append(i)
	var half_w: float = float(node.width) * 0.5
	var mid: Vector3 = _conveyor_midpoint_local(node)
	handles.append(mid + Vector3(0.0, 0.0, -half_w))
	handle_ids.append(WIDTH_LEFT_ID)
	handles.append(mid + Vector3(0.0, 0.0, half_w))
	handle_ids.append(WIDTH_RIGHT_ID)
	gizmo.add_handles(handles, get_material("path_belt_handles", gizmo), handle_ids)


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	if handle_id == WIDTH_LEFT_ID:
		return "Width (-Z)"
	if handle_id == WIDTH_RIGHT_ID:
		return "Width (+Z)"
	if handle_id == TAIL_HANDLE_ID:
		return "Tail length"
	return "Segment %d length" % handle_id


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var node := gizmo.get_node_3d()
	if handle_id == WIDTH_LEFT_ID or handle_id == WIDTH_RIGHT_ID:
		return float(node.width)
	if handle_id == TAIL_HANDLE_ID:
		var seg: BeltSegment = _get_segment(node, 0)
		return seg.length if seg else 0.0
	var seg: BeltSegment = _get_segment(node, handle_id)
	return seg.length if seg else 0.0


func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> void:
	var node := gizmo.get_node_3d()
	if handle_id == WIDTH_LEFT_ID or handle_id == WIDTH_RIGHT_ID:
		# Width drag shifts origin to keep the untouched edge put.
		_initial_state = {
			"width": float(node.width),
			"position": node.position,
			"global_transform": node.global_transform,
		}
		return
	if handle_id == TAIL_HANDLE_ID:
		var seg0: BeltSegment = _get_segment(node, 0)
		if seg0 == null:
			return
		_initial_state = {
			"node": node,
			"segment": seg0,
			"length": seg0.length,
			"transform": node.transform,
			"global_transform": node.global_transform,
		}
		return
	var seg: BeltSegment = _get_segment(node, handle_id)
	if seg == null:
		return
	_initial_state = {
		"segment": seg,
		"length": seg.length,
	}


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		camera: Camera3D, screen_point: Vector2) -> void:
	var node := gizmo.get_node_3d()
	if handle_id == WIDTH_LEFT_ID or handle_id == WIDTH_RIGHT_ID:
		_drag_width(node, handle_id, camera, screen_point)
	elif handle_id == TAIL_HANDLE_ID:
		_drag_tail(node, camera, screen_point)
	else:
		var seg: BeltSegment = _get_segment(node, handle_id)
		if seg == null:
			return
		_drag_length(node, seg, handle_id, camera, screen_point)
	node.update_gizmos()


func _commit_handle(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		_restore: Variant, cancel: bool) -> void:
	if _initial_state.is_empty():
		return
	var node := _gizmo.get_node_3d() if _gizmo else null
	var undo_redo := EditorInterface.get_editor_undo_redo()
	if handle_id == WIDTH_LEFT_ID or handle_id == WIDTH_RIGHT_ID:
		if cancel:
			node.width = _initial_state["width"]
			node.position = _initial_state["position"]
		else:
			# custom_context = node pins the action to the scene's history.
			undo_redo.create_action("Resize Width", UndoRedo.MERGE_DISABLE, node)
			# Position before width: width updates side guards from the transform.
			undo_redo.add_do_property(node, "position", node.position)
			undo_redo.add_do_property(node, "width", node.width)
			undo_redo.add_undo_property(node, "position", _initial_state["position"])
			undo_redo.add_undo_property(node, "width", _initial_state["width"])
			undo_redo.add_do_method(node, "update_gizmos")
			undo_redo.add_undo_method(node, "update_gizmos")
			undo_redo.commit_action()
		_initial_state.clear()
		return
	if handle_id == TAIL_HANDLE_ID:
		var seg0: BeltSegment = _initial_state["segment"]
		var initial_xform: Transform3D = _initial_state["transform"]
		var initial_length: float = _initial_state["length"]
		if cancel:
			seg0.length = initial_length
			node.transform = initial_xform
		else:
			# custom_context = node keeps sub-resource edits out of global history.
			undo_redo.create_action("Resize Tail", UndoRedo.MERGE_DISABLE, node)
			undo_redo.add_do_property(seg0, "length", seg0.length)
			undo_redo.add_undo_property(seg0, "length", initial_length)
			undo_redo.add_do_property(node, "transform", node.transform)
			undo_redo.add_undo_property(node, "transform", initial_xform)
			undo_redo.add_do_method(node, "update_gizmos")
			undo_redo.add_undo_method(node, "update_gizmos")
			undo_redo.commit_action()
		_initial_state.clear()
		return
	var seg: BeltSegment = _initial_state["segment"]
	if seg == null:
		_initial_state.clear()
		return
	if cancel:
		seg.length = _initial_state["length"]
	else:
		undo_redo.create_action("Resize Segment", UndoRedo.MERGE_DISABLE, node)
		undo_redo.add_do_property(seg, "length", seg.length)
		undo_redo.add_undo_property(seg, "length", _initial_state["length"])
		undo_redo.add_do_method(node, "update_gizmos")
		undo_redo.add_undo_method(node, "update_gizmos")
		undo_redo.commit_action()
	_initial_state.clear()


static func _drag_length(node: Node3D, seg: BeltSegment, seg_index: int,
		camera: Camera3D, screen_point: Vector2) -> void:
	var corner_local: Vector3 = _segment_start_corner(node, seg_index)
	var tangent_local: Vector3 = _segment_tangent(node, seg_index)
	var node_xform: Transform3D = node.global_transform
	var corner_world: Vector3 = node_xform * corner_local
	var tangent_world: Vector3 = (node_xform.basis * tangent_local).normalized()
	var ray_from: Vector3 = camera.project_ray_origin(screen_point)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_point)
	var v1: Vector3 = tangent_world
	var v2: Vector3 = ray_dir
	var v3: Vector3 = corner_world - ray_from
	var dot11: float = v1.dot(v1)
	var dot12: float = v1.dot(v2)
	var dot13: float = v1.dot(v3)
	var dot22: float = v2.dot(v2)
	var dot23: float = v2.dot(v3)
	var denom: float = dot11 * dot22 - dot12 * dot12
	if absf(denom) < 1.0e-4:
		return
	var distance_along_axis: float = (dot12 * dot23 - dot22 * dot13) / denom
	seg.length = maxf(0.05, distance_along_axis)


func _drag_tail(node: Node3D, camera: Camera3D, screen_point: Vector2) -> void:
	# Tail moves along seg 0's tangent; origin shifts so the head stays put.
	var seg0: BeltSegment = _initial_state.get("segment")
	if seg0 == null:
		return
	var initial_xform: Transform3D = _initial_state["global_transform"]
	var initial_length: float = _initial_state["length"]
	var tail_world: Vector3 = initial_xform.origin
	var tangent_world: Vector3 = initial_xform.basis.x.normalized()
	var ray_from: Vector3 = camera.project_ray_origin(screen_point)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_point)
	var v1: Vector3 = tangent_world
	var v2: Vector3 = ray_dir
	var v3: Vector3 = tail_world - ray_from
	var dot11: float = v1.dot(v1)
	var dot12: float = v1.dot(v2)
	var dot13: float = v1.dot(v3)
	var dot22: float = v2.dot(v2)
	var dot23: float = v2.dot(v3)
	var denom: float = dot11 * dot22 - dot12 * dot12
	if absf(denom) < 1.0e-4:
		return
	var drag_along_t: float = (dot12 * dot23 - dot22 * dot13) / denom
	var max_shrink: float = initial_length - 0.05
	drag_along_t = clampf(drag_along_t, -INF, max_shrink)
	var new_length: float = initial_length - drag_along_t
	var new_origin_world: Vector3 = initial_xform.origin + tangent_world * drag_along_t
	var parent: Node3D = node.get_parent_node_3d()
	if parent:
		var parent_inv := parent.global_transform.affine_inverse()
		var local_origin: Vector3 = parent_inv * new_origin_world
		node.transform = Transform3D(node.transform.basis, local_origin)
	else:
		node.global_transform = Transform3D(initial_xform.basis, new_origin_world)
	seg0.length = new_length


func _drag_width(node: Node3D, handle_id: int, camera: Camera3D, screen_point: Vector2) -> void:
	var initial_xform: Transform3D = _initial_state["global_transform"]
	var initial_width: float = _initial_state["width"]
	var initial_half_w: float = initial_width * 0.5
	var z_world: Vector3 = initial_xform.basis.z.normalized()
	var mid_local: Vector3 = _conveyor_midpoint_local(node)
	var mid_world: Vector3 = initial_xform * mid_local

	var ray_from: Vector3 = camera.project_ray_origin(screen_point)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_point)
	var v3: Vector3 = mid_world - ray_from
	var dot11: float = z_world.dot(z_world)
	var dot12: float = z_world.dot(ray_dir)
	var dot13: float = z_world.dot(v3)
	var dot22: float = ray_dir.dot(ray_dir)
	var dot23: float = ray_dir.dot(v3)
	var denom: float = dot11 * dot22 - dot12 * dot12
	if absf(denom) < 1.0e-4:
		return
	var distance_along_axis: float = (dot12 * dot23 - dot22 * dot13) / denom

	var side_sign: float = 1.0 if handle_id == WIDTH_RIGHT_ID else -1.0
	# Average with opposite edge so the untouched edge stays anchored.
	var new_half_w: float = maxf(0.05, (initial_half_w + side_sign * distance_along_axis) * 0.5)
	var shift_world: Vector3 = z_world * (side_sign * (new_half_w - initial_half_w))
	var parent_node: Node3D = node.get_parent_node_3d()
	var parent_inv: Transform3D = parent_node.global_transform.affine_inverse() \
			if parent_node else Transform3D.IDENTITY
	node.position = parent_inv * (initial_xform.origin + shift_world)
	node.width = new_half_w * 2.0


static func _conveyor_midpoint_local(node: Node3D) -> Vector3:
	var segments: Array = _get_segments(node)
	var total: float = 0.0
	for seg: BeltSegment in segments:
		if seg:
			total += seg.length
	if total <= 0.0:
		return Vector3.ZERO
	var target: float = total * 0.5
	var corner: Vector3 = Vector3.ZERO
	var tilt: float = 0.0
	var cumulative: float = 0.0
	for i in range(segments.size()):
		var seg: BeltSegment = segments[i]
		if seg == null:
			continue
		tilt += deg_to_rad(seg.tilt_relative_deg)
		var tangent := Vector3(cos(tilt), sin(tilt), 0.0)
		if cumulative + seg.length >= target:
			return corner + tangent * (target - cumulative)
		corner = corner + tangent * seg.length
		cumulative += seg.length
	return corner


## Per-segment end position. Null segments emit a placeholder so out[i] ↔ segments[i].
static func _segment_end_positions(node: Node3D) -> Array:
	var out: Array = []
	var segments: Array = _get_segments(node)
	if segments.is_empty():
		return out
	var corner: Vector3 = Vector3.ZERO
	var tilt: float = 0.0
	for i in range(segments.size()):
		var seg: BeltSegment = segments[i]
		if seg == null:
			out.append(corner)
			continue
		tilt += deg_to_rad(seg.tilt_relative_deg)
		var tangent := Vector3(cos(tilt), sin(tilt), 0.0)
		corner = corner + tangent * seg.length
		out.append(corner)
	return out


static func _segment_start_corner(node: Node3D, segment_index: int) -> Vector3:
	var segments: Array = _get_segments(node)
	var corner: Vector3 = Vector3.ZERO
	var tilt: float = 0.0
	for i in range(segment_index):
		var seg: BeltSegment = segments[i]
		if seg == null:
			continue
		tilt += deg_to_rad(seg.tilt_relative_deg)
		corner += Vector3(cos(tilt), sin(tilt), 0.0) * seg.length
	return corner


static func _segment_tangent(node: Node3D, segment_index: int) -> Vector3:
	var segments: Array = _get_segments(node)
	var tilt: float = 0.0
	for i in range(segment_index + 1):
		var seg: BeltSegment = segments[i]
		if seg == null:
			continue
		tilt += deg_to_rad(seg.tilt_relative_deg)
	return Vector3(cos(tilt), sin(tilt), 0.0)


static func _get_segments(node: Node3D) -> Array:
	if node == null:
		return []
	var segs: Variant = node.get("segments")
	if segs == null:
		return []
	return segs as Array


static func _get_segment(node: Node3D, segment_index: int) -> BeltSegment:
	var segments: Array = _get_segments(node)
	if segment_index < 0 or segment_index >= segments.size():
		return null
	return segments[segment_index] as BeltSegment
