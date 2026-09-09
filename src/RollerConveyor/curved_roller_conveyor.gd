@tool
class_name CurvedRollerConveyor
extends ResizableNode3D

const BASE_INNER_RADIUS: float = 0.5
const BASE_CONVEYOR_WIDTH: float = 1.524
const BASE_HEIGHT: float = 0.5

const CORNER_MESH_PATH := "res://assets/3DModels/Meshes/ConveyorRollerRollerCorner_Cylinder_002.res"

## Roller tube size, as a matched real-world duty class.
@export var roller_class: RollerSpec.DutyClass = RollerSpec.DutyClass.HEAVY:
	set(value):
		if roller_class == value:
			return
		roller_class = value
		if is_inside_tree():
			_update_rollers()
			_update_end_positions()

## Inner curve edge radius in meters.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var inner_radius: float = BASE_INNER_RADIUS:
	set(value):
		var clamped: float = max(0.1, value)
		if inner_radius == clamped:
			return
		inner_radius = clamped
		_sync_size_from_dimensions()

@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:m") var width: float = BASE_CONVEYOR_WIDTH:
	set(value):
		var clamped: float = max(0.1, value)
		if width == clamped:
			return
		width = clamped
		_sync_size_from_dimensions()

@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var height: float = BASE_HEIGHT:
	set(value):
		var clamped: float = max(0.1, value)
		if height == clamped:
			return
		height = clamped
		_sync_size_from_dimensions()


func _sync_size_from_dimensions() -> void:
	var d: float = 2.0 * (inner_radius + width)
	size = Vector3(d, height, d)


var local_bbox: AABB:
	get:
		var r_out: float = inner_radius + width
		var a: float = deg_to_rad(conveyor_angle)
		var c: float = cos(a)
		var x_min: float = -r_out * (1.0 if a >= PI * 0.5 else sin(a))
		var z_min: float = c * (inner_radius if c >= 0.0 else r_out)
		return AABB(Vector3(x_min, -height, z_min), Vector3(-x_min, height, r_out - z_min))


func _get_editor_rotation_lock() -> int:
	return (1 << 0) | (1 << 2)


func _get_constrained_size(new_size: Vector3) -> Vector3:
	var d: float
	match _resize_handle:
		0, 1:
			d = new_size.x
		4, 5:
			d = new_size.z
		_:
			d = maxf(new_size.x, new_size.z)
	d = maxf(2.0 * (0.1 + 0.1), d)
	return Vector3(d, new_size.y, d)


# Curved geometry has four parameters (inner_radius / width / height / conveyor_angle);
# the rectangular 6-handle model doesn't fit. Edit via the inspector.
func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array()


func _on_size_changed() -> void:
	var derived_width: float = maxf(0.1, size.x * 0.5 - inner_radius)
	if not is_equal_approx(width, derived_width):
		width = derived_width
	if not is_equal_approx(height, size.y):
		height = size.y
	_mesh_regeneration_needed = true
	_update_all_components()


## Curve section angle (5-180 degrees).
@export_range(5.0, 180.0, 1.0, "degrees") var conveyor_angle: float = 90.0:
	set(value):
		if conveyor_angle == value:
			return
		conveyor_angle = value
		_mesh_regeneration_needed = true
		_update_all_components()

## Hidden from the inspector — flipped by the snap system to reverse flow when
## a curved conveyor can't be rotated 180° (would swap inner/outer). Users
## should reverse direction via negative [member speed] instead.
@export_storage var reverse: bool = false:
	set(value):
		reverse = value
		_recalculate_speeds()
		_update_flow_arrow()
		_sync_preview_overlay_arrow(value)

## Linear speed at [member reference_distance] in m/s.
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 1.0:
	set(value):
		if value == speed:
			return
		speed = value
		_recalculate_speeds()
		if _running_tag.is_ready():
			_running_tag.write_bit(value != 0.0)

## Distance from outer edge where [member speed] is measured.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var reference_distance: float = BASE_CONVEYOR_WIDTH / 2.0:
	set(value):
		reference_distance = value
		_recalculate_speeds()

## Physics material applied to the conveyor bodies.
@export var physics_material: PhysicsMaterial = preload("res://parts/RollerSurfaceMaterial.tres"):
	set(value):
		physics_material = value
		_apply_physics_material()


func _roller_radius() -> float:
	return RollerSpec.radius(roller_class)


