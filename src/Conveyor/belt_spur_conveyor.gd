@tool
class_name BeltSpurConveyor
extends ResizableNode3D

## Diverging belt-spur conveyor — wedge of parallel belt strips fanning out by
## [member angle_downstream] / [member angle_upstream].

const _MIN_SLOT_LENGTH: float = 0.05
const _GAP_FILL_DEPTH: float = 0.05

## Spur length along the flow axis in meters.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var length: float = 2.0:
	set(value):
		size = Vector3(value, size.y, size.z)
	get:
		return size.x

## Spur width across the flow axis in meters.
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:m") var width: float = 1.524:
	set(value):
		size = Vector3(size.x, size.y, value)
	get:
		return size.z

## Belt height; drives end-pulley diameter ([code]height / 2[/code]).
@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var height: float = 0.5:
	set(value):
		size = Vector3(size.x, value, size.z)
	get:
		return size.y

## Splay angle of the downstream (+X) end. Positive splays outward.
@export_range(-70, 70, 1, "radians_as_degrees") var angle_downstream: float = deg_to_rad(30.0):
	set(value):
		if value == angle_downstream:
			return
		angle_downstream = value
		_request_rebuild()

## Splay angle of the upstream (-X) end. Positive splays outward.
@export_range(-70, 70, 1, "radians_as_degrees") var angle_upstream: float = 0.0:
	set(value):
		if value == angle_upstream:
			return
		angle_upstream = value
		_request_rebuild()

## Number of parallel belt strips.
@export_range(1, 20, 1) var conveyor_count: int = 20:
	set(value):
		var clamped: int = maxi(1, value)
		if clamped == conveyor_count:
			return
		conveyor_count = clamped
		_request_rebuild()

@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 2.0:
	set(value):
		if value == speed:
			return
		speed = value
		if _belt_material:
			_belt_material.set_shader_parameter("Scale", maxf(1.0, _approximate_loop_length()))
		if _running_tag.is_ready():
			_running_tag.write_bit(value != 0.0)

@export var belt_color: Color = Color.WHITE:
	set(value):
		belt_color = value
		if _belt_material:
			_belt_material.set_shader_parameter("ColorMix", belt_color)

@export var frame_color: Color = Color.WHITE:
	set(value):
		frame_color = value
		if _frame_material:
			_frame_material.set_shader_parameter("color", frame_color)

@export var belt_texture: BeltConveyor.BeltTexture = BeltConveyor.BeltTexture.STANDARD:
	set(value):
		belt_texture = value
		if _belt_material:
			_belt_material.set_shader_parameter("use_alternate_texture",
					belt_texture == BeltConveyor.BeltTexture.ALTERNATE)
		_request_rebuild()

## Physics material applied to the conveyor surface.
@export var physics_material: PhysicsMaterial = preload("res://parts/BeltSurfaceMaterial.tres"):
	set(value):
		physics_material = value
		_apply_physics_material()


@export_group("Frame & Side Guards")
@export var frame_rails_enabled: bool = true:
	set(value):
		if value == frame_rails_enabled:
			return
		frame_rails_enabled = value
		_request_rebuild()

@export var left_side_guards_enabled: bool = true:
	set(value):
		if value == left_side_guards_enabled:
			return
		left_side_guards_enabled = value
		_request_rebuild()

@export var right_side_guards_enabled: bool = true:
	set(value):
		if value == right_side_guards_enabled:
			return
		right_side_guards_enabled = value
		_request_rebuild()

## Openings in conveyor-local X (origin at tail, 0..length). arc-length == X (single-segment).
@export var side_guard_openings: Array[SideGuardOpening] = []:
	set(value):
		SideGuardOpening.sync_change_listeners(side_guard_openings, value, _request_rebuild, false, _guard_arc_bounds())
		side_guard_openings = value
		_request_rebuild()

## Per-side end overrides for frame and side guard. Snap uses this to extend the rails
## and guards up to the target's wall plane. Keys: [code]"left_front"[/code],
## [code]"left_back"[/code], [code]"right_front"[/code], [code]"right_back"[/code].
@export_storage var side_guard_snap_extents: Dictionary = {}:
	set(value):
		side_guard_snap_extents = value
		_request_rebuild()


@export_group("Legs")
@export var legs_enabled: bool = true:
	set(value):
		if value == legs_enabled:
			return
		legs_enabled = value
		_request_rebuild()

## World-space plane the legs reach down to.
@export var floor_plane: Plane = Plane(Vector3.UP, -2.0):
	set(value):
		if value == floor_plane:
			return
		floor_plane = value
		_request_legs_refresh()

@export var leg_model_scene: PackedScene = preload("res://parts/StraightLeg.tscn"):
	set(value):
		leg_model_scene = value
		_request_rebuild()

