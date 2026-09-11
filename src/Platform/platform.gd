@tool
class_name Platform
extends ResizableNode3D

## Mezzanine platform. Origin at deck-top center; deck at Y=0, columns to Y=-size.y.
## Auto-detects adjacent Platforms/Stairs to remove shared-edge railings and cut holes.

const SNAP_TOLERANCE: float = 0.15

@export var show_railings: bool = true:
	set(value):
		show_railings = value
		_rebuild()

@export var show_middle_supports: bool = true:
	set(value):
		show_middle_supports = value
		_rebuild()

@export var steel_color: Color = Color(0.95, 0.74, 0.06):
	set(value):
		steel_color = value
		_update_yellow_material_color()

@export var floor_y: float = 0.0:
	set(value):
		floor_y = value
		if is_inside_tree() and not _collision_reposition_active and not has_meta("is_preview"):
			_sync_height_to_floor()

var _floor_y_initialized: bool = false

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_body: StaticBody3D = $StaticBody3D
@onready var _collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var _side_guard_left_collision: CollisionShape3D = get_node_or_null("StaticBody3D/SideGuardLeftCollision") as CollisionShape3D
@onready var _side_guard_right_collision: CollisionShape3D = get_node_or_null("StaticBody3D/SideGuardRightCollision") as CollisionShape3D
@onready var _side_guard_front_collision: CollisionShape3D = get_node_or_null("StaticBody3D/SideGuardFrontCollision") as CollisionShape3D
@onready var _side_guard_back_collision: CollisionShape3D = get_node_or_null("StaticBody3D/SideGuardBackCollision") as CollisionShape3D

var _deck_material: ShaderMaterial
var _yellow_material: ShaderMaterial
var _dynamic_deck_collisions: Array[CollisionShape3D] = []
var _dynamic_guard_collisions: Array[CollisionShape3D] = []

var _computed_railing_openings: Array = []
var _computed_deck_holes: Array = []
var _prev_railing_hash: int = 0
var _prev_hole_hash: int = 0

@export_storage var _railing_openings: Array = []
@export_storage var _deck_holes: Array = []


func _init() -> void:
	super._init()
	size_default = Vector3(4.0, 2.0, 4.0)
	size_min = Vector3(0.5, 0.3, 0.5)
	set_notify_transform(true)


static var instances: Array[Platform] = []


func _enter_tree() -> void:
	super._enter_tree()


func _exit_tree() -> void:
	instances.erase(self)


func _ready() -> void:
	if _collision_shape and _collision_shape.shape:
		_collision_shape.shape = _collision_shape.shape.duplicate() as BoxShape3D
	if _side_guard_left_collision and _side_guard_left_collision.shape:
		_side_guard_left_collision.shape = _side_guard_left_collision.shape.duplicate() as BoxShape3D
	if _side_guard_right_collision and _side_guard_right_collision.shape:
		_side_guard_right_collision.shape = _side_guard_right_collision.shape.duplicate() as BoxShape3D
	if _side_guard_front_collision and _side_guard_front_collision.shape:
		_side_guard_front_collision.shape = _side_guard_front_collision.shape.duplicate() as BoxShape3D
	if _side_guard_back_collision and _side_guard_back_collision.shape:
		_side_guard_back_collision.shape = _side_guard_back_collision.shape.duplicate() as BoxShape3D
	_setup_materials()
	_rebuild()
	if has_meta("is_preview"):
		return
	if get_owner() != null:
		instances.append(self)
	# Suppress until the engine's post-add_child set_transform has run.
	set_notify_transform(false)
	call_deferred("_initial_floor_sync")
	call_deferred("_deferred_connection_update")


func _initial_floor_sync() -> void:
	if not is_inside_tree() or has_meta("is_preview"):
		set_notify_transform(true)
		return
	_floor_y_initialized = true
	floor_y = global_position.y - size.y
	set_notify_transform(true)