func _radial_scale() -> float:
	return RollerSpec.radial_scale(roller_class)


func _apply_physics_material() -> void:
	if _sb:
		_sb.physics_material_override = physics_material
	for static_body in _end_static_bodies:
		if is_instance_valid(static_body):
			static_body.physics_material_override = physics_material


@export_group("Side Guards")
@export var inner_side_guards_enabled: bool = true:
	set(value):
		if value == inner_side_guards_enabled:
			return
		inner_side_guards_enabled = value
		_rebuild_side_guards()

@export var outer_side_guards_enabled: bool = true:
	set(value):
		if value == outer_side_guards_enabled:
			return
		outer_side_guards_enabled = value
		_rebuild_side_guards()

## Openings in arc-length (m) along average radius. Side: [code]"inner"[/code]/[code]"outer"[/code].
@export var side_guard_openings: Array[SideGuardOpening] = []:
	set(value):
		SideGuardOpening.sync_change_listeners(side_guard_openings, value, _rebuild_side_guards, true, _guard_arc_bounds())
		side_guard_openings = value
		_rebuild_side_guards()


@export_group("Legs")
@export var legs_enabled: bool = true:
	set(value):
		if value == legs_enabled:
			return
		legs_enabled = value
		_rebuild_legs()

@export var floor_plane: Plane = Plane(Vector3.UP, -2.0):
	set(value):
		if floor_plane.is_equal_approx(value):
			return
		floor_plane = value
		_rebuild_legs()


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


@export var leg_model_scene: PackedScene = preload("res://parts/StraightLeg.tscn"):
	set(value):
		leg_model_scene = value
		_rebuild_legs()

@export_subgroup("Tail End", "tail_end")
@export var tail_end_leg_enabled: bool = true:
	set(value):
		if value == tail_end_leg_enabled:
			return
		tail_end_leg_enabled = value
		_rebuild_legs()

@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var tail_end_attachment_offset: float = 0.0:
	set(value):
		if value == tail_end_attachment_offset:
			return
		tail_end_attachment_offset = maxf(0.0, value)
		_rebuild_legs()

@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m") var tail_end_leg_clearance: float = 0.5:
	set(value):
		if value == tail_end_leg_clearance:
			return
		tail_end_leg_clearance = maxf(0.0, value)
		_rebuild_legs()

@export_subgroup("Head End", "head_end")
@export var head_end_leg_enabled: bool = true:
	set(value):
		if value == head_end_leg_enabled:
			return
		head_end_leg_enabled = value
		_rebuild_legs()

@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var head_end_attachment_offset: float = 0.0:
	set(value):
		if value == head_end_attachment_offset:
			return
		head_end_attachment_offset = maxf(0.0, value)
		_rebuild_legs()

@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m") var head_end_leg_clearance: float = 0.5:
	set(value):
		if value == head_end_leg_clearance:
			return
		head_end_leg_clearance = maxf(0.0, value)
		_rebuild_legs()

@export_subgroup("Middle Legs", "middle_legs")
@export var middle_legs_enabled: bool = false:
	set(value):
		if value == middle_legs_enabled:
			return
		middle_legs_enabled = value
		_rebuild_legs()

@export_range(0.5, 10.0, 0.05, "or_greater", "suffix:m") var middle_legs_spacing: float = 2.0:
	set(value):
		var clamped: float = maxf(0.5, value)
		if clamped == middle_legs_spacing:
			return
		middle_legs_spacing = clamped
		_rebuild_legs()

@export_subgroup("Leg Exclusion Zone", "exclusion_")
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var exclusion_start: float = 0.0:
	set(value):
		if value == exclusion_start:
			return
		exclusion_start = value
		_rebuild_legs()

@export_custom(PROPERTY_HINT_NONE, "suffix:m") var exclusion_end: float = 0.0:
	set(value):
		if value == exclusion_end:
			return
		exclusion_end = value
		_rebuild_legs()


var _mesh_regeneration_needed: bool = true
var _angular_speed: float = 0.0

var running: bool = false

@onready var _sb: StaticBody3D = get_node("StaticBody3D")
var _flow_arrow: Node3D
var _legs_state: Dictionary = {}
var _frame_mesh_instance: MeshInstance3D
var _metal_material: Material

var _rollers_mm: MultiMeshInstance3D
var roller_material: StandardMaterial3D
var _corner_mesh: ArrayMesh
var ends: Node3D