@export_subgroup("Tail End", "tail_end")
@export var tail_end_leg_enabled: bool = true:
	set(value):
		if value == tail_end_leg_enabled:
			return
		tail_end_leg_enabled = value
		_request_rebuild()

@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var tail_end_attachment_offset: float = 0.45:
	set(value):
		if value == tail_end_attachment_offset:
			return
		tail_end_attachment_offset = maxf(0.0, value)
		_request_rebuild()

@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m") var tail_end_leg_clearance: float = 0.5:
	set(value):
		if value == tail_end_leg_clearance:
			return
		tail_end_leg_clearance = maxf(0.0, value)
		_request_rebuild()

@export_subgroup("Head End", "head_end")
@export var head_end_leg_enabled: bool = false:
	set(value):
		if value == head_end_leg_enabled:
			return
		head_end_leg_enabled = value
		_request_rebuild()

@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var head_end_attachment_offset: float = 0.45:
	set(value):
		if value == head_end_attachment_offset:
			return
		head_end_attachment_offset = maxf(0.0, value)
		_request_rebuild()

@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m") var head_end_leg_clearance: float = 0.5:
	set(value):
		if value == head_end_leg_clearance:
			return
		head_end_leg_clearance = maxf(0.0, value)
		_request_rebuild()

@export_subgroup("Middle Legs", "middle_legs")
@export var middle_legs_enabled: bool = false:
	set(value):
		if value == middle_legs_enabled:
			return
		middle_legs_enabled = value
		_request_rebuild()

@export_range(0.5, 10.0, 0.05, "or_greater", "suffix:m") var middle_legs_spacing: float = 2.0:
	set(value):
		var clamped: float = maxf(0.5, value)
		if clamped == middle_legs_spacing:
			return
		middle_legs_spacing = clamped
		_request_rebuild()

@export_subgroup("Leg Exclusion Zone", "exclusion_")
## Skip legs in [code][tail + exclusion_start, tail + exclusion_end][/code]; both 0 disables.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var exclusion_start: float = 0.0:
	set(value):
		if value == exclusion_start:
			return
		exclusion_start = value
		_request_rebuild()

@export_custom(PROPERTY_HINT_NONE, "suffix:m") var exclusion_end: float = 0.0:
	set(value):
		if value == exclusion_end:
			return
		exclusion_end = value
		_request_rebuild()


@export_category("Communications")
@export var enable_comms: bool = false
@export var speed_tag_group_name: String
@export_custom(0, "tag_group_enum") var speed_tag_groups: String:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
@export var speed_tag_name: String = ""
@export var running_tag_group_name: String
@export_custom(0, "tag_group_enum") var running_tag_groups: String:
	set(value):
		running_tag_group_name = value
		running_tag_groups = value
@export var running_tag_name: String = ""


const _SIZE_DEFAULT: Vector3 = Vector3(2.0, 0.5, 1.524)
const _SIZE_MIN: Vector3 = Vector3(0.1, 0.05, 0.1)

var _simple_conveyor_shape: StaticBody3D
var _legs: Array[Node3D] = []
var _legs_state: Dictionary = {}
var _derived_side_guard_snap_extents: Dictionary = {}
var _flow_arrow: Node3D
var _belt_material: ShaderMaterial
var _frame_material: ShaderMaterial
var _belt_position: float = 0.0
var _rebuild_pending: bool = false
var _connection_rebuild_pending: bool = false
var _legs_refresh_pending: bool = false
var _speed_tag := OIPCommsTag.new()
var _running_tag := OIPCommsTag.new()


func _validate_property(property: Dictionary) -> void:
	# `length`/`width`/`height` are inspector facades; only `size` is serialized.
	var prop_name: String = property["name"]
	if prop_name in ["length", "width", "height"]:
		property["usage"] = PROPERTY_USAGE_EDITOR
		return
	if prop_name == "size":
		property["usage"] = PROPERTY_USAGE_STORAGE
		return
	if OIPCommsSetup.validate_tag_property(property, "speed_tag_group_name", "speed_tag_groups", "speed_tag_name"):
		return
	OIPCommsSetup.validate_tag_property(property, "running_tag_group_name", "running_tag_groups", "running_tag_name")


func _init() -> void:
	size_default = _SIZE_DEFAULT
	size_min = _SIZE_MIN
	super._init()
	if size == Vector3.ZERO:
		size = _SIZE_DEFAULT


func _on_size_changed() -> void:
	_request_rebuild()


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	return AABB(
			Vector3(0, -for_size.y, -for_size.z * 0.5),
			for_size)


func _get_editor_rotation_lock() -> int:
	return (1 << 0) | (1 << 2)


func _get_editor_gizmo_pivot_offset() -> Vector3:
	return Vector3(size.x * 0.5, 0.0, 0.0)