var _collision_reposition_active: bool = false
var _transform_update_pending: bool = false
var _last_collision_floor_y: float = INF


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if has_meta("is_preview"):
			return
		if _collision_reposition_active:
			return
		if not _transform_update_pending:
			_transform_update_pending = true
			call_deferred("_deferred_transform_update")
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_computed_railing_openings = []
		_computed_deck_holes = []
		_prev_railing_hash = 0
		_prev_hole_hash = 0
		_rebuild()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		call_deferred("_deferred_connection_update")


func _deferred_transform_update() -> void:
	_transform_update_pending = false
	if _collision_reposition_active:
		_collision_reposition_active = false
		return
	_sync_height_to_floor()
	_notify_all_platforms()


func _sync_height_to_floor() -> void:
	if not is_inside_tree() or not _floor_y_initialized or has_meta("is_preview"):
		return
	var target_y := maxf(size_min.y, global_position.y - floor_y)
	if not is_equal_approx(size.y, target_y):
		size = Vector3(size.x, target_y, size.z)


func _collision_repositioned_save() -> Variant:
	return floor_y

func _collision_repositioned(collision_point: Vector3, collision_normal: Vector3) -> void:
	if collision_normal == Vector3.ZERO:
		return
	_collision_reposition_active = true
	if not _transform_update_pending:
		call_deferred("_clear_collision_reposition_active")
	if is_equal_approx(_last_collision_floor_y, collision_point.y):
		return
	_last_collision_floor_y = collision_point.y
	var preserved := size.y
	floor_y = collision_point.y
	_floor_y_initialized = true
	# Pin origin so the post-flag-clear sync is a no-op.
	var target_origin_y := collision_point.y + preserved
	if not is_equal_approx(global_transform.origin.y, target_origin_y):
		var new_origin := global_transform.origin
		new_origin.y = target_origin_y
		global_transform.origin = new_origin

func _collision_repositioned_undo(saved_data: Variant) -> void:
	if saved_data is float:
		_collision_reposition_active = true
		if not _transform_update_pending:
			call_deferred("_clear_collision_reposition_active")
		floor_y = saved_data

func _clear_collision_reposition_active() -> void:
	_collision_reposition_active = false


func _transform_requested(data: Dictionary) -> void:
	if not EditorInterface.get_selection().get_selected_nodes().has(self):
		return
	if data.has("motion"):
		# Leg length is driven by floor_y, not the scale gizmo.
		data = {"motion": [data["motion"][0], 0.0, data["motion"][2]]}
	super._transform_requested(data)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 4, 5])


func _notify_all_platforms() -> void:
	if not is_inside_tree():
		return
	for platform in instances:
		platform.call_deferred("_deferred_connection_update")


func _setup_materials() -> void:
	_deck_material = PlatformMesh.create_material_deck()
	_yellow_material = PlatformMesh.create_material_yellow()
	_update_yellow_material_color()


func _update_yellow_material_color() -> void:
	if _yellow_material:
		_yellow_material.set_shader_parameter("color", steel_color)


func _get_constrained_size(new_size: Vector3) -> Vector3:
	new_size.x = maxf(new_size.x, 0.5)
	new_size.z = maxf(new_size.z, 0.5)
	if is_inside_tree() and _floor_y_initialized and not _collision_reposition_active and not has_meta("is_preview"):
		new_size.y = maxf(size_min.y, global_position.y - floor_y)
	else:
		new_size.y = maxf(new_size.y, size_min.y)
	return new_size

func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	var half_x := for_size.x * 0.5
	var half_z := for_size.z * 0.5
	return AABB(Vector3(-half_x, -for_size.y, -half_z), Vector3(for_size.x, for_size.y, for_size.z))


func _on_size_changed() -> void:
	_rebuild()
	_notify_all_platforms()