var _end_static_bodies: Array[StaticBody3D] = []

var _speed_tag := OIPCommsTag.new()
var _running_tag := OIPCommsTag.new()
@export_category("Communications")
@export var enable_comms := false
@export var speed_tag_group_name: String
@export_custom(0, "tag_group_enum") var speed_tag_groups: String:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
## The tag name for the speed value in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var speed_tag_name := ""
@export var running_tag_group_name: String
@export_custom(0, "tag_group_enum") var running_tag_groups: String:
	set(value):
		running_tag_group_name = value
		running_tag_groups = value
## The tag name for the running state in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var running_tag_name := ""


func _validate_property(property: Dictionary) -> void:
	if property.name == "size":
		property.usage = PROPERTY_USAGE_STORAGE
		return
	if OIPCommsSetup.validate_tag_property(property, "speed_tag_group_name", "speed_tag_groups", "speed_tag_name"):
		return
	OIPCommsSetup.validate_tag_property(property, "running_tag_group_name", "running_tag_groups", "running_tag_name")


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/CurvedRollerConveyor.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)

	_disable_collisions_recursive(preview_node)

	var preview_arrow: Node3D = FlowDirectionArrow.create_curved(
		inner_radius, width, height, conveyor_angle)
	preview_arrow.name = &"PreviewFlowDirectionArrow"
	preview_node.add_child(preview_arrow)

	return preview_node


func _rebuild_preview_flow_arrow(reversed: bool) -> void:
	var existing := get_node_or_null("PreviewFlowDirectionArrow")
	if existing == null:
		return
	# queue_free is deferred; rename so the new arrow can claim the name this frame.
	existing.name = &"_dead_overlay_arrow"
	existing.queue_free()
	var preview_arrow: Node3D = FlowDirectionArrow.create_curved(
		inner_radius, width, height, conveyor_angle, reversed)
	preview_arrow.name = &"PreviewFlowDirectionArrow"
	add_child(preview_arrow)


func _sync_preview_overlay_arrow(reversed: bool) -> void:
	_rebuild_preview_flow_arrow(reversed)
	var parent := get_parent()
	if parent and parent.has_method(&"_rebuild_preview_flow_arrow"):
		parent.call(&"_rebuild_preview_flow_arrow", reversed)


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		node.disabled = true

	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0

	# `true` includes INTERNAL_MODE_FRONT children (auto-managed legs etc.).
	for child in node.get_children(true):
		_disable_collisions_recursive(child)


func _reset_preview_holder_transform() -> void:
	if not has_meta("is_preview"):
		return
	var holder := get_parent() as Node3D
	if holder == null:
		return
	holder.transform = Transform3D.IDENTITY


func _init() -> void:
	super._init()
	var default_diameter: float = 2.0 * (BASE_INNER_RADIUS + BASE_CONVEYOR_WIDTH)
	size_default = Vector3(default_diameter, BASE_HEIGHT, default_diameter)
	if size == Vector3.ZERO:
		size = size_default


func _ready() -> void:
	_reset_preview_holder_transform()
	var collision_shape := _sb.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()

	_rollers_mm = get_node_or_null("Rollers")

	roller_material = _takeover_roller_material()
	_ensure_roller_multimeshes()

	ends = get_node_or_null("Ends")

	_metal_material = ConveyorFrameMesh.create_material()
	_frame_mesh_instance = get_node_or_null("FrameMesh") as MeshInstance3D
	if not _frame_mesh_instance:
		_frame_mesh_instance = MeshInstance3D.new()
		_frame_mesh_instance.name = "FrameMesh"
		add_child(_frame_mesh_instance)

	# Rollers cast their own shadows now; drop the solid shadow slab a saved scene may still carry.
	var existing_shadow := get_node_or_null("ShadowPlate")
	if existing_shadow:
		existing_shadow.queue_free()

	SideGuardOpening.claim_unique(side_guard_openings, get_instance_id())
	SideGuardOpening.sync_change_listeners([], side_guard_openings, _rebuild_side_guards, true)

	_mesh_regeneration_needed = true
	_update_all_components()
	size_changed.emit()
	_update_flow_arrow()
	if has_meta("is_preview"):
		_disable_collisions_recursive(self)


