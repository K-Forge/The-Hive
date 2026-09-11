@tool
class_name SixAxisRobot
extends Node3D

## A standard 6-axis articulated robot arm with vacuum gripper.
## Joint configuration:
## - J1: Base rotation (vertical axis)
## - J2: Shoulder (horizontal axis)
## - J3: Elbow (horizontal axis)
## - J4: Wrist rotation (forearm roll)
## - J5: Wrist pitch (horizontal axis)
## - J6: Tool rotation (end effector roll)

const BASE_SCALE := 1.0
const JOINT_LIMITS_MIN: Array[float] = [-180.0, -135.0, -160.0, -180.0, -120.0, -360.0]
const JOINT_LIMITS_MAX: Array[float] = [180.0, 135.0, 160.0, 180.0, 120.0, 360.0]
const JOINT_ANGLE_PROPS := ["j1_angle", "j2_angle", "j3_angle", "j4_angle", "j5_angle", "j6_angle"]
const JOINT_IS_Y_AXIS := [true, false, false, true, false, true]
const EOAT_PROPS := ["tool_size_x", "tool_size_z", "cup_pitch_x", "cup_pitch_z", "cup_margin_x", "cup_margin_z", "cups_enabled"]

@export_tool_button("Set Home") var action_set_home: Callable = set_home_action
@export_tool_button("Go Home") var action_go_home: Callable = go_home_action
@export_tool_button("Train Waypoint") var action_train: Callable = train_waypoint_action
@export_tool_button("Go To Waypoint") var action_go_to: Callable = go_to_waypoint_action
@export_tool_button("Delete Waypoint") var action_delete: Callable = delete_waypoint_action

@export var home_position: Array[float] = [0.0, -45.0, 90.0, 25.0, 75.0, 0.0]
@export var waypoints: Dictionary = {}
@export_range(1.0, 180.0, 1.0, "suffix:°/s") var motion_speed: float = 45.0
@export var selected_waypoint: String = ""
@export var new_waypoint_name: String = "Point1"

@export_category("Vacuum Gripper")
## Activates the vacuum gripper
@export var vacuum_on: bool = false:
	set(value):
		if value == vacuum_on:
			return
		vacuum_on = value
		_update_vacuum_state()

## Whether an object is currently held (read-only; derived from gripper state)
@export var holding_object: bool = false:
	set(_value):
		pass
	get:
		return _held_object != null

@export_category("EOAT")
## Tool width along the EOAT local X axis
@export_range(0.5, 3.0, 0.01, "or_greater", "suffix:m") var tool_size_x: float = 0.5:
	set(value):
		tool_size_x = maxf(value, 0.5)
		_apply_eoat_settings()
		update_gizmos()

## Tool length along the EOAT local Z axis
@export_range(0.5, 3.0, 0.01, "or_greater", "suffix:m") var tool_size_z: float = 0.5:
	set(value):
		tool_size_z = maxf(value, 0.5)
		_apply_eoat_settings()
		update_gizmos()

@export_range(0.01, 0.5, 0.005, "or_greater", "suffix:m") var cup_pitch_x: float = 0.1:
	set(value):
		cup_pitch_x = maxf(value, 0.01)
		_apply_eoat_settings()

@export_range(0.01, 0.5, 0.005, "or_greater", "suffix:m") var cup_pitch_z: float = 0.1:
	set(value):
		cup_pitch_z = maxf(value, 0.01)
		_apply_eoat_settings()

@export_range(0.0, 0.5, 0.005, "or_greater", "suffix:m") var cup_margin_x: float = 0.05:
	set(value):
		cup_margin_x = maxf(value, 0.0)
		_apply_eoat_settings()

@export_range(0.0, 0.5, 0.005, "or_greater", "suffix:m") var cup_margin_z: float = 0.05:
	set(value):
		cup_margin_z = maxf(value, 0.0)
		_apply_eoat_settings()

@export var cups_enabled: bool = true:
	set(value):
		cups_enabled = value
		_apply_eoat_settings()

@export_category("Joint Angles")
## Base rotation
@export_range(-180, 180, 0.1, "suffix:°") var j1_angle: float = 0.0:
	set(value):
		j1_angle = clampf(value, JOINT_LIMITS_MIN[0], JOINT_LIMITS_MAX[0])
		_update_joints()

## J2 angle
@export_range(-135, 135, 0.1, "suffix:°") var j2_angle: float = -45.0:
	set(value):
		j2_angle = clampf(value, JOINT_LIMITS_MIN[1], JOINT_LIMITS_MAX[1])
		_update_joints()

