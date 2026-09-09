@tool
class_name BeltPathCollision
extends RefCounted

## Collision layout for a path-based belt conveyor. Straight runs become boxes;
## bend arcs become a chain of convex prisms tangent to the arc.

class BoxDescriptor extends RefCounted:
	var size: Vector3
	## Non-empty for bend prisms; consumer uses a [ConvexPolygonShape3D] instead of a box.
	var convex_points: PackedVector3Array
	## Body transform in path-local space. Basis = surface frame (x tangent, y normal, z cross-belt).
	var local_xform: Transform3D
	var tangent: Vector3
	var run_index: int


const BEND_SUBDIVISIONS: int = 4


static func build(path: BeltPath, height: float, width: float,
		min_length: float = 0.001) -> Array:
	var out: Array = []
	if path == null or path.runs.is_empty() or path.segments.is_empty() \
			or height <= 0.0 or width <= 0.0:
		return out
	# Extend end runs by pulley radius so cargo on the wrap-around has a surface.
	var pulley_radius: float = height * 0.5
	var last_run_index: int = path.runs.size() - 1
	for i in range(path.runs.size()):
		var run: BeltPath.Run = path.runs[i]
		var run_len: float = run.effective_length
		if run_len <= min_length:
			continue
		var ext_back: float = pulley_radius if i == 0 else 0.0
		var ext_front: float = pulley_radius if i == last_run_index else 0.0
		var box_len: float = run_len + ext_back + ext_front
		var center_local := Vector3(box_len * 0.5 - ext_back, -height * 0.5, 0.0)
		var d := BoxDescriptor.new()
		d.size = Vector3(box_len, height, width)
		d.local_xform = Transform3D(run.start_xform.basis, run.start_xform * center_local)
		d.tangent = run.start_xform.basis.x
		d.run_index = i
		out.append(d)
	# Bend arcs: convex prisms with end caps perpendicular to the arc tangent,
	# shifted by ±sagitta so the top face is tangent to the arc midpoint.
	# `run_index = -joint_index - 1` distinguishes bend bodies from runs.
	var cross_axis := Vector3(0, 0, 1)
	for ji in range(path.joints.size()):
		var jt: BeltPath.Joint = path.joints[ji]
		if jt.radius <= 0.0 or absf(jt.turning_angle) <= 1.0e-4:
			continue
		var sign_turn: float = signf(jt.turning_angle)
		var to_start: Vector3 = jt.tangent_point_in - jt.center
		var sub_angle: float = jt.turning_angle / float(BEND_SUBDIVISIONS)
		var sagitta: float = jt.radius * (1.0 - cos(sub_angle * 0.5))
		for k in range(BEND_SUBDIVISIONS):
			var ang_back: float = float(k) / BEND_SUBDIVISIONS * jt.turning_angle
			var ang_front: float = float(k + 1) / BEND_SUBDIVISIONS * jt.turning_angle
			var ang_mid: float = (ang_back + ang_front) * 0.5
			var rot_mid := Basis(cross_axis, ang_mid)
			var pos_mid: Vector3 = jt.center + rot_mid * to_start
			var tangent_mid: Vector3 = (rot_mid * jt.tangent_in).normalized()
			var normal_mid: Vector3 = (sign_turn * (jt.center - pos_mid) / maxf(jt.radius, 1.0e-9)).normalized()
			var sag_offset: Vector3 = sign_turn * normal_mid * sagitta
			var body_basis := Basis(tangent_mid, normal_mid, cross_axis)
			var body_origin: Vector3 = pos_mid - normal_mid * (height * 0.5) - sag_offset
			var body_xform := Transform3D(body_basis, body_origin)
			var body_inv := body_xform.affine_inverse()
			var convex_points := PackedVector3Array()
			for ang: float in [ang_back, ang_front]:
				var rot_b := Basis(cross_axis, ang)
				var pos_b: Vector3 = jt.center + rot_b * to_start
				var normal_b: Vector3 = (sign_turn * (jt.center - pos_b) / maxf(jt.radius, 1.0e-9)).normalized()
				for sign_z: float in [-1.0, 1.0]:
					var top_pt: Vector3 = pos_b + cross_axis * (sign_z * width * 0.5) - sag_offset
					var bot_pt: Vector3 = pos_b - normal_b * height + cross_axis * (sign_z * width * 0.5) - sag_offset
					convex_points.append(body_inv * top_pt)
					convex_points.append(body_inv * bot_pt)
			var d := BoxDescriptor.new()
			d.convex_points = convex_points
			d.local_xform = body_xform
			d.tangent = tangent_mid
			d.run_index = -ji - 1
			out.append(d)
	return out
