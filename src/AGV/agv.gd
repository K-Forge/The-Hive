@tool
class_name AGV
extends Node3D


const WHEEL_RADIUS := 0.125
const PISTON_LIFT_RATIO := 0.5
const AGVWaypointScript := preload("res://src/AGV/agv_waypoint.gd")

@export_tool_button("Set Home") var action_set_home: Callable = set_home_action
@export_tool_button("Go Home") var action_go_home: Callable = go_home_action
@export_tool_button("Train Waypoint") var action_train: Callable = train_waypoint_action
@export_tool_button("Go To Waypoint") var action_go_to: Callable = go_to_waypoint_action
@export_tool_button("Delete Waypoint") var action_delete: Callable = delete_waypoint_action

@export var home_position: Vector3 = Vector3.ZERO:
	set(value):
		home_position = value
		if is_inside_tree():
			update_gizmos()
@export_range(-180.0, 180.0, 0.1, "suffix:°") var home_yaw_deg: float = 0.0
@export var waypoints: Dictionary = {}
@export var selected_waypoint: String = ""
@export var new_waypoint_name: String = "Point1"

@export_category("Motion")
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var drive_speed: float = 1.0
@export_range(10.0, 360.0, 1.0, "suffix:°/s") var turn_speed: float = 90.0
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var lift_speed: float = 1.2

@export_category("Lift")
@export_range(0.1, 8.0, 0.01, "suffix:m") var max_lift_height: float = 3.0:
	set(value):
		max_lift_height = maxf(value, 0.1)
		lift_height = clampf(lift_height, 0.0, max_lift_height)

@export_range(0.0, 8.0, 0.001, "suffix:m") var lift_height: float = 0.0:
	set(value):
		lift_height = clampf(value, 0.0, max_lift_height)
		if _lift_group:
			_lift_group.position.y = _lift_base_y + lift_height
		if _piston_rod:
			_piston_rod.position.y = _piston_base_y + lift_height * PISTON_LIFT_RATIO

@export var forks_raised: bool = false:
	set(value):
		forks_raised = value
		_on_forks_changed()

@export var holding_object: bool = false:
	set(value):
		holding_object = value
	get:
		return _held_bodies.size() > 0

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
## Integer value selecting which waypoint to move to (0 = home, 1+ = waypoint by order).[br]Datatype: [code]INT[/code] (16-bit integer)
@export var command_tag: String = ""
## Rising edge triggers movement to command waypoint.[br]Datatype: [code]BOOL[/code]
@export var execute_tag: String = ""
## True when AGV has reached target position.[br]Datatype: [code]BOOL[/code]
@export var done_tag: String = ""
## Fork lift control.[br]Datatype: [code]BOOL[/code]
@export var lift_tag: String = ""

var _command_tag := OIPCommsTag.new()
var _execute_tag := OIPCommsTag.new()
var _done_tag := OIPCommsTag.new()
var _lift_tag := OIPCommsTag.new()
var _last_execute: bool = false

var _lift_group: Node3D
var _lift_base_y: float = 0.0
var _piston_rod: Node3D
var _piston_base_y: float = 0.0
var _pickup_area: Area3D
var _wheels: Array[Node3D] = []
var _last_pos: Vector3 = Vector3.ZERO

var _held_bodies: Array = []
var _objects_in_range: Array[Node3D] = []

var _motion_tween: Tween = null
var _is_moving: bool = false
var _lift_tween: Tween = null

var _initial_transform: Transform3D
var _initial_lift_height: float = 0.0
var _initial_forks_raised: bool = false
var _has_initial_state: bool = false



func _enter_tree() -> void:
	set_notify_transform(true)
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	_lift_group = get_node_or_null("LiftGroup")
	if _lift_group:
		_lift_base_y = _lift_group.position.y - lift_height
	_piston_rod = get_node_or_null("PistonRod")
	if _piston_rod:
		_piston_base_y = _piston_rod.position.y - lift_height * PISTON_LIFT_RATIO
	_pickup_area = get_node_or_null("LiftGroup/PickupArea")

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
	new_waypoint_name = _get_next_waypoint_name()
	_wheels = [
		get_node_or_null("Wheel_LF") as Node3D,
		get_node_or_null("Wheel_LR") as Node3D,
		get_node_or_null("Wheel_RF") as Node3D,
		get_node_or_null("Wheel_RR") as Node3D,
	]
	if is_inside_tree():
		_last_pos = global_position
	if _pickup_area:
		if not _pickup_area.body_entered.is_connected(_on_pickup_body_entered):
			_pickup_area.body_entered.connect(_on_pickup_body_entered)
		if not _pickup_area.body_exited.is_connected(_on_pickup_body_exited):
			_pickup_area.body_exited.connect(_on_pickup_body_exited)
	update_gizmos()