## J3 angle
@export_range(-160, 160, 0.1, "suffix:°") var j3_angle: float = 90.0:
	set(value):
		j3_angle = clampf(value, JOINT_LIMITS_MIN[2], JOINT_LIMITS_MAX[2])
		_update_joints()

## J4 rotation
@export_range(-180, 180, 0.1, "suffix:°") var j4_angle: float = 25.0:
	set(value):
		j4_angle = clampf(value, JOINT_LIMITS_MIN[3], JOINT_LIMITS_MAX[3])
		_update_joints()

## J5 pitch
@export_range(-120, 120, 0.1, "suffix:°") var j5_angle: float = 75.0:
	set(value):
		j5_angle = clampf(value, JOINT_LIMITS_MIN[4], JOINT_LIMITS_MAX[4])
		_update_joints()

## Tool rotation
@export_range(-360, 360, 0.1, "suffix:°") var j6_angle: float = 0.0:
	set(value):
		j6_angle = clampf(value, JOINT_LIMITS_MIN[5], JOINT_LIMITS_MAX[5])
		_update_joints()

@export_category("Settings")
## Scale factor for the entire robot
@export_range(0.1, 10.0, 0.1) var robot_scale: float = 1.0:
	set(value):
		robot_scale = value
		_update_scale()

@export var show_gizmos: bool = true:
	set(value):
		show_gizmos = value
		update_gizmos()

@export var show_eoat_gizmo: bool = true:
	set(value):
		show_eoat_gizmo = value
		update_gizmos()

@export_category("Communications")
@export var enable_comms: bool = false
@export var tag_group_name: String
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## Integer value selecting which waypoint to move to (0 = home, 1+ = waypoint by order).[br]Datatype: [code]INT[/code] (16-bit integer)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var command_tag: String = ""
## Rising edge triggers movement to command waypoint.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var execute_tag: String = ""
## True when robot has reached target position.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var done_tag: String = ""
## Vacuum gripper control.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var vacuum_tag: String = ""

var _command_tag := OIPCommsTag.new()
var _execute_tag := OIPCommsTag.new()
var _done_tag := OIPCommsTag.new()
var _vacuum_tag := OIPCommsTag.new()
var _last_execute: bool = false

var _base_pivot: Node3D
var _upper_arm_pivot: Node3D
var _forearm_pivot: Node3D
var _wrist_rot_pivot: Node3D
var _wrist_pitch_pivot: Node3D
var _tool_pivot: Node3D

var _suction_mesh: MeshInstance3D
var _vacuum_active_material: StandardMaterial3D

var _vacuum_area: Area3D
var _held_object: Node3D = null
var _held_rigid_body: RigidBody3D = null
var _held_object_basis: Basis = Basis.IDENTITY
var _held_object_offset: Vector3 = Vector3.ZERO
var _objects_in_range: Array[Node3D] = []

var _motion_tween: Tween = null
var _is_moving: bool = false
var _initialized: bool = false
var _solving_ik: bool = false

func _connect_vacuum_area_signals() -> void:
	if not _vacuum_area:
		return

	if not _vacuum_area.body_entered.is_connected(_on_vacuum_area_body_entered):
		_vacuum_area.body_entered.connect(_on_vacuum_area_body_entered)

	if not _vacuum_area.body_exited.is_connected(_on_vacuum_area_body_exited):
		_vacuum_area.body_exited.connect(_on_vacuum_area_body_exited)


func get_attached_tool() -> Node3D:
	if not _tool_pivot:
		return null

	for child in _tool_pivot.get_children():
		if child == _suction_mesh or child == _vacuum_area:
			continue
		if child is Node3D:
			return child as Node3D

	return null


func _find_vacuum_area_in_attached_tool() -> Area3D:
	var tool := get_attached_tool()
	if not tool:
		return null
	return tool.find_child("VacuumArea", true, false) as Area3D


func _forward_vacuum_to_tool() -> void:
	var tool := get_attached_tool()
	if not tool:
		return

	if tool.has_method("set_vacuum_enabled"):
		tool.call("set_vacuum_enabled", vacuum_on)
	elif "vacuum_on" in tool:
		tool.set("vacuum_on", vacuum_on)


func _apply_eoat_settings() -> void:
	var tool := get_attached_tool()
	if not tool:
		return

	for prop: String in EOAT_PROPS:
		if prop in tool:
			tool.set(prop, get(prop))

