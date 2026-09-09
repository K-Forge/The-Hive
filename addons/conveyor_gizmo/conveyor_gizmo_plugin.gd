@tool
extends EditorNode3DGizmoPlugin

const HANDLE_SIZE = 0.1
const HANDLE_COLOR = Color(1, 0.5, 0, 1)
const HANDLE_COLOR_HOVER = Color(1, 0.8, 0, 1)

var _initial_state = {}
var sideguard_mode := false

func _get_gizmo_name():
	return "ConveyorGizmo"

func _has_gizmo(node):
	var node_script = node.get_script()
	if node_script == null:
		return false

	var script_path = node_script.resource_path
	# Path-based BeltConveyor owns its size gizmo elsewhere; here only for sideguard handles.
	var valid_scripts = [
		"res://src/Conveyor/belt_conveyor.gd",
		"res://src/Conveyor/belt_spur_conveyor.gd",
		"res://src/Conveyor/curved_belt_conveyor.gd",
		"res://src/RollerConveyor/roller_conveyor.gd",
		"res://src/RollerConveyor/roller_spur_conveyor.gd",
		"res://src/RollerConveyor/curved_roller_conveyor.gd",
		"res://src/Platform/platform.gd",
		"res://src/Stairs/stairs.gd",
		"res://src/GuardRail/guard_rail.gd",
		"res://src/Fence/fence.gd",
		"res://src/Rack/rack.gd",
		"res://src/FloorMarking/floor_marking.gd",
	]

	return script_path in valid_scripts

func _init():
	create_material("handles", HANDLE_COLOR)
	create_material("handles_hover", HANDLE_COLOR_HOVER)
	create_handle_material("handles", false)
	
	var handle_mat = get_material("handles", null)
	if handle_mat:
		handle_mat.vertex_color_use_as_albedo = true
		handle_mat.albedo_color = HANDLE_COLOR

func _redraw(gizmo: EditorNode3DGizmo):
	gizmo.clear()

	var node = gizmo.get_node_3d()

	if node.has_meta("is_preview"):
		return

	_add_selection_collision(gizmo, node)

	var sg_guards := _get_all_guards(node) if sideguard_mode else []
	var use_size_handles := not sideguard_mode or sg_guards.is_empty()

	if use_size_handles and node is ResizableNode3D:
		var resizable_node = node as ResizableNode3D
		var handles = PackedVector3Array()
		var handle_ids = PackedInt32Array()
		var active_ids: PackedInt32Array
		if resizable_node.has_method("_get_active_resize_handle_ids"):
			active_ids = resizable_node._get_active_resize_handle_ids()
		else:
			active_ids = PackedInt32Array([0, 1, 2, 3, 4, 5])
		for i in active_ids:
			handles.append(resizable_node.get_resize_handle_local_position(i, resizable_node.size))
			handle_ids.append(i)

		if handles.size() > 0:
			gizmo.add_handles(handles, get_material("handles", gizmo), handle_ids)

	if sideguard_mode and not sg_guards.is_empty():
		var sg_handles := PackedVector3Array()
		var sg_ids := PackedInt32Array()
		var sig: Dictionary = _significant_edges_per_side(node, sg_guards)
		for entry in sg_guards:
			var guard: SideGuard = entry["guard"]
			var y_mid: float = SideGuardMesh.WALL_HEIGHT / 2.0
			# Skip internal run boundaries so handles don't cluster at bends.
			var side: String = entry["side"]
			var pos: Vector3 = guard.position
			var arc_back: float = _guard_arc_back(guard)
			var arc_front: float = _guard_arc_front(guard)
			var significant: Array = sig[side] as Array
			if _arc_is_significant(arc_front, significant):
				sg_handles.append(Vector3(pos.x + guard.length / 2.0, pos.y + y_mid, pos.z))
				sg_ids.append(entry["front_id"])
			if _arc_is_significant(arc_back, significant):
				sg_handles.append(Vector3(pos.x - guard.length / 2.0, pos.y + y_mid, pos.z))
				sg_ids.append(entry["back_id"])
		# Single batched call: per-iteration calls would register duplicate IDs.
		gizmo.add_handles(sg_handles, get_material("handles", gizmo), sg_ids)

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool):
	if handle_id >= 100:
		var guard_idx: int = (handle_id - 100) / 2
		var is_front := (handle_id % 2) == 0
		return "Guard %d %s" % [guard_idx + 1, "Front" if is_front else "Back"]
	var names = ["Size +X", "Size -X", "Size +Y", "Size -Y", "Size +Z", "Size -Z"]
	if handle_id >= 0 and handle_id < names.size():
		return names[handle_id]
	return ""

