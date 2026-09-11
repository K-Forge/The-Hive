@tool
class_name CurvedBeltConveyor
extends ResizableNode3D

const BASE_INNER_RADIUS: float = 0.5
const BASE_CONVEYOR_WIDTH: float = 1.524
const BASE_HEIGHT: float = 0.5

const BELT_SHADER: Shader = preload("res://src/Conveyor/belt_surface_shader.gdshader")
const MESH_SCALE_FACTOR := 2.0

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
		_update_belt_material_scale()
		_update_flow_arrow()
		_sync_preview_overlay_arrow(value)

## Linear speed at [member reference_distance] in m/s.
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 2.0:
	set(value):
		if value == speed:
			return
		speed = value
		_recalculate_speeds()
		_update_belt_material_scale()
		if _running_tag.is_ready():
			_running_tag.write_bit(value != 0.0)

## Distance from outer edge where [member speed] is measured.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var reference_distance: float = BASE_CONVEYOR_WIDTH / 2.0:
	set(value):
		reference_distance = value
		_recalculate_speeds()

@export var belt_color: Color = Color.WHITE:
	set(value):
		belt_color = value
		if _belt_material:
			(_belt_material as ShaderMaterial).set_shader_parameter("ColorMix", belt_color)

@export var belt_texture: BeltConveyor.BeltTexture = BeltConveyor.BeltTexture.STANDARD:
	set(value):
		belt_texture = value
		if _belt_material:
			(_belt_material as ShaderMaterial).set_shader_parameter("use_alternate_texture", belt_texture == BeltConveyor.BeltTexture.ALTERNATE)

## Physics material applied to the conveyor bodies.
@export var physics_material: PhysicsMaterial = preload("res://parts/BeltSurfaceMaterial.tres"):
	set(value):
		physics_material = value
		_apply_physics_material()


func _apply_physics_material() -> void:
	if _sb:
		_sb.physics_material_override = physics_material
	if _end_body1:
		_end_body1.physics_material_override = physics_material
	if _end_body2:
		_end_body2.physics_material_override = physics_material


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


var _flow_arrow: Node3D
var _legs_state: Dictionary = {}
var _belt_material: ShaderMaterial
var _metal_material: Material
var _frame_mesh_instance: MeshInstance3D
var _belt_position: float = 0.0
var _angular_speed: float = 0.0
var _linear_speed: float = 0.0

@onready var _sb: StaticBody3D = get_node("StaticBody3D")
@onready var curved_mesh: MeshInstance3D = $MeshInstance3D
var _end_body1: StaticBody3D
var _end_body2: StaticBody3D

var _mesh_regeneration_needed: bool = true

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
	var preview_scene := load("res://parts/CurvedBeltConveyor.tscn") as PackedScene
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
		(node as CollisionShape3D).disabled = true

	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0

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

	var main_mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if main_mesh_instance and main_mesh_instance.mesh:
		main_mesh_instance.mesh = main_mesh_instance.mesh.duplicate()

	_end_body1 = get_node_or_null("EndBody1") as StaticBody3D
	if not _end_body1:
		_end_body1 = _create_end_body("EndBody1")
		add_child(_end_body1)
	_end_body2 = get_node_or_null("EndBody2") as StaticBody3D
	if not _end_body2:
		_end_body2 = _create_end_body("EndBody2")
		add_child(_end_body2)
	_apply_physics_material()

	_frame_mesh_instance = get_node_or_null("FrameMesh") as MeshInstance3D
	if not _frame_mesh_instance:
		_frame_mesh_instance = MeshInstance3D.new()
		_frame_mesh_instance.name = "FrameMesh"
		add_child(_frame_mesh_instance)

	SideGuardOpening.claim_unique(side_guard_openings, get_instance_id())
	SideGuardOpening.sync_change_listeners([], side_guard_openings, _rebuild_side_guards, true)

	_recalculate_speeds()
	_update_belt_ends()

	_mesh_regeneration_needed = true
	update_visible_meshes()
	_update_belt_material_scale()
	_update_flow_arrow()
	_update_side_guards()
	_update_assembly_components()
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


func _update_all_components() -> void:
	if not is_inside_tree():
		return

	update_visible_meshes()
	_recalculate_speeds()
	_update_side_guards()
	_update_assembly_components()
	_update_flow_arrow()
	ConveyorSnapping.notify_contacts_rebuild(self)


func _create_end_body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 0
	body.physics_material_override = physics_material
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = height / 2.0
	cylinder.height = width
	col.shape = cylinder
	col.rotation.x = PI / 2.0
	body.add_child(col)
	return body


