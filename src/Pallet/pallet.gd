@tool
class_name Pallet
extends Node3D

## Initial velocity applied to this pallet when simulation starts.
@export var initial_linear_velocity: Vector3 = Vector3.ZERO
## Mass of the pallet, in kilograms.
@export_custom(PROPERTY_HINT_NONE, "suffix:kg") var mass: float = 20.0:
	set(value):
		mass = value
		if _rigid_body:
			_rigid_body.mass = value
## The color of the pallet material.
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
var instanced: bool = false
var _paused: bool = false
var _enable_initial_transform: bool = false

@onready var _rigid_body: RigidBody3D = $RigidBody3D
@onready var _mesh_instance_3d: MeshInstance3D = $RigidBody3D/WoodPallet

func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	Simulation.pause_toggled.connect(_on_simulation_set_paused)

func _ready() -> void:
	_rigid_body.mass = mass
	_rigid_body.freeze = not Simulation.is_running()
	if Simulation.is_running():
		instanced = true
		_rigid_body.linear_velocity = initial_linear_velocity
	if color != Color.WHITE:
		set("color", color)

func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	Simulation.pause_toggled.disconnect(_on_simulation_set_paused)
	if instanced:
		queue_free()

func selected() -> void:
	if _paused or not Simulation.is_running():
		return
	
	if _rigid_body.freeze:
		_rigid_body.top_level = false
		if _rigid_body.transform != Transform3D.IDENTITY:
			_rigid_body.transform = Transform3D.IDENTITY
	else:
		_rigid_body.top_level = true
		if transform != _rigid_body.transform:
			transform = _rigid_body.transform

func use() -> void:
	if EditorInterface.is_transforming():
		EditorInterface.keep_transform_freeze()
		_rigid_body.freeze = true
		return
	_rigid_body.freeze = not _rigid_body.freeze

func _inspector_transform_committed() -> void:
	if _rigid_body.freeze or not Simulation.is_running():
		return
	var target := global_transform
	PhysicsServer3D.body_set_state(_rigid_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	_rigid_body.global_transform = target
	_rigid_body.linear_velocity = Vector3.ZERO
	_rigid_body.angular_velocity = Vector3.ZERO
	_rigid_body.reset_physics_interpolation()

func _on_simulation_started() -> void:
	if _enable_initial_transform:
		return
	
	_initial_transform = global_transform
	_rigid_body.linear_velocity = initial_linear_velocity
	_rigid_body.top_level = true
	_rigid_body.freeze = false
	_enable_initial_transform = true

func _on_simulation_ended() -> void:
	if instanced:
		queue_free()
	else:
		_rigid_body.top_level = false
		_rigid_body.transform = Transform3D.IDENTITY
		_rigid_body.linear_velocity = Vector3.ZERO
		_rigid_body.angular_velocity = Vector3.ZERO
		# Work around for #83
		if _enable_initial_transform:
			global_transform = _initial_transform
			_enable_initial_transform = false

func _on_simulation_set_paused(paused: bool) -> void:
	_paused = paused
	_rigid_body.top_level = true
	_rigid_body.freeze = paused
	transform = _rigid_body.transform
	_rigid_body.top_level = not paused
