@tool
class_name CurvedSideGuard
extends Node3D

## Curved side-guard wall covering one arc range on one side (inner or outer).

@export var radius: float = 1.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		_request_rebuild()

@export var start_angle_rad: float = 0.0:
	set(value):
		if is_equal_approx(start_angle_rad, value):
			return
		start_angle_rad = value
		_request_rebuild()

@export var end_angle_rad: float = PI / 2.0:
	set(value):
		if is_equal_approx(end_angle_rad, value):
			return
		end_angle_rad = value
		_request_rebuild()

## True = outer (radius outward from arc center), false = inner.
@export var outer_side: bool = true:
	set(value):
		if outer_side == value:
			return
		outer_side = value
		_request_rebuild()

## Tangent extension at arc start; 0 unless this segment owns the conveyor's natural back.
@export var back_ext: float = 0.0:
	set(value):
		if is_equal_approx(back_ext, value):
			return
		back_ext = value
		_request_rebuild()

## Tangent extension at arc end; 0 unless this segment owns the conveyor's natural front.
@export var front_ext: float = 0.0:
	set(value):
		if is_equal_approx(front_ext, value):
			return
		front_ext = value
		_request_rebuild()

## Arc value at the back edge (centerline coords; matches `side_guard_openings`).
@export_storage var arc_back: float = 0.0

## Arc value at the front edge.
@export_storage var arc_front: float = 0.0


var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _collision: CollisionShape3D
var _rebuild_pending: bool = false


func _ready() -> void:
	_ensure_nodes()
	_rebuild()


func _ensure_nodes() -> void:
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
		if not is_instance_valid(_mesh_instance):
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "Mesh"
			add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	if not is_instance_valid(_body):
		_body = _mesh_instance.get_node_or_null("StaticBody3D") as StaticBody3D
		if not is_instance_valid(_body):
			_body = StaticBody3D.new()
			_body.name = "StaticBody3D"
			# See SideGuard._update_collision_shape for rationale.
			_body.disable_mode = StaticBody3D.DISABLE_MODE_MAKE_STATIC
			_body.collision_mask = 8
			_body.ghost_collision_filtering_enabled = true
			var phys := PhysicsMaterial.new()
			phys.friction = 0.0
			_body.physics_material_override = phys
			_mesh_instance.add_child(_body)
	if not is_instance_valid(_collision):
		_collision = _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not is_instance_valid(_collision):
			_collision = CollisionShape3D.new()
			_collision.name = "CollisionShape3D"
			_body.add_child(_collision)


func _request_rebuild() -> void:
	if _rebuild_pending or not is_inside_tree():
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_pending = false
	if not is_inside_tree():
		return
	_ensure_nodes()
	var direction: float = 1.0 if outer_side else -1.0
	var span_rad: float = end_angle_rad - start_angle_rad
	if span_rad <= 0.0 or radius <= 0.0:
		_mesh_instance.mesh = null
		_collision.shape = null
		return
	var segments: int = maxi(2, int(rad_to_deg(span_rad) / 5.0))
	var visual_mesh := build_arc_wall(
		radius, SideGuardMesh.WALL_HEIGHT, SideGuardMesh.WALL_THICKNESS,
		start_angle_rad, end_angle_rad, direction, segments,
		back_ext, front_ext)
	_mesh_instance.mesh = visual_mesh
	_mesh_instance.set_surface_override_material(0, SideGuardMesh.create_material())
	_mesh_instance.set_instance_shader_parameter("Scale", 1.0)

	var collision_mesh := build_arc_wall(
		radius, SideGuardMesh.WALL_HEIGHT, SideGuardMesh.COLLISION_THICKNESS,
		start_angle_rad, end_angle_rad, direction, segments,
		back_ext, front_ext)
	if collision_mesh and collision_mesh.get_surface_count() > 0:
		var arrays: Array = collision_mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tri_verts := PackedVector3Array()
		for i in range(0, indices.size(), 3):
			if i + 2 >= indices.size():
				break
			tri_verts.append(verts[indices[i]])
			tri_verts.append(verts[indices[i + 1]])
			tri_verts.append(verts[indices[i + 2]])
		var shape := ConcavePolygonShape3D.new()
		shape.data = tri_verts
		_collision.shape = shape
		_collision.position = Vector3.ZERO
		_collision.rotation = Vector3.ZERO