func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool):
	var node = gizmo.get_node_3d()

	if handle_id >= 100:
		var guards := _get_all_guards(node)
		for entry in guards:
			if handle_id == entry["front_id"] or handle_id == entry["back_id"]:
				var is_front: bool = (handle_id == entry["front_id"])
				if Input.is_key_pressed(KEY_SHIFT):
					_merge_procedural_opening(node, entry, is_front)
					_initial_state = {"split": true}
					return
				if Input.is_key_pressed(KEY_CTRL):
					_split_procedural_guard(node, entry)
					_initial_state = {"split": true}
					return
				_initial_state = _capture_procedural_initial(node, entry)
				break
		return

	if not node is ResizableNode3D:
		return

	var resizable_node = node as ResizableNode3D

	_initial_state = {
		"size": resizable_node.size,
		"position": node.position,
		"transform": node.transform,
	}


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool):
	var node = gizmo.get_node_3d()
	if handle_id >= 100:
		for entry in _get_all_guards(node):
			if handle_id == entry["front_id"] or handle_id == entry["back_id"]:
				return (entry["guard"] as SideGuard).length
		return 0.0
	if not node is ResizableNode3D:
		return 0.0

	var resizable_node = node as ResizableNode3D
	var axis_index = int(handle_id / 2)

	return resizable_node.size[axis_index]

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, point: Vector2):
	var node = gizmo.get_node_3d()

	if handle_id >= 100:
		if _initial_state.has("split"):
			return
		if _initial_state.has("procedural"):
			var is_front := (handle_id % 2) == 0
			_set_procedural_handle(node, is_front, camera, point)
			node.update_gizmos()
		return

	if not node is ResizableNode3D:
		return
	
	var resizable_node = node as ResizableNode3D
	
	var axis_index = int(handle_id / 2)
	var is_positive = (handle_id % 2) == 0
	var opposite_handle_id: int = handle_id + 1 if is_positive else handle_id - 1
	
	var parent_transform = node.get_parent_node_3d().global_transform if node.get_parent_node_3d() else Transform3D.IDENTITY
	var initial_global_transform = parent_transform * _initial_state["transform"]
	var initial_size = _initial_state["size"]

	var fixed_edge_local := resizable_node.get_resize_handle_local_position(opposite_handle_id, initial_size)
	var fixed_edge_global = initial_global_transform * fixed_edge_local

	var axis_local = Vector3.ZERO
	axis_local[axis_index] = 1.0
	var axis_global = (initial_global_transform.basis * axis_local).normalized()

	var ray_from = camera.project_ray_origin(point)
	var ray_dir = camera.project_ray_normal(point)

	var v1 = axis_global
	var v2 = ray_dir
	var v3 = fixed_edge_global - ray_from
	
	var dot11 = v1.dot(v1)
	var dot12 = v1.dot(v2)
	var dot13 = v1.dot(v3)
	var dot22 = v2.dot(v2)
	var dot23 = v2.dot(v3)
	
	var denom = dot11 * dot22 - dot12 * dot12
	if abs(denom) < 0.0001:
		return
	
	var t1 = (dot12 * dot23 - dot22 * dot13) / denom
	var distance_along_axis = t1
	
	var new_size = initial_size
	new_size[axis_index] = absf(distance_along_axis)
	
	new_size = resizable_node.size_min.max(new_size)
	new_size = resizable_node._get_constrained_size(new_size)

	# Pin opposite handle in world-space for non-centered pivots.
	var new_fixed_local := resizable_node.get_resize_handle_local_position(opposite_handle_id, new_size)
	var new_origin_global: Vector3 = fixed_edge_global - (initial_global_transform.basis * new_fixed_local)
	var new_position: Vector3 = parent_transform.affine_inverse() * new_origin_global
	
	node.position = new_position
	resizable_node.resize(new_size, handle_id)

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore, cancel: bool):
	var node = gizmo.get_node_3d()

	if handle_id >= 100 and _initial_state.has("split"):
		_initial_state.clear()
		return

	if handle_id >= 100 and _initial_state.has("procedural"):
		if cancel:
			node.set(&"side_guard_openings", _initial_state["openings_before"])
		else:
			var undo_redo = EditorInterface.get_editor_undo_redo()
			undo_redo.create_action("Resize Spur Side Guard")
			undo_redo.add_do_property(node, "side_guard_openings", _initial_state["openings_after"])
			undo_redo.add_undo_property(node, "side_guard_openings", _initial_state["openings_before"])
			undo_redo.add_do_method(node, "update_gizmos")
			undo_redo.add_undo_method(node, "update_gizmos")
			undo_redo.commit_action()
		_initial_state.clear()
		return

	if not node is ResizableNode3D:
		return

	var resizable_node = node as ResizableNode3D

	if cancel:
		node.position = _initial_state["position"]
		resizable_node.size = _initial_state["size"]
	else:
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Resize Conveyor")
		# Position before size so the side-guard update sees the correct transform.
		undo_redo.add_do_property(node, "position", node.position)
		undo_redo.add_do_property(resizable_node, "size", resizable_node.size)
		undo_redo.add_undo_property(node, "position", _initial_state["position"])
		undo_redo.add_undo_property(resizable_node, "size", _initial_state["size"])
		undo_redo.commit_action()

	_initial_state.clear()


