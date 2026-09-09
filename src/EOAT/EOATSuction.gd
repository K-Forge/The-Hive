@tool
extends Node3D

const DEFAULT_SIZE := 0.5
const GENERATED_CUPS_NAME := "GeneratedCups"
const MAX_CUPS_PER_AXIS := 64
const VACUUM_SKIN := 0.05
const VACUUM_DEPTH := 0.3

@export var tool_size_x: float = 0.5:
	set(value):
		tool_size_x = maxf(value, 0.5)
		_queue_rebuild()

@export var tool_size_z: float = 0.5:
	set(value):
		tool_size_z = maxf(value, 0.5)
		_queue_rebuild()

@export var cup_pitch_x: float = 0.1:
	set(value):
		cup_pitch_x = maxf(value, 0.01)
		_queue_rebuild()

@export var cup_pitch_z: float = 0.1:
	set(value):
		cup_pitch_z = maxf(value, 0.01)
		_queue_rebuild()

@export var cup_margin_x: float = 0.05:
	set(value):
		cup_margin_x = maxf(value, 0.0)
		_queue_rebuild()

@export var cup_margin_z: float = 0.05:
	set(value):
		cup_margin_z = maxf(value, 0.0)
		_queue_rebuild()

@export var cups_enabled: bool = true:
	set(value):
		cups_enabled = value
		_queue_rebuild()

@export_category("Alignment Offsets")
@export var planes_position_offset: Vector3 = Vector3.ZERO:
	set(value):
		planes_position_offset = value
		_queue_rebuild()

@export var cap_01_offset: Vector3 = Vector3.ZERO:
	set(value):
		cap_01_offset = value
		_queue_rebuild()

@export var cap_02_offset: Vector3 = Vector3.ZERO:
	set(value):
		cap_02_offset = value
		_queue_rebuild()

@export var cap_03_offset: Vector3 = Vector3.ZERO:
	set(value):
		cap_03_offset = value
		_queue_rebuild()

@export var cap_04_offset: Vector3 = Vector3.ZERO:
	set(value):
		cap_04_offset = value
		_queue_rebuild()

@export_category("Vacuum")
@export var vacuum_on: bool = false:
	set(value):
		if vacuum_on == value:
			return
		vacuum_on = value
		_update_vacuum_state()

var _attachment: Node3D
var _planes: Node3D
var _rail_a_01: Node3D
var _rail_a_02: Node3D
var _rail_b_01: Node3D
var _rail_b_02: Node3D
var _cap_01: Node3D
var _cap_02: Node3D
var _cap_03: Node3D
var _cap_04: Node3D
var _cup_template: Node3D
var _generated_cups: Node3D
var _vacuum_area: Area3D
var _vacuum_collision: CollisionShape3D

var _cap_01_base: Vector3
var _cap_02_base: Vector3
var _cap_03_base: Vector3
var _cap_04_base: Vector3
var _rail_a_01_base: Vector3
var _rail_a_02_base: Vector3
var _rail_b_01_base: Vector3
var _rail_b_02_base: Vector3
var _planes_base: Vector3
var _cup_base: Vector3

var _setup_done := false
var _vacuum_active_material: StandardMaterial3D
var _rebuild_queued := false


func _ready() -> void:
	_setup_refs()
	_capture_base_positions()
	_rebuild()
	_update_vacuum_state()

func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_deferred_rebuild")

func _deferred_rebuild() -> void:
	_rebuild_queued = false
	_rebuild()

func _setup_refs() -> void:
	_vacuum_area = get_node_or_null("VacuumArea") as Area3D
	_vacuum_collision = _vacuum_area.get_node_or_null("VacuumCollision") as CollisionShape3D if _vacuum_area else null

	_attachment = get_node_or_null("Attachment") as Node3D
	if not _attachment:
		return

	_cap_01 = _attachment.get_node_or_null("Cap_01") as Node3D
	_cap_02 = _attachment.get_node_or_null("Cap_02") as Node3D
	_cap_03 = _attachment.get_node_or_null("Cap_03") as Node3D
	_cap_04 = _attachment.get_node_or_null("Cap_04") as Node3D
	_planes = _attachment.get_node_or_null("Planes") as Node3D
	_rail_b_01 = _attachment.get_node_or_null("Rail_B_01") as Node3D
	_rail_b_02 = _attachment.get_node_or_null("Rail_B_02") as Node3D
	_rail_a_01 = _attachment.get_node_or_null("Rail_A_01") as Node3D
	_rail_a_02 = _attachment.get_node_or_null("Rail_A_02") as Node3D
	_cup_template = _attachment.get_node_or_null("SuctionCup_01") as Node3D

	_generated_cups = _attachment.get_node_or_null(GENERATED_CUPS_NAME) as Node3D
	if not _generated_cups:
		_generated_cups = Node3D.new()
		_generated_cups.name = GENERATED_CUPS_NAME
		_attachment.add_child(_generated_cups)
		_assign_valid_owner(_generated_cups)

	_setup_done = true


func _capture_base_positions() -> void:
	if not _setup_done:
		return

	if _cap_01: _cap_01_base = _cap_01.position
	if _cap_02: _cap_02_base = _cap_02.position
	if _cap_03: _cap_03_base = _cap_03.position
	if _cap_04: _cap_04_base = _cap_04.position

	if _rail_a_01: _rail_a_01_base = _rail_a_01.position
	if _rail_a_02: _rail_a_02_base = _rail_a_02.position
	if _rail_b_01: _rail_b_01_base = _rail_b_01.position
	if _rail_b_02: _rail_b_02_base = _rail_b_02.position

	if _planes: _planes_base = _planes.position
	if _cup_template: _cup_base = _cup_template.position


