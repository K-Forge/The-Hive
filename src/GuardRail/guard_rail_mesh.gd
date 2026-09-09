@tool
class_name GuardRailMesh
extends RefCounted

## Origin at center-bottom of the railing run; extends along X, faces +Z.

const RAILING_HEIGHT: float = 1.07        # 42 inches OSHA standard
const MID_RAIL_HEIGHT: float = 0.54       # 21 inches OSHA standard
const TOE_BOARD_HEIGHT: float = 0.10      # 4 inches OSHA standard
const POST_SIZE: float = 0.04
const RAIL_SIZE: float = 0.032
## Keep under POST_SIZE/2 so the corner rail end stays hidden inside the post.
const CORNER_RAIL_EXT: float = RAIL_SIZE * 0.5
const MAX_POST_SPACING: float = 2.4       # 8 feet OSHA max

static var _metal_texture: Texture2D = preload("res://assets/3DModels/Textures/Metal.png")


static func create(length: float, height: float = RAILING_HEIGHT,
		omit_start_post: bool = false, omit_end_post: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var hl := length / 2.0
	var ps := POST_SIZE
	var rs := RAIL_SIZE
	var outward := Vector3(0, 0, 1)
	var tb_off := outward * (ps * 0.25)

	var mrh: float = height * (MID_RAIL_HEIGHT / RAILING_HEIGHT)
	var tbh: float = minf(TOE_BOARD_HEIGHT, height * 0.15)

	var num_spans := maxi(1, ceili(length / MAX_POST_SPACING))
	var span_length := length / float(num_spans)

	for span_idx in range(num_spans):
		var t0 := float(span_idx) * span_length
		var t1 := float(span_idx + 1) * span_length
		var sp0 := Vector3(-hl + t0, 0, 0)
		var sp1 := Vector3(-hl + t1, 0, 0)

		if not (span_idx == 0 and omit_start_post):
			_add_box_tube(verts, norms, uvs, indices,
				sp0, sp0 + Vector3(0, height, 0), ps)
		if span_idx == num_spans - 1 and not omit_end_post:
			_add_box_tube(verts, norms, uvs, indices,
				sp1, sp1 + Vector3(0, height, 0), ps)

		var rsp0 := sp0
		var rsp1 := sp1
		if span_idx == 0 and omit_start_post:
			rsp0 += Vector3(-CORNER_RAIL_EXT, 0, 0)
		if span_idx == num_spans - 1 and omit_end_post:
			rsp1 += Vector3(CORNER_RAIL_EXT, 0, 0)

		_add_box_tube(verts, norms, uvs, indices,
			rsp0 + Vector3(0, height, 0), rsp1 + Vector3(0, height, 0), rs)
		_add_box_tube(verts, norms, uvs, indices,
			rsp0 + Vector3(0, mrh, 0), rsp1 + Vector3(0, mrh, 0), rs)

		_add_quad(verts, norms, uvs, indices,
			rsp0 + tb_off, rsp1 + tb_off,
			rsp1 + tb_off + Vector3(0, tbh, 0), rsp0 + tb_off + Vector3(0, tbh, 0),
			outward)
		_add_quad(verts, norms, uvs, indices,
			rsp1 - tb_off, rsp0 - tb_off,
			rsp0 - tb_off + Vector3(0, tbh, 0), rsp1 - tb_off + Vector3(0, tbh, 0),
			-outward)

	if verts.is_empty():
		verts.append_array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		indices.append_array([0, 1, 2])

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/conveyor_frame_shader.gdshader")
	mat.set_shader_parameter("metal_texture", _metal_texture)
	mat.set_shader_parameter("color", Color(0.95, 0.74, 0.06))
	mat.set_shader_parameter("metallic_value", 0.0)
	mat.set_shader_parameter("roughness_value", 0.35)
	mat.set_shader_parameter("specular_value", 0.55)
	mat.set_shader_parameter("texture_influence", 0.5)
	return mat


static func _add_box_tube(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	from: Vector3, to: Vector3, tube_size: float
) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return
	dir = dir.normalized()

	var hs := tube_size / 2.0

	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var local_up := right.cross(dir).normalized()

	var offsets: Array[Vector3] = [
		-right * hs - local_up * hs,
		 right * hs - local_up * hs,
		 right * hs + local_up * hs,
		-right * hs + local_up * hs,
	]
	var face_normals: Array[Vector3] = [-local_up, right, local_up, -right]

	for face in range(4):
		var i0 := face
		var i1 := (face + 1) % 4
		var v0: Vector3 = from + offsets[i0]
		var v1: Vector3 = from + offsets[i1]
		var v2: Vector3 = to + offsets[i1]
		var v3: Vector3 = to + offsets[i0]
		var n: Vector3 = face_normals[face]
		var edge_len: float = offsets[i0].distance_to(offsets[i1])

		var base := verts.size()
		verts.append_array([v0, v1, v2, v3])
		norms.append_array([n, n, n, n])
		uvs.append_array([
			Vector2(0, 0), Vector2(edge_len, 0),
			Vector2(edge_len, length), Vector2(0, length)])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	_add_tube_cap(verts, norms, uvs, indices, from, offsets, -dir)
	_add_tube_cap(verts, norms, uvs, indices, to, offsets, dir)


static func _add_tube_cap(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	center: Vector3, offsets: Array[Vector3], normal: Vector3
) -> void:
	var base := verts.size()
	for offset: Vector3 in offsets:
		verts.append(center + offset)
		norms.append(normal)
		uvs.append(Vector2(offset.x, offset.z))
	if normal.dot(Vector3.UP) >= 0 and normal.dot(Vector3.FORWARD) >= 0:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	else:
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


static func _add_quad(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	normal: Vector3
) -> void:
	var base := verts.size()
	var w := v0.distance_to(v1)
	var h := v0.distance_to(v3)
	verts.append_array([v0, v1, v2, v3])
	norms.append_array([normal, normal, normal, normal])
	uvs.append_array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _pack_arrays(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