func _process(_delta: float) -> void:
	_update_held_object()
	_update_wheels()


func _physics_process(_delta: float) -> void:
	_align_to_surface()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_gizmos()


func _align_to_surface() -> void:
	if not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return

	var origin := global_position
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3(0, 2, 0),
		origin + Vector3(0, -4, 0)
	)
	var excludes: Array[RID] = []
	for entry: Dictionary in _held_bodies:
		if is_instance_valid(entry.rb):
			excludes.append(entry.rb.get_rid())
	if excludes.size() > 0:
		query.exclude = excludes

	var result := space.intersect_ray(query)
	if result.is_empty():
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	if hit_normal.length_squared() < 1e-6:
		return
	hit_normal = hit_normal.normalized()
	if hit_normal.dot(Vector3.UP) < 0.7:
		return
	if hit_point.y - global_position.y > 0.3:
		return

	var basis_z := global_transform.basis.z
	if basis_z.length_squared() < 1e-6:
		return
	var fwd := -basis_z.normalized()
	var yaw := atan2(-fwd.x, -fwd.z)
	var flat_forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var projected := flat_forward - hit_normal * flat_forward.dot(hit_normal)
	if projected.length_squared() < 1e-6:
		return
	projected = projected.normalized()

	global_position.y = hit_point.y
	look_at(global_position + projected, hit_normal)


func _update_wheels() -> void:
	if not is_inside_tree():
		return
	var cur := global_position
	var delta_pos := cur - _last_pos
	_last_pos = cur
	if delta_pos.length_squared() < 1e-8:
		return
	var forward := -global_transform.basis.z.normalized()
	var signed_dist := delta_pos.dot(forward)
	var angle := signed_dist / WHEEL_RADIUS
	for w in _wheels:
		if w:
			w.rotate_object_local(Vector3.LEFT, angle)


# --- Motion ---

func move_to_transform(target_xform: Transform3D, instant: bool = false) -> void:
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()

	if instant:
		global_transform = target_xform
		return

	_is_moving = true
	var current_pos := global_position
	var target_pos := target_xform.origin
	var current_yaw := rotation.y
	var target_yaw := target_xform.basis.get_euler().y

	var dir := target_pos - current_pos
	dir.y = 0
	var dir_len := dir.length()

	var fwd := Vector3(-sin(current_yaw), 0, -cos(current_yaw))
	var alignment := dir.dot(fwd) / dir_len if dir_len > 0.01 else 0.0
	var reversing := alignment < -0.95 and absf(wrapf(target_yaw - current_yaw, -PI, PI)) < 0.3

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

	if reversing:
		var drive_dur := maxf(dir_len / drive_speed, 0.01)
		_motion_tween = create_tween()
		_motion_tween.tween_property(self, "global_position", target_pos, drive_dur)
		_motion_tween.tween_callback(_on_motion_complete)
	else:
		_drive_arc(current_pos, target_pos, current_yaw, target_yaw)


func _drive_arc(from_pos: Vector3, to_pos: Vector3, from_yaw: float, to_yaw: float) -> void:
	var dir := to_pos - from_pos
	dir.y = 0
	var dist := dir.length()
	if dist < 0.001:
		var dyaw := wrapf(to_yaw - from_yaw, -PI, PI)
		var dur := maxf(absf(dyaw) / deg_to_rad(turn_speed), 0.01)
		_motion_tween = create_tween()
		_motion_tween.tween_property(self, "rotation:y", from_yaw + dyaw, dur)
		_motion_tween.tween_callback(_on_motion_complete)
		return

	var travel_yaw := atan2(-dir.x, -dir.z)
	var travel_yaw_rel := from_yaw + wrapf(travel_yaw - from_yaw, -PI, PI)
	var to_yaw_rel := travel_yaw_rel + wrapf(to_yaw - travel_yaw, -PI, PI)
	var dyaw_start := absf(travel_yaw_rel - from_yaw)
	var dyaw_end := absf(to_yaw_rel - travel_yaw_rel)

	var drive_dur := maxf(dist / drive_speed, 0.01)
	var start_turn_dur := dyaw_start / drive_speed
	var end_turn_dur := dyaw_end / drive_speed

	_motion_tween = create_tween()
	if start_turn_dur > 0.001:
		_motion_tween.tween_property(self, "rotation:y", travel_yaw_rel, start_turn_dur)
	_motion_tween.tween_property(self, "global_position", to_pos, drive_dur)
	if end_turn_dur > 0.001:
		_motion_tween.tween_property(self, "rotation:y", to_yaw_rel, end_turn_dur)
	_motion_tween.tween_callback(_on_motion_complete)