static func build_arc_wall(r: float, wall_height: float, wall_thickness: float,
		start_angle: float, end_angle: float, direction: float, segments: int,
		back_extension: float, front_extension: float) -> ArrayMesh:
	var span: float = end_angle - start_angle
	if span <= 0.0 or r <= 0.0:
		return ArrayMesh.new()

	var points: Array = []
	var total_dist: float = 0.0

	var arc_pt := func(angle: float) -> Vector3:
		return Vector3(-sin(angle) * r, 0.0, cos(angle) * r)
	var arc_normal := func(angle: float) -> Vector3:
		return Vector3(-sin(angle), 0.0, cos(angle)) * direction

	if back_extension > 0.0:
		var back_pos: Vector3 = arc_pt.call(start_angle)
		var back_normal: Vector3 = arc_normal.call(start_angle)
		var back_tangent := Vector3(cos(start_angle), 0.0, sin(start_angle))
		var ext_pos: Vector3 = back_pos + back_tangent * back_extension
		points.append({"pos": ext_pos, "normal": back_normal, "dist": total_dist})
		total_dist += back_extension

	points.append({"pos": arc_pt.call(start_angle), "normal": arc_normal.call(start_angle), "dist": total_dist})

	var step: float = span / segments
	for i in range(1, segments):
		var angle: float = start_angle + step * i
		total_dist += step * r
		points.append({"pos": arc_pt.call(angle), "normal": arc_normal.call(angle), "dist": total_dist})

	total_dist += step * r
	points.append({"pos": arc_pt.call(end_angle), "normal": arc_normal.call(end_angle), "dist": total_dist})

	if front_extension > 0.0:
		var front_pos: Vector3 = arc_pt.call(end_angle)
		var front_normal: Vector3 = arc_normal.call(end_angle)
		var front_tangent := Vector3(-cos(end_angle), 0.0, -sin(end_angle))
		var ext_pos: Vector3 = front_pos + front_tangent * front_extension
		total_dist += front_extension
		points.append({"pos": ext_pos, "normal": front_normal, "dist": total_dist})

	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var y_bottom: float = -ConveyorFrameMesh.FLANGE_THICKNESS

	var r_outer: float = r + wall_thickness / 2.0 * direction
	var r_inner: float = r - wall_thickness / 2.0 * direction

	for point: Dictionary in points:
		var p: Vector3 = point["pos"]
		var n: Vector3 = point["normal"]
		var d: float = point["dist"]
		var p_out: Vector3 = p * (r_outer / r)
		verts.append(Vector3(p_out.x, wall_height, p_out.z))
		norms.append(n)
		uvs.append(Vector2(d, 0))
		verts.append(Vector3(p_out.x, y_bottom, p_out.z))
		norms.append(n)
		uvs.append(Vector2(d, wall_height))

	var pt_count: int = points.size()
	for i in range(pt_count - 1):
		var base: int = i * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

	var inner_base_idx: int = verts.size()
	for point: Dictionary in points:
		var p: Vector3 = point["pos"]
		var n: Vector3 = point["normal"]
		var d: float = point["dist"]
		var p_in: Vector3 = p * (r_inner / r)
		verts.append(Vector3(p_in.x, wall_height, p_in.z))
		norms.append(-n)
		uvs.append(Vector2(d, 0))
		verts.append(Vector3(p_in.x, y_bottom, p_in.z))
		norms.append(-n)
		uvs.append(Vector2(d, wall_height))

	for i in range(pt_count - 1):
		var base: int = inner_base_idx + i * 2
		indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])

	var top_base_idx: int = verts.size()
	for point: Dictionary in points:
		var p: Vector3 = point["pos"]
		var d: float = point["dist"]
		var p_out: Vector3 = p * (r_outer / r)
		var p_in: Vector3 = p * (r_inner / r)
		verts.append(Vector3(p_in.x, wall_height, p_in.z))
		norms.append(Vector3.UP)
		uvs.append(Vector2(d, 0))
		verts.append(Vector3(p_out.x, wall_height, p_out.z))
		norms.append(Vector3.UP)
		uvs.append(Vector2(d, wall_thickness))

	for i in range(pt_count - 1):
		var base: int = top_base_idx + i * 2
		indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])

	for end_i: int in [0, pt_count - 1]:
		var p: Vector3 = points[end_i]["pos"]
		var p_out: Vector3 = p * (r_outer / r)
		var p_in: Vector3 = p * (r_inner / r)
		var cap_normal: Vector3
		if end_i == 0:
			var a0: Vector3 = points[0]["pos"]
			var a1: Vector3 = points[1]["pos"]
			cap_normal = (a0 - a1).normalized()
		else:
			var b0: Vector3 = points[pt_count - 1]["pos"]
			var b1: Vector3 = points[pt_count - 2]["pos"]
			cap_normal = (b0 - b1).normalized()
		cap_normal.y = 0
		cap_normal = cap_normal.normalized()

		var cb: int = verts.size()
		verts.append(Vector3(p_in.x, wall_height, p_in.z))
		verts.append(Vector3(p_in.x, y_bottom, p_in.z))
		verts.append(Vector3(p_out.x, wall_height, p_out.z))
		verts.append(Vector3(p_out.x, y_bottom, p_out.z))
		for _j in range(4):
			norms.append(cap_normal)
			uvs.append(Vector2(0, 0))
		indices.append_array([cb, cb + 2, cb + 1, cb + 1, cb + 2, cb + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