func _rebuild() -> void:
	if not is_instance_valid(_mesh_instance):
		return

	var length := size.x
	var height := size.y
	var width := size.z

	var all_openings: Array = []
	all_openings.append_array(_railing_openings)
	all_openings.append_array(_computed_railing_openings)

	var all_holes: Array = []
	all_holes.append_array(_deck_holes)
	all_holes.append_array(_computed_deck_holes)

	_mesh_instance.mesh = PlatformMesh.create(length, height, width, all_openings, all_holes, show_railings, show_middle_supports)

	if _mesh_instance.mesh:
		var sc := _mesh_instance.mesh.get_surface_count()
		if sc > 0:
			_mesh_instance.set_surface_override_material(0, _deck_material)
		if sc > 1:
			_mesh_instance.set_surface_override_material(1, _yellow_material)
		if sc > 2:
			_mesh_instance.set_surface_override_material(2, _yellow_material)

	_update_deck_collisions(length, width, all_holes)

	_update_side_guard_collisions(length, width, all_openings)



func _update_deck_collisions(length: float, width: float, holes: Array) -> void:
	_clear_dynamic_deck_collisions()
	if not is_instance_valid(_collision_body):
		return
	if holes.is_empty():
		if _collision_shape and _collision_shape.shape is BoxShape3D:
			(_collision_shape.shape as BoxShape3D).size = Vector3(
				length, PlatformMesh.DECK_THICKNESS + 0.02, width)
			_collision_shape.position = Vector3(0, -PlatformMesh.DECK_THICKNESS / 2.0, 0)
			_collision_shape.disabled = false
		return

	if _collision_shape:
		_collision_shape.disabled = true

	var concave := PlatformMesh.create_deck_top_collision_shape(length, width, holes)
	var col := CollisionShape3D.new()
	col.shape = concave
	col.position = Vector3.ZERO
	_collision_body.add_child(col, false, Node.INTERNAL_MODE_FRONT)
	_dynamic_deck_collisions.append(col)


func _clear_dynamic_deck_collisions() -> void:
	for col in _dynamic_deck_collisions:
		if is_instance_valid(col):
			col.free()
	_dynamic_deck_collisions.clear()


func _update_side_guard_collisions(length: float, width: float, openings: Array) -> void:
	_clear_dynamic_guard_collisions()

	for collision: CollisionShape3D in [_side_guard_left_collision, _side_guard_right_collision, _side_guard_front_collision, _side_guard_back_collision]:
		if collision:
			collision.disabled = true
	if not show_railings or not is_instance_valid(_collision_body):
		return

	var normalized_openings := _normalize_openings(openings)
	var guard_height := PlatformMesh.RAILING_HEIGHT
	var guard_thickness := PlatformMesh.POST_SIZE * 1.5
	var half_width := width * 0.5
	var half_length := length * 0.5
	var z_offset := half_width + PlatformMesh.POST_SIZE * 0.5
	var x_offset := half_length + PlatformMesh.POST_SIZE * 0.5

	# Edge ids match PlatformMesh:
	# 0:+X (run along Z), 1:-X (run along Z), 2:+Z (run along X), 3:-Z (run along X)
	for segment in _build_solid_railing_segments(width, _get_edge_openings(0, normalized_openings)):
		var z_center := (segment.x + segment.y) * 0.5 - half_width
		_create_guard_segment_collision(
			Vector3(segment.y - segment.x, guard_height, guard_thickness),
			Vector3(x_offset, guard_height * 0.5, z_center),
			Vector3(0, PI * 0.5, 0))

	for segment in _build_solid_railing_segments(width, _get_edge_openings(1, normalized_openings)):
		var z_center := (segment.x + segment.y) * 0.5 - half_width
		_create_guard_segment_collision(
			Vector3(segment.y - segment.x, guard_height, guard_thickness),
			Vector3(-x_offset, guard_height * 0.5, z_center),
			Vector3(0, PI * 0.5, 0))

	for segment in _build_solid_railing_segments(length, _get_edge_openings(2, normalized_openings)):
		var x_center := (segment.x + segment.y) * 0.5 - half_length
		_create_guard_segment_collision(
			Vector3(segment.y - segment.x, guard_height, guard_thickness),
			Vector3(x_center, guard_height * 0.5, z_offset),
			Vector3.ZERO)

	for segment in _build_solid_railing_segments(length, _get_edge_openings(3, normalized_openings)):
		var x_center := (segment.x + segment.y) * 0.5 - half_length
		_create_guard_segment_collision(
			Vector3(segment.y - segment.x, guard_height, guard_thickness),
			Vector3(x_center, guard_height * 0.5, -z_offset),
			Vector3.ZERO)