func _on_motion_complete() -> void:
	_is_moving = false


func is_moving() -> bool:
	return _is_moving


func stop_motion() -> void:
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	_is_moving = false
	if _lift_tween and _lift_tween.is_valid():
		_lift_tween.kill()


func drive_lift(target_height: float) -> void:
	var h := clampf(target_height, 0.0, max_lift_height)
	if _lift_tween and _lift_tween.is_valid():
		_lift_tween.kill()
	var duration: float = maxf(absf(h - lift_height) / lift_speed, 0.01)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	_lift_tween = create_tween()
	_lift_tween.tween_property(self, "lift_height", h, duration)


func is_lifting() -> bool:
	return _lift_tween != null and _lift_tween.is_valid()


func pick_at_current_height() -> void:
	_try_pick_up()


func release() -> void:
	_release_object()


# --- Waypoints ---

func _parent_xform() -> Transform3D:
	var p := get_parent()
	return (p as Node3D).global_transform if p is Node3D else Transform3D.IDENTITY


func set_home_action() -> void:
	home_position = position
	home_yaw_deg = rad_to_deg(_local_yaw())


func go_home_action() -> void:
	move_to_transform(_parent_xform() * _pose_to_xform(home_position, deg_to_rad(home_yaw_deg)))


func _pose_to_xform(pos: Vector3, yaw_rad: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw_rad), pos)


func _local_yaw() -> float:
	var fwd := -transform.basis.z.normalized()
	return atan2(-fwd.x, -fwd.z)


func train_waypoint_action() -> void:
	train_waypoint(new_waypoint_name)
	new_waypoint_name = _get_next_waypoint_name()


func go_to_waypoint_action() -> void:
	go_to_selected_waypoint()


func delete_waypoint_action() -> void:
	delete_waypoint(selected_waypoint)


func train_waypoint(waypoint_name: String) -> void:
	if waypoint_name.is_empty():
		push_warning("AGV: Cannot train waypoint with empty name")
		return
	var index := waypoints.size() + 1
	var indexed_name := "%d: %s" % [index, waypoint_name]
	var wp := AGVWaypointScript.new()
	wp.position = position
	wp.yaw_deg = rad_to_deg(_local_yaw())
	waypoints[indexed_name] = wp
	selected_waypoint = indexed_name
	notify_property_list_changed()
	update_gizmos()


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
	if waypoint_name.is_empty() or not waypoints.has(waypoint_name):
		return
	waypoints.erase(waypoint_name)
	if selected_waypoint == waypoint_name:
		selected_waypoint = waypoints.keys()[0] if waypoints.size() > 0 else ""
	notify_property_list_changed()
	update_gizmos()


func get_waypoint_names() -> Array:
	return waypoints.keys()


func go_to_waypoint(waypoint_name: String) -> void:
	if not waypoints.has(waypoint_name):
		push_warning("AGV: Waypoint '%s' not found" % waypoint_name)
		return
	var wp: Variant = waypoints[waypoint_name]
	var local_xform := _pose_to_xform(wp.position, deg_to_rad(wp.yaw_deg))
	move_to_transform(_parent_xform() * local_xform)


func go_to_selected_waypoint() -> void:
	go_to_waypoint(selected_waypoint)


# --- Fork pickup ---

func _on_forks_changed() -> void:
	if forks_raised:
		lift_height = max_lift_height
		_try_pick_up()
	else:
		lift_height = 0.0
		_release_object()


