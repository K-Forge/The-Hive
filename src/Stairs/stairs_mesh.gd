@tool
class_name StairsMesh
extends RefCounted

## Origin at center; stairs rise from (-size.x/2, -size.y/2) to (+size.x/2, +size.y/2).
## Surfaces: 0=treads/risers, 1=stringers/handrails.

const STANDARD_RISE: float = 0.178
const STANDARD_TREAD: float = 0.28
const MIN_RISE: float = 0.10
const MAX_RISE: float = 0.22
const TREAD_NOSING: float = 0.025
const TREAD_THICKNESS: float = 0.005
const STRINGER_WIDTH: float = 0.012
const STRINGER_HEIGHT: float = 0.25
const HANDRAIL_HEIGHT: float = 1.07
const HANDRAIL_SIZE: float = 0.04
const MID_RAIL_HEIGHT: float = 0.54
const POST_SIZE: float = 0.04
const LANDING_DEPTH: float = 0.6

static var _metal_texture: Texture2D = preload("res://assets/3DModels/Textures/Metal.png")


static func get_step_count(rise_height: float) -> int:
	return maxi(1, roundi(rise_height / STANDARD_RISE))


static func get_step_rise(rise_height: float) -> float:
	return rise_height / float(get_step_count(rise_height))


static func get_step_run(run_length: float, rise_height: float) -> float:
	var usable_run := maxf(run_length - LANDING_DEPTH, 0.3)
	return usable_run / float(get_step_count(rise_height))


static func get_default_run_length(rise_height: float) -> float:
	return float(get_step_count(rise_height)) * STANDARD_TREAD + LANDING_DEPTH


static func create(run_length: float, rise_height: float, width: float, include_handrails: bool = true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_tread_surface(mesh, run_length, rise_height, width)
	if include_handrails:
		_add_handrail_surface(mesh, run_length, rise_height, width)
	return mesh


static func create_material_tread() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/structure_floor_shader.gdshader")
	mat.set_shader_parameter("base_color_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_BaseColor.png"))
	mat.set_shader_parameter("normal_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_Normal.png"))
	mat.set_shader_parameter("orm_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_ORM.png"))
	return mat


static func create_material_yellow() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/conveyor_frame_shader.gdshader")
	mat.set_shader_parameter("metal_texture", _metal_texture)
	mat.set_shader_parameter("color", Color(0.95, 0.74, 0.06))
	mat.set_shader_parameter("metallic_value", 0.0)
	mat.set_shader_parameter("roughness_value", 0.35)
	mat.set_shader_parameter("specular_value", 0.55)
	mat.set_shader_parameter("texture_influence", 0.5)
	return mat


