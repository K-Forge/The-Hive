@tool
class_name Rack
extends ResizableNode3D

## Storage rack. Size: X = width, Z = depth. Height (Y) is num_shelves × shelf_spacing.
## Bottom level is left open.

var width: float:
	get: return size.x
var depth: float:
	get: return size.z

@export_group("Rack Configuration")
@export_range(1, 10, 1) var num_shelves: int = 4:
	set(value):
		num_shelves = value
		_apply_shelf_spacing()

## Vertical distance between shelves.
@export_range(0.5, 3.0, 0.05, "suffix:m") var shelf_spacing: float = 1.6:
	set(value):
		shelf_spacing = value
		_apply_shelf_spacing()

@export var shelf_color: Color = Color(0.8, 0.5, 0.2):
	set(value):
		shelf_color = value
		if is_node_ready():
			_update_materials()

@export var frame_color: Color = Color(0.3, 0.3, 0.3):
	set(value):
		frame_color = value
		if is_node_ready():
			_update_materials()

@export_group("Structural Support")
@export var enable_auto_poles: bool = true:
	set(value):
		enable_auto_poles = value
		if is_node_ready():
			size = _get_constrained_size(size)
			_rebuild_rack()

## Center-to-center spacing of the vertical uprights along width and depth.
@export_range(0.5, 3.0, 0.1) var pole_interval: float = 1.4:
	set(value):
		pole_interval = value
		if is_node_ready():
			size = _get_constrained_size(size)
			_rebuild_rack()

const FRAME_THICKNESS = 0.08
const SHELF_THICKNESS = 0.04

@onready var _static_body: StaticBody3D = $StaticBody3D
@onready var _frame_mi: MeshInstance3D = $StaticBody3D/FrameMesh
@onready var _shelf_mi: MeshInstance3D = $StaticBody3D/ShelfMesh

var _frame_material: StandardMaterial3D
var _shelf_material: StandardMaterial3D
var _frame_verts: PackedVector3Array = PackedVector3Array()
var _frame_normals: PackedVector3Array = PackedVector3Array()
var _shelf_verts: PackedVector3Array = PackedVector3Array()
var _shelf_normals: PackedVector3Array = PackedVector3Array()
var _collision_shapes: Array[CollisionShape3D] = []


func _init() -> void:
	super._init()
	size_default = Vector3(2.8, num_shelves * shelf_spacing, 1.4)
	# Y is governed by _get_constrained_size (num_shelves × shelf_spacing), not this floor.
	size_min = Vector3(0.5, 0.0, 0.5)


func _ready() -> void:
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = frame_color
	_shelf_material = StandardMaterial3D.new()
	_shelf_material.albedo_color = shelf_color

	_rebuild_rack()


func _on_size_changed() -> void:
	_rebuild_rack()


func _apply_shelf_spacing() -> void:
	if is_node_ready():
		size = Vector3(size.x, num_shelves * shelf_spacing, size.z)


func _get_constrained_size(new_size: Vector3) -> Vector3:
	new_size.y = num_shelves * shelf_spacing
	if enable_auto_poles:
		new_size.x = maxf(pole_interval, roundf(new_size.x / pole_interval) * pole_interval)
		new_size.z = maxf(pole_interval, roundf(new_size.z / pole_interval) * pole_interval)
	return new_size


func _update_materials() -> void:
	_frame_material.albedo_color = frame_color
	_shelf_material.albedo_color = shelf_color


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	return AABB(
		Vector3(-for_size.x / 2, 0, -for_size.z / 2),
		for_size,
	)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	# Y is num_shelves × shelf_spacing, so no vertical resize handle.
	return PackedInt32Array([0, 1, 4, 5])


func _rebuild_rack() -> void:
	if not is_node_ready():
		return

	_static_body.position = Vector3(-width / 2, 0, -depth / 2)

	_frame_verts.clear()
	_frame_normals.clear()
	_shelf_verts.clear()
	_shelf_normals.clear()
	_clear_collision_shapes()

	_create_vertical_frames()
	_create_shelves()
	_create_horizontal_supports()

	_frame_mi.mesh = _build_mesh(_frame_verts, _frame_normals, _frame_material)
	_shelf_mi.mesh = _build_mesh(_shelf_verts, _shelf_normals, _shelf_material)


