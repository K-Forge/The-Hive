@tool
class_name ConveyorSnapFeatures
extends RefCounted

## Generic snap-feature matcher. Parts opt in via [code]get_snap_features()[/code].

const DIVERTER_Y_OFFSET: float = 0.2
const DIVERTER_SIDE_OFFSET: float = 0.05
const BLADE_STOP_TARGET_LOCAL_Y: float = -0.188
const CHAIN_TRANSFER_TARGET_LOCAL_Y: float = -0.05
const SENSOR_GUARD_OFFSET: float = 0.02
const SENSOR_GUARD_LIFT: float = 0.06

enum Shape { POINT, SEGMENT, TRACK }


static func try_snap(
	selected: Node3D, target: Node3D, live_mode: bool = false,
	sel_features_in: Variant = null, tgt_features_in: Variant = null,
) -> Dictionary:
	var sel_features: Array = sel_features_in if sel_features_in != null else _features_of(selected)
	var tgt_features: Array = tgt_features_in if tgt_features_in != null else _features_of(target)
	if sel_features.is_empty() or tgt_features.is_empty():
		return {}

	if _has_kind(sel_features, &"straight_end_front") and _has_kind(tgt_features, &"straight_end_front"):
		return _align_straight_to_straight(selected, target, sel_features, tgt_features, live_mode)

	var best: Dictionary = {}
	var best_score: float = INF
	for sf in sel_features:
		for tf in tgt_features:
			if not _kinds_compatible(sf.kind, tf.kind):
				continue
			var score: float = _score_pair(selected, target, sf, tf)
			if score < best_score:
				best_score = score
				best = {"sel": sf, "tgt": tf}

	if best.is_empty():
		return {}

	return _align(selected, target, best.sel, best.tgt)


static func _features_of(node: Node3D) -> Array:
	if node.has_method(&"get_snap_features"):
		return node.get_snap_features()
	return _compute_features_for(node)


static func _has_kind(features: Array, kind: StringName) -> bool:
	for f in features:
		if f.kind == kind:
			return true
	return false


static func _find_by_kind(features: Array, kind: StringName) -> Dictionary:
	for f in features:
		if f.kind == kind:
			return f
	return {}


