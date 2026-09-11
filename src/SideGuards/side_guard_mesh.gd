@tool
class_name SideGuardMesh
extends RefCounted

## Procedural flat sideguard wall. Origin = bottom center of outer face.

const WALL_HEIGHT: float = 0.30
const WALL_THICKNESS: float = 0.005
const COLLISION_THICKNESS: float = 0.05

static var _metal_texture: Texture2D = preload("res://assets/3DModels/Textures/Metal.png")
static var _shared_material: ShaderMaterial


static func create(length: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half_l := length / 2.0
	var wt := WALL_THICKNESS
	var wh := WALL_HEIGHT

	# Overlap with the frame flange top.
	var y_bottom: float = -ConveyorFrameMesh.FLANGE_THICKNESS

	var profile := [
		Vector2(y_bottom, 0.0),
		Vector2(y_bottom, wt),
		Vector2(wh, wt),
		Vector2(wh, 0.0),
	]

	# Bottom face skipped to avoid z-fighting with the frame flange.
	var edge_normals := [
		Vector3.ZERO,
		Vector3(0, 0, 1),
		Vector3(0, 1, 0),
		Vector3(0, 0, -1),
	]

	for i in range(profile.size()):
		if edge_normals[i] == Vector3.ZERO:
			continue
		var j := (i + 1) % profile.size()
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[j]
		var n: Vector3 = edge_normals[i]

		var v0 := Vector3(half_l, p0.x, p0.y)
		var v1 := Vector3(half_l, p1.x, p1.y)
		var v2 := Vector3(-half_l, p1.x, p1.y)
		var v3 := Vector3(-half_l, p0.x, p0.y)

		var edge_len: float = p0.distance_to(p1)

		var base := verts.size()
		verts.append_array([v0, v1, v2, v3])
		norms.append_array([n, n, n, n])
		uvs.append_array([
			Vector2(0, 0),
			Vector2(0, edge_len),
			Vector2(length, edge_len),
			Vector2(length, 0),
		])
		indices.append_array([
			base, base + 1, base + 2,
			base, base + 2, base + 3,
		])

	_add_cap(verts, norms, uvs, indices, profile, half_l, Vector3(1, 0, 0))
	_add_cap(verts, norms, uvs, indices, profile, -half_l, Vector3(-1, 0, 0))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Curved sideguard along a bend joint. Pass `COLLISION_THICKNESS` as
## `wt_override` for a thick collision variant centered on the visual wall.
static func create_bend(joint: BeltPath.Joint, side_sign: float,
		half_w: float, segments: int = 8, wt_override: float = -1.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if joint == null:
		return mesh
	var radius: float = joint.radius
	var turning_angle: float = joint.turning_angle
	if radius <= 0.0 or absf(turning_angle) <= 1.0e-4 or segments < 1:
		return mesh

	var wt: float = wt_override if wt_override > 0.0 else WALL_THICKNESS
	# Centered on visual wall midline so collision overhangs equally inward/outward.
	var z_outer: float = WALL_THICKNESS * 0.5 - wt * 0.5
	var z_inner: float = WALL_THICKNESS * 0.5 + wt * 0.5
	var wt_rail: float = ConveyorFrameMesh.WALL_THICKNESS
	var ft: float = ConveyorFrameMesh.FLANGE_THICKNESS
	var wh: float = WALL_HEIGHT
	var y_bottom: float = -ft

	var profile: Array = [
		Vector2(y_bottom, z_outer),
		Vector2(y_bottom, z_inner),
		Vector2(wh, z_inner),
		Vector2(wh, z_outer),
	]
	# Bottom skipped — overlaps the flange.
	var edge_normals_2d: Array = [
		Vector2.ZERO,
		Vector2(0, 1),
		Vector2(1, 0),
		Vector2(0, -1),
	]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var sign_turn: float = signf(turning_angle)
	var cross_axis := Vector3(0, 0, 1)
	var arc_len: float = radius * absf(turning_angle)
	var sample_count: int = segments + 1

	var sample_top := PackedVector3Array()
	var sample_normal := PackedVector3Array()
	sample_top.resize(sample_count)
	sample_normal.resize(sample_count)
	for k in range(sample_count):
		var t: float = float(k) / segments
		var theta: float = t * turning_angle
		var rot := Basis(cross_axis, theta)
		var top_pos: Vector3 = joint.center + rot * (joint.tangent_point_in - joint.center)
		sample_top[k] = top_pos
		sample_normal[k] = (sign_turn * (joint.center - top_pos) / maxf(radius, 1.0e-9)).normalized()

	var reverse_winding: bool = side_sign > 0.0

	for s in range(segments):
		var sa: int = s + 1
		var sb: int = s
		var u_a: float = (float(sa) / segments) * arc_len
		var u_b: float = (float(sb) / segments) * arc_len
		for i in range(profile.size()):
			var en: Vector2 = edge_normals_2d[i]
			if en == Vector2.ZERO:
				continue
			var j: int = (i + 1) % profile.size()
			var p_i: Vector2 = profile[i]
			var p_j: Vector2 = profile[j]
			var v0: Vector3 = _bend_guard_vertex(sample_top[sa], sample_normal[sa], p_i, ft, half_w, wt_rail, side_sign, cross_axis)
			var v1: Vector3 = _bend_guard_vertex(sample_top[sa], sample_normal[sa], p_j, ft, half_w, wt_rail, side_sign, cross_axis)
			var v2: Vector3 = _bend_guard_vertex(sample_top[sb], sample_normal[sb], p_j, ft, half_w, wt_rail, side_sign, cross_axis)
			var v3: Vector3 = _bend_guard_vertex(sample_top[sb], sample_normal[sb], p_i, ft, half_w, wt_rail, side_sign, cross_axis)
			var n_a: Vector3 = (sample_normal[sa] * en.x + cross_axis * (-side_sign * en.y)).normalized()
			var n_b: Vector3 = (sample_normal[sb] * en.x + cross_axis * (-side_sign * en.y)).normalized()
			var edge_len: float = p_i.distance_to(p_j)
			var base: int = verts.size()
			verts.append_array([v0, v1, v2, v3])
			norms.append_array([n_a, n_a, n_b, n_b])
			uvs.append_array([
				Vector2(0, u_a),
				Vector2(edge_len, u_a),
				Vector2(edge_len, u_b),
				Vector2(0, u_b),
			])
			if reverse_winding:
				indices.append_array([
					base, base + 2, base + 1,
					base, base + 3, base + 2,
				])
			else:
				indices.append_array([
					base, base + 1, base + 2,
					base, base + 2, base + 3,
				])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _bend_guard_vertex(top: Vector3, normal: Vector3, p: Vector2,
		ft: float, half_w: float, wt_rail: float, side_sign: float, cross_axis: Vector3) -> Vector3:
	return top + normal * (ft + p.x) + cross_axis * (side_sign * (half_w + wt_rail - p.y))


## Shared material — per-instance beam cutouts via set_instance_shader_parameter.
static func create_material() -> ShaderMaterial:
	if _shared_material:
		return _shared_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/3DModels/Shaders/MetalShaderSideGuard.tres")
	mat.set_shader_parameter("metal_texture", _metal_texture)
	mat.set_shader_parameter("color_tint", Color(2.4, 2.4, 2.4))
	mat.set_shader_parameter("Metallic", 0.94)
	mat.set_shader_parameter("Roughness", 0.4)
	mat.set_shader_parameter("Specular", 0.5)
	_shared_material = mat
	return mat


static func _add_cap(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	profile: Array,
	x: float,
	normal: Vector3,
) -> void:
	var base := verts.size()
	for p: Vector2 in profile:
		verts.append(Vector3(x, p.x, p.y))
		norms.append(normal)
		uvs.append(Vector2(p.y, p.x))

	if normal.x > 0:
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return
