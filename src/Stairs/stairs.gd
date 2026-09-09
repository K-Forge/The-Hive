@tool
class_name Stairs
extends ResizableNode3D

## Industrial stairs. X=run, Y=rise, Z=width. Origin at top landing; bottom at Y=-size.y.

@export var show_handrails: bool = true:
	set(value):
		show_handrails = value
		_on_size_changed()

@export var steel_color: Color = Color(0.95, 0.74, 0.06):
	set(value):
		steel_color = value
		_update_yellow_material_color()

@export var floor_y: float = 0.0:
	set(value):
		floor_y = value
		if is_inside_tree() and not _collision_reposition_active and not has_meta("is_preview"):
			_sync_height_to_floor()

var _floor_y_initialized: bool = false

var step_count: int:
	get:
		return StairsMesh.get_step_count(size.y)

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_body: StaticBody3D = $StaticBody3D
@onready var _stair_collision: CollisionShape3D = $StaticBody3D/StairCollision
@onready var _landing_collision: CollisionShape3D = $StaticBody3D/LandingCollision
@onready var _left_slope_guard_collision: CollisionShape3D = get_node_or_null("StaticBody3D/LeftSlopeGuardCollision") as CollisionShape3D
@onready var _right_slope_guard_collision: CollisionShape3D = get_node_or_null("StaticBody3D/RightSlopeGuardCollision") as CollisionShape3D
@onready var _left_landing_guard_collision: CollisionShape3D = get_node_or_null("StaticBody3D/LeftLandingGuardCollision") as CollisionShape3D
@onready var _right_landing_guard_collision: CollisionShape3D = get_node_or_null("StaticBody3D/RightLandingGuardCollision") as CollisionShape3D

var _tread_material: ShaderMaterial
var _yellow_material: ShaderMaterial


func _init() -> void:
	super._init()
	size_default = Vector3(StairsMesh.get_default_run_length(2.0), 2.0, 1.2)
	size_min = Vector3(0.5, 0.3, 0.4)
	set_notify_transform(true)


static var instances: Array[Stairs] = []


func _enter_tree() -> void:
	super._enter_tree()


func _exit_tree() -> void:
	instances.erase(self)


func _ready() -> void:
	if _stair_collision and _stair_collision.shape:
		_stair_collision.shape = _stair_collision.shape.duplicate() as BoxShape3D
	if _landing_collision and _landing_collision.shape:
		_landing_collision.shape = _landing_collision.shape.duplicate() as BoxShape3D
	if _left_slope_guard_collision and _left_slope_guard_collision.shape:
		_left_slope_guard_collision.shape = _left_slope_guard_collision.shape.duplicate() as BoxShape3D
	if _right_slope_guard_collision and _right_slope_guard_collision.shape:
		_right_slope_guard_collision.shape = _right_slope_guard_collision.shape.duplicate() as BoxShape3D
	if _left_landing_guard_collision and _left_landing_guard_collision.shape:
		_left_landing_guard_collision.shape = _left_landing_guard_collision.shape.duplicate() as BoxShape3D
	if _right_landing_guard_collision and _right_landing_guard_collision.shape:
		_right_landing_guard_collision.shape = _right_landing_guard_collision.shape.duplicate() as BoxShape3D
	_setup_materials()
	_on_size_changed()
	if has_meta("is_preview"):
		return
	if get_owner() != null:
		Stairs.instances.append(self)
	# Suppress until the engine's post-add_child set_transform has run.
	set_notify_transform(false)
	call_deferred("_initial_floor_sync")


func _initial_floor_sync() -> void:
	if not is_inside_tree() or has_meta("is_preview"):
		set_notify_transform(true)
		return
	_floor_y_initialized = true
	floor_y = global_position.y - size.y
	set_notify_transform(true)


var _collision_reposition_active: bool = false
var _transform_update_pending: bool = false
var _last_collision_floor_y: float = INF


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if has_meta("is_preview"):
			return
		if _collision_reposition_active:
			return
		if not _transform_update_pending:
			_transform_update_pending = true
			call_deferred("_deferred_transform_update")