func _get_edge_openings(edge_id: int, openings: Array) -> Array:
	var edge_openings: Array = []
	for opening: Dictionary in openings:
		var edge: int = opening.get("edge", -1)
		if edge == edge_id:
			edge_openings.append(opening)
	return edge_openings


func _build_solid_railing_segments(edge_length: float, edge_openings: Array) -> Array[Vector2]:
	var half_edge := edge_length * 0.5
	var open_ranges: Array[Vector2] = []
	for opening: Dictionary in edge_openings:
		var raw_start: float = opening.get("start", 0.0)
		var raw_end: float = opening.get("end", 0.0)
		var o_start := clampf(raw_start + half_edge, 0.0, edge_length)
		var o_end := clampf(raw_end + half_edge, 0.0, edge_length)
		if o_start > o_end:
			var tmp := o_start
			o_start = o_end
			o_end = tmp
		if o_end - o_start > 0.01:
			open_ranges.append(Vector2(o_start, o_end))

	open_ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var solid_segments: Array[Vector2] = []
	var cursor := 0.0
	for r in open_ranges:
		if r.x > cursor + 0.01:
			solid_segments.append(Vector2(cursor, r.x))
		cursor = maxf(cursor, r.y)
	if cursor < edge_length - 0.01:
		solid_segments.append(Vector2(cursor, edge_length))
	return solid_segments


