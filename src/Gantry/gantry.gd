@tool
class_name Gantry
extends Node3D

## Art-driven 3-axis Cartesian gantry with vacuum gripper.
## Axis configuration:
## - X: travel along frame length
## - Y: travel along frame width
## - Z: vertical travel down from bridge

const DEFAULT_STRETCH_LENGTH := 4.0
const CARRIAGE_SIZE := 0.12
const TOOL_HEIGHT := 0.08
const Z_ACTUATOR_VERTICAL_OFFSET := 0.25

@export_tool_button("Set Home") var action_set_home: Callable = set_home_action
@export_tool_button("Go Home") var action_go_home: Callable = go_home_action
@export_tool_button("Train Waypoint") var action_train: Callable = train_waypoint_action
@export_tool_button("Go To Waypoint") var action_go_to: Callable = go_to_waypoint_action
@export_tool_button("Delete Waypoint") var action_delete: Callable = delete_waypoint_action

@export var home_position: Array[float] = [0.0, 0.0, 0.0]
@export var waypoints: Dictionary = {}
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var motion_speed: float = 1.0
@export var selected_waypoint: String = ""
@export var new_waypoint_name: String = "Point1"

@export_category("Frame Size")
@export_range(0.5, 20.0, 0.01, "suffix:m") var frame_length: float = 4.0:
	set(value):
		frame_length = maxf(value, 0.5)
		x_position = clampf(x_position, get_x_range().x, get_x_range().y)
		_rebuild_geometry()

@export_range(0.3, 10.0, 0.01, "suffix:m") var frame_width: float = 2.0:
	set(value):
		frame_width = maxf(value, 0.3)
		y_position = clampf(y_position, get_y_range().x, get_y_range().y)
		_rebuild_geometry()

@export_range(0.5, 10.0, 0.01, "suffix:m") var frame_height: float = 1.0:
	set(value):
		frame_height = maxf(value, 0.5)
		z_position = clampf(z_position, 0.0, _get_max_z_travel())
		_rebuild_geometry()

@export_category("Axis Positions")
@export_range(-10.0, 10.0, 0.001, "suffix:m") var x_position: float = 0.0:
	set(value):
		x_position = clampf(value, get_x_range().x, get_x_range().y)
		_update_axis_positions()

@export_range(-10.0, 10.0, 0.001, "suffix:m") var y_position: float = 0.0:
	set(value):
		y_position = clampf(value, get_y_range().x, get_y_range().y)
		_update_axis_positions()

@export_range(0.0, 10.0, 0.001, "suffix:m") var z_position: float = 0.0:
	set(value):
		z_position = clampf(value, 0.0, _get_max_z_travel())
		_update_axis_positions()

@export_category("Layout Offsets")
@export var beam_front_offset: Vector3 = Vector3.ZERO
@export var beam_back_offset: Vector3 = Vector3.ZERO
@export var x_carriage_offset: Vector3 = Vector3(0.0, 0.15, 0.0)
@export var beam_secondary_offset: Vector3 = Vector3.ZERO
@export var secondary_followers_offset: Vector3 = Vector3.ZERO
@export var y_carriage_offset: Vector3 = Vector3.ZERO
@export var z_actuator_offset: Vector3 = Vector3.ZERO

@export var leg_top_offset: Vector3 = Vector3.ZERO
@export var leg_bottom_offset: Vector3 = Vector3.ZERO

@export var beam_maincarriage_01_offset: Vector3 = Vector3.ZERO
@export var beam_maincarriage_02_offset: Vector3 = Vector3.ZERO

@export var beam_lift_offset: Vector3 = Vector3.ZERO
@export var tool_offset: Vector3 = Vector3.ZERO
@export var vacuum_area_offset: Vector3 = Vector3.ZERO

@export_category("Vacuum Gripper")
@export var vacuum_on: bool = false:
	set(value):
		vacuum_on = value
		_update_vacuum_state()

@export var holding_object: bool = false:
	set(value):
		holding_object = value
	get:
		return _held_object != null

@export_category("Settings")
@export var show_gizmos: bool = true:
	set(value):
		show_gizmos = value
		update_gizmos()

@export_category("Communications")
@export var enable_comms: bool = false
@export var tag_group_name: String
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