#region Procedural-guard helpers (BeltSpurConveyor)

func _capture_procedural_initial(node: Node3D, entry: Dictionary) -> Dictionary:
	var openings_before: Array = (node.get(&"side_guard_openings") as Array).duplicate(true)
	var side: String = entry["side"]
	var guard: SideGuard = entry["guard"]
	var front_arc: float = _guard_arc_front(guard)
	var back_arc: float = _guard_arc_back(guard)
	var natural_back: float = 0.0
	var natural_front: float = 0.0
	var per_side: Array = []
	for e in _get_procedural_guards(node):
		if e["side"] == side:
			per_side.append(e["guard"])
	if not per_side.is_empty():
		var first_g: SideGuard = per_side[0]
		var last_g: SideGuard = per_side[-1]
		natural_back = _guard_arc_back(first_g)
		natural_front = _guard_arc_front(last_g)
	return {
		"procedural": true,
		"side": side,
		"front_x": front_arc,
		"back_x": back_arc,
		"openings_before": openings_before,
		"openings_after": openings_before.duplicate(true),
		"natural_back": natural_back,
		"natural_front": natural_front,
	}


func _set_procedural_handle(node: Node3D, is_front: bool, camera: Camera3D, point: Vector2) -> void:
	var side: String = _initial_state["side"]
	var natural_back: float = _initial_state["natural_back"]
	var natural_front: float = _initial_state["natural_front"]
	var edge_x: float = _initial_state["front_x"] if is_front else _initial_state["back_x"]
	var merged: Array = _spur_merged_openings_from_array(_initial_state["openings_before"], side)

	var drag_x: float = _project_mouse_to_spur_x(node, camera, point)
	if is_nan(drag_x):
		return

	if is_front:
		var op_index: int = _find_opening_by_edge(merged, edge_x, true)
		if op_index >= 0:
			var op: Vector2 = merged[op_index]
			op.x = clampf(drag_x, -INF, op.y - 0.01)
			merged[op_index] = op
		elif absf(edge_x - natural_front) < 0.01:
			var clamped: float = clampf(drag_x, natural_back + 0.01, natural_front - 0.001)
			merged.append(Vector2(clamped, natural_front + 0.001))
			merged.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		else:
			return
	else:
		var op_index: int = _find_opening_by_edge(merged, edge_x, false)
		if op_index >= 0:
			var op: Vector2 = merged[op_index]
			op.y = clampf(drag_x, op.x + 0.01, INF)
			merged[op_index] = op
		elif absf(edge_x - natural_back) < 0.01:
			var clamped: float = clampf(drag_x, natural_back - 0.001, natural_front - 0.01)
			merged.insert(0, Vector2(natural_back - 0.001, clamped))
		else:
			return

	var new_openings: Array = _spur_replace_side_openings(_initial_state["openings_before"], side, merged)
	var typed: Array[SideGuardOpening] = []
	for op: SideGuardOpening in new_openings:
		typed.append(op)
	_initial_state["openings_after"] = typed
	node.set(&"side_guard_openings", typed)


