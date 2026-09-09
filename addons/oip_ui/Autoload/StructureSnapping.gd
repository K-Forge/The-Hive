@tool
extends Node

## One-shot (keyboard shortcut) and live (always-on while selected, Alt to
## escape) snapping for platforms, stairs, and guard rails.

const SEARCH_RADIUS: float = 8.0
const LIVE_VISIBLE_THRESHOLD: float = 3.0
const LIVE_FENCE_VISIBLE_THRESHOLD: float = 1.0
const LIVE_HEIGHT_TOLERANCE: float = 0.35
const LIVE_STAIRS_HEIGHT_PADDING: float = 0.25


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	if get_node_or_null("StructureLiveSnap") == null:
		var live_snap_script: GDScript = load("res://addons/oip_ui/Autoload/StructureLiveSnap.gd")
		if live_snap_script:
			var live_snap: Node = live_snap_script.new()
			live_snap.name = "StructureLiveSnap"
			add_child(live_snap)


func snap_selected_structures() -> void:
	var selection := EditorInterface.get_selection()
	var selected_nodes := selection.get_selected_nodes()

	if selected_nodes.size() < 2:
		EditorInterface.get_editor_toaster().push_toast(
			"Select two structures to snap (Platform+Stairs, Platform+Platform, Platform+GuardRail).",
			EditorToaster.SEVERITY_WARNING)
		return

	var platforms: Array[Platform] = []
	var stairs_list: Array[Stairs] = []
	var barriers: Array[ResizableNode3D] = []
	var markings: Array[FloorMarking] = []

	for node in selected_nodes:
		if node is Platform:
			platforms.append(node as Platform)
		elif node is Stairs:
			stairs_list.append(node as Stairs)
		elif _is_barrier(node):
			barriers.append(node as ResizableNode3D)
		elif node is FloorMarking:
			markings.append(node as FloorMarking)

	if stairs_list.size() > 0 and platforms.size() > 0:
		_snap_stairs_to_platform(stairs_list[0], platforms[0])
	elif barriers.size() >= 2 and platforms.is_empty():
		_snap_barrier_to_barrier(barriers[0], barriers[1])
	elif barriers.size() > 0 and platforms.size() > 0:
		_snap_barrier_to_platform(barriers[0], platforms[0])
	elif platforms.size() >= 2:
		_snap_platform_to_platform(platforms[0], platforms[1])
	elif markings.size() >= 2:
		_snap_marking_to_marking(markings[0], markings[1])
	else:
		EditorInterface.get_editor_toaster().push_toast(
			"Select Platform+Stairs, Platform+Barrier, Barrier+Barrier, Platform+Platform, or Marking+Marking.",
			EditorToaster.SEVERITY_WARNING)


static func find_snap_to_specific_platform(selected: Node3D, target: Platform, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected) or target == null or not is_instance_valid(target):
		return {}
	if target == selected:
		return {}
	if _horizontal_distance(target.global_position, intent.origin) > SEARCH_RADIUS:
		return {}

	var candidate: Variant = _calculate_snap_transform_for_intent(selected, target, intent)
	if candidate == null:
		return {}
	var candidate_transform: Transform3D = candidate
	var horizontal_delta := _horizontal_distance(intent.origin, candidate_transform.origin)
	if horizontal_delta > _get_live_visible_threshold(selected):
		return {}
	var height_delta := absf(intent.origin.y - candidate_transform.origin.y)
	if height_delta > _get_live_height_tolerance(selected):
		return {}
	var score := horizontal_delta + height_delta * 0.2
	var result := {"transform": candidate_transform, "target": target, "distance": score}
	if selected is Stairs:
		var stairs := selected as Stairs
		var target_rise := maxf(stairs.size_min.y, target.global_position.y - target.floor_y)
		var target_run := StairsMesh.get_default_run_length(target_rise)
		result["size"] = Vector3(target_run, target_rise, stairs.size.z)
	return result