## Integer value selecting which waypoint to move to (0 = home, 1+ = waypoint by order).
@export var command_tag: String = ""
## Rising edge triggers movement to command waypoint.
@export var execute_tag: String = ""
## True when gantry has reached target position.
@export var done_tag: String = ""
## Vacuum gripper control.
@export var vacuum_tag: String = ""

var _command_tag := OIPCommsTag.new()
var _execute_tag := OIPCommsTag.new()
var _done_tag := OIPCommsTag.new()
var _vacuum_tag := OIPCommsTag.new()
var _last_execute: bool = false

var _frame: Node3D
var _x_carriage: Node3D
var _y_carriage: Node3D
var _z_actuator: Node3D

var _leg_fl: Node3D
var _leg_fr: Node3D
var _leg_bl: Node3D
var _leg_br: Node3D

var _leg_main_fl: Node3D
var _leg_main_fr: Node3D
var _leg_main_bl: Node3D
var _leg_main_br: Node3D

var _leg_top_fl: Node3D
var _leg_top_fr: Node3D
var _leg_top_bl: Node3D
var _leg_top_br: Node3D

var _leg_bottom_fl: Node3D
var _leg_bottom_fr: Node3D
var _leg_bottom_bl: Node3D
var _leg_bottom_br: Node3D

var _beam_front: Node3D
var _beam_back: Node3D
var _beam_front_main: Node3D
var _beam_back_main: Node3D

var _beam_secondary: Node3D
var _beam_secondary_followers: Node3D
var _beam_maincarriage_01: Node3D
var _beam_maincarriage_02: Node3D

var _carriage: Node3D
var _beam_lift: Node3D
var _tool: Node3D
var _vacuum_area: Area3D

var _held_object: Node3D = null
var _held_rigid_body: RigidBody3D = null
var _held_object_basis: Basis = Basis.IDENTITY
var _objects_in_range: Array[Node3D] = []

var _motion_tween: Tween = null
var _is_moving: bool = false
var _initialized: bool = false


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
	_rebuild_geometry()
	new_waypoint_name = _get_next_waypoint_name()

	if _vacuum_area:
		if not _vacuum_area.body_entered.is_connected(_on_vacuum_area_body_entered):
			_vacuum_area.body_entered.connect(_on_vacuum_area_body_entered)
		if not _vacuum_area.body_exited.is_connected(_on_vacuum_area_body_exited):
			_vacuum_area.body_exited.connect(_on_vacuum_area_body_exited)


func _process(_delta: float) -> void:
	_update_held_object()


func _setup_node_references() -> void:
	_frame = get_node_or_null("Frame")
	_x_carriage = get_node_or_null("XCarriage")
	_y_carriage = _x_carriage.get_node_or_null("YCarriage") if _x_carriage else null
	_z_actuator = _y_carriage.get_node_or_null("ZActuator") if _y_carriage else null

	if not _frame or not _x_carriage or not _y_carriage or not _z_actuator:
		_initialized = false
		return

	_leg_fl = _frame.get_node_or_null("Leg_FL")
	_leg_fr = _frame.get_node_or_null("Leg_FR")
	_leg_bl = _frame.get_node_or_null("Leg_BL")
	_leg_br = _frame.get_node_or_null("Leg_BR")

	_leg_main_fl = _leg_fl.get_node_or_null("Leg_Main") if _leg_fl else null
	_leg_main_fr = _leg_fr.get_node_or_null("Leg_Main") if _leg_fr else null
	_leg_main_bl = _leg_bl.get_node_or_null("Leg_Main") if _leg_bl else null
	_leg_main_br = _leg_br.get_node_or_null("Leg_Main") if _leg_br else null

	_leg_top_fl = _leg_fl.get_node_or_null("Leg_Top") if _leg_fl else null
	_leg_top_fr = _leg_fr.get_node_or_null("Leg_Top") if _leg_fr else null
	_leg_top_bl = _leg_bl.get_node_or_null("Leg_Top") if _leg_bl else null
	_leg_top_br = _leg_br.get_node_or_null("Leg_Top") if _leg_br else null

	_leg_bottom_fl = _leg_fl.get_node_or_null("Leg_Bottom") if _leg_fl else null
	_leg_bottom_fr = _leg_fr.get_node_or_null("Leg_Bottom") if _leg_fr else null
	_leg_bottom_bl = _leg_bl.get_node_or_null("Leg_Bottom") if _leg_bl else null
	_leg_bottom_br = _leg_br.get_node_or_null("Leg_Bottom") if _leg_br else null

	_beam_front = _frame.get_node_or_null("Beam_Front")
	_beam_back = _frame.get_node_or_null("Beam_Back")
	_beam_front_main = _beam_front.get_node_or_null("Beam_Main") if _beam_front else null
	_beam_back_main = _beam_back.get_node_or_null("Beam_Main") if _beam_back else null

	_beam_secondary = _x_carriage.get_node_or_null("Beam_Secondary")
	_beam_secondary_followers = _x_carriage.get_node_or_null("Beam_Secondary_Followers")
	_beam_maincarriage_01 = _beam_secondary_followers.get_node_or_null("Beam_MainCarriage_01") if _beam_secondary_followers else null
	_beam_maincarriage_02 = _beam_secondary_followers.get_node_or_null("Beam_MainCarriage_02") if _beam_secondary_followers else null

	_carriage = _y_carriage.get_node_or_null("Carriage")
	_beam_lift = _z_actuator.get_node_or_null("Beam_Lift")
	_tool = _z_actuator.get_node_or_null("Tool")
	_vacuum_area = _z_actuator.get_node_or_null("VacuumArea")

	_initialized = true


