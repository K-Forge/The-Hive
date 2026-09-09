@tool
class_name Box
extends ResizableNode3D

## Initial velocity applied to this box when simulation starts.
@export var initial_linear_velocity: Vector3 = Vector3.ZERO
## Mass of the box in kilograms.
@export_custom(PROPERTY_HINT_NONE, "suffix:kg") var mass: float = 10.0:
	set(value):
		mass = value
		if _rigid_body_3d:
			_rigid_body_3d.mass = value
## The color of the box material.
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		if _mesh_instance_3d:
			_mesh_instance_3d.set_surface_override_material(0, _get_shared_material(color))

static var _material_cache: Dictionary = {}

func _get_shared_material(c: Color) -> StandardMaterial3D:
	if not _material_cache.has(c):
		var base: StandardMaterial3D = _mesh_instance_3d.mesh.surface_get_material(0)
		var mat: StandardMaterial3D = base.duplicate()
		mat.albedo_color = c
		_material_cache[c] = mat
	return _material_cache[c]

var _initial_transform: Transform3D
var _paused: bool = false
var _enable_initial_transform: bool = false
var instanced: bool = false

@onready var _rigid_body_3d: RigidBody3D = $RigidBody3D
@onready var _mesh_instance_3d: MeshInstance3D = $RigidBody3D/MeshInstance3D


func _init() -> void:
	super._init()
	size_default = Vector3(0.6, 0.4, 0.4)


func _enter_tree() -> void:
	super._enter_tree()
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	Simulation.pause_toggled.connect(_on_simulation_set_paused)


func _ready() -> void:
	_on_size_changed()
	if color != Color.WHITE:
		set("color", color)
	_rigid_body_3d.mass = mass
	_rigid_body_3d.freeze = not Simulation.is_running()
	if Simulation.is_running():
		instanced = true
		_rigid_body_3d.linear_velocity = initial_linear_velocity


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	Simulation.pause_toggled.disconnect(_on_simulation_set_paused)
	super._exit_tree()
	if instanced:
		queue_free()


func _get_constrained_size(new_size: Vector3) -> Vector3:
	return new_size


func selected() -> void:
	if _paused or not Simulation.is_running():
		return

	if _rigid_body_3d.freeze:
		_rigid_body_3d.top_level = false
		if _rigid_body_3d.transform != Transform3D.IDENTITY:
			_rigid_body_3d.transform = Transform3D.IDENTITY
	else:
		_rigid_body_3d.top_level = true
		if transform != _rigid_body_3d.transform:
			transform = _rigid_body_3d.transform


func use() -> void:
	if EditorInterface.is_transforming():
		EditorInterface.keep_transform_freeze()
		_rigid_body_3d.freeze = true
		return
	_rigid_body_3d.freeze = not _rigid_body_3d.freeze


func _inspector_transform_committed() -> void:
	if _rigid_body_3d.freeze or not Simulation.is_running():
		return
	var target := global_transform
	PhysicsServer3D.body_set_state(_rigid_body_3d.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	_rigid_body_3d.global_transform = target
	_rigid_body_3d.linear_velocity = Vector3.ZERO
	_rigid_body_3d.angular_velocity = Vector3.ZERO
	_rigid_body_3d.reset_physics_interpolation()


func _on_size_changed() -> void:
	if not is_instance_valid(_mesh_instance_3d) or not is_instance_valid(_rigid_body_3d):
		return

	var mesh_instance := _mesh_instance_3d
	var collision_shape := _rigid_body_3d.get_node_or_null("CollisionShape3D") as CollisionShape3D

	if mesh_instance:
		mesh_instance.scale = size/2

	if collision_shape:
		var box_shape := collision_shape.shape as BoxShape3D
		if box_shape:
			box_shape.size = size


func _on_simulation_started() -> void:
	if _enable_initial_transform:
		return

	_initial_transform = global_transform
	_rigid_body_3d.linear_velocity = initial_linear_velocity
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = false
	_enable_initial_transform = true


func _on_simulation_ended() -> void:
	if instanced:
		queue_free()
	else:
		_rigid_body_3d.top_level = false
		_rigid_body_3d.transform = Transform3D.IDENTITY
		_rigid_body_3d.linear_velocity = Vector3.ZERO
		_rigid_body_3d.angular_velocity = Vector3.ZERO
		# Work around for #83
		if _enable_initial_transform:
			global_transform = _initial_transform
			_enable_initial_transform = false


func _on_simulation_set_paused(paused: bool) -> void:
	_paused = paused
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = paused
	transform = _rigid_body_3d.transform
	_rigid_body_3d.top_level = not paused