var local_bbox: AABB:
	get:
		return _get_resize_local_bounds(size)


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_request_legs_refresh()
		_request_connection_rebuild()
		ConveyorSnapping.notify_contacts_rebuild(self)


func _get_scale_warning_text() -> String:
	return "Use `length` / `width` / `height` instead of scale."


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 4, 5])


func _enter_tree() -> void:
	set_meta("_edit_group_", true)
	super._enter_tree()
	speed_tag_group_name = OIPCommsSetup.default_tag_group(speed_tag_group_name)
	running_tag_group_name = OIPCommsSetup.default_tag_group(running_tag_group_name)
	if not Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.connect(_on_simulation_started)
	if not Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)
	ConveyorSnapping.notify_contacts_rebuild(self)


func _exit_tree() -> void:
	ConveyorSnapping.notify_contacts_rebuild(self)
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)
	super._exit_tree()


func _ready() -> void:
	_clear_stale_snap_metas()
	_reset_preview_holder_transform()
	_ensure_internal_nodes()
	SideGuardOpening.claim_unique(side_guard_openings, get_instance_id())
	SideGuardOpening.sync_change_listeners([], side_guard_openings, _request_rebuild)
	_rebuild()
	_bind_snap_meta_now()


func _reset_preview_holder_transform() -> void:
	if not has_meta("is_preview"):
		return
	var holder := get_parent() as Node3D
	if holder == null:
		return
	holder.transform = Transform3D.IDENTITY