func _rebuild_geometry() -> void:
	if not _initialized:
		return

	var half_l := frame_length * 0.5
	var half_w := frame_width * 0.5

	if _leg_fl:
		_leg_fl.position = Vector3(-half_l, 0.0, -half_w)
	if _leg_fr:
		_leg_fr.position = Vector3(half_l, 0.0, -half_w)
	if _leg_bl:
		_leg_bl.position = Vector3(-half_l, 0.0, half_w)
	if _leg_br:
		_leg_br.position = Vector3(half_l, 0.0, half_w)

	_apply_stretch(_leg_main_fl, "y", frame_height)
	_apply_stretch(_leg_main_fr, "y", frame_height)
	_apply_stretch(_leg_main_bl, "y", frame_height)
	_apply_stretch(_leg_main_br, "y", frame_height)

	_position_leg_parts(_leg_top_fl, _leg_bottom_fl)
	_position_leg_parts(_leg_top_fr, _leg_bottom_fr)
	_position_leg_parts(_leg_top_bl, _leg_bottom_bl)
	_position_leg_parts(_leg_top_br, _leg_bottom_br)

	if _beam_front:
		_beam_front.position = Vector3(0.0, frame_height, -half_w) + beam_front_offset
	if _beam_back:
		_beam_back.position = Vector3(0.0, frame_height, half_w) + beam_back_offset

	_apply_stretch(_beam_front_main, "x", frame_length)
	_apply_stretch(_beam_back_main, "x", frame_length)

	z_position = clampf(z_position, 0.0, _get_max_z_travel())
	_update_axis_positions()
	update_gizmos()


func _update_axis_positions() -> void:
	if not _initialized:
		return

	if _x_carriage:
		_x_carriage.position = Vector3(x_position, frame_height, 0.0) + x_carriage_offset

	if _beam_secondary:
		_beam_secondary.position = beam_secondary_offset
		_apply_stretch(_beam_secondary, "z", frame_width)

	if _beam_secondary_followers:
		_beam_secondary_followers.position = secondary_followers_offset

	_position_secondary_parts()

	if _y_carriage:
		_y_carriage.position = Vector3(0.0, 0.0, y_position) + y_carriage_offset

	if _carriage:
		_carriage.position = Vector3.ZERO

	if _z_actuator:
		_z_actuator.position = Vector3(0.0, frame_height - Z_ACTUATOR_VERTICAL_OFFSET, 0.0) + z_actuator_offset

	_update_tool_position()
	update_gizmos()


func _update_tool_position() -> void:
	if not _initialized:
		return

	var lift_length := frame_height
	_apply_stretch(_beam_lift, "y", lift_length)

	var lift_top_y := -z_position
	if _beam_lift:
		_beam_lift.position = Vector3(0.0, lift_top_y, 0.0) + beam_lift_offset

	var tool_y := lift_top_y - lift_length
	if _tool:
		_tool.position = Vector3(0.0, tool_y, 0.0) + tool_offset

	if _vacuum_area:
		_vacuum_area.position = Vector3(0.0, tool_y, 0.0) + vacuum_area_offset