static func find_best_snap_to_platform(selected: Node3D, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected):
		return {}

	if not (selected is Platform or selected is Stairs or _is_barrier(selected)):
		return {}

	var best_result: Dictionary = {}
	var best_target: Platform = null
	var best_dist := INF

	for target in Platform.instances:
		if not is_instance_valid(target):
			continue
		var r := find_snap_to_specific_platform(selected, target, intent)
		if r.is_empty():
			continue
		var d: float = r.distance
		if d < best_dist:
			best_dist = d
			best_result = r
			best_target = target

	if best_result.is_empty() or best_target == null:
		return {}
	return best_result


static func _calculate_snap_transform_for_intent(selected: Node3D, target: Platform, intent: Transform3D) -> Variant:
	if selected is Stairs:
		return _compute_stairs_to_platform_transform(selected as Stairs, target, intent)
	if _is_barrier(selected):
		return _compute_barrier_to_platform_transform(selected as ResizableNode3D, target, intent)
	if selected is Platform:
		return _compute_platform_to_platform_transform(selected as Platform, target, intent)
	return null


static func find_snap_to_specific_barrier(selected: Node3D, target: Node3D, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected) or target == null or not is_instance_valid(target):
		return {}
	# Same-type only: a fence chains to fences, a guard rail to guard rails.
	if target == selected or not _is_barrier(selected) or selected.get_script() != target.get_script():
		return {}
	if _horizontal_distance(target.global_position, intent.origin) > SEARCH_RADIUS:
		return {}

	var computed := _compute_barrier_to_barrier_transform(selected as ResizableNode3D, target as ResizableNode3D, intent)
	var candidate_transform: Transform3D = computed.transform
	var horizontal_delta := _horizontal_distance(intent.origin, candidate_transform.origin)
	if horizontal_delta > _get_live_visible_threshold(selected):
		return {}
	var height_delta := absf(intent.origin.y - candidate_transform.origin.y)
	if height_delta > LIVE_HEIGHT_TOLERANCE:
		return {}
	var score := horizontal_delta + height_delta * 0.2
	var result := {"transform": candidate_transform, "target": target, "distance": score}
	if _is_barrier(selected):
		result["omit_post_start"] = computed.omit_post_start
		result["omit_post_end"] = computed.omit_post_end
	return result


func _snap_marking_to_marking(moving: FloorMarking, target: FloorMarking) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Snap Marking to Marking")

	var new_transform: Transform3D = _compute_marking_to_marking_transform(moving, target, moving.global_transform)
	undo_redo.add_do_property(moving, "global_transform", new_transform)
	undo_redo.add_undo_property(moving, "global_transform", moving.global_transform)
	undo_redo.commit_action()


static func find_snap_to_specific_marking(selected: Node3D, target: FloorMarking, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected) or target == null or not is_instance_valid(target):
		return {}
	if target == selected or not (selected is FloorMarking):
		return {}
	if _horizontal_distance(target.global_position, intent.origin) > SEARCH_RADIUS:
		return {}

	var candidate_transform: Transform3D = _compute_marking_to_marking_transform(selected as FloorMarking, target, intent)
	var horizontal_delta := _horizontal_distance(intent.origin, candidate_transform.origin)
	if horizontal_delta > LIVE_VISIBLE_THRESHOLD:
		return {}
	var height_delta := absf(intent.origin.y - candidate_transform.origin.y)
	if height_delta > LIVE_HEIGHT_TOLERANCE:
		return {}
	var score := horizontal_delta + height_delta * 0.2
	return {"transform": candidate_transform, "target": target, "distance": score}


static func find_best_snap_to_marking(selected: Node3D, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected) or not (selected is FloorMarking):
		return {}

	var best_result: Dictionary = {}
	var best_dist := INF

	for target in FloorMarking.instances:
		if not is_instance_valid(target):
			continue
		var r := find_snap_to_specific_marking(selected, target, intent)
		if r.is_empty():
			continue
		var d: float = r.distance
		if d < best_dist:
			best_dist = d
			best_result = r

	return best_result