func _get_custom_preview_node() -> Node3D:
	# GEN_EDIT_STATE_DISABLED: preview-holder transform leaks with GEN_EDIT_STATE_INSTANCE.
	var preview_scene := load("res://parts/BeltSpurConveyor.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


static func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var co: CollisionObject3D = node
		co.collision_layer = 0
		co.collision_mask = 0
	for child in node.get_children(true):
		_disable_collisions_recursive(child)


func _collision_repositioned(collision_point: Vector3, collision_normal: Vector3) -> void:
	if collision_normal == Vector3.ZERO:
		return
	var new_plane: Plane = Plane(collision_normal, collision_point)
	if floor_plane.is_equal_approx(new_plane):
		return
	floor_plane = new_plane


func _collision_repositioned_save() -> Variant:
	return floor_plane


func _collision_repositioned_undo(saved: Variant) -> void:
	if saved is Plane:
		floor_plane = saved


func _clear_stale_snap_metas() -> void:
	if not Engine.is_editor_hint():
		return
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root != null and self != edited_root and not edited_root.is_ancestor_of(self):
		return
	const STALE: PackedStringArray = [
		"_snap_transform",
		"_snap_baseline_reverse",
		"_snap_baseline_floor_plane",
		"_snap_baseline_legs_xform",
		"_snap_flip_decision",
	]
	for key: String in STALE:
		if has_meta(key):
			remove_meta(key)


func _bind_snap_meta_now() -> void:
	if not Engine.is_editor_hint() or ConveyorLiveSnap.instance == null:
		return
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root == null:
		return
	if self != edited_root and not edited_root.is_ancestor_of(self):
		return
	ConveyorLiveSnap.instance.bind_snap_meta(self)


func _request_rebuild() -> void:
	if not is_inside_tree() or _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


## Frame-rails + side-guards-only rebuild, skipping the belt-slot mesh regen.
func _request_connection_rebuild() -> void:
	if _connection_rebuild_pending or not is_inside_tree():
		return
	_connection_rebuild_pending = true
	_do_connection_rebuild.call_deferred()


func _request_legs_recheck() -> void:
	_rebuild_legs()


func _do_connection_rebuild() -> void:
	_connection_rebuild_pending = false
	if not is_inside_tree():
		return
	_derive_side_guard_extents()
	_rebuild_frame_rails()
	_rebuild_side_guards()


func _request_legs_refresh() -> void:
	if _legs_refresh_pending or not is_inside_tree():
		return
	_legs_refresh_pending = true
	call_deferred("_refresh_legs_for_transform")


func _refresh_legs_for_transform() -> void:
	_legs_refresh_pending = false
	if not is_inside_tree():
		return
	_reposition_existing_legs()


func _rebuild() -> void:
	_rebuild_pending = false
	if not is_inside_tree():
		return
	_ensure_internal_nodes()
	_derive_side_guard_extents()
	_rebuild_belt_slots()
	_rebuild_collision()
	_rebuild_gap_fill()
	_rebuild_frame_rails()
	_rebuild_side_guards()
	_rebuild_legs()
	_update_flow_arrow()
	ConveyorSnapping.notify_contacts_rebuild(self)
	if Engine.is_editor_hint():
		update_gizmos()


func _ensure_internal_nodes() -> void:
	if _belt_material == null:
		_belt_material = BeltSurface.create_material(belt_color, belt_texture)
	if _frame_material == null:
		_frame_material = ConveyorFrameMesh.create_material_colored(frame_color)
	_ensure_simple_collision()


func _ensure_simple_collision() -> void:
	if not is_instance_valid(_simple_conveyor_shape):
		_simple_conveyor_shape = get_node_or_null("SimpleConveyorShape") as StaticBody3D
		if not is_instance_valid(_simple_conveyor_shape):
			_simple_conveyor_shape = StaticBody3D.new()
			_simple_conveyor_shape.name = "SimpleConveyorShape"
			add_child(_simple_conveyor_shape, false, Node.INTERNAL_MODE_FRONT)
		_apply_physics_material()
		var cs: CollisionShape3D = _simple_conveyor_shape.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs == null:
			cs = CollisionShape3D.new()
			cs.name = "CollisionShape3D"
			_simple_conveyor_shape.add_child(cs)


func _get_slot_geometry(index: int) -> Array[Vector3]:
	var conv_width: float = width / float(conveyor_count)
	var conv_half_width: float = 0.5 * conv_width
	var conv_pos_z: float = -0.5 * width + conv_half_width + index * conv_width
	var ds_displacement_x: float = tan(angle_downstream) * conv_pos_z
	var us_displacement_x: float = tan(angle_upstream) * conv_pos_z
	var conv_pos_x: float = length * 0.5 + (ds_displacement_x + us_displacement_x) / 2.0
	var conv_length: float = length + ds_displacement_x - us_displacement_x
	return [Vector3(conv_pos_x, 0.0, conv_pos_z),
			Vector3(conv_length, height, conv_width)]


## True arc extent of the side guard (origin at tail), default span for a new opening.
func _guard_arc_bounds() -> Vector2:
	return Vector2(0.0, length)


func _side_extents(side_z: float) -> Vector2:
	var front_x: float = length + tan(angle_downstream) * side_z
	var back_x: float = tan(angle_upstream) * side_z
	var side_key: String = "left" if side_z < 0.0 else "right"
	var front_key: String = side_key + "_front"
	var back_key: String = side_key + "_back"
	if _derived_side_guard_snap_extents.has(front_key):
		front_x = float(_derived_side_guard_snap_extents[front_key])
	elif side_guard_snap_extents.has(front_key):
		front_x = float(side_guard_snap_extents[front_key])
	if _derived_side_guard_snap_extents.has(back_key):
		back_x = float(_derived_side_guard_snap_extents[back_key])
	elif side_guard_snap_extents.has(back_key):
		back_x = float(side_guard_snap_extents[back_key])
	return Vector2(back_x, front_x)


func clear_side_guard_snap_extents() -> void:
	if side_guard_snap_extents.is_empty():
		return
	side_guard_snap_extents = {}


func _derive_side_guard_extents() -> void:
	_derived_side_guard_snap_extents = ConveyorSnapping.derive_extents_by_geometry(self)


func _approximate_loop_length() -> float:
	var radius: float = height * 0.5
	var max_loop: float = 0.0
	for i in range(conveyor_count):
		var geom: Array[Vector3] = _get_slot_geometry(i)
		var slot_length: float = geom[1].x
		if slot_length <= _MIN_SLOT_LENGTH:
			continue
		var loop: float = 2.0 * (slot_length - 2.0 * radius) + 2.0 * PI * radius
		if loop > max_loop:
			max_loop = loop
	return max_loop


func _rebuild_belt_slots() -> void:
	var belt := _MergeSurface.new()
	var caps := _MergeSurface.new()
	for i in range(conveyor_count):
		var geom: Array[Vector3] = _get_slot_geometry(i)
		var slot_pos: Vector3 = geom[0]
		var slot_size: Vector3 = geom[1]
		var slot_length: float = slot_size.x
		var slot_height: float = slot_size.y
		var slot_width: float = slot_size.z
		if slot_length <= _MIN_SLOT_LENGTH:
			continue
		var inner_gap: float = ConveyorFrameMesh.WALL_THICKNESS
		var left_gap: float = inner_gap * 0.5 if i > 0 else 0.0
		var right_gap: float = inner_gap * 0.5 if i < conveyor_count - 1 else 0.0
		var mesh_width: float = slot_width - left_gap - right_gap
		var mesh_pos: Vector3 = Vector3(slot_pos.x, slot_pos.y,
				slot_pos.z + (left_gap - right_gap) * 0.5)
		var uv_y_left: float
		var uv_y_right: float
		if belt_texture == BeltConveyor.BeltTexture.ALTERNATE:
			uv_y_left = 0.0
			uv_y_right = 1.0
		else:
			uv_y_left = float(i) / conveyor_count
			uv_y_right = float(i + 1) / conveyor_count
		var strip: ArrayMesh = BeltConveyorMesh.create_belt(
				slot_length, slot_height, mesh_width,
				true, true,
				i == 0, i == conveyor_count - 1,
				uv_y_left, uv_y_right)
		belt.append_surface(strip, 0, mesh_pos)
		if strip.get_surface_count() > 1:
			caps.append_surface(strip, 1, mesh_pos)

	var mi: MeshInstance3D = get_node_or_null("BeltMesh") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "BeltMesh"
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var mesh := ArrayMesh.new()
	if belt.add_to(mesh):
		mesh.surface_set_material(mesh.get_surface_count() - 1, _belt_material)
	if caps.add_to(mesh):
		mesh.surface_set_material(mesh.get_surface_count() - 1, _frame_material)
	mi.mesh = mesh

	_remove_orphans_with_prefix(["BeltMesh_", "BeltBody_"], PackedStringArray())
	if _belt_material:
		_belt_material.set_shader_parameter("Scale", maxf(1.0, _approximate_loop_length()))


func _rebuild_collision() -> void:
	if _simple_conveyor_shape == null:
		return
	var collision: CollisionShape3D = _simple_conveyor_shape.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return
	var half_w: float = size.z * 0.5
	var half_y: float = size.y * 0.5
	var tan_ds: float = tan(angle_downstream)
	var tan_us: float = tan(angle_upstream)
	var ds_left_x: float = size.x - half_w * tan_ds
	var ds_right_x: float = size.x + half_w * tan_ds
	var us_right_x: float = half_w * tan_us
	var us_left_x: float = -half_w * tan_us
	var points := PackedVector3Array([
		Vector3(ds_left_x, half_y, -half_w),
		Vector3(ds_right_x, half_y, half_w),
		Vector3(us_right_x, half_y, half_w),
		Vector3(us_left_x, half_y, -half_w),
		Vector3(ds_left_x, -half_y, -half_w),
		Vector3(ds_right_x, -half_y, half_w),
		Vector3(us_right_x, -half_y, half_w),
		Vector3(us_left_x, -half_y, -half_w),
	])
	var convex_shape := ConvexPolygonShape3D.new()
	convex_shape.points = points
	collision.shape = convex_shape
	_simple_conveyor_shape.position = Vector3(0, -size.y * 0.5, 0)


func _rebuild_gap_fill() -> void:
	var mi: MeshInstance3D = get_node_or_null("GapFillMesh") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "GapFillMesh"
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		mi.owner = self
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half_w: float = size.z * 0.5
	var tan_ds: float = tan(angle_downstream)
	var tan_us: float = tan(angle_upstream)
	# Downstream: strips are rectangles ending at their center-line X; push the angled
	# face out by one half-strip slope so each strip's inner corner stays enclosed.
	var conv_half_width: float = 0.5 * size.z / float(conveyor_count)
	var ds_shift: float = conv_half_width * absf(tan_ds)
	var ds_left_x: float = size.x - half_w * tan_ds + ds_shift
	var ds_right_x: float = size.x + half_w * tan_ds + ds_shift
	var roller_radius: float = size.y * 0.5
	var us_right_x: float = half_w * tan_us + roller_radius
	var us_left_x: float = -half_w * tan_us + roller_radius
	var ref_cos: float = cos(deg_to_rad(60.0))
	var max_angle: float = maxf(absf(angle_upstream), absf(angle_downstream))
	var y_top: float = -maxf(0.001, _GAP_FILL_DEPTH * cos(max_angle) / ref_cos)
	var y_bot: float = -size.y - 0.005
	var t0 := Vector3(us_left_x, y_top, -half_w)
	var t1 := Vector3(us_right_x, y_top, half_w)
	var t2 := Vector3(ds_right_x, y_top, half_w)
	var t3 := Vector3(ds_left_x, y_top, -half_w)
	var b0 := Vector3(us_left_x, y_bot, -half_w)
	var b1 := Vector3(us_right_x, y_bot, half_w)
	var b2 := Vector3(ds_right_x, y_bot, half_w)
	var b3 := Vector3(ds_left_x, y_bot, -half_w)
	var n_us := Vector3(-1.0, 0.0, tan_us).normalized()
	var n_ds := Vector3(1.0, 0.0, -tan_ds).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	_gap_fill_quad(verts, norms, uvs, indices, t0, t1, t2, t3, Vector3.UP)
	_gap_fill_quad(verts, norms, uvs, indices, b0, b3, b2, b1, Vector3.DOWN)
	_gap_fill_quad(verts, norms, uvs, indices, t0, b0, b3, t3, Vector3(0,0,-1))
	_gap_fill_quad(verts, norms, uvs, indices, t1, t2, b2, b1, Vector3(0,0,1))
	_gap_fill_quad(verts, norms, uvs, indices, t0, t1, b1, b0, n_us)
	_gap_fill_quad(verts, norms, uvs, indices, t3, b3, b2, t2, n_ds)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.set_surface_override_material(0, _frame_material)


static func _gap_fill_quad(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3) -> void:
	var base: int = verts.size()
	verts.append_array([p0, p1, p2, p3])
	norms.append_array([normal, normal, normal, normal])
	var u_dir: Vector3 = (p1 - p0).normalized()
	var v_dir: Vector3 = (p3 - p0).normalized()
	for p: Vector3 in [p0, p1, p2, p3]:
		var d: Vector3 = p - p0
		uvs.append(Vector2(d.dot(u_dir), d.dot(v_dir)))
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _rebuild_frame_rails() -> void:
	if not frame_rails_enabled:
		_remove_named_if_present(["FrameLeft", "FrameRight"])
		return
	var half_w: float = width * 0.5
	var wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var left_extents: Vector2 = _side_extents(-half_w)
	var right_extents: Vector2 = _side_extents(half_w)
	_reconcile_frame_rail("FrameLeft", left_extents, false, -half_w - wt)
	_reconcile_frame_rail("FrameRight", right_extents, true, half_w + wt)


func _reconcile_frame_rail(rail_name: String, extents: Vector2,
		flipped: bool, z_pos: float) -> void:
	var rail_length: float = maxf(0.01, extents.y - extents.x)
	var center_x: float = (extents.x + extents.y) * 0.5
	var mi: MeshInstance3D = get_node_or_null(NodePath(rail_name)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = rail_name
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		mi.owner = self
	mi.mesh = ConveyorFrameMesh.create(rail_length, height, true, true, true)
	mi.set_surface_override_material(0, ConveyorFrameMesh.create_material())
	var rail_basis: Basis = Basis(Vector3.UP, PI) if flipped else Basis.IDENTITY
	mi.transform = Transform3D(rail_basis, Vector3(center_x, -height, z_pos))


func request_side_guard_opening(arc_back: float, arc_front: float, side: String) -> void:
	if arc_front <= arc_back:
		return
	if side != "left" and side != "right":
		return
	var next: Array[SideGuardOpening] = side_guard_openings.duplicate(true)
	next.append(SideGuardOpening.make(arc_back, arc_front, side))
	side_guard_openings = next


func clear_side_guard_openings() -> void:
	if side_guard_openings.is_empty():
		return
	side_guard_openings = []


func _openings_for_side(side: String) -> Array[Vector2]:
	var ranges: Array[Vector2] = []
	for o: SideGuardOpening in side_guard_openings:
		# subtract openings are keep-closed overrides, not cutters; ignore them here.
		if o == null or o.side != side or o.subtract:
			continue
		var s: float = o.arc_back
		var e: float = o.arc_front
		if e <= s:
			continue
		ranges.append(Vector2(s, e))
	ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for r: Vector2 in ranges:
		if merged.is_empty() or r.x > merged[-1].y:
			merged.append(r)
		else:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, r.y))
	return merged