func _update_flow_arrow() -> void:
	if _flow_arrow:
		FlowDirectionArrow.unregister(_flow_arrow)
		_flow_arrow.queue_free()
	_flow_arrow = FlowDirectionArrow.create_curved(
		inner_radius, width, height, conveyor_angle, reverse)
	add_child(_flow_arrow, false, Node.INTERNAL_MODE_FRONT)
	FlowDirectionArrow.register(_flow_arrow)


func _enter_tree() -> void:
	super._enter_tree()
	speed_tag_group_name = OIPCommsSetup.default_tag_group(speed_tag_group_name)
	running_tag_group_name = OIPCommsSetup.default_tag_group(running_tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)
	ConveyorSnapping.notify_contacts_rebuild(self)


func _exit_tree() -> void:
	ConveyorSnapping.notify_contacts_rebuild(self)
	if _flow_arrow:
		FlowDirectionArrow.unregister(_flow_arrow)
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)
	super._exit_tree()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_rebuild_legs()
		ConveyorSnapping.notify_contacts_rebuild(self)


func _get_scale_warning_text() -> String:
	return "Use `inner_radius` / `width` / `height` / `conveyor_angle` instead of scale."


func _process(delta: float) -> void:
	if running and roller_material:
		var effective_speed := speed * (-1.0 if reverse else 1.0)
		# uv1_offset is in tiled-UV units; scale by tiles-per-wrap for true no-slip speed.
		var bands: float = roller_material.uv1_scale.x
		var uv_speed := bands * effective_speed / (2.0 * PI * _roller_radius())
		var uv_offset := roller_material.uv1_offset
		if not Simulation.is_paused():
			uv_offset.x = fmod(fmod(uv_offset.x, 1.0) + uv_speed * delta, 1.0)
		roller_material.uv1_offset = uv_offset


func _physics_process(delta: float) -> void:
	if LegFooting.legs_state_changed(self, _legs_state):
		_rebuild_legs()
		_legs_state = LegFooting.capture_leg_state(self)
	if Simulation.is_running() and _sb:
		var local_up := _sb.global_transform.basis.y.normalized()
		_sb.constant_angular_velocity = -local_up * _angular_speed

		var effective_speed := speed * (-1.0 if reverse else 1.0)
		for static_body in _end_static_bodies:
			var end_axis: Node3D = static_body.get_parent() as Node3D
			var velocity_dir: Vector3 = end_axis.global_transform.basis * Vector3(-1, 0, 0)
			static_body.constant_linear_velocity = velocity_dir.normalized() * effective_speed
	else:
		if _sb:
			_sb.constant_angular_velocity = Vector3.ZERO
		for static_body in _end_static_bodies:
			static_body.constant_linear_velocity = Vector3.ZERO


func _update_all_components() -> void:
	if not is_inside_tree():
		return

	_update_mesh()
	_recalculate_speeds()
	_update_side_guards()
	_update_assembly_components()
	_update_flow_arrow()
	ConveyorSnapping.notify_contacts_rebuild(self)
	if Engine.is_editor_hint():
		update_gizmos()


func _update_mesh() -> void:
	if not is_inside_tree() or not _frame_mesh_instance:
		return

	if _mesh_regeneration_needed:
		_create_frame_mesh()
		_create_collision_shape()
		_create_end_collision_shapes()
		_apply_physics_material()
		_mesh_regeneration_needed = false

	_update_rollers()
	_update_end_positions()
	_update_end_axis_angle()


func _create_frame_mesh() -> void:
	var angle_radians: float = deg_to_rad(conveyor_angle)
	var segments: int = maxi(4, int(conveyor_angle / 5.0))
	const DEFAULT_HEIGHT_RATIO: float = 0.50
	var mesh_height: float = DEFAULT_HEIGHT_RATIO * height
	const MESH_SCALE_FACTOR := 2.0

	var y_top: float = 0.125 * MESH_SCALE_FACTOR
	var y_bottom: float = (-mesh_height + 0.125) * MESH_SCALE_FACTOR

	var r_outer: float = inner_radius + width
	var mesh := ConveyorFrameMesh.create_curved(
			inner_radius, r_outer,
			y_top, y_bottom, angle_radians, segments, MESH_SCALE_FACTOR)
	mesh.surface_set_material(0, _metal_material)

	var tangent_r: float = height / 4.0 * 2.0
	ConveyorFrameMesh.add_curved_end_walls(mesh,
			inner_radius, r_outer, y_top, y_bottom, angle_radians,
			tangent_r, MESH_SCALE_FACTOR, _metal_material)

	_frame_mesh_instance.mesh = mesh
	_frame_mesh_instance.scale = Vector3(1.0 / MESH_SCALE_FACTOR, 1.0, 1.0 / MESH_SCALE_FACTOR)

	_frame_mesh_instance.position.y = -0.25


