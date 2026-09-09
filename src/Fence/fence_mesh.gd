@tool
class_name FenceMesh
extends RefCounted


const FENCE_HEIGHT: float = 2.0
const POST_SIZE: float = 0.06
const FRAME_SIZE: float = 0.03
const WIRE_SIZE: float = 0.008
const MESH_SPACING: float = 0.1
const MAX_POST_SPACING: float = 1.5
const CAP_HEIGHT: float = 0.03
const CAP_FOOTPRINT: float = POST_SIZE * 1.08

static var _metal_texture: Texture2D = preload("res://assets/3DModels/Textures/Metal.png")


## Surface 0 = yellow posts; surface 1 = black mesh assembly (frames, wire, caps).
static func create(length: float, height: float = FENCE_HEIGHT,
		omit_start_post: bool = false, omit_end_post: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	var pi := PackedInt32Array()

	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wu := PackedVector2Array()
	var wi := PackedInt32Array()

	var hl := length / 2.0
	var inset: float = minf(0.08, height * 0.1)
	var frame_bottom := inset
	var frame_top := height - inset

	var num_spans := maxi(1, ceili(length / MAX_POST_SPACING))
	var span_length := length / float(num_spans)

	var post_xs := PackedFloat32Array()
	for i in range(num_spans + 1):
		post_xs.append(-hl + float(i) * span_length)
	var last := post_xs.size() - 1

	for i in range(post_xs.size()):
		if (i == 0 and omit_start_post) or (i == last and omit_end_post):
			continue
		_add_box_tube(pv, pn, pu, pi,
			Vector3(post_xs[i], 0, 0), Vector3(post_xs[i], height, 0), POST_SIZE)

	var margin: float = POST_SIZE * 0.5 + 0.01
	for span_idx in range(num_spans):
		var xa := post_xs[span_idx] + margin
		var xb := post_xs[span_idx + 1] - margin
		if xb <= xa:
			continue
		_add_panel(wv, wn, wu, wi, xa, xb, frame_bottom, frame_top)

	for i in range(post_xs.size()):
		if (i == 0 and omit_start_post) or (i == last and omit_end_post):
			continue
		_add_box(wv, wn, wu, wi,
			Vector3(post_xs[i], height, 0),
			Vector3(CAP_FOOTPRINT, CAP_HEIGHT, CAP_FOOTPRINT))

	_add_surface(mesh, pv, pn, pu, pi)
	_add_surface(mesh, wv, wn, wu, wi)
	return mesh


static func _add_panel(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	xa: float, xb: float, yb: float, yt: float
) -> void:
	# Panel frame is part of the black mesh assembly, not the yellow posts.
	_add_box_tube(verts, norms, uvs, indices, Vector3(xa, yb, 0), Vector3(xb, yb, 0), FRAME_SIZE)
	_add_box_tube(verts, norms, uvs, indices, Vector3(xa, yt, 0), Vector3(xb, yt, 0), FRAME_SIZE)
	_add_box_tube(verts, norms, uvs, indices, Vector3(xa, yb, 0), Vector3(xa, yt, 0), FRAME_SIZE)
	_add_box_tube(verts, norms, uvs, indices, Vector3(xb, yb, 0), Vector3(xb, yt, 0), FRAME_SIZE)

	var width := xb - xa
	var height := yt - yb

	var cols := maxi(1, roundi(width / MESH_SPACING))
	var col_step := width / float(cols)
	for i in range(1, cols):
		var x := xa + float(i) * col_step
		_add_box_tube(verts, norms, uvs, indices, Vector3(x, yb, 0), Vector3(x, yt, 0), WIRE_SIZE)

	var rows := maxi(1, roundi(height / MESH_SPACING))
	var row_step := height / float(rows)
	for j in range(1, rows):
		var y := yb + float(j) * row_step
		_add_box_tube(verts, norms, uvs, indices, Vector3(xa, y, 0), Vector3(xb, y, 0), WIRE_SIZE)


static func create_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/conveyor_frame_shader.gdshader")
	mat.set_shader_parameter("metal_texture", _metal_texture)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("metallic_value", 0.0)
	mat.set_shader_parameter("roughness_value", 0.35)
	mat.set_shader_parameter("specular_value", 0.55)
	mat.set_shader_parameter("texture_influence", 0.5)
	return mat


static func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	if verts.is_empty():
		verts.append_array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		indices.append_array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _pack_arrays(verts, norms, uvs, indices))


static func _add_box(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	center: Vector3, size: Vector3
) -> void:
	var h := size * 0.5
	var c := center
	var p000 := c + Vector3(-h.x, -h.y, -h.z)
	var p100 := c + Vector3(h.x, -h.y, -h.z)
	var p110 := c + Vector3(h.x, h.y, -h.z)
	var p010 := c + Vector3(-h.x, h.y, -h.z)
	var p001 := c + Vector3(-h.x, -h.y, h.z)
	var p101 := c + Vector3(h.x, -h.y, h.z)
	var p111 := c + Vector3(h.x, h.y, h.z)
	var p011 := c + Vector3(-h.x, h.y, h.z)

	_add_quad(verts, norms, uvs, indices, p010, p110, p111, p011, Vector3.UP)
	_add_quad(verts, norms, uvs, indices, p000, p001, p101, p100, Vector3.DOWN)
	_add_quad(verts, norms, uvs, indices, p100, p101, p111, p110, Vector3.RIGHT)
	_add_quad(verts, norms, uvs, indices, p000, p010, p011, p001, Vector3.LEFT)
	_add_quad(verts, norms, uvs, indices, p001, p011, p111, p101, Vector3.BACK)
	_add_quad(verts, norms, uvs, indices, p000, p100, p110, p010, Vector3.FORWARD)


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
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3
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