func _rebuild_side_guards() -> void:
	var keep := PackedStringArray()
	var half_w: float = width * 0.5
	var wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var ft: float = ConveyorFrameMesh.FLANGE_THICKNESS
	if left_side_guards_enabled:
		var ext: Vector2 = _side_extents(-half_w)
		var subs: Array[Vector2] = _subdivide_around_openings(ext.x, ext.y, _openings_for_side("left"))
		for k in range(subs.size()):
			var sub: Vector2 = subs[k]
			var n: String = "SideGuardLeft_%d" % k
			keep.append(n)
			_emit_side_guard(n, sub.x, sub.y, false, -half_w - wt, ft)
	if right_side_guards_enabled:
		var ext: Vector2 = _side_extents(half_w)
		var subs: Array[Vector2] = _subdivide_around_openings(ext.x, ext.y, _openings_for_side("right"))
		for k in range(subs.size()):
			var sub: Vector2 = subs[k]
			var n: String = "SideGuardRight_%d" % k
			keep.append(n)
			_emit_side_guard(n, sub.x, sub.y, true, half_w + wt, ft)
	_remove_orphans_with_prefix(["SideGuardLeft_", "SideGuardRight_"], keep)


func _subdivide_around_openings(start_x: float, end_x: float, openings: Array[Vector2]) -> Array[Vector2]:
	var subs: Array[Vector2] = [Vector2(start_x, end_x)]
	for opening: Vector2 in openings:
		var next: Array[Vector2] = []
		for sub: Vector2 in subs:
			if opening.y <= sub.x or opening.x >= sub.y:
				next.append(sub)
				continue
			if opening.x > sub.x:
				next.append(Vector2(sub.x, opening.x))
			if opening.y < sub.y:
				next.append(Vector2(opening.y, sub.y))
		subs = next
	var out: Array[Vector2] = []
	for sub: Vector2 in subs:
		if sub.y - sub.x > _MIN_SLOT_LENGTH:
			out.append(sub)
	return out


