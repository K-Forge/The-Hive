@tool
class_name BeltConveyor
extends ResizableNode3D

## Multi-segment belt conveyor. Origin sits at the START of segment 0; +X is
## segment 0's tangent, +Z is across the belt.

const _BeltPathCollisionScript := preload("res://src/Conveyor/belt_path_collision.gd")

const _MIN_RUN_LENGTH: float = 0.01

enum BeltTexture {
	STANDARD,
	ALTERNATE,
}

enum ShapePreset {
	CUSTOM = 0,
	STRAIGHT,
	Z_FRAME,
	WALK_THRU,
	NOSE_OVER,
}

@export var shape_preset: ShapePreset = ShapePreset.STRAIGHT:
	set(value):
		var changed: bool = shape_preset != value
		shape_preset = value
		# Skip stamping during scene load so the saved segments aren't overwritten.
		if changed and is_inside_tree() and value != ShapePreset.CUSTOM:
			_apply_shape_preset(value)
		if changed:
			notify_property_list_changed()

const _DEFAULT_SEGMENT_LENGTH: float = 4.0
const _PRESET_INCLINE_DEG: float = 12.0
const _PRESET_WALK_THRU_DEG: float = 25.0
const _PRESET_NOSE_OVER_DEG: float = 8.0
const _PRESET_FLAT_LEN: float = 2.0
const _PRESET_RAMP_LEN: float = 3.0
const _PRESET_WALK_THRU_LEG_KEEP: float = 1.0

@export var segments: Array[BeltSegment] = []:
	set(value):
		_disconnect_segment_signals()
		# `value` may be a caller-owned literal — don't mutate it.
		var patched: Array[BeltSegment] = value.duplicate()
		for i in patched.size():
			if patched[i] == null:
				patched[i] = _make_default_segment()
		var prev_count: int = segments.size()
		segments = patched
		_connect_segment_signals()
		_request_rebuild()
		if prev_count != patched.size():
			notify_property_list_changed()

## Length of the only segment, when this conveyor has exactly one segment.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var length: float = _DEFAULT_SEGMENT_LENGTH:
	get:
		return segments[0].length + height if segments.size() > 0 else 0.0
	set(value):
		if segments.size() > 0:
			segments[0].length = maxf(_MIN_RUN_LENGTH, value - height)

## Incline of the only segment, in degrees, when this conveyor has exactly one segment.
@export_range(-89.0, 89.0, 0.1, "suffix:°") var incline: float = 0.0:
	get:
		return segments[0].tilt_relative_deg if segments.size() > 0 else 0.0
	set(value):
		if segments.size() > 0:
			segments[0].tilt_relative_deg = value


static func _make_default_segment() -> BeltSegment:
	return _make_segment(_DEFAULT_SEGMENT_LENGTH, 0.0)


static func _make_segment(seg_length: float, tilt_relative_deg: float) -> BeltSegment:
	var seg := BeltSegment.new()
	seg.length = seg_length
	seg.tilt_relative_deg = tilt_relative_deg
	seg.resource_local_to_scene = true
	return seg


static func _preset_template(preset: ShapePreset) -> Array:
	match preset:
		ShapePreset.STRAIGHT:
			return [[_DEFAULT_SEGMENT_LENGTH, 0.0]]
		ShapePreset.Z_FRAME:
			return [
				[_PRESET_FLAT_LEN, 0.0],
				[_PRESET_RAMP_LEN, _PRESET_INCLINE_DEG],
				[_PRESET_FLAT_LEN, -_PRESET_INCLINE_DEG],
			]
		ShapePreset.WALK_THRU:
			return [
				[_PRESET_FLAT_LEN, 0.0],
				[_PRESET_RAMP_LEN, _PRESET_WALK_THRU_DEG],
				[_PRESET_FLAT_LEN, -_PRESET_WALK_THRU_DEG],
				[_PRESET_RAMP_LEN, -_PRESET_WALK_THRU_DEG],
				[_PRESET_FLAT_LEN, _PRESET_WALK_THRU_DEG],
			]
		ShapePreset.NOSE_OVER:
			return [
				[_PRESET_FLAT_LEN, 0.0],
				[_PRESET_RAMP_LEN, -_PRESET_NOSE_OVER_DEG],
			]
		_:
			return []


func _apply_shape_preset(preset: ShapePreset) -> void:
	var template: Array = _preset_template(preset)
	if template.is_empty():
		return
	var new_segs: Array[BeltSegment] = []
	for entry: Array in template:
		var seg_len: float = entry[0]
		var seg_angle: float = entry[1]
		new_segs.append(_make_segment(seg_len, seg_angle))
	segments = new_segs
	if preset == ShapePreset.WALK_THRU:
		var total_len: float = _PRESET_FLAT_LEN * 3.0 + _PRESET_RAMP_LEN * 2.0
		exclusion_start = _PRESET_FLAT_LEN + _PRESET_WALK_THRU_LEG_KEEP
		exclusion_end = total_len - _PRESET_FLAT_LEN - _PRESET_WALK_THRU_LEG_KEEP
	else:
		exclusion_start = 0.0
		exclusion_end = 0.0


func _maybe_drift_to_custom() -> void:
	if shape_preset == ShapePreset.CUSTOM:
		return
	var template: Array = _preset_template(shape_preset)
	if template.is_empty() or segments.size() != template.size():
		shape_preset = ShapePreset.CUSTOM
		return
	for seg: BeltSegment in segments:
		if seg == null:
			shape_preset = ShapePreset.CUSTOM
			return

@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:m") var width: float = 1.524:
	set(value):
		var clamped: float = maxf(0.1, value)
		if clamped == width:
			return
		width = clamped
		_request_rebuild()

## Belt height in meters. Also sets end-pulley radius (= height / 2).
@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var height: float = 0.5:
	set(value):
		var clamped: float = maxf(0.05, value)
		if clamped == height:
			return
		height = clamped
		_request_rebuild()