func _create_collision_shape() -> void:
	var collision_shape: CollisionShape3D = _sb.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision_shape:
		return

	var segments: int = maxi(1, int(conveyor_angle / 3.0))
	var angle_radians: float = deg_to_rad(conveyor_angle)
	const DEFAULT_HEIGHT_RATIO: float = 0.50
	var mesh_height: float = DEFAULT_HEIGHT_RATIO * height
	const MESH_SCALE_FACTOR := 2.0

	var all_verts := PackedVector3Array()
	var all_indices := PackedInt32Array()

	for i in range(segments + 1):
		var t: float = float(i) / segments
		var angle: float = t * angle_radians
		var sin_a: float = sin(angle)
		var cos_a: float = cos(angle)

		var it: Vector3 = Vector3(-sin_a * inner_radius, 0.125, cos_a * inner_radius) * MESH_SCALE_FACTOR
		var ot: Vector3 = Vector3(-sin_a * (inner_radius + width), 0.125, cos_a * (inner_radius + width)) * MESH_SCALE_FACTOR
		var ib: Vector3 = Vector3(-sin_a * inner_radius, -mesh_height + 0.125, cos_a * inner_radius) * MESH_SCALE_FACTOR
		var ob: Vector3 = Vector3(-sin_a * (inner_radius + width), -mesh_height + 0.125, cos_a * (inner_radius + width)) * MESH_SCALE_FACTOR

		all_verts.append_array([it, ot, ib, ob])

	for i in range(segments):
		var b: int = i * 4
		all_indices.append_array([b, b + 1, b + 5, b, b + 5, b + 4])
		all_indices.append_array([b + 5, b + 1, b, b + 4, b + 5, b])
		all_indices.append_array([b + 2, b + 6, b + 3, b + 3, b + 6, b + 7])
		all_indices.append_array([b + 3, b + 6, b + 2, b + 7, b + 6, b + 3])

	var triangle_verts := PackedVector3Array()
	var base_scale := 1.0 / MESH_SCALE_FACTOR
	for i in range(0, all_indices.size(), 3):
		if i + 2 >= all_indices.size():
			break
		for j in range(3):
			var v: Vector3 = all_verts[all_indices[i + j]]
			triangle_verts.append(Vector3(v.x * base_scale, v.y, v.z * base_scale))

	var shape: ConcavePolygonShape3D = collision_shape.shape
	shape.data = triangle_verts
	collision_shape.scale = Vector3.ONE
	_sb.position.y = -0.25


func _update_rollers() -> void:
	if _rollers_mm == null or _rollers_mm.multimesh == null:
		return
	var center_r: float = inner_radius + width / 2.0
	var angle_rad: float = deg_to_rad(conveyor_angle)
	# Centerline pitch, so density matches a straight conveyor a snapped one can stay continuous with.
	var dtheta: float = RollerSpec.pitch(roller_class) / maxf(center_r, 0.01)
	var count: int = maxi(2, ceili(angle_rad / dtheta) + 1)

	var z_scale: float = width / RollerCorner.MODEL_BASE_LENGTH
	var radial := Transform3D(Basis.IDENTITY, Vector3(0, -_roller_radius(), center_r))
	var scale_xform := Transform3D(Basis.from_scale(Vector3(_radial_scale(), _radial_scale(), z_scale)), Vector3.ZERO)
	var mm := _rollers_mm.multimesh
	mm.instance_count = count
	for i in count:
		var a := angle_rad * float(i) / float(count - 1)
		var axis := Transform3D(Basis(Vector3.UP, -a), Vector3.ZERO)
		mm.set_instance_transform(i, axis * radial * scale_xform)


func _takeover_roller_material() -> StandardMaterial3D:
	return load("res://assets/3DModels/Materials/Metall2.tres").duplicate(true) as StandardMaterial3D


func _ensure_roller_multimeshes() -> void:
	if _corner_mesh == null:
		_corner_mesh = (load(CORNER_MESH_PATH) as ArrayMesh).duplicate() as ArrayMesh
		if roller_material and _corner_mesh.get_surface_count() > 0:
			_corner_mesh.surface_set_material(0, roller_material)
	if _rollers_mm == null:
		return
	_rollers_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _rollers_mm.multimesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _corner_mesh
		_rollers_mm.multimesh = mm


