@tool
class_name LegFooting
extends RefCounted


static func resolve_foot(conveyor: Node3D, belt_bottom_world: Vector3,
		legs_normal_world: Vector3, fallback_plane: Plane) -> Variant:
	var foot_v: Variant = _resolve_foot(conveyor, belt_bottom_world, legs_normal_world, fallback_plane)
	if foot_v == null:
		return null
	var column_bottom: Vector3 = (foot_v as Vector3) - legs_normal_world * _CROSS_DEPTH
	if _column_crosses_conveyor(conveyor, belt_bottom_world, column_bottom):
		return null
	return foot_v


static func _resolve_foot(conveyor: Node3D, belt_bottom_world: Vector3,
		legs_normal_world: Vector3, fallback_plane: Plane) -> Variant:
	if conveyor.is_inside_tree() and Engine.is_in_physics_frame():
		var world := conveyor.get_world_3d()
		if world != null and world.direct_space_state != null:
			var exclude_rids: Array[RID] = []
			_collect_collision_rids(conveyor, exclude_rids)
			var query := PhysicsRayQueryParameters3D.new()
			query.from = belt_bottom_world
			query.to = belt_bottom_world - legs_normal_world * 100.0
			query.exclude = exclude_rids
			var hit := world.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				return hit.position
	var foot_v: Variant = fallback_plane.intersects_ray(belt_bottom_world, -legs_normal_world)
	if foot_v == null:
		foot_v = fallback_plane.intersects_ray(belt_bottom_world, legs_normal_world)
	return foot_v


const _CROSS_INSET: float = 0.06

const _CROSS_DEPTH: float = 0.2


# Geometric, not a physics ray — must also work on idle-frame rebuild paths.
static func _column_crosses_conveyor(conveyor: Node3D, top_world: Vector3, foot_world: Vector3) -> bool:
	for obstacle: Dictionary in _crossing_obstacles(conveyor):
		var inv: Transform3D = obstacle["inv"]
		var box: AABB = obstacle["box"]
		if box.intersects_segment(inv * top_world, inv * foot_world):
			return true
	return false


static var _obstacles_for_id: int = 0
static var _obstacles_process_frame: int = -1
static var _obstacles_physics_frame: int = -1
static var _obstacles: Array = []


static func _crossing_obstacles(conveyor: Node3D) -> Array:
	if conveyor.get_instance_id() == _obstacles_for_id \
			and Engine.get_process_frames() == _obstacles_process_frame \
			and Engine.get_physics_frames() == _obstacles_physics_frame:
		return _obstacles
	var out: Array = []
	if conveyor.is_inside_tree():
		for n: Node3D in ConveyorSnapping._candidates_near(conveyor, 0.3):
			if n == conveyor or not is_instance_valid(n) or not n.is_inside_tree():
				continue
			if not (&"leg_model_scene" in n):
				continue
			if conveyor.is_ancestor_of(n) or n.is_ancestor_of(conveyor):
				continue
			var box: AABB = _conveyor_local_box(n)
			if box.size == Vector3.ZERO:
				continue
			var mx: float = minf(_CROSS_INSET, box.size.x * 0.49)
			var mz: float = minf(_CROSS_INSET, box.size.z * 0.49)
			box.position += Vector3(mx, 0.0, mz)
			box.size -= Vector3(mx * 2.0, 0.0, mz * 2.0)
			out.append({"inv": n.global_transform.affine_inverse(), "box": box})
	_obstacles_for_id = conveyor.get_instance_id()
	_obstacles_process_frame = Engine.get_process_frames()
	_obstacles_physics_frame = Engine.get_physics_frames()
	_obstacles = out
	return out


static func _conveyor_local_box(n: Node3D) -> AABB:
	if &"local_bbox" in n:
		var bb: AABB = n.get(&"local_bbox")
		if bb.size != Vector3.ZERO:
			return bb
	if &"size" in n:
		var s: Vector3 = n.get(&"size")
		if s != Vector3.ZERO:
			return AABB(-s * 0.5, s)
	return AABB()


static func _collect_collision_rids(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children(true):
		_collect_collision_rids(child, out)


static func capture_leg_state(node: Node3D) -> Dictionary:
	var s: Dictionary = {"xform": node.global_transform}
	if &"size" in node:
		s["size"] = node.get(&"size")
	if &"floor_plane" in node:
		s["floor_plane"] = node.get(&"floor_plane")
	return s


static func legs_state_changed(node: Node3D, last: Dictionary) -> bool:
	if last.is_empty():
		return true
	if node.global_transform != last.get("xform"):
		return true
	if &"size" in node and node.get(&"size") != last.get("size"):
		return true
	if &"floor_plane" in node and node.get(&"floor_plane") != last.get("floor_plane"):
		return true
	return false