func _emit_side_guard(guard_name: String, sub_start: float, sub_end: float,
		flipped: bool, z_pos: float, flange_y: float) -> void:
	var sub_len: float = sub_end - sub_start
	var sub_mid: float = (sub_start + sub_end) * 0.5
	var guard_basis: Basis = Basis(Vector3.UP, PI) if flipped else Basis.IDENTITY
	var origin: Vector3 = Vector3(sub_mid, flange_y, z_pos)
	var sg: SideGuard = get_node_or_null(NodePath(guard_name)) as SideGuard
	if sg == null:
		sg = SideGuard.new()
		sg.name = guard_name
		add_child(sg, false, Node.INTERNAL_MODE_FRONT)
		sg.owner = self
	sg.length = sub_len
	sg.transform = Transform3D(guard_basis, origin)
	sg.arc_back = sub_start
	sg.arc_front = sub_end


const _LEG_TAIL_NAME := "Leg_Tail"
const _LEG_HEAD_NAME := "Leg_Head"
const _LEG_MIDDLE_PREFIX := "Leg_Middle_"


func _rebuild_legs() -> void:
	_legs.clear()
	var keep: Dictionary = {}
	if not legs_enabled or leg_model_scene == null:
		_remove_orphan_legs(keep)
		return
	var specs: Array = _compute_leg_specs(length)
	if specs.is_empty():
		_remove_orphan_legs(keep)
		return
	var leg_z_scale: float = maxf(0.1, width * 0.5)
	var node_xform: Transform3D = global_transform if is_inside_tree() else Transform3D.IDENTITY
	var cross_axis_world: Vector3 = node_xform.basis.z.normalized()
	var legs_normal_world: Vector3 = floor_plane.normal.slide(cross_axis_world)
	if legs_normal_world.length_squared() < 1.0e-6:
		_remove_orphan_legs(keep)
		return
	legs_normal_world = legs_normal_world.normalized()
	for spec: Dictionary in specs:
		var leg_name: String = spec["name"]
		var x: float = spec["x"]
		var belt_bottom_local: Vector3 = Vector3(x, -height, 0.0)
		var belt_bottom_world: Vector3 = node_xform * belt_bottom_local
		var foot_v: Variant = LegFooting.resolve_foot(self, belt_bottom_world, legs_normal_world, floor_plane)
		if foot_v == null:
			continue
		var foot_world: Vector3 = foot_v
		var leg_height: float = (belt_bottom_world - foot_world).dot(legs_normal_world)
		if leg_height <= 0.05:
			continue
		var leg: Node3D = get_node_or_null(NodePath(leg_name)) as Node3D
		if leg == null:
			leg = leg_model_scene.instantiate() as Node3D
			if leg == null:
				continue
			leg.name = leg_name
			add_child(leg, false, Node.INTERNAL_MODE_FRONT)
		leg.visible = true
		var foot_local: Vector3 = node_xform.affine_inverse() * foot_world
		leg.position = foot_local
		leg.scale = Vector3(1.0, leg_height, leg_z_scale)
		keep[leg_name] = true
		_legs.append(leg)
	_remove_orphan_legs(keep)