func _update_end_positions() -> void:
	if not ends:
		return
	var center_r: float = inner_radius + width / 2.0
	for end_axis in ends.get_children():
		var roller := end_axis.get_child(0) as RollerCorner
		if roller:
			roller.radial_scale = _radial_scale()
			roller.position = Vector3(0, -_roller_radius(), center_r)
			roller.length = width
			if roller_material:
				roller.set_override_material(roller_material)


func _update_end_axis_angle() -> void:
	if ends:
		var end_axis2 := ends.get_node_or_null("EndAxis2")
		if end_axis2:
			end_axis2.rotation_degrees.y = -conveyor_angle


func _create_end_collision_shapes() -> void:
	if not ends:
		return

	_end_static_bodies.clear()
	var center_r: float = inner_radius + width / 2.0

	for end_axis in ends.get_children():
		var roller := end_axis.get_child(0) as RollerCorner
		if not roller:
			continue

		var static_body := end_axis.get_node_or_null("StaticBody3D") as StaticBody3D
		if not static_body:
			static_body = StaticBody3D.new()
			static_body.name = "StaticBody3D"
			end_axis.add_child(static_body)

		var collision_shape := static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			static_body.add_child(collision_shape)

		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.125, 0.25, width)

		var box_y: float = -box_shape.size.y / 2.0
		if end_axis.name == "EndAxis2":
			collision_shape.position = Vector3(-0.06, box_y, center_r)
		else:
			collision_shape.position = Vector3(0.06, box_y, center_r)

		collision_shape.shape = box_shape
		_end_static_bodies.append(static_body)


func _recalculate_speeds() -> void:
	var direction := -1.0 if reverse else 1.0
	var effective_speed := speed * direction
	var outer_radius: float = inner_radius + width
	var reference_radius: float = outer_radius - reference_distance
	_angular_speed = 0.0 if absf(reference_radius) < 1e-6 else effective_speed / reference_radius


func _update_side_guards() -> void:
	_rebuild_side_guards()


func _update_assembly_components() -> void:
	_rebuild_legs()


const _SIDE_INNER := "inner"
const _SIDE_OUTER := "outer"
const _MIN_GUARD_ARC: float = 0.05

func request_side_guard_opening(arc_back: float, arc_front: float, side: String) -> void:
	if arc_front <= arc_back:
		return
	if side != _SIDE_INNER and side != _SIDE_OUTER:
		return
	var next: Array[SideGuardOpening] = side_guard_openings.duplicate(true)
	next.append(SideGuardOpening.make(arc_back, arc_front, side))
	side_guard_openings = next


func clear_side_guard_openings() -> void:
	if side_guard_openings.is_empty():
		return
	side_guard_openings = []


func _avg_radius() -> float:
	return inner_radius + width * 0.5


## Side-guard arc extent for a new opening's default span. arc 0 is the back tangent, not the body start.
func _guard_arc_bounds() -> Vector2:
	return Vector2(0.0, _avg_radius() * deg_to_rad(conveyor_angle) + height)


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


func _subdivide_around_openings(start_arc: float, end_arc: float, openings: Array[Vector2]) -> Array[Vector2]:
	var subs: Array[Vector2] = [Vector2(start_arc, end_arc)]
	for opening: Vector2 in openings:
		var next_subs: Array[Vector2] = []
		for sub: Vector2 in subs:
			if opening.y <= sub.x or opening.x >= sub.y:
				next_subs.append(sub)
				continue
			if opening.x > sub.x:
				next_subs.append(Vector2(sub.x, opening.x))
			if opening.y < sub.y:
				next_subs.append(Vector2(opening.y, sub.y))
		subs = next_subs
	var out: Array[Vector2] = []
	for sub: Vector2 in subs:
		if sub.y - sub.x > _MIN_GUARD_ARC:
			out.append(sub)
	return out