## Local-space AABB including head/tail pulley wraps. Not centered on the node origin.
var local_bbox: AABB:
	get:
		var pulley_radius: float = height * 0.5
		if _path == null or _path.runs.is_empty():
			var fallback_len: float = maxf(0.5, _segments_total_length())
			return AABB(
					Vector3(-pulley_radius, -height, -width * 0.5),
					Vector3(fallback_len + 2.0 * pulley_radius, height, width))
		var aabb := AABB(Vector3.ZERO, Vector3.ZERO)
		var corner := Vector3.ZERO
		var tilt: float = 0.0
		for i in range(segments.size()):
			var seg: BeltSegment = segments[i]
			if seg == null:
				continue
			tilt += deg_to_rad(seg.tilt_relative_deg)
			corner += Vector3(cos(tilt), sin(tilt), 0.0) * seg.length
			aabb = aabb.expand(corner)
		# Inflate by pulley wrap along X, height down, and half-width on each side.
		var pad := Vector3(pulley_radius, 0.0, 0.0)
		aabb = aabb.expand(aabb.position - pad)
		aabb = aabb.expand(aabb.end + pad)
		return AABB(
				Vector3(aabb.position.x, aabb.position.y - height, -width * 0.5),
				Vector3(aabb.size.x, aabb.size.y + height, width))

func _get_constrained_size(_new_size: Vector3) -> Vector3:
	return local_bbox.size


func _get_editor_rotation_lock() -> int:
	return (1 << 0) | (1 << 2)


func _get_editor_gizmo_pivot_offset() -> Vector3:
	var bb := local_bbox
	return Vector3(bb.position.x + bb.size.x * 0.5, 0.0, 0.0)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array()


func _get_scale_warning_text() -> String:
	return "Use `length` / `width` / `height` / segment lengths instead of scale."


var _drag_initial_width: float = 0.0
var _drag_initial_height: float = 0.0
var _drag_initial_seg_length: float = 0.0


func _transform_requested(data: Dictionary) -> void:
	if not EditorInterface.get_selection().get_selected_nodes().has(self):
		return
	if not data.has("motion"):
		return
	var md: Array = data["motion"]
	var mx: float = md[0]
	var my: float = md[1]
	var mz: float = md[2]
	var motion := Vector3(mx, my, mz)

	if not transform_in_progress:
		_drag_initial_width = width
		_drag_initial_height = height
		var tail_seg: BeltSegment = segments[-1] if not segments.is_empty() else null
		_drag_initial_seg_length = tail_seg.length if tail_seg else 0.0
		transform_in_progress = true

	if not is_zero_approx(motion.z):
		width = maxf(0.1, _drag_initial_width + motion.z)
	if not is_zero_approx(motion.y):
		height = maxf(0.05, _drag_initial_height + motion.y)
	if not is_zero_approx(motion.x):
		var tail_seg: BeltSegment = segments[-1] if not segments.is_empty() else null
		if tail_seg:
			tail_seg.length = maxf(_MIN_RUN_LENGTH, _drag_initial_seg_length + motion.x)


func _transform_commited() -> void:
	if not transform_in_progress:
		return
	transform_in_progress = false
	var tail_seg: BeltSegment = segments[-1] if not segments.is_empty() else null
	var width_changed := absf(width - _drag_initial_width) > 1e-4
	var height_changed := absf(height - _drag_initial_height) > 1e-4
	var length_changed := tail_seg != null and absf(tail_seg.length - _drag_initial_seg_length) > 1e-4
	if not (width_changed or height_changed or length_changed):
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Resize BeltConveyor", UndoRedo.MERGE_ALL)
	if width_changed:
		undo_redo.add_do_property(self, "width", width)
		undo_redo.add_undo_property(self, "width", _drag_initial_width)
	if height_changed:
		undo_redo.add_do_property(self, "height", height)
		undo_redo.add_undo_property(self, "height", _drag_initial_height)
	if length_changed:
		undo_redo.add_do_property(tail_seg, "length", tail_seg.length)
		undo_redo.add_undo_property(tail_seg, "length", _drag_initial_seg_length)
	undo_redo.commit_action()


func _segments_total_length() -> float:
	var total: float = 0.0
	for seg: BeltSegment in segments:
		if seg:
			total += seg.length
	return total

## Belt linear speed in m/s.
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 2.0:
	set(value):
		if value == speed:
			return
		speed = value
		if _belt_material and _path:
			_belt_material.set_shader_parameter("Scale", maxf(1.0, _path.loop_length))
		if _running_tag.is_ready():
			_running_tag.write_bit(value != 0.0)

@export var belt_color: Color = Color.WHITE:
	set(value):
		belt_color = value
		if _belt_material:
			_belt_material.set_shader_parameter("ColorMix", belt_color)

@export var belt_texture: BeltTexture = BeltTexture.STANDARD:
	set(value):
		belt_texture = value
		if _belt_material:
			_belt_material.set_shader_parameter("use_alternate_texture", belt_texture == BeltTexture.ALTERNATE)

## Physics material applied to per-run bodies.
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

## Side-guard cutouts in conveyor-arc (cumulative top-surface arc from tail,
## including bend arcs). Use [method request_side_guard_opening] to add.
@export var side_guard_openings: Array[SideGuardOpening] = []:
	set(value):
		SideGuardOpening.sync_change_listeners(side_guard_openings, value, _request_rebuild, false, _guard_arc_bounds())
		side_guard_openings = value
		_request_rebuild()

@export_group("Legs")
@export var legs_enabled: bool = true:
	set(value):
		if value == legs_enabled:
			return
		legs_enabled = value
		_request_rebuild()

## World-space plane the legs reach down to. Independent of the conveyor's transform.
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
@export var head_end_leg_enabled: bool = true:
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
@export var middle_legs_enabled: bool = true:
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
## Arc-length range from tail; legs inside are skipped. Both 0 disables.
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
## The tag name for the speed value in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var speed_tag_name: String = ""
@export var running_tag_group_name: String
@export_custom(0, "tag_group_enum") var running_tag_groups: String:
	set(value):
		running_tag_group_name = value
		running_tag_groups = value
## The tag name for the running state in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var running_tag_name: String = ""

