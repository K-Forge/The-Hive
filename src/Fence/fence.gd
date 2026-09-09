@tool
class_name Fence
extends ResizableNode3D


@export var post_color: Color = Color(0.95, 0.74, 0.06):
	set(value):
		post_color = value
		_update_material_color()

@export var mesh_color: Color = Color(0.05, 0.05, 0.05):
	set(value):
		mesh_color = value
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

var _post_material: ShaderMaterial
var _mesh_material: ShaderMaterial


func _init() -> void:
	super._init()
	size_default = Vector3(4.0, FenceMesh.FENCE_HEIGHT, FenceMesh.POST_SIZE)
	size_min = Vector3(0.5, 0.5, FenceMesh.POST_SIZE)


static var instances: Array[Fence] = []


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
	_post_material = FenceMesh.create_material(post_color)
	_mesh_material = FenceMesh.create_material(mesh_color)


func _update_material_color() -> void:
	if _post_material:
		_post_material.set_shader_parameter("color", post_color)
	if _mesh_material:
		_mesh_material.set_shader_parameter("color", mesh_color)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 2, 3])


func _get_constrained_size(new_size: Vector3) -> Vector3:
	new_size.x = maxf(new_size.x, 0.5)
	new_size.y = maxf(new_size.y, 0.5)
	new_size.z = FenceMesh.POST_SIZE
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

	_mesh_instance.mesh = FenceMesh.create(length, height, omit_post_start, omit_post_end)

	if _mesh_instance.mesh and _mesh_instance.mesh.get_surface_count() >= 2:
		_mesh_instance.set_surface_override_material(0, _post_material)
		_mesh_instance.set_surface_override_material(1, _mesh_material)

	if _collision_shape and _collision_shape.shape is BoxShape3D:
		(_collision_shape.shape as BoxShape3D).size = Vector3(
			length, height, FenceMesh.POST_SIZE)
		_collision_shape.position = Vector3(0, height / 2.0, 0)


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/Fence.tscn") as PackedScene
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