func _update_belt_ends() -> void:
	if not _end_body1 or not _end_body2:
		return

	var radians := deg_to_rad(conveyor_angle)
	var avg_radius := inner_radius + width / 2.0
	var roller_radius := height / 2.0

	_end_body1.position = Vector3(-sin(radians) * avg_radius, -size.y / 2.0, cos(radians) * avg_radius)
	_end_body1.rotation.y = -radians
	_end_body2.position = Vector3(0, -size.y / 2.0, avg_radius)
	_end_body2.rotation.y = 0

	for body: StaticBody3D in [_end_body1, _end_body2]:
		var col := body.get_node("CollisionShape3D") as CollisionShape3D
		if col and col.shape is CylinderShape3D:
			var cyl := col.shape as CylinderShape3D
			cyl.radius = roller_radius
			cyl.height = width


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


func _natural_arc_total() -> float:
	return _avg_radius() * deg_to_rad(conveyor_angle) + 2.0 * (height * 0.5)


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
	var conveyor_angle_deg: float = conveyor_angle
	var specs: Array = _compute_curved_leg_specs(avg_r, conveyor_angle_deg)
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
		var belt_bottom_local := Vector3(-sin(angle_rad) * avg_r, -height, cos(angle_rad) * avg_r)
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


func update_visible_meshes() -> void:
	if not is_inside_tree():
		return

	if _mesh_regeneration_needed:
		_create_conveyor_mesh()
		_setup_collision_shape()
		_mesh_regeneration_needed = false


func _create_conveyor_mesh() -> void:
	var angle_radians: float = deg_to_rad(conveyor_angle)
	var radius_inner: float = inner_radius
	var radius_outer: float = inner_radius + width

	var arc_segments := maxi(1, int(conveyor_angle / 3.0))
	const DEFAULT_HEIGHT_RATIO: float = 0.50
	var mesh_height: float = DEFAULT_HEIGHT_RATIO * height

	var belt_mesh := ArrayMesh.new()

	_setup_materials()

	_build_belt_loop(belt_mesh, angle_radians, radius_inner, radius_outer,
			mesh_height, arc_segments, MESH_SCALE_FACTOR)

	curved_mesh.mesh = belt_mesh
	curved_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var base_scale := 1.0 / MESH_SCALE_FACTOR
	curved_mesh.scale = Vector3(base_scale, 1.0, base_scale)

	if _frame_mesh_instance:
		var frame_mesh := ArrayMesh.new()
		_add_curved_frame_surface(frame_mesh, angle_radians, radius_inner, radius_outer,
				mesh_height, arc_segments, MESH_SCALE_FACTOR)
		_frame_mesh_instance.mesh = frame_mesh
		_frame_mesh_instance.scale = Vector3(base_scale, 1.0, base_scale)


static var _belt_texture_res: Texture2D = preload("res://assets/3DModels/Textures/4K-fabric_39-diffuse.jpg")
static var _belt_texture_alt: Texture2D = preload("res://assets/3DModels/Textures/ConvBox_Conv_text__arrows_1024.png")

func _setup_materials() -> void:
	if not _belt_material:
		_belt_material = ShaderMaterial.new()
		_belt_material.shader = BELT_SHADER
		_belt_material.set_shader_parameter("belt_texture", _belt_texture_res)
		_belt_material.set_shader_parameter("belt_texture_alt", _belt_texture_alt)
	_belt_material.set_shader_parameter("ColorMix", belt_color)
	_belt_material.set_shader_parameter("use_alternate_texture", belt_texture == BeltConveyor.BeltTexture.ALTERNATE)
	_update_belt_material_scale()

	if not _metal_material:
		_metal_material = ConveyorFrameMesh.create_material()