var _path: BeltPath
var _mesh_instance: MeshInstance3D
var _bodies: Array[StaticBody3D] = []
var _frame_rail_meshes: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _legs_state: Dictionary = {}
var _side_guards: Array[SideGuard] = []
var _bend_side_guard_meshes: Array[MeshInstance3D] = []
var _derived_side_guard_openings: Array[SideGuardOpening] = []
var _flow_arrow: Node3D
var _belt_material: ShaderMaterial
var _belt_position: float = 0.0
var _rebuild_pending: bool = false
var _connection_rebuild_pending: bool = false
var _legs_refresh_pending: bool = false
var _speed_tag := OIPCommsTag.new()
var _running_tag := OIPCommsTag.new()


func _validate_property(property: Dictionary) -> void:
	if OIPCommsSetup.validate_tag_property(property, "speed_tag_group_name", "speed_tag_groups", "speed_tag_name"):
		return
	if OIPCommsSetup.validate_tag_property(property, "running_tag_group_name", "running_tag_groups", "running_tag_name"):
		return
	if property.name == "length" or property.name == "incline":
		property.usage = PROPERTY_USAGE_EDITOR if shape_preset == ShapePreset.STRAIGHT else PROPERTY_USAGE_NONE
	elif property.name == "segments":
		property.usage = PROPERTY_USAGE_DEFAULT if shape_preset != ShapePreset.STRAIGHT else PROPERTY_USAGE_STORAGE
	elif property.name == "size":
		property.usage = PROPERTY_USAGE_STORAGE


func get_snap_features() -> Array:
	# Drop-from-FileSystem invokes _snap_transform before _ready; lazy-build.
	if _path == null:
		_path = BeltPath.build(segments, 0.0, 0.0, 0.0, height)
	if _path == null or _path.runs.is_empty():
		return []
	var features: Array = []
	var start_xf: Transform3D = _path.start_transform()
	var end_xf: Transform3D = _path.end_transform()
	# Push end features out to the pulley-wrap outer edge so snapped neighbors don't overlap.
	var pulley_radius: float = height * 0.5
	features.append({
		"shape": ConveyorSnapFeatures.Shape.POINT,
		"kind": &"straight_end_back",
		"local_pos": start_xf.origin - start_xf.basis.x * pulley_radius,
		"local_outward": -start_xf.basis.x,
		"end_name": &"back",
	})
	features.append({
		"shape": ConveyorSnapFeatures.Shape.POINT,
		"kind": &"straight_end_front",
		"local_pos": end_xf.origin + end_xf.basis.x * pulley_radius,
		"local_outward": end_xf.basis.x,
		"end_name": &"front",
	})
	var half_w: float = width * 0.5
	var first_start_x: float = _path.runs[0].start_xform.origin.x
	var last_run: BeltPath.Run = _path.runs[_path.runs.size() - 1]
	var x_end: float = (last_run.start_xform * Vector3(maxf(0.0, last_run.effective_length), 0, 0)).x
	features.append({
		"shape": ConveyorSnapFeatures.Shape.SEGMENT,
		"kind": &"straight_sideguard_left",
		"seg_start": Vector3(first_start_x, 0.0, -half_w),
		"seg_end": Vector3(x_end, 0.0, -half_w),
		"seg_outward_local": Vector3(0, 0, -1),
	})
	features.append({
		"shape": ConveyorSnapFeatures.Shape.SEGMENT,
		"kind": &"straight_sideguard_right",
		"seg_start": Vector3(first_start_x, 0.0, half_w),
		"seg_end": Vector3(x_end, 0.0, half_w),
		"seg_outward_local": Vector3(0, 0, 1),
	})
	return features


func snap_surface_y(local_x: float) -> float:
	if _path == null:
		_path = BeltPath.build(segments, 0.0, 0.0, 0.0, height)
	if _path == null or _path.runs.is_empty():
		return 0.0
	var pts: Array[Vector2] = []
	for run: BeltPath.Run in _path.runs:
		var run_len: float = maxf(0.0, run.effective_length)
		if run_len <= 0.0:
			continue
		var s: Vector3 = run.start_xform.origin
		var e: Vector3 = run.start_xform * Vector3(run_len, 0, 0)
		pts.append(Vector2(s.x, s.y))
		pts.append(Vector2(e.x, e.y))
	if pts.is_empty():
		return 0.0
	if local_x <= pts[0].x:
		return pts[0].y
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if local_x >= a.x and local_x <= b.x:
			var t: float = 0.0 if is_equal_approx(b.x, a.x) else (local_x - a.x) / (b.x - a.x)
			return a.y + t * (b.y - a.y)
	return pts[pts.size() - 1].y


# Drag-from-FileSystem preview. GEN_EDIT_STATE_INSTANCE reuses a holder whose
# transform carries over from the previous drop — DISABLED avoids that.
func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/BeltConveyor.tscn") as PackedScene
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
	# `true` includes INTERNAL_MODE_FRONT children (RunBody_*, legs, etc.).
	for child in node.get_children(true):
		_disable_collisions_recursive(child)


# Editor drop hook (Godot fork): adopt the surface as the leg floor plane.
func _collision_repositioned(collision_point: Vector3, collision_normal: Vector3) -> void:
	if collision_normal == Vector3.ZERO:
		return
	var new_plane: Plane = Plane(collision_normal, collision_point)
	if floor_plane.is_equal_approx(new_plane):
		return
	floor_plane = new_plane


# Save/restore pair for the editor's surface-align undo path.
func _collision_repositioned_save() -> Variant:
	return floor_plane


func _collision_repositioned_undo(saved: Variant) -> void:
	if saved is Plane:
		floor_plane = saved


func _init() -> void:
	super._init()
	if segments.is_empty():
		segments = [_make_default_segment()]
	size = local_bbox.size


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_request_legs_refresh()
		_request_connection_rebuild()
		ConveyorSnapping.notify_contacts_rebuild(self)


func _request_legs_refresh() -> void:
	if _legs_refresh_pending or not is_inside_tree() or _path == null:
		return
	_legs_refresh_pending = true
	call_deferred("_refresh_legs_for_transform")


