@tool
class_name BeltConveyorMesh
extends RefCounted

## Belt conveyor surface mesh. Y=0 is belt top, Y=-height bottom.

const SEGMENTS: int = 16


static func create_belt(length: float, height: float, width: float,
		close_left: bool = false, close_right: bool = false,
		flat_left: bool = false, flat_right: bool = false,
		uv_y_left: float = 0.0, uv_y_right: float = 1.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var radius: float = height / 2.0
	var middle_length: float = length - 2.0 * radius
	var half_middle: float = middle_length / 2.0
	var half_width: float = width / 2.0
	var total_belt: float = 2.0 * PI * radius + 2.0 * middle_length

	var dist: float = 0.0

	var back_cx: float = -half_middle
	var back_cy: float = -radius
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var angle: float = PI * (1.0 - t)
		var x: float = back_cx - sin(angle) * radius
		var y: float = back_cy + cos(angle) * radius
		_add_pair(verts, norms, uvs, x, y, half_width, -sin(angle), cos(angle), (dist + t * PI * radius) / total_belt, uv_y_left, uv_y_right)
	_add_strip(indices, 0, SEGMENTS)
	dist += PI * radius

	var flat_top_base: int = verts.size()
	_add_pair(verts, norms, uvs, -half_middle, 0, half_width, 0, 1, dist / total_belt, uv_y_left, uv_y_right)
	_add_pair(verts, norms, uvs, half_middle, 0, half_width, 0, 1, (dist + middle_length) / total_belt, uv_y_left, uv_y_right)
	_add_strip(indices, flat_top_base, 1)
	dist += middle_length

	var front_cx: float = half_middle
	var front_cy: float = -radius
	var front_base: int = verts.size()
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var angle: float = PI * t
		var x: float = front_cx + sin(angle) * radius
		var y: float = front_cy + cos(angle) * radius
		_add_pair(verts, norms, uvs, x, y, half_width, sin(angle), cos(angle), (dist + t * PI * radius) / total_belt, uv_y_left, uv_y_right)
	_add_strip(indices, front_base, SEGMENTS)
	dist += PI * radius

	var bot_base: int = verts.size()
	_add_pair(verts, norms, uvs, half_middle, -height, half_width, 0, -1, dist / total_belt, uv_y_left, uv_y_right)
	_add_pair(verts, norms, uvs, -half_middle, -height, half_width, 0, -1, (dist + middle_length) / total_belt, uv_y_left, uv_y_right)
	_add_strip(indices, bot_base, 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if close_left or close_right:
		var side_verts := PackedVector3Array()
		var side_norms := PackedVector3Array()
		var side_uvs := PackedVector2Array()
		var side_indices := PackedInt32Array()

		var outline: Array[Vector2] = []
		for i in range(SEGMENTS + 1):
			var t: float = float(i) / SEGMENTS
			var angle: float = PI * (1.0 - t)
			outline.append(Vector2(back_cx - sin(angle) * radius, back_cy + cos(angle) * radius))
		outline.append(Vector2(half_middle, 0))
		for i in range(SEGMENTS + 1):
			var t: float = float(i) / SEGMENTS
			var angle: float = PI * t
			outline.append(Vector2(front_cx + sin(angle) * radius, front_cy + cos(angle) * radius))
		outline.append(Vector2(-half_middle, -height))

		var side_signs: Array[float] = []
		var side_flats: Array[bool] = []
		if close_left:
			side_signs.append(-1.0)
			side_flats.append(flat_left)
		if close_right:
			side_signs.append(1.0)
			side_flats.append(flat_right)
		for side_idx in range(side_signs.size()):
			var side_sign: float = side_signs[side_idx]
			var is_flat: bool = side_flats[side_idx]
			# Push flat walls outward to avoid z-fighting with the frame rail.
			var z_offset: float = ConveyorFrameMesh.WALL_THICKNESS / 2.0 if is_flat else 0.0
			var z: float = half_width * side_sign + z_offset * side_sign
			var n := Vector3(0, 0, side_sign)

			if is_flat:
				var hl: float = length / 2.0
				var sb: int = side_verts.size()
				side_verts.append(Vector3(-hl, 0, z))
				side_verts.append(Vector3(hl, 0, z))
				side_verts.append(Vector3(hl, -height, z))
				side_verts.append(Vector3(-hl, -height, z))
				side_norms.append_array([n, n, n, n])
				side_uvs.append_array([
					Vector2(0, 0), Vector2(length, 0),
					Vector2(length, height), Vector2(0, height),
				])
				if side_sign > 0:
					side_indices.append_array([sb, sb + 1, sb + 2, sb, sb + 2, sb + 3])
				else:
					side_indices.append_array([sb, sb + 2, sb + 1, sb, sb + 3, sb + 2])
			else:
				var center := Vector2(0, -radius)
				var fan_base: int = side_verts.size()
				side_verts.append(Vector3(center.x, center.y, z))
				side_norms.append(n)
				side_uvs.append(Vector2(0.5, 0.5))
				for p: Vector2 in outline:
					side_verts.append(Vector3(p.x, p.y, z))
					side_norms.append(n)
					side_uvs.append(Vector2(p.x, p.y))
				var point_count: int = outline.size()
				for i in range(point_count):
					var a: int = fan_base
					var b: int = fan_base + 1 + i
					var c: int = fan_base + 1 + (i + 1) % point_count
					if side_sign > 0:
						side_indices.append_array([a, b, c])
					else:
						side_indices.append_array([a, c, b])

		var side_arrays := []
		side_arrays.resize(Mesh.ARRAY_MAX)
		side_arrays[Mesh.ARRAY_VERTEX] = side_verts
		side_arrays[Mesh.ARRAY_NORMAL] = side_norms
		side_arrays[Mesh.ARRAY_TEX_UV] = side_uvs
		side_arrays[Mesh.ARRAY_INDEX] = side_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, side_arrays)

	return mesh


static func _add_pair(
	verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
	x: float, y: float, half_width: float,
	nx: float, ny: float, u: float,
	v_left: float = 0.0, v_right: float = 1.0,
) -> void:
	verts.append(Vector3(x, y, -half_width))
	norms.append(Vector3(nx, ny, 0))
	uvs.append(Vector2(u, v_left))

	verts.append(Vector3(x, y, half_width))
	norms.append(Vector3(nx, ny, 0))
	uvs.append(Vector2(u, v_right))


static func _add_strip(indices: PackedInt32Array, base: int, count: int) -> void:
	for i in range(count):
		var b: int = base + i * 2
		indices.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])