func _position_leg_parts(leg_top: Node3D, leg_bottom: Node3D) -> void:
	if leg_top:
		leg_top.position = Vector3(0.0, frame_height, 0.0) + leg_top_offset
	if leg_bottom:
		leg_bottom.position = leg_bottom_offset


func _position_secondary_parts() -> void:
	var half_w := frame_width * 0.5
	if _beam_maincarriage_01:
		_beam_maincarriage_01.position = Vector3(0.0, 0.0, half_w) + beam_maincarriage_01_offset
	if _beam_maincarriage_02:
		_beam_maincarriage_02.position = Vector3(0.0, 0.0, -half_w) + beam_maincarriage_02_offset


func _apply_stretch(node: Node3D, axis: String, target_length: float) -> void:
	if not node:
		return

	var ratio := maxf(target_length / DEFAULT_STRETCH_LENGTH, 0.001)
	var s := node.scale

	match axis:
		"x":
			s.x = ratio
		"y":
			s.y = ratio
		"z":
			s.z = ratio

	node.scale = s
	_push_uv_multiplier(node, ratio)


func _push_uv_multiplier(node: Node, ratio: float) -> void:
	if not node:
		return

	if node.has_method("set_u_tiling_multiplier"):
		node.call("set_u_tiling_multiplier", ratio)
		return

	if "u_tiling_multiplier" in node:
		node.set("u_tiling_multiplier", ratio)
		return

	for child in node.get_children():
		if child.has_method("set_u_tiling_multiplier"):
			child.call("set_u_tiling_multiplier", ratio)
			return
		if "u_tiling_multiplier" in child:
			child.set("u_tiling_multiplier", ratio)
			return


func get_tool_tip_position() -> Vector3:
	if _vacuum_area and is_inside_tree():
		return _vacuum_area.global_position
	if _tool and is_inside_tree():
		return _tool.global_position
	return global_position if is_inside_tree() else position


func get_tool_tip_transform() -> Transform3D:
	if _vacuum_area and is_inside_tree():
		return _vacuum_area.global_transform
	if _tool and is_inside_tree():
		return _tool.global_transform
	return global_transform if is_inside_tree() else transform


func get_axis_positions() -> Array[float]:
	return [x_position, y_position, z_position]


func set_axis_positions(positions: Array[float]) -> void:
	if positions.size() >= 1:
		x_position = positions[0]
	if positions.size() >= 2:
		y_position = positions[1]
	if positions.size() >= 3:
		z_position = positions[2]


func get_x_range() -> Vector2:
	var half := maxf((frame_length - CARRIAGE_SIZE) / 2.0, 0.0)
	return Vector2(-half, half)


func get_y_range() -> Vector2:
	var half := maxf((frame_width - CARRIAGE_SIZE) / 2.0, 0.0)
	return Vector2(-half, half)


func get_z_range() -> Vector2:
	return Vector2(0.0, _get_max_z_travel())


func _get_max_z_travel() -> float:
	return maxf(frame_height - Z_ACTUATOR_VERTICAL_OFFSET + 0.025, 0.0)


# --- Vacuum gripper ---


func _update_vacuum_state() -> void:
	if vacuum_on:
		_try_pick_up()
	else:
		_release_object()


func _update_held_object() -> void:
	if not _held_rigid_body or not is_instance_valid(_held_rigid_body):
		return
	if not _vacuum_area:
		return

	var tip_pos := _vacuum_area.global_position
	var cup_dir := -_vacuum_area.global_transform.basis.y.normalized()

	var box_offset := 0.1
	if _held_object and "size" in _held_object:
		box_offset = _held_object.size.y * 0.5

	var target_pos := tip_pos + cup_dir * box_offset
	_held_rigid_body.global_position = target_pos
	var area_basis := _vacuum_area.global_transform.basis.orthonormalized()
	_held_rigid_body.global_transform.basis = area_basis * _held_object_basis


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
		var area_basis := _vacuum_area.global_transform.basis.orthonormalized()
		var obj_basis := rigid_body.global_transform.basis.orthonormalized()
		_held_object_basis = area_basis.inverse() * obj_basis
	else:
		_held_object_basis = Basis.IDENTITY

	if rigid_body:
		rigid_body.gravity_scale = 0

	holding_object = true