func _find_opening_by_edge(merged: Array, edge_x: float, edge_is_start: bool) -> int:
	for i in range(merged.size()):
		var op: Vector2 = merged[i]
		var op_edge: float = op.x if edge_is_start else op.y
		if absf(op_edge - edge_x) < 0.01:
			return i
	return -1


func _significant_edges_per_side(node: Node3D, sg_guards: Array) -> Dictionary:
	var by_side: Dictionary = {"left": [], "right": []}
	var per_side_guards: Dictionary = {"left": [], "right": []}
	for e in sg_guards:
		if e.get("procedural", false):
			(per_side_guards[e["side"]] as Array).append(e["guard"])
	for side: String in ["left", "right"]:
		var guards: Array = per_side_guards[side]
		var significant: Array = []
		if not guards.is_empty():
			var first_g: SideGuard = guards[0]
			var last_g: SideGuard = guards[-1]
			significant.append(_guard_arc_back(first_g))
			significant.append(_guard_arc_front(last_g))
		var openings: Array = _spur_merged_openings_from_array(
				node.get(&"side_guard_openings") as Array, side)
		for op in openings:
			var v: Vector2 = op
			significant.append(v.x)
			significant.append(v.y)
		by_side[side] = significant
	return by_side


func _arc_is_significant(arc_x: float, significant_arcs: Array) -> bool:
	for s in significant_arcs:
		if absf(float(s) - arc_x) < 0.01:
			return true
	return false


func _guard_arc_back(guard: SideGuard) -> float:
	return guard.arc_back


func _guard_arc_front(guard: SideGuard) -> float:
	return guard.arc_front


func _project_mouse_to_spur_x(node: Node3D, camera: Camera3D, point: Vector2) -> float:
	var node_xform: Transform3D = node.global_transform
	var axis_global: Vector3 = node_xform.basis.x.normalized()
	var ray_from: Vector3 = camera.project_ray_origin(point)
	var ray_dir: Vector3 = camera.project_ray_normal(point)
	var v3: Vector3 = node_xform.origin - ray_from
	var dot11: float = axis_global.dot(axis_global)
	var dot12: float = axis_global.dot(ray_dir)
	var dot13: float = axis_global.dot(v3)
	var dot22: float = ray_dir.dot(ray_dir)
	var dot23: float = ray_dir.dot(v3)
	var denom: float = dot11 * dot22 - dot12 * dot12
	if absf(denom) < 0.0001:
		return NAN
	return (dot12 * dot23 - dot22 * dot13) / denom


func _split_procedural_guard(node: Node3D, entry: Dictionary) -> void:
	const GAP := 0.15
	var side: String = entry["side"]
	var guard: SideGuard = entry["guard"]
	var sub_back: float = _guard_arc_back(guard)
	var sub_front: float = _guard_arc_front(guard)
	if sub_front - sub_back <= GAP + 0.02:
		return
	var center: float = (sub_back + sub_front) * 0.5
	var openings_before: Array = (node.get(&"side_guard_openings") as Array).duplicate(true)
	var merged: Array = _spur_merged_openings_from_array(openings_before, side)
	merged.append(Vector2(center - GAP * 0.5, center + GAP * 0.5))
	merged.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var new_openings: Array = _spur_replace_side_openings(openings_before, side, merged)
	var typed: Array[SideGuardOpening] = []
	for op: SideGuardOpening in new_openings:
		typed.append(op)
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Split Side Guard Opening")
	undo_redo.add_do_property(node, "side_guard_openings", typed)
	undo_redo.add_undo_property(node, "side_guard_openings", openings_before)
	undo_redo.add_do_method(node, "update_gizmos")
	undo_redo.add_undo_method(node, "update_gizmos")
	undo_redo.commit_action()