static func _compute_marking_to_marking_transform(moving: FloorMarking, target: FloorMarking, intent: Transform3D) -> Transform3D:
	var m_pos := intent.origin
	var current_basis := intent.basis
	var m_hl := moving.size.x / 2.0
	var m_hw := moving.size.z / 2.0

	var target_edges := _get_marking_edges(target)

	var m_edge_centers_local: Array[Vector3] = [
		Vector3(m_hl, 0, 0),
		Vector3(-m_hl, 0, 0),
		Vector3(0, 0, m_hw),
		Vector3(0, 0, -m_hw),
	]
	var m_edge_outwards_local: Array[Vector3] = [
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.BACK,
		Vector3.FORWARD,
	]
	# Half-length of each moving edge along its own run direction (local).
	var m_edge_along_halves: Array[float] = [m_hw, m_hw, m_hl, m_hl]

	var current_forward := _horizontal_dir(current_basis.x, Vector3.RIGHT)
	var current_yaw := atan2(current_forward.z, current_forward.x)
	var target_basis := target.global_transform.basis.orthonormalized()

	var best_transform := intent
	var best_cost := INF

	for te in target_edges:
		var t_seg_start: Vector3 = te[0]
		var t_seg_end: Vector3 = te[1]
		var t_outward: Vector3 = _horizontal_dir(te[2], Vector3.RIGHT)
		var t_edge_vec := t_seg_end - t_seg_start
		var t_edge_len := t_edge_vec.length()
		var t_edge_dir: Vector3 = t_edge_vec / t_edge_len if t_edge_len > 0.0001 else Vector3.RIGHT

		for me_idx in range(4):
			var local_outward := m_edge_outwards_local[me_idx]
			var m_along_half := m_edge_along_halves[me_idx]
			var desired_outward := -t_outward

			var best_basis_for_pair := target_basis
			var best_dot := -INF
			for k in range(4):
				var candidate_basis := target_basis * Basis(Vector3.UP, float(k) * (PI * 0.5))
				var out_world := _horizontal_dir(candidate_basis * local_outward, Vector3.RIGHT)
				var d := out_world.dot(desired_outward)
				if d > best_dot:
					best_dot = d
					best_basis_for_pair = candidate_basis

			var candidate_basis := best_basis_for_pair
			var rotated_center := candidate_basis * m_edge_centers_local[me_idx]
			var yaw := atan2(_horizontal_dir(candidate_basis.x, Vector3.RIGHT).z, _horizontal_dir(candidate_basis.x, Vector3.RIGHT).x)
			var center_guess := m_pos + rotated_center
			var closest_clamped := _closest_point_on_segment_xz(center_guess, t_seg_start, t_seg_end)

			# Center-clamp lets the user slide; the two corner-flush candidates make
			# the moving's corner coincide with the target's corner near either end.
			var edge_positions: Array[Vector3] = [closest_clamped]
			if t_edge_len > 0.0001:
				edge_positions.append(t_seg_start + t_edge_dir * m_along_half)
				edge_positions.append(t_seg_end - t_edge_dir * m_along_half)

			for edge_pos in edge_positions:
				var candidate_pos := edge_pos - rotated_center
				candidate_pos.y = target.global_position.y

				var move_cost := Vector2(candidate_pos.x - m_pos.x, candidate_pos.z - m_pos.z).length()
				var rot_cost := absf(wrapf(yaw - current_yaw, -PI, PI))
				var total_cost := move_cost + rot_cost * 0.35
				if total_cost < best_cost:
					best_cost = total_cost
					best_transform = Transform3D(candidate_basis, candidate_pos)

	return best_transform