func _enter_tree() -> void:
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	_setup_node_references()

	if not Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.connect(_on_simulation_started)
	if not Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)


func _exit_tree() -> void:
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)


func _ready() -> void:
	_setup_node_references()
	_connect_vacuum_area_signals()
	_update_scale()
	_update_joints()
	_update_vacuum_indicator()
	_forward_vacuum_to_tool()
	_apply_eoat_settings()
	new_waypoint_name = _get_next_waypoint_name()

	if _vacuum_area:
		if not _vacuum_area.body_entered.is_connected(_on_vacuum_area_body_entered):
			_vacuum_area.body_entered.connect(_on_vacuum_area_body_entered)
		if not _vacuum_area.body_exited.is_connected(_on_vacuum_area_body_exited):
			_vacuum_area.body_exited.connect(_on_vacuum_area_body_exited)


func _physics_process(delta: float) -> void:
	_update_held_object(delta)


func _setup_node_references() -> void:
	_base_pivot = get_node_or_null("BasePivot")
	if not _base_pivot:
		return

	_initialized = true

	var shoulder_pivot := _base_pivot.get_node_or_null("ShoulderPivot")
	_upper_arm_pivot = shoulder_pivot.get_node_or_null("UpperArmPivot") if shoulder_pivot else null

	var elbow_pivot := _upper_arm_pivot.get_node_or_null("ElbowPivot") if _upper_arm_pivot else null
	_forearm_pivot = elbow_pivot.get_node_or_null("ForearmPivot") if elbow_pivot else null

	_wrist_rot_pivot = _forearm_pivot.get_node_or_null("WristRotPivot") if _forearm_pivot else null
	_wrist_pitch_pivot = _wrist_rot_pivot.get_node_or_null("WristPitchPivot") if _wrist_rot_pivot else null
	_tool_pivot = _wrist_pitch_pivot.get_node_or_null("ToolPivot") if _wrist_pitch_pivot else null

	_suction_mesh = _tool_pivot.get_node_or_null("ToolSuction") as MeshInstance3D if _tool_pivot else null
	_vacuum_area = _tool_pivot.get_node_or_null("VacuumArea") as Area3D if _tool_pivot else null

	if _tool_pivot and _vacuum_area == null:
		_vacuum_area = _find_vacuum_area_in_attached_tool()


func _update_held_object(_delta: float) -> void:
	if not _held_rigid_body or not is_instance_valid(_held_rigid_body):
		return
	if not _vacuum_area:
		return

	var cup_basis := _vacuum_area.global_transform.basis.orthonormalized()
	var tip_pos := _vacuum_area.global_position

	var box_offset := 0.1
	if _held_object and "size" in _held_object:
		box_offset = _held_object.size.y * 0.5

	_held_rigid_body.global_position = tip_pos + cup_basis * (_held_object_offset + Vector3(0, box_offset, 0))
	_held_rigid_body.global_transform.basis = cup_basis * _held_object_basis


func _validate_property(property: Dictionary) -> void:
	if property.name == "holding_object":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	
	if property.name == "selected_waypoint":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(waypoints.keys()) if waypoints.size() > 0 else "(no waypoints)"
	
	if OIPCommsSetup.validate_tag_property(property):
		return
	if property.name in ["command_tag", "execute_tag", "done_tag", "vacuum_tag"]:
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE




func _update_scale() -> void:
	if not _base_pivot:
		return
	var scale_factor := robot_scale / BASE_SCALE
	_base_pivot.scale = Vector3.ONE * scale_factor
	update_gizmos()


func _update_joints() -> void:
	if not _initialized:
		return
	
	if _base_pivot:
		_base_pivot.rotation.y = deg_to_rad(j1_angle)
	if _upper_arm_pivot:
		_upper_arm_pivot.rotation.z = deg_to_rad(j2_angle)
	if _forearm_pivot:
		_forearm_pivot.rotation.z = deg_to_rad(j3_angle)
	if _wrist_rot_pivot:
		_wrist_rot_pivot.rotation.y = deg_to_rad(j4_angle)
	if _wrist_pitch_pivot:
		_wrist_pitch_pivot.rotation.z = deg_to_rad(j5_angle)
	if _tool_pivot:
		_tool_pivot.rotation.y = deg_to_rad(j6_angle)
	
	if not _solving_ik:
		update_gizmos()