func _deferred_transform_update() -> void:
	_transform_update_pending = false
	if _collision_reposition_active:
		_collision_reposition_active = false
		return
	_sync_height_to_floor()
	if is_inside_tree():
		for platform in Platform.instances:
			platform.call_deferred("_deferred_connection_update")


func _sync_height_to_floor() -> void:
	if not is_inside_tree() or not _floor_y_initialized or has_meta("is_preview"):
		return
	var target_y := maxf(size_min.y, global_position.y - floor_y)
	if not is_equal_approx(size.y, target_y):
		size = Vector3(size.x, target_y, size.z)


func _collision_repositioned_save() -> Variant:
	return floor_y

func _collision_repositioned(collision_point: Vector3, collision_normal: Vector3) -> void:
	if collision_normal == Vector3.ZERO:
		return
	_collision_reposition_active = true
	if not _transform_update_pending:
		call_deferred("_clear_collision_reposition_active")
	if is_equal_approx(_last_collision_floor_y, collision_point.y):
		return
	_last_collision_floor_y = collision_point.y
	var preserved := size.y
	floor_y = collision_point.y
	_floor_y_initialized = true
	# Pin origin so the post-flag-clear sync is a no-op.
	var target_origin_y := collision_point.y + preserved
	if not is_equal_approx(global_transform.origin.y, target_origin_y):
		var new_origin := global_transform.origin
		new_origin.y = target_origin_y
		global_transform.origin = new_origin

func _collision_repositioned_undo(saved_data: Variant) -> void:
	if saved_data is float:
		_collision_reposition_active = true
		if not _transform_update_pending:
			call_deferred("_clear_collision_reposition_active")
		floor_y = saved_data

func _clear_collision_reposition_active() -> void:
	_collision_reposition_active = false


func _transform_requested(data: Dictionary) -> void:
	if not EditorInterface.get_selection().get_selected_nodes().has(self):
		return
	if data.has("motion"):
		# Rise is driven by floor_y, not the scale gizmo.
		data = {"motion": [data["motion"][0], 0.0, data["motion"][2]]}
	super._transform_requested(data)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 4, 5])


func _setup_materials() -> void:
	_tread_material = StairsMesh.create_material_tread()
	_yellow_material = StairsMesh.create_material_yellow()
	_update_yellow_material_color()


func _update_yellow_material_color() -> void:
	if _yellow_material:
		_yellow_material.set_shader_parameter("color", steel_color)


func _get_constrained_size(new_size: Vector3) -> Vector3:
	if is_inside_tree() and _floor_y_initialized and not _collision_reposition_active and not has_meta("is_preview"):
		new_size.y = maxf(size_min.y, global_position.y - floor_y)
	else:
		new_size.y = maxf(new_size.y, size_min.y)
	var step_count_val := StairsMesh.get_step_count(new_size.y)
	var min_run := float(step_count_val) * 0.15 + StairsMesh.LANDING_DEPTH
	new_size.x = maxf(new_size.x, min_run)
	new_size.z = maxf(new_size.z, 0.3)
	return new_size


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	var half_x := for_size.x * 0.5
	var half_z := for_size.z * 0.5
	return AABB(Vector3(-half_x, -for_size.y, -half_z), Vector3(for_size.x, for_size.y, for_size.z))


func _on_size_changed() -> void:
	if not is_instance_valid(_mesh_instance):
		return

	var run_length := size.x
	var rise_height := size.y
	var width := size.z

	_mesh_instance.mesh = StairsMesh.create(run_length, rise_height, width, show_handrails)
	_mesh_instance.position.y = -rise_height / 2.0
	if _collision_body:
		_collision_body.position.y = 0.0

	if _mesh_instance.mesh:
		var surface_count := _mesh_instance.mesh.get_surface_count()
		if surface_count > 0:
			_mesh_instance.set_surface_override_material(0, _tread_material)
		if surface_count > 1:
			_mesh_instance.set_surface_override_material(1, _yellow_material)

	_update_collision()

	if is_inside_tree():
		for platform in Platform.instances:
			platform.call_deferred("_deferred_connection_update")