static func _get_marking_edges(m: FloorMarking) -> Array:
	var xf := m.global_transform
	var hl := m.size.x / 2.0
	var hw := m.size.z / 2.0
	return [
		[xf * Vector3(hl, 0, -hw), xf * Vector3(hl, 0, hw), (xf.basis * Vector3.RIGHT).normalized()],
		[xf * Vector3(-hl, 0, hw), xf * Vector3(-hl, 0, -hw), (xf.basis * Vector3.LEFT).normalized()],
		[xf * Vector3(-hl, 0, hw), xf * Vector3(hl, 0, hw), (xf.basis * Vector3.BACK).normalized()],
		[xf * Vector3(hl, 0, -hw), xf * Vector3(-hl, 0, -hw), (xf.basis * Vector3.FORWARD).normalized()],
	]


static func find_best_snap_to_barrier(selected: Node3D, intent: Transform3D) -> Dictionary:
	if selected == null or not is_instance_valid(selected) or not _is_barrier(selected):
		return {}

	var best_result: Dictionary = {}
	var best_dist := INF

	for target in _barrier_instances(selected):
		if not is_instance_valid(target):
			continue
		var r := find_snap_to_specific_barrier(selected, target, intent)
		if r.is_empty():
			continue
		var d: float = r.distance
		if d < best_dist:
			best_dist = d
			best_result = r

	return best_result


static func _closest_point_on_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var ab_flat := Vector3(ab.x, 0, ab.z)
	var ap := point - a
	var ap_flat := Vector3(ap.x, 0, ap.z)
	var denom := ab_flat.dot(ab_flat)
	if denom < 0.0001:
		return a
	var t := clampf(ap_flat.dot(ab_flat) / denom, 0.0, 1.0)
	return a + ab * t


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _is_barrier(node: Node) -> bool:
	return node is GuardRail or node is Fence


static func _barrier_instances(node: Node) -> Array:
	if node is Fence:
		return Fence.instances
	return GuardRail.instances


static func _get_live_visible_threshold(selected: Node3D) -> float:
	if selected is Fence:
		return LIVE_FENCE_VISIBLE_THRESHOLD
	return LIVE_VISIBLE_THRESHOLD


static func _get_live_height_tolerance(selected: Node3D) -> float:
	if selected is Stairs:
		var stairs := selected as Stairs
		return maxf(LIVE_HEIGHT_TOLERANCE, stairs.size.y * 0.5 + LIVE_STAIRS_HEIGHT_PADDING)
	return LIVE_HEIGHT_TOLERANCE