func _refresh_legs_for_transform() -> void:
	_legs_refresh_pending = false
	if not is_inside_tree():
		return
	_reposition_existing_legs()


func _enter_tree() -> void:
	super._enter_tree()
	speed_tag_group_name = OIPCommsSetup.default_tag_group(speed_tag_group_name)
	running_tag_group_name = OIPCommsSetup.default_tag_group(running_tag_group_name)
	if not Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.connect(_on_simulation_started)
	if not Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)
	ConveyorSnapping.notify_contacts_rebuild(self)


# Children matching these names/prefixes are auto-managed; others are left alone.
const _AUTO_CHILD_NAMES: PackedStringArray = [
	"BeltMesh", "FrameLeft", "FrameRight",
]
const _AUTO_CHILD_PREFIXES: PackedStringArray = [
	"RunBody_", "BendBody_",
	"SideGuardLeft_", "SideGuardRight_",
	"BendSideGuardLeft_", "BendSideGuardRight_",
	"Leg_",
]


func _ready() -> void:
	_clear_stale_snap_metas()
	_reset_preview_holder_transform()
	_ensure_internal_nodes()
	_ensure_unique_segments()
	SideGuardOpening.claim_unique(side_guard_openings, get_instance_id())
	SideGuardOpening.sync_change_listeners([], side_guard_openings, _request_rebuild)
	_connect_segment_signals()
	_rebuild()
	_bind_snap_meta_now()


# The drop-preview holder is reused across drops; reset its stale transform.
func _reset_preview_holder_transform() -> void:
	if not has_meta("is_preview"):
		return
	var holder := get_parent() as Node3D
	if holder == null:
		return
	holder.transform = Transform3D.IDENTITY


# Wipe ConveyorLiveSnap metas inherited via Node.duplicate (bound to the original).
# Drop previews are skipped — their snap callable is bound by the autoload's listener.
func _clear_stale_snap_metas() -> void:
	if not Engine.is_editor_hint():
		return
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root != null and self != edited_root and not edited_root.is_ancestor_of(self):
		return  # preview path
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


# Bind snap meta synchronously so a drag started before the next _process
# tick still snaps. Drop previews already have a preview-specific binding.
func _bind_snap_meta_now() -> void:
	if not Engine.is_editor_hint() or ConveyorLiveSnap.instance == null:
		return
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root == null:
		return
	if self != edited_root and not edited_root.is_ancestor_of(self):
		return
	ConveyorLiveSnap.instance.bind_snap_meta(self)


# Deep-copy segments owned by another conveyor (handles duplicated nodes whose
# sub-resources weren't local-to-scene in older saves).
func _ensure_unique_segments() -> void:
	const META: StringName = &"_belt_conveyor_owner"
	var changed: bool = false
	for i in range(segments.size()):
		var seg: BeltSegment = segments[i]
		if seg == null:
			continue
		var owner_id: int = seg.get_meta(META, 0)
		if owner_id == 0 or owner_id == get_instance_id():
			seg.set_meta(META, get_instance_id())
			seg.resource_local_to_scene = true
		else:
			var dup := seg.duplicate(true) as BeltSegment
			dup.set_meta(META, get_instance_id())
			dup.resource_local_to_scene = true
			segments[i] = dup
			changed = true
	if changed:
		_disconnect_segment_signals()
		_connect_segment_signals()


func _exit_tree() -> void:
	ConveyorSnapping.notify_contacts_rebuild(self)
	_disconnect_segment_signals()
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)
	super._exit_tree()


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
	for body: StaticBody3D in _bodies:
		if is_instance_valid(body):
			body.constant_linear_velocity = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	_running_tag.on_group_initialized(tag_group_name_param)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return
	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()


func _request_rebuild() -> void:
	if not is_inside_tree() or _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


## Side-guards-only rebuild, skipping the belt-surface mesh regen that's too heavy per frame.
func _request_connection_rebuild() -> void:
	if _connection_rebuild_pending or not is_inside_tree():
		return
	_connection_rebuild_pending = true
	_do_connection_rebuild.call_deferred()


func _do_connection_rebuild() -> void:
	_connection_rebuild_pending = false
	if not is_inside_tree() or _path == null:
		return
	_derive_side_guard_openings()
	_rebuild_side_guards()


func _request_legs_recheck() -> void:
	_rebuild_legs()


func _rebuild() -> void:
	_rebuild_pending = false
	if not is_inside_tree():
		return
	_ensure_internal_nodes()
	# Bend radius = `height` so convex (nose-over) bends don't invert the loop.
	_path = BeltPath.build(segments, 0.0, 0.0, 0.0, height)
	_mesh_instance.mesh = BeltConveyorMesh.create_belt_from_path(_path, height, width, false, false)
	if _mesh_instance.mesh != null and (_mesh_instance.mesh as ArrayMesh).get_surface_count() > 0:
		_mesh_instance.set_surface_override_material(0, _belt_material)
	if _belt_material:
		_belt_material.set_shader_parameter("Scale", maxf(1.0, _path.loop_length))
	_rebuild_collision()
	_rebuild_frame_rails()
	_derive_side_guard_openings()
	_rebuild_side_guards()
	_rebuild_legs()
	_update_flow_arrow()
	size = local_bbox.size
	ConveyorSnapping.notify_contacts_rebuild(self)
	if Engine.is_editor_hint():
		update_gizmos()
		_maybe_drift_to_custom()


func _ensure_internal_nodes() -> void:
	if not _belt_material:
		_belt_material = BeltSurface.create_material(belt_color, belt_texture)
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = get_node_or_null("BeltMesh") as MeshInstance3D
		if not is_instance_valid(_mesh_instance):
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "BeltMesh"
			add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
			_mesh_instance.owner = self
		_mesh_instance.transform = Transform3D.IDENTITY
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


