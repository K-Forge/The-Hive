@tool
extends CharacterBody3D

@export_category("Default Character")
@export var move_speed: float = 3.5
@export var mouse_sensitivity: float = 0.1
@export var jump_velocity: float = 4.5
@export_range(20.0, 85.0, 0.5, "degrees") var floor_max_angle_degrees: float = 58.0
@export_range(0.0, 2.0, 0.01) var floor_snap_distance: float = 0.35

var _head: Node3D
var _camera: Camera3D
var _interact_text: Label3D
var _hold_point: Marker3D
var _mouse_input: Vector2 = Vector2.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _interact_ray_query: PhysicsRayQueryParameters3D

var held_box = null
var _held_box_rigid: RigidBody3D
var held_pallet = null
var _held_pallet_rigid: RigidBody3D
var _pallet_offset: Vector3 = Vector3.ZERO
var _interact_key_text: String = "E"


func _ready() -> void:
	if get_tree().edited_scene_root == self:
		return

	_head = $Head
	_camera = $Head/Camera3D
	_head.rotation.y = rotation.y
	_head.rotation.x = clamp(rotation.x, deg_to_rad(-90), deg_to_rad(90))
	rotation = Vector3.ZERO
	floor_max_angle = deg_to_rad(floor_max_angle_degrees)
	floor_snap_length = floor_snap_distance
	floor_stop_on_slope = true

	var editor_settings := EditorInterface.get_editor_settings()
	var interact_sc := editor_settings.get_shortcut("Pilot Mode/Interact")
	if interact_sc and interact_sc.events.size() > 0:
		_interact_key_text = interact_sc.events[0].as_text()

	var crosshair := Label3D.new()
	crosshair.text = "."
	crosshair.font_size = 56
	crosshair.position = Vector3(0, 0, -0.475)
	crosshair.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crosshair.pixel_size = 0.0005
	crosshair.no_depth_test = true
	_camera.add_child(crosshair)

	_interact_text = Label3D.new()
	_interact_text.font_size = 32
	_interact_text.position = Vector3(0, -0.104, -0.475)
	_interact_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_interact_text.pixel_size = 0.0005
	_interact_text.no_depth_test = true
	_interact_text.visible = false
	_camera.add_child(_interact_text)

	_hold_point = Marker3D.new()
	_hold_point.position = Vector3(0, -0.5, -2.2)
	_camera.add_child(_hold_point)

	_interact_ray_query = PhysicsRayQueryParameters3D.new()
	_interact_ray_query.collision_mask = 10
	_interact_ray_query.collide_with_areas = true


