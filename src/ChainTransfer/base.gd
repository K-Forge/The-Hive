@tool
class_name ChainTransferBase
extends Node3D

## When true, the chain base is raised to the active (popup) position.
@export var active: bool = false:
	set(value):
		if value == active:
			return
		active = value
		_set_vertical_position(_active_pos if active else _inactive_pos)

var running: bool = false
var _inactive_pos: float = 0.0
var _active_pos: float = 0.095
var _sb_active_position: Vector3 = Vector3.ZERO
var _sb_inactive_position: Vector3 = Vector3.ZERO
var _chain_base_length: float = 2.0
var _chain_scale: int = 32
var _chain_end_scale: int = 6
var _chain_material: ShaderMaterial
var _chain_end_l_material: ShaderMaterial
var _chain_end_r_material: ShaderMaterial
var _chain_position: float = 0.0
var _chain_end_position: float = 0.0
var _collision_shape: BoxShape3D
var _prev_owner_scale_x: float = NAN

@onready var _container_body: StaticBody3D = get_node("ContainerBody")
@onready var _chain_base: Node3D = get_node("Base")
@onready var _container: Node3D = get_node("Container")
@onready var _chain: Node3D = get_node("Chain")
@onready var _sb: StaticBody3D = get_node("Chain/StaticBody3D")

func _ready() -> void:
	_chain_material = _init_material("Chain")
	_chain_end_l_material = _init_material("Chain/ChainL")
	_chain_end_r_material = _init_material("Chain/ChainR")

	_chain_position = 0.0
	_chain_end_position = 0.0
	_set_all_chain_positions(0.0, 0.0)

	var collision_shape_node := _sb.get_node("CollisionShape3D") as CollisionShape3D
	if collision_shape_node and collision_shape_node.shape:
		collision_shape_node.shape = collision_shape_node.shape.duplicate() as BoxShape3D
		_collision_shape = collision_shape_node.shape

	owner = get_parent().get_parent()

	if owner:
		var ct := owner as ChainTransfer
		if _chain_material:
			_chain_material.set_shader_parameter("Scale", ct.scale.x * _chain_scale)
		if _collision_shape:
			_collision_shape.size.x = _chain_base_length * ct.scale.x
		_scale_children(_chain_base)
		_scale_children(_container)
		_scale_children(_chain)

	_set_vertical_position(_active_pos if active else _inactive_pos)

func _physics_process(delta: float) -> void:
	var ct := owner as ChainTransfer
	if running:
		var local_left := _sb.global_transform.basis.x.normalized()
		_sb.constant_linear_velocity = local_left * ct.speed
		_sb.position = _sb_active_position
		_sb.rotation = Vector3.ZERO

		if _chain_material and ct:
			var chain_meters: float = ct.scale.x * _chain_base_length
			var chain_links_per_meter: float = round(ct.scale.x * _chain_scale) / chain_meters
			if not Simulation.is_paused():
				_chain_position += ct.speed / chain_meters * delta
			_chain_position = fmod((fmod(_chain_position, 1) + 1.0), 1)
			_chain_end_position += ct.speed * chain_links_per_meter / _chain_end_scale * delta
			_chain_end_position = fmod((fmod(_chain_end_position, 1) + 1.0), 1)
			_set_all_chain_positions(_chain_position, _chain_end_position)

	if ct and ct.scale.x != _prev_owner_scale_x:
		_prev_owner_scale_x = ct.scale.x
		if _chain_material:
			_chain_material.set_shader_parameter("Scale", ct.scale.x * _chain_scale)
		if _collision_shape:
			_collision_shape.size.x = _chain_base_length * ct.scale.x
		_scale_children(_chain_base)
		_scale_children(_container)
		_scale_children(_chain)

func turn_on() -> void:
	running = true

func turn_off() -> void:
	running = false
	_chain_position = 0.0
	_chain_end_position = 0.0
	_set_all_chain_positions(0.0, 0.0)
	_sb.position = _sb_inactive_position
	_sb.rotation = Vector3.ZERO
	_sb.constant_linear_velocity = Vector3.ZERO

func _init_material(path: String) -> ShaderMaterial:
	var m := get_node(path) as MeshInstance3D
	var mat := m.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	m.set_surface_override_material(0, mat)
	return mat

func _set_chain_position(mat: ShaderMaterial, pos: float) -> void:
	if mat:
		mat.set_shader_parameter("ChainPosition", pos)

func _set_all_chain_positions(chain_pos: float, chain_end_pos: float) -> void:
	_set_chain_position(_chain_material, chain_pos)
	_set_chain_position(_chain_end_l_material, chain_end_pos)
	_set_chain_position(_chain_end_r_material, chain_end_pos)

func _scale_children(nodes_container: Node3D) -> void:
	var ct := owner as ChainTransfer
	if ct == null:
		return
	var inv_scale_x: float = 1.0 / ct.scale.x
	for child in nodes_container.get_children():
		if child is Node3D:
			(child as Node3D).scale = Vector3(inv_scale_x, 1, 1)

func _set_vertical_position(target_y: float) -> void:
	if not is_node_ready():
		return
	if is_inside_tree():
		var tween := create_tween().set_parallel()
		for node: Node3D in [_container_body, _container, _chain]:
			tween.tween_property(node, "position", Vector3(node.position.x, target_y, node.position.z), 0.15)
	else:
		for node: Node3D in [_container_body, _container, _chain]:
			node.position = Vector3(node.position.x, target_y, node.position.z)