func _rebuild_collision() -> void:
	_bodies.clear()
	if _path == null:
		_remove_orphans_with_prefix(["RunBody_", "BendBody_"], PackedStringArray())
		return
	var descriptors: Array = _BeltPathCollisionScript.build(_path, height, width, _MIN_RUN_LENGTH)
	var keep: PackedStringArray = PackedStringArray()
	var phys: PhysicsMaterial = physics_material
	# Bend subdivisions share a run_index; per-joint counter gives them unique names.
	var bend_sub_counts: Dictionary = {}
	for d: _BeltPathCollisionScript.BoxDescriptor in descriptors:
		var body_name: String
		if d.run_index >= 0:
			body_name = "RunBody_%d" % d.run_index
		else:
			var ji: int = -d.run_index - 1
			var sub: int = bend_sub_counts.get(ji, 0)
			bend_sub_counts[ji] = sub + 1
			body_name = "BendBody_%d_%d" % [ji, sub]
		keep.append(body_name)
		var body := get_node_or_null(NodePath(body_name)) as StaticBody3D
		if body == null:
			body = StaticBody3D.new()
			body.name = body_name
			add_child(body, false, Node.INTERNAL_MODE_FRONT)
			body.owner = self
		body.transform = d.local_xform
		body.physics_material_override = phys
		var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs == null:
			cs = CollisionShape3D.new()
			cs.name = "CollisionShape3D"
			body.add_child(cs)
			cs.owner = self
		# Fresh shape: the packed-scene shape is resource-cached across instances.
		if d.convex_points.is_empty():
			var box_shape := BoxShape3D.new()
			box_shape.size = d.size
			cs.shape = box_shape
		else:
			var convex_shape := ConvexPolygonShape3D.new()
			convex_shape.points = d.convex_points
			cs.shape = convex_shape
		_bodies.append(body)
	_remove_orphans_with_prefix(["RunBody_", "BendBody_"], keep)


func _rebuild_frame_rails() -> void:
	_frame_rail_meshes.clear()
	if not frame_rails_enabled or _path == null or _path.runs.is_empty():
		_remove_named_if_present(["FrameLeft", "FrameRight"])
		return
	var pulley_radius: float = height * 0.5
	_reconcile_path_frame_rail("FrameLeft", -1.0, pulley_radius, pulley_radius)
	_reconcile_path_frame_rail("FrameRight", 1.0, pulley_radius, pulley_radius)


