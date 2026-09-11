@tool
class_name GuardRail
extends ResizableNode3D

## OSHA-compliant safety guard rail. X = run length, Y = height, faces local +Z.

@export var steel_color: Color = Color(0.95, 0.74, 0.06):
	set(value):
		steel_color = value
		_update_material_color()

@export_storage var omit_post_start: bool = false:
	set(value):
		omit_post_start = value
		if is_node_ready():
			_rebuild()

@export_storage var omit_post_end: bool = false:
	set(value):
		omit_post_end = value
		if is_node_ready():
			_rebuild()

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

var _material: ShaderMaterial


func _init() -> void:
	super._init()
	size_default = Vector3(4.0, GuardRailMesh.RAILING_HEIGHT, 0.04)
	size_min = Vector3(0.5, 0.3, 0.04)


static var instances: Array[GuardRail] = []


func _enter_tree() -> void:
	super._enter_tree()
	if has_meta("is_preview"):
		return
	if not instances.has(self):
		instances.append(self)


func _exit_tree() -> void:
	super._exit_tree()
	instances.erase(self)


func _ready() -> void:
	if _collision_shape and _collision_shape.shape:
		_collision_shape.shape = _collision_shape.shape.duplicate() as BoxShape3D
	_setup_material()
	_rebuild()


func _setup_material() -> void:
	_material = GuardRailMesh.create_material()
	_update_material_color()


func _update_material_color() -> void:
	if _material:
		_material.set_shader_parameter("color", steel_color)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 2, 3])


func _get_constrained_size(new_size: Vector3) -> Vector3:
	new_size.x = maxf(new_size.x, 0.5)
	new_size.y = maxf(new_size.y, 0.3)
	new_size.z = 0.04
	return new_size


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	var half_x := for_size.x * 0.5
	return AABB(
		Vector3(-half_x, 0, 0),
		Vector3(for_size.x, for_size.y, 0))


func _on_size_changed() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_instance_valid(_mesh_instance):
		return

	var length := size.x
	var height := size.y

	_mesh_instance.mesh = GuardRailMesh.create(length, height, omit_post_start, omit_post_end)

	if _mesh_instance.mesh and _mesh_instance.mesh.get_surface_count() > 0:
		_mesh_instance.set_surface_override_material(0, _material)

	if _collision_shape and _collision_shape.shape is BoxShape3D:
		(_collision_shape.shape as BoxShape3D).size = Vector3(
			length, height, GuardRailMesh.POST_SIZE)
		_collision_shape.position = Vector3(0, height / 2.0, 0)


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/GuardRail.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
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