func _rebuild_side_guards() -> void:
	if not is_inside_tree():
		return
	var keep := PackedStringArray()
	if not (inner_side_guards_enabled or outer_side_guards_enabled):
		_remove_orphans_with_prefix(["SideGuardInner_", "SideGuardOuter_"], keep)
		return
	var avg_r: float = _avg_radius()
	var conveyor_angle_rad: float = deg_to_rad(conveyor_angle)
	var tangent_ext: float = height * 0.5
	var natural_back_arc: float = 0.0
	var natural_front_arc: float = avg_r * conveyor_angle_rad + 2.0 * tangent_ext
	var arc_back_inset: float = tangent_ext
	var arc_front_inset: float = tangent_ext + avg_r * conveyor_angle_rad
	var frame_wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var inner_radius_guard: float = inner_radius - frame_wt
	var outer_radius_guard: float = inner_radius + width + frame_wt

	if inner_side_guards_enabled:
		var subs: Array[Vector2] = _subdivide_around_openings(natural_back_arc, natural_front_arc, _openings_for_side(_SIDE_INNER))
		for k in range(subs.size()):
			var sub: Vector2 = subs[k]
			var n: String = "SideGuardInner_%d" % k
			keep.append(n)
			_emit_curved_guard(n, sub.x, sub.y, inner_radius_guard, false,
				avg_r, arc_back_inset, arc_front_inset, tangent_ext)
	if outer_side_guards_enabled:
		var subs: Array[Vector2] = _subdivide_around_openings(natural_back_arc, natural_front_arc, _openings_for_side(_SIDE_OUTER))
		for k in range(subs.size()):
			var sub: Vector2 = subs[k]
			var n: String = "SideGuardOuter_%d" % k
			keep.append(n)
			_emit_curved_guard(n, sub.x, sub.y, outer_radius_guard, true,
				avg_r, arc_back_inset, arc_front_inset, tangent_ext)
	_remove_orphans_with_prefix(["SideGuardInner_", "SideGuardOuter_"], keep)


func _emit_curved_guard(guard_name: String, sub_back_arc: float, sub_front_arc: float,
		guard_radius: float, outer: bool,
		avg_r: float, arc_back_inset: float, arc_front_inset: float, tangent_ext: float) -> void:
	var clipped_back_arc: float = clampf(sub_back_arc, arc_back_inset, arc_front_inset)
	var clipped_front_arc: float = clampf(sub_front_arc, arc_back_inset, arc_front_inset)
	var start_angle: float = (clipped_back_arc - arc_back_inset) / avg_r
	var end_angle: float = (clipped_front_arc - arc_back_inset) / avg_r
	var back_ext: float = 0.0
	var front_ext: float = 0.0
	if sub_back_arc < arc_back_inset:
		back_ext = minf(arc_back_inset - sub_back_arc, tangent_ext)
	if sub_front_arc > arc_front_inset:
		front_ext = minf(sub_front_arc - arc_front_inset, tangent_ext)

	var sg: CurvedSideGuard = get_node_or_null(NodePath(guard_name)) as CurvedSideGuard
	var fresh: bool = sg == null
	if fresh:
		sg = CurvedSideGuard.new()
		sg.name = guard_name
	sg.radius = guard_radius
	sg.start_angle_rad = start_angle
	sg.end_angle_rad = end_angle
	sg.outer_side = outer
	sg.back_ext = back_ext
	sg.front_ext = front_ext
	sg.arc_back = sub_back_arc
	sg.arc_front = sub_front_arc
	if fresh:
		add_child(sg, false, Node.INTERNAL_MODE_FRONT)


const _LEG_TAIL_NAME := "Leg_Tail"
const _LEG_HEAD_NAME := "Leg_Head"
const _LEG_CENTER_NAME := "Leg_Center"
const _LEG_MIDDLE_PREFIX := "Leg_Middle_"

func _request_legs_recheck() -> void:
	_rebuild_legs()


func _rebuild_legs() -> void:
	if not is_inside_tree():
		return
	var keep: Dictionary = {}
	if not legs_enabled or leg_model_scene == null:
		_remove_orphan_legs(keep)
		return
	var avg_r: float = _avg_radius()
	var specs: Array = _compute_curved_leg_specs(avg_r, conveyor_angle)
	if specs.is_empty():
		_remove_orphan_legs(keep)
		return
	var node_xform: Transform3D = global_transform
	var legs_normal_world: Vector3 = floor_plane.normal.normalized()
	if legs_normal_world.length_squared() < 1.0e-6:
		_remove_orphan_legs(keep)
		return
	var leg_z_scale: float = maxf(0.1, width * 0.5)
	for spec: Dictionary in specs:
		var leg_name: String = spec["name"]
		var angle_deg: float = spec["angle_deg"]
		var angle_rad: float = deg_to_rad(angle_deg)
		var belt_bottom_local: Vector3 = Vector3(-sin(angle_rad) * avg_r, -height, cos(angle_rad) * avg_r)
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
		leg.rotation = Vector3(0.0, -angle_rad, 0.0)
		leg.scale = Vector3(1.0, leg_height, leg_z_scale)
		keep[leg_name] = true
	_remove_orphan_legs(keep)