func _rebuild() -> void:
	if not is_node_ready():
		return

	if not _setup_done:
		_setup_refs()
		_capture_base_positions()

	if not _attachment:
		return

	var x_ratio := tool_size_x / DEFAULT_SIZE
	var z_ratio := tool_size_z / DEFAULT_SIZE

	_apply_axis_scale(_planes, true, false, true, x_ratio, 1.0, z_ratio)
	_apply_axis_scale(_rail_a_01, true, false, false, x_ratio, 1.0, 1.0)
	_apply_axis_scale(_rail_a_02, true, false, false, x_ratio, 1.0, 1.0)
	_apply_axis_scale(_rail_b_01, false, false, true, 1.0, 1.0, z_ratio)
	_apply_axis_scale(_rail_b_02, false, false, true, 1.0, 1.0, z_ratio)

	_reposition_parts()
	_rebuild_cups()
	_update_vacuum_area()
	_update_vacuum_state()


func _apply_axis_scale(node: Node3D, use_x: bool, use_y: bool, use_z: bool, x_value: float, y_value: float, z_value: float) -> void:
	if not node:
		return

	var s := node.scale
	if use_x:
		s.x = x_value
	if use_y:
		s.y = y_value
	if use_z:
		s.z = z_value
	node.scale = s


func _reposition_parts() -> void:
	var half_x := tool_size_x * 0.5
	var half_z := tool_size_z * 0.5

	if _cap_01:
		_cap_01.position = Vector3(-half_x, _cap_01_base.y, -half_z) + cap_01_offset
	if _cap_02:
		_cap_02.position = Vector3(half_x, _cap_02_base.y, -half_z) + cap_02_offset
	if _cap_03:
		_cap_03.position = Vector3(-half_x, _cap_03_base.y, half_z) + cap_03_offset
	if _cap_04:
		_cap_04.position = Vector3(half_x, _cap_04_base.y, half_z) + cap_04_offset

	if _rail_a_01:
		_rail_a_01.position = Vector3(0.0, _rail_a_01_base.y, -half_z)
	if _rail_a_02:
		_rail_a_02.position = Vector3(0.0, _rail_a_02_base.y, half_z)

	if _rail_b_01:
		_rail_b_01.position = Vector3(-half_x, _rail_b_01_base.y, 0.0)
	if _rail_b_02:
		_rail_b_02.position = Vector3(half_x, _rail_b_02_base.y, 0.0)

	if _planes:
		_planes.position = Vector3(0.0, _planes_base.y, 0.0) + planes_position_offset


func _rebuild_cups() -> void:
	if not _generated_cups:
		return

	for child in _generated_cups.get_children(true):
		_generated_cups.remove_child(child)
		child.queue_free()

	if not cups_enabled or not _cup_template:
		if _cup_template:
			_cup_template.visible = false
		return

	_cup_template.visible = false

	var usable_x := maxf(tool_size_x - cup_margin_x * 2.0, 0.0)
	var usable_z := maxf(tool_size_z - cup_margin_z * 2.0, 0.0)

	var count_x: int = clampi(int(usable_x / cup_pitch_x) + 1, 1, MAX_CUPS_PER_AXIS)
	var count_z: int = clampi(int(usable_z / cup_pitch_z) + 1, 1, MAX_CUPS_PER_AXIS)

	var start_x := -usable_x * 0.5
	var start_z := -usable_z * 0.5

	for ix in range(count_x):
		for iz in range(count_z):
			var cup := _cup_template.duplicate()
			cup.name = "SuctionCup_%d_%d" % [ix + 1, iz + 1]

			var px := 0.0 if count_x == 1 else start_x + ix * (usable_x / float(count_x - 1))
			var pz := 0.0 if count_z == 1 else start_z + iz * (usable_z / float(count_z - 1))

			cup.position = Vector3(px, _cup_base.y, pz)
			cup.visible = true
			_generated_cups.add_child(cup)
			_assign_valid_owner(cup)


func _update_vacuum_area() -> void:
	if not _vacuum_collision:
		return

	var box := _vacuum_collision.shape as BoxShape3D
	if not box:
		box = BoxShape3D.new()
		box.resource_local_to_scene = true
		_vacuum_collision.shape = box
	box.size = Vector3(tool_size_x + VACUUM_SKIN, VACUUM_DEPTH, tool_size_z + VACUUM_SKIN)


func set_vacuum_enabled(value: bool) -> void:
	vacuum_on = value


func _update_vacuum_state() -> void:
	var active_material := _get_vacuum_active_material() if vacuum_on else null

	_apply_material_recursive(_cup_template, active_material)

	if not _generated_cups:
		return

	for child in _generated_cups.get_children():
		_apply_material_recursive(child, active_material)


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node == null:
		return

	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material

	for child in node.get_children():
		_apply_material_recursive(child, material)


func _get_vacuum_active_material() -> StandardMaterial3D:
	if _vacuum_active_material:
		return _vacuum_active_material

	_vacuum_active_material = StandardMaterial3D.new()
	_vacuum_active_material.albedo_color = Color(0.2, 0.7, 0.2)
	_vacuum_active_material.emission_enabled = true
	_vacuum_active_material.emission = Color(0.1, 0.45, 0.1)
	return _vacuum_active_material


func _assign_valid_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	if node == null:
		return

	var valid_owner: Node = owner
	if valid_owner == null and _attachment:
		valid_owner = _attachment.owner

	if valid_owner != null and valid_owner.is_ancestor_of(node):
		node.owner = valid_owner