func _update_vacuum_indicator() -> void:
	if not _suction_mesh:
		return

	if vacuum_on:
		if not _vacuum_active_material:
			_vacuum_active_material = StandardMaterial3D.new()
			_vacuum_active_material.albedo_color = Color(0.2, 0.7, 0.2)
			_vacuum_active_material.emission_enabled = true
			_vacuum_active_material.emission = Color(0.1, 0.45, 0.1)
		_suction_mesh.material_override = _vacuum_active_material
	else:
		_suction_mesh.material_override = null


func get_tool_tip_position() -> Vector3:
	if _vacuum_area and is_inside_tree():
		return _vacuum_area.global_position
	return global_position if is_inside_tree() else position


func get_tool_tip_transform() -> Transform3D:
	if _vacuum_area and is_inside_tree():
		return _vacuum_area.global_transform
	return global_transform if is_inside_tree() else transform


func get_ik_pivots() -> Array[Node3D]:
	return [_base_pivot, _upper_arm_pivot, _forearm_pivot, _wrist_rot_pivot, _wrist_pitch_pivot, _tool_pivot]


func solve_ik(target_pos: Vector3, max_iterations: int = 20, tolerance: float = 0.01) -> bool:
	if not _initialized:
		return false

	stop_motion()
	_solving_ik = true
	var pivots := get_ik_pivots()
	
	for iteration in range(max_iterations):
		var tip := get_tool_tip_position()
		if tip.distance_to(target_pos) < tolerance:
			_solving_ik = false
			update_gizmos()
			return true
		
		for j in range(4, -1, -1):
			var pivot := pivots[j]
			if pivot == null:
				continue
			
			var pivot_pos := pivot.global_position
			var to_tip := get_tool_tip_position() - pivot_pos
			var to_target := target_pos - pivot_pos
			
			var axis: Vector3
			if JOINT_IS_Y_AXIS[j]:
				axis = pivot.global_transform.basis.y.normalized()
			else:
				axis = pivot.global_transform.basis.z.normalized()
			
			var proj_tip := to_tip - axis * to_tip.dot(axis)
			var proj_target := to_target - axis * to_target.dot(axis)
			
			if proj_tip.length_squared() < 0.0001 or proj_target.length_squared() < 0.0001:
				continue
			
			proj_tip = proj_tip.normalized()
			proj_target = proj_target.normalized()
			
			var dot_val := clampf(proj_tip.dot(proj_target), -1.0, 1.0)
			var angle := acos(dot_val)
			var cross := proj_tip.cross(proj_target)
			if cross.dot(axis) < 0:
				angle = -angle
			
			var current_angle: float = get(JOINT_ANGLE_PROPS[j])
			var new_angle := clampf(current_angle + rad_to_deg(angle), JOINT_LIMITS_MIN[j], JOINT_LIMITS_MAX[j])
			set(JOINT_ANGLE_PROPS[j], new_angle)
	
	_solving_ik = false
	update_gizmos()
	return get_tool_tip_position().distance_to(target_pos) < tolerance * 10.0


func _update_vacuum_state() -> void:
	_update_vacuum_indicator()
	_forward_vacuum_to_tool()

	if vacuum_on:
		_try_pick_up()
	else:
		_release_object()