func _build_belt_loop(mesh_instance: ArrayMesh, angle_radians: float,
		r_inner: float, r_outer: float, mesh_height: float,
		arc_segments: int, sf: float) -> void:
	const ROLLER_SEGS: int = 12

	var y_radius: float = mesh_height / 2.0
	var center_y: float = -y_radius
	var fixed_roller_r: float = mesh_height / 2.0
	var tangent_r: float = fixed_roller_r * 2.0  # XZ 2x to compensate mesh scale.
	var hw: float = (r_outer - r_inner) / 2.0
	var avg_r: float = (r_inner + r_outer) / 2.0

	var belt_arc: float = avg_r * angle_radians
	var roller_arc: float = y_radius * PI
	var total_belt: float = roller_arc + belt_arc + roller_arc + belt_arc

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var dist: float = 0.0

	var _add_row := func(pos_inner: Vector3, pos_outer: Vector3, normal: Vector3, belt_dist: float) -> void:
		var u: float = belt_dist / total_belt
		verts.append(pos_inner)
		norms.append(normal)
		uvs.append(Vector2(u, 1))
		verts.append(pos_outer)
		norms.append(normal)
		uvs.append(Vector2(u, 0))

	var start_tangent := Vector3(-1, 0, 0)
	var start_radial := Vector3(0, 0, 1)
	var start_center_xz := Vector3(0, 0, avg_r)
	for i in range(ROLLER_SEGS + 1):
		var t: float = float(i) / ROLLER_SEGS
		var cyl_angle: float = PI * (1.0 - t)
		var y_off: float = center_y + cos(cyl_angle) * y_radius
		var tang_off: float = -sin(cyl_angle) * tangent_r
		var xz_ps: Vector3 = start_center_xz + start_tangent * tang_off
		var norm := (start_tangent * (-sin(cyl_angle)) + Vector3(0, cos(cyl_angle), 0)).normalized()
		var inner_xz: Vector3 = (xz_ps - start_radial * hw) * sf
		var outer_xz: Vector3 = (xz_ps + start_radial * hw) * sf
		_add_row.call(
			Vector3(inner_xz.x, y_off * sf, inner_xz.z),
			Vector3(outer_xz.x, y_off * sf, outer_xz.z),
			norm, dist + t * roller_arc)
	dist += roller_arc

	for ai in range(arc_segments + 1):
		var arc_t: float = float(ai) / arc_segments
		var angle: float = arc_t * angle_radians
		var sin_a: float = sin(angle)
		var cos_a: float = cos(angle)
		var inner_pos := Vector3(-sin_a * r_inner, 0.0, cos_a * r_inner) * sf
		var outer_pos := Vector3(-sin_a * r_outer, 0.0, cos_a * r_outer) * sf
		_add_row.call(inner_pos, outer_pos, Vector3.UP, dist + arc_t * belt_arc)
	dist += belt_arc

	var end_sin: float = sin(angle_radians)
	var end_cos: float = cos(angle_radians)
	var end_tangent := Vector3(-end_cos, 0, -end_sin)
	var end_radial := Vector3(-end_sin, 0, end_cos)
	var end_center_xz := Vector3(-end_sin * avg_r, 0, end_cos * avg_r)
	for i in range(ROLLER_SEGS + 1):
		var t: float = float(i) / ROLLER_SEGS
		var cyl_angle: float = PI * t
		var y_off: float = center_y + cos(cyl_angle) * y_radius
		var tang_off: float = sin(cyl_angle) * tangent_r
		var xz_ps: Vector3 = end_center_xz + end_tangent * tang_off
		var norm := (end_tangent * sin(cyl_angle) + Vector3(0, cos(cyl_angle), 0)).normalized()
		var inner_xz: Vector3 = (xz_ps - end_radial * hw) * sf
		var outer_xz: Vector3 = (xz_ps + end_radial * hw) * sf
		_add_row.call(
			Vector3(inner_xz.x, y_off * sf, inner_xz.z),
			Vector3(outer_xz.x, y_off * sf, outer_xz.z),
			norm, dist + t * roller_arc)
	dist += roller_arc

	var y_bottom: float = -mesh_height * sf
	for ai in range(arc_segments + 1):
		var arc_t: float = float(ai) / arc_segments
		var angle: float = (1.0 - arc_t) * angle_radians
		var sin_a: float = sin(angle)
		var cos_a: float = cos(angle)
		var inner_pos := Vector3(-sin_a * r_inner * sf, y_bottom, cos_a * r_inner * sf)
		var outer_pos := Vector3(-sin_a * r_outer * sf, y_bottom, cos_a * r_outer * sf)
		_add_row.call(inner_pos, outer_pos, Vector3.DOWN, dist + arc_t * belt_arc)
	dist += belt_arc

	var row_count: int = floori(verts.size() / 2.0)
	for i in range(row_count - 1):
		var idx: int = i * 2
		_add_triangle(indices, idx, idx + 2, idx + 1)
		_add_triangle(indices, idx + 1, idx + 2, idx + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh_instance.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.surface_set_material(mesh_instance.get_surface_count() - 1, _belt_material)


func _add_curved_frame_surface(mesh_instance: ArrayMesh, angle_radians: float,
		r_inner: float, r_outer: float, mesh_height: float, segments: int, sf: float) -> void:
	var y_top: float = 0.0
	var y_bottom: float = -mesh_height * sf

	var frame_mesh := ConveyorFrameMesh.create_curved(
			r_inner, r_outer, y_top, y_bottom, angle_radians, segments, sf, true)
	frame_mesh.surface_set_material(0, _metal_material)

	for s: int in range(frame_mesh.get_surface_count()):
		mesh_instance.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, frame_mesh.surface_get_arrays(s))
		mesh_instance.surface_set_material(mesh_instance.get_surface_count() - 1, frame_mesh.surface_get_material(s))

	var fixed_roller_r: float = mesh_height / 2.0
	var tangent_r: float = fixed_roller_r * 2.0
	ConveyorFrameMesh.add_curved_end_walls(mesh_instance,
			r_inner, r_outer, y_top, y_bottom, angle_radians,
			tangent_r, sf, _metal_material)