func _remove_orphan_legs(keep: Dictionary) -> void:
	for child in get_children(true):
		var n: String = String(child.name)
		if not n.begins_with("Leg_"):
			continue
		if keep.has(n):
			continue
		remove_child(child)
		child.queue_free()


func _reposition_existing_legs() -> void:
	if not legs_enabled or leg_model_scene == null:
		return
	var leg_z_scale: float = maxf(0.1, width * 0.5)
	var node_xform: Transform3D = global_transform if is_inside_tree() else Transform3D.IDENTITY
	var cross_axis_world: Vector3 = node_xform.basis.z.normalized()
	var legs_normal_world: Vector3 = floor_plane.normal.slide(cross_axis_world)
	if legs_normal_world.length_squared() < 1.0e-6:
		return
	legs_normal_world = legs_normal_world.normalized()
	for spec: Dictionary in _compute_leg_specs(length):
		var leg: Node3D = get_node_or_null(NodePath(spec["name"])) as Node3D
		if leg == null:
			continue
		var x: float = spec["x"]
		var belt_bottom_local: Vector3 = Vector3(x, -height, 0.0)
		var belt_bottom_world: Vector3 = node_xform * belt_bottom_local
		var foot_v: Variant = LegFooting.resolve_foot(self, belt_bottom_world, legs_normal_world, floor_plane)
		if foot_v == null:
			leg.visible = false
			continue
		var foot_world: Vector3 = foot_v
		var leg_height: float = (belt_bottom_world - foot_world).dot(legs_normal_world)
		if leg_height <= 0.05:
			leg.visible = false
			continue
		leg.visible = true
		var foot_local: Vector3 = node_xform.affine_inverse() * foot_world
		leg.position = foot_local
		leg.scale = Vector3(1.0, leg_height, leg_z_scale)