func _try_pick_up() -> void:
	if _held_object != null:
		return
	
	var closest_obj: Node3D = null
	var closest_dist: float = INF
	var tip_pos := get_tool_tip_position()
	
	for obj in _objects_in_range:
		if not is_instance_valid(obj):
			continue
		
		var rigid_body: RigidBody3D = null
		if obj is RigidBody3D:
			rigid_body = obj
		elif obj.has_node("RigidBody3D"):
			rigid_body = obj.get_node("RigidBody3D")
		
		if rigid_body == null:
			continue
		
		var dist := tip_pos.distance_to(obj.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_obj = obj
	
	if closest_obj:
		_attach_object(closest_obj)


func _attach_object(obj: Node3D) -> void:
	if _held_object != null:
		return
	
	var rigid_body: RigidBody3D = null
	var target_node: Node3D = obj
	
	if obj is RigidBody3D:
		rigid_body = obj
		target_node = obj.get_parent() if obj.get_parent() is Node3D else obj
	elif obj.has_node("RigidBody3D"):
		rigid_body = obj.get_node("RigidBody3D")
		target_node = obj
	
	_held_object = target_node
	_held_rigid_body = rigid_body
	
	if rigid_body and _vacuum_area:
		var cup_basis := _vacuum_area.global_transform.basis.orthonormalized()
		var obj_basis := rigid_body.global_transform.basis.orthonormalized()
		_held_object_basis = cup_basis.inverse() * obj_basis
		var local_pos := cup_basis.inverse() * (rigid_body.global_position - _vacuum_area.global_position)
		_held_object_offset = Vector3(local_pos.x, 0.0, local_pos.z)
	else:
		_held_object_basis = Basis.IDENTITY
		_held_object_offset = Vector3.ZERO
	
	if rigid_body:
		rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid_body.freeze = true


func _release_object() -> void:
	if _held_object == null:
		return
	
	if not is_instance_valid(_held_object):
		_held_object = null
		_held_rigid_body = null
		return
	
	if _held_rigid_body and is_instance_valid(_held_rigid_body):
		_held_rigid_body.freeze = false
		_held_rigid_body.linear_velocity = Vector3.ZERO
		_held_rigid_body.angular_velocity = Vector3.ZERO

	_held_object = null
	_held_rigid_body = null


func _on_vacuum_area_body_entered(body: Node3D) -> void:
	if body not in _objects_in_range:
		_objects_in_range.append(body)
	if vacuum_on and _held_object == null:
		_try_pick_up()


func _on_vacuum_area_body_exited(body: Node3D) -> void:
	_objects_in_range.erase(body)


func set_joint_angles(angles: Array[float]) -> void:
	if angles.size() >= 1:
		j1_angle = angles[0]
	if angles.size() >= 2:
		j2_angle = angles[1]
	if angles.size() >= 3:
		j3_angle = angles[2]
	if angles.size() >= 4:
		j4_angle = angles[3]
	if angles.size() >= 5:
		j5_angle = angles[4]
	if angles.size() >= 6:
		j6_angle = angles[5]


func get_joint_angles() -> Array[float]:
	return [j1_angle, j2_angle, j3_angle, j4_angle, j5_angle, j6_angle]


func move_to_home() -> void:
	if home_position.size() >= 6:
		move_to_position(home_position)
	else:
		move_to_position([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func set_current_as_home() -> void:
	home_position = get_joint_angles()


func set_home_action() -> void:
	set_current_as_home()


func go_home_action() -> void:
	move_to_home()


func train_waypoint_action() -> void:
	train_waypoint(new_waypoint_name)
	new_waypoint_name = _get_next_waypoint_name()


func go_to_waypoint_action() -> void:
	go_to_selected_waypoint()


func delete_waypoint_action() -> void:
	delete_waypoint(selected_waypoint)


func train_waypoint(waypoint_name: String) -> void:
	if waypoint_name.is_empty():
		push_warning("SixAxisRobot: Cannot train waypoint with empty name")
		return
	var index := waypoints.size() + 1
	var indexed_name := "%d: %s" % [index, waypoint_name]
	waypoints[indexed_name] = get_joint_angles()
	selected_waypoint = indexed_name
	notify_property_list_changed()


func _get_next_waypoint_name() -> String:
	var base_name := "Point"
	var num := 1
	for wp_name: String in waypoints.keys():
		var colon_pos: int = wp_name.find(": ")
		if colon_pos != -1:
			var name_part: String = wp_name.substr(colon_pos + 2)
			if name_part.begins_with(base_name):
				var suffix: String = name_part.substr(base_name.length())
				if suffix.is_valid_int():
					num = max(num, int(suffix) + 1)
	return base_name + str(num)


func delete_waypoint(waypoint_name: String) -> void:
	if waypoint_name.is_empty():
		push_warning("SixAxisRobot: No waypoint selected to delete")
		return
	if not waypoints.has(waypoint_name):
		push_warning("SixAxisRobot: Waypoint '%s' not found" % waypoint_name)
		return
	waypoints.erase(waypoint_name)
	if selected_waypoint == waypoint_name:
		selected_waypoint = waypoints.keys()[0] if waypoints.size() > 0 else ""
	notify_property_list_changed()


func get_waypoint_names() -> Array:
	return waypoints.keys()


func go_to_waypoint(waypoint_name: String) -> void:
	if not waypoints.has(waypoint_name):
		push_warning("SixAxisRobot: Waypoint '%s' not found" % waypoint_name)
		return
	
	var target_angles: Array = waypoints[waypoint_name]
	if target_angles.size() >= 6:
		move_to_position(target_angles)


func go_to_selected_waypoint() -> void:
	go_to_waypoint(selected_waypoint)


func move_to_position(target_angles: Array, instant: bool = false) -> void:
	if target_angles.size() < 6:
		push_warning("SixAxisRobot: Invalid target angles array")
		return
	
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	
	if instant:
		j1_angle = target_angles[0]
		j2_angle = target_angles[1]
		j3_angle = target_angles[2]
		j4_angle = target_angles[3]
		j5_angle = target_angles[4]
		j6_angle = target_angles[5]
	else:
		_is_moving = true
		var current := get_joint_angles()
		
		var adjusted_targets: Array[float] = []
		for i in range(6):
			var target: float = target_angles[i]
			var wrapped := _shortest_angle_path(current[i], target)
			if wrapped >= JOINT_LIMITS_MIN[i] and wrapped <= JOINT_LIMITS_MAX[i]:
				adjusted_targets.append(wrapped)
			else:
				adjusted_targets.append(target)
		
		var max_diff: float = 0.0
		for i in range(6):
			max_diff = max(max_diff, abs(adjusted_targets[i] - current[i]))
		
		var duration: float = max(max_diff / motion_speed, 0.1)
		if Engine.is_editor_hint():
			EditorInterface.mark_scene_as_unsaved()
		_motion_tween = create_tween()
		_motion_tween.set_parallel(true)
		_motion_tween.tween_property(self, "j1_angle", adjusted_targets[0], duration)
		_motion_tween.tween_property(self, "j2_angle", adjusted_targets[1], duration)
		_motion_tween.tween_property(self, "j3_angle", adjusted_targets[2], duration)
		_motion_tween.tween_property(self, "j4_angle", adjusted_targets[3], duration)
		_motion_tween.tween_property(self, "j5_angle", adjusted_targets[4], duration)
		_motion_tween.tween_property(self, "j6_angle", adjusted_targets[5], duration)
		_motion_tween.chain().tween_callback(_on_motion_complete)


func _shortest_angle_path(from_angle: float, to_angle: float) -> float:
	var diff := fmod(to_angle - from_angle + 180.0, 360.0) - 180.0
	if diff < -180.0:
		diff += 360.0
	return from_angle + diff


func _on_motion_complete() -> void:
	_is_moving = false


func is_moving() -> bool:
	return _is_moving


func stop_motion() -> void:
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	_is_moving = false


func _on_simulation_ended() -> void:
	stop_motion()
	if _held_object != null:
		_release_object()
	_objects_in_range.clear()
	vacuum_on = false
	_last_execute = false


func _on_simulation_started() -> void:
	if not enable_comms or tag_group_name.is_empty():
		return

	_last_execute = false

	if not command_tag.is_empty():
		_command_tag.register(tag_group_name, command_tag, OIPComms.TAG_TYPE_INT16)
	if not execute_tag.is_empty():
		_execute_tag.register(tag_group_name, execute_tag, OIPComms.TAG_TYPE_BOOL)
	if not done_tag.is_empty():
		_done_tag.register(tag_group_name, done_tag, OIPComms.TAG_TYPE_BOOL)
	if not vacuum_tag.is_empty():
		_vacuum_tag.register(tag_group_name, vacuum_tag, OIPComms.TAG_TYPE_BOOL)


func _tag_group_initialized(group_name: String) -> void:
	_command_tag.on_group_initialized(group_name)
	_execute_tag.on_group_initialized(group_name)
	_done_tag.on_group_initialized(group_name)
	_vacuum_tag.on_group_initialized(group_name)
	_write_status_tags()


func _tag_group_polled(group_name: String) -> void:
	if group_name != tag_group_name:
		return

	if _vacuum_tag.is_ready():
		vacuum_on = _vacuum_tag.read_bit()

	if _execute_tag.is_ready():
		var execute := _execute_tag.read_bit()
		var rising_edge := execute and not _last_execute
		_last_execute = execute

		if rising_edge and not _is_moving:
			_execute_command()

	_write_status_tags()


func _execute_command() -> void:
	if not _command_tag.is_ready():
		return

	var cmd: int = _command_tag.read_int16()

	if cmd == 0:
		move_to_home()
	elif cmd > 0:
		var waypoint_names := waypoints.keys()
		var waypoint_index := cmd - 1
		if waypoint_index < waypoint_names.size():
			go_to_waypoint(waypoint_names[waypoint_index])
		else:
			push_warning("SixAxisRobot: Invalid waypoint index %d" % cmd)


func _write_status_tags() -> void:
	if _done_tag.is_ready():
		_done_tag.write_bit(not _is_moving)
