@tool
class_name BeltPath
extends RefCounted

## Path geometry for a multi-segment belt conveyor. Lives in the conveyor's
## local X-Y plane; +Z is cross-belt. Tilt rotates around +Z.

class Run extends RefCounted:
	var start_xform: Transform3D
	## Straight length after fillet insets at both ends. May be ≤ 0 if fillets overlap.
	var effective_length: float
	var s_at_run_start: float

## Tangent-fillet arc joining run[i] to run[i+1].
class Joint extends RefCounted:
	var corner: Vector3
	var tangent_in: Vector3
	var tangent_out: Vector3
	## Signed; rotation around +Z from tangent_in to tangent_out.
	var turning_angle: float
	var radius: float
	## radius * tan(|turning_angle| / 2).
	var inset: float
	var center: Vector3
	var arc_length: float
	var s_at_arc_start: float
	var tangent_point_in: Vector3
	var tangent_point_out: Vector3

var segments: Array = []
var base_tilt_rad: float = 0.0
var runs: Array = []
## joints[i] joins runs[i] and runs[i+1]; size = runs.size() - 1.
var joints: Array = []
var top_surface_length: float = 0.0
## Top + bottom + pulley wraps. Valid only when pulley radii were supplied.
var loop_length: float = 0.0


## [param bend_radius] is the tangent-fillet radius for every joint. Pass at least
## the conveyor's belt height to keep convex bends from self-intersecting.
static func build(segments_in: Array, base_tilt_rad_in: float = 0.0,
		head_pulley_radius: float = 0.0, tail_pulley_radius: float = 0.0,
		bend_radius: float = 0.0) -> BeltPath:
	var p := BeltPath.new()
	p.segments = segments_in
	p.base_tilt_rad = base_tilt_rad_in
	p._compute(head_pulley_radius, tail_pulley_radius, bend_radius)
	return p


func _compute(head_pulley_radius: float, tail_pulley_radius: float,
		bend_radius: float = 0.0) -> void:
	runs.clear()
	joints.clear()
	top_surface_length = 0.0
	loop_length = 0.0
	if segments.is_empty():
		return

	var r: float = maxf(bend_radius, 0.0)
	var insets: Array = []
	insets.resize(segments.size())
	insets[0] = 0.0
	for i in range(1, segments.size()):
		var seg: BeltSegment = segments[i]
		if seg == null:
			insets[i] = 0.0
			continue
		var turn: float = deg_to_rad(seg.tilt_relative_deg)
		insets[i] = r * absf(tan(turn * 0.5)) if r > 0.0 else 0.0

	# tilt_relative_deg is "rotation relative to what came before"; for segment 0
	# the "before" is the path's base orientation. Leading nulls don't contribute.
	var corner_in := Vector3.ZERO
	var tilt: float = base_tilt_rad
	var first_non_null: int = -1
	for i in range(segments.size()):
		if segments[i] != null:
			first_non_null = i
			break
	if first_non_null >= 0:
		var seg_tilt: float = segments[first_non_null].tilt_relative_deg
		tilt += deg_to_rad(seg_tilt)
		if first_non_null > 0:
			insets[first_non_null] = 0.0
	var tangent := _tangent_for_tilt(tilt)
	var s: float = 0.0

	for i in range(segments.size()):
		var seg: BeltSegment = segments[i]
		if seg == null:
			# Zero-length placeholder keeps downstream indexing aligned.
			var placeholder := Run.new()
			placeholder.start_xform = Transform3D(_basis_for_tangent(tangent), corner_in)
			placeholder.effective_length = 0.0
			placeholder.s_at_run_start = s
			runs.append(placeholder)
			continue
		var inset_start: float = insets[i]
		var inset_end: float = insets[i + 1] if i + 1 < segments.size() else 0.0

		var run := Run.new()
		var run_start: Vector3 = corner_in + tangent * inset_start
		run.start_xform = Transform3D(_basis_for_tangent(tangent), run_start)
		run.effective_length = seg.length - inset_start - inset_end
		run.s_at_run_start = s
		runs.append(run)
		s += maxf(0.0, run.effective_length)

		if i + 1 >= segments.size():
			break

		# Walk past null entries to the next non-null for joint composition.
		var next_idx: int = -1
		for j in range(i + 1, segments.size()):
			if segments[j] != null:
				next_idx = j
				break
		if next_idx < 0:
			break
		var next_seg: BeltSegment = segments[next_idx]
		var turn: float = deg_to_rad(next_seg.tilt_relative_deg)
		var corner_out: Vector3 = corner_in + tangent * seg.length
		var next_tilt: float = tilt + turn
		var next_tangent: Vector3 = _tangent_for_tilt(next_tilt)

		if next_idx == i + 1:
			var jt := Joint.new()
			jt.corner = corner_out
			jt.tangent_in = tangent
			jt.tangent_out = next_tangent
			jt.turning_angle = turn
			jt.radius = r
			jt.inset = insets[next_idx]
			jt.tangent_point_in = corner_out - tangent * jt.inset
			jt.tangent_point_out = corner_out + next_tangent * jt.inset
			# Rotate tangent +90° around +Z, then push to the inside of the turn.
			var left_in := Vector3(-tangent.y, tangent.x, 0.0)
			var sign_turn: float = signf(turn)
			jt.center = jt.tangent_point_in + left_in * (sign_turn * r)
			jt.arc_length = r * absf(turn)
			jt.s_at_arc_start = s
			joints.append(jt)
			s += jt.arc_length
		else:
			insets[next_idx] = 0.0

		corner_in = corner_out
		tilt = next_tilt
		tangent = next_tangent

	top_surface_length = s
	loop_length = top_surface_length * 2.0 + PI * (head_pulley_radius + tail_pulley_radius)