static func _horizontal_dir(v: Vector3, fallback: Vector3 = Vector3.RIGHT) -> Vector3:
	var flat := Vector3(v.x, 0, v.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


static func _basis_with_x_axis(direction_x: Vector3) -> Basis:
	var x_axis := _horizontal_dir(direction_x, Vector3.RIGHT)
	var z_axis := x_axis.cross(Vector3.UP)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.BACK
	else:
		z_axis = z_axis.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


static func _basis_with_x_and_z(x_dir: Vector3, z_dir: Vector3) -> Basis:
	var x_axis := _horizontal_dir(x_dir, Vector3.RIGHT)
	var z_axis := _horizontal_dir(z_dir, Vector3.BACK)
	z_axis = (Vector3.UP.cross(x_axis)).normalized() if absf(x_axis.dot(z_axis)) > 0.999 else z_axis
	var y_axis := z_axis.cross(x_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


static func _get_platform_edges(p: Platform) -> Array:
	var xf := p.global_transform
	var hl := p.size.x / 2.0
	var hw := p.size.z / 2.0
	return [
		[xf * Vector3(hl, 0, -hw), xf * Vector3(hl, 0, hw), (xf.basis * Vector3.RIGHT).normalized()],
		[xf * Vector3(-hl, 0, hw), xf * Vector3(-hl, 0, -hw), (xf.basis * Vector3.LEFT).normalized()],
		[xf * Vector3(-hl, 0, hw), xf * Vector3(hl, 0, hw), (xf.basis * Vector3.BACK).normalized()],
		[xf * Vector3(hl, 0, -hw), xf * Vector3(-hl, 0, -hw), (xf.basis * Vector3.FORWARD).normalized()],
	]


func _snap_stairs_to_platform(stairs: Stairs, platform: Platform) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Snap Stairs to Platform")

	var target_rise := maxf(stairs.size_min.y, platform.global_position.y - platform.floor_y)
	var target_run := StairsMesh.get_default_run_length(target_rise)
	var new_size := Vector3(target_run, target_rise, stairs.size.z)
	var new_transform: Transform3D = _compute_stairs_to_platform_transform(stairs, platform, stairs.global_transform)

	undo_redo.add_do_property(stairs, "size", new_size)
	undo_redo.add_undo_property(stairs, "size", stairs.size)
	undo_redo.add_do_property(stairs, "global_transform", new_transform)
	undo_redo.add_undo_property(stairs, "global_transform", stairs.global_transform)
	undo_redo.commit_action()


static func _compute_stairs_to_platform_transform(stairs: Stairs, platform: Platform, intent: Transform3D) -> Transform3D:
	var s_pos := intent.origin
	var target_rise := maxf(stairs.size_min.y, platform.global_position.y - platform.floor_y)
	var target_run := StairsMesh.get_default_run_length(target_rise)
	var s_size := Vector3(target_run, target_rise, stairs.size.z)
	var s_hw := s_size.z / 2.0
	var edges := _get_platform_edges(platform)

	var best_seg_start := Vector3.ZERO
	var best_seg_end := Vector3.ZERO
	var best_outward := Vector3.RIGHT
	var best_closest := Vector3.ZERO
	var best_dist := INF

	for e in edges:
		var seg_s: Vector3 = e[0]
		var seg_e: Vector3 = e[1]
		var outward: Vector3 = e[2]
		var closest := _closest_point_on_segment_xz(s_pos, seg_s, seg_e)
		var d := Vector2(s_pos.x - closest.x, s_pos.z - closest.z).length()
		if d < best_dist:
			best_dist = d
			best_seg_start = seg_s
			best_seg_end = seg_e
			best_outward = outward
			best_closest = closest

	var edge_vec := best_seg_end - best_seg_start
	var edge_len := edge_vec.length()
	if edge_len > 0.01:
		var edge_dir := edge_vec / edge_len
		var t := (best_closest - best_seg_start).dot(edge_dir)
		t = clampf(t, s_hw, maxf(s_hw, edge_len - s_hw))
		best_closest = best_seg_start + edge_dir * t

	var outward_flat := _horizontal_dir(best_outward, Vector3.RIGHT)
	var stair_forward := -outward_flat
	var new_pos := best_closest + outward_flat * (s_size.x / 2.0)
	new_pos.y = platform.global_position.y

	var new_basis := _basis_with_x_axis(stair_forward)
	return Transform3D(new_basis, new_pos)


func _snap_barrier_to_platform(barrier: ResizableNode3D, platform: Platform) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Snap Barrier to Platform")

	var new_transform: Transform3D = _compute_barrier_to_platform_transform(barrier, platform, barrier.global_transform)
	undo_redo.add_do_property(barrier, "global_transform", new_transform)
	undo_redo.add_undo_property(barrier, "global_transform", barrier.global_transform)
	undo_redo.commit_action()


static func _compute_barrier_to_platform_transform(barrier: ResizableNode3D, platform: Platform, intent: Transform3D) -> Transform3D:
	var r_pos := intent.origin
	var r_half_len := barrier.size.x / 2.0
	var edges := _get_platform_edges(platform)

	var best_seg_start := Vector3.ZERO
	var best_seg_end := Vector3.ZERO
	var best_outward := Vector3.BACK
	var best_closest := Vector3.ZERO
	var best_dist := INF

	for e in edges:
		var seg_s: Vector3 = e[0]
		var seg_e: Vector3 = e[1]
		var outward: Vector3 = e[2]
		var closest := _closest_point_on_segment_xz(r_pos, seg_s, seg_e)
		var d := Vector2(r_pos.x - closest.x, r_pos.z - closest.z).length()
		if d < best_dist:
			best_dist = d
			best_seg_start = seg_s
			best_seg_end = seg_e
			best_outward = outward
			best_closest = closest

	var edge_vec := best_seg_end - best_seg_start
	var edge_len := edge_vec.length()
	var edge_dir := _horizontal_dir(edge_vec, Vector3.RIGHT)
	if edge_len > 0.01:
		var t := (best_closest - best_seg_start).dot(edge_dir)
		t = clampf(t, r_half_len, maxf(r_half_len, edge_len - r_half_len))
		best_closest = best_seg_start + edge_dir * t

	var outward_flat := _horizontal_dir(best_outward, Vector3.BACK)
	var new_basis := _basis_with_x_and_z(edge_dir, outward_flat)
	var new_pos := best_closest
	new_pos.y = platform.global_position.y
	# Guard rails mount flush to the edge; centered geometry needs a half-post nudge.
	if barrier is GuardRail:
		new_pos += new_basis.z * (GuardRailMesh.POST_SIZE * 0.5)
	return Transform3D(new_basis, new_pos)


func _snap_barrier_to_barrier(moving: ResizableNode3D, target: ResizableNode3D) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Snap Barrier to Barrier")

	var result := _compute_barrier_to_barrier_transform(moving, target, moving.global_transform)
	undo_redo.add_do_property(moving, "global_transform", result.transform)
	undo_redo.add_undo_property(moving, "global_transform", moving.global_transform)
	if _is_barrier(moving):
		undo_redo.add_do_property(moving, "omit_post_start", result.omit_post_start)
		undo_redo.add_undo_property(moving, "omit_post_start", moving.get("omit_post_start"))
		undo_redo.add_do_property(moving, "omit_post_end", result.omit_post_end)
		undo_redo.add_undo_property(moving, "omit_post_end", moving.get("omit_post_end"))
	undo_redo.commit_action()


## Returns { transform, omit_post_start, omit_post_end }.
static func _compute_barrier_to_barrier_transform(moving: ResizableNode3D, target: ResizableNode3D, intent: Transform3D) -> Dictionary:
	var target_basis := target.global_transform.basis.orthonormalized()
	var target_x := _horizontal_dir(target_basis.x, Vector3.RIGHT)
	var target_origin := target.global_position
	var target_half := target.size.x / 2.0
	var moving_half := moving.size.x / 2.0

	var moving_x_current := _horizontal_dir(intent.basis.x, Vector3.RIGHT)
	var alignment := absf(moving_x_current.dot(target_x))
	var is_perpendicular := alignment < 0.5

	if not is_perpendicular:
		var cand_plus := target_origin + target_x * (target_half + moving_half)
		var cand_minus := target_origin - target_x * (target_half + moving_half)
		var new_pos: Vector3
		if intent.origin.distance_squared_to(cand_plus) <= intent.origin.distance_squared_to(cand_minus):
			new_pos = cand_plus
		else:
			new_pos = cand_minus
		return {"transform": Transform3D(target_basis, new_pos), "omit_post_start": false, "omit_post_end": false}

	# L-corner: moving end meets target end, 90° off target's X.
	var perp := Vector3(-target_x.z, 0, target_x.x)
	if moving_x_current.dot(perp) < 0.0:
		perp = -perp
	var corner_basis := _basis_with_x_axis(perp)
	var corner_x := _horizontal_dir(corner_basis.x, Vector3.RIGHT)

	var target_post_centers := [
		target_origin + target_x * target_half,
		target_origin - target_x * target_half,
	]
	var moving_end_offsets := [
		corner_x * moving_half,
		-corner_x * moving_half,
	]

	var best_center := intent.origin
	var best_dist := INF
	var best_is_plus_end := true
	for t_end in target_post_centers:
		for mi in range(moving_end_offsets.size()):
			var center: Vector3 = t_end - moving_end_offsets[mi]
			var d := intent.origin.distance_squared_to(center)
			if d < best_dist:
				best_dist = d
				best_center = center
				best_is_plus_end = mi == 0

	var omit_end := best_is_plus_end
	var omit_start := not best_is_plus_end
	return {
		"transform": Transform3D(corner_basis, best_center),
		"omit_post_start": omit_start,
		"omit_post_end": omit_end,
	}


func _snap_platform_to_platform(moving: Platform, target: Platform) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Snap Platform to Platform")

	var best_transform: Transform3D = _compute_platform_to_platform_transform(moving, target, moving.global_transform)
	undo_redo.add_do_property(moving, "global_transform", best_transform)
	undo_redo.add_undo_property(moving, "global_transform", moving.global_transform)
	undo_redo.commit_action()


static func _compute_platform_to_platform_transform(moving: Platform, target: Platform, intent: Transform3D) -> Transform3D:
	var m_pos := intent.origin
	var current_basis := intent.basis
	var m_hl := moving.size.x / 2.0
	var m_hw := moving.size.z / 2.0

	var target_edges := _get_platform_edges(target)

	var m_edge_centers_local: Array[Vector3] = [
		Vector3(m_hl, 0, 0),
		Vector3(-m_hl, 0, 0),
		Vector3(0, 0, m_hw),
		Vector3(0, 0, -m_hw),
	]
	var m_edge_outwards_local: Array[Vector3] = [
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.BACK,
		Vector3.FORWARD,
	]

	var current_forward := _horizontal_dir(current_basis.x, Vector3.RIGHT)
	var current_yaw := atan2(current_forward.z, current_forward.x)
	var target_basis := target.global_transform.basis.orthonormalized()

	var best_transform := intent
	var best_cost := INF

	for te in target_edges:
		var t_seg_start: Vector3 = te[0]
		var t_seg_end: Vector3 = te[1]
		var t_outward: Vector3 = _horizontal_dir(te[2], Vector3.RIGHT)

		for me_idx in range(4):
			var local_outward := m_edge_outwards_local[me_idx]
			var desired_outward := -t_outward

			# Candidate orientation must be target-aligned in 90° steps.
			var best_basis_for_pair := target_basis
			var best_dot := -INF
			for k in range(4):
				var candidate_basis := target_basis * Basis(Vector3.UP, float(k) * (PI * 0.5))
				var out_world := _horizontal_dir(candidate_basis * local_outward, Vector3.RIGHT)
				var d := out_world.dot(desired_outward)
				if d > best_dot:
					best_dot = d
					best_basis_for_pair = candidate_basis

			var candidate_basis := best_basis_for_pair
			var rotated_center := candidate_basis * m_edge_centers_local[me_idx]
			var yaw := atan2(_horizontal_dir(candidate_basis.x, Vector3.RIGHT).z, _horizontal_dir(candidate_basis.x, Vector3.RIGHT).x)
			var center_guess := m_pos + rotated_center
			var closest := _closest_point_on_segment_xz(center_guess, t_seg_start, t_seg_end)

			var candidate_pos := closest - rotated_center
			candidate_pos.y = target.global_position.y

			var move_cost := Vector2(candidate_pos.x - m_pos.x, candidate_pos.z - m_pos.z).length()
			var rot_cost := absf(wrapf(yaw - current_yaw, -PI, PI))
			var total_cost := move_cost + rot_cost * 0.35
			if total_cost < best_cost:
				best_cost = total_cost
				best_transform = Transform3D(candidate_basis, candidate_pos)

	return best_transform
