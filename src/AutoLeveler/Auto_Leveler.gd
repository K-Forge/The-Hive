@tool
extends Node3D

@export_tool_button("Run Auto Level") var action_run: Callable = run_cycle
@export_tool_button("Reset Auto Level") var action_reset: Callable = reset_pose

@export var auto_play_in_ready: bool = false

@export_range(-45.0, 45.0, 0.1, "suffix:deg") var main_start_angle: float = 0.0
@export_range(-45.0, 45.0, 0.1, "suffix:deg") var main_peak_angle: float = 6.0
@export_range(-45.0, 45.0, 0.1, "suffix:deg") var main_settle_angle: float = 3.0

@export_range(-180.0, 180.0, 0.1, "suffix:deg") var lip_closed_angle: float = -90.0
@export_range(-180.0, 180.0, 0.1, "suffix:deg") var lip_open_angle: float = 0.0

@export_range(0.01, 5.0, 0.01, "suffix:s") var main_raise_time: float = 0.6
@export_range(0.01, 5.0, 0.01, "suffix:s") var lip_open_time: float = 0.35
@export_range(0.01, 5.0, 0.01, "suffix:s") var main_settle_time: float = 0.45

@export var main_rotate_axis: Vector3 = Vector3(1.0, 0.0, 0.0)
@export var lip_rotate_axis: Vector3 = Vector3(1.0, 0.0, 0.0)

var _main: Node3D
var _lip: Node3D
var _tween: Tween


func _ready() -> void:
	_cache_parts()
	reset_pose()

	if auto_play_in_ready and not Engine.is_editor_hint():
		run_cycle()


func _cache_parts() -> void:
	_main = find_child("AutoLeveler_Lift_Main", true, false) as Node3D
	_lip = find_child("AutoLeveler_Lift_Lip", true, false) as Node3D


func reset_pose() -> void:
	_cache_parts()

	if _tween and _tween.is_valid():
		_tween.kill()

	if _main:
		_set_axis_rotation_degrees(_main, main_rotate_axis, main_start_angle)

	if _lip:
		_set_axis_rotation_degrees(_lip, lip_rotate_axis, lip_closed_angle)


func run_cycle() -> void:
	_cache_parts()

	if not _main or not _lip:
		push_warning("AutoLeveler: Missing AutoLeveler_Lift_Main or AutoLeveler_Lift_Lip")
		return

	if _tween and _tween.is_valid():
		_tween.kill()

	reset_pose()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)

	_tween.tween_method(
		func(v: float) -> void: _set_axis_rotation_degrees(_main, main_rotate_axis, v),
		main_start_angle,
		main_peak_angle,
		main_raise_time
	)

	_tween.tween_method(
		func(v: float) -> void: _set_axis_rotation_degrees(_lip, lip_rotate_axis, v),
		lip_closed_angle,
		lip_open_angle,
		lip_open_time
	)

	_tween.tween_method(
		func(v: float) -> void: _set_axis_rotation_degrees(_main, main_rotate_axis, v),
		main_peak_angle,
		main_settle_angle,
		main_settle_time
	)


func _set_axis_rotation_degrees(node: Node3D, axis: Vector3, angle_deg: float) -> void:
	var rot := node.rotation_degrees
	var a := axis.normalized()

	if abs(a.x) > 0.5:
		rot.x = angle_deg
	if abs(a.y) > 0.5:
		rot.y = angle_deg
	if abs(a.z) > 0.5:
		rot.z = angle_deg

	node.rotation_degrees = rot