func _reconcile_path_frame_rail(rail_name: String, side_sign: float,
		head_overhang: float, tail_overhang: float) -> void:
	var mesh: ArrayMesh = ConveyorFrameMesh.create_along_path(
			_path, height, width, side_sign, head_overhang, tail_overhang, true)
	if mesh == null or mesh.get_surface_count() == 0:
		_remove_named_if_present([rail_name])
		return
	var mi := get_node_or_null(NodePath(rail_name)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = rail_name
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		mi.owner = self
	mi.mesh = mesh
	mi.set_surface_override_material(0, ConveyorFrameMesh.create_material())
	_frame_rail_meshes.append(mi)


## Add a side-guard opening. [param side] is "left" (-Z) or "right" (+Z).
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


func _path_or_build() -> BeltPath:
	if _path == null:
		_path = BeltPath.build(segments, 0.0, 0.0, 0.0, height)
	return _path


## Total top-surface arc length including bend (joint) arcs.
func total_arc_length() -> float:
	var p: BeltPath = _path_or_build()
	var top: float = p.top_surface_length if p != null else _segments_total_length()
	return top + height


## Arc bounds for side guards / openings, including pulley wraps.
func arc_bounds() -> Vector2:
	var pulley_radius: float = height * 0.5
	var p: BeltPath = _path_or_build()
	if p == null:
		return Vector2(-pulley_radius, _segments_total_length() + pulley_radius)
	return p.arc_bounds(pulley_radius)


## Guard-relative span (0 == guard start) for a new manual opening's default.
func _guard_arc_bounds() -> Vector2:
	var b: Vector2 = arc_bounds()
	return Vector2(0.0, b.y - b.x)


## Conveyor-local point → arc-length at the closest path point.
func local_to_arc_length(local_pos: Vector3) -> float:
	var info: Dictionary = _closest_path_point(local_pos)
	if info.is_empty():
		return local_pos.x
	var arc_s: float = info.s
	return arc_s


## Forward tangent at the closest path point. Returns +X for empty paths.
func tangent_at_local_pos(local_pos: Vector3) -> Vector3:
	var info: Dictionary = _closest_path_point(local_pos)
	if info.is_empty():
		return Vector3.RIGHT
	var tangent: Vector3 = info.tangent
	return tangent


func _closest_path_point(local_pos: Vector3) -> Dictionary:
	var p: BeltPath = _path_or_build()
	if p == null or p.runs.is_empty():
		return {}
	return p.closest_path_point(local_pos, height * 0.5)


func _openings_for_side(side: String) -> Array[Vector2]:
	# Manual openings are guard-relative (arc 0 == guard start); the guard wraps the
	# end pulley, so that start sits at conveyor-arc arc_bounds().x.
	return SideGuardOpening.merge_openings_for_side(side, side_guard_openings, arc_bounds().x, _derived_side_guard_openings)


func _derive_side_guard_openings() -> void:
	_derived_side_guard_openings = ConveyorSnapping.derive_openings_by_geometry(self)


func _rebuild_side_guards() -> void:
	_side_guards.clear()
	_bend_side_guard_meshes.clear()
	var keep: PackedStringArray = PackedStringArray()
	if _path == null or _path.runs.is_empty() or not (left_side_guards_enabled or right_side_guards_enabled):
		_remove_orphans_with_prefix(["SideGuardLeft_", "SideGuardRight_",
				"BendSideGuardLeft_", "BendSideGuardRight_"], keep)
		return
	# All arc values below are in conveyor-arc (cumulative top-surface arc from tail).
	var wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var ft: float = ConveyorFrameMesh.FLANGE_THICKNESS
	var half_w: float = width * 0.5
	var pulley_radius: float = height * 0.5
	var last_index: int = _path.runs.size() - 1
	var left_openings: Array[Vector2] = _openings_for_side("left")
	var right_openings: Array[Vector2] = _openings_for_side("right")
	for i in range(_path.runs.size()):
		var run: BeltPath.Run = _path.runs[i]
		if run.effective_length <= _MIN_RUN_LENGTH:
			continue
		# First/last runs extend by pulley_radius to wrap over the end pulleys.
		var ext_back: float = pulley_radius if i == 0 else 0.0
		var ext_front: float = pulley_radius if i == last_index else 0.0
		var run_arc_back: float = run.s_at_run_start - ext_back
		var run_arc_front: float = run.s_at_run_start + run.effective_length + ext_front
		var run_basis: Basis = run.start_xform.basis
		var ft_axis: Vector3 = run_basis.y * ft
		var z_axis: Vector3 = run_basis.z
		# Right guard: flip 180° around Y so the outward face points +Z.
		var right_basis: Basis = run_basis * Basis(Vector3(0, 1, 0), PI)
		if left_side_guards_enabled:
			var subs: Array[Vector2] = _subdivide_arc_range_around_openings(
					run_arc_back, run_arc_front, left_openings)
			for k in range(subs.size()):
				var sub: Vector2 = subs[k]
				var n: String = "SideGuardLeft_%d_%d" % [i, k]
				keep.append(n)
				_emit_run_guard(n, sub.x, sub.y, run, run_basis,
						run_basis, ft_axis, z_axis * (-half_w - wt))
		if right_side_guards_enabled:
			var subs: Array[Vector2] = _subdivide_arc_range_around_openings(
					run_arc_back, run_arc_front, right_openings)
			for k in range(subs.size()):
				var sub: Vector2 = subs[k]
				var n: String = "SideGuardRight_%d_%d" % [i, k]
				keep.append(n)
				_emit_run_guard(n, sub.x, sub.y, run, run_basis,
						right_basis, ft_axis, z_axis * (half_w + wt))
	# Bend mesh is a single curved span — hide the whole bend on any opening overlap.
	for j in range(_path.joints.size()):
		var jt: BeltPath.Joint = _path.joints[j]
		var arc_start: float = jt.s_at_arc_start
		var arc_end: float = arc_start + jt.arc_length
		if left_side_guards_enabled and not _arc_overlaps_any_opening(arc_start, arc_end, left_openings):
			var n: String = "BendSideGuardLeft_%d" % j
			keep.append(n)
			_reconcile_bend_side_guard(n, jt, -1.0, half_w)
		if right_side_guards_enabled and not _arc_overlaps_any_opening(arc_start, arc_end, right_openings):
			var n: String = "BendSideGuardRight_%d" % j
			keep.append(n)
			_reconcile_bend_side_guard(n, jt, 1.0, half_w)
	_remove_orphans_with_prefix(["SideGuardLeft_", "SideGuardRight_",
			"BendSideGuardLeft_", "BendSideGuardRight_"], keep)


func _arc_overlaps_any_opening(arc_start: float, arc_end: float, merged_openings: Array[Vector2]) -> bool:
	for opening: Vector2 in merged_openings:
		if opening.x < arc_end - 0.001 and opening.y > arc_start + 0.001:
			return true
	return false


func _subdivide_arc_range_around_openings(arc_back: float, arc_front: float,
		merged_openings: Array[Vector2]) -> Array[Vector2]:
	var subs: Array[Vector2] = [Vector2(arc_back, arc_front)]
	for opening: Vector2 in merged_openings:
		var op_back: float = opening.x
		var op_front: float = opening.y
		var next_subs: Array[Vector2] = []
		for sub: Vector2 in subs:
			if op_front <= sub.x or op_back >= sub.y:
				next_subs.append(sub)
				continue
			if op_back > sub.x:
				next_subs.append(Vector2(sub.x, op_back))
			if op_front < sub.y:
				next_subs.append(Vector2(op_front, sub.y))
		subs = next_subs
	var out: Array[Vector2] = []
	for sub: Vector2 in subs:
		if sub.y - sub.x > _MIN_RUN_LENGTH:
			out.append(sub)
	return out


func _emit_run_guard(guard_name: String, arc_back: float, arc_front: float,
		run: BeltPath.Run, _run_basis: Basis, guard_basis: Basis,
		flange_offset: Vector3, lateral_offset: Vector3) -> void:
	var arc_mid: float = (arc_back + arc_front) * 0.5
	var sub_len: float = arc_front - arc_back
	# Run-local t may be negative or past effective_length for first/last pulley wraps.
	var t_mid: float = arc_mid - run.s_at_run_start
	var midpoint: Vector3 = run.start_xform * Vector3(t_mid, 0.0, 0.0)
	var origin: Vector3 = midpoint + flange_offset + lateral_offset
	_reconcile_side_guard(guard_name, sub_len, guard_basis, origin)
	var sg := get_node_or_null(NodePath(guard_name)) as SideGuard
	if sg != null:
		sg.arc_back = arc_back
		sg.arc_front = arc_front


func _reconcile_side_guard(guard_name: String, length_m: float, guard_basis: Basis, origin: Vector3) -> void:
	var sg := get_node_or_null(NodePath(guard_name)) as SideGuard
	if sg == null:
		sg = SideGuard.new()
		sg.name = guard_name
		add_child(sg, false, Node.INTERNAL_MODE_FRONT)
		sg.owner = self
	sg.length = length_m
	sg.transform = Transform3D(guard_basis, origin)
	_side_guards.append(sg)


func _reconcile_bend_side_guard(guard_name: String, joint: BeltPath.Joint,
		side_sign: float, half_w: float) -> void:
	var mesh: ArrayMesh = SideGuardMesh.create_bend(joint, side_sign, half_w)
	if mesh == null or mesh.get_surface_count() == 0:
		_remove_named_if_present([guard_name])
		return
	var mi := get_node_or_null(NodePath(guard_name)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = guard_name
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		mi.owner = self
	mi.mesh = mesh
	mi.set_surface_override_material(0, SideGuardMesh.create_material())
	_bend_side_guard_collision(mi, joint, side_sign, half_w)
	_bend_side_guard_meshes.append(mi)


# Thicker collision shape under the bend mesh so boxes don't tunnel through.
func _bend_side_guard_collision(mi: MeshInstance3D, joint: BeltPath.Joint,
		side_sign: float, half_w: float) -> void:
	var body := mi.get_node_or_null("StaticBody3D") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "StaticBody3D"
		# See SideGuard._update_collision_shape for why these are set.
		body.disable_mode = StaticBody3D.DISABLE_MODE_MAKE_STATIC
		body.collision_mask = 8
		body.ghost_collision_filtering_enabled = true
		var phys := PhysicsMaterial.new()
		phys.friction = 0.0
		body.physics_material_override = phys
		mi.add_child(body, false, Node.INTERNAL_MODE_FRONT)
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		body.add_child(cs)
	var collision_mesh := SideGuardMesh.create_bend(joint, side_sign, half_w, 8, SideGuardMesh.COLLISION_THICKNESS)
	if collision_mesh == null or collision_mesh.get_surface_count() == 0:
		cs.shape = null
		return
	var shape := ConcavePolygonShape3D.new()
	shape.data = collision_mesh.get_faces()
	cs.shape = shape


const _LEG_TAIL_NAME := "Leg_Tail"
const _LEG_HEAD_NAME := "Leg_Head"
const _LEG_MIDDLE_PREFIX := "Leg_Middle_"


const _ARROW_LIFT: float = 0.2
const _ARROW_HEAD_HEIGHT: float = 0.25
const _ARROW_HEAD_RADIUS: float = 0.15
const _ARROW_SHAFT_RADIUS: float = 0.05
const _ARROW_PATH_INSET_FRACTION: float = 0.2
const _ARROW_ARC_SAMPLE_STEP: float = 0.2


func _update_flow_arrow() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
		_flow_arrow.queue_free()
		_flow_arrow = null
	var path_length: float = _path.top_surface_length if _path != null else 0.0
	if path_length <= 0.0:
		return
	var inset: float = path_length * _ARROW_PATH_INSET_FRACTION
	var start_s: float = inset
	var end_s: float = path_length - inset
	var shaft_end_s: float = maxf(start_s, end_s - _ARROW_HEAD_HEIGHT)
	if shaft_end_s - start_s < 0.05:
		return
	var samples: Array[Transform3D] = _sample_path_for_flow_arrow(start_s, shaft_end_s)
	if samples.size() < 2:
		return

	var arrow := Node3D.new()
	arrow.name = "FlowDirectionArrow"
	var mat: StandardMaterial3D = _build_flow_arrow_material()
	for i in range(samples.size() - 1):
		_emit_flow_arrow_shaft(arrow, samples[i], samples[i + 1], mat)
	_emit_flow_arrow_head(arrow, _path.sample(end_s), mat)

	add_child(arrow, false, Node.INTERNAL_MODE_FRONT)
	_flow_arrow = arrow
	FlowDirectionArrow.register(_flow_arrow)
	# Drop previews are hosted outside the edited scene root and should always
	# show the arrow regardless of the global visibility toggle.
	if has_meta("is_preview"):
		_flow_arrow.visible = true


func _sample_path_for_flow_arrow(start_s: float, end_s: float) -> Array[Transform3D]:
	var samples: Array[Transform3D] = []
	if _path == null or _path.runs.is_empty():
		return samples
	var breakpoints: Array[float] = [start_s]
	for i in range(_path.runs.size()):
		var run: BeltPath.Run = _path.runs[i]
		var run_end: float = run.s_at_run_start + maxf(0.0, run.effective_length)
		if run_end > start_s + 0.001 and run_end < end_s - 0.001:
			breakpoints.append(run_end)
	for j in range(_path.joints.size()):
		var jt: BeltPath.Joint = _path.joints[j]
		var arc_s0: float = jt.s_at_arc_start
		var arc_s1: float = arc_s0 + jt.arc_length
		var win_start: float = maxf(arc_s0, start_s)
		var win_end: float = minf(arc_s1, end_s)
		if win_end - win_start < 0.001:
			continue
		var n: int = maxi(2, int(ceilf((win_end - win_start) / _ARROW_ARC_SAMPLE_STEP)))
		for k in range(1, n):
			breakpoints.append(lerpf(win_start, win_end, float(k) / float(n)))
		if win_end < end_s - 0.001:
			breakpoints.append(win_end)
	breakpoints.append(end_s)
	breakpoints.sort()
	var last_s: float = -INF
	for s: float in breakpoints:
		if s - last_s < 0.001:
			continue
		last_s = s
		samples.append(_path.sample(s))
	return samples


static func _build_flow_arrow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat


static func _emit_flow_arrow_shaft(parent: Node3D, a: Transform3D, b: Transform3D, mat: StandardMaterial3D) -> void:
	var from_p: Vector3 = a.origin + a.basis.y * _ARROW_LIFT
	var to_p: Vector3 = b.origin + b.basis.y * _ARROW_LIFT
	var delta: Vector3 = to_p - from_p
	var seg_length: float = delta.length()
	if seg_length < 0.01:
		return
	var dir: Vector3 = delta / seg_length
	var seg := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = _ARROW_SHAFT_RADIUS
	mesh.bottom_radius = _ARROW_SHAFT_RADIUS
	mesh.height = seg_length
	mesh.material = mat
	seg.mesh = mesh
	seg.transform = Transform3D(_basis_with_y_along(dir), (from_p + to_p) * 0.5)
	parent.add_child(seg)


static func _emit_flow_arrow_head(parent: Node3D, end_xform: Transform3D, mat: StandardMaterial3D) -> void:
	var dir: Vector3 = end_xform.basis.x.normalized()
	var tip: Vector3 = end_xform.origin + end_xform.basis.y * _ARROW_LIFT
	var center: Vector3 = tip - dir * (_ARROW_HEAD_HEIGHT * 0.5)
	var head := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = _ARROW_HEAD_RADIUS
	mesh.height = _ARROW_HEAD_HEIGHT
	mesh.material = mat
	head.mesh = mesh
	head.transform = Transform3D(_basis_with_y_along(dir), center)
	parent.add_child(head)


static func _basis_with_y_along(dir: Vector3) -> Basis:
	var ref_up := Vector3.UP
	if absf(dir.dot(ref_up)) > 0.99:
		ref_up = Vector3.FORWARD
	var right: Vector3 = dir.cross(ref_up).normalized()
	var up: Vector3 = right.cross(dir).normalized()
	return Basis(right, dir, up)


func _rebuild_legs() -> void:
	_legs.clear()
	var keep: Dictionary = {}
	if not legs_enabled or _path == null or _path.runs.is_empty() or leg_model_scene == null:
		_remove_orphan_legs(keep)
		return
	var top_len: float = _path.top_surface_length
	if top_len <= 0.0:
		_remove_orphan_legs(keep)
		return
	var specs: Array = _compute_leg_specs(top_len)
	var leg_z_scale: float = maxf(0.1, width * 0.5)
	var node_xform: Transform3D = global_transform if is_inside_tree() else Transform3D.IDENTITY
	# Project floor normal onto the belt-plane so legs stay flush on a tilted floor.
	var cross_axis_world: Vector3 = node_xform.basis.z.normalized()
	var legs_normal_world: Vector3 = floor_plane.normal.slide(cross_axis_world)
	if legs_normal_world.length_squared() < 1.0e-6:
		_remove_orphan_legs(keep)
		return
	legs_normal_world = legs_normal_world.normalized()
	for spec: Dictionary in specs:
		var leg_name: String = spec["name"]
		var s: float = spec["s"]
		var sample: Transform3D = _path.sample(s)
		var belt_bottom_local: Vector3 = sample.origin - sample.basis.y * height
		var belt_bottom_world: Vector3 = node_xform * belt_bottom_local
		var foot_v: Variant = LegFooting.resolve_foot(self, belt_bottom_world, legs_normal_world, floor_plane)
		if foot_v == null:
			continue
		var foot_world: Vector3 = foot_v
		var leg_height: float = (belt_bottom_world - foot_world).dot(legs_normal_world)
		if leg_height <= 0.05:
			continue
		var leg := get_node_or_null(NodePath(leg_name)) as Node3D
		if leg == null:
			leg = leg_model_scene.instantiate() as Node3D
			if leg == null:
				continue
			leg.name = leg_name
			# INTERNAL_MODE_FRONT keeps legs out of the editor's duplicate traversal,
			# which broke under the leg sub-scene's @tool scripts.
			add_child(leg, false, Node.INTERNAL_MODE_FRONT)
		leg.visible = true
		# Set position/scale only; reassigning global_transform triggers a leg-side
		# transform cascade before its @onready vars settle.
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


# Transform-time refresh: only position/scale/visibility, no add/remove children
# — keeps the child set stable during editor duplicates and gizmo bbox calcs.
func _reposition_existing_legs() -> void:
	if _path == null or _path.runs.is_empty():
		return
	if not legs_enabled or leg_model_scene == null:
		return
	var top_len: float = _path.top_surface_length
	if top_len <= 0.0:
		return
	var leg_z_scale: float = maxf(0.1, width * 0.5)
	var node_xform: Transform3D = global_transform if is_inside_tree() else Transform3D.IDENTITY
	var cross_axis_world: Vector3 = node_xform.basis.z.normalized()
	var legs_normal_world: Vector3 = floor_plane.normal.slide(cross_axis_world)
	if legs_normal_world.length_squared() < 1.0e-6:
		return
	legs_normal_world = legs_normal_world.normalized()
	for spec: Dictionary in _compute_leg_specs(top_len):
		var leg_name: String = spec["name"]
		var leg := get_node_or_null(NodePath(leg_name)) as Node3D
		if leg == null:
			continue
		var s_val: float = spec["s"]
		var sample: Transform3D = _path.sample(s_val)
		var belt_bottom_local: Vector3 = sample.origin - sample.basis.y * height
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
	if tail_end_leg_enabled and coverage_min <= top_len and not _is_s_excluded(coverage_min):
		specs.append({"name": _LEG_TAIL_NAME, "s": coverage_min})
	if middle_legs_enabled and middle_legs_spacing > 0.0:
		var tail_clear: float = tail_end_leg_clearance if tail_end_leg_enabled else 0.0
		var head_clear: float = head_end_leg_clearance if head_end_leg_enabled else 0.0
		var first: float = ceil((coverage_min + tail_clear) / middle_legs_spacing) * middle_legs_spacing
		var last: float = floor((coverage_max - head_clear) / middle_legs_spacing) * middle_legs_spacing
		var pos: float = first
		var idx: int = 1
		while pos <= last + 1.0e-6:
			if pos >= 0.0 and pos <= top_len and not _is_s_excluded(pos):
				specs.append({"name": "%s%d" % [_LEG_MIDDLE_PREFIX, idx], "s": pos})
				idx += 1
			pos += middle_legs_spacing
	if head_end_leg_enabled and coverage_max >= 0.0 and coverage_max <= top_len \
			and not _is_s_excluded(coverage_max):
		specs.append({"name": _LEG_HEAD_NAME, "s": coverage_max})
	return specs


func _is_s_excluded(s: float) -> bool:
	if exclusion_start == 0.0 and exclusion_end == 0.0:
		return false
	return s >= exclusion_start and s <= exclusion_end


func _apply_physics_material() -> void:
	for body: StaticBody3D in _bodies:
		if is_instance_valid(body):
			body.physics_material_override = physics_material


func _physics_process(delta: float) -> void:
	if LegFooting.legs_state_changed(self, _legs_state):
		_rebuild_legs()
		_legs_state = LegFooting.capture_leg_state(self)
	if not Simulation.is_running() or Simulation.is_paused():
		return
	for body: StaticBody3D in _bodies:
		BeltSurface.apply_velocity(body, speed)
	_belt_position = BeltSurface.advance_belt_position(
			_belt_material, speed, delta, _belt_position)


func _connect_segment_signals() -> void:
	for seg: BeltSegment in segments:
		if seg and not seg.changed.is_connected(_request_rebuild):
			seg.changed.connect(_request_rebuild)


func _disconnect_segment_signals() -> void:
	for seg: BeltSegment in segments:
		if seg and seg.changed.is_connected(_request_rebuild):
			seg.changed.disconnect(_request_rebuild)


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