static func _add_triangle(array_indices: PackedInt32Array, a: int, b: int, c: int) -> void:
	array_indices.append_array([a, b, c])


func _setup_collision_shape() -> void:
	var collision_shape: CollisionShape3D = $StaticBody3D.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert(collision_shape != null, "CollisionShape3D node is missing!")

	var all_verts: PackedVector3Array = PackedVector3Array()
	var all_indices: PackedInt32Array = PackedInt32Array()

	var mesh_instance := curved_mesh.mesh
	for surface_idx in range(mesh_instance.get_surface_count()):
		var surface := mesh_instance.surface_get_arrays(surface_idx)
		var base_index := all_verts.size()
		var surface_verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		all_verts.append_array(surface_verts)

		for i: int in surface[Mesh.ARRAY_INDEX]:
			all_indices.append(base_index + i)

	var triangle_verts: PackedVector3Array = PackedVector3Array()
	for i in range(0, all_indices.size(), 3):
		if i + 2 >= all_indices.size():
			break
		triangle_verts.append_array([
			all_verts[all_indices[i]],
			all_verts[all_indices[i + 1]],
			all_verts[all_indices[i + 2]]
		])

	var inv_sf := 1.0 / MESH_SCALE_FACTOR
	var scaled_verts := PackedVector3Array()
	for vert in triangle_verts:
		scaled_verts.append(Vector3(vert.x * inv_sf, vert.y, vert.z * inv_sf))

	var shape: ConcavePolygonShape3D = collision_shape.shape
	shape.backface_collision = true
	shape.data = scaled_verts
	collision_shape.position = Vector3.ZERO
	collision_shape.scale = Vector3.ONE
	_sb.position = Vector3.ZERO


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

func _recalculate_speeds() -> void:
	var direction := -1.0 if reverse else 1.0
	var effective_speed := speed * direction
	var outer_radius_val: float = inner_radius + width
	var reference_radius: float = outer_radius_val - reference_distance
	_angular_speed = 0.0 if absf(reference_radius) < 1e-6 else effective_speed / reference_radius

	var center_radius: float = (inner_radius + outer_radius_val) / 2.0
	_linear_speed = _angular_speed * center_radius

	_update_belt_ends()

func _physics_process(delta: float) -> void:
	if LegFooting.legs_state_changed(self, _legs_state):
		_rebuild_legs()
		_legs_state = LegFooting.capture_leg_state(self)
	if Simulation.is_running():
		var local_up := _sb.global_transform.basis.y.normalized()
		_sb.constant_angular_velocity = -local_up * _angular_speed
		var roller_radius: float = height / 2.0
		for body: StaticBody3D in [_end_body1, _end_body2]:
			if not body:
				continue
			if _linear_speed != 0:
				var local_front: Vector3 = body.global_transform.basis.z.normalized()
				body.constant_angular_velocity = local_front * _linear_speed / roller_radius
			else:
				body.constant_angular_velocity = Vector3.ZERO
		if not Simulation.is_paused():
			_belt_position = fmod(_belt_position + _linear_speed * delta, 1.0)
		if _linear_speed != 0:
			(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", _belt_position)


func _update_belt_material_scale() -> void:
	if _belt_material:
		var avg_r: float = inner_radius + width / 2.0
		var belt_arc: float = avg_r * deg_to_rad(conveyor_angle)
		const DEFAULT_HEIGHT_RATIO: float = 0.50
		var y_radius: float = (DEFAULT_HEIGHT_RATIO * height) / 2.0
		var roller_arc: float = y_radius * PI
		var total_belt: float = roller_arc + belt_arc + roller_arc + belt_arc
		var scale_value: float = max(1.0, total_belt)
		(_belt_material as ShaderMaterial).set_shader_parameter("Scale", scale_value)


func _on_simulation_started() -> void:
	_update_belt_ends()

	if enable_comms:
		_speed_tag.register(speed_tag_group_name, speed_tag_name, OIPComms.TAG_TYPE_FLOAT32)
		_running_tag.register(running_tag_group_name, running_tag_name, OIPComms.TAG_TYPE_BOOL)


func _on_simulation_ended() -> void:
	if _running_tag.is_ready():
		_running_tag.write_bit(false)
	_belt_position = 0.0
	if _belt_material and _belt_material is ShaderMaterial:
		(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", _belt_position)

	if _sb:
		_sb.constant_angular_velocity = Vector3.ZERO
	for body: StaticBody3D in [_end_body1, _end_body2]:
		if body:
			body.constant_angular_velocity = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	_running_tag.on_group_initialized(tag_group_name_param)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return

	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()