static func create_belt_from_path(path: BeltPath, height: float, width: float,
		close_left: bool = false, close_right: bool = false) -> ArrayMesh:
	assert(not (close_left or close_right), "create_belt_from_path: side walls not yet implemented")
	var mesh := ArrayMesh.new()
	if path == null or path.runs.is_empty():
		return mesh

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var radius: float = height / 2.0
	var half_w: float = width / 2.0
	var pulley_arc: float = PI * radius
	var top_len: float = path.top_surface_length
	var loop_len: float = 2.0 * top_len + 2.0 * pulley_arc
	if loop_len <= 0.0:
		return mesh

	var dist: float = 0.0

	var start_xform: Transform3D = path.start_transform()
	var end_xform: Transform3D = path.end_transform()

	var tail_base: int = verts.size()
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var phi: float = PI * (1.0 - t)
		var local_x: float = -sin(phi) * radius
		var local_y: float = -radius + cos(phi) * radius
		var pos: Vector3 = start_xform * Vector3(local_x, local_y, 0)
		var n: Vector3 = (start_xform.basis * Vector3(-sin(phi), cos(phi), 0)).normalized()
		var u: float = (dist + t * pulley_arc) / loop_len
		_add_pair_world(verts, norms, uvs, pos, n, start_xform.basis.z, half_w, u)
	_add_strip(indices, tail_base, SEGMENTS)
	dist += pulley_arc

	for i in range(path.runs.size()):
		var run: BeltPath.Run = path.runs[i]
		var run_len: float = maxf(0.0, run.effective_length)
		var run_base: int = verts.size()
		var n_run: Vector3 = run.start_xform.basis.y
		var z_run: Vector3 = run.start_xform.basis.z
		var p_a: Vector3 = run.start_xform.origin
		var p_b: Vector3 = run.start_xform * Vector3(run_len, 0, 0)
		_add_pair_world(verts, norms, uvs, p_a, n_run, z_run, half_w, dist / loop_len)
		_add_pair_world(verts, norms, uvs, p_b, n_run, z_run, half_w, (dist + run_len) / loop_len)
		_add_strip(indices, run_base, 1)
		dist += run_len

		if i < path.joints.size():
			var jt: BeltPath.Joint = path.joints[i]
			var arc_base: int = verts.size()
			for j in range(SEGMENTS + 1):
				var t: float = float(j) / SEGMENTS
				_emit_arc_pair(verts, norms, uvs, jt, t, height, half_w, dist, jt.arc_length, loop_len, false)
			_add_strip(indices, arc_base, SEGMENTS)
			dist += jt.arc_length

	var head_base: int = verts.size()
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var phi: float = PI * t
		var local_x: float = sin(phi) * radius
		var local_y: float = -radius + cos(phi) * radius
		var pos: Vector3 = end_xform * Vector3(local_x, local_y, 0)
		var n: Vector3 = (end_xform.basis * Vector3(sin(phi), cos(phi), 0)).normalized()
		var u: float = (dist + t * pulley_arc) / loop_len
		_add_pair_world(verts, norms, uvs, pos, n, end_xform.basis.z, half_w, u)
	_add_strip(indices, head_base, SEGMENTS)
	dist += pulley_arc

	for i in range(path.runs.size() - 1, -1, -1):
		var run: BeltPath.Run = path.runs[i]
		var run_len: float = maxf(0.0, run.effective_length)
		var run_base: int = verts.size()
		var n_top: Vector3 = run.start_xform.basis.y
		var n_bot: Vector3 = -n_top
		var z_run: Vector3 = run.start_xform.basis.z
		var top_end: Vector3 = run.start_xform * Vector3(run_len, 0, 0)
		var top_start: Vector3 = run.start_xform.origin
		var bot_end: Vector3 = top_end + n_bot * height
		var bot_start: Vector3 = top_start + n_bot * height
		_add_pair_world(verts, norms, uvs, bot_end, n_bot, z_run, half_w, dist / loop_len)
		_add_pair_world(verts, norms, uvs, bot_start, n_bot, z_run, half_w, (dist + run_len) / loop_len)
		_add_strip(indices, run_base, 1)
		dist += run_len

		if i > 0:
			var jt: BeltPath.Joint = path.joints[i - 1]
			var arc_base: int = verts.size()
			for j in range(SEGMENTS + 1):
				var t: float = float(j) / SEGMENTS
				_emit_arc_pair(verts, norms, uvs, jt, t, height, half_w, dist, jt.arc_length, loop_len, true)
			_add_strip(indices, arc_base, SEGMENTS)
			dist += jt.arc_length

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_pair_world(
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		pos: Vector3, normal: Vector3, z_axis: Vector3, half_w: float, u: float) -> void:
	verts.append(pos - z_axis * half_w)
	norms.append(normal)
	uvs.append(Vector2(u, 0))
	verts.append(pos + z_axis * half_w)
	norms.append(normal)
	uvs.append(Vector2(u, 1))


static func _emit_arc_pair(
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		jt: BeltPath.Joint, t: float, height: float, half_w: float,
		dist_at_arc_start: float, arc_length: float, loop_len: float, mirror_to_bottom: bool) -> void:
	var theta: float = (1.0 - t) * jt.turning_angle if mirror_to_bottom else t * jt.turning_angle
	var rot := Basis(Vector3(0, 0, 1), theta)
	var top_pos: Vector3 = jt.center + rot * (jt.tangent_point_in - jt.center)
	var top_norm: Vector3 = (signf(jt.turning_angle) * (jt.center - top_pos) / maxf(jt.radius, 1.0e-9)).normalized()
	var pos: Vector3 = top_pos
	var normal: Vector3 = top_norm
	if mirror_to_bottom:
		normal = -top_norm
		pos = top_pos + normal * height
	var u: float = (dist_at_arc_start + t * arc_length) / loop_len
	_add_pair_world(verts, norms, uvs, pos, normal, Vector3(0, 0, 1), half_w, u)
