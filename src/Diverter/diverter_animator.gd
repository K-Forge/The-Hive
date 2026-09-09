@tool
class_name DiverterAnimator
extends Node3D

enum LightColor {
	Red = 3,
	Green = 4
}

var _red_light_material: StandardMaterial3D
var _green_light_material: StandardMaterial3D
var _part1_start_pos: Vector3
var _part1_maximum_z_pos: float = 0.32
var _part2_start_pos: Vector3
var _part2_maximum_z_pos: float = 0.65
var _part_end_start_pos: Vector3
var _part_end_maximum_z_pos: float = 1.0

var _progress: float = 0.0
var _target: float = 0.0
var _time: float = 0.25
var _distance: float = 0.75

@onready var _pusher_mesh_instance: MeshInstance3D = $Pusher
@onready var _part1: MeshInstance3D = $Pusher/part1
@onready var _part2: MeshInstance3D = $Pusher/part2
@onready var _part_end: RigidBody3D = $Pusher/PartEnd


func _ready() -> void:
	_red_light_material = _pusher_mesh_instance.mesh.surface_get_material(3).duplicate() as StandardMaterial3D
	_green_light_material = _pusher_mesh_instance.mesh.surface_get_material(4).duplicate() as StandardMaterial3D
	_pusher_mesh_instance.set_surface_override_material(3, _red_light_material)
	_pusher_mesh_instance.set_surface_override_material(4, _green_light_material)

	_part1_start_pos = _part1.position
	_part2_start_pos = _part2.position
	_part_end_start_pos = _part_end.position
	_part_end.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func set_target(extended: bool, time: float, distance: float) -> void:
	_target = 1.0 if extended else 0.0
	_time = time
	_distance = distance


func _physics_process(delta: float) -> void:
	if _progress == _target:
		return
	var step := delta / maxf(_time, 0.01)
	if _progress < _target:
		_progress = minf(_target, _progress + step)
	else:
		_progress = maxf(_target, _progress - step)
	_apply_progress()


func _apply_progress() -> void:
	var home := is_zero_approx(_progress)
	_part_end.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC if home else RigidBody3D.FREEZE_MODE_KINEMATIC
	var forward := Vector3.FORWARD
	_part1.position = _part1_start_pos + forward * _part1_maximum_z_pos * _distance * _progress
	_part2.position = _part2_start_pos + forward * _part2_maximum_z_pos * _distance * _progress
	_part_end.position = _part_end_start_pos + forward * _part_end_maximum_z_pos * _distance * _progress
	_set_lamp_light(LightColor.Green, not home)


func _set_lamp_light(light_color: int, enabled: bool) -> void:
	var current_material: StandardMaterial3D
	if light_color == LightColor.Red:
		current_material = _red_light_material
	elif light_color == LightColor.Green:
		current_material = _green_light_material

	if current_material:
		if enabled:
			current_material.emission_energy_multiplier = 1.0
		else:
			current_material.emission_energy_multiplier = 0.0