## Sample the top surface at arc-length [param s_in]. Basis is (tangent, normal, cross).
func sample(s_in: float) -> Transform3D:
	if runs.is_empty():
		return Transform3D.IDENTITY
	var s: float = clampf(s_in, 0.0, top_surface_length)
	for i in range(runs.size()):
		var run: Run = runs[i]
		var run_len: float = maxf(0.0, run.effective_length)
		var run_end: float = run.s_at_run_start + run_len
		if s <= run_end + 1e-9:
			var local_x: float = s - run.s_at_run_start
			var pos: Vector3 = run.start_xform * Vector3(local_x, 0.0, 0.0)
			return Transform3D(run.start_xform.basis, pos)
		if i < joints.size():
			var jt: Joint = joints[i]
			var arc_end: float = jt.s_at_arc_start + jt.arc_length
			if s <= arc_end + 1e-9:
				var theta_unsigned: float = (s - jt.s_at_arc_start) / max(jt.radius, 1e-9)
				var theta: float = theta_unsigned * signf(jt.turning_angle)
				var rot := Basis(Vector3(0, 0, 1), theta)
				var to_start: Vector3 = jt.tangent_point_in - jt.center
				var pos: Vector3 = jt.center + rot * to_start
				var tan_at: Vector3 = (rot * jt.tangent_in).normalized()
				return Transform3D(_basis_for_tangent(tan_at), pos)
	var last: Run = runs[runs.size() - 1]
	var pos_end: Vector3 = last.start_xform * Vector3(maxf(0.0, last.effective_length), 0.0, 0.0)
	return Transform3D(last.start_xform.basis, pos_end)


func start_transform() -> Transform3D:
	return sample(0.0)


func end_transform() -> Transform3D:
	return sample(top_surface_length)


## Arc bounds including pulley wraps along the first/last run's tangent.
func arc_bounds(pulley_radius: float) -> Vector2:
	return Vector2(-pulley_radius, top_surface_length + pulley_radius)


## Closest point on the path to [param local_pos]. Returns {s, tangent, kind, index}
## or empty if the path is not built.
func closest_path_point(local_pos: Vector3, pulley_radius: float = 0.0) -> Dictionary:
	if runs.is_empty():
		return {}
	var last_index: int = runs.size() - 1
	var best_s: float = 0.0
	var best_tangent: Vector3 = Vector3.RIGHT
	var best_kind: StringName = &"run"
	var best_index: int = 0
	var best_dist: float = INF
	for i in range(runs.size()):
		var run: Run = runs[i]
		var run_inv: Transform3D = run.start_xform.affine_inverse()
		var pt_in_run: Vector3 = run_inv * local_pos
		var t_min: float = -pulley_radius if i == 0 else 0.0
		var t_max: float = run.effective_length + (pulley_radius if i == last_index else 0.0)
		var t_along: float = clampf(pt_in_run.x, t_min, t_max)
		var closest_local: Vector3 = run.start_xform * Vector3(t_along, 0.0, pt_in_run.z)
		var dist: float = local_pos.distance_to(closest_local)
		if dist < best_dist:
			best_dist = dist
			best_s = run.s_at_run_start + t_along
			best_tangent = run.start_xform.basis.x
			best_kind = &"run"
			best_index = i
	for j in range(joints.size()):
		var jt: Joint = joints[j]
		if jt.radius <= 0.0 or jt.arc_length <= 0.0:
			continue
		var to_pt: Vector3 = local_pos - jt.center
		var to_pt_xy: Vector2 = Vector2(to_pt.x, to_pt.y)
		if to_pt_xy.length_squared() < 1.0e-9:
			continue
		var to_start_v: Vector3 = jt.tangent_point_in - jt.center
		var to_start_xy: Vector2 = Vector2(to_start_v.x, to_start_v.y)
		var start_angle: float = atan2(to_start_xy.y, to_start_xy.x)
		var pt_angle: float = atan2(to_pt_xy.y, to_pt_xy.x)
		var sign_turn: float = signf(jt.turning_angle)
		var swept: float = absf(jt.turning_angle)
		var delta: float = pt_angle - start_angle
		if sign_turn < 0.0:
			delta = -delta
		while delta > PI:
			delta -= TAU
		while delta < -PI:
			delta += TAU
		delta = clampf(delta, 0.0, swept)
		var theta: float = sign_turn * delta
		var rot := Basis(Vector3(0, 0, 1), theta)
		var arc_pt: Vector3 = jt.center + rot * to_start_v
		var dist: float = local_pos.distance_to(arc_pt)
		if dist < best_dist:
			best_dist = dist
			best_s = jt.s_at_arc_start + delta * jt.radius
			best_tangent = (rot * jt.tangent_in).normalized()
			best_kind = &"joint"
			best_index = j
	if best_dist == INF:
		return {}
	return {"s": best_s, "tangent": best_tangent, "kind": best_kind, "index": best_index}


static func _tangent_for_tilt(tilt_rad: float) -> Vector3:
	return Vector3(cos(tilt_rad), sin(tilt_rad), 0.0)


static func _basis_for_tangent(tangent: Vector3) -> Basis:
	var x: Vector3 = tangent.normalized()
	var z := Vector3(0, 0, 1)
	var y: Vector3 = z.cross(x).normalized()
	return Basis(x, y, z)