func _try_pick_up() -> void:
	if not _held_bodies.is_empty() or not _pickup_area:
		return

	var area_inv := _pickup_area.global_transform.affine_inverse()

	for obj in _objects_in_range:
		if not is_instance_valid(obj):
			continue
		var rb: RigidBody3D = null
		if obj is RigidBody3D:
			rb = obj
		elif obj.has_node("RigidBody3D"):
			rb = obj.get_node("RigidBody3D")
		if rb == null:
			continue
		if _find_held_entry(rb) != -1:
			continue
		var rel := area_inv * rb.global_transform
		_held_bodies.append({
			"rb": rb,
			"offset": rel.origin,
			"basis": rel.basis,
		})
		rb.gravity_scale = 0
		rb.freeze = true

	if not _held_bodies.is_empty():
		holding_object = true


func _find_held_entry(rb: RigidBody3D) -> int:
	for i in _held_bodies.size():
		if _held_bodies[i].rb == rb:
			return i
	return -1


func _release_object() -> void:
	for entry: Dictionary in _held_bodies:
		var rb: RigidBody3D = entry.rb
		if rb and is_instance_valid(rb):
			rb.freeze = false
			rb.gravity_scale = 1
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
	_held_bodies.clear()
	holding_object = false


func _update_held_object() -> void:
	if _held_bodies.is_empty() or not _pickup_area:
		return
	var area_xform := _pickup_area.global_transform
	for entry: Dictionary in _held_bodies:
		var rb: RigidBody3D = entry.rb
		if not is_instance_valid(rb):
			continue
		rb.global_transform = Transform3D(area_xform.basis * entry.basis, area_xform * entry.offset)


func _on_pickup_body_entered(body: Node3D) -> void:
	if body not in _objects_in_range:
		_objects_in_range.append(body)
	if forks_raised and _held_bodies.is_empty():
		_try_pick_up()


func _on_pickup_body_exited(body: Node3D) -> void:
	_objects_in_range.erase(body)


# --- Validation ---

func _validate_property(property: Dictionary) -> void:
	if property.name == "holding_object":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name == "selected_waypoint":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(waypoints.keys()) if waypoints.size() > 0 else "(no waypoints)"
	if OIPCommsSetup.validate_tag_property(property):
		return
	if property.name in ["command_tag", "execute_tag", "done_tag", "lift_tag"]:
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE


# --- Simulation / Comms ---

func _on_simulation_started() -> void:
	if not _has_initial_state:
		_initial_transform = global_transform
		_initial_lift_height = lift_height
		_initial_forks_raised = forks_raised
		_has_initial_state = true
	if not enable_comms or tag_group_name.is_empty():
		return
	_last_execute = false
	if not command_tag.is_empty():
		_command_tag.register(tag_group_name, command_tag, OIPComms.TAG_TYPE_INT16)
	if not execute_tag.is_empty():
		_execute_tag.register(tag_group_name, execute_tag, OIPComms.TAG_TYPE_BOOL)
	if not done_tag.is_empty():
		_done_tag.register(tag_group_name, done_tag, OIPComms.TAG_TYPE_BOOL)
	if not lift_tag.is_empty():
		_lift_tag.register(tag_group_name, lift_tag, OIPComms.TAG_TYPE_BOOL)


func _on_simulation_ended() -> void:
	stop_motion()
	if not _held_bodies.is_empty():
		_release_object()
	_objects_in_range.clear()
	_last_execute = false
	if _has_initial_state:
		global_transform = _initial_transform
		forks_raised = _initial_forks_raised
		lift_height = _initial_lift_height
		_has_initial_state = false


func _tag_group_initialized(group_name: String) -> void:
	_command_tag.on_group_initialized(group_name)
	_execute_tag.on_group_initialized(group_name)
	_done_tag.on_group_initialized(group_name)
	_lift_tag.on_group_initialized(group_name)
	_write_status_tags()


func _tag_group_polled(group_name: String) -> void:
	if group_name != tag_group_name:
		return
	if _lift_tag.is_ready():
		forks_raised = _lift_tag.read_bit()
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
		go_home_action()
	elif cmd > 0:
		var wp_names := waypoints.keys()
		var idx := cmd - 1
		if idx < wp_names.size():
			go_to_waypoint(wp_names[idx])
		else:
			push_warning("AGV: Invalid waypoint index %d" % cmd)


func _write_status_tags() -> void:
	if _done_tag.is_ready():
		_done_tag.write_bit(not _is_moving)