func _compute_leg_specs(top_len: float) -> Array:
	var specs: Array = []
	var coverage_min: float = tail_end_attachment_offset if tail_end_leg_enabled else 0.0
	var coverage_max: float = top_len - head_end_attachment_offset if head_end_leg_enabled else top_len
	if tail_end_leg_enabled and coverage_min <= top_len and not _is_x_excluded(coverage_min):
		specs.append({"name": _LEG_TAIL_NAME, "x": coverage_min})
	if middle_legs_enabled and middle_legs_spacing > 0.0:
		var tail_clear: float = tail_end_leg_clearance if tail_end_leg_enabled else 0.0
		var head_clear: float = head_end_leg_clearance if head_end_leg_enabled else 0.0
		var first: float = coverage_min + tail_clear + middle_legs_spacing
		var last: float = coverage_max - head_clear
		var idx: int = 1
		var pos: float = first
		while pos <= last + 1.0e-6:
			if pos >= 0.0 and pos <= top_len and not _is_x_excluded(pos):
				specs.append({"name": "%s%d" % [_LEG_MIDDLE_PREFIX, idx], "x": pos})
				idx += 1
			pos += middle_legs_spacing
	if head_end_leg_enabled and coverage_max >= 0.0 and coverage_max <= top_len \
			and not _is_x_excluded(coverage_max):
		specs.append({"name": _LEG_HEAD_NAME, "x": coverage_max})
	return specs


func _is_x_excluded(x: float) -> bool:
	if exclusion_start == 0.0 and exclusion_end == 0.0:
		return false
	return x >= exclusion_start and x <= exclusion_end


func _apply_physics_material() -> void:
	if is_instance_valid(_simple_conveyor_shape):
		_simple_conveyor_shape.physics_material_override = physics_material


func _update_flow_arrow() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
		_flow_arrow.queue_free()
		_flow_arrow = null
	if length <= 0.0:
		return
	_flow_arrow = FlowDirectionArrow.create(Vector3(length, 0.0, width))
	_flow_arrow.position = Vector3(length * 0.5, 0.2, 0.0)
	add_child(_flow_arrow, false, Node.INTERNAL_MODE_FRONT)
	FlowDirectionArrow.register(_flow_arrow)
	if has_meta("is_preview"):
		_flow_arrow.visible = true


func _physics_process(delta: float) -> void:
	if LegFooting.legs_state_changed(self, _legs_state):
		_rebuild_legs()
		_legs_state = LegFooting.capture_leg_state(self)
	if not Simulation.is_running() or Simulation.is_paused():
		return
	BeltSurface.apply_velocity(_simple_conveyor_shape, speed)
	_belt_position = BeltSurface.advance_belt_position(
			_belt_material, speed, delta, _belt_position)


func _on_simulation_started() -> void:
	if enable_comms:
		_speed_tag.register(speed_tag_group_name, speed_tag_name, OIPComms.TAG_TYPE_FLOAT32)
		_running_tag.register(running_tag_group_name, running_tag_name, OIPComms.TAG_TYPE_BOOL)


func _on_simulation_ended() -> void:
	if _running_tag.is_ready():
		_running_tag.write_bit(false)
	_belt_position = 0.0
	if _belt_material:
		_belt_material.set_shader_parameter("BeltPosition", _belt_position)
	if is_instance_valid(_simple_conveyor_shape):
		_simple_conveyor_shape.constant_linear_velocity = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	_running_tag.on_group_initialized(tag_group_name_param)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return
	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()


func _remove_orphans_with_prefix(prefixes: Array, keep: PackedStringArray) -> void:
	for child in get_children(true):
		var n: String = child.name
		if n in keep:
			continue
		for prefix: String in prefixes:
			if n.begins_with(prefix):
				remove_child(child)
				child.queue_free()
				break


func _remove_named_if_present(names: Array) -> void:
	for n: String in names:
		var c := get_node_or_null(NodePath(n))
		if is_instance_valid(c):
			remove_child(c)
			c.queue_free()


class _MergeSurface:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func append_surface(src: ArrayMesh, surface: int, offset: Vector3) -> void:
		var a: Array = src.surface_get_arrays(surface)
		var base: int = verts.size()
		for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
			verts.append(v + offset)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		for idx: int in a[Mesh.ARRAY_INDEX]:
			indices.append(base + idx)

	func add_to(mesh: ArrayMesh) -> bool:
		if indices.is_empty():
			return false
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return true