func _merge_procedural_opening(node: Node3D, entry: Dictionary, is_front: bool) -> void:
	var side: String = entry["side"]
	var guard: SideGuard = entry["guard"]
	var edge_x: float = _guard_arc_front(guard) if is_front else _guard_arc_back(guard)
	var openings_before: Array = (node.get(&"side_guard_openings") as Array).duplicate(true)
	var merged: Array = _spur_merged_openings_from_array(openings_before, side)
	var op_index: int = _find_opening_by_edge(merged, edge_x, is_front)
	if op_index < 0:
		return
	merged.remove_at(op_index)
	var new_openings: Array = _spur_replace_side_openings(openings_before, side, merged)
	var typed: Array[SideGuardOpening] = []
	for op: SideGuardOpening in new_openings:
		typed.append(op)
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Merge Side Guard Opening")
	undo_redo.add_do_property(node, "side_guard_openings", typed)
	undo_redo.add_undo_property(node, "side_guard_openings", openings_before)
	undo_redo.add_do_method(node, "update_gizmos")
	undo_redo.add_undo_method(node, "update_gizmos")
	undo_redo.commit_action()


func _spur_merged_openings_from_array(openings: Array, side: String) -> Array:
	var ranges: Array = []
	for o: SideGuardOpening in openings:
		if o == null or o.side != side:
			continue
		if o.arc_front <= o.arc_back:
			continue
		ranges.append(Vector2(o.arc_back, o.arc_front))
	ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array = []
	for r: Vector2 in ranges:
		if merged.is_empty() or r.x > merged[-1].y:
			merged.append(r)
		else:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, r.y))
	return merged


func _spur_replace_side_openings(openings: Array, side: String, new_ranges: Array) -> Array:
	var result: Array = []
	for o: SideGuardOpening in openings:
		if o != null and o.side != side:
			result.append(o)
	for r in new_ranges:
		var v: Vector2 = r
		result.append(SideGuardOpening.make(v.x, v.y, side))
	return result

#endregion



func _get_all_guards(node: Node3D) -> Array:
	if node.has_method("request_side_guard_opening"):
		return _get_procedural_guards(node)
	return []


func _get_procedural_guards(node: Node3D) -> Array:
	var left_pairs: Array = []
	var right_pairs: Array = []
	for child in node.get_children(true):
		if not (child is SideGuard):
			continue
		var n: String = child.name
		if n.begins_with("SideGuardLeft_"):
			left_pairs.append([_parse_guard_index(n, "SideGuardLeft_"), child])
		elif n.begins_with("SideGuardRight_"):
			right_pairs.append([_parse_guard_index(n, "SideGuardRight_"), child])
	left_pairs.sort_custom(func(a, b): return a[0] < b[0])
	right_pairs.sort_custom(func(a, b): return a[0] < b[0])

	var result: Array = []
	var handle_idx := 100
	for entry: Array in [["left", left_pairs], ["right", right_pairs]]:
		var side: String = entry[0]
		var pairs: Array = entry[1]
		for k in range(pairs.size()):
			result.append({
				"guard": pairs[k][1] as SideGuard,
				"side_node": node,
				"front_id": handle_idx,
				"back_id": handle_idx + 1,
				"procedural": true,
				"side": side,
			})
			handle_idx += 2
	return result


#region Roller selection collision

const _ROLLER_BED_SCRIPTS := [
	"res://src/RollerConveyor/roller_conveyor.gd",
	"res://src/RollerConveyor/roller_spur_conveyor.gd",
]
const _CURVED_ROLLER_SCRIPT := "res://src/RollerConveyor/curved_roller_conveyor.gd"