func _compute_curved_leg_specs(avg_r: float, conveyor_angle_deg: float) -> Array:
	var specs: Array = []
	var tail_off_deg: float = rad_to_deg(maxf(0.0, tail_end_attachment_offset) / avg_r) if tail_end_leg_enabled else 0.0
	var head_off_deg: float = rad_to_deg(maxf(0.0, head_end_attachment_offset) / avg_r) if head_end_leg_enabled else 0.0
	var coverage_min: float = tail_off_deg
	var coverage_max: float = conveyor_angle_deg - head_off_deg
	if tail_end_leg_enabled and coverage_min <= conveyor_angle_deg and not _is_angle_excluded_deg(coverage_min, avg_r):
		specs.append({"name": _LEG_TAIL_NAME, "angle_deg": coverage_min})
	if middle_legs_enabled and middle_legs_spacing > 0.0:
		var spacing_deg: float = rad_to_deg(middle_legs_spacing / avg_r)
		var tail_clear_deg: float = rad_to_deg(maxf(0.0, tail_end_leg_clearance) / avg_r) if tail_end_leg_enabled else 0.0
		var head_clear_deg: float = rad_to_deg(maxf(0.0, head_end_leg_clearance) / avg_r) if head_end_leg_enabled else 0.0
		var first: float = ceili((coverage_min + tail_clear_deg) / spacing_deg) * spacing_deg
		var last: float = floori((coverage_max - head_clear_deg) / spacing_deg) * spacing_deg
		var idx: int = 1
		var pos: float = first
		while pos <= last + 1.0e-6:
			if pos >= 0.0 and pos <= conveyor_angle_deg and not _is_angle_excluded_deg(pos, avg_r):
				specs.append({"name": "%s%d" % [_LEG_MIDDLE_PREFIX, idx], "angle_deg": pos})
				idx += 1
			pos += spacing_deg
	elif avg_r * deg_to_rad(conveyor_angle_deg) > middle_legs_spacing:
		var center: float = conveyor_angle_deg * 0.5
		if not _is_angle_excluded_deg(center, avg_r):
			specs.append({"name": _LEG_CENTER_NAME, "angle_deg": center})
	if head_end_leg_enabled and coverage_max >= 0.0 and coverage_max <= conveyor_angle_deg \
			and not _is_angle_excluded_deg(coverage_max, avg_r):
		specs.append({"name": _LEG_HEAD_NAME, "angle_deg": coverage_max})
	return specs


func _is_angle_excluded_deg(angle_deg: float, avg_r: float) -> bool:
	if exclusion_start == 0.0 and exclusion_end == 0.0:
		return false
	var start_deg: float = rad_to_deg(exclusion_start / avg_r)
	var end_deg: float = rad_to_deg(exclusion_end / avg_r)
	return angle_deg >= start_deg and angle_deg <= end_deg


func _remove_orphan_legs(keep: Dictionary) -> void:
	for child in get_children(true):
		var n: String = String(child.name)
		if not n.begins_with("Leg_"):
			continue
		if keep.has(n):
			continue
		remove_child(child)
		child.queue_free()


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


func _on_simulation_started() -> void:
	running = true
	if enable_comms:
		_speed_tag.register(speed_tag_group_name, speed_tag_name, OIPComms.TAG_TYPE_FLOAT32)
		_running_tag.register(running_tag_group_name, running_tag_name, OIPComms.TAG_TYPE_BOOL)


func _on_simulation_ended() -> void:
	running = false
	if _running_tag.is_ready():
		_running_tag.write_bit(false)
	if _sb:
		_sb.constant_angular_velocity = Vector3.ZERO
	for static_body in _end_static_bodies:
		static_body.constant_linear_velocity = Vector3.ZERO
	if roller_material:
		roller_material.uv1_offset = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	_running_tag.on_group_initialized(tag_group_name_param)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return
	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()