func _release_object() -> void:
	if _held_object == null:
		return

	if not is_instance_valid(_held_object):
		_held_object = null
		_held_rigid_body = null
		holding_object = false
		return

	if _held_rigid_body and is_instance_valid(_held_rigid_body):
		_held_rigid_body.gravity_scale = 1
		_held_rigid_body.linear_velocity = Vector3.ZERO
		_held_rigid_body.angular_velocity = Vector3.ZERO

	_held_object = null
	_held_rigid_body = null
	holding_object = false


func _on_vacuum_area_body_entered(body: Node3D) -> void:
	if body not in _objects_in_range:
		_objects_in_range.append(body)
	if vacuum_on and _held_object == null:
		_try_pick_up()


func _on_vacuum_area_body_exited(body: Node3D) -> void:
	_objects_in_range.erase(body)


# --- Waypoint system ---


func move_to_home() -> void:
	if home_position.size() >= 3:
		move_to_position(home_position)
	else:
		move_to_position([0.0, 0.0, 0.0])


func set_current_as_home() -> void:
	home_position = get_axis_positions()


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
		push_warning("Gantry: Cannot train waypoint with empty name")
		return
	var index := waypoints.size() + 1
	var indexed_name := "%d: %s" % [index, waypoint_name]
	waypoints[indexed_name] = get_axis_positions()
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
		push_warning("Gantry: No waypoint selected to delete")
		return
	if not waypoints.has(waypoint_name):
		push_warning("Gantry: Waypoint '%s' not found" % waypoint_name)
		return
	waypoints.erase(waypoint_name)
	if selected_waypoint == waypoint_name:
		selected_waypoint = waypoints.keys()[0] if waypoints.size() > 0 else ""
	notify_property_list_changed()


func get_waypoint_names() -> Array:
	return waypoints.keys()


func go_to_waypoint(waypoint_name: String) -> void:
	if not waypoints.has(waypoint_name):
		push_warning("Gantry: Waypoint '%s' not found" % waypoint_name)
		return

	var target: Array = waypoints[waypoint_name]
	if target.size() >= 3:
		move_to_position(target)


func go_to_selected_waypoint() -> void:
	go_to_waypoint(selected_waypoint)


func move_to_position(target_positions: Array, instant: bool = false) -> void:
	if target_positions.size() < 3:
		push_warning("Gantry: Invalid target positions array")
		return

	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()

	if instant:
		x_position = target_positions[0]
		y_position = target_positions[1]
		z_position = target_positions[2]
	else:
		_is_moving = true
		var current := get_axis_positions()

		var max_dist: float = 0.0
		for i in range(3):
			max_dist = max(max_dist, abs(target_positions[i] - current[i]))

		var duration: float = max(max_dist / motion_speed, 0.1)
		if Engine.is_editor_hint():
			EditorInterface.mark_scene_as_unsaved()
		_motion_tween = create_tween()
		_motion_tween.set_parallel(true)
		_motion_tween.tween_property(self, "x_position", target_positions[0], duration)
		_motion_tween.tween_property(self, "y_position", target_positions[1], duration)
		_motion_tween.tween_property(self, "z_position", target_positions[2], duration)
		_motion_tween.chain().tween_callback(_on_motion_complete)


func _on_motion_complete() -> void:
	_is_moving = false


func is_moving() -> bool:
	return _is_moving


func stop_motion() -> void:
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	_is_moving = false


# --- Validation ---


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


# --- Simulation / Comms ---


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
	if cmd == null:
		return

	if cmd == 0:
		move_to_home()
	elif cmd > 0:
		var waypoint_names := waypoints.keys()
		var waypoint_index := cmd - 1
		if waypoint_index < waypoint_names.size():
			go_to_waypoint(waypoint_names[waypoint_index])
		else:
			push_warning("Gantry: Invalid waypoint index %d" % cmd)


func _write_status_tags() -> void:
	if _done_tag.is_ready():
		_done_tag.write_bit(not _is_moving)