func _add_selection_collision(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	var node_script = node.get_script()
	if node_script == null:
		return
	var path: String = node_script.resource_path
	var faces: PackedVector3Array
	if path == _CURVED_ROLLER_SCRIPT:
		faces = _curved_bed_faces(node)
	elif path in _ROLLER_BED_SCRIPTS:
		var bounds: AABB = (node as ResizableNode3D)._get_resize_local_bounds(node.size)
		# Cap the box top at the roller surface (y = 0) so it doesn't steal clicks from items on the bed.
		bounds.position.y = -bounds.size.y
		faces = _box_faces(bounds)
	elif path == "res://src/Fence/fence.gd":
		# Resize bounds are flat in Z; give the pick box the post's real depth.
		var bounds: AABB = (node as ResizableNode3D)._get_resize_local_bounds(node.size)
		bounds.position.z = -FenceMesh.POST_SIZE * 0.5
		bounds.size.z = FenceMesh.POST_SIZE
		faces = _box_faces(bounds)
	else:
		return
	if faces.size() < 3:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tri_mesh := arr_mesh.generate_triangle_mesh()
	if tri_mesh:
		gizmo.add_collision_triangles(tri_mesh)


static func _add_quad(f: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	f.append(a); f.append(b); f.append(c)
	f.append(a); f.append(c); f.append(d)


static func _box_faces(b: AABB) -> PackedVector3Array:
	var mn := b.position
	var mx := b.position + b.size
	var c000 := Vector3(mn.x, mn.y, mn.z)
	var c100 := Vector3(mx.x, mn.y, mn.z)
	var c110 := Vector3(mx.x, mx.y, mn.z)
	var c010 := Vector3(mn.x, mx.y, mn.z)
	var c001 := Vector3(mn.x, mn.y, mx.z)
	var c101 := Vector3(mx.x, mn.y, mx.z)
	var c111 := Vector3(mx.x, mx.y, mx.z)
	var c011 := Vector3(mn.x, mx.y, mx.z)
	var f := PackedVector3Array()
	_add_quad(f, c000, c100, c110, c010)
	_add_quad(f, c001, c011, c111, c101)
	_add_quad(f, c000, c010, c011, c001)
	_add_quad(f, c100, c101, c111, c110)
	_add_quad(f, c000, c001, c101, c100)
	_add_quad(f, c010, c110, c111, c011)
	return f


func _curved_bed_faces(node: Node3D) -> PackedVector3Array:
	var inner: float = node.inner_radius
	var outer: float = node.inner_radius + node.width
	var ang: float = deg_to_rad(node.conveyor_angle)
	var y_top := 0.0
	var y_bot := -0.30
	var segs: int = maxi(2, int(node.conveyor_angle / 5.0))
	var f := PackedVector3Array()
	for i in segs:
		var a0 := ang * float(i) / float(segs)
		var a1 := ang * float(i + 1) / float(segs)
		var s0 := sin(a0); var c0 := cos(a0)
		var s1 := sin(a1); var c1 := cos(a1)
		var in0_t := Vector3(-s0 * inner, y_top, c0 * inner)
		var out0_t := Vector3(-s0 * outer, y_top, c0 * outer)
		var in1_t := Vector3(-s1 * inner, y_top, c1 * inner)
		var out1_t := Vector3(-s1 * outer, y_top, c1 * outer)
		var in0_b := Vector3(-s0 * inner, y_bot, c0 * inner)
		var out0_b := Vector3(-s0 * outer, y_bot, c0 * outer)
		var in1_b := Vector3(-s1 * inner, y_bot, c1 * inner)
		var out1_b := Vector3(-s1 * outer, y_bot, c1 * outer)
		_add_quad(f, in0_t, out0_t, out1_t, in1_t)
		_add_quad(f, in0_b, in1_b, out1_b, out0_b)
		_add_quad(f, out0_t, out0_b, out1_b, out1_t)
		_add_quad(f, in0_t, in1_t, in1_b, in0_b)
	return f

#endregion


# Packs `<run>_<sub>` into one sort key; plain int(substr) collapses `0_*` to 0.
static func _parse_guard_index(name: String, prefix: String) -> int:
	var tail: String = name.substr(prefix.length())
	var parts: PackedStringArray = tail.split("_", false)
	if parts.is_empty():
		return 0
	var run_idx: int = int(parts[0])
	var sub_idx: int = int(parts[1]) if parts.size() > 1 else 0
	return run_idx * 10000 + sub_idx