static func _add_tread_surface(mesh: ArrayMesh, run_length: float, rise_height: float, width: float) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var step_count := get_step_count(rise_height)
	var step_rise := get_step_rise(rise_height)
	var step_run := get_step_run(run_length, rise_height)
	var hw := width / 2.0
	var hl := run_length / 2.0
	var hh := rise_height / 2.0
	var tt := TREAD_THICKNESS
	var nosing := TREAD_NOSING

	var base_x := -hl
	var base_y := -hh

	for i in range(step_count):
		var tread_y: float = base_y + float(i + 1) * step_rise
		var tread_x_start: float = base_x + float(i) * step_run - nosing
		var tread_x_end: float = base_x + float(i + 1) * step_run

		tread_x_start = maxf(tread_x_start, base_x - nosing)

		_add_quad(verts, norms, uvs, indices,
			Vector3(tread_x_start, tread_y, -hw),
			Vector3(tread_x_end, tread_y, -hw),
			Vector3(tread_x_end, tread_y, hw),
			Vector3(tread_x_start, tread_y, hw),
			Vector3.UP)

		_add_quad(verts, norms, uvs, indices,
			Vector3(tread_x_start, tread_y - tt, hw),
			Vector3(tread_x_end, tread_y - tt, hw),
			Vector3(tread_x_end, tread_y - tt, -hw),
			Vector3(tread_x_start, tread_y - tt, -hw),
			Vector3.DOWN)

		_add_quad(verts, norms, uvs, indices,
			Vector3(tread_x_start, tread_y, hw),
			Vector3(tread_x_start, tread_y, -hw),
			Vector3(tread_x_start, tread_y - tt, -hw),
			Vector3(tread_x_start, tread_y - tt, hw),
			Vector3(-1, 0, 0))

		var riser_x: float = tread_x_end
		var riser_bottom: float = tread_y
		var riser_top: float
		if i < step_count - 1:
			riser_top = base_y + float(i + 2) * step_rise
		else:
			riser_top = tread_y

		if riser_top > riser_bottom + 0.001:
			_add_quad(verts, norms, uvs, indices,
				Vector3(riser_x, riser_top, -hw),
				Vector3(riser_x, riser_top, hw),
				Vector3(riser_x, riser_bottom, hw),
				Vector3(riser_x, riser_bottom, -hw),
				Vector3(1, 0, 0))

		_add_quad(verts, norms, uvs, indices,
			Vector3(tread_x_start, tread_y, -hw),
			Vector3(tread_x_end, tread_y, -hw),
			Vector3(tread_x_end, tread_y - tt, -hw),
			Vector3(tread_x_start, tread_y - tt, -hw),
			Vector3(0, 0, -1))
		_add_quad(verts, norms, uvs, indices,
			Vector3(tread_x_end, tread_y, hw),
			Vector3(tread_x_start, tread_y, hw),
			Vector3(tread_x_start, tread_y - tt, hw),
			Vector3(tread_x_end, tread_y - tt, hw),
			Vector3(0, 0, 1))

	var first_riser_bottom := base_y
	var first_riser_top := base_y + step_rise
	var first_riser_x := base_x
	_add_quad(verts, norms, uvs, indices,
		Vector3(first_riser_x, first_riser_top, -hw),
		Vector3(first_riser_x, first_riser_top, hw),
		Vector3(first_riser_x, first_riser_bottom, hw),
		Vector3(first_riser_x, first_riser_bottom, -hw),
		Vector3(-1, 0, 0))

	var landing_x_start := base_x + float(step_count) * step_run
	var landing_x_end := hl
	var landing_y := base_y + rise_height

	if landing_x_end > landing_x_start + 0.01:
		_add_quad(verts, norms, uvs, indices,
			Vector3(landing_x_start, landing_y, -hw),
			Vector3(landing_x_end, landing_y, -hw),
			Vector3(landing_x_end, landing_y, hw),
			Vector3(landing_x_start, landing_y, hw),
			Vector3.UP)
		_add_quad(verts, norms, uvs, indices,
			Vector3(landing_x_start, landing_y - tt, hw),
			Vector3(landing_x_end, landing_y - tt, hw),
			Vector3(landing_x_end, landing_y - tt, -hw),
			Vector3(landing_x_start, landing_y - tt, -hw),
			Vector3.DOWN)
		_add_quad(verts, norms, uvs, indices,
			Vector3(landing_x_end, landing_y, hw),
			Vector3(landing_x_end, landing_y, -hw),
			Vector3(landing_x_end, landing_y - tt, -hw),
			Vector3(landing_x_end, landing_y - tt, hw),
			Vector3(1, 0, 0))

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _add_handrail_surface(mesh: ArrayMesh, run_length: float, rise_height: float, width: float) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var step_count := get_step_count(rise_height)
	var step_rise := get_step_rise(rise_height)
	var step_run := get_step_run(run_length, rise_height)
	var hw := width / 2.0
	var hl := run_length / 2.0
	var hh := rise_height / 2.0
	var base_x := -hl
	var base_y := -hh

	var landing_x_start := base_x + float(step_count) * step_run
	var landing_y := base_y + rise_height

	for side_val: float in [-1.0, 1.0]:
		var side: float = side_val
		var z_offset: float = side * (hw + STRINGER_WIDTH / 2.0)
		var stringer_normal := Vector3(0, 0, side)
		var sh := STRINGER_HEIGHT
		var sw := STRINGER_WIDTH

		var stringer_bottom := Vector3(base_x, base_y, z_offset)
		var stringer_top := Vector3(landing_x_start, landing_y, z_offset)
		var inner_offset := Vector3(0, 0, -side * sw)

		_add_quad(verts, norms, uvs, indices,
			stringer_bottom,
			stringer_top,
			stringer_top + Vector3(0, sh, 0),
			stringer_bottom + Vector3(0, sh, 0),
			stringer_normal)
		_add_quad(verts, norms, uvs, indices,
			stringer_top + inner_offset,
			stringer_bottom + inner_offset,
			stringer_bottom + inner_offset + Vector3(0, sh, 0),
			stringer_top + inner_offset + Vector3(0, sh, 0),
			-stringer_normal)

		if hl > landing_x_start + 0.01:
			var landing_stringer_start := Vector3(landing_x_start, landing_y, z_offset)
			var landing_stringer_end := Vector3(hl, landing_y, z_offset)
			var landing_stringer_inner_start := landing_stringer_start + inner_offset
			var landing_stringer_inner_end := landing_stringer_end + inner_offset
			var landing_stringer_top_start := landing_stringer_start + Vector3(0, sh, 0)
			var landing_stringer_top_end := landing_stringer_end + Vector3(0, sh, 0)
			var landing_stringer_top_inner_start := landing_stringer_top_start + inner_offset
			var landing_stringer_top_inner_end := landing_stringer_top_end + inner_offset
			_add_quad(verts, norms, uvs, indices,
				landing_stringer_start,
				landing_stringer_end,
				landing_stringer_top_end,
				landing_stringer_top_start,
				stringer_normal)
			_add_quad(verts, norms, uvs, indices,
				landing_stringer_inner_end,
				landing_stringer_inner_start,
				landing_stringer_top_inner_start,
				landing_stringer_top_inner_end,
				-stringer_normal)
			if side > 0.0:
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_inner_start,
					landing_stringer_top_inner_end,
					landing_stringer_top_end,
					landing_stringer_top_start,
					Vector3.UP)
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_start,
					landing_stringer_end,
					landing_stringer_inner_end,
					landing_stringer_inner_start,
					Vector3.DOWN)
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_inner_start,
					landing_stringer_top_start,
					landing_stringer_start,
					landing_stringer_inner_start,
					Vector3(-1, 0, 0))
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_end,
					landing_stringer_top_inner_end,
					landing_stringer_inner_end,
					landing_stringer_end,
					Vector3(1, 0, 0))
			else:
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_start,
					landing_stringer_top_end,
					landing_stringer_top_inner_end,
					landing_stringer_top_inner_start,
					Vector3.UP)
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_inner_start,
					landing_stringer_inner_end,
					landing_stringer_end,
					landing_stringer_start,
					Vector3.DOWN)
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_start,
					landing_stringer_top_inner_start,
					landing_stringer_inner_start,
					landing_stringer_start,
					Vector3(-1, 0, 0))
				_add_quad(verts, norms, uvs, indices,
					landing_stringer_top_inner_end,
					landing_stringer_top_end,
					landing_stringer_end,
					landing_stringer_inner_end,
					Vector3(1, 0, 0))

		var rail_start_y := base_y + step_rise + HANDRAIL_HEIGHT
		var rail_end_y := landing_y + HANDRAIL_HEIGHT
		var rail_run := landing_x_start - base_x

		for i in range(step_count + 1):
			var post_x: float
			var post_y: float
			if i < step_count:
				post_x = base_x + float(i) * step_run + step_run * 0.5
				post_y = base_y + float(i + 1) * step_rise
			else:
				post_x = landing_x_start + 0.05
				post_y = landing_y

			var post_top_y: float
			if i < step_count and rail_run > 0.0001:
				var f: float = (post_x - base_x) / rail_run
				post_top_y = rail_start_y + f * (rail_end_y - rail_start_y)
			else:
				post_top_y = landing_y + HANDRAIL_HEIGHT

			var post_bottom := Vector3(post_x, post_y, z_offset)
			var post_top := Vector3(post_x, post_top_y, z_offset)
			_add_box_tube(verts, norms, uvs, indices, post_bottom, post_top, POST_SIZE)

		var rail_bottom := Vector3(base_x, rail_start_y, z_offset)
		var rail_top := Vector3(landing_x_start, rail_end_y, z_offset)
		_add_box_tube(verts, norms, uvs, indices, rail_bottom, rail_top, HANDRAIL_SIZE)

		var mid_bottom := Vector3(base_x, base_y + step_rise + MID_RAIL_HEIGHT, z_offset)
		var mid_top := Vector3(landing_x_start, landing_y + MID_RAIL_HEIGHT, z_offset)
		_add_box_tube(verts, norms, uvs, indices, mid_bottom, mid_top, HANDRAIL_SIZE * 0.8)

		if hl > landing_x_start + 0.05:
			var landing_end_x := hl
			_add_box_tube(verts, norms, uvs, indices,
				Vector3(landing_end_x, landing_y, z_offset),
				Vector3(landing_end_x, landing_y + HANDRAIL_HEIGHT, z_offset),
				POST_SIZE)
			_add_box_tube(verts, norms, uvs, indices,
				Vector3(landing_x_start, landing_y + HANDRAIL_HEIGHT, z_offset),
				Vector3(landing_end_x, landing_y + HANDRAIL_HEIGHT, z_offset),
				HANDRAIL_SIZE)
			_add_box_tube(verts, norms, uvs, indices,
				Vector3(landing_x_start, landing_y + MID_RAIL_HEIGHT, z_offset),
				Vector3(landing_end_x, landing_y + MID_RAIL_HEIGHT, z_offset),
				HANDRAIL_SIZE * 0.8)

		var newel_bottom := Vector3(base_x, base_y, z_offset)
		var newel_top := Vector3(base_x, base_y + step_rise + HANDRAIL_HEIGHT + 0.05, z_offset)
		_add_box_tube(verts, norms, uvs, indices, newel_bottom, newel_top, POST_SIZE * 1.2)

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _add_box_tube(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	from: Vector3,
	to: Vector3,
	tube_size: Variant
) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return
	dir = dir.normalized()

	var hx: float
	var hz: float
	if tube_size is Vector3:
		hx = tube_size.x / 2.0
		hz = tube_size.y / 2.0
	else:
		var ts: float = tube_size
		hx = ts / 2.0
		hz = hx

	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var local_up := right.cross(dir).normalized()

	var offsets: Array[Vector3] = [
		-right * hx - local_up * hz,
		right * hx - local_up * hz,
		right * hx + local_up * hz,
		-right * hx + local_up * hz,
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
			Vector2(edge_len, length), Vector2(0, length),
		])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	var base_idx := verts.size()
	for offset: Vector3 in offsets:
		verts.append(from + offset)
		norms.append(-dir)
		uvs.append(Vector2(offset.x, offset.z))
	indices.append_array([base_idx, base_idx + 2, base_idx + 1, base_idx, base_idx + 3, base_idx + 2])

	base_idx = verts.size()
	for offset: Vector3 in offsets:
		verts.append(to + offset)
		norms.append(dir)
		uvs.append(Vector2(offset.x, offset.z))
	indices.append_array([base_idx, base_idx + 1, base_idx + 2, base_idx, base_idx + 2, base_idx + 3])


static func _add_quad(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	v3: Vector3,
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
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