func _update_collision() -> void:
	var run_length := size.x
	var rise_height := size.y
	var width := size.z
	var hl := run_length / 2.0
	var hh := rise_height / 2.0

	var sc := StairsMesh.get_step_count(rise_height)
	var step_run := StairsMesh.get_step_run(run_length, rise_height)
	var stair_run := float(sc) * step_run
	var slope_length := sqrt(stair_run * stair_run + rise_height * rise_height)
	var slope_angle := atan2(rise_height, stair_run)

	if _stair_collision and _stair_collision.shape is BoxShape3D:
		(_stair_collision.shape as BoxShape3D).size = Vector3(slope_length, 0.15, width)
		_stair_collision.position = Vector3(-hl + stair_run / 2.0, -hh, 0)
		_stair_collision.rotation = Vector3(0, 0, slope_angle)

	var landing_length := maxf(run_length - stair_run, 0.01)
	if _landing_collision and _landing_collision.shape is BoxShape3D:
		(_landing_collision.shape as BoxShape3D).size = Vector3(landing_length, 0.05, width)
		_landing_collision.position = Vector3(hl - landing_length / 2.0, 0, 0)
		_landing_collision.rotation = Vector3.ZERO

	_update_side_guard_collisions(hl, hh, width, stair_run, slope_length, slope_angle, landing_length)


func _update_side_guard_collisions(
		hl: float,
		hh: float,
		width: float,
		stair_run: float,
		slope_length: float,
		slope_angle: float,
		landing_length: float) -> void:
	var slope_enabled := show_handrails
	# Match mesh generation: landing railing is only present for meaningful landing depth.
	var landing_enabled := show_handrails and landing_length > 0.05
	for collision: CollisionShape3D in [_left_slope_guard_collision, _right_slope_guard_collision]:
		if collision:
			collision.disabled = not slope_enabled
	for collision: CollisionShape3D in [_left_landing_guard_collision, _right_landing_guard_collision]:
		if collision:
			collision.disabled = not landing_enabled
	if not slope_enabled and not landing_enabled:
		return

	var guard_height := StairsMesh.HANDRAIL_HEIGHT
	var guard_thickness := StairsMesh.POST_SIZE * 1.5
	var z_offset := width * 0.5 + StairsMesh.STRINGER_WIDTH
	var slope_center := Vector3(-hl + stair_run * 0.5, -hh + guard_height * 0.5, 0)
	var landing_center := Vector3(hl - landing_length * 0.5, guard_height * 0.5, 0)

	if slope_enabled and _left_slope_guard_collision and _left_slope_guard_collision.shape is BoxShape3D:
		(_left_slope_guard_collision.shape as BoxShape3D).size = Vector3(slope_length, guard_height, guard_thickness)
		_left_slope_guard_collision.position = slope_center + Vector3(0, 0, -z_offset)
		_left_slope_guard_collision.rotation = Vector3(0, 0, slope_angle)
	if slope_enabled and _right_slope_guard_collision and _right_slope_guard_collision.shape is BoxShape3D:
		(_right_slope_guard_collision.shape as BoxShape3D).size = Vector3(slope_length, guard_height, guard_thickness)
		_right_slope_guard_collision.position = slope_center + Vector3(0, 0, z_offset)
		_right_slope_guard_collision.rotation = Vector3(0, 0, slope_angle)

	if landing_enabled and _left_landing_guard_collision and _left_landing_guard_collision.shape is BoxShape3D:
		(_left_landing_guard_collision.shape as BoxShape3D).size = Vector3(landing_length, guard_height, guard_thickness)
		_left_landing_guard_collision.position = landing_center + Vector3(0, 0, -z_offset)
		_left_landing_guard_collision.rotation = Vector3.ZERO
	if landing_enabled and _right_landing_guard_collision and _right_landing_guard_collision.shape is BoxShape3D:
		(_right_landing_guard_collision.shape as BoxShape3D).size = Vector3(landing_length, guard_height, guard_thickness)
		_right_landing_guard_collision.position = landing_center + Vector3(0, 0, z_offset)
		_right_landing_guard_collision.rotation = Vector3.ZERO


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/Stairs.tscn") as PackedScene
	var preview_node: Node3D = preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)