func _physics_process(delta: float) -> void:
	if get_tree().edited_scene_root == self:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_pressed("pilot_jump") and is_on_floor():
		velocity.y = jump_velocity

	var current_speed := move_speed
	if held_pallet:
		current_speed = move_speed * 0.6

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("pilot_move_forward"):
		input_dir.y += 1
	if Input.is_action_pressed("pilot_move_back"):
		input_dir.y -= 1
	if Input.is_action_pressed("pilot_move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("pilot_move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var forward := -_head.global_transform.basis.z
	var right := _head.global_transform.basis.x
	var direction := (right * input_dir.x + forward * input_dir.y)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()

	_head.rotation_degrees.y -= _mouse_input.x * mouse_sensitivity
	_head.rotation_degrees.x -= _mouse_input.y * mouse_sensitivity
	_head.rotation_degrees.x = clamp(_head.rotation_degrees.x, -90.0, 90.0)
	_mouse_input = Vector2.ZERO

	if held_box:
		_update_held_box(delta)
	elif held_pallet:
		_update_held_pallet(delta)
	else:
		_handle_interaction()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_input += event.relative


# --- Interaction ---

func _handle_interaction() -> void:
	var start_pos := _camera.global_transform.origin
	var end_pos := start_pos - _camera.global_transform.basis.z * 3.0

	_interact_ray_query.from = start_pos
	_interact_ray_query.to = end_pos

	var result := get_world_3d().direct_space_state.intersect_ray(_interact_ray_query)
	if not result:
		_interact_text.visible = false
		return

	var hit_object = result.collider.get_parent()

	if hit_object is Box:
		_interact_text.text = "Press '%s' to pick up!" % _interact_key_text
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			_pick_up_box(hit_object)
		return

	if hit_object is Pallet:
		_interact_text.text = "Press '%s' to move pallet!" % _interact_key_text
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			_pick_up_pallet(hit_object)
		return

	if hit_object.has_method("use"):
		_interact_text.text = "Press '%s' to use %s" % [_interact_key_text, hit_object.name]
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			hit_object.call("use")
		return

	_interact_text.visible = false


# --- Box carrying ---

func _pick_up_box(box) -> void:
	held_box = box
	_held_box_rigid = box.get_node("RigidBody3D") as RigidBody3D


func _update_held_box(delta: float) -> void:
	var rigid := _held_box_rigid
	rigid.gravity_scale = 0
	rigid.global_position = rigid.global_position.lerp(_hold_point.global_position, 8.0 * delta)
	rigid.global_rotation = _hold_point.global_rotation

	_interact_text.visible = false

	var release := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if release or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		release_held_box()


func release_held_box() -> void:
	if held_box:
		_held_box_rigid.gravity_scale = 1
		_held_box_rigid.freeze = false
		_held_box_rigid.linear_velocity = Vector3.ZERO
		_held_box_rigid.angular_velocity = Vector3.ZERO
		held_box = null
		_held_box_rigid = null


# --- Pallet moving ---

func _pick_up_pallet(pallet) -> void:
	held_pallet = pallet
	_held_pallet_rigid = pallet.get_node("RigidBody3D") as RigidBody3D
	var initial_direction: Vector3 = (pallet.global_position - global_position).normalized()
	_pallet_offset = initial_direction * 2.5


func _update_held_pallet(delta: float) -> void:
	var rigid := _held_pallet_rigid
	rigid.gravity_scale = 0.1

	var pallet_jack_length := _pallet_offset.length()
	var forward_direction := -_head.global_transform.basis.z
	var target_pos := global_position + forward_direction * pallet_jack_length
	target_pos.y = global_position.y + 0.05

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("pilot_move_forward"):
		input_dir.y += 1
	if Input.is_action_pressed("pilot_move_back"):
		input_dir.y -= 1
	if Input.is_action_pressed("pilot_move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("pilot_move_right"):
		input_dir.x += 1
	var player_is_moving := input_dir.length() > 0.1

	var position_diff := target_pos - rigid.global_position
	var base_responsiveness := 1.8
	var movement_responsiveness := base_responsiveness if player_is_moving else base_responsiveness * 0.4

	var target_velocity := position_diff * movement_responsiveness
	rigid.linear_velocity.x = lerp(rigid.linear_velocity.x, target_velocity.x, 0.7)
	rigid.linear_velocity.z = lerp(rigid.linear_velocity.z, target_velocity.z, 0.7)
	rigid.linear_velocity.y = target_velocity.y * 2.0

	var target_rotation := _head.global_rotation.y
	var current_rotation := rigid.global_rotation.y
	var rotation_diff := target_rotation - current_rotation

	if rotation_diff > PI:
		rotation_diff -= 2.0 * PI
	elif rotation_diff < -PI:
		rotation_diff += 2.0 * PI

	var steering_responsiveness := 1.0 if player_is_moving else 0.3
	rigid.angular_velocity.y = lerp(rigid.angular_velocity.y, rotation_diff * steering_responsiveness, 0.6)
	rigid.angular_velocity.x = 0.0
	rigid.angular_velocity.z = 0.0

	_interact_text.visible = false

	var release := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if release or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		release_held_pallet()


func release_held_pallet() -> void:
	if held_pallet:
		_held_pallet_rigid.gravity_scale = 1
		_held_pallet_rigid.linear_velocity *= 0.3
		_held_pallet_rigid.angular_velocity *= 0.2
		held_pallet = null
		_held_pallet_rigid = null
		_pallet_offset = Vector3.ZERO