func _build_mesh(verts: PackedVector3Array, normals: PackedVector3Array, material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _get_axis_positions(length: float, interval: float) -> Array[float]:
	var positions: Array[float] = [0.0]
	var pos := interval
	while pos < length - 0.001:
		positions.append(pos)
		pos += interval
	if length > 0.001:
		positions.append(length)
	return positions


func _create_vertical_frames() -> void:
	var total_height := size.y

	if enable_auto_poles:
		var x_positions := _get_axis_positions(width, pole_interval)
		var z_positions := _get_axis_positions(depth, pole_interval)

		for x_pos in x_positions:
			for z_pos in z_positions:
				_add_frame_box(
					Vector3(x_pos, total_height / 2, z_pos),
					Vector3(FRAME_THICKNESS, total_height, FRAME_THICKNESS),
				)
	else:
		for x: float in [0.0, width]:
			for z: float in [0.0, depth]:
				_add_frame_box(
					Vector3(x, total_height / 2, z),
					Vector3(FRAME_THICKNESS, total_height, FRAME_THICKNESS),
				)


func _create_shelves() -> void:
	for i in range(num_shelves):
		var y_pos := (i + 1) * shelf_spacing
		var shelf_size := Vector3(width, SHELF_THICKNESS, depth)
		var pos := Vector3(width / 2, y_pos, depth / 2)

		_append_box_verts(_shelf_verts, _shelf_normals, pos, shelf_size)
		_add_collision_box(pos, shelf_size)

		if enable_auto_poles:
			_create_load_distribution_beams(y_pos)


func _create_horizontal_supports() -> void:
	for i in range(num_shelves + 1):
		var y_pos := i * shelf_spacing
		var support_size := Vector3(width - FRAME_THICKNESS, FRAME_THICKNESS, FRAME_THICKNESS)

		_add_frame_box(Vector3(width / 2, y_pos, 0), support_size)
		_add_frame_box(Vector3(width / 2, y_pos, depth), support_size)


func _create_load_distribution_beams(y_pos: float) -> void:
	var x_positions := _get_axis_positions(width, pole_interval)
	var z_positions := _get_axis_positions(depth, pole_interval)
	var beam_y := y_pos - SHELF_THICKNESS / 2 - FRAME_THICKNESS / 2

	for z_pos in z_positions:
		for w in range(x_positions.size() - 1):
			var beam_length := x_positions[w + 1] - x_positions[w]
			_add_frame_box(
				Vector3(x_positions[w] + beam_length / 2, beam_y, z_pos),
				Vector3(beam_length, FRAME_THICKNESS, FRAME_THICKNESS),
			)

	for x_pos in x_positions:
		for d in range(z_positions.size() - 1):
			var beam_length := z_positions[d + 1] - z_positions[d]
			_add_frame_box(
				Vector3(x_pos, beam_y, z_positions[d] + beam_length / 2),
				Vector3(FRAME_THICKNESS, FRAME_THICKNESS, beam_length),
			)


func _add_frame_box(pos: Vector3, box_size: Vector3) -> void:
	_append_box_verts(_frame_verts, _frame_normals, pos, box_size)
	_add_collision_box(pos, box_size)


const BOX_FACES = [
	[Vector3.UP, [4, 5, 6, 4, 6, 7]],
	[Vector3.DOWN, [3, 2, 1, 3, 1, 0]],
	[Vector3.RIGHT, [1, 2, 6, 1, 6, 5]],
	[Vector3.LEFT, [3, 0, 4, 3, 4, 7]],
	[Vector3.BACK, [2, 3, 7, 2, 7, 6]],
	[Vector3.FORWARD, [0, 1, 5, 0, 5, 4]],
]


func _append_box_verts(verts: PackedVector3Array, normals: PackedVector3Array, pos: Vector3, box_size: Vector3) -> void:
	var h := box_size / 2
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for face: Array in BOX_FACES:
		var normal: Vector3 = face[0]
		var indices: Array = face[1]
		for idx: int in indices:
			verts.append(pos + corners[idx])
			normals.append(normal)


func _add_collision_box(pos: Vector3, box_size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = box_size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	_static_body.add_child(col, false, Node.INTERNAL_MODE_FRONT)
	_collision_shapes.append(col)


func _clear_collision_shapes() -> void:
	for col in _collision_shapes:
		if is_instance_valid(col):
			col.free()
	_collision_shapes.clear()


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/Rack.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	_disable_collisions_recursive(preview_node)
	return preview_node


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		node.disabled = true
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)