func _create_guard_segment_collision(shape_size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = shape_size
	col.shape = shape
	col.position = pos
	col.rotation = rot
	_collision_body.add_child(col, false, Node.INTERNAL_MODE_FRONT)
	_dynamic_guard_collisions.append(col)


func _clear_dynamic_guard_collisions() -> void:
	for col in _dynamic_guard_collisions:
		if is_instance_valid(col):
			col.free()
	_dynamic_guard_collisions.clear()


func _deferred_connection_update() -> void:
	if not is_inside_tree():
		return
	_detect_connections()


func _detect_connections() -> void:
	var new_openings: Array = []
	var new_holes: Array = []

	for other in instances:
		if other == self:
			continue
		_detect_platform_connection(other, new_openings)

	for stairs in Stairs.instances:
		_detect_stair_connection(stairs, new_openings, new_holes)

	new_openings = _normalize_openings(new_openings)

	var o_hash := _openings_signature(new_openings)
	var h_hash := _holes_signature(new_holes)
	if o_hash != _prev_railing_hash or h_hash != _prev_hole_hash:
		_prev_railing_hash = o_hash
		_prev_hole_hash = h_hash
		_computed_railing_openings = new_openings
		_computed_deck_holes = new_holes
		_rebuild()


func _detect_platform_connection(other: Platform, openings: Array) -> void:
	var tol := SNAP_TOLERANCE
	var my_inv := global_transform.affine_inverse()

	var my_hl := size.x / 2.0
	var my_hw := size.z / 2.0
	var ot_hl := other.size.x / 2.0
	var ot_hw := other.size.z / 2.0

	var ot_origin_local := my_inv * other.global_position
	if absf(ot_origin_local.y) > tol:
		return

	var ot_xf := other.global_transform
	var c0 := my_inv * (ot_xf * Vector3(-ot_hl, 0, -ot_hw))
	var c1 := my_inv * (ot_xf * Vector3(ot_hl, 0, -ot_hw))
	var c2 := my_inv * (ot_xf * Vector3(ot_hl, 0, ot_hw))
	var c3 := my_inv * (ot_xf * Vector3(-ot_hl, 0, ot_hw))

	var other_basis_local := my_inv.basis * ot_xf.basis
	var other_edges := [
		{"a": c1, "b": c2, "outward": (other_basis_local * Vector3.RIGHT).normalized()},
		{"a": c0, "b": c3, "outward": (other_basis_local * Vector3.LEFT).normalized()},
		{"a": c3, "b": c2, "outward": (other_basis_local * Vector3.BACK).normalized()},
		{"a": c0, "b": c1, "outward": (other_basis_local * Vector3.FORWARD).normalized()},
	]
	var my_edges := _get_local_edges(my_hl, my_hw)

	const OPPOSING_DOT_MAX := -0.65
	const PARALLEL_DOT_MIN := 0.965
	for my_edge: Dictionary in my_edges:
		var my_point: Vector3 = my_edge["point"]
		var my_run_dir: Vector3 = my_edge["run_dir"]
		var my_outward: Vector3 = my_edge["outward"]
		var sec_min: float = my_edge["sec_min"]
		var sec_max: float = my_edge["sec_max"]
		var use_z_axis: bool = my_edge["use_z"]

		for other_edge: Dictionary in other_edges:
			var other_outward: Vector3 = other_edge["outward"]
			if my_outward.dot(other_outward) > OPPOSING_DOT_MAX:
				continue

			var oa: Vector3 = other_edge["a"]
			var ob: Vector3 = other_edge["b"]
			var other_dir := (ob - oa).normalized()
			if absf(other_dir.dot(my_run_dir)) < PARALLEL_DOT_MIN:
				continue

			var dist_a := (oa - my_point).dot(my_outward)
			var dist_b := (ob - my_point).dot(my_outward)
			if absf(dist_a) > tol or absf(dist_b) > tol:
				continue

			var sec_a := oa.z if use_z_axis else oa.x
			var sec_b := ob.z if use_z_axis else ob.x
			var overlap_min := maxf(minf(sec_a, sec_b), sec_min)
			var overlap_max := minf(maxf(sec_a, sec_b), sec_max)
			if overlap_max - overlap_min > 0.01:
				openings.append({"edge": my_edge["id"], "start": overlap_min, "end": overlap_max})

	# Fallback for overlap/containment cases where platforms intersect in footprint
	# without having clearly opposing edge pairs (e.g. one platform inside another).
	_detect_platform_overlap_footprint(
		PackedVector2Array([
			Vector2(c0.x, c0.z),
			Vector2(c1.x, c1.z),
			Vector2(c2.x, c2.z),
			Vector2(c3.x, c3.z),
		]),
		my_hl, my_hw, openings, tol)


func _detect_platform_overlap_footprint(
		other_poly: PackedVector2Array, my_hl: float, my_hw: float,
		openings: Array, tol: float) -> void:
	if other_poly.size() < 3:
		return

	var edge_defs := [
		{"id": 0, "a": Vector2(my_hl, -my_hw), "b": Vector2(my_hl, my_hw), "use_z": true},
		{"id": 1, "a": Vector2(-my_hl, -my_hw), "b": Vector2(-my_hl, my_hw), "use_z": true},
		{"id": 2, "a": Vector2(-my_hl, my_hw), "b": Vector2(my_hl, my_hw), "use_z": false},
		{"id": 3, "a": Vector2(-my_hl, -my_hw), "b": Vector2(my_hl, -my_hw), "use_z": false},
	]

	for edge: Dictionary in edge_defs:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var overlap: Array = _segment_overlap_range_against_polygon(a, b, other_poly, tol)
		if overlap.size() != 2:
			continue
		var t0: float = overlap[0]
		var t1: float = overlap[1]
		if t1 - t0 <= 0.01:
			continue

		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		var use_z: bool = edge["use_z"]
		var start: float = p0.y if use_z else p0.x
		var end: float = p1.y if use_z else p1.x
		openings.append({"edge": edge["id"], "start": start, "end": end})


func _segment_overlap_range_against_polygon(
		a: Vector2, b: Vector2, poly: PackedVector2Array, tol: float) -> Array:
	var ts: Array[float] = []
	var d := b - a

	if _point_in_polygon_or_near_edge(a, poly, tol):
		ts.append(0.0)
	if _point_in_polygon_or_near_edge(b, poly, tol):
		ts.append(1.0)

	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var inter: Variant = Geometry2D.segment_intersects_segment(a, b, p0, p1)
		if inter == null:
			continue
		var t: float
		if absf(d.x) >= absf(d.y):
			if absf(d.x) < 0.00001:
				t = 0.0
			else:
				t = (inter.x - a.x) / d.x
		else:
			if absf(d.y) < 0.00001:
				t = 0.0
			else:
				t = (inter.y - a.y) / d.y
		ts.append(clampf(t, 0.0, 1.0))

	if ts.size() < 2:
		return []

	ts.sort()
	var uniq: Array[float] = []
	for t in ts:
		if uniq.is_empty() or absf(t - uniq[-1]) > 0.0005:
			uniq.append(t)

	if uniq.size() < 2:
		return []
	return [uniq[0], uniq[uniq.size() - 1]]


func _point_in_polygon_or_near_edge(point: Vector2, poly: PackedVector2Array, tol: float) -> bool:
	if Geometry2D.is_point_in_polygon(point, poly):
		return true
	if tol <= 0.0:
		return false
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if _distance_point_to_segment(point, a, b) <= tol:
			return true
	return false


func _distance_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


func _get_local_edges(hl: float, hw: float) -> Array:
	return [
		{"id": 0, "point": Vector3(hl, 0, 0), "run_dir": Vector3.BACK, "outward": Vector3.RIGHT, "sec_min": -hw, "sec_max": hw, "use_z": true},
		{"id": 1, "point": Vector3(-hl, 0, 0), "run_dir": Vector3.BACK, "outward": Vector3.LEFT, "sec_min": -hw, "sec_max": hw, "use_z": true},
		{"id": 2, "point": Vector3(0, 0, hw), "run_dir": Vector3.RIGHT, "outward": Vector3.BACK, "sec_min": -hl, "sec_max": hl, "use_z": false},
		{"id": 3, "point": Vector3(0, 0, -hw), "run_dir": Vector3.RIGHT, "outward": Vector3.FORWARD, "sec_min": -hl, "sec_max": hl, "use_z": false},
	]


func _normalize_openings(openings: Array) -> Array:
	var grouped := {}
	for entry: Dictionary in openings:
		var edge: int = entry.get("edge", -1)
		if edge < 0:
			continue
		var start: float = entry.get("start", 0.0)
		var end: float = entry.get("end", 0.0)
		if end < start:
			var tmp := start
			start = end
			end = tmp
		if end - start <= 0.01:
			continue
		if not grouped.has(edge):
			grouped[edge] = []
		var bucket: Array = grouped[edge]
		bucket.append(Vector2(start, end))

	var result: Array = []
	var edges: Array = grouped.keys()
	edges.sort()
	for edge: int in edges:
		var ranges: Array = grouped[edge]
		if ranges.is_empty():
			continue
		ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Vector2 = ranges[0]
		for i in range(1, ranges.size()):
			var r: Vector2 = ranges[i]
			if r.x <= merged.y + 0.01:
				merged.y = maxf(merged.y, r.y)
			else:
				result.append({"edge": edge, "start": merged.x, "end": merged.y})
				merged = r
		result.append({"edge": edge, "start": merged.x, "end": merged.y})

	return result


func _detect_stair_connection(stair: Stairs, openings: Array, holes: Array) -> void:
	var tol := SNAP_TOLERANCE
	var my_inv := global_transform.affine_inverse()

	var s_size := stair.size
	var s_hl := s_size.x / 2.0
	var s_hw := s_size.z / 2.0

	var stair_xform := stair.global_transform
	var my_hl := size.x / 2.0
	var my_hw := size.z / 2.0

	var on_edge := false
	on_edge = _check_stair_endpoint(
		stair_xform * Vector3(s_hl, 0, 0),
		stair_xform * Vector3(s_hl, 0, -s_hw),
		stair_xform * Vector3(s_hl, 0, s_hw),
		my_inv, my_hl, my_hw, tol, openings) or on_edge
	on_edge = _check_stair_endpoint(
		stair_xform * Vector3(-s_hl, -s_size.y, 0),
		stair_xform * Vector3(-s_hl, -s_size.y, -s_hw),
		stair_xform * Vector3(-s_hl, -s_size.y, s_hw),
		my_inv, my_hl, my_hw, tol, openings) or on_edge

	# Cut a hole whenever the stair reaches the deck plane within tolerance.
	# Exact-height snapped stairs land at stair_y_max ~= 0 and still need a cutout.
	var stair_bot_local := my_inv * (stair_xform * Vector3(0, -s_size.y, 0))
	var stair_top_local := my_inv * (stair_xform * Vector3(0, 0, 0))
	var stair_y_min := minf(stair_bot_local.y, stair_top_local.y)
	var stair_y_max := maxf(stair_bot_local.y, stair_top_local.y)
	var intersects_deck_plane := stair_y_min < -tol and stair_y_max >= -tol
	if intersects_deck_plane:
		var corners: Array[Vector3] = [
			my_inv * (stair_xform * Vector3(-s_hl, 0, -s_hw)),
			my_inv * (stair_xform * Vector3(-s_hl, 0, s_hw)),
			my_inv * (stair_xform * Vector3(s_hl, 0, -s_hw)),
			my_inv * (stair_xform * Vector3(s_hl, 0, s_hw)),
		]
		var hole_poly := _build_stair_hole_polygon(corners, my_hl, my_hw)
		if hole_poly.size() >= 3:
			holes.append({"polygon": hole_poly})


func _build_stair_hole_polygon(corners: Array[Vector3], half_length: float, half_width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in corners:
		points.append(Vector2(corner.x, corner.z))
	if points.size() < 3:
		return PackedVector2Array()

	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].distance_to(hull[hull.size() - 1]) <= 0.0001:
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		return PackedVector2Array()

	var deck_poly := PackedVector2Array([
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
	])
	var clipped: Array = Geometry2D.intersect_polygons(deck_poly, hull)
	if clipped.is_empty():
		return PackedVector2Array()

	var best := PackedVector2Array()
	var best_area := 0.0
	for poly_variant: Variant in clipped:
		var poly: PackedVector2Array = poly_variant
		if poly.size() > 1 and poly[0].distance_to(poly[poly.size() - 1]) <= 0.0001:
			poly.remove_at(poly.size() - 1)
		var area := absf(_polygon_area(poly))
		if area > best_area:
			best_area = area
			best = poly
	if best_area > 0.0001:
		return best

	# Fallback so hole cutting still works even if polygon clipping fails unexpectedly.
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	min_x = clampf(min_x, -half_length, half_length)
	max_x = clampf(max_x, -half_length, half_length)
	min_z = clampf(min_z, -half_width, half_width)
	max_z = clampf(max_z, -half_width, half_width)
	if max_x - min_x <= 0.01 or max_z - min_z <= 0.01:
		return PackedVector2Array()
	return PackedVector2Array([
		Vector2(min_x, min_z),
		Vector2(max_x, min_z),
		Vector2(max_x, max_z),
		Vector2(min_x, max_z),
	])


func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func _openings_signature(openings: Array) -> int:
	var parts: Array[String] = []
	for opening: Dictionary in openings:
		var edge: int = opening.get("edge", -1)
		var raw_start: float = opening.get("start", 0.0)
		var raw_end: float = opening.get("end", 0.0)
		var start := snappedf(raw_start, 0.001)
		var end := snappedf(raw_end, 0.001)
		parts.append("%d:%s:%s" % [edge, str(start), str(end)])
	parts.sort()
	return "|".join(parts).hash()


func _holes_signature(holes: Array) -> int:
	var parts: Array[String] = []
	for hole: Variant in holes:
		if hole is Rect2:
			var r: Rect2 = hole
			parts.append(
				"R:%s:%s:%s:%s" % [
					str(snappedf(r.position.x, 0.001)),
					str(snappedf(r.position.y, 0.001)),
					str(snappedf(r.size.x, 0.001)),
					str(snappedf(r.size.y, 0.001)),
				]
			)
			continue

		if hole is Dictionary:
			var d: Dictionary = hole
			if d.has("polygon"):
				var poly_v: Variant = d["polygon"]
				var poly: PackedVector2Array = poly_v
				if poly.size() == 0:
					continue
				var pts: Array[String] = []
				for p in poly:
					pts.append("%s,%s" % [str(snappedf(p.x, 0.001)), str(snappedf(p.y, 0.001))])
				parts.append("P:%s" % ";".join(pts))
	parts.sort()
	return "|".join(parts).hash()


func _check_stair_endpoint(
		ep_center_global: Vector3, ep_left_global: Vector3, ep_right_global: Vector3,
		my_inv: Transform3D, my_hl: float, my_hw: float,
		tol: float, openings: Array) -> bool:

	var lc := my_inv * ep_center_global
	var ll := my_inv * ep_left_global
	var lr := my_inv * ep_right_global

	if absf(lc.y) > tol:
		return false

	var found := false

	var all_z: Array[float] = [lc.z, ll.z, lr.z]
	var all_x: Array[float] = [lc.x, ll.x, lr.x]
	var z_min := minf(minf(all_z[0], all_z[1]), all_z[2])
	var z_max := maxf(maxf(all_z[0], all_z[1]), all_z[2])
	var x_min := minf(minf(all_x[0], all_x[1]), all_x[2])
	var x_max := maxf(maxf(all_x[0], all_x[1]), all_x[2])

	if absf(lc.x - my_hl) < tol and z_max - z_min > 0.01:
		var o_min := maxf(z_min, -my_hw)
		var o_max := minf(z_max, my_hw)
		if o_max - o_min > 0.01:
			openings.append({"edge": 0, "start": o_min, "end": o_max})
			found = true

	if absf(lc.x + my_hl) < tol and z_max - z_min > 0.01:
		var o_min := maxf(z_min, -my_hw)
		var o_max := minf(z_max, my_hw)
		if o_max - o_min > 0.01:
			openings.append({"edge": 1, "start": o_min, "end": o_max})
			found = true

	if absf(lc.z - my_hw) < tol and x_max - x_min > 0.01:
		var o_min := maxf(x_min, -my_hl)
		var o_max := minf(x_max, my_hl)
		if o_max - o_min > 0.01:
			openings.append({"edge": 2, "start": o_min, "end": o_max})
			found = true

	if absf(lc.z + my_hw) < tol and x_max - x_min > 0.01:
		var o_min := maxf(x_min, -my_hl)
		var o_max := minf(x_max, my_hl)
		if o_max - o_min > 0.01:
			openings.append({"edge": 3, "start": o_min, "end": o_max})
			found = true

	return found


func add_railing_opening(edge: int, start_pos: float, end_pos: float) -> int:
	_railing_openings.append({"edge": edge, "start": start_pos, "end": end_pos})
	_rebuild()
	return _railing_openings.size() - 1


func add_deck_hole(hole: Variant) -> int:
	_deck_holes.append(hole)
	_rebuild()
	return _deck_holes.size() - 1


func clear_railing_openings() -> void:
	_railing_openings.clear()
	_rebuild()


func clear_deck_holes() -> void:
	_deck_holes.clear()
	_rebuild()


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/Platform.tscn") as PackedScene
	var preview_node: Node3D = preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)