static func _find_closest_segment_by_kind(features: Array, kind: StringName,
		tgt_xform: Transform3D, point_world: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for f in features:
		if f.kind != kind:
			continue
		var seg_start_world: Vector3 = tgt_xform * (f.seg_start as Vector3)
		var seg_end_world: Vector3 = tgt_xform * (f.seg_end as Vector3)
		var closest: Vector3 = _closest_point_on_segment(point_world, seg_start_world, seg_end_world)
		var d: float = point_world.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best = f
	return best


static func _compute_features_for(node: Node3D) -> Array:
	if not (&"size" in node):
		return []
	var size: Vector3 = node.size
	var hw: float = size.z / 2.0
	# Reading local_bbox works for both origin-centered and origin-at-tail conveyors.
	var back_x: float = -size.x / 2.0
	var front_x: float = size.x / 2.0
	if &"local_bbox" in node:
		var bbox: AABB = node.local_bbox
		back_x = bbox.position.x
		front_x = bbox.end.x
	var features: Array = [
		{
			"shape": Shape.POINT,
			"kind": &"straight_end_front",
			"local_pos": Vector3(front_x, 0, 0),
			"local_outward": Vector3(1, 0, 0),
			"end_name": &"front",
		},
		{
			"shape": Shape.POINT,
			"kind": &"straight_end_back",
			"local_pos": Vector3(back_x, 0, 0),
			"local_outward": Vector3(-1, 0, 0),
			"end_name": &"back",
		},
		{
			"shape": Shape.SEGMENT,
			"kind": &"straight_sideguard_left",
			"seg_start": Vector3(back_x, 0, -hw),
			"seg_end": Vector3(front_x, 0, -hw),
			"seg_outward_local": Vector3(0, 0, -1),
		},
		{
			"shape": Shape.SEGMENT,
			"kind": &"straight_sideguard_right",
			"seg_start": Vector3(back_x, 0, hw),
			"seg_end": Vector3(front_x, 0, hw),
			"seg_outward_local": Vector3(0, 0, 1),
		},
	]

	# Phase the roller tracks (incl. grid anchor) onto the grid MultiMeshRollers uses.
	if node is RollerConveyor:
		var rd: float = (node as RollerConveyor).roller_pitch()
		var axis_w: Vector3 = node.global_transform.basis.x
		var axis_len: float = axis_w.length()
		var on_phase: float = 0.0
		if axis_len > 1e-6:
			var axis_norm: Vector3 = axis_w / axis_len
			var anchor: Vector3 = Vector3.ZERO
			var anchor_var: Variant = (node as RollerConveyor).get_roller_grid_anchor()
			if anchor_var is Vector3:
				anchor = anchor_var
			on_phase = fposmod((anchor - node.global_transform.origin).dot(axis_norm), rd)
		var gap_phase: float = on_phase + rd / 2.0
		var track_x_min: float = back_x + AbstractRollerContainer.ROLLERS_START_OFFSET
		var track_x_max: float = front_x - AbstractRollerContainer.ROLLERS_START_OFFSET
		features.append({
			"shape": Shape.TRACK,
			"kind": &"roller_gap_track",
			"axis_local": Vector3(1, 0, 0),
			"phase": gap_phase,
			"step": rd,
			"x_min": track_x_min,
			"x_max": track_x_max,
		})
		features.append({
			"shape": Shape.TRACK,
			"kind": &"roller_on_track",
			"axis_local": Vector3(1, 0, 0),
			"phase": on_phase,
			"step": rd,
			"x_min": track_x_min,
			"x_max": track_x_max,
		})
	return features


static func _kinds_compatible(sel_kind: StringName, tgt_kind: StringName) -> bool:
	if sel_kind == &"diverter_push_side":
		return tgt_kind == &"straight_sideguard_left" or tgt_kind == &"straight_sideguard_right"
	if sel_kind == &"sensor_beam_mount":
		return tgt_kind == &"straight_sideguard_left" or tgt_kind == &"straight_sideguard_right"
	if sel_kind == &"blade_anchor":
		return tgt_kind == &"roller_gap_track"
	if sel_kind == &"chain_transfer_anchor_gap":
		return tgt_kind == &"roller_gap_track"
	if sel_kind == &"chain_transfer_anchor_on":
		return tgt_kind == &"roller_on_track"
	return false


static func _score_pair(selected: Node3D, target: Node3D, sf: Dictionary, tf: Dictionary) -> float:
	if tf.shape == Shape.SEGMENT:
		var seg_start_world: Vector3 = target.global_transform * (tf.seg_start as Vector3)
		var seg_end_world: Vector3 = target.global_transform * (tf.seg_end as Vector3)
		var sel_origin: Vector3 = ConveyorSnapping.get_selected_xform(selected).origin
		var contact: Vector3 = _closest_point_on_segment(sel_origin, seg_start_world, seg_end_world)
		return sel_origin.distance_to(contact)
	if tf.shape == Shape.TRACK:
		var anchor_world: Vector3 = ConveyorSnapping.get_selected_xform(selected) * (sf.local_pos as Vector3)
		var anchor_local: Vector3 = target.global_transform.affine_inverse() * anchor_world
		var perp: Vector2 = Vector2(anchor_local.y, anchor_local.z)
		return perp.length()
	return INF


static func _align(selected: Node3D, target: Node3D, sf: Dictionary, tf: Dictionary) -> Dictionary:
	if sf.shape == Shape.POINT and tf.shape == Shape.SEGMENT:
		return _align_point_to_segment(selected, target, sf, tf)
	if sf.shape == Shape.POINT and tf.shape == Shape.TRACK:
		return _align_point_to_track(selected, target, sf, tf)
	return {}


static func _align_point_to_segment(selected: Node3D, target: Node3D, sf: Dictionary, tf: Dictionary) -> Dictionary:
	var target_xform: Transform3D = target.global_transform
	var seg_start_world: Vector3 = target_xform * tf.seg_start
	var seg_end_world: Vector3 = target_xform * tf.seg_end
	var contact: Vector3 = _closest_point_on_segment(
		ConveyorSnapping.get_selected_xform(selected).origin, seg_start_world, seg_end_world
	)
	contact = _surface_contact(target, target_xform, contact)

	var side_sign: float = signf(tf.seg_outward_local.z)
	if side_sign == 0.0:
		side_sign = 1.0

	# Orthonormal orientation: local +Z faces outward from the target's side.
	# Flip both X and Z (180° around Y); Z alone would invert Y.
	var orient: Basis = Basis()
	orient.x = side_sign * target_xform.basis.x.normalized()
	orient.z = side_sign * target_xform.basis.z.normalized()
	orient.y = target_xform.basis.y.normalized()
	# Sensors mount facing inward so the beam (local +Z) shoots across the conveyor.
	if sf.get(&"face_inward", false):
		orient.x = -orient.x
		orient.z = -orient.z

	# Carry the part's own scale; the basis only sets orientation.
	var sel_scale: Vector3 = selected.scale
	var new_basis: Basis = Basis(orient.x * sel_scale.x, orient.y * sel_scale.y, orient.z * sel_scale.z)

	var origin: Vector3 = contact - new_basis * (sf.local_pos as Vector3)
	var y_offset: float = float(sf.get(&"y_offset", 0.0))
	origin -= orient.y * y_offset
	var outward_offset: float = float(sf.get(&"outward_offset", 0.0))
	if outward_offset != 0.0:
		var outward_world: Vector3 = (target_xform.basis * (tf.seg_outward_local as Vector3)).normalized()
		origin += outward_world * outward_offset

	var snap_transform: Transform3D = Transform3D(new_basis, origin)

	var contact_local: Vector3 = target_xform.affine_inverse() * contact
	var snapped_end: Dictionary = {
		"pos": sf.local_pos,
		"outward": sf.local_outward,
		"name": sf.get(&"end_name", &"feature"),
	}
	var target_end: Dictionary = {
		"pos": contact_local,
		"outward": Vector3(0, 0, side_sign),
		"name": (&"left_side" if side_sign < 0.0 else &"right_side"),
	}
	var end_names: Array = [&"front", &"back", &"head", &"tail"]
	var result: Dictionary = {
		"transform": snap_transform,
		"snapped_end": snapped_end,
		"target_end": target_end,
		"is_end_to_end": snapped_end.name in end_names and target_end.name in end_names,
	}
	# Fit the beam so it spans the belt and just reaches the far side guard.
	# Half-width is the contact's offset from the conveyor centerline along its Z axis.
	if sf.get(&"auto_fit_range", false):
		var tgt_z: Vector3 = target_xform.basis.z.normalized()
		var half_width: float = absf((contact - target_xform.origin).dot(tgt_z))
		result["property_overrides"] = {"max_range": 2.0 * half_width + 2.0 * outward_offset}
	if sf.has(&"visible_threshold"):
		result["visible_threshold"] = sf.visible_threshold
	return result


static func _align_point_to_track(selected: Node3D, target: Node3D, sf: Dictionary, tf: Dictionary) -> Dictionary:
	var target_xform: Transform3D = target.global_transform
	var local_pos: Vector3 = sf.local_pos
	var local_basis_rotation: Basis = sf.get(&"local_basis_rotation", Basis())
	var step: float = tf.step
	var track_extent: float = float(sf.get(&"track_extent", 0.0))

	var override_props: Dictionary = {}
	if sf.has(&"match_step_property"):
		override_props[String(sf.match_step_property)] = step
		if sf.has(&"step_array_count"):
			var center_off: float = float(int(sf.step_array_count) - 1) * step / 2.0
			local_pos = Vector3(center_off, local_pos.y, local_pos.z)
			track_extent = center_off

	var anchor_world: Vector3 = ConveyorSnapping.get_selected_xform(selected) * local_pos
	var anchor_local: Vector3 = target_xform.affine_inverse() * anchor_world

	var axis: Vector3 = (tf.axis_local as Vector3).normalized()
	var phase: float = tf.phase
	var x_min: float = tf.x_min + track_extent
	var x_max: float = tf.x_max - track_extent

	var anchor_axis: float = anchor_local.dot(axis)
	var n: int = roundi((anchor_axis - phase) / step)
	var n_min: int = ceili((x_min - phase) / step)
	var n_max: int = floori((x_max - phase) / step)
	if n_max >= n_min:
		n = clampi(n, n_min, n_max)
	var snapped_axis: float = phase + float(n) * step

	var target_local_y: float = float(sf.get(&"target_local_y", 0.0))
	var anchor_target_local: Vector3 = axis * snapped_axis + Vector3(0, target_local_y, 0)
	var rotated_local_pos: Vector3 = local_basis_rotation * local_pos
	var origin_target_local: Vector3 = anchor_target_local - rotated_local_pos
	var origin_world: Vector3 = target_xform * origin_target_local

	var tgt_basis: Basis = target_xform.basis.orthonormalized() * local_basis_rotation
	var sel_scale: Vector3 = selected.scale
	# Auto-fit Z to target belt width; native_z_width is the part's extent at scale.z=1.
	if sf.get(&"auto_fit_target_width", false) and &"size" in target:
		var native_z_width: float = float(sf.get(&"native_z_width", 1.0))
		if native_z_width > 0.0:
			var target_z: float = (target.size as Vector3).z
			sel_scale.z = target_z / native_z_width
	var new_basis: Basis = Basis(
		tgt_basis.x * sel_scale.x,
		tgt_basis.y * sel_scale.y,
		tgt_basis.z * sel_scale.z,
	)

	# On-top attachments: no snapped_end / target_end, so guard-opening doesn't apply.
	var result: Dictionary = {
		"transform": Transform3D(new_basis, origin_world),
		"is_end_to_end": false,
	}
	# Scale is a side effect: fork orthonormalizes the returned basis on drop hover.
	if sf.get(&"auto_fit_target_width", false):
		result["scale"] = sel_scale
	if not override_props.is_empty():
		result["property_overrides"] = override_props
	if sf.has(&"visible_threshold"):
		result["visible_threshold"] = sf.visible_threshold
	return result


static func _align_straight_to_straight(
	selected: Node3D, target: Node3D,
	sel_features: Array, tgt_features: Array,
	live_mode: bool = false
) -> Dictionary:
	var sel_xform: Transform3D = ConveyorSnapping.get_selected_xform(selected)
	var tgt_xform: Transform3D = target.global_transform
	var sel_origin: Vector3 = sel_xform.origin

	var tgt_front: Dictionary = _find_by_kind(tgt_features, &"straight_end_front")
	var tgt_back: Dictionary = _find_by_kind(tgt_features, &"straight_end_back")
	# Multi-segment belts expose one side-guard segment per run; pick the closest.
	var tgt_left: Dictionary = _find_closest_segment_by_kind(tgt_features, &"straight_sideguard_left", tgt_xform, sel_origin)
	var tgt_right: Dictionary = _find_closest_segment_by_kind(tgt_features, &"straight_sideguard_right", tgt_xform, sel_origin)
	var sel_front: Dictionary = _find_by_kind(sel_features, &"straight_end_front")
	var sel_back: Dictionary = _find_by_kind(sel_features, &"straight_end_back")
	if tgt_front.is_empty() or tgt_back.is_empty() or sel_front.is_empty() or sel_back.is_empty():
		return {}
	if tgt_left.is_empty() or tgt_right.is_empty():
		return {}

	var tgt_front_world: Vector3 = tgt_xform * (tgt_front.local_pos as Vector3)
	var tgt_back_world: Vector3 = tgt_xform * (tgt_back.local_pos as Vector3)
	var left_start_world: Vector3 = tgt_xform * (tgt_left.seg_start as Vector3)
	var left_end_world: Vector3 = tgt_xform * (tgt_left.seg_end as Vector3)
	var right_start_world: Vector3 = tgt_xform * (tgt_right.seg_start as Vector3)
	var right_end_world: Vector3 = tgt_xform * (tgt_right.seg_end as Vector3)
	# Use closest-point-on-segment so long segments aren't penalized vs short ones.
	var left_closest: Vector3 = _closest_point_on_segment(sel_origin, left_start_world, left_end_world)
	var right_closest: Vector3 = _closest_point_on_segment(sel_origin, right_start_world, right_end_world)

	var dist_front: float = sel_origin.distance_to(tgt_front_world)
	var dist_back: float = sel_origin.distance_to(tgt_back_world)
	var dist_left: float = sel_origin.distance_to(left_closest)
	var dist_right: float = sel_origin.distance_to(right_closest)

	# Prefer the mode that preserves facing unless the other is much closer.
	var sel_forward: Vector3 = sel_xform.basis.x.normalized()
	var tgt_forward: Vector3 = tgt_xform.basis.x.normalized()
	var dot_product: float = absf(sel_forward.dot(tgt_forward))
	var is_perpendicular: bool = dot_product < 0.7

	var min_side: float = minf(dist_left, dist_right)
	var min_end: float = minf(dist_front, dist_back)
	var min_distance: float
	if is_perpendicular:
		if min_end < 0.5 and min_end < min_side * 0.2:
			min_distance = min_end
		else:
			min_distance = min_side
	else:
		if min_side < 0.5 and min_side < min_end * 0.2:
			min_distance = min_side
		else:
			min_distance = min_end

	var sel_inclination: float = _z_inclination(sel_xform)
	# Feature-supplied positions cover both origin-centered and origin-at-tail conveyors.
	var sel_back_pos: Vector3 = sel_back.local_pos
	var sel_front_pos: Vector3 = sel_front.local_pos
	var sel_back_outward: Vector3 = sel_back.get(&"local_outward", Vector3(-1, 0, 0))
	var sel_front_outward: Vector3 = sel_front.get(&"local_outward", Vector3(1, 0, 0))

	var snap_transform: Transform3D = Transform3D()
	var snapped_end: Dictionary = {}
	var target_end: Dictionary = {}

	if min_distance == dist_front:
		var new_basis: Basis = _apply_inclination(tgt_xform.basis, sel_inclination)
		snap_transform.basis = new_basis
		snap_transform.origin = tgt_front_world - new_basis * sel_back_pos
		snapped_end = {"pos": sel_back_pos, "outward": sel_back_outward, "name": &"back"}
		target_end = {"pos": tgt_front.local_pos, "outward": Vector3(1, 0, 0), "name": &"front"}
	elif min_distance == dist_back:
		var new_basis: Basis = _apply_inclination(tgt_xform.basis, sel_inclination)
		snap_transform.basis = new_basis
		snap_transform.origin = tgt_back_world - new_basis * sel_front_pos
		snapped_end = {"pos": sel_front_pos, "outward": sel_front_outward, "name": &"front"}
		target_end = {"pos": tgt_back.local_pos, "outward": Vector3(-1, 0, 0), "name": &"back"}
	elif min_distance == dist_left:
		var contact: Vector3 = _closest_point_on_segment(sel_origin, left_start_world, left_end_world)
		contact = _surface_contact(target, tgt_xform, contact)
		# Pick the closer end so dragging tail-first doesn't flip the conveyor.
		var sel_front_world: Vector3 = sel_xform * sel_front_pos
		var sel_back_world: Vector3 = sel_xform * sel_back_pos
		var use_front: bool = sel_front_world.distance_to(contact) <= sel_back_world.distance_to(contact)
		var sel_end_pos: Vector3 = sel_front_pos if use_front else sel_back_pos
		var sel_end_outward: Vector3 = sel_front_outward if use_front else sel_back_outward
		var sel_end_name: StringName = &"front" if use_front else &"back"
		# Basis is chosen so the conveyor body extends OUTWARD from the target.
		var perp_basis: Basis = Basis()
		if use_front:
			perp_basis.x = tgt_xform.basis.z
			perp_basis.z = -tgt_xform.basis.x
		else:
			perp_basis.x = -tgt_xform.basis.z
			perp_basis.z = tgt_xform.basis.x
		perp_basis.y = tgt_xform.basis.y
		var new_basis: Basis = _apply_inclination(perp_basis, sel_inclination)
		snap_transform.basis = new_basis
		snap_transform.origin = contact - new_basis * sel_end_pos
		# Y tracks the contact so elevated segments (Z-frame top, walk-thru hump) work.
		snap_transform.origin.y = contact.y
		var contact_local: Vector3 = tgt_xform.affine_inverse() * contact
		snapped_end = {"pos": sel_end_pos, "outward": sel_end_outward, "name": sel_end_name}
		target_end = {"pos": contact_local, "outward": Vector3(0, 0, -1), "name": &"left_side"}
	else:
		var contact: Vector3 = _closest_point_on_segment(sel_origin, right_start_world, right_end_world)
		contact = _surface_contact(target, tgt_xform, contact)
		var sel_front_world: Vector3 = sel_xform * sel_front_pos
		var sel_back_world: Vector3 = sel_xform * sel_back_pos
		var use_front: bool = sel_front_world.distance_to(contact) <= sel_back_world.distance_to(contact)
		var sel_end_pos: Vector3 = sel_front_pos if use_front else sel_back_pos
		var sel_end_outward: Vector3 = sel_front_outward if use_front else sel_back_outward
		var sel_end_name: StringName = &"front" if use_front else &"back"
		var perp_basis: Basis = Basis()
		if use_front:
			perp_basis.x = -tgt_xform.basis.z
			perp_basis.z = tgt_xform.basis.x
		else:
			perp_basis.x = tgt_xform.basis.z
			perp_basis.z = -tgt_xform.basis.x
		perp_basis.y = tgt_xform.basis.y
		var new_basis: Basis = _apply_inclination(perp_basis, sel_inclination)
		snap_transform.basis = new_basis
		snap_transform.origin = contact - new_basis * sel_end_pos
		snap_transform.origin.y = contact.y
		var contact_local: Vector3 = tgt_xform.affine_inverse() * contact
		snapped_end = {"pos": sel_end_pos, "outward": sel_end_outward, "name": sel_end_name}
		target_end = {"pos": contact_local, "outward": Vector3(0, 0, 1), "name": &"right_side"}

	# Flow-flip and no-op flip apply to end-to-end snaps only.
	# Side snaps' basis is geometrically determined to keep the body OUTSIDE the target.
	var is_side_snap: bool = target_end.name == &"left_side" or target_end.name == &"right_side"
	if not is_side_snap:
		# Flow-flip: rotate 180° around Y if forward direction inverted.
		if sel_xform.basis.x.dot(snap_transform.basis.x) < 0.0:
			var flipped: Array = _flip_around_local_y(snap_transform, snapped_end)
			snap_transform = flipped[0]
			snapped_end = flipped[1]

		# No-op flip: visible feedback when snap matches current pose. Suppressed in live (oscillates).
		if not live_mode:
			var current: Transform3D = sel_xform
			if current.origin.distance_to(snap_transform.origin) < 0.01 and current.basis.x.dot(snap_transform.basis.x) > 0.999:
				var flipped: Array = _flip_around_local_y(snap_transform, snapped_end)
				snap_transform = flipped[0]
				snapped_end = flipped[1]

	var end_names: Array = [&"front", &"back", &"head", &"tail"]
	return {
		"transform": snap_transform,
		"snapped_end": snapped_end,
		"target_end": target_end,
		"is_end_to_end": snapped_end.name in end_names and target_end.name in end_names,
	}


static func _conveyor_size_x(node: Node3D) -> float:
	if &"size" in node:
		return (node.size as Vector3).x
	return 4.0


static func _z_inclination(xform: Transform3D) -> float:
	var forward: Vector3 = xform.basis.x.normalized()
	return atan2(forward.y, Vector2(forward.x, forward.z).length())


static func _apply_inclination(basis: Basis, inclination: float) -> Basis:
	var horizontal_forward: Vector3 = Vector3(basis.x.x, 0, basis.x.z).normalized()
	var horizontal_right: Vector3 = Vector3(basis.z.x, 0, basis.z.z).normalized()
	var inclined_forward: Vector3 = horizontal_forward * cos(inclination) + Vector3.UP * sin(inclination)
	var new_basis: Basis = Basis()
	new_basis.x = inclined_forward
	new_basis.z = horizontal_right
	new_basis.y = new_basis.z.cross(new_basis.x).normalized()
	return new_basis


static func _flip_around_local_y(snap_transform: Transform3D, snapped_end: Dictionary) -> Array:
	var flipped_transform: Transform3D = snap_transform
	flipped_transform.basis = Basis(-snap_transform.basis.x, snap_transform.basis.y, -snap_transform.basis.z)
	var name_map: Dictionary = {&"front": &"back", &"back": &"front"}
	var new_name: StringName = name_map.get(snapped_end.name, snapped_end.name)
	var flipped_end: Dictionary = {
		"pos": -(snapped_end.pos as Vector3),
		"outward": -(snapped_end.outward as Vector3),
		"name": new_name,
	}
	return [flipped_transform, flipped_end]


static func _surface_contact(target: Node3D, target_xform: Transform3D, contact: Vector3) -> Vector3:
	if not target.has_method(&"snap_surface_y"):
		return contact
	var c_local: Vector3 = target_xform.affine_inverse() * contact
	c_local.y = target.call(&"snap_surface_y", c_local.x)
	return target_xform * c_local


static func _closest_point_on_segment(point: Vector3, line_start: Vector3, line_end: Vector3) -> Vector3:
	var line_vector: Vector3 = line_end - line_start
	var line_length_squared: float = line_vector.length_squared()
	if line_length_squared == 0.0:
		return line_start
	var t: float = (point - line_start).dot(line_vector) / line_length_squared
	t = clampf(t, 0.0, 1.0)
	return line_start + t * line_vector
