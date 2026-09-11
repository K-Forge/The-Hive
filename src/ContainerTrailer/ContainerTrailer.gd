@tool
extends Node3D

@export var doors_open: bool = false:
	set(value):
		doors_open = value
		_update_doors()

@export_range(0.0, 350.0, 0.1, "suffix:deg") var open_angle: float = 350.0:
	set(value):
		open_angle = value
		_update_doors(true)

@export var animate_doors: bool = true
@export_range(0.0, 5.0, 0.01, "suffix:s") var animation_time: float = 0.4

var _door_left: Node3D
var _door_right: Node3D

var _left_closed_rotation: Vector3 = Vector3.ZERO
var _right_closed_rotation: Vector3 = Vector3.ZERO

var _left_tween: Tween
var _right_tween: Tween
var _initialized := false


func _ready() -> void:
	_setup_references()
	_update_doors(true)


func _setup_references() -> void:
	_door_left = get_node_or_null("Chassis/Container/Door_Left") as Node3D
	_door_right = get_node_or_null("Chassis/Container/Door_Right") as Node3D

	_left_closed_rotation = Vector3.ZERO
	_right_closed_rotation = Vector3.ZERO

	_initialized = true


func _update_doors(force_instant: bool = false) -> void:
	if not _initialized:
		return

	var left_target := _left_closed_rotation
	var right_target := _right_closed_rotation

	if doors_open:
		left_target.y = _left_closed_rotation.y - open_angle
		right_target.y = _right_closed_rotation.y + open_angle

	var instant := force_instant or not animate_doors

	_apply_rotation(_door_left, left_target, instant, true)
	_apply_rotation(_door_right, right_target, instant, false)


func _apply_rotation(door: Node3D, target_rotation: Vector3, instant: bool, is_left: bool) -> void:
	if not door:
		return

	if instant:
		door.rotation_degrees = target_rotation
		return

	if is_left and _left_tween and _left_tween.is_valid():
		_left_tween.kill()
	if not is_left and _right_tween and _right_tween.is_valid():
		_right_tween.kill()

	var tween := create_tween()
	tween.tween_property(door, "rotation_degrees", target_rotation, animation_time)

	if is_left:
		_left_tween = tween
	else:
		_right_tween = tween


func open_doors() -> void:
	doors_open = true


func close_doors() -> void:
	doors_open = false


func toggle_doors() -> void:
	doors_open = not doors_open
